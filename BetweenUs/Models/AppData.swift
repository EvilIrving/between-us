import CloudKit
import Foundation

struct AppData: Codable, Sendable {
    var items: [String: SecretItem] = [:]
    var relationship: RelationshipLocator?
    var currentUserRecordName: String?
    var privateSyncState: CKSyncEngine.State.Serialization?
    var sharedSyncState: CKSyncEngine.State.Serialization?
    var dirtyRecordNames: Set<String> = []
    var lastSuccessfulSyncAt: Date?
    var hasCompletedInitialSync = false
    var isLocalPreview = false

    enum CodingKeys: String, CodingKey {
        case items
        case relationship
        case currentUserRecordName
        case privateSyncState
        case sharedSyncState
        case dirtyRecordNames
        case lastSuccessfulSyncAt
        case hasCompletedInitialSync
        case isLocalPreview
    }

    init(
        items: [String: SecretItem] = [:],
        relationship: RelationshipLocator? = nil,
        currentUserRecordName: String? = nil,
        privateSyncState: CKSyncEngine.State.Serialization? = nil,
        sharedSyncState: CKSyncEngine.State.Serialization? = nil,
        dirtyRecordNames: Set<String> = [],
        lastSuccessfulSyncAt: Date? = nil,
        hasCompletedInitialSync: Bool = false,
        isLocalPreview: Bool = false
    ) {
        self.items = items
        self.relationship = relationship
        self.currentUserRecordName = currentUserRecordName
        self.privateSyncState = privateSyncState
        self.sharedSyncState = sharedSyncState
        self.dirtyRecordNames = dirtyRecordNames
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.hasCompletedInitialSync = hasCompletedInitialSync
        self.isLocalPreview = isLocalPreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([String: SecretItem].self, forKey: .items) ?? [:]
        relationship = try container.decodeIfPresent(RelationshipLocator.self, forKey: .relationship)
        currentUserRecordName = try container.decodeIfPresent(String.self, forKey: .currentUserRecordName)
        privateSyncState = try container.decodeIfPresent(
            CKSyncEngine.State.Serialization.self,
            forKey: .privateSyncState
        )
        sharedSyncState = try container.decodeIfPresent(
            CKSyncEngine.State.Serialization.self,
            forKey: .sharedSyncState
        )
        dirtyRecordNames = try container.decodeIfPresent(Set<String>.self, forKey: .dirtyRecordNames) ?? []
        lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
        hasCompletedInitialSync = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialSync) ?? false
        isLocalPreview = try container.decodeIfPresent(Bool.self, forKey: .isLocalPreview) ?? false
    }

    mutating func normalizeRecordKeys() {
        guard !items.isEmpty else { return }
        items = Dictionary(uniqueKeysWithValues: items.values.map { ($0.recordName, $0) })
        dirtyRecordNames = Set(dirtyRecordNames.map { $0.lowercased() })
    }

    mutating func removeRelationshipData() {
        items = [:]
        relationship = nil
        dirtyRecordNames = []
        lastSuccessfulSyncAt = nil
        hasCompletedInitialSync = false
        isLocalPreview = false
    }
}

enum LocalPreview {
    static let currentUserID = "preview-self"
    static let counterpartID = "preview-other"

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func makeAppData() -> AppData {
        let items = seededItems()
        return AppData(
            items: Dictionary(uniqueKeysWithValues: items.map { ($0.recordName, $0) }),
            relationship: RelationshipLocator(
                zoneName: "BetweenUsLocalPreview",
                ownerName: CKCurrentUserDefaultName,
                shareRecordName: "preview-share",
                scope: .privateOwner,
                createdAt: Date(timeIntervalSince1970: 1_735_689_600)
            ),
            currentUserRecordName: currentUserID,
            lastSuccessfulSyncAt: Date(),
            hasCompletedInitialSync: true,
            isLocalPreview: true
        )
    }

    @discardableResult
    static func replenishInteractiveContent(in data: inout AppData, minimum: Int = 2) -> Bool {
        guard data.isLocalPreview else { return false }
        var changed = false
        let target = max(1, minimum)
        let now = Date()

        for kind in ContainerKind.allCases {
            let creditShortfall = max(0, target - data.activeCredits(kind: kind))
            let waitingShortfall = max(0, target - data.unopenedCountFromCounterpart(kind: kind))

            for index in 0..<creditShortfall {
                let item = SecretItem(
                    kind: kind,
                    authorID: currentUserID,
                    text: previewText(for: kind, fromCounterpart: false, index: index),
                    createdAt: now.addingTimeInterval(-Double(creditShortfall - index + 4) * 900),
                    updatedAt: now.addingTimeInterval(-Double(creditShortfall - index + 4) * 900)
                )
                data.items[item.recordName] = item
                changed = true
            }

            for index in 0..<waitingShortfall {
                let item = SecretItem(
                    kind: kind,
                    authorID: counterpartID,
                    text: previewText(for: kind, fromCounterpart: true, index: index),
                    createdAt: now.addingTimeInterval(-Double(waitingShortfall - index + 1) * 600),
                    updatedAt: now.addingTimeInterval(-Double(waitingShortfall - index + 1) * 600)
                )
                data.items[item.recordName] = item
                changed = true
            }
        }

        return changed
    }

