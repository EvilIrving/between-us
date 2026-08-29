import Foundation
import SwiftUI

struct VoiceHoldRecorderView: View {
    let kind: ContainerKind
    @ObservedObject var recorder: AudioRecorder
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let hasComposeContent: Bool
    let isDisabled: Bool
    let onCommit: () -> Void
    let onRecorded: (AttachmentDraft) -> Void
    let onPreviewed: (AttachmentDraft) -> Void
    let onCancelled: () -> Void
    let onTooShort: () -> Void
    let onError: (String) -> Void

    @State private var captureState: VoiceCaptureState = .idle
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var dragAxis: VoiceDragAxis?
    @State private var isCancelArmed = false

    private let cancelDistance: CGFloat = 96
    private let lockDistance: CGFloat = 78
    private let minimumDuration: TimeInterval = 0.65

    var body: some View {
        recordingStage
    }

    private var recordingStage: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                recordingInfo
                voicePad
            }

            lockGuide
                .offset(x: -3, y: -54)
        }
        .frame(maxWidth: 360, minHeight: 47, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityAction(named: "开始录音") {
            guard !isDisabled, !hasComposeContent, captureState == .idle, !recorder.isRecording else { return }
            beginRecordingGesture()
        }
        .accessibilityAction(named: "发送录音") {
            guard recorder.isRecording else { return }
            finishRecordingGesture(cancelled: false)
        }
        .accessibilityAction(named: "停止并预览") {
            guard isLocked, recorder.isRecording else { return }
            previewLockedRecording()
        }
        .accessibilityAction(named: "取消录音") {
            guard fingerDown || isLocked || recorder.isRecording else { return }
            finishRecordingGesture(cancelled: true)
        }
        .onChange(of: recorder.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, captureState.acceptsExternalStop else { return }
            resetInteractionState()
        }
    }

    private var fingerDown: Bool { captureState.isFingerDown }
    private var isLocked: Bool { captureState.isLocked }

    private var accessibilityValue: String {
        if recorder.isPreparing { return "正在准备录音" }
        if captureState == .producingDraft { return "正在生成语音草稿" }
        if isLocked { return "录音已锁定，时长 \(recorder.duration.formattedRecordingDuration)" }
        if recorder.isRecording { return "正在录音，时长 \(recorder.duration.formattedRecordingDuration)" }
        return "尚未开始录音"
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            if recorder.isPreparing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(kind.tint)
            } else {
                Circle()
                    .fill(recorder.isRecording ? Color.red : AppTheme.secondaryText.opacity(0.22))
                    .frame(width: 10, height: 10)
                    .shadow(color: recorder.isRecording ? Color.red.opacity(0.38) : .clear, radius: 6)
            }

            Text(recorder.duration.formattedRecordingDuration)
                .monospacedDigit()
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .foregroundStyle(AppTheme.primaryText.opacity(0.78))
        .fixedSize()
    }

    private var recordingInfo: some View {
        ZStack {
            if captureState == .producingDraft {
                ProgressView()
                    .tint(kind.tint)
            } else if recorder.isRecording || recorder.isPreparing {
                HStack(spacing: 10) {
                    recordingStatus

                    Spacer(minLength: 8)

                    recordingCancelControl
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
            } else {
                TextField("这一刻的想法…", text: $text, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1...4)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .tint(kind.tint)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 47)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.38))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.66), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var recordingCancelControl: some View {
        if isLocked {
            Button {
                finishRecordingGesture(cancelled: true)
            } label: {
                Text("取消")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(kind.tint)
                    .frame(minWidth: 52, minHeight: 44)
            }
            .buttonStyle(.plain)
        } else if fingerDown {
            HStack(spacing: 6) {
                Image(systemName: cancelProgress >= 1 ? "xmark" : "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text(cancelProgress >= 1 ? "松开取消" : "左滑取消")
                    .font(.system(size: 14, weight: .regular))
            }
            .foregroundStyle(AppTheme.secondaryText.opacity(cancelProgress >= 1 ? 0.82 : 0.52))
            .offset(x: dragX * 0.16)
        } else {
            Color.clear
                .frame(width: 82, height: 1)
        }
    }

    private var lockGuide: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
            Image(systemName: lockProgress >= 1 ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(lockProgress >= 1 ? kind.tint : AppTheme.secondaryText.opacity(0.55))
        .frame(width: 40, height: 58)
        .background(Color.white.opacity(0.46))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.66), lineWidth: 1)
        }
        .opacity(!isLocked && fingerDown && recorder.isRecording ? max(0.46, lockProgress) : 0)
        .offset(y: dragY * 0.08)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var voicePad: some View {
        if isLocked && !fingerDown {
            Button {
                previewLockedRecording()
            } label: {
                voicePadSurface
            }
            .buttonStyle(SoftScaleButtonStyle())
            .disabled(isDisabled || !recorder.isRecording)
            .accessibilityLabel("停止录音并进入预览")
        } else if hasComposeContent && captureState == .idle {
            Button {
                onCommit()
            } label: {
                commitPadSurface
            }
            .buttonStyle(SoftScaleButtonStyle())
            .disabled(isDisabled)
            .accessibilityLabel("放入")
        } else {
            voicePadSurface
                .highPriorityGesture(recordingGesture, including: isDisabled || hasComposeContent ? .none : .all)
                .accessibilityLabel("按住录音")
                .accessibilityHint("左滑取消，上滑锁定")
        }
    }

    private var commitPadSurface: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 47)
            .background(kind.tint)
            .clipShape(Capsule())
    }

    private var voicePadSurface: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(fingerDown ? 0.58 : 0.44))
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }

            if recorder.isPreparing || captureState == .producingDraft {
                ProgressView()
                    .tint(kind.tint)
            } else {
                Image(systemName: voicePadSymbol)
                    .font(.system(size: isLocked ? 14 : 20, weight: .semibold))
                    .foregroundStyle(cancelProgress >= 1 ? AppTheme.secondaryText : kind.tint)
            }
        }
        .frame(width: 46, height: 47)
        .contentShape(Capsule())
        .scaleEffect(fingerDown ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: fingerDown)
    }

    private var voicePadSymbol: String {
        isLocked && recorder.isRecording ? "stop.fill" : "mic.fill"
    }

    private var cancelProgress: CGFloat {
        min(max(-dragX / cancelDistance, 0), 1)
    }

    private var lockProgress: CGFloat {
        min(max(-dragY / lockDistance, 0), 1)
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isDisabled else { return }
                if captureState == .idle {
                    beginRecordingGesture()
                }

                guard case .holding = captureState else {
                    resetTransientGestureState()
                    return
                }

                let leftDistance = max(-value.translation.width, 0)
                let upDistance = max(-value.translation.height, 0)
                if max(leftDistance, upDistance) < 8 {
                    dragAxis = nil
                } else if abs(leftDistance - upDistance) >= 6 || dragAxis == nil {
                    dragAxis = leftDistance >= upDistance ? .horizontal : .vertical
                }

                switch dragAxis {
                case .horizontal:
                    dragX = -min(leftDistance, cancelDistance + 18)
                    dragY = 0
                case .vertical:
                    dragX = 0
                    dragY = -min(upDistance, lockDistance + 18)
                case nil:
                    dragX = 0
                    dragY = 0
                }

                let shouldCancel = dragAxis == .horizontal && -dragX >= cancelDistance
                let shouldLock = dragAxis == .vertical && -dragY >= lockDistance

                if shouldLock, let sessionID = captureState.sessionID {
                    captureState = .locking(sessionID)
                    isCancelArmed = false
                    dragX = 0
                    dragY = 0
                    dragAxis = nil
                    RitualHaptics.success()
                    return
                }
                if shouldCancel, !isCancelArmed {
                    isCancelArmed = true
                    RitualHaptics.warning()
                } else if !shouldCancel,
                          isCancelArmed,
                          (dragAxis != .horizontal || leftDistance < cancelDistance * 0.72) {
                    isCancelArmed = false
                    RitualHaptics.selection()
                }
            }
            .onEnded { _ in
                switch captureState {
                case let .locking(sessionID):
                    captureState = .locked(sessionID)
                    resetTransientGestureState()
                case .holding:
                    finishRecordingGesture(cancelled: isCancelArmed)
                case .idle, .locked, .producingDraft:
                    break
                }
            }
    }

    private func beginRecordingGesture() {
        isFocused.wrappedValue = false
        let sessionID = UUID()
        captureState = .holding(sessionID)
        resetTransientGestureState()
        RitualHaptics.medium()

        Task { @MainActor in
            let started = await recorder.start()
            guard captureState.sessionID == sessionID else {
                if started { recorder.discard() }
                return
            }
            if !started {
                resetInteractionState()
                if let message = recorder.errorMessage {
                    onError(message)
                }
            }
        }
    }

    private func previewLockedRecording() {
        guard case .locked = captureState, recorder.isRecording else { return }
        captureState = .producingDraft
        resetTransientGestureState()
        Task { @MainActor in
            await Task.yield()
            finishRecordingGesture(cancelled: false, completion: .preview)
        }
    }

    private func resetTransientGestureState() {
        dragX = 0
        dragY = 0
        dragAxis = nil
        isCancelArmed = false
    }

    private func resetInteractionState() {
        captureState = .idle
        resetTransientGestureState()
    }

    private func finishRecordingGesture(
        cancelled: Bool,
        completion: VoiceRecordingCompletion = .send
    ) {
        let wasActive = recorder.isRecording || recorder.isPreparing

        if cancelled {
            resetInteractionState()
            recorder.discard()
            if wasActive { onCancelled() }
            return
        }

        if recorder.isPreparing {
            resetInteractionState()
            recorder.discard()
            RitualHaptics.warning()
            onTooShort()
            return
        }

        guard recorder.isRecording else { return }

        guard recorder.duration >= minimumDuration else {
            resetInteractionState()
            recorder.discard()
            RitualHaptics.warning()
            onTooShort()
            return
        }

        captureState = .producingDraft
        resetTransientGestureState()
        if let draft = recorder.stop() {
            RitualHaptics.success()
            switch completion {
            case .send:
                onRecorded(draft)
                resetInteractionState()
            case .preview:
                Task { @MainActor in
                    await Task.yield()
                    onPreviewed(draft)
                    resetInteractionState()
                }
            }
        } else {
            resetInteractionState()
        }
    }
}

private enum VoiceRecordingCompletion {
    case send
    case preview
}

private enum VoiceCaptureState: Equatable {
    case idle
    case holding(UUID)
    case locking(UUID)
    case locked(UUID)
    case producingDraft

    var sessionID: UUID? {
        switch self {
        case let .holding(id), let .locking(id), let .locked(id): return id
        case .idle, .producingDraft: return nil
        }
    }

    var isFingerDown: Bool {
        switch self {
        case .holding, .locking: return true
        case .idle, .locked, .producingDraft: return false
        }
    }

    var isLocked: Bool {
        switch self {
        case .locking, .locked: return true
        case .idle, .holding, .producingDraft: return false
        }
    }

    var acceptsExternalStop: Bool {
        switch self {
        case .holding, .locking, .locked: return true
        case .idle, .producingDraft: return false
        }
    }
}

private enum VoiceDragAxis: Equatable {
    case horizontal
    case vertical
}

extension TimeInterval {
    var formattedRecordingDuration: String {
        guard isFinite, self >= 0 else { return "0:00.0" }
        let tenths = Int((self * 10).rounded(.down))
        let minutes = tenths / 600
        let seconds = (tenths / 10) % 60
        let fraction = tenths % 10
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}
