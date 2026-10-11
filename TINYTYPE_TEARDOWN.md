# 排版小动物（小红书 Tinytype 2.1.0）全链路拆解

记录日期：2026-09-18
对象：Mac 上已安装的 iOS 包 `/Applications/排版小动物.app/Wrapper/Tinytype.app`（`com.kairuotu.tinytype`，v2.1.0，最低 iOS 18，Xcode 26 构建，235 MB）+ 运行时容器 `~/Library/Containers/com.kairuotu.tinytype/`
素材与提取物：`research/tinytype/paper/`（纸面切片，webp + 转好的 png）、`research/tinytype/strings/`（二进制里抽出的字符串：`logs.txt` 7153 条可读日志、`utf8.txt`、`emoji.txt`）、桌面副本 `~/Desktop/排版小动物素材/`
最重要的一条线索：他们把自己的坑写进了日志（`⚠️ / ⏭️ / ❌ / [诊断]` 前缀），所以这份文档里"踩坑"那一节几乎是他们的原话。

---

## 0. 结论摘要

| 维度 | 判断 |
| --- | --- |
| 身份 | 小红书内部产品（thrift 命名空间 `com.xiaohongshu.sns.tinytype.api`），双端，110+ 模板走 CDN |
| 最强的地方 | **输入方案**：纸能无限加长，写多长都装得下，用户一次也不需要理解页、容量、换纸（长高靠中段切片 **1:1 平铺**，不是拉伸，见 §5） |
| 第二强 | **资源与渲染的工程化**：内容寻址资源、多级短路缓存、渲染队列 + 自愈、管线版本、降级路径遍地 |
| 最弱的地方 | **状态分散在三处**（服务端 `/api/unlocked` + iCloud KV + 本地库），连他们自己的日志都在写"需联系后端清理该账号数据" |
| 对我们的意义 | 可平铺纸面 + 输入方案可以照搬（我们现役三张纸的中段接缝偏大，要按新口径重裁，见 §5.4）；成图上云、模板中台、ASR、埋点不照搬 |

---

## 1. 产品面（功能地图）

从日志、资产名、thrift 与本地库里还原出的完整功能面：

| 模块 | 事实 |
| --- | --- |
| 编辑器 | `DiaryEditorVC`：分组/分页横向滚动（`scrollToPage`、`allGroups`、"点击切组"），首页 Banner 直接 push 进编辑器（`Banner→DiaryEditorVC(首页输入页)`）；另有 `EditTypesettingModelView` 编辑既有卡片 |
| 卡片类型 | 普通 / **寄给未来**（`mailedAt`、`postFuture`、`/api/card/list scene=postOfficeV3`）/ 漂流瓶 / 系统卡 |
| 心情 | `MoodType` 六级，`WeeklyMoodManager` + `/api/mood/list` 周心情面板，`/api/checkin/get` 日历签到，`dailyFeatures` |
| 邮局 / 信件 | `HistoryLetter*` 系列页面；"收信版本/新版编辑器版本"两套场景枚举（`POST_OFFICE_V1/V3`）；`[放弃邮寄] 服务端返回 65206（未来信已寄出），本地直接放弃` |
| 箱子 | `CustomBoxManager`，`mergeCustomBoxes`，游客箱子合并（`fetchAllWithUserIdEmptyOnly`） |
| 打卡 | 习惯挑战（thrift `HabitChallengeCardInfo`），奖励阶段图章，彩带庆祝 |
| 解锁（付费） | `AnimalTemplateFeatureManager`：解锁对象分 **模板**（`templateType`）与 **角色**（`animalName`）；判定由**服务端 `/api/unlocked` 下发**，`/api/unlock` 触发，iCloud KV 缓存标记；编辑器里锁定页会"回退 lastUnlockedDocument" |
| 多图权益 | `hasMultiImagePrivilege` —— **多图是权益，不是必备能力** |
| 密码锁 | KMP 侧 `KmpPasswordLock*` / `KmpSetPasswordVC` |
| 补记 | `retroDate` —— 写日记时可以选过去的日期，`displayTime` 与 `updatedAt` 分离 |
| 桌面小组件 | 每模板**手写死的引导文案**（`laoshifu_templateTwo_wiget_word1..7`），不渲染用户内容 |
| 引导 | `[FirstCardPopup] 登录态但服务端未返回 liangliang1Unlocked=true，跳过弹窗`；`EmbeddedExampleViewController: DiaryEditor 资源预载结束（不阻塞跳转）` |
| 跳转 | deeplink：`tinytype://home`、`tinytype://received_mail?cardId=xxx`、`tinytype://editor?template_type=13`；URL scheme：`com.kairuotu.tinytype` / `.diary` / `.history` |
| 运营入口数据化 | `editor_mail_template.json` 把站内信按钮写成数据（`type/style/image_url/width/height/route`），改运营位不回版本 |
| 语音 | 录音 + ASR（模块 `tinytype_asr`、`transcribe`，**未用 `SFSpeechRecognizer`**，走自家服务） |
| 图片处理 | 小红书图像栈被复用：`FaceBeautyRenderer`、`AIFilter*`、`Lut3D`、`XavHDRView`、`FilterOffsetMapRenderer`，Metal kernel 源码（`texture2d<float, access::read>`、`inputOffset`） |
| 导出 | `UIGraphicsBeginPDFContextToFile`（**能导 PDF**）、成图分享、发布成小红书笔记（`KmpNoteDetail`） |

### 1.1 市场与商业事实（App Store / 官网 / 条款）

| 项 | 事实 |
| --- | --- |
| 主体 | **开若图科技（上海）有限公司**（`artistName` / `sellerName`），官网 `tinytypezoo.com`，联系 `hi@tinytypezoo.com`；而 thrift 命名空间是 `com.xiaohongshu.sns.tinytype`、CDN / 图床 / 图像栈全是小红书的 → **独立主体 + 复用小红书中台** |
| App Store | id `6749688592`，首发 **2025-08-29**，当前 2.1.0（2026-09-12） |
| 价格 | **免费**（CN 与 US 区都是 Free），无订阅 |
| 评分 | CN **4.88 / 43847 条**；US 4.91 / 343 条 |
| 体积 | `fileSizeBytes` **276 MB**（主要是字体 + 图像能力） |
| 分类 | 工具 / 生活，最低 iOS 15.0（当前构建用 iOS 18 SDK） |
| 语言 | `languageCodesISO2A` 只有 `EN`，且元数据是中文（没做多语言 listing）；App 内声明 `zh_CN + en` |
| 迭代节奏 | 2.1.0 的 `releaseNotes`："打卡功能上新…小邮局可以寄信了，寄给未来的自己" |
| 定位 | 自称"**排版事务所**"，**用 8 只小动物把模板人格化**：tsuki = 日系、拉尔夫 = 北欧极简、路易 = 旅行明信片、老师傅 = 老师风格、主任 = 奖状/通知、亮亮 = 千禧年、迈尔斯 = 马拉松式长期主义、kaka = 涂鸦 |
| 玩法 | 记录心情/生活/书摘/随感 → 排版成卡片 → 保存/转发；**把不同动物的卡片收进不同动物的纸箱归档** |
| 条款要点 | **内容默认自动 iCloud 同步**（占用户 iCloud 配额）；生成的排版卡片**不允许商用**（需额外书面许可）；有账号注册/注销体系 |

商业上的关键判断：**他们不靠卖软件赚钱**（免费 + 4.4 万评分 + 小红书内容生态引流 + 可发布成笔记），解锁是登录/邀请/任务触发的权益而非 Apple IAP（商品号在包里找不到，解锁由服务端 `/api/unlock` 下发）。**我们卖 ¥18 买断，走的是完全不同的商业路径。**

