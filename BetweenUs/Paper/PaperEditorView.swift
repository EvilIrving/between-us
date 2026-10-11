import SwiftUI
import UIKit

/// 创作态的纸：与查看态同一套纸面参数（长高方式 + 中段砖）、同一套排版属性（§3.4、§12 第 2 步）。
/// 纸 1:1——同样的纸宽、同样的字号与行距、同样的长高方式，所以写的时候看到的就是对方打开时的纸。
struct PaperEditorView: View {
    let kind: ContainerKind
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    /// 纸宽（点）。调用方按 `PaperSheetView.widthRatio × 屏宽` 给，与查看态同一口径。
    let paperWidth: CGFloat
    /// 光标纵向位置（纸内容坐标，点），用于让外层滚动跟随光标。
    var onCaretOffset: (CGFloat) -> Void = { _ in }

    var body: some View {
        // 纸由用户在创作态选（PAPER_DESIGN §10.3）；选择器还没落地，先用默认纸。
        let spec = PaperRegistry.spec(for: PaperRegistry.defaultPaperID)
        let scale = paperWidth / spec.pixelSize.width
        let sideMargin = paperWidth * spec.contentSideMarginRatio
        let contentWidth = paperWidth - sideMargin * 2
        let pointSize = spec.basePointSize
            * PaperFontResolver.dynamicTypeScale(baseSize: spec.basePointSize)
        let textHeight = PaperTextLayoutBuilder.contentHeight(
            text: text,
            spec: spec,
            pointSize: pointSize,
            width: contentWidth
        )
        let contentHeight = max(spec.center * scale, textHeight, spec.basePointSize * 2)
        let paperHeight = spec.paperHeight(forContent: contentHeight / scale) * scale

        ZStack(alignment: .topLeading) {
            PaperBackground(
                spec: spec,
                paperWidth: paperWidth,
                bands: spec.bandCount(forContent: contentHeight / scale)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)

            PaperEditableText(
                text: $text,
                isFocused: isFocused,
                spec: spec,
                pointSize: pointSize,
                onCaretOffset: onCaretOffset
            )
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .offset(x: sideMargin, y: spec.top * scale)

            if text.isEmpty {
                Text(kind.placeholder)
                    .font(Font(PaperFontResolver.font(for: spec.preferredFontRole, size: pointSize)))
                    .foregroundStyle(Color(spec.inkColor).opacity(0.34))
                    .multilineTextAlignment(.leading)
                    .frame(width: contentWidth, alignment: .topLeading)
                    .offset(x: sideMargin, y: spec.top * scale)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: paperWidth, height: paperHeight)
    }
}

/// 编辑宿主：`UITextView` 显式切到 TextKit 1，与查看态同一套属性、同一个宽度（§3.4）。
/// 正文不给选择菜单（copy / cut / selectAll 拦掉，paste 保留，§4.3）。
struct PaperEditableText: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let spec: PaperSheetSpec
    let pointSize: CGFloat
    var onCaretOffset: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCaretOffset: onCaretOffset)
    }

    func makeUIView(context: Context) -> PaperInputTextView {
        let view = PaperInputTextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.tintColor = spec.inkColor
        view.delegate = context.coordinator
        view.attributedText = PaperTextLayoutBuilder.attributedText(
            text,
            spec: spec,
            pointSize: pointSize
        )
        view.accessibilityLabel = T("正文")
        context.coordinator.appliedStyle = StyleKey(spec: spec.id, pointSize: pointSize)
        return view
    }

    func updateUIView(_ view: PaperInputTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCaretOffset = onCaretOffset

        // 外部改动（草稿恢复）才整段替换；不要每次求值都重置，否则光标与输入法会断。
        if view.text != text {
            view.attributedText = PaperTextLayoutBuilder.attributedText(
                text,
                spec: spec,
                pointSize: pointSize
            )
            coordinator.appliedStyle = StyleKey(spec: spec.id, pointSize: pointSize)
        } else {
            // 字号 / 字体角色变了才重刷属性；拼音等组合输入期间不动。
            let key = StyleKey(spec: spec.id, pointSize: pointSize)
            if coordinator.appliedStyle != key, view.markedTextRange == nil {
                let selected = view.selectedRange
                view.attributedText = PaperTextLayoutBuilder.attributedText(
                    view.text ?? "",
                    spec: spec,
                    pointSize: pointSize
                )
                view.selectedRange = selected
                coordinator.appliedStyle = key
            }
        }

        if isFocused.wrappedValue, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused.wrappedValue, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    struct StyleKey: Equatable {
        let spec: PaperID
        let pointSize: CGFloat
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        var onCaretOffset: (CGFloat) -> Void
        var appliedStyle: StyleKey?

        init(text: Binding<String>, onCaretOffset: @escaping (CGFloat) -> Void) {
            self.text = text
            self.onCaretOffset = onCaretOffset
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
            reportCaret(in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            reportCaret(in: textView)
        }

        private func reportCaret(in textView: UITextView) {
            let manager = textView.layoutManager
            let glyphRange = manager.glyphRange(
                forCharacterRange: textView.selectedRange,
                actualCharacterRange: nil
            )
            let rect = manager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            onCaretOffset(rect.maxY)
        }
    }
}

/// 正文不给复制/剪切/全选，粘贴保留（§4.3）。
final class PaperInputTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(selectAll(_:)):
            return false
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }
}
