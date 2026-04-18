import SwiftUI
import SwiftData

struct SymptomQuickLogCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\SymptomLog.occurredAt, order: .reverse)])
    private var recent: [SymptomLog]

    @State private var presetName: String? = nil
    @State private var showSheet = false
    @State private var showTimeline = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header
            chipRow
            if let latest = recent.first {
                latestEntry(latest)
            }
        }
        .padding(Theme.Space.md)
        .softCard(fill: Theme.Palette.paperSoft)
        .sheet(isPresented: $showSheet) {
            SymptomLogSheet(preset: presetName)
        }
        .sheet(isPresented: $showTimeline) {
            SymptomTimelineView()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.coralDeep)
            Text("How are you feeling?".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)
            Spacer()
            Button {
                Haptics.tap()
                showTimeline = true
            } label: {
                HStack(spacing: 4) {
                    Text("Timeline")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(Theme.Font.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.coralDeep)
            }
            .buttonStyle(.plain)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SymptomCatalog.common, id: \.name) { preset in
                    chip(preset.name, icon: preset.icon)
                }
                chip("Custom", icon: "plus", accent: true)
            }
        }
    }

    private func chip(_ title: String, icon: String, accent: Bool = false) -> some View {
        Button {
            Haptics.tap()
            presetName = accent ? nil : title
            showSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.Font.body(13, weight: .semibold))
            }
            .foregroundStyle(accent ? Theme.Palette.coralDeep : Theme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(accent ? Theme.Palette.peachTint : Theme.Palette.card))
            .overlay(Capsule().strokeBorder(accent ? Theme.Palette.coral.opacity(0.4) : Theme.Palette.ink.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func latestEntry(_ log: SymptomLog) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.card).frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                Image(systemName: SymptomCatalog.icon(for: log.symptom))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.coralDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Last logged · \(log.symptom)")
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(log.severityLabel)
                        .font(Theme.Font.body(10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Palette.peachTint))
                }
                Text(log.occurredAt.formatted(.relative(presentation: .named)))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            Spacer()
        }
    }
}
