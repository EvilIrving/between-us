import SwiftUI
import UIKit

// 独立学习入口，最低 iOS 17。将此文件加入一个 SwiftUI iOS target，
// 在现有 WindowGroup 中显示 MotionGallery()；不要新增第二个 @main。
// 网页中的值是教学起点。这里用原生动画展示真实的布局、手势和衔接。
struct MotionGallery: View {
    var body: some View {
        NavigationStack {
            List {
                Section("从一个动作开始") {
                    NavigationLink("位置与时间曲线") { MGPositionLab(spring: false, combined: false) }
                    NavigationLink("弹簧：响应与阻尼") { MGPositionLab(spring: true, combined: false) }
                    NavigationLink("沿弧线移动") { MGArcLab() }
                    NavigationLink("移动、缩放与旋转") { MGPositionLab(spring: true, combined: true) }
                }
                Section("让操作连续") {
                    NavigationLink("跟手、越界与吸附") { MGDragLab() }
                    NavigationLink("先到达，再揭示") { MGSequenceLab() }
                    NavigationLink("跨布局展开") { MGMatchedLab() }
                    NavigationLink("中途改变目标") { MGInterruptLab() }
                }
            }
            .navigationTitle("动效指南")
            .tint(MGStyle.green)
        }
    }
}

private enum MGStyle {
    static let green = Color(red: 0.19, green: 0.36, blue: 0.29)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.92)
    static let uiGreen = UIColor(red: 0.19, green: 0.36, blue: 0.29, alpha: 1)
}

private struct MGObject: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(MGStyle.green)
            .overlay {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

private struct MGSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value) + suffix)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
        }
        .font(.subheadline)
    }
}

private struct MGPositionLab: View {
    let spring: Bool
    let combined: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false
    @State private var response = 0.55
    @State private var damping = 0.85
    @State private var duration = 0.65
    @State private var scale = 1.7
    @State private var rotation = 20.0
    @State private var curve = 0

