import CloudKit
import UIKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        deliver(metadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            CloudShareAcceptanceBroker.shared.receive(metadata)
        }
    }
}
