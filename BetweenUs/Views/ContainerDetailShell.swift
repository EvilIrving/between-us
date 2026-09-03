import SwiftUI

struct ContainerDetailShell<Content: View>: View {
    let kind: ContainerKind
    let title: String
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        kind: ContainerKind,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SceneCloseControl(label: "返回首页") {
                            dismiss()
                        }

                        Spacer()

                        Text(title.localized)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Color.clear
                            .frame(width: 42, height: 42)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    content
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Shared state and interaction shell for capsule and paper scenes.
struct ContainerRitualScene: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var reveal = ContainerRevealAnimationController()

    @State private var showCompose = false
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?
    @State private var canvasSize: CGSize = .zero
    @State private var safeArea = EdgeInsets()
    @State private var revealAnchors: [ContainerKind: RevealAnchorFrames] = [:]
    @State private var liftedContent = false

    var body: some View {
        ZStack {
            ContainerDetailShell(
                kind: kind,
                title: kind.title
            ) {
                VStack(spacing: 14) {
                    ContainerHoldStage(
                        kind: kind,
                        count: displayedCount,
                        duration: AppMotion.holdDuration(for: kind),
                        isEnabled: canOpen,
                        isWorking: isOpening || reveal.isPlaying,
                        title: hasOpenableItem ? kind.openActionTitle : unavailableWhisper,
                        reportsRevealAnchors: true,
                        trackedContentIndex: trackedContentIndex,
                        containerFeedback: reveal.sample.container,
                        onComplete: openNext
                    )
                    .frame(height: 272)

                    ExchangeBalanceView(
                        kind: kind,
                        credits: credits,
                        waiting: unopenedCount
                    )

                    RitualActionToken(
                        kind: kind,
                        title: kind.homeActionTitle
                    ) {
                        showCompose = true
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            }

            ContainerRevealOverlay(
                controller: reveal,
                onDismiss: dismissReveal,
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
        .onChange(of: reveal.sample.showsToken) { showing in
            liftedContent = showing
        }
        .onChange(of: reveal.isPlaying) { playing in
            if !playing {
                liftedContent = false
                isOpening = false
            }
        }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            isOpening = false
            reveal.reset()
        }
        .sheet(isPresented: $showCompose) {
            ComposeSheet(kind: kind)
        }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: kind) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: kind) }
    private var sharedCount: Int { data.count(kind: kind) }
    private var displayedCount: Int {
        liftedContent ? max(0, sharedCount - 1) : sharedCount
    }
    private var trackedContentIndex: Int? {
        let visible = min(max(displayedCount, 0), 14)
        guard visible > 0 else { return nil }
        return visible - 1
    }
    private var hasOpenableItem: Bool { credits > 0 && unopenedCount > 0 }
    private var canOpen: Bool { hasOpenableItem && !isOpening && !reveal.isPlaying }

    private var unavailableWhisper: String {
        if credits == 0 { return kind.creditRequirementTitle }
        return kind.emptyWaitingTitle
    }

    private func openNext() {
        guard canOpen else { return }
        isOpening = true
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            let item = await store.openNext(kind: kind)
            guard !Task.isCancelled else { return }
            openingTask = nil
            guard let item else {
                isOpening = false
                RitualHaptics.warning()
                return
            }
            playReveal(item: item)
        }
    }

    private func playReveal(item: SecretItem) {
        let frames = revealAnchors[kind] ?? RevealAnchorFrames()
        let container = frames.hasContainer
            ? frames.container
            : CGRect(origin: .zero, size: canvasSize)
        let slots = ContainerRevealAnchors.contentSlots(for: kind)
        let slot = slots[min(max((trackedContentIndex ?? 0), 0), slots.count - 1)]
        let contentStart = frames.hasContent
            ? frames.contentCenter
            : ContainerRevealAnchors.point(slot, in: container)
        let exit = frames.hasExit
            ? frames.exitCenter
            : ContainerRevealAnchors.point(ContainerRevealAnchors.exitUnit(for: kind), in: container)
        let contentSize = frames.hasContent
            ? frames.content.size
            : ContainerRevealAnchors.contentSize(for: kind, in: container)

        let canvas = canvasSize.width > 1 ? canvasSize : UIScreen.main.bounds.size
        let (input, instance) = ContainerRevealLayout.makeInput(
            kind: kind,
            containerFrame: container,
            exitAnchor: exit,
            contentStart: contentStart,
            contentSize: contentSize,
            canvasSize: canvas,
            safeArea: safeArea,
            reduceMotion: reduceMotion,
            seed: item.id.hashValue
        )
        let token = RevealContentToken(
            type: ContentTokenType(kind),
            imageName: nil,
            seed: trackedContentIndex ?? abs(item.id.hashValue % 11),
            visualSize: contentSize
        )
        reveal.play(input: input, instance: instance, token: token, item: item)
    }

