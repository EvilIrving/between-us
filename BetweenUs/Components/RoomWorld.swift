import Combine
import SwiftUI

@MainActor
final class RoomWorld: ObservableObject {
    static let sharedClock = WaveAnimationDriver()

    let starPhysics: StarJarPhysicsSystem
    let trashPhysics: TrashBinPhysicsSystem
    let trashLid: TrashLidController
    let capsuleLid: CapsuleJarLidController
    let reveal: ContainerContentRevealController
    let starReveal: StarRevealAnimationController
    let contentStore: ContainerContentStoreController

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let clock = Self.sharedClock
        starPhysics = StarJarPhysicsSystem()
        trashPhysics = TrashBinPhysicsSystem()
        trashLid = TrashLidController(animationDriver: clock)
        capsuleLid = CapsuleJarLidController(animationDriver: clock)
        reveal = ContainerContentRevealController(animationDriver: clock)
        starReveal = StarRevealAnimationController(
            physics: starPhysics,
            reveal: ContainerContentRevealController(animationDriver: clock)
        )
        contentStore = ContainerContentStoreController(animationDriver: clock)

        for publisher in [
            starPhysics.objectWillChange,
            trashPhysics.objectWillChange,
            trashLid.objectWillChange,
            capsuleLid.objectWillChange,
            reveal.objectWillChange,
            starReveal.objectWillChange,
            contentStore.objectWillChange
        ] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    var isBusy: Bool {
        reveal.isPlaying || starReveal.isPlaying || contentStore.sample.isPlaying
    }

    func canPresent(kind: ContainerKind, data: AppData) -> Bool {
        guard !isBusy else { return false }
        guard data.activeCredits(kind: kind) > 0,
              data.unopenedCountFromCounterpart(kind: kind) > 0 else { return false }
        switch kind {
        case .star:
            return starPhysics.topmostStar() != nil
        case .paper:
            return trashPhysics.selectEmotion() != nil
        case .capsule:
            return true
        }
    }

    func beginReveal(
        kind: ContainerKind,
        item: SecretItem,
        anchors: RevealAnchorFrames,
        canvasSize: CGSize,
        safeArea: EdgeInsets,
        reduceMotion: Bool
    ) -> Bool {
        guard !isBusy, anchors.hasContainer else { return false }
        let canvas = canvasSize.width > 1 ? canvasSize : UIScreen.main.bounds.size

        switch kind {
        case .star:
            return starReveal.play(
                item: item,
                bottleFrame: anchors.container,
                canvasSize: canvas,
                safeArea: safeArea,
                reduceMotion: reduceMotion
            )
        case .paper:
            guard let target = trashPhysics.selectEmotion() else { return false }
            let start = trashPhysics.globalPosition(of: target, containerFrame: anchors.container)
            let exit = trashPhysics.globalOpeningCenter(containerFrame: anchors.container)
            let openingBounds = trashPhysics.globalOpeningBounds(containerFrame: anchors.container)
            let visualSide = target.visualSize / max(trashPhysics.scene.size.width, 1) * anchors.container.width
            let contentSize = CGSize(width: visualSide, height: visualSide)
            let releaseLift = max(20, contentSize.height * 0.5 + exit.y - openingBounds.minY + 4)
            let (input, instance) = ContainerRevealLayout.makeInput(
                kind: .paper,
                containerFrame: anchors.container,
                exitAnchor: exit,
                contentStart: start,
                contentSize: contentSize,
                canvasSize: canvas,
                safeArea: safeArea,
                reduceMotion: reduceMotion,
                seed: target.creationIndex,
                containerOpeningBounds: openingBounds,
                releaseLift: releaseLift
            )
            reveal.play(
                input: input,
                instance: instance,
                token: RevealContentToken(
                    type: .paperBall,
                    imageName: target.imageName,
                    seed: target.creationIndex,
                    visualSize: contentSize
                ),
                item: item,
                preparation: trashLid,
                restoration: trashLid,
                onTransferBegan: { [weak self] in
                    _ = self?.trashPhysics.detach(target.id)
                }
            )
            return true
        case .capsule:
            let slots = ContainerRevealAnchors.contentSlots(for: .capsule)
            let slot = slots[min(max(slots.count - 1, 0), slots.count - 1)]
            let contentStart = anchors.hasContent
                ? anchors.contentCenter
                : ContainerRevealAnchors.point(slot, in: anchors.container)
            let exit = anchors.hasExit
                ? anchors.exitCenter
                : ContainerRevealAnchors.point(ContainerRevealAnchors.exitUnit(for: .capsule), in: anchors.container)
            let contentSize = CapsuleJarMetrics.tokenSize(in: anchors.container)
            let (input, instance) = ContainerRevealLayout.makeInput(
                kind: .capsule,
                containerFrame: anchors.container,
                exitAnchor: exit,
                contentStart: contentStart,
                contentSize: contentSize,
                canvasSize: canvas,
                safeArea: safeArea,
                reduceMotion: reduceMotion,
                seed: item.id.hashValue,
                containerOpeningBounds: CapsuleJarMetrics.openingBounds(in: anchors.container),
                releaseLift: contentSize.height * 0.6 + 12,
                initialRotation: 0
            )
            reveal.play(
                input: input,
                instance: instance,
                token: RevealContentToken(
                    type: .capsule,
                    imageName: "Capsule_Closed",
                    seed: abs(item.id.hashValue % 11),
                    visualSize: contentSize
                ),
                item: item,
                preparation: capsuleLid,
                restoration: capsuleLid
            )
            return true
        }
    }

