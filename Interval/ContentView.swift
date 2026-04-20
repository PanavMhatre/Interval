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
        .preferredColorScheme(.light)
        .onAppear {
            SampleData.seedIfNeeded(context)
            if !didPrepareHaptics {
                Haptics.prepareAll()
                didPrepareHaptics = true
            }
            KeyboardDismissal.installIfNeeded()
        }
        .task {
            // Auto-link Apple Health on every launch. Apple's authorization
            // dialog only appears once; subsequent launches refresh silently.
            await appleHealth.bootstrap()
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(onProfileTap: { selection = .profile })
                    .navigationBarHidden(true)
            }
                .tabItem { tabLabel("HOME", selected: .home, activeSymbol: "house.fill", inactiveSymbol: "house") }
                .tag(Tab.home)

            NavigationStack { DocumentsView().navigationBarHidden(true) }
                .tabItem { tabLabel("DOCS", selected: .docs, activeSymbol: "doc.text.fill", inactiveSymbol: "doc.text") }
                .tag(Tab.docs)

            NavigationStack { MedicationsView().navigationBarHidden(true) }
                .tabItem { tabLabel("MEDS", selected: .meds, activeSymbol: "pills.fill", inactiveSymbol: "pills") }
                .tag(Tab.meds)

            NavigationStack { ChatView() }
                .tabItem { tabLabel("CHAT", selected: .chat, activeSymbol: "message.fill", inactiveSymbol: "message") }
                .tag(Tab.chat)

            NavigationStack { ProfileView().navigationBarHidden(true) }
                .tabItem { tabLabel("PROFILE", selected: .profile, activeSymbol: "person.fill", inactiveSymbol: "person") }
                .tag(Tab.profile)
        }
        .tint(Theme.Palette.primary)
        .toolbarBackground(Theme.Palette.surfaceContainerLowest, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selection) { _, _ in
            Haptics.select()
        }
    }

    private func tabLabel(_ title: String, selected tab: Tab, activeSymbol: String, inactiveSymbol: String) -> some View {
        Label(title, systemImage: selection == tab ? activeSymbol : inactiveSymbol)
    }
}

// MARK: - One-shot UIKit tab bar appearance

/// Applied exactly once at process launch (see `IntervalApp.init`). Setting
/// `UITabBar.appearance()` only affects tab bars created *after* the call, so
/// we must run this before SwiftUI instantiates the TabView. Applying it in
/// `.onAppear` caused a one-frame flicker where the system default (light in
/// light mode, dark in dark mode) painted before our custom chrome took over.
enum TabBarStyle {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Palette.surfaceContainerLowest)
        appearance.shadowColor = UIColor(Theme.Palette.outlineVariant.opacity(0.45))

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(Theme.Palette.onSurfaceVariant)
        normal.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.onSurfaceVariant),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .kern: 0.8
        ]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(Theme.Palette.primary)
        selected.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.primary),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .kern: 0.9
        ]

        appearance.inlineLayoutAppearance = appearance.stackedLayoutAppearance
        appearance.compactInlineLayoutAppearance = appearance.stackedLayoutAppearance

        let proxy = UITabBar.appearance()
        proxy.standardAppearance = appearance
        proxy.scrollEdgeAppearance = appearance
        proxy.unselectedItemTintColor = UIColor(Theme.Palette.onSurfaceVariant)
    }
}

#Preview("App entry") {
    ContentView()
        .modelContainer(previewContainer())
}
