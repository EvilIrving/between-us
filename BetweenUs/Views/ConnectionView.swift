import SwiftUI

/// 连接页。
///
/// 这一屏没有物件、没有房间：只有两个人的光，和它们之间的那片场。
///
/// - 还没有空间时，按住这团光就是创建空间。
/// - 空间建好了、对方还没进来时，这团光独自在等：对方靠近会变亮变慢，方向可信时整片场偏向对方那一侧。
/// - 对方真正进来的那一刻，另一团光从画面外围收进来，和自己的并成一团；然后说出结果，最后进入房间。
///
/// 方向和距离只影响光的形状与总量，从来不改变这一屏在做的事——没有对方的时候它也完整。
struct ConnectionView: View {

    enum Mode: Equatable {
        /// 真实流程。
        case live
        /// 从设置里完整看一遍这段动画：不动任何状态，也不进房间。
        case preview
    }

    let mode: Mode

    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var proximity = ProximityLinkService.shared
    @ObservedObject private var nearby = NearbyLinkService.shared

    /// 这一屏正在演哪一段。
    private enum Act: Equatable {
        case resting
        case arriving
        case united
        case entering
    }

    @State private var act: Act = .resting
    @State private var arrival: Double = 0
    @State private var flare: Double = 0
    @State private var united: Double = 0
    @State private var textReveal: Double = 0
    @State private var textRise: Double = 0
    @State private var bloom: Double = 0
    @State private var didEndText = false
    @State private var didEndCeremony = false
    @State private var isSettingsOpen = false
    @State private var previewMoment: ConnectionMoment?
    @State private var previewCloseness: Double = 0
    @State private var previewBias: CGVector = .zero

    private static let holdDuration: TimeInterval = 0.92
    private static let arrivalDuration: TimeInterval = 0.92

