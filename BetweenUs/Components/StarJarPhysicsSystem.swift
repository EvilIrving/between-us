import Combine
import QuartzCore
import SwiftUI

enum StarCollisionShape: Equatable {
    case star
}

enum StarSilhouette {
    static let outerRatio: CGFloat = 0.46
    static let innerRatio: CGFloat = 0.23
    static let points = 5

    static func radius(
        along nx: CGFloat,
        ny: CGFloat,
        rotation: CGFloat,
        visualSize: CGFloat
    ) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        let sector = twoPi / CGFloat(points)
        var local = atan2(ny, nx) - rotation + .pi / 2
        local = local.truncatingRemainder(dividingBy: twoPi)
        if local < 0 { local += twoPi }
        var inSector = local.truncatingRemainder(dividingBy: sector)
        if inSector > sector * 0.5 {
            inSector = sector - inSector
        }
        let u = min(max(inSector / (sector * 0.5), 0), 1)
        let blend = u * u * (3 - 2 * u)
        let outer = visualSize * outerRatio
        let inner = visualSize * innerRatio
        return outer + (inner - outer) * blend
    }
}

enum StarJarMetrics {
    static let maxStars = 10
    static let visualUnit: CGFloat = 0.148
    static let collisionRadiusUnit: CGFloat = visualUnit * StarSilhouette.outerRatio
    static let mouthCenter = CGPoint(x: 0.50, y: 0.072)
    static let mouthTop: CGFloat = 0.041
    static let mouthInnerHalf: CGFloat = 0.178
    static let releaseLift: CGFloat = 20
    static let layerClearance: CGFloat = 4

    static let gravity: CGFloat = 320
    static let restitution: CGFloat = 0.14
    static let friction: CGFloat = 0.72
    static let linearDamping: CGFloat = 1.45
    static let angularDamping: CGFloat = 7.0
    static let mass: CGFloat = 1.0
    static let solverIterations = 5
    static let penetrationSlop: CGFloat = 0.55
    static let correctionPercent: CGFloat = 0.48
    static let maxLinearSpeed: CGFloat = 420
    static let maxAngularSpeed: CGFloat = 2.2
    static let sleepLinearSpeed: CGFloat = 6
    static let sleepAngularSpeed: CGFloat = 0.15
    static let sleepDelay: CGFloat = 0.20

    /// Inner glass surface in unit space, clockwise from the left mouth lip
    /// around the floor to the right lip. The mouth itself stays open.
    /// Sampled from StarJarBottle inner cavity, then inset so charms rest
    /// against glass instead of clipping through it.
    static let interiorContour: [CGPoint] = [
        CGPoint(x: 0.318, y: 0.078),
        CGPoint(x: 0.310, y: 0.118),
        CGPoint(x: 0.300, y: 0.158),
        CGPoint(x: 0.272, y: 0.198),
        CGPoint(x: 0.228, y: 0.248),
        CGPoint(x: 0.188, y: 0.300),
        CGPoint(x: 0.174, y: 0.360),
        CGPoint(x: 0.168, y: 0.520),
        CGPoint(x: 0.168, y: 0.700),
        CGPoint(x: 0.174, y: 0.810),
        CGPoint(x: 0.190, y: 0.868),
        CGPoint(x: 0.232, y: 0.910),
        CGPoint(x: 0.312, y: 0.930),
        CGPoint(x: 0.400, y: 0.938),
        CGPoint(x: 0.500, y: 0.942),
        CGPoint(x: 0.600, y: 0.938),
        CGPoint(x: 0.688, y: 0.930),
        CGPoint(x: 0.768, y: 0.910),
        CGPoint(x: 0.810, y: 0.868),
        CGPoint(x: 0.826, y: 0.810),
        CGPoint(x: 0.832, y: 0.700),
        CGPoint(x: 0.832, y: 0.520),
        CGPoint(x: 0.826, y: 0.360),
        CGPoint(x: 0.812, y: 0.300),
        CGPoint(x: 0.772, y: 0.248),
        CGPoint(x: 0.728, y: 0.198),
        CGPoint(x: 0.700, y: 0.158),
        CGPoint(x: 0.690, y: 0.118),
        CGPoint(x: 0.682, y: 0.078)
    ]
}

