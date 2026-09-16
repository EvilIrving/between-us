import SwiftUI

struct StarCharm: Hashable, Identifiable {
    let imageName: String
    let series: Int
    let mood: Int

    var id: String { imageName }

    // Stable ordering preserves the identity of stars in existing saved placements.
    private static let styles = ["Candy", "Silver", "Handmade", "Iridescent", "Gift"]
    private static let moods = ["Joy", "Love", "Missing", "Thanks", "Comfort", "Hope"]

    var legacyImageName: String { "StarCharm_\(series)_\(mood)" }

    static let all: [StarCharm] = {
        styles.enumerated().flatMap { series, style in
            moods.enumerated().map { mood, emotion in
                StarCharm(imageName: "StarCharm_\(style)_\(emotion)", series: series + 1, mood: mood + 1)
            }
        }
    }()

    static func random() -> StarCharm {
        all.randomElement() ?? StarCharm(imageName: "StarCharm_Candy_Joy", series: 1, mood: 1)
    }

    static func displayCharms(count: Int) -> [StarCharm] {
        let n = min(max(count, 0), StarJarMetrics.maxStars)
        guard n > 0 else { return [] }
        return (0..<n).map { index in
            all[(index * 11 + 3) % all.count]
        }
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

/// Shared layered renderer for every star bottle surface.
/// In-bottle stars stay behind the bottle PNG; exiting flight is composited by the reveal overlay.
struct StarBottleView: View {
    @ObservedObject var physics: StarJarPhysicsSystem
    var count: Int
    var reportsRevealAnchors = false
    var animateCountChanges = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            let bottleFrame = CGRect(origin: origin, size: CGSize(width: side, height: side))

            ZStack(alignment: .topLeading) {
                ForEach(physics.stars) { star in
                    StarCharmImage(charm: star.charm)
                        .frame(width: star.visualSize, height: star.visualSize)
                        .rotationEffect(.radians(star.rotation))
                        .position(
                            x: origin.x + star.position.x,
                            y: origin.y + star.position.y
                        )
                        .background {
                            if reportsRevealAnchors, star.id == physics.topmostStar()?.id {
                                RevealAnchorProbe(kind: .star, id: .content)
                            }
                        }
                }

                Image("StarJar_Body")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .position(x: bottleFrame.midX, y: bottleFrame.midY)
                    .background {
                        if reportsRevealAnchors {
                            RevealAnchorProbe(kind: .star, id: .container)
                        }
                    }
                    .overlay {
                        if reportsRevealAnchors {
                            RevealAnchorProbe(kind: .star, id: .exit)
                                .frame(width: 2, height: 2)
                                .position(
                                    x: side * StarJarMetrics.mouthCenter.x,
                                    y: side * StarJarMetrics.mouthCenter.y
                                )
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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                physics.configure(side: side)
                physics.setStarCount(count, animated: false)
            }
            .onChange(of: side) { newSide in
                physics.configure(side: newSide)
                physics.setStarCount(count, animated: false)
            }
            .onChange(of: count) { newCount in
                physics.setStarCount(newCount, animated: animateCountChanges)
            }
        }
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
