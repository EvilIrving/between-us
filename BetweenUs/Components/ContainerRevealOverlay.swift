import SwiftUI

struct ContainerRevealOverlay: View {
    @ObservedObject var controller: ContainerRevealAnimationController
    var onDismiss: () -> Void
    var onRespond: () -> Void

    var body: some View {
        GeometryReader { canvas in
            let sample = controller.sample
            let cardSize = controller.cardFrame.size == .zero
                ? ContainerRevealAnchors.cardLayoutSize(in: canvas.size)
                : controller.cardFrame.size

            ZStack {
                Color.black.opacity(sample.dim)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if sample.cardInteractive {
                            onDismiss()
                        }
                    }
                    .allowsHitTesting(sample.cardInteractive)

                if let item = controller.item {
                    RevealNoteCard(item: item, onDismiss: onDismiss, onRespond: onRespond)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .scaleEffect(sample.card.scale)
                        .opacity(sample.card.opacity)
                        .position(sample.card.position == .zero ? CGPoint(x: canvas.size.width / 2, y: canvas.size.height * 0.46) : sample.card.position)
                        .allowsHitTesting(sample.cardInteractive)
                }

                if let token = controller.token, sample.showsToken {
                    RevealTokenView(token: token)
                        .frame(width: token.visualSize.width, height: token.visualSize.height)
                        .scaleEffect(sample.content.scale)
                        .rotation3DEffect(
                            .degrees(sample.content.rotationY),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.62
                        )
                        .shadow(
                            color: token.type.kind.tint.opacity(Double(0.22 * sample.content.glow * sample.content.opacity)),
                            radius: 10 + 16 * Double(sample.content.glow)
                        )
                        .opacity(sample.content.opacity)
                        .position(sample.content.position)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .allowsHitTesting(controller.isPlaying)
    }
}

struct RevealTokenView: View {
    let token: RevealContentToken

    var body: some View {
        switch token.type {
        case .star:
            if let imageName = token.imageName {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ParametricTokenView(kind: .star, seed: token.seed, filled: true)
            }
        case .capsule:
            ParametricTokenView(kind: .capsule, seed: token.seed, filled: true)
        case .paperBall:
            ParametricTokenView(kind: .paper, seed: token.seed, filled: true)
        }
    }
}

struct RevealNoteCard: View {
    let item: SecretItem
    let onDismiss: () -> Void
    let onRespond: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let writing = writingRect(in: proxy.size)

            ZStack {
                Image("NotesCard")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.58))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.48))
                                .clipShape(Circle())
                        }
                        .buttonStyle(SoftScaleButtonStyle())
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("关闭".localized)
                    }

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

                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    Button(action: onRespond) {
                        Text(item.kind.homeActionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.kind.tint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(SoftScaleButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.leading, writing.minX)
                .padding(.trailing, proxy.size.width - writing.maxX)
                .padding(.top, writing.minY)
                .padding(.bottom, proxy.size.height - writing.maxY)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func writingRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.22,
            y: size.height * 0.27,
            width: size.width * 0.56,
            height: size.height * 0.44
        )
    }
}
