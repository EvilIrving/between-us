import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var proximity = ProximityLinkService.shared

    @State private var isDrawerOpen = false
    @State private var isSettingsOpen = false
    @State private var composeKind: ContainerKind?
    @State private var openedItem: SecretItem?
    @State private var isOpening = false
    // 首页这一屏的上推信号：三个物件共用，读数不触发界面重绘。
    @State private var jolt = RoomJolt()
    // 设备姿态信号：横过来或晃手机时容器里的东西跟着动，同样不经过界面状态。
    @State private var motion = DeviceMotionSource()
    // 姿态反馈的开关档位；设置页改的就是它。
    @AppStorage(DeviceMotionMode.storageKey) private var deviceMotionModeRaw = DeviceMotionMode.standard.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientRoomBackground()

                // 对方靠近时，整间屋子跟着亮一点，光落在矮桌那一带。
                ProximityLight.Ambient(
                    intensity: proximity.isNear ? 1 : proximity.approach,
                    center: UnitPoint(x: 0.715, y: 0.169)
                )
                .opacity(proximity.mode == .waiting ? 1 : 0)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        sharedRoom
                            .padding(.bottom, 26)
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .background {
                        // 只读这一屏被向上推动的位移，不认手势、不改触摸竞争。
                        RoomJoltProbe(jolt: jolt, isActive: isRoomRunning)
                            .frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                    }
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
            .navigationDestination(isPresented: $isDrawerOpen) { MyDepositsView() }
            .navigationDestination(isPresented: $isSettingsOpen) { SettingsView() }
            .sheet(item: $composeKind) { kind in
                ComposeSheet(kind: kind)
            }
            .onAppear {
                RitualHaptics.prepare()
                motion.setActive(isRoomRunning)
            }
            .onChange(of: isRoomRunning) { _, running in motion.setActive(running) }
            .onDisappear { motion.setActive(false) }
        }
    }

    // 三个物件在窗口里各占一个物理场景。首页被推走一层、弹着创作页、内容页或共享面板时，
    // 它们既看不见也点不到，没有理由继续逐帧渲染和跑物理。
    private var isRoomRunning: Bool {        scenePhase == .active
            && !isDrawerOpen
            && !isSettingsOpen
            && composeKind == nil
            && openedItem == nil
            && store.viewModel.shareSheet == nil
    }

    private var deviceMotionSettings: DeviceMotionSettings {
        (DeviceMotionMode(rawValue: deviceMotionModeRaw) ?? .standard).settings
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("耳语")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            // 邀请只在还没等到对方时占一个位置，和抽屉、设置排在一起；两个人在同一个空间里就撤掉。
            if store.viewModel.showsInviteEntry {
                Button {
                    RitualHaptics.selection()
                    Task {
                        await store.presentInvite()
                    }
                } label: {
                    HomeTextControl(title: "邀请对方")
                }
                .buttonStyle(SoftScaleButtonStyle())
                .disabled(store.viewModel.isPerformingAction)
            }

            Button {
                isDrawerOpen = true
            } label: {
                HomeCornerControl(systemName: "archivebox", title: "抽屉")
            }
            .buttonStyle(SoftScaleButtonStyle())

            Button {
                isSettingsOpen = true
            } label: {
                HomeCornerControl(systemName: "slider.horizontal.3", title: "设置")
            }
            .buttonStyle(SoftScaleButtonStyle())
        }
    }

    // 房间是一块固定比例的画布：星星瓶、胶囊盒、纸团篓按阶梯锹开，
    // 每件东西在画布里的位置和宽度都用归一化坐标给出，换屏幕只等比缩放。
    private var sharedRoom: some View {
        GeometryReader { canvas in
            let light = waitingLightParams
            let geometry = WaitingLightGeometry(canvas: canvas.size)

            ZStack {
                // 等对方靠近时，桌上的灯是亮着的：光池落在桌面，瓶身压在光上。
                if let light {
                    ProximityLight.Backdrop(params: light, side: geometry.side)
                        .frame(width: geometry.side, height: geometry.side)
                        .position(geometry.center)
                }

                ForEach(ContainerKind.allCases) { kind in
                    let slot = HomeRoomMetrics.slot(for: kind)
                    roomObject(kind: kind)
                        .frame(width: canvas.size.width * slot.width)
                        .position(
                            x: canvas.size.width * slot.center.x,
                            y: canvas.size.height * slot.center.y
                        )
                }

                // 透过玻璃的光画在物件之上：它被瓶子的轮廓裁住，不会碰到另外两只。
                if let light {
                    ProximityLight.Glass(params: light, side: geometry.side)
                        .frame(width: geometry.side, height: geometry.side)
                        .position(geometry.center)
                }
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .aspectRatio(HomeRoomMetrics.roomAspect, contentMode: .fit)
        .frame(maxWidth: 430)
        .padding(.top, HomeRoomMetrics.topPadding)
    }

    /// 空间已经建好、对方还没进来：桌上的灯一直亮着，对方靠近时它会跟着变亮。
    private var waitingLightParams: ProximityLight.Params? {
        guard isRoomRunning, proximity.mode == .waiting else { return nil }
        return ProximityLight.Params(
            approach: proximity.approach,
            isNear: proximity.isNear,
            fill: proximity.didConnect ? 1 : proximity.claim,
            baseline: 0.16,
            isClaiming: proximity.didConnect
        )
    }

    /// 星星瓶的画面在房间里的位置与大小。瓶子位图是一个正方形，永远居中于自己的舞台，
    /// 所以只要按舞台宽度算出这张正方形的边长，光就永远和玻璃配准。
    private struct WaitingLightGeometry {
        let side: CGFloat
        let center: CGPoint

        init(canvas: CGSize) {
            let slot = HomeRoomMetrics.slot(for: .star)
            let stageWidth = canvas.width * slot.width
            let sceneAspect = ResourceCatalog.starJar.container.mapping.sceneSize
            side = stageWidth * (sceneAspect.height / sceneAspect.width)
            center = CGPoint(
                x: canvas.width * slot.center.x,
                y: canvas.height * slot.center.y
            )
        }
    }

    private func roomObject(kind: ContainerKind) -> some View {
        // 房间里的物件就是真实内容的物理现场：点这只物件，打开下一份。
        ContainerPhysicsStage(
            kind: kind,
            items: store.viewModel.data.allItems(kind: kind),
            jolt: jolt,
            motion: motion,
            motionSettings: deviceMotionSettings,
            isPaused: !isRoomRunning,
            onTap: { openNext(kind) }
        )
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
    // 画布就是屏幕宽度乘上这个高宽比。
    static let roomAspect: CGFloat = 402.0 / 668.5
    static let topPadding: CGFloat = 16

    struct Slot {
        var center: CGPoint // 画布内的归一化中心。
        var width: CGFloat // 占画布宽度的比例，高度由各自场景比例决定。
    }

    static func slot(for kind: ContainerKind) -> Slot {
        switch kind {
        case .star: return Slot(center: CGPoint(x: 0.715, y: 0.169), width: 0.388)
        case .capsule: return Slot(center: CGPoint(x: 0.291, y: 0.500), width: 0.495)
        case .paper: return Slot(center: CGPoint(x: 0.754, y: 0.808), width: 0.415)
        }
    }
}

private struct HomeCornerControl: View {
    let systemName: String
    let title: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText.opacity(0.66))
            .frame(width: 40, height: 40)
            .homeControlPill()
            .contentShape(Capsule())
            .accessibilityLabel(T(key: title))
    }
}

