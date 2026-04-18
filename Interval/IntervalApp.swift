import SwiftUI
import SwiftData

@main
struct IntervalApp: App {
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
