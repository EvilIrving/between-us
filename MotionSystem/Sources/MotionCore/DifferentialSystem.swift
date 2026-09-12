import Foundation

/// 用于没有解析解的二阶系统：x'' = acceleration(t,x,v)。
/// RK4 是积分方法，不是手感参数。强刚性系统需要更小步长或专用隐式求解器。
public struct DifferentialSystem: Sendable {
    public var acceleration: @Sendable (Double,MotionVector,MotionVector) -> MotionVector
    public init(acceleration: @escaping @Sendable (Double,MotionVector,MotionVector) -> MotionVector) {
        self.acceleration = acceleration
    }
    public func trajectory<Value: MotionValue>(initial: Value,velocity: MotionVector,
                                               duration: Double,step: Double = 1.0/240) throws -> MotionTrajectory<Value> {
        guard duration.isFinite, duration > 0, step.isFinite, step > 0 else { throw IntegrationError.invalidInterval }
        let intervals = ceil(duration/step)
        guard intervals.isFinite, intervals > 0, intervals <= 200_000 else { throw IntegrationError.excessiveInterval }
        let count = Int(intervals)
        let h = duration/Double(count), dimensions = initial.motionVector.count
        guard velocity.count == dimensions else { throw IntegrationError.dimensionMismatch }
        var position = initial.motionVector, speed = velocity
        var values = [position], speeds = [speed]
        for index in 0..<count {
            let t = Double(index)*h
            let k1x = speed, k1v = acceleration(t,position,speed)
            guard k1v.count == dimensions else { throw IntegrationError.dimensionMismatch }
            let k2x = speed+k1v*(h/2)
            let k2v = acceleration(t+h/2,position+k1x*(h/2),speed+k1v*(h/2))
            guard k2v.count == dimensions else { throw IntegrationError.dimensionMismatch }
            let k3x = speed+k2v*(h/2)
            let k3v = acceleration(t+h/2,position+k2x*(h/2),speed+k2v*(h/2))
            guard k3v.count == dimensions else { throw IntegrationError.dimensionMismatch }
            let k4x = speed+k3v*h
            let k4v = acceleration(t+h,position+k3x*h,speed+k3v*h)
            guard k4v.count == dimensions else { throw IntegrationError.dimensionMismatch }
            position = position+(k1x+k2x*2+k3x*2+k4x)*(h/6)
            speed = speed+(k1v+k2v*2+k3v*2+k4v)*(h/6)
            guard position.components.allSatisfy(\.isFinite),speed.components.allSatisfy(\.isFinite) else {
                throw IntegrationError.unstable
            }
            values.append(position); speeds.append(speed)
        }
        let positions = values, velocities = speeds
        let end = Value(motionVector: positions[count])
        return MotionTrajectory<Value>(duration: duration,start: initial,end: end) { time in
            if time >= duration {
                // 有限积分窗口不等于物理平衡。轨迹末尾保留物理速度，供调用方续接。
                return MotionSample(value: end,velocity: velocities[count],isSettled: false)
            }
            let index = min(count-1,Int(time/h)), local = time-Double(index)*h
            let components = (0..<dimensions).map {
                HermiteSegment(from: positions[index][$0],to: positions[index+1][$0],
                               startVelocity: velocities[index][$0],endVelocity: velocities[index+1][$0],duration: h)
                    .sample(at: local)
            }
            return MotionSample(value: Value(motionVector: MotionVector(components.map(\.value))),
                                velocity: MotionVector(components.map(\.velocity)))
        }
    }
    public static func pendulum(gravityOverLength: Double = 14,damping: Double = 1.5) -> Self {
        Self { _,angle,velocity in MotionVector([-gravityOverLength*sin(angle[0])-damping*velocity[0]]) }
    }
    public static func nonlinearSpring(stiffness: Double = 80,cubicStiffness: Double = 8,damping: Double = 12) -> Self {
        Self { _,position,velocity in
            MotionVector((0..<position.count).map { index in
                let x = position[index]
                return -stiffness*x-cubicStiffness*x*x*x-damping*velocity[index]
            })
        }
    }
    public enum IntegrationError: LocalizedError {
        case invalidInterval, excessiveInterval, dimensionMismatch, unstable
        public var errorDescription: String? {
            switch self {
            case .invalidInterval: return "积分时长和步长必须为有限正数。"
            case .excessiveInterval: return "积分窗口过长，请缩短时长或增大步长。"
            case .dimensionMismatch: return "加速度和速度必须与位置维数一致。"
            case .unstable: return "模型积分发散。请减小步长或降低刚度。"
            }
        }
    }
}
