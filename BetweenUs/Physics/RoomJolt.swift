import CoreMotion
import Foundation
import QuartzCore

// 首页这一屏的两路物理信号，都只写值、不经过 SwiftUI 状态：
// - `RoomJolt`：屏幕被向上推了多快、推了多远（由首页探针每帧写一次）。
// - `DeviceMotionSource`：手机的倾斜方向与手的晃动（只有可见时才开传感器）。
// 三个物件共用同一份值，场景只读。
@MainActor
final class RoomJolt {
    // 手势结束后每秒把累计的上推量收回多少点，容器里的东西随之落回原处。
    static let retractRate: CGFloat = 520

    private(set) var travel: CGFloat = 0 // 本次手势累计被向上推的点数。
    private(set) var speed: CGFloat = 0  // 上推速度，点/秒。

    // 只由首页探针调用：delta 是本帧位移，speed 是本帧速度，isGesturing 表示手势或惯性还在。
    // 手指停住不动时保持当前抬升，只有手势结束才收回。
    func update(delta: CGFloat, speed: CGFloat, isGesturing: Bool, dt: TimeInterval) {
        guard isGesturing else {
            self.speed = 0
            travel = max(0, travel - CGFloat(dt) * Self.retractRate)
            return
        }
        travel = max(0, travel + delta)
        self.speed = max(0, speed)
    }

    func sample() -> (travel: CGFloat, speed: CGFloat) { (travel, speed) }

    // 首页不在前台、被推走一层时收回抬升，回来时容器里的东西不会悬在半空。
    func reset() {
        travel = 0
        speed = 0
    }
}

// 手机姿态反馈的全部手感参数。算法不自己定数，只读这一份；要新效果就改这里的数，
// 不用碰物理代码：推力大小改 *Acceleration，跟手程度改 tiltDeadzone，滚动手感改 shakeSpin。
struct DeviceMotionSettings: Equatable {
    /// 总开关。关掉后手机怎么动，容器里都完全不受影响。
    var isEnabled: Bool = true
    /// 两路感应的总强度倍率：0.5 = 轻柔，1 = 标准，1.8 = 明显。
    var strength: CGFloat = 1
    /// 手机朝向（横过来、竖起来）通道的相对强度。0 = 不感应拿起手机这件事。
    var tiltStrength: CGFloat = 1
    /// 晃动通道的相对强度。0 = 不感应晃动。
    var shakeStrength: CGFloat = 1
    /// 晃动里的竖直方向。0 = 只跟着左右晃，不跟着上下动。
    var shakeVerticalStrength: CGFloat = 1
    /// 倾斜要多大才算倾斜：屏幕平面内横向小于它的当作手持抖动。0.03 ≈ 1.7°。
    var tiltDeadzone: CGFloat = 0.03
    /// 满倾斜（手机侧躺）时的横向推力，点/秒²。240 ≈ 横穿瓶子约 1.5 秒。
    var tiltAcceleration: CGFloat = 240
    /// 晃动推力：每 1g 惯性换算成多少点/秒²。
    var shakeAcceleration: CGFloat = 1200
    /// 晃动带起的翻滚，弧度/秒²。
    var shakeSpin: CGFloat = 12
    /// 晃动结束后，内容上限约束再绷多久（每秒衰减）。
    var containReleaseRate: CGFloat = 2
    /// 横向推力变化超过这个就把休眠的实体叫醒。
    var wakeThreshold: CGFloat = 8

    /// 两路实际生效的强度 = 开关 × 总强度 × 分路强度。
    var effectiveTiltStrength: CGFloat { isEnabled ? strength * tiltStrength : 0 }
    var effectiveShakeStrength: CGFloat { isEnabled ? strength * shakeStrength : 0 }
    var effectiveShakeVerticalStrength: CGFloat { effectiveShakeStrength * shakeVerticalStrength }
}

/// 设置页的档位；存进偏好的只是档位名，具体参数仍然以上面的结构为准。
enum DeviceMotionMode: String, CaseIterable, Identifiable {
    case standard
    case gentle
    case strong
    case shakeOnly
    case tiltOnly
    case off

    static let storageKey = "settings.deviceMotionMode"

    var id: String { rawValue }

    var settings: DeviceMotionSettings {
        switch self {
        case .standard: return DeviceMotionSettings()
        case .gentle: return DeviceMotionSettings(strength: 0.5)
        case .strong: return DeviceMotionSettings(strength: 1.8)
        case .shakeOnly: return DeviceMotionSettings(tiltStrength: 0)
        case .tiltOnly: return DeviceMotionSettings(shakeStrength: 0)
        case .off: return DeviceMotionSettings(isEnabled: false)
        }
    }

    /// 行内显示的当前状态。
    var statusTitle: String {
        switch self {
        case .standard: return T("标准")
        case .gentle: return T("轻柔")
        case .strong: return T("明显")
        case .shakeOnly: return T("只有晃动")
        case .tiltOnly: return T("只有倾斜")
        case .off: return T("已关闭")
        }
    }
}