struct StarPhysicsState: Equatable, Identifiable {
    var id: UUID
    var creationIndex: Int
    var charm: StarCharm
    var position: CGPoint
    var rotation: CGFloat
    var velocity: CGVector
    var angularVelocity: CGFloat
    var mass: CGFloat
    var friction: CGFloat
    var restitution: CGFloat
    var linearDamping: CGFloat
    var angularDamping: CGFloat
    var sleeping: Bool
    var kinematic: Bool
    var radius: CGFloat
    var visualSize: CGFloat
    var collisionShape: StarCollisionShape

    var unitPosition: CGPoint {
        CGPoint(x: position.x, y: position.y)
    }
}

struct StarPlacement: Codable, Equatable {
    var creationIndex: Int
    var unitPosition: CGPoint
    var rotation: CGFloat
    var charmName: String
}

enum StarJarCoordinates {
    static func unit(from point: CGPoint, side: CGFloat) -> CGPoint {
        let safe = max(side, 1)
        return CGPoint(x: point.x / safe, y: point.y / safe)
    }

    static func local(fromUnit unit: CGPoint, side: CGFloat) -> CGPoint {
        CGPoint(x: unit.x * side, y: unit.y * side)
    }

    static func space(fromLocal point: CGPoint, bottleFrame: CGRect, side: CGFloat) -> CGPoint {
        let unit = self.unit(from: point, side: side)
        return CGPoint(
            x: bottleFrame.minX + unit.x * bottleFrame.width,
            y: bottleFrame.minY + unit.y * bottleFrame.height
        )
    }

    static func local(fromSpace point: CGPoint, bottleFrame: CGRect, side: CGFloat) -> CGPoint {
        let width = max(bottleFrame.width, 1)
        let height = max(bottleFrame.height, 1)
        let unit = CGPoint(
            x: (point.x - bottleFrame.minX) / width,
            y: (point.y - bottleFrame.minY) / height
        )
        return local(fromUnit: unit, side: side)
    }

    static func mouthCenter(in side: CGFloat) -> CGPoint {
        local(fromUnit: StarJarMetrics.mouthCenter, side: side)
    }

    static func mouthTopY(in side: CGFloat) -> CGFloat {
        StarJarMetrics.mouthTop * side
    }

    static func mouthBounds(in side: CGFloat) -> CGRect {
        let center = mouthCenter(in: side)
        let half = StarJarMetrics.mouthInnerHalf * side
        let top = mouthTopY(in: side)
        return CGRect(x: center.x - half, y: top, width: half * 2, height: max(8, center.y - top + 6))
    }
}

@MainActor
final class StarJarPhysicsSystem: ObservableObject {
    @Published private(set) var stars: [StarPhysicsState] = []
    @Published private(set) var isSimulating = false
    @Published private(set) var side: CGFloat = 0

    private var bodies: [Body] = []
    private var walls: [Segment] = []
    private var driver: CADisplayLink?
    private let proxy = PhysicsDisplayLinkProxy()
    private var lastTimestamp: CFTimeInterval = 0
    private var nextCreationIndex = 0
    private var configuredSide: CGFloat = 0

    private static var placementCache: [Int: [StarPlacement]] = [:]
    private static let placementVersion = 4

    init() {
        proxy.handler = { [weak self] in
            self?.tick()
        }
    }

    deinit {
        driver?.invalidate()
        driver = nil
    }

    var mouthCenter: CGPoint {
        StarJarCoordinates.mouthCenter(in: max(side, 1))
    }

    var mouthTopY: CGFloat {
        StarJarCoordinates.mouthTopY(in: max(side, 1))
    }

    var mouthBounds: CGRect {
        StarJarCoordinates.mouthBounds(in: max(side, 1))
    }

    var visualSize: CGFloat {
        StarJarMetrics.visualUnit * max(side, 1)
    }

    var collisionRadius: CGFloat {
        StarJarMetrics.collisionRadiusUnit * max(side, 1)
    }

    func configure(side: CGFloat) {
        let clamped = max(side, 1)
        guard abs(clamped - configuredSide) > 0.5 else { return }
        let previous = configuredSide
        configuredSide = clamped
        self.side = clamped
        rebuildWalls()
        if previous > 1, !bodies.isEmpty {
            let scale = clamped / previous
            for index in bodies.indices {
                bodies[index].position.x *= scale
                bodies[index].position.y *= scale
                bodies[index].radius *= scale
                bodies[index].visualSize *= scale
            }
            publish()
        }
    }

    func initialStars(count: Int = StarJarMetrics.maxStars) {
        setStarCount(count, animated: false)
    }

