# Project Memory

## 耳语的机构是房间引擎，不是拆 Store 或搬 Telegram UI · 2026-09-04 10:55 CST · Codex

本条修正上方 Telegram L7–L9 条目中把「先拆 BetweenUsStore、导航意图化、FetchManager 式媒体门面」当成下一步的部分。那些原则仍可作边界，但不是当前产品缺的机构。

当前真正的结构问题在动效与物件所有权：首页、详情和星星瓶页各自 new 物理与揭示控制器；`NativeAnimationDriver.spring` 是按时长 ease 的假弹簧；星星揭示走空 `init()` 落到这套驱动；`HomeView.playReveal` 先 `openNext` 再赌动画能播。结果是多套时钟抢同一只瓶子，内容会在过场失败后被消耗。

要对齐的机构是房间引擎，不是模块墙：

- 一台钟：全项目只留真弹簧驱动（现有 Wave），`startFrames` / `animate` / `spring` 吃同一帧；SpriteKit 纸团可暂时保留，但必须接同一套锚点与导演，不再私自当页面时钟。
- 一个世界：`StarJarPhysicsSystem`、`TrashBinPhysicsSystem`、盖子与飞行 token 由房间宿主持有；页面只订阅，不创建。首页和详情看同一瓶星星、同一篓纸团。
- 一个导演：`open` / `store` / `fail` 先锁实体、校验锚点，成功再 `openNext`；播不出来就回弹，不改 `AppData`。
- SwiftUI 只渲染快照。混合渲染不变：位图管身份，代码管物理、开合、揭示和遮挡。

明确先做三件事：删假弹簧并把空 `init()` 打到真驱动；把物理从 Home / RitualScene / StarJarView 拎到共享房间；打开改为先校验再提交。不要先拆 `BetweenUsStore`，不要全局导航路由器，不要 FetchManager，不要为每个场景再做一套状态机。

## Telegram-iOS L7–L9 只吸收工程原则，不搬三套 UI 运行时 · 2026-09-04 10:44 CST · Codex

对 Telegram-iOS 的 Display / AsyncDisplayKit / ComponentFlow、TelegramUI、FetchManager 与扩展做了稀疏只读调研。耳语吸收的是分层原则，不是聊天业务，也不是 Telegram 的三套 UI 运行时。Telegram 同时保有 Display、Texture 和 ComponentFlow，是十年增量客户端的历史结果：窗口/导航/键盘必须有一个统一宿主，列表与图片解码需要异步节点，新屏又需要声明式组件。耳语没有这个历史包袱，继续以 SwiftUI 为产品层，SpriteKit / Core Animation 只服务物件物理与揭示；不要为了「更像大客户端」再引入第二套 UI 框架。

可执行约束：

