import Combine
import QuartzCore
import SwiftUI
import UIKit

enum ContainerRevealSpace {
    static let name = "containerRevealSpace"
}

enum ContentTokenType: Equatable {
    case star
    case capsule
    case paperBall

    init(_ kind: ContainerKind) {
        switch kind {
        case .star: self = .star
        case .capsule: self = .capsule
        case .paper: self = .paperBall
        }
    }

    var kind: ContainerKind {
        switch self {
        case .star: return .star
        case .capsule: return .capsule
        case .paperBall: return .paper
        }
    }
}

enum ExitPathStyle: Equatable {
    case straight
    case curved
}

enum RevealContentLayer: Equatable {
    case behindBottleForeground
    case foregroundFlight
}

enum ContainerRevealStage: Equatable {
    case idle
    case containerFeedback
    case exitContainer
    case flyToFocus
    case focusPause
    case collapse
    case revealCard
    case complete
}

struct RevealContentToken: Equatable {
    var type: ContentTokenType
    var imageName: String?
    var seed: Int
    var visualSize: CGSize
}

struct RevealPathConfiguration: Equatable {
    var exitPathStyle: ExitPathStyle
    var exitCurveBias: CGFloat
    var flightArcHeight: CGFloat
    var flightSideBias: CGFloat
    var releaseLift: CGFloat

    static let releaseLiftDefault: CGFloat = 20
}

struct RevealAnimationConfiguration: Equatable {
    var feedbackDuration: TimeInterval
    var exitDuration: TimeInterval
    var flyDuration: TimeInterval
    var pauseDuration: TimeInterval
    var collapseDuration: TimeInterval
    var cardDuration: TimeInterval
    var cardOverlap: TimeInterval
    var exitRotationY: Double
    var flyRotationY: Double
    var peakScale: CGFloat
    var motionExponent: CGFloat
    var collapseExponent: CGFloat
    var reduceMotion: Bool

    var totalDuration: TimeInterval {
        let collapseAndCard = collapseDuration + cardDuration - cardOverlap
        return feedbackDuration + exitDuration + flyDuration + pauseDuration + collapseAndCard
    }

    var cardStart: TimeInterval {
        feedbackDuration + exitDuration + flyDuration + pauseDuration + collapseDuration - cardOverlap
    }
}

struct RevealContext: Equatable {
    var containerFrame: CGRect
    var bottleMouthBounds: CGRect
    var contentStartPosition: CGPoint
    var containerExitPosition: CGPoint
    var finalFocusPosition: CGPoint
    var finalCardFrame: CGRect
    var exitPathStyle: ExitPathStyle
    var exitCurveBias: CGFloat
    var flightSideBias: CGFloat
    var flightArcFactor: CGFloat
    var initialRotationY: CGFloat
    var contentType: ContentTokenType
}

struct ContainerRevealInput: Equatable {
    var containerFrame: CGRect
    var bottleMouthBounds: CGRect
    var containerExitAnchor: CGPoint
    var contentStartPosition: CGPoint
    var contentVisualSize: CGSize
    var finalCardFrame: CGRect
    var pathConfiguration: RevealPathConfiguration
    var animationConfiguration: RevealAnimationConfiguration
}

struct ContentRevealInstance: Equatable {
    var contentStartPosition: CGPoint
    var containerExitPosition: CGPoint
    var finalFocusPosition: CGPoint
    var exitPathStyle: ExitPathStyle
    var exitCurveBias: CGFloat
    var flightArcHeight: CGFloat
    var flightSideBias: CGFloat
    var contentType: ContentTokenType
    var initialRotationPhase: CGFloat
}

/// Presets differ in weight, curve and flip — not in the state machine.
struct ContainerRevealPreset: Equatable {
    var exitPathStyle: ExitPathStyle
    var exitCurveBias: CGFloat
    var flightArcFactor: CGFloat
    var flightArcRange: ClosedRange<CGFloat>
    var sideBiasFactor: CGFloat
    var feedbackDuration: TimeInterval
    var exitDuration: TimeInterval
    var flyDuration: TimeInterval
    var pauseDuration: TimeInterval
    var collapseDuration: TimeInterval
    var cardDuration: TimeInterval
    var cardOverlap: TimeInterval
    var exitRotationY: Double
    var flyRotationY: Double
    var peakScale: CGFloat
    var motionExponent: CGFloat
    var collapseExponent: CGFloat
    var flightGlow: CGFloat

