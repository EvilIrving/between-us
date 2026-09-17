import UIKit
@preconcurrency import SpriteKit

struct VesselStatus: Equatable {
    var active = 0
    var resting = 0
    var waiting = 0
    var recoveries = 0
    var spawnBlocked = false
    var error: String? = nil
}

// 唯一场景执行器：不出现产品类型判断，不把「看不见」当成移除、冻结或压平的理由。
@MainActor
final class VesselPhysicsScene: SKScene {
    let recipe: VesselRecipe
    var onTokenTapped: ((UUID) -> Void)?
    var onEmptyTapped: (() -> Void)?
    var onRecovery: ((UUID) -> Void)?
    var onStatusChanged: ((VesselStatus) -> Void)?

    private let assets = VesselAssets()
    private let renderer: VesselRenderer
    private var queue: TokenQueue
    private var nodesByID: [UUID: SKSpriteNode] = [:]
    private var insertionOrder: [UUID] = []
    private var textures: [String: SKTexture] = [:]
    private var hitPaths: [CGPath] = []
    private var ready = false
    private var loadAttempted = false
    private var simulationTime: TimeInterval = 0
    private var previousTime: TimeInterval = 0
    private var nextSpawnTime: TimeInterval = 0
    private var blockedSince: TimeInterval?
    private var recoveryCount = 0
    private var lastReported = VesselStatus()
    private var errorMessage: String?
    private var reportNextTime: TimeInterval = 0
    private var debugRoot = SKNode()
    private var debugTokens: [UUID: SKNode] = [:]
    private var debugBuilt = false
    private var showGeometry = false
    private var tapFallback = false
    private var drag: Drag?

    private struct Drag {
        let touch: UITouch
        let id: UUID
        let handle: SKNode
        let joint: SKPhysicsJointSpring
        let startPoint: CGPoint
        let localAnchor: CGPoint
        let startTime: TimeInterval
        var target: CGPoint
        var maximumTravel: CGFloat
    }

