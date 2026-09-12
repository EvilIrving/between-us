import Foundation

/// 时间贝塞尔的横坐标是时间，纵坐标是进度。它不规定空间路线。
public struct CubicBezier: Codable, Equatable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = motionClamp(x1); self.y1 = y1; self.x2 = motionClamp(x2); self.y2 = y2
    }
    public static let easeInOut = Self(0.42, 0, 0.58, 1)
    public static let easeOut = Self(0, 0, 0.58, 1)
    public static let easeIn = Self(0.42, 0, 1, 1)
    public static let emphasized = Self(0.2, 0, 0.2, 1)
    private func polynomial(_ t: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1-t) * (1-t) * t * a + 3 * (1-t) * t * t * b + t*t*t
    }
    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1-t) * (1-t) * a + 6 * (1-t) * t * (b-a) + 3*t*t*(1-b)
    }
    public func parameter(at time: Double) -> Double {
        let x = motionClamp(time)
        if x == 0 || x == 1 { return x }
        var low = 0.0, high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if polynomial(middle, x1, x2) < x { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
    public func value(at time: Double) -> Double { polynomial(parameter(at: time), y1, y2) }
    public func slope(at time: Double) -> Double {
        // dx/ds 在端点可能为 0；用邻域斜率处理退化端点。
        let t = parameter(at: time)
        let dx = derivative(t, x1, x2)
        if abs(dx) > 1e-8 { return derivative(t, y1, y2) / dx }
        let low = max(0, time - 1e-5), high = min(1, time + 1e-5)
        return (value(at: high) - value(at: low)) / max(1e-8, high - low)
    }
}

public enum TimingCurve: Codable, Equatable, Sendable {
    case linear
    case bezier(CubicBezier)
    case smoothstep
    case smootherstep
    case sineInOut
    /// 离散阶梯是有意跳变，不能被描述为速度连续。
    case steps(Int)
    public func value(at time: Double) -> Double {
        let t = motionClamp(time)
        switch self {
        case .linear: return t
        case .bezier(let c): return c.value(at: t)
        case .smoothstep: return t*t*(3-2*t)
        case .smootherstep: return t*t*t*(t*(6*t-15)+10)
        case .sineInOut: return (1-cos(.pi*t))/2
        case .steps(let count): return floor(t*Double(max(1,count)))/Double(max(1,count))
        }
    }
    public func slope(at time: Double) -> Double {
        let t = motionClamp(time)
        switch self {
        case .linear: return 1
        case .bezier(let c): return c.slope(at: t)
        case .smoothstep: return 6*t*(1-t)
        case .smootherstep: return 30*t*t*(t-1)*(t-1)
        case .sineInOut: return .pi*sin(.pi*t)/2
        case .steps: return 0 // 跳点的速度不存在；返回值只表示平台区。
        }
    }
}

/// Hermite 用两端值与两端速度连接一段运动，适合固定结束时间的连续续接。
public struct HermiteSegment: Codable, Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var startVelocity: Double
    public var endVelocity: Double
    public var duration: Double
    public init(from: Double, to: Double, startVelocity: Double, endVelocity: Double = 0, duration: Double) {
        self.from = from; self.to = to; self.startVelocity = startVelocity
        self.endVelocity = endVelocity; self.duration = max(0.001, duration)
    }
    public func sample(at time: Double) -> (value: Double, velocity: Double) {
        let t = motionClamp(time / duration), t2 = t*t, t3 = t2*t
        let m0 = startVelocity * duration, m1 = endVelocity * duration
        let value = (2*t3-3*t2+1)*from + (t3-2*t2+t)*m0 + (-2*t3+3*t2)*to + (t3-t2)*m1
        let velocity = ((6*t2-6*t)*from + (3*t2-4*t+1)*m0 + (-6*t2+6*t)*to + (3*t2-2*t)*m1)/duration
        return (value, velocity)
    }
}
