import QuartzCore
import SwiftUI
import Wave

enum RotationStrategy: Equatable {
    case none
    case zAxis2D
    case axis3D(x: Float, y: Float, z: Float)
}

struct PathPreset: Equatable {
    var exitStyle: ExitPathStyle
    var exitCurveBias: CGFloat
    var flightArcFactor: CGFloat
    var flightArcRange: ClosedRange<CGFloat>
    var sideBiasFactor: CGFloat
    var releaseLift: CGFloat
}

struct TimingPreset: Equatable {
    var feedback: TimeInterval
    var preparation: TimeInterval
    var exit: TimeInterval
    var flight: TimeInterval
    var focusPause: TimeInterval
    var collapse: TimeInterval
    var cardReveal: TimeInterval
    var cardOverlap: TimeInterval
}

struct ScalePreset: Equatable {
    var start: CGFloat
    var focus: CGFloat
    var collapsed: CGFloat
    var delayedGrowthFraction: CGFloat
}

struct OpacityPreset: Equatable {
    var visible: CGFloat
    var hidden: CGFloat
}

struct PhysicsPreset: Equatable {
    var gravity: CGFloat
    var mass: CGFloat
    var friction: CGFloat
    var restitution: CGFloat
    var linearDamping: CGFloat
    var angularDamping: CGFloat
    var sleepVelocityThreshold: CGFloat
    var sleepAngularThreshold: CGFloat
    var stableDuration: TimeInterval

    static let trash = PhysicsPreset(
        gravity: 5.4,
        mass: 1.0,
        friction: 0.62,
        restitution: 0.045,
        linearDamping: 0.72,
        angularDamping: 0.80,
        sleepVelocityThreshold: 6,
        sleepAngularThreshold: 0.32,
        stableDuration: 0.38
    )
}

struct DriverSpring: Equatable {
    var dampingRatio: CGFloat
    var response: CGFloat
    var mass: CGFloat = 1

    static let heavyMetal = DriverSpring(dampingRatio: 1.0, response: 0.72, mass: 1.35)
}

enum DriverCurve {
    case linear
    case easeInOutCubic
    case easeOutCubic

    func value(at progress: CGFloat) -> CGFloat {
        switch self {
        case .linear:
            return RevealEasing.clamp(progress)
        case .easeInOutCubic:
            return RevealEasing.easeInOutCubic(progress)
        case .easeOutCubic:
            return RevealEasing.easeOutCubic(progress)
        }
    }
}

@MainActor
protocol AnimationDriver: AnyObject {
    @discardableResult
    func startFrames(_ handler: @escaping () -> Void) -> UUID
    func stopFrames(_ id: UUID)
    @discardableResult
    func animate(
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval,
        curve: DriverCurve,
        update: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void
    ) -> UUID
    @discardableResult
    func spring(
        from: CGFloat,
        to: CGFloat,
        configuration: DriverSpring,
        update: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void
    ) -> UUID
    func retarget(_ id: UUID, to value: CGFloat)
    func cancel(_ id: UUID)
    func cancelAll()
}

@MainActor
final class WaveAnimationDriver: AnimationDriver {
    private struct TimedAnimation {
        var from: CGFloat
        var to: CGFloat
        var start: TimeInterval
        var duration: TimeInterval
        var curve: DriverCurve
        var update: (CGFloat) -> Void
        var completion: () -> Void
    }

    private let frameProxy = AnimationFrameProxy()
    private var displayLink: CADisplayLink?
    private var frameHandlers: [UUID: () -> Void] = [:]
    private var timedAnimations: [UUID: TimedAnimation] = [:]
    private var springs: [UUID: SpringAnimator<CGFloat>] = [:]

