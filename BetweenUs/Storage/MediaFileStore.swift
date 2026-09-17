import Foundation

struct LocalPreviewAttachments: Sendable {
    let images: [AttachmentMetadata]
    let videos: [AttachmentMetadata]
    let audio: AttachmentMetadata
}

/// 本机预览使用的真实素材，随 app 包发布。
/// 对应的源文件在 `BetweenUs/PreviewAssets/`，替换素材后只需同步这里的时长。
enum PreviewResource {
    static let directory = "PreviewAssets"

    struct Spec {
        let name: String
        let kind: AttachmentKind
        let duration: TimeInterval?
    }

    static let images: [Spec] = (1...5).map {
        Spec(name: "preview-photo-\($0).jpg", kind: .image, duration: nil)
    }

    static let videos: [Spec] = [
        Spec(name: "preview-video-1.mp4", kind: .video, duration: 87.28)
    ]

    static let audio = Spec(name: "preview-audio-1.mp3", kind: .audio, duration: 600)
}

struct MediaFileStore: Sendable {
    static let maximumAttachmentBytes: Int64 = 48 * 1024 * 1024

    let directoryURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directoryURL = baseURL
            .appendingPathComponent("BetweenUs", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func importDraft(_ draft: AttachmentDraft, itemID: UUID, slot: Int = 0) throws -> AttachmentMetadata {
        let byteCount = fileSize(at: draft.url)
        guard byteCount > 0 else { throw MediaFileError.unavailable }
        guard byteCount <= Self.maximumAttachmentBytes else { throw MediaFileError.fileTooLarge }

        let fileExtension = resolvedExtension(kind: draft.kind, sourceURL: draft.url)
        let filename = "\(itemID.uuidString.lowercased())-\(slot)-\(draft.kind.rawValue).\(fileExtension)"
        let destination = directoryURL.appendingPathComponent(filename)
        try replace(destination: destination, source: draft.url)
        protect(destination)

        return AttachmentMetadata(
            kind: draft.kind,
            localFilename: filename,
            originalFilename: draft.originalFilename,
            duration: draft.duration,
            byteCount: fileSize(at: destination)
        )
    }

    func persistDownloadedAsset(
        sourceURL: URL,
        recordName: String,
        kind: AttachmentKind,
        originalFilename: String?,
        duration: TimeInterval?,
        expectedByteCount: Int64?
    ) throws -> AttachmentMetadata {
        let metadata = downloadedAssetMetadata(
            sourceURL: sourceURL,
            recordName: recordName,
            kind: kind,
            originalFilename: originalFilename,
            duration: duration,
            expectedByteCount: expectedByteCount
        )
        let filename = metadata.localFilename
        let destination = directoryURL.appendingPathComponent(filename)

        let existingSize = fileSize(at: destination)
        if !FileManager.default.fileExists(atPath: destination.path)
            || ((expectedByteCount ?? 0) > 0 && existingSize != expectedByteCount) {
            try replace(destination: destination, source: sourceURL)
            protect(destination)
        }

        return AttachmentMetadata(
            kind: kind,
            localFilename: filename,
            originalFilename: originalFilename,
            duration: duration,
            byteCount: fileSize(at: destination)
        )
    }

    func downloadedAssetMetadata(
        sourceURL: URL,
        recordName: String,
        kind: AttachmentKind,
        originalFilename: String?,
        duration: TimeInterval?,
        expectedByteCount: Int64?
    ) -> AttachmentMetadata {
        let fileExtension = resolvedExtension(kind: kind, sourceURL: sourceURL)
        let safeRecordName = recordName.replacingOccurrences(of: "/", with: "-").lowercased()
        return AttachmentMetadata(
            kind: kind,
            localFilename: "\(safeRecordName)-\(kind.rawValue).\(fileExtension)",
            originalFilename: originalFilename,
            duration: duration,
            byteCount: expectedByteCount ?? 0
        )
    }

    func url(for attachment: AttachmentMetadata) -> URL {
        directoryURL.appendingPathComponent(attachment.localFilename)
    }

    func fileExists(for attachment: AttachmentMetadata) -> Bool {
        FileManager.default.fileExists(atPath: url(for: attachment).path)
    }

    func remove(_ attachment: AttachmentMetadata) throws {
        let url = url(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func removeAll() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    func ensureLocalPreviewAttachments() throws -> LocalPreviewAttachments {
        var images: [AttachmentMetadata] = []
        for spec in PreviewResource.images {
            if let metadata = try installPreviewResource(spec) { images.append(metadata) }
        }

        var videos: [AttachmentMetadata] = []
        for spec in PreviewResource.videos {
            if let metadata = try installPreviewResource(spec) { videos.append(metadata) }
        }

        guard let audio = try installPreviewResource(PreviewResource.audio) else {
            throw MediaFileError.unavailable
        }

        return LocalPreviewAttachments(images: images, videos: videos, audio: audio)
    }

    /// 把包里随附录制的预览素材释放到媒体目录，本地文件名与包内名一致。
    private func installPreviewResource(_ spec: PreviewResource.Spec) throws -> AttachmentMetadata? {
        let fileExtension = (spec.name as NSString).pathExtension
        let baseName = (spec.name as NSString).deletingPathExtension
        guard let source = Bundle.main.url(
            forResource: baseName,
            withExtension: fileExtension,
            subdirectory: PreviewResource.directory
        ) else { return nil }

        let destination = directoryURL.appendingPathComponent(spec.name)
        if fileSize(at: destination) != fileSize(at: source) {
            try replace(destination: destination, source: source)
            protect(destination)
        }

        return AttachmentMetadata(
            kind: spec.kind,
            localFilename: spec.name,
            originalFilename: spec.name,
            duration: spec.duration,
            byteCount: fileSize(at: destination)
        )
    }

    private func replace(destination: URL, source: URL) throws {
        if destination.standardizedFileURL == source.standardizedFileURL { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func fileSize(at url: URL) -> Int64 {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? 0)
    }

    private func resolvedExtension(kind: AttachmentKind, sourceURL: URL) -> String {
        let value = sourceURL.pathExtension.lowercased()
        if !value.isEmpty { return value }
        switch kind {
        case .image: return "jpg"
        case .video: return "mov"
        case .audio: return "m4a"
        }
    }

    private func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

}

enum MediaFileError: LocalizedError {
    case fileTooLarge
    case unavailable

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "单个照片、视频或语音不能超过 48 MB。"
        case .unavailable: return "这份媒体文件暂时不可用。"
        }
    }
}