    func setStarCount(_ count: Int, animated: Bool) {
        let target = min(max(count, 0), StarJarMetrics.maxStars)
        guard configuredSide > 1 else { return }

        if bodies.isEmpty, target > 0 {
            if animated {
                for _ in 0..<target {
                    spawnStar(animated: true)
                }
            } else {
                restoreOrBake(count: target)
            }
            return
        }

        if target > bodies.count {
            let missing = target - bodies.count
            for _ in 0..<missing {
                spawnStar(animated: animated)
            }
            return
        }

        if target < bodies.count {
            let extra = bodies.count - target
            for _ in 0..<extra {
                _ = detachTargetStar()
            }
        }
    }

    func spawnStar(animated: Bool) {
        guard configuredSide > 1 else { return }
        let index = nextCreationIndex
        nextCreationIndex += 1
        var body = makeBody(index: index)
        body.position = spawnPosition(for: body)
        body.sleeping = false
        bodies.append(body)
        publish()
        if animated {
            startLoop()
        } else {
            settleFast(maxTime: 2.4)
        }
    }

    func topmostStar() -> StarPhysicsState? {
        guard let body = topmostBody() else { return nil }
        return publishedStar(from: body)
    }

    @discardableResult
    func detachStar(id: UUID) -> StarPhysicsState? {
        guard let target = bodies.first(where: { $0.id == id }) else { return nil }
        let state = publishedStar(from: target)
        bodies.removeAll { $0.id == id }
        wakeForSettle()
        publish()
        startLoop()
        return state
    }

    @discardableResult
    func detachTargetStar() -> StarPhysicsState? {
        guard let target = topmostBody() else { return nil }
        return detachStar(id: target.id)
    }

    func reinsert(_ state: StarPhysicsState) {
        var body = makeBody(index: state.creationIndex, id: state.id, charm: state.charm)
        body.position = state.position
        body.rotation = state.rotation
        body.sleeping = false
        bodies.append(body)
        nextCreationIndex = max(nextCreationIndex, state.creationIndex + 1)
        publish()
        startLoop()
    }

    func applyGentleShakeImpulse() {
        guard !bodies.isEmpty else { return }
        for index in bodies.indices {
            guard !bodies[index].kinematic else { continue }
            bodies[index].sleeping = false
            let sign: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            bodies[index].velocity.dx += sign * 9
            bodies[index].velocity.dy -= 5
            clampSpeed(&bodies[index], maxSpeed: 22)
        }
        publish()
        startLoop()
    }

    func isAboveMouth(_ star: StarPhysicsState) -> Bool {
        let bottom = star.position.y + star.visualSize * 0.48
        return bottom < mouthTopY - StarJarMetrics.layerClearance
    }

    func savedPlacement() -> [StarPlacement] {
        bodies.map { body in
            StarPlacement(
                creationIndex: body.creationIndex,
                unitPosition: StarJarCoordinates.unit(from: body.position, side: max(side, 1)),
                rotation: body.rotation,
                charmName: body.charm.imageName
            )
        }
        .sorted { $0.creationIndex < $1.creationIndex }
    }

    private func restoreOrBake(count: Int) {
        rebuildWalls()
        if let cached = Self.placementCache[count], cached.count == count {
            apply(placements: cached)
            return
        }
        if let persisted = Self.loadPlacements(count: count), persisted.count == count {
            Self.placementCache[count] = persisted
            apply(placements: persisted)
            return
        }
        let baked = Self.bake(count: count, side: max(configuredSide, 320))
        Self.placementCache[count] = baked
        Self.savePlacements(baked, count: count)
        apply(placements: baked)
    }

    private func apply(placements: [StarPlacement]) {
        bodies = placements.map { placement in
            let charm = StarCharm.all.first(where: { $0.imageName == placement.charmName })
                ?? StarCharm.displayCharms(count: placement.creationIndex + 1).last
                ?? StarCharm.random()
            var body = makeBody(index: placement.creationIndex, charm: charm)
            body.position = StarJarCoordinates.local(fromUnit: placement.unitPosition, side: max(side, 1))
            body.rotation = placement.rotation
            body.sleeping = true
            body.velocity = .zero
            body.angularVelocity = 0
            return body
        }
        nextCreationIndex = (bodies.map(\.creationIndex).max() ?? -1) + 1
        publish()
    }

