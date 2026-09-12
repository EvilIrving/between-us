import Foundation
import Combine
import MotionCore

/// 产品运行时事件，不执行测试或业务提交。
public enum MotionSessionEvent: Sendable {
    case play
    case pause
    case resume
    case cancel
    case targetChanged(MotionPose)
    case beginDrag
    case dragChanged(MotionPose,velocity: MotionVector)
    case release(toward: MotionPose)
    case reduceMotion(Bool)
    case leaveScene
}

/// 保存“正在播放的这一段”，而不是假定当前段仍然等于原始配方。
/// 这样一段被 retarget 过的弹簧也能恢复到相同的采样时刻。
public enum MotionSessionLeg: Codable, Sendable {
    case recipe(MotionRecipe)
    case transition(from: MotionPose,to: MotionPose,velocity: MotionVector,model: MotionModel)
    public var trajectory: MotionTrajectory<MotionPose> {
        switch self {
        case .recipe(let recipe): return recipe.makeTrajectory()
        case .transition(let from,let to,let velocity,let model):
            return .transition(from: from,to: to,velocity: velocity,model: model)
        }
    }
}

public struct MotionSessionBookmark: Codable, Sendable {
    public var version = 1
    public var recipe: MotionRecipe
    public var leg: MotionSessionLeg?
    public var value: MotionPose
    public var velocity: MotionVector
    public var time: Double
    public var state: MotionPlaybackState
    public var playbackRate: Double
    public var savedAt: Date
    public init(recipe: MotionRecipe,leg: MotionSessionLeg?,value: MotionPose,velocity: MotionVector,
                time: Double,state: MotionPlaybackState,playbackRate: Double) {
        self.recipe = recipe; self.leg = leg; self.value = value; self.velocity = velocity
        self.time = time; self.state = state; self.playbackRate = playbackRate; savedAt = Date()
    }
}

public struct MotionSessionRecord: Identifiable, Sendable {
    public var id = UUID()
    public var time = Date()
    public var action: String
    public var detail: String
    public var phase: MotionPlaybackState
}

