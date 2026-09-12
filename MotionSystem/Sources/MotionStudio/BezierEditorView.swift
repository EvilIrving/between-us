import SwiftUI
import MotionCore
import MotionSwiftUI

@MainActor
struct BezierEditorView: View {
    @ObservedObject var workspace: StudioWorkspace
    @State private var curve = CubicBezier.easeInOut
    @State private var duration = 0.65
    @StateObject private var driver = MotionDriver(initial: 0.0)
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("画的是节奏，不是路线。").font(.largeTitle.bold())
                Text("横轴是已经过去的时间，纵轴是已经完成的进度。控制点的 X 限制在 0…1；Y 可以越界，产生有意的反向或过冲。")
                    .foregroundStyle(.secondary)
                StudioPanel(title: "三次贝塞尔时间曲线") {
                    BezierCanvas(curve: $curve).frame(height: 310)
                    HStack {
                        Button("慢—快—慢") { curve = .easeInOut }
                        Button("快启动") { curve = .easeOut }
                        Button("强调减速") { curve = .emphasized }
                    }.buttonStyle(.bordered).font(.caption)
                    CurveControls(curve: Binding(get: { .bezier(curve) },set: { if case .bezier(let value) = $0 { curve = value } }))
                    ParameterSlider(title: "时长",value: $duration,range: 0.15...2,unit: "s")
                }
                StudioPanel(title: "把这条曲线用在直线位移上") {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.15)).frame(height: 2)
                            RoundedRectangle(cornerRadius: 16).fill(StudioStyle.green).frame(width: 48,height: 48)
                                .offset(x: driver.value*(geometry.size.width-48))
                        }.frame(height: 70)
                    }.frame(height: 70).clipped()
                    HStack {
                        Button("播放") {
                            driver.play(.transition(from: 0,to: 1,model: .tween(duration: duration,curve: .bezier(curve))))
                        }.buttonStyle(.borderedProminent)
                        Button("应用到工作台") {
                            workspace.recipe.curve = .bezier(curve)
                            workspace.recipe.duration = duration
                            workspace.recipe.family = .tween
                            workspace.rebuild()
                        }.buttonStyle(.bordered)
                    }
                    Text("曲线的斜率决定速度。起点斜率大就立刻出发；终点斜率不为零，结束时会突然失去速度。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                CodePanel(code: """
                // 原生 SwiftUI 使用同一组时间贝塞尔控制点。
                withAnimation(.timingCurve(
                    \(curve.x1), \(curve.y1), \(curve.x2), \(curve.y2),
                    duration: \(duration)
                )) {
                    expanded.toggle()
                }

                // 自有数据使用同一条曲线。
                let trajectory = MotionTrajectory<Double>.transition(
                    from: 12, to: 98,
                    model: .tween(duration: \(duration), curve: .bezier(
                        CubicBezier(\(curve.x1), \(curve.y1), \(curve.x2), \(curve.y2))
                    )
                )
                """)
                StudioPanel(title: "什么时候不要用贝塞尔时间曲线") {
                    Text("拖动释放需要继承速度时，优先弹簧。必须在固定时间到达且接住当前速度时，用 Hermite。贝塞尔可以做出漂亮的单次动作，但控制点不会自动包含刚才手指的速度。")
                    Text("空间路径也能用贝塞尔，但它的控制点单位是 pt。不要把两者的控制点混用。")
                }
            }.padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onAppear { driver.reduceMotion = reduced }
        .onChange(of: reduced) { _,value in driver.reduceMotion = value }
        .onChange(of: phase) { _,value in if value != .active { driver.pause() } }
        .onDisappear { driver.detach() }
    }
}

private struct BezierCanvas: View {
    @Binding var curve: CubicBezier
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // 保留上下越界区：y=-0.5 在底部，y=1.5 在顶部。
            let map: (Double,Double) -> CGPoint = { x,y in CGPoint(x: 24+x*(size.width-48),y: 20+(1.5-y)/2*(size.height-40)) }
            ZStack(alignment: .topLeading) {
                Canvas { context,_ in
                    for value in [0.0,0.25,0.5,0.75,1.0] {
                        var line = Path(); line.move(to: map(value,-0.5)); line.addLine(to: map(value,1.5))
                        context.stroke(line,with: .color(.secondary.opacity(0.15)),lineWidth: 1)
                    }
                    for value in [0.0,0.5,1.0] {
                        var line = Path(); line.move(to: map(0,value)); line.addLine(to: map(1,value))
                        context.stroke(line,with: .color(.secondary.opacity(0.25)),lineWidth: 1)
                    }
                    var handles = Path(); handles.move(to: map(0,0)); handles.addLine(to: map(curve.x1,curve.y1))
                    handles.move(to: map(1,1)); handles.addLine(to: map(curve.x2,curve.y2))
                    context.stroke(handles,with: .color(StudioStyle.rust.opacity(0.6)),style: StrokeStyle(lineWidth: 1,dash: [4,3]))
                    var path = Path()
                    for i in 0...180 {
                        let t = Double(i)/180, point = map(t,curve.value(at: t))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path,with: .color(StudioStyle.green),lineWidth: 3)
                    context.draw(Text("0").font(.caption2),at: map(0,-0.3))
                    context.draw(Text("时间 → 1").font(.caption2),at: map(0.87,-0.3))
                }
                ForEach(0..<2,id: \.self) { index in
                    let x = index == 0 ? curve.x1 : curve.x2, y = index == 0 ? curve.y1 : curve.y2
                    Circle().fill(StudioStyle.rust).frame(width: 18,height: 18)
                        .overlay { Text("\(index+1)").font(.system(size: 10,weight: .bold)).foregroundStyle(.white) }
                        .frame(width: 44,height: 44).contentShape(Rectangle())
                        .position(map(x,y))
                        .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .named("bezier-canvas"))
                            .onChanged { value in
                                let nextX = motionClamp((value.location.x-24)/(size.width-48))
                                let nextY = motionClamp(1.5-2*(value.location.y-20)/(size.height-40),-0.5...1.5)
                                if index == 0 { curve.x1 = nextX; curve.y1 = nextY }
                                else { curve.x2 = nextX; curve.y2 = nextY }
                            })
                        .accessibilityLabel("控制点 \(index+1)，请使用下方 X 和 Y 滑杆调整")
                }
            }.coordinateSpace(name: "bezier-canvas")
        }.background(StudioStyle.paper,in: RoundedRectangle(cornerRadius: 12))
    }
}
