import SwiftUI

/// 连接页的光。
///
/// 这一屏没有物件、没有房间：只有两个人的光，和它们之间的那片场。
/// 光不解释状态，光就是状态——靠近时它变厚、变慢、变深，方向可信时整片场偏向对方那一侧，
/// 方向不可信时就均匀地亮着。方向只改形状，总量从始至终只由距离决定。
enum ConnectionLight {

    struct Params: Equatable {
        /// 对方有多近，0…1。
        var closeness: Double = 0
        /// 已经在连接里（融合之后）：光核更大、更稳。
        var isUnited = false
        /// 屏幕坐标系下的偏心方向（单位向量乘上权重）。方向不可信时为零。
        var bias: CGVector = .zero
        /// 总强度 0…1。
        var intensity: Double = 0.40
        /// 光核的相对大小。
        var coreScale: Double = 1

        /// 静下来时同一屏上自己的那点光。没有对方、也没有方向。
        static let resting = Params()
    }

    // MARK: - 光场

    /// 满屏的光场。逐帧重画，只在页面可见时运行。
    ///
    /// 三层叠在一起：雾（整片柔光）、核（光的中心）、尘（被光照亮的微粒）。
    /// 全部加色叠加，所以重叠的地方真的更亮，像光而不是贴图。
    struct Field: View {
        let params: Params
        var isRunning = true
        /// 减少动态时停在某一帧，不表演。
        var frozenAt: TimeInterval = 3.7

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { proxy in
                let running = isRunning && !reduceMotion

                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { timeline in
                    let time = running ? timeline.date.timeIntervalSinceReferenceDate : frozenAt

                    Canvas { context, size in
                        render(context: &context, size: size, time: time)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        // MARK: 画

        private func render(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
            let unit = min(size.width, size.height)
            guard unit > 1 else { return }

            let intensity = min(max(params.intensity, 0), 1)
            guard intensity > 0.004 else { return }

            let closeness = min(max(params.closeness, 0), 1)
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.47)

            let bias = params.isUnited ? .zero : params.bias
            let weight = min((bias.dx * bias.dx + bias.dy * bias.dy).squareRoot(), 1)
            let direction = weight > 0.001
                ? CGVector(dx: bias.dx / weight, dy: bias.dy / weight)
                : CGVector(dx: 0, dy: 0)
            let directionPoint = CGPoint(x: direction.dx, y: direction.dy)

            // 靠近是放松不是激动：越近呼吸越慢、越深。
            let period = 3.1 + 2.5 * closeness
            let breath = sin(time * 2 * .pi / period)
            let hum = isRunning ? 0.6 + 0.4 * closeness : 0
            let pulse = 1 + (0.020 + 0.075 * closeness) * breath + hum * 0.016 * sin(time * 6.7)

            context.blendMode = .plusLighter

            // 雾：整片柔光。方向只让它偏心，总量不变——偏出去的那一份从另一边收回来。
            let halo = unit * 0.72
            let shift = unit * 0.11 * weight
            let base = 0.20 * intensity
            fillGlow(
                &context,
                center: center,
                radius: halo,
                alpha: base * (1 + 0.9 * weight)
            )
            if weight > 0.001 {
                fillGlow(
                    &context,
                    center: CGPoint(
                        x: center.x + directionPoint.x * shift,
                        y: center.y + directionPoint.y * shift
                    ),
                    radius: halo * 0.96,
                    alpha: base * 0.55 * weight
                )
                fillGlow(
                    &context,
                    center: CGPoint(
                        x: center.x - directionPoint.x * shift,
                        y: center.y - directionPoint.y * shift
                    ),
                    radius: halo * 0.92,
                    alpha: base * 0.55 * weight
                )
            }

            // 核：光的中心本身就带呼吸。
            let coreRadius = unit * max(0.030, 0.105 * params.coreScale * pulse)
            fillGlow(
                &context,
                center: center,
                radius: coreRadius,
                alpha: min(1, (0.92 + 0.30 * closeness) * intensity),
                inner: true
            )

            drawDust(
                context: &context,
                unit: unit,
                center: center,
                time: time,
                closeness: closeness,
                intensity: intensity,
                weight: weight,
                direction: direction
            )

            context.blendMode = .normal
        }

        /// 一团暖光。`inner` 亮核更集中，用来画光的中心。
        private func fillGlow(
            _ context: inout GraphicsContext,
            center: CGPoint,
            radius: CGFloat,
            alpha: Double,
            inner: Bool = false
        ) {
            guard alpha > 0.002, radius > 0.5 else { return }
            let color = inner
                ? Color(red: 1.0, green: 0.96, blue: 0.88)
                : Color(red: 1.0, green: 0.87, blue: 0.63)
            let stops: [Gradient.Stop] = inner
                ? [
                    .init(color: color.opacity(alpha), location: 0),
                    .init(color: color.opacity(alpha * 0.55), location: 0.34),
                    .init(color: color.opacity(alpha * 0.14), location: 0.70),
                    .init(color: color.opacity(0), location: 1)
                ]
                : [
                    .init(color: color.opacity(alpha), location: 0),
                    .init(color: color.opacity(alpha * 0.44), location: 0.38),
                    .init(color: color.opacity(alpha * 0.13), location: 0.72),
                    .init(color: color.opacity(0), location: 1)
                ]

            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(stops: stops),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }

        /// 光尘：被光照亮的微粒，沿流场慢慢游动。
        /// 方向可信时它们的闪动沿着对方那一侧走，不可信时只是各自漂着。
        private func drawDust(
            context: inout GraphicsContext,
            unit: CGFloat,
            center: CGPoint,
            time: TimeInterval,
            closeness: Double,
            intensity: Double,
            weight: Double,
            direction: CGVector
        ) {
            let tint = Color(red: 1.0, green: 0.94, blue: 0.84)
            let spread = 0.30 + 0.45 * closeness
            let influence = 0.85 * weight

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.011))
                layer.blendMode = .plusLighter

                for mote in Self.cloud {
                    let drift = 0.030 * sin(time * 0.33 + mote.phase)
                    let rise = 0.030 * cos(time * 0.29 + mote.phase * 1.7)
                    let projection = mote.x * direction.dx + mote.y * direction.dy
                    let wave = 0.026 * weight * sin(time * 0.5 + mote.phase + projection * 3.4)

                    let x = mote.x + drift + direction.dx * wave
                    let y = mote.y + rise + direction.dy * wave

                    let distance = (x * x + y * y).squareRoot()
                    let falloff = exp(-distance * 0.95)
                    guard falloff > 0.04 else { continue }

                    let alignment = distance > 0.0001
                        ? (x * direction.dx + y * direction.dy) / distance
                        : 1
                    let directional = 1 + influence * alignment
                    let alpha = mote.brightness * falloff * directional * spread * intensity * 0.52
                    guard alpha > 0.003 else { continue }

                    let radius = unit * mote.size
                    let point = CGPoint(
                        x: center.x + CGFloat(x) * unit,
                        y: center.y + CGFloat(y) * unit
                    )
                    layer.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - radius,
                            y: point.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(tint.opacity(min(alpha, 0.85)))
                    )
                }
            }
        }

        // MARK: 尘的位置

        private struct Mote {
            let x: Double
            let y: Double
            let phase: Double
            let size: Double
            let brightness: Double
        }

        /// 固定的一层尘：位置一次算好，每帧只让它们各自漂一点。
        private static let cloud: [Mote] = {
            var random = SplitMix(seed: 0x5EED_1234_ABCD)
            return (0..<150).map { _ in
                Mote(
                    x: random.unit(-0.70, 0.70),
                    y: random.unit(-1.12, 1.12),
                    phase: random.unit(0, 2 * .pi),
                    size: random.unit(0.0024, 0.0062),
                    brightness: random.unit(0.34, 1.0)
                )
            }
        }()
    }

    // MARK: - 对方的光到来

    /// 融合的第一步：另一团光从画面外围收进来，落到自己的光上。
    ///
    /// 方向可信时它从对方那一侧来；不可信时从四面八方一起收——不假装知道方位。
    struct Arrival: View {
        /// 0…1。
        let progress: Double
        /// 屏幕坐标系下的偏心方向（单位向量乘权重）。
        let bias: CGVector

        var body: some View {
            GeometryReader { proxy in
                let unit = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.47)
                let spread = 1.18 - 0.88 * eased
                let towardEdge = (1 - eased) * Double(unit) * 0.55

                light(unit: unit)
                    .frame(width: unit * 2.8, height: unit * 2.8)
                    .scaleEffect(spread)
                    .position(
                        x: center.x + bias.dx * towardEdge,
                        y: center.y + bias.dy * towardEdge
                    )
                    .opacity(arrivalOpacity)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private var eased: Double {
            let t = min(max(progress, 0), 1)
            return 1 - pow(1 - t, 3)
        }

        private var arrivalOpacity: Double {
            let t = min(max(progress, 0), 1)
            return min(1, t * 2.6) * (0.55 + 0.45 * t)
        }

        private func light(unit: CGFloat) -> some View {
            RadialGradient(
                stops: [
                    .init(color: Color(red: 1.0, green: 0.97, blue: 0.91).opacity(0.92), location: 0),
                    .init(color: AppTheme.warmLight.opacity(0.60), location: 0.22),
                    .init(color: AppTheme.warmLight.opacity(0.22), location: 0.52),
                    .init(color: AppTheme.warmLight.opacity(0.06), location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: unit * 0.52
            )
        }
    }

    /// 两团光碰到一起的那一下：一圈很快散开的光，然后安静下来。
    struct Flare: View {
        /// 0…1，0.35 之后基本看不见了。
        let progress: Double

        var body: some View {
            GeometryReader { proxy in
                let unit = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.47)
                let t = min(max(progress, 0), 1)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: Color(red: 1.0, green: 0.98, blue: 0.94).opacity(0.95), location: 0),
                                    .init(color: AppTheme.warmLight.opacity(0.42), location: 0.42),
                                    .init(color: .clear, location: 1)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: unit * (0.16 + 0.30 * t)
                            )
                        )
                        .frame(width: unit * 1.2, height: unit * 1.2)
                        .opacity(1 - t)

                    Circle()
                        .stroke(
                            Color(red: 1.0, green: 0.96, blue: 0.86).opacity(0.55 * (1 - t)),
                            lineWidth: unit * 0.006
                        )
                        .frame(width: unit * (0.22 + 0.72 * t), height: unit * (0.22 + 0.72 * t))
                        .blur(radius: unit * 0.01)
                }
                .blendMode(.plusLighter)
                .position(center)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - 收尾

    /// 进入空间之前，整片光短暂地涨满一次。这是这一页最后一件事。
    struct Bloom: View {
        /// 0…1。
        let progress: Double

        var body: some View {
            RadialGradient(
                stops: [
                    .init(color: Color(red: 1.0, green: 0.97, blue: 0.90).opacity(0.94), location: 0),
                    .init(color: AppTheme.warmLight.opacity(0.52), location: 0.45),
                    .init(color: AppTheme.warmLight.opacity(0.10), location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 620
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .opacity(pow(min(max(progress, 0), 1), 0.7))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 固定种子的小随机：同一层尘每次打开都一样，不会每次都是新的星图。
private struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value >> 11) / Double(1 << 53)
    }

    mutating func unit(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * next()
    }
}
