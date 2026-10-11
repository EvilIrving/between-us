import SwiftUI
import UIKit

// 连接页（ConnectionView）和「无法打开空间」共用的两个零件：
// QuietPill 是这一族页面里唯一的动作控件，ICloudRequiredView 是 iCloud 不可用时的落点。
// 首屏原本的瓶子引导已经由 ConnectionView 接手，这个文件里不再有那一屏。
/// 安静出口：一句话长在胶囊上。
/// 首屏、连接页和「无法打开空间」共用。tone 只分两级——真实动作和更轻的出口，不给第三种；
/// ground 只分两种——房间里的浅底，和连接页那片暮色。
/// 动作按钮只用文字，图标不重复文字已经说清的语义。
struct QuietPill: View {
    enum Tone {
        case action
        case muted
    }

    enum Ground {
        case room
        case dusk
    }

    let title: String
    var tone: Tone = .muted
    var ground: Ground = .room
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            Text(T(key: title))
                .font(font)
                .foregroundStyle(foreground)
                .padding(.horizontal, tone == .action ? 20 : 15)
                .frame(height: tone == .action ? 44 : 34)
                .background(fill)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(stroke, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityHint(accessibilityHint.map { T(key: $0) } ?? "")
    }

    private var font: Font {
        tone == .action ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var foreground: Color {
        switch ground {
        case .room:
            return tone == .action
                ? AppTheme.primaryText.opacity(0.86)
                : AppTheme.secondaryText.opacity(0.68)
        case .dusk:
            return Color(red: 1.0, green: 0.95, blue: 0.88)
                .opacity(tone == .action ? 0.92 : 0.72)
        }
    }

    private var fill: Color {
        switch ground {
        case .room:
            return Color.white.opacity(tone == .action ? 0.34 : 0.26)
        case .dusk:
            return Color.white.opacity(tone == .action ? 0.15 : 0.085)
        }
    }

    private var stroke: Color {
        switch ground {
        case .room:
            return Color.white.opacity(tone == .action ? 0.52 : 0.46)
        case .dusk:
            return Color.white.opacity(tone == .action ? 0.24 : 0.16)
        }
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

                    QuietPill(
                        title: "本机预览",
                        tone: .muted,
                        accessibilityHint: "进入本机预览"
                    ) {
                        Task { await store.enterLocalPreview() }
                    }

                    HStack(spacing: 12) {
                        QuietPill(title: "系统设置", tone: .muted) {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }

                        QuietPill(title: "重试", tone: .muted) {
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
