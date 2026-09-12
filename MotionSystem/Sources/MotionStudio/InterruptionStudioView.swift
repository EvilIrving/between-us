import SwiftUI
import MotionCore
import MotionSwiftUI

@MainActor
struct InterruptionStudioView: View {
    @StateObject private var session = MotionSession(recipe: MotionRecipes.unfold)
    @StateObject private var emptyComparison = MotionDriver(initial: MotionPose())
    @State private var bookmark: MotionSessionBookmark?
    @State private var localReduced = false
    @State private var cancellation = MotionCancellation.returnToStart
    @State private var interruptedTarget = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("动作进行到一半，之后呢？").font(.largeTitle.bold())
                Text("用真实事件改变同一个原生运动会话。可以抓住当前值、换目标、暂停、保存现场，再决定怎么恢复。")
                    .foregroundStyle(.secondary)
                StudioPanel(title: "当前会话") {
                    StudioStage(driver: session.driver,comparison: emptyComparison,recipe: session.recipe,
                                baseline: nil,showPath: true,showGhosts: false)
                    SessionReadout(driver: session.driver)
                    ViewThatFits {
                        HStack { playbackButtons }
                        VStack(alignment: .leading) { playbackButtons }
                    }
                    HStack {
                        Button("中途改变目标") {
                            var target = session.recipe.target
                            interruptedTarget.toggle()
                            target.x = interruptedTarget ? 65 : 270
                            target.y = interruptedTarget ? 80 : 190
                            session.send(.targetChanged(target))
                        }
                        Button("取消当前动作") { session.send(.cancel) }
                    }.buttonStyle(.bordered)
                    Picker("取消后",selection: $cancellation) {
                        ForEach(MotionCancellation.allCases,id: \.self) { Text($0.rawValue.motionTitle).tag($0) }
                    }
                    Toggle("模拟减少动态",isOn: $localReduced)
                    if let note = session.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                StudioPanel(title: "保存与恢复运动现场") {
                    HStack {
                        Button("保存此刻") { bookmark = session.bookmark() }.buttonStyle(.borderedProminent)
                        Button("恢复并暂停") { if let bookmark { session.restore(bookmark) } }
                            .buttonStyle(.bordered).disabled(bookmark == nil)
                    }
                    HStack {
                        Button("恢复后继续") { if let bookmark { session.restore(bookmark,resume: true) } }
                            .buttonStyle(.bordered).disabled(bookmark == nil)
                        Button("模拟离开场景") { session.send(.leaveScene) }.buttonStyle(.bordered)
                    }
                    if let bookmark {
                        Text("已保存：\(bookmark.time,specifier: "%.2f") s · X \(bookmark.value.x,specifier: "%.1f") · Y \(bookmark.value.y,specifier: "%.1f")")
                            .font(.caption.monospacedDigit())
                    }
                    Text("恢复记录保存的是当时正在播放的运动段，包括中途变更后的起点、目标和初速度。它不会把后来修改的参数误当成旧现场，也不会恢复已经结束的手指接触。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                StudioPanel(title: "事件与结果") {
                    if session.records.isEmpty { Text("还没有操作记录。").foregroundStyle(.secondary) }
                    ForEach(session.records.reversed()) { record in
                        VStack(alignment: .leading,spacing: 5) {
                            HStack {
                                Text(record.action).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(record.phase.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(record.detail).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,6)
                    }
                }
                CodePanel(code: """
                // 同一个会话接受按钮、手势、数据与生命周期事件。
                let session = MotionSession(recipe: MotionRecipes.unfold)
                session.send(.play)
                session.send(.targetChanged(newTarget))

                // 保存暂停点；Codable，可由宿主持久化到本机。
                let saved = session.bookmark()
                session.send(.leaveScene)
                session.restore(saved)                 // 默认不自动继续
                session.restore(saved, resume: true)   // 调用方明确要求继续

                // 这只恢复视觉状态。业务提交、媒体任务和网络请求
                // 不应该因为视觉恢复而再次发生。
                """)
            }.padding(20).frame(maxWidth: 950).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onAppear { session.send(.reduceMotion(reduced || localReduced)) }
        .onChange(of: reduced) { _,enabled in session.send(.reduceMotion(enabled || localReduced)) }
        .onChange(of: localReduced) { _,enabled in session.send(.reduceMotion(enabled || reduced)) }
        .onChange(of: cancellation) { _,value in
            var recipe = session.recipe; recipe.intent.cancellation = value
            session.updateIntent(recipe.intent)
        }
        .onChange(of: phase) { _,value in if value != .active { session.send(.pause) } }
        .onDisappear { session.send(.leaveScene); emptyComparison.detach() }
    }
    @ViewBuilder
    private var playbackButtons: some View {
        Button("从头播放") { session.send(.play) }.buttonStyle(.borderedProminent)
        Button("暂停") { session.send(.pause) }.buttonStyle(.bordered)
        Button("继续") { session.send(.resume) }.buttonStyle(.bordered)
    }
}

@MainActor
private struct SessionReadout: View {
    @ObservedObject var driver: MotionDriver<MotionPose>
    var body: some View {
        VStack(alignment: .leading,spacing: 6) {
            HStack {
                Text(driver.state.rawValue)
                Spacer(); Text("\(driver.elapsed,specifier: "%.2f") s")
            }
            Text("速度：X \(driver.velocity[0],specifier: "%.1f") / Y \(driver.velocity[1],specifier: "%.1f") pt/s")
        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }
}
