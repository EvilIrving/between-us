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
    func startFrames(_ handler: @escaping () -> Void)
    func stopFrames()
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
class NativeAnimationDriver: AnimationDriver {
    private let frameProxy = AnimationFrameProxy()
    private var displayLink: CADisplayLink?
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init() {
        frameProxy.handler = { [weak self] in
            self?.frameHandler?()
        }
    }

    private var frameHandler: (() -> Void)?

    func startFrames(_ handler: @escaping () -> Void) {
        stopFrames()
        frameHandler = handler
        let link = CADisplayLink(target: frameProxy, selector: #selector(AnimationFrameProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopFrames() {
        displayLink?.invalidate()
        displayLink = nil
        frameHandler = nil
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
        tasks[id] = Task { @MainActor [weak self] in
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
                let raw = CGFloat(elapsed / max(duration, 0.0001))
                let value = from + (to - from) * curve.value(at: raw)
                update(value)
                if raw >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard !Task.isCancelled else { return }
            update(to)
            completion()
            self?.tasks[id] = nil
        }
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
        animate(
            from: from,
            to: to,
            duration: configuration.response,
            curve: .easeOutCubic,
            update: update,
            completion: completion
        )
    }

    func retarget(_ id: UUID, to value: CGFloat) {
        // Native timed animations restart at the owning plugin's current value.
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        stopFrames()
    }
}

@MainActor
final class WaveAnimationDriver: NativeAnimationDriver {
    private var waveAnimators: [UUID: SpringAnimator<CGFloat>] = [:]

    override func spring(
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
            self?.waveAnimators[id] = nil
        }
        waveAnimators[id] = animator
        animator.start()
        return id
    }

    override func retarget(_ id: UUID, to value: CGFloat) {
        waveAnimators[id]?.target = value
    }

    override func cancel(_ id: UUID) {
        guard let animator = waveAnimators.removeValue(forKey: id) else {
            super.cancel(id)
            return
        }
        animator.completion = nil
        animator.valueChanged = nil
        animator.stop(immediately: true)
        super.cancel(id)
    }

    override func cancelAll() {
        let animators = Array(waveAnimators.values)
        waveAnimators.removeAll()
        for animator in animators {
            animator.completion = nil
            animator.valueChanged = nil
            animator.stop(immediately: true)
        }
        super.cancelAll()
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
