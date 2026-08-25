import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: DearUsStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var notificationState: NotificationAuthorizationState = .notDetermined

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    HStack {
                        SceneCloseControl(label: "回到共同房间") { dismiss() }
                        Spacer()
                        QuietSyncGlyph(status: store.viewModel.syncStatus)
                    }

                    VStack(spacing: 6) {
                        Text("房间设置")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("这些是共同空间的门锁、提醒和离开方式")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
                    }

                    SettingsSection(title: "共同空间") {
                        if isLocalPreview {
                            SettingsFactRow(
                                systemName: "eye",
                                title: "当前房间",
                                value: "本机预览"
                            )

                            Text("内容只留在这台设备，不会同步到 iCloud，也不能邀请对方。要开始真正的双人空间，先离开预览。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
                                .lineSpacing(4)
                        } else {
                            SettingsFactRow(
                                systemName: "person.2",
                                title: "你在这里的身份",
                                value: relationship?.isOwner == true ? "创建者" : "参与者"
                            )

                            SettingsActionRow(
                                systemName: "person.crop.circle.badge.plus",
                                title: relationship?.isOwner == true ? "邀请或管理对方" : "查看共同空间",
                                subtitle: "这一步会打开 Apple 的系统共享面板"
                            ) {
                                Task { await store.prepareShareSheet() }
                            }

                            SettingsActionRow(
                                systemName: "arrow.triangle.2.circlepath.icloud",
                                title: "让房间现在对齐一次",
                                subtitle: syncDetail
                            ) {
                                Task { await store.refresh() }
                            }
                        }
                    }

                    SettingsSection(title: "轻提醒") {
                        SettingsActionRow(
                            systemName: "bell.badge",
                            title: "容器发生变化时提醒",
                            subtitle: notificationDetail
                        ) {
                            handleNotificationAction()
                        }

                        Text("通知只会说共同房间发生了变化，不会展示星星、胶囊或纸团里的具体内容。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                            .lineSpacing(4)
                    }

                    SettingsSection(title: "本机与隐私") {
                        SettingsFactRow(
                            systemName: "internaldrive",
                            title: "这台设备上的媒体副本",
                            value: formattedStorage
                        )

                        Text("共同内容保存在 Apple CloudKit 的共享记录区。App 没有自建业务服务器，也不要求额外注册账号；照片和语音会在本机保留受文件保护的副本。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.65))
                            .lineSpacing(4)
                    }

                    SettingsSection(title: "关于") {
                        SettingsFactRow(
                            systemName: "app.badge",
                            title: "耳语 · Dear Us",
                            value: versionText
                        )

                        Text("核心体验不是聊天时间线，而是共同养着三个会随关系慢慢变化的容器。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.65))
                            .lineSpacing(4)
                    }

                    VStack(spacing: 13) {
                        Text(endSpaceTitle)
                            .font(.headline)
                            .foregroundStyle(Color.red.opacity(0.76))

                        Text(endSpaceExplanation)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.66))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 12)

                        HoldToOpenControl(
                            kind: .paper,
                            title: endSpaceActionTitle,
                            inactiveTitle: isLocalPreview ? "正在离开预览" : "正在处理共同空间",
                            duration: isLocalPreview ? 1.1 : 2.0,
                            isEnabled: !store.viewModel.isPerformingAction,
                            isWorking: store.viewModel.isPerformingAction,
                            onComplete: {
                                Task { await store.endRelationship() }
                            }
                        )
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)
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

    private var relationship: RelationshipLocator? {
        store.viewModel.data.relationship
    }

    private var isLocalPreview: Bool {
        store.viewModel.data.isLocalPreview
    }

    private var syncDetail: String {
        switch store.viewModel.syncStatus {
        case .idle: return "等待 iCloud"
        case .syncing: return "正在把两边的变化放回同一间房"
        case .upToDate(let date):
            guard let date else { return "已经同步" }
            return "上次对齐于 \(date.formatted(date: .omitted, time: .shortened))"
        case .attention(let message): return message
        case .localPreview: return "本机预览，不会同步"
        }
    }

    private var notificationDetail: String {
        switch notificationState {
        case .notDetermined: return "还没有决定"
        case .enabled: return "已经开启"
        case .disabled: return "已在系统中关闭"
        }
    }

    private var formattedStorage: String {
        ByteCountFormatter.string(
            fromByteCount: store.viewModel.data.totalAttachmentBytes,
            countStyle: .file
        )
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(version) (\(build))"
    }

    private var endSpaceTitle: String {
        if isLocalPreview { return "离开预览房间" }
        return relationship?.isOwner == true ? "结束并删除共同空间" : "退出共同空间"
    }

    private var endSpaceActionTitle: String {
        if isLocalPreview { return "持续按住，离开预览" }
        return relationship?.isOwner == true ? "持续按住，确认永久删除" : "持续按住，确认离开"
    }

    private var endSpaceExplanation: String {
        if isLocalPreview {
            return "离开后会回到开始页。预览里放下的内容只在这台设备上，不会变成真正的共同空间。"
        }
        if relationship?.isOwner == true {
            return "持续按住两秒后，CloudKit 中的星星、胶囊、纸团和媒体会一起删除，双方都无法恢复。"
        }
        return "持续按住两秒后，这台设备会离开共同空间；再次加入需要创建者重新邀请。"
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
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.30))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            }
        }
    }
}

private struct SettingsFactRow: View {
    let systemName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowGlyph(systemName: systemName)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsActionRow: View {
    let systemName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                SettingsRowGlyph(systemName: systemName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.66))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.32))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}

private struct SettingsRowGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText.opacity(0.68))
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.38))
            .clipShape(Circle())
    }
}
