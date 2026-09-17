import CloudKit
import Foundation

enum CommerceConfiguration {
    static let lifetimeProductID = "cain.com.between-us.lifetime"
    static let freeItemLimit = 10
}

struct SharedSpaceEntitlement: Codable, Equatable, Sendable {
    var productID: String
    var unlockedAt: Date
}

enum AddItemResult: Sendable {
    case success
    case quotaReached
    case failed
}

enum PurchaseActivity: Equatable, Sendable {
    case idle
    case loadingProduct
    case purchasing
    case restoring
    case pending
}

struct PurchaseViewState: Equatable, Sendable {
    var displayPrice: String?
    var ownsLifetimePurchase = false
    var canMakePayments = true
    var activity: PurchaseActivity = .idle
    var productLoadFailed = false
}

struct AppData: Codable, Sendable {
    var items: [String: SecretItem] = [:]
    var relationship: RelationshipLocator?
    var sharedSpaceEntitlement: SharedSpaceEntitlement?
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
        case sharedSpaceEntitlement
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
        sharedSpaceEntitlement: SharedSpaceEntitlement? = nil,
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
        self.sharedSpaceEntitlement = sharedSpaceEntitlement
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
        sharedSpaceEntitlement = try container.decodeIfPresent(
            SharedSpaceEntitlement.self,
            forKey: .sharedSpaceEntitlement
        )
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
        sharedSpaceEntitlement = nil
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
        let images = attachments.images
        let firstVideo = attachments.videos.first
        let secondVideo = attachments.videos.count > 1 ? attachments.videos[1] : attachments.videos.first
        let audio = attachments.audio
        let now = Date()

        func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // 长文案样例：约 200 / 300 / 500 字，中英日韩混排，分别和照片、视频、语音配对，
        // 覆盖长文案在不同书写系统和媒介下的排版与滚动表现。
        let paperShortZH = "昨天你问我周末想去哪里，我说随便。其实我说随便的时候，心里是有点难受的。你不是第一次这么问了，我每次都认真想过，只是说出口之后你总是低头看手机，我就懒得再说第二遍。今天我自己去了那家以前常去的面馆，坐在老位置，吃到一半突然就不想吃了。我没有生你的气，我只是有点想你，想那个会把我话听完的你。我不想要你每次都靠猜，我只想你偶尔问我一句，认真等我答完。等你有空的时候，我们把周末的事重新聊一次，好吗？"

        let paperWordsKO = "한 번도 말하지 않은 게 있어. 지난번 가족 모임에서 사람들 앞에서 내가 살쪘다고 했잖아. 악의는 없는 거 알아, 이렇게도 괜찮다고 덧붙이기까지 했고. 그런데 그때 밥그릇을 들고 앉아 있다가 갑자기 말하고 싶지 않아졌어. 살이 문제가 아니라, 그 순간 내가 꺼내져서 보여진 기분이었어. 나중에 왜 그러냐고 물었고, 나는 아무렇지 않다고 했고, 너는 다행이라고 했고, 그냥 넘어갔지. 이런 작은 일을 나는 오래 모아 뒀어. 그때마다 말할 만한 일이 아니라고 생각했는데, 모이고 모이니까 한 덩어리가 되더라. 이걸 쓰는 건 사과를 받고 싶어서가 아니야. 어떤 농담은 내 안에 오래 남는다는 걸 알려 주고 싶었어. 네가 일부러 그런 거 아닌 건 아는데, 그래도 이 일이 내게 얼마나 무거운지는 알아 줬으면 해. 다른 사람들 앞에서는 나를 먼저 꺼내지 말아 줘. 집에 오면 뭐라고 해도 괜찮아. 농담을 못 받아 주는 게 아니라, 사람들 사이에서 대화의 한 줄이 되고 싶지 않은 것뿐이야. 옆에 누가 있을 때는, 그냥 나를 한 번 봐 주면 돼."

