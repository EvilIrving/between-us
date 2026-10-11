# 交换日记 duck-z（v2.1.0）技术拆解

记录日期：2026-09-18
来源：Mac 上已安装的 iOS 包 `/Applications/duck-z.app/Wrapper/duck-z.app`（`com.tistory.lsh424.duck-z`，v2.1.0，最低 iOS 18，Xcode 26.3 / iOS 26.2 SDK 构建，46 MB）+ 线上接口 `https://api-diary.kro.kr` 实测
素材：`research/duckz/screens/`（App Store 韩/中/日/台/美 五地区各 5 张截图，各语言单独出图）、`research/duckz/assets-inventory.txt`（Assets.car 406 个 rendition 全清单）
性质：只读拆解，用于对照耳语的产品与资产策略。**不是可复用素材来源**，他们的贴纸、吉祥物、字体一律不进我们的包。

包内主二进制带 FairPlay DRM 标记（`SC_Info/`、`LC_ENCRYPTION_INFO_64 cryptid=1`），但加密区间只有 4096 字节，`__TEXT` 整体可读：Swift 反射元数据（`__swift5_reflstr` / `__swift5_fieldmd`）完整，因此第 2 节的内容模型是从二进制还原出来的字段级事实，不是猜测。

---

## 0. 一句话结论

这是一个**单人维护、持续 5 年的韩国「交换日记」双端应用**：用自建服务端账号体系 + **轮次锁** + **戳一下（催办）** + **3 小时编辑窗**，把「几个人轮流写同一本日记」做成了一套带时序压力的协作仪式。它的纸是**照片本身**——10 种灰阶底色 + 166 张贴纸直接压在照片上，没有纸的物理感，也没有任何动画。

关键的一条架构事实（第二轮的结论）：**卡片不是参数化的，卡片是「成图」**。一条日记在服务端只有**一张图片 URL**（`Diary.img: String`），没有贴纸字段；贴纸在写入时就被客户端合成进那张图。阅读页只有一个 `diaryImageView`，没有任何贴纸容器。这跟 tinytype 的 `savedURL` 是同一条路——**不为重排留任何余地**。

和耳语的关系：**场景相邻，哲学相反，技术不可复用**。相邻在于「一对一/一小群亲密关系 + 私密内容 + 邀请加入 + 无公开社交」，相反在于它用义务和催促驱动表达，耳语用「留下、等待被主动发现」驱动表达。

它最值得抄的不是机制，是**资产纪律**：406 个素材只花 1.79 MB，而 10 个内置字体吃掉 26.5 MB。

---

## 1. 产品身份与商业结构

| 项 | 事实 | 证据 |
| --- | --- | --- |
| 产品名 | 덕지 / duck-z（`CFBundleSpokenName = 덕지`） | Info.plist |
| 内部工程名 | **MemoryTrace** | Firebase 项目 `memorytrace-42402`、URL scheme `memorytrace://`、`.swiftlint.yml` 里的 `MemoryTrace/...` 路径、Asset 名 `img_duck` |
| 开发者 | SEUNGHWAN LEE 个人开发者，Team `6D8SYQ63KK` | iTunesMetadata / entitlements |
| Bundle 前缀 | `com.tistory.lsh424.duck-z`（用 Tistory 博客反域名当命名空间） | Info.plist |
| 上线 / 最后更新 | 2021-06-18 / 2026-08-18（v2.1.0） | iTunes lookup |
| 评分 | 韩国 963 条 4.47；美国 12 条；中国 3 条 | iTunes lookup |
| 商店自我定位 | 「No.1 교환일기」；截图角标「누적 다운로드 50,000+」 | 韩区截图 |
| 关系模型 | 「친구, 연인」共享的交换日记本；一本可多人（截图出现 2 人徽标 + 「+4」） | 商店文案 + kr_02。成员上限未从二进制确认，至少 6 |
| 商业化 | AdMob（列表内原生卡 + 戳一下时的插屏）+ 唯一内购 `duckz_2500`「请团队喝一杯咖啡」打赏。无订阅、无会员、无模板付费 | `DiaryNativeAdLoader` / `PinchInterstitialAdManager` / `enum InAppProducts { duckz_2500 }` + `IAPHelper` |
| 平台 | iOS 18+，iPhone only，竖屏，单窗口；Android 同代 | `UIDeviceFamily=[1]`；Info.plist 里带 `ANDROID_CLIENT_ID`、`aosDeeplink`、`devicePlatform` |
| 语言 | 12 个 lproj，196–197 个 key，除 `service_name` 外 100% 对齐 | Localizable.strings 逐语言比对 |
| 权限 | 相机 / 相册 / ATT 追踪 | Info.plist + 12 个 InfoPlist.strings |
| 商店下载体积 | **50.2 MB**（`fileSizeBytes`），安装后 46 MB | iTunes lookup |
| 商店分类 | 主 `라이프스타일`（Lifestyle）+ 副 `소셜 네트워킹`（Social Networking） | iTunes lookup。**Apple 把它归到了社交网络** |
| 关于举报/拉黑 | **完全没有**。12 个语言表里 `report` / `block` / `abuse` / `신고` / `차단` 命中数全为 0，二进制里也没有 `reportUser` / `blockUser` / `abuseReport` | 见 §11 第 17 条 |
| 去广告 | **没有**。唯一内购是打赏，不是解锁。广告是永久的 | `InAppProducts` 只有一个 case |
| 最小系统版本 | 包内 `MinimumOSVersion = 18.0`，**商店元数据却是 `16.0`** | 两者不一致，见 §11 第 18 条 |

一个可以直接看出来的品牌残留：从 **MemoryTrace（情侣回忆记录）** 转到 **duck-z（朋友/情侣交换日记）**，Firebase 项目和 URL scheme 都留在了旧名字上。产品方向换了，工程底座没换。

---

## 2. 内容模型与 API

### 2.1 对象图（从 `__swift5_fieldmd` 还原的字段与类型）

字段名与**类型**都是从 `__swift5_fieldmd` 的 FieldRecord 里解出来的（相对指针指向 `__swift5_reflstr`），所以下面每一项的 `: Int` / `: String?` / `: Bool` 都是二进制事实，不是推断。

```
Book      bookId: Int, nickname: String, title: String, bgColor: Int,   ← 封面色是索引
          stickerImg: String?,                                        ← 封面贴纸是名字
          participants, modifiedDate: String, numOfPeople: Int, userId: Int,
          profileImage: String?, profileColor: String,
          whoseTurn: Int?, inviteCode: String, createdDate: String, userList[]

Diary     modifiable: Bool, userId: Int, diaryId: Int, nickname: String,
          title: String, img: String,      ← ★ 一条日记只有一张图，没有贴纸字段
          content: String,
          template: Int,                   ← ★ 类型确认是 Int
          createdDate: String, commentCnt: Int,
          isDelete: Int,                   ← ★ 删除是状态位，不是删除（见 §3.4）
          latestComment,
          pinchable: Bool, pinchCnt: Int,  ← ★ 催办是内容级状态
          isLiked: Bool, likeCount: Int,
          profileImagePath: String?, profileColor: String, diaryLikeInfo

Comment   commentId: Int, parentCommentId: Int, userId: Int, nickname: String,
          profileImagePath: String?, profileColor: String, content: String,
          createdDate: String, isDelete: Int, isUpdate: Int   ← 两个都是 Int 状态位

DailyNote userId: Int, nickname: String, profileImage: String?,
          profileColor: String, mood: String, content: String  ← mood 是自由字符串

Mood      love, good, flat, tired, blue, laugh, wink, tongue, kiss, shy,
          excited, starEyes, cool, thinking, confused, suspicious, surprised,
          shocked, nervous, embarrassed, crying, sobbing, disappointed,
          worried, scared, angry, furious, annoyed, eyeRoll, sleeping, sick,
          dizzy, party, angel, devil, masked            ← 36 个枚举值

Notice    noticeId: Int, imgUrl: String, urlScheme: String?, iosDeeplink: String?,
          aosDeeplink: String?, createdDate: String, modifiedDate: String

AppVersion devicePlatform: String, latestVersion: String,
           minimumVersion: String?      ← ★ 强制更新闸门可以是「没有」

Login     snsType(apple|google|kakao), snsKey, profileImg, userId, jwt,
          token, deviceID, nickname, deleteProfileImage
```

