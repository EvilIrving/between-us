import SwiftUI
import MotionCore
import MotionSwiftUI

@MainActor
struct TimelineEditorView: View {
    @ObservedObject var workspace: StudioWorkspace
    @State private var selectedChannel: MotionChannel = .x
    @State private var selectedFrame: UUID?
    @State private var insertionTime = 0.4
    @State private var pixelsPerSecond = 200.0
    @State private var snapping = true
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var document: KeyframeDocument? { workspace.recipe.keyframeDocument }
    private var selectedLane: KeyframeLane? { document?.lanes.first { $0.channel == selectedChannel } }
    private var currentKey: MotionKeyframe? { selectedLane?.keyframes.first { $0.id == selectedFrame } }
    private var span: Double { max(2,(document?.duration ?? 1)+0.5) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("让每个变化有自己的时刻。").font(.largeTitle.bold())
                Text("每行是一种属性，每个菱形是一个关键帧。拖动改变时间，选中后调整数值和上一段的插值方式。")
                    .foregroundStyle(.secondary)
                if let document {
                    StudioPanel(title: "原生时间轴") {
                        Toggle("位置继续沿空间路径运动",isOn: Binding(get: { workspace.recipe.family == .path },set: { enabled in
                            workspace.edit("切换位置来源") { recipe in
                                recipe.family = enabled ? .path : .timeline
                                if enabled && recipe.pathDocument == nil { recipe.setPathDocument(recipe.editablePath) }
                            }
                        }))
                        if workspace.recipe.family == .path {
                            Text("X / Y 由路径决定，关键帧只控制缩放、旋转、透明度等外观通道。").font(.caption).foregroundStyle(.secondary)
                        }
                        TimelineCanvas(document: document,driver: workspace.driver,pixelsPerSecond: pixelsPerSecond,
                                       span: span,selectedChannel: selectedChannel,selectedFrame: selectedFrame,
                                       onSelect: { channel,id in selectedChannel = channel; selectedFrame = id },
                                       onBegin: { workspace.finishEdit(); workspace.beginEdit("移动关键帧") },
                                       onMove: { channel,id,time in
                                           workspace.updateContinuousEdit { recipe in
                                               guard var timeline = recipe.keyframeDocument,
                                                     let lane = timeline.lanes.firstIndex(where: { $0.channel == channel }) else { return }
                                               timeline.lanes[lane].move(id: id,to: motionClamp(time,0...30),snap: snapping ? 0.05 : nil)
                                               recipe.keyframeDocument = timeline
                                           }
                                       },onEnd: { workspace.finishEdit() })
                        HStack {
                            Toggle("吸附到 0.05 秒",isOn: $snapping).font(.caption)
                            Spacer()
                            Button("缩小",systemImage: "minus.magnifyingglass") { pixelsPerSecond = max(60,pixelsPerSecond/1.4) }
                            Button("放大",systemImage: "plus.magnifyingglass") { pixelsPerSecond = min(600,pixelsPerSecond*1.4) }
                        }.labelStyle(.iconOnly)
                        PlaybackControls(workspace: workspace,driver: workspace.driver)
                        EditorHistoryBar(workspace: workspace)
                        HStack {
                            Button("总时长 × 1.2") {
                                workspace.edit("整体放慢") { $0.keyframeDocument?.retime(scale: 1.2) }
                            }
                            Button("总时长 ÷ 1.2") {
                                workspace.edit("整体加快") { $0.keyframeDocument?.retime(scale: 1/1.2) }
                            }
                        }.buttonStyle(.bordered).font(.caption)
                    }
                    StudioPanel(title: "当前场景") {
                        StudioStage(driver: workspace.driver,comparison: workspace.comparison,
                                    recipe: workspace.recipe,baseline: workspace.baseline,showPath: false,showGhosts: false)
                        Text("此编辑器直接编排单次时间轴；开始延迟、重复与往返在总工作台设置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Menu("添加通道") {
                            ForEach(MotionChannel.allCases.filter { c in !document.lanes.contains { $0.channel == c } },id: \.self) { channel in
                                Button(channel.rawValue.motionTitle) { addLane(channel) }
                            }
                        }.buttonStyle(.bordered)
                        Picker("选中通道",selection: $selectedChannel) {
                            ForEach(document.lanes) { lane in Text(lane.channel.rawValue.motionTitle).tag(lane.channel) }
                        }
                    }
                    if let lane = selectedLane { laneInspector(lane) }
                    if let key = currentKey { keyInspector(key) }
                    StudioPanel(title: "值与速度") {
                        MotionCurvePlot(motion: workspace.source,baseline: nil,channel: selectedChannel,velocity: false,driver: workspace.driver)
                        MotionCurvePlot(motion: workspace.source,baseline: nil,channel: selectedChannel,velocity: true,driver: workspace.driver)
                        Text("时间轴的数值连续，不代表速度连续。Hermite 在两端使用 tangent；相邻区间都使用 Hermite，且共用同一个节点速度时，接点才具有匹配的速度。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    StudioPanel(title: "保持、插值与后续变化") {
                        Text("“保持到此帧”在抵达关键帧时跳到新值，适合有意的离散变化。“线性”保持区间匀速。“贝塞尔”把同一段值交给时间曲线。“Hermite”让你指定节点速度。")
                        Text("插入关键帧取当前曲线的显示值和速度，但重建区间可能改变原贝塞尔曲线；与路径的精确拆段不同。移除关键帧会把前后两段合并成一个新区间。")
                    }
                } else {
                    Button("创建可编辑时间轴") { initializeTimeline() }.buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onAppear {
            workspace.reduce(reduced)
            if document == nil { initializeTimeline() }
            else { if workspace.recipe.family != .path { workspace.recipe.family = .timeline }; workspace.rebuild() }
            repairSelection()
        }
        .onChange(of: selectedChannel) { _,_ in selectedFrame = selectedLane?.keyframes.first?.id }
        .onChange(of: workspace.recipe.keyframeDocument) { _,_ in repairSelection() }
        .onChange(of: reduced) { _,value in workspace.reduce(value) }
        .onDisappear { workspace.finishEdit(); workspace.pause() }
    }
    private func initializeTimeline() {
        let keepingPath = workspace.recipe.family == .path
        workspace.edit("创建关键帧时间轴") { recipe in
            let tracks = recipe.tracks.isEmpty ? MotionRecipes.stagedReveal.tracks : recipe.tracks
            recipe.keyframeDocument = .migrating(tracks: tracks,initial: recipe.initial,target: recipe.target)
            recipe.family = keepingPath ? .path : .timeline; recipe.delay = 0; recipe.repeatCount = 1; recipe.autoreverses = false
        }
        repairSelection()
    }
    private func repairSelection() {
        guard let lanes = document?.lanes else { return }
        if !lanes.contains(where: { $0.channel == selectedChannel }),let first = lanes.first { selectedChannel = first.channel }
        if selectedLane?.keyframes.contains(where: { $0.id == selectedFrame }) != true { selectedFrame = selectedLane?.keyframes.first?.id }
    }
    private func addLane(_ channel: MotionChannel) {
        workspace.edit("添加通道") { recipe in
            guard var timeline = recipe.keyframeDocument else { return }
            timeline.lanes.append(KeyframeLane(channel: channel,keyframes: [
                .init(time: 0,value: recipe.initial[channel]),
                .init(time: max(0.5,timeline.duration),value: recipe.target[channel])
            ]))
            recipe.keyframeDocument = timeline
        }
        selectedChannel = channel; selectedFrame = selectedLane?.keyframes.first?.id
    }
    private func updateLane(_ label: String,continuous: Bool = false,_ edit: @escaping (inout KeyframeLane) -> Void) {
        let apply: (inout MotionRecipe) -> Void = { recipe in
            guard var timeline = recipe.keyframeDocument,
                  let index = timeline.lanes.firstIndex(where: { $0.channel == selectedChannel }) else { return }
            edit(&timeline.lanes[index]); recipe.keyframeDocument = timeline
        }
        if continuous { workspace.beginEdit(label); workspace.updateContinuousEdit(apply) }
        else { workspace.edit(label,apply) }
    }
    @ViewBuilder
    private func laneInspector(_ lane: KeyframeLane) -> some View {
        StudioPanel(title: selectedChannel.rawValue.motionTitle) {
            if workspace.recipe.family == .path && (selectedChannel == .x || selectedChannel == .y) {
                Text("这个位置通道当前由路径接管。关键帧会保留，切回时间轴位置后才参与播放。").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("参与播放",isOn: Binding(get: { lane.isEnabled },set: { enabled in updateLane("切换通道") { $0.isEnabled = enabled } }))
            HStack {
                Button("整条提前 0.1 秒") { updateLane("提前整条通道") { $0.retime(scale: 1,offset: -0.1) } }
                Button("整条推后 0.1 秒") { updateLane("推后整条通道") { $0.retime(scale: 1,offset: 0.1) } }
            }.buttonStyle(.bordered).font(.caption)
            ParameterSlider(title: "插入时间",value: $insertionTime,range: 0...max(1,span),unit: "s")
            HStack {
                Button("插入关键帧") {
                    var id: UUID?
                    updateLane("插入关键帧") { lane in
                        id = lane.insert(at: insertionTime,fallback: workspace.recipe.initial[selectedChannel])
                    }
                    selectedFrame = id
                }.buttonStyle(.borderedProminent)
                Button("移除通道",role: .destructive) {
                    workspace.edit("移除通道") { recipe in
                        recipe.keyframeDocument?.lanes.removeAll { $0.channel == selectedChannel }
                    }
                }.buttonStyle(.bordered)
            }
        }
    }
    private func keyValue(_ key: MotionKeyframe) -> Binding<Double> {
        Binding(get: { currentKey?.value ?? key.value },set: { value in
            updateLane("改变关键帧数值",continuous: true) { lane in
                guard let index = lane.keyframes.firstIndex(where: { $0.id == key.id }) else { return }
                lane.keyframes[index].value = value
            }
        })
    }
    private func interpolationName(_ value: KeyframeInterpolation) -> String {
        switch value {
        case .linear: return "linear"
        case .bezier,.curve: return "bezier"
        case .hermite: return "hermite"
        case .hold: return "hold"
        }
    }
    @ViewBuilder
    private func keyInspector(_ key: MotionKeyframe) -> some View {
        StudioPanel(title: "关键帧 · \(key.time.formatted(.number.precision(.fractionLength(2)))) s") {
            ExactParameterField(title: "精确数值",value: keyValue(key),unit: selectedChannel.unit,
                                editingChanged: { if !$0 { workspace.finishEdit() } })
            ParameterSlider(title: "时间",value: Binding(get: { currentKey?.time ?? key.time },set: { time in
                updateLane("调整关键帧时间",continuous: true) { $0.move(id: key.id,to: time,snap: snapping ? 0.05 : nil) }
            }),range: 0...max(span,key.time+0.5),unit: "s",editingChanged: { if !$0 { workspace.finishEdit() } })
            ParameterSlider(title: selectedChannel.rawValue.motionTitle,value: keyValue(key),range: valueRange(for: selectedChannel,value: key.value),unit: selectedChannel.unit,
                            editingChanged: { if !$0 { workspace.finishEdit() } })
            Picker("上一帧到此帧",selection: Binding(get: { interpolationName(key.interpolation) },set: { name in
                updateLane("切换区间插值") { lane in
                    guard let index = lane.keyframes.firstIndex(where: { $0.id == key.id }) else { return }
                    switch name {
                    case "linear": lane.keyframes[index].interpolation = .linear
                    case "hermite": lane.keyframes[index].interpolation = .hermite
                    case "hold": lane.keyframes[index].interpolation = .hold
                    default: lane.keyframes[index].interpolation = .bezier(.easeInOut)
                    }
                }
            })) {
                Text("线性").tag("linear"); Text("时间曲线").tag("bezier")
                Text("Hermite").tag("hermite"); Text("保持到此帧").tag("hold")
            }
            ParameterSlider(title: "节点速度 tangent",value: Binding(get: { currentKey?.tangent ?? key.tangent },set: { value in
                updateLane("调整节点速度",continuous: true) { lane in
                    guard let index = lane.keyframes.firstIndex(where: { $0.id == key.id }) else { return }
                    lane.keyframes[index].tangent = value
                }
            }),range: -500...500,unit: "\(selectedChannel.unit)/s",hint: "仅参与相邻的 Hermite 区间。",editingChanged: { if !$0 { workspace.finishEdit() } })
            if interpolationName(key.interpolation) == "bezier" {
                CurveControls(curve: Binding(get: {
                    switch currentKey?.interpolation ?? key.interpolation {
                    case .bezier(let curve): return .bezier(curve)
                    case .curve(let curve): return curve
                    default: return .bezier(.easeInOut)
                    }
                },set: { curve in
                    updateLane("编辑关键帧时间曲线",continuous: true) { lane in
                        guard let index = lane.keyframes.firstIndex(where: { $0.id == key.id }) else { return }
                        lane.keyframes[index].interpolation = .curve(curve)
                    }
                }))
            }
            if (selectedLane?.keyframes.count ?? 0) > 2 {
                Button("删除关键帧",role: .destructive) { updateLane("删除关键帧") { $0.remove(id: key.id) } }
            }
        }
    }
    private func valueRange(for channel: MotionChannel,value: Double) -> ClosedRange<Double> {
        let standard: ClosedRange<Double>
        switch channel {
        case .x: standard = -50...390
        case .y: standard = -50...330
        case .scaleX,.scaleY: standard = 0.1...3
        case .rotation: standard = (-2 * .pi)...(2 * .pi)
        case .opacity: standard = 0...1
        case .blur: standard = 0...30
        case .cornerRadius: standard = 0...80
        case .width,.height: standard = 5...200
        }
        return min(standard.lowerBound,value)...max(standard.upperBound,value)
    }
}

@MainActor
private struct TimelineCanvas: View {
    let document: KeyframeDocument
    @ObservedObject var driver: MotionDriver<MotionPose>
    let pixelsPerSecond: Double
    let span: Double
    let selectedChannel: MotionChannel
    let selectedFrame: UUID?
    let onSelect: (MotionChannel,UUID) -> Void
    let onBegin: () -> Void
    let onMove: (MotionChannel,UUID,Double) -> Void
    let onEnd: () -> Void
    var body: some View {
        let width = max(400,96+span*pixelsPerSecond+24)
        let height = Double(document.lanes.count)*56+42
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                Canvas { context,size in
                    for t in stride(from: 0.0,through: span,by: 0.25) {
                        let x = 96+t*pixelsPerSecond
                        var line = Path(); line.move(to: CGPoint(x: x,y: 24)); line.addLine(to: CGPoint(x: x,y: size.height))
                        context.stroke(line,with: .color(.secondary.opacity(0.18)),lineWidth: 1)
                        if Int((t*4).rounded())%2 == 0 {
                            context.draw(Text("\(t,specifier: "%.1f")s").font(.system(size: 10,design: .monospaced)),at: CGPoint(x: x,y: 10))
                        }
                    }
                    for (index,lane) in document.lanes.enumerated() {
                        let y = 44+Double(index)*56
                        context.draw(Text(lane.channel.rawValue.motionTitle).font(.caption).foregroundColor(lane.isEnabled ? .primary : .secondary),at: CGPoint(x: 40,y: y))
                        if let first = lane.keyframes.first,let last = lane.keyframes.last {
                            var path = Path(); path.move(to: CGPoint(x: 96+first.time*pixelsPerSecond,y: y)); path.addLine(to: CGPoint(x: 96+last.time*pixelsPerSecond,y: y))
                            context.stroke(path,with: .color(StudioStyle.green.opacity(lane.isEnabled ? 0.25 : 0.08)),lineWidth: 12)
                        }
                    }
                    let playheadX = 96+driver.elapsed*pixelsPerSecond
                    var playhead = Path(); playhead.move(to: CGPoint(x: playheadX,y: 18)); playhead.addLine(to: CGPoint(x: playheadX,y: size.height))
                    context.stroke(playhead,with: .color(StudioStyle.rust),lineWidth: 1.5)
                }
                ForEach(Array(document.lanes.enumerated()),id: \.element.id) { index,lane in
                    ForEach(lane.keyframes) { frame in
                        TimelineKeyHandle(frame: frame,selected: selectedChannel == lane.channel && selectedFrame == frame.id,
                                          pixelsPerSecond: pixelsPerSecond,
                                          onBegin: { onSelect(lane.channel,frame.id); onBegin() },
                                          onMove: { onMove(lane.channel,frame.id,$0) },onEnd: onEnd)
                            .position(x: 96+frame.time*pixelsPerSecond,y: 44+Double(index)*56)
                    }
                }
            }.frame(width: width,height: max(100,height))
                .coordinateSpace(name: "timeline-authoring")
        }.background(StudioStyle.paper,in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TimelineKeyHandle: View {
    let frame: MotionKeyframe
    let selected: Bool
    let pixelsPerSecond: Double
    let onBegin: () -> Void
    let onMove: (Double) -> Void
    let onEnd: () -> Void
    @State private var originalTime: Double?
    @GestureState private var active = false
    var body: some View {
        Rectangle().fill(selected ? StudioStyle.rust : StudioStyle.green)
            .frame(width: 12,height: 12).rotationEffect(.degrees(45))
            .frame(width: 44,height: 44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .named("timeline-authoring"))
                .updating($active) { _,state,_ in state = true }
                .onChanged { value in
                    if originalTime == nil { originalTime = frame.time; onBegin() }
                    onMove((originalTime ?? frame.time)+value.translation.width/pixelsPerSecond)
                }
                .onEnded { _ in originalTime = nil; onEnd() })
            .onChange(of: active) { _,value in if !value && originalTime != nil { originalTime = nil; onEnd() } }
            .accessibilityLabel("关键帧")
            .accessibilityValue("\(frame.time,specifier: "%.2f") 秒，值 \(frame.value,specifier: "%.2f")")
            .accessibilityHint("点按选中，通过下方滑杆调整时间和数值")
            .accessibilityAction { onBegin(); onEnd() }
    }
}
