# MOODA 深挖：动画 / 性能 / 产品设计 / 踩坑 / 美术资产

记录日期：2026-09-18
对象：`/Applications/MOODA.app`（`io.analoglab.mooda` 2.3.1 build 63，Mac App Store 的 Catalyst 版，276 MB）
前置：`MOODA_TEARDOWN.md`（产品结构、情绪球、房间、字体、后端的总览）。本文只写那篇没展开的五条线。
素材：`research/mooda/`（同前一篇），新增的实测统计都在本文表格里。

**证据边界**：这个 App 在本机从未启动过（容器为空），所以**没有任何运行时性能数据**——没有启动耗时、没有内存峰值、没有掉帧记录。下面所有"性能"结论都是**结构成本**（包体、资源数量与规格、库的重复、启动时无条件加载的东西）和**代码里可验证的配置**（预取、降采样、缓存上限），不是实测。凡是推断我都标了。

---

## 0. 三条结论

1. **动画**：MOODA 的动效预算几乎全花在「状态反馈」上——系统弹簧 + 触觉 + 9 个固定 Lottie 片段 + 骨架屏。**全 App 没有一处物理模拟**（`UIDynamicItem` 只有 4 处类型编码，没有 `UIDynamicAnimator` 的实际使用），没有自绘转场，没有跟手手势动画（唯一跟手的是 SideMenu 抽屉，来自第三方库）。它的"活"来自**片段动画和骨头**，不是模拟真实物体。→ 耳语的物理不是行业默认做法，它是我们的差异化，代价必须由我们自己扛（时钟唯一性、可打断、Reduce Motion 降级）。
2. **性能**：276 MB 里 **232 MB 是字体**，美术资源只有 8.0 MB（2.9%），二进制 46 MB。它的性能策略是**把成本推到服务端和预生成物**：服务端按 `imageType` 出多规格图、包内预生成 47pt 预览瓦片、列表预取、骨架屏、两个图片库都配好降采样与缓存上限。→ 可学的是"资产与出图策略"，不可学的是"字体全内置 + 双图片库"。
3. **产品设计**：所有商业化压力都压在一个动作上——**保存日记**（订阅，或看 30 秒广告），所有情绪回报都压在一个时刻上——**月末的情绪球**。付费点设计得很密（四道免费限制），但情绪价值的兑现只有一处。→ 前者我们不要（耳语的免费门槛在"第 11 条"、无广告），后者我们要（耳语现在完全没有"回顾层"）。

---

## 1. 动画

### 1.1 实际用了什么（全部来自二进制符号与常量）

| 机制 | 证据 | 用量 |
| --- | --- | --- |
| 系统弹簧 | `animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:`、`initialSpringVelocity` 属性 | 主流动画手段 |
| Lottie | `LottieAnimationView`、`Lottie/LottieAnimationView.swift`、9 个 json | 9 个固定片段 |
| 触觉 | `Haptica` pod（`Hapticable` / `HapticOperation`）+ 自研 `MOODA.HapticManager` + `MOODA.HapticButton`（28 处接线） | 按钮级系统化接线 |
| 抽屉跟手 | `SideMenu` pod：`dampingRatio` / `initialSpringVelocity` / `revealDuration` / `hideDuration` / `enablePanGesture` / `enableRubberEffectWhenPanning` / `panGestureSensitivity` | 侧边抽屉 |
| 分页 | `Pageboy` pod（`PageboyViewControllerDataSource/Delegate`） | 首页「我 / 与好友一起」 |
| 加载指示器 | `NVActivityIndicatorView` pod（20+ 种动画）、自研 `LoadingView`（内含 `animationView` + `moodaLoadingBasic` / `moodaLoadingEmoji`）、`CircularProgressView.nib`、`ActivityIndicatorCell.nib` | 全局 |
| 关键帧/转场 | `CAKeyframeAnimation` 2 处、`CATransition` 2 处 | 可忽略 |
| **没有** | `UIViewPropertyAnimator` 0、`CASpringAnimation` 0、`UIPercentDrivenInteractiveTransition` 0、自己实现的 `UIViewControllerAnimatedTransitioning` 0（只有 SideMenu 自带的 `BasicTransitionAnimator`）、`UIDynamicAnimator` 0；SpriteKit/SceneKit 也没有业务使用（`SKView` / `SKAction` / `SKSpriteNode` / `SKPhysicsBody` / `SCNNode` 全为 0，`SKScene` 的几处引用来自 MetalPetal 的 `MTISKSceneRenderer`） | — |

### 1.2 九个 Lottie 片段（包内全部动效，合计 152 KB）

