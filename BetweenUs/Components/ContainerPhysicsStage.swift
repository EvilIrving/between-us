import SwiftUI

// 一个物件一份物理场景。页面只推送内容差异，不在界面重算时重建物理世界。
@MainActor
final class ContainerPhysicsModel: ObservableObject {
    let kind: ContainerKind
    let scene: VesselPhysicsScene
    private var presented: Set<UUID> = []

    init(kind: ContainerKind) {
        self.kind = kind
        scene = VesselPhysicsScene(recipe: ResourceCatalog.recipe(for: kind), initialCount: 0)
    }

    var recipe: VesselRecipe { scene.recipe }

    // 真实内容按标识进出：新增入队，已删除的退出物理世界；同一件内容不会重复入队。
    func sync(_ items: [SecretItem]) {
        let live = Set(items.map(\.id))
        for id in presented.subtracting(live) {
            _ = scene.detachForPresentation(id: id)
            presented.remove(id)
        }
        for item in items where !presented.contains(item.id) {
            let skin = ResourceCatalog.tokenSkinID(for: kind, id: item.id)
            if scene.queueToken(id: item.id, skinID: skin) {
                presented.insert(item.id)
            }
        }
    }
}

/// 首页与详情页共用的物件舞台：位图容器 + 真实内容的物理实体。
struct ContainerPhysicsStage: View {
    let kind: ContainerKind
    let items: [SecretItem]
    var jolt: RoomJolt?
    var motion: DeviceMotionSource?
    var motionSettings = DeviceMotionSettings()
    var isPaused = false
    var onTap: () -> Void

    @StateObject private var model: ContainerPhysicsModel

    init(
        kind: ContainerKind,
        items: [SecretItem],
        jolt: RoomJolt? = nil,
        motion: DeviceMotionSource? = nil,
        motionSettings: DeviceMotionSettings = DeviceMotionSettings(),
        isPaused: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.kind = kind
        self.items = items
        self.jolt = jolt
        self.motion = motion
        self.motionSettings = motionSettings
        self.isPaused = isPaused
        self.onTap = onTap
        _model = StateObject(wrappedValue: ContainerPhysicsModel(kind: kind))
    }

    var body: some View {
        PhysicsSceneView(scene: model.scene, isPaused: isPaused)
            .aspectRatio(model.recipe.container.mapping.sceneSize, contentMode: .fit)
            .onAppear { wire() }
            .onChange(of: items) { _, _ in wire() }
            .onChange(of: motionSettings) { _, _ in wire() }
            .accessibilityElement()
            .accessibilityLabel(kind.title)
            .accessibilityHint(T("点一下打开下一份"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
    }

    private func wire() {
        model.scene.jolt = jolt
        model.scene.motion = motion
        model.scene.motionSettings = motionSettings
        model.sync(items)
        // 点击打在整只物件上：点中里面积累的内容和点瓶身、篓身、盒身一样，都打开下一份。
        model.scene.onTokenTapped = { _ in onTap() }
        model.scene.onEmptyTapped = { onTap() }
    }
}