    private var animation: Animation {
        if spring { return .spring(response: response, dampingFraction: damping) }
        switch curve {
        case 1: return .timingCurve(0, 0, 0.58, 1, duration: duration)
        case 2: return .linear(duration: duration)
        default: return .timingCurve(0.42, 0, 0.58, 1, duration: duration)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GeometryReader { geometry in
                    let a = CGPoint(x: 52, y: 205)
                    let b = CGPoint(x: geometry.size.width - 65, y: 85)
                    ZStack(alignment: .topLeading) {
                        MGStyle.paper
                        Path { path in path.move(to: a); path.addLine(to: b) }
                            .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        Circle().stroke(.secondary.opacity(0.4)).frame(width: 56, height: 56).position(a)
                        Circle().stroke(.secondary.opacity(0.4)).frame(width: 56, height: 56).position(b)
                        MGObject().frame(width: 52, height: 52)
                            .scaleEffect(combined && moved ? scale : 1)
                            .rotationEffect(.degrees(combined && moved ? rotation : 0))
                            .position(moved ? b : a)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(height: 280)
                HStack {
                    Button(moved ? "返回 A" : "移动到 B") {
                        withAnimation(reduceMotion ? nil : animation) { moved.toggle() }
                    }.buttonStyle(.borderedProminent)
                    Button("复位") {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { moved = false }
                    }.buttonStyle(.bordered)
                }
                if spring {
                    MGSlider(title: "响应 response", value: $response, range: 0.15...1.2, suffix: " s")
                    MGSlider(title: "阻尼比", value: $damping, range: 0.25...1.3)
                } else {
                    MGSlider(title: "时长", value: $duration, range: 0.15...1.8, suffix: " s")
                    Picker("时间曲线", selection: $curve) {
                        Text("慢—快—慢").tag(0)
                        Text("快启动").tag(1)
                        Text("匀速").tag(2)
                    }.pickerStyle(.segmented)
                }
                if combined {
                    MGSlider(title: "终点缩放", value: $scale, range: 0.6...2.3, suffix: "×")
                    MGSlider(title: "终点旋转", value: $rotation, range: -90...90, suffix: "°")
                }
                Text("播放途中可以反向。先调节奏，再调回弹，最后才加其他属性。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(combined ? "组合动作" : spring ? "弹簧" : "位置")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MGStyle.green)
    }
}

// 只有 progress 参与插值。每一帧再从 progress 求空间坐标。
private struct MGArcPosition: AnimatableModifier {
    var progress: CGFloat
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let t = progress, u = 1 - t
        content.position(
            x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
            y: u*u*start.y + 2*u*t*control.y + t*t*end.y
        )
    }
}

private struct MGArcLab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false
    @State private var lift = 110.0
    @State private var duration = 0.85
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GeometryReader { geometry in
                    let start = CGPoint(x: 45, y: 210)
                    let end = CGPoint(x: geometry.size.width - 45, y: 155)
                    let control = CGPoint(x: geometry.size.width / 2, y: 182.5 - lift)
                    ZStack(alignment: .topLeading) {
                        MGStyle.paper
                        Path { p in
                            p.move(to: start)
                            p.addQuadCurve(to: end, control: control)
                        }.stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        Circle().fill(.orange).frame(width: 7, height: 7).position(control)
                        MGObject().frame(width: 52, height: 52)
                            .modifier(MGArcPosition(progress: moved ? 1 : 0,
                                                    start: start, control: control, end: end))
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                }.frame(height: 280)
                Button(moved ? "沿原路返回" : "沿弧线移动") {
                    withAnimation(reduceMotion ? nil : .timingCurve(0.42, 0, 0.58, 1, duration: duration)) {
                        moved.toggle()
                    }
                }.buttonStyle(.borderedProminent)
                MGSlider(title: "控制点抬高", value: $lift, range: 0...170, suffix: " pt")
                MGSlider(title: "时长", value: $duration, range: 0.2...1.8, suffix: " s")
                Text("橙点是控制点，不是必经点。改变路线后复位观察；时间曲线不改变路线形状。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("弧线路径").navigationBarTitleDisplayMode(.inline).tint(MGStyle.green)
    }
}

private struct MGSequenceLab: View {
    private struct Values {
        var progress: CGFloat = 0
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0
    @State private var generation = 0
    @State private var duration = 0.65
    @State private var pause = 0.18
    @State private var running = false
    @State private var finished = false
    @State private var completion: Task<Void, Never>?

    private func reset() {
        completion?.cancel()
        completion = nil
        running = false
        finished = false
        generation += 1
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GeometryReader { geometry in
                    MGObject().frame(width: 52, height: 52)
                        .keyframeAnimator(initialValue: Values(), trigger: trigger) { view, value in
                            let progress: CGFloat = reduceMotion && finished ? 1 : value.progress
                            let scale: CGFloat = reduceMotion && finished ? 2 : value.scale
                            let opacity = reduceMotion && finished ? 1 : value.opacity
                            view.scaleEffect(scale)
                                .overlay(alignment: .bottom) {
                                    Text("今天，也想到了你。")
                                        .font(.caption).fixedSize().offset(y: 65).opacity(opacity)
                                }
                                .position(x: 50 + progress * (geometry.size.width - 100),
                                          y: 205 - progress * 90)
                        } keyframes: { _ in
                            KeyframeTrack(\.progress) {
                                CubicKeyframe(1, duration: duration)
                                LinearKeyframe(1, duration: pause + 0.48)
                            }
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(1, duration: duration + pause)
                                CubicKeyframe(2, duration: 0.28)
                                LinearKeyframe(2, duration: 0.2)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0, duration: duration + pause + 0.28)
                                LinearKeyframe(1, duration: 0.2)
                            }
                        }.id(generation)
                }
                .frame(height: 280)
                .background(MGStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("移动并打开") {
                        if reduceMotion { finished = true; return }
                        running = true
                        trigger += 1
                        let total = duration + pause + 0.48
                        completion = Task { @MainActor in
                            do { try await Task.sleep(for: .seconds(total)) }
                            catch { return }
                            running = false
                            finished = true
                        }
                    }.disabled(running || finished).buttonStyle(.borderedProminent)
                    Button("取消并复位", action: reset).buttonStyle(.bordered)
                }
                MGSlider(title: "位移时长", value: $duration, range: 0.2...1.5, suffix: " s")
                    .disabled(running || finished)
                MGSlider(title: "到达后停留", value: $pause, range: 0...0.6, suffix: " s")
                    .disabled(running || finished)
                Text(running ? "移动 → 停留 → 展开 → 揭示" : finished ? "已打开" : "等待开始")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel(running ? "动作进行中" : finished ? "已打开" : "等待开始")
            }.padding()
        }
        .onDisappear(perform: reset)
        .onChange(of: reduceMotion) { _, enabled in
            if enabled && running {
                reset()
                finished = true
            }
        }
        .navigationTitle("分阶段动作").navigationBarTitleDisplayMode(.inline).tint(MGStyle.green)
    }
}