| 文件 | 画布 | 帧率 | 时长 | 图层 | 用途 |
| --- | --- | --- | --- | --- | --- |
| `moodaLogin.json` | 375×500 | 30 | 90 帧（3 s） | 13 | 登录页主视觉 |
| `moodaLoadingEmoji.json` | 240×240 | 30 | 30 帧（1 s） | 4 | 带表情的加载 |
| `moodaLoadingBasic.json` | 120×120 | 30 | 60 帧（2 s） | 2 | 基础加载 |
| `feedSkeleton.json` | 343×927 | 30 | 50 帧 | **1** | 整个 feed 的骨架（一张图走完） |
| `motionAddPhoto.json` | 92×92 | 30 | 50 帧 | 2 | 「加照片」的引导动效 |
| `emojiMixedFeelings.json` | 120×120 | 60 | 1080 帧（18 s） | 2 | 「复杂微妙」表情循环，两层相位错开（-581 帧） |
| `emojiThemeHolidayMixedFeelings.json` | 120×120 | 60 | 1080 帧 | **3** | 同上 + 第 3 层圣诞装饰 |
| `themeXmasLightDeco.json` | 1401×20 | — | 135 帧 | 4 | 圣诞灯串（横条装饰） |
| `themeXmasMainBotFootPrint.json` | 196×96 | — | 200 帧 | 22 | 圣诞小机器人脚印 |

两条可直接借用的做法：

1. **节日版本 = 在 base 图层上叠一层**。`emojiThemeHolidayMixedFeelings` 就是把 `emojiMixedFeelings` 的前两层照抄，再加第 3 层 `emojiThemeXmasComplicated Outlines`。同一招也在位图上用（`windowA_01_day` → `windowA_01_day_xmas`、`emojiHappy` → `emojiThemeHolidayHappy`）。**节日皮肤不该重画整套挂件，应该是基础件 + 覆盖层。**
2. **骨架屏是一个片段，不是一堆占位块**。`feedSkeleton.json` 只有 1 个图层，尺寸就是列表页尺寸（343×927），50 帧内做微光扫过。比用 SwiftUI 拼 6 个灰色圆角块更省事、也更稳。

### 1.3 触觉是"按钮类"层面的系统能力，不是散落的调用

`MOODA.HapticButton`（`_TtC5MOODA12HapticButton`）是自定义控件，界面上凡是这件事有意义的地方都用它：`photoFilterButton`、`drawButton`、`textButton`、`trashButton`、`editButton`、`commentButton`、`timeButton`、`logoutButton`、`changeButton`…（28 处接线）。加上 `Haptica` 库和 `HapticManager`，等于**触觉被抽象成控件属性**，而不是每个动作里写一行 `UIImpactFeedbackGenerator`。

> 耳语动作：我们已经有 `RitualHaptics`，但没有"控件级"的默认触觉。若要在编辑/抽屉类界面加触觉，先把它做成控件包装（一个 `HapticButton` 等价物），别在每个 action 里散落调用。

### 1.4 静态状态下"看起来会动"的地方

| 位置 | 资产 | 说明 |
| --- | --- | --- |
| 情绪球统计 | `roomMoodBallBarUp` / `Bardown` / `Capsule` + `MoodBallDynamicCircleView` / `MoodBallDynamicBottomView` | 用上下柱 + 胶囊表示数量，动的是数值不是物理 |
| 房间引导 | `RoomBoardTableGuideView`、`RoomEditorTooltip`、`drag_along = 沿线，向左拖动到右边`、多个 `ic16*Tooltip` 箭头 | 用箭头 + 引导线教摆放 |
| 贴纸/按钮提示 | `PackageTooltipView` / `TextTooltipView` | 气泡提示 |
| 空/错/权限态 | `CommonEmptyView(+Cell)`、`ErrorView`、`ic36null`、`ic36bg` | 静态插图 + 文案 |

**结论**：他们把"让用户看懂发生了什么"交给**静态插图 + 一次性片段动画**，把"顺手"交给**触觉 + 系统弹簧**。这套组合在性能上几乎零风险，代价是产品里没有"物性"——没有任何东西有重量、惯性、碰撞。

---

## 2. 性能

### 2.1 包体构成（实测，`du` / `ls -l`）

| 部分 | 大小 | 说明 |
| --- | --- | --- |
| 主二进制 | **46.4 MB**（48,619,248 B） | x86_64 + arm64 双架构，含静态链接的 RxSwift/SnapKit/Alamofire/Lottie/MetalPetal 等 |
| `Assets.car` | **8.0 MB**（占盘 7.3 MB） | 1326 个 rendition / 945 个名字 |
| 字体 | **116 MB**（50 个文件） | 占主 App 资源的 92% |
| 小组件 appex | **127 MB** | 其中字体 116 MB（整套复制） |
| Lottie | 152 KB | 9 个 json |
| 本地化 | 8 个 `Localizable.strings`（每个 37–58 KB）+ 8 个 `InfoPlist.strings` | 523 key × 8 |
| 界面资源 | 23 个 `*.storyboardc` + **68 个 `.nib`** | 组件级 storyboard/nib 大量使用 |
| StoreKit / Firebase 配置 | `MOODA_Dev_StoreKit.storekit`、`GoogleService-Info.plist`、`GoogleService-Info-Dev.plist` | 见踩坑 |