视图层能反推出的结构（也只列有把握的）：

```
StickerView         contentView, enableClose: Bool, enablecontrol: Bool,
                    showEditingHandlers: Bool, _minimumSize: Int,
                    _outlineBorderColor: UIColor, userInfo: Any?,
                    defaultInset: Int, defaultMinimumSize: Int
                    （＋手势中间量 beginningPoint/Center/initialBounds/
                      initialDistance/deltaAngle）
BottomSheetController  title: String, text: String, expandsForKeyboard: Bool,
                    contentView: UIView,
                    collapsedDetents: [UISheetPresentationControllerDetent]
                    ← 确认是系统 sheet + 自定义 detents
DiaryNativeAdLoader    adUnitID: String, numberOfAds: Int, loadedAds, onAdsLoaded,
                    rootViewController
PinchInterstitialAdManager  adUnitID: String, presentProbability: Double,
                    retryDelay: Double, maxRetryCount: Int,
                    isLoading: Bool, retryCount: Int, pendingCompletion
IAPHelper           productIdentifiers: Set<String>,
                    purchasedProductIdentifiers: Set<String>,
                    productsRequest: SKProductsRequest?,
                    productsRequestCompletionHandler: ((Bool,[SKProduct]?)->Void)?
StickerViewController  buttonImageNames: [String], stickerNames: [[String]]
                    ← 贴纸目录是「名字字符串的二维数组」，不是索引
```

响应包封：`{ statusCode: Int, code, message, data }`。`Routable` 协议里也留了 `(statusCode: Int, message: String)` 的元组形态。

两处值得单独指出的设计：

- **`Diary.template: Int`**：每条日记带一个整型编号。类型已确认是 `Int`，而且**日记结构里根本没有贴纸或布局字段**（见下面的 §4.4），所以它不可能是贴纸数据。最可能是「画布/卡片形态」的编号，但具体取值语义仍未确认，不要当成已知事实用。
- **`Diary.pinchable` + `pinchCnt`（Bool + Int）**：催办是**内容级**状态，不是关系级。列表里每条日记都自己带「还能不能被戳、被戳了几次」。
- **`Book.bgColor: Int` 与 `Book.stickerImg: String?` 是两种载体**：封面色用**索引**，贴纸用**名字**。这两种持久化方式在同一个数据结构里并存。

### 2.2 接口清单（`NetworkManager` / 各 Repository 的方法名）

```
login  invite  createBook  fetchBookInfo  fetchBookList
createDiary  fetchDiary  fetchDiaryList  modifyDiary  deleteDiary
comment  editComment  reply  deleteComment  fetchCommentList
toggleDiaryLike  fetchDiaryLikeUsers
fetchPinchInfo  pinch
createInvitationLink  validateinvitationToken  participateDiaryBook
exitBook  modifyBookCover
saveDailyNote  fetchBookDailyNotes
fetchUserInfo  updateProfile  updateLanguage  postFCMToken  deleteFCMToken
deleteAccount  notice  checkForceUpdateAppVersion
```

34 个方法，覆盖完整生命周期。`updateLanguage` 是把客户端语言上报给服务端——为了让**推送通知按用户语言发**。

### 2.3 服务端实测（线上）

```
$ curl -D- https://api-diary.kro.kr/
Server: nginx
HTTP Status 404 – Not Found                ← Tomcat 错误页

$ curl -H "x-platform: iOS" .../api/v1/app-version
{"data":{"latestVersion":"1.7.0","minimumVersion":"1.7.0","devicePlatform":"iOS"},
 "responseMessage":"앱 버전 조회 성공","statusCode":200}

$ curl .../api/v1/users/me
{"status":401,"error":"Unauthorized"}      ← Spring Security 默认体

$ curl -H "x-platform: ios" ...              ← 大小写敏感
{"statusCode":400,"message":"Unsupported platform.","code":"DAC01"}
```

结论：**nginx → Spring Boot/Tomcat，Java 服务端**。所有请求必须带 `x-platform: iOS`。所有 `responseMessage` 都是韩文，客户端不显示（用自己的本地化文案）——文案有两份真相。

### 2.4 完整路由表与随包发布的测试入口

二进制里有一整块连续的路由字符串，这是完整清单：

```
/api/v1/users/me/locale      /api/v1/app-version
/api/v1/invite/token         /api/v1/invite/participate   /api/v1/invite/books/
/api/v1/comment/             /api/v1/comment/list/       /api/v1/comment/update
/api/v1/diary/update         /api/v1/diary/list/
/api/v1/book/list?page=      /api/v1/book/exit/           /api/v1/book/update
/api/v1/token/fcm            /api/v1/token/test           ← FCM 测试接口
/api/v1/users/me             /api/v2/users/me             ← ★ v1 与 v2 并存
```

随包发布的东西（都是正式包里的，不是 debug 构建）：

| 入口 | 载体 | 作用 |
| --- | --- | --- |
| `DevViewModel.Server` | 枚举 | `real / dev / local` 三个服务端可切换 |
| `BASE_URL_DEV` / `BASE_URL_LOCAL` | Info.plist | `https://dev-api-diary.kro.kr`、`http://localhost:8080` |
| `InterfaceStyleTap` | 手势子类，挂在 `DiaryTopHeaderView` 上 | 点一下切明暗主题 |
| `/api/v1/token/test` | 接口 | FCM 推送测试 |
| Pulse（kean/Pulse） | SPM 依赖 | 网络请求日志库，带本地 UI |
| AdMob Ad Inspector | SDK 内置 | 广告调试面板 |
| `/api/v2/users/me` 与 v1 并存 | 接口 | 用户模型在迁移中 |

---

## 3. 产品设计：核心机制的取舍

这是 duck-z 唯一真正值得写长的部分，也是它和耳语最像、又最不像的地方。

### 3.1 三个时序机制

| 机制 | 规则 | 证据 |
| --- | --- | --- |
| **轮次锁** | 只有轮到的人能写；一本日记同时只有一个人处于「正在写」 | `Book.whoseTurn: Int?`、文案 `diary_turndescription = "내 차례가 되면 작성할 수 있어요."`、`main_iswriting / diary_iswriting`（首页与列表都显示「작성 중」） |
| **戳一下（Poke）** | 朋友写完 **3 小时后**才可戳；**每 3 小时**可重复；累计 **3 次**轮到下一位作者 | `diary_pinch_guide`（ko 三条 / en 少一条且编号 1、3）；`PinchRepository`、`PinchView`、Asset `duck_my_turn(_pinched)` |
| **3 小时编辑窗** | 写完 3 小时后不能再改 | `ReadingViewController` 里的硬编码韩文 `"일기 수정은 작성 후 3시간 이내에만 가능해요!"` |

节奏：写 → 3 小时内可改、3 小时后可被戳 → 每 3 小时戳一次 → 戳满 3 次轮到下一个。**一本日记的更新周期被服务端严格编排。**

### 3.2 做对的

1. **解决了真实问题。** 三个人轮流写一本日记，只要一个人不写就烂尾。「戳一下」不是游戏化，是**一个有上限、有冷却的催办通道**：3 次封顶，到顶就放过对方、把轮次交出去。这个「到顶就放弃」的设计比无限提醒克制得多。
2. **鸭子承担状态表达。** `duck_my_turn / duck_my_turn_pinched / duck_other_turn / duck_other_turn_pinched` 四个资产就把「轮到谁、被戳过几次」说清楚了（kr_03 里「✏️ 내 차례」条上三只鸭子，其中一只被戳过）。零文字、零数字。
3. **列表默认是月分组的照片网格，不是时间线。** kr_03 里 2025-09、2025-08 分组铺开缩略图，另有 polaroid（大卡片）视图可切。**回忆是拿来扫的，不是拿来刷的**——这和耳语「打开物件看到内容」的方向一致。
4. **阅读页的正文在卡片外。** 卡片只承载「照片 + 标题 + 点赞 + 日期」，正文落在页面背景上。卡片是物件，正文是文字——两者视觉分层清晰（kr_04 / cn_04 / jp_04）。
5. **封面彩色、内页灰阶**：日记本封面用彩色底 + 一张大贴纸 + 标题 + 成员头像堆叠（kr_02），而每条日记只有灰阶纸色。颜色只用来表达「容器」，内容区保持克制。

