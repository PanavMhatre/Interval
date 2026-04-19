import EventKit
import Foundation

struct MedicationReminderDraft: Hashable, Identifiable {
    let title: String
    let notes: String
    let scheduledTime: Date
    let isUrgent: Bool

    var id: String {
        "\(title.lowercased())-\(Int(scheduledTime.timeIntervalSince1970))"
    }
}

struct ReminderImportResult {
    let addedCount: Int
    let skippedCount: Int
}

enum AppleRemindersError: LocalizedError {
    case accessDenied
    case accessRestricted
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Allow Reminders access in Settings so Interval can add today's medications for you."
        case .accessRestricted:
            return "Reminders access is restricted on this device, so Interval can't add medication reminders right now."
        case .noCalendar:
            return "Apple Reminders is available, but no reminder list is ready for new items on this device."
        }
    }
}

@MainActor
final class AppleRemindersStore {
    static let shared = AppleRemindersStore()

    private let store = EKEventStore()
    private let calendar = Calendar(identifier: .gregorian)

    private init() {}

    func addMedicationReminders(for drafts: [MedicationReminderDraft]) async throws -> ReminderImportResult {
        guard !drafts.isEmpty else {
            return ReminderImportResult(addedCount: 0, skippedCount: 0)
        }

        let granted = try await requestReminderAccess()
        guard granted else { throw AppleRemindersError.accessDenied }

        store.reset()
        store.refreshSourcesIfNecessary()

        let reminderCalendar = try writableReminderCalendar()

        let bounds = dayBounds(for: drafts.map(\.scheduledTime))
        let existingReminders = await existingIncompleteReminders(
            in: [reminderCalendar],
            start: bounds.start,
            end: bounds.end
        )

        var knownKeys = Set(existingReminders.map(reminderKey))
        var addedCount = 0
        var skippedCount = 0

        for draft in drafts.sorted(by: { $0.scheduledTime < $1.scheduledTime }) {
            let key = reminderKey(for: draft)
            if knownKeys.contains(key) {
                skippedCount += 1
                continue
            }

            let reminder = EKReminder(eventStore: store)
            reminder.calendar = reminderCalendar
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.priority = draft.isUrgent ? 1 : 5

            let components = reminderComponents(for: draft.scheduledTime)
            reminder.startDateComponents = components
            reminder.dueDateComponents = components
            reminder.alarms = [EKAlarm(absoluteDate: draft.scheduledTime)]

            try store.save(reminder, commit: false)

            knownKeys.insert(key)
            addedCount += 1
        }

        if addedCount > 0 {
            try store.commit()
        }

        return ReminderImportResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    private func requestReminderAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .writeOnly:
            return true
        case .denied:
            return false
        case .restricted:
            throw AppleRemindersError.accessRestricted
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func writableReminderCalendar() throws -> EKCalendar {
        if let defaultCalendar = store.defaultCalendarForNewReminders(),
           defaultCalendar.allowsContentModifications {
            return defaultCalendar
        }

        if let existingCalendar = store.calendars(for: .reminder).first(where: \.allowsContentModifications) {
            return existingCalendar
        }

        if let intervalCalendar = store.calendars(for: .reminder).first(where: {
            $0.title == "Interval" && $0.allowsContentModifications
        }) {
            return intervalCalendar
        }

        return try createIntervalReminderCalendar()
    }

    private func createIntervalReminderCalendar() throws -> EKCalendar {
        guard let source = writableReminderSource() else {
            throw AppleRemindersError.noCalendar
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Interval"
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            throw AppleRemindersError.noCalendar
        }
    }

    private func writableReminderSource() -> EKSource? {
        let preferredTypes: [EKSourceType] = [.local, .mobileMe, .calDAV, .exchange]

        for sourceType in preferredTypes {
            if let source = store.sources.first(where: { $0.sourceType == sourceType }) {
                return source
            }
        }

        return store.sources.first(where: {
            $0.sourceType != .subscribed && $0.sourceType != .birthdays
        })
    }

    private func existingIncompleteReminders(
        in calendars: [EKCalendar],
        start: Date,
        end: Date
    ) async -> [EKReminder] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func reminderComponents(for date: Date) -> DateComponents {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = .current
        return components
    }

    private func dayBounds(for dates: [Date]) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: dates.min() ?? .now)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
        return (start, end)
    }

    private func reminderKey(for draft: MedicationReminderDraft) -> String {
        reminderKey(title: draft.title, dueDate: draft.scheduledTime)
    }

    private func reminderKey(for reminder: EKReminder) -> String {
        let dueDate = reminder.dueDateComponents?.date ?? reminder.startDateComponents?.date ?? .distantPast
        return reminderKey(title: reminder.title, dueDate: dueDate)
    }

    private func reminderKey(title: String, dueDate: Date) -> String {
        let minuteBucket = Int(dueDate.timeIntervalSince1970.rounded(.down) / 60)
        return "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(minuteBucket)"
    }
}
