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
                VStack(spacing: 16) {
                    HStack {
                        SceneCloseControl(label: "回到共同房间") { dismiss() }
                        Spacer()
                    }

                    Text("设置")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    SettingsSection(title: "共同空间") {
                        if isLocalPreview {
                            SettingsFactRow(
                                systemName: "eye",
                                title: "当前房间",
                                value: "本机预览"
                            )

                            SettingsActionRow(
                                systemName: "arrow.clockwise.circle",
                                title: "补充演示内容",
                                subtitle: "让三个容器都可以打开"
                            ) {
                                Task { await store.replenishLocalPreview() }
                            }

                        } else {
                            SettingsFactRow(
                                systemName: "person.2",
                                title: "身份",
                                value: relationship?.isOwner == true ? "创建者" : "参与者"
                            )

                            SettingsActionRow(
                                systemName: "person.crop.circle.badge.plus",
                                title: relationship?.isOwner == true ? "管理成员" : "查看成员",
                                subtitle: "打开 iCloud 共享"
                            ) {
                                Task { await store.prepareShareSheet() }
                            }

                            SettingsActionRow(
                                systemName: "arrow.triangle.2.circlepath.icloud",
                                title: "立即同步",
                                subtitle: syncDetail
                            ) {
                                Task { await store.refresh() }
                            }
                        }
                    }

                    SettingsSection(title: "通知") {
                        SettingsActionRow(
                            systemName: "bell.badge",
                            title: "内容变化提醒",
                            subtitle: notificationDetail
                        ) {
                            handleNotificationAction()
                        }
                    }

                    SettingsSection(title: "存储与隐私") {
                        SettingsFactRow(
                            systemName: "internaldrive",
                            title: "本机媒体",
                            value: formattedStorage
                        )
                    }

                    SettingsSection(title: "关于") {
                        SettingsFactRow(
                            systemName: "app.badge",
                            title: "耳语 · Dear Us",
                            value: versionText
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(endSpaceTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.82))

                        Text(endSpaceExplanation)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.66))

                        CompactHoldAction(
                            title: endSpaceActionTitle,
                            workingTitle: isLocalPreview ? "正在离开" : "正在处理",
                            duration: isLocalPreview ? 1.1 : 2.0,
                            isEnabled: !store.viewModel.isPerformingAction,
                            isWorking: store.viewModel.isPerformingAction
                        ) {
                            Task { await store.endRelationship() }
                        }
                    }
                    .padding(.top, 4)
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

    private var relationship: RelationshipLocator? {
        store.viewModel.data.relationship
    }

    private var isLocalPreview: Bool {
        store.viewModel.data.isLocalPreview
    }

    private var syncDetail: String {
        switch store.viewModel.syncStatus {
        case .idle: return "等待 iCloud"
        case .syncing: return "同步中"
        case .upToDate(let date):
            guard let date else { return "已经同步" }
            return "上次同步 \(date.formatted(date: .omitted, time: .shortened))"
        case .attention(let message): return message
        case .localPreview: return "本机预览，不会同步"
        }
    }

    private var notificationDetail: String {
        switch notificationState {
        case .notDetermined: return "未设置"
        case .enabled: return "已开启"
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
        if isLocalPreview { return "离开预览" }
        return relationship?.isOwner == true ? "删除共同空间" : "退出共同空间"
    }

    private var endSpaceActionTitle: String {
        if isLocalPreview { return "按住离开预览" }
        return relationship?.isOwner == true ? "按住删除共同空间" : "按住退出共同空间"
    }

    private var endSpaceExplanation: String {
        if isLocalPreview {
            return "本机预览内容将被删除。"
        }
        if relationship?.isOwner == true {
            return "所有内容和媒体将永久删除，双方都无法恢复。"
        }
        return "退出后需要新的邀请才能再次加入。"
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
        .frame(height: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("持续按住完成，松开取消")
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.30))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        .padding(.vertical, 10)
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
            .padding(.vertical, 10)
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
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.38))
            .clipShape(Circle())
    }
}
