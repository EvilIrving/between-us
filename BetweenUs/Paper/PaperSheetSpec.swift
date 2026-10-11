import CoreGraphics
import UIKit

/// 纸张全局唯一身份。rawValue 就是运行时资材（imageset）名。
/// 新增纸直接追加 case；旧内容的纸靠 `PaperRegistry.spec(for:)` 折叠到现役纸，不靠下标或哈希。
enum PaperID: String, Codable, CaseIterable, Sendable {
    /// 现役两张（纸由用户创作时选，物件不参与，§10.3）。
    case mood = "PaperMood"        // 情绪收藏夹（绿框点线纸）
    case sketch = "PaperSketch"    // 手绘记事本（蓝色线圈本纸）

    /// 已下架的三张：只为读老记录保留，资材已不再进包（不能出现在任何可选列表里）。
    case paper01 = "Paper01"
    case paper04 = "Paper04"
    case paper06 = "Paper06"
}

/// 字体按「情绪与容器角色」引用，不写死字体名。
enum FontRole: String, Codable, CaseIterable, Sendable {
    case tenderAffection   // 撒娇黏人
    case deepPromise       // 庄重长文
    case grievanceVent     // 委屈脆弱
}

/// 按角色取字体。§11 的字族进包前，统一退回系统字体的对应字重，排版口径不变。
enum PaperFontResolver {
    /// 每个角色一个 familyName（§11 白名单：霞鹜文楷、悠哉、小赖…）。
    private static let families: [FontRole: String] = [:]

    private static let weights: [FontRole: UIFont.Weight] = [
        .tenderAffection: .medium,
        .deepPromise: .regular,
        .grievanceVent: .medium
    ]

    /// 字号按 Dynamic Type 缩放，夹在 [1.0, 1.35]（§4.2）。
    static let dynamicTypeRange: ClosedRange<CGFloat> = 1.0...1.35

    static func dynamicTypeScale(baseSize: CGFloat) -> CGFloat {
        let scaled = UIFontMetrics.default.scaledValue(for: baseSize)
        guard baseSize > 0 else { return 1 }
        return min(max(scaled / baseSize, dynamicTypeRange.lowerBound), dynamicTypeRange.upperBound)
    }

    static func font(for role: FontRole, size: CGFloat) -> UIFont {
        if let family = families[role] {
            return UIFont(
                descriptor: UIFontDescriptor(fontAttributes: [.family: family]).withSize(size),
                size: size
            )
        }
        return .systemFont(ofSize: size, weight: weights[role] ?? .regular)
    }
}

/// 纸的规格。纸高不是常量，是排版的返回值（§3.2）。
struct PaperSheetSpec: Identifiable, Sendable {
    let id: PaperID
    let assetName: String

    /// 自然态尺寸（宽 × 三段高之和），运行时切图与它同尺寸；比例的唯一来源。
    let pixelSize: CGSize
    let top: CGFloat
    let center: CGFloat
    let bottom: CGFloat

    var naturalHeight: CGFloat { top + center + bottom }
    var aspectRatio: CGFloat { pixelSize.width / naturalHeight }

    /// 纸高 = 上段 + 中段区 + 下段。中段区从**一块砖**（`center`）起，按整块砖向上取整——
    /// 平铺时不会把刻痕/环切一半，纸长高就是一档一档的。出入参单位都是设计稿像素。
    func paperHeight(forContent contentHeight: CGFloat) -> CGFloat {
        top + middleHeight(forContent: contentHeight) + bottom
    }

    /// 中段区域高（设计稿像素）：`max(一块砖, 内容高)` 向上取整到整块砖。
    func middleHeight(forContent contentHeight: CGFloat) -> CGFloat {
        CGFloat(bandCount(forContent: contentHeight)) * center
    }

    /// 中段铺几块砖（≥ 1）。
    func bandCount(forContent contentHeight: CGFloat) -> Int {
        max(1, Int((max(0, contentHeight) / max(1, center)).rounded(.up)))
    }

    /// 左右内边距占纸宽的比例（0.12 → 内容宽 244pt，§3.2）。
    let contentSideMarginRatio: CGFloat
    let prefersDarkCloseIcon: Bool

    /// 相对基准字号 16pt 的系数，纸可微调 15–17pt（§4.2）。
    let fontScale: CGFloat
    /// 行距（基线到基线）= 字号 × 系数，内部换算成 NSParagraphStyle.lineSpacing。
    let lineSpacingRatio: CGFloat
    let inkColorHex: String
    let preferredFontRole: FontRole

    /// 纸在选择器里的展示名（String Catalog 的 key，四语言，见 §9.2）。
    let nameKey: String

    static let baseFontSize: CGFloat = 16

    var basePointSize: CGFloat { Self.baseFontSize * fontScale }

    var inkColor: UIColor { UIColor(hexString: inkColorHex) ?? .black }
}

extension UIColor {
    /// `#RRGGBB` / `#RRGGBBAA`；解析失败返回 nil，调用方给兜底色。
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
