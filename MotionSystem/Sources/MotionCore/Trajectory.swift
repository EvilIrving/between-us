import Foundation

public enum MotionModel: Codable, Equatable, Sendable {
    case tween(duration: Double, curve: TimingCurve)
    case spring(SpringConfiguration)
    case hermite(duration: Double)
    case decay(DecayConfiguration)
}

/// 纯采样器：不给 UI 写状态，不依赖帧率，任意时间可重复采样。
/// endValue 是稳定后的目标；duration 是有限播放窗口，不是所有模型的物理固有时长。
public struct MotionTrajectory<Value: MotionValue>: Sendable {
    public let duration: Double
    public let startValue: Value
    public let endValue: Value
    private let sampler: @Sendable (Double) -> MotionSample<Value>
    public init(duration: Double, start: Value, end: Value,
                sample: @escaping @Sendable (Double) -> MotionSample<Value>) {
        self.duration = max(0,duration); startValue = start; endValue = end; sampler = sample
    }
    public func sample(at time: Double) -> MotionSample<Value> { sampler(max(0,time)) }

    public static func transition(from: Value, to: Value, velocity: MotionVector? = nil, model: MotionModel) -> Self {
        let a = from.motionVector, b = to.motionVector
        precondition(a.count == b.count, "From and to must use the same dimensions")
        let v = velocity ?? MotionVector(repeating: 0,count: a.count)
        precondition(v.count == a.count, "Velocity units and dimensions must match the animated value")
        switch model {
        case .tween(let duration, let curve):
            let d = max(0.001,duration)
            return Self(duration: d,start: from,end: to) { time in
                if time >= d { return .resting(to) }
                let t = time/d
                return MotionSample(value: Value(motionVector: .lerp(a,b,curve.value(at: t))),
                                    velocity: (b-a)*(curve.slope(at: t)/d))
            }
        case .hermite(let duration):
            let d = max(0.001,duration)
            let segments = (0..<a.count).map { HermiteSegment(from: a[$0],to: b[$0],startVelocity: v[$0],duration: d) }
            return Self(duration: d,start: from,end: to) { time in
                if time >= d { return .resting(to) }
                let states = segments.map { $0.sample(at: time) }
                return MotionSample(value: Value(motionVector: MotionVector(states.map(\.value))),
                                    velocity: MotionVector(states.map(\.velocity)))
            }
        case .spring(let config):
            // 各维归一化，避免 300pt 位移掩盖 0...1 透明度通道的未收敛。
            let scales = (0..<a.count).map { max(1e-6,max(abs(b[$0]-a[$0]),abs(v[$0])/config.angularFrequency)) }
            let d = config.suggestedWindow
            return Self(duration: d,start: from,end: to) { time in
                if time >= d { return .resting(to) }
                let states = (0..<a.count).map { config.sample(time: time,from: a[$0],to: b[$0],velocity: v[$0]) }
                let settled = (0..<a.count).allSatisfy {
                    abs(states[$0].value-b[$0])/scales[$0] < config.relativeTolerance &&
                    abs(states[$0].velocity)/(scales[$0]*config.angularFrequency) < config.relativeTolerance
                }
                return MotionSample(value: Value(motionVector: MotionVector(states.map(\.value))),
                                    velocity: MotionVector(states.map(\.velocity)),isSettled: settled)
            }
        case .decay(let config):
            let end = Value(motionVector: a+v/config.rate)
            let d = config.duration(initialSpeed: v.maximumMagnitude)
            return Self(duration: d,start: from,end: end) { time in
                if time >= d { return .resting(end) }
                return MotionSample(value: Value(motionVector: a+v*((1-exp(-config.rate*time))/config.rate)),
                                    velocity: v*exp(-config.rate*time))
            }
        }
    }

    public func delayed(by delay: Double) -> Self {
        let wait = max(0,delay), original = self
        return Self(duration: wait+duration,start: startValue,end: endValue) { time in
            if time < wait {
                var resting = MotionSample.resting(original.startValue)
                resting.isSettled = false // 尚未开始不能触发完成。
                return resting
            }
            return original.sample(at: time-wait)
        }
    }

    /// 播放速率改变时间导数。速度也必须乘 rate，不能只改位置时间。
    public func speed(_ rate: Double) -> Self {
        let factor = max(0.001,rate), original = self
        return Self(duration: duration/factor,start: startValue,end: endValue) { time in
            var sample = original.sample(at: time*factor)
            sample.velocity = sample.velocity*factor
            return sample
        }
    }

    public func reversed() -> Self {
        let original = self
        return Self(duration: duration,start: endValue,end: startValue) { time in
            if time >= original.duration { return .resting(original.startValue) }
            var result = original.sample(at: original.duration-time)
            result.velocity = -result.velocity
            result.isSettled = false
            return result
        }
    }

    /// 有限重复。非往返重复会有意从终点跳回起点；平滑循环需保证接缝值与速度一致。
    public func repeated(_ count: Int, autoreverses: Bool = true) -> Self {
        let original = self, cycles = max(1,count), leg = max(0.001,duration)
        let total = leg*Double(cycles)*(autoreverses ? 2 : 1)
        let end = autoreverses ? startValue : endValue
        return Self(duration: total,start: startValue,end: end) { time in
            if time >= total { return .resting(end) }
            let index = Int(time/leg), local = time-Double(index)*leg
            if autoreverses && index%2 == 1 { return original.reversed().sample(at: local) }
            var sample = original.sample(at: local)
            sample.isSettled = false
            return sample
        }
    }

    /// 把数学值映射到业务数据。速度使用方向导数估计；精确导数用另一重载。
    public func map<Output: MotionValue>(_ transform: @escaping @Sendable (Value) -> Output) -> MotionTrajectory<Output> {
        map(transform, velocity: { value, velocity in
            let epsilon = 1e-5
            let x = value.motionVector
            let plus = transform(Value(motionVector: x+velocity*epsilon)).motionVector
            let minus = transform(Value(motionVector: x-velocity*epsilon)).motionVector
            return (plus-minus)/(2*epsilon)
        })
    }
    public func map<Output: MotionValue>(_ transform: @escaping @Sendable (Value) -> Output,
                velocity derivative: @escaping @Sendable (Value,MotionVector) -> MotionVector) -> MotionTrajectory<Output> {
        let original = self
        return MotionTrajectory<Output>(duration: duration,start: transform(startValue),end: transform(endValue)) { time in
            let s = original.sample(at: time)
            return MotionSample(value: transform(s.value),velocity: derivative(s.value,s.velocity),isSettled: s.isSettled)
        }
    }

    /// 补上静止尾部，使对照轨迹共享一个全局时钟窗口。
    public func padded(to totalDuration: Double) -> Self {
        let original = self
        return Self(duration: max(duration,totalDuration),start: startValue,end: endValue) { time in
            if time >= original.duration { return .resting(original.endValue) }
            var result = original.sample(at: time)
            result.isSettled = false
            return result
        }
    }
}