---

## 2. 内容模型与数据

服务端 thrift（`card.thrift`，13 KB，被打进线上包）：

```
Card { id, accountId, appVersion, clientCardId, templateType,
       cardTitle, cardContent, cardImages, cardStyle,
       moodType, source, baseCardImage, landscapeCardImage,
       visibleAt, mailedAt, isRead, isPinned, pinnedAt, displayTime }
```

- `cardStyle` = 排版样式（json 字符串），**可独立更新**（`UpdateCardScene.CARD_STYLE = 11`）
- `baseCardImage` / `landscapeCardImage` = **渲染好的成图**（竖版 + 横版两张）

本地库（GRDB，24 次迁移）`TypesettingApp.sqlite`：

```sql
typesetting_models(saveId, title, content, animalType,
  layoutTemplate, style,
  savedURL, savedSmallImgURL, hasOnDemandRenderedWholeImage, renderPipelineVersion,
  cardLockState, imageAttachments, customBoxId, serverBoxId, serverCardId, status,
  moodType, source, visibleAt, mailedAt, displayTime, displayDate, retroDate→displayDate,
  checkinBizType/TaskId/TaskName/BusinessDate, isPinned, pinnedAt, extra,
  updatedAt, lastEditedAt, serverCreatedAt, serverUpdatedAt)

image_attachments(attachmentId, typesettingId, localPath, remoteURL, uploadStatus,
                  width, height, orderIndex, createdAt, uploadedAt, compressedSize)
```

**正文里用占位符标记图片位置**：日志 `正文 [IMG:] 与 imageAttachments 的 key 无交集`、`content有[IMG] + 远程映射可完整还原 -> 下载后 performRenderCardImage`。也就是说纯文本里嵌 `[IMG:<key>]` 令牌，渲染时按 key 查 `imageAttachments` 换链下载再替换。这是他们"文字 + 图片"混排的落地方案，也是我们**不做内联混排**的直接对照。

**双产物**：每张卡渲染出 `Whole`（完整大图）+ `Small`（缩略图），分别落盘（`文件系统 Whole（扫描结果）`、`Small 目录`）、分别写库、分别同步 iCloud。

---

## 3. 同步与后端

`codesign -d --entitlements -` 实测能力：

```
aps-environment                  = production
com.apple.developer.icloud-services = CloudKit, CloudDocuments
icloud-container-identifiers     = iCloud.com.kairuotu.tinytype
application-groups               = group.com.kairuotu.tinytype
```

通道有四条，各司其职：

| 通道 | 用途 | 证据 |
| --- | --- | --- |
| CloudKit（自定义容器） | 卡片 / 箱子的跨设备同步 | `tinytype.icloud.sync`、`.iCloudTypesettingDataDidChange`、`ICloudKVManager` |
| iCloud Key-Value | 小状态（解锁标记等） | `AnimalTemplateFeatureManager 从 iCloud 同步解锁` |
| 自家服务端 | 业务唯一真相（卡片、心情、签到、解锁、邮局） | `edith.xiaohongshu.com`、`/api/card/list`、`/api/mood/list`、`/api/checkin/get`、`/api/unlocked` |
| S3 分块上传 | 图片本体 | `XYUploaderCloudS3+Multipart: 准备完成分块上传 … Complete Multipart Upload` |
| CDN | 模板 / 字体 / 静态资源 | `static.tgccdn.com`、`tinytype-static.tgccdn.com` |
| 长连接 | 推送 / 实时 | `tinytype.longlink.*`、`XYLongLinkService` |
| APNs | 富推送 | `PlugIns/NotificationServiceExtension.appex` |

**同步编排**（`DataSyncOrchestrator`）有三种流程，日志里写得清清楚楚：

```
完整流程：  后台线程，Step1(下载) → [Step1.5(本地卡片) || Step2-5(老数据)] 并行执行
精简流程：  仅 Step1+Step1.5（create/update 接口），未走 syncHistoryData
游客流程：  Step1(下载) → Step1.5(本地卡片上传) → 游客数据上传(Step3~5)
```

**降级分支被显式命名**（这是很值得学的一点，出问题时日志一眼定位）：

```
branch=invalid_saveid_to_icloud  detail=saveId无效，回退 loadViaICloud
branch=db_error_to_icloud        detail=DB查询失败，进入 loadViaICloud
fetchCardFromServerAndRender: serverCardId 为空，降级渲染
fetchCardFromServerAndRender: 未登录，降级渲染
fetchCardFromServerAndRender: 插图不可完整还原且无本地 Whole，等待 iCloud
```

**发布链路的状态机**（`CardPublishCoordinator`）：

- 无图或附件就绪 → 本地保存后立即刷新，iCloud 后台同步
- 有图且附件未就绪 → **跳过立即 iCloud 同步**，等图片上传完成后统一同步
- 发布回调带 `generation`，过期回调直接丢弃：`收到过期发布回调（generation 不匹配），已忽略`、`发布已超时过期（generation 不匹配），丢弃本轮渲染结果`
- 发布成功用通知驱动其他模块：`kDiaryEditorPublishDidSucceed` → `SideMenuView: 清缓存并重新拉取日历签到/心情数据`

**游客态是一个独立维度**：`退出登录 → merged，展示游客数据（DB 000000000 + 老格式文件系统）`、`游客合并: 查询 userId 为空、空字符串或游客默认ID`。

---

## 4. 纸张模板体系

三个 JSON 共 110+ 模板（编辑器 22 / 横版卡片 31 / 系统卡 18 + 变体），全部在 CDN，包内只有索引。

### 4.1 他们其实有三套纸面机制（画廊实测）

| 家族 | 背景字段 | 机制 | 高度 |
| --- | --- | --- | --- |
| **编辑器模板**（22） | `top` / `center` / `bottom` | 三段素材，**中段按原尺寸 1:1 纵向平铺**（不是拉伸，§5） | **无限长** |
| **横版卡片**（31） | `plain` / `low` / `mixed` / `image` | 四张**定高**背景，按内容状态换一张（不拉伸） | **档位**：95 / 124 / 178（如 tsuki-1） |
| **系统卡**（18） | `detail` + `thumbnail` | 两张**定图**（1200×1600 / 480×639） | 固定 |

也就是说，**只有编辑器模板是真正长高无上限的**（靠中段平铺，不是靠拉伸，§5）；横版卡片用的是"有限档位高度 + 状态换图"（`plain` 纯文字 / `low` 少字 / `mixed` 图文混排 / `image` 有图），并且配合 `low_margin_top` 调版。这正好解答了"文字长度不定"的第三种做法：**既不分页也不拉伸，而是分档**。

他们最偷懒的 `default` 模板（编辑器与系统卡各一个）**根本没有素材**（`detail`/`thumbnail` 的 url 为空），靠纯色渲染——所以它是兜底，不是设计。

### 4.2 模板字段

```jsonc
{
  "background": { "top": {...}, "center": {...}, "bottom": {...} },   // 三段切片，见 §5
  "decoration": [ { "key": "default", "url":…, "layout":{t,l,b,r}, "alignment":{vertical,horizontal} } ],
  "content": {
    "layout": { "top": 612, "left": 237, "bottom": 600, "right": 211 },
    "h1": { "font_family":"PFanHuTuTi","font_size":82,"line_height":84,"kerning":0,"color":"#194F25ff" },
    "h2": { "font_family":"JyunsaiKaai","font_size":54,"line_height":76,"kerning":0,"color":"#194F25ff" }
  },
  "date":      [ { "example":"1970$/$01$/$02", "font":{…}, "layout":{…}, "alignment":{…} } ],
  "signature": { "font":{…}, "layout":{…}, "alignment":{…} },
  "image_frame":[ { "id":"1-1", "frame":{url,945×746}, "mask":{url,833×606} } ],
  "locked_overlay": { url, 636×461, alignment: center }
}
```