合起来：**276 MB 里 232 MB 是字体（84%），美术资源 8 MB（2.9%）**。这不是"美术资源管理"问题，是"把字体当资源塞进包"的问题。

### 2.2 启动路径上无条件发生的事

1. `UIMainStoryboardFile = Splash` → `SplashViewController` 起手，随后跑 `moodaLogin` 的 Lottie（13 层、3 秒循环）。
2. `UIAppFonts` **51 条**静态注册：系统在启动时无条件加载/登记这 51 个字体面（116 MB 文件）。文件是 mmap，但**面数与字体表解析成本随条数线性增长**——这是他们启动成本里最确定的一项。
3. Firebase（Analytics + Crashlytics + Messaging + Installations）+ Facebook SDK + Google Sign-In + AdMob 初始化。
4. `UIBackgroundModes = fetch, remote-notification`（后台拉取 + 远端推送）。

> 对照我们自己的 `DesignAssets/fonts/README.md`：内置一款兜底就要付出"启动时无条件加载 +24 MB"的代价，我们因此把其余 14 款放 CDN。MOODA 的 51 条说明这条路他们没走——**我们要继续守住"内置一款"**。

### 2.3 图片：从取图到落盘整条链

| 环节 | 事实 | 证据 |
| --- | --- | --- |
| 服务端出图 | 图片按类型分规格下发，客户端带 `imageType` 取 | `/v1/images/item?imageType=`、`/v1/images?imageType=`、模型字段 `imageType` / `thumbnailImage` / `collageImage` / `contentImages` |
| 系统相册取出 | 按目标尺寸取，不取原图 | `requestImageForAsset:targetSize:contentMode:options:resultHandler:` |
| 解码降采样 | 用库的降采样能力配置，**没有手写缩略图** | Kingfisher 8 的 `imageThumbnailPixelSize` / `imageScaleDownLimitBytes` / `DownsamplingImageProcessor` / `cacheOriginalImage`；`CGImageSourceCreateThumbnailAtIndex` 出现 0 次 |
| 缓存上限 | 两套都显式配置 | `SDImageCacheConfig`（16 处）、`maxMemoryCost`、`maxDiskSize`、`diskCacheExpiration` |
| 上传 | JPEG 编码 + 记录压缩后大小 | `jpegData`、`compressionQuality`、`ImageUploadParam.compressedSize` |
| 双图片库并存 | **Kingfisher 与 SDWebImage 同时存在**（Kingfisher 278 处引用 / SDWebImage 180 处） | 包内两个 bundle 都在；两个内存/磁盘缓存各一套 |

### 2.4 列表与滚动

- `UICollectionViewDataSourcePrefetching` + `prefetchItemsAt`：列表预取有做（6 处引用）。
- `NSCollectionLayoutSection` 只有 2 处引用 → **绝大多数列表不是 Compositional Layout**，是传统 flow layout + 各自的 `XxxLayoutProvider`（`FeedLayoutProvider`、`SingleDiaryLayoutProvider`、`RoomBoardContentLayoutProvider`、`FeedReactionLayoutProvider`、`UserSearchViewLayoutProvider`、`PurchaseHistoryLayoutProvider`）。
- 骨架屏兜底首屏（`feedSkeleton`）。
- **图片管线省掉的猜测**：贴纸 600×600 PNG 不在列表里直接铺——商店里铺的是预生成的 47pt 预览瓦片（`pre_R_C`）、72pt 封面（`thumb`）、156pt 标签（`tag`），只有真正贴上去才解码 600×600。

### 2.5 性能上明确可学的三条 / 不要学的两条

**学**：
1. **规格分层**：同一份内容有「列表瓦片 / 卡片 / 全屏」三级资产，永远不在列表里解码大图（我们的贴纸/字体选择器将来也要这样）。
2. **降采样靠库配置，不手写**（Kingfisher 的 thumbnail 选项 + processor）。
3. **骨架屏用一段 Lottie**，比手拼占位块稳。

**不学**：
1. **两个图片库并存**：两套缓存、两套解码路径 = 双份内存与磁盘，且无法统一淘汰策略。
2. **字体进包**：见 §4。

---

## 3. 产品设计

### 3.1 首启动线：第一件事是"装饰一个属于你的东西"

从 `Classes/Feature/Onboarding/` 的目录结构与文案反推（**顺序为推断，目录本身是实测**）：

