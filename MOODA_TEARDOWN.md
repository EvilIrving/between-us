# MOODA（io.analoglab.mooda 2.3.1）技术拆解

记录日期：2026-09-18
来源：Mac 上已安装的 Mac App Store 版 `/Applications/MOODA.app`（`io.analoglab.mooda`，v2.3.1 build 63，AnalogLab Corp.，Xcode 16.3 构建，最低 iOS 15 / macOS 12，276 MB）
素材：`research/mooda/`（资产清单、源码路径表、两语言文案、API 清单、字体表、34 张原始 PDF 与渲染图）
性质：只读拆解，用于对照耳语的情绪体系、物件与房间。**不是可复用素材来源**，他们的位图/字体/Lottie 一律不进我们的包。

---

## 0. 一句话结论

MOODA 是一个**个人情绪日记 + 社交社区 + 订阅制**的完整商业产品：首页是日历，每天一篇日记（文字 + 手绘 + 贴纸 + 照片），情绪是结构化字段，月末由**一台扭蛋机（무드볼 / Mood Balls）把当月所有情绪吐成实物**。它跟耳语最容易混淆的地方是「房间里摆东西」，但两者的所有权相反：**MOODA 的空间属于一个人，墙上的东西是给朋友参观的展览；耳语的空间属于两个人，瓶里的东西是留给对方打开的**。技术路线上它和耳语几乎互补——服务端为主、无 CloudKit、无物理、50 款字体全内置（占包体 84%）、社交与广告归因 SDK 全家桶。

---

## 1. 产品与商业结构

| 项 | 事实 |
| --- | --- |
| 定位 | 情绪日记（`public.app-category.lifestyle`），首页 = 日历（我 / 与好友一起 两个 feed） |
| 形态 | iOS 为主，同时上架 Mac App Store；本包是 **Catalyst 版**（`LC_BUILD_VERSION platform 6`、`UIDeviceFamily = [2]` 只声明 iPad、链接 `/System/iOSSupport/...`） |
| 登录 | Apple / Google / Facebook / LINE 四种第三方登录，有登录墙（`Splash.storyboardc` 是 `UIMainStoryboardFile`） |
| 情绪 | 结构化字段，10 个表情面（`emojiJoy/Excited/Happy/Anger/Calm/Neutural/Fear/Tired/Sadness/MixedFeelings`）+ 节日主题版 10 个 |
| 页面 | 日历首页、房间、大家的一天（公开社区）、通知、搜索、好友、设置（43 个文件）、商店/会员、情绪球与统计、评论与回复 |
| 商业化 | **订阅**（`premium.month` / `premium.year`）+ **消耗型糖果**（`candy.30` / `candy.40` / `candy.50`，包内 StoreKit 文件标价 1.19 / 1.59 / 1.99） |
| 免费版限制 | ① 保存日记要「成为高级用户」或「看短广告并保存」，且这个选择 7 天内记住（`save_option` / `save_option_description`）；② 备忘录、照片有免费额度（`free_memo_limit` / `free_photo_limit`）；③ 日记搜索只能查最近 1 个月（`recent_one_month`，高级版才能全时段搜索）。另有一条 `recent_six_weeks_notification`（通知列表只显示最近 6 周）不确认是否属于付费分级 |
| 高级版权益 | 去广告、备忘录/照片/情绪球无限（`shop_unlimited_contents`）、商店所有付费道具免费用（`shop_paid_items`）、全时段搜索 |
| 语言 | 8 个 lproj（en/ko/ja/zh-Hans/zh-Hant/id/th），**7 种语言各 523 个 key，集合完全一致**（有硬性 key 对齐流程）。文案里留着 `lang_arabic`，但没有 ar.lproj |
| 运营 | 节日主题（圣诞：`emojiThemeHoliday*`、`windowA_*_xmas`、`themeXmas*` 动画、`vecThemeXmas*`）；情绪球月末通知；生日小礼物引导（`birthday_gift`） |

---

## 2. 内容模型：服务端为主，本地只缓存一张表

包内有两个 CoreData 模型，其中一个是空壳：

| 模型 | 实体 | 字段 |
| --- | --- | --- |
| `MOODA.momd/MOODA.mom` | **0 个实体**（`NSEntities` 为空） | — |
| `DiaryModel.momd/DiaryModel.mom` | `LocalDiary` | `content`、`writeYmd`、`title`、`updatedAt`、`background`、`metadata`、`diaryContentId` |

也就是说本地只落地日记正文与日期，**其余全在 `https://api.mooda.me`**（101 个端点，见 §8）。图片走独立图床端点（`/v1/images/upload`、`/v1/images/diary-content-upload`），网络层用 Alamofire + Kingfisher/SDWebImage。

**日记正文是 HTML 富文本，不是纯文本。** 二进制里有一整套自研 HTML 模型：