| 字段 | 说明 | 对照我们 |
| --- | --- | --- |
| `content.layout` 四边 inset | 书写区 | 我们的归一化 `writingRect`（等价） |
| `h1` / `h2` | **两个文本角色**，各自字体/字号/行高/字距/颜色 | 我们只有一套排版参数 |
| `kerning` 可为负 | -5、-4，紧凑排版 | 我们没有 |
| `letter_spacing` | 系统卡模板里有 | 我们没有 |
| `first_baseline_to_top_height` | 系统卡模板里有 | **= 我们的 `lineOriginY`** |
| `stroke_width / stroke_color` | 手写体描边 | 没有 |
| `underline` | 签名可下划线 | 没有 |
| `font_size: 0` | 自适应 | 没有 |
| `date.example` | 日期格式串，占位符 `$…$`：`1970$年$01$月$02$日`、`02$.$Fri.`、`Jan.$02` 等 10 种 | 我们只显示日期，无格式串 |
| 状态化背景 | 横版卡片有 `plain / low / mixed / image` 四变体，**有图就换一张背景** | 我们用 `keepOutZones` 避让 |
| `locked_overlay` / `upgrade_overlay` | 未解锁蒙层 | 我们没有模板级付费 |
| 编辑框 `key` | `decoration.key = "default"` 表示装饰可换变体 | — |

### 4.3 关闭与导航（关闭按钮不在模板里）

模板 JSON 里**没有任何按钮/关闭相关字段**，关闭一律是 UI 控件，浮在内容之上：

| 层级 | 做法 | 证据 |
| --- | --- | --- |
| 页面级 | 系统导航栏返回箭头，`nav_back`@2x 100×100（**Monochrome，自动模板模式，可染色**） | 日志 `Banner→DiaryEditorVC(首页输入页, push动画)`；`navigationItem` |
| 浮层/弹层级 | **可复用关闭组件** `closeButton` + `closeButtonTapped` + **`closeButtonTintColor`**（带颜色参数） | 二进制字符串 |
| 两套素材 | `close_black`@2x 33×30（≈16.5×15pt，纯色可染色，用于浅底）/ `close_white_border`@2x 61×61（≈30.5×30.5pt，ARGB 预设白边，用于深底、照片、动画层） | `Assets.car` 元数据；两者 `SizeOnDisk` 只有 **334 字节** |
| 位置 | 右上角；`close_white_border` 实际出现在"拆包裹"动画弹层上（`诶！收到小动物的新年包裹啦～ close_white_border 诶！盒子里出现了`） | 资产引用上下文 |
| 手势 | **不靠手势关闭**：无 `interactiveDismiss` / 下滑关闭实现（`UIPanGestureRecognizer` 仅 4 处） | 二进制符号计数 |
| 确认层 | 取消编辑会弹确认层：`取消编辑` / `📝 用户选择继续编辑`，按钮还按场景分（`cancel_edit_date_btn` / `cancel_edit_text_btn`） | 字符串 + `cancel_edit` 插画（600×416@2x） |
| 草稿 | 关闭不丢内容：`DiaryEditorVC：保存草稿 groupIndex=` / `草稿恢复完成 content.count=` | 日志 |

对我们的直接意义：**关闭按钮不属于纸张，属于屏幕**；用**两套素材 + tint** 解决"任意背景上的可见性"，而不是给每张纸算避让。这正好替掉我们 r2 里的 `closeButtonAnchor` / `keepOutZones`。

---

## 5. 纸怎么长高：中段 1:1 平铺（核心技术）

> **订正**：本节早先写成"中段纵向拉伸（`resizableImageWithCapInsets` + `stretch`）"，**是错的**。2026-09-20 用正在运行的 App + 逐像素比对重测，真实机制是「中段素材按原尺寸反复平铺」。旧结论的唯一依据是二进制里出现 `resizableImageWithCapInsets:` 这个选择器——它出现在**按字母排序的 ObjC 选择器表**里（邻居是 `resignContent`、`resolution`…），证明不了纸张用它。

### 5.1 做法：三段素材，中段按原尺寸反复平铺

`background` 是**三个独立素材**（CDN 三个 URL、同宽 1200），不是运行时从一张图切的（仅编辑器模板；横版卡片与系统卡见 §4.1）。以**素材实际尺寸**为准：

| 模板 | top | center（= 一块砖） | bottom | 实际合计 | JSON 声明 center |
| --- | --- | --- | --- | --- | --- |
| liangliang-1 | 1200×400 | 1200×**300** | 1200×900 | 1200×1600 | 138（不可信） |
| luis-1 | 1200×736 | 1200×**498** | 1200×366 | 1200×1600 | 336 |
| miles-1 | 1200×690 | 1200×**422** | 1200×488 | 1200×1600 | 260 |
| laoshifu-1 | 1200×638 | 1200×**346** | 1200×454 | 1200×1438 | 346（= 实际） |

合成：**上段、下段各按自然高度画一次；中间的区域由 center 素材按原尺寸反复铺满，不做任何平滑缩放**。纸高随内容变化，最后一块砖被裁到哪都行——砖本身是连续的纸纹。

代码侧：

| 证据 | 内容 |
| --- | --- |
| `DiaryEditorBackgroundView.swift` | `topImageView` / `middleImageView` / `bottomImageView` 三个视图，只有 `topHeightConstraint` / `bottomHeightConstraint`（**没有中段高度约束**：中段由上下两端夹出来，随内容变） |
| 同一个文件 | `DiaryPatternTileView` + `tiledImage` —— 图案平铺视图，中段就是它铺的 |
| 排版卡片是另一套 | 8 个动物的排版卡片走固定 1600 画布 + 文本截断（日志 `Miles标题+内容视图：总高度=1600`、`内容超出最大高度，停止渲染`），不要与编辑器的纸混淆 |

### 5.2 怎么证明是平铺而不是拉伸（App 实测）

在正在运行的编辑器里（当时显示 `liangliang-1`）：绿屏宽 728（2x px）÷ 素材里绿屏宽 974 设计 px ⇒ **0.7474 2x-px/设计 px**（即卡片宽 1200 设计 px = 448pt）。

1. **纹理重复周期 = 砖的真实高度**。拿左侧银色机身做位移自相关，只有一个尖峰：

| 位移 lag（2x px） | 225 | 224 | 226 | 300 | 149 |
| --- | --- | --- | --- | --- | --- |
| 平均行差 /255 | **0.93** | 5.20 | 6.13 | 6.31 | 6.31 |

lag 225（2x px）= **300 设计 px = `liangliang-1_center` 的真实高度**，行差 0.93 —— 同一条切片被**像素级相同地**重复画了很多遍。拉伸不可能造出这种"位移完全相同"的重复。

2. **颗粒尺度没变**。机身银灰颗粒的相邻行差：自然比例的顶部段 4.91，被加长的中段 5.67。真拉伸 5 倍会把它抹平到 ~1。

3. **整卡复现**。自建 `top + 8×center + bottom`、缩到同一尺度后与 App 截图对齐逐像素比：模板错时平均差 108 / 82（`liangliang-2` / `-3`），对上 `liangliang-1` 时降到 9.7；差分图里**所有结构边（机身轮廓、听筒、`TINY TYPE`、信号图标、屏内边框）都是纯黑（零差）**，残留的差只是一层均匀色偏（截图色彩管理），说明结构完全一致。

