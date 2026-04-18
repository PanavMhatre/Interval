import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @StateObject private var appleHealth = AppleHealthStore()
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
        .environmentObject(appleHealth)
        .animation(.smooth(duration: 0.45), value: profiles.first?.hasCompletedOnboarding)
        .onAppear {
            SampleData.seedIfNeeded(context)
            configureTabBarAppearance()
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
        .tint(Theme.Palette.primary)
        .onChange(of: selection) { _, _ in
            Haptics.select()
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Palette.surfaceContainerLowest)
        appearance.shadowColor = UIColor(Theme.Palette.outlineVariant.opacity(0.45))

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(Theme.Palette.onSurfaceVariant)
        normal.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.onSurfaceVariant),
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(Theme.Palette.primary)
        selected.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.primary),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.Palette.onSurfaceVariant)
    }
}

#Preview("App entry") {
    ContentView()
        .modelContainer(previewContainer())
}
