import SwiftUI

/// 两台手机靠近时共用的那一束光。
///
/// 光不解释状态，光就是状态：瓶底亮起来是「对方在附近」，光从瓶底涨到瓶口是
/// 「正在相认」，涨满了就落下一颗星。整个相认过程没有需要读的字。
///
/// 位图负责瓶子的身份，这里只负责状态驱动的光。所有位置都按 `StarJar_Body`
/// 的实际画面取（透明通道外框：左右 0.2265…0.7873，上下 0.1699…0.9820），
/// 换图只改这一份标定。
enum ProximityLight {

    /// 一束光在画面里的标定，单位是「瓶子的画面边长」。
    enum Metrics {
        static let centerX: CGFloat = 0.5069
        /// 玻璃底部外沿。
        static let jarBottom: CGFloat = 0.9810
        /// 瓶内底：光从这里往上长。
        static let innerFloor: CGFloat = 0.9250
        /// 瓶肩：光涨到这里就到口了。
        static let innerNeck: CGFloat = 0.3050
        /// 口沿。
        static let mouthCenterY: CGFloat = 0.2080
        static let mouthWidth: CGFloat = 0.4300
        static let mouthHeight: CGFloat = 0.1020

        /// 光此刻涨到的高度（0…1 的画面比例，从顶往下）。
        static func lightTop(fill: Double) -> CGFloat {
            let t = min(max(fill, 0), 1)
            return innerFloor + (innerNeck - innerFloor) * CGFloat(t)
        }
    }

    /// 一束光的全部输入：距离是连续量，相认是 0…1 的累积量。
    struct Params: Equatable {
        /// 对方有多近，0…1（信号强度平滑后的接近程度）。
        var approach: Double = 0
        /// 已经近到可以相认。
        var isNear = false
        /// 相认进度 0…1：光从瓶底涨到瓶口。
        var fill: Double = 0
        /// 静止底光：空间建好了还在等人时，留一点光说明这里在等。
        var baseline: Double = 0
        /// 正在相认：口沿的转光亮起来。
        var isClaiming = false

        /// 真正画出来的亮度。够近之后不再跟着信号抖，直接给到明确的一档。
        var intensity: Double {
            let lifted = isNear ? max(0.84, approach) : approach * 0.70
            return min(1, max(baseline, lifted))
        }

        var isLit: Bool { intensity > 0.02 }
    }

    /// 光池与背后光晕：画在瓶子下面，像桌面上真的多了一盏灯。
    struct Backdrop: View {
        let params: Params
        /// 瓶子的画面边长，和同一屏里 `ContainerVisual` 的边长一致。
        let side: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isBreathing = false

        var body: some View {
            let intensity = params.intensity

            ZStack {
                // 背后光晕：整只瓶子被照亮的那一层。
                RadialGradient(
                    colors: [
                        AppTheme.warmLight.opacity(0.40 * intensity),
                        AppTheme.warmLight.opacity(0.14 * intensity),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * (0.30 + 0.20 * intensity)
                )
                .frame(width: side * 1.08, height: side * 1.08)
                .position(x: side * Metrics.centerX, y: side * 0.60)

                // 桌面光池：贴着瓶底落在桌上的那一圈，椭圆按桌面透视压扁。
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.92, blue: 0.76).opacity(0.86 * intensity),
                                AppTheme.warmLight.opacity(0.42 * intensity),
                                AppTheme.warmLight.opacity(0.10 * intensity),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * 0.46
                        )
                    )
                    .frame(width: side * (0.62 + 0.28 * intensity), height: side * 0.19)
                    .blur(radius: side * 0.012)
                    .position(x: side * Metrics.centerX, y: side * Metrics.jarBottom - side * 0.012)

