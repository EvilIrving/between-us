import SpriteKit
import SwiftUI

struct TrashLidTransform: Equatable {
    var offset: CGSize
    var rotationZ: Double

    static let closed = TrashLidTransform(offset: .zero, rotationZ: 0)
}

enum TrashLidPhase: Equatable {
    case closed
    case lift
    case moveAside
    case holdOpen
    case returning
    case closing
}

@MainActor
final class TrashLidController: ObservableObject, ContainerPreparationPlugin, ContainerRestorationPlugin {
    @Published private(set) var phase: TrashLidPhase = .closed
    @Published private(set) var transform = TrashLidTransform.closed

    let preparationDuration: TimeInterval = 1.15
    let restorationDuration: TimeInterval = 0.85

    private let animationDriver: AnimationDriver
    private var restorationAnimations: [UUID] = []

    init(animationDriver: AnimationDriver) {
        self.animationDriver = animationDriver
    }

    func prepare(reduceMotion: Bool) {
        cancelRestoration()
        if reduceMotion {
            phase = .holdOpen
            transform = TrashLidTransform(offset: CGSize(width: 28, height: -34), rotationZ: -4)
        } else {
            phase = .lift
            transform = .closed
        }
    }

    func updatePreparation(progress: CGFloat) {
        let p = RevealEasing.clamp(progress)
        let liftEnd: CGFloat = 0.565
        if p < liftEnd {
            phase = .lift
            let local = RevealEasing.easeInOutCubic(p / liftEnd)
            transform = TrashLidTransform(
                offset: CGSize(
                    width: 0,
                    height: RevealEasing.lerp(CGFloat(0), CGFloat(-34), local)
                ),
                rotationZ: RevealEasing.lerp(0, -8, local)
            )
        } else {
            phase = .moveAside
            let local = RevealEasing.easeInOutCubic((p - liftEnd) / (1 - liftEnd))
            transform = TrashLidTransform(
                offset: CGSize(
                    width: RevealEasing.lerp(CGFloat(0), CGFloat(48), local),
                    height: RevealEasing.lerp(CGFloat(-34), CGFloat(-60), local)
                ),
                rotationZ: RevealEasing.lerp(-8, -7, local)
            )
        }
    }

    func holdOpen() {
        phase = .holdOpen
        transform = TrashLidTransform(offset: CGSize(width: 48, height: -60), rotationZ: -7)
    }

    func restore(reduceMotion: Bool) {
        cancelRestoration()
        if reduceMotion {
            finishRestoration()
            return
        }

        phase = .returning
        let start = transform
        restorationAnimations = [
            animationDriver.spring(
                from: start.offset.width,
                to: 0,
                configuration: .heavyMetal,
                update: { [weak self] value in self?.transform.offset.width = value },
                completion: { [weak self] in self?.phase = .closing }
            ),
            animationDriver.spring(
                from: start.offset.height,
                to: 0,
                configuration: .heavyMetal,
                update: { [weak self] value in self?.transform.offset.height = value },
                completion: {}
            ),
            animationDriver.spring(
                from: CGFloat(start.rotationZ),
                to: 0,
                configuration: .heavyMetal,
                update: { [weak self] value in self?.transform.rotationZ = Double(value) },
                completion: { [weak self] in self?.finishRestoration() }
            )
        ]
    }

    func updateRestoration(progress: CGFloat) {
        // Wave owns the continuous return transform and preserves velocity if retargeted.
    }

    func finishRestoration() {
        cancelRestoration()
        transform = .closed
        phase = .closed
    }

    private func cancelRestoration() {
        restorationAnimations.forEach(animationDriver.cancel)
        restorationAnimations.removeAll()
    }
}

struct EmotionPhysicsState: Equatable, Identifiable {
    var id: UUID
    var creationIndex: Int
    var imageName: String
    var position: CGPoint
    var rotation: CGFloat
    var velocity: CGVector
    var angularVelocity: CGFloat
    var mass: CGFloat
    var friction: CGFloat
    var restitution: CGFloat
    var linearDamping: CGFloat
    var angularDamping: CGFloat
    var collisionShape: String
    var sleeping: Bool
    var visualSize: CGFloat
}