4. **纸确实比设计稿长得多**。卡片上边缘 y≈242（2x px）、绿屏上沿 y=447 → 设计 y 274，与 `liangliang-1_top` 里绿屏起点 271 对上 ⇒ **上段是按自然高度画的**；被底部面板遮住处已经到设计 y 1790。即中段可见部分就有 **1516 设计 px ≈ 5 块砖**，而设计稿合计只有 1600。

### 5.3 22 个模板的砖逐块实测：砖不需要"平"

砖能不能铺，只看**首尾接缝**与**砖内相邻行差**是否同量级（22 个 `editor__tN__center` 全测）：

| 模板 | 砖高 | 砖内相邻行差 | 首尾接缝 | 结论 |
| --- | --- | --- | --- | --- |
| laoshifu-1（t7） | 346 | 3.67 | 4.23 | **砖里有纹理，照样铺** |
| laoshifu-2（t8） | 506 | 2.53 | 8.06 | 最差的一个，仍然能用 |
| liangliang-1（t11） | 300 | 0.86 | 1.65 | — |
| miles-1（t16） | 422 | 0.90 | 3.06 | — |
| fallback（t0） | 910 | 0.00 | 0.00 | 纯色 |

22 个模板的接缝都在 0–8/255，与砖内噪声同量级。**所以旧结论"中段必须平"是错的**：`laoshifu-1` 的砖内有 3.67/255 的纹理，拉伸必糊，平铺毫无问题。约束是"**这块砖首尾接得上**"，不是"平"。

### 5.3.1 带图案的砖：周期整除是设计签名（2026-09-20 复测）

22 个中段里有 5 个是**周期图案**（行特征自相关 + 峰间距双测）：

| 模板 | 砖高 | 图案 | 水平周期 | 垂直周期 | 砖高 ÷ 周期 |
| --- | --- | --- | --- | --- | --- |
| rolf-1（t9） | 940 | 点阵（蓝） | 85.4 | 85.3 | **11.06** |
| rolf-2（t10） | 842 | 方格（红） | 105.0 | 105.0 | **8.02** |
| tsuki-4（t4） | 1020 | 点线横格 | — | 113 | **9.03** |
| kaka-1（t31） | 637 | 横格 | — | 105.8 | **6.01** |
| kaka-2（t32） | 617 | 方格（绿） | ≈87 | ≈87 | 7.09 |

**前四个的砖高几乎正好是图案周期的整数倍**（残差 ≤ 2 px，铺开后肉眼不可见），kaka-2 是唯一一个没对齐的（7 格 = 609，砖高 617，接缝处会错 8 px）。图案本身在源素材里是**正方形周期**（rolf-1 = 85×85，rolf-2 = 105×105）——这就是"反复铺"的设计签名：

- 如果允许纵向缩放，砖高没有任何理由对齐周期；
- 更要命的是，真按内容长度纵向拉伸，一张日记少说要 2–4 倍，格子立刻变成 105×300 的长方形——**"正方形都拉成长方形了"，一眼就是废稿**。平铺多少次都还是正方形，缩放一次就不是。

所以这两张纸（点阵 / 方格）恰好是"拉伸说"最过不去的反例：**不是图案纸容忍不了拉伸，而是它们一开始就是按"一块砖反复铺"来画的**——周期是正方形的、砖高按周期整数倍裁。

坑：JSON 声明的 center 高度是**布局参考值，不是素材高度**——22 个模板里 19 个中段实际比声明多 **162 px**（合计 1600），另 3 个（`laoshifu-1`、`kaka-1`、`kaka-2`）中段声明 = 实际。（`kaka-1` 连下段素材也换过：声明 253 / 实际 760，三段实际合计 1945。）**一律以素材为准。**

### 5.4 我们的三张纸按新口径重测：现在的切线不能用

现役运行时资产（`BetweenUs/Assets.xcassets/Paper0X.imageset`）按注册的 `top/center/bottom` 取中段，实测：

| 纸 | 注册 top/center/bottom | 砖内相邻行差 | **首尾接缝** | 判定 |
| --- | --- | --- | --- | --- |
| Paper01 | 501 / 723 / 306 | 2.67 | **15.04** | 接缝可见，不能直接铺 |
| Paper04 | 340 / 1020 / 344 | 2.27 | **11.60** | 同上 |
| Paper06 | 500 / 650 / 548 | 6.25 | **13.76** | 同上 |

旧切点是按"拉伸要平"选的（找最平的窗口），对平铺没用。这三张的中段是**随机纤维纸纹**（没有周期可用），所以要么裁出一个首尾行差 ≤ 砖内噪声量级的窗口，要么对砖的首尾几十像素做交叉淡化，要么整块砖纵向镜像——具体配方见 §14；耳语侧的落地口径见 `PAPER_DESIGN.md` §3.3 / §9.5。

---

## 6. 渲染管线

导入符号（`nm -u`）：

```
_CTFramesetterCreateWithAttributedString / CreateFrame / SuggestFrameSizeWithConstraints
_CTLineGetGlyphRuns / _CTLineGetStringRange
_CTRunGetPositions / GetAdvances / GetTypographicBounds / GetGlyphCount
_UIGraphicsImageRenderer / BeginImageContextWithOptions / GetCurrentContext
_UIGraphicsBeginPDFContextToFile / BeginPDFPageWithInfo / EndPDFContext
```

- **排版 = CoreText**（CTFramesetter 定框 + CTRun 逐字位置），逐字取位置/步进说明按字/行手动绘制
- **出图 = CoreGraphics**，还能**导 PDF**
- 渲染器类名：`CardImageRenderer`、`TextRenderer`、`DiaryShortImageRenderer`、`TemplateBackground`

**渲染队列与并发**（日志原文）：

```
🎨 CardDataProvider: 启动渲染任务（当前并发: N）
⏳ CardDataProvider: 渲染队列已满（当前并发: N），加入等待队列（队列: M）
⚠️ CardDataProvider: 等待队列已满（M）
   - 策略：拒绝新任务，让用户稍后重试（通过页面切换触发）
🔄 CardDataProvider: 从等待队列取出任务（剩余队列: …，当前并发: …）
🛑 CardDataProvider: 已取消任务
```

**自愈与防覆盖**（每一条都是踩过的坑）：

```
⏭️ 渲染已落盘但插图未完整可还原，跳过 renderPipelineVersion 打戳（保持 …，可再次自愈）
⏭️ Whole 已存在但插图未全部本地就绪，跳过覆盖保存
⏭️ Whole 扩展名非 jpg/png，跳过重编码
🛡️ 跳过过期 generation 的 savedURL 写入
🛡️ server-owned 图片缓存回退已阻断
插图不可完整还原且 Whole 可读 -> loadLocalFileAndCacheForDB（禁止覆盖原图）
🔄 数据库 savedURL 为空，按需渲染（可能为别设备编辑数据）
🔄 索引 N Whole 存在但未标记 hasOnDemandRenderedWholeImage，日记卡继续按需渲染
Whole 不存在，强制重新渲染
✅ Whole JPEG 4:4:4 重编码成功（保留原图像素，不依赖插图源）
✅ Whole 已是 PNG，跳过重编码，仅打管线版本戳
```

**四级短路**（渲染前的快路径，日志按顺序出现）：

```
1. item.availableImage 已有内存图        → 不调渲染与 CDN
2. hasOnDemandRenderedWholeImage 且本地 Whole 存在 → 直接读盘
3. imageAttachments 齐全但缺文件          → 只下载缺的那几张
4. 都不行                                → performRenderCardImage
```

---

## 7. 字体

### 7.1 清单与落地

`resource_download.json` 声明 **25 款**，容器实测落盘：