```
MOODA.HTMLStorage / HTMLRepresentation / HTMLElementRepresentation / HTMLAttachment
MOODA.RootNode / Header / Figure / Figcaption / Blockquote / HTMLParagraph / HTMLLi / HTMLPre
MOODA.ParagraphProperty / ShortcodeAttribute / Attribute / InAttributeConverter
MOODA.MOODATextView + MOODATextStorageAttachmentsDelegate + MOODAStickerInserter + MOODAMediaInserter
```

含义：文字、颜色、荧光笔、分割线、贴纸、照片都是**同一段 HTML 里的元素**，编辑态是自绘的 `MOODATextView`（带附件插入器），阅读态按同一份 HTML 重现。他们不需要「纸张分页」这套东西，因为内容是一整段流；我们最贵的那部分（容器链分页、翻页、叠纸、写满换纸）在他们那里根本不存在。

---

## 3. 情绪体系（最值得耳语看的一节）

### 3.1 两套情绪表，一套露脸一套说话

| 集合 | 成员 | 用在哪 |
| --- | --- | --- |
| 表情面 | joy / excited / happy / anger / calm / neutural / fear / tired / sadness / **mixedFeelings** | 日历里的每日情绪、日记情绪、贴纸（`mooda_001_stic_01_joy`…）、扭蛋机里的情绪球 |
| MOODA 的话语 | bored / calm / ecstatic / excited / happy / mixed / sad / stressed / tired / worried | `feeling_*_encouragement` 每档一句安慰话，设置里叫 `encouragement_settings = MOODA的话语` |
| 情绪名可改 | `emotion_rename = 감정 이름 바꾸기`（改情绪名） | 用户能重命名情绪标签 |

两套集合并不重合（有 anger/fear/neutural 的表情，有 bored/stressed/worried 的话语），说明它们是两个系统：**脸用来记录与统计，话用来回应**。

值得注意的两点：

1. **扭蛋机里只有 9 个情绪球**（`roomMoodBallEmoji*` 少了 MixedFeelings），贴纸包 `mooda_001` 也只有 9 张。而「复杂微妙」拿到的是**包内唯一一份会动的 Lottie 表情**（`emojiMixedFeelings.json`，120×120、60fps、1080 帧、18 秒循环，两层 `Face Outlines` + `Emotion Outlines` 相位错开 -581 帧；二进制里也只引用这一个表情名）。说不清的情绪被做成唯一会动的那一个，这是很干净的产品判断。
2. **`neutural` 是全库一致的拼写错误**（asset 名、enum case、`roomMoodBallEmojiNeutural` 都一样），并且写进了素材名，改一次要动全套资产。

### 3.2 情绪球：把「这个月过得怎么样」做成一台扭蛋机

房间里的 `roomMoodBall`（300×437 矢量）画成一台**扭蛋机**：红色顶盖 + 细线勾的大玻璃球 + 红色底座带一个取物口（下面是原始 PDF 渲染出来的样子）。

| 件 | 资产 | 尺寸 | 作用 |
| --- | --- | --- | --- |
| 机身/玻璃/顶盖 | `moodball_body` / `moodball_glass` / `moodball_head` | 200×118 / 69×69 / 24×10 | 分层拼装，可单独动 |
| 机器本体 | `roomMoodBall` | 300×437 | 房间里摆着的那台 |
| 情绪球 | `roomMoodBallEmoji*` | — | 每个情绪一颗 |
| 单颗球/胶囊 | `roomMoodBallCapsule` | 56×56 | 出球、统计页里的胶囊 |
| 柱状部件 | `roomMoodBallBarUp` / `Bardown` | 64×79 | 统计页的上下柱 |
| 招牌 | `roomMoodBallLabel` / `PackLabel` | 100×120 / 92×70 | 机器上的「MOOD BALLS」牌 |

规则（全部来自文案，不是猜的）：

- **门槛**：`mood_ball_condition_1 = 10篇以上的日记` 且 `mood_ball_condition_2 = 每月的最后一天`（`mood_ball_condition_fulfilled = 已实现`、`mood_ball_day_left = 剩下%@天`）。
- **查询期**：`mood_ball_view_alert = 통계 보기는 6개월 전까지 가능해요`（只能看 6 个月内），高级版 `shop_unlimited_contents` 里写明「心情球的查看期限已取消」。
- **推送**：`moodball_notification = 이번 달 무드볼을 확인해 보세요!`。
- **统计页**由四类子视图拼成：`MoodBallStatisticsView`、`MoodBallEmotionCapsuleView`（每个情绪一颗胶囊带数量）、`MoodBallEmotionFactsView`（`EmotionFactsViewAmountView` + `SpacerView`）、`MoodBallDetailNoteView` / `AmountViewCellView` / `MoodBallDetailBottomView`，另有 `review_tilte = 이번 달 총평`（本月总评，最多 50 字，`review_guide = 点击留下本月的总评`）。

