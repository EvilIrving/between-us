// 当前两张素材的独立物理验证组件，不会修改原仓库
// 将本文件与附带图片资源加入应用目标，然后显示 JarPhysicsDemoView()
// 容器：724 × 724；星星：256 × 256；所有轮廓坐标均按原图左上角计量
// 更换构图或裁剪图片后必须重新标定，不能直接沿用这些轮廓
// 已做语法与离线几何检查，尚未在苹果设备上编译和验证物理手感

import SwiftUI
import Combine
import UIKit
@preconcurrency import SpriteKit

// MARK: - 固定设计坐标与素材轮廓

private enum JarGeometry {
    // 裁去左右空白的显示窗口；不裁剪原图，也不缩放单个物理节点
    static let sceneSize = CGSize(width: 500, height: 724)
    static let artworkSize = CGSize(width: 724, height: 724)
    static let artworkOrigin = CGPoint(x: -112, y: 0)
    static let charmSize = CGSize(width: 108, height: 108)

    // 左瓶口 -> 左内壁 -> 内底 -> 右内壁 -> 右瓶口
    // 这是内腔的设计近似，不是图片透明通道的外轮廓
    // 末尾不回连起点，瓶口必须保持开放
    static let wallPixels: [CGPoint] = [
        .init(x: 238, y: 155), .init(x: 237, y: 180),
        .init(x: 239, y: 211), .init(x: 232, y: 229),
        .init(x: 215, y: 249), .init(x: 201, y: 272),
        .init(x: 192, y: 303), .init(x: 189, y: 344),
        .init(x: 189, y: 566), .init(x: 192, y: 608),
        .init(x: 201, y: 637), .init(x: 219, y: 656),
        .init(x: 247, y: 670), .init(x: 283, y: 679),
        .init(x: 323, y: 683), .init(x: 366, y: 684),
        .init(x: 409, y: 683), .init(x: 451, y: 677),
        .init(x: 486, y: 667), .init(x: 513, y: 651),
        .init(x: 530, y: 630), .init(x: 538, y: 602),
        .init(x: 541, y: 563), .init(x: 541, y: 342),
        .init(x: 536, y: 302), .init(x: 525, y: 273),
        .init(x: 509, y: 249), .init(x: 493, y: 230),
        .init(x: 487, y: 213), .init(x: 491, y: 181),
        .init(x: 493, y: 155)
    ]

    // 中央五边形 + 五个凸形星角，共六块
    // 相邻块只共享边界，不留缝，也不互相重叠
    // 星角用短折线近似实际圆头，而不是延伸到想象中的锐利尖端
    // 避开透明留白、白色碎点和柔光，不把它们当作实体
    static let charmPiecesPixels: [[CGPoint]] = [
        [.init(x: 85, y: 90), .init(x: 168, y: 75),
         .init(x: 204, y: 137), .init(x: 146, y: 196), .init(x: 74, y: 169)],
        [.init(x: 85, y: 90), .init(x: 101, y: 44),
         .init(x: 114, y: 33), .init(x: 131, y: 36), .init(x: 168, y: 75)],
        [.init(x: 168, y: 75), .init(x: 218, y: 73),
         .init(x: 231, y: 79), .init(x: 233, y: 93), .init(x: 204, y: 137)],
        [.init(x: 204, y: 137), .init(x: 219, y: 187),
         .init(x: 218, y: 198), .init(x: 209, y: 205), .init(x: 146, y: 196)],
        [.init(x: 146, y: 196), .init(x: 105, y: 226),
         .init(x: 80, y: 226), .init(x: 76, y: 214), .init(x: 74, y: 169)],
        [.init(x: 74, y: 169), .init(x: 34, y: 143), .init(x: 26, y: 133),
         .init(x: 27, y: 122), .init(x: 33, y: 116), .init(x: 85, y: 90)]
    ]

    static func scenePoint(_ pixel: CGPoint) -> CGPoint {
        CGPoint(x: artworkOrigin.x + pixel.x, y: artworkSize.height - pixel.y)
    }

    static func charmPoint(_ pixel: CGPoint) -> CGPoint {
        // 纹理与物理体的共同原点是图片中心，不是非透明包围盒中心
        CGPoint(x: (pixel.x / 256 - 0.5) * charmSize.width,
                y: (0.5 - pixel.y / 256) * charmSize.height)
    }

