import SwiftUI

/// Coordinates belong to the exported 512 × 512 jar artwork, shared by every surface.
enum CapsuleJarMetrics {
    static let maximumVisibleCount = 10
    static let mouth = CGPoint(x: 0.50, y: 0.145)
    static let opening = CGRect(x: 0.335, y: 0.105, width: 0.33, height: 0.075)
    static let tokenAspect: CGFloat = 192.0 / 512.0
    static let tokenHeight: CGFloat = 0.19
    static let slots: [CGPoint] = [
        CGPoint(x: 0.38, y: 0.81), CGPoint(x: 0.50, y: 0.80), CGPoint(x: 0.62, y: 0.81),
        CGPoint(x: 0.40, y: 0.65), CGPoint(x: 0.53, y: 0.64), CGPoint(x: 0.63, y: 0.64),
        CGPoint(x: 0.38, y: 0.48), CGPoint(x: 0.50, y: 0.47), CGPoint(x: 0.62, y: 0.48),
        CGPoint(x: 0.50, y: 0.31)
    ]

    static func tokenSize(in frame: CGRect) -> CGSize {
        let height = frame.width * tokenHeight
        return CGSize(width: height * tokenAspect, height: height)
    }

    static func openingBounds(in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + opening.minX * frame.width,
               y: frame.minY + opening.minY * frame.height,
               width: opening.width * frame.width, height: opening.height * frame.height)
    }
}

/// The cap is already aligned with the neck in its PNG. Only actual opening motion lives here.
@MainActor
final class CapsuleJarLidController: ObservableObject, ContainerPreparationPlugin, ContainerRestorationPlugin {
    @Published private(set) var progress: CGFloat = 0
    let preparationDuration: TimeInterval = 0.72
    let restorationDuration: TimeInterval = 0.72
    private let driver: AnimationDriver
    private var animation: UUID?
    private var reduced = false
    private var restoring = false

    init(animationDriver: AnimationDriver) { driver = animationDriver }

    func prepare(reduceMotion: Bool) {
        cancelAnimation()
        reduced = reduceMotion
        restoring = false
        if reduceMotion {
            progress = 1
        } else {
            animation = driver.spring(from: progress, to: 1, configuration: .objectLid,
                update: { [weak self] in self?.progress = $0 }, completion: {})
        }
    }

    func updatePreparation(progress: CGFloat) { }
    func holdOpen() {
        guard !restoring else { return }
        if reduced { progress = 1 }
    }

    func restore(reduceMotion: Bool) {
        cancelAnimation()
        restoring = true
        if reduceMotion { progress = 0; return }
        animation = driver.spring(from: progress, to: 0, configuration: .objectLid,
            update: { [weak self] in self?.progress = $0 }, completion: {})
    }

    func updateRestoration(progress: CGFloat) { }
    func finishRestoration() {
        cancelAnimation()
        progress = 0
        restoring = false
    }

    private func cancelAnimation() {
        if let animation { driver.cancel(animation) }
        animation = nil
    }
}

struct CapsuleTokenView: View {
    var opening: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let amount = min(max(opening, 0), 1)
            let parts = min(amount * 8, 1)
            ZStack {
                Image("Capsule_Closed").resizable().interpolation(.high).scaledToFit()
                    .opacity(1 - parts)
                Image("Capsule_Bottom").resizable().interpolation(.high).scaledToFit()
                    .offset(y: proxy.size.height * amount * 0.10)
                    .opacity(parts)
                Image("Capsule_Top").resizable().interpolation(.high).scaledToFit()
                    .offset(y: -proxy.size.height * amount * 0.24)
                    .opacity(parts)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct CapsuleJarForeground: View {
    var body: some View {
        Image("CapsuleJar_Body")
            .resizable().interpolation(.high).scaledToFit()
    }
}

struct CapsuleJarVisual: View {
    let count: Int
    var trackedContentIndex: Int? = nil
    @EnvironmentObject private var room: RoomWorld

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let visible = min(max(count, 0), CapsuleJarMetrics.maximumVisibleCount)
            let size = CapsuleJarMetrics.tokenSize(in: CGRect(x: 0, y: 0, width: side, height: side))
            let opening = min(max(room.capsuleLid.progress, 0), 1)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: side * 0.46, height: side * 0.045)
                    .blur(radius: side * 0.022)
                    .position(x: side * 0.50, y: side * 0.94)
                ForEach(0..<visible, id: \.self) { index in
                    CapsuleTokenView()
                        .frame(width: size.width, height: size.height)
                        .background {
                            if trackedContentIndex != nil, index == visible - 1 {
                                RevealAnchorProbe(kind: .capsule, id: .content)
                            }
                        }
                        .position(x: side * CapsuleJarMetrics.slots[index].x,
                                  y: side * CapsuleJarMetrics.slots[index].y)
                }
                CapsuleJarForeground()
                Image("CapsuleJar_Lid")
                    .resizable().interpolation(.high).scaledToFit()
                    .rotationEffect(.degrees(-8 * Double(opening)), anchor: UnitPoint(x: 0.5, y: 0.15))
                    .offset(x: side * 0.34 * opening * opening,
                            y: -side * 0.08 * opening)
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