    func storePaperIfNeeded(
        currentCount: Int,
        previousVisualCount: Int,
        composeStartCount: Int,
        containerFrame: CGRect,
        canvasSize: CGSize,
        reduceMotion: Bool,
        onAttached: @escaping (Int) -> Void
    ) {
        let current = min(currentCount, TrashBinPhysicsSystem.maximumVisibleCount)
        guard current > previousVisualCount,
              current > composeStartCount,
              !contentStore.sample.isPlaying else { return }
        guard containerFrame.width > 1 else {
            trashPhysics.setCount(current, animated: true)
            onAttached(current)
            return
        }
        let opening = trashPhysics.globalOpeningCenter(containerFrame: containerFrame)
        let bounds = trashPhysics.globalOpeningBounds(containerFrame: containerFrame)
        let visualSide = containerFrame.width * TrashBinPhysicsSystem.visualSizeUnit
        let imageName = TrashBinPhysicsSystem.imageName(for: current - 1)
        contentStore.run(
            startPosition: CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.72),
            openingCenter: opening,
            openingBounds: bounds,
            token: RevealContentToken(
                type: .paperBall,
                imageName: imageName,
                seed: current - 1,
                visualSize: CGSize(width: visualSide, height: visualSide)
            ),
            preset: .trash,
            preparation: trashLid,
            restoration: trashLid,
            reduceMotion: reduceMotion,
            attachDynamic: { [weak self] in
                self?.trashPhysics.attachDynamic(imageName: imageName)
                onAttached(current)
            }
        )
    }

    func storeCapsuleIfNeeded(
        currentCount: Int,
        previousVisualCount: Int,
        composeStartCount: Int,
        containerFrame: CGRect,
        canvasSize: CGSize,
        reduceMotion: Bool,
        onAttached: @escaping (Int) -> Void
    ) {
        let current = min(currentCount, CapsuleJarMetrics.maximumVisibleCount)
        guard current > previousVisualCount,
              current > min(composeStartCount, CapsuleJarMetrics.maximumVisibleCount),
              !contentStore.sample.isPlaying else { return }
        guard containerFrame.width > 1 else { onAttached(current); return }
        let opening = ContainerRevealAnchors.point(CapsuleJarMetrics.mouth, in: containerFrame)
        let destination = ContainerRevealAnchors.point(CapsuleJarMetrics.slots[current - 1], in: containerFrame)
        contentStore.run(
            startPosition: CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.72),
            openingCenter: opening,
            openingBounds: CapsuleJarMetrics.openingBounds(in: containerFrame),
            token: RevealContentToken(type: .capsule, imageName: "Capsule_Closed", seed: current - 1,
                                      visualSize: CapsuleJarMetrics.tokenSize(in: containerFrame)),
            preset: .capsule,
            preparation: capsuleLid,
            restoration: capsuleLid,
            reduceMotion: reduceMotion,
            endPosition: destination,
            attachDynamic: { onAttached(current) }
        )
    }

    func dismissReveal(reduceMotion: Bool) {
        if starReveal.isPlaying {
            guard starReveal.sample.cardInteractive || reduceMotion else { return }
            starReveal.dismiss()
            return
        }
        guard reveal.sample.cardInteractive || reduceMotion else { return }
        reveal.dismiss()
    }

    func resetTransientPlayback() {
        contentStore.cancel()
        trashLid.finishRestoration()
        capsuleLid.finishRestoration()
        if reveal.isPlaying {
            reveal.reset()
        }
        starReveal.reset()
    }
}
