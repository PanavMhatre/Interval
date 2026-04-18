import SwiftUI
import SwiftData

struct SymptomTimelineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\SymptomLog.occurredAt, order: .reverse)])
    private var logs: [SymptomLog]

    @State private var showAdd = false
    @State private var editing: SymptomLog?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    summaryBanner
                    ForEach(grouped, id: \.key) { group in
                        section(title: group.key, logs: group.value)
                    }
                    if logs.isEmpty { emptyState }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Symptom timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showAdd = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Log").font(Theme.Font.body(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.Palette.coralDeep)
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            SymptomLogSheet()
        }
        .sheet(item: $editing) { log in
            SymptomLogSheet(existing: log)
        }
    }

    // MARK: - Summary

    private var summaryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.coralDeep)
                Text("What I've tracked".uppercased()).eyebrowStyle()
            }
            Text(summaryLine)
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                PillTag(text: "\(logs.count) entries", icon: "list.bullet")
                PillTag(text: "Share with doctor", icon: "square.and.arrow.up")
                Spacer()
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: Theme.Palette.paperSoft)
    }

    private var summaryLine: String {
        guard !logs.isEmpty else {
            return "Start logging how you feel. Over time this becomes a record your doctor can actually work from."
        }
        let commonest = logs.map(\.symptom)
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key ?? logs.first!.symptom
        return "\(logs.count) entries logged. Most frequent: \(commonest). Tap any entry to edit."
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Palette.inkMuted)
            Text("No symptoms logged yet")
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Tap Log above to add your first entry.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(.vertical, Theme.Space.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grouping

    private var grouped: [(key: String, value: [SymptomLog])] {
        let cal = Calendar.current
        let now = Date.now
        var buckets: [String: [SymptomLog]] = [:]
        var order: [String] = []
        for log in logs {
            let key: String
            if cal.isDateInToday(log.occurredAt) {
                key = "Today"
            } else if cal.isDateInYesterday(log.occurredAt) {
                key = "Yesterday"
            } else if let days = cal.dateComponents([.day], from: log.occurredAt, to: now).day, days < 7 {
                key = "This week"
            } else if let days = cal.dateComponents([.day], from: log.occurredAt, to: now).day, days < 30 {
                key = "Earlier this month"
            } else {
                key = log.occurredAt.formatted(.dateTime.month(.wide).year())
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(log)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private func section(title: String, logs: [SymptomLog]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title.uppercased()).eyebrowStyle()
            VStack(spacing: 8) {
                ForEach(logs, id: \.persistentModelID) { log in
                    row(log: log)
                }
            }
        }
    }

    private func row(log: SymptomLog) -> some View {
        Button {
            Haptics.select()
            editing = log
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.Palette.peachTint).frame(width: 34, height: 34)
                    Image(systemName: SymptomCatalog.icon(for: log.symptom))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(log.symptom)
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        StatusChip(text: log.severityLabel, kind: severityKind(log.severity))
                    }
                    HStack(spacing: 8) {
                        Text(log.occurredAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkMuted)
                        if let med = log.relatedMedName {
                            Text("·").font(Theme.Font.caption).foregroundStyle(Theme.Palette.inkMuted)
                            Text("with \(med)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.coralDeep)
                        }
                    }
                    if let notes = log.notes, !notes.isEmpty {
                        Text(notes)
                            .font(Theme.Font.body(13))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            .padding(Theme.Space.md)
            .softCard()
        }
        .buttonStyle(.plain)
    }

    private func severityKind(_ severity: Int) -> StatusChip.Kind {
        switch severity {
        case 1, 2: .done
        case 3:    .now
        case 4, 5: .warn
        default:   .now
        }
    }
}

#Preview {
    SymptomTimelineView()
        .modelContainer(previewContainer())
}
