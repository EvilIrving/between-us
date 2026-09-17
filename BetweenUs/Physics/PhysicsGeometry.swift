import Foundation

enum GeometryMath {
    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        return points.indices.reduce(0) { sum, i in
            let a = points[i], b = points[(i + 1) % points.count]
            return sum + a.x * b.y - b.x * a.y
        } / 2
    }
    static func counterclockwise(_ points: [CGPoint]) -> [CGPoint] {
        signedArea(points) < 0 ? Array(points.reversed()) : points
    }
    static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x)
    }
    static func isConvex(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3, abs(signedArea(points)) > 0.001 else { return false }
        let turns = points.indices.map { cross(points[$0], points[($0+1)%points.count], points[($0+2)%points.count]) }
        return turns.allSatisfy { $0 >= -0.0001 } || turns.allSatisfy { $0 <= 0.0001 }
    }
    static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
            j = i
        }
        return inside
    }
    static func isFinite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }

    // 不重叠的矩形 + 两个凸形半圆帽，避免两个完整圆与矩形重叠带来的质量分布误差。
    // 每片不超过八个顶点；用六段折线近似半圆，仍作为一个复合刚体。
    static func capsulePolygons(frame: CGRect) -> [[CGPoint]] {
        let r = frame.width / 2
        let top = CGPoint(x: frame.midX, y: frame.minY+r)
        let bottom = CGPoint(x: frame.midX, y: frame.maxY-r)
        let steps = 6
        let topCap = (0...steps).map { i -> CGPoint in
            let angle = CGFloat.pi + CGFloat(i) * .pi / CGFloat(steps)
            return CGPoint(x: top.x+r*cos(angle), y: top.y+r*sin(angle))
        }
        let bottomCap = (0...steps).map { i -> CGPoint in
            let angle = CGFloat(i) * .pi / CGFloat(steps)
            return CGPoint(x: bottom.x+r*cos(angle), y: bottom.y+r*sin(angle))
        }
        return [[CGPoint(x: frame.minX,y: top.y), CGPoint(x: frame.maxX,y: top.y),
                 CGPoint(x: frame.maxX,y: bottom.y), CGPoint(x: frame.minX,y: bottom.y)],
                topCap, bottomCap]
    }
    // 实体真实占位半径：碰撞几何自己覆盖的范围，不含贴图透明留白，旋转后也不会超出。
    static func halfExtent(_ geometry: TokenGeometry) -> CGFloat {
        var extent: CGFloat = 0
        func cover(_ points: [CGPoint]) {
            for point in points { extent = max(extent, abs(point.x), abs(point.y)) }
        }
        for piece in geometry.pieces {
            switch piece {
            case .convexPolygon(let points):
                cover(points.map(geometry.localPoint))
            case .circle(let center, let radius):
                let local = geometry.localPoint(center)
                let reach = radius * geometry.unitsPerPixel
                extent = max(extent, abs(local.x) + reach, abs(local.y) + reach)
            case .capsule(let frame):
                cover(capsulePolygons(frame: frame).flatMap { $0 }.map(geometry.localPoint))
            }
        }
        return extent > 0 ? extent : geometry.displaySize.height / 2
    }

    static func expandedPolygons(_ geometry: TokenGeometry) -> [[CGPoint]] {
        geometry.pieces.flatMap { piece in
            switch piece {
            case .convexPolygon(let points): return [points]
            case .capsule(let frame): return capsulePolygons(frame: frame)
            case .circle: return []
            }
        }
    }

    static func validate(_ recipe: VesselRecipe) -> [String] {
        var errors: [String] = []
        let c = recipe.container, g = recipe.entity.geometry, p = recipe.policy
        func require(_ valid: Bool, _ message: String) { if !valid { errors.append(message) } }
        require(c.mapping.sourceSize.width > 0 && c.mapping.sourceSize.height > 0 &&
                c.mapping.sceneSize.width > 0 && c.mapping.sceneSize.height > 0 && c.mapping.scale > 0,
                "画布尺寸或缩放无效")
        require(c.innerWall.count >= 3 && c.innerWall.first != c.innerWall.last, "内壁必须是开放链")
        require(c.innerWall.allSatisfy(isFinite), "内壁含无效坐标")
        require(g.referenceFrame.width > 0 && g.referenceFrame.height > 0 &&
                g.displaySize.width > 0 && g.displaySize.height > 0, "实体尺寸无效")
        require(abs(g.displaySize.width / max(g.referenceFrame.width, 0.001) -
                    g.displaySize.height / max(g.referenceFrame.height, 0.001)) < 0.001,
                "实体只允许等比缩放，避免圆形几何变形")
        require(!g.pieces.isEmpty, "缺少实体几何")
        for piece in g.pieces {
            switch piece {
            case .convexPolygon(let points):
                require(points.count <= 8 && points.allSatisfy(isFinite) && isConvex(points), "刚体分片必须是三至八顶点凸多边形")
            case .circle(let center, let radius):
                require(isFinite(center) && radius.isFinite && radius > 0, "圆形刚体无效")
            case .capsule(let rect):
                require(rect.width > 0 && rect.height > rect.width, "胶囊长轴必须大于直径")
                require(capsulePolygons(frame: rect).allSatisfy(isConvex), "胶囊分片无效")
            }
        }
        require(!recipe.skins.isEmpty, "至少需要一个皮肤")
        require(Set(recipe.skins.map(\.id)).count == recipe.skins.count, "皮肤标识重复")
        for skin in recipe.skins {
            require(skin.entityID == recipe.entity.id, "皮肤和实体类型不匹配")
            require(skin.contentRect.width > 0 && skin.contentRect.height > 0 &&
                    CGRect(origin: .zero, size: skin.sourceSize).contains(skin.contentRect), "皮肤有效图框超出图片")
            require(abs(skin.contentRect.width / max(skin.contentRect.height, 0.001) -
                        g.displaySize.width / max(g.displaySize.height, 0.001)) < 0.005,
                    "皮肤图框与实体宽高比不一致")
        }
        require(recipe.entity.material.mass > 0, "质量必须大于零")
        require(p.capacity > 0 && (0...p.capacity).contains(p.initialCount), "初始数量或容量无效")
        require(p.spawn.interval > 0 && p.spawn.clearanceHalfSize.width > 0 &&
                p.spawn.clearanceHalfSize.height > 0 && p.spawn.jitterX >= 0, "投放策略无效")
        require(p.maximumLinearSpeed > 0 && p.maximumAngularSpeed > 0 && p.recoveryMargin >= 0, "速度或恢复边界无效")
        require(p.contentCeilingPixel > 0 && p.contentCeilingPixel < c.mapping.sourceSize.height, "内容上限超出素材范围")
        require(p.drag.maximumStretch > 0 && p.drag.maximumHandleSpeed > 0, "拖拽限幅无效")
        return errors
    }
}
