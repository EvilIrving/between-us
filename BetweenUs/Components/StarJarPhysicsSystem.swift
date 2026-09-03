import Combine
import QuartzCore
import SwiftUI

enum StarCollisionShape: Equatable {
    case circle
}

enum StarJarMetrics {
    static let maxStars = 10
    static let visualUnit: CGFloat = 0.148
    static let collisionRadiusUnit: CGFloat = 0.064
    static let mouthCenter = CGPoint(x: 0.50, y: 0.072)
    static let mouthTop: CGFloat = 0.041
    static let mouthInnerHalf: CGFloat = 0.178
    static let releaseLift: CGFloat = 20
    static let layerClearance: CGFloat = 4

    static let gravity: CGFloat = 320
    static let restitution: CGFloat = 0.08
    static let friction: CGFloat = 0.68
    static let linearDamping: CGFloat = 2.35
    static let angularDamping: CGFloat = 2.7
    static let mass: CGFloat = 1.0

    /// Inner glass surface in unit space, clockwise from the left mouth lip
    /// around the floor to the right lip. The mouth itself stays open.
    static let interiorContour: [CGPoint] = [
        CGPoint(x: 0.322, y: 0.078),
        CGPoint(x: 0.318, y: 0.118),
        CGPoint(x: 0.322, y: 0.158),
        CGPoint(x: 0.308, y: 0.198),
        CGPoint(x: 0.258, y: 0.248),
        CGPoint(x: 0.218, y: 0.300),
        CGPoint(x: 0.206, y: 0.360),
        CGPoint(x: 0.204, y: 0.520),
        CGPoint(x: 0.206, y: 0.700),
        CGPoint(x: 0.214, y: 0.810),
        CGPoint(x: 0.232, y: 0.872),
        CGPoint(x: 0.270, y: 0.918),
        CGPoint(x: 0.340, y: 0.942),
        CGPoint(x: 0.420, y: 0.952),
        CGPoint(x: 0.500, y: 0.956),
        CGPoint(x: 0.580, y: 0.952),
        CGPoint(x: 0.660, y: 0.942),
        CGPoint(x: 0.730, y: 0.918),
        CGPoint(x: 0.768, y: 0.872),
        CGPoint(x: 0.786, y: 0.810),
        CGPoint(x: 0.794, y: 0.700),
        CGPoint(x: 0.796, y: 0.520),
        CGPoint(x: 0.794, y: 0.360),
        CGPoint(x: 0.782, y: 0.300),
        CGPoint(x: 0.742, y: 0.248),
        CGPoint(x: 0.692, y: 0.198),
        CGPoint(x: 0.678, y: 0.158),
        CGPoint(x: 0.682, y: 0.118),
        CGPoint(x: 0.678, y: 0.078)
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
    private static let placementVersion = 2

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
            bodies[index].angularVelocity += sign * 0.35
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
        let radius = collisionRadius
        let inertia = 0.42 * StarJarMetrics.mass * radius * radius
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
            visualSize: visualSize,
            collisionShape: .circle,
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
        let split = max(dt / CGFloat(max(substeps, 1)), 1.0 / 240.0)
        for _ in 0..<max(substeps, 1) {
            integrate(dt: split)
            solveStars()
            solveWalls()
            updateSleep(dt: split)
        }
    }

    private func integrate(dt: CGFloat) {
        for index in bodies.indices {
            if bodies[index].kinematic || bodies[index].sleeping { continue }
            bodies[index].velocity.dy += StarJarMetrics.gravity * dt
            let linear = max(0, 1 - bodies[index].linearDamping * dt)
            bodies[index].velocity.dx *= linear
            bodies[index].velocity.dy *= linear
            bodies[index].angularVelocity *= max(0, 1 - bodies[index].angularDamping * dt)
            clampSpeed(&bodies[index], maxSpeed: 420)
            bodies[index].position.x += bodies[index].velocity.dx * dt
            bodies[index].position.y += bodies[index].velocity.dy * dt
            bodies[index].rotation += bodies[index].angularVelocity * dt
        }
    }

