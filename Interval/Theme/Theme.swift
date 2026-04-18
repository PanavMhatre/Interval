import SwiftUI

enum Theme {

    // MARK: - Palette (VitalVault "golden hour")

    enum Palette {
        // Warm cream / peach surfaces
        static let paper        = Color(red: 1.000, green: 0.972, blue: 0.960) // #fff8f5
        static let paperSoft    = Color(red: 1.000, green: 0.945, blue: 0.912) // #fff1e9
        static let card         = Color.white
        static let peachTint    = Color(red: 1.000, green: 0.918, blue: 0.867) // #ffeadd
        static let peachSoft    = Color(red: 1.000, green: 0.945, blue: 0.912) // #fff1e9
        static let peachDeep    = Color(red: 0.953, green: 0.875, blue: 0.820) // #f3dfd1

        // Ink
        static let ink          = Color(red: 0.141, green: 0.098, blue: 0.071) // #241912
        static let inkSoft      = Color(red: 0.337, green: 0.263, blue: 0.204) // #564334
        static let inkMuted     = Color(red: 0.537, green: 0.451, blue: 0.384) // #897362
        static let hairline     = Color(red: 0.867, green: 0.757, blue: 0.682) // #ddc1ae

        // Primary — vibrant "golden hour" orange
        static let coral        = Color(red: 1.000, green: 0.549, blue: 0.000) // #ff8c00
        static let coralDeep    = Color(red: 0.565, green: 0.302, blue: 0.000) // #904d00

        // Secondary coral-red
        static let secondary    = Color(red: 0.996, green: 0.494, blue: 0.310) // #fe7e4f
        static let secondaryDeep = Color(red: 0.643, green: 0.235, blue: 0.071) // #a43c12

        // Sunny yellow-olive (tertiary)
        static let sunny        = Color(red: 0.780, green: 0.659, blue: 0.000) // #c7a800
        static let sunnyDeep    = Color(red: 0.439, green: 0.365, blue: 0.000) // #705d00

        // Mint / teal (success + tab accent)
        static let sage         = Color(red: 0.725, green: 0.875, blue: 0.690)
        static let sageDeep     = Color(red: 0.165, green: 0.616, blue: 0.561) // #2a9d8f
        static let mint         = Color(red: 0.863, green: 0.929, blue: 0.847)

        // Soft lilac (variety)
        static let lilac        = Color(red: 0.905, green: 0.870, blue: 0.965)
    }

    // MARK: - Typography (SF Rounded — closest match to Lexend on iOS)

    enum Font {
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let hero         = display(36, weight: .heavy)
        static let title        = display(28, weight: .bold)
        static let sectionTitle = display(22, weight: .bold)
        static let cardTitle    = body(17, weight: .semibold)
        static let bodyText     = body(15, weight: .regular)
        static let bodyBold     = body(15, weight: .semibold)
        static let caption      = body(12, weight: .medium)
        static let eyebrow      = body(11, weight: .semibold)
    }

    // MARK: - Layout

    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 14
        static let md: CGFloat = 22
        static let lg: CGFloat = 28
        static let xl: CGFloat = 36
        static let pill: CGFloat = 9999
    }
}

// MARK: - Reusable view modifiers

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.Palette.paper.ignoresSafeArea())
    }
}

/// Elevated card: warm-shadow depth, no visible border by default.
struct SoftCard: ViewModifier {
    var fill: Color = Theme.Palette.card
    var radius: CGFloat = Theme.Radius.md
    var stroke: Color = .clear
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: stroke == .clear ? 0 : 1)
            )
            .shadow(
                color: Theme.Palette.coral.opacity(elevated ? 0.10 : 0),
                radius: 14, x: 0, y: 6
            )
    }
}

/// Tinted warm glow for primary actions / hero elements.
struct WarmGlow: ViewModifier {
    var intensity: Double = 0.22
    func body(content: Content) -> some View {
        content.shadow(color: Theme.Palette.coral.opacity(intensity), radius: 16, x: 0, y: 10)
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
    func softCard(fill: Color = Theme.Palette.card,
                  radius: CGFloat = Theme.Radius.md,
                  stroke: Color = .clear,
                  elevated: Bool = true) -> some View {
        modifier(SoftCard(fill: fill, radius: radius, stroke: stroke, elevated: elevated))
    }
    func warmGlow(intensity: Double = 0.22) -> some View { modifier(WarmGlow(intensity: intensity)) }
    func eyebrowStyle() -> some View { modifier(EyebrowLabel()) }
}

// MARK: - Shared gradients

extension LinearGradient {
    static let goldenHour = LinearGradient(
        colors: [Theme.Palette.sunny, Theme.Palette.coral],
        startPoint: .leading, endPoint: .trailing
    )
    static let warmCard = LinearGradient(
        colors: [Theme.Palette.peachSoft, Theme.Palette.peachTint],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static let impactLight  = UIImpactFeedbackGenerator(style: .light)
    static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    static let selection    = UISelectionFeedbackGenerator()
    static let notification = UINotificationFeedbackGenerator()

    static func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        selection.prepare()
        notification.prepare()
    }

    static func tap()      { impactLight.impactOccurred() }
    static func select()   { selection.selectionChanged() }
    static func success()  { notification.notificationOccurred(.success) }
    static func warning()  { notification.notificationOccurred(.warning) }
    static func error()    { notification.notificationOccurred(.error) }
}
