import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @EnvironmentObject private var room: RoomWorld
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var composeKind: ContainerKind?
    @State private var isShowingLifetimeUnlock = false
    @State private var canvasSize: CGSize = .zero
    @State private var safeArea = EdgeInsets()
    @State private var revealAnchors: [ContainerKind: RevealAnchorFrames] = [:]
    @State private var revealingKind: ContainerKind?
    @State private var liftedKind: ContainerKind?
    @State private var failedNudge: CGFloat = 0
    @State private var nudgeKind: ContainerKind?
    @State private var paperVisualCount = 0
    @State private var composeStartCount = 0
    @State private var composeStartKind: ContainerKind?
    @State private var revealTask: Task<Void, Never>?

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
                .scrollDisabled(room.isBusy)
                .refreshable {
                    await store.refresh()
                }

                ContainerRevealOverlay(
                    controller: room.reveal,
                    onDismiss: dismissReveal,
                    onRespond: {
                        if let kind = revealingKind ?? room.reveal.item?.kind {
                            beginCompose(kind)
                        }
                    }
                )

                ContainerStoreOverlay(
                    controller: room.contentStore,
                    containerFrame: revealAnchors[.paper]?.container ?? .zero
                )

                ContainerRevealOverlay(
                    controller: room.starReveal.reveal,
                    onDismiss: dismissReveal,
                    onRespond: {
                        beginCompose(.star)
                    }
                )
            }
            .coordinateSpace(name: ContainerRevealSpace.name)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            canvasSize = proxy.size
                            safeArea = proxy.safeAreaInsets
                        }
                        .onChange(of: proxy.size) { canvasSize = $0 }
                }
            }
            .onPreferenceChange(RevealAnchorKey.self) { revealAnchors = $0 }
            .onAppear {
                paperVisualCount = min(sharedCount(.paper), TrashBinPhysicsSystem.maximumVisibleCount)
            }
            .onChange(of: room.reveal.sample.showsToken) { showing in
                liftedKind = showing ? revealingKind : nil
            }
            .onChange(of: room.reveal.isPlaying) { playing in
                if !playing {
                    liftedKind = nil
                    revealingKind = nil
                }
            }
            .onChange(of: room.starReveal.isPlaying) { playing in
                if !playing {
                    revealingKind = nil
                }
            }
            .onChange(of: composeKind) { kind in
                if kind == nil {
                    if composeStartKind == .paper {
                        playPaperStoreIfNeeded()
                    }
                    composeStartKind = nil
                }
            }
            .onChange(of: sharedCount(.paper)) { count in
                guard composeKind != .paper, !room.contentStore.sample.isPlaying else { return }
                if count < paperVisualCount {
                    paperVisualCount = min(count, TrashBinPhysicsSystem.maximumVisibleCount)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $composeKind) { kind in
                ComposeSheet(kind: kind)
            }
            .sheet(isPresented: $isShowingLifetimeUnlock) {
                LifetimeUnlockView(context: .quotaReached)
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

            HStack(alignment: .top, spacing: HomeRoomMetrics.rowSpacing) {
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
        relationship?.isOwner == true ? "邀请对方" : "查看共享"
    }

    private var relationship: RelationshipLocator? {
        store.viewModel.data.relationship
    }

    private func roomObject(kind: ContainerKind) -> some View {
        let count = displayedCount(kind)
        let waiting = unopenedCount(kind)
        return VStack(spacing: 2) {
            Button {
                handleContainerTap(kind)
            } label: {
                RoomObject(
                    kind: kind,
                    count: count,
                    waiting: waiting,
                    reportsRevealAnchors: true,
                    trackedContentIndex: trackedIndex(kind, count: count),
                    containerFeedback: feedback(for: kind),
                    starPhysics: kind == .star ? room.starPhysics : nil,
                    trashPhysics: kind == .paper ? room.trashPhysics : nil,
                    trashLid: kind == .paper ? room.trashLid : nil
                )
            }
            .buttonStyle(SoftScaleButtonStyle())
            .disabled(room.isBusy)

            Button {
                RitualHaptics.selection()
                if store.viewModel.canAddContent {
                    beginCompose(kind)
                } else {
                    RitualHaptics.warning()
                    isShowingLifetimeUnlock = true
                }
            } label: {
                Text(kind.homeActionTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.tint.opacity(0.82))
                    .frame(height: 28)
            }
            .buttonStyle(SoftScaleButtonStyle())
            .disabled(room.isBusy)
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

    private func credits(_ kind: ContainerKind) -> Int {
        store.viewModel.data.activeCredits(kind: kind)
    }

    private func displayedCount(_ kind: ContainerKind) -> Int {
        if kind == .paper { return paperVisualCount }
        let count = sharedCount(kind)
        guard kind != .star else { return count }
        return liftedKind == kind ? max(0, count - 1) : count
    }

    private func trackedIndex(_ kind: ContainerKind, count: Int) -> Int? {
        let visible = min(max(count, 0), 14)
        guard visible > 0 else { return nil }
        return visible - 1
    }

    private func canOpen(_ kind: ContainerKind) -> Bool {
        room.canPresent(kind: kind, data: store.viewModel.data)
    }

    private func feedback(for kind: ContainerKind) -> ContainerFeedbackTransform {
        if kind == .star, room.starReveal.isPlaying {
            return room.starReveal.sample.container
        }
        if room.reveal.isPlaying, revealingKind == kind {
            return room.reveal.sample.container
        }
        if nudgeKind == kind {
            return ContainerFeedbackTransform(
                rotation: .degrees(Double(failedNudge) * 1.5),
                offsetX: failedNudge * 1.6
            )
        }
        return .identity
    }

    private func handleContainerTap(_ kind: ContainerKind) {
        guard !room.isBusy else { return }
        guard canOpen(kind) else {
            RitualHaptics.warning()
            playFailedNudge(kind)
            return
        }
        playReveal(kind)
    }

    private func playFailedNudge(_ kind: ContainerKind) {
        nudgeKind = kind
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.06)) { failedNudge = 1 }
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.08)) { failedNudge = -1 }
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.06)) { failedNudge = 0 }
            nudgeKind = nil
        }
    }

    private func playReveal(_ kind: ContainerKind) {
        revealingKind = kind
        RitualHaptics.medium()
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            let frames = revealAnchors[kind] ?? RevealAnchorFrames()
            guard room.canPresent(kind: kind, data: store.viewModel.data), frames.hasContainer else {
                revealingKind = nil
                RitualHaptics.warning()
                playFailedNudge(kind)
                return
            }
            guard let item = await store.peekOpenable(kind: kind) else {
                revealingKind = nil
                RitualHaptics.warning()
                playFailedNudge(kind)
                return
            }
            let started = room.beginReveal(
                kind: kind,
                item: item,
                anchors: frames,
                canvasSize: canvasSize,
                safeArea: safeArea,
                reduceMotion: reduceMotion
            )
            if started {
                _ = await store.commitOpen(item)
            } else {
                revealingKind = nil
                RitualHaptics.warning()
                playFailedNudge(kind)
            }
        }
    }

    private func beginCompose(_ kind: ContainerKind) {
        composeStartCount = sharedCount(kind)
        composeStartKind = kind
        composeKind = kind
    }

    private func playPaperStoreIfNeeded() {
        room.storePaperIfNeeded(
            currentCount: sharedCount(.paper),
            previousVisualCount: paperVisualCount,
            composeStartCount: composeStartCount,
            containerFrame: revealAnchors[.paper]?.container ?? .zero,
            canvasSize: canvasSize,
            reduceMotion: reduceMotion,
            onAttached: { paperVisualCount = $0 }
        )
    }

    private func dismissReveal() {
        room.dismissReveal(reduceMotion: reduceMotion)
    }
}