        let capsuleReplyZH = "你说你坐在老位置吃到一半就不想吃了，我看到这句话的时候，在工位上坐了很久。我一直以为我只是累，现在才明白，我是把你推远了。这半年项目赶得紧，我每天回家脑子还在转工作的事，你跟我说话我嗯一声就过去了，你说随便，我也就真的当成随便。上个月你提过一次想去看海，我记在了备忘录里，然后那条备忘录我一次都没再打开。今天下午我提前从公司出来，把车停在江边坐了一会儿，把你这半年发我的语音从头听了一遍。听到三月那条，你说你今天有点累，想让我抱一下，我回了个好的，我那时候正在开会。对不起。我不是不在乎，我是把在乎当成了不用说出口的东西。这些话说出来有点晚，但我想认真说一次：我记得你喜欢靠窗的位置，记得你吃面不放香菜，记得你每次不开心都会先去洗个很长的澡。以后我尽量八点前到家，进门先把手机放进抽屉，吃饭的时候不刷。周末如果你还想去海边，我来订票、订住的地方，路线也我来查。你不想去了也行，我们就在附近走走，找家没吃过的店。我不想每次都等你先难受了，我才反应过来。这段话我写在备忘录里，删了又改，改到凌晨才敢发给你，因为我不想只是嘴上说说。我知道光靠说还不够，所以我会从明天开始做给你看。"

        let capsulePlanKO = "주말 계획은 내가 진짜 고민해서 짜 봤어. 토요일 오전에 출발해서 기차로 바다에 가고, 점심은 항구 마을에서 먹자. 오후엔 너는 낮잠 자고, 나는 산책로를 한 바퀴 돌고 올게. 저녁 먹기 전에 깨우러 갈게. 일요일엔 관광지는 안 가고 근처만 천천히 걷다가 피곤하면 호텔로 돌아오자. 일정은 메모에 다 넣어 뒀고 언제든 바꿔도 돼. 몇 시에 나가고 싶은지만 알려줘, 나머지는 내가 다 할게. 준비할 건 없어, 사람만 나오면 돼. 이틀은 네가 정하는 거야, 나는 길만 제대로 찾으면 돼. 집에 있고 싶으면 그것도 괜찮아. 늦게까지 자고, 일어나서 간단히 뭐 해 먹자."

        let starThanksJA = "昨日、あれだけ話してくれてありがとう。あなたはいつもひとりで抱えて、抱えきれなくなってからやっと口にするから、話し始めたときにはもう限界だったんだよね。夕べ川沿いでボイスメッセージを最初から聞き直して、ふたりの間に言いそびれた小さなことがこんなにあったんだと初めて知った。あの店に行っていたことも、三月に海に行きたいと言ったのを覚えていてくれたことも、言わないまま自分の中にしまってあったことも。ためこんだまま離れることを選ばなくてよかった。もう一度チャンスをくれてありがとう。あなたが「どっちでもいい」と言うときは、これからはもう一回聞く。「大丈夫」と言うときは、ちゃんと顔を見る。今朝、出かける前に振り返ったあなたの顔を、わたしは長く覚えている。あの一瞬のほうが、昨日の話よりずっと安心できた。まだここにいてくれて、まだふたりでいられてよかった。"

