import SwiftUI

struct StarJarView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var reveal = ContainerRevealAnimationController()

    @State private var showCompose = false
    @State private var bottleFrame: CGRect = .zero
    @State private var sittingCharm: StarCharm?
    @State private var motionCharm: StarCharm?
    @State private var canvasSize: CGSize = .zero
    @State private var safeArea = EdgeInsets()
    @State private var revealAnchors: [ContainerKind: RevealAnchorFrames] = [:]
    @State private var failedNudge: CGFloat = 0

    @State private var drop: CGFloat = 1
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
                        .frame(height: 320)
                        .rotationEffect(bottleRotation)
                        .offset(x: bottleOffsetX)

                    if let unavailableWhisper, !reveal.isPlaying {
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

            StarDropStage(
                bottleFrame: bottleFrame,
                charm: motionCharm,
                drop: drop,
                showsFrontStar: showsDropStar
            )

            ContainerRevealOverlay(
                controller: reveal,
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
        .onPreferenceChange(RevealAnchorKey.self) { revealAnchors = $0 }
        .onPreferenceChange(StarBottleFrameKey.self) { bottleFrame = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            knownCount = sharedCount
            if sittingCharm == nil, sharedCount > 0 {
                sittingCharm = StarCharm.random()
            }
        }
        .onDisappear {
            motionTask?.cancel()
            motionTask = nil
            reveal.reset()
        }
        .onChange(of: sharedCount) { count in
            if count == 0 {
                sittingCharm = nil
            } else if sittingCharm == nil, !reveal.isPlaying, !isBusy {
                sittingCharm = StarCharm.random()
            }
        }
        .onChange(of: reveal.sample.showsToken) { showing in
            if showing {
                sittingCharm = nil
            } else if reveal.isPlaying, sittingCharm == nil, sharedCount > 0 {
                sittingCharm = StarCharm.random()
            }
        }
        .onChange(of: reveal.isPlaying) { playing in
            if !playing {
                finishReveal()
            }
        }
        .onChange(of: showCompose) { isShowing in
            if isShowing {
                knownCount = sharedCount
                return
            }
            let added = sharedCount > knownCount
            knownCount = sharedCount
            if added {
                playDrop()
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
                charms: backCharm.map { [$0] } ?? [],
                drop: drop,
                neckScale: neckScale,
                reportsRevealAnchors: true,
                idleMotion: !isBusy && !reveal.isPlaying
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || reveal.isPlaying)
        .onPreferenceChange(StarBottleFrameKey.self) { bottleFrame = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "%@，里面积累了 %d 件内容。%@".localized(
                ContainerKind.star.title,
                sharedCount,
                (unavailableWhisper ?? "点一下取出星星".localized)
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(reveal.isShowingCard)
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: .star) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: .star) }
    private var sharedCount: Int { data.count(kind: .star) }
    private var canOpen: Bool {
        credits > 0 && unopenedCount > 0 && !isBusy && !reveal.isPlaying
    }

    private var unavailableWhisper: String? {
        if credits == 0 { return "先放入一颗星星".localized }
        if unopenedCount == 0 { return "暂无新的星星".localized }
        return nil
    }

    private var backCharm: StarCharm? {
        if drop < 0.99, drop > 0.58 {
            return motionCharm ?? sittingCharm
        }
        if reveal.sample.showsToken { return nil }
        if reveal.isPlaying, reveal.sample.stage != .containerFeedback, reveal.sample.stage != .idle {
            return nil
        }
        return sittingCharm
    }

    private var neckScale: CGSize {
        StarDropLayout.neckScale(drop: drop)
    }

    private var showsDropStar: Bool {
        drop < 0.58
    }

    private var bottleRotation: Angle {
        reveal.isPlaying ? reveal.sample.container.rotation : .degrees(Double(failedNudge) * 1.5)
    }

    private var bottleOffsetX: CGFloat {
        reveal.isPlaying ? reveal.sample.container.offsetX : failedNudge * 1.6
    }

    private func handleBottleTap() {
        guard !isBusy, !reveal.isPlaying else { return }
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

    private func playDrop() {
        motionTask?.cancel()
        let charm = StarCharm.random()
        motionCharm = charm
        sittingCharm = nil
        drop = 0
        isBusy = true
        RitualHaptics.medium()

        motionTask = Task { @MainActor in
            if reduceMotion {
                drop = 1
                sittingCharm = charm
                motionCharm = nil
                isBusy = false
                return
            }
            withAnimation(.timingCurve(0.42, 0.00, 0.88, 0.18, duration: 0.38)) {
                drop = 1
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            sittingCharm = charm
            motionCharm = nil
            isBusy = false
        }
    }

    private func playTake() {
        isBusy = true
        RitualHaptics.medium()
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            let item = await store.drawStar()
            guard !Task.isCancelled else { return }
            guard let item else {
                isBusy = false
                RitualHaptics.warning()
                return
            }

            let charm = sittingCharm ?? StarCharm.random()
            motionCharm = charm
            drop = 1

            let frames = revealAnchors[.star] ?? RevealAnchorFrames()
            let container = frames.hasContainer ? frames.container : bottleFrame
            let contentStart = frames.hasContent
                ? frames.contentCenter
                : ContainerRevealAnchors.point(CGPoint(x: 0.50, y: 0.62), in: container)
            let exit = frames.hasExit
                ? frames.exitCenter
                : ContainerRevealAnchors.point(ContainerRevealAnchors.exitUnit(for: .star), in: container)
            let contentSize = frames.hasContent
                ? frames.content.size
                : CGSize(width: max(40, container.width * 0.44), height: max(40, container.width * 0.44))

            let canvas = canvasSize.width > 1 ? canvasSize : UIScreen.main.bounds.size
            let (input, instance) = ContainerRevealLayout.makeInput(
                kind: .star,
                containerFrame: container,
                exitAnchor: exit,
                contentStart: contentStart,
                contentSize: contentSize,
                canvasSize: canvas,
                safeArea: safeArea,
                reduceMotion: reduceMotion,
                seed: charm.series * 10 + charm.mood
            )
            let token = RevealContentToken(
                type: .star,
                imageName: charm.imageName,
                seed: charm.mood,
                visualSize: contentSize
            )
            reveal.play(input: input, instance: instance, token: token, item: item)
        }
    }

    private func dismissPreview() {
        guard reveal.sample.cardInteractive || reduceMotion else { return }
        reveal.dismiss()
    }

    private func finishReveal() {
        motionCharm = nil
        drop = 1
        sittingCharm = sharedCount > 0 ? StarCharm.random() : nil
        isBusy = false
        motionTask = nil
    }
}

private struct StarDropStage: View {
    let bottleFrame: CGRect
    let charm: StarCharm?
    let drop: CGFloat
    let showsFrontStar: Bool

    var body: some View {
        GeometryReader { canvas in
            let hole = CGPoint(x: bottleFrame.midX, y: bottleFrame.minY + bottleFrame.height * 0.62)
            let sky = CGPoint(x: bottleFrame.midX, y: bottleFrame.minY - 108)
            let t = min(max(drop, 0), 1)
            let center = CGPoint(
                x: sky.x + (hole.x - sky.x) * t,
                y: sky.y + (hole.y - sky.y) * t
            )
            let size = max(40, bottleFrame.width * 0.44)
            let neck = StarDropLayout.neckScale(drop: drop)

            ZStack {
                if let charm, showsFrontStar {
                    StarCharmImage(charm: charm)
                        .frame(width: size, height: size)
                        .scaleEffect(x: neck.width, y: neck.height)
                        .rotationEffect(.degrees(18 - 22 * Double(t)))
                        .position(center)
                        .allowsHitTesting(false)
                }
            }
        }
        .allowsHitTesting(drop < 0.99)
    }
}