struct TrashPlacement: Codable {
    var creationIndex: Int
    var unitX: CGFloat
    var unitY: CGFloat
    var rotation: CGFloat
    var imageName: String
}

enum CoordinateSpaceAdapter {
    static func swiftUILocalToGlobal(_ point: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
    }

    static func globalToSwiftUILocal(_ point: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }

    static func spriteKitToSwiftUI(_ point: CGPoint, sceneSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: sceneSize.height - point.y)
    }

    static func swiftUIToSpriteKit(_ point: CGPoint, sceneSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: sceneSize.height - point.y)
    }

    static func spriteKitToGlobal(_ point: CGPoint, sceneSize: CGSize, frame: CGRect) -> CGPoint {
        let local = spriteKitToSwiftUI(point, sceneSize: sceneSize)
        return CGPoint(
            x: frame.minX + local.x / max(sceneSize.width, 1) * frame.width,
            y: frame.minY + local.y / max(sceneSize.height, 1) * frame.height
        )
    }

    static func globalToSpriteKit(_ point: CGPoint, sceneSize: CGSize, frame: CGRect) -> CGPoint {
        let unit = CGPoint(
            x: (point.x - frame.minX) / max(frame.width, 1),
            y: (point.y - frame.minY) / max(frame.height, 1)
        )
        return CGPoint(x: unit.x * sceneSize.width, y: (1 - unit.y) * sceneSize.height)
    }
}

@MainActor
final class TrashBinPhysicsSystem: ObservableObject {
    @Published private(set) var emotions: [EmotionPhysicsState] = []
    @Published private(set) var scene: TrashBinPhysicsScene

    static let maximumVisibleCount = 10
    static let openingUnit = CGPoint(x: 0.50, y: 0.145)
    static let openingHalfWidthUnit: CGFloat = 0.205
    static let openingTopUnit: CGFloat = 0.085
    static let visualSizeUnit: CGFloat = 0.125

    private var configuredSize: CGSize = .zero

    init() {
        let scene = TrashBinPhysicsScene(size: CGSize(width: 272, height: 272))
        self.scene = scene
        scene.onStatesChanged = { [weak self] states in
            self?.emotions = states
        }
    }

    var openingCenter: CGPoint {
        CGPoint(x: configuredSize.width * Self.openingUnit.x, y: configuredSize.height * Self.openingUnit.y)
    }

    var openingBounds: CGRect {
        let center = openingCenter
        let half = configuredSize.width * Self.openingHalfWidthUnit
        return CGRect(
            x: center.x - half,
            y: configuredSize.height * Self.openingTopUnit,
            width: half * 2,
            height: center.y - configuredSize.height * Self.openingTopUnit + 5
        )
    }

    func configure(size: CGSize, count: Int) {
        let side = max(1, min(size.width, size.height))
        let target = CGSize(width: side, height: side)
        if abs(target.width - configuredSize.width) > 0.5 {
            configuredSize = target
            scene.resize(to: target)
        }
        setCount(count, animated: false)
    }

    func setCount(_ count: Int, animated: Bool) {
        scene.setCount(min(max(count, 0), Self.maximumVisibleCount), animated: animated)
    }

    func selectEmotion(id: UUID? = nil) -> EmotionPhysicsState? {
        if let id {
            return emotions.first(where: { $0.id == id })
        }
        return emotions.max { lhs, rhs in
            if abs(lhs.position.y - rhs.position.y) > 3 {
                return lhs.position.y < rhs.position.y
            }
            return lhs.creationIndex < rhs.creationIndex
        }
    }

    @discardableResult
    func detach(_ id: UUID) -> EmotionPhysicsState? {
        scene.detach(id: id)
    }

    func attachDynamic(imageName: String? = nil) {
        scene.spawn(imageName: imageName, animated: true)
    }

    func globalPosition(of emotion: EmotionPhysicsState, containerFrame: CGRect) -> CGPoint {
        CoordinateSpaceAdapter.spriteKitToGlobal(
            emotion.position,
            sceneSize: scene.size,
            frame: containerFrame
        )
    }

    func globalOpeningCenter(containerFrame: CGRect) -> CGPoint {
        CoordinateSpaceAdapter.swiftUILocalToGlobal(openingCenter, frame: containerFrame)
    }