        let starLoveEN = "Today I was going through the photo album and found pictures from when we first met. You were wearing a blue shirt washed almost white, standing outside the convenience store waiting for me with two bottles of water in your hand, one room temperature and one cold, because you were worried I couldn't drink anything too cold. I remember thinking, this is someone who will keep track of a lot of small things about me. And you have. You remember I don't eat bitter melon, that I need a small light on when I sleep, that when I'm sick I can only drink warm honey water, and that when I'm sad I don't want to be reasoned with, I want to be held first. You've forgotten things too, and I've forgotten things about you. But every time we sit down and actually talk, we find our way back. Yesterday you asked why I suddenly started going through the album, and I couldn't answer. It's because after everything you said, I kept thinking about how we started. Back then we had nothing, and we hid nothing from each other. Whoever was upset said so that same night. We never carried it into the next day. Then life got easier, and we somehow forgot that part. I picked a few photos from the day we made up and put them in the star jar. They're the ones where you're laughing carelessly, not posed. Just looking at them makes me smile. There's one of you crouching on the sidewalk tying your shoe, looking up halfway through, with your hair sticking up. I haven't really looked at you in a long time. This past half year I kept saying you'd changed, but I was the one who stopped looking first. From now on, no matter how busy things get, let's keep at least one day a month for nothing. We do nothing, we just stay together, phones far away, and it's fine if we don't say anything at all. I put that promise in here too. If you don't agree with it, come and take it out of the star jar."

        func demo(
            index: Int,
            kind: ContainerKind,
            author: String,
            text: String,
            minutesAgo minutes: Double,
            attachment: AttachmentMetadata?,
            additional: [AttachmentMetadata] = [],
            openedByCurrentUser: Bool = false
        ) -> SecretItem {
            let date = minutesAgo(minutes)
            let openedAt = openedByCurrentUser ? date.addingTimeInterval(1_800) : nil
            return SecretItem(
                id: UUID(uuidString: String(format: "56A0C0DE-%04d-4000-8000-000000000%03d", index, index))!,
                kind: kind,
                authorID: author,
                text: text,
                createdAt: date,
                updatedAt: date,
                openedByID: openedByCurrentUser ? currentUserID : nil,
                openedAt: openedAt,
                attachment: attachment,
                additionalAttachments: additional.isEmpty ? nil : additional
            )
        }

        let demos: [SecretItem] = [
            // 中文 200 字 + 一张照片：当时的画面配一段说不出口的委屈。
            demo(
                index: 1, kind: .paper, author: currentUserID,
                text: paperShortZH,
                minutesAgo: 600, attachment: firstImage
            ),
            // 韩文 300 字左右 + 语音：同一件事的另一面，说着说着声音比文字多。
            demo(
                index: 6, kind: .paper, author: counterpartID,
                text: paperWordsKO,
                minutesAgo: 540, attachment: audio
            ),
            // 中文 500 字 + 视频：最长的一段回应，配下班路上拍的画面。
            demo(
                index: 2, kind: .capsule, author: counterpartID,
                text: capsuleReplyZH,
                minutesAgo: 480, attachment: firstVideo
            ),
            // 日文 300 字左右 + 三张照片：谢谢对方愿意把话说清楚。
            demo(
                index: 3, kind: .star, author: currentUserID,
                text: starThanksJA,
                minutesAgo: 420, attachment: firstImage, additional: Array(images.dropFirst().prefix(2))
            ),
            // 韩文 200 字左右 + 语音：把约定说到底，附带一段口述的安排。
            demo(
                index: 4, kind: .capsule, author: currentUserID,
                text: capsulePlanKO,
                minutesAgo: 360, attachment: audio
            ),
            // 英文 500 字左右 + 两张照片 + 视频，已被当前用户打开。
            demo(
                index: 5, kind: .star, author: counterpartID,
                text: starLoveEN,
                minutesAgo: 300, attachment: firstImage,
                additional: Array(images.dropFirst().prefix(1)) + [secondVideo ?? firstVideo].compactMap { $0 },
                openedByCurrentUser: true
            ),
            // 只有语音
            demo(
                index: 7, kind: .capsule, author: currentUserID,
                text: "", minutesAgo: 240, attachment: audio
            ),
            // 只有多张照片
            demo(
                index: 8, kind: .capsule, author: counterpartID,
                text: "", minutesAgo: 200, attachment: firstImage,
                additional: Array(images.dropFirst().prefix(1))
            ),
            // 照片 + 视频，没有文字
            demo(
                index: 9, kind: .capsule, author: counterpartID,
                text: "", minutesAgo: 170, attachment: firstImage,
                additional: [firstVideo].compactMap { $0 }
            ),
            // 只有视频
            demo(
                index: 10, kind: .star, author: currentUserID,
                text: "", minutesAgo: 140, attachment: secondVideo ?? firstVideo
            ),
            // 只有一张照片
            demo(
                index: 11, kind: .star, author: counterpartID,
                text: "", minutesAgo: 110,
                attachment: images.count > 2 ? images[2] : firstImage
            ),
            // 语音 + 两张照片 + 视频
            demo(
                index: 12, kind: .star, author: currentUserID,
                text: "", minutesAgo: 80, attachment: audio,
                additional: Array(images.prefix(2)) + [secondVideo ?? firstVideo].compactMap { $0 }
            ),
            // 只有语音
            demo(
                index: 13, kind: .paper, author: currentUserID,
                text: "", minutesAgo: 55, attachment: audio
            ),
            // 只有一张照片
            demo(
                index: 14, kind: .paper, author: counterpartID,
                text: "", minutesAgo: 35,
                attachment: images.count > 3 ? images[3] : firstImage
            ),
            // 只有视频
            demo(
                index: 15, kind: .paper, author: currentUserID,
                text: "", minutesAgo: 22, attachment: firstVideo
            ),
            // 只有视频
            demo(
                index: 16, kind: .star, author: counterpartID,
                text: "", minutesAgo: 10, attachment: secondVideo ?? firstVideo
            )
        ].filter(\.hasContent)

