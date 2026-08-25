import CloudKit
import Foundation

@MainActor
final class CloudShareAcceptanceBroker {
    static let shared = CloudShareAcceptanceBroker()

    private var handler: ((CKShare.Metadata) -> Void)?
    private var pendingMetadata: [CKShare.Metadata] = []

    private init() {}

    func install(handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler
        let pending = pendingMetadata
        pendingMetadata.removeAll()
        pending.forEach(handler)
    }

    func receive(_ metadata: CKShare.Metadata) {
        if let handler {
            handler(metadata)
        } else {
            pendingMetadata.append(metadata)
        }
    }
}

