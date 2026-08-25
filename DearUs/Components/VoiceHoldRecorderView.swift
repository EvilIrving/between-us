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
    @State private var crossedCancelThreshold = false
    @State private var currentSessionID: UUID?

    private let cancelDistance: CGFloat = 96
    private let minimumDuration: TimeInterval = 0.65

    var body: some View {
        VStack(spacing: 24) {
            recordingStatus

            LiveVoiceWaveform(
                level: recorder.level,
                isActive: recorder.isRecording,
                tint: cancelProgress >= 1 ? AppTheme.secondaryText : kind.tint
            )
            .frame(height: 66)
            .padding(.horizontal, 16)

            ZStack {
                cancelTrail

                voicePad
                    .offset(x: dragX)
            }
            .frame(height: 150)

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
        .accessibilityHint("可按住说话，也可使用辅助功能动作开始、完成或取消录音")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "开始录音") {
            guard !isDisabled, !fingerDown, !recorder.isRecording else { return }
            beginRecordingGesture()
        }
        .accessibilityAction(named: "完成并放入") {
            guard fingerDown || recorder.isRecording else { return }
            finishRecordingGesture(cancelled: false)
        }
        .accessibilityAction(named: "取消录音") {
            guard fingerDown || recorder.isRecording else { return }
            finishRecordingGesture(cancelled: true)
        }
        .onChange(of: recorder.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, fingerDown else { return }
            resetGestureState()
        }
    }


    private var accessibilityValue: String {
        if recorder.isPreparing { return "正在准备录音" }
        if recorder.isRecording { return "正在录音，时长 \(recorder.duration.formattedRecordingDuration)" }
        return "尚未开始录音"
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recorder.isRecording ? Color.red : AppTheme.secondaryText.opacity(0.22))
                .frame(width: 8, height: 8)
                .shadow(color: recorder.isRecording ? Color.red.opacity(0.38) : .clear, radius: 6)

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

    private var voicePad: some View {
        ZStack {
            Circle()
                .fill(kind.tint.opacity(fingerDown ? 0.19 : 0.10))
                .frame(width: 142, height: 142)
                .blur(radius: fingerDown ? 0 : 3)

            Circle()
                .fill(Color.white.opacity(fingerDown ? 0.78 : 0.58))
                .frame(width: 112, height: 112)
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
                Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 33, weight: .semibold))
                    .foregroundStyle(cancelProgress >= 1 ? AppTheme.secondaryText : kind.tint)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
            }
        }
        .scaleEffect(fingerDown ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: fingerDown)
        .highPriorityGesture(recordingGesture, including: isDisabled ? .none : .all)
    }

    private var instructionTitle: String {
        if cancelProgress >= 1 { return "松开，这段就不会留下" }
        if recorder.isPreparing { return "保持按住" }
        if recorder.isRecording { return "正在录音" }
        return "按住说话"
    }

    private var instructionDetail: String {
        if recorder.isRecording {
            return "松开后会直接封好并放进\(kind.title)，不再出现确认按钮"
        }
        return "长按开始 · 向左滑取消 · 松开完成"
    }

    private var cancelProgress: CGFloat {
        min(max(-dragX / cancelDistance, 0), 1)
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isDisabled else { return }
                if !fingerDown {
                    beginRecordingGesture()
                }
                dragX = min(0, value.translation.width)
                let shouldCancel = -value.translation.width >= cancelDistance
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
                finishRecordingGesture(cancelled: -value.translation.width >= cancelDistance)
            }
    }

    private func beginRecordingGesture() {
        fingerDown = true
        dragX = 0
        crossedCancelThreshold = false
        let sessionID = UUID()
        currentSessionID = sessionID
        RitualHaptics.medium()

        Task { @MainActor in
            let started = await recorder.start()
            guard currentSessionID == sessionID, fingerDown else {
                if started { recorder.discard() }
                return
            }
            if !started, let message = recorder.errorMessage {
                fingerDown = false
                currentSessionID = nil
                onError(message)
            }
        }
    }

    private func resetGestureState() {
        fingerDown = false
        dragX = 0
        crossedCancelThreshold = false
        currentSessionID = nil
    }

    private func finishRecordingGesture(cancelled: Bool) {
        resetGestureState()

        guard recorder.isRecording else { return }
        if cancelled {
            recorder.discard()
            onCancelled()
            return
        }

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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 6.5
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<25, id: \.self) { index in
                    let wave = (sin(phase + Double(index) * 0.72) + 1) / 2
                    let centerWeight = 1 - abs(Double(index) - 12) / 18
                    let liveLevel = isActive ? max(0.10, min(1, level * 1.65)) : 0.06
                    let height = 7 + 43 * liveLevel * (0.32 + wave * 0.68) * centerWeight

                    Capsule()
                        .fill(tint.opacity(isActive ? 0.70 : 0.24))
                        .frame(width: 3.5, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
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
