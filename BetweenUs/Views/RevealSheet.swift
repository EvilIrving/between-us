import SwiftUI

struct RevealSheet: View {
    let item: SecretItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUnsealed = false
    @State private var contentAppears = false
    @State private var showResponseComposer = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: item.kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        SceneCloseControl(label: "关闭") {
                            dismiss()
                        }
                        Spacer()
                        Text(item.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.kind.tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.28))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)

                    RevealObjectAnimation(kind: item.kind, isUnsealed: isUnsealed)
                        .frame(height: 150)
                        .padding(.top, 4)

                    if contentAppears {
                        VStack(spacing: 18) {
                            if !item.text.isEmpty {
                                Text(item.text)
                                    .font(.system(size: 21, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !item.allAttachments.isEmpty {
                                AttachmentCollectionView(attachments: item.allAttachments, tint: item.kind.tint)
                                    .frame(maxWidth: .infinity)
                            }

                            Text(item.createdAt.formatted(date: .long, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .background(RevealPaperShape(kind: item.kind).fill(AppTheme.paper.opacity(0.91)))
                        .overlay {
                            RevealPaperShape(kind: item.kind)
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.065), radius: 26, y: 14)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))

                        RitualActionToken(
                            kind: item.kind,
                            title: item.kind.homeActionTitle
                        ) {
                            showResponseComposer = true
                        }

                        VStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                            Text("下拉关闭")
                                .font(.caption2)
                        }
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.46))
                        .padding(.top, 2)
                        .padding(.bottom, 30)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .offset(y: dragOffset)
            .scaleEffect(1 - min(dragOffset / 1200, 0.035))
            .simultaneousGesture(dismissGesture)
        }
        .onAppear {
            if reduceMotion {
                isUnsealed = true
                contentAppears = true
            } else {
                withAnimation(.easeOut(duration: AppMotion.modeDuration)) {
                    isUnsealed = true
                    contentAppears = true
                }
            }
        }
        .sheet(isPresented: $showResponseComposer) {
            ComposeSheet(kind: item.kind)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height * 0.58
            }
            .onEnded { value in
                if value.translation.height > 165,
                   abs(value.translation.height) > abs(value.translation.width) {
                    RitualHaptics.soft()
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.settle) {
                        dragOffset = 0
                    }
                }
            }
    }

}

private struct RevealObjectAnimation: View {
    let kind: ContainerKind
    let isUnsealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.glow(for: kind)
                .frame(width: 220, height: 150)
                .opacity(isUnsealed ? 1 : 0.38)

            switch kind {
            case .star:
                ParametricTokenView(kind: .star, seed: 4, filled: true)
                    .frame(width: isUnsealed ? 88 : 58, height: isUnsealed ? 88 : 58)
                    .rotationEffect(.degrees(isUnsealed ? 22 : -42))
                    .shadow(color: kind.tint.opacity(0.28), radius: 18)

            case .capsule:
                ZStack {
                    CapsuleShellHalf(side: .leading)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.72, green: 0.80, blue: 0.73), kind.tint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay { CapsuleShellHalf(side: .leading).stroke(kind.tint.opacity(0.44), lineWidth: 1) }
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.white.opacity(0.34))
                                .frame(width: 2)
                                .padding(.vertical, 3)
                        }
                        .frame(width: 52, height: 36)
                        .offset(x: isUnsealed ? -39 : -26)

                    CapsuleShellHalf(side: .trailing)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.96), AppTheme.paper],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay { CapsuleShellHalf(side: .trailing).stroke(kind.tint.opacity(0.30), lineWidth: 1) }
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(kind.tint.opacity(0.20))
                                .frame(width: 2)
                                .padding(.vertical, 3)
                        }
                        .frame(width: 52, height: 36)
                        .offset(x: isUnsealed ? 39 : 26)
                }
                .rotationEffect(.degrees(-15))
                .shadow(color: kind.tint.opacity(0.20), radius: 15)

            case .paper:
                if isUnsealed {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppTheme.paper)
                        .frame(width: 112, height: 92)
                        .overlay {
                            PaperCreaseShape(seed: 11)
                                .stroke(AppTheme.secondaryText.opacity(0.10), lineWidth: 1)
                                .padding(10)
                        }
                        .rotationEffect(.degrees(-3))
                        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    CrumpledPaper(index: 5)
                        .frame(width: 72, height: 72)
                }
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.64, dampingFraction: 0.68),
            value: isUnsealed
        )
        .accessibilityHidden(true)
    }
}

private struct CapsuleShellHalf: Shape {
    enum Side {
        case leading
        case trailing
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        var path = Path()

        switch side {
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.midY),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.midY),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

private struct RevealPaperShape: Shape {
    let kind: ContainerKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .star:
            return RoundedRectangle(cornerRadius: 30, style: .continuous).path(in: rect)
        case .capsule:
            return RoundedRectangle(cornerRadius: min(42, rect.height * 0.18), style: .continuous).path(in: rect)
        case .paper:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.minY + 6))
            path.addLine(to: CGPoint(x: rect.maxX - 17, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.height * 0.34))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 13))
            path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 7))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.58))
            path.closeSubpath()
            return path
        }
    }
}
