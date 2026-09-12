import SwiftUI
import MotionCore
import MotionSwiftUI

private struct InstrumentValue: MotionValue {
    var amount: Double
    var progress: Double
    var radius: Double
    var tint: Double
    var motionVector: MotionVector { MotionVector([amount,progress,radius,tint]) }
    init(amount: Double,progress: Double,radius: Double,tint: Double) {
        self.amount = amount; self.progress = progress; self.radius = radius; self.tint = tint
    }
    init(motionVector: MotionVector) {
        amount = motionVector[0]; progress = motionVector[1]; radius = motionVector[2]; tint = motionVector[3]
    }
}

@MainActor
struct DataMotionLab: View {
    @StateObject private var driver = MotionDriver(initial: InstrumentValue(amount: 20,progress: 0.2,radius: 8,tint: 0))
    @StateObject private var pendulum = MotionDriver(initial: 0.8)
    @State private var target = 80.0
    @State private var response = 0.65
    @State private var damping = 0.82
    @State private var angle = 0.8
    @State private var friction = 1.5
    @State private var error: String?
    @State private var order = [0,1,2,3]
    @Namespace private var tiles
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    private let cold = MotionRGBA(sRGBRed: 0.19,green: 0.38,blue: 0.3)
    private let warm = MotionRGBA(sRGBRed: 0.76,green: 0.44,blue: 0.2)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("动的是数据，不只是视图。").font(.largeTitle.bold())
                Text("同一份连续状态可以同时驱动数字、长度、形状和颜色。业务保存目标值，动画驱动器保存正在显示的值。")
                    .foregroundStyle(.secondary)
                StudioPanel(title: "自定义数据结构 → 四个视觉通道") {
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(.secondary.opacity(0.15),lineWidth: 8)
                            Circle().trim(from: 0,to: motionClamp(driver.value.progress))
                                .stroke(StudioStyle.green,style: StrokeStyle(lineWidth: 8,lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(driver.value.amount.formatted(.number.precision(.fractionLength(0))))
                                .font(.system(size: 35,weight: .medium,design: .rounded)).monospacedDigit()
                        }.frame(width: 110,height: 110)
                        let color = MotionRGBA(motionVector: .lerp(cold.motionVector,warm.motionVector,driver.value.tint)).color
                        RoundedRectangle(cornerRadius: max(0,driver.value.radius))
                            .fill(color).frame(width: 110,height: 110)
                    }.frame(maxWidth: .infinity).padding(.vertical,12)
                    ParameterSlider(title: "新的业务目标",value: $target,range: 0...100,unit: "%")
                    HStack {
                        Button("更新到 15") { target = 15 }
                        Button("更新到 85") { target = 85 }
                        Button("更新到 45") { target = 45 }
                    }.buttonStyle(.bordered)
                    ParameterSlider(title: "响应",value: $response,range: 0.2...1.2,unit: "s")
                    ParameterSlider(title: "阻尼比",value: $damping,range: 0.35...1.3)
                    Text("数字只在显示时取整；内部始终保存小数。进度和颜色在显示时限制合法范围，原始弹簧仍可能越界。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CodePanel(code: """
                struct InstrumentValue: MotionValue {
                    var amount: Double
                    var progress: Double
                    var radius: Double
                    var tint: Double
                    var motionVector: MotionVector {
                        MotionVector([amount, progress, radius, tint])
                    }
                    init(motionVector v: MotionVector) {
                        amount = v[0]; progress = v[1]
                        radius = v[2]; tint = v[3]
                    }
                }
                // 数据更新时：
                driver.animate(
                    to: nextValue,
                    model: .spring(.init(response: 0.65, dampingRatio: 0.82))
                )
                // View 读取 driver.value；不要在业务值上每帧写回动画中间值。
                """)
                StudioPanel(title: "其他数学模型：非线性摆动") {
                    GeometryReader { geometry in
                        let pivot = CGPoint(x: geometry.size.width/2,y: 20)
                        let end = CGPoint(x: pivot.x+sin(pendulum.value)*120,y: pivot.y+cos(pendulum.value)*120)
                        Path { p in p.move(to: pivot); p.addLine(to: end) }.stroke(.secondary,lineWidth: 2)
                        Circle().fill(StudioStyle.green).frame(width: 34,height: 34).position(end)
                        Circle().fill(.secondary).frame(width: 7,height: 7).position(pivot)
                    }.frame(height: 180)
                    ParameterSlider(title: "释放角度",value: $angle,range: -1.5...1.5,unit: "rad")
                    ParameterSlider(title: "角速度阻尼",value: $friction,range: 0.2...4,unit: "1/s")
                    Button("释放摆锤") {
                        do {
                            let motion = try DifferentialSystem.pendulum(damping: friction)
                                .trajectory(initial: angle,velocity: MotionVector([0]),duration: 10)
                            pendulum.play(motion)
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("θ″ = −(g/L) sin θ − cθ′。这不是把位置套进 ease 曲线，而是在求解状态随时间的变化。采用 RK4 积分，10 秒为观察窗口，不保证届时已达到物理平衡。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                CodePanel(code: """
                // 可以替换为自己的加速度函数。
                let system = DifferentialSystem { time, position, velocity in
                    MotionVector([-14 * sin(position[0]) - 1.5 * velocity[0]])
                }
                let trajectory = try system.trajectory(
                    initial: 0.8, velocity: MotionVector([0]),
                    duration: 10, step: 1.0 / 240
                )
                driver.play(trajectory)
                // 更复杂的系统应选择合适的积分方法，RK4 不保证任何方程都稳定。
                """)
                StudioPanel(title: "不能直接插值的数据：集合与身份") {
                    HStack {
                        ForEach(order,id: \.self) { id in
                            Text("\(id+1)").font(.title3.monospacedDigit()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(StudioStyle.green,in: RoundedRectangle(cornerRadius: 12))
                                .matchedGeometryEffect(id: id,in: tiles)
                        }
                    }
                    Button("改变顺序") {
                        withAnimation(reduced ? nil : .spring(response: 0.5,dampingFraction: 0.9)) {
                            order.append(order.removeFirst())
                        }
                    }.buttonStyle(.bordered)
                    Text("数组顺序、文字和 Bool 不是连续数轴。保留稳定身份，让布局、透明度或进度成为中间表示；不要把字符编码或数组索引直接插值。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onChange(of: target) { _,value in
            let next = InstrumentValue(amount: value,progress: value/100,radius: 4+value*0.45,tint: value/100)
            driver.animate(to: next,model: .spring(.init(response: response,dampingRatio: damping)))
        }
        .onAppear { driver.reduceMotion = reduced; pendulum.reduceMotion = reduced }
        .onChange(of: reduced) { _,value in driver.reduceMotion = value; pendulum.reduceMotion = value }
        .onChange(of: phase) { _,value in if value != .active { driver.pause(); pendulum.pause() } }
        .onDisappear { driver.detach(); pendulum.detach() }
    }
}
