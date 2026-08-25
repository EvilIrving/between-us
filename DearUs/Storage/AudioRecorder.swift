import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var level: Double = 0
    @Published private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

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
        defer { isPreparing = false }

        guard await requestPermission() else {
            errorMessage = "需要麦克风权限，才能把这句话录下来。"
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dear-us-\(UUID().uuidString.lowercased()).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else { throw AudioRecorderError.failedToStart }

            self.recorder = recorder
            fileURL = url
            isRecording = true
            duration = 0
            level = 0
            startTimer()
            return true
        } catch {
            errorMessage = "这次没有录下来：\(error.localizedDescription)"
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
        isRecording = false
        duration = recordedDuration
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return AttachmentDraft(
            kind: .audio,
            url: fileURL,
            originalFilename: "语音.m4a",
            duration: recordedDuration
        )
    }

    func discard() {
        recorder?.stop()
        recorder = nil
        stopTimer()
        isRecording = false
        duration = 0
        level = 0
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.duration = recorder.currentTime
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                // Map the useful spoken-voice range (roughly -48...0 dB) to a calm 0...1 animation value.
                let normalized = max(0, min(1, (Double(power) + 48) / 48))
                self.level = pow(normalized, 1.45)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? { "录音器无法启动。" }
}