    private func dismissReveal() {
        guard reveal.sample.cardInteractive || reduceMotion else { return }
        reveal.dismiss()
    }
}

private struct ContainerHoldStage: View {
    let kind: ContainerKind
    let count: Int
    let duration: TimeInterval
    let isEnabled: Bool
    let isWorking: Bool
    let title: String
    var reportsRevealAnchors = false
    var trackedContentIndex: Int? = nil
    var containerFeedback: ContainerFeedbackTransform = .identity
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HoldToCompleteSurface(
            duration: duration,
            isEnabled: isEnabled,
            isWorking: isWorking,
            onComplete: onComplete
        ) { progress, isPressing in
            let motionProgress = reduceMotion ? 0 : min(max(progress, 0), 1)

            VStack(spacing: 8) {
                ZStack {
                    AppTheme.glow(for: kind)
                        .scaleEffect(1 + motionProgress * 0.20)
                        .opacity(
                            isPressing || isWorking
                                ? 1
                                : (isEnabled ? 0.70 : 0.34)
                        )

                    ContainerVisual(
                        kind: kind,
                        count: count,
                        style: .detail,
                        interactionProgress: motionProgress,
                        isActive: isPressing || isWorking,
                        reportsRevealAnchors: reportsRevealAnchors,
                        trackedContentIndex: trackedContentIndex
                    )
                    .padding(.horizontal, kind == .capsule ? 18 : 36)
                    .padding(.vertical, 8)
                    .brightness(motionProgress * 0.035)
                    .shadow(
                        color: kind.tint.opacity(motionProgress * 0.24),
                        radius: motionProgress * 16,
                        y: motionProgress * 4
                    )
                }
                .scaleEffect(reduceMotion ? 1 : 1 - motionProgress * 0.045)
                .offset(y: reduceMotion ? 0 : motionProgress * 6)
                .rotationEffect(containerFeedback.rotation)
                .offset(x: containerFeedback.offsetX)
                .animation(.easeOut(duration: AppMotion.pressDuration), value: isPressing)

                ShimmeringHoldLabel(
                    text: title,
                    tint: kind.tint,
                    baseStyle: labelStyle(progress: progress),
                    isShimmering: isPressing && !reduceMotion
                )
                .offset(y: promptOffset)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("%@，里面积累了 %d 件内容。%@".localized(kind.title, count, title.localized))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("持续按住完成，提前松开取消".localized)
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            onComplete()
        }
    }

    private func labelStyle(progress: CGFloat) -> LinearGradient {
        let restingColor = isEnabled
            ? AppTheme.secondaryText.opacity(0.42)
            : AppTheme.secondaryText.opacity(0.54)
        let filledColor = isWorking ? kind.tint : kind.tint.opacity(0.96)
        let fill = isWorking ? 1 : min(max(progress, 0), 1)

        if !isEnabled || fill == 0 {
            return LinearGradient(
                colors: [restingColor, restingColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        if fill == 1 {
            return LinearGradient(
                colors: [filledColor, filledColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            stops: [
                .init(color: filledColor, location: 0),
                .init(color: filledColor, location: fill),
                .init(color: restingColor, location: min(fill + 0.018, 1)),
                .init(color: restingColor, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var promptOffset: CGFloat {
        switch kind {
        case .star: return -34
        case .capsule: return -20
        case .paper: return -26
        }
    }
}

private struct ShimmeringHoldLabel: View {
    let text: String
    let tint: Color
    let baseStyle: LinearGradient
    let isShimmering: Bool

    var body: some View {
        Text(text.localized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(baseStyle)
            .overlay {
                if isShimmering {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        GeometryReader { proxy in
                            let width = max(28, proxy.size.width * 0.42)
                            let cycle = timeline.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1.75) / 1.75

                            LinearGradient(
                                colors: [
                                    .clear,
                                    tint.opacity(0.16),
                                    Color.white.opacity(0.94),
                                    tint.opacity(0.26),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: width)
                            .offset(x: CGFloat(cycle) * (proxy.size.width + width) - width)
                            .blendMode(.screen)
                        }
                        .mask {
                            Text(text.localized)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .frame(height: 20)
    }
}

struct ExchangeBalanceView: View {
    let kind: ContainerKind
    let credits: Int
    let waiting: Int

    var body: some View {
        HStack(spacing: 0) {
            BalanceValue(value: credits, label: "可打开", tint: kind.tint)
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 34)
            BalanceValue(value: waiting, label: "待打开", tint: kind.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("可打开 %d 次，还有 %d 件内容等你打开".localized(credits, waiting))
    }
}

private struct BalanceValue: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? tint : AppTheme.secondaryText.opacity(0.48))
            Text(label.localized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("%@ %d 件".localized(label.localized, value))
    }
}

struct RitualDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
            Text(text.localized)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.46))
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}
