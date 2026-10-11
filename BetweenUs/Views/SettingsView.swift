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
    @State private var isShowingLifetimeUnlock = false
    @State private var lifetimeUnlockContext: LifetimeUnlockContext = .settings
    @State private var releaseUpdateState: ReleaseUpdateState = .idle
    #if DEBUG
    @State private var isShowingConnectionPreview = false
    #endif
    @AppStorage(DeviceMotionMode.storageKey) private var deviceMotionModeRaw = DeviceMotionMode.standard.rawValue

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    settingsHeader

                    SettingsSection(title: "") {
                        if !isLocalPreview {
                            SettingsFactRow(
                                systemName: "person.2",
                                title: "身份",
                                value: relationship?.isOwner == true ? T("创建者") : T("参与者"),
                                tint: ContainerKind.capsule.tint
                            )

                            if store.viewModel.showsInviteEntry {
                                SettingsRowDivider()

                                SettingsActionRow(
                                    systemName: "person.crop.circle.badge.plus",
                                    title: T("邀请对方"),
                                    value: nil,
                                    tint: ContainerKind.capsule.tint
                                ) {
                                    Task { await store.presentInvite() }
                                }
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

                    if isLocalPreview {
                        SettingsSection(title: "测试功能") {
                            SettingsActionRow(
                                systemName: "infinity",
                                title: "预览永久版",
                                value: nil,
                                tint: ContainerKind.star.tint
                            ) {
                                lifetimeUnlockContext = .preview
                                isShowingLifetimeUnlock = true
                            }

                            SettingsRowDivider()

                            SettingsActionRow(
                                systemName: "arrow.clockwise.circle",
                                title: "恢复数据",
                                value: nil,
                                tint: ContainerKind.star.tint
                            ) {
                                Task { await store.replenishLocalPreview() }
                            }

                            SettingsRowDivider()

                            SettingsDeviceMotionRow(selection: deviceMotionMode)

                            SettingsRowDivider()

                            SettingsActionRow(
                                systemName: "rectangle.portrait.and.arrow.right",
                                title: "离开预览",
                                value: nil,
                                tint: Color.red.opacity(0.72)
                            ) {
                                Task { await store.endRelationship() }
                            }
                            .disabled(store.viewModel.isPerformingAction)
                        }
                    }

                    #if DEBUG
                    if !isLocalPreview {
                        // 连接这一段动画要两台手机才走得完，开发时留一个单机看它的入口。
                        SettingsSection(title: "测试功能") {
                            SettingsActionRow(
                                systemName: "sparkles",
                                title: "重播连接动画",
                                value: nil,
                                tint: ContainerKind.star.tint
                            ) {
                                isShowingConnectionPreview = true
                            }
                        }
                    }
                    #endif

                    if !isLocalPreview {
                        SettingsSection(title: "") {
                            SettingsActionRow(
                                systemName: store.viewModel.hasUnlimitedContent ? "infinity" : "tray.full",
                                title: store.viewModel.hasUnlimitedContent ? "永久版" : "免费版",
                                value: contentPlanDetail,
                                tint: ContainerKind.star.tint
                            ) {
                                lifetimeUnlockContext = .settings
                                isShowingLifetimeUnlock = true
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
                            systemName: "doc.text",
                            title: "使用条款",
                            value: nil,
                            tint: Color(red: 0.50, green: 0.54, blue: 0.72)
                        ) {
                            openWebsite("terms/")
                        }

                        SettingsRowDivider()

                        SettingsActionRow(
                            systemName: "cart",
                            title: "购买与退款",
                            value: nil,
                            tint: ContainerKind.star.tint
                        ) {
                            openWebsite("purchases/")
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
                            value: "dong.yy1916@gmail.com",
                            isCopied: didCopyFeedbackEmail,
                            tint: ContainerKind.paper.tint
                        ) {
                            copyFeedbackEmail()
                        }

                        SettingsRowDivider()

                        SettingsActionRow(
                            systemName: releaseUpdateSystemName,
                            title: releaseUpdateTitle,
                            value: releaseUpdateDetail,
                            tint: Color(red: 0.50, green: 0.54, blue: 0.72),
                            showsProgress: releaseUpdateState.isChecking
                        ) {
                            handleReleaseUpdateAction()
                        }
                        .disabled(releaseUpdateState.isChecking)

                        SettingsRowDivider()

                        SettingsFactRow(
                            systemName: "app.badge",
                            title: "耳语 · Between us",
                            value: versionText,
                            tint: ContainerKind.paper.tint
                        )
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
        .sheet(isPresented: $isShowingLifetimeUnlock) {
            LifetimeUnlockView(context: lifetimeUnlockContext)
        }
        #if DEBUG
        .fullScreenCover(isPresented: $isShowingConnectionPreview) {
            ConnectionView(mode: .preview)
        }
        #endif
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
            if !isLocalPreview {
                protectedEndSpaceZone
            }
        }
    }

    private var protectedEndSpaceZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(endSpaceTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText.opacity(0.82))

            CompactHoldAction(
                title: endSpaceActionTitle,
                workingTitle: T("正在处理"),
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
                Text(T("清空内容"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.82))

                Spacer(minLength: 8)

                Text(T("%d 条", store.viewModel.data.items.count))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
            }

            CompactHoldAction(
                title: T("按住清空"),
                workingTitle: T("正在清空"),
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

    private var deviceMotionMode: Binding<DeviceMotionMode> {
        Binding(
            get: { DeviceMotionMode(rawValue: deviceMotionModeRaw) ?? .standard },
            set: { deviceMotionModeRaw = $0.rawValue }
        )
    }

    private var isLocalPreview: Bool {
        store.viewModel.data.isLocalPreview
    }

    private var syncDetail: String {
        switch store.viewModel.syncStatus {
        case .idle: return T("等待 iCloud")
        case .syncing: return T("同步中")
        case .upToDate(let date):
            guard let date else { return T("已同步") }
            return T("上次同步 %@", date.formatted(date: .omitted, time: .shortened))
        case .attention(let message): return T(key: message)
        case .localPreview: return T("仅保存在本机")
        }
    }

    private var notificationDetail: String {
        switch notificationState {
        case .notDetermined: return T("未设置")
        case .enabled: return T("已开启")
        case .disabled: return T("已关闭")
        }
    }

    private var contentPlanDetail: String {
        if store.viewModel.hasUnlimitedContent {
            return T("不限量")
        }
        return T("%d / %d", 
            store.viewModel.data.items.count,
            CommerceConfiguration.freeItemLimit
        )
    }

    private var formattedStorage: String {
        ByteCountFormatter.string(
            fromByteCount: store.viewModel.data.totalAttachmentBytes,
            countStyle: .file
        )
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return version
    }

    private var releaseUpdateSystemName: String {
        switch releaseUpdateState {
        case .upToDate:
            return "checkmark.circle"
        case .available:
            return "arrow.down.circle"
        case .comingSoon:
            return "clock"
        case .failed:
            return "wifi.exclamationmark"
        case .idle, .checking:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var releaseUpdateTitle: String {
        switch releaseUpdateState {
        case .available:
            return "发现新版本"
        case .comingSoon:
            return "新版本即将开放"
        default:
            return "检查更新"
        }
    }

    private var releaseUpdateDetail: String? {
        switch releaseUpdateState {
        case .idle:
            return nil
        case .checking:
            return "正在检查"
        case .upToDate:
            return "已是最新版本"
        case .available(let version, _):
            return version
        case .comingSoon(let version):
            return version
        case .failed:
            return "稍后重试"
        }
    }

    private var endSpaceTitle: String {
        relationship?.isOwner == true ? T("永久删除") : T("退出空间")
    }

    private var endSpaceActionTitle: String {
        relationship?.isOwner == true ? T("按住删除空间") : T("按住退出空间")
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

    private func handleReleaseUpdateAction() {
        if case .available(_, let downloadURL) = releaseUpdateState {
            openURL(downloadURL)
            return
        }

        releaseUpdateState = .checking
        Task { @MainActor in
            do {
                let result = try await ReleaseUpdateService().check(currentVersion: versionText)
                switch result {
                case .upToDate:
                    releaseUpdateState = .upToDate
                case .available(let version, let downloadURL):
                    releaseUpdateState = .available(version: version, downloadURL: downloadURL)
                case .comingSoon(let version):
                    releaseUpdateState = .comingSoon(version: version)
                }
            } catch {
                releaseUpdateState = .failed
            }
        }
    }

    private func copyFeedbackEmail() {
        UIPasteboard.general.string = "dong.yy1916@gmail.com"
        RitualHaptics.success()
        didCopyFeedbackEmail = true

        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopyFeedbackEmail = false
        }
    }
}

private struct SettingsDeviceMotionRow: View {
    @Binding var selection: DeviceMotionMode

    var body: some View {
        HStack(spacing: 13) {
            SettingsRowGlyph(systemName: "iphone", tint: Color(red: 0.50, green: 0.58, blue: 0.62))

            Text("跟随手机动作")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 10)

            Menu {
                ForEach(DeviceMotionMode.allCases) { mode in
                    Button {
                        RitualHaptics.selection()
                        selection = mode
                    } label: {
                        if selection == mode {
                            Label(mode.statusTitle, systemImage: "checkmark")
                        } else {
                            Text(mode.statusTitle)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.statusTitle)
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
        .accessibilityHint(T("持续按住完成，松开取消"))
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
            if !title.isEmpty {
                Text(T(key: title))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 5)
            }

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

            Text(T(key: title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 12)

            Text(T(key: value))
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
    var showsProgress = false
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            HStack(spacing: 13) {
                SettingsRowGlyph(systemName: systemName, tint: tint)

                Text(T(key: title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                if let value {
                    Text(T(key: value))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                        .lineLimit(1)
                }

                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.28))
                }
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

                Text(T(key: title))
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
        .accessibilityLabel(T("反馈问题"))
        .accessibilityValue(value)
        .accessibilityHint(isCopied ? T("已复制") : T("点按复制"))
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

private enum ReleaseUpdateState {
    case idle
    case checking
    case upToDate
    case available(version: String, downloadURL: URL)
    case comingSoon(version: String)
    case failed

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

private struct ReleaseManifest: Decodable {
    let latestVersion: String
    let downloadURL: String
    let isDownloadOpen: Bool
}

private enum ReleaseCheckResult {
    case upToDate
    case available(version: String, downloadURL: URL)
    case comingSoon(version: String)
}

private enum ReleaseUpdateError: Error {
    case invalidResponse
}

private struct ReleaseUpdateService {
    private let manifestURL = URL(string: "https://betweenus.onecat.dev/release.json")!
    private let allowedDownloadHosts = ["testflight.apple.com", "apps.apple.com"]

    func check(currentVersion: String) async throws -> ReleaseCheckResult {
        var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
        ]

        guard let requestURL = components?.url else {
            throw ReleaseUpdateError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw ReleaseUpdateError.invalidResponse
        }

        let manifest = try JSONDecoder().decode(ReleaseManifest.self, from: data)
        let hasNewVersion = manifest.latestVersion.compare(
            currentVersion,
            options: .numeric
        ) == .orderedDescending

        guard hasNewVersion else {
            return .upToDate
        }

        guard manifest.isDownloadOpen else {
            return .comingSoon(version: manifest.latestVersion)
        }

        guard let downloadURL = URL(string: manifest.downloadURL),
              downloadURL.scheme == "https",
              let host = downloadURL.host?.lowercased(),
              allowedDownloadHosts.contains(host) else {
            throw ReleaseUpdateError.invalidResponse
        }

        return .available(version: manifest.latestVersion, downloadURL: downloadURL)
    }
}