```
Library/Application Support/Fonts/
  b3483ec650bba4a4416d39c4d6030a99.ttf   ← 文件名 = 文件 md5（内容寻址）
  65ca26788518709fb795115930783dc3.woff  ← 与包内兜底同 md5，命中即跳过
  …共 15 个已下载
```

| 字段 | 值 |
| --- | --- |
| `path_iOS` / `path_Android` | `Library/Application Support/Fonts` / `files/fonts` |
| `platform` | iOS 9 / Android 9 / all 7 |
| `url` / `md5` | CDN + 校验 |
| `extra.familyName` | 引用键，如 `DanMingA.woff → DYmingA` |

模板写 `"font_family": "DYmingA"`，**引用的是家族名而不是文件名**。格式：woff 9 / ttf 6 / otf 1。包内 3 款兜底共约 50 MB（小赖 24 MB ttf、丹明A 15 MB woff、`AaZTGJWWTjf` 12 MB woff）。收录里有我们规划中的**汇文明朝体**与**小赖**。

### 7.2 woff 怎么被 CoreText 吃下去

导入符号 `_CGFontCreateWithDataProvider` + `_CTFontManagerRegisterGraphicsFont` + `_CTFontManagerRegisterFontsForURL`，字符串里有 `woff`、`inflate`。流程：下载 woff → zlib inflate 出 sfnt → `CGFontCreateWithDataProvider` → 注册。

**对我们的价值：woff 是 zlib 压缩的 sfnt，比 ttf 小 40–50%**。我们 CDN 计划的 230 MB 可压到 ~130 MB，内置霞鹜文楷 24.4 MB ttf 可压到 ~12 MB。

### 7.3 字体这块踩过的坑（原话）

```
FontInstaller: fonts.zip 已移除，字体由动态下载提供，跳过解压        ← 早期方案：内置 zip 解压
FontInstaller.registerDynamicFontsIfNeeded: 开始扫描动态字体目录     ← 现在：每次启动扫描目录
[字体诊断] DYmingA 未注册，降级为系统字体（覆盖安装时可能因 rename 导致注册失效）  ← 真实坑
[KmpFont] Bundle 中缺少 XiaoLaiZiTiPSC.ttf，回退系统字体
[DiaryEditor] viewDidLoad: isFontsReady=false，等待字体就绪通知
[DiaryEditor] viewDidLoad: isFontsReady=true，字体已就绪，补刷模板字体   ← 就绪后补刷
[AppDelegate] 主线程：发送 resourceFontAllReady 通知
个已缓存模版，修正此前的系统兜底字体                                  ← 字体到位后修正兜底
下载完成，清除字体缓存 / 字体缓存已清理
```

教训：**字体是异步资源，"先渲染后补刷"必须显式处理**；覆盖安装会导致注册失效，所以他们用 md5 命名 + 启动扫描。

---

## 8. 动画

四套机制并存，按场景各用：

| 机制 | 用在哪儿 | 证据 |
| --- | --- | --- |
| **Lottie** | 彩带庆祝、心情选择器 | `HabitCaidaiCelebration: 未能加载彩带 Lottie 资源`、`DiaryMoodPickerView: 未能加载 Lottie 资源`、`已将 Lottie 容器添加到 overlayBoxView`、包内 `a.json`/`b.json`/`daka_*_caidai_data.json` |
| **PAG（libpag）** | AE 导出的模板/效果动画 | `Frameworks/libpag.framework`，是链接的系统框架之外唯一的动效框架 |
| **APNG** | 编辑器里的入箱/散开等一次性动画 | `APNGPreloadManager`、`DiaryEditorVC：开始执行入箱动画`、`短图已掉入箱中，等待 APNG 动画结束`、`❌❌ 选中的模板图片尺寸无效，跳过散开动画` |
| **WebP 动画** | 轻量替代 APNG | `✅ 已配置原生 WebP 动画支持 (iOS 14+)`、`card_save APNG未预加载，使用系统API动态加载` |

**预载与内存保护**：

```
APNGPreloadManager: 当前内存占用 …
APNGPreloadManager: 内存压力过高，停止预加载剩余自定义APNG    ← 内存压力下的主动放弃
card_save APNG未预加载，使用系统API动态加载                   ← 未预载时的降级路径
✅ card_save APNG系统API加载成功 / ❌ card_save APNG系统API加载失败
✅ EmbeddedExampleViewController: DiaryEditor 资源预载结束（不阻塞跳转）   ← 预载不阻塞导航
```

**动画与布局的耦合点**：`DiaryEditorVC：scaledImageHeight 无效，跳过动画` / `短图尺寸无效，跳过动画` —— 动画依赖上一帧算出的尺寸，尺寸无效就整段跳过。

---

## 9. 美术资产：规划与加载

### 9.1 边界：什么进包，什么走 CDN

| 位置 | 内容 | 量级 |
| --- | --- | --- |
| 包内 `Assets.car` | **只有 UI 控件**：按钮、图标、对齐/字体/字号控件、情绪"饼"（`dairy_two_bing_kaixin/qifen/...`）、角色选择（`animalselection_*`）、解锁 banner | 331 个资产 |
| 包内散文件 | 3 款兜底字体、模板索引 JSON、动物心情矩阵 `animal_felling.json`、模板预览 webp（`template_preview_{tsuki,luis,laoshifu,rolf,liangliang,zhuren,miles}.webp`）、加载图（`animal_loading_tip.png`、`post_loading_top.png`）、花纹（`animal_paten.png`） | — |
| CDN | **全部纸面 / 装饰 / 相框 / 蒙层 / 模板预览 / 字体** | 每张纸 3 张切片 + 装饰若干 |

也就是说：**纸和装饰一件都不进包**，包内只留"没有资源也要能跑起来"的骨架。

### 9.2 命名与寻址规范

| 规范 | 例子 | 好处 |
| --- | --- | --- |
| 资产名带设计尺寸前缀 | `300_196_letter`、`300_208_double_bg`、`1200_...` | 一眼知道素材的设计尺寸与用途 |
| 内容寻址（md5 文件名） | `b3483ec6…ff.ttf` | 天然去重、天然校验、换源不破坏缓存 |
| CDN 资源 ID 无扩展名 | `static.tgccdn.com/tinytype/editor/4613527f…162166` | 统一路径、由 JSON 声明宽高 |
| 模板按类型编号 | `template_type: 16` = miles-1 | 与 thrift 枚举一一对应，跨端一致 |
| 情绪按角色 × 情绪两级 | `animal_felling.json`：8 角色 × 6 情绪各一张 url | **与我们的 `StarCharm_{Style}_{Emotion}` 同构** |
| 资源清单集中声明 | `resource_download.json`（字体 25 条，含 path/platform/md5/familyName） | 加资源不改代码 |
| **扩展用字体子集** | 小组件里是一个 **27 KB** 的 `DanMingAWiget.ttf`，而不是 15 MB 完整版 | 扩展只打它要用的字，包体几乎不增 |
| App Intents 元数据 | `PlugIns/TinytypeWidgetExtension.appex/Metadata.appintents` | 小组件可配置 |

### 9.3 加载与缓存分层

```
L0 内存图      item.availableImage / SimpleImageManager / EditImageManager（编辑器独立）
L1 磁盘成图    Whole（完整）+ Small（缩略图），分目录，落盘文件名与库字段对应
L2 附件本地    imageAttachments[].localPath / uploadStatus / orderIndex
L3 CDN         fileId → URL 批量换链（batchQueryImgUrlByFileId）→ 下载 → 渲染
```

