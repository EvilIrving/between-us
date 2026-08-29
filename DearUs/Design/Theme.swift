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
    static let roomWall = Color(red: 0.945, green: 0.918, blue: 0.855)
    static let roomTable = Color(red: 0.72, green: 0.61, blue: 0.47)

    static func backgroundGradient(for kind: ContainerKind? = nil) -> LinearGradient {
        let accent = kind?.tint ?? warmLight
        return LinearGradient(
            colors: [
                Color(red: 0.982, green: 0.970, blue: 0.944),
                background,
                accent.opacity(0.075)
            ],
            startPoint: .top,
            endPoint: .bottom
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

enum AppMotion {
    static let pressDuration: TimeInterval = 0.10
    static let modeDuration: TimeInterval = 0.16
    static let resetDuration: TimeInterval = 0.14
    static let settle = Animation.spring(response: 0.34, dampingFraction: 0.80)

    static func holdDuration(for kind: ContainerKind) -> TimeInterval {
        switch kind {
        case .star: return 0.72
        case .capsule: return 0.78
        case .paper: return 1.55
        }
    }
}
