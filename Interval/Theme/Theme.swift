import SwiftUI

enum Theme {

    // MARK: - Palette

    enum Palette {
        static let paper        = Color(red: 0.965, green: 0.949, blue: 0.918)
        static let paperSoft    = Color(red: 0.984, green: 0.973, blue: 0.949)
        static let card         = Color.white
        static let ink          = Color(red: 0.094, green: 0.094, blue: 0.102)
        static let inkSoft      = Color(red: 0.329, green: 0.329, blue: 0.341)
        static let inkMuted     = Color(red: 0.541, green: 0.541, blue: 0.553)
        static let hairline     = Color(red: 0.835, green: 0.820, blue: 0.788)

        static let coral        = Color(red: 0.941, green: 0.490, blue: 0.388)
        static let coralDeep    = Color(red: 0.875, green: 0.388, blue: 0.290)
        static let peachTint    = Color(red: 0.996, green: 0.890, blue: 0.867)
        static let peachSoft    = Color(red: 0.988, green: 0.933, blue: 0.918)

        static let sage         = Color(red: 0.710, green: 0.831, blue: 0.686)
        static let sageDeep     = Color(red: 0.357, green: 0.557, blue: 0.341)
        static let mint         = Color(red: 0.863, green: 0.929, blue: 0.847)

        static let sunny        = Color(red: 0.988, green: 0.827, blue: 0.478)
        static let lilac        = Color(red: 0.820, green: 0.804, blue: 0.929)
    }

    // MARK: - Typography

    enum Font {
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let hero         = display(34, weight: .bold)
        static let title        = display(26, weight: .semibold)
        static let sectionTitle = display(20, weight: .semibold)
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
        static let lg:  CGFloat = 20
        static let xl:  CGFloat = 28
        static let xxl: CGFloat = 40
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
}

// MARK: - Reusable view modifiers

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.Palette.paper.ignoresSafeArea())
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
                    .strokeBorder(stroke, lineWidth: 1)
            )
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
                  stroke: Color = Theme.Palette.hairline) -> some View {
        modifier(SoftCard(fill: fill, radius: radius, stroke: stroke))
    }
    func eyebrowStyle() -> some View { modifier(EyebrowLabel()) }
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
