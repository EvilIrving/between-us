import SwiftUI
import UIKit

struct RelationshipOnboardingView: View {
    @EnvironmentObject private var store: DearUsStore

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    ZStack {
                        AppTheme.glow(for: .star)
                            .frame(width: 300, height: 260)
                        FunctionalContainerPlaceholder(kind: .star, count: 0, compact: true)
                            .frame(width: 184, height: 208)
                    }

                    VStack(spacing: 10) {
                        Text("耳语")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("两个人，共用三个容器。")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.80))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                    }
                    .padding(.horizontal, 28)

                    if LocalPreview.isSimulator {
                        LookAroundEntry(prominent: true) {
                            Task { await store.enterLocalPreview() }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 4)
                    }

                    HoldToOpenControl(
                        kind: .star,
                        title: "按住创建空间",
                        inactiveTitle: "正在创建",
                        duration: 0.92,
                        isEnabled: !store.viewModel.isPerformingAction,
                        isWorking: store.viewModel.isPerformingAction,
                        onComplete: {
                            Task { await store.createRelationship() }
                        }
                    )
                    .padding(.horizontal, 36)

                    if !LocalPreview.isSimulator {
                        LookAroundEntry {
                            Task { await store.enterLocalPreview() }
                        }
                        .padding(.top, 4)
                    }

                    VStack(spacing: 8) {
                        Text("已有邀请")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("打开对方发送的 iCloud 邀请即可加入。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 34)

                    Text("一次只能加入一个共同空间。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ICloudRequiredView: View {
    let message: String

    @EnvironmentObject private var store: DearUsStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AmbientRoomBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.34))
                            .frame(width: 132, height: 132)
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(spacing: 9) {
                        Text("共同房间暂时没有打开")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.primaryText)
                        Text(message)
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }

                    LookAroundEntry(prominent: true) {
                        Task { await store.enterLocalPreview() }
                    }

                    HStack(spacing: 22) {
                        QuietSystemAction(systemName: "gear", title: "系统设置") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }

                        QuietSystemAction(systemName: "arrow.clockwise", title: "再试一次") {
                            Task { await store.sceneBecameActive() }
                        }
                    }
                }
                .padding(30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct LookAroundEntry: View {
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: prominent ? 8 : 6) {
                if prominent {
                    RitualObjectGlyph(kind: .star, size: 64, filled: false)
                }
                Text("本机预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("不创建空间，内容不会同步。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityHint("进入本机预览房间")
    }
}

private struct QuietSystemAction: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.72))
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.38))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}
