import CoreGraphics
import Foundation

/// 两张现役纸的规格。数字来自 `PAPER_DESIGN.md` §8（逐行像素实测，判据见 §3.3）。
/// 纸由用户在创作时选，物件不参与（§10.3）。
enum PaperRegistry {
    /// 情绪收藏夹（绿框点线纸）：top 249 / 砖 373 / bottom 1178，合计 1800。
    static let mood = PaperSheetSpec(
        id: .mood,
        assetName: "PaperMood",
        pixelSize: CGSize(width: 1200, height: 1800),
        top: 249,
        center: 373,
        bottom: 1178,
        contentSideMarginRatio: 0.12,
        prefersDarkCloseIcon: true,
        fontScale: 1.0,
        lineSpacingRatio: 1.75,
        inkColorHex: "#2A2723",
        preferredFontRole: .tenderAffection,
        nameKey: "情绪收藏夹"
    )

    /// 手绘记事本（蓝色线圈本纸）：top 351 / 砖 1209 / bottom 240，合计 1800。
    static let sketch = PaperSheetSpec(
        id: .sketch,
        assetName: "PaperSketch",
        pixelSize: CGSize(width: 1200, height: 1800),
        top: 351,
        center: 1209,
        bottom: 240,
        contentSideMarginRatio: 0.12,
        prefersDarkCloseIcon: true,
        fontScale: 1.0,
        lineSpacingRatio: 1.75,
        inkColorHex: "#1E2B37",
        preferredFontRole: .deepPromise,
        nameKey: "手绘记事本"
    )

    /// 可选的纸，顺序就是选择器里的顺序；第一张是默认纸。
    static let all: [PaperSheetSpec] = [mood, sketch]

    static var defaultPaperID: PaperID { all[0].id }

    private static let specsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// 取规格。已下架的纸（老记录里可能存着 `Paper01` 等）折叠到默认纸。
    static func spec(for id: PaperID) -> PaperSheetSpec {
        specsByID[id] ?? all[0]
    }

    /// 老记录的纸：老实现按下标/哈希从 [paper01, paper03, paper04, paper05, paper06] 派生，
    /// 那几张纸已经下架，所以老记录一律折叠到默认纸；新记录一定带 `storedPaperID`（用户自己选的）。
    static func legacyPaperID(for id: UUID) -> PaperID {
        defaultPaperID
    }
}
