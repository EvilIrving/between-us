import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct AttachmentDraftPreview: View {
    let draft: AttachmentDraft
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 14) {
                preview
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                        .lineLimit(2)
                }

                Spacer(minLength: 42)
            }
            .padding(13)
            .background(Color.white.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            }

            Button {
                RitualHaptics.selection()
                remove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.56))
                    .clipShape(Circle())
            }
            .buttonStyle(SoftScaleButtonStyle())
            .padding(10)
            .accessibilityLabel("移除附件")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if draft.kind == .image,
           let image = UIImage(contentsOfFile: draft.url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.44)
                Image(systemName: draft.kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var metadataText: String {
        if let duration = draft.duration {
            return "已经录下 \(duration.formattedDuration)"
        }
        return draft.originalFilename ?? "已经准备好"
    }
}

struct AttachmentContentView: View {
    let attachment: AttachmentMetadata
    var tint: Color = ContainerKind.capsule.tint

    private let mediaStore = MediaFileStore()

    var body: some View {
        let url = mediaStore.url(for: attachment)
        Group {
            if !mediaStore.fileExists(for: attachment) {
                unavailable
            } else {
                switch attachment.kind {
                case .image:
                    ImageAttachmentView(url: url)
                case .video:
                    LegacyVideoAttachmentView(url: url)
                case .audio:
                    AudioAttachmentView(url: url, expectedDuration: attachment.duration, tint: tint)
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 11) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 28, weight: .light))
            Text("这份内容还在从 iCloud 慢慢回来")
                .font(.subheadline.weight(.semibold))
            Text("保持网络连接，稍后再靠近它")
                .font(.caption)
                .opacity(0.68)
        }
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 148)
        .background(Color.white.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        }
    }
}

private struct ImageAttachmentView: View {
    let url: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 430)
                .padding(7)
                .background(Color.white.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.07), radius: 20, y: 10)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.title2)
                Text("照片暂时无法展开")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 170)
        }
    }
}

/// 1.1 no longer creates new video items, but this reader remains so content made by 1.0 is not lost.
private struct LegacyVideoAttachmentView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(spacing: 8) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text("这是 1.0 留下的视频；1.1 暂停新增视频写入")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.52))
        }
        .onDisappear { player.pause() }
    }
}

@MainActor
private final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(url: URL) {
        super.init()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            self.player = nil
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func toggle() {
        guard let player else { return }
        RitualHaptics.selection()
        if player.isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            if player.currentTime >= player.duration { player.currentTime = 0 }
            player.play()
            isPlaying = true
            startTimer()
        }
        currentTime = player.currentTime
    }

    func seek(progress: Double) {
        guard let player else { return }
        let clamped = min(max(progress, 0), 1)
        player.currentTime = clamped * player.duration
        currentTime = player.currentTime
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        player.currentTime = 0
        stopTimer()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct AudioAttachmentView: View {
    @StateObject private var controller: AudioPlaybackController
    let expectedDuration: TimeInterval?
    let tint: Color

    init(url: URL, expectedDuration: TimeInterval?, tint: Color) {
        _controller = StateObject(wrappedValue: AudioPlaybackController(url: url))
        self.expectedDuration = expectedDuration
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: controller.toggle) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(controller.isPlaying ? 0.18 : 0.10))
                        .frame(width: 86, height: 86)
                    Circle()
                        .fill(Color.white.opacity(0.62))
                        .frame(width: 64, height: 64)
                        .overlay { Circle().stroke(Color.white.opacity(0.72), lineWidth: 1) }
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tint)
                        .offset(x: controller.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel(controller.isPlaying ? "暂停语音" : "播放语音")

            AudioWaveformScrubber(
                progress: controller.progress,
                isPlaying: controller.isPlaying,
                tint: tint,
                onSeek: { controller.seek(progress: $0) }
            )
            .frame(height: 54)

            HStack {
                Text(controller.currentTime.formattedDuration)
                Spacer()
                Text(totalDuration.formattedDuration)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText.opacity(0.66))
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
        .onDisappear { controller.stop() }
    }

    private var totalDuration: TimeInterval {
        controller.duration > 0 ? controller.duration : expectedDuration ?? 0
    }
}

private struct AudioWaveformScrubber: View {
    let progress: Double
    let isPlaying: Bool
    let tint: Color
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<42, id: \.self) { index in
                    let normalizedIndex = Double(index) / 41
                    let pseudoWave = 0.26 + abs(sin(Double(index) * 1.73)) * 0.74
                    Capsule()
                        .fill(normalizedIndex <= progress ? tint.opacity(0.84) : AppTheme.secondaryText.opacity(0.16))
                        .frame(width: 3, height: 10 + 36 * pseudoWave)
                        .scaleEffect(y: isPlaying && abs(normalizedIndex - progress) < 0.08 ? 1.12 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        onSeek(Double(value.location.x / proxy.size.width))
                    }
            )
        }
        .animation(.easeOut(duration: 0.14), value: progress)
        .accessibilityElement()
        .accessibilityLabel("语音播放进度")
        .accessibilityValue("百分之 \(Int(progress * 100))")
    }
}

extension TimeInterval {
    var formattedDuration: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
