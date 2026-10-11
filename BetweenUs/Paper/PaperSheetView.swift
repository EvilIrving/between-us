import SwiftUI

/// 纸条纸面：一条内容永远用同一张纸（写入时冻结），纸随内容长（§3.2）。
/// 一次排版、一次绘制：纸高由排版结果给出，正文用同一个 `NSLayoutManager` 画上去（§3.4）。
struct PaperSheetView: View {
    let item: SecretItem
    let onRespond: () -> Void

    /// 纸宽占屏宽的比例（§3.2）。
    static let widthRatio: CGFloat = 0.8
    /// 正文块、媒体块之间的间距。
    static let sectionSpacing: CGFloat = 16
    /// 回复入口保留但先不露字（沿用既有决定），只占位不显形。
    private static let respondRowHeight: CGFloat = 28

    var body: some View {
        let spec = PaperRegistry.spec(for: item.paperID)
        GeometryReader { canvas in
            let paperWidth = canvas.size.width * Self.widthRatio
            let scale = paperWidth / spec.pixelSize.width
            let sideMargin = paperWidth * spec.contentSideMarginRatio
            let contentWidth = paperWidth - sideMargin * 2
            let pointSize = spec.basePointSize
                * PaperFontResolver.dynamicTypeScale(baseSize: spec.basePointSize)
            let layout = PaperTextLayoutBuilder.make(
                text: item.text,
                spec: spec,
                pointSize: pointSize,
                width: contentWidth
            )
            let textHeight = item.text.isEmpty ? 0 : layout.contentHeight
            let metrics = PaperMediaMetrics(
                contentWidth: contentWidth,
                dynamicTypeScale: pointSize / spec.basePointSize
            )
            let mediaHeight = metrics.height(for: item.allAttachments)
            let sections = [textHeight, mediaHeight, Self.respondRowHeight].filter { $0 > 0 }
            let contentHeight = sections.reduce(0, +)
                + CGFloat(max(0, sections.count - 1)) * Self.sectionSpacing
            let paperHeight = spec.paperHeight(forContent: contentHeight / scale) * scale

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        PaperBackground(
                            spec: spec,
                            paperWidth: paperWidth,
                            bands: spec.bandCount(forContent: contentHeight / scale)
                        )
                        .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)

                        VStack(spacing: 0) {
                            Color.clear.frame(height: spec.top * scale)

                            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                                if textHeight > 0 {
                                    PaperTextCanvas(layout: layout)
                                        .frame(height: textHeight)
                                }

                                if mediaHeight > 0 {
                                    AttachmentCollectionView(
                                        attachments: item.allAttachments,
                                        tint: item.kind.tint,
                                        paperMetrics: metrics
                                    )
                                    .frame(height: mediaHeight, alignment: .top)
                                }

                                Button(action: onRespond) {
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                        .frame(height: Self.respondRowHeight)
                                }
                                .buttonStyle(.plain)
                                .opacity(0)
                                .accessibilityLabel(item.kind.homeActionTitle)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: max(spec.center * scale, contentHeight),
                                alignment: .topLeading
                            )

                            dateRow(spec: spec, pointSize: pointSize)
                                .frame(minHeight: spec.bottom * scale, alignment: .top)
                        }
                        .padding(.horizontal, sideMargin)
                    }
                }
                .frame(width: paperWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .frame(minHeight: canvas.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 日期落在下段上沿、右对齐（§6）：正文角色，字号 = 基准 × 0.68，墨色 = 正文墨色 × 0.62。
    private func dateRow(spec: PaperSheetSpec, pointSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(Font(PaperFontResolver.font(
                    for: spec.preferredFontRole,
                    size: pointSize * 0.68
                )))
                .foregroundStyle(Color(spec.inkColor).opacity(0.62))
        }
        .padding(.top, 4)
    }
}
