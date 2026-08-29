import SwiftUI

enum ContainerVisualStyle {
    case compact
    case room
    case detail

    var contentLimit: Int {
        switch self {
        case .compact: return 4
        case .room: return 8
        case .detail: return 14
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch kind {
                case .star:
                    StarJarVisual(
                        count: min(max(count, 0), style.contentLimit),
                        progress: interactionProgress,
                        isActive: isActive,
                        shadowScale: style.shadowScale
                    )
                case .capsule:
                    CapsuleKeepsakeVisual(
                        count: min(max(count, 0), style.contentLimit),
                        progress: interactionProgress,
                        isActive: isActive,
                        shadowScale: style.shadowScale
                    )
                case .paper:
                    PaperHolderVisual(
                        count: min(max(count, 0), style.contentLimit),
                        progress: interactionProgress,
                        isActive: isActive,
                        shadowScale: style.shadowScale
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(1 - min(max(interactionProgress, 0), 1) * 0.012)
            .offset(y: min(max(interactionProgress, 0), 1) * 2)
        }
        .aspectRatio(kind == .capsule ? 1.30 : 0.88, contentMode: .fit)
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
                                    ? [Color(red: 1.00, green: 0.82, blue: 0.44), kind.tint, Color(red: 0.72, green: 0.36, blue: 0.12)]
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
}

private struct StarJarVisual: View {
    let count: Int
    let progress: CGFloat
    let isActive: Bool
    let shadowScale: CGFloat

    private let positions: [CGPoint] = [
        .init(x: 0.35, y: 0.76), .init(x: 0.51, y: 0.79), .init(x: 0.66, y: 0.74),
        .init(x: 0.29, y: 0.65), .init(x: 0.47, y: 0.65), .init(x: 0.64, y: 0.62),
        .init(x: 0.38, y: 0.54), .init(x: 0.57, y: 0.52), .init(x: 0.70, y: 0.48),
        .init(x: 0.31, y: 0.44), .init(x: 0.49, y: 0.41), .init(x: 0.64, y: 0.36),
        .init(x: 0.39, y: 0.31), .init(x: 0.55, y: 0.27)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let clampedProgress = min(max(progress, 0), 1)
            let bottle = ProfiledShape(profile: ParametricPreset.bottleProfile, tension: 0.73)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: width * 0.60, height: height * 0.075)
                    .blur(radius: 8 * shadowScale)
                    .offset(y: height * 0.43)

                bottle
                    .fill(
                        LinearGradient(
                            colors: [
                                ProceduralPalette.amberGlass.light,
                                ProceduralPalette.amberGlass.base,
                                ProceduralPalette.amberGlass.shade
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.horizontal, width * 0.12)
                    .padding(.vertical, height * 0.07)

                ForEach(0..<min(count, positions.count), id: \.self) { index in
                    let position = positions[index]
                    ParametricTokenView(kind: .star, seed: index)
                        .frame(width: width * (index.isMultiple(of: 4) ? 0.135 : 0.115), height: width * (index.isMultiple(of: 4) ? 0.135 : 0.115))
                        .rotationEffect(.degrees(Double(index * 31 - 24)))
                        .position(x: width * position.x, y: height * position.y)
                        .offset(y: -clampedProgress * height * CGFloat(0.018 + Double(index % 3) * 0.006))
                        .scaleEffect(1 + clampedProgress * (index.isMultiple(of: 2) ? 0.08 : 0.04))
                        .shadow(
                            color: ContainerKind.star.tint.opacity(clampedProgress * 0.32),
                            radius: 3 + clampedProgress * 8
                        )
                }

                bottle
                    .stroke(
                        LinearGradient(
                            colors: [ProceduralPalette.amberGlass.highlight, ProceduralPalette.amberGlass.edge, ProceduralPalette.amberGlass.highlight.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.2, width * 0.010)
                    )
                    .padding(.horizontal, width * 0.12)
                    .padding(.vertical, height * 0.07)

                BottleLightBand()
                    .fill(ProceduralPalette.amberGlass.highlight.opacity(isActive ? 0.54 : 0.36))
                    .frame(width: width * 0.13, height: height * 0.58)
                    .offset(x: -width * 0.22, y: height * 0.09)
                    .blur(radius: width * 0.006)

                ZStack {
                    SuperellipseShape(exponent: 4.2)
                        .fill(ProceduralPalette.warmWood.shade.opacity(0.82))
                        .overlay {
                            SuperellipseShape(exponent: 4.2)
                                .stroke(ProceduralPalette.warmWood.edge, lineWidth: max(1, width * 0.007))
                        }
                        .frame(width: width * 0.30, height: height * 0.09)
                        .offset(y: height * 0.062)

                    ProceduralSurface(
                        shape: SuperellipseShape(exponent: 5.2),
                        palette: .warmWood,
                        edgeWidth: max(1, width * 0.008),
                        shadowRadius: (7 + clampedProgress * 10) * shadowScale,
                        shadowY: (4 + clampedProgress * 7) * shadowScale
                    )
                    .frame(width: width * 0.50, height: height * 0.135)
                }
                .offset(
                    x: width * (0.30 * clampedProgress * clampedProgress),
                    y: -height * 0.405 - sin(clampedProgress * .pi / 2) * height * 0.17
                )
                .rotationEffect(.degrees(clampedProgress * 24), anchor: .bottomLeading)
            }
        }
    }
}

private struct CapsuleKeepsakeVisual: View {
    let count: Int
    let progress: CGFloat
    let isActive: Bool
    let shadowScale: CGFloat

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
                    .fill(Color.black.opacity(0.09))
                    .frame(width: width * 0.66, height: height * 0.075)
                    .blur(radius: 9 * shadowScale)
                    .offset(y: height * 0.31)

                ProceduralSurface(
                    shape: shell,
                    palette: .sageEnamel,
                    edgeWidth: max(1, width * 0.006),
                    shadowRadius: 10 * shadowScale,
                    shadowY: 6 * shadowScale
                )
                .frame(width: width * 0.76, height: height * 0.37)
                .offset(y: height * 0.12)

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
                    .frame(width: width * 0.66, height: height * 0.25)
                    .offset(y: height * 0.085)
                    .opacity(0.12 + reveal * 0.88)

                HStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.42))
                    Rectangle().fill(Color.white.opacity(0.24))
                    Rectangle().fill(Color.white.opacity(0.34))
                }
                .frame(width: width * 0.50, height: 1)
                .offset(y: height * 0.085)
                .opacity(reveal * 0.55)