**这是 MOODA 最值得耳语抄的东西，而且不是抄外观，是抄结构：** 它不是把日记做成时间线，而是**在每个月的最后一天，把散落一个月的情绪压成一颗可以拿在手里看的实物**。门槛（≥10 篇）、稀缺（只有月末出现）、有限期限（免费只给 6 个月）、提醒（月末推送）四条一起，让它既不打断日常，又给长期使用一个非游戏化的理由——没有签到、没有任务、没有金币。

---

## 4. 房间：一个可以被参观的实物展台

房间（`RoomViewController` / `RoomBoardView` / `RoomBoardItemView` / `RoomBoardGridView` / `RoomBoardGestureRecognizer` / `RoomBoardToolbarView` / `RoomBoardTableGuideView` / `RoomMenuViewController`）是耳语最该对照的一块。

### 4.1 结构与规则

| 项 | 事实 |
| --- | --- |
| 两个面 | **墙**和**桌**各算一份容量，各自报错：`space_lack_wall = 墙上没有足够的空间粘贴。请先创建空间。` / `space_lack_desk = 桌子上放置的空间不足。请先创建空间。`（韩文原文是「먼저 만들어 주세요」= 请先创建空间） |
| 上限 | 备忘录 1 万（`space_lack_memo`）、照片 100（`space_lack_photo`）；免费额度另有 `add_memo_limit = 备忘录最多 50`、`photos_stickers_limit` |
| 可见性 | `allow_room = 允许访问您的房间`（可以设置谁能进你的房间）、`room_view_all = 全部`、`room_view_friend = 好友`、`room_locked = 房间已锁住` |
| 放置 | 位置存服务端（`/v1/room/items/position`），按类型查看（`/v1/room/items-by-view-type`），长按装饰（`long_press_to_decorate = 长按装饰房间`）、`touch_to_decorate_photo`、拖动指引（`drag_along = 沿线，向左拖动到右边`） |
| 待办 | 代码里有 `RoomTodo/Todo/TodoViewController`、`TodoViewModel`、`TodoRouter` 与图标 `ic24Todo`，**但 8 种语言一个 todo 文案都没有** → 未发布功能 |

### 4.2 房间里的东西：frame + mask，全是 PDF 矢量

和耳语的物件走的是同一种配准思路（前景框 + 遮罩），但他们把这类资产做成矢量：

| 家族 | 件数 | 画布（1x） | 说明 |
| --- | --- | --- | --- |
| `roomMemo_01..03_[frame\|mask]` | 3×2 | 144×144 | 便签纸，手绘粗糙方框 |
| `roomPhotoSquare_01..03` | 3×2 | 144×176 | 方形照片框（带一条黄色和纸胶带） |
| `roomPhotoVer_01..03` | 3×2 | 144×192 | 竖版 |
| `roomPhotoHoriz_01..03` | 3×2 | 192×144 | 横版 |

配套皮肤完全是**颜色 token**：墙 14 个（`wallBh/Bl/Bm/Bvh` 四档明度）、桌 14 个（`tableB*`）、便签底 36 个（`bgC*` 9 色 ×4）、画笔 20 个（`pen*`）、马克笔 8 个（`marker*`）、荧光笔、`guideline`、`scrim`、`selected`、`toast`，另有图案 PNG（`pttrnGingham1..9` 1:1 格纹、`pttrnGridBlue/GridDot/GridGrey`）。**墙/桌/笔/荧光笔没有一张位图**——身份靠色值，材质靠图案。

### 4.3 时段与节日：预先出图，不运行时算

窗户是最典型的做法：`windowA/B/C` × 5 款 × `day`/`night` × 普通/`xmas` × 全尺寸/`small` = **120 张**（`windowA_01_day_xmas_small` 这种命名把六个维度写进资产名）。灯 4 款 + `_small`。节日另加 Lottie 覆盖（`themeXmasLightDeco.json` 是灯串，`themeXmasMainBotFootPrint.json` 22 层是小机器人脚印，`vecThemeXmas*` 是按钮/月度装饰）。

**规律：所有"会因为时间/节日变化"的视觉都提前出成变体图，运行时只挑图，不做着色、不做避让计算。** 这一条和 TinyType 的 `plain/low/mixed/image` 背景变体是同一个工程习惯。

---

## 5. 资产管线

`Assets.car` 7.3 MB，1326 个 rendition / 945 个名字：

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| Image | 1077 | 渲染名里 561 是位图（deepmap2 压缩）、560 是 PDF（`RenditionName` 后缀 `.pdf`） |
| Color | 130 | 整套设计 token（见 §4.2） |
| Vector | 34 | 34 个 `vec*`（Logo、锁屏、分割线、Marker、圣诞装饰） |
| PackedImage | 73 | Apple 打包格式（`ZZZZPackedAsset-*`） |

