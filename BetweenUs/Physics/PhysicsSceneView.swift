import SwiftUI
@preconcurrency import SpriteKit

// 调用方持有场景，不在 SwiftUI 的 body 中创建新场景。
@MainActor
struct PhysicsSceneView: UIViewRepresentable {
    let scene: VesselPhysicsScene
    var isPaused = false
    var showGeometry = false
    var xRay = false

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        // 透出宿主房间背景，容器只画自己的位图和实体。
        view.backgroundColor = .clear
        view.allowsTransparency = true
        // 不把场景钉在 60 帧：同屏的滚动和导航在 ProMotion 上都是 120Hz，
        // 钉死 60 会让容器里的物件显出手感割裂；没有高刷的设备会自动停在 60。
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = false
        view.presentScene(scene)
        apply(view)
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            (view.scene as? VesselPhysicsScene)?.prepareForSuspension()
            view.presentScene(scene)
        }
        apply(view)
    }
    private func apply(_ view: SKView) {
        if view.isPaused != isPaused {
            scene.prepareForSuspension()
            view.isPaused = isPaused
        }
        scene.setInspection(showGeometry:showGeometry,xRay:xRay)
        view.showsFPS = showGeometry
        // 使用场景的独立调试层，确保不透明前壁后面的全部刚体轮廓也能看见。
        view.showsPhysics = false
        view.showsNodeCount = false
    }
    static func dismantleUIView(_ view: SKView, coordinator: ()) {
        (view.scene as? VesselPhysicsScene)?.prepareForSuspension()
        view.presentScene(nil)
    }
}
