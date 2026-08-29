import SwiftUI
import UIKit

struct MyDepositsView: View {
    @EnvironmentObject private var store: DearUsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: ContainerKind?
    @State private var section: DrawerSection = .leftByMe

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        SceneCloseControl(label: "关上抽屉") { dismiss() }
                        Spacer()
                    }

                    VStack(spacing: 6) {
                        Text("抽屉")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
                            .multilineTextAlignment(.center)
                    }

                    sectionTokens

                    filterTokens

                    if items.isEmpty {
                        EmptyDrawerView(kind: selectedKind, section: section)
                            .frame(minHeight: 360)
                    } else {
                        LazyVStack(spacing: 13) {
                            ForEach(items) { item in
                                NavigationLink {
                                    DrawerItemDetailView(item: item, section: section)
                                } label: {
                                    DrawerItemCard(item: item, section: section)
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

    private var sectionTokens: some View {
        HStack(spacing: 8) {
            ForEach(DrawerSection.allCases) { candidate in
                DrawerSectionToken(
                    section: candidate,
                    isSelected: section == candidate
                ) {
                    section = candidate
                }
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.20))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.38), lineWidth: 1) }
    }

    private var filterTokens: some View {
        HStack(spacing: 8) {
            DrawerFilterToken(
                title: "全部",
                kind: nil,
                systemImage: "circle.grid.3x3.fill",
                tint: AppTheme.primaryText,
                isSelected: selectedKind == nil
            ) {
                selectedKind = nil
            }

            ForEach(ContainerKind.allCases) { kind in
                DrawerFilterToken(
                    title: shortTitle(for: kind),
                    kind: kind,
                    systemImage: nil,
                    tint: kind.tint,
                    isSelected: selectedKind == kind
                ) {
                    selectedKind = kind
                }
            }
        }
    }

    private var items: [SecretItem] {
        switch section {
        case .leftByMe:
            return store.viewModel.data.ownItems(kind: selectedKind)
        case .openedFromOther:
            return store.viewModel.data.openedFromCounterpart(kind: selectedKind)
        }
    }

    private func shortTitle(for kind: ContainerKind) -> String {
        switch kind {
        case .star: return "星星"
        case .capsule: return "胶囊"
        case .paper: return "纸团"
        }
    }

}

private enum DrawerSection: String, CaseIterable, Identifiable {
    case leftByMe
    case openedFromOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftByMe: return "我留下的"
        case .openedFromOther: return "我接住的"
        }
    }

    var subtitle: String {
        switch self {
        case .leftByMe: return "你留下的内容"
        case .openedFromOther: return "你打开过的内容"
        }
    }

    var systemImage: String {
        switch self {
        case .leftByMe: return "tray.and.arrow.down"
        case .openedFromOther: return "hands.sparkles"
        }
    }
}

private struct DrawerSectionToken: View {
    let section: DrawerSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.56))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white.opacity(0.50) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}

private struct DrawerFilterToken: View {
    let title: String
    let kind: ContainerKind?
    let systemImage: String?
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: 5) {
                if let kind {
                    RitualObjectGlyph(kind: kind, size: 28, filled: true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(height: 28)
                }
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
    let section: DrawerSection

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
            Text(section == .leftByMe ? "还没有留下内容" : "还没有打开内容")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
        }
    }

    private var emptyMessage: String {
        switch section {
        case .leftByMe:
            return "从任一容器留下一件后，会显示在这里。"
        case .openedFromOther:
            return "打开过的内容会保留在这里。"
        }
    }
}

private struct DrawerItemCard: View {
    let item: SecretItem
    let section: DrawerSection

    var body: some View {
        HStack(spacing: 14) {
            DrawerItemLeadingVisual(item: item)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(item.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.kind.tint)
                    if let attachmentSummary {
                        Label(attachmentSummary.text, systemImage: attachmentSummary.systemImage)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.58))
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
                    .fill(statusIsActive ? item.kind.tint.opacity(0.78) : AppTheme.secondaryText.opacity(0.16))
                    .frame(width: 9, height: 9)
                    .shadow(color: statusIsActive ? item.kind.tint.opacity(0.34) : .clear, radius: 5)
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusIsActive ? item.kind.tint : AppTheme.secondaryText.opacity(0.56))
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

    private var statusIsActive: Bool {
        section == .openedFromOther || item.openedAt != nil
    }

    private var attachmentSummary: (text: String, systemImage: String)? {
        let images = item.allAttachments.filter { $0.kind == .image }
        if !images.isEmpty {
            return (images.count == 1 ? "照片" : "\(images.count) 张", images.count == 1 ? "photo" : "photo.stack")
        }
        if let audio = item.allAttachments.first(where: { $0.kind == .audio }) {
            return ((audio.duration ?? 0).formattedDuration, "waveform")
        }
        return nil
    }

    private var statusText: String {
        switch section {
        case .leftByMe: return item.openedAt == nil ? "等着" : "看过"
        case .openedFromOther: return "收好"
        }
    }

    private var rotation: Double {
        Double(abs(item.id.uuidString.hashValue % 5) - 2) * 0.22
    }
}

private struct DrawerItemLeadingVisual: View {
    let item: SecretItem
    private let mediaStore = MediaFileStore()

    var body: some View {
        let images = item.allAttachments.filter { $0.kind == .image }
        if images.count > 1 {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(images.prefix(9).enumerated()), id: \.offset) { _, attachment in
                    if let image = UIImage(contentsOfFile: mediaStore.url(for: attachment).path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else if let attachment = images.first,
           let image = UIImage(contentsOfFile: mediaStore.url(for: attachment).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                }
        } else if item.attachment?.kind == .audio {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.kind.tint.opacity(0.11))
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .background(item.kind.tint.opacity(0.88))
                    .clipShape(Circle())
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(item.kind.tint.opacity(0.16), lineWidth: 1)
            }
        } else {
            ContainerItemIcon(kind: item.kind)
        }
    }
}

private struct DrawerItemDetailView: View {
    let item: SecretItem
    let section: DrawerSection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: item.kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        SceneCloseControl(label: "返回抽屉") { dismiss() }
                        Spacer()
                        Text(detailStatus)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(section == .openedFromOther || item.openedAt != nil ? item.kind.tint : AppTheme.secondaryText)
                    }

                    RevealObjectAnimationForDeposit(kind: item.kind)
                        .frame(height: 116)

                    VStack(spacing: 17) {
                        if !item.text.isEmpty {
                            Text(item.text)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !item.allAttachments.isEmpty {
                            AttachmentCollectionView(attachments: item.allAttachments, tint: item.kind.tint)
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

    private var detailStatus: String {
        switch section {
        case .leftByMe:
            return item.openedAt == nil ? "还在等对方" : "对方已经打开"
        case .openedFromOther:
            guard let openedAt = item.openedAt else { return "已经接住" }
            return "你在 \(openedAt.formatted(date: .abbreviated, time: .shortened)) 接住了它"
        }
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
