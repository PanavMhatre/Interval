import Foundation
import Combine
import HealthKit

@MainActor
final class AppleHealthStore: ObservableObject {
    struct Snapshot: Equatable {
        var stepsToday: Double?
        var sleepHours: Double?
        var waterCups: Double?
        var restingHeartRate: Double?
        var lastSync: Date?

        var hasAnyData: Bool {
            [stepsToday, sleepHours, waterCups, restingHeartRate].contains {
                guard let value = $0 else { return false }
                return value > 0
            }
        }

        var stepsText: String {
            guard let stepsToday else { return "No data" }
            return Int(stepsToday.rounded()).formatted()
        }

        var sleepText: String {
            guard let sleepHours else { return "No data" }
            let totalMinutes = max(Int((sleepHours * 60).rounded()), 0)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "\(hours)h \(minutes)m"
        }

        var waterGoalText: String {
            guard let waterCups else { return "No data" }
            if abs(waterCups.rounded() - waterCups) < 0.05 {
                return "\(Int(waterCups.rounded()))/8"
            }
            return String(format: "%.1f/8", waterCups)
        }

        var restingHeartRateText: String {
            guard let restingHeartRate else { return "No data" }
            return "\(Int(restingHeartRate.rounded())) bpm"
        }

        var stepsProgress: Double {
            min(max((stepsToday ?? 0) / 10_000, 0), 1)
        }

        var sleepProgress: Double {
            min(max((sleepHours ?? 0) / 8, 0), 1)
        }

        var waterProgress: Double {
            min(max((waterCups ?? 0) / 8, 0), 1)
        }
    }

    enum SyncState: Equatable {
        case unavailable
        case disconnected
        case syncing
        case connected
        case waitingForData
    }

    @Published private(set) var snapshot: Snapshot
    @Published private(set) var isConnected: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var syncState: SyncState {
        if !isAvailable { return .unavailable }
        if isLoading { return .syncing }
        if !isConnected { return .disconnected }
        return snapshot.hasAnyData ? .connected : .waitingForData
    }

    private let healthStore: HKHealthStore?
    private let defaults: UserDefaults
    private let enabledKey = "appleHealth.isEnabled"
    private let lastSyncKey = "appleHealth.lastSync"

    init(
        defaults: UserDefaults = .standard,
        previewSnapshot: Snapshot? = nil,
        previewConnected: Bool? = nil
    ) {
        self.defaults = defaults

        if let previewSnapshot {
            self.snapshot = previewSnapshot
            self.isConnected = previewConnected ?? true
            self.healthStore = nil
            self.lastError = nil
            return
        }

        let savedLastSync = defaults.object(forKey: lastSyncKey) as? Date
        self.snapshot = Snapshot(lastSync: savedLastSync)
        self.isConnected = defaults.bool(forKey: enabledKey)
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        self.lastError = nil
    }

    func requestAccess() async {
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return
        }

        do {
            try await requestAuthorization()
            setConnected(true)
            await refresh(force: true)
        } catch {
            lastError = "Couldn't connect Apple Health right now."
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard isConnected else { return }
        guard force || shouldRefresh else { return }
        await refresh(force: force)
    }

    func disableSync() {
        lastError = nil
        snapshot = Snapshot()
        defaults.removeObject(forKey: lastSyncKey)
        setConnected(false)
    }

    private var shouldRefresh: Bool {
        guard !isLoading else { return false }
        guard let lastSync = snapshot.lastSync else { return true }
        return Date().timeIntervalSince(lastSync) > 900
    }

    private func setConnected(_ value: Bool) {
        defaults.set(value, forKey: enabledKey)
        isConnected = value
    }

    private func refresh(force: Bool) async {
        guard isConnected || force else { return }
        guard let healthStore else {
            lastError = "Apple Health isn't available on this device."
            return
        }
        guard !isLoading else { return }

        isLoading = true
        lastError = nil

        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -18, to: startOfDay) ?? startOfDay

        async let stepsToday: Double? = try? cumulativeQuantity(
            in: healthStore,
            identifier: .stepCount,
            unit: .count(),
            start: startOfDay,
            end: now
        )

        async let waterOunces: Double? = try? cumulativeQuantity(
            in: healthStore,
            identifier: .dietaryWater,
            unit: .fluidOunceUS(),
            start: startOfDay,
            end: now
        )

        async let sleepHours: Double? = try? sleepDuration(
            in: healthStore,
            start: sleepWindowStart,
            end: now
        )

        async let restingHeartRate: Double? = try? latestQuantity(
            in: healthStore,
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )

        let newSnapshot = Snapshot(
            stepsToday: await stepsToday,
            sleepHours: await sleepHours,
            waterCups: await waterOunces.map { $0 / 8 },
            restingHeartRate: await restingHeartRate,
            lastSync: now
        )

        snapshot = newSnapshot
        defaults.set(now, forKey: lastSyncKey)
        isLoading = false
    }

    private func requestAuthorization() async throws {
        guard let healthStore else {
            throw AppleHealthError.unavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: AppleHealthError.authorizationFailed)
                }
            }
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .dietaryWater),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ]
        .forEach { type in
            if let type {
                types.insert(type)
            }
        }

        return types
    }

    private func cumulativeQuantity(
        in healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw AppleHealthError.missingType
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        in healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw AppleHealthError.missingType
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = (samples?.first as? HKQuantitySample)?
                    .quantity
                    .doubleValue(for: unit)

                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    private func sleepDuration(
        in healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw AppleHealthError.missingType
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let totalSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { partial, sample in
                    guard asleepValues.contains(sample.value) else { return partial }
                    return partial + sample.endDate.timeIntervalSince(sample.startDate)
                }

                continuation.resume(returning: totalSeconds / 3600)
            }

            healthStore.execute(query)
        }
    }

    enum AppleHealthError: Error {
        case unavailable
        case authorizationFailed
        case missingType
    }
}

extension AppleHealthStore {
    static var previewConnected: AppleHealthStore {
        AppleHealthStore(
            previewSnapshot: Snapshot(
                stepsToday: 8432,
                sleepHours: 7.2,
                waterCups: 3,
                restingHeartRate: 62,
                lastSync: .now
            ),
            previewConnected: true
        )
    }

    static var previewDisconnected: AppleHealthStore {
        AppleHealthStore(
            previewSnapshot: Snapshot(),
            previewConnected: false
        )
    }
}
