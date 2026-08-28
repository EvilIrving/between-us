import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: DearUsStore

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientRoomBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        VStack(spacing: 7) {
                            Text("耳语")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)

                            Text(roomWhisper)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.78))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 2)

                        sharedRoom
                            .padding(.horizontal, 14)
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
        HStack(spacing: 12) {
            Spacer()

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
                    containerGlyph(size: 64)

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
                .frame(height: 116)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        containerGlyph(size: 48)
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
                .frame(height: 154)
            }
        }
        .background(kind.tint.opacity(waiting > 0 ? 0.13 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(kind.tint.opacity(waiting > 0 ? 0.42 : 0.20), lineWidth: waiting > 0 ? 1.5 : 1)
        }
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
        Image(systemName: symbolName)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(kind.tint)
            .frame(width: size, height: size)
            .background(kind.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if waiting > 0 {
                    Circle()
                        .fill(kind.tint)
                        .frame(width: 8, height: 8)
                        .padding(7)
                }
            }
    }

    private var symbolName: String {
        switch kind {
        case .star: return "star.fill"
        case .capsule: return "capsule.fill"
        case .paper: return "doc.fill"
        }
    }
}

private struct HomeCornerControl: View {
    let systemName: String
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText.opacity(0.70))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.28))
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
        }
        .accessibilityElement(children: .combine)
    }
}
