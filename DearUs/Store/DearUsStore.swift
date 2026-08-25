import CloudKit
import Foundation
import OSLog

final actor DearUsStore: Sendable, ObservableObject {
    static let container = CKContainer.default()

    @MainActor @Published var viewModel = AppViewModel()

    private let repository: LocalStateRepository
    private let mediaStore: MediaFileStore
    private let notificationManager: NotificationManager
    private var appData: AppData
    private var privateSyncEngine: CKSyncEngine?
    private var sharedSyncEngine: CKSyncEngine?
    private var didStart = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DearUs",
        category: "CloudKit"
    )

    init(
        repository: LocalStateRepository = LocalStateRepository(),
        mediaStore: MediaFileStore = MediaFileStore(),
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.repository = repository
        self.mediaStore = mediaStore
        self.notificationManager = notificationManager
        var loaded = repository.load()
        loaded.normalizeRecordKeys()
        self.appData = loaded
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        await publishData()
        await setPhase(.loading)
        await installSystemEventHandlers()
        guard await refreshAccountState() else { return }

        initializeSyncEnginesIfNeeded()
        queuePersistedDirtyRecords()
        if appData.relationship != nil {
            await refresh()
        }
    }

    func sceneBecameActive() async {
        if !didStart {
            await start()
            return
        }
        guard await refreshAccountState() else { return }
        initializeSyncEnginesIfNeeded()
        queuePersistedDirtyRecords()
        guard appData.relationship != nil else { return }
        await refresh()
    }

    func refresh() async {
        guard let relationship = appData.relationship,
              let engine = syncEngine(for: relationship.scope.databaseScope) else { return }

        await setSyncStatus(.syncing)
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            appData.lastSuccessfulSyncAt = Date()
            try persist()
            await publishData()
            await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
        } catch {
            logger.info("Manual sync deferred: \(error.localizedDescription, privacy: .public)")
            await setSyncStatus(.attention("网络恢复后会自动重试"))
        }
    }

    func createRelationship() async {
        guard appData.relationship == nil else { return }
        guard !appData.currentUserID.isEmpty else {
            await showNotice(title: "无法创建", message: "请先在系统设置中登录 iCloud。")
            return
        }

        await setPerformingAction(true)
        defer { Task { await self.setPerformingAction(false) } }

        var createdZoneID: CKRecordZone.ID?
        do {
            let zone = CKRecordZone(zoneName: "DearUsRelationship-\(UUID().uuidString)")
            let database = Self.container.privateCloudDatabase
            _ = try await database.save(zone)
            createdZoneID = zone.zoneID

            let relationshipRecordID = CKRecord.ID(
                recordName: "relationship",
                zoneID: zone.zoneID
            )
            let relationshipRecord = CKRecord(
                recordType: "DearUsRelationship",
                recordID: relationshipRecordID
            )
            relationshipRecord["schemaVersion"] = 1 as CKRecordValue
            relationshipRecord["createdAt"] = Date() as CKRecordValue
            relationshipRecord.encryptedValues["ownerID"] = appData.currentUserID as CKRecordValue

            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = "耳语" as CKRecordValue
            share.publicPermission = .none

            _ = try await database.modifyRecords(
                saving: [relationshipRecord, share],
                deleting: []
            )

            appData.relationship = RelationshipLocator(
                zoneName: zone.zoneID.zoneName,
                ownerName: zone.zoneID.ownerName,
                shareRecordName: share.recordID.recordName,
                scope: .privateOwner,
                createdAt: Date()
            )
            appData.items = [:]
            appData.dirtyRecordNames = []
            appData.privateSyncState = nil
            privateSyncEngine = nil
            initializePrivateSyncEngine()
            try persist()
            await publishData()
            await setPhase(.ready)
            await setSyncStatus(.upToDate(Date()))
            await presentShareSheet(share)
        } catch {
            if appData.relationship == nil, let createdZoneID {
                try? await Self.container.privateCloudDatabase.deleteRecordZone(withID: createdZoneID)
            }
            logger.error("Failed to create relationship: \(error.localizedDescription, privacy: .public)")
            await showNotice(title: "创建失败", message: cloudFriendlyMessage(for: error))
        }
    }

    func prepareShareSheet() async {
        guard let relationship = appData.relationship else { return }
        await setPerformingAction(true)
        defer { Task { await self.setPerformingAction(false) } }

        let database = Self.container.database(with: relationship.scope.databaseScope)
        let shareID = CKRecord.ID(
            recordName: relationship.shareRecordName.isEmpty
                ? CKRecordNameZoneWideShare
                : relationship.shareRecordName,
            zoneID: relationship.zoneID
        )

        do {
            if let share = try await database.record(for: shareID) as? CKShare {
                await presentShareSheet(share)
                return
            }
            throw StoreError.invalidShare
        } catch let error as CKError where error.code == .unknownItem && relationship.isOwner {
            do {
                let share = CKShare(recordZoneID: relationship.zoneID)
                share[CKShare.SystemFieldKey.title] = "耳语" as CKRecordValue
                share.publicPermission = .none
                _ = try await database.modifyRecords(saving: [share], deleting: [])
                appData.relationship?.shareRecordName = share.recordID.recordName
                try persist()
                await publishData()
                await presentShareSheet(share)
            } catch {
                await showNotice(title: "无法打开共享", message: cloudFriendlyMessage(for: error))
            }
        } catch {
            await showNotice(title: "无法打开共享", message: cloudFriendlyMessage(for: error))
        }
    }

    func dismissShareSheet() async {
        await MainActor.run {
            self.viewModel.shareSheet = nil
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        let incomingZoneID = metadata.share.recordID.zoneID
        if let existing = appData.relationship {
            if existing.zoneID == incomingZoneID {
                await refresh()
                return
            }
            await showNotice(
                title: "已有共同空间",
                message: "当前版本一次只支持一段关系，请先在设置中结束现有共同空间。"
            )
            return
        }

        if let expectedIdentifier = Self.container.containerIdentifier,
           metadata.containerIdentifier != expectedIdentifier {
            await showNotice(title: "邀请无效", message: "这个邀请不属于当前 App 的 iCloud 容器。")
            return
        }

        await setPerformingAction(true)
        defer { Task { await self.setPerformingAction(false) } }

        do {
            guard await accountStatus() == .available else {
                throw StoreError.iCloudUnavailable
            }

            try await acceptShareMetadata(metadata)
            appData.relationship = RelationshipLocator(
                zoneName: incomingZoneID.zoneName,
                ownerName: incomingZoneID.ownerName,
                shareRecordName: metadata.share.recordID.recordName,
                scope: .sharedParticipant,
                createdAt: Date()
            )
            appData.items = [:]
            appData.dirtyRecordNames = []
            appData.sharedSyncState = nil
            sharedSyncEngine = nil
            initializeSharedSyncEngine()
            try persist()
            await publishData()
            await setPhase(.ready)

            do {
                if let sharedSyncEngine {
                    try await sharedSyncEngine.fetchChanges()
                }
                appData.lastSuccessfulSyncAt = Date()
                try persist()
                await publishData()
                await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
            } catch {
                logger.info("Share accepted; initial sync deferred: \(error.localizedDescription, privacy: .public)")
                await setSyncStatus(.attention("已加入，网络恢复后会继续同步"))
            }
        } catch {
            logger.error("Failed to accept share: \(error.localizedDescription, privacy: .public)")
            await showNotice(title: "加入失败", message: cloudFriendlyMessage(for: error))
        }
    }

    func add(
        kind: ContainerKind,
        text: String,
        attachment draft: AttachmentDraft? = nil
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4_000,
              (!trimmed.isEmpty || draft != nil),
              let relationship = appData.relationship,
              !appData.currentUserID.isEmpty else { return false }

        let itemID = UUID()
        let attachment: AttachmentMetadata?
        do {
            attachment = try draft.map { try mediaStore.importDraft($0, itemID: itemID) }
        } catch {
            await showNotice(title: "无法加入附件", message: error.localizedDescription)
            return false
        }

        let item = SecretItem(
            id: itemID,
            kind: kind,
            authorID: appData.currentUserID,
            text: trimmed,
            attachment: attachment
        )
        appData.items[item.recordName] = item
        appData.dirtyRecordNames.insert(item.recordName)

        do {
            try persist()
            await publishData()
            queueSave(item.recordID(in: relationship), scope: relationship.scope.databaseScope)
            try? await syncEngine(for: relationship.scope.databaseScope)?.sendChanges()
            cleanupTemporaryDraft(draft)
            return true
        } catch {
            appData.items[item.recordName] = nil
            appData.dirtyRecordNames.remove(item.recordName)
            if let attachment {
                try? mediaStore.remove(attachment)
            }
            await showNotice(title: "没有保存下来", message: "本机存储失败，请稍后再试。")
            return false
        }
    }

    func drawStar() async -> SecretItem? {
        guard appData.activeCredits(kind: .star) > 0,
              let candidate = appData.unopenedFromCounterpart(kind: .star).randomElement() else {
            return nil
        }
        return await open(candidate)
    }

    func openNext(kind: ContainerKind) async -> SecretItem? {
        guard kind != .star else { return await drawStar() }
        guard appData.activeCredits(kind: kind) > 0,
              let candidate = appData.unopenedFromCounterpart(kind: kind)
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first else { return nil }
        return await open(candidate)
    }

    func requestNotificationAuthorization() async -> Bool {
        await notificationManager.requestAuthorization()
    }

    func notificationAuthorizationStatus() async -> NotificationAuthorizationState {
        await notificationManager.authorizationState()
    }

    func endRelationship() async {
        guard let relationship = appData.relationship else { return }
        await setPerformingAction(true)
        defer { Task { await self.setPerformingAction(false) } }

        do {
            let shareID = CKRecord.ID(
                recordName: relationship.shareRecordName.isEmpty
                    ? CKRecordNameZoneWideShare
                    : relationship.shareRecordName,
                zoneID: relationship.zoneID
            )

            if relationship.isOwner {
                let database = Self.container.privateCloudDatabase
                do {
                    _ = try await database.deleteRecord(withID: shareID)
                } catch let error as CKError where error.code == .unknownItem {
                    // The owner may already have stopped sharing through the system sheet.
                }
                _ = try await database.deleteRecordZone(withID: relationship.zoneID)
            } else {
                // Deleting the CKShare from a participant's shared database leaves the share
                // without deleting the owner's records.
                _ = try await Self.container.sharedCloudDatabase.deleteRecord(withID: shareID)
            }

            appData.removeRelationshipData()
            appData.privateSyncState = nil
            appData.sharedSyncState = nil
            privateSyncEngine = nil
            sharedSyncEngine = nil
            try? mediaStore.removeAll()
            initializeSyncEnginesIfNeeded()
            try persist()
            await publishData()
            await setPhase(.needsRelationship)
            await setSyncStatus(.idle)
        } catch {
            await showNotice(title: "操作失败", message: cloudFriendlyMessage(for: error))
        }
    }

    func clearNotice() async {
        await MainActor.run {
            self.viewModel.notice = nil
        }
    }

    func reportSharingFailure(_ error: Error) async {
        await dismissShareSheet()
        await showNotice(
            title: "共享没有完成",
            message: cloudFriendlyMessage(for: error)
        )
    }

    func sharingDidStop() async {
        await dismissShareSheet()
        if appData.relationship?.isOwner == true {
            await showNotice(
                title: "已停止共享",
                message: "你的内容仍保留在 iCloud 中；需要时可以重新邀请对方。"
            )
            return
        }

        appData.removeRelationshipData()
        appData.sharedSyncState = nil
        sharedSyncEngine = nil
        try? mediaStore.removeAll()
        initializeSharedSyncEngine()
        try? persist()
        await publishData()
        await setPhase(.needsRelationship)
        await setSyncStatus(.idle)
    }

    private func open(_ candidate: SecretItem) async -> SecretItem? {
        guard let relationship = appData.relationship,
              var item = appData.items[candidate.recordName],
              item.authorID != appData.currentUserID,
              item.openedAt == nil else { return nil }

        let original = item
        let now = Date()
        item.openedByID = appData.currentUserID
        item.openedAt = now
        item.updatedAt = now
        appData.items[item.recordName] = item
        appData.dirtyRecordNames.insert(item.recordName)

        do {
            try persist()
            await publishData()
            queueSave(item.recordID(in: relationship), scope: relationship.scope.databaseScope)
            try? await syncEngine(for: relationship.scope.databaseScope)?.sendChanges()
            return item
        } catch {
            appData.items[original.recordName] = original
            appData.dirtyRecordNames.remove(original.recordName)
            await publishData()
            await showNotice(title: "没有保存打开状态", message: "本机存储失败，请稍后再试一次。")
            return nil
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension DearUsStore: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let scope = databaseScope(for: syncEngine)
        logger.debug("CKSyncEngine event for \(String(describing: scope), privacy: .public): \(String(describing: event), privacy: .public)")

        switch event {
        case .stateUpdate(let event):
            if scope == .private {
                appData.privateSyncState = event.stateSerialization
            } else {
                appData.sharedSyncState = event.stateSerialization
            }
            try? persist()

        case .accountChange(let event):
            await handleAccountChange(event)

        case .fetchedDatabaseChanges(let event):
            await handleFetchedDatabaseChanges(event)

        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)

        case .sentDatabaseChanges:
            break

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            await setSyncStatus(.syncing)

        case .didFetchRecordZoneChanges:
            break

        case .didFetchChanges:
            if appData.relationship?.scope.databaseScope == scope {
                appData.hasCompletedInitialSync = true
            }
            appData.lastSuccessfulSyncAt = Date()
            try? persist()
            await publishData()
            await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))

        case .didSendChanges:
            appData.lastSuccessfulSyncAt = Date()
            try? persist()
            await publishData()
            await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            scope.contains($0)
        }
        let relationship = appData.relationship
        let items = appData.items
        let mediaStore = self.mediaStore

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let relationship,
                  recordID.zoneID == relationship.zoneID,
                  let item = items[recordID.recordName.lowercased()] else {
                syncEngine.state.remove(
                    pendingRecordZoneChanges: [.saveRecord(recordID)]
                )
                return nil
            }

            if let attachment = item.attachment,
               !mediaStore.fileExists(for: attachment) {
                return nil
            }

            let record = item.lastKnownRecord
                ?? CKRecord(recordType: SecretItem.recordType, recordID: recordID)
            item.populate(record, mediaStore: mediaStore)
            return record
        }
    }
}

