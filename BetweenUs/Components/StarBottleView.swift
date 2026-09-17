import SwiftUI

struct StarCharm: Hashable, Identifiable {
    let imageName: String

    var id: String { imageName }

    private static let styles = ["Candy", "Silver", "Handmade", "Iridescent", "Gift"]
    private static let moods = ["Joy", "Love", "Missing", "Thanks", "Comfort", "Hope"]

    static let all: [StarCharm] = styles.flatMap { style in
        moods.map { emotion in
            StarCharm(imageName: "StarCharm_\(style)_\(emotion)")
        }
    }

    static func displayCharms(count: Int) -> [StarCharm] {
        (0..<min(max(count, 0), 10)).map { index in
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

struct StarBottleView: View {
    let count: Int

    private let slots: [CGPoint] = [
        CGPoint(x: 0.36, y: 0.80), CGPoint(x: 0.50, y: 0.81), CGPoint(x: 0.64, y: 0.80),
        CGPoint(x: 0.36, y: 0.67), CGPoint(x: 0.50, y: 0.68), CGPoint(x: 0.64, y: 0.67),
        CGPoint(x: 0.36, y: 0.54), CGPoint(x: 0.50, y: 0.55), CGPoint(x: 0.64, y: 0.54),
        CGPoint(x: 0.50, y: 0.41)
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let charms = StarCharm.displayCharms(count: count)

            ZStack {
                Image("StarJar_Body")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()

                ForEach(Array(charms.enumerated()), id: \.element.id) { index, charm in
                    StarCharmImage(charm: charm)
                        .frame(width: side * 0.12, height: side * 0.12)
                        .rotationEffect(.degrees(Double((index * 17) % 45 - 22)))
                        .position(x: side * slots[index].x, y: side * slots[index].y)
                }
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