    init() {
        frameProxy.handler = { [weak self] in
            self?.tick()
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    @discardableResult
    func startFrames(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        frameHandlers[id] = handler
        ensureDisplayLink()
        return id
    }

    func stopFrames(_ id: UUID) {
        frameHandlers[id] = nil
        stopDisplayLinkIfIdle()
    }

    @discardableResult
    func animate(
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval,
        curve: DriverCurve,
        update: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void
    ) -> UUID {
        let id = UUID()
        timedAnimations[id] = TimedAnimation(
            from: from,
            to: to,
            start: CACurrentMediaTime(),
            duration: max(duration, 0.0001),
            curve: curve,
            update: update,
            completion: completion
        )
        update(from)
        ensureDisplayLink()
        return id
    }

    @discardableResult
    func spring(
        from: CGFloat,
        to: CGFloat,
        configuration: DriverSpring,
        update: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void
    ) -> UUID {
        let id = UUID()
        let model = Spring(
            dampingRatio: configuration.dampingRatio,
            response: configuration.response,
            mass: configuration.mass
        )
        let animator = SpringAnimator<CGFloat>(spring: model, value: from, target: to)
        animator.integralizeValues = false
        animator.valueChanged = update
        animator.completion = { [weak self] event in
            guard case .finished = event else { return }
            completion()
            self?.springs[id] = nil
        }
        springs[id] = animator
        animator.start()
        return id
    }

    func retarget(_ id: UUID, to value: CGFloat) {
        springs[id]?.target = value
    }

    func cancel(_ id: UUID) {
        if let animator = springs.removeValue(forKey: id) {
            animator.completion = nil
            animator.valueChanged = nil
            animator.stop(immediately: true)
        }
        let timedCompletion = timedAnimations.removeValue(forKey: id)?.completion
        frameHandlers[id] = nil
        stopDisplayLinkIfIdle()
        timedCompletion?()
    }

    func cancelAll() {
        let animators = Array(springs.values)
        springs.removeAll()
        for animator in animators {
            animator.completion = nil
            animator.valueChanged = nil
            animator.stop(immediately: true)
        }
        timedAnimations.removeAll()
        frameHandlers.removeAll()
        stopDisplayLink()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        for handler in frameHandlers.values {
            handler()
        }

        let identifiers = Array(timedAnimations.keys)
        for id in identifiers {
            guard let animation = timedAnimations[id] else { continue }
            let raw = CGFloat((now - animation.start) / animation.duration)
            let progress = animation.curve.value(at: raw)
            animation.update(animation.from + (animation.to - animation.from) * progress)
            if raw >= 1 {
                timedAnimations[id] = nil
                animation.update(animation.to)
                animation.completion()
            }
        }
        stopDisplayLinkIfIdle()
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: frameProxy, selector: #selector(AnimationFrameProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLinkIfIdle() {
        guard frameHandlers.isEmpty, timedAnimations.isEmpty else { return }
        stopDisplayLink()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

@MainActor
protocol ContainerPreparationPlugin: AnyObject {
    var preparationDuration: TimeInterval { get }
    func prepare(reduceMotion: Bool)
    func updatePreparation(progress: CGFloat)
    func holdOpen()
}

@MainActor
protocol ContainerRestorationPlugin: AnyObject {
    var restorationDuration: TimeInterval { get }
    func restore(reduceMotion: Bool)
    func updateRestoration(progress: CGFloat)
    func finishRestoration()
}

private final class AnimationFrameProxy: NSObject {
    var handler: (() -> Void)?

    @objc func fire() {
        handler?()
    }
}

extension ContainerRevealPreset {
    var pathPreset: PathPreset {
        PathPreset(
            exitStyle: exitPathStyle,
            exitCurveBias: exitCurveBias,
            flightArcFactor: flightArcFactor,
            flightArcRange: flightArcRange,
            sideBiasFactor: sideBiasFactor,
            releaseLift: RevealPathConfiguration.releaseLiftDefault
        )
    }

    var timingPreset: TimingPreset {
        TimingPreset(
            feedback: feedbackDuration,
            preparation: preparationDuration,
            exit: exitDuration,
            flight: flyDuration,
            focusPause: pauseDuration,
            collapse: collapseDuration,
            cardReveal: cardDuration,
            cardOverlap: cardOverlap
        )
    }

    var scalePreset: ScalePreset {
        ScalePreset(start: 1, focus: peakScale, collapsed: 0.1, delayedGrowthFraction: 0.12)
    }

    var opacityPreset: OpacityPreset {
        OpacityPreset(visible: 1, hidden: 0)
    }
}

typealias RevealAnimationPreset = ContainerRevealPreset
