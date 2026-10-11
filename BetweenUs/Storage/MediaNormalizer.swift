import AVFoundation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import WICompress

/// 从系统照片选择器取出文件本体，而不是先把整段视频读进 `Data`。
///
/// 视频走 `.movie`、图片走 `.image`，取回的是落在本应用临时目录里的原文件副本，
/// 调用方用完要删。缩放、转码、时长判断全部交给 `MediaNormalizer`，这里只负责搬运。
struct MediaPickerFile: Transferable {
    let kind: AttachmentKind
    let url: URL
    let originalFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            try MediaPickerFile(kind: .image, receivedFile: received.file)
        }

        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            try MediaPickerFile(kind: .video, receivedFile: received.file)
        }
    }

    private init(kind: AttachmentKind, receivedFile: URL) throws {
        let fileExtension = receivedFile.pathExtension.isEmpty
            ? (kind == .video ? "mov" : "jpg")
            : receivedFile.pathExtension.lowercased()
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("between-us-\(UUID().uuidString.lowercased()).\(fileExtension)")
        try FileManager.default.copyItem(at: receivedFile, to: copy)

        self.kind = kind
        self.url = copy
        self.originalFilename = "\(kind == .video ? "视频" : "照片").\(fileExtension)"
    }
}

/// 附件进入本机媒体库之前的归一化入口。
///
/// 图片：交给 `WICompress`（ImageIO 之上的一层）按长边下采样、编码 JPEG、剥掉位置等元数据，
/// 并把字节控制在给定上限内；视频：系统 720p H.264 导出，并执行产品上的时长上限；语音不改动。
///
/// 参数只此一份（`Parameters`），调用点不要另写缩放比例、码率或时长判断。
/// 以后加应用内拍摄、其他导入路径或重压历史内容，都走同一个入口。
struct MediaNormalizer: Sendable {
    struct Parameters: Sendable {
        /// 照片长边上限。3x 屏上一张整屏截图就要两千六百像素上下，压到两千放大立刻发虚。
        var imageMaxLongEdge = 2_560
        /// 单张照片的字节上限，质量由库自己搜到这个数以内。
        var imageMaximumBytes = 1_500_000
        /// 视频时长上限，产品规则「视频最长 1 分钟」读的就是它。
        var videoMaximumDuration: TimeInterval = 60
        /// 系统报出的时长有毫秒级误差，60 秒整的片子不能因此被拒。
        var videoDurationTolerance: TimeInterval = 0.5
        /// 720p H.264：系统编解码器里的兼容档，体积也够小。
        var videoExportPresetName = AVAssetExportPreset1280x720
        /// 已经比目标更小更低的片子原样入库：再导出一遍只会更大、更慢。
        var videoPassThroughLongEdge = 1_280
        var videoPassThroughBitrate: Float = 2_000_000
    }

    static let shared = MediaNormalizer()

    let parameters: Parameters

