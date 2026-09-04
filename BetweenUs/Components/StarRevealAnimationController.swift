import Combine
import SwiftUI

@MainActor
final class StarRevealAnimationController: ObservableObject {
    let physics: StarJarPhysicsSystem
    let reveal: ContainerContentRevealController

    @Published private(set) var context: RevealContext?

    private var cancellables: Set<AnyCancellable> = []
    private var targetStar: StarPhysicsState?
    private var didDetachTarget = false

    init() {
        self.physics = StarJarPhysicsSystem()
        self.reveal = ContainerContentRevealController()

        physics.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        reveal.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        reveal.$sample
            .sink { [weak self] sample in
                self?.handle(sample: sample)
            }
            .store(in: &cancellables)
    }

    var sample: RevealSample { reveal.sample }
    var isPlaying: Bool { reveal.isPlaying }

    func configureBottle(side: CGFloat, count: Int) {
        physics.configure(side: side)
        physics.setStarCount(count, animated: false)
    }

    @discardableResult
    func play(
        item: SecretItem,
        bottleFrame: CGRect,
        canvasSize: CGSize,
        safeArea: EdgeInsets,
        reduceMotion: Bool
    ) -> Bool {
        guard !reveal.isPlaying,
              bottleFrame.width > 1,
              let target = physics.topmostStar()
        else { return false }

        targetStar = target
        didDetachTarget = false

        let side = max(physics.side, bottleFrame.width)
        let contentStart = StarJarCoordinates.space(
            fromLocal: target.position,
            bottleFrame: bottleFrame,
            side: side
        )
        let exit = StarJarCoordinates.space(
            fromLocal: physics.mouthCenter,
            bottleFrame: bottleFrame,
            side: side
        )
        let localMouth = physics.mouthBounds
        let mouthBounds = CGRect(
            x: bottleFrame.minX + localMouth.minX / side * bottleFrame.width,
            y: bottleFrame.minY + localMouth.minY / side * bottleFrame.height,
            width: localMouth.width / side * bottleFrame.width,
            height: localMouth.height / side * bottleFrame.height
        )
        let visualSide = target.visualSize / side * bottleFrame.width
        let contentSize = CGSize(width: visualSide, height: visualSide)
        let mouthCenterToTop = exit.y - mouthBounds.minY
        let releaseLift = max(
            StarJarMetrics.releaseLift,
            contentSize.height * 0.5 + mouthCenterToTop + StarJarMetrics.layerClearance
        )
        let canvas = canvasSize.width > 1 ? canvasSize : UIScreen.main.bounds.size
        let (input, instance) = ContainerRevealLayout.makeInput(
            kind: .star,
            containerFrame: bottleFrame,
            exitAnchor: exit,
            contentStart: contentStart,
            contentSize: contentSize,
            canvasSize: canvas,
            safeArea: safeArea,
            reduceMotion: reduceMotion,
            seed: target.creationIndex,
            containerOpeningBounds: mouthBounds,
            releaseLift: releaseLift
        )

        let preset = ContainerRevealPreset.star
        context = RevealContext(
            containerFrame: bottleFrame,
            bottleMouthBounds: mouthBounds,
            contentStartPosition: contentStart,
            containerExitPosition: exit,
            finalFocusPosition: instance.finalFocusPosition,
            finalCardFrame: input.finalCardFrame,
            exitPathStyle: instance.exitPathStyle,
            exitCurveBias: instance.exitCurveBias,
            flightSideBias: instance.flightSideBias,
            flightArcFactor: preset.flightArcFactor,
            initialRotationY: instance.initialRotationPhase,
            contentType: .star
        )

        let token = RevealContentToken(
            type: .star,
            imageName: target.charm.imageName,
            seed: target.creationIndex,
            visualSize: contentSize
        )
        reveal.play(input: input, instance: instance, token: token, item: item)
        return true
    }

    func dismiss() {
        reveal.dismiss()
    }

    func reset() {
        reveal.reset()
        targetStar = nil
        didDetachTarget = false
        context = nil
    }

    func spawnNewStar() {
        physics.spawnStar(animated: true)
    }

    private func handle(sample: RevealSample) {
        guard sample.stage == .exitContainer,
              !didDetachTarget,
              let targetStar
        else { return }
        didDetachTarget = true
        _ = physics.detachStar(id: targetStar.id)
    }
}
