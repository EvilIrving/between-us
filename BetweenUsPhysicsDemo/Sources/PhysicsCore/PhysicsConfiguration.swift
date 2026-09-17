import Foundation

// 所有素材标定使用「原图左上角为原点」；物理场景只在统一映射入口翻转纵轴。
// 配置为值类型；同一场景装载后固定物理配置，不在逐帧循环中识别物件名字。
struct ArtworkMapping: Codable, Equatable {
    var sourceSize: CGSize
    var sceneSize: CGSize
    var origin: CGPoint // 原图左下角在场景中的位置，允许裁窗产生负值。
    var scale: CGFloat = 1

    func scenePoint(_ pixel: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + pixel.x * scale,
                y: origin.y + (sourceSize.height - pixel.y) * scale)
    }
    func pixelPoint(_ scene: CGPoint) -> CGPoint {
        CGPoint(x: (scene.x - origin.x) / scale,
                y: sourceSize.height - (scene.y - origin.y) / scale)
    }
}

struct TokenGeometry: Codable, Equatable {
    // 形状自己的设计框，与皮肤的图片分辨率解耦。
    var referenceFrame: CGRect
    var displaySize: CGSize
    var pieces: [CollisionPiece]

    func localPoint(_ pixel: CGPoint) -> CGPoint {
        CGPoint(x: ((pixel.x - referenceFrame.minX) / referenceFrame.width - 0.5) * displaySize.width,
                y: (0.5 - (pixel.y - referenceFrame.minY) / referenceFrame.height) * displaySize.height)
    }
    var unitsPerPixel: CGFloat { displaySize.width / referenceFrame.width }
}

enum CollisionPiece: Codable, Equatable {
    case convexPolygon([CGPoint])
    case circle(center: CGPoint, radius: CGFloat)
    // 胶囊只是一种几何原语，不是场景的物种分支；长轴为素材的纵轴。
    case capsule(frame: CGRect)
}

enum PathCommand: Codable, Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(to: CGPoint, control: CGPoint)
    case cubic(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

struct MaskPath: Codable, Equatable {
    var commands: [PathCommand]
    static func polygon(_ points: [CGPoint]) -> MaskPath {
        guard let first = points.first else { return MaskPath(commands: []) }
        return MaskPath(commands: [.move(first)] + points.dropFirst().map { .line($0) } + [.close])
    }
}

struct RenderLayer: Codable, Equatable {
    var asset: String
    var depth: CGFloat
    var opacity: CGFloat = 1
    var mask: MaskPath? = nil
    // 仅控制调试透视和遮挡命中，不改变任何刚体。
    var isForeground: Bool = false
    var blocksHitTesting: Bool = false
}

struct ContainerProfile: Codable, Equatable {
    var id: String
    var mapping: ArtworkMapping
    var innerWall: [CGPoint] // 左口、完整内壁与底部、右口；永不自动闭口。
    var mouth: [CGPoint] // 展示和标定用，不自动生成额外墙或顶盖。
    var wallFriction: CGFloat
    var wallRestitution: CGFloat
    var entityDepth: CGFloat = 10
    var layers: [RenderLayer]
}

struct BodyMaterial: Codable, Equatable {
    var mass: CGFloat
    var friction: CGFloat
    var restitution: CGFloat
    var linearDamping: CGFloat
    var angularDamping: CGFloat
    var allowsRotation: Bool = true
    var preciseCollisions: Bool = true
}

struct EntityProfile: Codable, Equatable {
    var id: String
    var geometry: TokenGeometry
    var material: BodyMaterial
}

struct SkinProfile: Codable, Equatable {
    var id: String
    var entityID: String
    var asset: String
    var sourceSize: CGSize
    // 手动定义的有效图框，不做透明通道自动描边；同型皮肤映射到共同设计框。
    var contentRect: CGRect
}

struct SpawnPolicy: Codable, Equatable {
    var center: CGPoint // 场景坐标；已和容器配对标定。
    var jitterX: CGFloat
    var initialRotation: ClosedRange<CGFloat>
    var initialVelocityX: ClosedRange<CGFloat>
    var initialVelocityY: ClosedRange<CGFloat> = 0...0
    var interval: TimeInterval
    var clearanceHalfSize: CGSize
    var blockedNoticeDelay: TimeInterval = 2
}

struct DragPolicy: Codable, Equatable {
    var springFrequency: CGFloat
    var springDamping: CGFloat
    var maximumStretch: CGFloat
    var maximumHandleSpeed: CGFloat
    var tapDistance: CGFloat = 8
    var tapDuration: TimeInterval = 0.3
}

struct SimulationPolicy: Codable, Equatable {
    var gravity: CGPoint // 表示重力向量；避免核心数据依赖图形框架。
    var capacity: Int
    var initialCount: Int
    var maximumLinearSpeed: CGFloat
    var maximumAngularSpeed: CGFloat
    var recoveryMargin: CGFloat = 160
    var spawn: SpawnPolicy
    var drag: DragPolicy
}

struct VesselRecipe: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var geometryVersion: Int = 1
    var container: ContainerProfile
    var entity: EntityProfile
    var skins: [SkinProfile]
    var policy: SimulationPolicy
    var defaultSkin: SkinProfile { skins[0] }
    func skin(id: String) -> SkinProfile? { skins.first { $0.id == id } }
}
