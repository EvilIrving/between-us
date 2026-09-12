import Foundation
import QuartzCore
import UIKit

@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var clock: MotionClock?
    @objc func frame(_ link: CADisplayLink) { clock?.frame(link) }
}

/// 所有 driver 共用一条显示时钟；暂停、完成或离开场景后不继续空转。
@MainActor
public final class MotionClock {
    public static let shared = MotionClock()
    private var listeners: [UUID: (Double) -> Void] = [:]
    private var link: CADisplayLink?
    private let target = DisplayLinkTarget()
    private var previous: CFTimeInterval?
    public init() { target.clock = self }
    @discardableResult
    public func add(_ callback: @escaping (Double) -> Void) -> UUID {
        let id = UUID(); listeners[id] = callback
        if link == nil {
            let display = CADisplayLink(target: target,selector: #selector(DisplayLinkTarget.frame(_:)))
            display.preferredFrameRateRange = CAFrameRateRange(minimum: 30,maximum: 120,preferred: 120)
            display.add(to: .main,forMode: .common)
            link = display; previous = nil
        }
        return id
    }
    public func remove(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { link?.invalidate(); link = nil; previous = nil }
    }
    fileprivate func frame(_ display: CADisplayLink) {
        let delta = previous.map { display.timestamp-$0 } ?? 0
        previous = display.timestamp
        // 后台恢复不补演几十秒；正常掉帧仍使用实际时间差。
        if delta > 0.5 { return }
        let callbacks = Array(listeners.values)
        for callback in callbacks { callback(max(0,delta)) }
    }
}