- **fileId 换链**是必须的：`ImageCDNDownloader → 将 fileId 换链并下载`，因为下载地址会过期；换来换去还要 `批量` 查询（`batchQueryImgUrlByFileId 成功，返回 URL 条数=`）
- **预载**：`StoragePreloadManager`（箱子数据）、`APNGPreloadManager`（动效）、`个模版已存在，无需预加载`（模板缓存 `tinytype.shorttemplate.cache`）、`⏰ 开始预加载同步（延后…）`
- **清理**：`🗑️ 清缓清单 = CardDataProvider / StorageDataSource / StoragePreloadManager / 图片缓存`，触发时机是**进入后台**、**内存警告**、**账号切换**、**手动强制刷新**
- **资源下载器**：`ResourceDownloadManager` 双源（Bundle 配置 + 远端配置）+ 退避重试，且**队列清了但还有任务在退避时不发完成通知**（`⏳ 队列暂时清空，但仍有任务在退避重试中，暂不发出完成通知`）

### 9.4 CDN 路径与命名规范

模板里共 330 个不同 URL，分布：

| 主机 + 路径 | 数量 | 形态 | 用途 |
| --- | --- | --- | --- |
| `tinytype-static.tgccdn.com/tinytype/static/` | 143 | 多为 `.webp` | 静态素材（角色、贴纸、蒙层、花纹） |
| `static.tgccdn.com/tinytype/editor/` | 80 | **无扩展名**（hash id） | 编辑器模板的纸面 / 装饰 / 相框 |
| `tinytype-static.tgccdn.com/tinytype/template/` | 51 | 无扩展名 | 横版卡片背景 |
| `static.tgccdn.com/tinytype/static/` | 25 | 无扩展名 | 同上 |
| `static.tgccdn.com/tinytype/template/` | 19 | 无扩展名 | 同上 |
| `static.tgccdn.com/tinytype/diary/` | 12 | 无扩展名 | 日记本模板配色 |

要点：**资源 ID 不带扩展名**（靠 Content-Type 返回 WebP）；宽高与用途由 JSON 声明；只有静态素材直接写 `.webp`。两个主机分工：`static.` 放模板与编辑器资源，`tinytype-static.` 放静态素材。

### 9.5 资产这块踩过的坑（原话）

```
缓存为空！这是重启后图片不显示的主要原因
解决方案：需要在显示编辑页面前，从数据库加载图片到缓存
收到内存警告，清理存储预加载缓存
图片缓存加载期间账号变化，按当前上下文重试一次
刷新缓存期间账号可见性变化，丢弃旧结果
整图预加载期间账号可见性变化，丢弃旧缓存结果
StoragePreloadManager 箱子数据收集超时，使用已收集到的部分数据兜底渲染
ThumbnailGetter 实例数已达上限，且无法释放更多实例 (withEffect=%d)
```

---

## 10. 性能工程

| 手法 | 证据 |
| --- | --- |
| 关键路径埋点（耗时） | `📊 [getCards] 数据库查询完成，耗时:`、`自定义箱子查询完成，耗时:`、`文件检查完成（N 目录），总耗时:`、`ProcessGlobalService 处理失败, ret=%d, 耗时=%lldms` |
| 并发闸门 + 等待队列 + 拒绝策略 | 渲染队列（§6） |
| 多级短路 | 内存图 → 磁盘 Whole → 只补缺图 → 渲染（§6） |
| 主线程保护 | `generateShortTemplateImageOnMainThread 在非主线程调用，强制切换到主线程` |
| 后台线程边界明确 | `[AppDelegate] 后台线程：installIfNeeded`、`[AppDelegate] 主线程：registerDynamicFontsIfNeeded`、`[DataSyncOrchestrator] 后台线程`、`[LocalCardUploadManager] 后台线程` |
| 预载不阻塞导航 | `DiaryEditor 资源预载结束（不阻塞跳转）` |
| 内存压力降级 | `APNGPreloadManager: 内存压力过高，停止预加载剩余自定义APNG`、`ThumbnailGetter 实例数已达上限` |
| 图片格式选择 | `Whole JPEG 4:4:4`（无色度抽样，保清晰）、PNG 不动 |
| 陈旧结果丢弃 | generation / 账号可见性变化时丢弃缓存与渲染结果 |

---

## 11. 踩坑清单（他们的防护 = 我们的清单）

| # | 现象 | 他们的防护 | 我们要注意 |
| --- | --- | --- | --- |
| 1 | 重启后图片不显示（缓存空） | 显示编辑页前先从数据库把图片灌进缓存 | 查看/编辑两态都要预热 |
| 2 | 覆盖安装后字体注册失效 | 字体用 md5 命名 + 启动扫描动态目录 + 未注册降级系统字体 | 字体注册必须每次启动重扫 |
| 3 | 字体异步就绪导致模板用错字体 | `isFontsReady` 通知 + 就绪后补刷模板字体 | 与我们的"字体缺失兜底 + 就绪重排"同题 |
| 4 | 插图未下载完就渲染，结果不可还原 | 不打 `renderPipelineVersion` 戳，下次重渲**自愈** | 渲染/分页结果要不要落盘，看这条 |
| 5 | 旧 Whole 覆盖新图 | `Whole 已存在但插图未全部就绪，跳过覆盖保存`、`禁止覆盖原图` | 本地缓存回写要有守卫 |
| 6 | 服务端图被本地缓存回退覆盖 | `server-owned 图片缓存回退已阻断` | 远端数据不可被本地旧数据覆盖 |
| 7 | 过期任务回写覆盖新结果 | `跳过过期 generation 的 savedURL 写入` | 异步任务全部带 generation |
| 8 | 别设备编辑后本地成图为空 | `savedURL 为空，按需渲染（可能为别设备编辑数据）` | 双人空间必然遇到 |
| 9 | 渲染并发把内存打爆 | 并发闸门 + 等待队列 + 满则拒绝并让用户切页重试 | 一次只渲染一个物件 |
| 10 | 缩略图生成器实例泄漏 | 实例数上限，到上限停止申请 | — |
| 11 | 下载 URL 过期 | fileId → URL 批量换链 | 我们不引第三方 CDN，但同理 |
| 12 | 账号切换打乱缓存 | 账号可见性变化时丢弃旧结果并按新上下文重试 | 双人空间切换/退出要有同样守卫 |
| 13 | 非 jpg/png 的 Whole 被误重编码 | 扩展名判断后跳过 | — |
| 14 | 解锁状态三处并存难收敛 | 服务端 `/api/unlocked` 为准 + iCloud KV 缓存 + 日志里写排查步骤 | **教训**：权益状态只能有一处真相 |
| 15 | 老数据格式与新结构共存 | 游客态 `DB 000000000 + 老格式文件系统`、`migrateLegacyFontsIfNeeded` | 我们的 legacy 派生同题 |
| 16 | 字体包方案向动态下载迁移 | `FontInstaller: fonts.zip 已移除，字体由动态下载提供，跳过解压` | 我们直接从动态下载起步，别做 zip |
| 17 | 模板 JSON 解析失败导致编辑器空白 | `DiaryEditorVC: allGroups is empty — editor_template.json 可能解析失败或缺失`、`setViewControllers 前检查失败，currentTemplates 为空` | 规格表解析失败要有兜底纸 |
| 18 | 展示尺寸声明不可信 | 模板声明 center 高 138 / 实际 300（§5.2） | 比例只以运行时切图为准 |
| 19 | 模板资源版本与包内 JSON 漂 | 同上 | 规格与素材要同源发布 |
| 20 | 图片存储目录取不到 | `ImprovedImageStorageManager: 无法获取 Documents 目录，降级使用临时目录` | — |
| 21 | **`updatedAt` 语义混乱，连修三次** | 24 次 GRDB 迁移里有 `v1_9_repair_updated_at_from_server_created`、`v1_10_repair_updated_at_again`、`v1_11_repair_all_updated_at` | 我们一开始就要分清 `createdAt / updatedAt / openedAt / displayTime / serverCreatedAt` 各自用途，否则要全量迁移修数据 |
| 22 | 渲染管线版本是后补的 | `render_pipeline_version` 在 **v1_17** 才加（自愈机制之前不存在） | 渲染/分页一旦落盘，版本戳要从第一天就在 |
| 23 | 模板与用户样式是两期做的 | `v1_15` 同批加 `server_template_type` + `style` | 我们一开始就把“纸”与“用户可调排版”拆成两个字段，就不用回头改表 |

