import Foundation
import SwiftUI
import MotionCore
import MotionSwiftUI

// 使用可编辑数据构造复杂动作；无需复制工作台的编辑 UI。
// 以下工厂返回完整配方，宿主自己提供坐标和语义。
public enum AuthoredMotionExamples {
    public static func throughOpening(start: CGPoint,opening: CGPoint,end: CGPoint) -> MotionRecipe {
        var recipe = MotionRecipe(name: "经过入口再展开")
        recipe.family = .path
        recipe.duration = 0.95
        recipe.pathMode = .arcLength
        recipe.curve = .bezier(.easeInOut)
        let a = MotionPoint(start.x,start.y),b = MotionPoint(opening.x,opening.y),c = MotionPoint(end.x,end.y)
        // 中间两侧切线都水平，但长度由场景决定。
        let document = PathDocument(knots: [
            PathKnot(point: a,incoming: a,outgoing: a+MotionPoint(0,-50)),
            PathKnot(point: b,incoming: b+MotionPoint(-35,0),outgoing: b+MotionPoint(35,0),mode: .mirrored),
            PathKnot(point: c,incoming: c+MotionPoint(-40,30),outgoing: c)
        ])
        recipe.setPathDocument(document)
        recipe.target.scaleX = 1.6; recipe.target.scaleY = 1.6
        recipe.intent.coordinateSpace = "object-stage-local-points"
        recipe.intent.purpose = "保留物件经过入口并靠近的空间关系"
        recipe.intent.cancellation = .returnToStart
        recipe.intent.success = "物件到达可阅读的位置"
        return recipe
    }

    public static func arriveThenReveal(start: MotionPose,end: MotionPose) -> MotionRecipe {
        var recipe = MotionRecipe(name: "到达后展开内容")
        recipe.family = .timeline; recipe.initial = start; recipe.target = end
        recipe.keyframeDocument = KeyframeDocument(lanes: [
            KeyframeLane(channel: .x,keyframes: [
                .init(time: 0,value: start.x),
                .init(time: 0.55,value: end.x,tangent: 0,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .y,keyframes: [
                .init(time: 0,value: start.y),
                .init(time: 0.55,value: end.y,tangent: 0,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .scaleX,keyframes: [
                .init(time: 0,value: start.scaleX),
                .init(time: 0.6,value: start.scaleX,interpolation: .hold),
                .init(time: 0.85,value: end.scaleX)
            ]),
            KeyframeLane(channel: .scaleY,keyframes: [
                .init(time: 0,value: start.scaleY),
                .init(time: 0.6,value: start.scaleY,interpolation: .hold),
                .init(time: 0.85,value: end.scaleY)
            ]),
            KeyframeLane(channel: .opacity,keyframes: [
                .init(time: 0,value: start.opacity),
                .init(time: 0.75,value: start.opacity,interpolation: .hold),
                .init(time: 1,value: end.opacity,interpolation: .linear)
            ])
        ])
        recipe.intent.purpose = "让到达和打开被理解为连续的两个阶段"
        recipe.intent.reducedBehavior = .finish
        return recipe
    }
}

// MotionSessionBookmark 可以序列化，但持久化路径、过期时机和业务匹配由宿主定义。
// 此处不自动写磁盘，也不把旧书签应用到已经变化的业务记录。
@MainActor
public final class ProductMotionController {
    public let session: MotionSession
    public init(recipe: MotionRecipe) { session = MotionSession(recipe: recipe) }
    public func pauseAndCapture() throws -> Data {
        session.send(.pause)
        return try JSONEncoder().encode(session.bookmark())
    }
    public func restoreFromTrustedLocalCapture(_ data: Data) throws {
        let bookmark = try JSONDecoder().decode(MotionSessionBookmark.self,from: data)
        session.restore(bookmark,resume: false)
    }
    public func leave() { session.send(.leaveScene) }
}

// 路线与外观组合：各通道只有一个来源，时间窗口自动取最晚结束时间。
public extension AuthoredMotionExamples {
    static func routeWithAppearance(start: CGPoint,opening: CGPoint,end: CGPoint) -> MotionRecipe {
        var recipe = throughOpening(start: start,opening: opening,end: end)
        let arrival = recipe.duration
        recipe.keyframeDocument = KeyframeDocument(lanes: [
            KeyframeLane(channel: .scaleX,keyframes: [
                .init(time: 0,value: 1),
                .init(time: arrival,value: 1,interpolation: .hold),
                .init(time: arrival+0.28,value: 1.6,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .scaleY,keyframes: [
                .init(time: 0,value: 1),
                .init(time: arrival,value: 1,interpolation: .hold),
                .init(time: arrival+0.28,value: 1.6,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .opacity,keyframes: [
                .init(time: 0,value: 0.65),
                .init(time: arrival+0.12,value: 0.65,interpolation: .hold),
                .init(time: arrival+0.4,value: 1,interpolation: .linear)
            ])
        ])
        recipe.intent.purpose = "先让物件通过入口，再在阅读位置展开"
        recipe.intent.success = "路径和全部外观通道完成后可阅读"
        return recipe
    }
}
