import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BetweenUsStore
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

                        coupleSyncCard
                            .padding(.horizontal, 20)

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
            VStack(alignment: .leading) {
                Text("耳语")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
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

    private var coupleSyncCard: some View {
        Button {
            RitualHaptics.selection()
            Task {
                if store.viewModel.data.isLocalPreview {
                    await store.leaveLocalPreview()
                } else {
                    await store.prepareShareSheet()
                }
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: store.viewModel.data.isLocalPreview ? "icloud.slash" : "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ContainerKind.capsule.tint.opacity(0.90))
                    .frame(width: 42, height: 42)
                    .background(ContainerKind.capsule.tint.opacity(0.11))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("情侣同步".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(syncCardDetail.localized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(syncCardAction.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ContainerKind.capsule.tint.opacity(0.92))
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(ContainerKind.capsule.tint.opacity(0.10))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .disabled(store.viewModel.isPerformingAction)
    }

    private var syncCardDetail: String {
        if store.viewModel.data.isLocalPreview {
            return "真机登录 iCloud 后可用"
        }
        return relationship?.isOwner == true ? "邀请对方，共用当前空间" : "已通过 iCloud 同步"
    }

    private var syncCardAction: String {
        if store.viewModel.data.isLocalPreview {
            return "离开预览"
        }
        return relationship?.isOwner == true ? "邀请对方" : "查看共享"
    }

    private var relationship: RelationshipLocator? {
        store.viewModel.data.relationship
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
                Text(kind.homeActionTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.tint.opacity(0.82))
                    .frame(height: 28)
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel("在%@%@".localized(kind.title, kind.homeActionTitle))
        }
        .frame(maxWidth: .infinity)
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
        .accessibilityHint("打开%@".localized(kind.title))
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
            Text(title.localized)
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
