import SwiftUI

private enum StudioDestination: String, CaseIterable, Identifiable {
    case workbench, bezier, path, timeline, gesture, interruption, data, library, guide, agent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workbench: return "动效工作台"
        case .bezier: return "贝塞尔编辑器"
        case .path: return "空间路径编辑器"
        case .timeline: return "关键帧时间轴"
        case .gesture: return "手势与物理"
        case .interruption: return "中断与恢复"
        case .data: return "让数据动起来"
        case .library: return "配方库"
        case .guide: return "原理与实现指南"
        case .agent: return "给 Agent 的动效约定"
        }
    }
    var icon: String {
        switch self {
        case .workbench: return "slider.horizontal.3"
        case .bezier: return "point.topleft.down.curvedto.point.bottomright.up"
        case .path: return "point.3.connected.trianglepath.dotted"
        case .timeline: return "timeline.selection"
        case .gesture: return "hand.draw"
        case .interruption: return "arrow.triangle.branch"
        case .data: return "waveform.path"
        case .library: return "square.stack"
        case .guide: return "book"
        case .agent: return "text.bubble"
        }
    }
}

/// 原生工作台入口。只有 SwiftUI、UIKit 与自有数学模型，无 WebView 或 JS。
@MainActor
public struct MotionStudioRoot: View {
    @StateObject private var workspace = StudioWorkspace()
    @State private var destination: StudioDestination? = .workbench
    @Environment(\.scenePhase) private var phase
    public init() {}
    public var body: some View {
        NavigationSplitView {
            List(StudioDestination.allCases,selection: $destination) { item in
                NavigationLink(value: item) { Label(item.title,systemImage: item.icon) }
            }
            .navigationTitle("Motion Studio")
            .safeAreaInset(edge: .bottom) {
                Text("表达意图 · 定义模型 · 观察变化 · 带回 Swift")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            Group {
                switch destination ?? .workbench {
                case .workbench: WorkbenchView(workspace: workspace)
                case .bezier: BezierEditorView(workspace: workspace)
                case .path: PathEditorView(workspace: workspace)
                case .timeline: TimelineEditorView(workspace: workspace)
                case .gesture: GestureLabView()
                case .interruption: InterruptionStudioView()
                case .data: DataMotionLab()
                case .library: RecipeLibraryView(workspace: workspace)
                case .guide: MotionGuideView()
                case .agent: AgentContractView(workspace: workspace)
                }
            }
            .navigationTitle((destination ?? .workbench).title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(StudioStyle.green)
        .onChange(of: destination) { _,_ in workspace.pause() }
        .onChange(of: phase) { _,value in if value != .active { workspace.pause() } }
        .onDisappear { workspace.driver.detach(); workspace.comparison.detach() }
    }
}