### 3.3 做错的 / 与耳语冲突的

1. **每条内容带评论区，而评论区事实上是群聊。** kr_05 里 5 个人在一条日记下你来我往，有「답글 달기」、有「1시간 전」。这直接把产品拉进了「聊天工具」的范畴——正好是耳语明确不做的。
2. **催办变成广告位。** `PinchInterstitialAdManager` 挂在戳一下的路径上，带 `presentProbability`、`retryDelay`、`maxRetryCount`。「我戳你一下」和「看一条广告」被绑在一起。
3. **写日记页底部带评论输入条**（kr_04 / cn_04 都可见，占位符「댓글을 남겨 보세요. / 留下评论吧。」）。写作页和阅读页共用同一套容器，导致一条尚未保存的内容旁边有评论入口。
4. **一句话状态条会长成每日打卡。** 最新版更新日志是「이제 친구들과 상태 메시지를 공유할 수 있어요!」——`DailyNoteStripView` 在日记本顶部铺一排头像气泡，每人一个心情脸 + 一句话（`DailyNoteSheetView`：recentMoods 最近、gridMoods 全量、counterLabel 字数、questionLabel「오늘 어땠어?」）。形态很轻、想法不坏，但它天然会变成「今天你打卡了吗」。**这条对耳语是明确的禁区。**
5. **没有草稿、没有离线。** 中途退出内容即丢（`write_exit_description` 明确警告），断网列表为空。

一句话：duck-z 的机制是**为了让人写**，耳语的机制是**为了让表达不被打扰**。前者需要服务和编排，后者需要物件和安静。

### 3.4 删除是「墓碑」，不是消失

`Diary.isDelete: Int`、`Comment.isDelete: Int`、`Comment.isUpdate: Int` 都是状态位而不是删除；列表里有专门的 `DeletedDiaryCell` 和 `deletedDiaryIcon`，文案里有：

- `diary_deleteddiary`「已删除的日记条目」
- `comment_deletedcomment`「该评论已被删除。」
- `my_hidedeleted`「隐藏已删除的日记」——**由自己选择看不看**
- `entry_delete_description`「删除的日记无法恢复」

也就是说：**你删掉一条，其他成员仍然知道「这里曾经有过一条、被删了」，直到他们各自决定隐藏。** 这不是偷懒，是一个关系设计选择——删除是可见的动作，而不是默默地消失。
对耳语的意义：耳语现在删除就是消失。要不要让另一半知道你删了什么，是个必须明确做决定的问题；duck-z 选的是「让你知道，但不逼你看」。

### 3.5 一个战略信号：最低摩擦的功能，最后才加

2.1.0 的更新日志只有一句：「이제 친구들과 상태 메시지를 공유할 수 있어요!」（现在可以和朋友们分享状态消息了），对应的是「心情脸 + 一句话」的状态条（`DailyNoteStripView` / `DailyNoteSheetView`）。

用词是「이제 …있어요」（现在可以了），说明是**新功能**。一个做了 5 年、以「轮流写长日记」为核心的 App，在 2.1.0 才加上整个产品里摩擦最低的输入，这个顺序值得注意：

- 轮次锁 + 3 小时窗 + 催办是一个**高摩擦、高承诺**的循环，它的留存依赖两个人（或几个人）同时配合。
- 一句话状态是**零承诺**的：选个表情，写一行，或者什么都不写。它不需要轮到你。

此处我的读读（推断，不是事实）：他们开始往低摩擦那一端找日常活跃，因为靠「轮到你了」撑不起每日打开。这正是耳语必须提前想清楚的事：**主动发现同样面临「没人打开」，而低摩擦的标准解法就是打卡。** 耳语的出路只能在物件本身，不能在降低表达门槛上。

---

## 4. 卡片与贴纸编辑器

### 4.1 卡片结构

```
作者头像 + 昵称
┌ 圆角卡片 ───────────────────┐
│  照片（贴纸直接压在照片上）    │
│  标题              ♥ 10      │
│  2025-09-09                 │
└─────────────────────────────┘
正文（在卡片外，页面背景上）
────────────
评论输入条
```

- **卡片纸 = 颜色资产，不是图片**：`bg01`–`bg10` 十组，全部是灰阶/白/黑（浅色下的 `bg10` 是 0.129 近黑「黑纸」，深色下变 0.31 深灰）。没有任何彩色纸。
- **文字色**：`text01`–`text04` 四组，同样带暗色变体。
- 纸张质感（网格/横线/圆点/编号）不在这里——那些是贴纸分类（section4/5/8），不是纸。

### 4.2 贴纸编辑器（这个 App 最难的一块）

`StickerView` 是一个完整的 Instagram 式变换框，全部用 UIKit 视图实现：

| 能力 | 实现 |
| --- | --- |
| 移动 | `moveGesture`（UIPan）+ `beginningPoint` / `beginningCenter` 记录手势起点 |
| 缩放 | `UIPinchGestureRecognizer` + `initialBounds` / `initialDistance`，带 `_minimumSize` 下限 |
| 旋转 | 右下角把手 `controlImageView` + `controlGesture`（Pan）+ `deltaAngle`（**不用 UIRotationGestureRecognizer**） |
| 删除 | 左上角 `closeImageView` + `closeGesture`，由 `enableClose` 控制是否出现 |
| 外围 | `_outlineBorderColor`、`showEditingHandlers`、`enablecontrol` 全部是属性，不是常量 |

`StickerViewController` 提供分类按钮（`buttonImageNames` / `stickerNames` / `buttons` / `_currentButton`）+ 预览滚动 + 贴纸网格；`StickerViewLayout` / `StickerLayout` 是自定义 flow layout。

写页贴纸目录是一份 `[[String]]`（`stickerNames`），即**按名字字符串索引**，不是按数字下标。至于日记里的贴纸——它根本不落地，看下一节。

### 4.3 「保存到相册」与「上传到服务端」是同一件事

`entry_save_title`「保存日记 / 日记已保存到相册」→ 二进制里有 `UIGraphicsImageRenderer`（含 `UIGraphicsImageRendererContext` 闭包签名）+ `PHPhotoLibrary.performChanges` / `creationRequestForAsset`。即：**把整张卡片离屏渲染成图**，一份写相册，一份上传。

上传前会压缩（`compressionQuality` 出现过；`jpegData` / `resizeImage` 未出现，说明用的是标准 JPEG 压缩路径而不是自写缩放）。

### 4.4 关键结论：卡片是「成图」，不是参数

第二轮把日记、阅读页、写作页、封面的字段全部对完之后，可以确定：

| 证据 | 事实 |
| --- | --- |
| `Diary` 的全部字段 | 只有一个 `img: String`（一个 URL）。**没有贴纸数组、没有位置、没有缩放、没有旋转** |
| `ReadingViewController` 的视图字段 | `polaroidView` + 一个 `diaryImageView`。**全屏只有一个图片视图，没有任何贴纸容器** |
| `WritingViewController` 的视图字段 | 才有 `$__lazy_storage_$_stickerView`、`_selectedStickerView`、`stickerViewController` |
| 写页的提示文案 | `write_edit_picture_description`「修改会删除所有已附的贴纸和照片」——改图就清空画布，因为画布就是图 |
| 写页的取图入口 | `UIImagePickerController`（未开 `allowsEditing`，`allowsEditing` 在整个二进制出现 0 次） |
| 纯色日记 | `write_selectpicture_color`「纯色」+ `colorIndex: Int?` → 选纯色时也是把「底色 + 贴纸」合成成一张图 |

**所以两条日记在服务端的差别，就是一张 URL 的差别。贴纸、底色、标题、日期全部被烘进像素。**

