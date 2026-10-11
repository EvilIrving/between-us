import SwiftUI
import UIKit

/// 排版真相源：`NSTextStorage` + `NSLayoutManager` + **一个不限高的 `NSTextContainer`**（§3.4）。
/// 容器链（原生分页）不需要了——纸不会拒绝你写；纸高就是这里算出来的内容高。
struct PaperTextLayout {
    let storage: NSTextStorage
    let manager: NSLayoutManager
    let container: NSTextContainer
    /// 排版宽度（点），与容器几何一致；绘制时也用同一个值，避免两处宽度取整不同。
    /// 排版宽度（点）与容器几何一致；绘制时也用同一个值，避免两处宽度取整不同。
    var contentHeight: CGFloat {
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    var glyphRange: NSRange { manager.glyphRange(for: container) }
}

enum PaperTextLayoutBuilder {
    /// 正文属性：每张纸一套（字体角色、墨色、行距），断行只有一种结果。
    static func attributedText(
        _ text: String,
        spec: PaperSheetSpec,
        pointSize: CGFloat
    ) -> NSAttributedString {
        let font = PaperFontResolver.font(for: spec.preferredFontRole, size: pointSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .natural
        paragraph.lineSpacing = max(0, pointSize * spec.lineSpacingRatio - font.lineHeight)
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: spec.inkColor,
                .kern: 0,
                .paragraphStyle: paragraph
            ]
        )
    }

    static func make(
        text: String,
        spec: PaperSheetSpec,
        pointSize: CGFloat,
        width: CGFloat
    ) -> PaperTextLayout {
        let storage = NSTextStorage(attributedString: attributedText(text, spec: spec, pointSize: pointSize))
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        return PaperTextLayout(
            storage: storage,
            manager: manager,
            container: container
        )
    }

    static func contentHeight(
        text: String,
        spec: PaperSheetSpec,
        pointSize: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        return make(text: text, spec: spec, pointSize: pointSize, width: width).contentHeight
    }
}

/// 用同一个 `NSLayoutManager` 把正文画到纸面（§4.3：正文由我们绘制，天然不可选）。
struct PaperTextCanvas: UIViewRepresentable {
    let layout: PaperTextLayout

    func makeUIView(context: Context) -> PaperTextCanvasView {
        PaperTextCanvasView()
    }

    func updateUIView(_ view: PaperTextCanvasView, context: Context) {
        view.layout = layout
    }
}

final class PaperTextCanvasView: UIView {
    var layout: PaperTextLayout? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let layout, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        layout.manager.drawGlyphs(forGlyphRange: layout.glyphRange, at: .zero)
        context.restoreGState()
    }
}
