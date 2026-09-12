import Foundation

public enum MotionFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case tween, spring, hermite, decay, path, timeline
    public var id: String { rawValue }
}
public enum MotionInterruption: String, Codable, CaseIterable, Sendable {
    case preserveVelocity, preservePosition, restart
}
public enum MotionCancellation: String, Codable, CaseIterable, Sendable {
    case hold, returnToStart, finish
}
public enum MotionReducedBehavior: String, Codable, CaseIterable, Sendable {
    case finish, returnToStart
}
public enum MotionTrigger: String, Codable, CaseIterable, Sendable {
    case tap, dragRelease, dataChange, appear
}

/// 配方不是一句“丝滑”。这些字段要求作者先描述可观察的行为。
/// 字段记录设计意图；外部输入事件由宿主调用 driver，不由配方自动监听。
public struct MotionIntent: Codable, Equatable, Sendable {
    public var purpose: String = "让用户看懂物件从哪里来到哪里去"
    public var trigger: MotionTrigger = .tap
    public var coordinateSpace: String = "stage-local-points"
    public var interruption: MotionInterruption = .preserveVelocity
    public var cancellation: MotionCancellation = .returnToStart
    public var reducedBehavior: MotionReducedBehavior = .finish
    public var success: String = "物件停在目标位置，内容可操作"
    public var recovery: String = "取消后回到起点，可再次打开"
    public var frequency: String = "低频打开"
    public init() {}
}

public struct RecipeTrack: Codable, Equatable, Sendable, Identifiable {
    public var channel: MotionChannel
    public var startTime: Double
    public var duration: Double
    public var curve: TimingCurve
    public var id: String { channel.rawValue }
    public init(_ channel: MotionChannel,start: Double,duration: Double,curve: TimingCurve = .bezier(.easeInOut)) {
        self.channel = channel; startTime = start; self.duration = duration; self.curve = curve
    }
}

