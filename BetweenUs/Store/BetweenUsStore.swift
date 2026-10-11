import CloudKit
import Foundation
import OSLog
import StoreKit

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
    private var lifetimeProduct: Product?
    private var ownedLifetimeTransaction: Transaction?
    private var purchaseActivity: PurchaseActivity = .idle
    private var productLoadFailed = false
    private var transactionListenerTask: Task<Void, Never>?
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
        beginObservingStoreKitTransactions()

        await publishData()
        Task { await self.prepareCommerce() }
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
        await refreshProximityMode()
    }

    func sceneBecameActive() async {
        if !didStart {
            await start()
            return
        }
        Task { await self.refreshOwnedLifetimePurchase() }
        if appData.isLocalPreview {
            await presentLocalPreview()
            return
        }
        guard await refreshAccountState() else { return }
        initializeSyncEnginesIfNeeded()
        queuePersistedDirtyRecords()
        await resumeProximity()
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
        await refreshProximityMode()
    }

    func replenishLocalPreview() async {
        guard appData.isLocalPreview else { return }
        let changed = prepareLocalPreviewContent()
        if changed {
            let persisted = await persistOrReport(
                context: "保存放回的预览内容",
                noticeMessage: "东西已经放回来了，但这次更改可能不会保留。"
            )
            await publishData()
            guard persisted else { return }
        }
        await showNotice(
            title: "已放回",
            message: ""
        )
    }

    func refresh() async {
        guard !appData.isLocalPreview else {
            await setSyncStatus(.localPreview)
            return
        }
        guard let relationship = appData.relationship,
              let engine = syncEngine(for: relationship.scope.databaseScope) else { return }

        // 对方可能已经进来了。顺手确认一次，顺便把递链接时打开的门关上。
        if relationship.isOwner, appData.partnerJoinedAt == nil {
            _ = await partnerHasJoined()
        }

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
            await showNotice(title: "操作进行中", message: "")
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
            await showNotice(title: "无法创建", message: "请先在系统设置中登录 iCloud。", autoDismiss: false)
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
            relationshipRecord["schemaVersion"] = 2 as CKRecordValue
            relationshipRecord["createdAt"] = Date() as CKRecordValue
            relationshipRecord.encryptedValues["ownerID"] = appData.currentUserID as CKRecordValue

            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = T("耳语") as CKRecordValue
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
            appData.sharedSpaceEntitlement = nil
            appData.partnerJoinedAt = nil
            appData.dirtyRecordNames = []
            appData.privateSyncState = nil
            privateSyncEngine = nil
            initializePrivateSyncEngine()
            try persist()
            await publishData()
            await setPhase(.ready)
            await setSyncStatus(.upToDate(Date()))
            await refreshProximityMode()
            if let ownedLifetimeTransaction {
                _ = await syncLifetimeEntitlementToCurrentSpace(using: ownedLifetimeTransaction)
            }
        } catch {
            if let createdZoneID {
                _ = try? await Self.container.privateCloudDatabase.deleteRecordZone(withID: createdZoneID)
            }
            appData = originalData
            privateSyncEngine = nil
            sharedSyncEngine = nil
            _ = await persistOrReport(context: "恢复创建空间前的本机状态")
            await publishData()
            await setPhase(.needsRelationship)
            let diagnostic = cloudDiagnostic(for: error)
            logger.error("Failed to create relationship: \(diagnostic, privacy: .public)")
            await showNotice(title: "创建失败", message: cloudFriendlyMessage(for: error), autoDismiss: false)
        }
    }

    func prepareShareSheet() async {
        if appData.isLocalPreview {
            await showNotice(
                title: "无法邀请",
                message: ""
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
                share[CKShare.SystemFieldKey.title] = T("耳语") as CKRecordValue
                share.publicPermission = .none
                _ = try await database.modifyRecords(saving: [share], deleting: [])
                appData.relationship?.shareRecordName = share.recordID.recordName
                try persist()
                await publishData()
                await presentShareSheet(share)
            } catch {
                await showNotice(title: "无法打开共享", message: cloudFriendlyMessage(for: error), autoDismiss: false)
            }
        } catch {
            await showNotice(title: "无法打开共享", message: cloudFriendlyMessage(for: error), autoDismiss: false)
        }
    }

    func dismissShareSheet() async {
        await MainActor.run {
            self.viewModel.shareSheet = nil
        }
    }

    // MARK: - 靠近相认

    /// 「邀请对方」：把邀请链接交到对方手上。靠近相认不需要这个入口，它自己会发生，
    /// 这里只保留两个人不在一起时的那条路。
    func presentInvite() async {
        await prepareShareSheet()
    }

    /// 靠近相认什么时候开机、什么时候停，只在这一个地方决定。
    /// 有空间、对方还没进来 → 广播等着；没有空间 → 去找对方的空间。本机预览不参与。
    func refreshProximityMode() async {
        await MainActor.run {
            let proximity = ProximityLinkService.shared
            proximity.onLink = { [weak self] url in
                guard let self else { return }
                Task { await self.joinSpace(shareURL: url) }
            }
            proximity.linkProvider = { [weak self] in
                await self?.pairingInviteURL()
            }
            proximity.onLinkServed = { [weak self] in
                guard let self else { return }
                Task { await self.notePartnerArriving() }
            }
        }

        guard !appData.isLocalPreview else {
            await MainActor.run { ProximityLinkService.shared.stop() }
            return
        }

        if let relationship = appData.relationship {
            if relationship.isOwner, appData.partnerJoinedAt == nil {
                await MainActor.run { ProximityLinkService.shared.startWaiting() }
            } else {
                await MainActor.run { ProximityLinkService.shared.stop() }
            }
        } else {
            await MainActor.run { ProximityLinkService.shared.startSeeking() }
        }
    }

    /// 回到前台时把广播和扫描补回来：退到后台时系统会把它们停掉。
    func resumeProximity() async {
        await MainActor.run { ProximityLinkService.shared.resume() }
    }

    /// 配对时交给对方的邀请链接。
    ///
    /// 面对面这条路上，链接是直接递过去的，CloudKit 必须允许「拿着链接的人」加入：
    /// 共享默认是私享（`publicPermission = .none`），那种共享只认系统面板里单独邀请的联系人，
    /// 收到原始链接的人会被当成不存在的共享（`CKErrorUnknownItem`）。
    /// 所以递链接之前先把门打开，对方进来之后在 `partnerHasJoined` 里关上。
    /// 开着的那几分钟里谁拿到链接谁能进来——这正是面对面递链接的意义。
    func pairingInviteURL() async -> URL? {
        guard let relationship = appData.relationship else { return nil }
        guard let share = await shareRecord(for: relationship) else {
            // 停过共享之后，链接要重新建一个；等着的设备自己修好，不要求人再点一次。
            return await recreateInviteShare(for: relationship)
        }
        guard share.publicPermission != .readWrite else { return share.url }

        let database = Self.container.database(with: relationship.scope.databaseScope)
        share.publicPermission = .readWrite
        do {
            _ = try await database.modifyRecords(saving: [share], deleting: [])
        } catch {
            logger.error("Failed to open the invite link: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return share.url
    }

    private func recreateInviteShare(for relationship: RelationshipLocator) async -> URL? {
        guard relationship.isOwner else { return nil }
        let database = Self.container.database(with: relationship.scope.databaseScope)
        let share = CKShare(recordZoneID: relationship.zoneID)
        share[CKShare.SystemFieldKey.title] = T("耳语") as CKRecordValue
        share.publicPermission = .readWrite
        do {
            _ = try await database.modifyRecords(saving: [share], deleting: [])
            appData.relationship?.shareRecordName = share.recordID.recordName
            try persist()
            await publishData()
            return share.url
        } catch {
            logger.error("Failed to recreate the invite link: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 用面对面配对拿到的链接加入空间，不经过系统链接跳转。
    func joinSpace(shareURL: URL) async {
        guard relationshipOperation == nil else {
            await showNotice(title: "另一项空间操作还在进行中。", message: "")
            return
        }
        relationshipOperation = .accepting
        await setPerformingAction(true)

        do {
            let metadata = try await fetchShareMetadata(for: shareURL)
            await performAcceptShare(metadata)
        } catch {
            logger.error(
                "Failed to join through pairing: \(error.localizedDescription, privacy: .public)"
            )
            await showNotice(title: "无法加入", message: cloudFriendlyMessage(for: error), autoDismiss: false)
            await MainActor.run { ProximityLinkService.shared.noteAttemptFailed() }
        }

        await setPhase(appData.relationship == nil ? .needsRelationship : .ready)
        await setPerformingAction(false)
        relationshipOperation = nil
        await refreshProximityMode()
    }

    private func shareRecord(for relationship: RelationshipLocator) async -> CKShare? {
        let database = Self.container.database(with: relationship.scope.databaseScope)
        let shareID = CKRecord.ID(
            recordName: relationship.shareRecordName.isEmpty
                ? CKRecordNameZoneWideShare
                : relationship.shareRecordName,
            zoneID: relationship.zoneID
        )
        return try? await database.record(for: shareID) as? CKShare
    }

    private func partnerHasJoined(announce: Bool = true) async -> Bool {
        guard let relationship = appData.relationship, relationship.isOwner else { return false }
        // 本机已经知道就直接用，不再问网络。
        if appData.partnerJoinedAt != nil { return true }

        guard let share = await shareRecord(for: relationship) else { return false }
        // 只发了链接、还没接受的人会以 pending 出现，不能算进来。
        let accepted = share.participants.contains {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }
        guard accepted else { return false }

        appData.partnerJoinedAt = Date()
        _ = await persistOrReport(context: "保存对方已加入的时刻")
        await publishData()
        await MainActor.run { ProximityLinkService.shared.noteConnected() }
        await refreshProximityMode()

        // 连接页正在演这一段的时候，由光来说这件事，不再另外弹一条。
        let isCeremonyRunning = await MainActor.run { self.viewModel.connectionMoment != nil }
        if announce, !isCeremonyRunning {
            await showNotice(title: "对方已经进来了", message: "")
        }
        return true
    }

    // MARK: - 连接页

    private var partnerWatchTask: Task<Void, Never>?

    /// 连接页出现时开始盯着对方有没有进来。
    /// 两个人都在看手机的那一刻要能同时发生，所以这里短轮询；不引入推送，也不要求谁保持前台。
    func beginWatchingPartner() async {
        guard partnerWatchTask == nil else { return }
        guard !appData.isLocalPreview,
              let relationship = appData.relationship,
              relationship.isOwner,
              appData.partnerJoinedAt == nil else { return }

        partnerWatchTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            while !Task.isCancelled {
                // 刚打开时盯得紧一点：两个人正对着手机的那几秒要能同时发生。
                // 等久了就放慢，别让人一直开着的页面每小时问上千次。
                let interval: TimeInterval = elapsed < 120 ? 1.6 : 9
                try? await Task.sleep(for: .seconds(interval))
                elapsed += interval
                guard let self, !Task.isCancelled else { return }
                let stillWaiting = await self.pollPartnerArrival()
                if !stillWaiting { return }
            }
        }
    }

    func endWatchingPartner() async {
        partnerWatchTask?.cancel()
        partnerWatchTask = nil
    }

    /// 返回是否还要继续盯。
    private func pollPartnerArrival() async -> Bool {
        guard appData.partnerJoinedAt == nil else { return false }
        guard await partnerHasJoined(announce: false) else { return true }
        // 对方进来了：如果这一刻没有别的东西在讲这件事，就让光来讲。
        await ensureConnectionMoment(isCreator: true, isSettled: true)
        return false
    }

    /// 创建者这一侧：链接刚递出去，有人正在进来。同步的是这一刻，不是谁先按下了什么。
    func notePartnerArriving() async {
        guard !appData.isLocalPreview,
              appData.relationship?.isOwner == true,
              appData.partnerJoinedAt == nil else { return }
        await ensureConnectionMoment(isCreator: true, isSettled: false)
    }

    /// 连接页演完了这一段：把这一刻收掉，落回房间。
    func completeConnectionCeremony() async {
        await MainActor.run { self.viewModel.connectionMoment = nil }
        await setPhase(appData.relationship == nil ? .needsRelationship : .ready)
        await publishData()
    }

    private func ensureConnectionMoment(isCreator: Bool, isSettled: Bool) async {
        await MainActor.run {
            guard var moment = self.viewModel.connectionMoment else {
                self.viewModel.connectionMoment = ConnectionMoment(
                    isCreator: isCreator,
                    isSettled: isSettled
                )
                return
            }
            moment.isSettled = moment.isSettled || isSettled
            self.viewModel.connectionMoment = moment
        }
    }

    private func settleConnectionMoment() async {
        await MainActor.run {
            guard var moment = self.viewModel.connectionMoment else { return }
            moment.isSettled = true
            self.viewModel.connectionMoment = moment
        }
    }

    private func clearConnectionMoment() async {
        await MainActor.run { self.viewModel.connectionMoment = nil }
    }

    /// 加入方在真正加入的那一刻把时间戳写进关系记录，创建方靠同步就能知道对方进来了。
    /// 只写一次；写不进去也不影响加入，创建方那边会退回问一次 CloudKit。
    private func publishPartnerJoinedAt() async {
        guard let relationship = appData.relationship, !relationship.isOwner else { return }
        let recordID = CKRecord.ID(recordName: "relationship", zoneID: relationship.zoneID)
        let database = Self.container.database(with: relationship.scope.databaseScope)

        do {
            var record = try await database.record(for: recordID)
            if let existing = record[RelationshipRecordField.partnerJoinedAt] as? Date {
                await adoptPartnerJoinedAt(existing)
                return
            }

            for attempt in 0..<2 {
                record[RelationshipRecordField.partnerJoinedAt] = Date() as CKRecordValue
                do {
                    let saved = try await database.save(record)
                    await adoptPartnerJoinedAt(
                        saved[RelationshipRecordField.partnerJoinedAt] as? Date ?? Date()
                    )
                    return
                } catch let error as CKError
                    where error.code == .serverRecordChanged && attempt == 0 {
                    guard let serverRecord = error.serverRecord else { throw error }
                    if let existing = serverRecord[RelationshipRecordField.partnerJoinedAt] as? Date {
                        await adoptPartnerJoinedAt(existing)
                        return
                    }
                    record = serverRecord
                }
            }
        } catch {
            logger.info("Partner joined timestamp deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func adoptPartnerJoinedAt(_ joinedAt: Date) async {
        guard appData.partnerJoinedAt != joinedAt else { return }
        appData.partnerJoinedAt = joinedAt
        _ = await persistOrReport(context: "保存对方已加入的时刻")
        await publishData()
    }

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        let operation = CKFetchShareMetadataOperation(shareURLs: [url])
        operation.shouldFetchRootRecord = false
        operation.qualityOfService = .userInitiated
        return try await withCheckedThrowingContinuation { continuation in
            let resume = ShareMetadataContinuation(continuation)
            operation.perShareMetadataResultBlock = { _, result in
                resume.finish(with: result)
            }
            operation.fetchShareMetadataResultBlock = { result in
                if case .failure(let error) = result {
                    resume.finish(throwing: error)
                }
            }
            Self.container.add(operation)
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard relationshipOperation == nil else {
            await showNotice(title: "操作进行中", message: "")
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
                title: "已有空间",
                message: "一次只能加入一个空间。请先在设置中退出或删除当前空间。",
                autoDismiss: false
            )
            return
        }

        if let expectedIdentifier = Self.container.containerIdentifier,
           metadata.containerIdentifier != expectedIdentifier {
            await showNotice(title: "邀请无效", message: "此邀请无法用于当前应用。", autoDismiss: false)
            return
        }

        var didAcceptShare = false
        // 从这一刻起，连接页开始演这一段的「正在加入」。
        await ensureConnectionMoment(isCreator: false, isSettled: false)

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
            appData.sharedSpaceEntitlement = nil
            appData.partnerJoinedAt = nil
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
            if let ownedLifetimeTransaction {
                _ = await syncLifetimeEntitlementToCurrentSpace(using: ownedLifetimeTransaction)
            }
            await publishPartnerJoinedAt()
            await MainActor.run { ProximityLinkService.shared.noteConnected() }
            await settleConnectionMoment()
        } catch {
            logger.error("Failed to accept share: \(error.localizedDescription, privacy: .public)")
            if didAcceptShare, appData.relationship != nil {
                await publishData()
                await setPhase(.ready)
                await settleConnectionMoment()
                await showNotice(
                    title: "已加入空间",
                    message: "本机状态尚未完整保存。重新打开应用后会继续从 iCloud 同步。"
                )
            } else {
                await clearConnectionMoment()
                await showNotice(title: "加入失败", message: cloudFriendlyMessage(for: error), autoDismiss: false)
            }
        }

        // 加入方从此有了空间，不再需要找对方的空间。
        await refreshProximityMode()
    }

    /// 正文的数据完整性上限（不是产品容量上限）：纸不会拒绝你写，但一条 CloudKit 记录里
    /// 非资源字段总量不能超过 1MB，所以给正文留一半余量。产品侧容量由纸高决定（§3.2、§4.2）。
    private static let maximumTextBytes = 512 * 1024

    func add(
        kind: ContainerKind,
        text: String,
        attachments drafts: [AttachmentDraft] = [],
        paperID: PaperID = PaperRegistry.defaultPaperID
    ) async -> AddItemResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count < Self.maximumTextBytes,
              (!trimmed.isEmpty || !drafts.isEmpty),
              drafts.count <= 9,
              let relationship = appData.relationship,
              !appData.currentUserID.isEmpty else { return .failed }

        guard hasUnlimitedContent
                || appData.items.count < CommerceConfiguration.freeItemLimit else {
            return .quotaReached
        }

        let itemID = UUID()
        let attachments: [AttachmentMetadata]
        do {
            attachments = try drafts.enumerated().map { index, draft in
                try mediaStore.importDraft(draft, itemID: itemID, slot: index)
            }
        } catch {
            await showNotice(title: "附件添加失败", message: error.localizedDescription, autoDismiss: false)
            return .failed
        }

        let item = SecretItem(
            id: itemID,
            kind: kind,
            storedPaperID: paperID,
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
            return .success
        } catch {
            appData.items[item.recordName] = nil
            appData.dirtyRecordNames.remove(item.recordName)
            for attachment in attachments {
                try? mediaStore.remove(attachment)
            }
            await showNotice(title: "保存失败", message: "无法写入本机存储，请稍后重试。", autoDismiss: false)
            return .failed
        }
    }

    func deleteItem(id: UUID) async -> Bool {
        guard let relationship = appData.relationship,
              let item = appData.items.values.first(where: { $0.id == id }) else {
            return false
        }

        let recordName = item.recordName
        let wasDirty = appData.dirtyRecordNames.contains(recordName)
        appData.items[recordName] = nil
        appData.dirtyRecordNames.remove(recordName)

        do {
            try persist()
        } catch {
            appData.items[recordName] = item
            if wasDirty { appData.dirtyRecordNames.insert(recordName) }
            await showNotice(title: "删除失败", message: "无法写入本机存储，请稍后重试。", autoDismiss: false)
            return false
        }

        if !appData.isLocalPreview {
            let scope = relationship.scope.databaseScope
            queueDeletes([item.recordID(in: relationship)], scope: scope)
            Task { await self.sendQueuedChanges(scope: scope) }
        }

        for attachment in item.allAttachments {
            do {
                try mediaStore.remove(attachment)
            } catch {
                logger.error("Failed to remove deleted attachment: \(error.localizedDescription, privacy: .public)")
            }
        }
        await publishData()
        return true
    }

    func loadLifetimeProduct() async {
        guard lifetimeProduct == nil else {
            await publishPurchaseState()
            return
        }
        guard purchaseActivity != .purchasing, purchaseActivity != .restoring else { return }

        purchaseActivity = .loadingProduct
        productLoadFailed = false
        await publishPurchaseState()

        do {
            let products = try await Product.products(
                for: [CommerceConfiguration.lifetimeProductID]
            )
            lifetimeProduct = products.first(where: { $0.type == .nonConsumable })
            productLoadFailed = lifetimeProduct == nil
        } catch {
            productLoadFailed = true
            logger.info("StoreKit product load deferred: \(error.localizedDescription, privacy: .public)")
        }

        purchaseActivity = .idle
        await publishPurchaseState()
    }

    func purchaseLifetime() async {
        guard !hasUnlimitedContent else {
            await showNotice(title: "空间已解锁", message: "")
            return
        }
        guard SKPaymentQueue.canMakePayments() else {
            await showNotice(title: "无法购买", message: "这台设备目前不允许 App 内购买。", autoDismiss: false)
            return
        }

        if lifetimeProduct == nil {
            await loadLifetimeProduct()
        }
        guard let lifetimeProduct else {
            await showNotice(title: "暂时无法连接 App Store", message: "请检查网络后再试。", autoDismiss: false)
            return
        }

        purchaseActivity = .purchasing
        await publishPurchaseState()

        do {
            switch try await lifetimeProduct.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await handleVerifiedLifetimeTransaction(transaction, announce: true)
                case .unverified:
                    purchaseActivity = .idle
                    await publishPurchaseState()
                    await showNotice(
                        title: "无法确认购买",
                        message: "App Store 无法验证这次交易，未收取或恢复权益。",
                        autoDismiss: false
                    )
                }

            case .pending:
                purchaseActivity = .pending
                await publishPurchaseState()
                await showNotice(
                    title: "购买等待确认",
                    message: "完成 App Store 的确认后，永久版会自动解锁。"
                )

            case .userCancelled:
                purchaseActivity = .idle
                await publishPurchaseState()

            @unknown default:
                purchaseActivity = .idle
                await publishPurchaseState()
            }
        } catch {
            purchaseActivity = .idle
            await publishPurchaseState()
            logger.info("StoreKit purchase failed: \(error.localizedDescription, privacy: .public)")
            await showNotice(title: "购买未完成", message: "请稍后再试。", autoDismiss: false)
        }
    }

    func restoreLifetimePurchase() async {
        guard purchaseActivity != .purchasing, purchaseActivity != .restoring else { return }

        purchaseActivity = .restoring
        await publishPurchaseState()
        do {
            try await AppStore.sync()
            await refreshOwnedLifetimePurchase()
            purchaseActivity = .idle
            await publishPurchaseState()

            if ownedLifetimeTransaction != nil {
                await showNotice(title: "购买已恢复", message: "")
            } else {
                await showNotice(title: "没有可恢复的购买", message: "请确认使用了购买时的 Apple Account。", autoDismiss: false)
            }
        } catch {
            purchaseActivity = .idle
            await publishPurchaseState()
            logger.info("StoreKit restore failed: \(error.localizedDescription, privacy: .public)")
            await showNotice(title: "恢复未完成", message: "请稍后再试。", autoDismiss: false)
        }
    }

    func peekOpenable(kind: ContainerKind) -> SecretItem? {
        nextOpenable(kind: kind)
    }

    func drawStar() async -> SecretItem? {
        await openNext(kind: .star)
    }

    func openNext(kind: ContainerKind) async -> SecretItem? {
        guard let candidate = nextOpenable(kind: kind) else { return nil }
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
            await showNotice(title: "操作进行中", message: "")
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
            await showNotice(title: "操作进行中", message: "")
            return
        }
        guard !appData.items.isEmpty else {
            await showNotice(title: "无需清空", message: "")
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
            await showNotice(title: "清空失败", message: "无法写入本机存储，请稍后重试。", autoDismiss: false)
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
            message: ""
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
            _ = await persistRelationshipRemoval(context: "保存结束空间后的本机状态")
            await publishData()
            await setPhase(.needsRelationship)
            await setSyncStatus(.idle)
            await refreshProximityMode()
        } catch {
            await showNotice(title: "操作失败", message: cloudFriendlyMessage(for: error), autoDismiss: false)
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
            message: cloudFriendlyMessage(for: error),
            autoDismiss: false
        )
    }

    func sharingDidStop() async {
        await dismissShareSheet()
        if appData.relationship?.isOwner == true {
            // 共享停了，对方也不再是成员：空间回到「等对方靠近」，邀请随时可以再发。
            appData.partnerJoinedAt = nil
            _ = await persistOrReport(context: "保存停止共享后的空间状态")
            await publishData()
            await refreshProximityMode()
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
        await refreshProximityMode()
    }

    private func nextOpenable(kind: ContainerKind) -> SecretItem? {
        let waiting = appData.unopenedFromCounterpart(kind: kind)
        if kind == .star {
            return waiting.randomElement()
        }
        return waiting.sorted(by: { $0.createdAt < $1.createdAt }).first
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
            await showNotice(title: "状态保存失败", message: "无法写入本机存储，请稍后重试。", autoDismiss: false)
            return nil
        }
    }

    /// 顶部通知条：只报告短暂状态，不伪装成页面跳转；默认到时自动收起，新通知会顶掉旧计时。
    /// 需要用户读完并采取行动的失败通知传 `autoDismiss: false`，常驻到点按关闭。
    func showNotice(title: String, message: String, autoDismiss: Bool = true) async {
        let notice = AppNotice(title: T(key: title), message: T(key: message))
        await MainActor.run {
            self.viewModel.notice = notice
        }
        guard autoDismiss else { return }
        Task { [weak self] in
            try? await Task.sleep(for: AppMotion.noticeAutoDismissDelay(message: notice.message))
            await self?.dismissNotice(id: notice.id)
        }
    }

    private func dismissNotice(id: AppNotice.ID) async {
        await MainActor.run {
            guard self.viewModel.notice?.id == id else { return }
            self.viewModel.notice = nil
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
            guard record.recordID.zoneID == relationship.zoneID else { continue }

            if record.recordType == "BetweenUsRelationship" {
                let entitlement = sharedEntitlement(from: record)
                if entitlement != appData.sharedSpaceEntitlement {
                    appData.sharedSpaceEntitlement = entitlement
                    changed = true
                }
                let joinedAt = record[RelationshipRecordField.partnerJoinedAt] as? Date
                if let joinedAt, joinedAt != appData.partnerJoinedAt {
                    appData.partnerJoinedAt = joinedAt
                    changed = true
                }
                continue
            }

            guard record.recordType == SecretItem.recordType else { continue }

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
        _ = await persistRelationshipRemoval(context: "保存远端空间删除")
        await publishData()
        await setPhase(.needsRelationship)
        await setSyncStatus(.idle)
        await showNotice(
            title: "空间已结束",
            message: relationship.isOwner
                ? "空间已从 iCloud 删除。"
                : "邀请方已停止共享，或你已被移出空间。"
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
                        title: "空间不可用",
                        message: "空间已被删除，或当前账号没有写入权限。",
                        autoDismiss: false
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
                    message: "原始媒体文件已不在本机，请重新选择后再放入。",
                    autoDismiss: false
                )

            case .permissionFailure:
                await showNotice(
                    title: "没有写入权限",
                    message: "请让空间的创建者把权限设为“可更改”。",
                    autoDismiss: false
                )

            case .networkFailure, .networkUnavailable, .zoneBusy,
                 .serviceUnavailable, .notAuthenticated, .operationCancelled,
                 .requestRateLimited:
                break

            default:
                logger.error("Unresolved CloudKit save error: \(failedSave.error.localizedDescription, privacy: .public)")
            }
        }

        for (recordID, error) in event.failedRecordDeletes {
            switch error.code {
            case .unknownItem:
                break

            case .networkFailure, .networkUnavailable, .zoneBusy,
                 .serviceUnavailable, .notAuthenticated, .operationCancelled,
                 .requestRateLimited:
                retryRecordChanges.append(.deleteRecord(recordID))

            case .permissionFailure:
                await showNotice(
                    title: "没有删除权限",
                    message: "请让共同空间的创建者把权限设为“可更改”。",
                    autoDismiss: false
                )

            default:
                logger.error("Unresolved CloudKit delete error: \(error.localizedDescription, privacy: .public)")
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
            await setPhase(.needsICloud(message: T("iCloud 账号已更改。请确认账号后重新打开应用。")))
            await setSyncStatus(.idle)
        @unknown default:
            break
        }
    }
}