    static func path(_ points: [CGPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }

    static func counterclockwise(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        var doubleArea: CGFloat = 0
        for i in points.indices {
            let next = points[(i + 1) % points.count]
            doubleArea += points[i].x * next.y - next.x * points[i].y
        }
        return doubleArea < 0 ? Array(points.reversed()) : points
    }

    static var charmPaths: [CGPath] {
        charmPiecesPixels.map {
            path(counterclockwise($0.map(charmPoint)), closed: true)
        }
    }

    // 前瓶沿的裁切轮廓；后瓶沿不能和前瓶沿一起盖在星星上方
    static var frontLipPath: CGPath {
        let p = CGMutablePath()
        p.move(to: scenePoint(.init(x: 224, y: 153)))
        p.addCurve(to: scenePoint(.init(x: 506, y: 153)),
                   control1: scenePoint(.init(x: 263, y: 184)),
                   control2: scenePoint(.init(x: 465, y: 184)))
        p.addLine(to: scenePoint(.init(x: 520, y: 185)))
        p.addQuadCurve(to: scenePoint(.init(x: 499, y: 217)),
                       control: scenePoint(.init(x: 530, y: 205)))
        p.addLine(to: scenePoint(.init(x: 493, y: 237)))
        p.addQuadCurve(to: scenePoint(.init(x: 239, y: 237)),
                       control: scenePoint(.init(x: 367, y: 252)))
        p.addLine(to: scenePoint(.init(x: 231, y: 216)))
        p.addQuadCurve(to: scenePoint(.init(x: 215, y: 183)),
                       control: scenePoint(.init(x: 204, y: 202)))
        p.closeSubpath()
        return p
    }
}

private enum JarCollision {
    static let wall: UInt32 = 1 << 0
    static let charm: UInt32 = 1 << 1
}

// MARK: - 一个场景持有全部物理对象

@MainActor
final class JarPhysicsScene: SKScene {
    // 业务层收到点击后再决定是否进入阅读，不在碰撞回调里删除记录
    var onCharmTapped: ((UUID) -> Void)?
    // 越出整个显示区域才触发恢复；这是异常提示，不是日常边界求解器
    var onRecovery: ((UUID) -> Void)?

    private let maximumCount = 10
    private var loaded = false
    private var texture: SKTexture?
    private var charms: [UUID: SKSpriteNode] = [:]
    private var waiting: [UUID] = []
    private var nextSpawnTime: TimeInterval = 0
    private var previousTime: TimeInterval = 0
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

    init(initialCount: Int = 8) {
        super.init(size: JarGeometry.sceneSize)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .white
        // 以下数值仅是这组尺寸的手感起点，不是引擎保证稳定的万能参数
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.4)
        for _ in 0..<min(max(initialCount, 0), maximumCount) {
            waiting.append(UUID())
        }
    }

    required init?(coder aDecoder: NSCoder) { return nil }

    override func didMove(to view: SKView) {
        view.allowsTransparency = false
        view.backgroundColor = .white
        view.isMultipleTouchEnabled = false
        previousTime = 0
        guard !loaded else { return }
        loaded = true
        guard let jarImage = Self.loadImage("StarJar_Body"),
              let charmImage = Self.loadImage("StarCharm_Gift_Love") else {
            let message = SKLabelNode(fontNamed: "PingFangSC-Regular")
            message.text = "缺少瓶子或星星图片资源"
            message.fontColor = .black
            message.fontSize = 24
            message.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(message)
            return
        }
        texture = SKTexture(image: charmImage)
        buildJar(texture: SKTexture(image: jarImage))
    }

    private static func loadImage(_ name: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return nil
    }

    override func willMove(from view: SKView) {
        cancelDrag()
        previousTime = 0
    }

    private func buildJar(texture: SKTexture) {
        func artwork(z: CGFloat, alpha: CGFloat = 1) -> SKSpriteNode {
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = JarGeometry.artworkSize
            node.position = JarGeometry.artworkOrigin
            node.zPosition = z
            node.alpha = alpha
            return node
        }

        // 瓶身中心接近不透明，原图作为后景，不能整张覆盖在星星前面
        addChild(artwork(z: 0))

        // 验证阶段用同一纹理的低透明度副本近似玻璃着色
        // 正式视觉最好导出专门的透明反光前景，替换此层，不改变物理轮廓
        addChild(artwork(z: 20, alpha: 0.10))

        let front = SKCropNode()
        front.zPosition = 30
        let mask = SKShapeNode(path: JarGeometry.frontLipPath)
        mask.fillColor = .white
        mask.strokeColor = .clear
        front.maskNode = mask
        front.addChild(artwork(z: 0))
        addChild(front)

        let wall = SKNode()
        wall.name = "jar.innerWall"
        let wallPath = JarGeometry.path(JarGeometry.wallPixels.map(JarGeometry.scenePoint),
                                        closed: false)
        let body = SKPhysicsBody(edgeChainFrom: wallPath)
        body.isDynamic = false
        body.categoryBitMask = JarCollision.wall
        body.collisionBitMask = JarCollision.charm
        body.contactTestBitMask = 0
        body.friction = 0.5
        body.restitution = 0.08
        wall.physicsBody = body
        addChild(wall)
    }