// MARK: - Sync event handling

private extension DearUsStore {
    func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        guard let relationship = appData.relationship else { return }
        let shouldNotify = appData.hasCompletedInitialSync
        var recordsToRetry: [CKSyncEngine.PendingRecordZoneChange] = []
        var changed = false
        var newItemKinds: [ContainerKind] = []
        var openedOwnItemKinds: [ContainerKind] = []

        for modification in event.modifications {
            let record = modification.record
            guard record.recordID.zoneID == relationship.zoneID,
                  record.recordType == SecretItem.recordType else { continue }

            let recordName = record.recordID.recordName.lowercased()
            if var local = appData.items[recordName] {
                let wasOwnUnopened = local.authorID == appData.currentUserID && local.openedAt == nil
                let needsUpload = local.mergeFromServerRecord(record, mediaStore: mediaStore)
                if wasOwnUnopened && local.openedAt != nil {
                    openedOwnItemKinds.append(local.kind)
                }
                appData.items[recordName] = local
                if needsUpload {
                    appData.dirtyRecordNames.insert(recordName)
                    recordsToRetry.append(.saveRecord(record.recordID))
                } else {
                    appData.dirtyRecordNames.remove(recordName)
                }
            } else if let item = SecretItem(record: record, mediaStore: mediaStore) {
                appData.items[recordName] = item
                if item.authorID != appData.currentUserID {
                    newItemKinds.append(item.kind)
                }
            }
            changed = true
        }

