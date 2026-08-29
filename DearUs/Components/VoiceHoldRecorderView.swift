import Foundation
import SwiftUI

struct VoiceHoldRecorderView: View {
    let kind: ContainerKind
    @ObservedObject var recorder: AudioRecorder
    let isDisabled: Bool
    let onRecorded: (AttachmentDraft) -> Void
    let onCancelled: () -> Void
    let onTooShort: () -> Void
    let onError: (String) -> Void

    @State private var fingerDown = false
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var isLocked = false
    @State private var gestureBeganLocked = false
    @State private var didUnlockDuringGesture = false
    @State private var crossedCancelThreshold = false
    @State private var currentSessionID: UUID?

    private let cancelDistance: CGFloat = 96
    private let lockDistance: CGFloat = 78
    private let minimumDuration: TimeInterval = 0.65

    var body: some View {
        VStack(spacing: 14) {
            recordingStatus

            LiveVoiceWaveform(
                level: recorder.level,
                isActive: recorder.isRecording && !recorder.isPaused,
                tint: cancelProgress >= 1 ? AppTheme.secondaryText : kind.tint
            )
            .frame(height: 48)
            .padding(.horizontal, 16)

            ZStack {
                cancelTrail
                lockTrail

                voicePad
                    .offset(x: dragX, y: dragY * 0.22)
            }
            .frame(height: 124)

            VStack(spacing: 6) {
                Text(instructionTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .animation(.easeOut(duration: 0.18), value: instructionTitle)

                Text(instructionDetail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 22)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("语音输入")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("按住说话，上滑可锁定录音；也可使用辅助功能动作开始、完成或取消")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "开始录音") {
            guard !isDisabled, !fingerDown, !recorder.isRecording else { return }
            beginRecordingGesture()
        }
        .accessibilityAction(named: "完成并放入") {
            guard fingerDown || isLocked || recorder.isRecording else { return }
            finishRecordingGesture(cancelled: false)
        }
        .accessibilityAction(named: "取消录音") {
            guard fingerDown || isLocked || recorder.isRecording else { return }
            finishRecordingGesture(cancelled: true)
        }
        .onChange(of: recorder.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, (fingerDown || isLocked) else { return }
            resetGestureState()
        }
    }


    private var accessibilityValue: String {
        if recorder.isPreparing { return "正在准备录音" }
        if recorder.isPaused { return "录音已暂停，时长 \(recorder.duration.formattedRecordingDuration)" }
        if recorder.isRecording { return "正在录音，时长 \(recorder.duration.formattedRecordingDuration)" }
        return "尚未开始录音"
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recorder.isRecording && !recorder.isPaused ? Color.red : AppTheme.secondaryText.opacity(0.22))
                .frame(width: 8, height: 8)
                .shadow(color: recorder.isRecording && !recorder.isPaused ? Color.red.opacity(0.38) : .clear, radius: 6)

            if recorder.isPreparing {
                Text("正在听见你……")
            } else {
                Text(recorder.duration.formattedRecordingDuration)
                    .monospacedDigit()
            }
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(height: 22)
    }

    private var cancelTrail: some View {
        HStack(spacing: 8) {
            Image(systemName: cancelProgress >= 1 ? "xmark.circle.fill" : "arrow.left")
                .font(.system(size: 15, weight: .bold))
            Text(cancelProgress >= 1 ? "松开取消" : "向左滑取消")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(cancelProgress >= 1 ? AppTheme.secondaryText : AppTheme.secondaryText.opacity(0.46))
        .opacity(fingerDown ? max(0.28, cancelProgress) : 0)
        .offset(x: -112)
        .animation(.easeOut(duration: 0.16), value: cancelProgress)
    }

    private var lockTrail: some View {
        VStack(spacing: 3) {
            Image(systemName: isLocked ? "lock.open.fill" : (lockProgress >= 1 ? "lock.fill" : "arrow.up"))
                .font(.system(size: 14, weight: .bold))
            Text(isLocked ? "再上滑解锁" : (lockProgress >= 1 ? "松手继续录音" : "上滑锁定"))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle((isLocked || lockProgress >= 1) ? kind.tint : AppTheme.secondaryText.opacity(0.50))
        .opacity(isLocked ? 0.78 : (fingerDown ? max(0.42, lockProgress) : 0))
        .offset(y: -53)
        .animation(.easeOut(duration: 0.16), value: lockProgress)
    }

    private var voicePad: some View {
        ZStack {
            Circle()
                .fill(kind.tint.opacity(fingerDown ? 0.19 : 0.10))
                .frame(width: 92, height: 92)
                .blur(radius: fingerDown ? 0 : 3)

            Circle()
                .fill(Color.white.opacity(fingerDown ? 0.78 : 0.58))
                .frame(width: 70, height: 70)
                .overlay {
                    Circle()
                        .stroke(
                            cancelProgress >= 1 ? AppTheme.secondaryText.opacity(0.42) : kind.tint.opacity(0.38),
                            lineWidth: fingerDown ? 2 : 1
                        )
                }
                .shadow(color: kind.tint.opacity(fingerDown ? 0.24 : 0.10), radius: fingerDown ? 24 : 12, y: 8)

            if recorder.isPreparing {
                ProgressView()
                    .tint(kind.tint)
            } else {
                Image(systemName: voicePadSymbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(cancelProgress >= 1 ? AppTheme.secondaryText : kind.tint)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording && !recorder.isPaused && !isLocked)
            }
        }
        .scaleEffect(fingerDown ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: fingerDown)
        .highPriorityGesture(recordingGesture, including: isDisabled ? .none : .all)
    }

    private var voicePadSymbol: String {
        if recorder.isPaused { return "play.fill" }
        if isLocked && recorder.isRecording { return "pause.fill" }
        return recorder.isRecording ? "waveform" : "mic.fill"
    }

    private var instructionTitle: String {
        if recorder.isPaused { return "录音已暂停" }
        if isLocked { return "录音已锁定" }
        if cancelProgress >= 1 { return "松开，这段就不会留下" }
        if recorder.isPreparing { return "保持按住" }
        if recorder.isRecording { return "正在录音" }
        return "按住说话"
    }

    private var instructionDetail: String {
        if isLocked {
            return recorder.isPreparing ? "正在准备，松手也会继续" : "轻点暂停 · 左滑取消 · 再上滑解锁"
        }
        if recorder.isRecording {
            return "上滑锁定 · 左滑取消 · 松开完成"
        }
        return "长按开始 · 上滑锁定 · 左滑取消"
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
                if !fingerDown {
                    if isLocked {
                        fingerDown = true
                        gestureBeganLocked = true
                        didUnlockDuringGesture = false
                        crossedCancelThreshold = false
                    } else {
                        beginRecordingGesture()
                    }
                }
                dragX = min(0, value.translation.width)
                dragY = min(0, value.translation.height)
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let shouldCancel = isHorizontal && -value.translation.width >= cancelDistance
                let shouldLock = !isHorizontal && -value.translation.height >= lockDistance

                if gestureBeganLocked {
                    if shouldLock {
                        isLocked = false
                        gestureBeganLocked = false
                        didUnlockDuringGesture = true
                        dragX = 0
                        dragY = 0
                        RitualHaptics.selection()
                        return
                    }
                } else if shouldLock, !isLocked, !didUnlockDuringGesture {
                    isLocked = true
                    dragX = 0
                    dragY = 0
                    RitualHaptics.success()
                    return
                }
                if shouldCancel, !crossedCancelThreshold {
                    crossedCancelThreshold = true
                    RitualHaptics.warning()
                } else if !shouldCancel, crossedCancelThreshold, -value.translation.width < cancelDistance * 0.72 {
                    crossedCancelThreshold = false
                    RitualHaptics.selection()
                }
            }
            .onEnded { value in
                guard fingerDown else { return }
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let shouldCancel = isHorizontal && -value.translation.width >= cancelDistance

                if gestureBeganLocked, isLocked {
                    fingerDown = false
                    dragX = 0
                    dragY = 0
                    gestureBeganLocked = false
                    crossedCancelThreshold = false
                    if shouldCancel {
                        finishRecordingGesture(cancelled: true)
                    } else if hypot(value.translation.width, value.translation.height) < 12 {
                        recorder.togglePause()
                        RitualHaptics.selection()
                    }
                    return
                }
                if isLocked {
                    fingerDown = false
                    dragX = 0
                    dragY = 0
                    return
                }
                finishRecordingGesture(cancelled: shouldCancel)
            }
    }

    private func beginRecordingGesture() {
        fingerDown = true
        dragX = 0
        dragY = 0
        isLocked = false
        gestureBeganLocked = false
        didUnlockDuringGesture = false
        crossedCancelThreshold = false
        let sessionID = UUID()
        currentSessionID = sessionID
        RitualHaptics.medium()

        Task { @MainActor in
            let started = await recorder.start()
            guard currentSessionID == sessionID, (fingerDown || isLocked) else {
                if started { recorder.discard() }
                return
            }
            if !started {
                resetGestureState()
                if let message = recorder.errorMessage {
                    onError(message)
                }
            }
        }
    }

    private func resetGestureState() {
        fingerDown = false
        dragX = 0
        dragY = 0
        isLocked = false
        gestureBeganLocked = false
        didUnlockDuringGesture = false
        crossedCancelThreshold = false
        currentSessionID = nil
    }

    private func finishRecordingGesture(cancelled: Bool) {
        let wasActive = recorder.isRecording || recorder.isPreparing
        resetGestureState()

        if cancelled {
            recorder.discard()
            if wasActive { onCancelled() }
            return
        }

        guard recorder.isRecording else { return }

        guard recorder.duration >= minimumDuration else {
            recorder.discard()
            RitualHaptics.warning()
            onTooShort()
            return
        }

        if let draft = recorder.stop() {
            RitualHaptics.success()
            onRecorded(draft)
        }
    }
}

private struct LiveVoiceWaveform: View {
    let level: Double
    let isActive: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    waveform(phase: context.date.timeIntervalSinceReferenceDate * 6.5, active: true)
                }
            } else {
                waveform(phase: 0, active: isActive)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func waveform(phase: Double, active: Bool) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<25, id: \.self) { index in
                let wave = (sin(phase + Double(index) * 0.72) + 1) / 2
                let centerWeight = 1 - abs(Double(index) - 12) / 18
                let liveLevel = active ? max(0.10, min(1, level * 1.65)) : 0.06
                let height = 7 + 43 * liveLevel * (0.32 + wave * 0.68) * centerWeight

                Capsule()
                    .fill(tint.opacity(active ? 0.70 : 0.24))
                    .frame(width: 3.5, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