迁移动线（24 条记录的先后就是他们的功能迭代顺序）：

```
typesetting 表 → 索引 → last_edited_at → 附件表 → custom_box_id → user_id
→ 服务端卡字段 → server_box_id → 时间字段修复×3 → display_date
→ has_on_demand_rendered → display_time → server_template_type + style
→ mood_type → render_pipeline_version → pinned → card_lock_state
→ checkin 字段 → source + visible_at → mailed_at
```

---

## 12. 输入方案（他们最强的地方）

| 输入项 | 行为 |
| --- | --- |
| 正文 | 一条连续文本流，模板给字体/字号/行高默认值，**没有分页、没有页数、没有容量** |
| 排版开关 | 只有三个：对齐（`editor_alinment_*`）、字体（`editor_font_Aa`）、字号（`editor_font_large`） |
| 文本角色 | `h1` / `h2` 两套模板默认样式 |
| 日期 | **自动生成**，格式由模板的 `example` 串决定（10 种） |
| 签名 | 可选，位置与字体模板给 |
| 图片 | 槽位 + 相框/遮罩；正文里用 `[IMG:key]` 占位；**多图是权益**（`hasMultiImagePrivilege`） |
| 语音 | 录音 + 自家 ASR（`tinytype_asr`），可转文字 |
| 补记 | `retroDate` 可选过去日期 |
| 换风格 | 换模板；用户改过的排版存进 `style`，随卡片同步 |
| 保存 | 出图（Whole + Small）→ 上传 S3 → 同步服务端/CloudKit；伴入箱动画 |

**低摩擦的本质不是功能少，而是"纸不会拒绝你写"**：写多长都装得下。我们 r2 里那套最贵的东西（容器链分页、翻页手势、叠纸、容量上限、换纸出口）在他们那里被"**中段一块砖反复平铺**"整体消掉了。

---

## 13. 能拿 / 不能拿

### 值得拿（10 条）

1. **可平铺纸面**：长高靠"中段一块砖 1:1 反复平铺"，砖不需要平，只需要**首尾接得上**（§5.3）；我们现役三张纸的中段接缝 11.6–15.0/255，必须按新口径重裁（§5.4）。
2. **输入方案改成"纸不会拒绝你写"**：删掉分页/翻页/叠纸/容量上限/换纸出口，只留"纸能长多高"。
3. **字体清单数据化**（url / md5 / platform / familyName）+ **md5 文件名** + **内置兜底与远端同 md5**。
4. **woff + 自己 inflate 注册**：字体体积砍 40–50%。
5. **补字段**：`letterSpacing`、负 `kerning`、`strokeWidth/strokeColor`、日期格式串、`font_size: 0`。
6. **失败路径的显式命名**（`branch=db_error_to_icloud`、`降级渲染`、`跳过…`）：我们出问题时能一眼定位。
7. **三级降级与自愈思路**：不完整的结果不打版本戳、留着下次自愈。
8. **并发闸门 + 等待队列 + 满则拒绝**：对象件渲染/物理同样适用。
9. **资源与页面的解耦**：纸/装饰不进包，包内只留骨架。
10. **多备一张背景变体**代替避让计算（他们 `plain/low/mixed/image`）。

### 不能拿（7 条）

1. **图片当槽位/相框**：我们的照片是内容主体。
2. **模板 CDN 热更 + 模板 × 角色 × 语言 的组合中台**：我们没有人扛。
3. **卡片渲染成图片上云**：我们无服务端，且内容要能重排（换字体/改规则）。
4. **语音 ASR 走服务端**：违背隐私优先。
5. **模板级付费墙 + 权益三处并存**：我们的付费是空间一次买断，且状态只能有一处真相。
6. **埋点与广告归因**（Firebase + Crashlytics + SolarEngine + Umeng + AdServices/ATT）：AGENTS 明确禁止。
7. **小红书图像栈**（美颜、LUT 滤镜、HDR）：与我们的产品无关。

### 一条必须承认的分歧

他们的纸**能无限加长**，我们的纸是**屏幕上的实物**。他们能在 feed 里滚动，我们不能——在屏幕内，纸的高是有限的，内容容量天然有限。所以「中段平铺」只能解决"中等长度"，**超长内容仍然需要一个决定**：限长，还是缩字。这点见 §14。

---

## 14. 如果耳语改成"纸能长高"：具体配方

1. 每张纸在 `DesignAssets/paper/` 出三张源图（top / center / bottom），画布等宽 1200，**三段高度之和 = 原画布高**（他们的 1600 就是原画布高）。
2. **中段的唯一约束是"这块砖首尾接得上"**（首尾行差 ≤ 砖内相邻行差量级，§5.3）：
   - 有周期图案（虚线、条纹、格线）→ 砖高取**周期的整数倍**，接缝自动为零，而且拉到任意长都不会变形；
   - 随机纸纹（我们现在这三张）→ 裁一个接缝够小的窗口，或对砖的首尾几十像素做交叉淡化，或整块砖纵向镜像；
   - 旧口径"中段必须平"作废。
3. 切点由实测决定，且**不与装饰重叠**（装饰一律落在上/下段，段结构本身就是避让区）。
4. 合成：**上段、下段按自然高各画一次；中段区域用 center 原尺寸平铺填满，不做平滑缩放**。实现走 `UIColor(patternImage:)` / pattern 图层；也可以用 `resizableImageWithCapInsets(_:resizingMode: .tile)`，但左右 inset 为 0 时横向也会平铺，要么给左右留 inset，要么保证视图宽 = 切片宽。
5. `PaperSheetSpec`：`top` / `bottom` 固定；中段从"自然高"变成"**一块砖的高度**"。纸高 = `top + max(砖高, 内容高) + bottom`——砖高只决定内容区的**最小**高度，不再是"能拉多长"的上限。
6. 纸高上限仍要定：耳语的纸是屏幕上的实物，取 **屏高 × 0.86**（查看时整张纸要在屏内，否则要么缩放要么滚动，两个都不接受）。
7. 因此**容量仍存在，但退化成一个数**：纸上能写多少字 = （屏高上限 − 上下段）÷ 行距 × 每行字数。写满就停，不翻页。
8. 需要保留的能力：`keepOutZones`、`closeAnchor`、媒体流（媒体仍与纸张无关）。
9. 代价：`paperID` 冻结的意义减弱（同一张纸渲染出不同高度）、叠纸视觉失去意义、翻页仪式感整块消失。**先定这个，再动代码。**

估算（402pt 屏宽、纸宽 0.8、17pt 中文、行距 28pt）：屏内上限约 750pt，减上下装饰段后内容区约 480pt → **约 17 行 × 14 字 ≈ 240 字**；纸在自然高度时约 130 字。也就是说现有的 4000 字上限必须下调到与纸匹配的量级，同时创作端"剩余 N 字"要换成"纸快写满了"。

---

## 15. 模块地图（从队列名与类名还原）

**原生侧派发队列 / 模块（`tinytype.*`，二进制字符串）**

