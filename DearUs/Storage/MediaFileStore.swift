import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LocalPreviewAttachments: Sendable {
    let images: [AttachmentMetadata]
    let audio: AttachmentMetadata
}

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
        for index in 0..<3 {
            let imageFilename = "preview-window-light-\(index + 1).jpg"
            let imageURL = directoryURL.appendingPathComponent(imageFilename)
            if fileSize(at: imageURL) == 0 {
                try writePreviewImage(to: imageURL, variant: index)
                protect(imageURL)
            }
            images.append(
                AttachmentMetadata(
                    kind: .image,
                    localFilename: imageFilename,
                    originalFilename: "窗边的光-\(index + 1).jpg",
                    duration: nil,
                    byteCount: fileSize(at: imageURL)
                )
            )
        }

        let audioFilename = "preview-voice-note-long.wav"
        let audioURL = directoryURL.appendingPathComponent(audioFilename)
        if fileSize(at: audioURL) == 0 {
            try previewAudioData().write(to: audioURL, options: .atomic)
            protect(audioURL)
        }

        return LocalPreviewAttachments(
            images: images,
            audio: AttachmentMetadata(
                kind: .audio,
                localFilename: audioFilename,
                originalFilename: "想对你说.wav",
                duration: 76,
                byteCount: fileSize(at: audioURL)
            )
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

    private func writePreviewImage(to url: URL, variant: Int) throws {
        let width = 900
        let height = 680
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MediaFileError.unavailable }

        let palettes: [[CGColor]] = [
            [CGColor(red: 0.98, green: 0.90, blue: 0.75, alpha: 1), CGColor(red: 0.70, green: 0.78, blue: 0.70, alpha: 1), CGColor(red: 0.34, green: 0.43, blue: 0.39, alpha: 1)],
            [CGColor(red: 0.91, green: 0.81, blue: 0.72, alpha: 1), CGColor(red: 0.63, green: 0.71, blue: 0.73, alpha: 1), CGColor(red: 0.30, green: 0.37, blue: 0.43, alpha: 1)],
            [CGColor(red: 0.99, green: 0.84, blue: 0.62, alpha: 1), CGColor(red: 0.75, green: 0.66, blue: 0.58, alpha: 1), CGColor(red: 0.38, green: 0.34, blue: 0.34, alpha: 1)]
        ]
        let backgroundColors = palettes[variant % palettes.count] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: backgroundColors,
            locations: [0, 0.54, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 80, y: height),
                end: CGPoint(x: width, y: 0),
                options: []
            )
        }

        context.setFillColor(CGColor(red: 1, green: 0.91, blue: 0.70, alpha: 0.52))
        context.fillEllipse(in: CGRect(x: 54, y: 208, width: 450, height: 450))

        context.setFillColor(CGColor(red: 0.36, green: 0.25, blue: 0.19, alpha: 0.82))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 238))

        context.setFillColor(CGColor(red: 0.87, green: 0.76, blue: 0.56, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 160, y: 140, width: 230, height: 190), cornerWidth: 46, cornerHeight: 46, transform: nil))
        context.fillPath()
        context.setStrokeColor(CGColor(red: 0.36, green: 0.27, blue: 0.21, alpha: 0.46))
        context.setLineWidth(12)
        context.strokeEllipse(in: CGRect(x: 325, y: 190, width: 112, height: 96))

        context.setFillColor(CGColor(red: 0.39, green: 0.52, blue: 0.40, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 492, y: 112, width: 202, height: 174), cornerWidth: 42, cornerHeight: 42, transform: nil))
        context.fillPath()
        context.setStrokeColor(CGColor(red: 0.88, green: 0.85, blue: 0.69, alpha: 0.55))
        context.setLineWidth(8)
        context.strokeEllipse(in: CGRect(x: 651, y: 158, width: 92, height: 82))

        context.setFillColor(CGColor(red: 0.96, green: 0.86, blue: 0.65, alpha: 0.82))
        context.fillEllipse(in: CGRect(x: 191, y: 258, width: 166, height: 30))
        context.setFillColor(CGColor(red: 0.18, green: 0.14, blue: 0.12, alpha: 0.72))
        context.fillEllipse(in: CGRect(x: 523, y: 229, width: 140, height: 25))

        context.setStrokeColor(CGColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 0.78))
        context.setLineWidth(7)
        context.move(to: CGPoint(x: 758, y: 218))
        context.addCurve(to: CGPoint(x: 794, y: 520), control1: CGPoint(x: 734, y: 326), control2: CGPoint(x: 824, y: 402))
        context.strokePath()
        context.setFillColor(CGColor(red: 0.38, green: 0.55, blue: 0.40, alpha: 0.88))
        context.fillEllipse(in: CGRect(x: 714, y: 380, width: 92, height: 48))
        context.fillEllipse(in: CGRect(x: 775, y: 445, width: 84, height: 44))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else { throw MediaFileError.unavailable }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw MediaFileError.unavailable }
    }

    private func previewAudioData() -> Data {
        let sampleRate = 16_000
        let duration = 76.0
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let phrasePosition = time.truncatingRemainder(dividingBy: 0.72) / 0.72
            let syllableEnvelope = pow(sin(.pi * min(max(phrasePosition, 0), 1)), 1.7)
            let phraseEnvelope = min(1, time / 0.16) * min(1, (duration - time) / 0.24)
            let baseFrequency = 142 + 24 * sin(time * 2.1) + 15 * sin(time * 5.4)
            let voice = sin(2 * .pi * baseFrequency * time)
                + 0.34 * sin(2 * .pi * baseFrequency * 2.02 * time)
                + 0.15 * sin(2 * .pi * baseFrequency * 3.08 * time)
            let pause = phrasePosition > 0.78 ? 0.12 : 1.0
            let value = voice * syllableEnvelope * phraseEnvelope * pause * 0.20
            samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
        }

        var data = Data()
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(UInt32(36) + byteCount, to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt32(sampleRate), to: &data)
        appendLittleEndian(UInt32(sampleRate * 2), to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(byteCount, to: &data)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
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