    private func makeBody(index: Int, id: UUID = UUID(), charm: StarCharm? = nil) -> Body {
        let visual = visualSize
        let radius = visual * StarSilhouette.outerRatio
        let inertia = 0.38 * StarJarMetrics.mass * radius * radius
        return Body(
            id: id,
            creationIndex: index,
            charm: charm ?? Self.charm(for: index),
            position: .zero,
            rotation: spawnRotation(index),
            velocity: .zero,
            angularVelocity: 0,
            mass: StarJarMetrics.mass,
            inverseMass: 1 / StarJarMetrics.mass,
            inertia: inertia,
            inverseInertia: inertia > 0 ? 1 / inertia : 0,
            friction: StarJarMetrics.friction,
            restitution: StarJarMetrics.restitution,
            linearDamping: StarJarMetrics.linearDamping,
            angularDamping: StarJarMetrics.angularDamping,
            radius: radius,
            visualSize: visual,
            collisionShape: .star,
            sleeping: false,
            kinematic: false,
            sleepTimer: 0
        )
    }

    private func spawnPosition(for body: Body) -> CGPoint {
        let mouth = mouthBounds
        let top = bodies.min(by: { $0.position.y < $1.position.y })
        var x = mouth.midX
        if let top {
            x = top.position.x
        }
        x += spawnJitter(body.creationIndex)
        let minX = mouth.minX + body.radius + 1
        let maxX = mouth.maxX - body.radius - 1
        x = min(max(x, min(minX, maxX)), max(minX, maxX))
        let y = mouth.minY - body.radius - 12
        return CGPoint(x: x, y: y)
    }

    private func spawnJitter(_ index: Int) -> CGFloat {
        let span = StarJarMetrics.mouthInnerHalf * max(side, 1) * 0.52
        let stepped = CGFloat((index * 37 + 11) % 21) - 10
        return (stepped / 10) * span
    }

    private func spawnRotation(_ index: Int) -> CGFloat {
        CGFloat((index * 47) % 360) * .pi / 180
    }

    private func rebuildWalls() {
        let points = StarJarMetrics.interiorContour.map {
            StarJarCoordinates.local(fromUnit: $0, side: max(configuredSide, 1))
        }
        walls = zip(points, points.dropFirst()).map { Segment(a: $0, b: $1) }
    }

    fileprivate static func charm(for index: Int) -> StarCharm {
        StarCharm.all[(index * 11 + 3) % StarCharm.all.count]
    }

    private static func placementKey(count: Int) -> String {
        "starJar.placements.v\(placementVersion).\(count)"
    }

    private static func loadPlacements(count: Int) -> [StarPlacement]? {
        guard let data = UserDefaults.standard.data(forKey: placementKey(count: count)) else { return nil }
        return try? PropertyListDecoder().decode([StarPlacement].self, from: data)
    }

    private static func savePlacements(_ placements: [StarPlacement], count: Int) {
        guard let data = try? PropertyListEncoder().encode(placements) else { return }
        UserDefaults.standard.set(data, forKey: placementKey(count: count))
    }

    private func topmostBody() -> Body? {
        bodies
            .filter { !$0.kinematic }
            .min { lhs, rhs in
                if abs(lhs.position.y - rhs.position.y) > 4 {
                    return lhs.position.y < rhs.position.y
                }
                return lhs.creationIndex > rhs.creationIndex
            }
    }

    private func wakeForSettle() {
        for index in bodies.indices {
            bodies[index].sleeping = false
            bodies[index].sleepTimer = 0
            bodies[index].velocity.dy += 14
            clampSpeed(&bodies[index], maxSpeed: 32)
        }
    }

    private func startLoop() {
        if driver != nil {
            isSimulating = true
            return
        }
        lastTimestamp = 0
        let link = CADisplayLink(target: proxy, selector: #selector(PhysicsDisplayLinkProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        driver = link
        isSimulating = true
    }

    private func stopLoop() {
        driver?.invalidate()
        driver = nil
        isSimulating = false
        lastTimestamp = 0
        guard !bodies.isEmpty else { return }
        let placements = savedPlacement()
        Self.placementCache[bodies.count] = placements
        Self.savePlacements(placements, count: bodies.count)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt: CGFloat
        if lastTimestamp == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(CGFloat(now - lastTimestamp), 1.0 / 30.0)
        }
        lastTimestamp = now
        step(dt: dt, substeps: 3)
        publish()
        if bodies.allSatisfy({ $0.sleeping || $0.kinematic }) {
            stopLoop()
        }
    }

    private func settleFast(maxTime: CGFloat) {
        var time: CGFloat = 0
        let dt: CGFloat = 1.0 / 120.0
        while time < maxTime {
            step(dt: dt, substeps: 1)
            time += dt
            if bodies.allSatisfy({ $0.sleeping || $0.kinematic }) {
                break
            }
        }
        publish()
        if !bodies.allSatisfy({ $0.sleeping || $0.kinematic }) {
            startLoop()
        }
    }