    func globalOpeningBounds(containerFrame: CGRect) -> CGRect {
        openingBounds.offsetBy(dx: containerFrame.minX, dy: containerFrame.minY)
    }
}

final class TrashBinPhysicsScene: SKScene {
    var onStatesChanged: (([EmotionPhysicsState]) -> Void)?

    private let preset = PhysicsPreset.trash
    private var nextCreationIndex = 0
    private var stableSince: TimeInterval?
    private var lastPublish: TimeInterval = 0
    private var targetCount = 0

    private var emotionNodes: [SKSpriteNode] {
        children.compactMap { $0 as? SKSpriteNode }.filter { $0.name?.hasPrefix("emotion:") == true }
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -preset.gravity)
        rebuildBoundary()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func resize(to size: CGSize) {
        self.size = size
        rebuildBoundary()
        restoreCurrentNodesToBounds()
    }

    func setCount(_ count: Int, animated: Bool) {
        targetCount = count
        if emotionNodes.isEmpty, count > 0, !animated, restore(count: count) {
            publishStates()
            return
        }
        if emotionNodes.isEmpty, count > 0, !animated {
            speed = 4
            run(.sequence([
                .wait(forDuration: 4.4),
                .run { [weak self] in self?.speed = 1 }
            ]))
        }
        if count > emotionNodes.count {
            for _ in emotionNodes.count..<count {
                spawn(imageName: nil, animated: animated)
            }
        } else if count < emotionNodes.count {
            let ordered = emotionNodes.sorted { creationIndex(of: $0) > creationIndex(of: $1) }
            for node in ordered.prefix(emotionNodes.count - count) {
                node.removeFromParent()
            }
            publishStates()
        }
    }