    @discardableResult
    static func installAttachmentDemos(
        in data: inout AppData,
        attachments: LocalPreviewAttachments
    ) -> Bool {
        guard data.isLocalPreview else { return false }
        guard let firstImage = attachments.images.first else { return false }
        let remainingImages = Array(attachments.images.dropFirst())
        let now = Date()
        let imageDate = Date(timeIntervalSince1970: 1_704_067_200)
        let audioDate = imageDate.addingTimeInterval(60)
        let demos = [
            SecretItem(
                id: UUID(uuidString: "56A0C0DE-0001-4000-8000-000000000001")!,
                kind: .capsule,
                authorID: currentUserID,
                text: "下班路上拍的，想问问你觉得怎么样。",
                createdAt: now.addingTimeInterval(-240),
                updatedAt: now.addingTimeInterval(-240),
                attachment: firstImage,
                additionalAttachments: remainingImages
            ),
            SecretItem(
                id: UUID(uuidString: "56A0C0DE-0002-4000-8000-000000000002")!,
                kind: .capsule,
                authorID: currentUserID,
                text: "有件事想跟你说，我录下来了。",
                createdAt: now.addingTimeInterval(-120),
                updatedAt: now.addingTimeInterval(-120),
                attachment: attachments.audio
            ),
            SecretItem(
                id: UUID(uuidString: "56A0C0DE-0003-4000-8000-000000000003")!,
                kind: .capsule,
                authorID: counterpartID,
                text: "今天在窗边拍的，你看看。",
                createdAt: imageDate,
                updatedAt: imageDate,
                attachment: firstImage,
                additionalAttachments: remainingImages
            ),
            SecretItem(
                id: UUID(uuidString: "56A0C0DE-0004-4000-8000-000000000004")!,
                kind: .capsule,
                authorID: counterpartID,
                text: "我录了一段话，有空听一下。",
                createdAt: audioDate,
                updatedAt: audioDate,
                attachment: attachments.audio
            )
        ]

        var changed = false
        for demo in demos {
            if var existing = data.items[demo.recordName] {
                if existing.attachment != demo.attachment
                    || existing.additionalAttachments != demo.additionalAttachments {
                    existing.attachment = demo.attachment
                    existing.additionalAttachments = demo.additionalAttachments
                    data.items[demo.recordName] = existing
                    changed = true
                }
            } else {
                data.items[demo.recordName] = demo
                changed = true
            }
        }
        return changed
    }

    private static func seededItems() -> [SecretItem] {
        let now = Date()
        func hoursAgo(_ hours: Double) -> Date {
            now.addingTimeInterval(-hours * 3_600)
        }

        return [
            SecretItem(
                kind: .star,
                authorID: currentUserID,
                text: "谢谢你刚才帮我倒了杯水。",
                createdAt: hoursAgo(30),
                updatedAt: hoursAgo(30)
            ),
            SecretItem(
                kind: .star,
                authorID: currentUserID,
                text: "谢谢你没有追问，让我自己缓了一会儿。",
                createdAt: hoursAgo(20),
                updatedAt: hoursAgo(8),
                openedByID: counterpartID,
                openedAt: hoursAgo(8)
            ),
            SecretItem(
                kind: .star,
                authorID: counterpartID,
                text: "今天没什么特别的，只是想跟你说声晚安。",
                createdAt: hoursAgo(12),
                updatedAt: hoursAgo(12)
            ),
            SecretItem(
                kind: .star,
                authorID: counterpartID,
                text: "你不在家，我怎么有一种不想洗澡、不想睡觉的感觉？",
                createdAt: hoursAgo(4),
                updatedAt: hoursAgo(4)
            ),
            SecretItem(
                kind: .capsule,
                authorID: currentUserID,
                text: "你最近有点累，今晚早点休息吧。",
                createdAt: hoursAgo(18),
                updatedAt: hoursAgo(18)
            ),
            SecretItem(
                kind: .capsule,
                authorID: counterpartID,
                text: "这件事不用急，我们明天一起想办法。",
                createdAt: hoursAgo(6),
                updatedAt: hoursAgo(6)
            ),
            SecretItem(
                kind: .paper,
                authorID: currentUserID,
                text: "刚才那句话让我有点不舒服，我还没想好怎么说。",
                createdAt: hoursAgo(22),
                updatedAt: hoursAgo(22)
            ),
            SecretItem(
                kind: .paper,
                authorID: counterpartID,
                text: "我今天心情不好，想先自己待一会儿，不是你的问题。",
                createdAt: hoursAgo(3),
                updatedAt: hoursAgo(3)
            )
        ]
    }