    /// Light, floating, longer curve, a clear Y-axis flip.
    static let star = ContainerRevealPreset(
        exitPathStyle: .curved,
        exitCurveBias: 0.42,
        flightArcFactor: 0.18,
        flightArcRange: 50...150,
        sideBiasFactor: 1.0,
        feedbackDuration: 0.25,
        exitDuration: 1.30,
        flyDuration: 1.65,
        pauseDuration: 0.35,
        collapseDuration: 0.60,
        cardDuration: 1.00,
        cardOverlap: 0.15,
        exitRotationY: 180,
        flyRotationY: 540,
        peakScale: 2.0,
        motionExponent: 1.40,
        collapseExponent: 1.35,
        flightGlow: 0.28
    )

    /// Steadier, more direct, smaller curve, less spin.
    static let capsule = ContainerRevealPreset(
        exitPathStyle: .straight,
        exitCurveBias: 0.16,
        flightArcFactor: 0.12,
        flightArcRange: 28...72,
        sideBiasFactor: 0.62,
        feedbackDuration: 0.17,
        exitDuration: 0.58,
        flyDuration: 1.05,
        pauseDuration: 0.55,
        collapseDuration: 0.34,
        cardDuration: 0.50,
        cardOverlap: 0.08,
        exitRotationY: 110,
        flyRotationY: 180,
        peakScale: 1.85,
        motionExponent: 1.72,
        collapseExponent: 1.5,
        flightGlow: 0.18
    )

    /// Heavier, a more obvious parabola, speed with weight.
    static let paperBall = ContainerRevealPreset(
        exitPathStyle: .curved,
        exitCurveBias: 0.28,
        flightArcFactor: 0.22,
        flightArcRange: 48...128,
        sideBiasFactor: 0.88,
        feedbackDuration: 0.18,
        exitDuration: 0.72,
        flyDuration: 1.35,
        pauseDuration: 0.68,
        collapseDuration: 0.40,
        cardDuration: 0.58,
        cardOverlap: 0.10,
        exitRotationY: 140,
        flyRotationY: 360,
        peakScale: 1.92,
        motionExponent: 1.88,
        collapseExponent: 1.55,
        flightGlow: 0.08
    )

    static func preset(for type: ContentTokenType) -> ContainerRevealPreset {
        switch type {
        case .star: return .star
        case .capsule: return .capsule
        case .paperBall: return .paperBall
        }
    }

    func animationConfiguration(reduceMotion: Bool) -> RevealAnimationConfiguration {
        if reduceMotion {
            return RevealAnimationConfiguration(
                feedbackDuration: 0.10,
                exitDuration: 0.22,
                flyDuration: 0.28,
                pauseDuration: 0.16,
                collapseDuration: 0.18,
                cardDuration: 0.26,
                cardOverlap: 0.08,
                exitRotationY: 0,
                flyRotationY: 0,
                peakScale: 1.12,
                motionExponent: 1.35,
                collapseExponent: 1.35,
                reduceMotion: true
            )
        }
        return RevealAnimationConfiguration(
            feedbackDuration: feedbackDuration,
            exitDuration: exitDuration,
            flyDuration: flyDuration,
            pauseDuration: pauseDuration,
            collapseDuration: collapseDuration,
            cardDuration: cardDuration,
            cardOverlap: cardOverlap,
            exitRotationY: exitRotationY,
            flyRotationY: flyRotationY,
            peakScale: peakScale,
            motionExponent: motionExponent,
            collapseExponent: collapseExponent,
            reduceMotion: false
        )
    }
}

enum ContainerRevealAnchors {
    static func exitUnit(for kind: ContainerKind) -> CGPoint {
        switch kind {
        case .star: return CGPoint(x: 0.50, y: 0.11)
        case .capsule: return CGPoint(x: 0.50, y: 0.34)
        case .paper: return CGPoint(x: 0.50, y: 0.32)
        }
    }