    private func step(dt: CGFloat, substeps: Int) {
        StarPhysicsSolver.step(bodies: &bodies, walls: walls, dt: dt, substeps: substeps)
    }

    private func clampSpeed(_ body: inout Body, maxSpeed: CGFloat) {
        StarPhysicsSolver.clampSpeed(&body, maxSpeed: maxSpeed)
    }

    private func publish() {
        stars = bodies.map(publishedStar(from:))
    }

    private func publishedStar(from body: Body) -> StarPhysicsState {
        StarPhysicsState(
            id: body.id,
            creationIndex: body.creationIndex,
            charm: body.charm,
            position: body.position,
            rotation: body.rotation,
            velocity: body.velocity,
            angularVelocity: body.angularVelocity,
            mass: body.mass,
            friction: body.friction,
            restitution: body.restitution,
            linearDamping: body.linearDamping,
            angularDamping: body.angularDamping,
            sleeping: body.sleeping,
            kinematic: body.kinematic,
            radius: body.radius,
            visualSize: body.visualSize,
            collisionShape: body.collisionShape
        )
    }

    private static func bake(count: Int, side: CGFloat) -> [StarPlacement] {
        var world = OfflineWorld(side: side)
        for index in 0..<count {
            world.spawn(index: index)
            world.settle(maxTime: 0.82)
        }
        world.settle(maxTime: 3.6)
        return world.placements()
    }
}

private struct Body {
    var id: UUID
    var creationIndex: Int
    var charm: StarCharm
    var position: CGPoint
    var rotation: CGFloat
    var velocity: CGVector
    var angularVelocity: CGFloat
    var mass: CGFloat
    var inverseMass: CGFloat
    var inertia: CGFloat
    var inverseInertia: CGFloat
    var friction: CGFloat
    var restitution: CGFloat
    var linearDamping: CGFloat
    var angularDamping: CGFloat
    var radius: CGFloat
    var visualSize: CGFloat
    var collisionShape: StarCollisionShape
    var sleeping: Bool
    var kinematic: Bool
    var sleepTimer: CGFloat
}

private struct Segment {
    var a: CGPoint
    var b: CGPoint

    var inwardNormal: CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(0.0001, hypot(dx, dy))
        return CGVector(dx: dy / length, dy: -dx / length)
    }

    func closestPoint(to point: CGPoint) -> CGPoint {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let span = abx * abx + aby * aby
        guard span > 0.0001 else { return a }
        let t = min(max(((point.x - a.x) * abx + (point.y - a.y) * aby) / span, 0), 1)
        return CGPoint(x: a.x + abx * t, y: a.y + aby * t)
    }
}

private struct OfflineWorld {
    var side: CGFloat
    var bodies: [Body] = []
    var walls: [Segment]

    init(side: CGFloat) {
        self.side = side
        let points = StarJarMetrics.interiorContour.map {
            StarJarCoordinates.local(fromUnit: $0, side: side)
        }
        self.walls = zip(points, points.dropFirst()).map { Segment(a: $0, b: $1) }
    }

    mutating func spawn(index: Int) {
        let visual = StarJarMetrics.visualUnit * side
        let radius = visual * StarSilhouette.outerRatio
        let inertia = 0.38 * StarJarMetrics.mass * radius * radius
        let mouth = StarJarCoordinates.mouthBounds(in: side)
        let jitter = CGFloat((index * 37 + 11) % 21 - 10) / 10 * StarJarMetrics.mouthInnerHalf * side * 0.52
        var x = mouth.midX + jitter
        x = min(max(x, mouth.minX + radius + 1), mouth.maxX - radius - 1)
        let body = Body(
            id: UUID(),
            creationIndex: index,
            charm: StarCharm.all[(index * 11 + 3) % StarCharm.all.count],
            position: CGPoint(x: x, y: mouth.minY - radius - 12 - CGFloat(index % 3)),
            rotation: CGFloat((index * 47) % 360) * .pi / 180,
            velocity: .zero,
            angularVelocity: 0,
            mass: StarJarMetrics.mass,
            inverseMass: 1,
            inertia: inertia,
            inverseInertia: inertia > 0 ? 1 / inertia : 0,
            friction: StarJarMetrics.friction,
            restitution: StarJarMetrics.restitution,
            linearDamping: StarJarMetrics.linearDamping,
            angularDamping: StarJarMetrics.angularDamping,
            radius: radius,
            visualSize: visual,
            collisionShape: .star,
            sleeping: false,
            kinematic: false,
            sleepTimer: 0
        )
        bodies.append(body)
    }

