import SwiftUI
import UIKit

// Installs a window-level tap gesture that resigns the first responder
// whenever the user taps outside a text field. `cancelsTouchesInView = false`
// ensures buttons, chips, and other controls still receive their taps.
enum KeyboardDismissal {
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = KeyboardDismissDelegate.shared
        window.addGestureRecognizer(tap)
        installed = true
    }
}

private final class KeyboardDismissDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissDelegate()

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