    static func contentSlots(for kind: ContainerKind) -> [CGPoint] {
        switch kind {
        case .star:
            return [CGPoint(x: 0.50, y: 0.62)]
        case .capsule:
            return [
                CGPoint(x: 0.36, y: 0.54), CGPoint(x: 0.55, y: 0.54), CGPoint(x: 0.67, y: 0.60),
                CGPoint(x: 0.43, y: 0.63), CGPoint(x: 0.58, y: 0.64), CGPoint(x: 0.31, y: 0.63),
                CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.70, y: 0.54)
            ]
        case .paper:
            return [
                CGPoint(x: 0.42, y: 0.72), CGPoint(x: 0.55, y: 0.74), CGPoint(x: 0.63, y: 0.69),
                CGPoint(x: 0.35, y: 0.77), CGPoint(x: 0.49, y: 0.79), CGPoint(x: 0.62, y: 0.78),
                CGPoint(x: 0.40, y: 0.67), CGPoint(x: 0.54, y: 0.68), CGPoint(x: 0.66, y: 0.73),
                CGPoint(x: 0.33, y: 0.71), CGPoint(x: 0.48, y: 0.75)
            ]
        }
    }

    static func contentSize(for kind: ContainerKind, in container: CGRect) -> CGSize {
        let width = max(container.width, 1)
        switch kind {
        case .star:
            let side = width * 0.44
            return CGSize(width: side, height: side)
        case .capsule:
            return CGSize(width: width * 0.22, height: width * 0.085)
        case .paper:
            let side = width * 0.145
            return CGSize(width: side, height: side)
        }
    }

    static func cardLayoutSize(in canvas: CGSize) -> CGSize {
        let width = min(max(canvas.width - 8, 300), 440)
        return CGSize(width: width, height: width * (1024.0 / 1536.0))
    }

    static func defaultFocus(
        canvas: CGSize,
        cardSize: CGSize,
        safeArea: EdgeInsets
    ) -> CGPoint {
        let usable = CGRect(
            x: safeArea.leading,
            y: safeArea.top,
            width: max(1, canvas.width - safeArea.leading - safeArea.trailing),
            height: max(1, canvas.height - safeArea.top - safeArea.bottom)
        )
        let minY = usable.minY + cardSize.height / 2 + 8
        let maxY = usable.maxY - cardSize.height / 2 - 72
        let y = min(max(usable.midY - 12, minY), max(minY, maxY))
        return CGPoint(x: usable.midX, y: y)
    }

    static func point(_ unit: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + unit.x * frame.width,
            y: frame.minY + unit.y * frame.height
        )
    }
}

enum RevealEasing {
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * clamp(t)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = clamp(t)
        return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }

    static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = clamp(t)
        return x * x * (3 - 2 * x)
    }

    static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        let x = clamp(t)
        if x < 0.5 {
            return 4 * x * x * x
        }
        return 1 - pow(-2 * x + 2, 3) / 2
    }

    static func easeIn(_ t: CGFloat) -> CGFloat {
        let x = clamp(t)
        return x * x
    }

    static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let x = clamp(t)
        return 1 - pow(1 - x, 3)
    }

    static func motionProgress(_ t: CGFloat, exponent: CGFloat) -> CGFloat {
        pow(clamp(t), exponent)
    }

    static func collapseProgress(_ t: CGFloat, exponent: CGFloat) -> CGFloat {
        pow(clamp(t), exponent)
    }

    static func cardReveal(_ t: CGFloat) -> CGFloat {
        easeOutCubic(t)
    }
}

struct RevealPath {
    let start: CGPoint
    let exit: CGPoint
    let release: CGPoint
    let focus: CGPoint
    let exitControl: CGPoint
    let flightControl: CGPoint
    let exitStyle: ExitPathStyle
    let exitSplit: CGFloat

    static func make(from input: ContainerRevealInput, instance: ContentRevealInstance) -> RevealPath {
        let start = instance.contentStartPosition
        let exit = instance.containerExitPosition
        let release = CGPoint(
            x: exit.x,
            y: exit.y - input.pathConfiguration.releaseLift
        )
        let focus = instance.finalFocusPosition
        let exitControl = exitControlPoint(
            start: start,
            exit: exit,
            release: release,
            bias: instance.exitCurveBias
        )
        let flightControl = CGPoint(
            x: (release.x + focus.x) / 2 + instance.flightSideBias,
            y: min(release.y, focus.y) - instance.flightArcHeight
        )
        let startToExit = hypot(exit.x - start.x, exit.y - start.y)
        let exitToRelease = hypot(release.x - exit.x, release.y - exit.y)
        let split = max(0.12, min(0.88, startToExit / max(startToExit + exitToRelease, 1)))
        return RevealPath(
            start: start,
            exit: exit,
            release: release,
            focus: focus,
            exitControl: exitControl,
            flightControl: flightControl,
            exitStyle: instance.exitPathStyle,
            exitSplit: split
        )
    }