```
tinytype.card.render          卡片渲染队列（并发闸门）
tinytype.card.filecleanup     成图文件清理
tinytype.image.resize         上传前压缩
tinytype.localcardupload      本地卡片上传
tinytype.apng.preload         APNG 预载
tinytype.storage.preload      存储预载（箱子数据）
tinytype.shorttemplate.cache  短模板缓存
tinytype.icloud.sync           iCloud 同步
tinytype.icloud.status        iCloud 环境探测
tinytype.custombox.icloud.sync 箱子同步
tinytype.sync.orchestrator     同步编排
tinytype.longlink(*.callback / *.client.queue / *.dns.callback)  长连接
tinytype.networkmonitor       网络监控
tinytype.logger.remote        远程日志
tinytype.launchlogin.manager  启动登录
tinytype.boxcardrelation.database / tinytype.custombox.database  两类本地库
tinytype.animal / tinytype.diary / tinytype.history / tinytype.custom  业务域
tinytype.array                工具
```

**跨端共享层（`TinyCmpShared.framework` = Compose Multiplatform + Skia）**

```
KmpCard / KmpCardLock(+Controller) / KmpNoteDetail(+Controller)
KmpDatabase(+ServiceImpl) / KmpDownloadServiceImpl / KmpNetworkServiceImpl / KmpAccountServiceImpl
KmpFont / KmpEvent / KmpInit
KmpPasswordLockVC / View / Observable / KmpSetPasswordVC
KmpDebugVC / KmpDebugActionButton        ← 调试入口也进了发布包
```

**关键原生类**：`CardImageRenderer` / `TextRenderer` / `CardDataProvider` / `CardPublishCoordinator` / `DataSyncOrchestrator` / `ResourceDownloadManager` / `FontInstaller` / `AnimalTemplateFeatureManager` / `ImageCDNDownloader` / `StoragePreloadManager` / `ThumbnailGetter` / `SimpleImageManager` / `EditImageManager` / `SystemCardManager` / `CustomBoxManager` / `DiaryEditorVC` / `BannerMainVC` / `SideMenuView` / `HistoryLetter*` / `WeeklyMoodManager` / `CalendarSessionManager`。

**链接的系统框架**（`otool -L`）：`UIKit` / `SwiftUI` / `Combine` / `QuartzCore` / `CoreText` / `CoreGraphics` / `ImageIO` / `AVFoundation` / `VideoToolbox` / `Speech` / `CoreMotion`；三方：`libpag` / `TinyCmpShared` / `FirebaseAnalytics` / `GoogleAppMeasurement` / `SolarEngine`。

---

## 16. 商业与获客对照

| 维度 | 排版小动物 | 耳语 | 判断 |
| --- | --- | --- | --- |
| 收费 | 免费 + 权益解锁（登录 / 邀请 / 任务触发） | ¥18 / US$2.99 一次买断 | 两条路。他们用免费换规模，我们用买断换收入 |
| 引流 | 小红书内容生态（可发布成笔记）+ 邀请 banner | 无平台可借 | 我们的获客只能靠商店与内容，定价要自洽 |
| 留存手段 | 打卡 + 心情周报 + 日历签到 + 寄给未来 | 三个物件 + 主动打开的仪式 | 他们靠习惯养成，我们靠关系。**不要学打卡** |
| 情感包装 | 8 只动物承担模板的人格与叙事 | 三个物件承担情绪的分流 | 同一种手法：**让载体有人格**。这是我们做对的地方 |
| 归档 | 纸箱（按动物分类收藏） | 我的抽屉 | 都有。我们的抽屉还带打开状态 |
| 规模 | 4.4 万评分、276 MB、免费 | 未发布 | 他们验证了“写下来 + 排版成实物感的卡片”有大受众 |

最值得记的一条：**他们证明了“纸 + 字排版 + 手写字体”这个方向本身有市场**（4.88 分、4.4 万评分、上架一年），而不是只有我们觉得好看。差别在商业与关系模型，不在纸张技术。

---

## 附录：证据索引与复现方式

| 结论 | 证据 |
| --- | --- |
| 小红书内部产品 | `card.thrift` 首行 `namespace java com.xiaohongshu.sns.tinytype.thrift.api`；内部文档链接；`edith.xiaohongshu.com` |
| 三段素材 + 中段平铺 | `editor_template.json` 的 `background.{top,center,bottom}`（三个独立 URL）；22 个模板实际合计 19 个是 1600、3 个是 1438；声明 center 与实际可差 162 px（§5.1、§5.3） |
| 平铺而非拉伸 | App 编辑器实测纹理位移重复周期 = center 素材真实高度（225 2x-px = 300 设计 px，行差 0.93 vs 其他位移 5–7）；`DiaryEditorBackgroundView` 的 top/middle/bottomImageView + `DiaryPatternTileView.tiledImage`（§5.2） |
| 图案砖的周期与砖高 | 22 个 `editor__tN__center.webp`：逐行墨量峰值间距 + 行特征自相关双测周期（rolf-1 85、rolf-2 105、tsuki-4 113、kaka-1 106、kaka-2 87），再比砖高（§5.3.1）；结果与 CDN 素材尺寸一一对上 |
| 整卡复现验证 | 自建 `top + 8×center + bottom` 与 App 截图对齐逐像素比：模板错时平均差 108 / 82，对时 9.7，差分图所有结构边零差（§5.2） |
| CoreText 渲染 + PDF | `nm -u Tinytype` 中的 `_CTFramesetter*` / `_CTRun*` / `_UIGraphics*` / `_UIGraphicsBeginPDFContextToFile` |
| woff 自解压注册 | `_CGFontCreateWithDataProvider` + `_CTFontManagerRegisterGraphicsFont` + `woff` / `inflate` |
| 字体 md5 寻址 | 容器 `Application Support/Fonts/` 文件名 = 清单里 `md5` 字段 |
| 成图管线 | `typesetting_models.savedURL/savedSmallImgURL/renderPipelineVersion`；thrift `baseCardImage`/`landscapeCardImage` |
| 同步四通道 | `codesign -d --entitlements -`；`tinytype.icloud.sync`；`XYUploaderCloudS3+Multipart`；`DataSyncOrchestrator` 日志 |
| 踩坑清单 | `research/tinytype/strings/logs.txt`（从二进制抽出的 7153 条可读日志） |
| CMP + Skia | `TinyCmpShared.framework` 里的 `ComposeUIViewController` / `org.jetbrains.compose` / `Skia` / `CAMetalLayer` |
| CDN 路径规范 | 330 个 URL 按主机/目录聚类（§9.5） |
| 模块地图 | `tinytype.*` 队列名与 `Kmp*` 类名（§15） |
| 商业与市场事实 | `itunes.apple.com/lookup?id=6749688592&country=cn|us`、`tinytypezoo.com`、`tinytypezoo.com/terms-of-service.html` |
| 数据模型演进 | `TypesettingApp.sqlite` 的 `grdb_migrations` 24 条（§11） |
| 内部文档泄漏 | 包内 `TINYTYPE_HABIT_CHALLENGE_API_DESIGN.md`（70 KB） |

**提取方法**（可复现，无第三方依赖）：

```bash
# 1. 素材：从模板 JSON 取 url 下载（webp，sips 转 png）
python3 → 解析 editor_template.json → curl → sips -s format png
# 2. 像素：纯 zlib 解 PNG，逐行比对（相邻行均差、唯一行数、周期、接缝）
python3 → zlib.decompress + PNG 反滤波
# 3. 字符串：strings 会切掉中文，必须直接解 UTF-8 扫二进制
python3 → bytes.decode('utf-8','ignore') → 正则抽 CJK 段 → research/tinytype/strings/logs.txt
# 4. 能力：codesign -d --entitlements -；导入符号：nm -u | grep -oE "_CT[A-Za-z]*|_CG[A-Za-z]*"
```
