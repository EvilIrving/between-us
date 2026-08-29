import CloudKit
import Foundation
import OSLog

final actor BetweenUsStore: Sendable, ObservableObject {
    static let container = CKContainer.default()

    private enum RelationshipOperation {
        case creating
        case accepting
        case clearing
        case ending
    }

    @MainActor @Published var viewModel = AppViewModel()

    private let repository: LocalStateRepository
    private let mediaStore: MediaFileStore
    private let notificationManager: NotificationManager
    private let composeDraftRepository: ComposeDraftRepository
    private var appData: AppData
    private var privateSyncEngine: CKSyncEngine?
    private var sharedSyncEngine: CKSyncEngine?
    private var syncEngineScopes: [ObjectIdentifier: CKDatabase.Scope] = [:]
    private var relationshipOperation: RelationshipOperation?
    private var didStart = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetweenUs",
        category: "CloudKit"
    )

    init(
        repository: LocalStateRepository = LocalStateRepository(),
        mediaStore: MediaFileStore = MediaFileStore(),
        notificationManager: NotificationManager = NotificationManager(),
        composeDraftRepository: ComposeDraftRepository = ComposeDraftRepository()
    ) {
        self.repository = repository
        self.mediaStore = mediaStore
        self.notificationManager = notificationManager
        self.composeDraftRepository = composeDraftRepository
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
        if appData.isLocalPreview {
            await presentLocalPreview()
            return
        }
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
        if appData.isLocalPreview {
            await presentLocalPreview()
            return
        }
        guard await refreshAccountState() else { return }
        initializeSyncEnginesIfNeeded()
        queuePersistedDirtyRecords()
        guard appData.relationship != nil else { return }
        await refresh()
    }

    func enterLocalPreview() async {
        guard appData.relationship == nil || appData.isLocalPreview else { return }
        appData = LocalPreview.makeAppData()
        privateSyncEngine = nil
        sharedSyncEngine = nil
        _ = await persistOrReport(
            context: "保存本机预览状态",
            noticeMessage: "本机预览可以继续使用，但本次更改可能不会保留。"
        )
        await presentLocalPreview()
    }

    func leaveLocalPreview() async {
        guard appData.isLocalPreview else { return }
        appData = AppData()
        privateSyncEngine = nil
        sharedSyncEngine = nil
        do {
            try repository.reset()
        } catch {
            logger.error("Failed to reset local preview state: \(error.localizedDescription, privacy: .public)")
        }
        try? mediaStore.removeAll()
        composeDraftRepository.clearAll()
        _ = await persistOrReport(
            context: "保存退出本机预览后的状态",
            noticeMessage: "退出状态未能写入本机，请重新打开应用后重试。"
        )
        await publishData()
        await setSyncStatus(.idle)
        _ = await refreshAccountState()
    }

    func replenishLocalPreview() async {
        guard appData.isLocalPreview else { return }
        let changed = prepareLocalPreviewContent()
        if changed {
            let persisted = await persistOrReport(
                context: "保存补充后的容器内容",
                noticeMessage: "容器内容已补充，但本次更改可能不会保留。"
            )
            await publishData()
            guard persisted else { return }
        }
        await showNotice(
            title: "容器内容已补充",
            message: "三个容器现在都可以打开。"
        )
    }

    func refresh() async {
        guard !appData.isLocalPreview else {
            await setSyncStatus(.localPreview)
            return
        }
        guard let relationship = appData.relationship,
              let engine = syncEngine(for: relationship.scope.databaseScope) else { return }

        await setSyncStatus(.syncing)
        do {
            try await engine.fetchChanges()
            await recoverMissingAttachments(in: relationship)
            try await engine.sendChanges()
            appData.lastSuccessfulSyncAt = Date()
            let persisted = await persistOrReport(
                context: "保存手动同步结果",
                syncScope: relationship.scope.databaseScope
            )
            await publishData()
            if persisted {
                await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
            }
        } catch {
            logger.info("Manual sync deferred: \(error.localizedDescription, privacy: .public)")
            await setSyncStatus(.attention("网络恢复后会自动重试"))
        }
    }

    func createRelationship() async {
        guard relationshipOperation == nil else {
            await showNotice(title: "请稍候", message: "另一项共同空间操作还在进行中。")
            return
        }
        relationshipOperation = .creating
        await setPerformingAction(true)
        await performCreateRelationship()
        await setPerformingAction(false)
        relationshipOperation = nil
    }

    private func performCreateRelationship() async {
        guard appData.relationship == nil else { return }
        guard !appData.currentUserID.isEmpty else {
            await showNotice(title: "无法创建", message: "请先在系统设置中登录 iCloud。")
            return
        }

        let originalData = appData
        var createdZoneID: CKRecordZone.ID?
        do {
            let zone = CKRecordZone(zoneName: "BetweenUsRelationship-\(UUID().uuidString)")
            let database = Self.container.privateCloudDatabase
            _ = try await database.save(zone)
            createdZoneID = zone.zoneID

            let relationshipRecordID = CKRecord.ID(
                recordName: "relationship",
                zoneID: zone.zoneID
            )
            let relationshipRecord = CKRecord(
                recordType: "BetweenUsRelationship",
                recordID: relationshipRecordID
            )
            relationshipRecord["schemaVersion"] = 1 as CKRecordValue
            relationshipRecord["createdAt"] = Date() as CKRecordValue
            relationshipRecord.encryptedValues["ownerID"] = appData.currentUserID as CKRecordValue

            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = "耳语".localized as CKRecordValue
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
            if let createdZoneID {
                try? await Self.container.privateCloudDatabase.deleteRecordZone(withID: createdZoneID)
            }
            appData = originalData
            privateSyncEngine = nil
            sharedSyncEngine = nil
            _ = await persistOrReport(context: "恢复创建共同空间前的本机状态")
            await publishData()
            await setPhase(.needsRelationship)
            logger.error("Failed to create relationship: \(error.localizedDescription, privacy: .public)")
            await showNotice(title: "创建失败", message: cloudFriendlyMessage(for: error))
        }
    }

    func prepareShareSheet() async {
        if appData.isLocalPreview {
            await showNotice(
                title: "本机预览",
                message: "本机预览无法邀请成员。"
            )
            return
        }
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
                share[CKShare.SystemFieldKey.title] = "耳语".localized as CKRecordValue
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
        guard relationshipOperation == nil else {
            await showNotice(title: "请稍候", message: "另一项共同空间操作还在进行中。")
            return
        }
        relationshipOperation = .accepting
        await setPerformingAction(true)
        await performAcceptShare(metadata)
        await setPerformingAction(false)
        relationshipOperation = nil
    }

    private func performAcceptShare(_ metadata: CKShare.Metadata) async {
        let incomingZoneID = metadata.share.recordID.zoneID
        if let existing = appData.relationship {
            if existing.zoneID == incomingZoneID {
                await refresh()
                return
            }
            await showNotice(
                title: "已有共同空间",
                message: "一次只能加入一个共同空间。请先在设置中退出或删除当前空间。"
            )
            return
        }

        if let expectedIdentifier = Self.container.containerIdentifier,
           metadata.containerIdentifier != expectedIdentifier {
            await showNotice(title: "邀请无效", message: "此邀请无法用于当前应用。")
            return
        }

        var didAcceptShare = false

        do {
            guard await accountStatus() == .available else {
                throw StoreError.iCloudUnavailable
            }

            try await acceptShareMetadata(metadata)
            didAcceptShare = true
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
                let persisted = await persistOrReport(
                    context: "保存加入后的首次同步结果",
                    syncScope: .shared
                )
                await publishData()
                if persisted {
                    await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
                }
            } catch {
                logger.info("Share accepted; initial sync deferred: \(error.localizedDescription, privacy: .public)")
                await setSyncStatus(.attention("已加入，网络恢复后会继续同步"))
            }
        } catch {
            logger.error("Failed to accept share: \(error.localizedDescription, privacy: .public)")
            if didAcceptShare, appData.relationship != nil {
                await publishData()
                await setPhase(.ready)
                await showNotice(
                    title: "已加入共同空间",
                    message: "本机状态尚未完整保存。重新打开应用后会继续从 iCloud 同步。"
                )
            } else {
                await showNotice(title: "加入失败", message: cloudFriendlyMessage(for: error))
            }
        }
    }

    func add(
        kind: ContainerKind,
        text: String,
        attachments drafts: [AttachmentDraft] = []
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4_000,
              (!trimmed.isEmpty || !drafts.isEmpty),
              drafts.count <= 9,
              let relationship = appData.relationship,
              !appData.currentUserID.isEmpty else { return false }

        let itemID = UUID()
        let attachments: [AttachmentMetadata]
        do {
            attachments = try drafts.enumerated().map { index, draft in
                try mediaStore.importDraft(draft, itemID: itemID, slot: index)
            }
        } catch {
            await showNotice(title: "附件添加失败", message: error.localizedDescription)
            return false
        }

        let item = SecretItem(
            id: itemID,
            kind: kind,
            authorID: appData.currentUserID,
            text: trimmed,
            attachment: attachments.first,
            additionalAttachments: attachments.count > 1 ? Array(attachments.dropFirst()) : nil
        )
        appData.items[item.recordName] = item
        appData.dirtyRecordNames.insert(item.recordName)

        do {
            try persist()
            await publishData()
            if !appData.isLocalPreview {
                let scope = relationship.scope.databaseScope
                queueSave(item.recordID(in: relationship), scope: scope)
                Task { await self.sendQueuedChanges(scope: scope) }
            }
            for draft in drafts { cleanupTemporaryDraft(draft) }
            return true
        } catch {
            appData.items[item.recordName] = nil
            appData.dirtyRecordNames.remove(item.recordName)
            for attachment in attachments {
                try? mediaStore.remove(attachment)
            }
            await showNotice(title: "保存失败", message: "无法写入本机存储，请稍后重试。")
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
        guard relationshipOperation == nil else {
            await showNotice(title: "请稍候", message: "另一项共同空间操作还在进行中。")
            return
        }
        relationshipOperation = .ending
        await setPerformingAction(true)
        await performEndRelationship()
        await setPerformingAction(false)
        relationshipOperation = nil
    }

    func clearAllContent() async {
        guard relationshipOperation == nil else {
            await showNotice(title: "请稍候", message: "另一项共同空间操作还在进行中。")
            return
        }
        guard !appData.items.isEmpty else {
            await showNotice(title: "无需清空", message: "三个容器里还没有内容。")
            return
        }

        relationshipOperation = .clearing
        await setPerformingAction(true)
        await performClearAllContent()
        await setPerformingAction(false)
        relationshipOperation = nil
    }

    private func performClearAllContent() async {
        guard let relationship = appData.relationship else { return }

        let originalItems = appData.items
        let originalDirtyRecordNames = appData.dirtyRecordNames
        let recordIDs = originalItems.values.map { $0.recordID(in: relationship) }

        appData.items = [:]
        appData.dirtyRecordNames = []

        do {
            try persist()
        } catch {
            appData.items = originalItems
            appData.dirtyRecordNames = originalDirtyRecordNames
            await showNotice(title: "清空失败", message: "无法写入本机存储，请稍后重试。")
            return
        }

        if !appData.isLocalPreview {
            let scope = relationship.scope.databaseScope
            queueDeletes(recordIDs, scope: scope)
            Task { await self.sendQueuedChanges(scope: scope) }
        }

        do {
            try mediaStore.removeAll()
        } catch {
            logger.error("Failed to remove cleared media: \(error.localizedDescription, privacy: .public)")
        }
        composeDraftRepository.clearAll()
        await publishData()
        await showNotice(
            title: "已清空",
            message: "三个容器里的内容已删除，共同空间仍然保留。"
        )
    }

    private func performEndRelationship() async {
        if appData.isLocalPreview {
            await leaveLocalPreview()
            return
        }
        guard let relationship = appData.relationship else { return }

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
            composeDraftRepository.clearAll()
            initializeSyncEnginesIfNeeded()
            _ = await persistRelationshipRemoval(context: "保存结束共同空间后的本机状态")
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
            title: "共享失败",
            message: cloudFriendlyMessage(for: error)
        )
    }

    func sharingDidStop() async {
        await dismissShareSheet()
        if appData.relationship?.isOwner == true {
            await showNotice(
                title: "已停止共享",
                message: "内容仍保存在 iCloud，可再次邀请对方。"
            )
            return
        }

        appData.removeRelationshipData()
        appData.sharedSyncState = nil
        sharedSyncEngine = nil
        try? mediaStore.removeAll()
        composeDraftRepository.clearAll()
        initializeSharedSyncEngine()
        _ = await persistRelationshipRemoval(context: "保存停止共享后的本机状态")
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
            if !appData.isLocalPreview {
                let scope = relationship.scope.databaseScope
                queueSave(item.recordID(in: relationship), scope: scope)
                Task { await self.sendQueuedChanges(scope: scope) }
            }
            return item
        } catch {
            appData.items[original.recordName] = original
            appData.dirtyRecordNames.remove(original.recordName)
            await publishData()
            await showNotice(title: "状态保存失败", message: "无法写入本机存储，请稍后重试。")
            return nil
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension BetweenUsStore: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let scope = databaseScope(for: syncEngine)
        logger.debug("CKSyncEngine event for \(String(describing: scope), privacy: .public): \(String(describing: event), privacy: .public)")

        switch event {
        case .stateUpdate(let event):
            switch scope {
            case .private:
                appData.privateSyncState = event.stateSerialization
            case .shared:
                appData.sharedSyncState = event.stateSerialization
            default:
                break
            }
            _ = await persistOrReport(
                context: "保存 \(scope) 同步游标",
                syncScope: scope
            )

        case .accountChange(let event):
            await handleAccountChange(event)

        case .fetchedDatabaseChanges(let event):
            await handleFetchedDatabaseChanges(event, syncEngine: syncEngine)

        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)

        case .sentDatabaseChanges:
            break

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            if isCurrentRelationshipScope(scope) {
                await setSyncStatus(.syncing)
            }

        case .didFetchRecordZoneChanges:
            break

        case .didFetchChanges:
            guard isCurrentRelationshipScope(scope) else { break }
            appData.hasCompletedInitialSync = true
            appData.lastSuccessfulSyncAt = Date()
            let persisted = await persistOrReport(
                context: "保存拉取完成状态",
                syncScope: scope
            )
            await publishData()
            if persisted {
                await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
            }

        case .didSendChanges:
            guard isCurrentRelationshipScope(scope) else { break }
            appData.lastSuccessfulSyncAt = Date()
            let persisted = await persistOrReport(
                context: "保存上传完成状态",
                syncScope: scope
            )
            await publishData()
            if persisted {
                await setSyncStatus(.upToDate(appData.lastSuccessfulSyncAt))
            }

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let relationship = appData.relationship,
              relationship.scope.databaseScope == databaseScope(for: syncEngine) else {
            return nil
        }
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            scope.contains($0)
        }
        let items = appData.items
        let mediaStore = self.mediaStore

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard recordID.zoneID == relationship.zoneID,
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