    init(recipe: VesselRecipe = ResourceCatalog.starJar, initialCount: Int? = nil) {
        self.recipe = recipe
        renderer = VesselRenderer(container:recipe.container)
        queue = TokenQueue(capacity:recipe.policy.capacity)
        super.init(size:recipe.container.mapping.sceneSize)
        scaleMode = .aspectFit
        anchorPoint = .zero
        // 容器贴在应用自身的房间里，场景底色必须透出宿主背景。
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx:recipe.policy.gravity.x,dy:recipe.policy.gravity.y)
        let n = min(max(initialCount ?? recipe.policy.initialCount,0),recipe.policy.capacity)
        if let skin = recipe.skins.first {
            for _ in 0..<n { _ = queue.enqueue(TokenRequest(id:UUID(),skinID:skin.id)) }
        }
    }
    required init?(coder aDecoder: NSCoder) { return nil }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        previousTime = 0
        guard !loadAttempted else { reportStatus(force:true); return }
        loadAttempted = true
        do {
            let errors = GeometryMath.validate(recipe)
            guard errors.isEmpty else { throw VesselError.invalidConfiguration(errors) }
            for skin in recipe.skins { textures[skin.id] = try assets.texture(for:skin) }
            try renderer.install(in:self,assets:assets)
            addChild(PhysicsFactory.wall(for:recipe.container))
            hitPaths = PhysicsFactory.localPaths(recipe.entity.geometry)
            debugRoot.zPosition = 1_000
            addChild(debugRoot)
            ready = true
            buildDebugGeometry()
        } catch {
            errorMessage = error.localizedDescription
            let message = SKLabelNode(fontNamed:"PingFangSC-Regular")
            message.text = "资源或配置错误，请查看下方提示"
            message.fontColor = .black; message.fontSize = 20
            message.position = CGPoint(x:size.width/2,y:size.height/2)
            message.zPosition = 2_000
            addChild(message)
        }
        reportStatus(force:true)
    }

    override func willMove(from view: SKView) { prepareForSuspension() }
    func prepareForSuspension() { cancelDrag(); previousTime = 0 }

    // 只改变渲染；墙、实体、位置、速度、质量、队列和休眠状态均不修改。
    func setInspection(showGeometry: Bool, xRay: Bool) {
        self.showGeometry = showGeometry
        renderer.setXRay(xRay)
        debugRoot.isHidden = !showGeometry
        if showGeometry {
            for (id,shape) in debugTokens {
                guard let node = nodesByID[id] else { continue }
                shape.position = node.position; shape.zRotation = node.zRotation
            }
        }
    }

    @discardableResult
    func queueToken(id: UUID = UUID(), skinID: String? = nil) -> Bool {
        guard let skin = skinID.flatMap({ recipe.skin(id:$0) }) ?? (skinID == nil ? recipe.skins.first : nil)
        else { return false }
        return queue.enqueue(TokenRequest(id:id,skinID:skin.id))
    }

    func fillToCapacity() {
        while queue.totalCount < recipe.policy.capacity {
            guard queueToken() else { break }
        }
    }

    func resetDemo() {
        clearWorld()
        recoveryCount = 0
        for _ in 0..<recipe.policy.initialCount { _ = queueToken() }
        reportStatus(force:true)
    }

    private func clearWorld() {
        cancelDrag()
        for node in nodesByID.values { node.removeFromParent() }
        nodesByID.removeAll(); insertionOrder.removeAll(); queue.clear()
        for node in debugTokens.values { node.removeFromParent() }
        debugTokens.removeAll()
        nextSpawnTime = 0; previousTime = 0; simulationTime = 0
        blockedSince = nil; reportNextTime = 0
    }

    func request(for id: UUID) -> TokenRequest? { queue.active[id] }

    func contains(id: UUID) -> Bool {
        queue.active[id] != nil || queue.waiting.contains { $0.id == id }
    }

    // 业务仪式的交接点，不会删除业务记录；节点离开物理后才交给取出/阅读动画。
    // 返回位置属于本场景；调用方转换坐标，并规划经过开口的动画路径。
    func detachForPresentation(id: UUID) -> SKSpriteNode? {
        if drag?.id == id { cancelDrag() }
        _ = queue.remove(id)
        insertionOrder.removeAll { $0 == id }
        debugTokens.removeValue(forKey:id)?.removeFromParent()
        guard let node = nodesByID.removeValue(forKey:id) else { return nil }
        node.physicsBody = nil
        node.removeFromParent()
        return node
    }

    func makeSnapshot() -> VesselSnapshot {
        let active = insertionOrder.compactMap { id -> TokenPlacement? in
            guard let node = nodesByID[id], let body = node.physicsBody,
                  let request = queue.active[id] else { return nil }
            return TokenPlacement(request:request,position:node.position,rotation:node.zRotation,
                                  velocity:CGPoint(x:body.velocity.dx,y:body.velocity.dy),
                                  angularVelocity:body.angularVelocity,isResting:body.isResting)
        }
        return VesselSnapshot(recipeID:recipe.id,geometryVersion:recipe.geometryVersion,
                              active:active,waiting:queue.waiting)
    }

    // 快照只保存应用需要的位姿，不声称保存了引擎的接触缓存或逐位可重复的物理世界。
    // 验证全部成功才替换旧世界，不能把另一种容器的快照直接灌进来。
    func restore(_ snapshot: VesselSnapshot) throws {
        guard ready else { throw VesselError.notReady }
        let errors = snapshot.validationErrors(for:recipe)
        guard errors.isEmpty else { throw VesselError.invalidConfiguration(errors) }
        let prepared = try snapshot.active.map { placement -> (TokenPlacement,SKSpriteNode) in
            let node = try makeNode(placement.request)
            node.position = placement.position; node.zRotation = placement.rotation
            node.physicsBody?.velocity = CGVector(dx:placement.velocity.x,dy:placement.velocity.y)
            node.physicsBody?.angularVelocity = placement.angularVelocity
            return (placement,node)
        }
        clearWorld()
        for (placement,node) in prepared {
            _ = queue.enqueue(placement.request); _ = queue.activateNext()
            addChild(node); nodesByID[placement.request.id] = node
            insertionOrder.append(placement.request.id)
            node.physicsBody?.isResting = placement.isResting
            addDebugToken(id:placement.request.id,node:node)
        }
        for request in snapshot.waiting { _ = queue.enqueue(request) }
        reportStatus(force:true)
    }

    private func makeNode(_ request: TokenRequest) throws -> SKSpriteNode {
        guard let texture = textures[request.skinID] else { throw VesselError.missingImage(request.skinID) }
        let node = SKSpriteNode(texture:texture)
        node.name = request.id.uuidString
        node.size = recipe.entity.geometry.displaySize
        node.anchorPoint = CGPoint(x:0.5,y:0.5)
        node.zPosition = recipe.container.entityDepth
        node.physicsBody = PhysicsFactory.body(for:recipe.entity)
        return node
    }

    private func spawnIfClear() {
        guard ready, !queue.waiting.isEmpty, simulationTime >= nextSpawnTime else {
            if queue.waiting.isEmpty { blockedSince = nil }
            return
        }
        let p = recipe.policy.spawn
        let position = CGPoint(x:p.center.x+CGFloat.random(in:-p.jitterX...p.jitterX),y:p.center.y)
        let zone = CGRect(x:position.x-p.clearanceHalfSize.width,y:position.y-p.clearanceHalfSize.height,
                          width:2*p.clearanceHalfSize.width,height:2*p.clearanceHalfSize.height)
        guard nodesByID.values.allSatisfy({ !$0.calculateAccumulatedFrame().intersects(zone) }) else {
            if blockedSince == nil { blockedSince = simulationTime }
            return // 堵口就等，不穿透已有物体，不强行塞进容器。
        }
        guard let request = queue.waiting.first else { return }
        do {
            let node = try makeNode(request)
            _ = queue.activateNext()
            node.position = position
            node.zRotation = CGFloat.random(in:p.initialRotation)
            node.physicsBody?.velocity = CGVector(dx:CGFloat.random(in:p.initialVelocityX),dy:CGFloat.random(in:p.initialVelocityY))
            addChild(node); nodesByID[request.id] = node; insertionOrder.append(request.id)
            addDebugToken(id:request.id,node:node)
            nextSpawnTime = simulationTime+p.interval
            blockedSince = nil
        } catch { errorMessage = error.localizedDescription }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = previousTime == 0 ? 1.0/60.0 : min(max(currentTime-previousTime,0),1.0/30.0)
        previousTime = currentTime
        guard ready else { return }
        simulationTime += dt
        spawnIfClear()
        updateDrag(dt:dt)
        for node in nodesByID.values {
            guard let body = node.physicsBody, !body.isResting else { continue }
            let speed = hypot(body.velocity.dx,body.velocity.dy)
            let limit = recipe.policy.maximumLinearSpeed
            if speed > limit {
                body.velocity = CGVector(dx:body.velocity.dx*limit/speed,dy:body.velocity.dy*limit/speed)
            }
            let angularLimit = recipe.policy.maximumAngularSpeed
            if abs(body.angularVelocity) > angularLimit {
                body.angularVelocity = min(max(body.angularVelocity,-angularLimit),angularLimit)
            }
        }
        // 不写实体的正常运动坐标；位置积分、碰撞、转动和休眠仍完全由引擎执行。
    }

    override func didSimulatePhysics() {
        guard ready else { return }
        let margin = recipe.policy.recoveryMargin
        let validArea = CGRect(origin:.zero,size:size).insetBy(dx:-margin,dy:-margin)
        let lost = nodesByID.compactMap { id,node in
            GeometryMath.isFinite(node.position) && validArea.contains(node.position) ? nil : id
        }
        for id in lost {
            if drag?.id == id { cancelDrag() }
            nodesByID.removeValue(forKey:id)?.removeFromParent()
            insertionOrder.removeAll { $0 == id }
            debugTokens.removeValue(forKey:id)?.removeFromParent()
            _ = queue.recover(id)
            recoveryCount += 1
            onRecovery?(id)
        }
        if showGeometry {
            for (id,shape) in debugTokens {
                guard let node = nodesByID[id] else { continue }
                shape.position = node.position; shape.zRotation = node.zRotation
            }
        }
        reportStatus()
    }

    private func reportStatus(force: Bool = false) {
        guard force || simulationTime >= reportNextTime else { return }
        reportNextTime = simulationTime+0.15
        let status = VesselStatus(active:nodesByID.count,
            resting:nodesByID.values.filter { $0.physicsBody?.isResting == true }.count,
            waiting:queue.waiting.count,recoveries:recoveryCount,
            spawnBlocked:blockedSince.map { simulationTime-$0 >= recipe.policy.spawn.blockedNoticeDelay } ?? false,
            error:errorMessage)
        guard force || status != lastReported else { return }
        lastReported = status
        onStatusChanged?(status)
    }

    private func updateDrag(dt: TimeInterval) {
        guard let drag, let node = nodesByID[drag.id] else { return }
        let p = recipe.policy.drag
        let grabPoint = node.convert(drag.localAnchor,to:self)
        let pull = CGVector(dx:drag.target.x-grabPoint.x,dy:drag.target.y-grabPoint.y)
        let distance = hypot(pull.dx,pull.dy)
        let factor: CGFloat = distance > p.maximumStretch ? p.maximumStretch/distance : 1
        let target = CGPoint(x:grabPoint.x+pull.dx*factor,y:grabPoint.y+pull.dy*factor)
        let dx = target.x-drag.handle.position.x, dy = target.y-drag.handle.position.y
        let length = hypot(dx,dy)
        if length > 0.001 {
            let step = min(length,p.maximumHandleSpeed*CGFloat(dt))
            drag.handle.position.x += dx/length*step
            drag.handle.position.y += dy/length*step
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drag == nil, ready, let touch = touches.first else { return }
        let point = touch.location(in:self)
        guard !renderer.blocksHit(at:point) else {
            // 不透明前壁也算物件本身，按空白处理。
            tapFallback = true
            return
        }
        // 顶层优先；隐藏实体不会被隔着桶壁点中，透视检查时可以主动测试内部拖拽。
        guard let id = insertionOrder.reversed().first(where:{ id in
            guard let node = nodesByID[id] else { return false }
            return hitPaths.contains { $0.contains(node.convert(point,from:self)) }
        }), let node = nodesByID[id], let body = node.physicsBody else {
            // 空白处松手由宿主决定，例如继续按顺序打开下一件内容。
            drag = nil
            tapFallback = true
            return
        }
        tapFallback = false
        body.isResting = false
        let handle = SKNode(); handle.position = point
        let handleBody = SKPhysicsBody(circleOfRadius:1)
        handleBody.isDynamic = false
        handleBody.categoryBitMask = 0; handleBody.collisionBitMask = 0; handleBody.contactTestBitMask = 0
        handle.physicsBody = handleBody
        addChild(handle)
        let joint = SKPhysicsJointSpring.joint(withBodyA:body,bodyB:handleBody,anchorA:point,anchorB:point)
        joint.frequency = recipe.policy.drag.springFrequency
        joint.damping = recipe.policy.drag.springDamping
        physicsWorld.add(joint)
        drag = Drag(touch:touch,id:id,handle:handle,joint:joint,startPoint:point,
                    localAnchor:node.convert(point,from:self),startTime:touch.timestamp,target:point,maximumTravel:0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var state = drag, let touch = touches.first(where:{ $0 === state.touch }) else { return }
        let point = touch.location(in:self)
        state.target = point
        state.maximumTravel = max(state.maximumTravel,hypot(point.x-state.startPoint.x,point.y-state.startPoint.y))
        drag = state
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = drag, let touch = touches.first(where:{ $0 === state.touch }) else {
            if tapFallback { tapFallback = false; onEmptyTapped?() }
            return
        }
        let end = touch.location(in:self)
        let travel = max(state.maximumTravel,hypot(end.x-state.startPoint.x,end.y-state.startPoint.y))
        let tap = travel < recipe.policy.drag.tapDistance && touch.timestamp-state.startTime < recipe.policy.drag.tapDuration
        cancelDrag() // 不补速度、不重置位置和角度，保留实际释放运动。
        if tap { onTokenTapped?(state.id) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tapFallback = false
        if let state = drag, touches.contains(where:{ $0 === state.touch }) { cancelDrag() }
    }
    func cancelDrag() {
        tapFallback = false
        guard let state = drag else { return }
        physicsWorld.remove(state.joint); state.handle.removeFromParent(); drag = nil
    }

    private func buildDebugGeometry() {
        guard !debugBuilt else { return }
        debugBuilt = true
        let wall = SKShapeNode(path:PhysicsFactory.path(recipe.container.innerWall.map(recipe.container.mapping.scenePoint),closed:false))
        wall.strokeColor = .systemPink; wall.lineWidth = 2.5
        debugRoot.addChild(wall)
        let mouth = SKShapeNode(path:PhysicsFactory.path(recipe.container.mouth.map(recipe.container.mapping.scenePoint),closed:false))
        mouth.strokeColor = .systemTeal; mouth.lineWidth = 1.5
        debugRoot.addChild(mouth)
        let p = recipe.policy.spawn
        let marker = SKShapeNode(circleOfRadius:5)
        marker.position = p.center; marker.fillColor = .systemOrange; marker.strokeColor = .clear
        debugRoot.addChild(marker)
        debugRoot.isHidden = !showGeometry
    }
    private func addDebugToken(id: UUID, node: SKSpriteNode) {
        let group = SKNode()
        for path in hitPaths {
            let shape = SKShapeNode(path:path)
            shape.strokeColor = .systemGreen; shape.lineWidth = 1.2; shape.fillColor = .clear
            group.addChild(shape)
        }
        group.position = node.position; group.zRotation = node.zRotation
        debugRoot.addChild(group); debugTokens[id] = group
    }
}