    func exitPosition(t: CGFloat) -> CGPoint {
        let u = RevealEasing.clamp(t)
        switch exitStyle {
        case .straight:
            if u <= exitSplit {
                return RevealEasing.lerp(start, exit, u / max(exitSplit, 0.0001))
            }
            return RevealEasing.lerp(exit, release, (u - exitSplit) / max(1 - exitSplit, 0.0001))
        case .curved:
            return Self.quadratic(start, exitControl, release, u)
        }
    }

    func flightPosition(t: CGFloat) -> CGPoint {
        Self.quadratic(release, flightControl, focus, RevealEasing.clamp(t))
    }

    func reducedFlightPosition(t: CGFloat) -> CGPoint {
        RevealEasing.lerp(release, focus, RevealEasing.smoothstep(t))
    }

    static func quadratic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }

    /// Control point is derived from the content's side of the mouth, never a screen constant.
    private static func exitControlPoint(
        start: CGPoint,
        exit: CGPoint,
        release: CGPoint,
        bias: CGFloat
    ) -> CGPoint {
        let direction: CGFloat
        if abs(exit.x - start.x) < 1 {
            direction = 0
        } else {
            direction = exit.x > start.x ? 1 : -1
        }
        let curve = min(max(abs(exit.x - start.x) * 0.32, 8), 30) * bias
        return CGPoint(
            x: RevealEasing.lerp(start.x, exit.x, 0.55) + curve * direction,
            y: RevealEasing.lerp(start.y, exit.y, 0.45)
        )
    }
}

struct ContentTransform: Equatable {
    var position: CGPoint
    var scale: CGFloat
    var rotationY: Double
    var opacity: CGFloat
    var glow: CGFloat

    static let hidden = ContentTransform(
        position: .zero,
        scale: 1,
        rotationY: 0,
        opacity: 0,
        glow: 0
    )
}

struct CardTransform: Equatable {
    var position: CGPoint
    var scale: CGFloat
    var opacity: CGFloat

    static let hidden = CardTransform(position: .zero, scale: 0.1, opacity: 0)
}

struct ContainerFeedbackTransform: Equatable {
    var rotation: Angle
    var offsetX: CGFloat

    static let identity = ContainerFeedbackTransform(rotation: .zero, offsetX: 0)
}

struct RevealSample: Equatable {
    var stage: ContainerRevealStage
    var content: ContentTransform
    var card: CardTransform
    var container: ContainerFeedbackTransform
    var dim: CGFloat
    var contentLayer: RevealContentLayer
    var showsToken: Bool
    var cardInteractive: Bool
    var isFinished: Bool

    static let idle = RevealSample(
        stage: .idle,
        content: .hidden,
        card: .hidden,
        container: .identity,
        dim: 0,
        contentLayer: .foregroundFlight,
        showsToken: false,
        cardInteractive: false,
        isFinished: false
    )
}

