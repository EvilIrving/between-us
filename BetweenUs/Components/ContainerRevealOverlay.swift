import SwiftUI
import UIKit

struct ContainerRevealOverlay: View {
    let item: SecretItem
    let onDismiss: () -> Void
    let onRespond: () -> Void

    var body: some View {
        GeometryReader { canvas in
            let card = NotePaper.cardSize(for: item.id, in: canvas.size)

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                RevealNoteCard(item: item, onDismiss: onDismiss, onRespond: onRespond)
                    .frame(width: card.width, height: card.height)
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .transaction { $0.animation = nil }
    }
}

/// 纸条纸面：一条内容永远用同一张纸，纸面尺寸只由这张纸自身决定。
/// 运行时资产已按纸面边界裁掉透明留白，图片即纸面，右上角即纸面右上角。
private enum NotePaper {
    static let names = ["Paper01", "Paper03", "Paper04", "Paper05", "Paper06"]

    /// 纸面宽度占屏宽的比例，高度按纸面自身比例推导。
    static let widthRatio: CGFloat = 0.8
    /// 纵向兜底，纸面特别长时整体等比缩小，避免超出屏幕。
    static let maxHeightRatio: CGFloat = 0.86

    static func name(for id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return names[Int(bytes[0] &+ bytes[1]) % names.count]
    }

    static func cardSize(for id: UUID, in canvas: CGSize) -> CGSize {
        let width = canvas.width * widthRatio
        guard let image = UIImage(named: name(for: id)), image.size.width > 0 else {
            return CGSize(width: width, height: width)
        }
        let height = width * (image.size.height / image.size.width)
        let limit = canvas.height * maxHeightRatio
        guard height > limit else { return CGSize(width: width, height: height) }
        return CGSize(width: width * (limit / height), height: limit)
    }
}

struct RevealNoteCard: View {
    let item: SecretItem
    let onDismiss: () -> Void
    let onRespond: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let writing = writingRect(in: proxy.size)
            let bodyHeight = contentBodyHeight(in: proxy.size)

            ZStack(alignment: .topTrailing) {
                Image(NotePaper.name(for: item.id))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !item.text.isEmpty {
                                Text(item.text)
                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !item.allAttachments.isEmpty {
                                AttachmentCollectionView(
                                    attachments: item.allAttachments,
                                    tint: item.kind.tint
                                )
                                .frame(maxWidth: .infinity)
                            }

                            Spacer(minLength: 0)

                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, minHeight: bodyHeight, alignment: .topLeading)
                    }
                    .frame(width: writing.width, height: bodyHeight, alignment: .topLeading)

                    Spacer(minLength: 0)

                    // 用户明确要求：先隐藏回复入口的文字，入口本身保留（点击仍进入创作），
                    // 之后会用别的形式重新露出，所以代码不删。
                    Button(action: onRespond) {
                        Text(item.kind.homeActionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.kind.tint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .opacity(0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.kind.homeActionTitle)
                }
                .padding(.leading, writing.minX)
                .padding(.trailing, proxy.size.width - writing.maxX)
                .padding(.top, writing.minY)
                .padding(.bottom, proxy.size.height - writing.maxY)

                // 纸面尺寸不统一，关闭按钮统一落在纸面右上角。
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText.opacity(0.58))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.52))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .position(x: proxy.size.width, y: 0)
                .accessibilityLabel("关闭".localized)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func writingRect(in size: CGSize) -> CGRect {
        let width = size.width * 0.76
        return CGRect(
            x: (size.width - width) / 2,
            y: size.height * 0.26,
            width: width,
            height: size.height * 0.60
        )
    }

    private func contentBodyHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.36, 112), writingRect(in: size).height - 36)
    }
}
