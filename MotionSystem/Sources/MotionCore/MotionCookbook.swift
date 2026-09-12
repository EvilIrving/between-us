import Foundation

/// 这些是构造方式，不是统一视觉标准。调用方按自己的坐标空间提供锚点。
public enum MotionCookbook {
    public static func reveal(from origin: MotionPose,to target: MotionPose,
                              travel: Double = 0.55,pause: Double = 0.08) -> MotionTrajectory<MotionPose> {
        let move: MotionModel = .tween(duration: travel,curve: .bezier(.easeOut))
        let open: MotionModel = .tween(duration: 0.25,curve: .bezier(.easeInOut))
        let tracks: [MotionChannel: MotionTrack] = [
            .x: MotionTrack(initial: origin.x).then(to: target.x,model: move),
            .y: MotionTrack(initial: origin.y).then(to: target.y,model: move),
            .scaleX: MotionTrack(initial: origin.scaleX).then(to: target.scaleX,model: open,after: travel+pause),
            .scaleY: MotionTrack(initial: origin.scaleY).then(to: target.scaleY,model: open,after: travel+pause),
            .opacity: MotionTrack(initial: origin.opacity).then(to: target.opacity,model: .tween(duration: 0.18,curve: .linear),after: travel+pause+0.15)
        ]
        return PoseTimeline(initial: origin,tracks: tracks).trajectory
    }
    public static func toast(fromY: Double,toY: Double) -> MotionTrajectory<Double> {
        .transition(from: fromY,to: toY,model: .spring(.init(response: 0.35,dampingRatio: 1)))
    }
    public static func pressedScale() -> MotionTrajectory<Double> {
        .transition(from: 1,to: 0.96,model: .tween(duration: 0.1,curve: .bezier(.easeOut)))
    }
    public static func breathe() -> MotionTrajectory<Double> {
        .transition(from: 0.98,to: 1.02,model: .tween(duration: 2,curve: .sineInOut))
            .repeated(3,autoreverses: true)
    }
    public static func orbit(center: MotionPoint,radius: Double,turns: Double = 1,duration: Double = 2) -> MotionTrajectory<MotionPoint> {
        let angle = MotionTrajectory<Double>.transition(from: 0,to: turns*2 * .pi,model: .tween(duration: duration,curve: .linear))
        return angle.map({ MotionPoint(center.x+radius*cos($0),center.y+radius*sin($0)) },velocity: { theta,velocity in
            MotionVector([-radius*sin(theta)*velocity[0],radius*cos(theta)*velocity[0]])
        })
    }
    /// 一条曲线经过入口后，再走第二条曲线；控制点要让接点两侧的切线方向一致。
    public static func throughWaypoint(start: MotionPoint,entry: MotionPoint,end: MotionPoint,
                                      startHandle: MotionPoint,entryIncoming: MotionPoint,
                                      entryOutgoing: MotionPoint,endHandle: MotionPoint,
                                      duration: Double = 1) -> MotionTrajectory<MotionPoint> {
        let path = MotionPath(segments: [
            .init(start: start,control1: startHandle,control2: entryIncoming,end: entry),
            .init(start: entry,control1: entryOutgoing,control2: endHandle,end: end)
        ])
        return path.trajectory(progress: .transition(from: 0,to: 1,model: .tween(duration: duration,curve: .bezier(.easeInOut))),mode: .arcLength)
    }
}
