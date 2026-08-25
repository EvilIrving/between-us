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

    var title: String {
        switch self {
        case .idle: return "等待同步"
        case .syncing: return "正在同步"
        case .upToDate: return "已同步"
        case .attention: return "同步需处理"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .upToDate: return "checkmark.icloud"
        case .attention: return "exclamationmark.icloud"
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
