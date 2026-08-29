import SwiftUI
import UIKit

enum RitualHaptics {
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        .accessibilityLabel(label.localized)
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

struct RitualObjectGlyph: View {
    let kind: ContainerKind
    var size: CGFloat = 58
    var filled = true

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.tint.opacity(filled ? 0.14 : 0.07))
                .frame(width: size, height: size)

            switch kind {
            case .star:
                ParametricTokenView(kind: kind, seed: 2, filled: filled)
                    .frame(width: size * 0.53, height: size * 0.53)
                    .rotationEffect(.degrees(-8))
            case .capsule:
                ParametricTokenView(kind: kind, seed: 1, filled: filled)
                    .frame(width: size * 0.64, height: size * 0.27)
                    .rotationEffect(.degrees(-18))
            case .paper:
                ParametricTokenView(kind: kind, seed: filled ? 3 : 1, filled: filled)
                    .frame(width: size * 0.56, height: size * 0.56)
            }
        }
        .accessibilityHidden(true)
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
                RitualObjectGlyph(kind: kind, size: 52, filled: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localized)
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
                    Text(title.localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(message.localized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(3)
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
        .accessibilityLabel("通知：%@，%@。轻点关闭".localized(title.localized, message.localized))
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

                Text(title.localized)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RitualDepositControl: View {
    let kind: ContainerKind
    let isEnabled: Bool
    let isWorking: Bool
    let instruction: String
    var onGestureBegan: (() -> Void)? = nil
    let onCommit: () -> Void

    @GestureState private var dragY: CGFloat = 0
    @State private var crossedThreshold = false

    private var progress: CGFloat {
        min(max(-dragY / 72, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            RitualObjectGlyph(kind: kind, size: 48, filled: true)
                .scaleEffect(1 - progress * 0.10)
                .rotationEffect(.degrees(rotationForProgress))

            Text(isWorking ? "正在保存…".localized : instruction.localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    isEnabled
                        ? AppTheme.primaryText
                        : AppTheme.secondaryText.opacity(0.46)
                )

            Spacer(minLength: 8)

            if isWorking {
                ProgressView()
                    .tint(kind.tint)
            } else {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kind.tint.opacity(isEnabled ? 0.78 : 0.28))
                    .frame(width: 30, height: 30)
                    .background(kind.tint.opacity(isEnabled ? 0.10 : 0.04))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(Color.white.opacity(isEnabled ? 0.46 : 0.28))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(kind.tint.opacity(isEnabled ? 0.24 : 0.10), lineWidth: 1)
        }
        .offset(y: dragY * 0.14)
        .scaleEffect(1 - progress * 0.025)
        .opacity(isWorking ? 0.62 : 1)
        .shadow(color: kind.tint.opacity(progress * 0.18), radius: progress * 14, y: 6)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture, including: isEnabled && !isWorking ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(instruction.localized)
        .accessibilityHint("向上拖动完成".localized)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            onCommit()
        }
    }

    private var rotationForProgress: Double {
        switch kind {
        case .star: return -10 + Double(progress) * 40
        case .capsule: return -18 + Double(progress) * 16
        case .paper: return -4 + Double(progress) * -24
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragY) { value, state, _ in
                guard isEnabled, !isWorking else { return }
                state = min(0, value.translation.height)
            }
            .onChanged { value in
                guard isEnabled, !isWorking else { return }
                onGestureBegan?()
                let currentProgress = min(max(-value.translation.height / 72, 0), 1)
                if currentProgress >= 0.84, !crossedThreshold {
                    crossedThreshold = true
                    RitualHaptics.medium()
                } else if currentProgress < 0.72 {
                    crossedThreshold = false
                }
            }
            .onEnded { value in
                guard isEnabled, !isWorking else { return }
                let finalProgress = min(max(-value.translation.height / 72, 0), 1)
                crossedThreshold = false
                if finalProgress >= 0.84 {
                    RitualHaptics.success()
                    onCommit()
                }
            }
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
            .onChange(of: isWorking) { working in
                if working {
                    activationTask?.cancel()
                    activationTask = nil
                    isPressing = false
                } else if !isPressing {
                    resetProgress()
                }
            }
            .onChange(of: isEnabled) { enabled in
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

struct HoldToOpenControl: View {
    let kind: ContainerKind
    let title: String
    let inactiveTitle: String
    let duration: TimeInterval
    let isEnabled: Bool
    let isWorking: Bool
    let onComplete: () -> Void

    var body: some View {
        HoldToCompleteSurface(
            duration: duration,
            isEnabled: isEnabled,
            isWorking: isWorking,
            onComplete: onComplete
        ) { progress, isPressing in
            HStack(spacing: 14) {
                RitualObjectGlyph(kind: kind, size: 54, filled: true)
                    .scaleEffect(isPressing ? 0.94 : 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text((isEnabled ? title : inactiveTitle).localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEnabled ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.52))

                    Text(isWorking ? "请稍候".localized : "持续按住 · 松开取消".localized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(isEnabled ? 0.66 : 0.40))
                }

                Spacer(minLength: 8)

                if isWorking {
                    ProgressView()
                        .tint(kind.tint)
                } else {
                    ZStack(alignment: .leading) {
                        Capsule().fill(kind.tint.opacity(0.13))
                        Capsule()
                            .fill(kind.tint)
                            .scaleEffect(x: progress, anchor: .leading)
                    }
                    .frame(width: 44, height: 5)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(isPressing ? 0.52 : 0.34))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(kind.tint.opacity(isPressing ? 0.34 : 0.16), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("持续按住完成".localized)
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            onComplete()
        }
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