    func spawn(imageName: String?, animated: Bool) {
        let index = nextCreationIndex
        nextCreationIndex += 1
        let resolvedName = imageName ?? "TrashEmotion_\((index % TrashBinPhysicsSystem.maximumVisibleCount) + 1)"
        let visual = size.width * TrashBinPhysicsSystem.visualSizeUnit
        let texture = SKTexture(imageNamed: resolvedName)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: CGSize(width: visual, height: visual))
        node.name = "emotion:\(index):\(UUID().uuidString)"
        node.userData = NSMutableDictionary()
        node.userData?["id"] = UUID().uuidString
        node.userData?["creationIndex"] = index
        node.userData?["imageName"] = resolvedName
        let body = SKPhysicsBody(circleOfRadius: visual * 0.40)
        body.mass = preset.mass
        body.friction = preset.friction
        body.restitution = preset.restitution
        body.linearDamping = preset.linearDamping
        body.angularDamping = 1
        body.allowsRotation = false
        body.angularVelocity = 0
        body.usesPreciseCollisionDetection = true
        node.physicsBody = body
        node.position = spawnPosition(index: index, radius: visual * 0.40)
        node.zRotation = CGFloat((index * 31) % 29 - 14) * .pi / 180
        node.alpha = animated ? 1 : 0
        addChild(node)
        if !animated {
            node.run(.fadeIn(withDuration: 0.20))
        }
        wakeNearby(around: node.position, radius: visual * 2.2)
        publishStates()
    }

    func detach(id: UUID) -> EmotionPhysicsState? {
        guard let node = emotionNodes.first(where: { nodeID(of: $0) == id }) else { return nil }
        let state = state(for: node)
        let removedPosition = node.position
        let radius = node.size.width * 2.2
        node.removeFromParent()
        wakeNearby(around: removedPosition, radius: radius)
        publishStates()
        return state
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        applySlopeAssist()
        for node in emotionNodes {
            node.physicsBody?.angularVelocity = 0
        }
        let moving = emotionNodes.contains { node in
            guard let body = node.physicsBody else { return false }
            return hypot(body.velocity.dx, body.velocity.dy) >= preset.sleepVelocityThreshold
        }
        if moving {
            stableSince = nil
        } else if stableSince == nil {
            stableSince = currentTime
        } else if let stableSince, currentTime - stableSince >= preset.stableDuration {
            savePlacement()
        }
        if currentTime - lastPublish > 1.0 / 30.0 {
            lastPublish = currentTime
            publishStates()
        }
    }

    private func rebuildBoundary() {
        childNode(withName: "trash-boundary")?.removeFromParent()
        let boundary = SKNode()
        boundary.name = "trash-boundary"
        let points = [
            CGPoint(x: size.width * 0.285, y: size.height * 0.86),
            CGPoint(x: size.width * 0.29, y: size.height * 0.77),
            CGPoint(x: size.width * 0.30, y: size.height * 0.68),
            CGPoint(x: size.width * 0.70, y: size.height * 0.68),
            CGPoint(x: size.width * 0.71, y: size.height * 0.77),
            CGPoint(x: size.width * 0.715, y: size.height * 0.86)
        ]
        let path = CGMutablePath()
        path.addLines(between: points)
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.friction = preset.friction
        body.restitution = preset.restitution
        boundary.physicsBody = body
        addChild(boundary)
    }

    private func spawnPosition(index: Int, radius: CGFloat) -> CGPoint {
        let openingX = size.width * 0.50
        let half = size.width * TrashBinPhysicsSystem.openingHalfWidthUnit
        let jitter = CGFloat((index * 37 + 7) % 19 - 9) / 9 * half * 0.62
        let x = min(max(openingX + jitter, openingX - half + radius), openingX + half - radius)
        return CGPoint(
            x: x,
            y: size.height * 0.94 + radius + CGFloat(index) * size.width * TrashBinPhysicsSystem.visualSizeUnit * 0.82
        )
    }

    private func applySlopeAssist() {
        let nodes = emotionNodes
        for node in nodes {
            guard let body = node.physicsBody, !body.isResting else { continue }
            let neighbors = nodes.filter {
                $0 !== node && hypot($0.position.x - node.position.x, $0.position.y - node.position.y) < node.size.width * 1.08
            }
            guard neighbors.count == 1,
                  let support = neighbors.first,
                  node.position.y > support.position.y + node.size.height * 0.45
            else { continue }
            let direction: CGFloat = node.position.x >= support.position.x ? 1 : -1
            body.applyForce(CGVector(dx: direction * 0.18, dy: 0))
            body.friction = min(body.friction, 0.52)
        }
    }

    private func wakeNearby(around point: CGPoint, radius: CGFloat) {
        for node in emotionNodes where hypot(node.position.x - point.x, node.position.y - point.y) <= radius {
            node.physicsBody?.isResting = false
        }
    }

    private func restoreCurrentNodesToBounds() {
        for node in emotionNodes {
            node.position.x = min(max(node.position.x, size.width * 0.30), size.width * 0.70)
            node.position.y = min(max(node.position.y, size.height * 0.69), size.height * 0.88)
        }
    }

    private func placementKey(_ count: Int) -> String {
        "trashBin.spriteKitPlacement.v2.\(count)"
    }

    private func restore(count: Int) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: placementKey(count)),
              let placements = try? PropertyListDecoder().decode([TrashPlacement].self, from: data),
              placements.count == count
        else { return false }

        nextCreationIndex = 0
        for placement in placements.sorted(by: { $0.creationIndex < $1.creationIndex }) {
            spawn(imageName: placement.imageName, animated: true)
            guard let node = emotionNodes.max(by: { creationIndex(of: $0) < creationIndex(of: $1) }) else { continue }
            node.position = CGPoint(x: placement.unitX * size.width, y: placement.unitY * size.height)
            node.zRotation = placement.rotation
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
            node.physicsBody?.isResting = true
        }
        return true
    }

    private func savePlacement() {
        let placements = emotionNodes.map { node in
            TrashPlacement(
                creationIndex: creationIndex(of: node),
                unitX: node.position.x / max(size.width, 1),
                unitY: node.position.y / max(size.height, 1),
                rotation: node.zRotation,
                imageName: imageName(of: node)
            )
        }
        .sorted { $0.creationIndex < $1.creationIndex }
        guard placements.count == targetCount,
              let data = try? PropertyListEncoder().encode(placements)
        else { return }
        UserDefaults.standard.set(data, forKey: placementKey(placements.count))
    }

    private func publishStates() {
        onStatesChanged?(emotionNodes.map(state(for:)))
    }

    private func state(for node: SKSpriteNode) -> EmotionPhysicsState {
        let body = node.physicsBody
        return EmotionPhysicsState(
            id: nodeID(of: node),
            creationIndex: creationIndex(of: node),
            imageName: imageName(of: node),
            position: node.position,
            rotation: node.zRotation,
            velocity: body?.velocity ?? .zero,
            angularVelocity: body?.angularVelocity ?? 0,
            mass: body?.mass ?? preset.mass,
            friction: body?.friction ?? preset.friction,
            restitution: body?.restitution ?? preset.restitution,
            linearDamping: body?.linearDamping ?? preset.linearDamping,
            angularDamping: body?.angularDamping ?? preset.angularDamping,
            collisionShape: "insetCircle",
            sleeping: body?.isResting ?? true,
            visualSize: node.size.width
        )
    }

    private func nodeID(of node: SKSpriteNode) -> UUID {
        UUID(uuidString: node.userData?["id"] as? String ?? "") ?? UUID()
    }

    private func creationIndex(of node: SKSpriteNode) -> Int {
        node.userData?["creationIndex"] as? Int ?? 0
    }

    private func imageName(of node: SKSpriteNode) -> String {
        node.userData?["imageName"] as? String ?? "TrashEmotion_1"
    }
}

