import Foundation

struct TokenRequest: Codable, Equatable, Identifiable {
    var id: UUID
    var skinID: String
}

// 只负责身份、去重和容量；不持有贴图、轮廓、显示状态或物理引擎。
struct TokenQueue {
    let capacity: Int
    private(set) var waiting: [TokenRequest] = []
    private(set) var active: [UUID: TokenRequest] = [:]
    var totalCount: Int { waiting.count + active.count }

    @discardableResult mutating func enqueue(_ request: TokenRequest) -> Bool {
        guard totalCount < capacity, active[request.id] == nil,
              !waiting.contains(where: { $0.id == request.id }) else { return false }
        waiting.append(request)
        return true
    }
    mutating func activateNext() -> TokenRequest? {
        guard !waiting.isEmpty else { return nil }
        let request = waiting.removeFirst()
        active[request.id] = request
        return request
    }
    @discardableResult mutating func recover(_ id: UUID) -> Bool {
        guard let request = active.removeValue(forKey: id) else { return false }
        waiting.append(request)
        return true
    }
    mutating func remove(_ id: UUID) -> TokenRequest? {
        if let request = active.removeValue(forKey: id) { return request }
        if let index = waiting.firstIndex(where: { $0.id == id }) { return waiting.remove(at: index) }
        return nil
    }
    mutating func clear() { active.removeAll(); waiting.removeAll() }
}

struct TokenPlacement: Codable, Equatable {
    var request: TokenRequest
    var position: CGPoint
    var rotation: CGFloat
    var velocity: CGPoint
    var angularVelocity: CGFloat
    var isResting: Bool
}

struct VesselSnapshot: Codable, Equatable {
    var formatVersion: Int = 1
    var recipeID: String
    var geometryVersion: Int
    var active: [TokenPlacement]
    var waiting: [TokenRequest]

    func validationErrors(for recipe: VesselRecipe) -> [String] {
        var errors: [String] = []
        if formatVersion != 1 || recipeID != recipe.id || geometryVersion != recipe.geometryVersion {
            errors.append("快照与当前容器或几何版本不匹配")
        }
        let requests = active.map(\.request) + waiting
        if requests.count > recipe.policy.capacity { errors.append("快照超过容量") }
        if Set(requests.map(\.id)).count != requests.count { errors.append("快照含重复内容标识") }
        if requests.contains(where: { recipe.skin(id: $0.skinID) == nil }) { errors.append("快照含未注册皮肤") }
        let area = CGRect(origin: .zero, size: recipe.container.mapping.sceneSize)
            .insetBy(dx: -recipe.policy.recoveryMargin, dy: -recipe.policy.recoveryMargin)
        if active.contains(where: {
            !GeometryMath.isFinite($0.position) || !GeometryMath.isFinite($0.velocity) ||
            !$0.rotation.isFinite || !$0.angularVelocity.isFinite || !area.contains($0.position)
        }) { errors.append("快照含无效位置、速度或角度") }
        return errors
    }
}
