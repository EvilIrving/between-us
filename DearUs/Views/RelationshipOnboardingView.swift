import SwiftUI
import UIKit

struct RelationshipOnboardingView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var bottleBreathes = false

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    ZStack {
                        AppTheme.glow(for: .star)
                            .frame(width: 300, height: 260)
                        StarBottleIllustration(count: 0)
                            .frame(width: 184, height: 208)
                            .scaleEffect(bottleBreathes ? 1.025 : 0.98)
                            .offset(y: bottleBreathes ? -3 : 2)
                    }
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: bottleBreathes)
                    .onAppear { bottleBreathes = true }

                    VStack(spacing: 10) {
                        Text("耳语")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("不是把话发出去，\n而是在两个人共同拥有的地方，慢慢留下生活。")
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
                        title: "按住，放下第一个空瓶子",
                        inactiveTitle: "正在布置共同房间",
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
                        Text("已经收到邀请？")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("直接打开对方发来的 iCloud 邀请。系统接受后，你会回到这间共同房间。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 34)

                    Text("一次只保留一个双人空间。没有额外账号，也没有公开主页。")
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
                Text("先看看房间")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("不创建 iCloud 共同空间。星星瓶、胶囊盒和纸团篓都可以先摸一遍。")
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