struct TrashBinVisual: View {
    @ObservedObject var physics: TrashBinPhysicsSystem
    @ObservedObject var lid: TrashLidController
    var count: Int
    var reportsRevealAnchors = false
    var animateCountChanges = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            let lidScale = side / 272

            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: side * 0.58, height: side * 0.08)
                    .blur(radius: 9)
                    .position(x: frame.midX, y: frame.minY + side * 0.86)

                Image("PaperBinFilled")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .position(x: frame.midX, y: frame.midY)

                SpriteView(scene: physics.scene, options: [.allowsTransparency])
                    .frame(width: side, height: side)
                    .mask(TrashInteriorMask())
                    .opacity(lid.phase == .closed ? 0 : 1)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)

                TrashBinForegroundLayer()
                    .frame(width: side, height: side)
                    .position(x: frame.midX, y: frame.midY)

                Image("PaperBinEmpty")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(lid.transform.rotationZ))
                    .offset(
                        x: lid.transform.offset.width * lidScale,
                        y: -side * 0.34 + lid.transform.offset.height * lidScale
                    )
                    .position(x: frame.midX, y: frame.midY)

                if reportsRevealAnchors {
                    RevealAnchorProbe(kind: .paper, id: .container)
                        .frame(width: side, height: side)
                        .position(x: frame.midX, y: frame.midY)

                    RevealAnchorProbe(kind: .paper, id: .exit)
                        .frame(width: 2, height: 2)
                        .position(
                            x: frame.minX + physics.openingCenter.x,
                            y: frame.minY + physics.openingCenter.y
                        )

                    if let target = physics.selectEmotion() {
                        let local = CoordinateSpaceAdapter.spriteKitToSwiftUI(
                            target.position,
                            sceneSize: physics.scene.size
                        )
                        RevealAnchorProbe(kind: .paper, id: .content)
                            .frame(width: target.visualSize, height: target.visualSize)
                            .position(x: frame.minX + local.x, y: frame.minY + local.y)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                physics.configure(size: CGSize(width: side, height: side), count: count)
            }
            .onChange(of: side) { newSide in
                physics.configure(size: CGSize(width: newSide, height: newSide), count: count)
            }
            .onChange(of: count) { newCount in
                physics.setCount(newCount, animated: animateCountChanges)
            }
        }
    }
}

struct TrashBinForegroundLayer: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Image("PaperBinFilled")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: side * 0.34)
                            Rectangle()
                        }
                    }

                Image("PaperBinFilled")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .mask {
                        TrashRimMask()
                            .fill(Color.white, style: FillStyle(eoFill: true))
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct TrashRimMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.205))
        path.addEllipse(in: CGRect(
            x: rect.width * 0.30,
            y: rect.height * 0.095,
            width: rect.width * 0.40,
            height: rect.height * 0.075
        ))
        return path
    }
}

private struct TrashInteriorMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.285, y: rect.height * 0.105))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.715, y: rect.height * 0.105),
            control: CGPoint(x: rect.width * 0.50, y: rect.height * 0.055)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.38))
        path.closeSubpath()
        return path
    }
}