代价（每条都真实）：

- 贴纸**不能被重新拿走**，只能改图重传；不能重排、不能换字号、不能适配其他语言。
- 图片分辨率被固定死。排版器改版后，旧日记不会跟着变（好也是坏）。
- 文字不可选中、不可搜索、不可被辅助技术读到（对无障碍是直接的坑）。

收益（也很实）：

- **永远不会重排。** 没有「写完 3 页打开变 4 页」这类问题。
- 服务端零渲染成本；列表缩略图零成本（同一张图裁成方图）。
- 跨端一致：Android 不需要知道贴纸和底色是什么。

#### 这对耳语意味着什么

这是第三个选项。目前能看到三条路：

| 路线 | 谁在用 | 冻结的是什么 | 代价 |
| --- | --- | --- | --- |
| 可平铺皮肤 | tinytype | 冻结模板参数，纸可无限加长（中段一块砖按原尺寸反复平铺，见 `TINYTYPE_TEARDOWN.md` §5） | 纸失去了实物尺寸 |
| **成图** | **duck-z** | **冻结像素** | **贴纸不可再编辑、分辨率不可变、文字不可读** |
| 参数化实物 | 耳语（当前） | 冻结参数（`paperID`） | 要自己承担分页、重排、容量 |

duck-z 的选择比 tinytype 更彻底。而他们**并不是不知道成图的代价**：日记全用成图，封面却保留了参数化（`bgColor: Int` + `stickerImg: String?`）——因为在封面上贴纸不需要被反复调整。

对耳语的价值：**「成图」能省掉的东西（重排、分页、分辨率、跨语言），恰好是耳语「实物感」所依赖的东西。** 星星挂件要能在瓶子里被拨动、纸团要能被重新摊开，就不能成图。但反过来，任何**不需要再动**的展示面（分享卡、导出图、关于页插画）都应该直接成图，不要为了「统一架构」去参数化它。

> 反过来说：duck-z 把贴纸编辑器做得那么好，却让它成为**一次性**能力——写完就变成像素，再也回不到编辑器。耳语若要做可反复调整的布置，这一步必须提前想清楚。

---

## 5. 动画

老实说：**几乎没有动画**。

统计（去重后的符号与选择器计数）：

| 动画相关 API | 次数 |
| --- | --- |
| `animateWithDuration:animations:` | 2 |
| `animateWithDuration:delay:options:animations:completion:` | 1 |
| `transitionWithView:duration:options:animations:completion:` | 1 |
| `snapshotViewAfterScreenUpdates:` | 1 |
| `UIViewPropertyAnimator` | 1 |
| `animateKeyframesWithDuration` | **0** |
| `CAAnimation` / `CAKeyframeAnimation` / `CABasicAnimation` / `CASpringAnimation` | **0** |
| `CATransition` / `CAShapeLayer` / `CAGradientLayer` / `CAReplicatorLayer` | **0** |
| `UIPercentDrivenInteractiveTransition` / `UIPresentationController` / `transitioningDelegate` | **0** |
| `UISpringTimingParameters` / `CAMediaTimingFunction` | **0** |

三条结论：

1. **它的「手感」不来自动画，来自手势。** 贴纸拖拽/缩放/旋转是直接改 transform 的即时跟手，没有弹簧、没有惯性、没有吸附、松手不回弹。用户能感知到的顺滑是「无延迟」，不是「有物理」。
2. **模态全部交给系统。** `UISheetPresentationController` + `detents` 出现（`BottomSheetController` 包装系统 sheet，SponsorBottomSheet 用它），不自造 presentation controller、不做自定义转场。这条与耳语 AGENTS「弹窗分层要克制、优先系统 sheet」的判断一致，而且他们已经验证过可行。
3. **值得拿的唯一一条：贴纸编辑器的参数化。** 最小尺寸、把手位置、外框颜色、是否可关、是否显示编辑框——全部是属性。这正是耳语要的「位图负责身份，代码负责参数化原语」，只是他们只做到了变换，没做到物理。

对照耳语：duck-z 是**工具动效**（操作完成即结束），耳语是**物动效**（重量、阻尼、碰撞、开盖、揭示）。两者不冲突，也互相学不到什么。

---

## 6. 性能

### 6.1 可测事实

```
总包体          46 MB
  内置字体      26.5 MB   ← 58%
  主二进制      16.7 MB
  Assets.car     1.79 MB  ← 406 个 rendition
  Base.lproj      232 KB
  其余（框架/plist/签名）
```

字体明细：

| 文件 | 大小 |
| --- | --- |
| LINESeedTW_TTF_Rg / _Bd | 6.87 / 6.56 MB |
| LINESeedJP_A_TTF_Rg / _Bd | 3.68 / 3.52 MB |
| LINESeedKR-Rg / -Bd | 3.42 / 3.42 MB |
| LINESeedSansTH_A_Rg / _Bd | 0.078 / 0.077 MB |
| WixMadeforDisplay-Regular / -Bold | 0.089 / 0.089 MB |

**繁体中文一个语言包就 13.4 MB。** 泰文只占 0.15 MB。10 个 TTF 通过 `UIAppFonts` 全量注册，没有子集化、没有按需。

主二进制 16.7 MB 是静态链接的全部第三方：RxSwift/RxCocoa、Alamofire、Kingfisher、SnapKit、Toast-Swift、**Pulse（网络日志，开发期工具）**、Firebase（Auth/Core/Crashlytics/Messaging/Installations/Analytics）、GoogleSignIn + AppAuth + GTMAppAuth、Kakao SDK（含 FriendCore/CertCore）、GoogleMobileAds + UMP。

### 6.2 结构性的性能特征

- **没有本地数据库。** `CoreData` / `SQLite` / `Realm` / `GRDB` 在二进制里出现 0 次。列表是分页拉取（`curPage` / `hasNext` / `book/list?page=`），图片靠 Kingfisher（`ImageCache`、`memoryStorage`）。**断网 = 空列表**，翻历史靠网络。
- **列表是异构 UICollectionView**：`displayList` 里混着 `polaroid / grid / diary / ad` 四种 cell，自定义 `DiaryPolaroidLayout` / `DiaryMiniLayout` / `StickerLayout`。用了 `prefetchItemsAtIndexPaths` 预取，cell 尺寸用懒加载常量（`girdLayoutCellSize` / `polaroidLayoutCellSize` / `deletedCellSize`）一次算好，**不用 `estimatedItemSize`**——对固定尺寸网格是正确取舍。
- **广告在关键路径上**：`DiaryNativeAdCell` 按 `firstAdAfterContentCount` 先插第 N 条之后，再按 `adIntervalContentCount` 定间隔插；`PinchInterstitialAdManager` 挂在戳一下上。原生广告 cell 与列表复用、预取、滚动性能都要额外照顾。
- **内存峰值在「渲染成图」**：卡片保存到相册要把照片 + 叠加贴纸整体离屏渲染，照片原图分辨率没有上限约束的证据。
- **素材侧几乎不花钱**：406 个 rendition 只占 1.79 MB。贴纸 100pt（200×200@2x）、心情脸 60pt（120×120@2x）、其余能用矢量的全部用 PDF。这是极好的素材预算纪律。

### 6.3 一句结论

46 MB 里，**真正属于「内容」的只有 1.79 MB，其余是字体和 SDK**。耳语当前规划的 CDN 字体 230 MB 比它贵一个数量级——TINYTYPE_TEARDOWN 的「woff + 自己 inflate」结论在这里第二次成立，而且 duck-z 连子集化都没做就已经花了 26.5 MB。

---

## 7. 美术资产：规划 / 使用 / 加载

### 7.1 规划：按「载体」分四类，而不是按「用途」

