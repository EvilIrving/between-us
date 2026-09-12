import Foundation

public enum KeyframeInterpolation: Codable, Equatable, Sendable {
    case linear
    case bezier(CubicBezier)
    case curve(TimingCurve)
    case hermite
    case hold
}

/// 时间是全局秒数；value 使用该通道单位；tangent 为对应单位/s。
/// interpolation 描述“上一帧到这一帧”的区间。
public struct MotionKeyframe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: Double
    public var value: Double
    public var tangent: Double
    public var interpolation: KeyframeInterpolation
    public init(id: UUID = UUID(),time: Double,value: Double,tangent: Double = 0,
                interpolation: KeyframeInterpolation = .bezier(.easeInOut)) {
        self.id = id; self.time = time; self.value = value; self.tangent = tangent; self.interpolation = interpolation
    }
}

public struct KeyframeLane: Codable, Equatable, Identifiable, Sendable {
    public var channel: MotionChannel
    public var keyframes: [MotionKeyframe]
    public var isEnabled: Bool
    public var id: String { channel.rawValue }
    public init(channel: MotionChannel,keyframes: [MotionKeyframe],isEnabled: Bool = true) {
        self.channel = channel; self.keyframes = keyframes.sorted { $0.time < $1.time }; self.isEnabled = isEnabled
    }
    public var duration: Double { keyframes.last?.time ?? 0 }
    public func sample(at time: Double,fallback: Double) -> MotionSample<Double> {
        guard let first = keyframes.first,let last = keyframes.last else { return .resting(fallback) }
        if time < first.time { return MotionSample(value: fallback,velocity: MotionVector([0]),isSettled: false) }
        if time >= last.time { return .resting(last.value) }
        for (a,b) in zip(keyframes,keyframes.dropFirst()) where time >= a.time && time < b.time {
            let duration = max(1e-6,b.time-a.time),local = time-a.time,q = local/duration
            switch b.interpolation {
            case .hold: return MotionSample(value: a.value,velocity: MotionVector([0]))
            case .linear: return MotionSample(value: a.value+(b.value-a.value)*q,velocity: MotionVector([(b.value-a.value)/duration]))
            case .bezier(let curve):
                return MotionSample(value: a.value+(b.value-a.value)*curve.value(at: q),
                                    velocity: MotionVector([(b.value-a.value)*curve.slope(at: q)/duration]))
            case .curve(let curve):
                return MotionSample(value: a.value+(b.value-a.value)*curve.value(at: q),
                                    velocity: MotionVector([(b.value-a.value)*curve.slope(at: q)/duration]))
            case .hermite:
                let segment = HermiteSegment(from: a.value,to: b.value,startVelocity: a.tangent,endVelocity: b.tangent,duration: duration)
                let state = segment.sample(at: local)
                return MotionSample(value: state.value,velocity: MotionVector([state.velocity]))
            }
        }
        return .resting(first.value)
    }
    public mutating func move(id: UUID,to time: Double,value: Double? = nil,snap: Double? = nil) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        let proposed = snap.map { (time/$0).rounded()*$0 } ?? time
        // 关键帧不允许穿过邻居；至少留 10ms，避免零长度区间。
        let lower = index == 0 ? 0 : keyframes[index-1].time+0.01
        let upper = index+1 < keyframes.count ? keyframes[index+1].time-0.01 : max(lower,proposed)
        keyframes[index].time = motionClamp(proposed,lower...max(lower,upper))
        if let value { keyframes[index].value = value }
    }
    @discardableResult
    public mutating func insert(at time: Double,fallback: Double) -> UUID {
        if let existing = keyframes.first(where: { abs($0.time-time)<0.01 }) { return existing.id }
        let sample = sample(at: time,fallback: fallback)
        let key = MotionKeyframe(time: max(0,time),value: sample.value,tangent: sample.velocity[0],interpolation: .hermite)
        keyframes.append(key); keyframes.sort { $0.time < $1.time }
        return key.id
    }
    public mutating func remove(id: UUID) {
        guard keyframes.count > 2 else { return }
        keyframes.removeAll { $0.id == id }
    }
    /// 调整时间必须同时缩放速度；否则 Hermite 会改变原来的形状。
    public mutating func retime(scale: Double,offset: Double = 0) {
        let factor = max(0.05,scale)
        let earliest = keyframes.first?.time ?? 0
        let shift = max(-earliest*factor,offset)
        for index in keyframes.indices {
            keyframes[index].time = keyframes[index].time*factor+shift
            keyframes[index].tangent /= factor
        }
    }
}

public struct KeyframeDocument: Codable, Equatable, Sendable {
    public var lanes: [KeyframeLane]
    public init(lanes: [KeyframeLane]) { self.lanes = lanes }
    public var duration: Double { lanes.filter(\.isEnabled).map(\.duration).max() ?? 0 }
    public mutating func retime(scale: Double) {
        for index in lanes.indices { lanes[index].retime(scale: scale) }
    }
    public func trajectory(initial: MotionPose) -> MotionTrajectory<MotionPose> {
        let document = self
        var endpoint = initial,start = initial
        for lane in lanes where lane.isEnabled {
            endpoint[lane.channel] = lane.keyframes.last?.value ?? initial[lane.channel]
            if let first = lane.keyframes.first,first.time == 0 { start[lane.channel] = first.value }
        }
        return MotionTrajectory(duration: duration,start: start,end: endpoint) { time in
            var pose = initial,velocity = MotionVector(repeating: 0,count: 10)
            for lane in document.lanes where lane.isEnabled {
                let sample = lane.sample(at: time,fallback: initial[lane.channel])
                pose[lane.channel] = sample.value; velocity[lane.channel.index] = sample.velocity[0]
            }
            return MotionSample(value: pose,velocity: velocity,isSettled: time >= document.duration)
        }
    }
    public static func migrating(tracks: [RecipeTrack],initial: MotionPose,target: MotionPose) -> Self {
        Self(lanes: tracks.map { track in
            let interpolation: KeyframeInterpolation
            if case .bezier(let curve) = track.curve { interpolation = .bezier(curve) }
            else { interpolation = .curve(track.curve) }
            var frames = [MotionKeyframe(time: 0,value: initial[track.channel])]
            if track.startTime > 0 {
                frames.append(MotionKeyframe(time: track.startTime,value: initial[track.channel],interpolation: .hold))
            }
            frames.append(MotionKeyframe(time: track.startTime+track.duration,value: target[track.channel],interpolation: interpolation))
            return KeyframeLane(channel: track.channel,keyframes: frames)
        })
    }
}
