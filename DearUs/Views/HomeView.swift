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

                        Text("不是谁给谁发来了一条消息。只是你们共同拥有的房间，悄悄发生了一点变化。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 42)
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
            QuietSyncGlyph(status: store.viewModel.syncStatus)

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
        VStack(spacing: 6) {
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

            ShelfPlank()
                .frame(height: 20)
                .padding(.horizontal, 26)
                .offset(y: -22)

            HStack(alignment: .top, spacing: 8) {
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
            .padding(.top, -14)

            ShelfPlank()
                .frame(height: 18)
                .padding(.horizontal, 12)
                .offset(y: -18)
        }
    }

    private var roomWhisper: String {
        let waiting = ContainerKind.allCases.reduce(0) { $0 + unopenedCount($1) }
        switch waiting {
        case 0: return "今天这里很安静。想起什么，就放下一点。"
        case 1: return "房间里有一件东西，等你愿意靠近。"
        default: return "有几件东西悄悄留在这里，不催你现在打开。"
        }
    }

    private func sharedCount(_ kind: ContainerKind) -> Int {
        store.viewModel.data.count(kind: kind)
    }

    private func unopenedCount(_ kind: ContainerKind) -> Int {
        store.viewModel.data.unopenedCountFromCounterpart(kind: kind)
    }

    private var starWhisper: String {
        unopenedCount(.star) > 0 ? "瓶底有新的光" : "喜欢会慢慢积起来"
    }

    private var capsuleWhisper: String {
        unopenedCount(.capsule) > 0 ? "盒子比昨天重一点" : "需要时，再封一颗"
    }

    private var paperWhisper: String {
        unopenedCount(.paper) > 0 ? "等准备好再接住" : "这里可以先放下"
    }
}

private enum RoomObjectScale {
    case large
    case compact

    var artworkHeight: CGFloat {
        switch self {
        case .large: return 230
        case .compact: return 154
        }
    }

    var containerHeight: CGFloat {
        switch self {
        case .large: return 292
        case .compact: return 226
        }
    }
}

private struct RoomObject: View {
    let kind: ContainerKind
    let count: Int
    let waiting: Int
    let scale: RoomObjectScale
    let quietText: String

    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: scale == .large ? 8 : 5) {
            ZStack(alignment: .topTrailing) {
                AppTheme.glow(for: kind)
                    .frame(width: scale == .large ? 260 : 180, height: scale == .large ? 230 : 160)
                    .opacity(waiting > 0 ? (isBreathing ? 1 : 0.62) : 0.34)

                artwork
                    .frame(height: scale.artworkHeight)
                    .scaleEffect(isBreathing ? 1.012 : 0.992)
                    .offset(y: isBreathing ? -2 : 2)

                if waiting > 0 {
                    WaitingFirefly(kind: kind)
                        .padding(scale == .large ? 24 : 12)
                }
            }

            VStack(spacing: 3) {
                Text(kind.title)
                    .font(scale == .large ? .title3.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(quietText)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale.containerHeight)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: isBreathing)
        .onAppear { isBreathing = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title)，\(quietText)")
        .accessibilityHint("打开这个共同容器")
    }

    @ViewBuilder
    private var artwork: some View {
        switch kind {
        case .star:
            StarBottleIllustration(count: count)
                .frame(width: 210)
        case .capsule:
            CapsuleBoxIllustration(count: count)
                .frame(width: 176)
        case .paper:
            PaperBinIllustration(count: count)
                .frame(width: 164)
        }
    }
}

private struct WaitingFirefly: View {
    let kind: ContainerKind
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.tint.opacity(0.16))
                .frame(width: 26, height: 26)
                .scaleEffect(pulse ? 1.26 : 0.84)
            Circle()
                .fill(kind.tint.opacity(0.88))
                .frame(width: 7, height: 7)
                .shadow(color: kind.tint, radius: 8)
        }
        .animation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

private struct ShelfPlank: View {
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.36, blue: 0.26).opacity(0.30),
                        Color(red: 0.36, green: 0.26, blue: 0.20).opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color.black.opacity(0.09), radius: 9, y: 7)
            .accessibilityHidden(true)
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
