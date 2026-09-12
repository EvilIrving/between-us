import SwiftUI
import MotionCore

private struct RecipeChange: Identifiable {
    var field: String
    var before: String
    var after: String
    var consequence: String
    var id: String { field }
}

/// 比较配方语义，不把源码 diff 当成用户要判断的动效变化。
struct RecipeComparisonView: View {
    let baseline: MotionRecipe
    let current: MotionRecipe
    private func numeric(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    private var changes: [RecipeChange] {
        var results: [RecipeChange] = []
        func add(_ title: String,_ before: String,_ after: String,_ consequence: String) {
            if before != after { results.append(.init(field: title,before: before,after: after,consequence: consequence)) }
        }
        add("模型",baseline.family.rawValue.motionTitle,current.family.rawValue.motionTitle,"改变数值随时间变化的建模方式。")
        add("时长",numeric(baseline.duration)+" s",numeric(current.duration)+" s","对定时模型改变整体节奏；弹簧不以这个值决定停稳。")
        add("响应",numeric(baseline.spring.response)+" s",numeric(current.spring.response)+" s","改变弹簧自然频率，数值越小通常越利落。")
        add("阻尼比",numeric(baseline.spring.dampingRatio),numeric(current.spring.dampingRatio),"改变振荡和回弹；与响应共同决定手感。")
        add("开始等待",numeric(baseline.delay)+" s",numeric(current.delay)+" s","改变首次响应前的等待，不改变后续轨迹本身。")
        add("衰减率",numeric(baseline.decay.rate)+" /s",numeric(current.decay.rate)+" /s","改变减速速度和自然停点。")
        add("路径参数化",baseline.pathMode.rawValue,current.pathMode.rawValue,"改变沿路线的速度分布，不改变几何路线。")
        add("重复次数",String(baseline.repeatCount),String(current.repeatCount),"改变重复的播放轮数。")
        add("往返",baseline.autoreverses ? "开启" : "关闭",current.autoreverses ? "开启" : "关闭","改变每轮是否沿原时间轴返回。")
        add("取消行为",baseline.intent.cancellation.rawValue.motionTitle,current.intent.cancellation.rawValue.motionTitle,"改变取消后的产品结果。")
        add("减少动态",baseline.intent.reducedBehavior.rawValue.motionTitle,current.intent.reducedBehavior.rawValue.motionTitle,"改变减少动态时保留的稳定状态。")
        for (label,a,b) in [("起点",baseline.initial,current.initial),("目标",baseline.target,current.target)] {
            for channel in MotionChannel.allCases {
                add(label+" · "+channel.rawValue.motionTitle,numeric(a[channel])+" "+channel.unit,numeric(b[channel])+" "+channel.unit,
                    "改变状态映射；高级关键帧通道的最终值仍以各自关键帧为准。")
            }
        }
        for channel in MotionChannel.allCases {
            add("初速度 · "+channel.rawValue.motionTitle,numeric(baseline.velocity[channel.index]),numeric(current.velocity[channel.index]),
                "影响新播放的出发速度；中途续接使用当时的显示速度。")
        }
        if baseline.curve != current.curve {
            results.append(.init(field: "时间曲线",before: curveName(baseline.curve),after: curveName(current.curve),consequence: "改变区间内的速度分配，不等于修改空间路线。"))
        }
        if baseline.pathDocument != current.pathDocument || baseline.control1 != current.control1 || baseline.control2 != current.control2 {
            results.append(.init(field: "空间路线",before: "\(baseline.editablePath.knots.count) 个节点",after: "\(current.editablePath.knots.count) 个节点",
                                 consequence: "节点或手柄发生变化；同样的总时长下，路程改变也会影响速度。"))
        }
        if baseline.keyframeDocument != current.keyframeDocument || baseline.tracks != current.tracks {
            let old = baseline.keyframeDocument?.lanes.reduce(0) { $0+$1.keyframes.count }
            let new = current.keyframeDocument?.lanes.reduce(0) { $0+$1.keyframes.count }
            results.append(.init(field: "阶段编排",before: old.map { "\($0) 个关键帧" } ?? "\(baseline.tracks.count) 条简单轨道",
                                 after: new.map { "\($0) 个关键帧" } ?? "\(current.tracks.count) 条简单轨道",
                                 consequence: "关键帧值、时间或区间模型变化，可能影响多个阶段的先后关系。"))
        }
        return results
    }
    var body: some View {
        DisclosureGroup("相对对照，改变了什么") {
            let changes = changes
            if changes.isEmpty { Text("尚未修改动效参数。").font(.caption).foregroundStyle(.secondary) }
            ForEach(changes) { change in
                VStack(alignment: .leading,spacing: 6) {
                    Text(change.field).font(.subheadline.weight(.medium))
                    Text("\(change.before) → \(change.after)").font(.caption.monospacedDigit())
                    Text(change.consequence).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity,alignment: .leading).padding(.vertical,8)
            }
            Text("这里解释参数含义，不代替实际效果判断。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func curveName(_ curve: TimingCurve) -> String {
        switch curve {
        case .linear: return "线性"
        case .bezier(let c): return "Bézier (\(numeric(c.x1)), \(numeric(c.y1)), \(numeric(c.x2)), \(numeric(c.y2)))"
        case .smoothstep: return "Smoothstep"
        case .smootherstep: return "Smootherstep"
        case .sineInOut: return "正弦"
        case .steps(let count): return "\(count) 阶"
        }
    }
}