| 类别 | 载体 | 数量 | 尺寸/形式 |
| --- | --- | --- | --- |
| 纸色 | **Color Asset**（不是图） | 10 组 × 明暗 | 灰阶/白/黑 |
| 文字色 | **Color Asset** | 4 组 × 明暗 | 灰阶 |
| 贴纸 | Image Asset | **166** | 200×200@2x（100pt）；数字类为矢量 PDF |
| 心情脸 | Image Asset（同一只鸭子的 36 种表情） | **36** | 120×120@2x（60pt） |
| 图标/插画 | 矢量 PDF 为主 | ~70 | `invitationImage`、`splash_icon`、`img_duck`、`popup_duck`、`duckz_sponsor` |
| 界面色 | Color Asset | `colorRed/Orange/Yellow/Green/OceanBlue/SystemBlue/Blue/DarkBlue/Purple/Pink` | 只用于**日记本封面** |

贴纸的 8 个分类（`RenditionName` 揭示了原始文件名，而 asset 名是流水号）：

| 段 | 原始名 | 数量 | 内容（看图后确认） |
| --- | --- | --- | --- |
| section1 | `alphabet_a` … `alphabet_z` | 26 | 小写字母，圆润手写体，**每个字母一个颜色**，带白色描边 |
| section2 | `alphabet_A` … `alphabet_Z` | 26 | 大写字母，同一套手写体（颜色与小写那套不同） |
| section3 | `Sticker@2x` 系列 | 8 | 通用涂鸦（放射线、小标记之类） |
| section4 | `line_1` … `line_10` | 10 | 线条 / 飘带（弯的螺旋形） |
| section5 | `round_1..5` + `roundring_1..5` | 10 | 5 个实心圆 + 5 个圆环 |
| section6 | `Music_01` … `Music_24` | 24 | 音乐主题（唱片、音符等） |
| section7 | `Nature_01` … `Nature_12` | 12 | 自然主题（花、叶等） |
| section8 | `number_{red,yellow,blue,green,purple}_0..9` | 50 | 五色数字 |

**合计 166 张，一个 section 一个主题，同一个主题内 5–10 张起步。** 分类不是按情绪，是按**可组合的视觉元素**——字母、数字、线条、圆环、主题插画。用户拼的是字和装饰，不是情绪。

看图之后能补上的三条：

- **字母贴纸是主力**：52/166 是字母，用户靠拼字把「cute」「HAPPY」压在照片上（商店截图里就是这两个词）。数字贴纸再补 50。真正意义上的「插画」只有 section3/6/7 的 44 张。
- **36 个心情脸全部是同一只白鸭的 36 种表情**（爱心眼、发火、大哭、吹哨派对、光环天使…），贴纸质感（右下角有一个翻角）。也就是说鸭子同时承担了品牌、心情、轮次状态三件事。
- **App 图标就是 `splash_icon`**：黑圆 + 白鸭 + 翻角，跟心情脸同一个视觉系统。邀请插画 `invitationImage` 是一个黄色信封 + 礼花。

带图的可视化核对见 `research/duckz/gallery.html`（263 个素材全部列在里面）。

### 7.2 规划里最该抄的和最该避的

**该抄：**

- **承载形式正确**：纸色、文字色、界面色一律是 Color Asset（带 `UIAppearanceDark` 变体），不产生任何位图成本。深色模式免费拿到。
- **尺寸纪律**：贴纸 100pt、心情脸 60pt，只出 @2x，不上 @1x/@3x。**矢量优先**：所有能矢量的（图标、数字、吉祥物、邀请插画、启动图）都是 PDF。
- **描边保证可读**：贴纸压在照片上是任意深浅的背景，所以字母/数字贴纸全部带白色描边（kr_01 的 `cute`、`HAPPY` 都是这个做法），配 `alphaBlackBase` / `alphaWhiteBase` 两个纯色底。**这条对耳语的星星挂件和情绪纸团同样成立**——压在深色照片/深色瓶体上必须有描边或高光。
- **吉祥物承担状态表达**：`img_duck`、`img_duck_colorTheme`、`duck_my_turn(_pinched)`、`duck_other_turn(_pinched)`、`popup_duck`、`duckz_sponsor`——一只鸭子覆盖品牌、轮次状态、弹窗、赞助页。资产数量极少，表达面很大。
- **封面彩色 / 内页灰阶**的克制分层。

**该避：**

- **资产名是流水号 `sectionN_M`，和内容无关。** 真名只存在于 `RenditionName`（`alphabet_a`、`number_red_0`、`Music_01`）。这里要区分两件事：**持久化用的是名字字符串**（`Book.stickerImg: String?`，写页的目录是 `stickerNames: [[String]]`），不是下标——这一点他们做对了，插贴纸不会错位；**但资产名本身不可读**，所以调试和维护时要靠 `RenditionName` 才知道 `section8_24` 是什么。耳语的做法应该是两边都对：语义资产名（`StarCharm_Candy_Joy`）+ 用名字（或稳定 ID）持久化。
- **没有版本化设计稿坐标**：贴纸 100pt 的画布与最终卡片尺寸的关系没有体现在资产里（对比 tinytype 的 1200 宽设计稿坐标系），所以「贴纸在白底上看多大」和「压在照片上多大」靠代码算。这一点因为卡片最终会被烘成图（§4.4）而不致命，但如果以后要做可编辑的布置，就会变成必须补的课。

### 7.3 加载：全部内置，零按需

- `NSBundleResourceRequest` 出现 **0 次**，没有任何 on-demand tag。**166 张贴纸 + 36 个心情脸 + 全部图标都内置在 Assets.car（1.79 MB）。**
- 好处：零网络、零首启等待、离线可用、永不 404。
- 代价：加素材 = 发版。
- **因为只有 1.79 MB，这个选择完全正确。** 这是 duck-z 最值得直接照搬的一条：**贴纸/心情/挂件这类小素材内置，不要建 CDN。** 耳语现在的星星挂件与情绪纸团正好属于这一类。
- 远程素材只有用户内容：照片（`img` URL）和头像（`profileImagePath`）走 Kingfisher，没有自定义压缩、预取策略的证据。
- 字体走 `UIAppFonts` 全量注册（10 个 TTF 一次加载，无子集化）。

---

## 8. 字体与本地化

**字体族**：LINESeed（KR / JP / TW / TH）+ WixMadeforDisplay（拉丁与数字）。用 LINE Seed 一个家族覆盖 CJK + 泰文，视觉统一、字重齐全。

**覆盖度**：12 个 lproj（en/ko/ja/zh-Hans/zh-Hant/de/es/fr/id/ru/th/vi），196–197 个 key，**除 `service_name` 外 100% 对齐**；12 个语言里除 en 外全部有 `InfoPlist.strings`（权限文案本地化）。这个纪律比多数独立开发者规范。

**但质量是机器翻译级**：

- 中文 `日记条目`、`我们已准备了更好的最新版本`、`停止显示`、`解码失败`、`戳一下` —— 都是从韩文（原为日文式韩语）硬转的，不符合中文习惯。
- `en` 的 `diary_pinch_guide` **只有两条**且编号是 1、3（缺「每 3 小时可以重复」），而 ko/zh 有三条 —— 少的那条只在 en 丢了。
- **有一批用户可见文案硬编码韩文，不进 Localizable**：
  - 赞助页：`덕지팀에게 커피 한 잔 사주기`、`서비스 유지를 위해 커피 한잔 값을 후원해 주세요!`、`덕지를 잘 사용하고 계신가요?`
  - 编辑窗提示：`일기 수정은 작성 후 3시간 이내에만 가능해요!`
  - 广告日志：`전면 광고 로드 실패` / `네이티브 광고 로드 실패`
  → **非韩语用户会看到韩文**（编辑窗提示是普通用户一定能碰到的路径）。
- 服务端所有 `responseMessage` 是韩文，客户端不显示（用自己本地化文案）——文案有两份真相，改文案要两边改。

对照耳语 AGENTS「修改任何用户可见文案时必须同步四种语言」「按各语言自然重写，不逐字直译」——duck-z 正好是**覆盖度达标、自然度不达标、还有漏网硬编码**的样本。

### 8.1 一个可检验但没解掉的观察：约一半 key 在二进制里找不到引用

197 个 key 中，只有约 **98 个**能在主二进制的任何位置找到字面量引用（全文件字节搜索，不是 `strings` 单节）。缺的那局部不是随机的：