    private func solveStars() {
        guard bodies.count > 1 else { return }
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                if bodies[i].kinematic && bodies[j].kinematic { continue }
                collideBodies(i, j)
            }
        }
    }

    private func collideBodies(_ i: Int, _ j: Int) {
        let a = bodies[i]
        let b = bodies[j]
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distance = max(0.0001, hypot(dx, dy))
        let minimum = a.radius + b.radius
        guard distance < minimum else { return }

        let nx = dx / distance
        let ny = dy / distance
        let penetration = minimum - distance
        let inverse = (a.kinematic ? 0 : a.inverseMass) + (b.kinematic ? 0 : b.inverseMass)
        guard inverse > 0 else { return }
        let correction = penetration / inverse * 0.86
        if !a.kinematic {
            bodies[i].position.x -= nx * correction * a.inverseMass
            bodies[i].position.y -= ny * correction * a.inverseMass
            bodies[i].sleeping = false
        }
        if !b.kinematic {
            bodies[j].position.x += nx * correction * b.inverseMass
            bodies[j].position.y += ny * correction * b.inverseMass
            bodies[j].sleeping = false
        }

        let rvx = b.velocity.dx - a.velocity.dx
        let rvy = b.velocity.dy - a.velocity.dy
        let relative = rvx * nx + rvy * ny
        if relative > 0 { return }

        let restitution = min(a.restitution, b.restitution)
        let impulse = -(1 + restitution) * relative / inverse
        let ix = impulse * nx
        let iy = impulse * ny
        if !a.kinematic {
            bodies[i].velocity.dx -= ix * a.inverseMass
            bodies[i].velocity.dy -= iy * a.inverseMass
        }
        if !b.kinematic {
            bodies[j].velocity.dx += ix * b.inverseMass
            bodies[j].velocity.dy += iy * b.inverseMass
        }

        let tx = rvx - relative * nx
        let ty = rvy - relative * ny
        let tangentLength = hypot(tx, ty)
        guard tangentLength > 0.0001 else { return }
        let tnx = tx / tangentLength
        let tny = ty / tangentLength
        let friction = sqrt(a.friction * b.friction)
        var frictionImpulse = -(rvx * tnx + rvy * tny) / inverse
        let maxFriction = abs(impulse) * friction
        frictionImpulse = min(max(frictionImpulse, -maxFriction), maxFriction)
        if !a.kinematic {
            bodies[i].velocity.dx -= tnx * frictionImpulse * a.inverseMass
            bodies[i].velocity.dy -= tny * frictionImpulse * a.inverseMass
            bodies[i].angularVelocity -= frictionImpulse * a.radius * a.inverseInertia * 0.35
        }
        if !b.kinematic {
            bodies[j].velocity.dx += tnx * frictionImpulse * b.inverseMass
            bodies[j].velocity.dy += tny * frictionImpulse * b.inverseMass
            bodies[j].angularVelocity += frictionImpulse * b.radius * b.inverseInertia * 0.35
        }
    }

    private func solveWalls() {
        for i in bodies.indices {
            if bodies[i].kinematic { continue }
            for wall in walls {
                collideWall(index: i, segment: wall)
            }
        }
    }

    private func collideWall(index: Int, segment: Segment) {
        let body = bodies[index]
        let closest = segment.closestPoint(to: body.position)
        let dx = body.position.x - closest.x
        let dy = body.position.y - closest.y
        let inward = segment.inwardNormal
        let signedDistance = dx * inward.dx + dy * inward.dy
        let euclideanDistance = hypot(dx, dy)
        guard euclideanDistance < body.radius else { return }
        let penetration = body.radius - signedDistance
        bodies[index].position.x += inward.dx * penetration
        bodies[index].position.y += inward.dy * penetration
        bodies[index].sleeping = false

        let relative = bodies[index].velocity.dx * inward.dx + bodies[index].velocity.dy * inward.dy
        if relative < 0 {
            let impulse = -(1 + body.restitution) * relative
            bodies[index].velocity.dx += impulse * inward.dx
            bodies[index].velocity.dy += impulse * inward.dy
            let tx = -inward.dy
            let ty = inward.dx
            let tangentSpeed = bodies[index].velocity.dx * tx + bodies[index].velocity.dy * ty
            let frictionImpulse = tangentSpeed * body.friction * 0.55
            bodies[index].velocity.dx -= tx * frictionImpulse
            bodies[index].velocity.dy -= ty * frictionImpulse
            bodies[index].angularVelocity -= frictionImpulse * body.radius * body.inverseInertia * 0.28
        }
    }

    private func updateSleep(dt: CGFloat) {
        for index in bodies.indices {
            if bodies[index].kinematic {
                bodies[index].sleeping = false
                bodies[index].sleepTimer = 0
                continue
            }
            let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            let spin = abs(bodies[index].angularVelocity)
            if speed < 7, spin < 0.38 {
                bodies[index].sleepTimer += dt
                if bodies[index].sleepTimer > 0.32 {
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

    private func clampSpeed(_ body: inout Body, maxSpeed: CGFloat) {
        let speed = hypot(body.velocity.dx, body.velocity.dy)
        guard speed > maxSpeed, speed > 0 else { return }
        let scale = maxSpeed / speed
        body.velocity.dx *= scale
        body.velocity.dy *= scale
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
        let radius = StarJarMetrics.collisionRadiusUnit * side
        let inertia = 0.42 * StarJarMetrics.mass * radius * radius
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
            visualSize: StarJarMetrics.visualUnit * side,
            collisionShape: .circle,
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
            integrate(dt: dt)
            collideStars()
            collideWalls()
            sleep(dt: dt)
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

    private mutating func integrate(dt: CGFloat) {
        for index in bodies.indices {
            if bodies[index].sleeping { continue }
            bodies[index].velocity.dy += StarJarMetrics.gravity * dt
            let linear = max(0, 1 - bodies[index].linearDamping * dt)
            bodies[index].velocity.dx *= linear
            bodies[index].velocity.dy *= linear
            bodies[index].angularVelocity *= max(0, 1 - bodies[index].angularDamping * dt)
            bodies[index].position.x += bodies[index].velocity.dx * dt
            bodies[index].position.y += bodies[index].velocity.dy * dt
            bodies[index].rotation += bodies[index].angularVelocity * dt
        }
    }

    private mutating func collideStars() {
        guard bodies.count > 1 else { return }
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i]
                let b = bodies[j]
                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distance = max(0.0001, hypot(dx, dy))
                let minimum = a.radius + b.radius
                guard distance < minimum else { continue }
                let nx = dx / distance
                let ny = dy / distance
                let correction = (minimum - distance) / (a.inverseMass + b.inverseMass) * 0.86
                bodies[i].position.x -= nx * correction * a.inverseMass
                bodies[i].position.y -= ny * correction * a.inverseMass
                bodies[j].position.x += nx * correction * b.inverseMass
                bodies[j].position.y += ny * correction * b.inverseMass
                bodies[i].sleeping = false
                bodies[j].sleeping = false
                let rvx = b.velocity.dx - a.velocity.dx
                let rvy = b.velocity.dy - a.velocity.dy
                let relative = rvx * nx + rvy * ny
                if relative >= 0 { continue }
                let impulse = -(1 + min(a.restitution, b.restitution)) * relative / (a.inverseMass + b.inverseMass)
                bodies[i].velocity.dx -= impulse * nx * a.inverseMass
                bodies[i].velocity.dy -= impulse * ny * a.inverseMass
                bodies[j].velocity.dx += impulse * nx * b.inverseMass
                bodies[j].velocity.dy += impulse * ny * b.inverseMass
            }
        }
    }

    private mutating func collideWalls() {
        for i in bodies.indices {
            for wall in walls {
                let closest = wall.closestPoint(to: bodies[i].position)
                let dx = bodies[i].position.x - closest.x
                let dy = bodies[i].position.y - closest.y
                let inward = wall.inwardNormal
                let signedDistance = dx * inward.dx + dy * inward.dy
                let euclideanDistance = hypot(dx, dy)
                guard euclideanDistance < bodies[i].radius else { continue }
                let penetration = bodies[i].radius - signedDistance
                bodies[i].position.x += inward.dx * penetration
                bodies[i].position.y += inward.dy * penetration
                bodies[i].sleeping = false
                let relative = bodies[i].velocity.dx * inward.dx + bodies[i].velocity.dy * inward.dy
                if relative < 0 {
                    let impulse = -(1 + bodies[i].restitution) * relative
                    bodies[i].velocity.dx += impulse * inward.dx
                    bodies[i].velocity.dy += impulse * inward.dy
                }
            }
        }
    }

    private mutating func sleep(dt: CGFloat) {
        for index in bodies.indices {
            let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            if speed < 7, abs(bodies[index].angularVelocity) < 0.38 {
                bodies[index].sleepTimer += dt
                if bodies[index].sleepTimer > 0.32 {
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
}

private final class PhysicsDisplayLinkProxy: NSObject {
    var handler: (() -> Void)?

    @objc func fire() {
        handler?()
    }
}