### 5.1 贴纸包 = 四类图 + 预览瓦片

6 个内置包，共 221 张贴纸（`mooda_001` 9 张情绪、`friends_002` 34、`abstract_003` 28、`letteringRed_004` / `letteringYellow_005` / `letteringBlue_006` 各 50），每个包的命名模式固定：

| 角色 | 命名 | 规格 | 用途 |
| --- | --- | --- | --- |
| 贴纸本体 | `{pack}_stic_NN`（情绪包带后缀，如 `_stic_01_joy`） | **600×600 PNG** | 编辑/房间里的实际贴纸 |
| 预览瓦片 | `{pack}_pre_R_C` | 141×144 @3x（47×48 pt） | 商店里铺成 3 行 × 5–8 列的包内容预览 |
| 包封面 | `{pack}_thumb` | 72 pt | 列表封面 |
| 包标签 | `{pack}_tag` | 156 pt | 包名字图 |
| 商店大图 | `polaroidPack_1000_storeThumb` | 1125 pt | 商品页主图 |

两条可用的结论：

1. **预览瓦片是预生成的独立资产**（不是运行时把 600×600 缩下来拼），所以商店列表不需要解码大图——和我们做字体/贴纸选择器时应有的做法一致。
2. **`polaroidPack_1000` 包内一张贴纸都没有**（只有 18 张预览瓦片 + `storeThumb` + `tag`），本体靠 `/v1/sales-item/sticker-image` 从服务端下发。也就是说**商店是服务端数据驱动的，包内资产只是默认包**（`/v1/sales-item/detail`、`/stickers`、`/stickers/my`、`/recent-id`、`/pre-image`、`/v1/shop/sticker-items`）。

### 5.2 位图 vs 矢量

- 贴纸 = 600×600 PNG（4–6 KB/张，线条艺术压得极狠）。
- 房间物件、扭蛋机、分割线、图标 = PDF（`roomPhotoSquare_01_frame.pdf` 144×176 与 288×352 两档 + 一份 47 KB 的矢量副本）。
- 图案 = 102×102 @3x PNG（可平铺）。
- 情绪脸 = 360×360 @3x PNG，节日版另出一套（`emojiThemeHoliday*`），只有「复杂微妙」额外给了 Lottie。

**我们的分歧点**：耳语的物件是位图身份（材质、光影、真实感），MOODA 是矢量手绘风（颤动的墨线、低饱和填色、便签与胶带）。这不是能力差距，是两条审美路。**唯一可以直接借的是"变体不重绘"：节日皮肤做成同画布覆盖层（他们的节日表情就是在 base 的 2 层上加了第 3 层 `emojiThemeXmasComplicated Outlines`），而不是重画整套挂件。**

---

## 6. 字体：50 款 116 MB，占包体 84%

| 项 | 事实 |
| --- | --- |
| 数量 | **50 个字体文件（116 MB）**，`UIAppFonts` 里声明了 **51 条** |
| 僵尸条目 | `03_drfont_daraehand_Basic.ttf` 在 plist 里但**不在包里**（真身是 `03_DaraeHand.otf`） |
| 同名隔离 | 几乎所有韩/日字体都被重制并**加了 `New` 后缀**：`DaraeHandNew`、`GaeguNew`、`UhBeePudingNew`、`PoorStoryNew`、`XiaolaiSCNew`、`SetoNew`、`MushinNew`…（全部 `Version 1.000;Glyphs 3.1.2`，明显是同一批重导出） |
| 按语言成组 | 韩 24 / 日 15 / 泰 9（Mali×3、Itim、Kancha×4、nura-aroi）/ 中 **2**（`19_ZCOOLKuaiLe-Regular.ttf` 3.1 MB + **`20_XiaolaiSC.otf` 23.6 MB**）；体积前三是 `XiaolaiSCNew` 23.6 MB、`851TegakiZatsuNew` 16.1 MB、`SetoNew` 8.5 MB |
| 用户可见 | 字体是设置项（`font_style = 字体`、`font_size = 尺寸`、`InputFontSelectView`），文案键语义化（`font_xiaolaisc`、`font_uhbee_puding`），与文件名解耦 |
| 小组件复制 | `CalendarWidgetExtension.appex` **把 50 款字体整套又打了一份**（116 MB）→ 全 App 276 MB 里 **232 MB 是字体** |
| 加载方式 | `UIAppFonts` 静态注册，启动时系统无条件加载全部 51 条 |