| 组 | 总量 | 找到引用 | 备注 |
| --- | --- | --- | --- |
| `picture_*`（裁剪/翻转/旋转） | 8 | **0** | 见下 |
| `policy_*`（同意条款/隐私） | 6 | **0** | 工程里也没有任何条款同意页类 |
| `permission_*`（自定义权限弹窗） | 6 | **0** | |
| `common_*`（取消/保存/删除…） | 12 | **0** | 全是弹窗按钮文案 |
| `my_*` | 33 | 13 | 找到的全是子页面文案（个人资料编辑/主题/注销）；缺的全是主页行标题与弹窗标题 |
| `write_*` | 15 | 12 | 缺 `write_header`（正是写作页的导航标题）等 |
| `diary_*` / `entry_*` / `comment_*` / `cover_*` / `invitation_*` | 60+ | 大部分 | 反而不缺 |

我把能想到的机制都排除了：UTF-16 存储（0）、camelCase 生成枚举（0）、前缀拼接（`"my_"` / `"write_"` 这类裸前缀不存在）、字符串在 .nib 里（全 bundle 搜不到）、部分加密（`__TEXT,__cstring` 可打印字节率 0.896，且 `LC_ENCRYPTION_INFO_64` 只声明 4096 字节）、别的二进制（全包只有主二进制和通知扩展两个 Mach-O）。

**所以结论只能停在「我无法判定机制」上**。能确定的是其中两组：

- `picture_*`（8 个）看着就是同一功能先后用过的两套 key（旧 `picture_*` → 新 `write_selectpicture_*`），旧的没删；因为**裁剪/旋转/翻转的 UI 在这个构建里不存在**：没有任何裁剪视图类、没有第三方裁剪库、唯一的取图入口是 `UIImagePickerController` 且没开编辑。
- `my_privacy` / `my_terms` / `my_opensourcelicense` 在**所有 12 个语言文件里都是英文原文**（中文表里也是 `Privacy Policy`），说明这三个入口本来就没做本地化。

对耳语的价值：**一个无法静态校验的 key 表本身就是负债。** 耳语强制四语言同步，如果 key 与使用方的关系不可机械检查，那么“是否漏翻”“是否死文案”就只能靠人看。可靠的 cheap 做法只有两条：key 一律是字面量、不在运行时拼接；以及一个脚本比对 `.strings` 的 key 集合与代码里的字面量引用。

---

## 9. 与耳语的关系：竞品判定

### 9.1 逐项对比

| 维度 | duck-z | 耳语 |
| --- | --- | --- |
| 关系模型 | 2–6 人共享一本交换日记（朋友或恋人） | 一个空间两个人 |
| 内容形态 | 每条 = 照片卡片 + 标题 + 正文 + 点赞 + 评论串 | 星星瓶 / 胶囊瓶 / 纸团篓三个物件 |
| 时序 | 轮次锁 + 3 小时编辑窗 + 3 小时可戳 + 戳满 3 次换人 | 无时序、无催办、无提醒 |
| 发现方式 | 通知推送（「重要的人写了日记马上通知」）+ 列表浏览 | 主动打开物件，自己发现 |
| 互动 | 点赞 + 评论 + 回复（事实上是群聊） | 交换表达，无评论区 |
| 账号/同步 | 自建服务端 + Apple/Google/Kakao 登录 + JWT | iCloud CloudKit + CKShare，无账号体系 |
| 离线 | 不可用（无本地库） | 本地保存 + 离线可用 + 恢复联网同步 |
| 商业化 | 广告（原生 + 插屏）+ ₩2,500 打赏 | 一次买断 ¥18 / US$2.99 |
| 隐私 | ATT 追踪 + Firebase Analytics + Crashlytics + AdMob | 不引追踪与第三方分析 SDK |
| 平台 | iOS + Android 双端 | iOS 原生 |

### 9.2 判定

**低竞争风险的相邻产品。** 它不抢耳语的用户：它的市场几乎全在韩国（KR 963 条评分，US 12 条，CN 3 条），它的关系单位是「几个朋友」，耳语的单位是「两个人」。同一个用户可能同时装两个，用途不同——duck-z 是和朋友一起、可以公开讨论的日记，耳语是和恋人之间、不打算给别人看的表达。

**但它的存在证明了一件事**：「轮流写」这个约束在韩语市场是刚需。5 年不退、963 条 4.47 分、自称 50k 下载——靠的是**时序压力**，不是贴纸。贴纸是包装，「对方必须轮到」才是留存机制。

这对耳语的真正意义是提醒：**主动发现的代价是「可能永远没人打开」。** duck-z 的解法是催促和广告；耳语的反制不能是「也加个提醒」，只能是**让留下的东西本身值得被打开**（物件的生命感、开盖的仪式、纸团的重量）。这是唯一不破坏产品原则的竞争方式。

### 9.3 一个必须显式承认的分歧

duck-z：关系需要被维护，维护需要节奏，节奏需要提醒，提醒可以变现。
耳语：表达是礼物，礼物不该有 deadline，也不该有人催。

技术拆解只能证明一件事：**duck-z 那条路上的每一个部件（轮次锁、催办、3 小时窗、评论区、插件广告位）我们都能做，且都不难**（贴纸编辑器是全 App 最难的一块，而它也只是一个变换框）。要不要做，是产品决定，不是技术决定。

---

## 10. 能拿的 / 不能拿的

### 值得拿（7 条，都很便宜）

1. **小素材内置，不建 CDN。** 166 张贴纸 + 36 个心情脸 = 1.79 MB。耳语的星星挂件、情绪纸团、纸篓纸团同理，进 `Assets.xcassets` 就够，不要走下载。
2. **位图尺寸纪律**：贴纸 100pt、表情脸 60pt、只出 @2x、矢量优先。可直接当耳语的资产规格基线。
3. **贴纸必须有描边/透明通道**，保证压在任意照片或深色背景上都可读（`cute` / `HAPPY` 的白描边）。耳语的挂件压在瓶体、纸团压在篓内同题。
4. **变换框参数化**：`minimumSize` / `outlineBorderColor` / `showEditingHandlers` / `enableClose` 全是属性。对应耳语的物理原语参数系统。
5. **封面彩色 / 内页灰阶**：颜色只用来表达容器，内容区保持材质。耳语可在「空间/物件」层面用色，物件内部保持纸与瓶的克制。
6. **模态用系统 `UISheetPresentationController` + detents**，不自造 presentation controller——与耳语 AGENTS 第 6 条一致，他们已验证可行。
7. **颜色资产带 Dark 变体**：深色模式零素材成本。`bg03` 浅色下 0.412 深灰、深色下 1.0 白；`bg10` 浅色下 0.129 近黑、深色下 0.31——「深灰纸↔白纸」的互转直接在资产层解决。

### 不能拿（5 条）

1. **轮次锁 + 戳一下 + 催办插屏广告。** 与耳语「等待对方主动发现」的核心直接冲突，且把亲密关系变成 KPI。**明确不做。**
2. **一句话状态条（心情 + 一句话贴在本子顶部）。** 形态很轻、体感很好，但它天然会长成每日打卡，与耳语 AGENTS「不加入连续签到、每日任务」冲突。**不做。**
3. **每条内容下的评论区 / 回复串。** 一旦有评论串，产品立刻变成聊天工具，主动打开的仪式感消失。**不做。**
4. **`sectionN_M` 式不可读的资产名。** 坚持两边都对：语义资产名 + 用名字/稳定 ID 持久化。（他们持久化用名字这一点是对的，不要学错。）
5. **自建服务端账号体系。** 不是「不做」而是「不具备」；它换来的是多语言推送、按用户下发文案、跨端一致，代价是离线不可用 + 隐私面扩大。耳语不要因为它能发多语言推送就动心。

### 一条可以正面借鉴的反例

**服务端 `app-version` 报 `1.7.0`，实际发布 `2.1.0`** —— 版本闸门数据没跟着发版更新。耳语的 `release.json` 是唯一真相源且随发布更新，这个对比说明：**没有服务端的项目，版本信息反而更不容易腐坏。**

---