    var body: some View {
        ZStack {
            ground

            fieldLayer

            if arrival > 0 {
                ConnectionLight.Arrival(progress: arrival, bias: bias)
            }

            if flare > 0 {
                ConnectionLight.Flare(progress: flare)
            }

            stage

            if bloom > 0 {
                ConnectionLight.Bloom(progress: bloom)
            }
        }
        .background(AppTheme.dusk.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if mode == .preview {
                SceneCloseControl { dismiss() }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $isSettingsOpen) { SettingsView() }
        .onAppear { Task { await appeared() } }
        .onDisappear { Task { await store.endWatchingPartner() } }
        .onChange(of: moment?.id) { _, id in
            // 预览自己排这一段，不让状态变化插进来。
            guard mode == .live else { return }
            if id == nil { recede() } else { Task { await playArrival() } }
        }
        .onChange(of: moment?.isSettled) { _, settled in
            guard settled == true else { return }
            Task { await endText() }
        }
        .onChange(of: line) { _, newLine in
            // 光的变化不能只靠看：这一句是状态本身，读屏要能听到。
            guard act != .resting, !newLine.isEmpty else { return }
            AccessibilityNotification.Announcement(T(key: newLine)).post()
        }
        .onChange(of: store.viewModel.data.relationship?.zoneName) { _, zoneName in
            // 刚刚创建完空间：从这一刻起才有人在等，才开始盯着对方。
            guard zoneName != nil else { return }
            Task { await store.beginWatchingPartner() }
        }
    }

    // MARK: - 分层

    /// 这一页的地：不是黑，是深下去的暮色，光才有地方亮。
    private var ground: some View {
        ZStack {
            AppTheme.dusk

            RadialGradient(
                colors: [Color(red: 0.26, green: 0.21, blue: 0.17).opacity(0.62), .clear],
                center: UnitPoint(x: 0.5, y: 0.47),
                startRadius: 0,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 光这一层。还没有空间的时候，按住它就是在创建空间——进度长在光本身上。
    @ViewBuilder
    private var fieldLayer: some View {
        if canHoldToCreate {
            HoldToCompleteSurface(
                duration: Self.holdDuration,
                isEnabled: !store.viewModel.isPerformingAction,
                isWorking: store.viewModel.isPerformingAction,
                onComplete: { Task { await store.createRelationship() } }
            ) { progress, isPressing in
                ConnectionLight.Field(
                    params: field(holdProgress: Double(progress)),
                    isRunning: isRunning
                )
                .scaleEffect(isPressing ? 0.994 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(T("按住创建空间"))
            .accessibilityHint(T("持续按住完成"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await store.createRelationship() } }
        } else {
            ConnectionLight.Field(params: field(holdProgress: 0), isRunning: isRunning)
        }
    }

    @ViewBuilder
    private var stage: some View {
        if act == .resting {
            restingEntries
        } else if act != .entering {
            ceremonyLine
        }
    }

    /// 融合之后那句话。从自己的两条边往中间收进来，然后放大、淡出。
    private var ceremonyLine: some View {
        Text(line)
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 1.0, green: 0.96, blue: 0.90))
            .shadow(color: Color.black.opacity(0.36), radius: 14, y: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 26)
            .fixedSize()
            .mask(revealMask)
            .scaleEffect(1 + 0.5 * textRise)
            .opacity(0.95 * (1 - 0.4 * textRise))
            .offset(y: 84)
            .contentTransition(.opacity)
            .animation(AppMotion.settle, value: line)
            .accessibilityLabel(T(key: line))
    }

    /// 从两条边开始出现：两端先亮，中间最后合上。
    private var revealMask: some View {
        GeometryReader { proxy in
            let half = max(proxy.size.width, 1) / 2
            HStack(spacing: 0) {
                Rectangle().frame(width: half * textReveal)
                Spacer(minLength: 0)
                Rectangle().frame(width: half * textReveal)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// 还没有进入融合之前这一页上的东西：一句话，加一个出口。
    private var restingEntries: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(T(key: stageTitle))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.94, blue: 0.86).opacity(0.60))
                .frame(height: 20)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: AppMotion.modeDuration), value: stageTitle)

            Spacer(minLength: 0)
                .frame(maxHeight: 232)

            HStack(spacing: 12) {
                if store.viewModel.data.relationship == nil, mode == .live {
                    QuietPill(
                        title: "本机预览",
                        tone: .muted,
                        ground: .dusk,
                        accessibilityHint: "进入本机预览"
                    ) {
                        Task { await store.enterLocalPreview() }
                    }
                }

                if store.viewModel.showsInviteEntry, mode == .live {
                    QuietPill(
                        title: "邀请对方",
                        tone: .action,
                        ground: .dusk,
                        accessibilityHint: "把邀请交给对方"
                    ) {
                        Task { await store.presentInvite() }
                    }
                }

                if store.viewModel.data.relationship != nil, mode == .live {
                    QuietPill(
                        title: "设置",
                        tone: .muted,
                        ground: .dusk,
                        accessibilityHint: "打开设置"
                    ) {
                        isSettingsOpen = true
                    }
                }
            }
            .disabled(store.viewModel.isPerformingAction)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 输入

    private var isRunning: Bool {
        scenePhase == .active && act != .entering
    }

    private var canHoldToCreate: Bool {
        mode == .live
            && store.viewModel.data.relationship == nil
            && !isMakingContact
            && act == .resting
    }

    /// 光在管着这一屏的时候，按住就不再是「创建」：这一刻它属于两个人相认。
    private var isMakingContact: Bool {
        proximity.didConnect || proximity.isJoining || proximity.claim > 0 || proximity.isNear
    }

    private var moment: ConnectionMoment? {
        mode == .preview ? previewMoment : store.viewModel.connectionMoment
    }

    private var line: String {
        guard let moment else { return "" }
        switch (moment.isCreator, moment.isSettled) {
        case (true, false): return T("正在创建空间")
        case (true, true): return T("空间已经创建好")
        case (false, false): return T("正在加入空间")
        case (false, true): return T("已经加入空间")
        }
    }

    /// 对方有多近：有 UWB 就用米，没有就用蓝牙信号强度。
    private var closeness: Double {
        if mode == .preview { return previewCloseness }
        if let distance = nearby.distance {
            return min(1, max(0, 1 - distance / 6.0))
        }
        return proximity.approach
    }

    private var bias: CGVector {
        mode == .preview ? previewBias : nearby.bias
    }

    private func field(holdProgress: Double) -> ConnectionLight.Params {
        let isUnited = act == .united || act == .entering
        let distanceFactor = isUnited ? 1 : closeness
        let base = isUnited ? 1 : min(1, 0.40 + 0.55 * distanceFactor)

        return ConnectionLight.Params(
            closeness: distanceFactor,
            isUnited: isUnited,
            bias: bias,
            intensity: min(1, base + 0.55 * holdProgress + 0.55 * united),
            coreScale: 1 + 0.6 * holdProgress + 0.55 * united
        )
    }

    /// 一句话说清现在该谁做什么。距离自己变化时不产生判决式的说法。
    private var stageTitle: String {
        guard store.viewModel.data.relationship != nil else {
            if proximity.didConnect { return "连上了" }
            if proximity.isJoining { return "正在加入" }
            if proximity.claim > 0 { return "正在连上" }
            if proximity.isNear { return "对方就在旁边" }
            return store.viewModel.isPerformingAction ? "正在创建" : "按住创建空间"
        }
        return proximity.didConnect ? "正在连接" : "等对方进来"
    }

    // MARK: - 动作

    private func appeared() async {
        RitualHaptics.prepare()
        nearby.start()

        if mode == .preview {
            await runPreview()
            return
        }
        await store.beginWatchingPartner()
        if store.viewModel.connectionMoment != nil {
            await playArrival()
        }
    }

    /// 另一团光从画面外围收进来，碰到一起。
    @MainActor
    private func playArrival() async {
        guard act == .resting, arrival == 0 else { return }
        act = .arriving
        RitualHaptics.soft()

        withAnimation(.timingCurve(0.20, 0.86, 0.24, 1.0, duration: Self.arrivalDuration)) {
            arrival = 1
        }
        try? await Task.sleep(for: .seconds(Self.arrivalDuration))
        guard act == .arriving else { return }

        // 碰到了。这一下是整段里唯一一次用满的反馈。
        RitualHaptics.success()
        withAnimation(.timingCurve(0.14, 0.92, 0.22, 1.0, duration: 0.78)) { flare = 1 }
        withAnimation(.easeInOut(duration: 0.24)) { united = 1 }

        try? await Task.sleep(for: .seconds(0.24))
        guard act == .arriving else { return }
        act = .united
        withAnimation(.spring(response: 0.50, dampingFraction: 0.84)) { textReveal = 1 }

        if moment?.isSettled == true {
            await endText()
        }
    }

    /// 空间确认了：那句话站一会儿，然后放大、消失，光涨满。
    @MainActor
    private func endText() async {
        guard act == .united, !didEndText else { return }
        didEndText = true

        try? await Task.sleep(for: .seconds(1.15))
        guard act == .united else { return }

        withAnimation(.easeIn(duration: 0.46)) { textRise = 1 }
        try? await Task.sleep(for: .seconds(0.40))
        guard act == .united, !didEndCeremony else { return }

        didEndCeremony = true
        act = .entering
        withAnimation(.easeIn(duration: 0.52)) { bloom = 1 }
        try? await Task.sleep(for: .seconds(0.46))

        if mode == .preview {
            recede()
        } else {
            await store.completeConnectionCeremony()
        }
    }

    /// 这一次没成：光退回去，页面回到等人的样子，不留一句判决。
    private func recede() {
        withAnimation(.easeOut(duration: 0.5)) {
            arrival = 0
            flare = 0
            united = 0
            textReveal = 0
            textRise = 0
            bloom = 0
        }
        act = .resting
        didEndText = false
        didEndCeremony = false
        previewMoment = nil
    }

    /// 预览：先把靠近和方向走一遍，再把融合演完。
    @MainActor
    private func runPreview() async {
        try? await Task.sleep(for: .seconds(0.7))
        previewMoment = ConnectionMoment(isCreator: true, isSettled: false)

        withAnimation(.easeInOut(duration: 1.5)) { previewCloseness = 1 }
        withAnimation(.easeInOut(duration: 0.9)) { previewBias = CGVector(dx: 1, dy: 0) }
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.easeInOut(duration: 0.9)) { previewBias = .zero }
        try? await Task.sleep(for: .seconds(1.0))

        await playArrival()
        try? await Task.sleep(for: .seconds(1.3))
        previewMoment?.isSettled = true
    }
}

/// 一次连接正在发生：谁的这一段、空间是不是已经确认了。
struct ConnectionMoment: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// 这一侧是发起者（创建空间的一方）。
    var isCreator: Bool
    /// 空间已经在 CloudKit 上确认可用。
    var isSettled: Bool
}
