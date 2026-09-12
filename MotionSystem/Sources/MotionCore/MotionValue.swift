import Foundation
import CoreGraphics

/// 连续数据通过向量参与运动。向量维数在一次运动中必须保持一致。
/// 单位属于业务：位置是 pt，角度是 rad，透明度无量纲，速度总是对应单位 / s。
public struct MotionVector: Equatable, Codable, Sendable {
    public var components: [Double]
    public init(_ components: [Double]) {
        precondition(!components.isEmpty, "A motion value needs at least one component")
        self.components = components
    }
    public init(repeating value: Double, count: Int) { self.init(Array(repeating: value, count: count)) }
    public var count: Int { components.count }
    public var magnitude: Double { sqrt(components.reduce(0) { $0 + $1 * $1 }) }
    public var maximumMagnitude: Double { components.map(abs).max() ?? 0 }
    public subscript(_ index: Int) -> Double {
        get { components[index] }
        set { components[index] = newValue }
    }
    public func map(_ transform: (Double) -> Double) -> Self { Self(components.map(transform)) }
    public static func + (lhs: Self, rhs: Self) -> Self {
        precondition(lhs.count == rhs.count, "Motion dimensions must match")
        return Self(zip(lhs.components, rhs.components).map(+))
    }
    public static func - (lhs: Self, rhs: Self) -> Self {
        precondition(lhs.count == rhs.count, "Motion dimensions must match")
        return Self(zip(lhs.components, rhs.components).map(-))
    }
    public static func * (lhs: Self, rhs: Double) -> Self { lhs.map { $0 * rhs } }
    public static func / (lhs: Self, rhs: Double) -> Self { lhs.map { $0 / rhs } }
    public static prefix func - (value: Self) -> Self { value * -1 }
    public static func lerp(_ a: Self, _ b: Self, _ progress: Double) -> Self { a + (b - a) * progress }
}

public protocol MotionValue: Sendable {
    var motionVector: MotionVector { get }
    init(motionVector: MotionVector)
}

extension Double: MotionValue {
    public var motionVector: MotionVector { MotionVector([self]) }
    public init(motionVector: MotionVector) { self = motionVector[0] }
}
extension CGFloat: MotionValue {
    public var motionVector: MotionVector { MotionVector([Double(self)]) }
    public init(motionVector: MotionVector) { self = CGFloat(motionVector[0]) }
}
extension CGPoint: MotionValue {
    public var motionVector: MotionVector { MotionVector([Double(x), Double(y)]) }
    public init(motionVector: MotionVector) { self.init(x: motionVector[0], y: motionVector[1]) }
}
extension CGSize: MotionValue {
    public var motionVector: MotionVector { MotionVector([Double(width), Double(height)]) }
    public init(motionVector: MotionVector) { self.init(width: motionVector[0], height: motionVector[1]) }
}
extension CGRect: MotionValue {
    public var motionVector: MotionVector { MotionVector([Double(origin.x), Double(origin.y), Double(width), Double(height)]) }
    public init(motionVector: MotionVector) {
        self.init(x: motionVector[0], y: motionVector[1], width: motionVector[2], height: motionVector[3])
    }
}
extension MotionVector: MotionValue {
    public var motionVector: MotionVector { self }
    public init(motionVector: MotionVector) { self = motionVector }
}

/// 角度显式采用弧度与展开后的连续值；不自动把 350° → 10° 解释为转 -340°。
public struct MotionAngle: MotionValue, Codable, Equatable, Sendable {
    public var radians: Double
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { radians = degrees * .pi / 180 }
    public var degrees: Double { radians * 180 / .pi }
    public var motionVector: MotionVector { MotionVector([radians]) }
    public init(motionVector: MotionVector) { radians = motionVector[0] }
    public func nearestEquivalent(to reference: Self) -> Self {
        let delta = atan2(sin(radians - reference.radians), cos(radians - reference.radians))
        return Self(radians: reference.radians + delta)
    }
}

/// 在线性 RGB 中插值，展示时再转成 sRGB；不要从任意 SwiftUI.Color 反推分量。
public struct MotionRGBA: MotionValue, Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(linearRed: Double, green: Double, blue: Double, alpha: Double = 1) {
        red = linearRed; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public init(sRGBRed: Double, green: Double, blue: Double, alpha: Double = 1) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        self.init(linearRed: linear(sRGBRed), green: linear(green), blue: linear(blue), alpha: alpha)
    }
    public var motionVector: MotionVector { MotionVector([red, green, blue, alpha]) }
    public init(motionVector: MotionVector) {
        red = motionVector[0]; green = motionVector[1]; blue = motionVector[2]; alpha = motionVector[3]
    }
}

/// 可视元素常见通道的统一载体；不同通道可以使用各自模型与时间段。
public struct MotionPose: MotionValue, Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    public var rotation: Double = 0
    public var opacity: Double = 1
    public var blur: Double = 0
    public var cornerRadius: Double = 18
    public var width: Double = 56
    public var height: Double = 56
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    public var motionVector: MotionVector {
        MotionVector([x, y, scaleX, scaleY, rotation, opacity, blur, cornerRadius, width, height])
    }
    public init(motionVector v: MotionVector) {
        x = v[0]; y = v[1]; scaleX = v[2]; scaleY = v[3]; rotation = v[4]
        opacity = v[5]; blur = v[6]; cornerRadius = v[7]; width = v[8]; height = v[9]
    }
    public subscript(channel: MotionChannel) -> Double {
        get { motionVector[channel.index] }
        set { var v = motionVector; v[channel.index] = newValue; self = Self(motionVector: v) }
    }
}

public enum MotionChannel: String, Codable, CaseIterable, Sendable {
    case x, y, scaleX, scaleY, rotation, opacity, blur, cornerRadius, width, height
    public var index: Int { Self.allCases.firstIndex(of: self)! }
    public var unit: String {
        switch self {
        case .rotation: return "rad"
        case .scaleX, .scaleY, .opacity: return "ratio"
        default: return "pt"
        }
    }
}

public struct MotionSample<Value: MotionValue>: Sendable {
    public var value: Value
    /// 每一个分量以该分量的单位 / s 表示，不能把预测位移当作速度。
    public var velocity: MotionVector
    public var isSettled: Bool
    public init(value: Value, velocity: MotionVector, isSettled: Bool = false) {
        self.value = value; self.velocity = velocity; self.isSettled = isSettled
    }
    public static func resting(_ value: Value) -> Self {
        Self(value: value, velocity: MotionVector(repeating: 0, count: value.motionVector.count), isSettled: true)
    }
}

public func motionClamp(_ value: Double, _ range: ClosedRange<Double> = 0...1) -> Double {
    min(range.upperBound, max(range.lowerBound, value))
}
