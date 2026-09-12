import Foundation

public struct SpringConfiguration: Codable, Equatable, Sendable {
    public var response: Double
    public var dampingRatio: Double
    public var mass: Double
    /// 容差是相对于各通道此次行程归一化后的值。
    public var relativeTolerance: Double
    public init(response: Double = 0.55, dampingRatio: Double = 0.9, mass: Double = 1, relativeTolerance: Double = 0.0001) {
        self.response = max(0.02,response); self.dampingRatio = max(0.01,dampingRatio)
        self.mass = max(0.001,mass); self.relativeTolerance = max(1e-8,relativeTolerance)
    }
    public init(stiffness: Double, damping: Double, mass: Double = 1) {
        let m = max(0.001,mass), k = max(0.001,stiffness)
        self.init(response: 2 * .pi / sqrt(k/m), dampingRatio: max(0.001,damping)/(2*sqrt(k*m)), mass: m)
    }
    public var angularFrequency: Double { 2 * .pi / max(0.02,response) }
    public var stiffness: Double { mass * angularFrequency * angularFrequency }
    public var damping: Double { 2 * dampingRatio * sqrt(stiffness * mass) }
    public var suggestedWindow: Double {
        let z = max(0.01,dampingRatio), w = angularFrequency
        let rate = z <= 1 ? z*w : w/(z+sqrt(z*z-1))
        return max(0.1, -log(relativeTolerance)*1.8/rate)
    }
    public func sample(time: Double, from: Double, to: Double, velocity: Double = 0) -> (value: Double, velocity: Double) {
        let t = max(0,time), w = angularFrequency, z = max(0.01,dampingRatio), a = from-to
        if abs(z-1) < 1e-5 {
            let b = velocity+w*a, e = exp(-w*t)
            return (to+(a+b*t)*e, (b-w*(a+b*t))*e)
        }
        if z < 1 {
            let wd = w*sqrt(1-z*z), b = (velocity+z*w*a)/wd, e = exp(-z*w*t)
            let c = cos(wd*t), s = sin(wd*t), displacement = a*c+b*s
            return (to+e*displacement, e*(-z*w*displacement-a*wd*s+b*wd*c))
        }
        let root = sqrt(z*z-1), r1 = -w/(z+root), r2 = -w*(z+root)
        let c1 = (velocity-r2*a)/(r1-r2), c2 = a-c1
        return (to+c1*exp(r1*t)+c2*exp(r2*t), c1*r1*exp(r1*t)+c2*r2*exp(r2*t))
    }
}

/// v(t)=v₀ exp(-λt)。λ 单位 1/s，不依赖 60Hz 或 120Hz。
public struct DecayConfiguration: Codable, Equatable, Sendable {
    public var rate: Double
    public var velocityTolerance: Double
    public init(rate: Double = 5, velocityTolerance: Double = 0.1) {
        self.rate = max(0.01,rate); self.velocityTolerance = max(1e-8,velocityTolerance)
    }
    public func displacement(velocity: Double, time: Double) -> Double {
        velocity * (1-exp(-rate*max(0,time))) / rate
    }
    public func velocity(_ initial: Double, time: Double) -> Double { initial*exp(-rate*max(0,time)) }
    public func projectedDisplacement(velocity: Double) -> Double { velocity/rate }
    public func duration(initialSpeed: Double) -> Double {
        max(0,log(max(velocityTolerance,initialSpeed)/velocityTolerance)/rate)
    }
}

public struct RubberBand: Codable, Equatable, Sendable {
    public var limit: Double
    public init(limit: Double = 80) { self.limit = max(0.001,limit) }
    public func displacement(_ distance: Double) -> Double {
        let sign = distance < 0 ? -1.0 : 1.0, magnitude = abs(distance)
        return sign * limit * magnitude / (limit+magnitude)
    }
    public func derivative(_ distance: Double) -> Double { pow(limit/(limit+abs(distance)),2) }
    public func inverse(_ display: Double) -> Double {
        let magnitude = min(abs(display),limit-1e-6)
        return (display < 0 ? -1 : 1)*limit*magnitude/(limit-magnitude)
    }
    public func map(_ position: Double, bounds: ClosedRange<Double>) -> Double {
        if position < bounds.lowerBound { return bounds.lowerBound+displacement(position-bounds.lowerBound) }
        if position > bounds.upperBound { return bounds.upperBound+displacement(position-bounds.upperBound) }
        return position
    }
    public func rawPosition(_ display: Double, bounds: ClosedRange<Double>) -> Double {
        if display < bounds.lowerBound { return bounds.lowerBound+inverse(display-bounds.lowerBound) }
        if display > bounds.upperBound { return bounds.upperBound+inverse(display-bounds.upperBound) }
        return display
    }
}

public struct SnapConfiguration: Codable, Equatable, Sendable {
    public var points: [Double]
    public var projection: DecayConfiguration
    public init(points: [Double], projection: DecayConfiguration = .init()) {
        precondition(!points.isEmpty, "At least one legal snap point is required")
        self.points = points.sorted(); self.projection = projection
    }
    public func target(position: Double, velocity: Double) -> Double {
        let predicted = position+projection.projectedDisplacement(velocity: velocity)
        return points.min { abs($0-predicted)<abs($1-predicted) }!
    }
}

/// 手势采样只保存最近一小段时间；停留再松手不会继承很久以前的速度。
public struct VelocityTracker: Sendable {
    private var samples: [(time: Double, value: MotionVector)] = []
    public var window: Double = 0.09
    public init() {}
    public mutating func reset() { samples.removeAll(keepingCapacity: true) }
    public mutating func append(_ value: MotionVector, at time: Double) {
        if let last = samples.last, time <= last.time { return }
        samples.append((time,value))
        samples.removeAll { time-$0.time > window }
    }
    public func velocity(at time: Double, dimensions: Int) -> MotionVector {
        guard let first = samples.first, let last = samples.last,
              time-last.time < 0.1, last.time-first.time > 1e-5 else {
            return MotionVector(repeating: 0,count: dimensions)
        }
        return (last.value-first.value)/(last.time-first.time)
    }
}
