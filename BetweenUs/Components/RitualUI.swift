import SwiftUI
import UIKit

enum RitualHaptics {
    // 每次现建生成器拿不到引擎预热，第一次震动的延迟正好落在手指按下的那一刻；
    // 复用同一批生成器，并在界面出现时预热一次。
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepare() {
        softGenerator.prepare()
        mediumGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    static func soft() {
        softGenerator.impactOccurred()
        softGenerator.prepare()
    }

    static func medium() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
}

struct AmbientRoomBackground: View {
    let kind: ContainerKind?

    init(kind: ContainerKind? = nil) {
        self.kind = kind
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.backgroundGradient(for: kind)

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.48),
                        (kind?.tint ?? AppTheme.warmLight).opacity(0.055),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 4,
                    endRadius: proxy.size.width * 1.18
                )

                RadialGradient(
                    colors: [
                        (kind?.tint ?? AppTheme.warmLight).opacity(0.045),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 8,
                    endRadius: proxy.size.width * 1.28
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct SceneCloseControl: View {
    let label: String
    let action: () -> Void

    init(label: String = "关闭", action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.52))
                    .frame(width: 42, height: 42)
                    .overlay { Circle().stroke(Color.white.opacity(0.62), lineWidth: 1) }
                    .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)

                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.74))
            }
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityLabel(T(key: label))
    }
}

struct SoftScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AppMotion.pressDuration),
                value: configuration.isPressed
            )
    }
}

/// 产品里所有情绪/物件身份挂件共用这一个名义尺寸，不允许各处再传大一点小一点。
enum TokenIconMetrics {
    static let size: CGFloat = 54

    /// 名义尺寸是挂件外框，不是画面尺寸。星星挂件的有效画面只占外框约八成，
    /// 胶囊和纸团却把外框填满，所以这两件按同一个系数收回一点，三件视觉重量才齐。
    static func inkScale(for kind: ContainerKind) -> CGFloat {
        switch kind {
        case .star: return 1
        case .capsule: return 0.9
        case .paper: return 0.9
        }
    }
}

struct RitualObjectGlyph: View {
    let kind: ContainerKind
    var filled = true
    /// 内容身份图标默认不带圆底；入口类场景可打开底色。
    var showsBackground = false
    /// 传入内容标识时用与物件舞台同一张皮肤，抽屉里的星星和瓶里的星星是同一颗。
    var tokenID: UUID? = nil

    var body: some View {
        ZStack {
            if showsBackground {
                Circle()
                    .fill(kind.tint.opacity(filled ? 0.14 : 0.07))
                    .frame(width: TokenIconMetrics.size, height: TokenIconMetrics.size)
            }

            ContainerTokenImage(kind: kind, id: tokenID)
                .rotationEffect(.degrees(rotation))
                .opacity(filled ? 1 : 0.80)
        }
        .frame(width: TokenIconMetrics.size, height: TokenIconMetrics.size)
        .accessibilityHidden(true)
    }

    private var rotation: Double {
        switch kind {
        case .star: return -8
        case .capsule: return -14
        case .paper: return 0
        }
    }
}

struct RitualActionToken: View {
    let kind: ContainerKind
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            HStack(spacing: 13) {
                RitualObjectGlyph(kind: kind, filled: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(T(key: title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.38))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(kind.tint.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
    }
}

struct WhisperNoticeBanner: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.warmLight)

                VStack(alignment: .leading, spacing: 3) {
                    Text(T(key: title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    if !message.isEmpty {
                        Text(T(key: message))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityLabel(
            message.isEmpty
                ? T(key: title)
                : T("通知：%@，%@。轻点关闭", T(key: title), T(key: message))
        )
    }
}

struct RitualModeToken: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? tint.opacity(0.18) : Color.white.opacity(0.32))
                        .frame(width: 43, height: 43)
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : AppTheme.secondaryText.opacity(0.72))
                }

                Text(T(key: title))
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct HoldToCompleteSurface<Content: View>: View {
    let duration: TimeInterval
    let isEnabled: Bool
    let isWorking: Bool
    let onComplete: () -> Void
    let content: (CGFloat, Bool) -> Content

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @State private var didComplete = false
    @State private var activationTask: Task<Void, Never>?

    init(
        duration: TimeInterval,
        isEnabled: Bool,
        isWorking: Bool,
        onComplete: @escaping () -> Void,
        @ViewBuilder content: @escaping (CGFloat, Bool) -> Content
    ) {
        self.duration = duration
        self.isEnabled = isEnabled
        self.isWorking = isWorking
        self.onComplete = onComplete
        self.content = content
    }

    var body: some View {
        content(progress, isPressing)
            .contentShape(Rectangle())
            .highPriorityGesture(pressGesture, including: isEnabled && !isWorking ? .all : .none)
            .onDisappear { cancelPress() }
            .onChange(of: isWorking) { _, working in
                if working {
                    activationTask?.cancel()
                    activationTask = nil
                    isPressing = false
                } else if !isPressing {
                    resetProgress()
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, !isWorking, !didComplete {
                    cancelPress()
                }
            }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in beginPressIfNeeded() }
            .onEnded { _ in endPress() }
    }

    private func beginPressIfNeeded() {
        guard isEnabled, !isWorking, !isPressing, !didComplete else { return }
        isPressing = true
        progress = 0
        RitualHaptics.soft()

        withAnimation(.linear(duration: max(0.1, duration))) {
            progress = 1
        }

        activationTask?.cancel()
        activationTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0.1, duration) * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, isPressing, isEnabled, !isWorking else { return }
            didComplete = true
            RitualHaptics.success()
            onComplete()
        }
    }

    private func endPress() {
        isPressing = false
        activationTask?.cancel()
        activationTask = nil
        if didComplete {
            activationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, !isWorking else { return }
                resetProgress()
                activationTask = nil
            }
            return
        }
        resetProgress()
    }

    private func resetProgress() {
        didComplete = false
        withAnimation(.easeOut(duration: AppMotion.resetDuration)) {
            progress = 0
        }
    }

    private func cancelPress() {
        activationTask?.cancel()
        activationTask = nil
        isPressing = false
        didComplete = false
        progress = 0
    }
}

/// 按住时从瓶底升起来的一点暖光。
///
/// 两个界面共用这一套——首屏的「按住创建空间」和配对页的「按住允许 / 按住加入」。
/// 位置按瓶子的画面尺寸算：瓶子在整张图里高约 0.57 个画布，所以瓶底落在中心下方约 0.29 处，
/// 按满时光升到瓶身中段。画面尺寸换了位置跟着换，不写死点数。
struct BottleHoldLight: View {
    /// 瓶子的画面尺寸，和传给 `ContainerVisual` 的那条边长一致。
    let side: CGFloat
    /// 按住进度 0…1。
    let progress: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [AppTheme.warmLight, AppTheme.warmLight.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.094
                )
            )
            .frame(width: side * 0.19, height: side * 0.19)
            .blur(radius: 2)
            .scaleEffect(0.5 + 0.5 * progress)
            .offset(y: offset)
            .opacity(0.92 * Double(max(0, min(1, progress))))
            .allowsHitTesting(false)
    }

    private var offset: CGFloat {
        let bottom = side * 0.29
        let rest = -side * 0.09
        return bottom + (rest - bottom) * progress
    }
}

struct QuietSyncGlyph: View {
    let status: CloudSyncStatus

    var body: some View {
        Group {
            if status == .syncing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
        .frame(width: 34, height: 34)
        .background(Color.white.opacity(0.25))
        .clipShape(Circle())
        .accessibilityLabel(status.title)
    }
}