/// 持久化只存数学参数，不存显示时钟或闭包；Swift 和 JSON 都能携带同一个配方。
public struct MotionRecipe: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var name: String
    public var intent = MotionIntent()
    public var family: MotionFamily = .spring
    public var initial = MotionPose(x: 55,y: 200)
    public var target = MotionPose(x: 275,y: 90)
    public var duration: Double = 0.65
    public var delay: Double = 0
    public var curve: TimingCurve = .bezier(.easeInOut)
    public var spring = SpringConfiguration()
    public var decay = DecayConfiguration()
    public var velocity = MotionVector(repeating: 0,count: 10)
    public var control1 = MotionPoint(95,35)
    public var control2 = MotionPoint(235,35)
    public var pathDocument: PathDocument?
    public var pathMode: PathParameterization = .arcLength
    public var pathBoundary: PathBoundary = .extendTangent
    public var pathUsesSpring = false
    public var tracks: [RecipeTrack] = []
    public var keyframeDocument: KeyframeDocument?
    public var repeatCount: Int = 1
    public var autoreverses = false
    public init(id: String = UUID().uuidString,name: String = "新的动效") { self.id = id; self.name = name }

    public var model: MotionModel {
        switch family {
        case .tween, .path, .timeline: return .tween(duration: duration,curve: curve)
        case .spring: return .spring(spring)
        case .hermite: return .hermite(duration: duration)
        case .decay: return .decay(decay)
        }
    }
    /// continuation 适用于数值模型；路径与时间轴的中断须重新设计路径或重新排时间轴。
    public func makeTrajectory(from continuation: MotionSample<MotionPose>? = nil) -> MotionTrajectory<MotionPose> {
        let source = continuation?.value ?? initial
        let speed = continuation?.velocity ?? velocity
        let base: MotionTrajectory<MotionPose>
        switch family {
        case .path:
            let route = resolvedPath(start: MotionPoint(source.x,source.y))
            let progressModel: MotionModel = pathUsesSpring ? .spring(spring) : .tween(duration: duration,curve: curve)
            let progress = MotionTrajectory<Double>.transition(from: 0,to: 1,model: progressModel)
            let startVector = source.motionVector, endVector = target.motionVector
            let mode = pathMode, boundary = pathBoundary
            base = progress.map({ q in
                var pose = MotionPose(motionVector: .lerp(startVector,endVector,q))
                let location = route.sample(progress: q,mode: mode,boundary: boundary).point
                pose.x = location.x; pose.y = location.y
                return pose
            },velocity: { q,v in
                var result = (endVector-startVector)*v[0]
                let tangent = route.sample(progress: q,mode: mode,boundary: boundary).derivative
                result[0] = tangent.x*v[0]; result[1] = tangent.y*v[0]
                return result
            })
        case .timeline:
            if let document = keyframeDocument {
                base = document.trajectory(initial: source)
                break
            }
            var channels: [MotionChannel: MotionTrack] = [:]
            for track in tracks {
                channels[track.channel] = MotionTrack(initial: source[track.channel])
                    .then(to: target[track.channel],model: .tween(duration: track.duration,curve: track.curve),after: track.startTime)
            }
            base = PoseTimeline(initial: source,tracks: channels).trajectory
        default:
            base = .transition(from: source,to: target,velocity: speed,model: model)
        }
        let composed: MotionTrajectory<MotionPose>
        if family == .path,let document = keyframeDocument {
            let appearance = KeyframeDocument(lanes: document.lanes.filter { $0.isEnabled && $0.channel != .x && $0.channel != .y })
            composed = base.overriding(Set(appearance.lanes.map(\.channel)),with: appearance.trajectory(initial: source))
        } else { composed = base }
        let delayed = delay > 0 ? composed.delayed(by: delay) : composed
        return repeatCount > 1 || autoreverses ? delayed.repeated(repeatCount,autoreverses: autoreverses) : delayed
    }
    public var editablePath: PathDocument {
        pathDocument ?? PathDocument(segment: .init(start: MotionPoint(initial.x,initial.y),
            control1: control1,control2: control2,end: MotionPoint(target.x,target.y)))
    }
    public func resolvedPath(start: MotionPoint? = nil) -> MotionPath {
        var document = editablePath
        document.replaceEndpoints(start: start ?? MotionPoint(initial.x,initial.y),end: MotionPoint(target.x,target.y))
        return document.path
    }
    public mutating func setPathDocument(_ document: PathDocument) {
        pathDocument = document
        if let start = document.knots.first,let end = document.knots.last {
            initial.x = start.point.x; initial.y = start.point.y
            target.x = end.point.x; target.y = end.point.y
            control1 = start.outgoing; control2 = end.incoming
        }
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        var saved = self
        saved.schemaVersion = pathDocument != nil || keyframeDocument != nil ? 2 : 1
        return try encoder.encode(saved)
    }
    public static func decode(_ data: Data) throws -> Self {
        let recipe = try JSONDecoder().decode(Self.self,from: data)
        guard (1...2).contains(recipe.schemaVersion) else { throw RecipeError.unsupportedVersion }
        guard recipe.velocity.count == 10 else { throw RecipeError.velocityDimensions }
        if let path = recipe.pathDocument {
            guard path.knots.count >= 2,path.knots.count <= 200,
                  Set(path.knots.map(\.id)).count == path.knots.count,
                  path.knots.allSatisfy({ [$0.point.x,$0.point.y,$0.incoming.x,$0.incoming.y,$0.outgoing.x,$0.outgoing.y].allSatisfy(\.isFinite) })
            else { throw RecipeError.invalidParameters }
        }
        if let timeline = recipe.keyframeDocument {
            guard Set(timeline.lanes.map(\.channel)).count == timeline.lanes.count,
                  timeline.lanes.allSatisfy({ lane in
                      lane.keyframes.count >= 2 && lane.keyframes.count <= 1000 &&
                      Set(lane.keyframes.map(\.id)).count == lane.keyframes.count &&
                      lane.keyframes.allSatisfy { $0.time.isFinite && $0.time >= 0 && $0.value.isFinite && $0.tangent.isFinite } &&
                      zip(lane.keyframes,lane.keyframes.dropFirst()).allSatisfy { pair in pair.0.time < pair.1.time }
                  }) else { throw RecipeError.invalidParameters }
        }
        let numbers = recipe.initial.motionVector.components + recipe.target.motionVector.components + recipe.velocity.components
        func usableCurve(_ curve: TimingCurve) -> Bool {
            switch curve {
            case .bezier(let c):
                return [c.x1,c.y1,c.x2,c.y2].allSatisfy(\.isFinite) && (0...1).contains(c.x1) && (0...1).contains(c.x2)
            case .steps(let count): return count > 0 && count <= 10_000
            default: return true
            }
        }
        guard usableCurve(recipe.curve), Set(recipe.tracks.map(\.channel)).count == recipe.tracks.count,
              numbers.allSatisfy(\.isFinite), recipe.duration.isFinite, recipe.duration > 0,
              recipe.delay.isFinite, recipe.delay >= 0, (1...100).contains(recipe.repeatCount),
              recipe.spring.response.isFinite, recipe.spring.response > 0,
              recipe.spring.dampingRatio.isFinite, recipe.spring.dampingRatio > 0,
              recipe.spring.mass.isFinite, recipe.spring.mass > 0,
              recipe.spring.relativeTolerance > 0, recipe.spring.relativeTolerance < 1,
              recipe.decay.rate.isFinite, recipe.decay.rate > 0,
              recipe.decay.velocityTolerance.isFinite, recipe.decay.velocityTolerance > 0,
              [recipe.control1.x,recipe.control1.y,recipe.control2.x,recipe.control2.y].allSatisfy(\.isFinite),
              recipe.tracks.allSatisfy({ $0.startTime.isFinite && $0.startTime >= 0 && $0.duration.isFinite && $0.duration > 0 && usableCurve($0.curve) })
        else { throw RecipeError.invalidParameters }
        return recipe
    }
    public enum RecipeError: LocalizedError {
        case unsupportedVersion, velocityDimensions, invalidParameters
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "配方版本不受支持。当前支持 schemaVersion 1 和 2。"
            case .velocityDimensions: return "姿态速度需要 10 个分量，顺序须与 MotionPose 一致。"
            case .invalidParameters: return "配方参数超出有效范围。时长、质量和衰减率必须为正，所有数值必须有限。"
            }
        }
    }
}

