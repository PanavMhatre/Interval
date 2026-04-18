import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var initials: String
    var age: Int
    var sex: String
    var bloodType: String
    var heightInches: Int
    var weightPounds: Int = 141
    var location: String
    var conditions: [String]
    var allergies: [String]
    var hasCompletedOnboarding: Bool
    var createdAt: Date

    init(
        name: String = "Sarah K.",
        initials: String = "S",
        age: Int = 34,
        sex: String = "Female",
        bloodType: String = "O+",
        heightInches: Int = 66,
        weightPounds: Int = 141,
        location: String = "Austin, TX",
        conditions: [String] = ["Hypertension", "Prediabetes", "Iron def."],
        allergies: [String] = ["Penicillin", "Shellfish"],
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.initials = initials
        self.age = age
        self.sex = sex
        self.bloodType = bloodType
        self.heightInches = heightInches
        self.weightPounds = weightPounds
        self.location = location
        self.conditions = conditions
        self.allergies = allergies
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
    }
}