private extension BetweenUsStore {
    func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        let scope = databaseScope(for: syncEngine)
        guard let relationship = appData.relationship,
              relationship.scope.databaseScope == scope else { return }
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
                if item.authorID != appData.currentUserID, item.openedAt == nil {
                    newItemKinds.append(item.kind)
                }
            }
            changed = true
        }

        for deletion in event.deletions where deletion.recordID.zoneID == relationship.zoneID {
            let key = deletion.recordID.recordName.lowercased()
            for attachment in appData.items[key]?.allAttachments ?? [] {
                try? mediaStore.remove(attachment)
            }
            appData.items[key] = nil
            appData.dirtyRecordNames.remove(key)
            changed = true
        }

        syncEngine.state.add(pendingRecordZoneChanges: recordsToRetry)
        if changed {
            _ = await persistOrReport(
                context: "保存远端内容变更",
                syncScope: scope
            )
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
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) async {
        let scope = databaseScope(for: syncEngine)
        guard let relationship = appData.relationship,
              relationship.scope.databaseScope == scope else { return }
        let relationshipWasRemoved = event.deletions.contains {
            $0.zoneID == relationship.zoneID
        }
        guard relationshipWasRemoved else { return }

        appData.removeRelationshipData()
        privateSyncEngine = nil
        sharedSyncEngine = nil
        try? mediaStore.removeAll()
        composeDraftRepository.clearAll()
        _ = await persistRelationshipRemoval(context: "保存远端共同空间删除")
        await publishData()
        await setPhase(.needsRelationship)
        await setSyncStatus(.idle)
        await showNotice(
            title: "共同空间已结束",
            message: relationship.isOwner
                ? "共同空间已从 iCloud 删除。"
                : "邀请方已停止共享，或你已被移出共同空间。"
        )
    }

    func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        let scope = databaseScope(for: syncEngine)
        guard isCurrentRelationshipScope(scope) else { return }
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
                        message: "共同空间已被删除，或当前账号没有写入权限。"
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
        _ = await persistOrReport(
            context: "保存上传结果",
            syncScope: scope
        )
        await publishData()
    }

    func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async {
        guard !appData.isLocalPreview else { return }
        switch event.changeType {
        case .signIn:
            _ = await refreshAccountState()
        case .signOut, .switchAccounts:
            appData = AppData()
            privateSyncEngine = nil
            sharedSyncEngine = nil
            do {
                try repository.reset()
            } catch {
                logger.error("Failed to reset local state after account change: \(error.localizedDescription, privacy: .public)")
                _ = await persistOrReport(
                    context: "清除账号切换前的本机状态",
                    noticeMessage: "iCloud 账号已更改，但旧的本机数据未能完整清除。请重新打开应用。"
                )
            }
            try? mediaStore.removeAll()
            composeDraftRepository.clearAll()
            await publishData()
            await setPhase(.needsICloud(message: "iCloud 账号已更改。请确认账号后重新打开应用。"))
            await setSyncStatus(.idle)
        @unknown default:
            break
        }
    }
}

