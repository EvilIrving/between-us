import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    private var recordingSessionID: UUID?

    @discardableResult
    func preparePermission() async -> Bool {
        guard !isPreparing, !isRecording else { return isRecording }
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        let granted = await requestPermission()
        if !granted {
            errorMessage = "需要麦克风权限，才能把这句话录下来。"
        }
        return granted
    }

    @discardableResult
    func start() async -> Bool {
        guard !isRecording, !isPreparing else { return isRecording }
        errorMessage = nil
        isPreparing = true
        let sessionID = UUID()
        recordingSessionID = sessionID
        defer {
            if recordingSessionID == sessionID || recordingSessionID == nil {
                isPreparing = false
            }
        }

        guard await requestPermission() else {
            if recordingSessionID == sessionID {
                recordingSessionID = nil
                errorMessage = "需要麦克风权限，才能把这句话录下来。"
            }
            return false
        }
        guard recordingSessionID == sessionID else { return false }

        do {
            try await RecordingAudioSession.shared.activate()
            // 激活期间用户可能已经松手取消，取消路径自己会停用会话，这里不能再建一个没人管的录音器。
            guard recordingSessionID == sessionID else { return false }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("between-us-\(UUID().uuidString.lowercased()).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else { throw AudioRecorderError.failedToStart }

            self.recorder = recorder
            fileURL = url
            isRecording = true
            duration = 0
            startTimer()
            return true
        } catch {
            errorMessage = T("这次没有录下来：%@", error.localizedDescription)
            discard()
            return false
        }
    }

    func stop() -> AttachmentDraft? {
        guard isRecording, let recorder, let fileURL else { return nil }
        let recordedDuration = recorder.currentTime
        recorder.stop()
        stopTimer()
        self.recorder = nil
        self.fileURL = nil
        recordingSessionID = nil
        isRecording = false
        duration = recordedDuration
        Task { await RecordingAudioSession.shared.deactivate() }

        return AttachmentDraft(
            kind: .audio,
            url: fileURL,
            originalFilename: "语音.m4a",
            duration: recordedDuration
        )
    }

    func discard() {
        recordingSessionID = nil
        recorder?.stop()
        recorder = nil
        stopTimer()
        isPreparing = false
        isRecording = false
        duration = 0
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        Task { await RecordingAudioSession.shared.deactivate() }
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.duration = recorder.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// 会话配置与激活要一直等到系统完成路由协商才返回，放在主线程上正好卡在用户按住说话的那一刻。
/// 录音器的会话操作统一走这个串行 actor：不占主线程，停用与下一次激活也按发生顺序执行。
private actor RecordingAudioSession {
    static let shared = RecordingAudioSession()

    private let session = AVAudioSession.sharedInstance()

    func activate() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum AudioRecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? { "录音器无法启动。" }
}
