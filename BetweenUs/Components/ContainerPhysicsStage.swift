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
    var isPaused = false
    var onOpenItem: (SecretItem) -> Void
    var onEmptyTap: () -> Void

    @StateObject private var model: ContainerPhysicsModel

    init(
        kind: ContainerKind,
        items: [SecretItem],
        jolt: RoomJolt? = nil,
        isPaused: Bool = false,
        onOpenItem: @escaping (SecretItem) -> Void,
        onEmptyTap: @escaping () -> Void
    ) {
        self.kind = kind
        self.items = items
        self.jolt = jolt
        self.isPaused = isPaused
        self.onOpenItem = onOpenItem
        self.onEmptyTap = onEmptyTap
        _model = StateObject(wrappedValue: ContainerPhysicsModel(kind: kind))
    }

    var body: some View {
        PhysicsSceneView(scene: model.scene, isPaused: isPaused)
            .aspectRatio(model.recipe.container.mapping.sceneSize, contentMode: .fit)
            .onAppear { wire() }
            .onChange(of: items) { _, _ in wire() }
            .accessibilityElement()
            .accessibilityLabel(kind.title)
            .accessibilityHint(kind.openActionTitle)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onEmptyTap() }
    }

    private func wire() {
        model.scene.jolt = jolt
        model.sync(items)
        let snapshot = items
        model.scene.onTokenTapped = { id in
            guard let item = snapshot.first(where: { $0.id == id }) else { return }
            onOpenItem(item)
        }
        model.scene.onEmptyTapped = { onEmptyTap() }
    }
}
