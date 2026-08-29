import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var notificationState: NotificationAuthorizationState = .notDetermined
    @State private var isClearingContent = false
    @State private var didCopyFeedbackEmail = false

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    settingsHeader

                    SettingsSection(title: "共同空间") {
                        if isLocalPreview {
                            SettingsActionRow(
                                systemName: "arrow.clockwise.circle",
                                title: "恢复数据",
                                value: nil,
                                tint: ContainerKind.star.tint
                            ) {
                                Task { await store.replenishLocalPreview() }
                            }

                        } else {
                            SettingsFactRow(
                                systemName: "person.2",
                                title: "身份",
                                value: relationship?.isOwner == true ? "创建者".localized : "参与者".localized,
                                tint: ContainerKind.capsule.tint
                            )

                            SettingsRowDivider()

                            SettingsActionRow(
                                systemName: "person.crop.circle.badge.plus",
                                title: relationship?.isOwner == true ? "邀请对方".localized : "查看共享".localized,
                                value: nil,
                                tint: ContainerKind.capsule.tint
                            ) {
                                Task { await store.prepareShareSheet() }
                            }

                            SettingsRowDivider()

                            SettingsActionRow(
                                systemName: "arrow.triangle.2.circlepath.icloud",
                                title: "同步",
                                value: syncDetail,
                                tint: Color(red: 0.44, green: 0.58, blue: 0.66)
                            ) {
                                Task { await store.refresh() }
                            }
                        }
                    }

                    SettingsSection(title: "偏好") {
                        SettingsLanguageRow(
                            selection: Binding(
                                get: { localization.currentLanguage },
                                set: { localization.setLanguage($0) }
                            )
                        )

                        SettingsRowDivider()

                        SettingsActionRow(
                            systemName: "bell.badge",
                            title: "内容变化提醒",
                            value: notificationDetail,
                            tint: ContainerKind.star.tint
                        ) {
                            handleNotificationAction()
                        }
                    }

                    SettingsSection(title: "这台设备") {
                        SettingsFactRow(
                            systemName: "internaldrive",
                            title: "媒体文件",
                            value: formattedStorage,
                            tint: Color(red: 0.48, green: 0.55, blue: 0.57)
                        )

                        SettingsRowDivider()

                        SettingsFactRow(
                            systemName: "app.badge",
                            title: "耳语 · Between us",
                            value: versionText,
                            tint: ContainerKind.paper.tint
                        )
                    }

                    SettingsSection(title: "关于") {
                        SettingsActionRow(
                            systemName: "heart.text.square",
                            title: "关于耳语",
                            value: nil,
                            tint: ContainerKind.star.tint
                        ) {
                            openWebsite("")
                        }

                        SettingsRowDivider()

                        SettingsActionRow(
                            systemName: "hand.raised",
                            title: "隐私政策",
                            value: nil,
                            tint: Color(red: 0.44, green: 0.58, blue: 0.66)
                        ) {
                            openWebsite("privacy/")
                        }

                        SettingsRowDivider()

                        SettingsActionRow(
                            systemName: "questionmark.bubble",
                            title: "使用帮助",
                            value: nil,
                            tint: ContainerKind.capsule.tint
                        ) {
                            openWebsite("support/")
                        }

                        SettingsRowDivider()

                        SettingsCopyRow(
                            systemName: "envelope",
                            title: "反馈问题",
                            value: "jescain2024@gmail.com",
                            isCopied: didCopyFeedbackEmail,
                            tint: ContainerKind.paper.tint
                        ) {
                            copyFeedbackEmail()
                        }
                    }

                    if !isLocalPreview {
                        clearContentZone
                    }
                    dangerZone
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 9)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            notificationState = await store.notificationAuthorizationStatus()
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            SceneCloseControl(label: "返回首页") { dismiss() }

            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

            }

            Spacer()
        }
    }

    private var dangerZone: some View {
        Group {
            if isLocalPreview {
                Button {
                    RitualHaptics.selection()
                    Task { await store.endRelationship() }
                } label: {
                    Text("离开预览".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(SoftScaleButtonStyle())
                .disabled(store.viewModel.isPerformingAction)
            } else {
                protectedEndSpaceZone
            }
        }
    }

    private var protectedEndSpaceZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(endSpaceTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText.opacity(0.82))

                    Text(endSpaceExplanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CompactHoldAction(
                title: endSpaceActionTitle,
                workingTitle: "正在处理".localized,
                duration: 2.0,
                isEnabled: !store.viewModel.isPerformingAction,
                isWorking: store.viewModel.isPerformingAction && !isClearingContent
            ) {
                Task { await store.endRelationship() }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.red.opacity(0.09), lineWidth: 1)
        }
    }

    private var clearContentZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("清空全部内容")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText.opacity(0.82))

                    Text(clearContentExplanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CompactHoldAction(
                title: "按住清空".localized,
                workingTitle: "正在清空".localized,
                duration: 2.0,
                isEnabled: !store.viewModel.data.items.isEmpty && !store.viewModel.isPerformingAction,
                isWorking: isClearingContent
            ) {
                isClearingContent = true
                Task {
                    await store.clearAllContent()
                    isClearingContent = false
                }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.red.opacity(0.09), lineWidth: 1)
        }
    }

    private var relationship: RelationshipLocator? {
        store.viewModel.data.relationship
    }

    private var isLocalPreview: Bool {
        store.viewModel.data.isLocalPreview
    }

    private var syncDetail: String {
        switch store.viewModel.syncStatus {
        case .idle: return "等待 iCloud".localized
        case .syncing: return "同步中".localized
        case .upToDate(let date):
            guard let date else { return "已同步".localized }
            return "上次同步 %@".localized(date.formatted(date: .omitted, time: .shortened))
        case .attention(let message): return message.localized
        case .localPreview: return "仅保存在本机".localized
        }
    }

    private var notificationDetail: String {
        switch notificationState {
        case .notDetermined: return "未设置".localized
        case .enabled: return "已开启".localized
        case .disabled: return "已关闭".localized
        }
    }

    private var formattedStorage: String {
        ByteCountFormatter.string(
            fromByteCount: store.viewModel.data.totalAttachmentBytes,
            countStyle: .file
        )
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var endSpaceTitle: String {
        if isLocalPreview { return "离开预览".localized }
        return relationship?.isOwner == true ? "删除共同空间".localized : "退出共同空间".localized
    }

    private var clearContentExplanation: String {
        let count = Int64(store.viewModel.data.items.count)
        return "当前共 %lld 条；清空后双方都无法恢复，但共同空间会保留。".localized(count)
    }

    private var endSpaceActionTitle: String {
        if isLocalPreview { return "按住离开预览".localized }
        return relationship?.isOwner == true ? "按住删除共同空间".localized : "按住退出共同空间".localized
    }

    private var endSpaceExplanation: String {
        if isLocalPreview {
            return "本机预览内容将被删除。".localized
        }
        if relationship?.isOwner == true {
            return "所有内容和媒体将永久删除，双方都无法恢复。".localized
        }
        return "退出后需要新的邀请才能再次加入。".localized
    }

    private func handleNotificationAction() {
        switch notificationState {
        case .enabled, .disabled:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        case .notDetermined:
            Task {
                _ = await store.requestNotificationAuthorization()
                notificationState = await store.notificationAuthorizationStatus()
            }
        }
    }

    private func openWebsite(_ path: String) {
        guard let url = URL(string: "https://betweenus.onecat.dev/\(path)") else { return }
        openURL(url)
    }

    private func copyFeedbackEmail() {
        UIPasteboard.general.string = "jescain2024@gmail.com"
        RitualHaptics.success()
        didCopyFeedbackEmail = true

        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopyFeedbackEmail = false
        }
    }
}