    private static func previewText(
        for kind: ContainerKind,
        fromCounterpart: Bool,
        index: Int
    ) -> String {
        let choices: [String]
        switch (kind, fromCounterpart) {
        case (.star, false):
            choices = ["谢谢你今天来接我。", "今天一起吃饭很开心。"]
        case (.star, true):
            choices = ["今天见到你很开心。", "谢谢你记得我随口提过的事。"]
        case (.capsule, false):
            choices = ["今晚别再忙了，早点休息。", "这件事不用急，我们明天再商量。"]
        case (.capsule, true):
            choices = ["你已经做得很好了，先休息一下。", "如果需要帮忙，可以直接告诉我。"]
        case (.paper, false):
            choices = ["今天有点难受，我想先把它说出来。", "这件事让我有些委屈，需要一点时间。"]
        case (.paper, true):
            choices = ["我刚才不说话，是因为有点生气。", "这件事我还没想清楚，晚点再跟你聊。"]
        }
        return choices[index % choices.count]
    }
}

extension AppData {
    var currentUserID: String { currentUserRecordName ?? "" }

    func allItems(kind: ContainerKind) -> [SecretItem] {
        items.values
            .filter { $0.kind == kind }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func count(kind: ContainerKind) -> Int {
        allItems(kind: kind).count
    }

    func count(kind: ContainerKind, authoredByCurrentUser: Bool) -> Int {
        allItems(kind: kind).filter {
            ($0.authorID == currentUserID) == authoredByCurrentUser
        }.count
    }

    func unopenedFromCounterpart(kind: ContainerKind) -> [SecretItem] {
        allItems(kind: kind).filter {
            $0.authorID != currentUserID && $0.openedAt == nil
        }
    }

    func unopenedCountFromCounterpart(kind: ContainerKind) -> Int {
        unopenedFromCounterpart(kind: kind).count
    }

    func ownItems(kind: ContainerKind? = nil) -> [SecretItem] {
        items.values
            .filter { item in
                item.authorID == currentUserID && (kind == nil || item.kind == kind)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func openedFromCounterpart(kind: ContainerKind? = nil) -> [SecretItem] {
        items.values
            .filter { item in
                item.authorID != currentUserID
                    && item.openedByID == currentUserID
                    && item.openedAt != nil
                    && (kind == nil || item.kind == kind)
            }
            .sorted {
                ($0.openedAt ?? $0.createdAt) > ($1.openedAt ?? $1.createdAt)
            }
    }

    func activeCredits(kind: ContainerKind) -> Int {
        let deposited = allItems(kind: kind).filter { $0.authorID == currentUserID }.count
        let opened = allItems(kind: kind).filter {
            $0.authorID != currentUserID && $0.openedByID == currentUserID
        }.count
        return max(0, deposited - opened)
    }

    func ownItemsOpenedByCounterpart(kind: ContainerKind) -> Int {
        allItems(kind: kind).filter {
            $0.authorID == currentUserID && $0.openedAt != nil
        }.count
    }

    func ownItemsWaiting(kind: ContainerKind) -> Int {
        allItems(kind: kind).filter {
            $0.authorID == currentUserID && $0.openedAt == nil
        }.count
    }

    var totalAttachmentBytes: Int64 {
        items.values.reduce(0) { total, item in
            total + item.allAttachments.reduce(0) { $0 + $1.byteCount }
        }
    }
}

enum AppPhase: Equatable, Sendable {
    case loading
    case needsICloud(message: String)
    case needsRelationship
    case ready
}

enum CloudSyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case upToDate(Date?)
    case attention(String)
    case localPreview

    var title: String {
        switch self {
        case .idle: return "等待同步".localized
        case .syncing: return "正在同步".localized
        case .upToDate: return "已同步".localized
        case .attention: return "同步需处理".localized
        case .localPreview: return "本机预览".localized
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .upToDate: return "checkmark.icloud"
        case .attention: return "exclamationmark.icloud"
        case .localPreview: return "eye"
        }
    }
}

struct AppNotice: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title: String
    var message: String
}

struct ShareSheetPayload: Identifiable, @unchecked Sendable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct AppViewModel: Sendable {
    var data = AppData()
    var phase: AppPhase = .loading
    var syncStatus: CloudSyncStatus = .idle
    var isPerformingAction = false
    var shareSheet: ShareSheetPayload?
    var notice: AppNotice?
}
