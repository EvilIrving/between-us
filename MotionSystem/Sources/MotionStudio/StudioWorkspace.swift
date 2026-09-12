import SwiftUI
import Combine
import UniformTypeIdentifiers
import MotionCore
import MotionSwiftUI

@MainActor
final class StudioWorkspace: ObservableObject {
    @Published var recipe = MotionRecipes.quietSpring
    @Published var baseline: MotionRecipe?
    @Published var selectedChannel: MotionChannel = .x
    @Published var showPath = true
    @Published var showGhosts = false
    @Published var showVelocity = false
    @Published var playbackRate = 1.0
    @Published var followEdits = true
    @Published var notice: String?
    @Published var library: [MotionRecipe] = []
    @Published var exportedCode = ""
    @Published private(set) var motionRevision = 0
    @Published private(set) var undoTitle: String?
    @Published private(set) var redoTitle: String?
    private var undoItems: [(String,MotionRecipe)] = []
    private var redoItems: [(String,MotionRecipe)] = []
    private var pendingEdit: (String,MotionRecipe)?
    let driver = MotionDriver(initial: MotionRecipes.quietSpring.initial)
    let comparison = MotionDriver(initial: MotionRecipes.quietSpring.initial)
    private let libraryKey = "MotionStudio.saved-recipes.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: libraryKey),
           let stored = try? JSONDecoder().decode([MotionRecipe].self,from: data) { library = stored }
        rebuild()
    }
    var source: MotionTrajectory<MotionPose> { driver.trajectory ?? recipe.makeTrajectory() }
    func beginEdit(_ title: String) {
        if pendingEdit == nil { pendingEdit = (title,recipe); pause() }
    }
    func finishEdit() {
        guard let edit = pendingEdit else { return }
        pendingEdit = nil
        guard edit.1 != recipe else { return }
        undoItems.append(edit)
        if undoItems.count > 100 { undoItems.removeFirst() }
        redoItems.removeAll(); updateHistoryLabels()
    }
    func edit(_ title: String,_ change: (inout MotionRecipe) -> Void) {
        finishEdit()
        beginEdit(title)
        var changed = recipe; change(&changed); recipe = changed
        rebuild(); finishEdit()
    }
    func updateContinuousEdit(_ change: (inout MotionRecipe) -> Void) {
        var changed = recipe; change(&changed); recipe = changed
        rebuild()
    }
    func undo() {
        finishEdit()
        guard let item = undoItems.popLast() else { return }
        redoItems.append((item.0,recipe)); recipe = item.1; rebuild(); updateHistoryLabels()
        notice = "已撤销：\(item.0)"
    }
    func redo() {
        finishEdit()
        guard let item = redoItems.popLast() else { return }
        undoItems.append((item.0,recipe)); recipe = item.1; rebuild(); updateHistoryLabels()
        notice = "已重做：\(item.0)"
    }
    private func updateHistoryLabels() { undoTitle = undoItems.last?.0; redoTitle = redoItems.last?.0 }
    func load(_ value: MotionRecipe) {
        finishEdit()
        undoItems.append(("载入配方",recipe)); redoItems.removeAll(); updateHistoryLabels()
        recipe = value; baseline = nil; comparison.detach(); rebuild(); notice = "已载入「\(value.name)」"
    }
    private func launchPair() {
        let current = recipe.makeTrajectory(), saved = baseline?.makeTrajectory()
        let total = max(current.duration,saved?.duration ?? 0)
        driver.playbackRate = playbackRate; comparison.playbackRate = playbackRate
        driver.play(current.padded(to: total))
        if let saved { comparison.play(saved.padded(to: total)) }
        motionRevision += 1
    }
    func rebuild() {
        let current = recipe.makeTrajectory(),saved = baseline?.makeTrajectory()
        let total = max(current.duration,saved?.duration ?? 0)
        driver.prepare(current.padded(to: total))
        if let saved { comparison.prepare(saved.padded(to: total)) }
        motionRevision += 1
        updateExport()
    }
    func editApplied() {
        let wasPlaying = driver.state == .playing
        if followEdits && wasPlaying && [.spring,.hermite,.tween,.decay].contains(recipe.family) {
            driver.animate(to: recipe.target,model: recipe.model,interruption: recipe.intent.interruption)
            notice = recipe.family == .tween ? "已接住位置；普通时间曲线不保证速度连续。" : "参数已应用到当前运动。"
            comparison.pause(); motionRevision += 1
        } else { rebuild() }
        updateExport()
    }
    func play() {
        if driver.reduceMotion && recipe.intent.reducedBehavior == .returnToStart {
            driver.setImmediately(recipe.initial)
            comparison.setImmediately(baseline?.initial ?? recipe.initial)
            notice = "减少动态：保留起点状态。"
            return
        }
        driver.playbackRate = playbackRate; comparison.playbackRate = playbackRate
        if driver.state == .paused && driver.elapsed > 0 && driver.elapsed < driver.duration {
            driver.resume(); comparison.resume()
        } else { launchPair() }
    }
    func reverse() {
        comparison.pause()
        if [.spring,.hermite,.tween,.decay].contains(recipe.family) {
            let model: MotionModel = recipe.family == .decay ? .spring(recipe.spring) : recipe.model
            driver.animate(to: recipe.initial,model: model,interruption: recipe.intent.interruption)
        } else {
            let original = source, time = min(driver.elapsed,original.duration)
            let from = original.sample(at: time).value
            let reversed = MotionTrajectory<MotionPose>(duration: time,start: from,end: original.startValue) { t in
                var result = original.sample(at: max(0,time-t)); result.velocity = -result.velocity
                result.isSettled = t >= time
                return result
            }
            driver.play(reversed)
            notice = "沿当前时间线返回；换向处可能有速度突变。需要惯性转向时使用弹簧模型。"
        }
        motionRevision += 1
    }
    func pause() { driver.pause(); comparison.pause() }
    func seek(_ time: Double) { driver.seek(to: time); comparison.seek(to: time) }
    func cancel() {
        comparison.pause()
        if recipe.intent.cancellation == .returnToStart { driver.animate(to: recipe.initial,model: .spring(recipe.spring)) }
        else { driver.cancel(recipe.intent.cancellation) }
        motionRevision += 1
    }
    func reduce(_ enabled: Bool) {
        if enabled && recipe.intent.reducedBehavior == .returnToStart {
            driver.setImmediately(recipe.initial); comparison.setImmediately(baseline?.initial ?? recipe.initial)
        }
        driver.reduceMotion = enabled; comparison.reduceMotion = enabled
    }
    func saveBaseline() { baseline = recipe; rebuild(); notice = "已保存对照。两组配方共用时间刻度。" }
    func saveRecipe() {
        var copy = recipe; copy.id = UUID().uuidString
        library.append(copy)
        persistLibrary(); notice = "已保存到本机配方库。"
    }
    func deleteRecipe(_ id: String) { library.removeAll { $0.id == id }; persistLibrary() }
    private func persistLibrary() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(library),forKey: libraryKey) }
        catch { notice = "配方未保存：\(error.localizedDescription)" }
    }
    func importRecipe(_ data: Data) {
        do { load(try MotionRecipe.decode(data)) }
        catch { notice = error.localizedDescription }
    }
    func updateExport() {
        do { exportedCode = try SwiftRecipeExporter.source(for: recipe) }
        catch { exportedCode = "// 不能导出：\(error.localizedDescription)" }
    }
}

struct RecipeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