对照耳语（`DesignAssets/fonts/README.md`）：我们 15 款、内置 1 款兜底（霞鹜文楷 24.4 MB）、其余 230 MB 走 CDN 按角色下载。**这个方向不变**，但 MOODA 给了两条必须照做的经验：

1. **`*New` 命名空间隔离。** 我们 CDN 下来的字体用的是原始 PostScript 名（`Yozai-Regular`、`Xiaolai`），而 MOODA 选择重制字体并统一改名。用户机器上装着同名字体时，`CTFontManagerRegisterFontsForURL` 的注册结果与解析结果都不确定（我们的文档已经记了 Caveat 重复名报 105/305）。改名是唯一能把这条不确定性彻底消掉的办法——尤其 `XiaolaiSCNew` 这种：他们的中文手写体和我们的 `Xiaolai` 是同一支。
2. **小组件只带一款字体。** 他们要日历小组件用上 50 款可选字体，于是复制了 116 MB。我们的周/月视图只需要一款兜底字体；这一条如果哪天真做小组件，先定死。

---

## 7. 编辑器：一个贴着便签的工具栏

从 `Editor/`、`Draw`、`PhotoEditor`、`PhotoFilter`、`Divider`、`Sticker`、`Font`、`ColorPicker` 这些 storyboard 与类名反推：

| 能力 | 事实 | 限制 |
| --- | --- | --- |
| 文字 | `MOODATextView`（HTML 附件模型） | 标题 + 正文 |
| 画笔 | `pen*` 20 色 + `vecMarker14Left/Right` 马克笔 8 色 + `highlighter` 荧光笔 + `guideline` | 画布手绘 |
| 分割线 | `vecDivider003..009`（各 2 个方向）、`DividerCrossMixView` | `max_divider = 最多十条分隔线` |
| 贴纸 | `MOODAStickerInserter` + `StickerFrameType` / `FreeStickerPackageType` | 每篇 `photos_stickers_limit = 照片和贴纸最多 50 个` |
| 照片 | `EditorPhotoFrame` / `EditorDualPhotoFrame` / `EditorThirdPhotoFrame` / `EditorFourthPhotoFrame` | `max_photo_upload = 最多四张`；`collage_photos = 打包上传照片` |
| 滤镜 | `EF1/EF2/EF3` + `photo_filter_none` | 三档 |
| 抽屉 | `drawer = 抽屉`、`irStickerView` | 底部工具抽屉 |
| 装饰手势 | `long_press_to_decorate`、`touch_to_decorate_photo`、`drag_along` | 长按/拖动 |
| 心情 | 每天一个情绪（`how_was_your_day = 오늘 하루는 어땠니?` / `how_was_past_day`） | 10 档 |

编辑器里**没有任何物理**：`UIDynamicItem` 只有 4 处引用、`UIDynamicAnimator` 没有意义地出现在一个符号残片里；拖动是手势识别器 + 网格吸附（`RoomBoardGridView`）+ 触觉反馈（`HapticManager` / 自定义 `HapticButton`）。耳语的路（SpriteKit 物理驱动）在 MOODA 这条线上完全不存在——这反过来证明我们的物理不是必需品，而是**我们选择的物性**。

---

## 8. 后端、同步与合规

### 8.1 自有服务端 + Firebase，没有 CloudKit

```
entitlements: app-sandbox / network.client / photos-library
              aps-environment=production / applesignin / application-groups(group.io.analoglab.mooda)
              associated-domains(applinks,webcredentials: app.mooda.me)
              keychain-access-groups     ← 没有 iCloud / CloudKit 任何一条
```

域名与端点：

| 组 | 端点 |
| --- | --- |
| 用户 | `/v1/users/me/{username,language,birth,push-token,push-setting,private-setting,setting,join-username}`、`/v1/users/{diaries,withdraw,devices,check-username,calendar-color,diary-title,diary-cover-image}` |
| 日记 | `/v1/diary-content{,/write,/modify,/delete,/all-private,/search/detail,/search/metadata}`、`/v1/diaries/{monthly-diary,recent-writeable-date}`、`/v1/alarm`、`/v1/alarm/recent-id` |
| 房间 | `/v1/room/items/{memo,photo,detail,position,count,my}`、`/v1/room/items-by-view-type`、`/v1/room/mood-ball/{summary,detail,feed,memo}` |
| 社交 | `/v2/friends{,/approvers}`、`/v1/friends/{request,accept,delete,count}`、`/v1/follow{,/status,/cancel}`、`/v1/feed/{daily,monthly}-friends-summary`、`/v1/feed/following`、`/v2/comments/*`、`/v2/replies-with-id`、`/v1/reactions/{list,count,cancel}` |
| 商店 | `/v1/sales-item/{detail,stickers,stickers/my,sticker-image,pre-image,recent-id}`、`/v1/shop/{membership,sticker-items}`、`/v1/billing/{prepare,success}`、`/v1/candy/histories`、`/v1/subscription/{receipt,histories}` |
| 图片 | `/v1/images`、`/v1/images/upload`、`/v1/images/diary-content-upload`、`/v1/images/item` |
| 其他 | `/v1/status`（强更开关）、`/v1/terms/agreement`、`app.mooda.me?link=`（分享链接）、`docs.mooda.me/{ko,en,ja,th,id,zs,zt}-{terms,privacy,notice,faqs,community-guide}` |