enum RevealTransformEvaluator {
    static func evaluate(
        elapsed: TimeInterval,
        path: RevealPath,
        instance: ContentRevealInstance,
        input: ContainerRevealInput,
        configuration: RevealAnimationConfiguration,
        preset: ContainerRevealPreset,
        isDismissing: Bool,
        dismissElapsed: TimeInterval
    ) -> RevealSample {
        if isDismissing {
            return dismissSample(
                path: path,
                configuration: configuration,
                elapsed: dismissElapsed
            )
        }

        let timing = configuration
        let tFeedback = timing.feedbackDuration
        let tExit = tFeedback + timing.exitDuration
        let tFly = tExit + timing.flyDuration
        let tPause = tFly + timing.pauseDuration
        let tCollapse = tPause + timing.collapseDuration
        let cardStart = timing.cardStart
        let tCard = cardStart + timing.cardDuration

        let stage: ContainerRevealStage
        if elapsed < tFeedback {
            stage = .containerFeedback
        } else if elapsed < tExit {
            stage = .exitContainer
        } else if elapsed < tFly {
            stage = .flyToFocus
        } else if elapsed < tPause {
            stage = .focusPause
        } else if elapsed < tCollapse {
            stage = .collapse
        } else if elapsed < tCard {
            stage = .revealCard
        } else {
            stage = .complete
        }

        var container = ContainerFeedbackTransform.identity
        if elapsed < tFeedback {
            container = feedback(progress: elapsed / max(tFeedback, 0.0001))
        }

        var content = ContentTransform.hidden
        var showsToken = false
        if elapsed >= tFeedback {
            showsToken = true
            content = contentTransform(
                elapsed: elapsed,
                tFeedback: tFeedback,
                tExit: tExit,
                tFly: tFly,
                tPause: tPause,
                tCollapse: tCollapse,
                path: path,
                instance: instance,
                configuration: timing,
                preset: preset
            )
            if content.opacity <= 0.001 && elapsed >= tPause {
                showsToken = false
            }
        }

        var contentLayer = RevealContentLayer.foregroundFlight
        if instance.contentType == .star, showsToken, input.bottleMouthBounds != .zero {
            let halfHeight = input.contentVisualSize.height * content.scale * 0.5
            let starBottom = content.position.y + halfHeight
            // Stay behind the bottle until the full star clears the mouth lip.
            if starBottom >= input.bottleMouthBounds.minY - StarJarMetrics.layerClearance {
                contentLayer = .behindBottleForeground
            }
        }

        var card = CardTransform(position: path.focus, scale: 0.1, opacity: 0)
        if elapsed >= cardStart {
            let local = RevealEasing.clamp(CGFloat((elapsed - cardStart) / max(timing.cardDuration, 0.0001)))
            let progress = RevealEasing.cardReveal(local)
            card.scale = RevealEasing.lerp(0.1, 1.0, progress)
            card.opacity = RevealEasing.lerp(0.0, 1.0, progress)
        }

        let dim: CGFloat
        if elapsed < tFeedback {
            dim = 0
        } else if elapsed < tFly {
            dim = RevealEasing.smoothstep(CGFloat((elapsed - tFeedback) / max(tFly - tFeedback, 0.0001))) * 0.42
        } else {
            dim = 0.42
        }

        return RevealSample(
            stage: stage,
            content: content,
            card: card,
            container: container,
            dim: dim,
            contentLayer: contentLayer,
            showsToken: showsToken,
            cardInteractive: elapsed >= tCard - 0.04,
            isFinished: elapsed >= tCard
        )
    }

