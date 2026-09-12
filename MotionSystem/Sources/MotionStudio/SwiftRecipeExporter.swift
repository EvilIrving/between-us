import Foundation
import MotionCore

public enum SwiftRecipeExporter {
    private static func literal(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\",with: "\\\\")
            .replacingOccurrences(of: "\"",with: "\\\"")
            .replacingOccurrences(of: "\n",with: "\\n")
            .replacingOccurrences(of: "\r",with: "\\r")
            .replacingOccurrences(of: "\t",with: "\\t")
        return "\""+escaped+"\""
    }
    private static func curve(_ value: TimingCurve) -> String {
        switch value {
        case .linear: return ".linear"
        case .bezier(let c): return ".bezier(CubicBezier(\(c.x1), \(c.y1), \(c.x2), \(c.y2)))"
        case .smoothstep: return ".smoothstep"
        case .smootherstep: return ".smootherstep"
        case .sineInOut: return ".sineInOut"
        case .steps(let count): return ".steps(\(count))"
        }
    }
    private static func interpolation(_ value: KeyframeInterpolation) -> String {
        switch value {
        case .linear: return ".linear"
        case .hermite: return ".hermite"
        case .hold: return ".hold"
        case .bezier(let c): return ".bezier(CubicBezier(\(c.x1), \(c.y1), \(c.x2), \(c.y2)))"
        case .curve(let c): return ".curve(\(curve(c)))"
        }
    }
    /// 导出可阅读的 Swift 配方与完整原生 View，不把关键参数藏进编码字符串。
    public static func source(for r: MotionRecipe) throws -> String {
        _ = try r.encoded()
        var lines = ["var recipe = MotionRecipe(id: \(literal(r.id)), name: \(literal(r.name)))",
                     "recipe.schemaVersion = \(r.pathDocument != nil || r.keyframeDocument != nil ? 2 : 1)",
                     "recipe.family = .\(r.family.rawValue)"]
        for (name,pose) in [("initial",r.initial),("target",r.target)] {
            for channel in MotionChannel.allCases {
                lines.append("recipe.\(name).\(channel.rawValue) = \(pose[channel])")
            }
        }
        lines += [
            "recipe.duration = \(r.duration)", "recipe.delay = \(r.delay)",
            "recipe.curve = \(curve(r.curve))",
            "recipe.spring = .init(response: \(r.spring.response), dampingRatio: \(r.spring.dampingRatio), mass: \(r.spring.mass), relativeTolerance: \(r.spring.relativeTolerance))",
            "recipe.decay = .init(rate: \(r.decay.rate), velocityTolerance: \(r.decay.velocityTolerance))",
            "recipe.velocity = MotionVector(\(r.velocity.components))",
            "recipe.control1 = MotionPoint(\(r.control1.x), \(r.control1.y))",
            "recipe.control2 = MotionPoint(\(r.control2.x), \(r.control2.y))",
            "recipe.pathMode = .\(r.pathMode.rawValue)", "recipe.pathBoundary = .\(r.pathBoundary.rawValue)",
            "recipe.pathUsesSpring = \(r.pathUsesSpring)",
            "recipe.repeatCount = \(r.repeatCount)", "recipe.autoreverses = \(r.autoreverses)",
            "recipe.intent.purpose = \(literal(r.intent.purpose))",
            "recipe.intent.trigger = .\(r.intent.trigger.rawValue)",
            "recipe.intent.coordinateSpace = \(literal(r.intent.coordinateSpace))",
            "recipe.intent.interruption = .\(r.intent.interruption.rawValue)",
            "recipe.intent.cancellation = .\(r.intent.cancellation.rawValue)",
            "recipe.intent.reducedBehavior = .\(r.intent.reducedBehavior.rawValue)",
            "recipe.intent.success = \(literal(r.intent.success))",
            "recipe.intent.recovery = \(literal(r.intent.recovery))",
            "recipe.intent.frequency = \(literal(r.intent.frequency))"
        ]
        if !r.tracks.isEmpty {
            lines.append("recipe.tracks = [")
            lines += r.tracks.map { "    RecipeTrack(.\($0.channel.rawValue), start: \($0.startTime), duration: \($0.duration), curve: \(curve($0.curve)))," }
            lines.append("]")
        }
        if let document = r.pathDocument {
            lines.append("recipe.pathDocument = PathDocument(knots: [")
            for knot in document.knots {
                lines.append("    PathKnot(id: UUID(uuidString: \(literal(knot.id.uuidString)))!, point: MotionPoint(\(knot.point.x), \(knot.point.y)), incoming: MotionPoint(\(knot.incoming.x), \(knot.incoming.y)), outgoing: MotionPoint(\(knot.outgoing.x), \(knot.outgoing.y)), mode: .\(knot.mode.rawValue)),")
            }
            lines.append("])")
        }
        if let document = r.keyframeDocument {
            lines.append("recipe.keyframeDocument = KeyframeDocument(lanes: [")
            for lane in document.lanes {
                lines.append("    KeyframeLane(channel: .\(lane.channel.rawValue), keyframes: [")
                for key in lane.keyframes {
                    lines.append("        MotionKeyframe(id: UUID(uuidString: \(literal(key.id.uuidString)))!, time: \(key.time), value: \(key.value), tangent: \(key.tangent), interpolation: \(interpolation(key.interpolation))),")
                }
                lines.append("    ], isEnabled: \(lane.isEnabled)),")
            }
            lines.append("])")
        }
        lines.append("return recipe")
        let definition = lines.map { "        "+$0 }.joined(separator: "\n")
        return """
        import SwiftUI
        import Foundation
        import MotionCore
        import MotionSwiftUI

        // 加入本地 MotionSystem package 后，直接使用此 View。
        // 340×280 为教学坐标；接入产品时从实际舞台锚点构造 initial / target。
        @MainActor
        struct ExportedMotionView: View {
            static let recipe: MotionRecipe = {
        \(definition)
            }()
            @StateObject private var driver: MotionDriver<MotionPose>
            @Environment(\\.accessibilityReduceMotion) private var reduced
            @Environment(\\.scenePhase) private var phase

            init() {
                _driver = StateObject(wrappedValue: MotionDriver(initial: Self.recipe.initial))
            }
            var body: some View {
                VStack(spacing: 20) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        Rectangle().fill(.green).motionPose(driver.value)
                    }
                    .frame(width: 340, height: 280)
                    .clipped()
                    HStack {
                        Button("播放") {
                            if reduced && Self.recipe.intent.reducedBehavior == .returnToStart {
                                driver.setImmediately(Self.recipe.initial)
                            } else {
                                driver.play(Self.recipe.makeTrajectory())
                            }
                        }
                        Button("取消") {
                            if Self.recipe.intent.cancellation == .returnToStart {
                                driver.animate(to: Self.recipe.initial, model: .spring(Self.recipe.spring))
                            } else { driver.cancel(Self.recipe.intent.cancellation) }
                        }
                    }
                }
                .onAppear { driver.reduceMotion = reduced }
                .onChange(of: reduced) { _, enabled in
                    if enabled && Self.recipe.intent.reducedBehavior == .returnToStart {
                        driver.setImmediately(Self.recipe.initial)
                    }
                    driver.reduceMotion = enabled
                }
                .onChange(of: phase) { _, value in
                    if value != .active { driver.pause() }
                }
                .onDisappear { driver.detach() }
            }
        }
        """
    }
}