```
Splash → 登录（Apple / Google / Facebook / LINE）
      → UserName（账号名，check-username 可用性）
      → Birthday（birthday_gift = 你的生日是什么时候？\n我会为你准备一份小礼物。）
      → CoverName（diary_name = 日记名称）
      → CoverEdit（diary_cover = %@的\n日记封面，请装饰它。）
          ├─ Draw（画笔涂封面）
          ├─ Sticker（StickerPackSelect 选一个免费包 → 顺带进 StickerShopView）
          └─ Gallery（从相册挑一张）
      → sign_up_complete → 首页日历
```

产品判断：**注册后不让用户面对空列表，而是先让 ta 给"自己的日记本"做一个封面**，并且把三种装饰能力（画/贴/选照片）在入职流程里各教一遍；选免费贴纸包时顺手展示商店（`FreeStickerPackageType` + `StickerShopView`），把变现入口在第一天就摆出来而不打断。对一个"每天写一篇"的产品，这个首启是合格的：先建立"这是我的本子"，再谈内容。

### 3.2 日常节奏与免费阶梯

| 环节 | 设计 | 关键文案 |
| --- | --- | --- |
| 每天一篇 | 先问情绪再写内容 | `how_was_your_day = 오늘 하루는 어땠니?`、补昨天的 `how_was_past_day` |
| 保存 | **免费用户要"订阅"或"看短广告"**，选择 7 天内记住 | `save_option_first = 成为高级用户`、`save_option_second = 看短广告并保存`、`save_option_description = 选择将保持 7 天` |
| 房间额度 | 备忘录/照片有免费额度，高级版无限 | `free_memo_limit`、`free_photo_limit` |
| 搜索 | 免费只搜最近 1 个月 | `recent_one_month`、`buy_premium_search` |
| 回顾 | 情绪球免费只看 6 个月 | `mood_ball_view_alert`、`shop_unlimited_contents` |
| 商店 | 高级版让所有付费道具免费 | `shop_paid_items = 모든 유료 아이템 무료 이용` |
| 广告 | 高级版去广告 | `shop_remove_ads` |

这是**四道以上的免费限制**（保存、备忘、照片、搜索、回顾期限、广告），全部指向同一件事：订阅。判断：转化压力集中，且**压在"写入"这个核心动作上**——用户写完一篇日记，点保存，被要求订阅或看广告。这条我们不要；耳语的门槛是"放入第 11 条"，而且不做广告。

### 3.3 隐私粒度（这一块设计得比我们细）

| 能力 | 文案/证据 |
| --- | --- |
| 每篇的可见范围 | `public_visibility = 全部公开` / `private_visibility = 非公开`、`use_public`（可关掉这个选项） |
| **只公开情绪，不公开内容** | `hide_diary = 隐藏日记内容`、`hide_diary_guide = 只公开情感和标题` |
| 批量转私密（不可逆，有专门警告） | `change_private_alert_description = 转为非公开的日记只有您自己可以查看，与日记相关的评论和点赞将不再显示…此操作是不可逆转的` |
| 评论/点赞范围 | `allow_comment` / `allow_like` + 「谁可以评论你的公开帖子」 |
| 房间访问权限 | `allow_room = 允许访问您的房间`、`room_view_all` / `room_view_friend` |
| 资料可见性 | `allow_friend_request`、`friends_tab_empty` |
| 屏蔽/举报/受限 | `block_user_description`（屏蔽不通知对方）、`report_diary/comment`、`restricted_user_temp/permanent` |
| 社区准则 | `community_guide_description`（"大家的一天"的社区空间说明） |

**`hide_diary` 值得我们认真看一秒**：它把"情绪可分享、内容不可分享"当成一个显式选项——保护的粒度是**内容**而不是**存在**。耳语的空间是双人私有的，不需要公开档，但同样的思路可以落在别的边界上（例如某条内容对方能看到"有东西在这里"但不能打开？）。**这只是个可以想的方向，不要现在改产品。**

### 3.4 通知与提醒

| 机制 | 文案 |
| --- | --- |
| 写作提醒（可自定义时间与内容，30 字上限） | `notification_writing = 写日记提醒`、`notification_writing_msg`、`max_message_length = 通知消息最多只能输入30个字符`、`AlarmTitleViewController` |
| 好友写了日记 | `notification_friend_diary = %@ 写了一篇日记。` |
| 月末情绪球 | `moodball_notification = 이번 달 무드볼을 확인해 보세요!` |
| 通知列表窗口 | `recent_six_weeks_notification`（只显示最近 6 周） |
| 权限缺失的恢复路径 | `no_access_notification_description` + `no_access_notification_button = 进入设置` |
| 按类型开关 | `notification_settings_management`、`push_notification_settings` |

### 3.5 账号、设备、订阅的"自助区"

