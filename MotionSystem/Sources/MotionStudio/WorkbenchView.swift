import SwiftUI
import MotionCore
import MotionSwiftUI

@MainActor
struct WorkbenchView: View {
    @ObservedObject var workspace: StudioWorkspace
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var simulateReduced = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading,spacing: 20) {
                    VStack(alignment: .leading,spacing: 8) {
                        Text(workspace.recipe.name).font(.largeTitle.bold())
                        Text("同一份配方，驱动显示、曲线和 Swift 输出。单位采用点、弧度和秒。")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top,spacing: 20) {
                            stageColumn.frame(maxWidth: .infinity)
                            controls.frame(width: 340)
                        }
                    } else { stageColumn; controls }
                    StudioPanel(title: "可复用的 Swift View") { CodePanel(code: workspace.exportedCode) }
                }.padding(20).frame(maxWidth: 1300).frame(maxWidth: .infinity)
            }.background(StudioStyle.paper)
        }
        .onAppear { workspace.reduce(systemReduced || simulateReduced) }
        .onChange(of: systemReduced) { _,value in workspace.reduce(value || simulateReduced) }
        .onChange(of: simulateReduced) { _,value in workspace.reduce(value || systemReduced) }
        .onChange(of: workspace.recipe) { _,_ in workspace.editApplied() }
        .onDisappear { workspace.pause() }
    }
    private var stageColumn: some View {
        VStack(spacing: 18) {
            StudioPanel(title: "运动舞台") {
                StudioStage(driver: workspace.driver,comparison: workspace.comparison,
                            recipe: workspace.recipe,baseline: workspace.baseline,
                            showPath: workspace.showPath,showGhosts: workspace.showGhosts)
                PlaybackControls(workspace: workspace,driver: workspace.driver)
                HStack {
                    Toggle("路径",isOn: $workspace.showPath)
                    Toggle("等时采样点",isOn: $workspace.showGhosts)
                }.font(.caption)
                if let notice = workspace.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            StudioPanel(title: "观察一个通道") {
                Picker("通道",selection: $workspace.selectedChannel) {
                    ForEach(MotionChannel.allCases,id: \.self) { channel in
                        Text(channel.rawValue.motionTitle).tag(channel)
                    }
                }
                Picker("曲线",selection: $workspace.showVelocity) {
                    Text("值").tag(false); Text("速度").tag(true)
                }.pickerStyle(.segmented)
                MotionCurvePlot(motion: workspace.source,baseline: workspace.baseline?.makeTrajectory(),
                                channel: workspace.selectedChannel,velocity: workspace.showVelocity,
                                driver: workspace.driver)
                LiveReadout(driver: workspace.driver,channel: workspace.selectedChannel)
                HStack {
                    Button("保存为对照") { workspace.saveBaseline() }
                    if workspace.baseline != nil {
                        Button("清除对照") { workspace.baseline = nil; workspace.comparison.detach() }
                    }
                }.buttonStyle(.bordered)
                Text("实线是当前动作，虚线是保存的配方。修改过程中续接的新动作，可能与原始起终点不同。")
                    .font(.caption).foregroundStyle(.secondary)
                if let baseline = workspace.baseline { RecipeComparisonView(baseline: baseline,current: workspace.recipe) }
            }
        }
    }
    private var controls: some View {
        VStack(spacing: 18) {
            StudioPanel(title: "模型") {
                Picker("运动模型",selection: $workspace.recipe.family) {
                    ForEach(MotionFamily.allCases) { Text($0.rawValue.motionTitle).tag($0) }
                }
                ModelControls(recipe: $workspace.recipe)
                Toggle("播放中续接参数修改",isOn: $workspace.followEdits).font(.caption)
            }
            StudioPanel(title: "起终点与属性") {
                PoseControls(pose: $workspace.recipe.initial,title: "起点")
                if workspace.recipe.family == .timeline && workspace.recipe.keyframeDocument != nil {
                    Text("已启用多关键帧；各通道的目标值在关键帧时间轴中编辑。").font(.caption).foregroundStyle(.secondary)
                } else { PoseControls(pose: $workspace.recipe.target,title: "终点") }
            }
            StudioPanel(title: "重复、取消与减少动态") {
                ParameterSlider(title: "开始前等待",value: $workspace.recipe.delay,range: 0...1,unit: "s")
                Stepper("重复 \(workspace.recipe.repeatCount) 次",value: $workspace.recipe.repeatCount,in: 1...8)
                Toggle("往返",isOn: $workspace.recipe.autoreverses)
                Picker("中断",selection: $workspace.recipe.intent.interruption) {
                    ForEach(MotionInterruption.allCases,id: \.self) { Text($0.rawValue.motionTitle).tag($0) }
                }
                Picker("取消",selection: $workspace.recipe.intent.cancellation) {
                    ForEach(MotionCancellation.allCases,id: \.self) { Text($0.rawValue.motionTitle).tag($0) }
                }
                Picker("减少动态结果",selection: $workspace.recipe.intent.reducedBehavior) {
                    ForEach(MotionReducedBehavior.allCases,id: \.self) { Text($0.rawValue.motionTitle).tag($0) }
                }
                Toggle("模拟减少动态",isOn: $simulateReduced)
                if systemReduced { Text("系统减少动态已开启。这里只能增加限制，不能覆盖系统偏好。").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ModelControls: View {
    @Binding var recipe: MotionRecipe
    var body: some View {
        Group {
            if [.spring,.path].contains(recipe.family) {
                if recipe.family == .path { Toggle("用弹簧驱动路径进度",isOn: $recipe.pathUsesSpring) }
                if recipe.family == .spring || recipe.pathUsesSpring {
                    ParameterSlider(title: "响应 response",value: $recipe.spring.response,range: 0.15...1.2,unit: "s",hint: "先调节奏，不是精确结束时间。")
                    ParameterSlider(title: "阻尼比 ζ",value: $recipe.spring.dampingRatio,range: 0.2...1.5,hint: "静止释放时：小于 1 可回弹，等于 1 临界，大于 1 慢趋近。")
                    Text("k = \(recipe.spring.stiffness,specifier: "%.1f") · c = \(recipe.spring.damping,specifier: "%.1f") · m = \(recipe.spring.mass,specifier: "%.1f")")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if recipe.family == .tween || recipe.family == .hermite || recipe.family == .path && !recipe.pathUsesSpring {
                ParameterSlider(title: "时长",value: $recipe.duration,range: 0.1...2.5,unit: "s")
            }
            if recipe.family == .tween || recipe.family == .path && !recipe.pathUsesSpring {
                CurveControls(curve: $recipe.curve)
            }
            if [.spring,.hermite,.decay].contains(recipe.family) {
                ParameterSlider(title: "初速度 X",value: Binding(get: { recipe.velocity[0] },set: { recipe.velocity[0] = $0 }),range: -1200...1200,unit: "pt/s")
                ParameterSlider(title: "初速度 Y",value: Binding(get: { recipe.velocity[1] },set: { recipe.velocity[1] = $0 }),range: -1200...1200,unit: "pt/s")
                Text("初速度用于新播放；续接时使用当前运动速度。").font(.caption).foregroundStyle(.secondary)
            }
            if recipe.family == .decay {
                ParameterSlider(title: "衰减率 λ",value: $recipe.decay.rate,range: 1...12,unit: "1/s")
                Text("终点由 x₀ + v₀/λ 决定，不使用手填目标。这里没有碰撞边界；吸附见手势实验。").font(.caption).foregroundStyle(.secondary)
            }
            if recipe.family == .path {
                Picker("路径进度",selection: $recipe.pathMode) {
                    Text("贝塞尔参数").tag(PathParameterization.parameter)
                    Text("近似弧长").tag(PathParameterization.arcLength)
                }
                Picker("越过端点",selection: $recipe.pathBoundary) {
                    Text("沿切线延伸").tag(PathBoundary.extendTangent)
                    Text("硬限制在端点").tag(PathBoundary.clamp)
                }
                if recipe.pathDocument == nil {
                    ParameterSlider(title: "控制点 1 · X",value: $recipe.control1.x,range: 0...340,unit: "pt")
                    ParameterSlider(title: "控制点 1 · Y",value: $recipe.control1.y,range: -50...280,unit: "pt")
                    ParameterSlider(title: "控制点 2 · X",value: $recipe.control2.x,range: 0...340,unit: "pt")
                    ParameterSlider(title: "控制点 2 · Y",value: $recipe.control2.y,range: -50...280,unit: "pt")
                } else {
                    Text("已启用多段路线，节点和手柄在空间路径编辑器中修改。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if recipe.family == .timeline {
                if recipe.keyframeDocument == nil { TimelineControls(recipe: $recipe) }
                else { Text("已启用多关键帧，各段时间与数值在关键帧时间轴中编辑。").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct CurveControls: View {
    @Binding var curve: TimingCurve
    private var name: String {
        switch curve {
        case .linear: return "linear"
        case .bezier: return "bezier"
        case .smoothstep: return "smoothstep"
        case .smootherstep: return "smootherstep"
        case .sineInOut: return "sine"
        case .steps: return "steps"
        }
    }
    var body: some View {
        Picker("曲线",selection: Binding(get: { name },set: { key in
            switch key {
            case "linear": curve = .linear
            case "smoothstep": curve = .smoothstep
            case "smootherstep": curve = .smootherstep
            case "sine": curve = .sineInOut
            case "steps": curve = .steps(6)
            default: curve = .bezier(.easeInOut)
            }
        })) {
            Text("线性").tag("linear"); Text("三次贝塞尔").tag("bezier")
            Text("Smoothstep").tag("smoothstep"); Text("Smootherstep").tag("smootherstep")
            Text("正弦").tag("sine"); Text("阶梯").tag("steps")
        }
        if case .bezier(let c) = curve {
            ForEach(0..<4,id: \.self) { index in
                ParameterSlider(title: ["x₁","y₁","x₂","y₂"][index],value: Binding(get: {
                    [c.x1,c.y1,c.x2,c.y2][index]
                },set: { value in
                    var values = [c.x1,c.y1,c.x2,c.y2]; values[index] = value
                    curve = .bezier(.init(values[0],values[1],values[2],values[3]))
                }),range: index%2 == 0 ? 0...1 : -0.5...1.5)
            }
        }
        if case .steps(let count) = curve {
            Stepper("\(count) 个阶梯",value: Binding(get: { count },set: { curve = .steps($0) }),in: 2...24)
        }
    }
}

struct PoseControls: View {
    @Binding var pose: MotionPose
    let title: String
    var body: some View {
        DisclosureGroup(title) {
            ForEach(MotionChannel.allCases,id: \.self) { channel in
                ParameterSlider(title: channel.rawValue.motionTitle,value: Binding(get: { pose[channel] },set: { pose[channel] = $0 }),range: range(channel),unit: channel.unit)
            }
        }
    }
    private func range(_ channel: MotionChannel) -> ClosedRange<Double> {
        switch channel {
        case .x: return 20...320
        case .y: return 20...260
        case .scaleX,.scaleY: return 0.2...3
        case .rotation: return -.pi...(.pi*2)
        case .opacity: return 0...1
        case .blur: return 0...20
        case .cornerRadius: return 0...60
        case .width,.height: return 10...150
        }
    }
}

struct TimelineControls: View {
    @Binding var recipe: MotionRecipe
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            if recipe.tracks.isEmpty {
                Button("加入位移和展开轨道") { recipe.tracks = MotionRecipes.stagedReveal.tracks }
            }
            ForEach($recipe.tracks) { $track in
                DisclosureGroup(track.channel.rawValue.motionTitle) {
                    ParameterSlider(title: "开始",value: $track.startTime,range: 0...2,unit: "s")
                    ParameterSlider(title: "持续",value: $track.duration,range: 0.1...2,unit: "s")
                    CurveControls(curve: $track.curve)
                    Button("移除轨道",role: .destructive) { recipe.tracks.removeAll { $0.channel == track.channel } }
                }
            }
            Menu("添加轨道") {
                ForEach(MotionChannel.allCases.filter { c in !recipe.tracks.contains { $0.channel == c } },id: \.self) { c in
                    Button(c.rawValue.motionTitle) { recipe.tracks.append(.init(c,start: 0,duration: 0.6)) }
                }
            }
            Text("每条轨道控制一个通道；未加入轨道的通道保持起点值。这里各轨道从静止出发，互不继承速度。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct PlaybackControls: View {
    @ObservedObject var workspace: StudioWorkspace
    @ObservedObject var driver: MotionDriver<MotionPose>
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(driver.state == .playing ? "暂停" : "播放",systemImage: driver.state == .playing ? "pause.fill" : "play.fill") {
                    if driver.state == .playing { workspace.pause() } else { workspace.play() }
                }.buttonStyle(.borderedProminent)
                Button("返回") { workspace.reverse() }.buttonStyle(.bordered)
                Button("取消") { workspace.cancel() }.buttonStyle(.bordered)
                Button("复位") { workspace.rebuild() }.buttonStyle(.borderless)
            }.font(.subheadline)
            HStack {
                Text("\(driver.elapsed,specifier: "%.2f") / \(driver.duration,specifier: "%.2f") s")
                    .font(.caption.monospacedDigit())
                Spacer()
                Picker("播放速度",selection: $workspace.playbackRate) {
                    Text("¼×").tag(0.25); Text("½×").tag(0.5); Text("1×").tag(1.0)
                }.pickerStyle(.menu)
            }
            Slider(value: Binding(get: { driver.elapsed },set: { workspace.seek($0) }),in: 0...max(0.001,driver.duration))
                .accessibilityLabel("时间观察")
        }.onChange(of: workspace.playbackRate) { _,value in
            workspace.driver.playbackRate = value; workspace.comparison.playbackRate = value
        }
    }
}

@MainActor
struct StudioStage: View {
    @ObservedObject var driver: MotionDriver<MotionPose>
    @ObservedObject var comparison: MotionDriver<MotionPose>
    var recipe: MotionRecipe
    var baseline: MotionRecipe?
    var showPath: Bool
    var showGhosts: Bool
    var body: some View {
        GeometryReader { geometry in
            let factor = min(geometry.size.width/340,geometry.size.height/280)
            ZStack(alignment: .topLeading) {
                Canvas { context,size in
                    for x in stride(from: 0.0,through: 340.0,by: 20) {
                        for y in stride(from: 0.0,through: 280.0,by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x,y: y,width: 1.2,height: 1.2)),with: .color(.secondary.opacity(0.25)))
                        }
                    }
                    if showPath {
                        var path = Path(); path.move(to: CGPoint(x: recipe.initial.x,y: recipe.initial.y))
                        if recipe.family == .path {
                            for segment in recipe.resolvedPath().segments {
                                path.addCurve(to: segment.end.cgPoint,control1: segment.control1.cgPoint,control2: segment.control2.cgPoint)
                            }
                        } else {
                            let end = recipe.makeTrajectory().endValue
                            path.addLine(to: CGPoint(x: end.x,y: end.y))
                        }
                        context.stroke(path,with: .color(.secondary.opacity(0.5)),style: StrokeStyle(lineWidth: 1,dash: [3,4]))
                    }
                    if showGhosts {
                        let motion = recipe.makeTrajectory()
                        for index in 0...18 {
                            let point = motion.sample(at: motion.duration*Double(index)/18).value
                            context.stroke(Path(ellipseIn: CGRect(x: point.x-3,y: point.y-3,width: 6,height: 6)),with: .color(StudioStyle.rust.opacity(0.65)),lineWidth: 1)
                        }
                    }
                }.frame(width: 340,height: 280)
                if baseline != nil {
                    Rectangle().stroke(StudioStyle.rust,style: StrokeStyle(lineWidth: 2,dash: [4,3]))
                        .motionPose(comparison.value)
                }
                Rectangle().fill(StudioStyle.green)
                    .overlay { Image(systemName: "arrow.up.right").foregroundStyle(.white).font(.title3) }
                    .motionPose(driver.value)
            }
            .frame(width: 340,height: 280,alignment: .topLeading)
            .scaleEffect(factor,anchor: .topLeading)
            .frame(width: geometry.size.width,height: geometry.size.height,alignment: .topLeading)
        }
        .frame(height: 280)
        .background(StudioStyle.paper,in: RoundedRectangle(cornerRadius: 12))
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("运动舞台")
        .accessibilityValue("X \(Int(driver.value.x))，Y \(Int(driver.value.y))")
    }
}

@MainActor
struct MotionCurvePlot: View {
    let motion: MotionTrajectory<MotionPose>
    let baseline: MotionTrajectory<MotionPose>?
    let channel: MotionChannel
    let velocity: Bool
    let driver: MotionDriver<MotionPose>
    var body: some View {
        let duration = max(0.001,max(motion.duration,baseline?.duration ?? 0))
        let samples = series(motion,duration: duration)
        let saved = baseline.map { series($0,duration: duration) } ?? []
        let all = samples+saved
        let low = min(0,all.min() ?? 0), high = max(low+0.01,all.max() ?? 1)
        VStack(alignment: .leading,spacing: 6) {
            HStack {
                Text("\(high,specifier: "%.2f") \(channel.unit)\(velocity ? "/s" : "")")
                Spacer(); Text("\(duration,specifier: "%.2f") s")
            }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            ZStack {
                Canvas { context,size in
                    for i in 0...4 {
                        let y = size.height*Double(i)/4
                        var line = Path(); line.move(to: CGPoint(x: 0,y: y)); line.addLine(to: CGPoint(x: size.width,y: y))
                        context.stroke(line,with: .color(.secondary.opacity(0.15)),lineWidth: 1)
                    }
                    func line(_ values: [Double]) -> Path {
                        var path = Path()
                        for (i,value) in values.enumerated() {
                            let p = CGPoint(x: Double(i)/Double(max(1,values.count-1))*size.width,y: size.height-(value-low)/(high-low)*size.height)
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        return path
                    }
                    context.stroke(line(samples),with: .color(StudioStyle.green),lineWidth: 2)
                    if !saved.isEmpty { context.stroke(line(saved),with: .color(StudioStyle.rust),style: StrokeStyle(lineWidth: 1.5,dash: [4,3])) }
                }
                CurvePlayhead(driver: driver,duration: duration)
            }.frame(height: 170)
            Text("\(low,specifier: "%.2f")").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    private func series(_ trajectory: MotionTrajectory<MotionPose>,duration: Double) -> [Double] {
        (0...200).map {
            let sample = trajectory.sample(at: duration*Double($0)/200)
            return velocity ? sample.velocity[channel.index] : sample.value[channel]
        }
    }
}

@MainActor
private struct CurvePlayhead: View {
    @ObservedObject var driver: MotionDriver<MotionPose>
    let duration: Double
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(StudioStyle.rust.opacity(0.7)).frame(width: 1)
                .offset(x: geometry.size.width*motionClamp(driver.elapsed/duration))
        }.allowsHitTesting(false)
    }
}
@MainActor
private struct LiveReadout: View {
    @ObservedObject var driver: MotionDriver<MotionPose>
    let channel: MotionChannel
    var body: some View {
        HStack {
            Text("值 \(driver.value[channel],specifier: "%.3f")")
            Spacer()
            Text("速度 \(driver.velocity[channel.index],specifier: "%.3f") \(channel.unit)/s")
        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }
}