    mutating func settle(maxTime: CGFloat) {
        var time: CGFloat = 0
        let dt: CGFloat = 1.0 / 120.0
        while time < maxTime {
            StarPhysicsSolver.step(bodies: &bodies, walls: walls, dt: dt, substeps: 1)
            time += dt
            if bodies.allSatisfy(\.sleeping) { break }
        }
    }

    func placements() -> [StarPlacement] {
        bodies.map { body in
            StarPlacement(
                creationIndex: body.creationIndex,
                unitPosition: StarJarCoordinates.unit(from: body.position, side: side),
                rotation: body.rotation,
                charmName: body.charm.imageName
            )
        }
        .sorted { $0.creationIndex < $1.creationIndex }
    }
}

private enum StarPhysicsSolver {
    static func step(bodies: inout [Body], walls: [Segment], dt: CGFloat, substeps: Int) {
        let split = max(dt / CGFloat(max(substeps, 1)), 1.0 / 240.0)
        for _ in 0..<max(substeps, 1) {
            integrate(bodies: &bodies, dt: split)
            for _ in 0..<StarJarMetrics.solverIterations {
                collideStars(bodies: &bodies)
                collideWalls(bodies: &bodies, walls: walls)
            }
            updateSleep(bodies: &bodies, dt: split)
        }
    }

    static func clampSpeed(_ body: inout Body, maxSpeed: CGFloat) {
        let speed = hypot(body.velocity.dx, body.velocity.dy)
        guard speed > maxSpeed, speed > 0 else { return }
        let scale = maxSpeed / speed
        body.velocity.dx *= scale
        body.velocity.dy *= scale
    }

    private static func integrate(bodies: inout [Body], dt: CGFloat) {
        for index in bodies.indices {
            if bodies[index].kinematic || bodies[index].sleeping { continue }
            bodies[index].velocity.dy += StarJarMetrics.gravity * dt
            let linear = 1 / (1 + bodies[index].linearDamping * dt)
            bodies[index].velocity.dx *= linear
            bodies[index].velocity.dy *= linear
            clampMotion(&bodies[index])
            bodies[index].position.x += bodies[index].velocity.dx * dt
            bodies[index].position.y += bodies[index].velocity.dy * dt
        }
    }

