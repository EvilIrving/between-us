import SwiftUI
import UIKit

struct RelationshipOnboardingView: View {
    @EnvironmentObject private var store: BetweenUsStore

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    ZStack {
                        AppTheme.glow(for: .star)
                            .frame(width: 300, height: 260)
                        ContainerVisual(kind: .star, count: 0, style: .compact)
                            .frame(width: 184, height: 208)
                    }

                    Text("耳语")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(.horizontal, 28)

                    HoldToOpenControl(
                        kind: .star,
                        title: "按住邀请",
                        inactiveTitle: "正在创建",
                        duration: 0.92,
                        isEnabled: !store.viewModel.isPerformingAction,
                        isWorking: store.viewModel.isPerformingAction,
                        onComplete: {
                            Task { await store.createRelationship() }
                        }
                    )
                    .padding(.horizontal, 36)

                    JoinSpaceHint()
                        .padding(.horizontal, 28)

                    LookAroundEntry {
                        Task { await store.enterLocalPreview() }
                    }

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct JoinSpaceHint: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "envelope.open")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ContainerKind.capsule.tint.opacity(0.88))
                .frame(width: 42, height: 42)
                .background(ContainerKind.capsule.tint.opacity(0.10))
                .clipShape(Circle())

            Text("打开 iCloud 邀请".localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ICloudRequiredView: View {
    let message: String

    @EnvironmentObject private var store: BetweenUsStore
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
                        Text("无法打开空间")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.primaryText)
                        Text(message)
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }

                    LookAroundEntry {
                        Task { await store.enterLocalPreview() }
                    }

                    HStack(spacing: 22) {
                        QuietSystemAction(systemName: "gear", title: "系统设置") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }

                        QuietSystemAction(systemName: "arrow.clockwise", title: "重试") {
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
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.caption.weight(.semibold))
                Text("本机预览")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Color.white.opacity(0.26))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.46), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityHint("进入本机预览".localized)
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
                Text(title.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}
