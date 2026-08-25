import SwiftUI

/// The visual language deliberately resembles a quiet shared room rather than a utility screen.
enum AppTheme {
    static let background = Color(red: 0.965, green: 0.950, blue: 0.915)
    static let dusk = Color(red: 0.125, green: 0.118, blue: 0.130)
    static let surface = Color.white.opacity(0.72)
    static let paper = Color(red: 0.985, green: 0.972, blue: 0.934)
    static let primaryText = Color(red: 0.19, green: 0.18, blue: 0.17)
    static let secondaryText = Color(red: 0.40, green: 0.38, blue: 0.35)
    static let border = Color.black.opacity(0.08)
    static let warmLight = Color(red: 0.98, green: 0.77, blue: 0.39)

    static func backgroundGradient(for kind: ContainerKind? = nil) -> LinearGradient {
        let accent = kind?.tint ?? warmLight
        return LinearGradient(
            colors: [
                background,
                accent.opacity(0.11),
                Color(red: 0.92, green: 0.89, blue: 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glow(for kind: ContainerKind) -> RadialGradient {
        RadialGradient(
            colors: [kind.tint.opacity(0.28), kind.tint.opacity(0.02), .clear],
            center: .center,
            startRadius: 2,
            endRadius: 160
        )
    }
}