// MARK: - StoreKit and shared entitlement

private extension BetweenUsStore {
    enum EntitlementRecordField {
        static let productID = "lifetimeProductID"
        static let unlockedAt = "lifetimeUnlockedAt"
    }

    /// 关系记录上除了权益以外的字段。它们跟着 CloudKit 同步走，
    /// 两台设备不用各自再去问一次「对方进来了没有」。
    enum RelationshipRecordField {
        static let partnerJoinedAt = "partnerJoinedAt"
    }

    var hasUnlimitedContent: Bool {
        appData.isLocalPreview
            || ownedLifetimeTransaction != nil
            || appData.sharedSpaceEntitlement != nil
    }

    func beginObservingStoreKitTransactions() {
        guard transactionListenerTask == nil else { return }
        transactionListenerTask = Task(priority: .background) { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { return }
                await self.handleStoreKitUpdate(verification)
            }
        }
    }

    func prepareCommerce() async {
        await refreshOwnedLifetimePurchase()
        await loadLifetimeProduct()
    }

    func refreshOwnedLifetimePurchase() async {
        var newestTransaction: Transaction?

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productID == CommerceConfiguration.lifetimeProductID,
                  transaction.revocationDate == nil else { continue }

            if newestTransaction == nil
                || transaction.purchaseDate > (newestTransaction?.purchaseDate ?? .distantPast) {
                newestTransaction = transaction
            }
        }

        ownedLifetimeTransaction = newestTransaction
        if purchaseActivity == .pending {
            purchaseActivity = .idle
        }
        await publishPurchaseState()

        if let newestTransaction {
            _ = await syncLifetimeEntitlementToCurrentSpace(using: newestTransaction)
        }
    }

    func handleStoreKitUpdate(_ verification: VerificationResult<Transaction>) async {
        switch verification {
        case .verified(let transaction):
            guard transaction.productID == CommerceConfiguration.lifetimeProductID else { return }
            if transaction.revocationDate != nil {
                ownedLifetimeTransaction = nil
                purchaseActivity = .idle
                await publishPurchaseState()
                await revokeSharedLifetimeEntitlement(matching: transaction)
                await transaction.finish()
                return
            }
            await handleVerifiedLifetimeTransaction(transaction, announce: purchaseActivity == .pending)

        case .unverified:
            logger.error("StoreKit delivered an unverified lifetime transaction")
        }
    }

    func handleVerifiedLifetimeTransaction(
        _ transaction: Transaction,
        announce: Bool
    ) async {
        guard transaction.productID == CommerceConfiguration.lifetimeProductID,
              transaction.revocationDate == nil else { return }

        ownedLifetimeTransaction = transaction
        purchaseActivity = .idle
        await publishPurchaseState()

        let sharedWithSpace = await syncLifetimeEntitlementToCurrentSpace(using: transaction)
        await transaction.finish()

        guard announce else { return }
        if sharedWithSpace {
            await showNotice(
                title: "空间已解锁",
                message: ""
            )
        } else {
            await showNotice(
                title: "这台设备已解锁",
                message: ""
            )
        }
    }

    func syncLifetimeEntitlementToCurrentSpace(using transaction: Transaction) async -> Bool {
        guard let relationship = appData.relationship else { return false }
        guard !appData.isLocalPreview else { return true }

        let entitlement = SharedSpaceEntitlement(
            productID: CommerceConfiguration.lifetimeProductID,
            unlockedAt: transaction.purchaseDate
        )
        if appData.sharedSpaceEntitlement != nil {
            return true
        }
        let recordID = CKRecord.ID(recordName: "relationship", zoneID: relationship.zoneID)
        let database = Self.container.database(with: relationship.scope.databaseScope)

        do {
            var record = try await database.record(for: recordID)
            if let existing = sharedEntitlement(from: record) {
                await adoptSharedEntitlement(existing, context: "保存空间永久权益")
                return true
            }

            for attempt in 0..<2 {
                apply(entitlement, to: record)
                do {
                    let savedRecord = try await database.save(record)
                    let savedEntitlement = sharedEntitlement(from: savedRecord) ?? entitlement
                    await adoptSharedEntitlement(savedEntitlement, context: "保存空间永久权益")
                    return true
                } catch let error as CKError
                    where error.code == .serverRecordChanged && attempt == 0 {
                    guard let serverRecord = error.serverRecord else { throw error }
                    if let existing = sharedEntitlement(from: serverRecord) {
                        await adoptSharedEntitlement(existing, context: "保存空间永久权益")
                        return true
                    }
                    record = serverRecord
                }
            }
        } catch {
            logger.info("Shared lifetime entitlement sync deferred: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    func apply(_ entitlement: SharedSpaceEntitlement, to record: CKRecord) {
        record[EntitlementRecordField.productID] = entitlement.productID as CKRecordValue
        record[EntitlementRecordField.unlockedAt] = entitlement.unlockedAt as CKRecordValue
    }

    func revokeSharedLifetimeEntitlement(matching transaction: Transaction) async {
        guard let relationship = appData.relationship,
              let sharedEntitlement = appData.sharedSpaceEntitlement,
              sharedEntitlement.productID == transaction.productID,
              matchesTransaction(sharedEntitlement, transaction),
              !appData.isLocalPreview else { return }

        await clearSharedLifetimeEntitlement(in: relationship)
    }

    func clearSharedLifetimeEntitlement(in relationship: RelationshipLocator) async {

        let recordID = CKRecord.ID(recordName: "relationship", zoneID: relationship.zoneID)
        let database = Self.container.database(with: relationship.scope.databaseScope)
        do {
            let record = try await database.record(for: recordID)
            record[EntitlementRecordField.productID] = nil
            record[EntitlementRecordField.unlockedAt] = nil
            _ = try await database.save(record)
            appData.sharedSpaceEntitlement = nil
            _ = await persistOrReport(context: "保存空间权益撤销")
            await publishData()
        } catch {
            logger.info("Shared lifetime entitlement revocation deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    func matchesTransaction(_ entitlement: SharedSpaceEntitlement, _ transaction: Transaction) -> Bool {
        return abs(entitlement.unlockedAt.timeIntervalSince(transaction.purchaseDate)) < 2
    }

    func sharedEntitlement(from record: CKRecord) -> SharedSpaceEntitlement? {
        guard record.recordType == "BetweenUsRelationship",
              let productID = record[EntitlementRecordField.productID] as? String,
              productID == CommerceConfiguration.lifetimeProductID,
              let unlockedAt = record[EntitlementRecordField.unlockedAt] as? Date else {
            return nil
        }
        return SharedSpaceEntitlement(
            productID: productID,
            unlockedAt: unlockedAt
        )
    }

    func adoptSharedEntitlement(_ entitlement: SharedSpaceEntitlement, context: String) async {
        guard appData.sharedSpaceEntitlement != entitlement else { return }
        appData.sharedSpaceEntitlement = entitlement
        _ = await persistOrReport(context: context)
        await publishData()
    }

    func publishPurchaseState() async {
        let state = PurchaseViewState(
            displayPrice: lifetimeProduct?.displayPrice,
            ownsLifetimePurchase: ownedLifetimeTransaction != nil,
            canMakePayments: SKPaymentQueue.canMakePayments(),
            activity: purchaseActivity,
            productLoadFailed: productLoadFailed
        )
        await MainActor.run {
            self.viewModel.purchase = state
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
        await refreshProximityMode()
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
                message = T("请在系统设置中登录 iCloud 后重试。")
            case .restricted:
                message = "这台设备限制了 iCloud，请检查屏幕使用时间或设备管理设置。"
            case .temporarilyUnavailable:
                message = "iCloud 暂时不可用，请稍后重新打开应用。"
            default:
                message = T("暂时无法确认 iCloud 状态，请检查网络和系统设置。")
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
            Task { await self.refreshOwnedLifetimePurchase() }
            await setPhase(appData.relationship == nil ? .needsRelationship : .ready)
            if appData.relationship != nil, let ownedLifetimeTransaction {
                _ = await syncLifetimeEntitlementToCurrentSpace(using: ownedLifetimeTransaction)
            }
            return true
        } catch {
            await setPhase(.needsICloud(message: cloudFriendlyMessage(for: error)))
            return false
        }
    }

    func discoverExistingRelationship() async {
        do {
            if let found = try await discoverRelationship(in: .private) {
                appData.relationship = found.locator
                appData.items = [:]
                appData.sharedSpaceEntitlement = nil
                appData.partnerJoinedAt = found.partnerJoinedAt
                appData.dirtyRecordNames = []
                appData.privateSyncState = nil
                privateSyncEngine = nil
                return
            }
            if let found = try await discoverRelationship(in: .shared) {
                appData.relationship = found.locator
                appData.items = [:]
                appData.sharedSpaceEntitlement = nil
                appData.partnerJoinedAt = found.partnerJoinedAt
                appData.dirtyRecordNames = []
                appData.sharedSyncState = nil
                sharedSyncEngine = nil
            }
        } catch {
            logger.info("Relationship discovery deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 从 iCloud 找回本账号已经存在的空间，连同「对方是否已经加入」一起带回来。
    struct DiscoveredRelationship {
        var locator: RelationshipLocator
        var partnerJoinedAt: Date?
    }

    func discoverRelationship(in scope: CKDatabase.Scope) async throws -> DiscoveredRelationship? {
        let database = Self.container.database(with: scope)
        let zones = try await database.allRecordZones().filter {
            $0.zoneID != CKRecordZone.default().zoneID
        }
        var candidates: [DiscoveredRelationship] = []

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
                    DiscoveredRelationship(
                        locator: RelationshipLocator(
                            zoneName: zone.zoneID.zoneName,
                            ownerName: zone.zoneID.ownerName,
                            shareRecordName: CKRecordNameZoneWideShare,
                            scope: scope == .private ? .privateOwner : .sharedParticipant,
                            createdAt: createdAt
                        ),
                        partnerJoinedAt: record[RelationshipRecordField.partnerJoinedAt] as? Date
                    )
                )
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return candidates.max { $0.locator.createdAt < $1.locator.createdAt }
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
                await showNotice(title: "本机存储失败", message: noticeMessage, autoDismiss: false)
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
                message: "空间已结束，但本机数据未能清除。请重新打开应用。",
                autoDismiss: false
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

    func cloudFriendlyMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        switch cloudError.code {
        case .notAuthenticated:
            return T("请在系统设置中登录 iCloud。")
        case .networkUnavailable, .networkFailure:
            return T("当前网络不可用。本机内容不会丢失，联网后会自动重试。")
        case .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return T("iCloud 正忙，请稍后再试。")
        case .permissionFailure:
            return T("当前账号没有访问这个空间的权限。")
        case .quotaExceeded:
            return T("iCloud 储存空间不足。")
        default:
            return cloudDiagnostic(for: error)
        }
    }

    /// CloudKit 拒绝请求时，真正的原因藏在 userInfo 和批次里的单条错误上，
    /// 界面上只剩一句「错误 15」。把服务器自己说的话带出来，才查得下去。
    func cloudDiagnostic(for error: Error) -> String {
        guard let cloudError = error as? CKError else { return error.localizedDescription }

        var parts: [String] = ["CKError \(cloudError.code.rawValue)"]
        let userInfo = (error as NSError).userInfo
        for key in [
            NSLocalizedFailureReasonErrorKey,
            NSDebugDescriptionErrorKey,
            "CKErrorServerDescription",
            NSLocalizedDescriptionKey
        ] {
            guard let text = userInfo[key] as? String, !text.isEmpty, !parts.contains(text) else { continue }
            parts.append(text)
        }
        for (item, itemError) in cloudError.partialErrorsByItemID ?? [:] {
            let name = (item as? CKRecord.ID)?.recordName ?? String(describing: item)
            parts.append("\(name): \(itemError.localizedDescription)")
        }
        return parts.joined(separator: " · ")
    }
}

/// CloudKit 取分享元数据时会分别回调单条结果和整体结果，用一次性的壳保证只 resume 一次。
private final class ShareMetadataContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CKShare.Metadata, Error>?

    init(_ continuation: CheckedContinuation<CKShare.Metadata, Error>) {
        self.continuation = continuation
    }

    func finish(with result: Result<CKShare.Metadata, Error>) {
        take()?.resume(with: result)
    }

    func finish(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<CKShare.Metadata, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}