    private static func collideStars(bodies: inout [Body]) {
        guard bodies.count > 1 else { return }
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                if bodies[i].kinematic && bodies[j].kinematic { continue }
                collideBodies(&bodies, i, j)
            }
        }
    }

    private static func collideBodies(_ bodies: inout [Body], _ i: Int, _ j: Int) {
        var a = bodies[i]
        var b = bodies[j]
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distance = hypot(dx, dy)
        let minimum = a.radius + b.radius
        guard distance < minimum else { return }

        let nx: CGFloat
        let ny: CGFloat
        if distance > 0.0001 {
            nx = dx / distance
            ny = dy / distance
        } else {
            nx = 0
            ny = -1
        }
        let penetration = minimum - (distance > 0.0001 ? distance : 0)

        let rax = nx * a.radius
        let ray = ny * a.radius
        let rbx = -nx * b.radius
        let rby = -ny * b.radius
        let inverseAMass = a.kinematic ? 0 : a.inverseMass
        let inverseBMass = b.kinematic ? 0 : b.inverseMass
        let inverseAInertia = a.kinematic ? 0 : a.inverseInertia
        let inverseBInertia = b.kinematic ? 0 : b.inverseInertia
        let raCrossN = rax * ny - ray * nx
        let rbCrossN = rbx * ny - rby * nx
        let inverse = inverseAMass + inverseBMass
            + raCrossN * raCrossN * inverseAInertia
            + rbCrossN * rbCrossN * inverseBInertia
        guard inverse > 0 else { return }

        correctPenetration(
            bodies: &bodies,
            i: i,
            j: j,
            nx: nx,
            ny: ny,
            penetration: penetration,
            inverseAMass: inverseAMass,
            inverseBMass: inverseBMass
        )
        a = bodies[i]
        b = bodies[j]
        if !a.kinematic { bodies[i].sleeping = false }
        if !b.kinematic { bodies[j].sleeping = false }

        let avx = a.velocity.dx - a.angularVelocity * ray
        let avy = a.velocity.dy + a.angularVelocity * rax
        let bvx = b.velocity.dx - b.angularVelocity * rby
        let bvy = b.velocity.dy + b.angularVelocity * rbx
        let rvx = bvx - avx
        let rvy = bvy - avy
        let relative = rvx * nx + rvy * ny
        if relative <= 0 {
            var restitution = min(a.restitution, b.restitution)
            if abs(relative) < StarJarMetrics.gravity * 0.018 {
                restitution = 0
            }
            let impulse = -(1 + restitution) * relative / inverse
            applyImpulse(
                &bodies[i],
                impulseX: -impulse * nx,
                impulseY: -impulse * ny,
                radiusX: rax,
                radiusY: ray,
                inverseMass: inverseAMass,
                inverseInertia: inverseAInertia
            )
            applyImpulse(
                &bodies[j],
                impulseX: impulse * nx,
                impulseY: impulse * ny,
                radiusX: rbx,
                radiusY: rby,
                inverseMass: inverseBMass,
                inverseInertia: inverseBInertia
            )

            a = bodies[i]
            b = bodies[j]
            let avx2 = a.velocity.dx - a.angularVelocity * ray
            let avy2 = a.velocity.dy + a.angularVelocity * rax
            let bvx2 = b.velocity.dx - b.angularVelocity * rby
            let bvy2 = b.velocity.dy + b.angularVelocity * rbx
            let rvx2 = bvx2 - avx2
            let rvy2 = bvy2 - avy2
            var tx = rvx2 - (rvx2 * nx + rvy2 * ny) * nx
            var ty = rvy2 - (rvx2 * nx + rvy2 * ny) * ny
            let tangentLength = hypot(tx, ty)
            if tangentLength > 0.0001 {
                tx /= tangentLength
                ty /= tangentLength
                let raCrossT = rax * ty - ray * tx
                let rbCrossT = rbx * ty - rby * tx
                let tangentInverse = inverseAMass + inverseBMass
                    + raCrossT * raCrossT * inverseAInertia
                    + rbCrossT * rbCrossT * inverseBInertia
                if tangentInverse > 0 {
                    var frictionImpulse = -(rvx2 * tx + rvy2 * ty) / tangentInverse
                    let maxFriction = abs(impulse) * sqrt(a.friction * b.friction)
                    frictionImpulse = min(max(frictionImpulse, -maxFriction), maxFriction)
                    applyImpulse(
                        &bodies[i],
                        impulseX: -frictionImpulse * tx,
                        impulseY: -frictionImpulse * ty,
                        radiusX: rax,
                        radiusY: ray,
                        inverseMass: inverseAMass,
                        inverseInertia: inverseAInertia
                    )
                    applyImpulse(
                        &bodies[j],
                        impulseX: frictionImpulse * tx,
                        impulseY: frictionImpulse * ty,
                        radiusX: rbx,
                        radiusY: rby,
                        inverseMass: inverseBMass,
                        inverseInertia: inverseBInertia
                    )
                }
            }
        }
        clampMotion(&bodies[i])
        clampMotion(&bodies[j])
    }

    private static func collideWalls(bodies: inout [Body], walls: [Segment]) {
        for i in bodies.indices {
            if bodies[i].kinematic { continue }
            for wall in walls {
                collideWall(bodies: &bodies, index: i, segment: wall)
            }
        }
    }

    private static func collideWall(bodies: inout [Body], index: Int, segment: Segment) {
        var body = bodies[index]
        let closest = segment.closestPoint(to: body.position)
        let dx = body.position.x - closest.x
        let dy = body.position.y - closest.y
        let euclideanDistance = hypot(dx, dy)
        guard euclideanDistance < body.radius else { return }

        let inward = segment.inwardNormal
        let nx: CGFloat
        let ny: CGFloat
        if euclideanDistance > 0.0001, dx * inward.dx + dy * inward.dy > 0 {
            nx = dx / euclideanDistance
            ny = dy / euclideanDistance
        } else {
            nx = inward.dx
            ny = inward.dy
        }
        let signedDistance = dx * nx + dy * ny
        let penetration = body.radius - signedDistance
        let correction = max(penetration - StarJarMetrics.penetrationSlop, 0) * StarJarMetrics.correctionPercent
        bodies[index].position.x += nx * correction
        bodies[index].position.y += ny * correction
        bodies[index].sleeping = false
        body = bodies[index]

        let rax = -nx * body.radius
        let ray = -ny * body.radius
        let contactVX = body.velocity.dx - body.angularVelocity * ray
        let contactVY = body.velocity.dy + body.angularVelocity * rax
        let relative = contactVX * nx + contactVY * ny
        if relative < 0 {
            let raCrossN = rax * ny - ray * nx
            let inverse = body.inverseMass + raCrossN * raCrossN * body.inverseInertia
            guard inverse > 0 else { return }
            var restitution = body.restitution
            if abs(relative) < StarJarMetrics.gravity * 0.018 {
                restitution = 0
            }
            let impulse = -(1 + restitution) * relative / inverse
            applyImpulse(
                &bodies[index],
                impulseX: impulse * nx,
                impulseY: impulse * ny,
                radiusX: rax,
                radiusY: ray,
                inverseMass: body.inverseMass,
                inverseInertia: body.inverseInertia
            )

            body = bodies[index]
            let contactVX2 = body.velocity.dx - body.angularVelocity * ray
            let contactVY2 = body.velocity.dy + body.angularVelocity * rax
            var tx = contactVX2 - (contactVX2 * nx + contactVY2 * ny) * nx
            var ty = contactVY2 - (contactVX2 * nx + contactVY2 * ny) * ny
            let tangentLength = hypot(tx, ty)
            if tangentLength > 0.0001 {
                tx /= tangentLength
                ty /= tangentLength
                let raCrossT = rax * ty - ray * tx
                let tangentInverse = body.inverseMass + raCrossT * raCrossT * body.inverseInertia
                if tangentInverse > 0 {
                    var frictionImpulse = -(contactVX2 * tx + contactVY2 * ty) / tangentInverse
                    let maxFriction = abs(impulse) * body.friction
                    frictionImpulse = min(max(frictionImpulse, -maxFriction), maxFriction)
                    applyImpulse(
                        &bodies[index],
                        impulseX: frictionImpulse * tx,
                        impulseY: frictionImpulse * ty,
                        radiusX: rax,
                        radiusY: ray,
                        inverseMass: body.inverseMass,
                        inverseInertia: body.inverseInertia
                    )
                }
            }
        }
        clampMotion(&bodies[index])
    }

    private static func correctPenetration(
        bodies: inout [Body],
        i: Int,
        j: Int,
        nx: CGFloat,
        ny: CGFloat,
        penetration: CGFloat,
        inverseAMass: CGFloat,
        inverseBMass: CGFloat
    ) {
        let massSum = inverseAMass + inverseBMass
        guard massSum > 0 else { return }
        let correction = max(penetration - StarJarMetrics.penetrationSlop, 0) / massSum * StarJarMetrics.correctionPercent
        if inverseAMass > 0 {
            bodies[i].position.x -= nx * correction * inverseAMass
            bodies[i].position.y -= ny * correction * inverseAMass
        }
        if inverseBMass > 0 {
            bodies[j].position.x += nx * correction * inverseBMass
            bodies[j].position.y += ny * correction * inverseBMass
        }
    }

    private static func applyImpulse(
        _ body: inout Body,
        impulseX: CGFloat,
        impulseY: CGFloat,
        radiusX: CGFloat,
        radiusY: CGFloat,
        inverseMass: CGFloat,
        inverseInertia: CGFloat
    ) {
        guard inverseMass > 0 || inverseInertia > 0 else { return }
        body.velocity.dx += impulseX * inverseMass
        body.velocity.dy += impulseY * inverseMass
    }

    private static func updateSleep(bodies: inout [Body], dt: CGFloat) {
        for index in bodies.indices {
            if bodies[index].kinematic {
                bodies[index].sleeping = false
                bodies[index].sleepTimer = 0
                continue
            }
            let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            if speed < StarJarMetrics.sleepLinearSpeed {
                bodies[index].sleepTimer += dt
                if bodies[index].sleepTimer > StarJarMetrics.sleepDelay {
                    bodies[index].sleeping = true
                    bodies[index].velocity = .zero
                    bodies[index].angularVelocity = 0
                }
            } else {
                bodies[index].sleepTimer = 0
                bodies[index].sleeping = false
            }
        }
    }

    private static func clampMotion(_ body: inout Body) {
        clampSpeed(&body, maxSpeed: StarJarMetrics.maxLinearSpeed)
        body.angularVelocity = 0
    }
}

private final class PhysicsDisplayLinkProxy: NSObject {
    var handler: (() -> Void)?

    @objc func fire() {
        handler?()
    }
}