### 8.2 数据与隐私

- **埋点与广告归因全家桶**：FirebaseAnalytics + Crashlytics + Messaging + Google Sign-In + Facebook（AppID、ClientToken 都在 plist 里）+ LINE + AdMob（`GADApplicationIdentifier`）+ ATT（`NSUserTrackingUsageDescription` + `NSPrivacyTrackingDomains = ep1.facebook.com`）+ **42 个 SKAdNetworkIdentifier**。
- **包内同时带着开发环境配置**：`GoogleService-Info.plist`（项目 `mooda-4d208`）与 **`GoogleService-Info-Dev.plist`（项目 `mooda-f2cb9`、bundle id `io.analoglab.mooda.dev`、含 Realtime Database URL）** 一起进了正式包，打包时没有排除。
- **硬编码的 deeplink 密钥**：二进制里成对出现 `MOODADEEPLINKSECRETKEY__20210403` 与 `DEEPLINKSECRETIV`，配合 `MOODA.CryptoManager`（CryptoSwift）使用。密钥随包发布，这种对称加密只能防用户随手改链接，防不住任何人逆向。
- 账号注销有冷静期（`24hours_join_impossible = 退出后 24 小时内无法重新加入`）。
- 对比耳语：我们只有 CloudKit + CKShare、不做账号体系、不带任何追踪 SDK。**MOODA 说明这条路在商业上是可行的另一条，但也正好说明我们放弃的是什么。**

### 8.3 小组件

`CalendarWidgetExtension`（`io.analoglab.mooda.widget`，WidgetKit）是一个**情感日历**：`widget_title = 情感日历`、`widget_description = 이번 달 내 감정을 모아 보세요`（把本月我的情绪收在一起看）。它自带一整套基础设施：`WidgetNetwork` + `KeychainManager`（读 App 写入的 token）+ `LocaleManager` + `CalendarManager` + `MoodaLogger` + `MoodaErrorResponsePlugin`，把 9–10 个 `emoji*` 面按天铺在月历上。代价见 §6：116 MB 的字体复制。

---

## 9. 工程观察

- 架构：**MVVM**，每个功能三件套 `XxxRouter` + `XxxViewModel` + `XxxViewController`（`AloneViewModelInput/Output/Type` 这种协议组合在二进制里非常整齐）。242 个自有源码路径完整泄漏：`/Users/mookie/Developer/AnalogLab/MOODA-iOS/MOODA/Classes/Feature|UIComponents|Common/…`，也就是说**功能目录本身就是产品地图**：Feature 199 个文件 / 41 个 UIComponents / 2 个 Common。
- 目录分布（Feature 下）：Setting 43、Product 14、Onboarding 14、RoomMemo 12、Room 11、Feed 11、Editor 10、MoodBallDetail 9、Search 7、RoomPhoto 7、MembershipDetail 7、Comment 7、MoodBall 6、Notice 4、DiaryHome 4、StickerOrder 3、ShareProfile 3、Scope 3、Main 3、RoomPreview 2、RoomMenu 2、PrivacyPolicy 2、PhotoFilter 2、Login 2、Every 2、Alone 2、其余各 1。
- 第三方栈：RxSwift/RxCocoa、SnapKit、Then、Alamofire、Kingfisher、SDWebImage、Lottie、Toast、QRCode、CryptoSwift、AppAuth、DeviceKit、NVActivityIndicatorView、SideMenuSwift、CoreData。UI 是 storyboard 混合代码（23 个 `*.storyboardc` + 大量 `.nib`，在 Catalyst 上继续用 iOS 那套）。
- 质量细节（可以当反面清单）：`neutural`（拼写）、`DivierMixView`（拼写）、`count_days_title = NOD:` 与 `count_days_content = %@ days`、`*Monthly Value` 在 **zh-Hans/zh-Hant 里没被本地化**（`%@ days`、英文标题直接露给中文用户）；`UIRequiredDeviceCapabilities = armv7` 这种 2013 年的遗留字段还在；Dev 配置进包；`UIAppFonts` 里留着一个不存在的字体条目。
- 8 种语言 523 key 完全对齐（集合逐一比对：missing 0 / extra 0），说明他们有强制的 key 对齐流程——**这一点耳语的四语言同步要求可以照抄成硬约束，但要连"中文里不留英文占位"一起管住**。

