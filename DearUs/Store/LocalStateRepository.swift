import Foundation

struct LocalStateRepository: Sendable {
    private let fileURL: URL
    private let backupURL: URL

    init(filename: String = "dear-us-v1.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appendingPathComponent("DearUs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        self.fileURL = directoryURL.appendingPathComponent(filename)
        self.backupURL = directoryURL.appendingPathComponent("\(filename).backup")
    }

    func load() -> AppData {
        if let state = decode(at: fileURL) {
            return state
        }
        if let recovered = decode(at: backupURL) {
            try? recoveredDataWrite(recovered)
            return recovered
        }
        return AppData()
    }

    func save(_ state: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)

        if FileManager.default.fileExists(atPath: fileURL.path), decode(at: fileURL) != nil {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }

        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func reset() throws {
        for url in [fileURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func decode(at url: URL) -> AppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: data)
    }

    private func recoveredDataWrite(_ state: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

struct ComposeDraftSnapshot: Sendable {
    var text: String
    var attachment: AttachmentDraft?
}

struct ComposeDraftRepository: Sendable {
    private struct StoredDraft: Codable {
        var text = ""
        var attachment: StoredAttachment?

        var isEmpty: Bool { text.isEmpty && attachment == nil }
    }

    private struct StoredAttachment: Codable {
        var kind: AttachmentKind
        var localFilename: String
        var originalFilename: String?
        var duration: TimeInterval?
    }

    private let fileURL: URL
    private let mediaDirectoryURL: URL

    init(filename: String = "compose-drafts-v2.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appendingPathComponent("DearUs", isDirectory: true)
        mediaDirectoryURL = directoryURL.appendingPathComponent("DraftMedia", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        fileURL = directoryURL.appendingPathComponent(filename)
    }

    func snapshot(spaceID: String, kind: ContainerKind) -> ComposeDraftSnapshot {
        let stored = load()[key(spaceID: spaceID, kind: kind)] ?? StoredDraft()
        let attachment = stored.attachment.flatMap { value -> AttachmentDraft? in
            let url = mediaDirectoryURL.appendingPathComponent(value.localFilename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AttachmentDraft(
                kind: value.kind,
                url: url,
                originalFilename: value.originalFilename,
                duration: value.duration
            )
        }
        return ComposeDraftSnapshot(text: stored.text, attachment: attachment)
    }

    func text(spaceID: String, kind: ContainerKind) -> String {
        snapshot(spaceID: spaceID, kind: kind).text
    }

    func saveText(_ text: String, spaceID: String, kind: ContainerKind) {
        var drafts = load()
        let draftKey = key(spaceID: spaceID, kind: kind)
        var draft = drafts[draftKey] ?? StoredDraft()
        draft.text = text
        drafts[draftKey] = draft.isEmpty ? nil : draft
        persist(drafts)
    }

    func storeAttachment(
        _ attachment: AttachmentDraft,
        spaceID: String,
        kind: ContainerKind
    ) throws -> AttachmentDraft {
        var drafts = load()
        let draftKey = key(spaceID: spaceID, kind: kind)
        var storedDraft = drafts[draftKey] ?? StoredDraft()
        let previousAttachment = storedDraft.attachment

        let fileExtension = attachment.url.pathExtension.isEmpty
            ? defaultExtension(for: attachment.kind)
            : attachment.url.pathExtension.lowercased()
        let filename = "\(UUID().uuidString.lowercased())-\(attachment.kind.rawValue).\(fileExtension)"
        let destination = mediaDirectoryURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: attachment.url, to: destination)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )

        storedDraft.attachment = StoredAttachment(
            kind: attachment.kind,
            localFilename: filename,
            originalFilename: attachment.originalFilename,
            duration: attachment.duration
        )
        drafts[draftKey] = storedDraft
        do {
            try persistOrThrow(drafts)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        removeFile(for: previousAttachment)

        return AttachmentDraft(
            kind: attachment.kind,
            url: destination,
            originalFilename: attachment.originalFilename,
            duration: attachment.duration
        )
    }

    func removeAttachment(spaceID: String, kind: ContainerKind) {
        var drafts = load()
        let draftKey = key(spaceID: spaceID, kind: kind)
        guard var draft = drafts[draftKey] else { return }
        removeFile(for: draft.attachment)
        draft.attachment = nil
        drafts[draftKey] = draft.isEmpty ? nil : draft
        persist(drafts)
    }

    func clear(spaceID: String, kind: ContainerKind) {
        var drafts = load()
        let draftKey = key(spaceID: spaceID, kind: kind)
        removeFile(for: drafts[draftKey]?.attachment)
        drafts[draftKey] = nil
        persist(drafts)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: mediaDirectoryURL)
        try? FileManager.default.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func key(spaceID: String, kind: ContainerKind) -> String {
        "\(spaceID)|\(kind.rawValue)"
    }

    private func load() -> [String: StoredDraft] {
        guard let data = try? Data(contentsOf: fileURL),
              let drafts = try? JSONDecoder().decode([String: StoredDraft].self, from: data) else {
            return [:]
        }
        return drafts
    }

    private func persist(_ drafts: [String: StoredDraft]) {
        try? persistOrThrow(drafts)
    }

    private func persistOrThrow(_ drafts: [String: StoredDraft]) throws {
        guard !drafts.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        let data = try JSONEncoder().encode(drafts)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func removeFile(for attachment: StoredAttachment?) {
        guard let attachment else { return }
        let url = mediaDirectoryURL.appendingPathComponent(attachment.localFilename)
        try? FileManager.default.removeItem(at: url)
    }

    private func defaultExtension(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "jpg"
        case .video: return "mov"
        case .audio: return "m4a"
        }
    }
}