// 设备姿态信号：手机横过来时容器里的东西被横向推着走，手上的晃动按惯性反向推一把。
// 只用加速度计轮询，不走 deviceMotion 融合：只需要方向和一个高频分量，也更省电。
// 符号约定（SDK 头文件）：`accelerometerData.acceleration` = gravity + userAcceleration，
// 所以读数本身就是重力方向（朝下）；不要按物理课的“比力”当成朝上，那样重力会整个反。
@MainActor
final class DeviceMotionSource {
    struct Sample {
        // 屏幕平面内的重力方向，场景坐标，长度 0…1（单位 g）；手机平放时接近零。
        var gravity: CGVector = .zero
        // 惯性扰动，场景坐标，单位 g；已扣掉自然抖动与上限。
        var shake: CGVector = .zero
    }

    // 低通时间常数：倾斜要跟得上手，晃动要留得住幅度。
    private static let smoothDuration: TimeInterval = 0.1
    // 小于这只手的自然抖动不响应，避免手机拿在手里容器里一直在抖。
    private static let shakeDeadzone: CGFloat = 0.04
    private static let maximumShake: CGFloat = 1.6
    private static let updateInterval: TimeInterval = 1.0 / 60.0
    // 同一帧里三个场景都会读一次，滤波只推进一次。
    private static let sameFrameInterval: TimeInterval = 1.0 / 240.0
    // 调试用：把真机读数打到设备控制台；平时关着，要看时改成 true。
    private static let diagnosticsEnabled = false

    private let manager = CMMotionManager()
    private var smoothed = CGVector(dx:0, dy:-1) // 低通后的加速度计读数，即重力方向（朝下）。
    private var lastReadAt: CFTimeInterval?
    private var current = Sample()
    private var lastDiagnosticAt: CFTimeInterval = 0

    // 只在首页可见时开；被推走一层、App 进后台就停。
    func setActive(_ active: Bool) {
        guard manager.isAccelerometerAvailable else { return }
        if active {
            guard !manager.isAccelerometerActive else { return }
            manager.accelerometerUpdateInterval = Self.updateInterval
            smoothed = CGVector(dx:0, dy:-1)
            lastReadAt = nil
            current = Sample()
            manager.startAccelerometerUpdates()
        } else {
            guard manager.isAccelerometerActive else { return }
            manager.stopAccelerometerUpdates()
            lastReadAt = nil
            current = Sample()
        }
    }

    // 每帧由场景读一次；未开传感器时返回静止值，重力保持配方里的竖直重力。
    func sample() -> Sample {
        guard manager.isAccelerometerActive else { return current }
        guard let reading = manager.accelerometerData?.acceleration else { return current }
        let now = CACurrentMediaTime()
        guard let previous = lastReadAt else {
            // 刚开启：以当前读数为基准，不把启动那一瞬当成一次晃动。
            lastReadAt = now
            smoothed = CGVector(dx:reading.x, dy:reading.y)
            current = Sample(gravity:CGVector(dx:reading.x, dy:reading.y), shake:.zero)
            return current
        }
        // 同一帧里三个场景都会读一次，滤波只推进一次。
        let elapsed = now - previous
        guard elapsed >= Self.sameFrameInterval else { return current }
        let dt = min(elapsed, 0.1)
        lastReadAt = now

        let raw = CGVector(dx:reading.x, dy:reading.y)
        // 设备坐标 x 向右、y 向上（竖屏场景同向），读数即重力方向，直接就是场景里的重力方向。
        let blend = CGFloat(1 - exp(-dt / Self.smoothDuration))
        smoothed.dx += (raw.dx - smoothed.dx) * blend
        smoothed.dy += (raw.dy - smoothed.dy) * blend

        // 扣掉低通剩下的就是设备自身的运动；容器里的东西按惯性反向受力。
        var shake = CGVector(dx:smoothed.dx - raw.dx, dy:smoothed.dy - raw.dy)
        let magnitude = hypot(shake.dx, shake.dy)
        if magnitude <= Self.shakeDeadzone {
            shake = .zero
        } else {
            let scale = min(magnitude - Self.shakeDeadzone, Self.maximumShake) / magnitude
            shake = CGVector(dx:shake.dx * scale, dy:shake.dy * scale)
        }

        current = Sample(gravity:CGVector(dx:smoothed.dx, dy:smoothed.dy), shake:shake)
        if Self.diagnosticsEnabled, now - lastDiagnosticAt >= 1 {
            lastDiagnosticAt = now
            print("[sensor] active=\(manager.isAccelerometerActive) raw=\(reading.x),\(reading.y),\(reading.z) gravity=\(current.gravity.dx),\(current.gravity.dy) shake=\(current.shake.dx),\(current.shake.dy)")
        }
        return current
    }
}