- 依赖只能单向。`Views` / `Components` 订阅快照和发意图，不持有 `CKDatabase`、`CKSyncEngine`、`CKRecord` 或 StoreKit 交易句柄。`SecretItem` 可以知道自己如何映射到 CloudKit 记录，但界面不得直接拼 record。当前最大偏离是 `BetweenUsStore` 同时当账号世界、同步引擎、购买、媒体导入和 UI 快照源；后续拆分优先把「空间世界」和「界面快照」分开，而不是先拆更多 View。
- 列表和物件数量的真相源是本地 `AppData`。CloudKit / `CKSyncEngine` 只是填充器和冲突合并器。首页星星瓶、胶囊盒、纸团篓、抽屉都读本地 items；同步失败不得清空或改写用户已经放入的内容。`isLocalPreview` 是另一个世界，不是正式空间上的开关字段。
- 内容身份是「本地 UUID → 发送中/脏记录 → 服务器记录名」。放入时本机先落盘并立即可见，再进入 `dirtyRecordNames`；不要等 CloudKit 成功才给用户完成感。附件必须随这条本地身份走，不能另起一套只存在于 View 里的临时 URL。
- 账号/空间切换是切世界，不是改一个 token。离开预览、删除空间、退出空间、iCloud 账号变更都要替换整份 `AppData`、媒体目录和同步引擎，不得在旧世界上打补丁。一方创建空间、另一方加入后，两边看到的是同一份共享世界的本地投影。
- 主题与动效是语义 token，不是页面私有色值。`AppTheme` / `AppMotion` / `DriverSpring` 已经是 presentation 层；气泡、导航、通知条、购买页和三个物件揭示应从同一套 token 取值。不要在单个 sheet 里另起魔法数字或第二套背景语义。
- 媒体不是 `URL + AsyncImage`。下载/导入要有优先级、引用和可见性：用户正在看的附件高于后台同步，打开中的内容高于抽屉缩略图，后台静默推送只补元数据，不抢前台预算。`MediaFileStore` 继续做磁盘身份和缓存键，但 View 不得自己 `UIImage(contentsOfFile:)` 或另建一套 `MediaFileStore()`；`MyDepositsView` 当前自行实例化 store 属于应收回的偏离。
- 导航是意图，不是到处 push 具体页面类型。打开抽屉、设置、创作、购买、媒体全屏、系统共享，应是少数稳定意图；揭示层从对应物件长出并回到原物件，底部 sheet 表示任务覆盖，顶部通知条表示短暂状态。系统 `sheet` / `fullScreenCover` 只留给创作、购买、媒体查看和 CloudKit 共享。不要在首页、详情、揭示流程里各自再 push 一套具体类名。
- 连接与同步是全局可订阅状态机。`CloudSyncStatus` 和 `AppPhase` 已经具备雏形；页面不得自己 ping iCloud 或重复 `accountStatus()`。静默推送只唤醒同步引擎，不把 Notification Service / Share 扩展开成整棵 UI。耳语近期不需要 Notification Content 扩展或 VoIP；如果以后做推送解密，扩展只链数据与媒体存储，不链 `Views` / `Components`。
- 产品层状态机按场景拆，而不是做成聊天历史。首页订阅空间阶段、同步状态、三个物件计数和揭示锚点；创作订阅草稿与额度；抽屉订阅本地 items 的过滤投影；媒体查看器订阅附件资源状态。不要把这些状态继续堆进 `HomeView` 的 `@State` 或 `BetweenUsStore` 的全部方法里。

明确不搬：AsyncDisplayKit 节点树、ComponentFlow 自研声明式运行时、`ChatHistoryListNode` 的 π 旋转列表、`FetchManager` 的完整优先级实现、tgcalls / RTMP、RLottie 运行时。这些解决的是 Telegram 的规模问题。耳语要对齐的是单向依赖、本地真相源、意图导航、语义主题和带引用的媒体预算。

## 静态价格按界面语言展示 · 2026-08-30 04:38 CST · Codex

公开页面、商店描述等静态价格文案按内容语言决定：简体中文只显示 `¥18`，英文、日文和韩文只显示 `US$2.99`，不在同一语言里并列两种价格。此约定只控制文案展示，不覆盖 App Store 的实际地区定价；应用内购买按钮必须继续使用 StoreKit 的 `Product.displayPrice`，最终扣款以 Apple 系统购买界面显示的本地结算价格为准。

## 正式英文名为 Between us · 2026-08-30 04:36 CST · Codex

用户明确确认：产品中文名为「耳语」，正式英文名为「Between us」。这取代此前把 `Whisper` 作为英文显示名、把 `Between us` 作为副标题的约定。应用显示名、App Store 元数据、官网、政策与支持材料均不得再把 `Whisper` 用作产品名；现有 `WhisperNoticeBanner` 等内部 Swift 符号不属于用户可见品牌，可在不引发无关重构的前提下保留。

## 永久买断闭环已接入，发布仍依赖后台配置 · 2026-08-30 04:27 CST · Codex

本条取代下方“商业模式确定为双人共享永久买断”条目中“当前构建尚未接入”的状态说明。应用现已接入 StoreKit 2 非消耗型购买、恢复购买和交易监听，免费空间在放入第 11 条时拦截，删除单条或清空可释放额度；并发同步造成暂时超过 10 条时保留双方内容，只阻止后续新增。

