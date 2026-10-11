import SwiftUI
import UIKit

struct MyDepositsView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: ContainerKind?
    @State private var section: DrawerSection = .leftByMe
    // 抽屉里点开的就是首页那一张纸：纸浮在抽屉上，关掉回到抽屉。
    @State private var openedItem: SecretItem?
    @State private var composeKind: ContainerKind?

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            VStack(spacing: 16) {
                drawerHeader

                sectionTokens

                filterTokens

                if items.isEmpty {
                    EmptyDrawerView(kind: selectedKind)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 13) {
                            ForEach(items) { item in
                                Button {
                                    openPaper(item)
                                } label: {
                                    DrawerItemCard(item: item, section: section)
                                }
                                .buttonStyle(SoftScaleButtonStyle())
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 32)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 9)
            .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            .disabled(openedItem != nil)
            .accessibilityHidden(openedItem != nil)

            if let openedItem {
                ContainerRevealOverlay(
                    item: openedItem,
                    onDismiss: { self.openedItem = nil },
                    onRespond: {
                        let kind = openedItem.kind
                        self.openedItem = nil
                        composeKind = kind
                    },
                    screenLayerHeight: DrawerPaperScreenLayer.barHeight
                ) {
                    DrawerPaperScreenLayer(
                        item: openedItem,
                        section: section,
                        onDeleted: { self.openedItem = nil }
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $composeKind) { kind in
            ComposeSheet(kind: kind)
        }
    }

    private func openPaper(_ item: SecretItem) {
        RitualHaptics.selection()
        openedItem = item
    }

    // 与设置页共用一套页头：返回控件在左，标题紧跟其右。
    private var drawerHeader: some View {
        HStack(spacing: 14) {
            SceneCloseControl(label: "返回首页") { dismiss() }

            Text("抽屉")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()
        }
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
                accessibilityTitle: "全部",
                kind: nil,
                systemImage: "circle.grid.3x3.fill",
                tint: AppTheme.primaryText,
                isSelected: selectedKind == nil
            ) {
                selectedKind = nil
            }

            ForEach(ContainerKind.allCases) { kind in
                DrawerFilterToken(
                    accessibilityTitle: kind.title,
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

}

private enum DrawerSection: String, CaseIterable, Identifiable {
    case leftByMe
    case openedFromOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftByMe: return T("我放入的")
        case .openedFromOther: return T("我打开的")
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
    let accessibilityTitle: String
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
            Group {
                if let kind {
                    RitualObjectGlyph(kind: kind, filled: true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: TokenIconMetrics.size, height: TokenIconMetrics.size)
                }
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
        .accessibilityLabel(T(key: accessibilityTitle))
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
                    RitualObjectGlyph(kind: kind, filled: false)
                } else {
                    Image(systemName: "archivebox")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.55))
                }
            }
            Text("暂无记录")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
        }
    }
}

private struct DrawerItemCard: View {
    let item: SecretItem
    let section: DrawerSection