    private static func feedback(progress: CGFloat) -> ContainerFeedbackTransform {
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.0),
            (0.25, -1.5),
            (0.50, 1.5),
            (0.75, -0.7),
            (1.00, 0.0)
        ]
        let p = RevealEasing.clamp(progress)
        var angle: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            if p >= start.0, p <= end.0 {
                let local = RevealEasing.easeInOutCubic((p - start.0) / (end.0 - start.0))
                angle = RevealEasing.lerp(start.1, end.1, local)
                break
            }
        }
        return ContainerFeedbackTransform(
            rotation: .degrees(Double(angle)),
            offsetX: angle * 0.9
        )
    }

    private static func contentTransform(
        elapsed: TimeInterval,
        tFeedback: TimeInterval,
        tExit: TimeInterval,
        tFly: TimeInterval,
        tPause: TimeInterval,
        tCollapse: TimeInterval,
        path: RevealPath,
        instance: ContentRevealInstance,
        configuration: RevealAnimationConfiguration,
        preset: ContainerRevealPreset
    ) -> ContentTransform {
        let initial = Double(instance.initialRotationPhase)
        let reduce = configuration.reduceMotion

        if elapsed < tExit {
            let local = RevealEasing.clamp(CGFloat((elapsed - tFeedback) / max(configuration.exitDuration, 0.0001)))
            let eased = RevealEasing.easeInOutCubic(local)
            let position = path.exitPosition(t: eased)
            return ContentTransform(
                position: position,
                scale: 1,
                rotationY: initial + configuration.exitRotationY * Double(eased),
                opacity: 1,
                glow: preset.flightGlow * 0.35
            )
        }

        if elapsed < tFly {
            let local = RevealEasing.clamp(CGFloat((elapsed - tExit) / max(configuration.flyDuration, 0.0001)))
            let motion = RevealEasing.motionProgress(local, exponent: configuration.motionExponent)
            let position = reduce
                ? path.reducedFlightPosition(t: local)
                : path.flightPosition(t: motion)
            let scaleProgress = RevealEasing.clamp((local - 0.1) / 0.9)
            let scale = RevealEasing.lerp(1.0, configuration.peakScale, RevealEasing.easeInOutCubic(scaleProgress))
            return ContentTransform(
                position: position,
                scale: scale,
                rotationY: initial + configuration.exitRotationY + configuration.flyRotationY * Double(local),
                opacity: 1,
                glow: preset.flightGlow * RevealEasing.lerp(0.35, 1.0, local)
            )
        }

        let focused = ContentTransform(
            position: path.focus,
            scale: configuration.peakScale,
            rotationY: initial + configuration.exitRotationY + configuration.flyRotationY,
            opacity: 1,
            glow: preset.flightGlow
        )

        if elapsed < tPause {
            return focused
        }

        if elapsed < tCollapse {
            let local = RevealEasing.clamp(CGFloat((elapsed - tPause) / max(configuration.collapseDuration, 0.0001)))
            let collapse = RevealEasing.collapseProgress(local, exponent: configuration.collapseExponent)
            return ContentTransform(
                position: path.focus,
                scale: RevealEasing.lerp(configuration.peakScale, 0.1, collapse),
                rotationY: focused.rotationY,
                opacity: RevealEasing.lerp(1.0, 0.0, collapse),
                glow: focused.glow * (1 - collapse)
            )
        }

        return ContentTransform(
            position: path.focus,
            scale: 0.1,
            rotationY: focused.rotationY,
            opacity: 0,
            glow: 0
        )
    }

    private static func dismissSample(
        path: RevealPath,
        configuration: RevealAnimationConfiguration,
        elapsed: TimeInterval
    ) -> RevealSample {
        let duration: TimeInterval = configuration.reduceMotion ? 0.12 : 0.24
        let t = RevealEasing.clamp(CGFloat(elapsed / duration))
        let fade = RevealEasing.easeIn(t)
        return RevealSample(
            stage: .complete,
            content: .hidden,
            card: CardTransform(
                position: path.focus,
                scale: RevealEasing.lerp(1.0, 0.92, fade),
                opacity: 1 - fade
            ),
            container: .identity,
            dim: 0.42 * (1 - fade),
            contentLayer: .foregroundFlight,
            showsToken: false,
            cardInteractive: t < 0.35,
            isFinished: t >= 1
        )
    }
}

