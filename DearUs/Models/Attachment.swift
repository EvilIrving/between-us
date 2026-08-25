import Foundation

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio

    var title: String {
        switch self {
        case .image: return "照片"
        case .video: return "视频"
        case .audio: return "语音"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }
}

struct AttachmentMetadata: Codable, Hashable, Sendable {
    var kind: AttachmentKind
    var localFilename: String
    var originalFilename: String?
    var duration: TimeInterval?
    var byteCount: Int64
}

struct AttachmentDraft: Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: AttachmentKind
    var url: URL
    var originalFilename: String?
    var duration: TimeInterval?
}
