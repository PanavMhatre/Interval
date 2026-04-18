import SwiftUI

struct SideEffectTip: Identifiable {
    let id = UUID()
    let source: String
    let effect: String
    let mitigation: String
    let icon: String
    let severity: Severity
    let tint: Color

    enum Severity { case info, caution, important }
}

enum MedicationAdvisor {
    static func tips(medications: [Medication], allergies: [String]) -> [SideEffectTip] {
        var out: [SideEffectTip] = []
        for med in medications {
            out.append(contentsOf: medicationTips(for: med))
        }
        out.append(contentsOf: interactionTips(for: medications))
        for allergen in allergies {
            out.append(contentsOf: allergyTips(for: allergen))
        }
        return out.sorted(by: { $0.severity.sortRank > $1.severity.sortRank })
    }

    private static func medicationTips(for med: Medication) -> [SideEffectTip] {
        let name = med.name.lowercased()
        let brand = med.brand?.lowercased() ?? ""
        var tips: [SideEffectTip] = []

        if name.contains("lisinopril") || name.contains("enalapril") || name.contains("ramipril") {
            tips.append(.init(
                source: med.name,
                effect: "Dizziness on standing",
                mitigation: "Rise slowly from bed or chairs. Hydrate, especially in heat.",
                icon: "figure.stand",
                severity: .caution,
                tint: Theme.Palette.coralDeep
            ))
            tips.append(.init(
                source: med.name,
                effect: "Dry cough",
                mitigation: "Sip warm fluids. If it lingers past 2 weeks, flag it to your doctor.",
                icon: "lungs.fill",
                severity: .info,
                tint: Theme.Palette.coral
            ))
        }

        if name.contains("metformin") {
            tips.append(.init(
                source: med.name,
                effect: "Stomach upset",
                mitigation: "Take with your largest meal. Ramp up slowly if recently started.",
                icon: "fork.knife",
                severity: .info,
                tint: Theme.Palette.coral
            ))
        }

        if name.contains("iron") || brand.contains("ferrous") {
            tips.append(.init(
                source: med.name,
                effect: "Constipation",
                mitigation: "Extra water + fiber. Pair with vitamin C to boost absorption.",
                icon: "drop.fill",
                severity: .info,
                tint: Theme.Palette.coral
            ))
        }

        if name.contains("ibuprofen") || name.contains("naproxen") || name.contains("aspirin") {
            tips.append(.init(
                source: med.name,
                effect: "Stomach irritation",
                mitigation: "Take with food and a full glass of water. Avoid daily use long-term.",
                icon: "fork.knife",
                severity: .caution,
                tint: Theme.Palette.coralDeep
            ))
        }

        if name.contains("hydrochlorothiazide") || name.contains("doxycycline")
            || name.contains("ciprofloxacin") || name.contains("tretinoin")
            || name.contains("retin") || name.contains("sulfa") {
            tips.append(.init(
                source: med.name,
                effect: "Sun sensitivity",
                mitigation: "Wear SPF 30+. Avoid midday sun. Hat + long sleeves on long outings.",
                icon: "sun.max.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            ))
        }

        if name.contains("warfarin") || name.contains("apixaban") || brand.contains("eliquis") {
            tips.append(.init(
                source: med.name,
                effect: "Bleeding risk",
                mitigation: "Avoid NSAIDs + heavy alcohol. Go easy on contact sports.",
                icon: "bandage.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            ))
        }

        if name.contains("statin") || name.contains("atorvastatin") || name.contains("simvastatin") {
            tips.append(.init(
                source: med.name,
                effect: "Muscle soreness",
                mitigation: "Skip grapefruit. Flag persistent aches — don't muscle through.",
                icon: "figure.run",
                severity: .caution,
                tint: Theme.Palette.coralDeep
            ))
        }

        if name.contains("cetirizine") || name.contains("diphenhydramine")
            || name.contains("benadryl") || name.contains("loratadine") {
            tips.append(.init(
                source: med.name,
                effect: "Drowsiness",
                mitigation: "Take in the evening if possible. Skip before driving long distances.",
                icon: "moon.fill",
                severity: .caution,
                tint: Theme.Palette.lilac
            ))
        }

        if name.contains("prednisone") || name.contains("corticosteroid") {
            tips.append(.init(
                source: med.name,
                effect: "Blood sugar spikes",
                mitigation: "Watch for extra thirst / urination. Don't stop abruptly — taper.",
                icon: "drop.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            ))
        }

        return tips
    }

    private static func interactionTips(for meds: [Medication]) -> [SideEffectTip] {
        let names = Set(meds.map { $0.name.lowercased() })
        let brands = Set(meds.compactMap { $0.brand?.lowercased() })
        let combined = names.union(brands)
        var tips: [SideEffectTip] = []

        let hasLisinopril = combined.contains { $0.contains("lisinopril") || $0.contains("enalapril") }
        let hasNSAID = combined.contains { $0.contains("ibuprofen") || $0.contains("naproxen") || $0.contains("advil") }
        if hasLisinopril && hasNSAID {
            tips.append(.init(
                source: "Lisinopril + NSAID",
                effect: "Kidney stress, reduced BP control",
                mitigation: "Keep NSAIDs short-term. Drink extra water. Space doses 2+ hours apart.",
                icon: "drop.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            ))
        }

        let hasIron = combined.contains { $0.contains("iron") || $0.contains("ferrous") }
        let hasThyroid = combined.contains { $0.contains("levothyroxine") || $0.contains("synthroid") }
        let hasCalcium = combined.contains { $0.contains("calcium") || $0.contains("tums") }
        if hasIron && (hasThyroid || hasCalcium) {
            tips.append(.init(
                source: "Iron absorption",
                effect: "Reduced uptake with thyroid / calcium",
                mitigation: "Space iron 4+ hours from thyroid meds, calcium, tea, and coffee.",
                icon: "clock.fill",
                severity: .caution,
                tint: Theme.Palette.coralDeep
            ))
        }

        let hasMetformin = combined.contains { $0.contains("metformin") }
        if hasMetformin {
            tips.append(.init(
                source: "Metformin",
                effect: "B12 depletion over time",
                mitigation: "Include B12-rich foods (eggs, fish, dairy) or a daily B-complex.",
                icon: "leaf.fill",
                severity: .info,
                tint: Theme.Palette.sageDeep
            ))
        }

        return tips
    }

    private static func allergyTips(for allergen: String) -> [SideEffectTip] {
        let a = allergen.lowercased()
        if a.contains("penicillin") || a.contains("amoxicillin") {
            return [.init(
                source: "Penicillin allergy",
                effect: "Beta-lactam antibiotics",
                mitigation: "Remind providers before any new prescription. Double-check pharmacy labels.",
                icon: "flag.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            )]
        }
        if a.contains("shellfish") {
            return [.init(
                source: "Shellfish allergy",
                effect: "Contrast imaging caution",
                mitigation: "Mention before CT or MRI scans with iodine contrast.",
                icon: "flag.fill",
                severity: .caution,
                tint: Theme.Palette.coralDeep
            )]
        }
        if a.contains("nut") || a.contains("peanut") {
            return [.init(
                source: allergen,
                effect: "Cross-contamination risk",
                mitigation: "Scan ingredient labels. Keep epinephrine accessible when eating out.",
                icon: "flag.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            )]
        }
        if a.contains("sulfa") {
            return [.init(
                source: "Sulfa allergy",
                effect: "Sulfonamide antibiotics + some diuretics",
                mitigation: "Flag it at every new-prescription check-in.",
                icon: "flag.fill",
                severity: .important,
                tint: Theme.Palette.coralDeep
            )]
        }
        return []
    }
}

private extension SideEffectTip.Severity {
    var sortRank: Int {
        switch self {
        case .important: 2
        case .caution:   1
        case .info:      0
        }
    }
}

extension MedicationAdvisor {
    struct Avoidance: Identifiable {
        let id = UUID()
        let medication: String
        let items: [String]
    }

    static func avoidances(for meds: [Medication]) -> [Avoidance] {
        meds.compactMap { med in
            let name = med.name.lowercased()
            let brand = med.brand?.lowercased() ?? ""
            let items: [String]
            if name.contains("lisinopril") || name.contains("enalapril") {
                items = [
                    "Daily NSAIDs (ibuprofen, naproxen)",
                    "Potassium salt substitutes",
                    "Heavy sweating without replacing fluids"
                ]
            } else if name.contains("metformin") {
                items = [
                    "Heavy alcohol",
                    "Iodine-contrast scans — pause 48h prior"
                ]
            } else if name.contains("iron") || brand.contains("ferrous") {
                items = [
                    "Calcium / dairy within 2 hours",
                    "Coffee or tea within 2 hours",
                    "Thyroid meds within 4 hours"
                ]
            } else if name.contains("ibuprofen") || name.contains("naproxen") || name.contains("aspirin") {
                items = [
                    "ACE inhibitors (e.g. Lisinopril)",
                    "Daily use beyond 10 days",
                    "Taking on an empty stomach"
                ]
            } else if name.contains("warfarin") || name.contains("apixaban") || brand.contains("eliquis") {
                items = [
                    "NSAIDs (ibuprofen, naproxen)",
                    "Sudden swings in leafy greens",
                    "More than 1 alcoholic drink per day"
                ]
            } else if name.contains("statin") || name.contains("atorvastatin") || name.contains("simvastatin") {
                items = [
                    "Grapefruit juice",
                    "Heavy alcohol"
                ]
            } else if name.contains("cetirizine") || name.contains("diphenhydramine") || name.contains("loratadine") {
                items = [
                    "Driving on the first few doses",
                    "Mixing with alcohol or sleep aids"
                ]
            } else if name.contains("doxycycline") || name.contains("ciprofloxacin") {
                items = [
                    "Dairy / calcium within 2 hours",
                    "Unprotected sun exposure",
                    "Antacids within 2 hours"
                ]
            } else {
                return nil
            }
            return Avoidance(medication: med.name, items: items)
        }
    }

    static func interactionPairs(from tips: [SideEffectTip]) -> [SideEffectTip] {
        tips.filter { $0.source.contains("+") || $0.source.lowercased().contains("absorption") }
    }
}
