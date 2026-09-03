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
    var interactionProgress: CGFloat = 0
    var isActive = false
    var reportsRevealAnchors = false
    var trackedContentIndex: Int? = nil
    var sharedStarPhysics: StarJarPhysicsSystem? = nil

    @StateObject private var starPhysics = StarJarPhysicsSystem()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch kind {
                case .star:
                    StarBottleView(
                        physics: sharedStarPhysics ?? starPhysics,
                        count: min(max(count, 0), style.contentLimit),
                        reportsRevealAnchors: reportsRevealAnchors
                    )
                case .capsule:
                    CapsuleKeepsakeVisual(
                        count: min(max(count, 0), style.contentLimit),
                        progress: interactionProgress,
                        isActive: isActive,
                        shadowScale: style.shadowScale,
                        trackedContentIndex: trackedContentIndex
                    )
                case .paper:
                    PaperHolderVisual(
                        count: min(max(count, 0), style.contentLimit),
                        progress: interactionProgress,
                        isActive: isActive,
                        shadowScale: style.shadowScale,
                        trackedContentIndex: trackedContentIndex
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(1 - min(max(interactionProgress, 0), 1) * 0.012)
            .offset(y: min(max(interactionProgress, 0), 1) * 2)
            .background {
                if reportsRevealAnchors, kind != .star {
                    RevealAnchorProbe(kind: kind, id: .container)
                }
            }
            .overlay {
                if reportsRevealAnchors, kind != .star {
                    GeometryReader { geometry in
                        let unit = ContainerRevealAnchors.exitUnit(for: kind)
                        RevealAnchorProbe(kind: kind, id: .exit)
                            .frame(width: 2, height: 2)
                            .position(
                                x: geometry.size.width * unit.x,
                                y: geometry.size.height * unit.y
                            )
                    }
                    .allowsHitTesting(false)
                }
            }
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
                let capsule = SpherocylinderShape()
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(filled ? capsuleColor : AppTheme.paper)
                        Rectangle()
                            .fill(filled ? Color(red: 0.92, green: 0.89, blue: 0.78) : Color.white.opacity(0.86))
                    }
                    .clipShape(capsule)
                    capsule
                        .stroke(Color(red: 0.22, green: 0.29, blue: 0.25).opacity(0.30), lineWidth: max(0.7, proxy.size.height * 0.035))
                    Rectangle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: max(0.8, proxy.size.width * 0.018))
                        .padding(.vertical, proxy.size.height * 0.12)
                }
                .shadow(color: kind.tint.opacity(filled ? 0.15 : 0.06), radius: proxy.size.height * 0.18, y: proxy.size.height * 0.10)

            case .paper:
                CrumpledPaper(index: seed)
                    .opacity(filled ? 1 : 0.82)
                    .shadow(color: Color.black.opacity(0.07), radius: proxy.size.width * 0.09, y: proxy.size.width * 0.06)
            }
        }
    }

    private var capsuleColor: Color {
        switch seed % 4 {
        case 0: return Color(red: 0.47, green: 0.62, blue: 0.53)
        case 1: return Color(red: 0.71, green: 0.51, blue: 0.39)
        case 2: return Color(red: 0.42, green: 0.56, blue: 0.63)
        default: return Color(red: 0.64, green: 0.57, blue: 0.68)
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

private struct CapsuleKeepsakeVisual: View {
    let count: Int
    let progress: CGFloat
    let isActive: Bool
    let shadowScale: CGFloat
    var trackedContentIndex: Int? = nil

    private let positions: [CGPoint] = [
        .init(x: 0.36, y: 0.54), .init(x: 0.55, y: 0.54), .init(x: 0.67, y: 0.60),
        .init(x: 0.43, y: 0.63), .init(x: 0.58, y: 0.64), .init(x: 0.31, y: 0.63),
        .init(x: 0.48, y: 0.56), .init(x: 0.70, y: 0.54)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let clampedProgress = min(max(progress, 0), 1)
            let shell = SuperellipseShape(exponent: ParametricPreset.keepsakeBoxExponent)
            let reveal = pow(clampedProgress, 0.72)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: width * 0.72, height: height * 0.08)
                    .blur(radius: 9 * shadowScale)
                    .offset(y: height * 0.28)

                ProceduralSurface(
                    shape: shell,
                    palette: .sageEnamel,
                    edgeWidth: max(1, width * 0.006),
                    shadowRadius: 10 * shadowScale,
                    shadowY: 6 * shadowScale
                )
                .frame(width: width * 0.88, height: height * 0.48)
                .offset(y: height * 0.06)

                shell
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.91, green: 0.89, blue: 0.80),
                                Color(red: 0.76, green: 0.78, blue: 0.68)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        shell.stroke(Color.white.opacity(0.62), lineWidth: max(1, width * 0.005))
                    }
                    .frame(width: width * 0.76, height: height * 0.32)
                    .offset(y: height * 0.03)
                    .opacity(0.12 + reveal * 0.88)

                HStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.42))
                    Rectangle().fill(Color.white.opacity(0.24))
                    Rectangle().fill(Color.white.opacity(0.34))
                }
                .frame(width: width * 0.58, height: 1)
                .offset(y: height * 0.03)
                .opacity(reveal * 0.55)

                ForEach(0..<min(count, positions.count), id: \.self) { index in
                    let position = positions[index]
                    ParametricTokenView(kind: .capsule, seed: index)
                        .frame(width: width * 0.17, height: width * 0.066)
                        .rotationEffect(.degrees(Double(index.isMultiple(of: 2) ? -15 : 13)))
                        .background {
                            if trackedContentIndex == index {
                                RevealAnchorProbe(kind: .capsule, id: .content)
                            }
                        }
                        .position(x: width * position.x, y: height * (position.y - 0.06))
                        .offset(y: -reveal * height * CGFloat(0.008 + Double(index % 3) * 0.004))
                        .scaleEffect(0.88 + reveal * 0.12)
                        .opacity(reveal)
                }

                HStack(spacing: width * 0.28) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.66, green: 0.53, blue: 0.31).opacity(0.72))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.66, green: 0.53, blue: 0.31).opacity(0.72))
                }
                .frame(width: width * 0.46, height: max(3, height * 0.02))
                .offset(y: -height * 0.14)
                .opacity(0.35 + reveal * 0.65)

                ZStack {
                    ProceduralSurface(
                        shape: shell,
                        palette: .sageEnamel,
                        edgeWidth: max(1, width * 0.006),
                        highlightStrength: isActive ? 1 : 0.76,
                        shadowRadius: (7 + reveal * 6) * shadowScale,
                        shadowY: (4 + reveal * 3) * shadowScale
                    )

                    shell
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        .padding(width * 0.032)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.72, green: 0.58, blue: 0.34).opacity(0.76))
                        .frame(width: width * 0.10, height: max(3, height * 0.024))
                        .offset(y: height * 0.17)
                }
                .frame(width: width * 0.88, height: height * 0.48)
                .offset(y: height * (0.02 - clampedProgress * 0.012))
                .rotation3DEffect(
                    .degrees(-Double(clampedProgress) * 72),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.55
                )

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.68, green: 0.54, blue: 0.31).opacity(0.76))
                    .frame(width: width * 0.11, height: max(3, height * 0.024))
                    .offset(y: height * 0.26)
            }
        }
    }
}

private struct PaperHolderVisual: View {
    let count: Int
    let progress: CGFloat
    let isActive: Bool
    let shadowScale: CGFloat
    var trackedContentIndex: Int? = nil

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let clampedProgress = min(max(progress, 0), 1)
            let imageName = count > 0 ? "PaperBinFilled" : "PaperBinEmpty"

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: side * 0.58, height: side * 0.08)
                    .blur(radius: 9 * shadowScale)
                    .offset(y: side * 0.34)

                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .scaleEffect(1 + clampedProgress * 0.02)
                    .offset(y: -clampedProgress * side * 0.018)
                    .shadow(
                        color: ContainerKind.paper.tint.opacity(isActive ? 0.18 : 0.08),
                        radius: (isActive ? 14 : 10) * shadowScale,
                        y: 6 * shadowScale
                    )
                    .overlay {
                        if trackedContentIndex != nil {
                            GeometryReader { geometry in
                                RevealAnchorProbe(kind: .paper, id: .content)
                                    .frame(width: 2, height: 2)
                                    .position(
                                        x: geometry.size.width * 0.50,
                                        y: geometry.size.height * 0.42
                                    )
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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