    init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    /// 归一化一个草稿。返回值沿用原 `id`，`url` 指向新的临时文件；
    /// 传入和返回的临时文件都由调用方负责清理。进度只来自视频导出。
    func normalize(
        _ draft: AttachmentDraft,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AttachmentDraft {
        switch draft.kind {
        case .image:
            return try await normalizedImage(draft)
        case .video:
            return try await normalizedVideo(draft, progress: progress)
        case .audio:
            return draft
        }
    }

    // MARK: - 图片

    private func normalizedImage(_ draft: AttachmentDraft) async throws -> AttachmentDraft {
        let target: WICompressionTarget
        do {
            target = try WICompressionTarget(
                maxBytes: parameters.imageMaximumBytes,
                sizing: WICompressionSizing(maximumPixelSize: parameters.imageMaxLongEdge),
                output: WIImageOutput(
                    // 透明图压到白底上，和纸、房间的底色一致；元数据在这里一并剥掉。
                    representation: .jpeg(background: .white),
                    metadata: .strip,
                    colorSpace: .convert(to: .sRGB)
                )
            )
        } catch {
            throw MediaNormalizerError.mediaUnreadable
        }

        let outputURL = temporaryFileURL(fileExtension: "jpg")
        do {
            let result = try await WICompressor.compress(contentsOf: draft.url, to: target)
            try result.data.write(to: outputURL, options: .atomic)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw MediaNormalizerError.mediaUnreadable
        }

        return AttachmentDraft(
            id: draft.id,
            kind: .image,
            url: outputURL,
            originalFilename: draft.originalFilename,
            duration: nil
        )
    }

    // MARK: - 视频

    private func normalizedVideo(
        _ draft: AttachmentDraft,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> AttachmentDraft {
        let asset = AVURLAsset(url: draft.url)
        guard let duration = try? await asset.load(.duration) else {
            throw MediaNormalizerError.mediaUnreadable
        }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw MediaNormalizerError.mediaUnreadable
        }
        guard seconds <= parameters.videoMaximumDuration + parameters.videoDurationTolerance else {
            throw MediaNormalizerError.videoTooLong
        }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            throw MediaNormalizerError.mediaUnreadable
        }

        if await isAlreadySmallerThanTarget(track) {
            return AttachmentDraft(
                id: draft.id,
                kind: .video,
                url: draft.url,
                originalFilename: draft.originalFilename,
                duration: seconds
            )
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: parameters.videoExportPresetName) else {
            throw MediaNormalizerError.mediaUnreadable
        }
        session.shouldOptimizeForNetworkUse = true

        let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let outputURL = temporaryFileURL(fileExtension: fileType == .mp4 ? "mp4" : "mov")
        do {
            try await export(session, to: outputURL, fileType: fileType, progress: progress)
            try Task.checkCancellation()
            // 导出成功但没落盘任何字节是坏结果，不能当成功交给上层的媒体库。
            guard MediaFileStore.fileSize(at: outputURL) > 0 else {
                throw MediaNormalizerError.videoExportFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if error is CancellationError { throw error }
            throw MediaNormalizerError.videoExportFailed
        }

        return AttachmentDraft(
            id: draft.id,
            kind: .video,
            url: outputURL,
            originalFilename: draft.originalFilename,
            duration: seconds
        )
    }

    private func isAlreadySmallerThanTarget(_ track: AVAssetTrack) async -> Bool {
        guard let naturalSize = try? await track.load(.naturalSize),
              let dataRate = try? await track.load(.estimatedDataRate) else {
            return false
        }
        return max(naturalSize.width, naturalSize.height) <= CGFloat(parameters.videoPassThroughLongEdge)
            && dataRate <= parameters.videoPassThroughBitrate
    }

    private func export(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let box = ExportSessionBox(session)

        if #available(iOS 18.0, *) {
            let progressTask = progress.map { report in
                Task {
                    for await state in box.session.states(updateInterval: 0.2) {
                        if case .exporting(let value) = state {
                            report(value.fractionCompleted)
                        }
                    }
                }
            }
            defer { progressTask?.cancel() }
            try await box.session.export(to: outputURL, as: fileType)
            return
        }

        session.outputURL = outputURL
        session.outputFileType = fileType
        let progressTask = progress.map { report in
            Task {
                // iOS 17 没有 states 序列，按时间读进度；导出本身跑在系统线程上。
                while !Task.isCancelled {
                    report(Double(box.session.progress))
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        defer { progressTask?.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // iOS 17 上没有可等待的异步导出，取消也不会中断正在编码的会话；
            // 任务被取消时等它自然结束，调用方丢掉输出文件。
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: box.session.error ?? MediaNormalizerError.videoExportFailed)
                }
            }
        }
    }

    // MARK: - 工具

    private func temporaryFileURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("between-us-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }
}

/// `AVAssetExportSession` 不是 Sendable，而进度循环和完成回调都要跨线程读它。
/// 这里只读系统自己维护的进度与终态，不并发调用它的可变方法，所以按不可变引用传递。
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum MediaNormalizerError: LocalizedError {
    /// 超过产品上限的视频；文案和 `MediaNormalizer.Parameters.videoMaximumDuration` 保持一致。
    case videoTooLong
    case mediaUnreadable
    case videoExportFailed

    var errorDescription: String? {
        switch self {
        case .videoTooLong: return T("视频最长 1 分钟")
        case .mediaUnreadable: return T("这份媒体暂时打不开，换一个试试。")
        case .videoExportFailed: return T("视频没能压缩，换一段试试。")
        }
    }
}