struct ContainerRevealLayout {
    static func makeInput(
        kind: ContainerKind,
        containerFrame: CGRect,
        exitAnchor: CGPoint,
        contentStart: CGPoint,
        contentSize: CGSize,
        canvasSize: CGSize,
        safeArea: EdgeInsets,
        reduceMotion: Bool,
        seed: Int,
        bottleMouthBounds: CGRect = .zero,
        releaseLift: CGFloat = RevealPathConfiguration.releaseLiftDefault
    ) -> (ContainerRevealInput, ContentRevealInstance) {
        let type = ContentTokenType(kind)
        let preset = ContainerRevealPreset.preset(for: type)
        let cardSize = ContainerRevealAnchors.cardLayoutSize(in: canvasSize)
        let focus = ContainerRevealAnchors.defaultFocus(
            canvas: canvasSize,
            cardSize: cardSize,
            safeArea: safeArea
        )
        let cardFrame = CGRect(
            x: focus.x - cardSize.width / 2,
            y: focus.y - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
        let release = CGPoint(x: exitAnchor.x, y: exitAnchor.y - releaseLift)
        let distance = hypot(focus.x - release.x, focus.y - release.y)
        var arcHeight = min(
            max(distance * preset.flightArcFactor, preset.flightArcRange.lowerBound),
            preset.flightArcRange.upperBound
        )
        let verticalRoom = min(release.y, focus.y)
        if verticalRoom < 90 {
            arcHeight *= max(0.35, verticalRoom / 90)
        }
        if distance < 90 {
            arcHeight *= 0.42
        }
        if reduceMotion {
            arcHeight *= 0.22
        }

        let canvasMidX = canvasSize.width / 2
        let containerOffset = containerFrame.midX - canvasMidX
        let outward: CGFloat
        if abs(containerOffset) > 8 {
            outward = containerOffset < 0 ? -1 : 1
        } else {
            outward = contentStart.x <= exitAnchor.x ? -1 : 1
        }
        var sideBias = outward * min(max(abs(focus.x - release.x) * 0.22 + 16, 12), 56) * preset.sideBiasFactor
        if reduceMotion {
            sideBias *= 0.15
        }

        let pathConfiguration = RevealPathConfiguration(
            exitPathStyle: reduceMotion ? .straight : preset.exitPathStyle,
            exitCurveBias: reduceMotion ? 0 : preset.exitCurveBias,
            flightArcHeight: arcHeight,
            flightSideBias: sideBias,
            releaseLift: releaseLift
        )
        let animation = preset.animationConfiguration(reduceMotion: reduceMotion)
        let input = ContainerRevealInput(
            containerFrame: containerFrame,
            bottleMouthBounds: bottleMouthBounds,
            containerExitAnchor: exitAnchor,
            contentStartPosition: contentStart,
            contentVisualSize: contentSize,
            finalCardFrame: cardFrame,
            pathConfiguration: pathConfiguration,
            animationConfiguration: animation
        )
        let boundedSeed = UInt(truncatingIfNeeded: seed) % 50
        let phase = CGFloat((boundedSeed * 47 + 13) % 50) - 18
        let instance = ContentRevealInstance(
            contentStartPosition: contentStart,
            containerExitPosition: exitAnchor,
            finalFocusPosition: focus,
            exitPathStyle: pathConfiguration.exitPathStyle,
            exitCurveBias: pathConfiguration.exitCurveBias,
            flightArcHeight: pathConfiguration.flightArcHeight,
            flightSideBias: pathConfiguration.flightSideBias,
            contentType: type,
            initialRotationPhase: reduceMotion ? 0 : phase
        )
        return (input, instance)
    }
}

@MainActor
final class ContainerRevealAnimationController: ObservableObject {
    @Published private(set) var sample: RevealSample = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var item: SecretItem?
    @Published private(set) var token: RevealContentToken?
    @Published private(set) var cardFrame: CGRect = .zero
    @Published private(set) var containerFrame: CGRect = .zero

    private(set) var preset: ContainerRevealPreset = .star

    private var session: Session?
    private var driver: CADisplayLink?
    private let proxy = DisplayLinkProxy()
    private var lastStage: ContainerRevealStage = .idle
    private var didArriveHaptic = false
    private var didCardHaptic = false

    private struct Session {
        var startedAt: TimeInterval
        var input: ContainerRevealInput
        var instance: ContentRevealInstance
        var path: RevealPath
        var preset: ContainerRevealPreset
        var isDismissing: Bool
        var dismissStartedAt: TimeInterval
        var hasClearedBottleMouth: Bool
    }

    init() {
        proxy.handler = { [weak self] in
            self?.tick()
        }
    }

    deinit {
        driver?.invalidate()
        driver = nil
    }

    var containerFeedback: ContainerFeedbackTransform { sample.container }
    var hidesLiftedContent: Bool { isPlaying && sample.stage != .idle }
    var isShowingCard: Bool { sample.card.opacity > 0.6 }

    func play(
        input: ContainerRevealInput,
        instance: ContentRevealInstance,
        token: RevealContentToken,
        item: SecretItem
    ) {
        stopDriver()
        self.token = token
        self.item = item
        self.preset = ContainerRevealPreset.preset(for: instance.contentType)
        self.cardFrame = input.finalCardFrame
        self.containerFrame = input.containerFrame
        let path = RevealPath.make(from: input, instance: instance)
        session = Session(
            startedAt: CACurrentMediaTime(),
            input: input,
            instance: instance,
            path: path,
            preset: preset,
            isDismissing: false,
            dismissStartedAt: 0,
            hasClearedBottleMouth: false
        )
        lastStage = .idle
        didArriveHaptic = false
        didCardHaptic = false
        isPlaying = true
        sample = evaluate(at: CACurrentMediaTime())
        startDriver()
        RitualHaptics.soft()
    }

