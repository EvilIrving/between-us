import Foundation

public enum PathHandleMode: String, Codable, CaseIterable, Sendable {
    case independent, aligned, mirrored
}
public enum PathHandle: String, Codable, Sendable { case anchor, incoming, outgoing }

/// 手柄采用舞台绝对坐标。移动锚点时，两个手柄一起平移。
public struct PathKnot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var point: MotionPoint
    public var incoming: MotionPoint
    public var outgoing: MotionPoint
    public var mode: PathHandleMode
    public init(id: UUID = UUID(),point: MotionPoint,incoming: MotionPoint,outgoing: MotionPoint,
                mode: PathHandleMode = .independent) {
        self.id = id; self.point = point; self.incoming = incoming; self.outgoing = outgoing; self.mode = mode
    }
    public mutating func move(_ handle: PathHandle,to location: MotionPoint) {
        switch handle {
        case .anchor:
            let delta = location-point
            point = location; incoming = incoming+delta; outgoing = outgoing+delta
        case .incoming:
            let oppositeLength = (outgoing-point).length
            incoming = location
            if mode == .mirrored { outgoing = point+(point-incoming) }
            if mode == .aligned { outgoing = point+(point-incoming).normalized*oppositeLength }
        case .outgoing:
            let oppositeLength = (incoming-point).length
            outgoing = location
            if mode == .mirrored { incoming = point+(point-outgoing) }
            if mode == .aligned { incoming = point+(point-outgoing).normalized*oppositeLength }
        }
    }
    public mutating func setMode(_ value: PathHandleMode) {
        mode = value
        if mode != .independent { move(.outgoing,to: outgoing) }
    }
}

/// 可编辑路径。序列化结构与求值器分开，拖动时不维护旧长度缓存。
public struct PathDocument: Codable, Equatable, Sendable {
    public var knots: [PathKnot]
    public init(knots: [PathKnot]) {
        precondition(knots.count >= 2,"A route needs at least two knots")
        self.knots = knots
    }
    public init(segment: BezierSegment) {
        knots = [
            PathKnot(point: segment.start,incoming: segment.start,outgoing: segment.control1),
            PathKnot(point: segment.end,incoming: segment.control2,outgoing: segment.end)
        ]
    }
    public var segments: [BezierSegment] {
        guard knots.count >= 2 else { return [] }
        return zip(knots,knots.dropFirst()).map { a,b in
            BezierSegment(start: a.point,control1: a.outgoing,control2: b.incoming,end: b.point)
        }
    }
    public var path: MotionPath { MotionPath(segments: segments) }
    public func index(of id: UUID) -> Int? { knots.firstIndex { $0.id == id } }
    public mutating func move(id: UUID,handle: PathHandle,to point: MotionPoint) {
        guard let index = index(of: id) else { return }
        knots[index].move(handle,to: point)
    }
    public mutating func setMode(id: UUID,mode: PathHandleMode) {
        guard let index = index(of: id) else { return }
        knots[index].setMode(mode)
    }
    public mutating func replaceEndpoints(start: MotionPoint,end: MotionPoint) {
        guard knots.count >= 2 else { return }
        knots[0].move(.anchor,to: start)
        knots[knots.count-1].move(.anchor,to: end)
    }
    /// De Casteljau 精确拆分。拆段前后的曲线路线相同；两段参数时标不同。
    @discardableResult
    public mutating func split(segment index: Int,at fraction: Double = 0.5) -> UUID? {
        guard segments.indices.contains(index) else { return nil }
        let s = segments[index], t = motionClamp(fraction,0.01...0.99)
        let a = s.start+(s.control1-s.start)*t
        let b = s.control1+(s.control2-s.control1)*t
        let c = s.control2+(s.end-s.control2)*t
        let d = a+(b-a)*t, e = b+(c-b)*t, f = d+(e-d)*t
        knots[index].outgoing = a
        knots[index+1].incoming = c
        // 邻居未参与的手柄不应被“镜像模式”联动改变；当前操作保留原曲线。
        if knots[index].mode == .mirrored { knots[index].mode = .aligned }
        if knots[index+1].mode == .mirrored { knots[index+1].mode = .aligned }
        let inserted = PathKnot(point: f,incoming: d,outgoing: e,mode: .aligned)
        knots.insert(inserted,at: index+1)
        return inserted.id
    }
    /// 删除内节点会把邻居连接成一段，不能保证原路线；端点不可删除。
    public mutating func removeInterior(id: UUID) {
        guard let index = index(of: id),index > 0,index < knots.count-1 else { return }
        knots.remove(at: index)
    }
    public func tangentAgreement(at index: Int) -> Double? {
        guard index > 0,index < knots.count-1 else { return nil }
        let incoming = knots[index].point-knots[index].incoming
        let outgoing = knots[index].outgoing-knots[index].point
        guard incoming.length > 1e-8,outgoing.length > 1e-8 else { return nil }
        let a = incoming.normalized,b = outgoing.normalized
        return acos(motionClamp(a.x*b.x+a.y*b.y,-1...1))*180 / .pi
    }
}
