import UIKit
@preconcurrency import SpriteKit

// 几何编译器只认识原语，不认识星星、胶囊、纸团或产品的容器种类。
@MainActor
enum PhysicsFactory {
    static let wallCategory: UInt32 = 1 << 0
    static let entityCategory: UInt32 = 1 << 1

    static func path(_ points: [CGPoint], closed: Bool) -> CGPath {
        let result = CGMutablePath()
        guard let first = points.first else { return result }
        result.move(to: first)
        points.dropFirst().forEach { result.addLine(to: $0) }
        if closed { result.closeSubpath() }
        return result
    }

    static func path(_ mask: MaskPath, map: (CGPoint) -> CGPoint) -> CGPath {
        let result = CGMutablePath()
        for command in mask.commands {
            switch command {
            case .move(let p): result.move(to: map(p))
            case .line(let p): result.addLine(to: map(p))
            case .quad(let end, let control): result.addQuadCurve(to: map(end), control: map(control))
            case .cubic(let end, let c1, let c2):
                result.addCurve(to: map(end), control1: map(c1), control2: map(c2))
            case .close: result.closeSubpath()
            }
        }
        return result
    }

    static func localPaths(_ geometry: TokenGeometry) -> [CGPath] {
        geometry.pieces.flatMap { piece -> [CGPath] in
            switch piece {
            case .convexPolygon(let points):
                return [path(GeometryMath.counterclockwise(points.map(geometry.localPoint)), closed: true)]
            case .circle(let center, let radius):
                let c = geometry.localPoint(center), r = radius * geometry.unitsPerPixel
                return [CGPath(ellipseIn: CGRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2), transform:nil)]
            case .capsule(let frame):
                return GeometryMath.capsulePolygons(frame: frame).map {
                    path(GeometryMath.counterclockwise($0.map(geometry.localPoint)), closed:true)
                }
            }
        }
    }

    static func body(for entity: EntityProfile) -> SKPhysicsBody {
        let g = entity.geometry
        let pieces: [SKPhysicsBody] = g.pieces.flatMap { piece in
            switch piece {
            case .convexPolygon(let points):
                return [SKPhysicsBody(polygonFrom: path(GeometryMath.counterclockwise(points.map(g.localPoint)),closed:true))]
            case .circle(let center, let radius):
                return [SKPhysicsBody(circleOfRadius:radius*g.unitsPerPixel, center:g.localPoint(center))]
            case .capsule(let frame):
                return GeometryMath.capsulePolygons(frame:frame).map {
                    SKPhysicsBody(polygonFrom:path(GeometryMath.counterclockwise($0.map(g.localPoint)),closed:true))
                }
            }
        }
        let body = pieces.count == 1 ? pieces[0] : SKPhysicsBody(bodies:pieces)
        let m = entity.material
        body.isDynamic = true
        body.affectedByGravity = true
        body.allowsRotation = m.allowsRotation
        body.mass = m.mass
        body.friction = m.friction
        body.restitution = m.restitution
        body.linearDamping = m.linearDamping
        body.angularDamping = m.angularDamping
        body.usesPreciseCollisionDetection = m.preciseCollisions
        body.categoryBitMask = entityCategory
        body.collisionBitMask = wallCategory | entityCategory
        body.contactTestBitMask = 0
        return body
    }

    static func wall(for profile: ContainerProfile) -> SKNode {
        let node = SKNode()
        node.name = "physics.innerWall"
        let wallPath = path(profile.innerWall.map(profile.mapping.scenePoint),closed:false)
        let body = SKPhysicsBody(edgeChainFrom:wallPath)
        body.isDynamic = false
        body.categoryBitMask = wallCategory
        body.collisionBitMask = entityCategory
        body.contactTestBitMask = 0
        body.friction = profile.wallFriction
        body.restitution = profile.wallRestitution
        node.physicsBody = body
        return node
    }
}
