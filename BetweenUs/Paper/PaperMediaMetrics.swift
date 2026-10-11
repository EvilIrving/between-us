import CoreGraphics
import Foundation

/// 纸面上媒体的确定性几何（§5）。排版算纸高与渲染必须用同一组数字，所以两边共用一个度量。
@MainActor
struct PaperMediaMetrics {
    /// 内容宽（点）= 纸宽 × (1 − 2 × contentSideMarginRatio)。
    let contentWidth: CGFloat
    /// Dynamic Type 系数（[1.0, 1.35]），只影响行高类元素。
    let dynamicTypeScale: CGFloat

    static let gap: CGFloat = 7
    static let blockSpacing: CGFloat = 10
    static let maximumSingleVisualHeight: CGFloat = 430
    static let maximumVisualCount = 9
    /// 录音行的自然高：52 圆钮 / 36 波形 + 13 上下内边距。
    static let audioRowBaseHeight: CGFloat = 80
    /// 拿不到像素尺寸时的预留比例（宽 : 高 = 3 : 4）。
    static let reservedAspectRatio: CGFloat = 3.0 / 4.0

    var audioRowHeight: CGFloat { Self.audioRowBaseHeight * dynamicTypeScale }

    private var mediaStore: MediaFileStore { MediaFileStore() }

    /// 单张图/视频按原比例缩到内容宽，再夹在 430pt 内。
    func singleVisualHeight(for attachment: AttachmentMetadata) -> CGFloat {
        guard let size = AttachmentImageStore.shared.pixelSize(for: mediaStore.url(for: attachment)),
              size.width > 0, size.height > 0 else {
            return contentWidth / Self.reservedAspectRatio
        }
        return min(contentWidth * (size.height / size.width), Self.maximumSingleVisualHeight)
    }

    func visualGridCellSize(count: Int) -> CGFloat {
        let columns = count == 2 ? 2 : 3
        return (contentWidth - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)
    }

    func visualHeight(for attachments: [AttachmentMetadata]) -> CGFloat {
        let visual = attachments.filter { $0.kind == .image || $0.kind == .video }
            .prefix(Self.maximumVisualCount)
        guard let first = visual.first else { return 0 }
        if visual.count == 1 { return singleVisualHeight(for: first) }
        let cell = visualGridCellSize(count: visual.count)
        let rows = Int(ceil(Double(visual.count) / Double(visual.count == 2 ? 2 : 3)))
        return CGFloat(rows) * cell + CGFloat(rows - 1) * Self.gap
    }

    /// 媒体块总高：录音行在前，图片/视频网格在后（§4.1、§5）。
    func height(for attachments: [AttachmentMetadata]) -> CGFloat {
        var blocks: [CGFloat] = []
        let audio = attachments.filter { $0.kind == .audio }
        if !audio.isEmpty {
            blocks.append(
                CGFloat(audio.count) * audioRowHeight + CGFloat(audio.count - 1) * Self.blockSpacing
            )
        }
        let visual = visualHeight(for: attachments)
        if visual > 0 { blocks.append(visual) }
        guard !blocks.isEmpty else { return 0 }
        return blocks.reduce(0, +) + CGFloat(blocks.count - 1) * Self.blockSpacing
    }
}
