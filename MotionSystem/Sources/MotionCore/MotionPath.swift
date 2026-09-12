import Foundation
import CoreGraphics

public struct MotionPoint: MotionValue, Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public var cgPoint: CGPoint { CGPoint(x: x,y: y) }
    public var motionVector: MotionVector { MotionVector([x,y]) }
    public init(motionVector: MotionVector) { x = motionVector[0]; y = motionVector[1] }
    public static func + (a: Self,b: Self) -> Self { Self(a.x+b.x,a.y+b.y) }
    public static func - (a: Self,b: Self) -> Self { Self(a.x-b.x,a.y-b.y) }
    public static func * (a: Self,b: Double) -> Self { Self(a.x*b,a.y*b) }
    public var length: Double { hypot(x,y) }
    public var normalized: Self { length > 1e-10 ? self*(1/length) : Self(0,0) }
}

public struct BezierSegment: Codable, Equatable, Sendable {
    public var start: MotionPoint
    public var control1: MotionPoint
    public var control2: MotionPoint
    public var end: MotionPoint
    public init(start: MotionPoint,control1: MotionPoint,control2: MotionPoint,end: MotionPoint) {
        self.start = start; self.control1 = control1; self.control2 = control2; self.end = end
    }
    public static func line(from a: MotionPoint,to b: MotionPoint) -> Self {
        Self(start: a,control1: a+(b-a)*(1/3),control2: a+(b-a)*(2/3),end: b)
    }
    public static func quadratic(from a: MotionPoint,control c: MotionPoint,to b: MotionPoint) -> Self {
        Self(start: a,control1: a+(c-a)*(2/3),control2: b+(c-b)*(2/3),end: b)
    }
    public func point(at t: Double) -> MotionPoint {
        let u = 1-t
        return start*(u*u*u)+control1*(3*u*u*t)+control2*(3*u*t*t)+end*(t*t*t)
    }
    public func derivative(at t: Double) -> MotionPoint {
        let u = 1-t
        return (control1-start)*(3*u*u)+(control2-control1)*(6*u*t)+(end-control2)*(3*t*t)
    }
}

public enum PathParameterization: String, Codable, CaseIterable, Sendable { case parameter, arcLength }
public enum PathBoundary: String, Codable, CaseIterable, Sendable { case clamp, extendTangent }

/// 路径长度表属于运动模型，不是测试脚手架。预计算一次，采样时二分定位。
/// 多段路径由调用方保证位置连续；弧长重参数化不会修复尖角或断开的路径。
public struct MotionPath: Sendable {
    public let segments: [BezierSegment]
    public let length: Double
    private let lengths: [Double]
    private let parameters: [Double]
    public init(segments: [BezierSegment], samplesPerSegment: Int = 160) {
        precondition(!segments.isEmpty,"A path must contain a segment")
        self.segments = segments
        let count = max(8,samplesPerSegment)*segments.count
        var lengths = [0.0], parameters = [0.0], total = 0.0
        var previous = segments[0].start
        for i in 1...count {
            let q = Double(i)/Double(count)
            let segmentIndex = min(segments.count-1,Int(q*Double(segments.count)))
            let t = q*Double(segments.count)-Double(segmentIndex)
            let point = segments[segmentIndex].point(at: t)
            total += (point-previous).length
            lengths.append(total); parameters.append(q); previous = point
        }
        self.lengths = lengths; self.parameters = parameters; length = total
    }
    public func parameter(for progress: Double, mode: PathParameterization) -> Double {
        let q = motionClamp(progress)
        guard mode == .arcLength, length > 1e-8 else { return q }
        let distance = q*length
        var low = 0, high = lengths.count-1
        while low+1 < high {
            let middle = (low+high)/2
            if lengths[middle] < distance { low = middle } else { high = middle }
        }
        let span = lengths[high]-lengths[low]
        let fraction = span > 1e-10 ? (distance-lengths[low])/span : 0
        return parameters[low]+(parameters[high]-parameters[low])*fraction
    }
    public func sample(progress: Double, mode: PathParameterization = .arcLength,
                       boundary: PathBoundary = .extendTangent) -> (point: MotionPoint, derivative: MotionPoint) {
        let q = parameter(for: progress,mode: mode)
        let index = min(segments.count-1,Int(q*Double(segments.count)))
        let t = q*Double(segments.count)-Double(index)
        let segment = segments[index], point = segment.point(at: t)
        let rawDerivative = segment.derivative(at: t)*Double(segments.count)
        let derivative = mode == .arcLength ? rawDerivative.normalized*length : rawDerivative
        if progress < 0 || progress > 1 {
            if boundary == .clamp { return (point,MotionPoint(0,0)) }
            return (point+derivative*(progress-motionClamp(progress)),derivative)
        }
        return (point,derivative)
    }
    public func trajectory(progress: MotionTrajectory<Double>, mode: PathParameterization = .arcLength,
                           boundary: PathBoundary = .extendTangent) -> MotionTrajectory<MotionPoint> {
        let path = self
        return progress.map({ path.sample(progress: $0,mode: mode,boundary: boundary).point },velocity: { value,velocity in
            path.sample(progress: value,mode: mode,boundary: boundary).derivative.motionVector*velocity[0]
        })
    }
}