        for deletion in event.deletions where deletion.recordID.zoneID == relationship.zoneID {
            let key = deletion.recordID.recordName.lowercased()
            appData.items[key] = nil
            appData.dirtyRecordNames.remove(key)
            changed = true
        }

        syncEngine.state.add(pendingRecordZoneChanges: recordsToRetry)
        if changed {
            try? persist()
            await publishData()
        }

        if shouldNotify {
            for kind in newItemKinds {
                await notificationManager.notifyNewItem(kind: kind)
            }
            for kind in openedOwnItemKinds {
                await notificationManager.notifyOpened(kind: kind)
            }
        }
    }

    func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges
    ) async {
        guard let relationship = appData.relationship else { return }
        let relationshipWasRemoved = event.deletions.contains {
            $0.zoneID == relationship.zoneID
        }
        guard relationshipWasRemoved else { return }

        appData.removeRelationshipData()
        try? mediaStore.removeAll()
        try? persist()
        await publishData()
        await setPhase(.needsRelationship)
        await showNotice(
            title: "共同空间已结束",
            message: relationship.isOwner
                ? "这个 iCloud 共同空间已经被删除。"
                : "邀请方已经停止共享，或你已不再是参与者。"
        )
    }

    func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        let scope = databaseScope(for: syncEngine)
        var retryRecordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        var retryDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []

        for savedRecord in event.savedRecords {
            let recordName = savedRecord.recordID.recordName.lowercased()
            guard var item = appData.items[recordName] else { continue }
            item.setLastKnownRecordIfNewer(savedRecord)
            appData.items[recordName] = item
            appData.dirtyRecordNames.remove(recordName)
        }

        for failedSave in event.failedRecordSaves {
            let record = failedSave.record
            let recordName = record.recordID.recordName.lowercased()

            switch failedSave.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failedSave.error.serverRecord,
                      var local = appData.items[recordName] else { continue }
                let needsUpload = local.mergeFromServerRecord(serverRecord, mediaStore: mediaStore)
                appData.items[recordName] = local
                if needsUpload {
                    appData.dirtyRecordNames.insert(recordName)
                    retryRecordChanges.append(.saveRecord(record.recordID))
                } else {
                    appData.dirtyRecordNames.remove(recordName)
                }

            case .zoneNotFound:
                if scope == .private {
                    retryDatabaseChanges.append(
                        .saveZone(CKRecordZone(zoneID: record.recordID.zoneID))
                    )
                    retryRecordChanges.append(.saveRecord(record.recordID))
                } else {
                    await showNotice(
                        title: "共同空间不可用",
                        message: "共享区域已经不存在，或当前账号没有写入权限。"
                    )
                }

            case .unknownItem:
                if var local = appData.items[recordName] {
                    local.lastKnownRecord = nil
                    appData.items[recordName] = local
                    appData.dirtyRecordNames.insert(recordName)
                    retryRecordChanges.append(.saveRecord(record.recordID))
                }

            case .assetFileNotFound:
                await showNotice(
                    title: "附件暂时不可用",
                    message: "原始媒体文件已不在本机，请重新选择后再放入。"
                )

            case .permissionFailure:
                await showNotice(
                    title: "没有写入权限",
                    message: "请让共同空间的创建者把权限设为“可更改”。"
                )

            case .networkFailure, .networkUnavailable, .zoneBusy,
                 .serviceUnavailable, .notAuthenticated, .operationCancelled,
                 .requestRateLimited:
                break

            default:
                logger.error("Unresolved CloudKit save error: \(failedSave.error.localizedDescription, privacy: .public)")
            }
        }

        syncEngine.state.add(pendingDatabaseChanges: retryDatabaseChanges)
        syncEngine.state.add(pendingRecordZoneChanges: retryRecordChanges)
        try? persist()
        await publishData()
    }

    func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async {
        switch event.changeType {
        case .signIn:
            _ = await refreshAccountState()
        case .signOut, .switchAccounts:
            appData = AppData()
            privateSyncEngine = nil
            sharedSyncEngine = nil
            try? repository.reset()
            try? mediaStore.removeAll()
            await publishData()
            await setPhase(.needsICloud(message: "iCloud 账号发生了变化，请确认系统账号后重新打开 App。"))
            await setSyncStatus(.idle)
        @unknown default:
            break
        }
    }
}