// 右上角唯一的文字控件：和两枚图标共用同一副胶囊外形，只把内容换成文字。
private struct HomeTextControl: View {
    let title: String

    var body: some View {
        Text(T(key: title))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .homeControlPill()
            .contentShape(Capsule())
    }
}

private extension View {
    func homeControlPill() -> some View {
        background(Color.white.opacity(0.36))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.60), lineWidth: 1) }
    }
}

// 把宿主 ScrollView 每帧的位移换算成晃瓶力度：只读 contentOffset，不参与触摸判定，
// 也不经过 SwiftUI 状态，因此滚动时不会重建这一屏和三个物理舞台。
private struct RoomJoltProbe: UIViewRepresentable {
    let jolt: RoomJolt
    let isActive: Bool

    func makeUIView(context: Context) -> UIView { RoomJoltProbeView(jolt: jolt) }
    func updateUIView(_ view: UIView, context: Context) {
        (view as? RoomJoltProbeView)?.setActive(isActive)
    }
}

private final class RoomJoltProbeView: UIView {
    private let jolt: RoomJolt
    private var link: CADisplayLink?
    private var lastOffsetY: CGFloat?
    private var lastTick: CFTimeInterval?
    private weak var scrollView: UIScrollView?
    private var isActive = true

    init(jolt: RoomJolt) {
        self.jolt = jolt
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard isActive, window != nil, let scrollView = enclosingScrollView() else {
            stop()
            return
        }
        self.scrollView = scrollView
        start()
    }

    // 首页被推走一层时停掉探针：没有滚动可读，也不该留着每帧回调。
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active, window != nil, scrollView != nil {
            start()
        } else {
            stop()
            jolt.reset()
        }
    }

    private func enclosingScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView { return scrollView }
            candidate = view.superview
        }
        return nil
    }

    private func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        lastOffsetY = nil
        lastTick = nil
    }

    // 每帧把这一屏的位移、速度和「手势还在不在」交给同一条信号。
    @objc private func tick(_ link: CADisplayLink) {
        guard let scrollView else { return }
        let offsetY = scrollView.contentOffset.y
        let dt = lastTick.map { min(max(link.timestamp - $0, 1.0 / 240.0), 0.25) } ?? (1.0 / 60.0)
        let delta = lastOffsetY.map { offsetY - $0 } ?? 0
        lastOffsetY = offsetY
        lastTick = link.timestamp
        // 惯性滚动也算手势延续：上推的力度跟得住屏，不会在松手瞬间断掉。
        let isGesturing = scrollView.isDragging || scrollView.isDecelerating
        jolt.update(delta: delta,
                    speed: min(max(delta / CGFloat(dt), -4_000), 4_000),
                    isGesturing: isGesturing,
                    dt: dt)
    }
}