    var body: some View {
        HStack(spacing: 14) {
            ContainerItemIcon(kind: item.kind, id: item.id)

            VStack(alignment: .leading, spacing: 6) {
                if !attachmentBadges.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(attachmentBadges) { badge in
                            HStack(spacing: 2) {
                                Image(systemName: badge.symbol)
                                if badge.showsCount {
                                    Text("\(badge.count)")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                }
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.58))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(attachmentAccessibilityText)
                }

                if let itemText {
                    Text(itemText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                }
            }
            // 给右侧状态圆点留出宽度，正文和它不会互相压住。
            .padding(.trailing, 23)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
        // 纯媒体内容没有正文行，日期直接落进右下角；有正文时才为它留出一行。
        .padding(.bottom, itemText == nil ? 14 : 33)
        .overlay(alignment: .bottomTrailing) {
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
                .padding(.trailing, 15)
                .padding(.bottom, 12)
        }
        .overlay(alignment: .trailing) {
            // 状态只保留圆点：文案表达留待后续用别的方式呈现。
            Circle()
                .fill(statusIsActive ? item.kind.tint.opacity(0.78) : AppTheme.secondaryText.opacity(0.16))
                .frame(width: 9, height: 9)
                .shadow(color: statusIsActive ? item.kind.tint.opacity(0.34) : .clear, radius: 5)
                .accessibilityLabel(statusText)
                .padding(.trailing, 15)
        }
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

    // 列表只留图标：录音、照片、视频依次排列，图标区分一到三件，三件以上再补数字。
    private var attachmentBadges: [AttachmentBadge] {
        let images = item.allAttachments.filter { $0.kind == .image }
        let videos = item.allAttachments.filter { $0.kind == .video }
        let audioCount = item.allAttachments.filter { $0.kind == .audio }.count

        var badges: [AttachmentBadge] = []
        if audioCount > 0 {
            badges.append(AttachmentBadge(symbol: "waveform", count: audioCount))
        }
        if !images.isEmpty {
            badges.append(AttachmentBadge(symbol: Self.photoSymbol(count: images.count), count: images.count))
        }
        if !videos.isEmpty {
            badges.append(AttachmentBadge(symbol: Self.videoSymbol(count: videos.count), count: videos.count))
        }
        return badges
    }

    // 一张、斜叠两张、整齐一叠三张。
    private static func photoSymbol(count: Int) -> String {
        switch count {
        case 1: return "photo"
        case 2: return "photo.on.rectangle.angled"
        default: return "photo.stack"
        }
    }

    private static func videoSymbol(count: Int) -> String {
        switch count {
        case 1: return "video"
        case 2: return "play.rectangle.on.rectangle"
        default: return "film.stack"
        }
    }

    // 仅供 VoiceOver 使用，界面不再显示附件类型文案。
    private var attachmentAccessibilityText: String {
        let images = item.allAttachments.filter { $0.kind == .image }
        let videos = item.allAttachments.filter { $0.kind == .video }
        let audio = item.allAttachments.first { $0.kind == .audio }

        var parts: [String] = []
        if let audio, let duration = audio.duration, duration > 0 {
            parts.append(duration.formattedDuration)
        } else if audio != nil {
            parts.append(T("语音"))
        }
        if !images.isEmpty {
            parts.append(images.count == 1 ? T("一张照片") : T("%d 张照片", images.count))
        }
        if !videos.isEmpty {
            parts.append(videos.count == 1 ? T("一段视频") : T("%d 个视频", videos.count))
        }
        return parts.joined(separator: "、")
    }

    // 只有真实文字才占一行，纯媒体内容用图标和日期表达。
    private var itemText: String? {
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // 仅供 VoiceOver 使用，界面不再显示文案。
    private var statusText: String {
        switch section {
        case .leftByMe: return item.openedAt == nil ? T("未打开") : T("已打开")
        case .openedFromOther: return T("已打开")
        }
    }

    /// 纸条的自然倾斜：从 UUID 字节稳定派生。
    /// 不用 `uuidString.hashValue`：String 哈希每进程重播种，倾斜每次启动都会变（§10.4）。
    private var rotation: Double {
        let bytes = withUnsafeBytes(of: item.id.uuid) { Array($0) }
        return Double(Int(bytes[0] % 5) - 2) * 0.22
    }

    private struct AttachmentBadge: Identifiable {
        let symbol: String
        let count: Int

        var id: String { symbol }
        // 图标只表达到三件，三件以上再补数量。
        var showsCount: Bool { count >= 3 }
    }
}

private struct DrawerPaperScreenLayer: View {
    let item: SecretItem
    let section: DrawerSection
    let onDeleted: () -> Void

    /// 这一层占的高度，纸的舞台按这个值让位，两边用的是同一个数。
    static let barHeight: CGFloat = 62
    /// 删除用的红：屏幕层是半透明白底，系统红压在上面对比度不够。
    private static let deleteInk = Color(red: 0.70, green: 0.14, blue: 0.12)

    @EnvironmentObject private var store: BetweenUsStore
    @State private var isDeleting = false

    var body: some View {
        HStack(spacing: 10) {
            // 和关闭按钮同一套屏幕层成色：半透明白底 + 深墨字。
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText.opacity(0.72))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.55), in: Capsule())

            Spacer(minLength: 8)

            deleteControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .frame(height: Self.barHeight, alignment: .top)
    }

    private var deleteControl: some View {
        HoldToCompleteSurface(
            duration: 1.5,
            isEnabled: !isDeleting,
            isWorking: isDeleting,
            onComplete: startDeletion
        ) { progress, _ in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.55))

                    Capsule()
                        .fill(Self.deleteInk.opacity(0.18))
                        .frame(width: proxy.size.width * progress)

                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Self.deleteInk)
                        }
                        Text(isDeleting ? T("正在删除") : T("按住删除"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Self.deleteInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 132, height: 44)
        .accessibilityLabel(T("按住删除"))
        .accessibilityHint(T("持续按住完成，松开取消"))
        .accessibilityAction {
            guard !isDeleting else { return }
            startDeletion()
        }
    }

    private var statusText: String {
        switch section {
        case .leftByMe:
            return item.openedAt == nil ? T("等待对方打开") : T("对方已打开")
        case .openedFromOther:
            guard let openedAt = item.openedAt else { return T("已打开") }
            return T("打开于 %@", openedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func startDeletion() {
        isDeleting = true
        Task {
            let deleted = await store.deleteItem(id: item.id)
            isDeleting = false
            if deleted {
                RitualHaptics.success()
                onDeleted()
            } else {
                RitualHaptics.warning()
            }
        }
    }
}

struct ContainerItemIcon: View {
    let kind: ContainerKind
    var id: UUID? = nil

    var body: some View {
        RitualObjectGlyph(kind: kind, filled: true, tokenID: id)
    }
}
