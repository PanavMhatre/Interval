import SwiftUI
import SwiftData

@main
struct IntervalApp: App {
    init() {
        // Must run before SwiftUI instantiates the TabView — the UITabBar
        // appearance proxy only affects tab bars created after it's set.
        // Configuring later would cause a one-frame flash of the system
        // default (light/dark) chrome on first tab tap.
        TabBarStyle.apply()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Medication.self,
            DoseLog.self,
            MedicalDocument.self,
            LabResult.self,
            HealthInsight.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
