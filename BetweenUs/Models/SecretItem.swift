import CloudKit
import Foundation

struct SecretItem: Identifiable, Codable, Hashable, Sendable {
    static let recordType: CKRecord.RecordType = "BetweenUsItem"

    var id: UUID
    var kind: ContainerKind
    var authorID: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var openedByID: String?
    var openedAt: Date?
    var attachment: AttachmentMetadata?
    var additionalAttachments: [AttachmentMetadata]?
    var lastKnownRecordData: Data?

    init(
        id: UUID = UUID(),
        kind: ContainerKind,
        authorID: String,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        openedByID: String? = nil,
        openedAt: Date? = nil,
        attachment: AttachmentMetadata? = nil,
        additionalAttachments: [AttachmentMetadata]? = nil,
        lastKnownRecordData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.authorID = authorID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.openedByID = openedByID
        self.openedAt = openedAt
        self.attachment = attachment
        self.additionalAttachments = additionalAttachments
        self.lastKnownRecordData = lastKnownRecordData
    }

    var recordName: String { id.uuidString.lowercased() }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !allAttachments.isEmpty
    }

    var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let images = allAttachments.filter { $0.kind == .image }
        if !images.isEmpty {
            return images.count == 1 ? "一张照片".localized : "%d 张照片".localized(images.count)
        }
        let videos = allAttachments.filter { $0.kind == .video }
        if !videos.isEmpty {
            return videos.count == 1 ? "一段视频".localized : "%d 个视频".localized(videos.count)
        }
        return attachment?.kind.title ?? "一段内容".localized
    }

    var allAttachments: [AttachmentMetadata] {
        (attachment.map { [$0] } ?? []) + (additionalAttachments ?? [])
    }
}

extension SecretItem {
    enum Field {
        static let schemaVersion = "schemaVersion"
        static let kind = "kind"
        static let text = "text"
        static let authorID = "authorID"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let openedByID = "openedByID"
        static let openedAt = "openedAt"
        static let attachmentKind = "attachmentKind"
        static let attachment = "attachment"
        static let originalFilename = "originalFilename"
        static let duration = "duration"
        static let byteCount = "byteCount"
    }

    func recordID(in relationship: RelationshipLocator) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: relationship.zoneID)
    }

    init?(record: CKRecord, mediaStore: MediaFileStore) {
        guard record.recordType == Self.recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let kindRawValue = record[Field.kind] as? String,
              let kind = ContainerKind(rawValue: kindRawValue),
              let text = record.encryptedValues[Field.text] as? String,
              let authorID = record.encryptedValues[Field.authorID] as? String,
              let createdAt = record[Field.createdAt] as? Date,
              let updatedAt = record[Field.updatedAt] as? Date else {
            return nil
        }

        var attachmentMetadata: AttachmentMetadata?
        if let attachmentKindRaw = record[Field.attachmentKind] as? String,
           let attachmentKind = AttachmentKind(rawValue: attachmentKindRaw),
           let asset = record[Field.attachment] as? CKAsset,
           let assetURL = asset.fileURL {
            let byteCount = (record[Field.byteCount] as? NSNumber)?.int64Value
            let duration = (record[Field.duration] as? NSNumber)?.doubleValue
            let originalFilename = record[Field.originalFilename] as? String
            attachmentMetadata = (try? mediaStore.persistDownloadedAsset(
                sourceURL: assetURL,
                recordName: record.recordID.recordName,
                kind: attachmentKind,
                originalFilename: originalFilename,
                duration: duration,
                expectedByteCount: byteCount
            )) ?? mediaStore.downloadedAssetMetadata(
                sourceURL: assetURL,
                recordName: record.recordID.recordName,
                kind: attachmentKind,
                originalFilename: originalFilename,
                duration: duration,
                expectedByteCount: byteCount
            )
        }

        self.init(
            id: id,
            kind: kind,
            authorID: authorID,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            openedByID: record.encryptedValues[Field.openedByID] as? String,
            openedAt: record.encryptedValues[Field.openedAt] as? Date,
            attachment: attachmentMetadata
        )
        self.lastKnownRecord = record
    }

    func populate(_ record: CKRecord, mediaStore: MediaFileStore) {
        record[Field.schemaVersion] = 1 as CKRecordValue
        record[Field.kind] = kind.rawValue as CKRecordValue
        record[Field.createdAt] = createdAt as CKRecordValue
        record[Field.updatedAt] = updatedAt as CKRecordValue
        record.encryptedValues[Field.text] = text as CKRecordValue
        record.encryptedValues[Field.authorID] = authorID as CKRecordValue

        if let openedByID {
            record.encryptedValues[Field.openedByID] = openedByID as CKRecordValue
        } else {
            record.encryptedValues[Field.openedByID] = nil
        }
        if let openedAt {
            record.encryptedValues[Field.openedAt] = openedAt as CKRecordValue
        } else {
            record.encryptedValues[Field.openedAt] = nil
        }

        if let attachment, mediaStore.fileExists(for: attachment) {
            record[Field.attachmentKind] = attachment.kind.rawValue as CKRecordValue
            if let originalFilename = attachment.originalFilename {
                record[Field.originalFilename] = originalFilename as CKRecordValue
            } else {
                record[Field.originalFilename] = nil
            }
            if let duration = attachment.duration {
                record[Field.duration] = duration as CKRecordValue
            } else {
                record[Field.duration] = nil
            }
            record[Field.byteCount] = NSNumber(value: attachment.byteCount)
            record[Field.attachment] = CKAsset(fileURL: mediaStore.url(for: attachment))
        } else {
            record[Field.attachmentKind] = nil
            record[Field.originalFilename] = nil
            record[Field.duration] = nil
            record[Field.byteCount] = nil
            record[Field.attachment] = nil
        }
    }

    mutating func mergeFromServerRecord(_ record: CKRecord, mediaStore: MediaFileStore) -> Bool {
        guard var remote = SecretItem(record: record, mediaStore: mediaStore) else { return false }
        remote.additionalAttachments = additionalAttachments

        // Opening an item only changes its open metadata. If a transient CKAsset download
        // fails during that merge, keep the valid local copy instead of accidentally
        // uploading a record with its attachment fields cleared.
        if let localAttachment = attachment,
           mediaStore.fileExists(for: localAttachment),
           remote.attachment.map({ !mediaStore.fileExists(for: $0) }) ?? true {
            remote.attachment = localAttachment
        }

        let localOpenNeedsUpload = openedAt != nil && remote.openedAt == nil
        if localOpenNeedsUpload {
            remote.openedByID = openedByID
            remote.openedAt = openedAt
            remote.updatedAt = max(updatedAt, remote.updatedAt)
            remote.lastKnownRecord = record
            self = remote
            return true
        }

        self = remote
        return false
    }

    mutating func setLastKnownRecordIfNewer(_ record: CKRecord) {
        guard record.recordID.recordName.caseInsensitiveCompare(recordName) == .orderedSame else { return }
        if let currentDate = lastKnownRecord?.modificationDate,
           let incomingDate = record.modificationDate,
           currentDate >= incomingDate {
            return
        }
        lastKnownRecord = record
    }

    var lastKnownRecord: CKRecord? {
        get {
            guard let lastKnownRecordData else { return nil }
            do {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: lastKnownRecordData)
                unarchiver.requiresSecureCoding = true
                return CKRecord(coder: unarchiver)
            } catch {
                return nil
            }
        }
        set {
            guard let newValue else {
                lastKnownRecordData = nil
                return
            }
            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            newValue.encodeSystemFields(with: archiver)
            lastKnownRecordData = archiver.encodedData
        }
    }
}
