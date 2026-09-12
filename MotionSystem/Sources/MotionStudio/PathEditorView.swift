import SwiftUI
import MotionCore
import MotionSwiftUI

@MainActor
struct PathEditorView: View {
    @ObservedObject var workspace: StudioWorkspace
    @State private var selected: UUID?
    @State private var splitFraction = 0.5
    @State private var showHandles = true
    @State private var showSpacing = false
    @State private var viewport = CGRect(x: -20,y: -20,width: 380,height: 320)
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var document: PathDocument? { workspace.recipe.pathDocument }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("把路线直接画出来。").font(.largeTitle.bold())
                Text("移动圆形节点改变必经点，移动菱形手柄改变出发与到达方向。空间路线用点坐标，时间曲线仍然独立控制节奏。")
                    .foregroundStyle(.secondary)
                if let document {
                    StudioPanel(title: "多段贝塞尔路径") {
                        PathEditingCanvas(document: document,selected: $selected,driver: workspace.driver,
                                          showHandles: showHandles,showSpacing: showSpacing,viewport: viewport,
                                          onBegin: { workspace.beginEdit($0) },
                                          onMove: { id,handle,point in
                                              workspace.updateContinuousEdit { recipe in
                                                  guard var path = recipe.pathDocument else { return }
                                                  path.move(id: id,handle: handle,to: point)
                                                  recipe.setPathDocument(path)
                                              }
                                          },onCommit: { workspace.finishEdit() })
                            .frame(height: 360)
                        HStack {
                            Toggle("显示手柄",isOn: $showHandles)
                            Toggle("等路程标记",isOn: $showSpacing)
                        }.font(.caption)
                        HStack {
                            Button("全部入镜") { fit(document) }
                            Button("恢复舞台范围") { viewport = CGRect(x: -20,y: -20,width: 380,height: 320) }
                        }.font(.caption).buttonStyle(.bordered)
                        PlaybackControls(workspace: workspace,driver: workspace.driver)
                        EditorHistoryBar(workspace: workspace)
                    }
                    if let knot = document.knots.first(where: { $0.id == selected }) {
                        nodeInspector(knot,document: document)
                    } else {
                        Text("点按一个节点，编辑它的坐标、切线或拆分相邻曲线。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    StudioPanel(title: "沿路径的运动") {
                        ParameterSlider(title: "行程时长",value: scalar(\.duration,label: "调整行程时长"),range: 0.15...3,unit: "s",editingChanged: { if !$0 { workspace.finishEdit() } })
                        Picker("参数化",selection: Binding(get: { workspace.recipe.pathMode },set: { value in
                            workspace.edit("切换路径参数化") { $0.pathMode = value }
                        })) {
                            Text("按贝塞尔参数").tag(PathParameterization.parameter)
                            Text("按近似弧长").tag(PathParameterization.arcLength)
                        }.pickerStyle(.segmented)
                        Text("按近似弧长时，线性时间进度对应近似匀速路程。等路程标记与时间曲线不同；控制点越弯，二者的区别越明显。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("匀速沿路径") { workspace.edit("使用匀速") { $0.curve = .linear; $0.pathUsesSpring = false }; workspace.play() }
                            Button("自然减速") { workspace.edit("使用自然减速") { $0.curve = .bezier(.easeInOut); $0.pathUsesSpring = false }; workspace.play() }
                        }.buttonStyle(.bordered)
                    }
                    StudioPanel(title: "节点与速度的关系") {
                        Text("共线手柄保证接点两侧朝向一致，称为几何切线连续。镜像手柄进一步约束两侧长度。最终速度仍取决于每段参数化和时间进度，不能只看手柄共线就断言速度完全连续。")
                        Text("插入节点使用 De Casteljau 拆分，保留原路线；删除内节点会重连两侧，路线会改变。两种操作都可以撤销。")
                    }
                    CodePanel(code: pathCode(document))
                } else {
                    Button("将当前配方转为空间路径") { initializePath() }.buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onAppear {
            workspace.reduce(reduced)
            if document == nil { initializePath() }
            else { workspace.recipe.family = .path; workspace.rebuild(); selected = document?.knots.first?.id }
        }
        .onChange(of: reduced) { _,enabled in workspace.reduce(enabled) }
        .onChange(of: workspace.recipe.pathDocument) { _,path in
            if let selected,path?.index(of: selected) == nil { self.selected = path?.knots.first?.id }
        }
        .onDisappear { workspace.finishEdit(); workspace.pause() }
    }
    private func initializePath() {
        workspace.edit("创建多段路径") { recipe in
            let path = recipe.editablePath
            recipe.family = .path; recipe.setPathDocument(path)
        }
        selected = workspace.recipe.pathDocument?.knots.first?.id
    }
    private func fit(_ document: PathDocument) {
        let points = document.knots.flatMap { [$0.point,$0.incoming,$0.outgoing] }
        let minX = min(0,points.map(\.x).min() ?? 0)-24
        let minY = min(0,points.map(\.y).min() ?? 0)-24
        let maxX = max(340,points.map(\.x).max() ?? 340)+24
        let maxY = max(280,points.map(\.y).max() ?? 280)+24
        viewport = CGRect(x: minX,y: minY,width: maxX-minX,height: maxY-minY)
    }
    private func scalar(_ key: WritableKeyPath<MotionRecipe,Double>,label: String) -> Binding<Double> {
        Binding(get: { workspace.recipe[keyPath: key] },set: { value in
            workspace.beginEdit(label)
            workspace.updateContinuousEdit { $0[keyPath: key] = value }
        })
    }
    @ViewBuilder
    private func nodeInspector(_ knot: PathKnot,document: PathDocument) -> some View {
        let index = document.index(of: knot.id) ?? 0
        StudioPanel(title: index == 0 ? "起点" : index == document.knots.count-1 ? "终点" : "必经点 \(index)") {
            ForEach([PathHandle.anchor,.incoming,.outgoing],id: \.self) { handle in
                if handle == .anchor || handle == .incoming && index > 0 || handle == .outgoing && index < document.knots.count-1 {
                    DisclosureGroup(handle == .anchor ? "节点坐标" : handle == .incoming ? "到达手柄" : "出发手柄") {
                        ExactParameterField(title: "精确 X",value: coordinate(knot.id,handle: handle,x: true),unit: "pt",editingChanged: { if !$0 { workspace.finishEdit() } })
                        ExactParameterField(title: "精确 Y",value: coordinate(knot.id,handle: handle,x: false),unit: "pt",editingChanged: { if !$0 { workspace.finishEdit() } })
                        ParameterSlider(title: "X",value: coordinate(knot.id,handle: handle,x: true),range: -20...360,unit: "pt",editingChanged: { if !$0 { workspace.finishEdit() } })
                        ParameterSlider(title: "Y",value: coordinate(knot.id,handle: handle,x: false),range: -20...300,unit: "pt",editingChanged: { if !$0 { workspace.finishEdit() } })
                    }
                }
            }
            if index > 0 && index < document.knots.count-1 {
                Picker("切线模式",selection: Binding(get: { knot.mode },set: { mode in
                    workspace.edit("改变切线模式") { recipe in
                        guard var path = recipe.pathDocument else { return }
                        path.setMode(id: knot.id,mode: mode); recipe.setPathDocument(path)
                    }
                })) {
                    Text("独立").tag(PathHandleMode.independent)
                    Text("共线").tag(PathHandleMode.aligned)
                    Text("镜像").tag(PathHandleMode.mirrored)
                }.pickerStyle(.segmented)
                if let angle = document.tangentAgreement(at: index) {
                    Text("两侧切线夹角：\(angle,specifier: "%.1f")°，接近 0° 表示方向连续。")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if index < document.knots.count-1 {
                ParameterSlider(title: "下一段的拆分位置",value: $splitFraction,range: 0.1...0.9)
                Button("在下一段插入节点") {
                    var created: UUID?
                    workspace.edit("插入路径节点") { recipe in
                        guard var path = recipe.pathDocument else { return }
                        created = path.split(segment: index,at: splitFraction); recipe.setPathDocument(path)
                    }
                    selected = created
                }.buttonStyle(.bordered)
            }
            if index > 0 && index < document.knots.count-1 {
                Button("删除这个必经点",role: .destructive) {
                    workspace.edit("删除路径节点") { recipe in
                        guard var path = recipe.pathDocument else { return }
                        path.removeInterior(id: knot.id); recipe.setPathDocument(path)
                    }
                }
            }
        }
    }
    private func coordinate(_ id: UUID,handle: PathHandle,x: Bool) -> Binding<Double> {
        Binding(get: {
            guard let knot = workspace.recipe.pathDocument?.knots.first(where: { $0.id == id }) else { return 0 }
            let point = handle == .anchor ? knot.point : handle == .incoming ? knot.incoming : knot.outgoing
            return x ? point.x : point.y
        },set: { value in
            workspace.beginEdit("调整节点坐标")
            workspace.updateContinuousEdit { recipe in
                guard var path = recipe.pathDocument,let index = path.index(of: id) else { return }
                let knot = path.knots[index]
                var point = handle == .anchor ? knot.point : handle == .incoming ? knot.incoming : knot.outgoing
                if x { point.x = value } else { point.y = value }
                path.move(id: id,handle: handle,to: point); recipe.setPathDocument(path)
            }
        })
    }
    private func pathCode(_ document: PathDocument) -> String {
        let segments = document.segments.map { s in
            "    BezierSegment(start: MotionPoint(\(s.start.x), \(s.start.y)),\n        control1: MotionPoint(\(s.control1.x), \(s.control1.y)),\n        control2: MotionPoint(\(s.control2.x), \(s.control2.y)),\n        end: MotionPoint(\(s.end.x), \(s.end.y)))"
        }.joined(separator: ",\n")
        return """
        let route = MotionPath(segments: [
        \(segments)
        ])
        let progress = MotionTrajectory<Double>.transition(
            from: 0, to: 1,
            model: .tween(duration: \(workspace.recipe.duration), curve: .linear)
        )
        let movement = route.trajectory(progress: progress, mode: .\(workspace.recipe.pathMode.rawValue))
        // 这是路径代码；完整配方的时间曲线、外观与行为请从工作台导出。
        """
    }
}

@MainActor
struct EditorHistoryBar: View {
    @ObservedObject var workspace: StudioWorkspace
    var body: some View {
        HStack {
            Button("撤销",systemImage: "arrow.uturn.backward") { workspace.undo() }.disabled(workspace.undoTitle == nil)
            Button("重做",systemImage: "arrow.uturn.forward") { workspace.redo() }.disabled(workspace.redoTitle == nil)
            Spacer()
            Button("保存配方") { workspace.finishEdit(); workspace.saveRecipe() }
        }.font(.caption).buttonStyle(.bordered)
    }
}

@MainActor
private struct PathEditingCanvas: View {
    let document: PathDocument
    @Binding var selected: UUID?
    @ObservedObject var driver: MotionDriver<MotionPose>
    let showHandles: Bool
    let showSpacing: Bool
    let viewport: CGRect
    let onBegin: (String) -> Void
    let onMove: (UUID,PathHandle,MotionPoint) -> Void
    let onCommit: () -> Void
    var body: some View {
        GeometryReader { geometry in
            let scale = min((geometry.size.width-24)/viewport.width,(geometry.size.height-24)/viewport.height)
            let origin = CGPoint(x: (geometry.size.width-viewport.width*scale)/2-viewport.minX*scale,
                                 y: (geometry.size.height-viewport.height*scale)/2-viewport.minY*scale)
            let map: (MotionPoint) -> CGPoint = { CGPoint(x: origin.x+$0.x*scale,y: origin.y+$0.y*scale) }
            ZStack(alignment: .topLeading) {
                Canvas { context,_ in
                    for x in stride(from: 0.0,through: 340,by: 20) {
                        for y in stride(from: 0.0,through: 280,by: 20) {
                            let p = map(MotionPoint(x,y))
                            context.fill(Path(ellipseIn: CGRect(x: p.x,y: p.y,width: 1.3,height: 1.3)),with: .color(.secondary.opacity(0.25)))
                        }
                    }
                    var line = Path()
                    if let first = document.knots.first { line.move(to: map(first.point)) }
                    for s in document.segments { line.addCurve(to: map(s.end),control1: map(s.control1),control2: map(s.control2)) }
                    context.stroke(line,with: .color(StudioStyle.green),lineWidth: 2)
                    if showSpacing {
                        let path = document.path
                        for i in 0...24 {
                            let p = map(path.sample(progress: Double(i)/24).point)
                            context.fill(Path(ellipseIn: CGRect(x: p.x-2,y: p.y-2,width: 4,height: 4)),with: .color(StudioStyle.rust))
                        }
                    }
                    if showHandles,let knot = document.knots.first(where: { $0.id == selected }) {
                        var line = Path(); line.move(to: map(knot.incoming)); line.addLine(to: map(knot.point)); line.addLine(to: map(knot.outgoing))
                        context.stroke(line,with: .color(StudioStyle.rust.opacity(0.7)),style: StrokeStyle(lineWidth: 1,dash: [3,3]))
                    }
                }
                Circle().fill(StudioStyle.green.opacity(0.22)).frame(width: 30,height: 30)
                    .position(map(MotionPoint(driver.value.x,driver.value.y))).allowsHitTesting(false)
                ForEach(Array(document.knots.enumerated()),id: \.element.id) { index,knot in
                    PathHandleControl(point: knot.point,screen: map(knot.point),scale: scale,
                                      label: "节点 \(index+1)",number: index+1,selected: selected == knot.id,diamond: false,
                                      onBegin: { selected = knot.id; onBegin("移动路径节点") },
                                      onMove: { onMove(knot.id,.anchor,$0) },onCommit: onCommit)
                    if showHandles && selected == knot.id {
                        if index > 0 {
                            PathHandleControl(point: knot.incoming,screen: map(knot.incoming),scale: scale,
                                              label: "到达手柄",number: nil,selected: true,diamond: true,
                                              onBegin: { onBegin("移动到达手柄") },
                                              onMove: { onMove(knot.id,.incoming,$0) },onCommit: onCommit)
                        }
                        if index < document.knots.count-1 {
                            PathHandleControl(point: knot.outgoing,screen: map(knot.outgoing),scale: scale,
                                              label: "出发手柄",number: nil,selected: true,diamond: true,
                                              onBegin: { onBegin("移动出发手柄") },
                                              onMove: { onMove(knot.id,.outgoing,$0) },onCommit: onCommit)
                        }
                    }
                }
            }.coordinateSpace(name: "path-authoring")
        }.background(StudioStyle.paper,in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PathHandleControl: View {
    let point: MotionPoint
    let screen: CGPoint
    let scale: Double
    let label: String
    let number: Int?
    let selected: Bool
    let diamond: Bool
    let onBegin: () -> Void
    let onMove: (MotionPoint) -> Void
    let onCommit: () -> Void
    @State private var origin: MotionPoint?
    @GestureState private var active = false
    var body: some View {
        ZStack {
            if diamond {
                Rectangle().fill(StudioStyle.rust).frame(width: 12,height: 12).rotationEffect(.degrees(45))
            } else {
                Circle().fill(selected ? StudioStyle.green : Color.white).frame(width: 24,height: 24)
                    .overlay(Circle().stroke(StudioStyle.green,lineWidth: 1.5).frame(width: 24,height: 24))
                if let number { Text("\(number)").font(.system(size: 10,weight: .semibold)).foregroundStyle(selected ? Color.white : StudioStyle.green) }
            }
        }.frame(width: 44,height: 44).contentShape(Rectangle()).position(screen)
        .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .named("path-authoring"))
            .updating($active) { _,state,_ in state = true }
            .onChanged { value in
                if origin == nil { origin = point; onBegin() }
                guard let origin else { return }
                onMove(MotionPoint(origin.x+value.translation.width/scale,origin.y+value.translation.height/scale))
            }
            .onEnded { _ in origin = nil; onCommit() })
        .onChange(of: active) { _,value in if !value && origin != nil { origin = nil; onCommit() } }
        .accessibilityLabel(label)
        .accessibilityValue("X \(point.x,specifier: "%.0f")，Y \(point.y,specifier: "%.0f")")
        .accessibilityHint("点按选中，然后通过下方坐标滑杆调整")
        .accessibilityAction { onBegin(); onCommit() }
    }
}