    private func makeCharmBody() -> SKPhysicsBody {
        let pieces = JarGeometry.charmPaths.map { SKPhysicsBody(polygonFrom: $0) }
        // 六个凸体合成一个刚体，不是六个通过关节连接的独立物体
        let body = SKPhysicsBody(bodies: pieces)
        body.isDynamic = true
        body.affectedByGravity = true
        body.allowsRotation = true
        body.mass = 0.03
        body.friction = 0.55
        body.restitution = 0.12
        body.linearDamping = 0.22
        body.angularDamping = 0.35
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = JarCollision.charm
        body.collisionBitMask = JarCollision.wall | JarCollision.charm
        body.contactTestBitMask = 0
        return body
    }

    // 接业务时传真实内容标识，不要只按数量重建所有节点
    @discardableResult
    func queueCharm(id: UUID = UUID()) -> Bool {
        guard charms[id] == nil, !waiting.contains(id),
              charms.count + waiting.count < maximumCount else { return false }
        waiting.append(id)
        return true
    }

    func resetDemo() {
        cancelDrag()
        for node in charms.values { node.removeFromParent() }
        charms.removeAll()
        waiting.removeAll()
        nextSpawnTime = 0
        previousTime = 0
        for _ in 0..<8 { _ = queueCharm() }
    }

    // 阅读动画的明确交接点：先退出物理，再由另一个控制器接管
    // 调用方负责保存业务内容、执行取出动画以及随后归还或删除的语义
    // 从堆中取出应规划经过瓶口的路径，不直接沿直线穿过瓶壁
    func detachForPresentation(id: UUID) -> SKSpriteNode? {
        if drag?.id == id { cancelDrag() }
        waiting.removeAll { $0 == id }
        guard let node = charms.removeValue(forKey: id) else { return nil }
        node.physicsBody = nil
        node.removeFromParent()
        // 返回时位置仍是本场景坐标，接入其他坐标系须显式转换
        return node
    }

