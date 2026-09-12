import Foundation

public struct MotionTrack: Sendable {
    private struct Segment: Sendable {
        var start: Double
        var motion: MotionTrajectory<Double>
    }
    public let initial: Double
    public private(set) var duration: Double = 0
    public private(set) var endValue: Double
    private var segments: [Segment] = []
    public init(initial: Double) { self.initial = initial; endValue = initial }
    public func then(to target: Double, model: MotionModel, after delay: Double = 0,
                     velocity: Double = 0) -> Self {
        var result = self
        let motion = MotionTrajectory<Double>.transition(from: endValue,to: target,
                        velocity: MotionVector([velocity]),model: model)
        result.segments.append(Segment(start: duration+max(0,delay),motion: motion))
        result.duration += max(0,delay)+motion.duration
        result.endValue = motion.endValue
        return result
    }
    public func hold(_ seconds: Double) -> Self {
        then(to: endValue,model: .tween(duration: max(0.001,seconds),curve: .linear))
    }
    public func sample(at time: Double) -> MotionSample<Double> {
        var value = initial
        for segment in segments {
            if time < segment.start { return MotionSample(value: value,velocity: MotionVector([0]),isSettled: false) }
            if time < segment.start+segment.motion.duration { return segment.motion.sample(at: time-segment.start) }
            value = segment.motion.endValue
        }
        return .resting(value)
    }
}

/// 各通道独立排时间，同时采样。透明度可以无回弹，位置可以保留弹性。
public struct PoseTimeline: Sendable {
    public var initial: MotionPose
    public var tracks: [MotionChannel: MotionTrack]
    public init(initial: MotionPose,tracks: [MotionChannel: MotionTrack]) { self.initial = initial; self.tracks = tracks }
    public var duration: Double { tracks.values.map(\.duration).max() ?? 0 }
    public var trajectory: MotionTrajectory<MotionPose> {
        let timeline = self
        var end = initial
        for (channel,track) in tracks { end[channel] = track.endValue }
        return MotionTrajectory(duration: duration,start: initial,end: end) { time in
            var pose = timeline.initial, velocity = MotionVector(repeating: 0,count: 10)
            for (channel,track) in timeline.tracks {
                let sample = track.sample(at: time)
                pose[channel] = sample.value; velocity[channel.index] = sample.velocity[0]
            }
            return MotionSample(value: pose,velocity: velocity,isSettled: time >= timeline.duration)
        }
    }
}

/// 约束作用在显示值的边界。它会改变速度；硬裁剪不能承诺 C1 连续。
public struct ScalarConstraint: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case clamp, rubberBand }
    public var lower: Double
    public var upper: Double
    public var mode: Mode
    public var resistance: Double
    public init(_ range: ClosedRange<Double>,mode: Mode = .clamp,resistance: Double = 80) {
        lower = range.lowerBound; upper = range.upperBound; self.mode = mode; self.resistance = resistance
    }
    public func value(_ x: Double) -> Double {
        switch mode {
        case .clamp: return motionClamp(x,lower...upper)
        case .rubberBand: return RubberBand(limit: resistance).map(x,bounds: lower...upper)
        }
    }
    public func slope(_ x: Double) -> Double {
        if (lower...upper).contains(x) { return 1 }
        switch mode {
        case .clamp: return 0
        case .rubberBand: return RubberBand(limit: resistance).derivative(x < lower ? x-lower : x-upper)
        }
    }
}

extension MotionTrajectory where Value == Double {
    public func constrained(_ constraint: ScalarConstraint) -> Self {
        map(constraint.value,velocity: { value,velocity in velocity*constraint.slope(value) })
    }
}

extension MotionTrajectory where Value == MotionPose {
    /// 通道级组合：例如 base 管路径的 x/y，另一条时间轴管 scale 与 opacity。
    /// 每个通道只由一个来源写入，避免两个动画驱动器竞争同一属性。
    public func overriding(_ channels: Set<MotionChannel>,with overlay: MotionTrajectory<MotionPose>) -> MotionTrajectory<MotionPose> {
        guard !channels.isEmpty else { return self }
        let base = self
        var start = startValue,end = endValue
        for channel in channels {
            start[channel] = overlay.startValue[channel]
            end[channel] = overlay.endValue[channel]
        }
        let total = max(duration,overlay.duration)
        return MotionTrajectory(duration: total,start: start,end: end) { time in
            var result = base.sample(at: time)
            let addition = overlay.sample(at: time)
            for channel in channels {
                result.value[channel] = addition.value[channel]
                result.velocity[channel.index] = addition.velocity[channel.index]
            }
            result.isSettled = time >= total
            return result
        }
    }
}
