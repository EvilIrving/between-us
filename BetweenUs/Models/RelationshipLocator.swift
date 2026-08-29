import CloudKit
import Foundation

enum RelationshipScope: String, Codable, Sendable {
    case privateOwner
    case sharedParticipant

    var databaseScope: CKDatabase.Scope {
        switch self {
        case .privateOwner: return .private
        case .sharedParticipant: return .shared
        }
    }

    var isOwner: Bool { self == .privateOwner }
}

struct RelationshipLocator: Codable, Hashable, Sendable {
    var zoneName: String
    var ownerName: String
    var shareRecordName: String
    var scope: RelationshipScope
    var createdAt: Date

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    var isOwner: Bool { scope.isOwner }
}
