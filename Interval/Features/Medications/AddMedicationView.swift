import SwiftUI
import SwiftData

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable { case manual = "Manual", scan = "Scan Rx", history = "From history" }

    @State private var mode: Mode = .manual
    @State private var name = "Ibuprofen"
    @State private var brand = "Advil"
    @State private var doseAmount = "200"
    @State private var doseUnit = "mg"
    @State private var form: DoseForm = .tablet
    @State private var schedule: ScheduleKind = .everyXHours
    @State private var intervalHours = 6
    @State private var maxPerDay: Int? = 4
    @State private var withFood = true
    @State private var withWater = true
    @State private var reminders = true

    @State private var showInteraction = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {

                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("< Cancel")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text("New medication")
                        .font(Theme.Font.display(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Button {
                        Haptics.tap()
                        save()
                    } label: {
                        Text("Save")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.coralDeep)
                    }.buttonStyle(.plain)
                }
                DashedHairline()

                // Mode toggle
                HStack(spacing: 6) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Button {
                            Haptics.select()
                            withAnimation(.snappy) { mode = m }
                        } label: {
                            Text(m.rawValue)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(mode == m ? .white : Theme.Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(mode == m ? Theme.Palette.ink : Color.clear))
                                .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(mode == m ? 0 : 0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                // Fields
                fieldCard(label: "Name", prominent: true) {
                    TextField("Medication name", text: $name)
                        .font(Theme.Font.body(18, weight: .semibold))
                    Text("brand: \(brand)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }

                HStack(spacing: 10) {
                    fieldCard(label: "Dose") {
                        HStack {
                            TextField("0", text: $doseAmount)
                                .keyboardType(.numberPad)
                                .font(Theme.Font.body(17, weight: .semibold))
                            Text(doseUnit).font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
                        }
                    }
                    fieldCard(label: "Form") {
                        Menu {
                            ForEach(DoseForm.allCases) { f in
                                Button(f.displayName) { form = f }
                            }
                        } label: {
                            HStack {
                                Text(form.displayName)
                                    .font(Theme.Font.body(15, weight: .medium))
                                    .foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.inkMuted)
                            }
                        }
                    }
                }

                fieldCard(label: "Schedule") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Every \(intervalHours)h · as needed")
                            .font(Theme.Font.body(16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("Max \(maxPerDay ?? 4)× daily")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                }

                fieldCard(label: "With") {
                    HStack {
                        withChip("Food", on: $withFood, icon: "fork.knife")
                        withChip("Water", on: $withWater, icon: "drop.fill")
                        Spacer()
                    }
                }

                // Reminders toggle
                HStack {
                    Text("Add to reminders")
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Toggle("", isOn: $reminders)
                        .labelsHidden()
                        .tint(Theme.Palette.ink)
                }
                .padding(Theme.Space.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(
                            Theme.Palette.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )

                // AI double-check blurb
                HStack(alignment: .top, spacing: 10) {
                    AvatarCircle(initials: "i", size: 28)
                    Text("I checked this against your current meds — looking good. Double-checking one thing…")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(fill: Theme.Palette.paperSoft)

                PrimaryButton(title: "Check interactions") {
                    showInteraction = true
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showInteraction) {
            NavigationStack {
                InteractionCheckView(newMedName: name, newDose: "\(doseAmount)\(doseUnit)") {
                    save()
                }
            }
        }
    }

    private func fieldCard<Content: View>(label: String, prominent: Bool = false, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).eyebrowStyle()
            content()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func withChip(_ title: String, on: Binding<Bool>, icon: String) -> some View {
        Button {
            Haptics.select()
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(Theme.Font.body(13, weight: .semibold))
            }
            .foregroundStyle(on.wrappedValue ? Theme.Palette.coralDeep : Theme.Palette.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(on.wrappedValue ? Theme.Palette.peachTint : Theme.Palette.paperSoft))
            .overlay(Capsule().strokeBorder(on.wrappedValue ? Theme.Palette.coral.opacity(0.4) : Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let amount = Double(doseAmount) ?? 0
        let med = Medication(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            doseAmount: amount,
            doseUnit: doseUnit,
            form: form,
            schedule: schedule,
            intervalHours: intervalHours,
            maxPerDay: maxPerDay,
            withFood: withFood,
            withWater: withWater,
            preferredTimes: ["9:00 PM"],
            notes: nil,
            remindersEnabled: reminders
        )
        context.insert(med)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AddMedicationView()
    }
    .modelContainer(previewContainer())
}
