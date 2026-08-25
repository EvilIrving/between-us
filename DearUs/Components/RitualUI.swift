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
    @State private var isFloating = false

    init(kind: ContainerKind? = nil) {
        self.kind = kind
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.backgroundGradient(for: kind)

                Ellipse()
                    .fill((kind?.tint ?? AppTheme.warmLight).opacity(0.10))
                    .frame(width: proxy.size.width * 1.15, height: proxy.size.width * 0.82)
                    .blur(radius: 26)
                    .offset(x: -proxy.size.width * 0.28, y: -proxy.size.height * 0.28)

                Ellipse()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: proxy.size.width * 0.95, height: proxy.size.width * 0.70)
                    .blur(radius: 34)
                    .offset(x: proxy.size.width * 0.34, y: proxy.size.height * 0.28)

                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index.isMultiple(of: 3) ? 0.34 : 0.18))
                        .frame(width: CGFloat(3 + index % 4), height: CGFloat(3 + index % 4))
                        .position(
                            x: proxy.size.width * CGFloat((index * 37) % 91 + 4) / 100,
                            y: proxy.size.height * CGFloat((index * 53) % 86 + 7) / 100
                        )
                        .offset(y: isFloating ? CGFloat((index % 5) - 2) * 8 : CGFloat((index % 5) - 2) * -5)
                        .opacity(isFloating ? 0.75 : 0.38)
                }
            }
            .animation(
                .easeInOut(duration: 4.8).repeatForever(autoreverses: true),
                value: isFloating
            )
            .onAppear { isFloating = true }
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
        .accessibilityLabel(label)
    }
}

struct SoftScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
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
                StarShape()
                    .fill(filled ? kind.tint : Color.white.opacity(0.92))
                    .overlay { StarShape().stroke(kind.tint.opacity(0.32), lineWidth: 1) }
                    .frame(width: size * 0.53, height: size * 0.53)
                    .rotationEffect(.degrees(-8))
            case .capsule:
                Capsule()
                    .fill(filled ? kind.tint : Color.white.opacity(0.92))
                    .overlay { Capsule().stroke(kind.tint.opacity(0.36), lineWidth: 1) }
                    .frame(width: size * 0.64, height: size * 0.27)
                    .rotationEffect(.degrees(-18))
            case .paper:
                CrumpledPaper(index: filled ? 3 : 1)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .opacity(filled ? 1 : 0.78)
            }
        }
        .accessibilityHidden(true)
    }
}

struct RitualActionToken: View {
    let kind: ContainerKind
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    @State private var isBreathing = false

    var body: some View {
        Button {
            RitualHaptics.selection()
            action()
        } label: {
            VStack(spacing: 8) {
                RitualObjectGlyph(kind: kind, size: 68, filled: false)
                    .scaleEffect(isBreathing ? 1.035 : 0.97)
                    .shadow(color: kind.tint.opacity(0.18), radius: isBreathing ? 18 : 8)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftScaleButtonStyle())
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: isBreathing)
        .onAppear { isBreathing = true }
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
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(message)
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
        .accessibilityLabel("\(title)，\(message)，轻点关闭")
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

                Text(title)
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
        min(max(-dragY / 112, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 5) {
                ZStack {
                    Capsule()
                        .stroke(kind.tint.opacity(0.20 + progress * 0.44), lineWidth: 1.5)
                        .frame(width: 74 + progress * 18, height: 27 + progress * 6)
                        .blur(radius: progress * 1.5)

                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(kind.tint.opacity(0.45 + progress * 0.45))
                        .offset(y: -1)
                }

                Text(isWorking ? "正在放进去……" : instruction)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText.opacity(isEnabled ? 0.80 : 0.42))
            }
            .frame(maxWidth: .infinity, alignment: .top)

            RitualObjectGlyph(kind: kind, size: 72, filled: true)
                .scaleEffect(1 - progress * 0.18)
                .rotationEffect(.degrees(rotationForProgress))
                .offset(y: dragY)
                .shadow(color: kind.tint.opacity(0.14 + progress * 0.22), radius: 14 + progress * 14)
                .opacity(isWorking ? 0.40 : (isEnabled ? 1 : 0.35))
                .overlay {
                    if isWorking {
                        ProgressView()
                            .tint(kind.tint)
                    }
                }
        }
        .frame(height: 142)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture, including: isEnabled && !isWorking ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(instruction)
        .accessibilityHint("向上拖动完成")
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
                let currentProgress = min(max(-value.translation.height / 112, 0), 1)
                if currentProgress >= 0.84, !crossedThreshold {
                    crossedThreshold = true
                    RitualHaptics.medium()
                } else if currentProgress < 0.72 {
                    crossedThreshold = false
                }
            }
            .onEnded { value in
                guard isEnabled, !isWorking else { return }
                let finalProgress = min(max(-value.translation.height / 112, 0), 1)
                crossedThreshold = false
                if finalProgress >= 0.84 {
                    RitualHaptics.success()
                    onCommit()
                }
            }
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

    @State private var isPressing = false
    @State private var pressedAt: Date?
    @State private var activationTask: Task<Void, Never>?
    @State private var didComplete = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = progress(at: context.date)

            VStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.46), lineWidth: 7)
                        .frame(width: 92, height: 92)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            kind.tint,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: kind.tint.opacity(0.28), radius: 8)

                    Circle()
                        .fill(Color.white.opacity(isPressing ? 0.66 : 0.46))
                        .frame(width: 74, height: 74)
                        .overlay { Circle().stroke(Color.white.opacity(0.72), lineWidth: 1) }

                    if isWorking {
                        ProgressView()
                            .tint(kind.tint)
                    } else {
                        Image(systemName: kind == .paper ? "hand.raised.fill" : "hand.tap.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(isEnabled ? kind.tint : AppTheme.secondaryText.opacity(0.36))
                            .scaleEffect(isPressing ? 0.90 : 1)
                    }
                }

                Text(isEnabled ? title : inactiveTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEnabled ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.52))
                    .multilineTextAlignment(.center)

                if isEnabled, !isWorking {
                    Text(kind == .paper ? "按住，直到你真的准备好" : "按住，让它慢慢把一件东西交给你")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(pressGesture, including: isEnabled && !isWorking ? .all : .none)
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isPressing)
        }
        .onDisappear { cancelPress() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("持续按住完成")
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            onComplete()
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                beginPressIfNeeded()
            }
            .onEnded { _ in
                endPress()
            }
    }

    private func progress(at date: Date) -> CGFloat {
        guard isPressing, let pressedAt else { return didComplete ? 1 : 0 }
        return min(max(date.timeIntervalSince(pressedAt) / duration, 0), 1)
    }

    private func beginPressIfNeeded() {
        guard isEnabled, !isWorking, !isPressing else { return }
        isPressing = true
        didComplete = false
        pressedAt = Date()
        RitualHaptics.soft()

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
        pressedAt = nil
        activationTask?.cancel()
        activationTask = nil
        if !didComplete {
            withAnimation(.easeOut(duration: 0.16)) {
                didComplete = false
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                didComplete = false
            }
        }
    }

    private func cancelPress() {
        isPressing = false
        pressedAt = nil
        activationTask?.cancel()
        activationTask = nil
        didComplete = false
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