`DeviceConnectViewController`（设备列表 / `current_device` / `logout_device`）、`PurchaseHistoryViewController`（购买历史 + `no_items_purchased`）、`MembershipViewController`（`menu_membership_status`、`next_billing_date`、`menu_membership_settings = 管理订阅`）、`WithdrawViewController`（注销 + `24hours_join_impossible` 24 小时冷却）、`LanguageSheet`（语言切换）、`import_diary`（从旧版 MOODA 导数据，`LSApplicationQueriesSchemes` 里还留着旧 bundle `com.olivestonelab.mooddiary`）。

### 3.6 设置清单（当检查表用）

首页设置：`background`（背景）、日历视图、`font_style` / `font_size`、`highlighter`（荧光笔开关）、`allow_comment`、`first_day_of_week`（每周第一天）、`show_diary_title`、`diary_cover`、`calendar-color`（日历配色）。
贴纸设置：`sticker_settings_description = 长按按钮可以更改贴纸的顺序`（长按排序）。
账号：`edit_profile` / `profile_share`（二维码 + 链接）/ `blocked_accounts` / `device` / `logout`。
其他：`notification_settings`、`passcode_settings`（密码锁 + 面容 ID）、`privacy_settings`、`contact`、`rate_app`、`app_version`、`menu_membership`。

**我们从这里能拿的**：`first_day_of_week`、日历配色、长按排序这两类"高密度单行设置"的组织方式；以及"通知权限缺失时给出可点的恢复入口"。

### 3.7 最该拿的一条：回顾层

`mood_ball_condition_1 = 10篇以上的日记` + `mood_ball_condition_2 = 每月的最后一天` + `moodball_notification` + 统计页（每情绪胶囊数量 + `EmotionFactsView` + `review_tilte = 本月总评`，最多 50 字）+ `count_days_title = 기록일수`（记录天数）。

这是一套**不靠签到/任务/金币的长期动机**：内容攒够才有回顾，回顾只在月末出现，回顾对象是一个可以看的实物（扭蛋机里的一颗颗球），并且允许自己写下本月总评。耳语现在三个物件只有"放入/打开"，没有任何"过一段时间一起看"的出口——**这是产品层最实的缺口，也是本文唯一推荐优先补的东西**。

---

## 4. 踩坑

### 4.1 包与发布

| 坑 | 证据 | 我们的对照 |
| --- | --- | --- |
| 字体占包体 84%（116 MB），小组件再复制一份（+116 MB） | `du`；appex 内 50 个同名字体文件 | 我们内置 1 款 + CDN，保持 |
| `UIAppFonts` 里有**不存在的字体** | 第 51 条 `03_drfont_daraehand_Basic.ttf` 不在包内 | 我们的 CDN 字体没有这种清单，但**内置款要保证清单与文件一致** |
| 开发环境配置进正式包 | `GoogleService-Info-Dev.plist`（项目 `mooda-f2cb9`、bundle id `.dev`、含 Realtime Database URL）与生产 plist 同目录 | 我们只有生产 CloudKit 容器，仍应在发布检查里加一条"包内不得出现 dev/staging 配置" |
| ATS 全开 | `NSAllowsArbitraryLoads = true` | 我们不要开 |
| Catalyst 版声明 iPad family 上 Mac | `UIDeviceFamily = [2]`、`UIRequiredDeviceCapabilities = armv7`（2013 年字段仍在） | 我们只做 iPhone，别留历史字段 |
| 42 个 `SKAdNetworkIdentifier` + ATT + Facebook 归因域 | `Info.plist`、`NSPrivacyTrackingDomains = ep1.facebook.com` | AGENTS 明确禁止，继续不引 |

### 4.2 资产与命名

| 坑 | 证据 |
| --- | --- |
| **拼写错误被写进资产名** | `emojiNeutural` / `roomMoodBallEmojiNeutural` / `mooda_001_stic_06_neutural`（`neutural`，全库一致）、`contolPagingActive` / `contolPagingDefault`（`contol`）、类名 `DivierMixView` |
| 占位图与营销图占掉美术预算的大头 | `imgPhotoDummy` 900×900 @1x = **406 KB**（占 Assets.car 的 5%）；`polaroidPack_1000_storeThumb` 1125×1125 @3x = **729 KB**（占 9%）；本地化商店横幅 7 张 ≈ 790 KB（每语言一张位图） |
| 变体图吃掉美术预算 | `windowA/B/C` 120 张共约 2.4 MB，占 `Assets.car`（8.0 MB）的 30%——为"房间时段/节日"付的代价 |
| 同一 PDF 存三份 rendition | 房间/扭蛋机的 PDF 同时存在 `Image@1x` + `Image@2x` + `Vector` 三条 rendition |
| 无暗色模式 | 1326 个 rendition 里 **0 个任何 dark 外观**；全库只有 `universal` idiom |

> 命名是给未来的人看的接口。`neutural` 这种拼写一旦被写进资产名，就会跟着资产走一辈子（他们的 enum case 也叫 `neutural`）。**我们的挂件命名已经带 `{Style}_{Emotion}`，任何拼写错误都会变成"已保存的星星找不到挂件"级别的问题——`MOODA` 这个例子值得写进我们的资产规范里当反面教材。**