---

## 10. 能拿的 / 不能拿的

### 值得拿（9 条，按价值排序）

1. **月末回顾物件（情绪球的结构，不是外观）。** 门槛（≥10 篇）+ 月末才出现 + 免费只看 6 个月 + 月末推送 + 统计页（每情绪胶囊数量、总评、备注），是一套完整的**非游戏化长期动机**。耳语现在三个物件只有"放入 / 打开"，没有任何"攒到一定程度一起看"的仪式，这是产品层最实的一块缺口。
2. **说不清的那个情绪给唯一的动画。** 「复杂微妙」是 10 个情绪里唯一有 Lottie 的。这条判断可以直接迁移：我们不需要每个挂件都动，**只给最难命名的那一个情绪更高的动态预算**。
3. **节日 = base + 覆盖层。** 他们的节日表情是在 base 两层之上加第 3 层 `emojiThemeXmasComplicated Outlines`，不重画。我们的 `StarCharm_{Style}_{Emotion}` 如果要做节日版，优先出同画布覆盖层位图（挂件 + 一层圣诞元素），而不是 5 系列 × 6 情绪 × N 节日重出图。
4. **时段/环境变体也是预出图。** `windowA_01_day/night/xmas/small` 六个维度写进资产名。我们的首页如果要有"白天/夜晚""生日/节日"，照这个做，运行时只挑图。
5. **颜色 token 与图案分离的房间皮肤。** 墙、桌、便签底、画笔、马克笔、荧光笔全是色值（130 个 Color 资产），只有图案是 PNG。我们的纸张/物件如果开放自定义色，也应该只换 token，不换位图。
6. **预览瓦片预生成**（`pre_R_C` 47 pt + `thumb` 72 pt + `tag` 156 pt）。选择器不要运行时缩大图——我们做字体/贴纸预览时直接用。
7. **字体 family 加命名空间**（`*New`），把用户机器上同名字体的不确定性彻底消掉；`XiaolaiSCNew` 就是我们的 `Xiaolai`。
8. **小组件只带一款字体**（他们的 116 MB 复制是反面教材）。
9. **key 对齐当硬约束**（7 语言 523 key 全等），同时把"目标语言里不留英文占位"写进检查项。

### 不能拿（7 条）

1. **社交社区**：大家的一天、好友、关注、评论、点赞、屏蔽、举报、好友日记推送。耳语没有公开流，也不该有。
2. **账号体系与服务端存储**：我们唯一通道是 CloudKit + CKShare，没有业务服务器。
3. **服务端驱动的商店与资源热更**（`sales-item` / `sticker-image`）：我们没有 CDN，也没有服务端账本。
4. **订阅 + 消耗型糖果**：`candy.30/40/50` 需要服务端货币账本；我们的付费是"一个空间一次买断、对方不用再买"，这条不换。
5. **广告**，特别是"看短广告并保存日记"：它把最核心的写入动作放在广告后面。我们的免费额度拦截点是"放入第 11 条"，不碰广告。
6. **50 款字体全内置**（232 MB / 276 MB）。
7. **房间的参观模型**（好友能进你的房间看）：我们的空间是双人私有，不是展台。

### 一个必须承认的分歧

他们的空间是**一个人布置、别人来参观的展台**；我们的空间是**两个人共同生活的私有场地**。同样叫"房间 / 空间"，同样是实物摆放，但一个的默认观众是外人，一个的默认观众只有对方。**所以 MOODA 的"墙/桌容量、房间访问权限、参观许可"整块都不能搬，能搬的只有"实物语言 + 位置记忆 + 长按装饰"这套交互词汇。**

---

## 11. 如果照 MOODA 的思路补耳语，具体动什么（先定产品，再动代码）

1. **补一个"回顾层"。** 现在的三个物件只回答"我要说点什么"，不回答"这一个月我们过得怎么样"。最小可行做法：给已有的瓶子加一个**周期性结算状态**（不是新物件、不是新 tab），只在内容攒够之后出现一次，给一张可保存的实物化结果。**先定门槛与频率，再谈视觉**——MOODA 的门槛是"≥10 篇 + 月末"，我们的对应物应该是"内容数 + 自然周期"，不是推送驱动的每日任务。
2. **节日皮肤改成覆盖层资产。** 在 `DesignAssets/` 里按 `StarCharm_{Style}_{Emotion}` 同画布出 `{Holiday}_Overlay` 图层，运行时叠加，不改现有挂件命名与索引。
3. **字体家族加命名空间。** 在我们的字体分发流程里加一步改名/校验：CDN 文件的 family 与 PostScript 名必须带我们的前缀，避免与系统或用户自带字体冲突；这一步是分发前的硬检查，不是运行时兜底。
4. **容量用实物语言说。** 免费上限规则不改，文案可以更接近实物（MOODA 说"墙上没有足够的空间"，我们说"第 11 条"）。这条要连四种语言一起改，且不能变成解释性副标题。

