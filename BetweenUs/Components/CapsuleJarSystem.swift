import SwiftUI

/// Token coordinates still belong to the capsule artwork, not the box frames.
enum CapsuleJarMetrics {
    static let maximumVisibleCount = 10
    /// 与 `Capsule_Closed` 不透明主体 75×228 @256 画布一致。
    static let tokenAspect: CGFloat = 75.0 / 228.0
    static let tokenHeight: CGFloat = 0.19
    static let slots: [CGPoint] = [
        CGPoint(x: 0.38, y: 0.81), CGPoint(x: 0.50, y: 0.80), CGPoint(x: 0.62, y: 0.81),
        CGPoint(x: 0.40, y: 0.65), CGPoint(x: 0.53, y: 0.64), CGPoint(x: 0.63, y: 0.64),
        CGPoint(x: 0.38, y: 0.48), CGPoint(x: 0.50, y: 0.47), CGPoint(x: 0.62, y: 0.48),
        CGPoint(x: 0.50, y: 0.31)
    ]
}

struct CapsuleTokenView: View {
    var body: some View {
        Image("Capsule_Closed")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct CapsuleJarVisual: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: side * 0.58, height: side * 0.055)
                    .blur(radius: side * 0.018)
                    .position(x: side * 0.50, y: side * 0.88)

                Image("Capsule_Open_00")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
