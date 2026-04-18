import SwiftUI
import SwiftData

struct SymptomLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]

    var preset: String?
    var existing: SymptomLog?

    @State private var symptom: String = ""
    @State private var severity: Int = 3
    @State private var occurredAt: Date = .now
    @State private var notes: String = ""
    @State private var relatedMedName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    eyebrow
                    symptomField
                    severityField
                    whenField
                    linkedMedField
                    notesField
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)
            }
            .background(Theme.Palette.paper)
            .navigationTitle(existing == nil ? "Log symptom" : "Edit symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        dismiss()
                    }
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.Palette.coralDeep : Theme.Palette.inkMuted)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let existing {
                symptom = existing.symptom
                severity = existing.severity
                occurredAt = existing.occurredAt
                notes = existing.notes ?? ""
                relatedMedName = existing.relatedMedName
            } else if let preset {
                symptom = preset
            }
        }
    }

    // MARK: - Fields

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.coralDeep)
            Text("Private · stays on device".uppercased()).eyebrowStyle()
        }
    }

    private var symptomField: some View {
        fieldCard(label: "What's going on?") {
            TextField("e.g. dry cough, headache, fatigue", text: $symptom)
                .font(Theme.Font.body(17, weight: .semibold))
                .submitLabel(.next)
        }
    }

    private var severityField: some View {
        fieldCard(label: "Severity") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            Haptics.select()
                            withAnimation(.snappy) { severity = level }
                        } label: {
                            Text("\(level)")
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(severity == level ? .white : Theme.Palette.ink)
                                .frame(width: 40, height: 34)
                                .background(Capsule().fill(severity == level ? severityColor(level) : Color.clear))
                                .overlay(Capsule().strokeBorder(severity == level ? Color.clear : Theme.Palette.ink.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(SymptomLog.label(for: severity))
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(severityColor(severity))
                }
                Text(severityHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
        }
    }

    private var whenField: some View {
        fieldCard(label: "When") {
            DatePicker("", selection: $occurredAt, in: ...Date.now)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private var linkedMedField: some View {
        fieldCard(label: "Related med · optional") {
            Menu {
                Button("Not med-related") {
                    relatedMedName = nil
                }
                ForEach(medications, id: \.persistentModelID) { med in
                    Button(med.name) {
                        relatedMedName = med.name
                    }
                }
            } label: {
                HStack {
                    Text(relatedMedName ?? "Not med-related")
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(relatedMedName == nil ? Theme.Palette.inkSoft : Theme.Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
        }
    }

    private var notesField: some View {
        fieldCard(label: "Notes · optional") {
            TextField("Anything worth remembering later", text: $notes, axis: .vertical)
                .font(Theme.Font.bodyText)
                .lineLimit(3...6)
        }
    }

    private func fieldCard<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).eyebrowStyle()
            content()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !symptom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var severityHint: String {
        switch severity {
        case 1: "Barely noticeable."
        case 2: "There but not disruptive."
        case 3: "Noticeable all day."
        case 4: "Hard to ignore or work through."
        case 5: "Significantly limiting — flag for your doctor."
        default: ""
        }
    }

    private func severityColor(_ level: Int) -> Color {
        switch level {
        case 1, 2: Theme.Palette.sageDeep
        case 3:    Theme.Palette.coral
        case 4, 5: Theme.Palette.coralDeep
        default:   Theme.Palette.coral
        }
    }

    private func save() {
        let trimmed = symptom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.success()
        if let existing {
            existing.symptom = trimmed
            existing.severity = severity
            existing.occurredAt = occurredAt
            existing.notes = notes.isEmpty ? nil : notes
            existing.relatedMedName = relatedMedName
        } else {
            let log = SymptomLog(
                symptom: trimmed,
                severity: severity,
                occurredAt: occurredAt,
                notes: notes.isEmpty ? nil : notes,
                relatedMedName: relatedMedName
            )
            context.insert(log)
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    SymptomLogSheet(preset: "Cough")
        .modelContainer(previewContainer())
}