付款人的已验证权益会写入当前 `BetweenUsRelationship`，由双方共享；被邀请的一方不需要购买或恢复“会员”。关系记录使用 `lifetimeProductID`、`lifetimeUnlockedAt`、付款人的 CloudKit 记录标识和已验证交易标识来同步与撤销权益，不保存银行卡或其他付款资料。付款人退款或购买被撤销时，由付款人设备清除对应的空间权益，另一方通过 CloudKit 同步回免费版，已有内容不得自动删除。发布前必须在 App Store Connect 创建非消耗型产品 `cain.com.between-us.lifetime`，并把新增 CloudKit 字段部署到 Production Schema；本地 `Configuration.storekit` 只用于 Xcode 调试。

面向用户与公开页面时不得把星星瓶、胶囊盒和纸团篓统称为“容器”。需要概括时使用“空间”，描述物件时直接说“星星瓶、胶囊盒、纸团篓”或“星星、胶囊、纸团”；“容器”只保留在 CloudKit、代码类型和绘制系统等内部技术语境。

## 用户概念统一称为「空间」 · 2026-08-30 03:45 · Codex

面向用户的产品文案统一使用「空间」，不再使用「共同空间」。英文、日文和韩文对应使用 `space`、`スペース`、`공간`，不再额外强调 shared / 共有 / 공유。CloudKit、CKShare 的所有者与参与者差异仍属于内部实现，不应改变这一用户概念。

## 商业模式确定为双人共享永久买断 · 2026-08-30 03:28 · Codex

免费版按双方当前留下的星星、胶囊和纸团总数计量，最多 10 件；删除单件内容或清空全部内容会立即释放免费额度。

额度执行以“放入第 11 条”为拦截点：当前总数小于 10 时可以继续放入，达到 10 条后必须买断或先删除内容。若双方在同步前同时从 9 条各放入一条，允许总数暂时超过上限；两条内容都必须保留，不回滚或丢弃任何一方的内容。此后停止新增，直到买断或删除到 10 条以下。

付费只提供一次性永久买断，不提供月付、年付或其他订阅。中国区价格为 ¥18，美国区价格为 US$2.99，其他地区使用 App Store 对等价格。一人购买后，当前双人空间由双方共享无限内容权益。

当前构建尚未接入 StoreKit、空间权益同步和 10 条额度拦截。在这些能力实际完成前，官网和商店文案不得将买断描述为已经上线。

## 核心物件改为混合渲染 · 2026-09-04 · Codex

本条取代下方“核心物件使用共享参数化绘制系统”中“外部美术只是可替换增强层”的旧结论。当前正式实现是混合渲染：

- 星星瓶：`StarJarBottle` + `StarCharm_*` 位图，配合 `StarJarPhysicsSystem`。
- 纸团篓：`PaperBinEmpty` / `PaperBinFilled` + `TrashEmotion_*` 位图，配合 `TrashBinPhysicsSystem`。
- 胶囊盒：仍以共享参数化几何与材质绘制。

位图负责物件身份与材质；代码负责物理、开合、揭示、遮挡和状态驱动。源文件在 `DesignAssets/`，运行时资产在 `BetweenUs/Assets.xcassets`。不得再把纯参数化示意图写成当前事实。

## 核心物件使用共享参数化绘制系统 · 2026-08-29 · gpt-5

历史记录：早期实现以共享几何内核、参数预设、材质层和运动状态为主，外部美术只作为可替换增强层。该阶段结论已被上方“混合渲染”条目取代。

## 交互与 UX 文案以连续、直接、可恢复为准 · 2026-08-28 18:04 · gpt-5.6-sol

操作采用直接操控和即时反馈，出错可恢复；流程尽量无弹窗、无等待、无跳跃。界面使用清晰短文案，相关信息成组，强调当前状态和下一步。动效只服务于按压、拖动阈值、打开、保存和错误等状态变化。

本机持久化是“放入/打开”的完成点，CloudKit 在后台同步，不阻塞当前操作；失败时保留草稿并支持立即重试。空状态需要说明当前状态及内容出现路径，核心价值入口保持可见。