    func dismiss() {
        guard var session, !session.isDismissing else { return }
        session.isDismissing = true
        session.dismissStartedAt = CACurrentMediaTime()
        self.session = session
        isPlaying = true
        startDriver()
        RitualHaptics.soft()
    }

    func reset() {
        stopDriver()
        session = nil
        sample = .idle
        isPlaying = false
        item = nil
        token = nil
        cardFrame = .zero
        containerFrame = .zero
        lastStage = .idle
        didArriveHaptic = false
        didCardHaptic = false
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let next = evaluate(at: now)
        if next.stage != lastStage {
            handleStageChange(next.stage)
            lastStage = next.stage
        }
        sample = next
        if session?.isDismissing == true, next.isFinished {
            reset()
        } else if next.isFinished, session?.isDismissing != true {
            stopDriver()
        }
    }

    private func evaluate(at time: TimeInterval) -> RevealSample {
        guard var session else { return .idle }
        let elapsed = max(0, time - session.startedAt)
        let dismissElapsed = session.isDismissing ? max(0, time - session.dismissStartedAt) : 0
        var sample = RevealTransformEvaluator.evaluate(
            elapsed: elapsed,
            path: session.path,
            instance: session.instance,
            input: session.input,
            configuration: session.input.animationConfiguration,
            preset: session.preset,
            isDismissing: session.isDismissing,
            dismissElapsed: dismissElapsed
        )

        if session.instance.contentType == .star {
            if session.hasClearedBottleMouth {
                sample.contentLayer = .foregroundFlight
            } else if sample.contentLayer == .foregroundFlight, sample.showsToken {
                session.hasClearedBottleMouth = true
                self.session = session
            }
        }

        return sample
    }

    private func handleStageChange(_ stage: ContainerRevealStage) {
        switch stage {
        case .focusPause:
            if !didArriveHaptic {
                didArriveHaptic = true
                RitualHaptics.soft()
            }
        case .revealCard, .complete:
            if !didCardHaptic {
                didCardHaptic = true
                RitualHaptics.success()
            }
        default:
            break
        }
    }

    private func startDriver() {
        stopDriver()
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        driver = link
    }

    private func stopDriver() {
        driver?.invalidate()
        driver = nil
    }
}

private final class DisplayLinkProxy: NSObject {
    var handler: (() -> Void)?

    @objc func fire() {
        handler?()
    }
}

enum RevealAnchorID: Hashable {
    case container
    case exit
    case content
}

struct RevealAnchorFrames: Equatable {
    var container: CGRect = .zero
    var exit: CGRect = .zero
    var content: CGRect = .zero

    var hasContent: Bool { content != .zero && content.width > 1 }
    var hasExit: Bool { exit != .zero }
    var hasContainer: Bool { container != .zero && container.width > 1 }

    var contentCenter: CGPoint { CGPoint(x: content.midX, y: content.midY) }
    var exitCenter: CGPoint { CGPoint(x: exit.midX, y: exit.midY) }
}

struct RevealAnchorKey: PreferenceKey {
    static var defaultValue: [ContainerKind: RevealAnchorFrames] = [:]

    static func reduce(
        value: inout [ContainerKind: RevealAnchorFrames],
        nextValue: () -> [ContainerKind: RevealAnchorFrames]
    ) {
        for (kind, frames) in nextValue() {
            var merged = value[kind] ?? RevealAnchorFrames()
            if frames.container != .zero { merged.container = frames.container }
            if frames.exit != .zero { merged.exit = frames.exit }
            if frames.content != .zero { merged.content = frames.content }
            value[kind] = merged
        }
    }
}

struct RevealAnchorProbe: View {
    var kind: ContainerKind = .star
    let id: RevealAnchorID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RevealAnchorKey.self,
                value: [kind: frameValue(proxy.frame(in: .named(ContainerRevealSpace.name)))]
            )
        }
        .allowsHitTesting(false)
    }

    private func frameValue(_ frame: CGRect) -> RevealAnchorFrames {
        var value = RevealAnchorFrames()
        switch id {
        case .container: value.container = frame
        case .exit: value.exit = frame
        case .content: value.content = frame
        }
        return value
    }
}
