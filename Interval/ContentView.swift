import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]

    @State private var didPrepareHaptics = false

    var body: some View {
        @Bindable var router = router
        return Group {
            if let profile = profiles.first, profile.hasCompletedOnboarding {
                TabView(selection: $router.tab) {
                    NavigationStack { HomeView().navigationBarHidden(true) }
                        .tabItem { Label("Home",  systemImage: "house.fill") }
                        .tag(AppTab.home)

                    NavigationStack { DocumentsView().navigationBarHidden(true) }
                        .tabItem { Label("Docs",  systemImage: "doc.text.fill") }
                        .tag(AppTab.docs)

                    NavigationStack { MedicationsView().navigationBarHidden(true) }
                        .tabItem { Label("Meds",  systemImage: "pills.fill") }
                        .tag(AppTab.meds)

                    NavigationStack { ChatView() }
                        .tabItem { Label("Chat",  systemImage: "bubble.left.and.bubble.right.fill") }
                        .tag(AppTab.chat)

                    NavigationStack { ProfileView().navigationBarHidden(true) }
                        .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                        .tag(AppTab.profile)
                }
                .tint(Theme.Palette.coral)
                .onChange(of: router.tab) { _, _ in
                    Haptics.select()
                }
            } else {
                OnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.smooth(duration: 0.45), value: profiles.first?.hasCompletedOnboarding)
        .onAppear {
            SampleData.seedIfNeeded(context)
            if !didPrepareHaptics {
                Haptics.prepareAll()
                didPrepareHaptics = true
            }
        }
    }
}

#Preview("App entry") {
    ContentView()
        .modelContainer(previewContainer())
        .environment(AppRouter())
}