    private func spawnIfClear(at currentTime: TimeInterval) {
        guard texture != nil, !waiting.isEmpty, currentTime >= nextSpawnTime else { return }
        let position = CGPoint(x: 250 + CGFloat.random(in: -45...45), y: 662)
        // 使用保守包围范围，避免一开始就把新刚体放进已有刚体里
        let freeZone = CGRect(x: position.x - 82, y: position.y - 82,
                              width: 164, height: 164)
        guard charms.values.allSatisfy({ !$0.calculateAccumulatedFrame().intersects(freeZone) })
        else { return }
        let id = waiting.removeFirst()
        let node = SKSpriteNode(texture: texture)
        node.name = id.uuidString
        node.size = JarGeometry.charmSize
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = position
        node.zPosition = 10
        node.zRotation = CGFloat.random(in: -0.4...0.4)
        node.physicsBody = makeCharmBody()
        // 初始微小横向扰动；后续转动由碰撞产生，没有循环旋转动画
        node.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -12...12), dy: 0)
        addChild(node)
        charms[id] = node
        nextSpawnTime = currentTime + 0.65
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = previousTime == 0 ? 1.0 / 60.0 : min(max(currentTime - previousTime, 0), 1.0 / 30.0)
        previousTime = currentTime
        spawnIfClear(at: currentTime)
        if let drag, let node = charms[drag.id] {
            // 只移动无碰撞的拖拽锚点，不逐帧写星星的 position
            // 相对真正的抓取点限制拉伸，不能用图片中心代替抓取点
            let grabPoint = node.convert(drag.localAnchor, to: self)
            let pull = CGVector(dx: drag.target.x - grabPoint.x,
                                dy: drag.target.y - grabPoint.y)
            let pullLength = hypot(pull.dx, pull.dy)
            let factor: CGFloat = pullLength > 36 ? 36 / pullLength : 1
            let safeTarget = CGPoint(x: grabPoint.x + pull.dx * factor,
                                     y: grabPoint.y + pull.dy * factor)
            let delta = CGVector(dx: safeTarget.x - drag.handle.position.x,
                                 dy: safeTarget.y - drag.handle.position.y)
            let distance = hypot(delta.dx, delta.dy)
            let step = min(distance, 480 * CGFloat(dt))
            if distance > 0.001 {
                drag.handle.position.x += delta.dx / distance * step
                drag.handle.position.y += delta.dy / distance * step
            }
        }
        for node in charms.values {
            guard let body = node.physicsBody, !body.isResting else { continue }
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            if speed > 550 {
                body.velocity = CGVector(dx: body.velocity.dx * 550 / speed,
                                         dy: body.velocity.dy * 550 / speed)
            }
            // 只限制极端转速，不清零正常角速度
            if abs(body.angularVelocity) > 7 {
                body.angularVelocity = min(max(body.angularVelocity, -7), 7)
            }
        }
        // 位置积分、碰撞求解与正常休眠全部由 SpriteKit 处理
    }

    override func didSimulatePhysics() {
        // 开口允许物体被拖出；只有离开整个场景后才归还队列
        // 此恢复策略不会删除内容，正式接入时应记录异常并区分主动取出
        let validArea = frame.insetBy(dx: -160, dy: -160)
        let lost: [UUID] = charms.compactMap { id, node in
            validArea.contains(node.position) ? nil : id
        }
        for id in lost {
            if drag?.id == id { cancelDrag() }
            charms.removeValue(forKey: id)?.removeFromParent()
            waiting.append(id)
            onRecovery?(id)
        }
    }

    // MARK: - 拖拽仍在物理世界内，避免“手指移动”和“碰撞求解”争夺坐标

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drag == nil, let touch = touches.first else { return }
        let point = touch.location(in: self)
        // 命中复合体轮廓，而不是图片透明包围矩形
        guard let (id, node) = charms.first(where: { _, node in
            let local = node.convert(point, from: self)
            return JarGeometry.charmPaths.contains { $0.contains(local) }
        }), let body = node.physicsBody else { return }
        body.isResting = false
        let handle = SKNode()
        handle.position = point
        let handleBody = SKPhysicsBody(circleOfRadius: 1)
        handleBody.isDynamic = false
        handleBody.categoryBitMask = 0
        handleBody.collisionBitMask = 0
        handleBody.contactTestBitMask = 0
        handle.physicsBody = handleBody
        addChild(handle)
        let joint = SKPhysicsJointSpring.joint(withBodyA: body, bodyB: handleBody,
                                               anchorA: point, anchorB: point)
        joint.frequency = 5
        joint.damping = 0.85
        physicsWorld.add(joint)
        drag = Drag(touch: touch, id: id, handle: handle, joint: joint,
                    startPoint: point, localAnchor: node.convert(point, from: self),
                    startTime: touch.timestamp,
                    target: point, maximumTravel: 0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var current = drag,
              let touch = touches.first(where: { $0 === current.touch }) else { return }
        let point = touch.location(in: self)
        // 保存手指真实目标；限制拉伸与限速放在每帧更新里
        // 这样手指暂停后，物体仍能继续跟上，而不是停在旧的截断目标
        current.target = point
        current.maximumTravel = max(current.maximumTravel,
                                    hypot(point.x - current.startPoint.x, point.y - current.startPoint.y))
        drag = current
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let current = drag,
              let touch = touches.first(where: { $0 === current.touch }) else { return }
        let isTap = current.maximumTravel < 8 && touch.timestamp - current.startTime < 0.3
        cancelDrag()
        // 松手不重新设定位置或强制旋转，保留物理引擎计算出的释放速度
        if isTap { onCharmTapped?(current.id) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let current = drag, touches.contains(where: { $0 === current.touch }) else { return }
        cancelDrag()
    }

    func cancelDrag() {
        guard let current = drag else { return }
        physicsWorld.remove(current.joint)
        current.handle.removeFromParent()
        drag = nil
    }
}

// MARK: - 稳定持有场景，避免界面状态改变时重建整个物理世界

@MainActor
private final class JarDemoModel: ObservableObject {
    let scene = JarPhysicsScene()
}

@MainActor
struct JarPhysicsDemoView: View {
    @StateObject private var model = JarDemoModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var debug = true

    var body: some View {
        VStack(spacing: 12) {
            JarSKView(scene: model.scene,
                      isPaused: scenePhase != .active,
                      debug: debug)
                .aspectRatio(JarGeometry.sceneSize.width / JarGeometry.sceneSize.height,
                             contentMode: .fit)
            HStack {
                Button("放入一颗") { _ = model.scene.queueCharm() }
                Button("重新试验") { model.scene.resetDemo() }
                Toggle("显示碰撞轮廓", isOn: $debug)
            }
            .font(.footnote)
        }
        .padding()
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.scene.cancelDrag() }
        }
        .onDisappear { model.scene.cancelDrag() }
    }
}

private struct JarSKView: UIViewRepresentable {
    let scene: JarPhysicsScene
    var isPaused: Bool
    var debug: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .white
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        apply(view)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        apply(view)
        if view.scene !== scene {
            view.presentScene(scene)
        }
    }

    private func apply(_ view: SKView) {
        view.isPaused = isPaused
        view.showsFPS = debug
        view.showsPhysics = debug
        view.showsNodeCount = debug
    }
}
