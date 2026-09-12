import SwiftUI
import MotionCore
import MotionSwiftUI

// 将本文件中需要的 View 加入宿主 target。
// MotionSystem/ExampleApp 已有独立工作台入口，这里展示真实项目如何按需使用库。

@MainActor
struct NumericMotionExample: View {
    // 业务数据保存最终目标，driver 保存视觉中间值。
    let amount: Double
    @StateObject private var driver = MotionDriver(initial: 0.0)
    var body: some View {
        AnimatedMotionValue(driver: driver) { value in
            Text(value.formatted(.number.precision(.fractionLength(0))))
                .font(.largeTitle.monospacedDigit())
        }
        .onChange(of: amount,initial: true) { _,target in
            driver.animate(to: target,model: .spring(.init(response: 0.5,dampingRatio: 0.95)))
        }
    }
}

@MainActor
struct PathMotionExample: View {
    @StateObject private var driver = MotionDriver(initial: MotionPoint(40,220))
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack {
            GeometryReader { geometry in
                Circle().fill(.green).frame(width: 44,height: 44)
                    .position(driver.value.cgPoint)
                    .frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .topLeading)
                    .overlay(alignment: .bottom) {
                        Button("经过入口后打开") {
                            let width = geometry.size.width
                            let start = driver.value
                            let entry = MotionPoint(Double(width)*0.5,120)
                            let end = MotionPoint(Double(width)-45,70)
                            let path = MotionCookbook.throughWaypoint(
                                start: start,entry: entry,end: end,
                                startHandle: MotionPoint(start.x,160),
                                entryIncoming: entry+MotionPoint(-35,0),
                                entryOutgoing: entry+MotionPoint(35,0),
                                endHandle: end+MotionPoint(-30,30)
                            )
                            driver.play(path)
                        }
                    }
            }.frame(height: 280)
        }
        .onAppear { driver.reduceMotion = reduced }
        .onChange(of: reduced) { _,enabled in driver.reduceMotion = enabled }
        .onChange(of: phase) { _,value in if value != .active { driver.pause() } }
        .onDisappear { driver.detach() }
    }
}

@MainActor
struct RecipeEventExample: View {
    @StateObject private var session = MotionSession(recipe: MotionRecipes.stagedReveal)
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack {
            // session 拥有语义；driver 拥有显示值。
            AnimatedMotionValue(driver: session.driver) { pose in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Rectangle().fill(.green).motionPose(pose)
                }.frame(width: 340,height: 280)
            }
            HStack {
                Button("打开") { session.send(.play) }
                Button("取消") { session.send(.cancel) }
            }
        }
        .onAppear { session.send(.reduceMotion(reduced)) }
        .onChange(of: reduced) { _,enabled in session.send(.reduceMotion(enabled)) }
        .onChange(of: phase) { _,value in if value != .active { session.send(.pause) } }
        .onDisappear { session.send(.leaveScene) }
    }
}

// 自定义类型只要明确连续表示即可加入系统；不需要改驱动器。
struct MeterState: MotionValue {
    var level: Double
    var angle: Double
    var glow: Double
    init(level: Double,angle: Double,glow: Double) {
        self.level = level; self.angle = angle; self.glow = glow
    }
    var motionVector: MotionVector { MotionVector([level,angle,glow]) }
    init(motionVector value: MotionVector) {
        level = value[0]; angle = value[1]; glow = value[2]
    }
}

// 接入提醒：
// - 在已有耳语工程中，先评估 AppMotion / DriverSpring 与现有 Wave 驱动的边界。
// - 不同时让两个驱动器写同一个属性；这份系统是独立库，不会自动接管现有物件。
// - 340×280 是教学舞台；真实产品应使用项目自己的布局基线与物件锚点。
// - 渲染依赖的目标状态、点击可用性、业务提交和数据同步仍由宿主负责。
