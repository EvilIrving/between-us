import Foundation
import QuartzCore

// 首页这一屏被向上推了多快、推了多远。
// 力度不预设幅度：抬多高由手势本身决定，容器只负责不让它跳出去。
// 三个物件共用同一份值，探针每帧写一次，场景只读。
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
}