private struct MGMatchedLab: View {
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var response = 0.6
    @State private var damping = 0.95
    private var object: some View {
        RoundedRectangle(cornerRadius: expanded ? 30 : 18)
            .fill(MGStyle.green)
            .matchedGeometryEffect(id: "keepsake", in: space)
            .frame(width: expanded ? 160 : 52, height: expanded ? 160 : 52)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack {
                    if expanded {
                        object
                        Spacer()
                    } else {
                        Spacer()
                        HStack { object; Spacer() }
                    }
                }
                .padding(30).frame(maxWidth: .infinity).frame(height: 280)
                .background(MGStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                Button(expanded ? "收回物件" : "展开物件") {
                    withAnimation(reduceMotion ? nil : .spring(response: response, dampingFraction: damping)) {
                        expanded.toggle()
                    }
                }.buttonStyle(.borderedProminent)
                MGSlider(title: "响应", value: $response, range: 0.2...1.2, suffix: " s")
                MGSlider(title: "阻尼比", value: $damping, range: 0.4...1.3)
                Text("两个布局，共享一个身份。起终点由布局决定，不使用全屏硬编码坐标。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("跨布局展开").navigationBarTitleDisplayMode(.inline).tint(MGStyle.green)
    }
}

// MARK: - UIKit 呈现位置、释放速度与可中断弹簧
// 这里用 center 管理位置，不给物件添加位置约束或额外 transform。
// UIKit 的 presentation layer 提供显示中的位置；CADisplayLink 采样显示速度。
@MainActor
private final class MGDisplayLinkProxy: NSObject {
    weak var owner: MGPhysicsView?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

@MainActor
private final class MGPhysicsView: UIView {
    var response: CGFloat = 0.55
    var dampingRatio: CGFloat = 0.85
    var reduceMotion = false
    var draggable = true { didSet { pan.isEnabled = draggable } }
    var onState: ((Bool) -> Void)?
    private let object = UIView()
    private let rail = UIView()
    private let startDot = UIView()
    private let endDot = UIView()
    private var animator: UIViewPropertyAnimator?
    private var displayLink: CADisplayLink?
    private let proxy = MGDisplayLinkProxy()
    private var previousSample: (point: CGPoint, time: CFTimeInterval)?
    private var velocity = CGVector.zero
    private var targetOpen = false
    private var dragOrigin: CGFloat = 0
    private var previousBounds = CGRect.zero
    private var gestureInProgress = false
    private var gestureSample: (x: CGFloat, time: CFTimeInterval)?
    private var displayedDragVelocity: CGFloat = 0
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var a: CGPoint { CGPoint(x: 50, y: bounds.midY) }
    private var b: CGPoint { CGPoint(x: max(51, bounds.width - 50), y: bounds.midY) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 1)
        layer.cornerRadius = 12
        clipsToBounds = true
        rail.backgroundColor = MGStyle.uiGreen.withAlphaComponent(0.12)
        addSubview(rail)
        for dot in [startDot, endDot] {
            dot.layer.borderColor = MGStyle.uiGreen.withAlphaComponent(0.35).cgColor
            dot.layer.borderWidth = 1
            dot.layer.cornerRadius = 28
            addSubview(dot)
        }
        object.backgroundColor = MGStyle.uiGreen
        object.layer.cornerRadius = 18
        object.bounds = CGRect(x: 0, y: 0, width: 52, height: 52)
        object.isAccessibilityElement = true
        object.accessibilityLabel = "可移动的物件"
        object.accessibilityTraits = .button
        addSubview(object)
        object.addGestureRecognizer(pan)
        proxy.owner = self
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func layoutSubviews() {
        super.layoutSubviews()
        rail.frame = CGRect(x: a.x, y: a.y - 1, width: b.x - a.x, height: 2)
        startDot.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
        endDot.bounds = startDot.bounds
        startDot.center = a
        endDot.center = b
        if previousBounds.size != bounds.size {
            stopAtVisiblePosition()
            object.center = targetOpen ? b : a
            previousBounds = bounds
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopAtVisiblePosition() }
    }
    private func updateAccessibility() {
        object.accessibilityValue = targetOpen ? "已打开" : "已关闭"
        object.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: targetOpen ? "关闭" : "打开", target: self,
                                        selector: #selector(accessibilityToggle))
        ]
    }
    @objc private func accessibilityToggle() -> Bool {
        move(open: !targetOpen)
        return true
    }
    private func visibleCenter() -> CGPoint {
        object.layer.presentation()?.position ?? object.center
    }
    @discardableResult
    private func stopAtVisiblePosition() -> CGPoint {
        animator?.pauseAnimation()
        let visible = visibleCenter()
        animator?.stopAnimation(true)
        animator = nil
        object.center = visible
        displayLink?.invalidate()
        displayLink = nil
        previousSample = nil
        return visible
    }
    fileprivate func tick(_ link: CADisplayLink) {
        let visible = visibleCenter()
        if let old = previousSample {
            let dt = link.timestamp - old.time
            if dt > 0 {
                velocity = CGVector(dx: (visible.x - old.point.x) / dt,
                                    dy: (visible.y - old.point.y) / dt)
            }
        }
        previousSample = (visible, link.timestamp)
    }
    func move(open: Bool, initialVelocity: CGVector? = nil) {
        layoutIfNeeded()
        let inherited = initialVelocity ?? velocity
        let start = stopAtVisiblePosition()
        targetOpen = open
        let target = open ? b : a
        updateAccessibility()
        onState?(open)
        if reduceMotion {
            object.center = target
            velocity = .zero
            return
        }
        let dx = target.x - start.x, dy = target.y - start.y
        if hypot(dx, dy) < 0.1 && hypot(inherited.dx, inherited.dy) < 1 {
            object.center = target
            velocity = .zero
            return
        }
        // UIKit 使用相对剩余距离的初速度。极小位移上不做除法。
        let normalized = CGVector(dx: abs(dx) > 1 ? inherited.dx / dx : 0,
                                  dy: abs(dy) > 1 ? inherited.dy / dy : 0)
        let omega = 2 * CGFloat.pi / max(0.15, response)
        let timing = UISpringTimingParameters(mass: 1, stiffness: omega * omega,
                                              damping: 2 * dampingRatio * omega,
                                              initialVelocity: normalized)
        let next = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        next.addAnimations { [weak self] in self?.object.center = target }
        next.addCompletion { [weak self, weak next] _ in
            guard let self, let next, self.animator === next else { return }
            self.animator = nil
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.previousSample = nil
            self.velocity = .zero
            UIAccessibility.post(notification: .announcement, argument: open ? "已打开" : "已关闭")
        }
        animator = next
        velocity = inherited
        previousSample = nil
        let link = CADisplayLink(target: proxy, selector: #selector(MGDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        next.startAnimation()
    }
    func jump(open: Bool) {
        _ = stopAtVisiblePosition()
        targetOpen = open
        object.center = open ? b : a
        velocity = .zero
        updateAccessibility()
    }
    func shutdown() {
        _ = stopAtVisiblePosition()
        onState = nil
    }
    private func rubber(_ distance: CGFloat) -> CGFloat { 80 * distance / (80 + distance) }
    private func resisted(_ x: CGFloat) -> CGFloat {
        if x < a.x { return a.x - rubber(a.x - x) }
        if x > b.x { return b.x + rubber(x - b.x) }
        return x
    }
    private func unresisted(_ x: CGFloat) -> CGFloat {
        // 橡皮筋逆映射。再次抓住越界中的物件时保持显示位置连续。
        if x < a.x {
            let distance = min(79.9, a.x - x)
            return a.x - 80 * distance / (80 - distance)
        }
        if x > b.x {
            let distance = min(79.9, x - b.x)
            return b.x + 80 * distance / (80 - distance)
        }
        return x
    }
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            gestureInProgress = true
            let visible = stopAtVisiblePosition()
            dragOrigin = unresisted(visible.x)
            gestureSample = (visible.x, CACurrentMediaTime())
            displayedDragVelocity = 0
        case .changed:
            let raw = dragOrigin + recognizer.translation(in: self).x
            let displayed = resisted(raw)
            let now = CACurrentMediaTime()
            if let sample = gestureSample, now > sample.time {
                displayedDragVelocity = (displayed - sample.x) / (now - sample.time)
            }
            gestureSample = (displayed, now)
            object.center = CGPoint(x: displayed, y: a.y)
        case .ended, .cancelled, .failed:
            guard gestureInProgress else { return }
            gestureInProgress = false
            let cancelled = recognizer.state != .ended
            if let sample = gestureSample, CACurrentMediaTime() - sample.time > 0.1 {
                displayedDragVelocity = 0
            }
            let releaseVelocity = cancelled ? 0 : displayedDragVelocity
            let predicted = object.center.x + releaseVelocity * 0.18
            move(open: predicted > (a.x + b.x) / 2,
                 initialVelocity: CGVector(dx: releaseVelocity, dy: 0))
            gestureSample = nil
        default: break
        }
    }
}

private struct MGPhysicsStage: UIViewRepresentable {
    var response: Double
    var damping: Double
    var reduceMotion: Bool
    var draggable: Bool
    var command: Int
    var open: Bool
    var onState: (Bool) -> Void
    final class Coordinator {
        var command = 0
        var reduceMotion = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MGPhysicsView {
        let view = MGPhysicsView()
        view.response = response
        view.dampingRatio = damping
        view.reduceMotion = reduceMotion
        view.draggable = draggable
        view.onState = onState
        context.coordinator.command = command
        context.coordinator.reduceMotion = reduceMotion
        return view
    }
    func updateUIView(_ view: MGPhysicsView, context: Context) {
        view.response = response
        view.dampingRatio = damping
        view.draggable = draggable
        view.reduceMotion = reduceMotion
        view.onState = onState
        if context.coordinator.command != command {
            context.coordinator.command = command
            // 此闭包由 SwiftUI 状态操作驱动，不在 update 中回写同一 Binding。
            view.onState = nil
            view.move(open: open)
            view.onState = onState
        } else if reduceMotion && !context.coordinator.reduceMotion {
            view.jump(open: open)
        }
        context.coordinator.reduceMotion = reduceMotion
    }
    static func dismantleUIView(_ uiView: MGPhysicsView, coordinator: Coordinator) { uiView.shutdown() }
}

private struct MGDragLab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var response = 0.5
    @State private var damping = 0.85
    @State private var command = 0
    @State private var open = false
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MGPhysicsStage(response: response, damping: damping, reduceMotion: reduceMotion,
                               draggable: true, command: command, open: open,
                               onState: { open = $0 })
                    .frame(height: 280)
                HStack {
                    Button("打开") { open = true; command += 1 }
                    Button("关闭") { open = false; command += 1 }
                }.buttonStyle(.borderedProminent)
                MGSlider(title: "响应", value: $response, range: 0.2...1.2, suffix: " s")
                MGSlider(title: "阻尼比", value: $damping, range: 0.4...1.3)
                Text("拖动物件，越界后继续拉；回弹过程中可以再次抓住。释放速度来自显示位置的采样。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(open ? "目标：打开" : "目标：关闭").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("拖动与吸附").navigationBarTitleDisplayMode(.inline).tint(MGStyle.green)
    }
}

private struct MGInterruptLab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var response = 0.85
    @State private var damping = 0.65
    @State private var command = 0
    @State private var open = false
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MGPhysicsStage(response: response, damping: damping, reduceMotion: reduceMotion,
                               draggable: false, command: command, open: open,
                               onState: { open = $0 })
                    .frame(height: 280)
                HStack {
                    Button("前往 B") { open = true; command += 1 }
                    Button("返回 A") { open = false; command += 1 }
                }.buttonStyle(.borderedProminent)
                MGSlider(title: "响应", value: $response, range: 0.2...1.2, suffix: " s")
                MGSlider(title: "阻尼比", value: $damping, range: 0.4...1.3)
                Text("运动途中反复切换目标。显示位置和采样速度被带到下一段弹簧；高速反向时可能先继续前行一点。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("中途改目标").navigationBarTitleDisplayMode(.inline).tint(MGStyle.green)
    }
}