                ForEach(0..<min(count, positions.count), id: \.self) { index in
                    let position = positions[index]
                    ParametricTokenView(kind: .capsule, seed: index)
                        .frame(width: width * 0.15, height: width * 0.058)
                        .rotationEffect(.degrees(Double(index.isMultiple(of: 2) ? -15 : 13)))
                        .position(x: width * position.x, y: height * position.y)
                        .offset(y: -reveal * height * CGFloat(0.008 + Double(index % 3) * 0.004))
                        .scaleEffect(0.88 + reveal * 0.12)
                        .opacity(reveal)
                }

                HStack(spacing: width * 0.25) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.66, green: 0.53, blue: 0.31).opacity(0.72))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.66, green: 0.53, blue: 0.31).opacity(0.72))
                }
                .frame(width: width * 0.40, height: max(3, height * 0.018))
                .offset(y: -height * 0.075)
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
                        .frame(width: width * 0.09, height: max(3, height * 0.022))
                        .offset(y: height * 0.15)
                }
                .frame(width: width * 0.76, height: height * 0.37)
                .offset(y: height * (0.075 - clampedProgress * 0.012))
                .rotation3DEffect(
                    .degrees(-Double(clampedProgress) * 72),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.55
                )

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.68, green: 0.54, blue: 0.31).opacity(0.76))
                    .frame(width: width * 0.10, height: max(3, height * 0.022))
                    .offset(y: height * 0.295)
            }
        }
    }
}

private struct PaperHolderVisual: View {
    let count: Int
    let progress: CGFloat
    let isActive: Bool
    let shadowScale: CGFloat

    private let paperPositions: [CGPoint] = [
        .init(x: 0.42, y: 0.72), .init(x: 0.55, y: 0.74), .init(x: 0.63, y: 0.69),
        .init(x: 0.35, y: 0.77), .init(x: 0.49, y: 0.79), .init(x: 0.62, y: 0.78),
        .init(x: 0.40, y: 0.67), .init(x: 0.54, y: 0.68), .init(x: 0.66, y: 0.73),
        .init(x: 0.33, y: 0.71), .init(x: 0.48, y: 0.75)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let clampedProgress = min(max(progress, 0), 1)
            let bin = BinShape()

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.11))
                    .frame(width: width * 0.59, height: height * 0.08)
                    .blur(radius: 9 * shadowScale)
                    .offset(y: height * 0.39)

                ProceduralSurface(
                    shape: bin,
                    palette: .paperFiber,
                    edgeWidth: max(1.1, width * 0.008),
                    highlightStrength: isActive ? 1 : 0.72,
                    shadowRadius: 12 * shadowScale,
                    shadowY: 8 * shadowScale
                )
                .frame(width: width * 0.68, height: height * 0.66)
                .offset(y: height * 0.13)

                SuperellipseShape(exponent: 3.2)
                    .fill(Color(red: 0.35, green: 0.32, blue: 0.30).opacity(0.34))
                    .frame(width: width * 0.65, height: height * 0.10)
                    .offset(y: -height * 0.18)

                ForEach(0..<min(count, paperPositions.count), id: \.self) { index in
                    let position = paperPositions[index]
                    ParametricTokenView(kind: .paper, seed: index)
                        .frame(width: width * 0.145, height: width * 0.14)
                        .position(x: width * position.x, y: height * position.y)
                        .offset(
                            x: clampedProgress * width * (index.isMultiple(of: 2) ? -0.025 : 0.025),
                            y: -clampedProgress * height * CGFloat(0.055 + Double(index % 3) * 0.012)
                        )
                        .rotationEffect(
                            .degrees(clampedProgress * Double(index.isMultiple(of: 2) ? -10 : 10))
                        )
                        .scaleEffect(1 + clampedProgress * 0.08)
                        .shadow(
                            color: ContainerKind.paper.tint.opacity(clampedProgress * 0.20),
                            radius: clampedProgress * 7
                        )
                }

                bin
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .clear, location: 0.30),
                                .init(color: ProceduralPalette.paperFiber.base.opacity(0.78), location: 0.52),
                                .init(color: ProceduralPalette.paperFiber.shade.opacity(0.94), location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.68, height: height * 0.66)
                    .offset(y: height * 0.13)

                SuperellipseShape(exponent: 3.2)
                    .stroke(ProceduralPalette.paperFiber.highlight.opacity(0.82), lineWidth: max(3, width * 0.025))
                    .frame(width: width * 0.68, height: height * 0.12)
                    .offset(y: -height * 0.18)
            }
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

private struct BottleLightBand: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.68, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.28, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.28),
            control2: CGPoint(x: rect.width * 0.72, y: rect.height * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.68, y: rect.minY),
            control1: CGPoint(x: rect.width * 0.50, y: rect.height * 0.70),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.22)
        )
        path.closeSubpath()
        return path
    }
}