---

## 附录：证据索引

| 结论 | 证据 |
| --- | --- |
| Catalyst 版、iPad family | `Info.plist` 的 `CFBundleSupportedPlatforms = MacOSX`、`UIDeviceFamily = [2]`；`LC_BUILD_VERSION platform 6 sdk 18.4`；`otool -L` 里全是 `/System/iOSSupport/...` |
| 无 CloudKit | `codesign -d --entitlements` 只有 sandbox / network / photos / aps / applesignin / app group / keychain |
| 服务端为主、本地仅缓存 | `MOODA.mom` 0 实体；`DiaryModel.mom` 只有 `LocalDiary` 7 个字段；`api_endpoints.txt` 101 条 |
| 正文是 HTML 富文本 | 二进制类型名 `HTMLStorage` / `HTMLElementRepresentation` / `ParagraphProperty` / `Figure` / `MOODATextView` / `MOODAStickerInserter` / `MOODAMediaInserter` |
| 情绪球规则 | `mood_ball_condition_1/2`、`mood_ball_view_alert`、`moodball_notification`、`review_tilte`（`localizable_ko.txt` / `localizable_zh-Hans.txt`） |
| 扭蛋机实物形态 | 从 `Assets.car` 里抽出的原始 PDF `roomMoodBall`（300×437）渲染图，见 `research/mooda/art/view/15.png` |
| 房间 frame + mask | `roomMemo_0X_frame/mask`、`roomPhoto{Square,Ver,Horiz}_0X_frame/mask`；抽取出的 PDF 与其尺寸 |
| 墙/桌/笔是颜色 token | `assetutil --info` 中 130 条 `AssetType = Color`（`wallB*`/`tableB*`/`pen*`/`marker*`/`bgC*`） |
| 时段与节日预出图 | `windowA_01_day|night[_xmas][_small]` 共 120 条；`emojiThemeHoliday*`；`themeXmas*.json` |
| 贴纸 600×600 与预览瓦片 | `mooda_001_stic_01_joy` 600×600；`mooda_001_pre_1_1` 141×144 @3x；`_thumb` 72 pt；`_tag` 156 pt |
| 商店服务端驱动 | `polaroidPack_1000` 无本体贴纸，只有预览；`/v1/sales-item/sticker-image`、`/v1/sales-item/pre-image` |
| 字体 50 款 116 MB、widget 再复制一份 | `du -ch Resources/*.otf *.ttf`；`CalendarWidgetExtension.appex` 内容清单；`fonts.txt` 里 family 全是 `*New` |
| `UIAppFonts` 僵尸条目 | `Info.plist` 第 51 条 `03_drfont_daraehand_Basic.ttf` 在包内不存在 |
| 免费版四道限制 | `save_option*`、`free_memo_limit` / `free_photo_limit`、`recent_one_month` / `buy_premium_search` |
| 商品与付费 | `MOODA_Dev_StoreKit.storekit`（candy.30/40/50、premium.month/year）；二进制字符串里的 `io.analoglab.mooda.{candy,premium,attributed}` |
| Dev 配置进包 | 包内同时存在 `GoogleService-Info.plist`（`mooda-4d208`）与 `GoogleService-Info-Dev.plist`（`mooda-f2cb9` / `.dev`） |
| deeplink 硬编码密钥 | 二进制字符串成对出现 `MOODADEEPLINKSECRETKEY__20210403` 与 `DEEPLINKSECRETIV`，配合 `MOODA.CryptoManager` |
| 未发布的 Todo | `RoomTodo/Todo/TodoViewController`、`TodoViewModel`、`ic24Todo`，8 种语言 0 个 todo key |
| key 全对齐 | 7 个 lproj 各 523 key，集合差集为空（逐语言比对） |
| 埋点与归因 | `FirebaseAnalytics.framework`、FBSDK、`GADApplicationIdentifier`、`NSPrivacyTrackingDomains`、42 个 `SKAdNetworkIdentifier` |
| 无物理 | `UIDynamicItem` 仅 4 处引用、无 `UIDynamicAnimator` 实际使用；拖动靠 `RoomBoardGestureRecognizer` + `RoomBoardGridView` + `HapticManager` |

复现方式：全程只读。`assetutil --info Assets.car` 取资产表；`strings` 取符号与 API 路径；`plutil` 读 plist 与 `Localizable.strings`；原始 PDF 用 `Assets.car` 里未压缩的 `%PDF` 段直接抽出（34 张，见 `research/mooda/art/`），再 `sips` 渲染成 PNG。没有第三方依赖，也没有改动原 App。
