import SwiftUI

struct StarCharm: Hashable, Identifiable {
    let imageName: String
    let series: Int
    let mood: Int

    var id: String { imageName }

    static let all: [StarCharm] = {
        (1...5).flatMap { series in
            (1...6).map { mood in
                StarCharm(imageName: "StarCharm_\(series)_\(mood)", series: series, mood: mood)
            }
        }
    }()

    static func random() -> StarCharm {
        all.randomElement() ?? StarCharm(imageName: "StarCharm_1_1", series: 1, mood: 1)
    }

    static func displayCharms(count: Int) -> [StarCharm] {
        let n = min(max(count, 0), 3)
        guard n > 0 else { return [] }
        return (0..<n).map { index in
            all[(index * 11 + 3) % all.count]
        }
    }

    var idlePhase: Double {
        Double((series * 97 + mood * 163) % 628) / 100.0
    }
}

struct StarCharmImage: View {
    let charm: StarCharm

    var body: some View {
        Image(charm.imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

struct StarIdleBob: ViewModifier {
    let charm: StarCharm
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if !enabled || reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let sway = sin(time * 2 * .pi / 4.2 + charm.idlePhase)
                let tilt = sin(time * 2 * .pi / 5.6 + charm.idlePhase * 1.7)
                content
                    .offset(y: CGFloat(sway) * 3.0)
                    .rotationEffect(.degrees(Double(tilt) * 1.6))
            }
        }
    }
}

/// The only star-jar renderer. Home, detail, loading and onboarding share this bottle.
struct StarBottleView: View {
    var charms: [StarCharm]
    var drop: CGFloat = 1
    var neckScale: CGSize = CGSize(width: 1, height: 1)
    var reportsRevealAnchors = false
    var idleMotion = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(charms.enumerated()), id: \.element.id) { index, charm in
                    let layout = charmLayout(index: index, count: charms.count, side: side)
                    StarCharmImage(charm: charm)
                        .frame(width: layout.size, height: layout.size)
                        .modifier(StarIdleBob(charm: charm, enabled: idleMotion))
                        .scaleEffect(x: neckScale.width, y: neckScale.height)
                        .background {
                            if reportsRevealAnchors, index == charms.count - 1 {
                                RevealAnchorProbe(kind: .star, id: .content)
                            }
                        }
                        .position(layout.position)
                }

                Image("StarJarBottle")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .background {
                        if reportsRevealAnchors {
                            RevealAnchorProbe(kind: .star, id: .container)
                        }
                    }
                    .overlay {
                        if reportsRevealAnchors {
                            GeometryReader { bottle in
                                let unit = ContainerRevealAnchors.exitUnit(for: .star)
                                RevealAnchorProbe(kind: .star, id: .exit)
                                    .frame(width: 2, height: 2)
                                    .position(
                                        x: bottle.size.width * unit.x,
                                        y: bottle.size.height * unit.y
                                    )
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .background(
                        GeometryReader { bottle in
                            Color.clear.preference(
                                key: StarBottleFrameKey.self,
                                value: bottle.frame(in: .named(ContainerRevealSpace.name))
                            )
                        }
                    )
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func charmLayout(index: Int, count: Int, side: CGFloat) -> (size: CGFloat, position: CGPoint) {
        let bellyY = side * StarDropLayout.holeY(drop: drop, side: side)
        let belly = CGPoint(x: side * 0.50, y: bellyY)
        if count <= 1 {
            return (side * 0.44, belly)
        }
        let size = side * 0.30
        let offsets: [CGSize] = [
            CGSize(width: -side * 0.07, height: side * 0.015),
            CGSize(width: side * 0.08, height: -side * 0.01),
            CGSize(width: 0, height: -side * 0.07)
        ]
        let offset = offsets[index % offsets.count]
        return (size, CGPoint(x: belly.x + offset.width, y: belly.y + offset.height))
    }
}

struct StarBottleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

enum StarDropLayout {
    static func holeY(drop: CGFloat, side: CGFloat) -> CGFloat {
        let settled = side * 0.62
        let mouthY = side * 0.16
        let t = min(max((drop - 0.58) / 0.42, 0), 1)
        return drop < 0.999 ? mouthY + (settled - mouthY) * t : settled
    }

    static func neckScale(drop: CGFloat) -> CGSize {
        func bump(near value: CGFloat, at target: CGFloat, width: CGFloat) -> CGFloat {
            max(0, 1 - abs(value - target) / width)
        }
        var amount: CGFloat = 0
        if drop < 0.999 {
            amount = max(amount, bump(near: min(max(drop, 0), 1), at: 0.58, width: 0.16))
        }
        return CGSize(width: 1 - 0.16 * amount, height: 1 + 0.08 * amount)
    }
}