private enum HomeRoomMetrics {
    static let canvas: CGFloat = 156
    static let titleHeight: CGFloat = 23
    static let glyphTitleSpacing: CGFloat = 9
    static let cellHeight: CGFloat = canvas + glyphTitleSpacing + titleHeight
    static let rowSpacing: CGFloat = 28
    static let topPadding: CGFloat = 94
}

private struct RoomObject: View {
    let kind: ContainerKind
    let count: Int
    let waiting: Int
    var reportsRevealAnchors = false
    var trackedContentIndex: Int? = nil
    var containerFeedback: ContainerFeedbackTransform = .identity
    var starPhysics: StarJarPhysicsSystem? = nil
    var trashPhysics: TrashBinPhysicsSystem? = nil
    var trashLid: TrashLidController? = nil

    var body: some View {
        VStack(spacing: HomeRoomMetrics.glyphTitleSpacing) {
            containerGlyph

            Text(kind.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .frame(height: HomeRoomMetrics.titleHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: HomeRoomMetrics.cellHeight, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.openActionTitle)
    }

    private var containerGlyph: some View {
        ZStack {
            ContainerVisual(
                kind: kind,
                count: count,
                style: .room,
                isActive: waiting > 0,
                reportsRevealAnchors: reportsRevealAnchors,
                trackedContentIndex: trackedContentIndex,
                sharedStarPhysics: starPhysics,
                sharedTrashPhysics: trashPhysics,
                sharedTrashLid: trashLid
            )
        }
        .frame(width: HomeRoomMetrics.canvas, height: HomeRoomMetrics.canvas)
        .rotationEffect(containerFeedback.rotation)
        .offset(x: containerFeedback.offsetX)
        .overlay(alignment: .topTrailing) {
            if waiting > 0 {
                Circle()
                    .fill(kind.tint)
                    .frame(width: 8, height: 8)
                    .padding(4)
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
