import SwiftUI
import UIKit

enum Theme {

    // MARK: - Palette

    enum Palette {
        static let surface = Color(hex: "#fff8f5")
        static let surfaceDim = Color(hex: "#ead6c9")
        static let surfaceBright = Color(hex: "#fff8f5")
        static let surfaceContainerLowest = Color(hex: "#ffffff")
        static let surfaceContainerLow = Color(hex: "#fff1e9")
        static let surfaceContainer = Color(hex: "#ffeadd")
        static let surfaceContainerHigh = Color(hex: "#f9e4d7")
        static let surfaceContainerHighest = Color(hex: "#f3dfd1")
        static let surfaceVariant = Color(hex: "#f3dfd1")

        static let onSurface = Color(hex: "#241912")
        static let onSurfaceVariant = Color(hex: "#564334")
        static let inverseSurface = Color(hex: "#3a2e25")
        static let inverseOnSurface = Color(hex: "#ffede3")
        static let outline = Color(hex: "#897362")
        static let outlineVariant = Color(hex: "#ddc1ae")
        static let surfaceTint = Color(hex: "#904d00")

        static let primary = Color(hex: "#904d00")
        static let onPrimary = Color(hex: "#ffffff")
        static let primaryContainer = Color(hex: "#ff8c00")
        static let onPrimaryContainer = Color(hex: "#623200")
        static let inversePrimary = Color(hex: "#ffb77d")

        static let secondary = Color(hex: "#a43c12")
        static let onSecondary = Color(hex: "#ffffff")
        static let secondaryContainer = Color(hex: "#fe7e4f")
        static let onSecondaryContainer = Color(hex: "#6b1f00")

        static let tertiary = Color(hex: "#705d00")
        static let onTertiary = Color(hex: "#ffffff")
        static let tertiaryContainer = Color(hex: "#c7a800")
        static let onTertiaryContainer = Color(hex: "#4b3e00")

        static let error = Color(hex: "#ba1a1a")
        static let onError = Color(hex: "#ffffff")
        static let errorContainer = Color(hex: "#ffdad6")
        static let onErrorContainer = Color(hex: "#93000a")

        static let primaryFixed = Color(hex: "#ffdcc3")
        static let primaryFixedDim = Color(hex: "#ffb77d")
        static let onPrimaryFixed = Color(hex: "#2f1500")
        static let onPrimaryFixedVariant = Color(hex: "#6e3900")

        static let secondaryFixed = Color(hex: "#ffdbcf")
        static let secondaryFixedDim = Color(hex: "#ffb59c")
        static let onSecondaryFixed = Color(hex: "#380c00")
        static let onSecondaryFixedVariant = Color(hex: "#822800")

        static let tertiaryFixed = Color(hex: "#ffe16d")
        static let tertiaryFixedDim = Color(hex: "#e9c400")
        static let onTertiaryFixed = Color(hex: "#221b00")
        static let onTertiaryFixedVariant = Color(hex: "#544600")

        static let background = Color(hex: "#fff8f5")
        static let onBackground = Color(hex: "#241912")

        // Legacy aliases used across the app
        static let paper = background
        static let paperSoft = surfaceContainerLow
        static let card = surfaceContainerLowest
        static let ink = onSurface
        static let inkSoft = onSurfaceVariant
        static let inkMuted = outline
        static let hairline = outlineVariant

        static let coral = secondaryContainer
        static let coralDeep = secondary
        static let peachTint = secondaryFixed
        static let peachSoft = surfaceContainer

        static let sage = primaryFixed
        static let sageDeep = primary
        static let mint = surfaceContainerHigh

        static let sunny = tertiaryFixed
        static let lilac = primaryFixedDim
    }

    enum Shadow {
        static let ambient = Palette.primary.opacity(0.08)
        static let warm = Palette.secondary.opacity(0.10)
        static let glow = Palette.primaryFixedDim.opacity(0.22)
    }

    // MARK: - Typography

    enum Font {
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            lexend(size, weight: weight, relativeTo: .title2)
        }

        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            lexend(size, weight: weight, relativeTo: .body)
        }

        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let hero = display(40, weight: .bold)
        static let title = display(32, weight: .semibold)
        static let sectionTitle = display(24, weight: .semibold)
        static let cardTitle = body(18, weight: .semibold)
        static let bodyText = body(16, weight: .regular)
        static let bodyBold = body(16, weight: .semibold)
        static let caption = body(12, weight: .medium)
        static let eyebrow = body(12, weight: .semibold)

        private static func lexend(_ size: CGFloat, weight: SwiftUI.Font.Weight, relativeTo: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            let preferredName = lexendName(for: weight)

            if UIFont(name: preferredName, size: size) != nil {
                return .custom(preferredName, size: size, relativeTo: relativeTo)
            }

            if UIFont(name: "Lexend", size: size) != nil {
                return .custom("Lexend", size: size, relativeTo: relativeTo).weight(weight)
            }

            return .system(size: size, weight: weight, design: .rounded)
        }

        private static func lexendName(for weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .black, .heavy, .bold:
                return "Lexend-Bold"
            case .semibold:
                return "Lexend-SemiBold"
            case .medium:
                return "Lexend-Medium"
            default:
                return "Lexend-Regular"
            }
        }
    }

    // MARK: - Layout

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
    }
}

// MARK: - Reusable view modifiers

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.Palette.background.ignoresSafeArea())
    }
}

struct SoftCard: ViewModifier {
    var fill: Color = Theme.Palette.card
    var radius: CGFloat = Theme.Radius.md
    var stroke: Color = Theme.Palette.hairline

    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.ambient, radius: 18, y: 10)
            .shadow(color: Theme.Shadow.warm.opacity(0.35), radius: 6, y: 2)
    }
}

struct EyebrowLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.eyebrow)
            .tracking(1.2)
            .foregroundStyle(Theme.Palette.inkMuted)
            .textCase(.uppercase)
    }
}

extension View {
    func paperBackground() -> some View { modifier(PaperBackground()) }

    func softCard(
        fill: Color = Theme.Palette.card,
        radius: CGFloat = Theme.Radius.md,
        stroke: Color = Theme.Palette.hairline
    ) -> some View {
        modifier(SoftCard(fill: fill, radius: radius, stroke: stroke))
    }

    func eyebrowStyle() -> some View { modifier(EyebrowLabel()) }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static let impactLight = UIImpactFeedbackGenerator(style: .light)
    static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    static let selection = UISelectionFeedbackGenerator()
    static let notification = UINotificationFeedbackGenerator()

    static func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        selection.prepare()
        notification.prepare()
    }

    static func tap() { impactLight.impactOccurred() }
    static func select() { selection.selectionChanged() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    static func error() { notification.notificationOccurred(.error) }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
