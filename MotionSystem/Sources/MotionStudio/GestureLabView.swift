import SwiftUI
import QuartzCore
import MotionCore
import MotionSwiftUI

@MainActor
struct GestureLabView: View {
    @StateObject private var driver = MotionDriver(initial: 0.0)
    @State private var response = 0.5
    @State private var damping = 0.88
    @State private var resistance = 70.0
    @State private var decayRate = 5.0
    @State private var mode = "snap"
    @State private var dragOrigin: Double?
    @State private var tracker = VelocityTracker()
    @State private var lastTarget = 0.0
    @State private var event = "等待按下"
    @GestureState private var contact = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    private let travel = 220.0
    private var spring: MotionModel { .spring(.init(response: response,dampingRatio: damping)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("让手指与运动交接。").font(.largeTitle.bold())
                Text("按住正在回弹的物件，再往别处拖。模型值就是屏幕显示值，不需要猜测它此刻在哪里。")
                    .foregroundStyle(.secondary)
                StudioPanel(title: "横向拖动") {
                    GeometryReader { geometry in
                        let scale = min(1,geometry.size.width/320)
                        ZStack(alignment: .topLeading) {
                            ForEach([0.0,110,220],id: \.self) { x in
                                Circle().stroke(.secondary.opacity(0.4),style: StrokeStyle(lineWidth: 1,dash: [3,4]))
                                    .frame(width: 52,height: 52).position(x: 50+x,y: 90)
                            }
                            RoundedRectangle(cornerRadius: 18).fill(StudioStyle.green)
                                .frame(width: 52,height: 52).position(x: 50+driver.value,y: 90)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .updating($contact) { _,state,_ in state = true }
                                    .onChanged { value in
                                        if dragOrigin == nil {
                                            driver.beginDragging(); tracker.reset()
                                            dragOrigin = RubberBand(limit: resistance).rawPosition(driver.value,bounds: 0...travel)
                                            tracker.append(driver.value.motionVector,at: CACurrentMediaTime())
                                            event = "跟随：直接更新，无额外动画"
                                        }
                                        let raw = (dragOrigin ?? 0)+value.translation.width/scale
                                        let displayed = RubberBand(limit: resistance).map(raw,bounds: 0...travel)
                                        tracker.append(displayed.motionVector,at: CACurrentMediaTime())
                                        driver.updateDragging(value: displayed,velocity: tracker.velocity(at: CACurrentMediaTime(),dimensions: 1))
                                    }
                                    .onEnded { _ in release(cancelled: false) })
                                .accessibilityLabel("可拖动物件")
                                .accessibilityValue("位置 \(driver.value,specifier: "%.0f") 点")
                                .accessibilityAction(named: Text("移到中间")) { settle(110) }
                                .accessibilityAction(named: Text("返回起点")) { settle(0) }
                        }.frame(width: 320,height: 180).scaleEffect(scale,anchor: .topLeading)
                    }.frame(height: 180).clipped()
                    Text(event).font(.caption).foregroundStyle(.secondary)
                    Text("位置 \(driver.value,specifier: "%.1f") pt · 速度 \(driver.velocity[0],specifier: "%.1f") pt/s")
                        .font(.caption.monospacedDigit())
                    HStack {
                        Button("起点") { settle(0) }; Button("中间") { settle(110) }; Button("终点") { settle(220) }
                    }.buttonStyle(.bordered)
                    Picker("松手后",selection: $mode) {
                        Text("预测并吸附").tag("snap")
                        Text("惯性滑行").tag("decay")
                        Text("返回起点").tag("return")
                    }.pickerStyle(.segmented)
                    Text("惯性模式没有碰撞，可能离开舞台；边界吸附模式会选择合法目标。它们是不同的设计选择。").font(.caption).foregroundStyle(.secondary)
                }
                StudioPanel(title: "手感参数") {
                    ParameterSlider(title: "响应",value: $response,range: 0.15...1.2,unit: "s")
                    ParameterSlider(title: "阻尼比",value: $damping,range: 0.25...1.4)
                    ParameterSlider(title: "越界极限",value: $resistance,range: 20...140,unit: "pt",hint: "越大，边界越松；边界以内仍然一比一跟随。")
                    ParameterSlider(title: "衰减率",value: $decayRate,range: 2...12,unit: "1/s",hint: "越大，预测停点越近。参数不以每帧为单位。")
                }
                StudioPanel(title: "手势不是一条预设动画") {
                    Text("按下 → 抓住显示值；拖动 → 更新位置、记录速度；越界 → 映射阻力；释放 → 预测目标、接住速度；取消 → 回到最近的合法状态。")
                    Text("预测位移与初速度是两回事。这里从显示位置采样速度，因此越界阻力降低了显示速度时，释放阶段不会突然继承过大的手指速度。")
                }
                CodePanel(code: """
                // 释放时，driver.value 就是当前显示值。
                let snap = SnapConfiguration(
                    points: [0, 110, 220],
                    projection: .init(rate: \(decayRate))
                )
                let destination = snap.target(
                    position: driver.value,
                    velocity: driver.velocity[0]
                )
                driver.animate(
                    to: destination,
                    model: .spring(.init(response: \(response), dampingRatio: \(damping))),
                    interruption: .preserveVelocity
                )
                """)
            }.padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onAppear { driver.reduceMotion = reduced }
        .onChange(of: reduced) { _,value in driver.reduceMotion = value }
        .onChange(of: contact) { _,active in
            if !active && dragOrigin != nil { release(cancelled: true) }
        }
        .onChange(of: phase) { _,value in
            if value != .active { dragOrigin = nil; driver.pause() }
        }
        .onDisappear { dragOrigin = nil; driver.detach() }
    }
    private func settle(_ value: Double) {
        lastTarget = value
        driver.animate(to: value,model: spring)
        event = "吸附目标：\(Int(value)) pt"
    }
    private func release(cancelled: Bool) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        let velocity = cancelled ? MotionVector([0]) : tracker.velocity(at: CACurrentMediaTime(),dimensions: 1)
        driver.updateDragging(value: driver.value,velocity: velocity)
        if mode == "decay" && !cancelled {
            driver.animate(to: driver.value,model: .decay(.init(rate: decayRate)))
            event = "惯性衰减：终点由释放速度决定"
        } else {
            let target = mode == "return" ? 0 : SnapConfiguration(points: [0,110,220],projection: .init(rate: decayRate))
                .target(position: driver.value,velocity: velocity[0])
            settle(target)
            if cancelled { event = "手势取消：回到合法吸附点" }
        }
    }
}