### 4.3 本地化

| 坑 | 证据 |
| --- | --- |
| key 对齐 ≠ 翻译完成 | 7 语言各 523 key、集合完全一致（missing 0 / extra 0），但 zh-Hans 里留着 `count_days_title = NOD:`、`count_days_content = %@ days`、`count_days_standard = *Monthly Value` |
| 有语言项没有语言文件 | `lang_arabic` 存在，但没有 `ar.lproj`（8 个语言目录里没有阿拉伯语） |
| 通知文案是拼接的 | `%@和其他%@人发表了评论` 这种复数/词序依赖的串，在四种语言里很难同时正确 |

> 我们的做法已经更严（"本地化要按各语言自然重写，不逐字直译"），但**"key 全等"这种自动检查会漏掉未翻译的英文占位**。检查项应该加一条：目标语言的 value 不得与 en 完全相同（白名单除外）。

### 4.4 工程与安全

| 坑 | 证据 |
| --- | --- |
| 客户端硬编码对称密钥 | 二进制里成对出现 `MOODADEEPLINKSECRETKEY__20210403` 与 `DEEPLINKSECRETIV`，配合 `MOODA.CryptoManager`（CryptoSwift）。密钥随包发布 → 只能防手改链接 |
| 双图片库 | Kingfisher + SDWebImage 同时引入（两套缓存） |
| 未上线功能连着图标一起进包 | `RoomTodo/Todo/TodoViewController` + `TodoViewModel` + `ic24Todo`，8 种语言 0 个 todo 文案 |
| 正文用自研 HTML 富文本 | `HTMLStorage` / `HTMLElementRepresentation` / `ParagraphAttribute` 全套自研解析与渲染 —— 灵活但重，任何格式变更都要自己扛迁移 |
| 源码路径与内部结构全泄露 | 242 个 `/Users/mookie/Developer/AnalogLab/MOODA-iOS/...` 路径字符串 |
| 订阅 + 消耗型糖果并存 | `premium.month/year` + `candy.30/40/50`，且糖果需要服务端账本（`/v1/candy/histories`、`/v1/billing/*`） |

---

## 5. 美术资产：怎么规划、怎么用、怎么加载

### 5.1 命名即索引：六套命名法（实测统计）

| 族 | 数量 | 命名 | 规格 |
| --- | --- | --- | --- |
| 图标 | **153 个名字**（306 个位图档：1x + 2x PDF，另有 3 个带矢量副本） | `ic{12,16,20,24,28,36,40}{Name}`（ic24 最多，102 个） | PDF 矢量，`Template Mode = automatic`（可 tint），其中 208 档是灰阶单通道 |
| 插画装饰 | 34 | `vec{Name}`（`vecLogoHoriz`、`vecLock*`、`vecDivider003..009`、`vecMarker14*`、`vecThemeXmas*`） | PDF 矢量 |
| 贴纸包 | 6 包 221 张 | `{pack}_stic_NN` / `_pre_R_C` / `_thumb` / `_tag` / `_storeThumb` | PNG @3x：本体 600×600、预览瓦片 141×144、封面 72pt、标签 156pt、商店图 1125pt |
| 房间实物 | 24 | `roomMemo_0X_{frame,mask}`、`roomPhoto{Square,Ver,Horiz}_0X_{frame,mask}` | PDF，1x 144×144 / 144×176 / 144×192 / 192×144 + @2x |
| 扭蛋机 | 18 | `roomMoodBall*`（15）、`moodball_{body,glass,head}`、`BarUp/BarDown`、`Capsule`、`Label` | PDF 分层件 |
| 主题 token | 130 色 + 13 图案 | `wallB{h,l,m,vh}N` / `tableB*` / `bgC*` / `pen*` / `marker*` / `pttrn{Gingham,Grid}*` | Color asset（无位图）+ 图案 PNG 102×102 @3x |
| 环境变体 | 120（窗户）+ 10（节日表情）+ 8（灯） | `window{A,B,C}_{NN}_{day,night}[_xmas][_small]`、`emojiThemeHoliday*`、`lamp_0X[_small]` | PNG @3x |
| 本地化营销图 | 7 | `polaroid_banner` 一个名字下挂 `imgShopBn{En,Ko,Jp,Zt,Zs,Th,Id}` | PNG @3x 1080×432（每语言一张，合计 ≈ 790 KB） |
| 占位/默认 | 13 | `img*`（9 个：`imgCoverPhoto`、`imgPhotoDummy`、`imgSetupBirthday`、`imgShadow`、`imgStickerCover{Top,Bottom,BottomCut}`、`imgStickerPackDash{On,Off}`）+ `default_A` + `ic36{bg,divider,null}` | 混用（`imgPhotoDummy` 是 1x 大位图，其余多为 @3x） |