        var changed = false
        for demo in demos {
            if var existing = data.items[demo.recordName] {
                let presentationChanged = existing.kind != demo.kind
                    || existing.authorID != demo.authorID
                    || existing.text != demo.text
                    || existing.attachment != demo.attachment
                    || existing.additionalAttachments != demo.additionalAttachments
                guard presentationChanged else { continue }
                existing.kind = demo.kind
                existing.authorID = demo.authorID
                existing.text = demo.text
                existing.attachment = demo.attachment
                existing.additionalAttachments = demo.additionalAttachments
                existing.openedByID = demo.openedByID
                existing.openedAt = demo.openedAt
                data.items[demo.recordName] = existing
                changed = true
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

        // 短文案三条：中文、日文、英文各一条，三种物件各一条。
        return [
            SecretItem(
                kind: .star,
                authorID: currentUserID,
                text: "谢谢你刚才帮我倒了杯水。",
                createdAt: hoursAgo(30),
                updatedAt: hoursAgo(30)
            ),
            SecretItem(
                kind: .capsule,
                authorID: counterpartID,
                text: "急がなくていいからね。明日、ふたりで考えよう。",
                createdAt: hoursAgo(18),
                updatedAt: hoursAgo(18)
            ),
            SecretItem(
                kind: .paper,
                authorID: counterpartID,
                text: "I'm not feeling great today and need some quiet time alone. It's nothing you did.",
                createdAt: hoursAgo(6),
                updatedAt: hoursAgo(6)
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

    // 房间里点中具体一份内容时的可打开判断，与顺序打开使用同一套条件。
    func isOpenableByMe(_ item: SecretItem) -> Bool {
        guard let current = items[item.recordName] else { return false }
        return current.authorID != currentUserID
            && current.openedAt == nil
            && activeCredits(kind: current.kind) > 0
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
    var purchase = PurchaseViewState()
    var isPerformingAction = false
    var shareSheet: ShareSheetPayload?
    var notice: AppNotice?

    var hasUnlimitedContent: Bool {
        data.isLocalPreview
            || purchase.ownsLifetimePurchase
            || data.sharedSpaceEntitlement != nil
    }

    var canAddContent: Bool {
        hasUnlimitedContent || data.items.count < CommerceConfiguration.freeItemLimit
    }
}
