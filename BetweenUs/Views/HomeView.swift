import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var composeKind: ContainerKind?
    @State private var openedItem: SecretItem?
    @State private var isOpening = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientRoomBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        if !store.viewModel.data.isLocalPreview {
                            coupleSyncCard
                                .padding(.horizontal, 20)
                        }

                        sharedRoom
                            .padding(.horizontal, 20)
                            .padding(.bottom, 26)
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDisabled(openedItem != nil)
                .accessibilityHidden(openedItem != nil)
                .refreshable {
                    await store.refresh()
                }

                if let openedItem {
                    ContainerRevealOverlay(
                        item: openedItem,
                        onDismiss: { self.openedItem = nil },
                        onRespond: {
                            self.openedItem = nil
                            composeKind = openedItem.kind
                        }
                    )
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
        VStack(spacing: HomeRoomMetrics.rowSpacing) {
            roomObject(kind: .star)

            HStack(alignment: .bottom, spacing: HomeRoomMetrics.rowSpacing) {
                roomObject(kind: .capsule)
                roomObject(kind: .paper)
            }
        }
        .frame(maxWidth: 430)
        .padding(.top, HomeRoomMetrics.topPadding)
    }

    private var coupleSyncCard: some View {
        Button {
            RitualHaptics.selection()
            Task {
                await store.prepareShareSheet()
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ContainerKind.capsule.tint.opacity(0.90))
                    .frame(width: 42, height: 42)
                    .background(ContainerKind.capsule.tint.opacity(0.11))
                    .clipShape(Circle())

                Text("空间共享".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

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

    private var syncCardAction: String {
        store.viewModel.data.relationship?.isOwner == true ? "邀请对方" : "查看共享"
    }

    private func roomObject(kind: ContainerKind) -> some View {
        // 房间里的物件就是真实内容的物理现场：点具体的一份内容直接打开它。
        ContainerPhysicsStage(
            kind: kind,
            items: store.viewModel.data.allItems(kind: kind),
            isPaused: scenePhase != .active || openedItem != nil,
            onOpenItem: { open($0) },
            onEmptyTap: { openNext(kind) }
        )
        .frame(maxWidth: kind == .star ? HomeRoomMetrics.starWidth : .infinity)
    }

    private func open(_ item: SecretItem) {
        guard !isOpening, openedItem == nil else { return }
        guard store.viewModel.data.isOpenableByMe(item) else {
            RitualHaptics.warning()
            return
        }
        isOpening = true
        Task { @MainActor in
            defer { isOpening = false }
            guard let opened = await store.commitOpen(item) else {
                RitualHaptics.warning()
                return
            }
            openedItem = opened
        }
    }

    private func openNext(_ kind: ContainerKind) {
        guard !isOpening, openedItem == nil else { return }
        isOpening = true
        Task { @MainActor in
            defer { isOpening = false }
            guard let item = await store.openNext(kind: kind) else {
                RitualHaptics.warning()
                return
            }
            openedItem = item
        }
    }
}

private enum HomeRoomMetrics {
    static let starWidth: CGFloat = 195
    static let rowSpacing: CGFloat = 28
    static let topPadding: CGFloat = 16
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