### 5.2 规格决策规则（可当规范抄）

| 资产类型 | 结论 | 实测佐证 |
| --- | --- | --- |
| 图标 | **矢量 PDF + 模板色**，按显示尺寸分家命名 | 153 个图标 = 306 档 PDF（1x + 2x），全部 `automatic` 模板 |
| 房间物件 / 机器 | **矢量 PDF**，`frame` + `mask` 成对 | `room*_frame` / `room*_mask`，1x+2x |
| 贴纸 / 表情 | **PNG @3x 单档** | 600×600、360×360(@3x→120pt) |
| 图案 | PNG，可平铺 | `pttrn*` 102×102 @3x |
| 色值 | **Color asset，不做位图** | 130 个 Color，墙/桌/笔/荧光笔全是色值 |
| 会动的东西 | Lottie（9 个），节日 = base + 覆盖层 | §1.2 |
| scale 策略 | 位图**只出 @3x**（224 个），矢量出 1x+2x（264 个），另有 455 个只有 1x | `Scale` 分布 |
| idiom | **全部 universal**（没有 phone/pad 分家） | 1326/1326 |
| 色彩空间 | sRGB 987 / Gray 303 / P3 少量（56+17） | `Colorspace` 分布 |
| 外观 | **无暗色变体** | `Appearances` 里 0 个 dark |
| 压缩 | `deepmap2` 1155 / `lzfse` 5 | `Compression` 分布 |

> 关于分辨率，我们和 MOODA 用的是**两种都成立但必须写清楚**的约定：
> - MOODA：位图按"显示尺寸 × 3"出图（情绪脸 120pt → 360px，预览瓦片 47pt → 141px），系统负责挑档。
> - 耳语：`ArtworkMapping(sourceSize → sceneSize)` 把**画布像素当成设计坐标系**，资产目录里不声明 scale。首页实测三个物件的显示宽度（402pt 画布上）约为星星 156pt、胶囊 199pt、纸团篓 167pt，@3x 设备需要 468–597 px，而我们的画布是 724–2500 px，**余量是够的**。
> 结论：不要为了"统一"去改我们的约定，但要把这条关系写进 `DesignAssets/README.md` 当硬约束——**画布像素必须 ≥ 该物件在最大机型上的显示尺寸 × 3**，否则新物件会在新设备上先糊。

### 5.3 使用：同一份资产如何被复用

- **一个图标多处用**：`ic24Memoryball`（房间里的机器入口 / 菜单 / 设置行）、`ic16*Tooltip`（四种方向的提示箭头）、`ic40MyMonth` / `ic40FriendsMonth`（首页分页）。
- **色值 + 模板图标 = 主题**：墙 14 色 × 桌 14 色 × 图案 13 × 窗户 15 款 —— **换皮肤不换位图**，代价只在"窗户"这一项上（2.4 MB）。
- **frame + mask 的复用**：3 种便签 × 3 种照片规格 = 9 套框，同一套 `mask` 服务所有同规格内容。
- **贴纸包的四件套**：本体（600×600）、列表瓦片（47pt）、封面（72pt）、标签（156pt）各司其职；商店大图（`storeThumb` 1125pt）只给商品页。
- **本地化美术是位图级的**：`polaroid_banner` 一个资产名下挂了 7 张语言版本（`imgShopBnEn/Ko/Jp/Zt/Zs/Th/Id`，1080×432，合计 ≈ 790 KB）。**代价是每加一个语言就要再出一张图**。耳语要支持四种语言，凡是带文字的插图（如果我们要做）必须先决定：是每语言出图（美术成本 ×4、包体 ×4），还是只出无字底图、文字用代码叠（一处排版逻辑，四种语言共用）。MOODA 选了前者，我们应选后者。

### 5.4 加载：三层来源 + 两种缓存

| 层 | 内容 | 通道 |
| --- | --- | --- |
| 包内 | UI 图标、主题 token、房间/机器矢量件、6 个默认贴纸包（221 张）、窗户/灯变体、情绪脸、9 个 Lottie | `Assets.car`（8 MB）+ `Bundle` |
| 服务端（商店） | 更多贴纸包与相框包（`polaroidPack_1000` 就是包内无本体、只有预览的包） | `/v1/sales-item/{stickers,sticker-image,pre-image,detail}`、`/v1/shop/sticker-items` |
| 服务端（用户内容） | 用户上传的日记图、房间照片、头像 | `/v1/images?imageType=`、`/v1/images/item?imageType=` + Kingfisher/SDWebImage |
| 本地相册 | 写日记时选图 | `PHImageManager.requestImageForAsset:targetSize:` |

配的三件事：**预取**（列表）、**降采样**（库配置）、**骨架屏**（Lottie）。加上"列表只用预生成小图"，这就是他们整套资产加载策略。

