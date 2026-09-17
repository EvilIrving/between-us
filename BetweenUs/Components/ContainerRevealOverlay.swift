import SwiftUI

struct ContainerRevealOverlay: View {
    let item: SecretItem
    let onDismiss: () -> Void
    let onRespond: () -> Void

    var body: some View {
        GeometryReader { canvas in
            let cardWidth = min(max(canvas.size.width - 8, 300), 440)

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                RevealNoteCard(item: item, onDismiss: onDismiss, onRespond: onRespond)
                    .frame(width: cardWidth, height: cardWidth * (1024.0 / 1536.0))
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .transaction { $0.animation = nil }
    }
}

/// The six note papers are one family; a note keeps the same sheet on every open.
private enum NotePaper {
    static let names = (1...6).map { "Note_Paper_0\($0)" }

    static func name(for id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return names[Int(bytes[0] &+ bytes[1]) % names.count]
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

                    Button(action: onRespond) {
                        Text(item.kind.homeActionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.kind.tint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, writing.minX)
                .padding(.trailing, proxy.size.width - writing.maxX)
                .padding(.top, writing.minY)
                .padding(.bottom, proxy.size.height - writing.maxY)

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
                .position(
                    x: proxy.size.width * 0.76 + 30,
                    y: proxy.size.height * 0.155
                )
                .accessibilityLabel("关闭".localized)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func writingRect(in size: CGSize) -> CGRect {
        let width = size.width * 0.70 * (2.0 / 3.0)
        return CGRect(
            x: (size.width - width) / 2,
            y: size.height * 0.29,
            width: width,
            height: size.height * 0.55
        )
    }

    private func contentBodyHeight(in size: CGSize) -> CGFloat {
        // ~4 lines of 17pt text with line spacing, leaving respond lower on the note.
        min(max(size.height * 0.36, 112), writingRect(in: size).height - 36)
    }
}
