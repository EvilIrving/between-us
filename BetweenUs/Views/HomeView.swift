import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var composeKind: ContainerKind?

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
            .sheet(item: $composeKind) { kind in
                ComposeSheet(kind: kind)
            }
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
        VStack(spacing: 18) {
            roomObject(kind: .star) {
                StarJarView()
            }
            .frame(width: 140)

            HStack(alignment: .top, spacing: 34) {
                roomObject(kind: .capsule) {
                    CapsuleBoxView()
                }
                .frame(width: 140)

                roomObject(kind: .paper) {
                    PaperBinView()
                }
                .frame(width: 140)
            }
        }
        .frame(maxWidth: 430)
        .padding(.top, 20)
    }

    private func roomObject<Destination: View>(
        kind: ContainerKind,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        VStack(spacing: 2) {
            NavigationLink(destination: destination) {
                RoomObject(
                    kind: kind,
                    count: sharedCount(kind),
                    waiting: unopenedCount(kind)
                )
            }
            .buttonStyle(SoftScaleButtonStyle())

            Button {
                RitualHaptics.selection()
                composeKind = kind
            } label: {
                Text("留下")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.tint.opacity(0.82))
                    .frame(height: 28)
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel("在\(kind.title)留下一件")
        }
        .frame(maxWidth: .infinity)
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

}

private struct RoomObject: View {
    let kind: ContainerKind
    let count: Int
    let waiting: Int

    var body: some View {
        VStack(spacing: 9) {
            containerGlyph

            Text(kind.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .frame(height: 23, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 156, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.title)
        .accessibilityHint("打开这个共同容器")
    }

    private var containerGlyph: some View {
        ZStack {
            ContainerVisual(
                kind: kind,
                count: count,
                style: .room,
                isActive: waiting > 0
            )
            .scaleEffect(
                x: horizontalArtworkScale,
                y: verticalArtworkScale
            )
            .offset(y: artworkVerticalOffset)
        }
        .frame(width: 124, height: 124)
        .overlay(alignment: .topTrailing) {
            if waiting > 0 {
                Circle()
                    .fill(kind.tint)
                    .frame(width: 8, height: 8)
                    .padding(4)
            }
        }
    }

    private var horizontalArtworkScale: CGFloat {
        switch kind {
        case .star: return 0.88
        case .capsule: return 1
        case .paper: return 0.98
        }
    }

    private var verticalArtworkScale: CGFloat {
        switch kind {
        case .star: return 0.88
        case .capsule: return 1.75
        case .paper: return 0.98
        }
    }

    private var artworkVerticalOffset: CGFloat {
        switch kind {
        case .star: return 0
        case .capsule: return -6
        case .paper: return -4
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