### 5.5 落到耳语的具体动作（按可执行度排序）

1. **命名规范补两族**：图标用 `ic{24}{Name}`（PDF + template），变体用 `{Base}_{场景}`（如 `StarCharm_Candy_Joy_Xmas`）。理由：他们 153 个图标 / 120 个变体全部靠命名自解释，我们的资产名已经承担"改名会让已保存内容找不到资源"的责任。
2. **节日层资产**：`StarCharm_{Style}_{Emotion}` 不动，另出同画布 `StarCharm_{Style}_HolidayOverlay`（或按节日细分），运行时叠加。**这是 MOODA 唯一一处"用工程省美术"的地方，且几乎零风险。**
3. **贴纸/字体选择器预生成缩略图**：列表只解小图，选中后才解原图（他们的 `pre/thumb/tag` 四件套）。我们现在没有选择器，一旦做就按这个来。
4. **色值走 asset catalog 的 colorset**：目前我们只有 `AccentColor` / `LaunchBackground`。纸张、挂件如果以后要出配色，先做成 colorset 而不是新位图。
5. **`DesignAssets/README.md` 补一条分辨率硬约束**：画布像素 ≥ 最大显示尺寸 × 3（见 §5.2）。
6. **发布检查加三条**：包内不得有 dev/staging 配置；`UIAppFonts` 清单与实际文件一致；位图资产不得只存在 @1x 声明却又没有足够像素（我们的 single scale 约定要求这条）。

### 5.6 明确不做

- 不做 130 个色值的完整 token 体系（他们的房间有墙/桌/笔/荧光笔四套皮肤，我们只有三个物件，过度系统化没有产出）。
- 不做 P3/灰阶/双 rendition 的精细化（我们单档位图 + 单套 scale 已经够）。
- 不引第二个图片库，不引 Metal 滤镜管线（他们的 MetalPetal 是为照片滤镜服务的，我们不做滤镜）。
- 不做背景音乐/环境音去凑"实物感"。

---

## 附录：本文新增证据索引

| 结论 | 证据 |
| --- | --- |
| 无物理、无自绘转场 | `UIDynamicAnimator` 0 处使用、`UIDynamicItem` 4 处、`UIViewPropertyAnimator` / `CASpringAnimation` / `UIPercentDrivenInteractiveTransition` 均 0；只有 SideMenu 自带 `BasicTransitionAnimator` |
| 抽屉跟手与橡皮筋 | SideMenu 配置键 `dampingRatio` / `initialSpringVelocity` / `enableRubberEffectWhenPanning` / `panGestureSensitivity` |
| 触觉控件化 | `_TtC5MOODA12HapticButton` + 28 处 `T@"_TtC5MOODA12HapticButton"` 属性接线 + `Haptica` |
| 9 个 Lottie 与规格 | 逐个解析 json 的 `w/h/fr/op/layers`（本文 §1.2 表） |
| 节日 = 覆盖层 | `emojiThemeHolidayMixedFeelings.json` 3 层 = base 2 层 + `emojiThemeXmasComplicated Outlines` |
| 包体构成 | `du -sh`、`ls -l MacOS/MOODA`、`ls -l Resources/Assets.car`、appex 目录清单 |
| 缩略图/降采样配置 | `imageThumbnailPixelSize`、`imageScaleDownLimitBytes`、`DownsamplingImageProcessor`、`cacheOriginalImage`、`SDImageCacheConfig` / `maxMemoryCost` / `maxDiskSize`；`CGImageSourceCreateThumbnailAtIndex` 0 次 |
| 预取与布局 | `UICollectionViewDataSourcePrefetching`、`prefetchItemsAt`；`NSCollectionLayoutSection` 仅 2 处 |
| 资产规格分布 | `assetutil --info` 全量统计：Scale / Idiom / Appearances / Compression / Colorspace / Template Mode |
| 资产体积分布 | 按名字前缀汇总 `SizeOnDisk`：window* ≈ 2.4 MB、polaroid* ≈ 1.6 MB、`imgPhotoDummy` 406 KB |
| 免费阶梯与隐私粒度 | `localizable_ko.txt` / `localizable_zh-Hans.txt` 全文（523 项） |
| 首启动线 | `Classes/Feature/Onboarding/{UserName,Birthday,CoverName,CoverEdit,Draw,Sticker,Gallery}`（`sources.txt`）+ 对应文案 |
| 未上线 Todo | `RoomTodo/Todo/TodoViewController`、`ic24Todo`；8 语言 0 个 todo key |
| deeplink 硬编码密钥 | 二进制字符串 `MOODADEEPLINKSECRETKEY__20210403` / `DEEPLINKSECRETIV` + `MOODA.CryptoManager` |

复现方式与前一文相同（`assetutil`、`strings`、`plutil`、从 `Assets.car` 抽原始 PDF），全程只读，未改动原 App，未启动该 App。
