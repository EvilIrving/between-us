import UIKit
@preconcurrency import SpriteKit

enum VesselError: LocalizedError {
    case invalidConfiguration([String])
    case missingImage(String)
    case invalidImage(String)
    case notReady
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let messages): return messages.joined(separator:"；")
        case .missingImage(let name): return "缺少图片：\(name)"
        case .invalidImage(let name): return "图片尺寸、方向或有效图框不符：\(name)"
        case .notReady: return "物理场景尚未装载"
        }
    }
}

@MainActor
final class VesselAssets {
    // 首页三个物件各有一份场景，各自再解一遍同样的位图、上传同样的纹理纯属重复。
    // 图片和纹理本身不可变，按素材名共用一份。
    static let shared = VesselAssets()

    private var images: [String: UIImage] = [:]
    private var tokenTextures: [String: SKTexture] = [:]
    private var layerTextures: [String: SKTexture] = [:]

    func image(named name: String) throws -> UIImage {
        if let image = images[name] { return image }
        let bundled = Bundle.main.url(forResource:name,withExtension:"png")
            .flatMap { UIImage(contentsOfFile:$0.path) }
        guard let image = UIImage(named:name) ?? bundled else { throw VesselError.missingImage(name) }
        images[name] = image
        return image
    }

    func texture(for skin: SkinProfile) throws -> SKTexture {
        if let texture = tokenTextures[skin.id] { return texture }
        let image = try image(named:skin.asset)
        guard image.imageOrientation == .up, let cgImage = image.cgImage,
              cgImage.width == Int(skin.sourceSize.width), cgImage.height == Int(skin.sourceSize.height),
              let cropped = cgImage.cropping(to:skin.contentRect) else { throw VesselError.invalidImage(skin.asset) }
        let texture = SKTexture(cgImage:cropped)
        tokenTextures[skin.id] = texture
        return texture
    }

    // 星星瓶三层用同一张瓶体位图：共用一张纹理，不重复上传。
    func layerTexture(named name: String, image: UIImage) -> SKTexture {
        if let texture = layerTextures[name] { return texture }
        let texture = SKTexture(image:image)
        layerTextures[name] = texture
        return texture
    }
}

// 遮挡前景独立于物理节点；透视开关只改图层透明度，不卸载或停用任何刚体。
@MainActor
final class VesselRenderer {
    private struct Layer {
        let specification: RenderLayer
        let node: SKNode
        let sceneMask: CGPath?
        var alphaMap: AlphaMap?
    }
    private let container: ContainerProfile
    private var layers: [Layer] = []
    private(set) var isXRay = false

    init(container: ContainerProfile) { self.container = container }

    func install(in scene: SKScene, assets: VesselAssets) throws {
        for spec in container.layers {
            let image = try assets.image(named:spec.asset)
            guard let cg = image.cgImage,
                  cg.width == Int(container.mapping.sourceSize.width),
                  cg.height == Int(container.mapping.sourceSize.height) else { throw VesselError.invalidImage(spec.asset) }
            let sprite = SKSpriteNode(texture:assets.layerTexture(named:spec.asset,image:image))
            sprite.anchorPoint = .zero
            sprite.position = container.mapping.origin
            sprite.size = CGSize(width:container.mapping.sourceSize.width*container.mapping.scale,
                                 height:container.mapping.sourceSize.height*container.mapping.scale)
            let sceneMask = spec.mask.map { PhysicsFactory.path($0,map:container.mapping.scenePoint) }
            let node: SKNode
            if let sceneMask {
                let crop = SKCropNode()
                let mask = SKShapeNode(path:sceneMask)
                mask.fillColor = .white
                mask.strokeColor = .clear
                crop.maskNode = mask
                crop.addChild(sprite)
                node = crop
            } else { node = sprite }
            node.zPosition = spec.depth
            node.alpha = spec.opacity * (isXRay ? (spec.isForeground ? 0.12 : 0.35) : 1)
            scene.addChild(node)
            layers.append(Layer(specification:spec,node:node,sceneMask:sceneMask,alphaMap:nil))
            if spec.blocksHitTesting { loadAlphaMap(at:layers.count-1,from:cg) }
        }
    }

    // 命中采样要知道桶壁哪一块是透明留白，代价是把整张 724 位图画进灰度缓冲。
    // 这份工作不该压在第一帧上：放到后台做完再挂回来，未就绪时按遮罩判定，行为与原先一致。
    private func loadAlphaMap(at index: Int, from image: CGImage) {
        Task.detached(priority:.userInitiated) {
            let map = AlphaMap(image)
            await MainActor.run { [weak self] in
                guard let self, self.layers.indices.contains(index) else { return }
                self.layers[index].alphaMap = map
            }
        }
    }

    func setXRay(_ enabled: Bool) {
        guard isXRay != enabled else { return }
        isXRay = enabled
        for layer in layers {
            let multiplier: CGFloat = enabled ? (layer.specification.isForeground ? 0.12 : 0.35) : 1
            layer.node.alpha = layer.specification.opacity * multiplier
        }
    }

    func blocksHit(at point: CGPoint) -> Bool {
        guard !isXRay else { return false }
        let pixel = container.mapping.pixelPoint(point)
        return layers.contains { layer in
            guard layer.specification.blocksHitTesting,
                  layer.specification.opacity >= 0.9,
                  layer.sceneMask?.contains(point) ?? true else { return false }
            // 不把遮罩内的透明留白误当成实体桶壁；物理墙不使用这个采样。
            return (layer.alphaMap?.alpha(at:pixel) ?? 0) > 0.8
        }
    }

    private final class AlphaMap: @unchecked Sendable {
        private let width: Int
        private let height: Int
        private var pixels: [UInt8]
        init?(_ image: CGImage) {
            width = image.width; height = image.height
            pixels = [UInt8](repeating:0,count:width*height)
            let w = width, h = height
            let success = pixels.withUnsafeMutableBytes { raw -> Bool in
                // 显式构造 CGBitmapInfo，避免匹配到已废弃的非可选 space 重载。
                guard let context = CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,
                    bytesPerRow:w,space:nil,
                    bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.alphaOnly.rawValue)) else { return false }
                context.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
                return true
            }
            if !success { return nil }
        }
        func alpha(at point: CGPoint) -> CGFloat {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= 0,point.y >= 0,point.x < CGFloat(width),point.y < CGFloat(height) else { return 0 }
            return CGFloat(pixels[Int(point.y)*width+Int(point.x)]) / 255
        }
    }
}