// MARK: - Setup and helpers

private extension DearUsStore {
    enum StoreError: LocalizedError {
        case invalidShare
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidShare: return "CloudKit 没有返回有效的共享记录。"
            case .iCloudUnavailable: return "当前无法使用 iCloud。"
            }
        }
    }

    func refreshAccountState() async -> Bool {
        let status = await accountStatus()
        guard status == .available else {
            let message: String
            switch status {
            case .noAccount:
                message = "请在系统设置中登录 iCloud，关系数据只通过 Apple CloudKit 保存。"
            case .restricted:
                message = "这台设备限制了 iCloud，请检查屏幕使用时间或设备管理设置。"
            case .temporarilyUnavailable:
                message = "iCloud 暂时不可用，请稍后重新打开 App。"
            default:
                message = "暂时无法确认 iCloud 状态，请检查网络和系统设置。"
            }
            await setPhase(.needsICloud(message: message))
            return false
        }

        do {
            let recordID = try await Self.container.userRecordID()
            if let previous = appData.currentUserRecordName,
               previous != recordID.recordName {
                appData = AppData(currentUserRecordName: recordID.recordName)
                privateSyncEngine = nil
                sharedSyncEngine = nil
                try? mediaStore.removeAll()
            } else {
                appData.currentUserRecordName = recordID.recordName
            }
            if appData.relationship == nil {
                await discoverExistingRelationship()
            }
            initializeSyncEnginesIfNeeded()
            queuePersistedDirtyRecords()
            try persist()
            await publishData()
            await setPhase(appData.relationship == nil ? .needsRelationship : .ready)
            return true
        } catch {
            await setPhase(.needsICloud(message: cloudFriendlyMessage(for: error)))
            return false
        }
    }

    func discoverExistingRelationship() async {
        do {
            if let privateRelationship = try await discoverRelationship(in: .private) {
                appData.relationship = privateRelationship
                appData.items = [:]
                appData.dirtyRecordNames = []
                appData.privateSyncState = nil
                privateSyncEngine = nil
                return
            }
            if let sharedRelationship = try await discoverRelationship(in: .shared) {
                appData.relationship = sharedRelationship
                appData.items = [:]
                appData.dirtyRecordNames = []
                appData.sharedSyncState = nil
                sharedSyncEngine = nil
            }
        } catch {
            logger.info("Relationship discovery deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discoverRelationship(in scope: CKDatabase.Scope) async throws -> RelationshipLocator? {
        let database = Self.container.database(with: scope)
        let zones = try await database.allRecordZones().filter {
            $0.zoneID != CKRecordZone.default().zoneID
        }
        var candidates: [RelationshipLocator] = []

        for zone in zones {
            if scope == .private && !zone.zoneID.zoneName.hasPrefix("DearUsRelationship-") {
                continue
            }
            let recordID = CKRecord.ID(recordName: "relationship", zoneID: zone.zoneID)
            do {
                let record = try await database.record(for: recordID)
                guard record.recordType == "DearUsRelationship" else { continue }
                let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? .distantPast
                candidates.append(
                    RelationshipLocator(
                        zoneName: zone.zoneID.zoneName,
                        ownerName: zone.zoneID.ownerName,
                        shareRecordName: CKRecordNameZoneWideShare,
                        scope: scope == .private ? .privateOwner : .sharedParticipant,
                        createdAt: createdAt
                    )
                )
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return candidates.max { $0.createdAt < $1.createdAt }
    }

    func accountStatus() async -> CKAccountStatus {
        await withCheckedContinuation { continuation in
            Self.container.accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func initializeSyncEnginesIfNeeded() {
        initializePrivateSyncEngine()
        initializeSharedSyncEngine()
    }

    func initializePrivateSyncEngine() {
        guard privateSyncEngine == nil else { return }
        var configuration = CKSyncEngine.Configuration(
            database: Self.container.privateCloudDatabase,
            stateSerialization: appData.privateSyncState,
            delegate: self
        )
        configuration.automaticallySync = true
        privateSyncEngine = CKSyncEngine(configuration)
    }

    func initializeSharedSyncEngine() {
        guard sharedSyncEngine == nil else { return }
        var configuration = CKSyncEngine.Configuration(
            database: Self.container.sharedCloudDatabase,
            stateSerialization: appData.sharedSyncState,
            delegate: self
        )
        configuration.automaticallySync = true
        sharedSyncEngine = CKSyncEngine(configuration)
    }

    func syncEngine(for scope: CKDatabase.Scope) -> CKSyncEngine? {
        switch scope {
        case .private: return privateSyncEngine
        case .shared: return sharedSyncEngine
        case .public: return nil
        @unknown default: return nil
        }
    }

    func databaseScope(for syncEngine: CKSyncEngine) -> CKDatabase.Scope {
        if let privateSyncEngine, privateSyncEngine === syncEngine {
            return .private
        }
        return .shared
    }

    func queueSave(_ recordID: CKRecord.ID, scope: CKDatabase.Scope) {
        syncEngine(for: scope)?.state.add(
            pendingRecordZoneChanges: [.saveRecord(recordID)]
        )
    }

    func queuePersistedDirtyRecords() {
        guard let relationship = appData.relationship,
              let engine = syncEngine(for: relationship.scope.databaseScope) else { return }
        let changes = appData.dirtyRecordNames.compactMap { recordName -> CKSyncEngine.PendingRecordZoneChange? in
            let normalized = recordName.lowercased()
            guard appData.items[normalized] != nil else { return nil }
            let recordID = CKRecord.ID(recordName: normalized, zoneID: relationship.zoneID)
            return .saveRecord(recordID)
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func cleanupTemporaryDraft(_ draft: AttachmentDraft?) {
        guard let draft else { return }
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if draft.url.standardizedFileURL.path.hasPrefix(temporaryDirectory) {
            try? FileManager.default.removeItem(at: draft.url)
        }
    }

    func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws {
        _ = try await Self.container.accept(metadata)
    }

    func installSystemEventHandlers() async {
        await MainActor.run {
            CloudShareAcceptanceBroker.shared.install { [weak self] metadata in
                Task { await self?.acceptShare(metadata) }
            }
            CloudKitPushBroker.shared.install { [weak self] in
                await self?.refresh()
            }
        }
    }

    func persist() throws {
        try repository.save(appData)
    }

    func publishData() async {
        let snapshot = appData
        await MainActor.run {
            self.viewModel.data = snapshot
        }
    }

    func setPhase(_ phase: AppPhase) async {
        await MainActor.run {
            self.viewModel.phase = phase
        }
    }

    func setSyncStatus(_ status: CloudSyncStatus) async {
        await MainActor.run {
            self.viewModel.syncStatus = status
        }
    }

    func setPerformingAction(_ value: Bool) async {
        await MainActor.run {
            self.viewModel.isPerformingAction = value
        }
    }

    func presentShareSheet(_ share: CKShare) async {
        let payload = ShareSheetPayload(share: share, container: Self.container)
        await MainActor.run {
            self.viewModel.shareSheet = payload
        }
    }

    func showNotice(title: String, message: String) async {
        await MainActor.run {
            self.viewModel.notice = AppNotice(title: title, message: message)
        }
    }

    func cloudFriendlyMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        switch cloudError.code {
        case .notAuthenticated:
            return "请在系统设置中登录 iCloud。"
        case .networkUnavailable, .networkFailure:
            return "当前网络不可用；本地内容不会丢失，恢复网络后会自动重试。"
        case .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return "iCloud 正忙，请稍后再试。"
        case .permissionFailure:
            return "当前账号没有访问这个共同空间的权限。"
        case .quotaExceeded:
            return "iCloud 储存空间不足。"
        default:
            return cloudError.localizedDescription
        }
    }
}
