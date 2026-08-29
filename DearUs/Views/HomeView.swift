import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: DearUsStore

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientRoomBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        sharedRoom
                            .padding(.horizontal, 20)
                            .padding(.bottom, 26)
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await store.refresh()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("耳语")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Text(roomWhisper)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            NavigationLink {
                MyDepositsView()
            } label: {
                HomeCornerControl(systemName: "archivebox", title: "抽屉")
            }
            .buttonStyle(SoftScaleButtonStyle())

            NavigationLink {
                SettingsView()
            } label: {
                HomeCornerControl(systemName: "slider.horizontal.3", title: "设置")
            }
            .buttonStyle(SoftScaleButtonStyle())
        }
    }

    private var sharedRoom: some View {
        VStack(spacing: 12) {
            NavigationLink {
                StarJarView()
            } label: {
                RoomObject(
                    kind: .star,
                    count: sharedCount(.star),
                    waiting: unopenedCount(.star),
                    scale: .large,
                    quietText: starWhisper
                )
            }
            .buttonStyle(SoftScaleButtonStyle())

            HStack(spacing: 12) {
                NavigationLink {
                    CapsuleBoxView()
                } label: {
                    RoomObject(
                        kind: .capsule,
                        count: sharedCount(.capsule),
                        waiting: unopenedCount(.capsule),
                        scale: .compact,
                        quietText: capsuleWhisper
                    )
                }
                .buttonStyle(SoftScaleButtonStyle())

                NavigationLink {
                    PaperBinView()
                } label: {
                    RoomObject(
                        kind: .paper,
                        count: sharedCount(.paper),
                        waiting: unopenedCount(.paper),
                        scale: .compact,
                        quietText: paperWhisper
                    )
                }
                .buttonStyle(SoftScaleButtonStyle())
            }
        }
    }

    private var roomWhisper: String {
        if store.viewModel.data.isLocalPreview {
            return "本机预览 · 内容不会同步"
        }
        let waiting = ContainerKind.allCases.reduce(0) { $0 + unopenedCount($1) }
        switch waiting {
        case 0: return "没有待打开的内容"
        case 1: return "1 件内容待打开"
        default: return "\(waiting) 件内容待打开"
        }
    }

    private func sharedCount(_ kind: ContainerKind) -> Int {
        store.viewModel.data.count(kind: kind)
    }

    private func unopenedCount(_ kind: ContainerKind) -> Int {
        store.viewModel.data.unopenedCountFromCounterpart(kind: kind)
    }

    private var starWhisper: String {
        statusText(for: .star)
    }

    private var capsuleWhisper: String {
        statusText(for: .capsule)
    }

    private var paperWhisper: String {
        statusText(for: .paper)
    }

    private func statusText(for kind: ContainerKind) -> String {
        let waiting = unopenedCount(kind)
        if waiting > 0 { return "\(waiting) 件待打开" }
        return sharedCount(kind) == 0 ? "还没有内容" : "共 \(sharedCount(kind)) 件"
    }
}

private enum RoomObjectScale {
    case large
    case compact
}

private struct RoomObject: View {
    let kind: ContainerKind
    let count: Int
    let waiting: Int
    let scale: RoomObjectScale
    let quietText: String

    var body: some View {
        Group {
            if scale == .large {
                HStack(spacing: 16) {
                    containerGlyph(size: 86)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(kind.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(quietText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                    }

                    Spacer(minLength: 10)

                    countView
                }
                .padding(.horizontal, 18)
                .frame(height: 134)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        containerGlyph(size: 72)
                        Spacer()
                        countView
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text(quietText)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 178)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.38), kind.tint.opacity(waiting > 0 ? 0.15 : 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(kind.tint.opacity(waiting > 0 ? 0.42 : 0.20), lineWidth: waiting > 0 ? 1.5 : 1)
        }
        .shadow(color: kind.tint.opacity(waiting > 0 ? 0.09 : 0.04), radius: 18, y: 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title)，\(quietText)")
        .accessibilityHint("打开这个共同容器")
    }

    private var countView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(AppTheme.primaryText)
            Text("件")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
        }
    }

    private func containerGlyph(size: CGFloat) -> some View {
        ZStack {
            AppTheme.glow(for: kind)
            ContainerVisual(
                kind: kind,
                count: count,
                style: .room,
                isActive: waiting > 0
            )
            .padding(kind == .capsule ? 2 : 5)
        }
            .frame(width: size, height: kind == .capsule ? size * 0.76 : size * 1.06)
            .overlay(alignment: .topTrailing) {
                if waiting > 0 {
                    Circle()
                        .fill(kind.tint)
                        .frame(width: 8, height: 8)
                        .padding(7)
                }
            }
    }
}

private struct HomeCornerControl: View {
    let systemName: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(AppTheme.primaryText.opacity(0.66))
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.white.opacity(0.36))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.60), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}
