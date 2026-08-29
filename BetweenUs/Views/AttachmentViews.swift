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
            .accessibilityLabel("移除附件".localized)
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
            return "录音时长 %@".localized(duration.formattedDuration)
        }
        return draft.originalFilename ?? "已准备".localized
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
                    VideoAttachmentView(url: url)
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
            Text("正在从 iCloud 下载附件")
                .font(.subheadline.weight(.semibold))
            Text("请保持网络连接，稍后重试")
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

struct AttachmentCollectionView: View {
    let attachments: [AttachmentMetadata]
    var tint: Color = ContainerKind.capsule.tint

    private let mediaStore = MediaFileStore()

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        if images.count == attachments.count, images.count > 1 {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 7),
                count: images.count == 2 ? 2 : 3
            )
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, attachment in
                    SavedImageTile(
                        image: UIImage(contentsOfFile: mediaStore.url(for: attachment).path)
                    )
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                    AttachmentContentView(attachment: attachment, tint: tint)
                }
            }
        }
    }
}

private struct SavedImageTile: View {
    let image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.42))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.title2)
                Text("照片暂时无法显示")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 170)
        }
    }
}

private struct VideoAttachmentView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            .accessibilityLabel(controller.isPlaying ? "暂停语音".localized : "播放语音".localized)

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
        .onDisappear { controller.stop() }
    }

    private var totalDuration: TimeInterval {
        controller.duration > 0 ? controller.duration : expectedDuration ?? 0
    }
}

struct VoiceDraftPreviewPlayer: View {
    @StateObject private var controller: AudioPlaybackController
    let expectedDuration: TimeInterval?
    let tint: Color
    let discard: () -> Void
    let commit: () -> Void

    init(
        url: URL,
        expectedDuration: TimeInterval?,
        tint: Color,
        discard: @escaping () -> Void,
        commit: @escaping () -> Void
    ) {
        _controller = StateObject(wrappedValue: AudioPlaybackController(url: url))
        self.expectedDuration = expectedDuration
        self.tint = tint
        self.discard = discard
        self.commit = commit
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                controller.stop()
                RitualHaptics.selection()
                discard()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.42))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.68), lineWidth: 1)
                    }
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel("删除录音并重录".localized)

            HStack(spacing: 8) {
                Button(action: controller.toggle) {
                    HStack(spacing: 3) {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .offset(x: controller.isPlaying ? 0 : 1)

                        Text(displayedDuration.formattedDuration)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 22)
                    .background(Color.white.opacity(0.52))
                    .clipShape(Capsule())
                }
                .buttonStyle(SoftScaleButtonStyle())
                .accessibilityLabel(controller.isPlaying ? "暂停语音".localized : "播放语音".localized)

                AudioWaveformScrubber(
                    progress: controller.progress,
                    isPlaying: controller.isPlaying,
                    tint: tint,
                    onSeek: { controller.seek(progress: $0) }
                )
                .frame(height: 13)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.38))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.66), lineWidth: 1)
            }

            Button(action: commit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint)
                    .clipShape(Circle())
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel("保存并放入容器".localized)
        }
        .frame(maxWidth: 360)
        .onDisappear { controller.stop() }
    }

    private var displayedDuration: TimeInterval {
        if controller.isPlaying || controller.currentTime > 0 {
            return controller.currentTime
        }
        return controller.duration > 0 ? controller.duration : expectedDuration ?? 0
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
                    let minimumBarHeight = max(3, proxy.size.height * 0.24)
                    let barHeight = minimumBarHeight + max(0, proxy.size.height - minimumBarHeight) * pseudoWave
                    Capsule()
                        .fill(normalizedIndex <= progress ? tint.opacity(0.84) : AppTheme.secondaryText.opacity(0.16))
                        .frame(width: 3, height: barHeight)
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
        .accessibilityLabel("语音播放进度".localized)
        .accessibilityValue("百分之 %d".localized(Int(progress * 100)))
    }
}

extension TimeInterval {
    var formattedDuration: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