private struct SettingsLanguageRow: View {
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 13) {
            SettingsRowGlyph(systemName: "globe", tint: Color(red: 0.50, green: 0.54, blue: 0.72))

            Text("语言")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 10)

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        RitualHaptics.selection()
                        selection = language
                    } label: {
                        if selection == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.displayName)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppTheme.primaryText.opacity(0.72))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.white.opacity(0.42))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.66), lineWidth: 1) }
            }
        }
        .padding(.vertical, 11)
    }
}

private struct CompactHoldAction: View {
    let title: String
    let workingTitle: String
    let duration: TimeInterval
    let isEnabled: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        HoldToCompleteSurface(
            duration: duration,
            isEnabled: isEnabled,
            isWorking: isWorking,
            onComplete: action
        ) { progress, _ in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.06))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.14))
                        .frame(width: proxy.size.width * progress)

                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.red)
                        } else {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.caption.weight(.semibold))
                        }

                        Text(isWorking ? workingTitle : title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.red.opacity(isEnabled ? 0.82 : 0.42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("持续按住完成，松开取消".localized)
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            action()
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.localized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 5)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.018), radius: 18, y: 8)
        }
    }
}

private struct SettingsFactRow: View {
    let systemName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            SettingsRowGlyph(systemName: systemName, tint: tint)

            Text(title.localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 12)

            Text(value.localized)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsActionRow: View {
    let systemName: String
    let title: String
    let value: String?
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            HStack(spacing: 13) {
                SettingsRowGlyph(systemName: systemName, tint: tint)

                Text(title.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                if let value {
                    Text(value.localized)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.28))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}

private struct SettingsCopyRow: View {
    let systemName: String
    let title: String
    let value: String
    let isCopied: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 13) {
                SettingsRowGlyph(systemName: systemName, tint: tint)

                Text(title.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 8)

                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCopied ? tint : AppTheme.secondaryText.opacity(0.40))
                    .frame(width: 18)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityLabel("反馈问题".localized)
        .accessibilityValue(value)
        .accessibilityHint((isCopied ? "已复制" : "点按复制").localized)
    }
}

private struct SettingsRowGlyph: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint.opacity(0.90))
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.10))
            .clipShape(Circle())
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.primaryText.opacity(0.055))
            .frame(height: 1)
            .padding(.leading, 51)
    }
}
