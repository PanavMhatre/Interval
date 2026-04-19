import Foundation
import SwiftData

enum MedicationInteractionSeverity: Int, Comparable, CaseIterable {
    case low
    case moderate
    case high

    static func < (lhs: MedicationInteractionSeverity, rhs: MedicationInteractionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .low: "Review"
        case .moderate: "Careful"
        case .high: "High risk"
        }
    }
}

enum MedicationInteractionKind {
    case monitoring
    case timing
    case allergy
    case duplicateTherapy
}

struct MedicationSafetyDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String?
    let doseText: String
    let preferredTimes: [String]
    let notes: String?
    let withFood: Bool
    let withWater: Bool

    init(
        id: String,
        name: String,
        brand: String? = nil,
        doseText: String = "",
        preferredTimes: [String] = [],
        notes: String? = nil,
        withFood: Bool = false,
        withWater: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.doseText = doseText
        self.preferredTimes = preferredTimes
        self.notes = notes
        self.withFood = withFood
        self.withWater = withWater
    }

    init(_ medication: Medication) {
        self.init(
            id: String(describing: medication.persistentModelID),
            name: medication.name,
            brand: medication.brand,
            doseText: medication.doseText,
            preferredTimes: medication.preferredTimes,
            notes: medication.notes,
            withFood: medication.withFood,
            withWater: medication.withWater
        )
    }

    static func candidate(
        name: String,
        brand: String? = nil,
        doseText: String = "",
        preferredTimes: [String] = [],
        notes: String? = nil,
        withFood: Bool = false,
        withWater: Bool = false
    ) -> MedicationSafetyDescriptor {
        MedicationSafetyDescriptor(
            id: "candidate-\(name.lowercased().replacingOccurrences(of: " ", with: ""))",
            name: name,
            brand: brand,
            doseText: doseText,
            preferredTimes: preferredTimes,
            notes: notes,
            withFood: withFood,
            withWater: withWater
        )
    }

    var displayName: String { name }

    fileprivate var searchableText: String {
        [name, brand, notes]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}

struct MedicationScheduleAdjustment: Hashable {
    let targetMedicationID: String
    let targetMedicationName: String
    let anchorMedicationName: String
    let anchorTime: String
    let suggestedTime: String
    let minimumGapHours: Int
}

struct MedicationInteractionIssue: Identifiable, Hashable {
    let id: String
    let primary: MedicationSafetyDescriptor
    let secondary: MedicationSafetyDescriptor
    let severity: MedicationInteractionSeverity
    let kind: MedicationInteractionKind
    let title: String
    let summary: String
    let recommendation: String
    let source: String
    let scheduleAdjustment: MedicationScheduleAdjustment?

    var pairLabel: String { "\(primary.displayName) + \(secondary.displayName)" }
}

struct MedicationPairAssessment: Identifiable, Hashable {
    let primary: MedicationSafetyDescriptor
    let secondary: MedicationSafetyDescriptor
    let issue: MedicationInteractionIssue?

    var id: String { "\(primary.id)-\(secondary.id)" }
    var isClear: Bool { issue == nil }
}

struct MedicationSafetyReport {
    let pairAssessments: [MedicationPairAssessment]

    var issues: [MedicationInteractionIssue] {
        pairAssessments.compactMap(\.issue).sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.pairLabel < rhs.pairLabel
        }
    }

    var clearPairs: [MedicationPairAssessment] {
        pairAssessments.filter(\.isClear)
    }
}

struct MedicationAdditionReport {
    let candidate: MedicationSafetyDescriptor
    let issues: [MedicationInteractionIssue]
    let checkedMedications: [MedicationSafetyDescriptor]

    var highestSeverity: MedicationInteractionSeverity? {
        issues.map(\.severity).max()
    }

    var issueCount: Int { issues.count }
    var isClear: Bool { issues.isEmpty }
}

@MainActor
enum MedicationSafetyEngine {
    private struct PairRule {
        enum MatchKind {
            case monitoring
            case timing(minimumGapHours: Int)
            case duplicateTherapy
        }

