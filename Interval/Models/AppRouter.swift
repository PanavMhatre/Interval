import SwiftUI

enum AppTab: Hashable {
    case home, docs, meds, chat, profile
}

@Observable
final class AppRouter {
    var tab: AppTab = .home
    var pendingChatPrompt: String? = nil
}
