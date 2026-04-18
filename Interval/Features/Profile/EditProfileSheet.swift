import SwiftUI
import SwiftData

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var profile: UserProfile

    @State private var name: String = ""
    @State private var age: Int = 0
    @State private var sex: String = "Female"
    @State private var bloodType: String = "O+"
    @State private var feet: Int = 5
    @State private var inches: Int = 6
    @State private var weight: Int = 141
    @State private var location: String = ""

    private let sexes = ["Female", "Male", "Non-binary", "Prefer not to say"]
    private let bloodTypes = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    eyebrow
                    nameField
                    ageSexRow
                    bloodHeightRow
                    weightField
                    locationField
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Edit profile")
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
                        .foregroundStyle(Theme.Palette.coralDeep)
                }
            }
        }
        .onAppear(perform: loadCurrentValues)
    }

    // MARK: - Fields

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.coralDeep)
            Text("Private · stays on device".uppercased()).eyebrowStyle()
        }
    }

    private var nameField: some View {
        fieldCard(label: "Name") {
            TextField("Your name", text: $name)
                .font(Theme.Font.body(18, weight: .semibold))
        }
    }

    private var ageSexRow: some View {
        HStack(spacing: 10) {
            fieldCard(label: "Age") {
                HStack {
                    TextField("0", value: $age, format: .number)
                        .keyboardType(.numberPad)
                        .font(Theme.Font.body(17, weight: .semibold))
                    Text("yrs").font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            fieldCard(label: "Sex") {
                Menu {
                    ForEach(sexes, id: \.self) { option in
                        Button(option) { sex = option }
                    }
                } label: {
                    menuLabel(sex)
                }
            }
        }
    }

    private var bloodHeightRow: some View {
        HStack(spacing: 10) {
            fieldCard(label: "Blood type") {
                Menu {
                    ForEach(bloodTypes, id: \.self) { option in
                        Button(option) { bloodType = option }
                    }
                } label: {
                    menuLabel(bloodType)
                }
            }
            fieldCard(label: "Height") {
                HStack(spacing: 6) {
                    TextField("0", value: $feet, format: .number)
                        .keyboardType(.numberPad)
                        .font(Theme.Font.body(17, weight: .semibold))
                        .frame(width: 28)
                    Text("ft").font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
                    TextField("0", value: $inches, format: .number)
                        .keyboardType(.numberPad)
                        .font(Theme.Font.body(17, weight: .semibold))
                        .frame(width: 28)
                    Text("in").font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
                }
            }
        }
    }

    private var weightField: some View {
        fieldCard(label: "Weight") {
            HStack {
                TextField("0", value: $weight, format: .number)
                    .keyboardType(.numberPad)
                    .font(Theme.Font.body(17, weight: .semibold))
                Text("lb").font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
            }
        }
    }

    private var locationField: some View {
        fieldCard(label: "Location") {
            TextField("City, state", text: $location)
                .font(Theme.Font.body(15, weight: .medium))
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

    private func menuLabel(_ value: String) -> some View {
        HStack {
            Text(value)
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
    }

    // MARK: - Load / save

    private func loadCurrentValues() {
        name = profile.name
        age = profile.age
        sex = profile.sex
        bloodType = profile.bloodType
        feet = profile.heightInches / 12
        inches = profile.heightInches % 12
        weight = profile.weightPounds
        location = profile.location
    }

    private func save() {
        Haptics.success()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        profile.name = trimmedName.isEmpty ? "Friend" : trimmedName
        profile.initials = String(profile.name.prefix(1)).uppercased()
        profile.age = max(0, age)
        profile.sex = sex
        profile.bloodType = bloodType
        profile.heightInches = max(0, feet * 12 + inches)
        profile.weightPounds = max(0, weight)
        profile.location = location
        try? context.save()
        dismiss()
    }
}