        let id: String
        let leftTokens: [String]
        let rightTokens: [String]
        let severity: MedicationInteractionSeverity
        let kind: MatchKind
        let title: String
        let summary: String
        let recommendation: String
        let source: String
    }

    private struct AllergyRule {
        let id: String
        let allergyTokens: [String]
        let medicationTokens: [String]
        let severity: MedicationInteractionSeverity
        let title: String
        let summary: String
        let recommendation: String
        let source: String
    }

    static func analyzeCurrentMedications(_ medications: [Medication]) -> MedicationSafetyReport {
        let descriptors = medications.map(MedicationSafetyDescriptor.init)
        var assessments: [MedicationPairAssessment] = []

        guard descriptors.count >= 2 else {
            return MedicationSafetyReport(pairAssessments: [])
        }

        for index in descriptors.indices {
            for nextIndex in descriptors.indices where nextIndex > index {
                let first = descriptors[index]
                let second = descriptors[nextIndex]
                let issue = issueForCurrentPair(first, second)
                assessments.append(
                    MedicationPairAssessment(primary: first, secondary: second, issue: issue)
                )
            }
        }

        return MedicationSafetyReport(pairAssessments: assessments)
    }

    static func analyzeAddition(
        candidateName: String,
        candidateBrand: String? = nil,
        candidateDoseText: String,
        preferredTimes: [String] = [],
        notes: String? = nil,
        withFood: Bool = false,
        withWater: Bool = false,
        currentMedications: [Medication],
        profile: UserProfile?
    ) -> MedicationAdditionReport {
        let candidate = MedicationSafetyDescriptor.candidate(
            name: candidateName,
            brand: candidateBrand,
            doseText: candidateDoseText,
            preferredTimes: preferredTimes,
            notes: notes,
            withFood: withFood,
            withWater: withWater
        )
        let currentDescriptors = currentMedications.map(MedicationSafetyDescriptor.init)

        var issues = currentDescriptors.compactMap { issueForCandidate(candidate, against: $0) }
        issues += allergyIssues(for: candidate, profile: profile)
        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.pairLabel < rhs.pairLabel
        }

