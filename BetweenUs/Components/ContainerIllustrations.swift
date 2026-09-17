import SwiftUI

enum ContainerVisualStyle {
    case compact
    case room
    case detail

    var contentLimit: Int {
        switch self {
        case .compact: return 4
        case .room: return 10
        case .detail: return 10
        }
    }

    var shadowScale: CGFloat {
        switch self {
        case .compact: return 0.55
        case .room: return 0.78
        case .detail: return 1
        }
    }
}

struct ProceduralPalette {
    let light: Color
    let base: Color
    let shade: Color
    let edge: Color
    let highlight: Color
    let shadow: Color

    static let amberGlass = ProceduralPalette(
        light: Color(red: 0.96, green: 0.72, blue: 0.32).opacity(0.52),
        base: Color(red: 0.73, green: 0.42, blue: 0.16).opacity(0.48),
        shade: Color(red: 0.40, green: 0.22, blue: 0.10).opacity(0.62),
        edge: Color(red: 0.48, green: 0.27, blue: 0.12).opacity(0.68),
        highlight: Color(red: 1.00, green: 0.88, blue: 0.63).opacity(0.64),
        shadow: Color(red: 0.24, green: 0.14, blue: 0.08).opacity(0.18)
    )

    static let sageEnamel = ProceduralPalette(
        light: Color(red: 0.79, green: 0.84, blue: 0.76),
        base: Color(red: 0.52, green: 0.62, blue: 0.53),
        shade: Color(red: 0.31, green: 0.40, blue: 0.34),
        edge: Color(red: 0.25, green: 0.34, blue: 0.29).opacity(0.58),
        highlight: Color(red: 0.93, green: 0.92, blue: 0.82).opacity(0.76),
        shadow: Color(red: 0.16, green: 0.22, blue: 0.18).opacity(0.18)
    )

    static let paperFiber = ProceduralPalette(
        light: Color(red: 0.86, green: 0.82, blue: 0.76),
        base: Color(red: 0.62, green: 0.58, blue: 0.54),
        shade: Color(red: 0.39, green: 0.36, blue: 0.34),
        edge: Color(red: 0.31, green: 0.29, blue: 0.28).opacity(0.52),
        highlight: Color(red: 0.98, green: 0.94, blue: 0.85).opacity(0.60),
        shadow: Color.black.opacity(0.15)
    )

    static let warmWood = ProceduralPalette(
        light: Color(red: 0.71, green: 0.49, blue: 0.29),
        base: Color(red: 0.51, green: 0.33, blue: 0.20),
        shade: Color(red: 0.31, green: 0.20, blue: 0.14),
        edge: Color(red: 0.25, green: 0.16, blue: 0.11).opacity(0.58),
        highlight: Color.white.opacity(0.24),
        shadow: Color.black.opacity(0.17)
    )
}

private struct ProceduralSurface<Surface: Shape>: View {
    let shape: Surface
    let palette: ProceduralPalette
    var edgeWidth: CGFloat = 1.2
    var highlightStrength: CGFloat = 1
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 6

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [palette.light, palette.base, palette.shade],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                LinearGradient(
                    colors: [palette.highlight.opacity(highlightStrength), .clear, Color.black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask(shape)
            }
            .overlay { shape.stroke(palette.edge, lineWidth: edgeWidth) }
            .shadow(color: palette.shadow, radius: shadowRadius, y: shadowY)
    }
}

/// The single public container renderer used by home, details, onboarding and loading.
struct ContainerVisual: View {
    let kind: ContainerKind
    let count: Int
    var style: ContainerVisualStyle = .room
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch kind {
                case .star:
                    StarBottleView(count: min(max(count, 0), style.contentLimit))
                case .capsule:
                    CapsuleJarVisual(count: min(max(count, 0), style.contentLimit))
                case .paper:
                    TrashBinVisual()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ParametricTokenView: View {
    let kind: ContainerKind
    var seed = 0
    var filled = true

    var body: some View {
        GeometryReader { proxy in
            switch kind {
            case .star:
                let star = StarShape(
                    innerRatio: 0.46 + CGFloat(seed % 3) * 0.015,
                    roundness: 0.13
                )
                ZStack {
                    star
                        .fill(
                            LinearGradient(
                                colors: filled
                                    ? starFillColors
                                    : [AppTheme.paper, Color(red: 0.88, green: 0.82, blue: 0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    StarFacetShape()
                        .stroke(Color.white.opacity(filled ? 0.30 : 0.20), lineWidth: max(0.65, proxy.size.width * 0.018))
                        .padding(proxy.size.width * 0.18)
                    star
                        .stroke(Color(red: 0.42, green: 0.24, blue: 0.10).opacity(0.34), lineWidth: max(0.7, proxy.size.width * 0.018))
                }
                .shadow(color: kind.tint.opacity(filled ? 0.18 : 0.08), radius: proxy.size.width * 0.10, y: proxy.size.width * 0.06)

            case .capsule:
                CapsuleTokenView()
                    .opacity(filled ? 1 : 0.72)

            case .paper:
                CrumpledPaper(index: seed)
                    .opacity(filled ? 1 : 0.82)
                    .shadow(color: Color.black.opacity(0.07), radius: proxy.size.width * 0.09, y: proxy.size.width * 0.06)
            }
        }
    }

    private var starFillColors: [Color] {
        switch seed % 5 {
        case 0:
            return [
                Color(red: 1.00, green: 0.84, blue: 0.46),
                Color(red: 0.98, green: 0.62, blue: 0.22),
                Color(red: 0.72, green: 0.36, blue: 0.12)
            ]
        case 1:
            return [
                Color(red: 1.00, green: 0.74, blue: 0.82),
                Color(red: 0.90, green: 0.40, blue: 0.56),
                Color(red: 0.58, green: 0.20, blue: 0.32)
            ]
        case 2:
            return [
                Color(red: 0.74, green: 0.94, blue: 0.92),
                Color(red: 0.30, green: 0.70, blue: 0.76),
                Color(red: 0.14, green: 0.42, blue: 0.50)
            ]
        case 3:
            return [
                Color(red: 1.00, green: 0.80, blue: 0.44),
                Color(red: 0.96, green: 0.50, blue: 0.16),
                Color(red: 0.68, green: 0.30, blue: 0.10)
            ]
        default:
            return [
                Color(red: 0.84, green: 0.96, blue: 0.54),
                Color(red: 0.52, green: 0.76, blue: 0.28),
                Color(red: 0.30, green: 0.48, blue: 0.16)
            ]
        }
    }
}

private struct StarFacetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<5 {
            let angle = -.pi / 2 + CGFloat(index) * 2 * .pi / 5
            path.move(to: center)
            path.addLine(
                to: CGPoint(
                    x: center.x + cos(angle) * rect.width * 0.50,
                    y: center.y + sin(angle) * rect.height * 0.50
                )
            )
        }
        return path
    }
}



