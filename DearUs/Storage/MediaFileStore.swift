import Foundation

struct MediaFileStore: Sendable {
    static let maximumAttachmentBytes: Int64 = 48 * 1024 * 1024

    let directoryURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directoryURL = baseURL
            .appendingPathComponent("DearUs", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func importDraft(_ draft: AttachmentDraft, itemID: UUID) throws -> AttachmentMetadata {
        let byteCount = fileSize(at: draft.url)
        guard byteCount > 0 else { throw MediaFileError.unavailable }
        guard byteCount <= Self.maximumAttachmentBytes else { throw MediaFileError.fileTooLarge }

        let fileExtension = resolvedExtension(kind: draft.kind, sourceURL: draft.url)
        let filename = "\(itemID.uuidString.lowercased())-\(draft.kind.rawValue).\(fileExtension)"
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
