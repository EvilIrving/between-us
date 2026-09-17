import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var composeKind: ContainerKind?
    @State private var openedItem: SecretItem?
    @State private var isOpening = false
    // 首页这一屏的上推信号：三个物件共用，读数不触发界面重绘。
    @State private var jolt = RoomJolt()

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
                            .padding(.bottom, 26)
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .background {
                        // 只读这一屏被向上推动的位移，不认手势、不改触摸竞争。
                        RoomJoltProbe(jolt: jolt)
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

    // 房间是一块固定比例的画布：星星瓶、胶囊盒、纸团篓按阶梯锹开，
    // 每件东西在画布里的位置和宽度都用归一化坐标给出，换屏幕只等比缩放。
    private var sharedRoom: some View {
        GeometryReader { canvas in
            ZStack {
                ForEach(ContainerKind.allCases) { kind in
                    let slot = HomeRoomMetrics.slot(for: kind)
                    roomObject(kind: kind)
                        .frame(width: canvas.size.width * slot.width)
                        .position(
                            x: canvas.size.width * slot.center.x,
                            y: canvas.size.height * slot.center.y
                        )
                }
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .aspectRatio(HomeRoomMetrics.roomAspect, contentMode: .fit)
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
            jolt: jolt,
            isPaused: scenePhase != .active || openedItem != nil,
            onOpenItem: { open($0) },
            onEmptyTap: { openNext(kind) }
        )
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
            .background(Color.white.opacity(0.36))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.60), lineWidth: 1) }
            .contentShape(Capsule())
            .accessibilityLabel(title.localized)
    }
}

// 把宿主 ScrollView 每帧的位移换算成晃瓶力度：只读 contentOffset，不参与触摸判定，
// 也不经过 SwiftUI 状态，因此滚动时不会重建这一屏和三个物理舞台。
private struct RoomJoltProbe: UIViewRepresentable {
    let jolt: RoomJolt

    func makeUIView(context: Context) -> UIView { RoomJoltProbeView(jolt: jolt) }
    func updateUIView(_ view: UIView, context: Context) {}
}

private final class RoomJoltProbeView: UIView {
    private let jolt: RoomJolt
    private var link: CADisplayLink?
    private var lastOffsetY: CGFloat?
    private var lastTick: CFTimeInterval?
    private weak var scrollView: UIScrollView?

    init(jolt: RoomJolt) {
        self.jolt = jolt
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, let scrollView = enclosingScrollView() else {
            stop()
            return
        }
        self.scrollView = scrollView
        start()
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