## 11. 工程与踩坑清单

每一条都带证据强度，供对照。

| # | 问题 | 证据 | 影响 |
| --- | --- | --- | --- |
| 1 | 包内带了 `.swiftlint.yml`（1030 字节） | bundle 根目录可见 | 工程文件被打进发布包，说明打包脚本没做白名单 |
| 2 | 赞助页硬编码韩文 | `SponsorBottomSheet.swift` 里的韩文字面量 | 非韩语用户看到韩文 |
| 3 | 编辑窗提示硬编码韩文 | `ReadingViewController.swift` 邻近字符串 | 同上，且这是常见路径 |
| 4 | `en` 的 pinch 说明缺一条、编号 1/3 | `en.lproj/Localizable.strings` | 英用户拿不到完整规则 |
| 5 | 服务端报 1.7.0 vs 实际 2.1.0 | `GET /api/v1/app-version` | 版本闸门无人守；当前 `minimumVersion` 也低所以不会误拦 |
| 6 | `BASE_URL_DEV` / `BASE_URL_LOCAL` 进正式包，且有 real/dev/local 切换（`DevViewModel`） | Info.plist + 二进制 | 无密钥泄漏，但测试入口随包发布 |
| 7 | 通知扩展 `MinimumOSVersion = 16.0`，主 App `18.0` | NSE Info.plist | 子目标没同步 |
| 8 | 声明 `UIDesignRequiresCompatibility` | Info.plist | 在 Xcode 26 上主动退回 iOS 26 之前的视觉（不跟随 Liquid Glass），对老 UIKit 工程是务实选择 |
| 9 | 架构两代混装 | 老：UIKit + Storyboard + SnapKit + RxSwift（MVVM，`ViewModelType` / `ViewModelBindableType` 协议）；新：SwiftUI（`DailyNoteStripView` / `DailyNoteSheetView`，`Binding<PresentationMode>`、`ObjectWillChangePublisher`）+ 一个 `Routable` 协调器 | 没有统一也没有硬统一；`Routable` 的 case 已还原：`bookCover(bookID:page:)`、`writingContent(diaryID:bookID:page:size:)`、`invitationCode(String)`、`login(nickname:deleteProfileImage:userId:token:deviceID:)`、`saveDailyNote(bookID:mood:content:)`、`commentInfo(commentID:)`、`replyInfo(commentID:)` |
| 10 | 无本地库、无草稿 | `CoreData`/`SQLite`/`Realm`/`GRDB` = 0；`write_exit_description` 警告内容丢失 | 断网空列表；写一半退出即丢 |
| 11 | 可访问性几乎为零 | 主工程 `isAccessibilityElement` = 0；唯一的 `accessibilityLabel` 来自 Kakao SDK | 三只鸭子、贴纸把手、心情脸都没有 VoiceOver 等价物 |
| 12 | 开发工具随包发布 | `Pulse`（kean/Pulse 网络日志）、AdMob **Ad Inspector** | 增加包体与攻击面 |
| 13 | 追踪与广告归因齐全 | ATT + `SKAdNetworkItems` 长列表 + FirebaseAnalytics + Crashlytics + UMP consent | 与耳语 AGENTS「不加入广告追踪或第三方分析 SDK」正相反 |
| 14 | 贴纸无误操作兜底 | 把手/关闭按钮尺寸小，未见撤销入口 | 保存到相册后无法回退 |
| 15 | 写作页带评论输入条 | kr_04 / cn_04 / jp_04 截图 | 未保存的内容旁边有评论入口，产品语义混乱 |
| 16 | 服务端文案只有韩文 | 所有 `responseMessage` | 双重真相，改文案要两边改 |
| 17 | **没有任何举报/拉黑机制** | 12 个语言表里 `report`/`block`/`abuse`/`신고`/`차단` 命中数全为 0；二进制里没有 `reportUser`/`blockUser`/`abuseReport` | 这是一个 UGC 应用，而且从 2.1.0 开始 Apple 把它归到 `소셜 네트워킹`。有联系方式（문의 + Instagram），但没有内容举报路径。它能在 5 年里过审，靠的是「必须被邀请才能加入」这个封闭性 |
| 18 | 商店最小系统版本与包内不一致 | 商店 `minimumOsVersion = 16.0`，包内 `MinimumOSVersion = 18.0` | 两个可能：商店元数据滞后，或这个安装包被第三方工具处理过（同一个包里通知扩展又是 16.0）。无论哪种，都是「发版后无人校对商店元数据」 |
| 19 | 通知扩展无法审计 | `NotificationServiceExtension` 91,840 字节，全部是密文，`strings` 只掘到 29 条乱码 | 主二进制的 `__TEXT` 可读（`__cstring` 可打印率 0.896），扩展却是全加密——所以「通知到底做了什么」这次没能查清，不要写成已确认 |
| 20 | 调试入口随包发布 | `DevViewModel.Server(real/dev/local)`、`BASE_URL_DEV`/`BASE_URL_LOCAL`、`InterfaceStyleTap`（点顶部切换明暗主题）、`/api/v1/token/test`、Pulse 网络日志、AdMob Ad Inspector | 无密钥泄漏；但一个普通用户随手点到顶部就可能切主题。测试入口没有任何构建标记隔离 |
| 21 | 广告没有豁免选项 | `InAppProducts` 只有一个 case `duckz_2500`（打赏） | 他们选择「永久广告 + 可打赏」，而不是「付费去广告」。这是个商业选择：卖的是好感，不是解脱 |

值得承认的对照：**这个 App 在「不腐坏」这件事上做得比多数独立开发者好**（12 语言 key 100% 对齐、5 年持续发版、素材三分类清楚），但它腐坏的地方全部集中在**没人守的边角**：包内容物、子目标版本、版本闸门数据、商店元数据、硬编码文案、可访问性、举报机制。这也说明「规范数字」比「规范表述」更值得投。

---

## 12. 第二轮深挖：改掉的两条结论，与仍未知的三件事

第一版里有两条结论在第二轮被推翻或收窄，在这里明文记下，以免以后被引用错：

### 12.1 已推翻：「贴纸按索引持久化，会造成历史内容错位」

**错。** 封面贴纸持久化的是**名字字符串**（`Book.stickerImg: String?`），写页的贴纸目录是 `stickerNames: [[String]]`。名字持久化不会因插入贴纸而错位。而日记里的贴纸**根本不落地**（§4.4 的成图）。
可保留的只有一半：**资产名本身是流水号**（`section8_24`）→ 要靠 `RenditionName` 才知道它是 `number_blue_3.pdf`。

### 12.2 已推翻：「贴纸是参数化存储、可以重新编辑」

**错，而且这是整个拆解里最重要的修正。** 日记在服务端只有一个 `img` URL，阅读页只有一个 `diaryImageView`。贴纸在写入时就被烘进像素。具体证据见 §4.4。
直接后果：它那个做得很完整的贴纸编辑器（拖拽/缩放/旋转/删除把手）是**一次性**的，写完即不可逆。

### 12.3 仍未知：`template: Int` 的取值语义

类型确认是 `Int`，位置在 `Diary` 里 `img` 与 `createdDate` 之间。已排除「贴纸数据」（日记没有贴纸字段）和「排序字段」（已有 `createdDate`）。最可能是画布/卡片形态编号，但**没有任何直接证据**，不要用。

### 12.4 仍未知：约 99 个本地化 key 的引用方式

已排除 UTF-16、camelCase 生成枚举、前缀拼接、nib 内置、子二进制、部分加密六种解释（§8.1）。我不知道这些 key 是怎么被查到的，只能确认其中两组。要真搞清楚，只能在真机/模拟器上跑起来抓 `NSLocalizedString` 的调用（`DYLD_PRINT` 或 hook `bundle.localizedString`），不在本轮范围内。

### 12.5 仍未知：通知扩展做了什么

它的二进制是全加密的（91,840 字节，无可读字符串），面只有 Foundation / UserNotifications / libswiftCore。`aps-environment = production`，`UIBackgroundModes = [fetch, remote-notification]`，主 App 有 `postFCMToken`/`deleteFCMToken`/`fcmTest` 三个推送接口。**所以「他们有富推送扩展」是事实，「扩展里做了什么」不是。**

