import Foundation
import Combine
import MotionCore

public enum MotionPlaybackState: String, Codable, Sendable { case idle, playing, paused, dragging, completed }

/// 持有当前显示值，不把 target 冒充为正在显示的位置。
/// 所有模型使用同一时钟；任意数据更新都可以 animate(to:model:)。
@MainActor
public final class MotionDriver<Value: MotionValue>: ObservableObject {
    @Published public private(set) var sample: MotionSample<Value>
    @Published public private(set) var state: MotionPlaybackState = .idle
    @Published public private(set) var elapsed: Double = 0
    public private(set) var trajectory: MotionTrajectory<Value>?
    public var playbackRate: Double = 1
    public var reduceMotion = false {
        didSet { if reduceMotion && state == .playing { finish() } }
    }
    public var onCompletion: (() -> Void)?
    private var token: UUID?
    private let clock: MotionClock
    public var value: Value { sample.value }
    public var velocity: MotionVector { sample.velocity }
    public var duration: Double { trajectory?.duration ?? 0 }
    public init(initial: Value,clock: MotionClock? = nil) { sample = .resting(initial); self.clock = clock ?? .shared }

    deinit {
        let cleanupClock = clock
        let cleanupToken = token
        if let cleanupToken {
            Task { @MainActor in cleanupClock.remove(cleanupToken) }
        }
    }

    public func play(_ trajectory: MotionTrajectory<Value>) {
        stopClock()
        self.trajectory = trajectory; elapsed = 0; sample = trajectory.sample(at: 0)
        if reduceMotion || trajectory.duration <= 0 { finish(); return }
        state = .playing; startClock()
    }
    /// 安装一个运动段并停在指定时刻，不短暂播放开头，也不发完成回调。
    public func prepare(_ trajectory: MotionTrajectory<Value>,at time: Double = 0) {
        stopClock(); self.trajectory = trajectory
        elapsed = motionClamp(time,0...trajectory.duration)
        sample = trajectory.sample(at: elapsed)
        state = .paused
    }
    public func animate(to target: Value,model: MotionModel,interruption: MotionInterruption = .preserveVelocity) {
        let start: Value
        let speed: MotionVector
        switch interruption {
        case .preserveVelocity: start = value; speed = velocity
        case .preservePosition: start = value; speed = MotionVector(repeating: 0,count: value.motionVector.count)
        case .restart: start = trajectory?.startValue ?? value; speed = MotionVector(repeating: 0,count: value.motionVector.count)
        }
        play(.transition(from: start,to: target,velocity: speed,model: model))
    }
    public func pause() {
        guard state == .playing else { return }
        stopClock(); state = .paused
    }
    public func resume() {
        guard state == .paused, trajectory != nil else { return }
        if reduceMotion { finish(); return }
        state = .playing; startClock()
    }
    public func seek(to time: Double) {
        guard let trajectory else { return }
        stopClock(); elapsed = motionClamp(time,0...trajectory.duration)
        sample = trajectory.sample(at: elapsed); state = .paused
    }
    public func beginDragging() {
        stopClock(); state = .dragging
        // 保留呈现中的值，接下来由手势写入，不重置到旧目标。
    }
    public func updateDragging(value: Value,velocity: MotionVector? = nil) {
        stopClock(); sample = MotionSample(value: value,velocity: velocity ?? MotionVector(repeating: 0,count: value.motionVector.count))
        state = .dragging
    }
    public func setImmediately(_ value: Value) {
        stopClock(); trajectory = nil; elapsed = 0; sample = .resting(value); state = .idle
    }
    public func cancel(_ behavior: MotionCancellation = .hold,returnModel: MotionModel = .spring(.init())) {
        switch behavior {
        case .hold:
            stopClock(); sample = .resting(value); state = .paused
        case .finish: finish()
        case .returnToStart:
            guard let start = trajectory?.startValue else { setImmediately(value); return }
            animate(to: start,model: returnModel)
        }
    }
    public func finish(preserveEndVelocity: Bool = false) {
        stopClock()
        guard let trajectory else { return }
        elapsed = trajectory.duration
        sample = preserveEndVelocity ? trajectory.sample(at: trajectory.duration) : .resting(trajectory.endValue)
        state = .completed
        let callback = onCompletion
        callback?()
    }
    /// 页面退出时显式释放订阅；不依赖析构或弱引用来停止全局时钟。
    public func detach() { stopClock(); onCompletion = nil; if state == .playing { state = .paused } }
    private func startClock() {
        token = clock.add { [weak self] delta in self?.advance(delta) }
    }
    private func stopClock() {
        if let token { clock.remove(token); self.token = nil }
    }
    private func advance(_ delta: Double) {
        guard let trajectory, state == .playing else { return }
        elapsed = min(trajectory.duration,elapsed+delta*max(0.01,playbackRate))
        sample = trajectory.sample(at: elapsed)
        // 时间轴中的平台区也可能瞬时稳定；只在全局末端发完成。
        if elapsed >= trajectory.duration { finish(preserveEndVelocity: true) }
    }
}