                // 底光：不动的时候也有一个很小的亮核，说明这里在等。
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.84).opacity(0.92 * max(intensity, 0.55)),
                                AppTheme.warmLight.opacity(0.46 * intensity),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * 0.075
                        )
                    )
                    .frame(width: side * 0.15, height: side * 0.15)
                    .scaleEffect(isBreathing && !reduceMotion ? 1.10 : 0.94)
                    .opacity(params.baseline > 0 && !params.isNear ? max(0.5, intensity + 0.4) : 1)
                    .position(x: side * Metrics.centerX, y: side * Metrics.innerFloor - side * 0.018)
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .onAppear { isBreathing = true }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true),
                value: isBreathing
            )
        }
    }

    /// 透过玻璃的光：光从瓶底往上涨，涨到口沿时出现一圈转光。
    struct Glass: View {
        let params: Params
        let side: CGFloat

        /// 口沿转光的相位，只在相认时转起来。
        @State private var turn: Double = 0

        var body: some View {
            let intensity = params.intensity
            let lightTop = Metrics.lightTop(fill: params.fill)

            ZStack {
                // 整只瓶子透出来的暖光，越靠瓶底越亮。
                Image("StarJar_Body")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 1.0, green: 0.90, blue: 0.70).opacity(0.95), location: 0),
                                .init(color: AppTheme.warmLight.opacity(0.86), location: 0.34),
                                .init(color: AppTheme.warmLight.opacity(0.40), location: 0.72),
                                .init(color: AppTheme.warmLight.opacity(0.0), location: 1)
                            ],
                            startPoint: UnitPoint(x: 0.5, y: 0.985),
                            endPoint: UnitPoint(x: 0.5, y: lightTop)
                        )
                    )
                    .frame(width: side, height: side)
                    .blendMode(.plusLighter)
                    .opacity(0.30 + 0.70 * intensity)

                // 瓶里的亮核：光是从这里长出来的。
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.97, blue: 0.90).opacity(0.95),
                                Color(red: 1.0, green: 0.84, blue: 0.52).opacity(0.60),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * 0.11
                        )
                    )
                    .frame(width: side * 0.22, height: side * 0.22)
                    .blur(radius: side * 0.012)
                    .blendMode(.plusLighter)
                    .opacity(intensity)
                    .position(x: side * Metrics.centerX, y: side * (Metrics.innerFloor - 0.016))

                // 口沿：光涨上来时这一圈才亮，相认时慢慢转。
                Ellipse()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.84),
                                AppTheme.warmLight,
                                Color(red: 1.0, green: 0.99, blue: 0.94),
                                AppTheme.warmLight.opacity(0.55),
                                Color(red: 1.0, green: 0.95, blue: 0.84)
                            ],
                            center: .center
                        ),
                        lineWidth: max(1.6, side * 0.007)
                    )
                    .frame(width: side * Metrics.mouthWidth, height: side * Metrics.mouthHeight)
                    .rotationEffect(.degrees(turn))
                    .blur(radius: side * 0.004)
                    .blendMode(.plusLighter)
                    .opacity(mouthLight)
                    .position(x: side * Metrics.centerX, y: side * Metrics.mouthCenterY)
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .onAppear { updateTurn() }
            .onChange(of: params.isClaiming) { _, _ in updateTurn() }
        }

        /// 口沿的光只在相认快满的时候出现：光涨到口了，才有这一圈。
        private var mouthLight: Double {
            let ramped = (params.fill - 0.72) / 0.28
            return min(1, max(0, ramped)) * params.intensity
        }

        private func updateTurn() {
            guard params.isClaiming else {
                withAnimation(.easeOut(duration: 0.3)) { turn = 0 }
                return
            }
            turn = 0
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                turn = 360
            }
        }
    }

    /// 整个房间被照亮的程度：铺在背景之上、物件之下。
    struct Ambient: View {
        /// 0…1。
        let intensity: Double
        /// 光落在画面里的位置。默认在瓶子那一带，房间里则对准矮桌上的那几只。
        var center = UnitPoint(x: 0.5, y: 0.34)

        var body: some View {
            RadialGradient(
                colors: [
                    AppTheme.warmLight.opacity(0.20 * intensity),
                    AppTheme.warmLight.opacity(0.07 * intensity),
                    .clear
                ],
                center: center,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