### 12.6 本轮新增的确认项（速查）

| 项 | 结论 |
| --- | --- |
| 点赞是可见的 | `toggleDiaryLike` + `fetchDiaryLikeUsers` + `LikeListViewController` + `LikeUserCell`：能看谁点了赞（不同于耳语无任何弱社交信号） |
| 点赞列表是一个独立页面 | `LikeListViewController` / `LikeUserCell` |
| 底部 sheet 用系统实现 | `collapsedDetents: [UISheetPresentationControllerDetent]` |
| 首页书卡显示最新评论预览 | 书卡的视图字段里有 `commentContainerView` / `commentNicknameLabel` / `commentLabel` → 首页是一个「有动静」的入口，不是一个日记本书架 |
| 首页书卡有红点 | `redDotImageView` |
| 成员能互相看到「正在写」 | `diary_manage_members_writing`「写日记中」 + `main_iswriting` / `diary_iswriting` |
| 强制更新闸门可以为空 | `minimumVersion: String?` |
| 分享走自定义 item source | `ShareActivityItemSource` 类 + `og_description` 文案 |
| 制作人页面 + 开发者 Instagram | `MakersViewController`“만든 사람들”、`instagram://user?username=duck_z_official` |
| 反馈邮件预填四项信息 | `my_inquiry_form` = 昵称/登录方式/版本/注册时间（比耳语的「点按复制邮箱」信息量更充分；但耳语不跳转邮件 App 这一点更克制） |
| 通知扩展最小系统 16.0 vs 主 App 18.0 | 见 §11 第 7 条 |

---

## 附录：证据索引

| 结论 | 证据 |
| --- | --- |
| 内部工程名 MemoryTrace | Firebase 项目 `memorytrace-42402`；URL scheme `memorytrace`；`.swiftlint.yml` 中 `MemoryTrace/Application/AppDelegate.swift` |
| 单人开发者、韩国市场 | iTunes lookup（author/sellerName SEUNGHWAN LEE，KR 963 评分，US 12 评分，CN 3 评分） |
| 内容模型字段与类型 | `__swift5_fieldmd` + `__swift5_reflstr` 解析（`template: Int`、`pinchable: Bool`、`pinchCnt: Int`、`whoseTurn: Int?`、`mood: String?`） |
| 34 个接口 | 二进制里连续排列的 `NetworkManager` 方法名字符串 |
| 后端是 Java/Spring + nginx | 线上 `Server: nginx` + Tomcat 404 页 + Spring Security 401 体 + `x-platform` 必填 |
| 轮次锁 | `Book.whoseTurn`；`diary_turndescription`；`main_iswriting` / `diary_iswriting` |
| 戳一下规则 | `diary_pinch_guide`（ko 三条）；`PinchRepository` / `PinchView` / `duck_my_turn_pinched` |
| 3 小时编辑窗 | `ReadingViewController` 邻接的硬编码 `일기 수정은 작성 후 3시간 이내에만 가능해요!` |
| 贴纸编辑器实现 | `StickerView` 字段表（`moveGesture` / `controlGesture` / `initialBounds` / `initialDistance` / `deltaAngle` / `_minimumSize` / `_outlineBorderColor` / `showEditingHandlers` / `enableClose`） |
| 卡片纸是颜色资产 | `assetutil --info`：`bg01`–`bg10`、`text01`–`text04` 的 `AssetType: Color` + `UIAppearanceDark` 变体 |
| 166 张贴纸的分类 | `RenditionName`（`alphabet_a`、`Music_01`、`Nature_01`、`number_red_0`、`round_1`、`roundring_1`、`line_1`） |
| 素材全部内置、无 ODR | `NSBundleResourceRequest` = 0；Assets.car 1,825,960 字节 / 406 rendition |
| 字体 26.5 MB | bundle 内 10 个 TTF 字节数求和 |
| 无本地库 | `CoreData` / `SQLite` / `Realm` / `GRDB` 在二进制中出现 0 次 |
| 几乎没有动画 | 上表动画 API 计数；`CAAnimation` / `CATransition` / `UIPercentDrivenInteractiveTransition` 均为 0 |
| 模态用系统 sheet | `UISheetPresentationController` + `detents` 出现；`UIPresentationController` = 0 |
| 保存到相册靠离屏渲染 | `UIGraphicsImageRendererContext` 闭包签名 + `PHPhotoLibrary.performChanges` / `creationRequestForAsset` |
| 广告位与打赏 | `ca-app-pub-5859381660545372/1734275722`（列表原生）、`.../8550965519`（戳一下插屏）、`enum InAppProducts { duckz_2500 }` |
| 可访问性缺失 | 主工程 `isAccessibilityElement` = 0；`accessibility_*` 字符串全部来自 `KakaoSDKFriendCore` |

| 卡片是「成图」 | `Diary` 全部字段（只有 `img: String`，无贴纸字段）；`ReadingViewController` 只有一个 `diaryImageView`；`WritingViewController` 才有 `_selectedStickerView`；`write_edit_picture_description` |
| 字段类型（Int/String?/Bool） | 自写 Mach-O 解析：`__swift5_fieldmd` 的 FieldRecord + 指向 `__swift5_reflstr` 的相对指针（§2.1 全表） |
| 封面贴纸用名字、封面色用索引 | `Book.stickerImg: String?` / `Book.bgColor: Int`；`stickerNames: [[String]]` |
| 删除是墓碑 | `isDelete: Int`；`DeletedDiaryCell`；`my_hidedeleted`；`comment_deletedcomment` |
| 无举报/拉黑 | 12 个语言表关键词匹配全为 0；无 `reportUser`/`blockUser`/`abuseReport` 符号 |
| 成图的收益：缩略图零成本 | `DiaryPolaroidLayout` / `DiaryMiniLayout` 共用同一个 `img` |
| 商店体积 50.2 MB / 分类 Lifestyle+Social | `itunes.apple.com/lookup?id=1572692131` 的 `fileSizeBytes` / `genres` |

复现命令：

```bash
A=/Applications/duck-z.app/Wrapper/duck-z.app

# 元数据
plutil -p "$A/Info.plist"
plutil -p /Applications/duck-z.app/Wrapper/iTunesMetadata.plist
codesign -d --entitlements :- "$A"

# 资产全清单
xcrun --sdk iphoneos assetutil --info "$A/Assets.car" > /tmp/assets.json

# 二进制字符串 / 类型系统 / 类清单
strings -a "$A/duck-z" > /tmp/duckz.strings.txt
grep -oE '_TtC6duck_z([0-9]+)([A-Za-z0-9_]+)' /tmp/duckz.strings.txt | sort -u
grep -oE '\$s6duck_z([0-9]+)([A-Za-z0-9_]+)' /tmp/duckz.strings.txt | sort -u

# Swift 字段名与类型（research/duckz/swift-fieldmd.py）
python3 research/duckz/swift-fieldmd.py "$A/duck-z" template stickerImg
python3 research/duckz/swift-fieldmd.py "$A/duck-z" | less   # 全部 6352 条

# 本地化 key 的可追踪性审计（把所有 key 与二进制对比）
python3 - <<'PY'
import plistlib
d = plistlib.load(open("/Applications/duck-z.app/Wrapper/duck-z.app/en.lproj/Localizable.strings", "rb"))
blob = open("/tmp/duckz.strings.txt", "rb").read()
dead = [k for k in sorted(d) if k.encode() not in blob]
print(f"live={len(d)-len(dead)} dead={len(dead)}")
for k in dead: print("  ", k)
PY

# 服务端
curl -H "x-platform: iOS" https://api-diary.kro.kr/api/v1/app-version
curl -i https://api-diary.kro.kr/

# 商店元数据与截图
curl -s "https://itunes.apple.com/lookup?id=1572692131&country=kr"
```

素材位置：`research/duckz/screens/`（20 张 App Store 截图，五地区）、`research/duckz/assets-inventory.txt`（406 个 rendition 全清单）。
