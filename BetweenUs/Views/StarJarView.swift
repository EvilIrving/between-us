import SwiftUI

struct StarJarView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @EnvironmentObject private var room: RoomWorld
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCompose = false
    @State private var bottleFrame: CGRect = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var safeArea = EdgeInsets()
    @State private var failedNudge: CGFloat = 0
    @State private var isBusy = false
    @State private var knownCount = 0
    @State private var motionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    bottleStage
                        .frame(height: 272)
                        .rotationEffect(bottleRotation)
                        .offset(x: bottleOffsetX)

                    if let unavailableWhisper, !room.starReveal.isPlaying {
                        Text(unavailableWhisper)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                            .frame(height: 20)
                    }

                    ExchangeBalanceView(
                        kind: .star,
                        credits: credits,
                        waiting: unopenedCount
                    )

                    RitualActionToken(
                        kind: .star,
                        title: ContainerKind.star.homeActionTitle
                    ) {
                        showCompose = true
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ContainerRevealOverlay(
                controller: room.starReveal.reveal,
                onDismiss: dismissPreview,
                onRespond: { showCompose = true }
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
        .onPreferenceChange(StarBottleFrameKey.self) { bottleFrame = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            knownCount = min(sharedCount, StarJarMetrics.maxStars)
        }
        .onDisappear {
            motionTask?.cancel()
            motionTask = nil
        }
        .onChange(of: sharedCount) { count in
            guard !showCompose, !room.starReveal.isPlaying else { return }
            if count < knownCount {
                knownCount = min(count, StarJarMetrics.maxStars)
            }
        }
        .onChange(of: room.starReveal.isPlaying) { playing in
            if !playing {
                isBusy = false
            }
        }
        .onChange(of: showCompose) { isShowing in
            if isShowing {
                knownCount = min(sharedCount, StarJarMetrics.maxStars)
                return
            }
            let target = min(sharedCount, StarJarMetrics.maxStars)
            if target > knownCount {
                knownCount = target
            } else if sharedCount > knownCount,
                      room.starPhysics.stars.count < StarJarMetrics.maxStars {
                room.starReveal.spawnNewStar()
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeSheet(kind: .star)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SceneCloseControl(label: "返回首页") {
                dismiss()
            }
            Spacer()
            Text(ContainerKind.star.title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }

    private var bottleStage: some View {
        Button {
            handleBottleTap()
        } label: {
            StarBottleView(
                physics: room.starPhysics,
                count: knownCount,
                reportsRevealAnchors: true,
                animateCountChanges: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || room.starReveal.isPlaying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "%@，里面积累了 %d 件内容。%@".localized(
                ContainerKind.star.title,
                sharedCount,
                (unavailableWhisper ?? "点一下取出星星".localized)
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(room.starReveal.reveal.isShowingCard)
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: .star) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: .star) }
    private var sharedCount: Int { data.count(kind: .star) }
    private var canOpen: Bool {
        room.canPresent(kind: .star, data: data) && !isBusy
    }

    private var unavailableWhisper: String? {
        if credits == 0 { return "先放入一颗星星".localized }
        if unopenedCount == 0 { return "暂无新的星星".localized }
        return nil
    }

    private var bottleRotation: Angle {
        room.starReveal.isPlaying
            ? room.starReveal.sample.container.rotation
            : .degrees(Double(failedNudge) * 1.5)
    }

    private var bottleOffsetX: CGFloat {
        room.starReveal.isPlaying
            ? room.starReveal.sample.container.offsetX
            : failedNudge * 1.6
    }

    private func handleBottleTap() {
        guard !isBusy, !room.starReveal.isPlaying else { return }
        guard canOpen else {
            RitualHaptics.warning()
            playFailedNudge()
            return
        }
        playTake()
    }

    private func playFailedNudge() {
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.06)) { failedNudge = 1 }
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.08)) { failedNudge = -1 }
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.06)) { failedNudge = 0 }
        }
    }

    private func playTake() {
        isBusy = true
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            let frames = RevealAnchorFrames(container: bottleFrame)
            guard room.canPresent(kind: .star, data: data), frames.hasContainer else {
                isBusy = false
                RitualHaptics.warning()
                playFailedNudge()
                return
            }
            guard let item = await store.peekOpenable(kind: .star) else {
                isBusy = false
                RitualHaptics.warning()
                return
            }
            let started = room.beginReveal(
                kind: .star,
                item: item,
                anchors: frames,
                canvasSize: canvasSize,
                safeArea: safeArea,
                reduceMotion: reduceMotion
            )
            if started {
                _ = await store.commitOpen(item)
            } else {
                isBusy = false
                RitualHaptics.warning()
                playFailedNudge()
            }
        }
    }

    private func dismissPreview() {
        room.dismissReveal(reduceMotion: reduceMotion)
    }
}
