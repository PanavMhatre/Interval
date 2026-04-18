import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var selection: Tab = .home
    @State private var didPrepareHaptics = false

    enum Tab: Hashable {
        case home, docs, meds, chat, profile
    }

    var body: some View {
        Group {
            if let profile = profiles.first, profile.hasCompletedOnboarding {
                mainTabs
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

    private var mainTabs: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView().navigationBarHidden(true) }
                .tabItem { Label("Home",  systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack { DocumentsView().navigationBarHidden(true) }
                .tabItem { Label("Docs",  systemImage: "doc.text.fill") }
                .tag(Tab.docs)

            NavigationStack { MedicationsView().navigationBarHidden(true) }
                .tabItem { Label("Meds",  systemImage: "pills.fill") }
                .tag(Tab.meds)

            NavigationStack { ChatView() }
                .tabItem { Label("Chat",  systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.chat)

            NavigationStack { ProfileView().navigationBarHidden(true) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .tint(Theme.Palette.coralDeep)
        .onChange(of: selection) { _, _ in
            Haptics.select()
        }
    }
}

#Preview("App entry") {
    ContentView()
        .modelContainer(previewContainer())
}
