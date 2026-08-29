import SwiftUI

/// A small geometry kernel shared by every procedural object in the app.
/// Product shapes are parameter presets; curves, smoothing and deterministic variation live here.
enum ParametricGeometry {
    struct ProfilePoint {
        let y: CGFloat
        let halfWidth: CGFloat
    }

    static func roundedStar(
        in rect: CGRect,
        points: Int = 5,
        innerRatio: CGFloat = 0.47,
        roundness: CGFloat = 0.12,
        rotation: CGFloat = -.pi / 2
    ) -> Path {
        let pointCount = max(3, points)
        let vertexCount = pointCount * 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.48
        let innerRadius = outerRadius * min(max(innerRatio, 0.18), 0.82)
        let corner = min(max(roundness, 0), 0.32)

        let vertices = (0..<vertexCount).map { index -> CGPoint in
            let angle = rotation + CGFloat(index) * .pi / CGFloat(pointCount)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        let before = vertices.indices.map { index in
            interpolate(vertices[index], vertices[(index - 1 + vertexCount) % vertexCount], by: corner)
        }
        let after = vertices.indices.map { index in
            interpolate(vertices[index], vertices[(index + 1) % vertexCount], by: corner)
        }

        var path = Path()
        path.move(to: after[0])
        for step in 1...vertexCount {
            let index = step % vertexCount
            path.addLine(to: before[index])
            path.addQuadCurve(to: after[index], control: vertices[index])
        }
        path.closeSubpath()
        return path
    }

    static func superellipse(
        in rect: CGRect,
        exponent: CGFloat = 4.4,
        samples: Int = 72
    ) -> Path {
        let safeExponent = max(2, exponent)
        let power = 2 / safeExponent
        let sampleCount = max(24, samples)
        let a = rect.width / 2
        let b = rect.height / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let points = (0..<sampleCount).map { index -> CGPoint in
            let angle = CGFloat(index) / CGFloat(sampleCount) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = signedPower(cosine, power: power) * a
            let y = signedPower(sine, power: power) * b
            return CGPoint(x: center.x + x, y: center.y + y)
        }
        return smoothClosedPath(points, tension: 0.68)
    }

    static func spherocylinder(in rect: CGRect) -> Path {
        var path = Path()
        if rect.width >= rect.height {
            let radius = rect.height / 2
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.midY),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.midY),
                radius: radius,
                startAngle: .degrees(90),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            let radius = rect.width / 2
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }

    static func mirroredProfile(
        in rect: CGRect,
        profile: [ProfilePoint],
        tension: CGFloat = 0.70
    ) -> Path {
        let ordered = profile.sorted { $0.y < $1.y }
        guard ordered.count >= 3 else {
            var fallback = Path()
            fallback.addRect(rect)
            return fallback
        }

        let left = ordered.map { point in
            CGPoint(
                x: rect.midX - rect.width * min(max(point.halfWidth, 0.02), 0.5),
                y: rect.minY + rect.height * min(max(point.y, 0), 1)
            )
        }
        let right = ordered.reversed().map { point in
            CGPoint(
                x: rect.midX + rect.width * min(max(point.halfWidth, 0.02), 0.5),
                y: rect.minY + rect.height * min(max(point.y, 0), 1)
            )
        }
        return smoothClosedPath(left + right, tension: tension)
    }

    static func organicLoop(
        in rect: CGRect,
        seed: Int,
        roughness: CGFloat = 0.10,
        samples: Int = 32
    ) -> Path {
        let sampleCount = max(20, samples)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.45
        let radiusY = rect.height * 0.45
        let phaseA = phase(seed: seed, harmonic: 3)
        let phaseB = phase(seed: seed, harmonic: 5)
        let phaseC = phase(seed: seed, harmonic: 7)

        let points = (0..<sampleCount).map { index -> CGPoint in
            let angle = CGFloat(index) / CGFloat(sampleCount) * 2 * .pi
            let wave = sin(angle * 3 + phaseA) * roughness
                + sin(angle * 5 + phaseB) * roughness * 0.48
                + sin(angle * 7 + phaseC) * roughness * 0.22
            let radius = 1 + wave
            return CGPoint(
                x: center.x + cos(angle) * radiusX * radius,
                y: center.y + sin(angle) * radiusY * radius
            )
        }
        return smoothClosedPath(points, tension: 0.56)
    }