// MARK: - Setup and helpers

private extension BetweenUsStore {
    enum StoreError: LocalizedError {
        case invalidShare
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidShare: return "共享信息无效。"
            case .iCloudUnavailable: return "当前无法使用 iCloud。"
            }
        }
    }

    func presentLocalPreview() async {
        if prepareLocalPreviewContent() {
            _ = await persistOrReport(
                context: "保存本机预览内容",
                noticeMessage: "本机预览可以继续使用，但本次更改可能不会保留。"
            )
        }
        await publishData()
        await setPhase(.ready)
        await setSyncStatus(.localPreview)
    }

    private func prepareLocalPreviewContent() -> Bool {
        var changed = false
        if let attachments = try? mediaStore.ensureLocalPreviewAttachments() {
            changed = LocalPreview.installAttachmentDemos(
                in: &appData,
                attachments: attachments
            ) || changed
        }
        changed = LocalPreview.replenishInteractiveContent(in: &appData) || changed
        return changed
    }

    func refreshAccountState() async -> Bool {
        if appData.isLocalPreview {
            await presentLocalPreview()
            return true
        }
        let status = await accountStatus()
        guard status == .available else {
            let message: String
            switch status {
            case .noAccount:
                message = "请在系统设置中登录 iCloud 后重试。"
            case .restricted:
                message = "这台设备限制了 iCloud，请检查屏幕使用时间或设备管理设置。"
            case .temporarilyUnavailable:
                message = "iCloud 暂时不可用，请稍后重新打开应用。"
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
                composeDraftRepository.clearAll()
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
            if scope == .private && !zone.zoneID.zoneName.hasPrefix("BetweenUsRelationship-") {
                continue
            }
            let recordID = CKRecord.ID(recordName: "relationship", zoneID: zone.zoneID)
            do {
                let record = try await database.record(for: recordID)
                guard record.recordType == "BetweenUsRelationship" else { continue }
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
        guard !appData.isLocalPreview else { return }
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
        let engine = CKSyncEngine(configuration)
        privateSyncEngine = engine
        syncEngineScopes[ObjectIdentifier(engine)] = .private
    }

    func initializeSharedSyncEngine() {
        guard sharedSyncEngine == nil else { return }
        var configuration = CKSyncEngine.Configuration(
            database: Self.container.sharedCloudDatabase,
            stateSerialization: appData.sharedSyncState,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        sharedSyncEngine = engine
        syncEngineScopes[ObjectIdentifier(engine)] = .shared
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
        syncEngineScopes[ObjectIdentifier(syncEngine)] ?? .public
    }

    func isCurrentRelationshipScope(_ scope: CKDatabase.Scope) -> Bool {
        appData.relationship?.scope.databaseScope == scope
    }

    @discardableResult
    func persistOrReport(
        context: String,
        syncScope: CKDatabase.Scope? = nil,
        noticeMessage: String? = nil
    ) async -> Bool {
        do {
            try persist()
            return true
        } catch {
            logger.error("\(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            if let syncScope, isCurrentRelationshipScope(syncScope) {
                await setSyncStatus(.attention("本机同步状态未保存，请稍后重试"))
            }
            if let noticeMessage {
                await showNotice(title: "本机存储失败", message: noticeMessage)
            }
            return false
        }
    }

    @discardableResult
    func persistRelationshipRemoval(context: String) async -> Bool {
        do {
            try repository.reset()
        } catch {
            logger.error("\(context, privacy: .public) could not clear the previous snapshot: \(error.localizedDescription, privacy: .public)")
            return await persistRemovalFallback(context: context)
        }

        do {
            try persist()
            return true
        } catch {
            // The repository is already empty, so a restart still recovers to a safe state.
            logger.error("\(context, privacy: .public) kept a clean reset but could not save the empty snapshot: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }

    func persistRemovalFallback(context: String) async -> Bool {
        do {
            try persist()
            return true
        } catch {
            logger.fault("\(context, privacy: .public) failed completely: \(error.localizedDescription, privacy: .public)")
            await showNotice(
                title: "本机清理未完成",
                message: "共同空间已结束，但本机数据未能清除。请重新打开应用。"
            )
            return false
        }
    }

    func queueSave(_ recordID: CKRecord.ID, scope: CKDatabase.Scope) {
        syncEngine(for: scope)?.state.add(
            pendingRecordZoneChanges: [.saveRecord(recordID)]
        )
    }

    func queueDeletes(_ recordIDs: [CKRecord.ID], scope: CKDatabase.Scope) {
        guard let engine = syncEngine(for: scope), !recordIDs.isEmpty else { return }
        engine.state.remove(
            pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) }
        )
        engine.state.add(
            pendingRecordZoneChanges: recordIDs.map { .deleteRecord($0) }
        )
    }

    func sendQueuedChanges(scope: CKDatabase.Scope) async {
        guard let engine = syncEngine(for: scope) else { return }
        do {
            try await engine.sendChanges()
        } catch {
            logger.info("Background sync deferred: \(error.localizedDescription, privacy: .public)")
            if isCurrentRelationshipScope(scope) {
                await setSyncStatus(.attention("等待网络同步"))
            }
        }
    }

    func queuePersistedDirtyRecords() {
        guard !appData.isLocalPreview,
              let relationship = appData.relationship,
              let engine = syncEngine(for: relationship.scope.databaseScope) else { return }
        let changes = appData.dirtyRecordNames.compactMap { recordName -> CKSyncEngine.PendingRecordZoneChange? in
            let normalized = recordName.lowercased()
            guard appData.items[normalized] != nil else { return nil }
            let recordID = CKRecord.ID(recordName: normalized, zoneID: relationship.zoneID)
            return .saveRecord(recordID)
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func recoverMissingAttachments(in relationship: RelationshipLocator) async {
        let missingRecordNames = appData.items.values.compactMap { item -> String? in
            guard let attachment = item.attachment,
                  !mediaStore.fileExists(for: attachment) else { return nil }
            return item.recordName
        }
        guard !missingRecordNames.isEmpty else { return }

        let database = Self.container.database(with: relationship.scope.databaseScope)
        var changed = false

        for recordName in missingRecordNames {
            let recordID = CKRecord.ID(recordName: recordName, zoneID: relationship.zoneID)
            do {
                let record = try await database.record(for: recordID)
                guard var local = appData.items[recordName] else { continue }
                let hadLocalFile = local.attachment.map { mediaStore.fileExists(for: $0) } ?? false
                let needsUpload = local.mergeFromServerRecord(record, mediaStore: mediaStore)
                appData.items[recordName] = local
                if needsUpload {
                    appData.dirtyRecordNames.insert(recordName)
                    queueSave(recordID, scope: relationship.scope.databaseScope)
                }
                let hasLocalFile = local.attachment.map { mediaStore.fileExists(for: $0) } ?? false
                changed = changed || hadLocalFile != hasLocalFile || needsUpload
            } catch {
                logger.info("Attachment recovery deferred for \(recordName, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
        }

        if changed {
            _ = await persistOrReport(
                context: "保存附件恢复结果",
                syncScope: relationship.scope.databaseScope
            )
            await publishData()
        }
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
            self.viewModel.notice = AppNotice(title: title.localized, message: message.localized)
        }
    }

    func cloudFriendlyMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        switch cloudError.code {
        case .notAuthenticated:
            return "请在系统设置中登录 iCloud。".localized
        case .networkUnavailable, .networkFailure:
            return "当前网络不可用。本机内容不会丢失，联网后会自动重试。".localized
        case .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return "iCloud 正忙，请稍后再试。".localized
        case .permissionFailure:
            return "当前账号没有访问这个共同空间的权限。".localized
        case .quotaExceeded:
            return "iCloud 储存空间不足。".localized
        default:
            return cloudError.localizedDescription
        }
    }
}