        return MedicationAdditionReport(
            candidate: candidate,
            issues: issues,
            checkedMedications: currentDescriptors
        )
    }

    static func interactionIssue(primary: String, secondary: String, profile: UserProfile? = nil) -> MedicationInteractionIssue? {
        let left = MedicationSafetyDescriptor.candidate(name: primary)
        let right = MedicationSafetyDescriptor.candidate(name: secondary)
        return highestPriorityIssue(between: left, and: right, considerSchedule: false)
    }

    static func medicationNamesMentioned(in text: String, currentMedications: [Medication]) -> [String] {
        let haystack = normalized(text)

        var names: [String] = currentMedications.compactMap { medication in
            let tokens = [medication.name, medication.brand].compactMap { $0 }
            let matched = tokens.contains { haystack.contains(normalized($0)) }
            return matched ? medication.name : nil
        }

        for token in commonDrugTokens where haystack.contains(normalized(token)) {
            if !names.contains(where: { normalized($0) == normalized(token) }) {
                names.append(token)
            }
        }

        return names
    }

    private static func issueForCurrentPair(
        _ first: MedicationSafetyDescriptor,
        _ second: MedicationSafetyDescriptor
    ) -> MedicationInteractionIssue? {
        highestPriorityIssue(between: first, and: second, considerSchedule: true)
    }

    private static func issueForCandidate(
        _ candidate: MedicationSafetyDescriptor,
        against current: MedicationSafetyDescriptor
    ) -> MedicationInteractionIssue? {
        highestPriorityIssue(between: candidate, and: current, considerSchedule: false)
    }

    private static func highestPriorityIssue(
        between first: MedicationSafetyDescriptor,
        and second: MedicationSafetyDescriptor,
        considerSchedule: Bool
    ) -> MedicationInteractionIssue? {
        var matches: [MedicationInteractionIssue] = []

        for rule in pairRules {
            if matchesRule(rule, left: first, right: second) {
                if let issue = issue(for: rule, primary: first, secondary: second, considerSchedule: considerSchedule) {
                    matches.append(issue)
                }
            } else if matchesRule(rule, left: second, right: first) {
                if let issue = issue(for: rule, primary: second, secondary: first, considerSchedule: considerSchedule) {
                    matches.append(issue)
                }
            }
        }

        return matches.max { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.title < rhs.title
        }
    }

    private static func issue(
        for rule: PairRule,
        primary: MedicationSafetyDescriptor,
        secondary: MedicationSafetyDescriptor,
        considerSchedule: Bool
    ) -> MedicationInteractionIssue? {
        let issueKind: MedicationInteractionKind
        let adjustment: MedicationScheduleAdjustment?

        switch rule.kind {
        case .monitoring:
            issueKind = .monitoring
            adjustment = nil
        case .duplicateTherapy:
            issueKind = .duplicateTherapy
            adjustment = nil
        case .timing(let minimumGapHours):
            issueKind = .timing
            if considerSchedule {
                guard let suggestion = scheduleAdjustment(
                    primary: primary,
                    secondary: secondary,
                    minimumGapHours: minimumGapHours
                ) else {
                    return nil
                }
                adjustment = suggestion
            } else {
                adjustment = timingGuidance(
                    primary: primary,
                    secondary: secondary,
                    minimumGapHours: minimumGapHours
                )
            }
        }

        return MedicationInteractionIssue(
            id: "\(rule.id)-\(primary.id)-\(secondary.id)",
            primary: primary,
            secondary: secondary,
            severity: rule.severity,
            kind: issueKind,
            title: rule.title,
            summary: rule.summary,
            recommendation: rule.recommendation,
            source: rule.source,
            scheduleAdjustment: adjustment
        )
    }

    private static func allergyIssues(
        for candidate: MedicationSafetyDescriptor,
        profile: UserProfile?
    ) -> [MedicationInteractionIssue] {
        guard let profile else { return [] }

        let allergies = profile.allergies.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return allergyRules.compactMap { rule in
            let matchedAllergy = allergies.first { allergy in
                let normalizedAllergy = normalized(allergy)
                return rule.allergyTokens.contains { normalizedAllergy.contains(normalized($0)) || normalized($0).contains(normalizedAllergy) }
            }

            guard matchedAllergy != nil, matches(candidate, any: rule.medicationTokens) else { return nil }

            let allergyDescriptor = MedicationSafetyDescriptor(
                id: "allergy-\(rule.id)",
                name: matchedAllergy ?? "Profile allergy",
                brand: nil,
                doseText: "Profile allergy"
            )

            return MedicationInteractionIssue(
                id: "\(rule.id)-\(candidate.id)",
                primary: candidate,
                secondary: allergyDescriptor,
                severity: rule.severity,
                kind: .allergy,
                title: rule.title,
                summary: rule.summary,
                recommendation: rule.recommendation,
                source: rule.source,
                scheduleAdjustment: nil
            )
        }
    }

    private static func matchesRule(
        _ rule: PairRule,
        left: MedicationSafetyDescriptor,
        right: MedicationSafetyDescriptor
    ) -> Bool {
        matches(left, any: rule.leftTokens) && matches(right, any: rule.rightTokens)
    }

    private static func matches(_ medication: MedicationSafetyDescriptor, any tokens: [String]) -> Bool {
        let haystack = medication.searchableText
        return tokens.contains { token in
            let normalizedToken = normalized(token)
            return haystack.contains(normalizedToken)
        }
    }

    private static func scheduleAdjustment(
        primary: MedicationSafetyDescriptor,
        secondary: MedicationSafetyDescriptor,
        minimumGapHours: Int
    ) -> MedicationScheduleAdjustment? {
        guard
            let primaryTime = parseTime(primary.preferredTimes.first),
            let secondaryTime = parseTime(secondary.preferredTimes.first)
        else {
            return timingGuidance(primary: primary, secondary: secondary, minimumGapHours: minimumGapHours)
        }

        let gapHours = abs(secondaryTime.timeIntervalSince(primaryTime)) / 3600
        guard gapHours < Double(minimumGapHours) else { return nil }

        let suggested = primaryTime.addingTimeInterval(Double(minimumGapHours) * 3600)

        return MedicationScheduleAdjustment(
            targetMedicationID: secondary.id,
            targetMedicationName: secondary.displayName,
            anchorMedicationName: primary.displayName,
            anchorTime: formatTime(primaryTime),
            suggestedTime: formatTime(suggested),
            minimumGapHours: minimumGapHours
        )
    }

    private static func timingGuidance(
        primary: MedicationSafetyDescriptor,
        secondary: MedicationSafetyDescriptor,
        minimumGapHours: Int
    ) -> MedicationScheduleAdjustment {
        MedicationScheduleAdjustment(
            targetMedicationID: secondary.id,
            targetMedicationName: secondary.displayName,
            anchorMedicationName: primary.displayName,
            anchorTime: primary.preferredTimes.first ?? "the first dose",
            suggestedTime: "at least \(minimumGapHours)h later",
            minimumGapHours: minimumGapHours
        )
    }

    private static func parseTime(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    private static let pairRules: [PairRule] = [
        PairRule(
            id: "acei-arb-nsaid",
            leftTokens: ["lisinopril", "enalapril", "ramipril", "benazepril", "losartan", "valsartan", "olmesartan", "irbesartan", "candesartan"],
            rightTokens: ["ibuprofen", "naproxen", "diclofenac", "celecoxib", "meloxicam", "indomethacin"],
            severity: .moderate,
            kind: .monitoring,
            title: "Kidney and blood-pressure caution",
            summary: "NSAIDs can blunt the blood-pressure effect of ACE inhibitors or ARBs and add kidney stress if they become a repeated pattern.",
            recommendation: "If this is a short course, keep it brief, stay hydrated, and check with a clinician if you need it more than occasionally.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "acei-arb-potassium",
            leftTokens: ["lisinopril", "enalapril", "ramipril", "benazepril", "losartan", "valsartan", "olmesartan", "irbesartan", "candesartan"],
            rightTokens: ["spironolactone", "eplerenone", "amiloride", "triamterene", "potassium chloride", "potassium supplement", "potassium"],
            severity: .high,
            kind: .monitoring,
            title: "Potassium can run too high",
            summary: "This combination can raise potassium levels, especially if it is used without lab monitoring.",
            recommendation: "Do not start or stack these without clinician guidance and a plan for potassium checks.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "warfarin-nsaid",
            leftTokens: ["warfarin", "coumadin"],
            rightTokens: ["ibuprofen", "naproxen", "diclofenac", "celecoxib", "meloxicam", "indomethacin"],
            severity: .high,
            kind: .monitoring,
            title: "Bleeding risk goes up",
            summary: "NSAIDs and warfarin together can increase bleeding risk, including stomach bleeding.",
            recommendation: "Do not combine these without clinician or pharmacist guidance.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "levothyroxine-iron",
            leftTokens: ["levothyroxine", "synthroid", "levoxyl", "unithroid"],
            rightTokens: ["iron", "ferrous", "ferrous sulfate", "ferrous gluconate"],
            severity: .moderate,
            kind: .timing(minimumGapHours: 4),
            title: "Absorption timing conflict",
            summary: "Iron can lower how much levothyroxine your body absorbs if they are taken too close together.",
            recommendation: "Keep the iron dose at least 4 hours away from the thyroid medication.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "levothyroxine-mineral",
            leftTokens: ["levothyroxine", "synthroid", "levoxyl", "unithroid"],
            rightTokens: ["calcium", "magnesium", "zinc", "multivitamin"],
            severity: .moderate,
            kind: .timing(minimumGapHours: 4),
            title: "Minerals can block absorption",
            summary: "Calcium, magnesium, zinc, and some multivitamins can interfere with thyroid medication absorption.",
            recommendation: "Keep the mineral supplement at least 4 hours away from the thyroid medication.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "iron-mineral",
            leftTokens: ["iron", "ferrous", "ferrous sulfate", "ferrous gluconate"],
            rightTokens: ["calcium", "magnesium", "zinc", "multivitamin"],
            severity: .moderate,
            kind: .timing(minimumGapHours: 2),
            title: "Minerals can crowd out iron",
            summary: "Calcium, magnesium, zinc, and multivitamins can reduce iron absorption if they land too close together.",
            recommendation: "Keep the iron dose and the mineral supplement at least 2 hours apart.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "iron-quinolone",
            leftTokens: ["ciprofloxacin", "levofloxacin", "moxifloxacin"],
            rightTokens: ["iron", "ferrous", "ferrous sulfate", "ferrous gluconate"],
            severity: .moderate,
            kind: .timing(minimumGapHours: 4),
            title: "Iron can block antibiotic absorption",
            summary: "Iron can bind certain antibiotics and make them absorb less well.",
            recommendation: "Keep iron at least 4 hours away from this antibiotic unless your clinician gives a different plan.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "iron-tetracycline",
            leftTokens: ["doxycycline", "minocycline", "tetracycline"],
            rightTokens: ["iron", "ferrous", "ferrous sulfate", "ferrous gluconate"],
            severity: .moderate,
            kind: .timing(minimumGapHours: 2),
            title: "Iron can lower antibiotic absorption",
            summary: "Iron can reduce how well tetracycline antibiotics absorb if they are taken together.",
            recommendation: "Keep iron at least 2 hours away from this antibiotic.",
            source: "Curated medication-safety rules"
        ),
        PairRule(
            id: "duplicate-nsaid",
            leftTokens: ["ibuprofen", "naproxen", "diclofenac", "celecoxib", "meloxicam", "indomethacin"],
            rightTokens: ["ibuprofen", "naproxen", "diclofenac", "celecoxib", "meloxicam", "indomethacin"],
            severity: .moderate,
            kind: .duplicateTherapy,
            title: "Same drug class overlap",
            summary: "These medications sit in the same NSAID family, so stacking them can increase stomach, kidney, and bleeding risk.",
            recommendation: "Use one NSAID plan at a time unless a clinician specifically told you to combine them.",
            source: "Curated medication-safety rules"
        )
    ]

    private static let allergyRules: [AllergyRule] = [
        AllergyRule(
            id: "penicillin",
            allergyTokens: ["penicillin"],
            medicationTokens: ["penicillin", "amoxicillin", "augmentin", "ampicillin", "dicloxacillin"],
            severity: .high,
            title: "Matches a penicillin allergy",
            summary: "This medication falls in the penicillin family, which conflicts with the allergy listed in the profile.",
            recommendation: "Do not add or take it until the allergy history has been reviewed by a clinician.",
            source: "Profile allergy cross-check"
        ),
        AllergyRule(
            id: "sulfa",
            allergyTokens: ["sulfa", "sulfamethoxazole"],
            medicationTokens: ["bactrim", "sulfamethoxazole", "trimethoprim-sulfamethoxazole", "septra"],
            severity: .high,
            title: "Matches a sulfa allergy",
            summary: "This medication can conflict with a sulfa allergy listed in the profile.",
            recommendation: "Do not add or take it until the allergy history has been reviewed by a clinician.",
            source: "Profile allergy cross-check"
        )
    ]

    private static let commonDrugTokens: [String] = [
        "Ibuprofen", "Naproxen", "Diclofenac", "Celecoxib", "Meloxicam",
        "Lisinopril", "Losartan", "Valsartan", "Levothyroxine",
        "Iron", "Calcium", "Magnesium", "Ciprofloxacin", "Doxycycline",
        "Warfarin", "Spironolactone", "Potassium", "Amoxicillin", "Bactrim"
    ]
}