    static func creasePath(in rect: CGRect, seed: Int) -> Path {
        let drift = CGFloat((abs(seed) % 7) - 3) * 0.015
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * (0.32 + drift)))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * (0.43 - drift)),
            control1: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.10),
            control2: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + rect.height * 0.62)
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * (0.36 - drift), y: rect.minY + rect.height * 0.10))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * (0.52 + drift), y: rect.maxY - rect.height * 0.10),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.72)
        )
        return path
    }

    private static func smoothClosedPath(_ points: [CGPoint], tension: CGFloat) -> Path {
        guard points.count > 2 else { return Path() }
        let count = points.count
        let gain = min(max(tension, 0), 1) / 6
        var path = Path()
        path.move(to: points[0])

        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let following = points[(index + 2) % count]
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) * gain,
                y: current.y + (next.y - previous.y) * gain
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) * gain,
                y: next.y - (following.y - current.y) * gain
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }

    private static func signedPower(_ value: CGFloat, power: CGFloat) -> CGFloat {
        let magnitude = CGFloat(pow(Double(abs(value)), Double(power)))
        return value < 0 ? -magnitude : magnitude
    }

    private static func phase(seed: Int, harmonic: Int) -> CGFloat {
        let degrees = abs(seed &* 37 &+ harmonic &* 71) % 360
        return CGFloat(degrees) * .pi / 180
    }

    private static func interpolate(_ start: CGPoint, _ end: CGPoint, by amount: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount
        )
    }
}

enum ParametricPreset {
    static let starInnerRatio: CGFloat = 0.47
    static let starRoundness: CGFloat = 0.13
    static let keepsakeBoxExponent: CGFloat = 3.15
    static let openingExponent: CGFloat = 3.4

    static let bottleProfile: [ParametricGeometry.ProfilePoint] = [
        .init(y: 0.06, halfWidth: 0.23),
        .init(y: 0.16, halfWidth: 0.23),
        .init(y: 0.24, halfWidth: 0.36),
        .init(y: 0.36, halfWidth: 0.43),
        .init(y: 0.82, halfWidth: 0.45),
        .init(y: 0.94, halfWidth: 0.39),
        .init(y: 0.97, halfWidth: 0.31)
    ]

    static let paperHolderProfile: [ParametricGeometry.ProfilePoint] = [
        .init(y: 0.04, halfWidth: 0.46),
        .init(y: 0.16, halfWidth: 0.45),
        .init(y: 0.54, halfWidth: 0.39),
        .init(y: 0.90, halfWidth: 0.31),
        .init(y: 0.97, halfWidth: 0.27)
    ]
}

struct StarShape: Shape {
    var points = 5
    var innerRatio: CGFloat = ParametricPreset.starInnerRatio
    var roundness: CGFloat = ParametricPreset.starRoundness

    func path(in rect: CGRect) -> Path {
        ParametricGeometry.roundedStar(
            in: rect,
            points: points,
            innerRatio: innerRatio,
            roundness: roundness
        )
    }
}

struct SuperellipseShape: Shape {
    var exponent: CGFloat = 4.4

    func path(in rect: CGRect) -> Path {
        ParametricGeometry.superellipse(in: rect, exponent: exponent)
    }
}

struct SpherocylinderShape: Shape {
    func path(in rect: CGRect) -> Path {
        ParametricGeometry.spherocylinder(in: rect)
    }
}

struct ProfiledShape: Shape {
    let profile: [ParametricGeometry.ProfilePoint]
    var tension: CGFloat = 0.70

    func path(in rect: CGRect) -> Path {
        ParametricGeometry.mirroredProfile(in: rect, profile: profile, tension: tension)
    }
}

struct OrganicPaperShape: Shape {
    let seed: Int
    var roughness: CGFloat = 0.10

    func path(in rect: CGRect) -> Path {
        ParametricGeometry.organicLoop(in: rect, seed: seed, roughness: roughness)
    }
}

struct PaperCreaseShape: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        ParametricGeometry.creasePath(in: rect, seed: seed)
    }
}

struct BinShape: Shape {
    func path(in rect: CGRect) -> Path {
        ParametricGeometry.mirroredProfile(
            in: rect,
            profile: ParametricPreset.paperHolderProfile,
            tension: 0.62
        )
    }
}

struct CrumpledPaper: View {
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            let paper = OrganicPaperShape(seed: index, roughness: 0.105)
            ZStack {
                paper
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), AppTheme.paper.opacity(0.86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                paper
                    .stroke(Color.black.opacity(0.08), lineWidth: max(0.7, proxy.size.width * 0.018))
                PaperCreaseShape(seed: index)
                    .stroke(Color.black.opacity(0.10), lineWidth: max(0.6, proxy.size.width * 0.016))
                    .padding(proxy.size.width * 0.11)
            }
        }
        .rotationEffect(.degrees(Double((index * 17) % 31) - 15))
    }
}
