import SwiftUI

struct ContentStorePreset: Equatable {
    var flightDuration: TimeInterval
    var entryDuration: TimeInterval
    var arcFactor: CGFloat
    var arcRange: ClosedRange<CGFloat>
    var motionExponent: CGFloat
    var rotationAmount: Double
    var scaleAtOpening: CGFloat

    static let trash = ContentStorePreset(
        flightDuration: 1.20,
        entryDuration: 0.52,
        arcFactor: 0.14,
        arcRange: 42...110,
        motionExponent: 1.28,
        rotationAmount: 24,
        scaleAtOpening: 0.72
    )
}

struct ContentStoreSample: Equatable {
    var content: ContentTransform = .hidden
    var layer: RevealContentLayer = .foregroundFlight
    var isPlaying = false
}

@MainActor
final class ContainerContentStoreController: ObservableObject {
    @Published private(set) var sample = ContentStoreSample()
    @Published private(set) var token: RevealContentToken?

    private let animationDriver: AnimationDriver
    private var task: Task<Void, Never>?

    init() {
        self.animationDriver = NativeAnimationDriver()
    }

    init(animationDriver: AnimationDriver) {
        self.animationDriver = animationDriver
    }

    deinit {
        task?.cancel()
    }

    func run(
        startPosition: CGPoint,
        openingCenter: CGPoint,
        openingBounds: CGRect,
        token: RevealContentToken,
        preset: ContentStorePreset,
        preparation: ContainerPreparationPlugin,
        restoration: ContainerRestorationPlugin,
        reduceMotion: Bool,
        attachDynamic: @escaping () -> Void
    ) {
        cancel()
        self.token = token
        sample = ContentStoreSample(
            content: ContentTransform(
                position: startPosition,
                scale: 1,
                rotationY: 0,
                rotationZ: 0,
                opacity: 1,
                glow: 0
            ),
            layer: .foregroundFlight,
            isPlaying: true
        )

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            preparation.prepare(reduceMotion: reduceMotion)
            await animateProgress(duration: reduceMotion ? 0.18 : preparation.preparationDuration) { progress in
                preparation.updatePreparation(progress: progress)
            }
            guard !Task.isCancelled else { return }
            preparation.holdOpen()

            let release = CGPoint(x: openingCenter.x, y: openingCenter.y - 28)
            let distance = hypot(release.x - startPosition.x, release.y - startPosition.y)
            let arc = min(max(distance * preset.arcFactor, preset.arcRange.lowerBound), preset.arcRange.upperBound)
            let side: CGFloat = startPosition.x <= openingCenter.x ? -1 : 1
            let control = CGPoint(
                x: (startPosition.x + release.x) / 2 + side * min(42, distance * 0.12),
                y: min(startPosition.y, release.y) - arc
            )

            await animateProgress(duration: reduceMotion ? 0.24 : preset.flightDuration) { progress in
                let motion = pow(progress, preset.motionExponent)
                self.sample.content.position = RevealPath.quadratic(startPosition, control, release, motion)
                self.sample.content.rotationZ = preset.rotationAmount * Double(side) * Double(progress)
                self.sample.content.scale = RevealEasing.lerp(1, preset.scaleAtOpening, RevealEasing.easeInOutCubic(progress))
            }
            guard !Task.isCancelled else { return }

            await animateProgress(duration: reduceMotion ? 0.12 : preset.entryDuration) { progress in
                let eased = RevealEasing.easeInOutCubic(progress)
                self.sample.content.position = RevealEasing.lerp(release, openingCenter, eased)
                self.sample.content.rotationZ = preset.rotationAmount * Double(side) * Double(1 - eased)
                self.sample.content.scale = RevealEasing.lerp(preset.scaleAtOpening, 0.62, eased)
                let top = self.sample.content.position.y - token.visualSize.height * self.sample.content.scale * 0.5
                if top >= openingBounds.minY {
                    self.sample.layer = .behindContainerForeground
                }
            }
            guard !Task.isCancelled else { return }

            sample.content.opacity = 0
            attachDynamic()
            restoration.restore(reduceMotion: reduceMotion)
            await animateProgress(duration: reduceMotion ? 0.12 : restoration.restorationDuration) { progress in
                restoration.updateRestoration(progress: progress)
            }
            restoration.finishRestoration()
            sample = ContentStoreSample()
            self.token = nil
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        animationDriver.cancelAll()
        sample = ContentStoreSample()
        token = nil
    }

    private func animateProgress(
        duration: TimeInterval,
        update: @escaping (CGFloat) -> Void
    ) async {
        await withCheckedContinuation { continuation in
            animationDriver.animate(
                from: 0,
                to: 1,
                duration: duration,
                curve: .linear,
                update: update,
                completion: { continuation.resume() }
            )
        }
    }
}

struct ContainerStoreOverlay: View {
    @ObservedObject var controller: ContainerContentStoreController
    var containerFrame: CGRect

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let token = controller.token, controller.sample.isPlaying {
                    RevealTokenView(token: token)
                        .frame(width: token.visualSize.width, height: token.visualSize.height)
                        .scaleEffect(controller.sample.content.scale)
                        .rotationEffect(.degrees(controller.sample.content.rotationZ))
                        .opacity(controller.sample.content.opacity)
                        .position(controller.sample.content.position)
                        .allowsHitTesting(false)

                    if controller.sample.layer == .behindContainerForeground {
                        TrashBinForegroundLayer()
                            .frame(width: containerFrame.width, height: containerFrame.height)
                            .position(x: containerFrame.midX, y: containerFrame.midY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}
