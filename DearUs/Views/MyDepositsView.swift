import SwiftUI

struct MyDepositsView: View {
    @EnvironmentObject private var store: DearUsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: ContainerKind?

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        SceneCloseControl(label: "关上抽屉") { dismiss() }
                        Spacer()
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                            .frame(width: 42, height: 42)
                    }

                    VStack(spacing: 6) {
                        Text("我的抽屉")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("你曾经放下的东西，以及它有没有被对方轻轻打开")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
                            .multilineTextAlignment(.center)
                    }

                    filterTokens

                    if items.isEmpty {
                        EmptyDrawerView(kind: selectedKind)
                            .frame(minHeight: 360)
                    } else {
                        LazyVStack(spacing: 13) {
                            ForEach(items) { item in
                                NavigationLink {
                                    OwnDepositDetailView(item: item)
                                } label: {
                                    OwnDepositCard(item: item)
                                }
                                .buttonStyle(SoftScaleButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 9)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var filterTokens: some View {
        HStack(spacing: 8) {
            DrawerFilterToken(
                title: "全部",
                systemImage: "circle.grid.3x3.fill",
                tint: AppTheme.primaryText,
                isSelected: selectedKind == nil
            ) {
                selectedKind = nil
            }

            ForEach(ContainerKind.allCases) { kind in
                DrawerFilterToken(
                    title: shortTitle(for: kind),
                    systemImage: filterSymbol(for: kind),
                    tint: kind.tint,
                    isSelected: selectedKind == kind
                ) {
                    selectedKind = kind
                }
            }
        }
    }

    private var items: [SecretItem] {
        store.viewModel.data.ownItems(kind: selectedKind)
    }

    private func shortTitle(for kind: ContainerKind) -> String {
        switch kind {
        case .star: return "星星"
        case .capsule: return "胶囊"
        case .paper: return "纸团"
        }
    }

    private func filterSymbol(for kind: ContainerKind) -> String {
        switch kind {
        case .star: return "star.fill"
        case .capsule: return "capsule.fill"
        case .paper: return "doc.fill"
        }
    }
}

private struct DrawerFilterToken: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? tint : AppTheme.secondaryText.opacity(0.54))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.48) : Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.20) : Color.white.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}

private struct EmptyDrawerView: View {
    let kind: ContainerKind?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 124, height: 124)
                if let kind {
                    RitualObjectGlyph(kind: kind, size: 82, filled: false)
                } else {
                    Image(systemName: "archivebox")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.55))
                }
            }
            Text("这个角落还是空的")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text("你放进共同容器的内容，会在这里留下只属于你的存根。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
        }
    }
}

private struct OwnDepositCard: View {
    let item: SecretItem

    var body: some View {
        HStack(spacing: 14) {
            ContainerItemIcon(kind: item.kind)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(item.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.kind.tint)
                    if let attachment = item.attachment {
                        Image(systemName: attachment.kind.systemImage)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
                    }
                }

                Text(item.previewText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
            }

            Spacer(minLength: 5)

            VStack(spacing: 7) {
                Circle()
                    .fill(item.openedAt == nil ? AppTheme.secondaryText.opacity(0.16) : item.kind.tint.opacity(0.78))
                    .frame(width: 9, height: 9)
                    .shadow(color: item.openedAt == nil ? .clear : item.kind.tint.opacity(0.34), radius: 5)
                Text(item.openedAt == nil ? "等着" : "看过")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.openedAt == nil ? AppTheme.secondaryText.opacity(0.56) : item.kind.tint)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(AppTheme.paper.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.045), radius: 16, y: 8)
        .rotationEffect(.degrees(rotation))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var rotation: Double {
        Double(abs(item.id.uuidString.hashValue % 5) - 2) * 0.22
    }
}

private struct OwnDepositDetailView: View {
    let item: SecretItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: item.kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        SceneCloseControl(label: "返回抽屉") { dismiss() }
                        Spacer()
                        Text(item.openedAt == nil ? "还在等对方" : "对方已经打开")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.openedAt == nil ? AppTheme.secondaryText : item.kind.tint)
                    }

                    RevealObjectAnimationForDeposit(kind: item.kind)
                        .frame(height: 116)

                    VStack(spacing: 17) {
                        if !item.text.isEmpty {
                            Text(item.text)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .multilineTextAlignment(.center)
                                .lineSpacing(7)
                                .textSelection(.enabled)
                        }

                        if let attachment = item.attachment {
                            AttachmentContentView(attachment: attachment, tint: item.kind.tint)
                        }

                        Text(item.createdAt.formatted(date: .long, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.paper.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.68), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.06), radius: 24, y: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 9)
                .padding(.bottom, 34)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RevealObjectAnimationForDeposit: View {
    let kind: ContainerKind

    var body: some View {
        ZStack {
            AppTheme.glow(for: kind)
                .frame(width: 190, height: 116)
            RitualObjectGlyph(kind: kind, size: 92, filled: true)
                .shadow(color: kind.tint.opacity(0.20), radius: 14)
        }
        .accessibilityHidden(true)
    }
}

struct ContainerItemIcon: View {
    let kind: ContainerKind

    var body: some View {
        RitualObjectGlyph(kind: kind, size: 54, filled: true)
    }
}
