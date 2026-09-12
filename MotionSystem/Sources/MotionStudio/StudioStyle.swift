import SwiftUI
import UIKit

public enum StudioStyle {
    public static let ink = Color(red: 0.17,green: 0.24,blue: 0.22)
    public static let green = Color(red: 0.19,green: 0.38,blue: 0.30)
    public static let rust = Color(red: 0.66,green: 0.35,blue: 0.21)
    public static let paper = Color(red: 0.96,green: 0.95,blue: 0.92)
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit = ""
    var hint: String? = nil
    var editingChanged: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading,spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))) + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value,in: range,onEditingChanged: editingChanged).accessibilityLabel(title)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical,4)
    }
}

struct StudioPanel<Content: View>: View {
    let title: String
    var content: Content
    init(title: String,@ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(title).font(.headline)
            content
        }.padding(20).frame(maxWidth: .infinity,alignment: .leading)
            .background(.background,in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CodePanel: View {
    let code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack {
                Text("Swift").font(.headline)
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    UIPasteboard.general.string = code; copied = true
                }.buttonStyle(.bordered)
            }
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 12,design: .monospaced))
                    .textSelection(.enabled).padding(16)
            }
            .background(StudioStyle.ink,in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color.white.opacity(0.92))
        }.onChange(of: code) { _,_ in copied = false }
    }
}

extension String {
    var motionTitle: String {
        switch self {
        case "tween": return "时间曲线"
        case "spring": return "弹簧"
        case "hermite": return "Hermite 衔接"
        case "decay": return "惯性衰减"
        case "path": return "空间路径"
        case "timeline": return "多通道时间轴"
        case "preserveVelocity": return "续接值与速度"
        case "preservePosition": return "只续接值"
        case "restart": return "重新开始"
        case "hold": return "停在当前值"
        case "returnToStart": return "返回起点"
        case "finish": return "直接到结果"
        case "tap": return "点按"
        case "dragRelease": return "手势释放"
        case "dataChange": return "数据变化"
        case "appear": return "出现"
        case "x": return "位置 X"
        case "y": return "位置 Y"
        case "scaleX": return "横向缩放"
        case "scaleY": return "纵向缩放"
        case "rotation": return "旋转"
        case "opacity": return "透明度"
        case "blur": return "模糊"
        case "cornerRadius": return "圆角"
        case "width": return "宽度"
        case "height": return "高度"
        default: return self
        }
    }
}

/// 滑杆用于找手感，精确输入用于配准锚点和关键时刻。
struct ExactParameterField: View {
    let title: String
    @Binding var value: Double
    var unit = ""
    var editingChanged: (Bool) -> Void = { _ in }
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline)
            Spacer(minLength: 12)
            TextField("数值",value: $value,format: .number.precision(.fractionLength(0...4)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 150)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }
                .accessibilityLabel(title)
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary).frame(minWidth: 20) }
        }.onChange(of: focused) { _,value in editingChanged(value) }
    }
}