public enum MotionRecipes {
    public static var all: [MotionRecipe] { [transfer,quietSpring,expressiveSpring,arc,unfold,stagedReveal,numberChange,inertia,velocityBridge,throughOpening,routeAndReveal] }
    public static var transfer: MotionRecipe {
        var r = MotionRecipe(id: "transfer",name: "明确的位移")
        r.family = .tween; return r
    }
    public static var quietSpring: MotionRecipe {
        var r = MotionRecipe(id: "quiet",name: "利落停稳")
        r.spring = .init(response: 0.42,dampingRatio: 1); return r
    }
    public static var expressiveSpring: MotionRecipe {
        var r = MotionRecipe(id: "elastic",name: "轻微弹性")
        r.spring = .init(response: 0.62,dampingRatio: 0.7); return r
    }
    public static var arc: MotionRecipe {
        var r = MotionRecipe(id: "arc",name: "经过上方的弧线")
        r.family = .path; r.duration = 0.9; return r
    }
    public static var unfold: MotionRecipe {
        var r = MotionRecipe(id: "unfold",name: "靠近并展开")
        r.target.scaleX = 1.8; r.target.scaleY = 1.8; r.target.rotation = .pi/10
        r.spring = .init(response: 0.65,dampingRatio: 0.95); return r
    }
    public static var stagedReveal: MotionRecipe {
        var r = MotionRecipe(id: "reveal",name: "先到达，再揭示")
        r.family = .timeline; r.initial.opacity = 0.25
        r.target.scaleX = 1.8; r.target.scaleY = 1.8
        r.tracks = [.init(.x,start: 0,duration: 0.6),.init(.y,start: 0,duration: 0.6),
                    .init(.scaleX,start: 0.7,duration: 0.25),.init(.scaleY,start: 0.7,duration: 0.25),
                    .init(.opacity,start: 0.95,duration: 0.2)]
        return r
    }
    public static var numberChange: MotionRecipe {
        var r = MotionRecipe(id: "data",name: "数值驱动形态")
        r.initial.width = 40; r.target.width = 105
        r.initial.cornerRadius = 4; r.target.cornerRadius = 28
        r.target.x = 170; r.target.y = 140; r.family = .hermite
        r.intent.trigger = .dataChange; return r
    }
    public static var inertia: MotionRecipe {
        var r = MotionRecipe(id: "decay",name: "释放后的惯性")
        r.family = .decay; r.initial.y = 140; r.target.y = 140
        r.velocity[0] = 900; r.decay = .init(rate: 5)
        return r
    }
    public static var velocityBridge: MotionRecipe {
        var r = MotionRecipe(id: "hermite",name: "接住速度，按时结束")
        r.family = .hermite; r.velocity[0] = 450; r.duration = 0.8; return r
    }
}