@MainActor
public final class MotionSession: ObservableObject {
    @Published public private(set) var recipe: MotionRecipe
    @Published public private(set) var note: String?
    @Published public private(set) var records: [MotionSessionRecord] = []
    public private(set) var activeLeg: MotionSessionLeg?
    public let driver: MotionDriver<MotionPose>
    private var stateSubscription: AnyCancellable?
    public init(recipe: MotionRecipe) {
        self.recipe = recipe; driver = MotionDriver(initial: recipe.initial)
        stateSubscription = driver.$state.removeDuplicates().sink { [weak self] phase in
            guard let self else { return }
            if phase == .completed { self.record("到达当前段末端","视觉播放结束；业务结果由宿主决定。",phase: phase) }
        }
    }
    public func replaceRecipe(_ value: MotionRecipe) {
        driver.detach(); recipe = value; activeLeg = nil
        driver.setImmediately(value.initial); note = nil
        record("载入配方",value.name)
    }
    public func updateIntent(_ intent: MotionIntent) {
        recipe.intent = intent
        record("更新行为约定","改变后续取消和减少动态策略，保留正在播放的轨迹。")
    }
    public func bookmark() -> MotionSessionBookmark {
        MotionSessionBookmark(recipe: recipe,leg: activeLeg,value: driver.value,velocity: driver.velocity,
                              time: driver.elapsed,state: driver.state,playbackRate: driver.playbackRate)
    }
    /// 默认停在保存的位置，用户明确要求时才继续。不会重建已经消失的手指接触。
    public func restore(_ bookmark: MotionSessionBookmark,resume: Bool = false) {
        guard bookmark.version == 1 else { note = "这个恢复记录的版本不受支持。"; return }
        driver.detach(); recipe = bookmark.recipe; activeLeg = bookmark.leg
        driver.playbackRate = max(0.01,bookmark.playbackRate)
        if driver.reduceMotion {
            applyReducedResult(); record("恢复现场",note ?? "减少动态：保留结果。")
            return
        }
        if bookmark.state == .dragging {
            driver.setImmediately(bookmark.value); activeLeg = nil
            note = "保存时正在拖动；恢复为静止显示，等待新的手势。"
        } else if let leg = bookmark.leg {
            driver.prepare(leg.trajectory,at: bookmark.time)
            if resume && bookmark.time < driver.duration { driver.resume() }
            note = bookmark.time >= driver.duration ? "已恢复到保存运动段的末端。" : resume ? "已从保存的运动段继续。" : "已恢复显示位置，尚未继续播放。"
        } else { driver.setImmediately(bookmark.value) }
        record("恢复现场",note ?? "恢复为静止状态。")
    }
    public func send(_ event: MotionSessionEvent) {
        switch event {
        case .play:
            if driver.reduceMotion { applyReducedResult(); return }
            let leg = MotionSessionLeg.recipe(recipe); activeLeg = leg; driver.play(leg.trajectory)
            record("播放",recipe.name)
        case .pause:
            driver.pause(); record("暂停","保留显示值、速度和当前时间。")
        case .resume:
            if driver.reduceMotion { applyReducedResult(); return }
            guard activeLeg != nil else { note = "没有可继续的运动段，请播放或提供新目标。"; return }
            driver.resume(); record("继续","沿保存的当前运动段继续。")
        case .cancel:
            switch recipe.intent.cancellation {
            case .returnToStart:
                transition(to: recipe.initial,model: .spring(recipe.spring),policy: .preserveVelocity)
                record("取消并返回","起点是配方起点，不是最近一次 retarget 的起点。")
            case .hold:
                driver.setImmediately(driver.value); activeLeg = nil
                record("取消并停留","清除旧运动段；继续操作需要新的目标。")
            case .finish:
                driver.finish(); record("取消并到结果","当前段直接到目标；不触发任何业务提交。")
            }
        case .targetChanged(let target):
            recipe.target = target
            if driver.reduceMotion {
                activeLeg = nil
                driver.setImmediately(recipe.intent.reducedBehavior == .returnToStart ? recipe.initial : target)
                return
            }
            if recipe.family == .path {
                // 保存真正的新起点，保证可序列化恢复。
                var legRecipe = recipe; legRecipe.initial = driver.value; legRecipe.delay = 0
                legRecipe.repeatCount = 1; legRecipe.autoreverses = false
                legRecipe.keyframeDocument = nil
                let leg = MotionSessionLeg.recipe(legRecipe); activeLeg = leg
                driver.play(leg.trajectory)
                note = "从显示状态重新生成路径与姿态过渡；不重放旧外观关键帧，也不保证切向速度自动匹配。"
            } else if recipe.family == .timeline {
                // 关键帧绝对值属于旧编排；数据新目标不能偷偷重放旧起点。
                transition(to: target,model: .hermite(duration: recipe.duration),policy: recipe.intent.interruption)
                note = "新目标以 Hermite 续接；没有重放旧关键帧。需要新阶段时应换入新配方。"
            } else {
                transition(to: target,model: recipe.model,policy: recipe.intent.interruption)
                note = recipe.family == .tween ? "保留显示位置；时间曲线不保证初速度匹配。" : "从当前显示状态续接。"
            }
            record("目标变化",note ?? "目标已更新。")
        case .beginDrag:
            driver.beginDragging(); activeLeg = nil; record("开始拖动","取得当前显示值的控制权。")
        case .dragChanged(let value,let velocity):
            driver.updateDragging(value: value,velocity: velocity)
        case .release(let target):
            transition(to: target,model: .spring(recipe.spring),policy: .preserveVelocity)
            record("手势释放","显示速度进入弹簧。")
        case .reduceMotion(let enabled):
            if enabled { driver.pause() }
            driver.reduceMotion = enabled
            if enabled { applyReducedResult() }
            record("减少动态",enabled ? "直接保留产品结果。" : "之后的新动作允许运动。")
        case .leaveScene:
            driver.detach(); record("离开场景","时钟订阅已释放，当前数据仍可保存。")
        }
    }
    private func transition(to target: MotionPose,model: MotionModel,policy: MotionInterruption) {
        if driver.reduceMotion {
            driver.setImmediately(recipe.intent.reducedBehavior == .returnToStart ? recipe.initial : target)
            activeLeg = nil; return
        }
        let initial = policy == .restart ? recipe.initial : driver.value
        let velocity = policy == .preserveVelocity ? driver.velocity : MotionVector(repeating: 0,count: 10)
        let leg = MotionSessionLeg.transition(from: initial,to: target,velocity: velocity,model: model)
        activeLeg = leg; driver.play(leg.trajectory)
    }
    private func applyReducedResult() {
        let value = recipe.intent.reducedBehavior == .returnToStart ? recipe.initial : (activeLeg?.trajectory.endValue ?? recipe.makeTrajectory().endValue)
        driver.setImmediately(value); activeLeg = nil
        note = recipe.intent.reducedBehavior == .returnToStart ? "减少动态：回到起点。" : "减少动态：直接到最终状态。"
    }
    private func record(_ action: String,_ detail: String,phase: MotionPlaybackState? = nil) {
        records.append(MotionSessionRecord(action: action,detail: detail,phase: phase ?? driver.state))
        if records.count > 40 { records.removeFirst(records.count-40) }
    }
}
