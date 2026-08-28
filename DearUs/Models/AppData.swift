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
                zoneName: "DearUsLocalPreview",
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

    private static func seededItems() -> [SecretItem] {
        let now = Date()
        func hoursAgo(_ hours: Double) -> Date {
            now.addingTimeInterval(-hours * 3_600)
        }

        return [
            SecretItem(
                kind: .star,
                authorID: currentUserID,
                text: "今天你把杯子往我这边推了一点点，我其实一直记着。",
                createdAt: hoursAgo(30),
                updatedAt: hoursAgo(30)
            ),
            SecretItem(
                kind: .star,
                authorID: currentUserID,
                text: "谢谢你没有追问。那已经够了。",
                createdAt: hoursAgo(20),
                updatedAt: hoursAgo(8),
                openedByID: counterpartID,
                openedAt: hoursAgo(8)
            ),
            SecretItem(
                kind: .star,
                authorID: counterpartID,
                text: "没有什么特别的事。就是想把这一天轻轻放进来。",
                createdAt: hoursAgo(12),
                updatedAt: hoursAgo(12)
            ),
            SecretItem(
                kind: .star,
                authorID: counterpartID,
                text: "你靠过来的时候，房间好像安静了一点。",
                createdAt: hoursAgo(4),
                updatedAt: hoursAgo(4)
            ),
            SecretItem(
                kind: .capsule,
                authorID: currentUserID,
                text: "最近你已经很努力了。先歇一下也没关系。",
                createdAt: hoursAgo(18),
                updatedAt: hoursAgo(18)
            ),
            SecretItem(
                kind: .capsule,
                authorID: counterpartID,
                text: "我想认真告诉你：你做得比自己以为的好。",
                createdAt: hoursAgo(6),
                updatedAt: hoursAgo(6)
            ),
            SecretItem(
                kind: .paper,
                authorID: currentUserID,
                text: "有一句没有说完的话，先揉在这里。",
                createdAt: hoursAgo(22),
                updatedAt: hoursAgo(22)
            ),
            SecretItem(
                kind: .paper,
                authorID: counterpartID,
                text: "今天有点闷。不是你的错，只是想被接住。",
                createdAt: hoursAgo(3),
                updatedAt: hoursAgo(3)
            )
        ]
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
        items.values.reduce(0) { $0 + ($1.attachment?.byteCount ?? 0) }
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
        case .idle: return "等待同步"
        case .syncing: return "正在同步"
        case .upToDate: return "已同步"
        case .attention: return "同步需处理"
        case .localPreview: return "本机预览"
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
