import SwiftUI

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.46
        var path = Path()

        for index in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct BinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.16, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct CrumpledPaper: View {
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
            Path { path in
                path.move(to: CGPoint(x: 6, y: 18))
                path.addCurve(
                    to: CGPoint(x: 27, y: 10),
                    control1: CGPoint(x: 12, y: 5),
                    control2: CGPoint(x: 20, y: 25)
                )
                path.move(to: CGPoint(x: 9, y: 28))
                path.addCurve(
                    to: CGPoint(x: 28, y: 24),
                    control1: CGPoint(x: 16, y: 18),
                    control2: CGPoint(x: 19, y: 34)
                )
            }
            .stroke(Color.black.opacity(0.10), lineWidth: 1)
        }
        .rotationEffect(.degrees(Double((index * 17) % 31) - 15))
    }
}
