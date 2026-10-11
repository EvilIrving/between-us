# 排版小动物 深挖：动画 / 性能 / 产品设计 / 踩坑 / 美术资产

记录日期：2026-09-18
对象：`/Applications/排版小动物.app/Wrapper/Tinytype.app`（`com.kairuotu.tinytype` 2.1.0 build 2010806，Xcode 26 / iOS 26 SDK，235 MB）+ 运行时容器 `~/Library/Containers/com.kairuotu.tinytype/`
前置：`TINYTYPE_TEARDOWN.md`（产品面、内容模型、同步、纸面三切片、渲染管线、字体、10/11 节的性能与踩坑清单）。**本文只写那篇没展开的五条线，并且全部换成实测数字。**
新增素材：`research/tinytype/{bitmaps,fonts,strings}`（前一轮已抽好的 220 个 CDN webp、21 个字体文件 + 元数据、日志字符串），本轮新增的量化结论都标了来源。

**证据边界**（比 MOODA 好，但也有硬限制）：
- 有**运行时落盘证据**：容器 85 MB 已实测（字体 70 MB、4 个 sqlite、URLCache 46 个文件、SDImageCache 124 个 webp）。
- 有**真实网络证据**：`Cache.db` 里 86 条缓存响应（含完整 URL 与体积）、缓存里的 7 份服务端配置 JSON。
- **没有可读的运行日志**：`Documents/logFileV2/*.log`（1 MB）是加密的，`marslog/*.xlog`（412 KB）是二进制；`research/tinytype/strings/logs.txt` 是**从二进制里抽出的日志键**（只有模板，没有数值）。所以"耗时/内存"这类结论只能引用他们自己埋点的**存在性与分层**，不能引用数值。
- 本机只打开过 App，DB 里 `typesetting_models` / `image_attachments` 都是 **0 行**，`grdb_migrations` 24 条 —— 也就是说容器是"冷启动骨架 + 缓存"，不是使用中的状态。

---

## 0. 三条结论

1. **动画**：四套机制（Lottie / APNG / 动画 WebP / PAG）**全是"播片段"**，全 App 没有一处物理。真正值得学的是他们对 APNG 的处理——预载 → 内存压力放弃 → 落到系统 API → 再失败才提示，一条三角降级链；以及"动画依赖上一帧算出的尺寸，尺寸无效就整段跳过"这个耦合点。另外：`libpag.framework`（2 MB）被主二进制链接，但**没有任何 PAG 符号引用、包内没有 .pag 资源、KMP 框架也没引用**，疑似死依赖。
2. **性能**：包 235 MB 的结构是 **96 MB 主二进制（其中 KMP 共享层 48 MB）+ 51 MB 字体 + 25 MB Assets.car + 2 MB libpag**；真正的内容美术（已抽出的 220 个 CDN webp）只有 **20 MB**。性能手法是"多级短路 + 并发闸门 + 预载 + 主动放弃"（teardown §6/§10 已写），我补充的是**实测落盘量**和**网络层是工业级**（GSLB 三段竞速、双链路耗时埋点、DoH 解析自家 APM 域名、Cronet 安全通道）。
3. **美术资产**：他们的资产策略是**"配置驱动 + 每类资产固定设计宽度"**（纸面 1200、横版 1014、系统卡 3602、情绪脸 159、占位 300、clip 390），代价是**变体冗余**（横版卡片一个模板 4 个背景变体 ≈ 1.6–1.8 MB；系统卡 520 一张 2.1 MB 还存了 thumbnail + detail 两份）；包内还留着一张 **9.26 MB 的单张背景**（占 Assets.car 的 37%）。字体这块他们**合法地踩在了红线附近**：方正兰亭 ×3、微软 Bahnschrift、平方时光体（fsType 4，仅允许预览/打印嵌入）都在通过 CDN 下发——**我们的字体 CDN 计划必须先过 fsType + 授权这一关**。

---

## 1. 动画

### 1.1 包内只有 6 个 Lottie，全部实测规格

| 文件 | 画布 | 帧率 | 帧数 | 图层 | 图层名 | 用途 |
| --- | --- | --- | --- | --- | --- | --- |
| `a.json` | 393×150 | 25 | 0–10 | 1 | `face-bg 2` | 心情选择器/卡片表情的底 |
| `b.json` | 393×150 | 25 | 65–71 | 1 | `face-bg 2` | 同一条时间轴的**后一段** |
| `daka_large_caidai_data.json` | 1179×2556 | 60 | 90 | **18** | `动态层 16/15/17/14/13…` | 打卡彩带（全屏） |
| `daka_small_caidai_data.json` | 400×350 | 60 | 60 | 4 | `动态层 3/2/1/` | 打卡彩带（小尺寸） |
| `post_loading_bottom.json` | 760×200 | 24 | 72 | 3 | `空 13` / `正加急投递中` / `...` | 邮局投递中的动画 |
| `monthly_mood_summary_entrance.json` | 1080×1710 | 25 | 30 | 2 | `形状图层 2/3` | 月度情绪总结入口 |

两个可抄的点：

1. **同一时间轴切两段存**（`a.json` 0–10、`b.json` 65–71）：需要"进入 + 循环"两态时不用两个文件表达两套设计，切帧就行。
2. **彩带准备两档而不是缩放一套**：全屏 1179×2556 用 18 层 60fps 的精细版，小场景 400×350 用 4 层版。庆祝动画是低频高光时刻，值这一份冗余；高频动效不要这么干。

### 1.2 四套机制的实际分工（含"疑似死代码"）

| 机制 | 证据 | 判断 |
| --- | --- | --- |
| Lottie（v5.12.x） | 上面 6 个文件 + `HabitCaidaiCelebration: 未能加载彩带 Lottie 资源`、`DiaryMoodPickerView: 未能加载 Lottie 资源` | 真实在用，且带加载失败兜底 |
| APNG | `APNGPreloadManager`、24 条相关日志键 | 编辑器一次性动画（入箱/散开/保存） |
| 动画 WebP | `✅ 已配置原生 WebP 动画支持 (iOS 14+)` | 轻量替代 APNG |
| **PAG（libpag 2 MB）** | 主二进制 `LC_LOAD_DYLIB @rpath/libpag.framework/libpag`；但 `nm -u` 里 **0 个 PAG 符号**，KMP 框架也没有，全包 **0 个 `.pag` 文件** | **疑似死依赖**：链接了但没有任何静态引用（除非用 `NSClassFromString` 动态取类，没证据） |

### 1.3 APNG 的三角降级链（这条值得抄结构）

```
启动/进编辑器前：开始预加载所有自定义APNG动画…
   ├─ APNGPreloadManager: 当前内存占用…（留出余量判断）
   ├─ 内存压力过高 → 停止预加载剩余自定义APNG（主动放弃，不赌）
   └─ 预载完成 → ✅ 使用预加载的 APNG…
播放时若没预载到：
   ├─ card_save APNG未预加载，使用系统API动态加载
   ├─ ✅ 系统API加载成功 / ❌ 失败 → 记录并继续（不阻塞保存）
其他：收到内存警告，清理APNG预加载缓存；❌ 找不到或无法解码自定义APNG文件
```

**内存压力下"停止预载"比"预载失败"更值得学**：他们把内存当作**预算**而不是**上限**，先探测再决定要不要继续。我们做三件物件的物理/贴图预载时应该照这个结构做（先读 `os_proc_available_memory` 之类的信号，再决定预载件数）。

### 1.4 动画与布局的耦合点（他们自己写出来的坑）

```
❌❌ 选中的模板图片尺寸无效，跳过散开动画
DiaryEditorVC：scaledImageHeight 无效，跳过动画
短图尺寸无效，跳过动画
DiaryEditorVC：第一步上移完成，等待 130ms 后掉落入箱
```

动画的起点/终点依赖**上一次布局算出的尺寸**；尺寸无效就整段跳过。这是一个可迁移的工程共识：**动画不要自己算几何，必须从当前布局取**；但取不到时的行为要显式定义（跳过 + 立即落到终态），不能静默不动。

> **耳语动作**：① 我们的物理已有独立时钟，但要补一条"尺寸无效 → 落终态"的显式分支（现在打开仪式里如果容器尺寸拿不到会怎样，值得查一次）；② 低频高光时刻（买断成功、打开积压内容）可以像彩带一样准备两档片段；③ 高频动效一律系统弹簧 + 触觉，不引第二套动画引擎（尤其不要引 PAG：他们自己都没用起来）。

---

## 2. 性能

### 2.1 包体结构（实测）

| 部分 | 大小 | 说明 |
| --- | --- | --- |
| `Tinytype` 主二进制 | **96 MB** | 双架构；含全部静态库 + `TinyCmpShared` 之外的业务代码 |
| `Frameworks/TinyCmpShared.framework` | **48 MB** | Compose Multiplatform + Skia 共享 UI 层 |
| `Assets.car` | **25 MB** | 332 个 rendition / 295 个名字 |
| 随包字体（3 款） | **51 MB** | 小赖 24 MB + 丹明A 15 MB + AaZTGJWWTjf 12 MB |
| `Frameworks` 其余 | 2.1 MB | libpag 2.0 MB + Firebase/Google 三个占位框架 |
| `RedI18N.bundle` | 6.3 MB | 9 语言字符串（红书通用库） |
| `PlugIns` | 0.97 MB | Widget 836 KB（含 27 KB 字体子集）+ 通知扩展 132 KB |
| 其他随包资源 | ~3 MB | `animal_paten.png` 1.6 MB、`post_loading_top.png` 240 KB、`animal_list_all.webp` 220 KB… 另有 6 个 Lottie（`daka_large_caidai_data.json` 37 KB 最大） |

要点：**KMP 共享层 48 MB 是"一套 UI 跑两端"付的过路费**；美术资源（Assets.car 25 MB + 散图 3 MB）加起来也只占 12%。**我们目前包体小是优势，不要为了统一架构把它变重。**

### 2.2 运行时落盘（本机实测，冷启动骨架）

| 位置 | 体积 | 内容 |
| --- | --- | --- |
| `Application Support/Fonts/` | **70 MB** | 15 个 md5 命名字体（内容寻址） |
| `Caches/com.kairuotu.tinytype/` | 2.8 MB | `Cache.db` 640 KB + WAL 772 KB + `fsCachedData` 46 个文件 1.4 MB（**URLCache**） |
| `Caches/com.hackemist.SDImageCache/` | 3.1 MB | 124 个 webp：`default` 1.9 MB + 自定义命名空间 `AnimalFelling` 1.2 MB |
| `Caches/com.xingin.tracklite` / `emitter` | 4.1 MB | 他们自己的埋点/统计库落盘（红书体系） |
| `Application Support/database/` | 484 KB | `TypesettingApp.sqlite`（24 条迁移，0 行数据）、`CustomBoxes.sqlite`、`UniversalData.sqlite` |
| `Documents/TinyDB/box_card_relations.sqlite` | 96 KB | **箱子↔卡片关系单独一个库**（另有"内存数据库后备"日志） |
| `Documents/tiny_kmp.db` | 16 KB | KMP 侧 `tiny_record` 表 |
| `Documents/XYStorageCoreRoot/` | 132 KB | 红书存储框架：`storage.infra.experiment`（AB 实验）、`storage.infra.configCenter`（配置中心） |

**注意 URLCache 与 SDImageCache 是两套独立缓存**（前者走 `NSURLCache`，46 个文件；后者是图片专用，124 个文件）——他们有一个自研 `ImageCDNDownloader`（fileId 换链下载卡片附件）+ SDWebImage（模板/静态素材）并存。teardown 已记"缓存为空导致重启不显示"的坑，这里补的是**落盘形态**。

### 2.3 网络层是工业级的（这一块与我们完全不同量级）

从缓存 JSON 与日志键里还原：

| 能力 | 证据 |
| --- | --- |
| GSLB 竞速 + TTL + 测速 | `evaluation-v2-gslb case1：切网强制竞速… case2：ttl到期竞速或者冷启 更新计时器 … case3：ttl没有到期，有ip变化，根据ifSpeedtest往下传，但不更新计时器` |
| 双链路耗时埋点 | `XYNetDualLinkEntry-Wi-Fi 请求耗时:` / `XYNetDualLinkEntry-蜂窝网络请求耗时:`（同请求两条链路对比） |
| Cronet 安全通道 + GSLB 直连 | 二进制字符串 `Cronet`、`GSLB`、`XYWorldSnake/XYAPIRoute`；"用户使用代理 所以返回"（代理检测） |
| 长连接 | `celestial`（`/api/sns/celestial/v2/connect/config?domain=tinytype`） |
| DoH 解析自家 APM | 缓存里实测 `https://doh.pub/dns-query?name=apm-native.xiaohongshu.com`、`https://dns.alidns.com/resolve?name=apm-native.xiaohongshu.com` |
| 配置中心 + AB 实验 | `storage.infra.configCenter` / `storage.infra.experiment` |
| 埋点上报 | `com.xingin.tracklite`（3.2 MB 落盘）、`com.xingin.emitter`（940 KB）、SolarEngine（SKAdNetwork 检查） |

**结论**：他们的"性能"有相当一部分是**平台遗产**（红书的网络/存储/实验框架）换来的，不是这个 App 自己做的。我们**不能也不需要**照抄；能照抄的只有下面 2.4。

### 2.4 真正可迁移的四条

1. **每类资产固定设计宽度**（纸面 1200 / 横版 1014 / 系统卡 3602 / 情绪 159 / 占位 300 / clip 390，实测自缓存 webp 与配置声明，两者一致）。我们的 `ArtworkMapping` 已经是这个思路，只差把"设计宽度"写成明文规范。
2. **上传/落盘前的主动降采样**：`超 JPEG 上限，降采样至…`、`Whole JPEG 4:4:4`（保清晰）、`图片超过20MB，无法添加`、`size超过阈值，不计算md5`。我们做媒体时同样要有"压缩 + 拒收超大"两条硬线。
3. **关键路径都埋耗时日志**：`✅ 数据库初始化完成，耗时:`、`✅ 字体和图片预加载完成，耗时:`、`CardImageRenderer: 渲染完成，耗时:`、`✅ analyzeServerCards 完成，耗时:`、`XYNetDualLinkEntry-*-请求耗时:`、`当前动物模版生成完成，耗时:`、`✅ 短图生成完成，耗时:`、`磁盘整图命中，总耗时:`、`管线渲染完成，总耗时:`、`% 平均耗时是:`。我们不需要埋这么多，但**"渲染一条内容 / 打开一个物件"必须有一条可对比的耗时口径**。
4. **内存警告分级处理**：`ImageMemoryManager: 收到内存警告，清理图片缓存`、`收到内存警告，清理APNG预加载缓存`、`TinyPrivacyVC 收到内存警告，清理富文本缓存`、`ThumbnailGetter 实例数已达上限，且无法释放更多实例` —— 每个缓存域各自响应，有实例上限。

> **耳语动作**：包体我们已经是他们的 1/100（约 2.4 MB 位图 + 724 画布），别为了"架构统一"引入跨端框架；但要补两条他们做得比我们好的：① 渲染/打开一条内容的耗时口径；② 内存警告时的分级清理与预载预算判断（不是等系统杀进程）。

---

## 3. 产品设计

### 3.1 一个还没上线的新功能，被完整地泄露了出来

包内 `TINYTYPE_HABIT_CHALLENGE_API_DESIGN.md`（72 KB）是一份**完整的后端契约评审稿**：17 个新增接口、HTTP/Thrift 映射、"已确认 / 设计建议 / 待客户端确认"三级标记，还点名引用了另外 6 份内部文档（`PROJECT_CURRENT_STATE.md`、`..._DATA_MODEL_FINAL_BASELINE.md`、`..._ASSET_POOL_DESIGN.md`、`..._EXPOSURE_API_ANALYSIS.md`、`..._TECHNICAL_DESIGN.md`、`..._IMPLEMENTATION_PLAN.md`）。

从里面能读出的产品设计（**习惯挑战**）：

| 维度 | 规则 |
| --- | --- |
| 阶段 | 目标天数 **7 / 21 / 100**，完成后可"继续挑战"升级到下一阶段 |
| 图章 | 完成阶段获得图章（`stamp`），有"已完成图章列表"接口，**不提供图鉴库接口**（客户端不能自己攒图鉴） |
| 主题资产 | 一个阶段三个资源：`progressBadge`（进行中）/ `completedBadge`（完成图）/ `stamp`（印章），**同 themeKey 共享**，服务端按 ACTIVE/COMPLETED 决定返回哪些（"ACTIVE 阶段不得提前展示"） |
| 欠图降级 | `isFallback`：主题资源还没画完时服务端给 FALLBACK 完整主题，客户端**只**据此显示"欠图提示"，不许推导替换进度 |
| 提醒 | 客户端只提交 `enabled / weekDays / remindTime`，**不许提交 timezone，服务端固定 `Asia/Shanghai`** |
| Banner | 优先级 `DIARY_MONTHLY > KAKA > HABIT_CHALLENGE`，曝光/已读分两个接口，旧客户端空 body 也能走同一条路径 |
| 事实源 | **Card 是打卡的唯一事实源**；打卡创建/修改/删除都走专域，但详情复用既有 `GET /api/card` |

值得学的是**协作格式**（不是功能本身）：

- 每个接口都写清"冻结域 + Method + Path + Query/Body 位置 + 兼容策略"，并明确**不新增哪些接口**（`getHabitChallengeCard`、`getCheckinCard`、深层嵌套路径）。
- 字段表带**三档标记**：已确认 / 设计建议 / 待客户端确认 —— 让"这是产品规则"和"这是我的建议"在文档里不会混。
- 把"客户端不得做什么"写成条款（不得推导内部状态、不得提前展示 COMPLETED 资源、不得提交 timezone）。**我们跟 Codex/AI 协作时最缺的就是这一层：把禁止项显式写进契约。**

两块该被质疑的地方：

1. **提醒固定 `Asia/Shanghai`，而 App 有 9 种语言**（`RedI18N` 里有 ja/ko/es/fr/ru）。海外用户的提醒时间会偏；即便提醒由客户端本地调度，服务端侧的任务日切也会错。**我们做任何按天的功能（免费额度按天、月末回顾）必须一开始就把时区显式建模，宁可存 `timezone` 字段。**
2. `{"version":N,"config":"<JSON 字符串>"}` —— **配置是双重编码的**（外层 JSON 里塞JSON 字符串）。所有 7 份配置都这样。这是他们能"服务端热更"的代价：解析要解两次、日志难看、错误难定位。

### 3.2 商业化：不是卖软件，也不用 IAP 赚钱

| 项 | 实测 |
| --- | --- |
| 解锁链路 | 92 处日志提到解锁；全部走 `AnimalTemplateFeatureManager` + 服务端 `/api/unlocked`（6 处）/ `/api/unlock`（11 处） |
| 触发方式 | 登录（访客 → 邀请 banner → 登录后自动 `/api/unlock`）、iCloud KV 标记、活动奖励（`editor_mail_template.json` 里 `system_activity_reward_kaka`、`system_editor_reward_liangliang_2`、`system_first_image_liangliang_3`） |
| IAP | StoreKit **被链接**，且有 `requestProductsWithProductIdentifiers:` / `in_app_purchase` / `invalidProductIdentifiers` 符号与红书会员购买漏斗事件名（`MemberPurchaseInLandingPage*`），但**包内找不到任何商品号** → 更像基础库自带能力，不是本 App 在卖货 |
| 运营位 | 系统卡其实是**运营位**：`editor_mail_template.json` 的 `actions` 带 `image_url / margin_* / route / style / type`（deeplink 直达） |

这与 `TINYTYPE_TEARDOWN.md` §16 的判断一致，我补的是"StoreKit 确实被链接 + 有商品查询符号 + 没有商品号"这一层。**耳语不适用**：我们一次买断，权益状态只能有一处真相（StoreKit 本体）。

### 3.3 交互与规则细节（当检查表用）

| 项 | 规则（实测字符串） |
| --- | --- |
| 卡片标题排版 | `行长上限8字，避免标点开头`、`字数≤8时保持单行显示`、`行长差异过大 (max-min>` —— 他们按"每行 8 字"手工校验 |
| 多图 | `hasMultiImagePrivilege` —— 多图是**权益**；`[MultiImageTips] 展示多图解锁蒙层` |
| 补记 | `retroDate`（可选过去日期）+ `displayTime` 与 `updatedAt` 分离 |
| 邮寄上限 | `[邮寄] 当前系统时间已超过可寄上限，无可寄的未来日期，拦截邮寄流程` |
| 箱子 | `CustomBoxManager: 自定义箱子数量已达到上限（999个）`、`无法创建新箱子：已达到上限` |
| 图片 | `图片超过20MB，无法添加`、`图片数量已达上限，不应调用 presentImagePicker` |
| 密码锁 | KMP 侧 `KmpPasswordLock*` / `KmpSetPasswordVC`（跨端实现） |
| 草稿 | `DiaryEditorVC：草稿恢复完成 content.count=`（写一半退出可恢复） |
| 游客态 | 游客数据与正式账号分库（teardown 已记），且游客可创建内容、登录后合并 |

> **耳语动作**：上面这些"硬规则字符串"是很好的检查表素材——尤其 **`20MB 上限 + 数量上限 + 超大图片提前拦住`**（我们的媒体入口应该有同样的两条），以及 **`草稿恢复`**（我们的创作流程目前没有显式草稿态，值得确认一次）。

---

## 4. 踩坑（新增，不与 teardown 的 23 条重复）

### 4.1 包与体积

| 坑 | 实测 |
| --- | --- |
| **一张背景图吃掉资产库的 37%** | `dairy_two_bg.png` 3240×5130 @1x = **9.26 MB**（Assets.car 共 24.87 MB） |
| 节日主题整包进 App | 7 张新年壁纸（`新年壁纸导出-01..07.jpg`，1200×2608，每张 468–507 KB）≈ 3.4 MB |
| 同一张底图存两份 | 系统卡节日素材 `system_____-520__thumbnail.webp` 与 `__detail.webp` **各 2.1 MB、尺寸相同** |
| 图案用 PNG 而不是 WebP | `animal_paten.png` 1179×1500 = **1.6 MB**（同目录 CDN 素材全用 webp，同类纹理在 MOODA 里是 102×102 可平铺） |
| 链接了不用的框架 | `libpag.framework` 2 MB（无符号引用、无 `.pag` 资源） |
| 跨端框架的过路费 | `TinyCmpShared.framework` 48 MB |

### 4.2 资产规格

| 坑 | 实测 |
| --- | --- |
| 两套尺寸并行 | 随包 UI 用 1179 宽（= iPhone 15/16 Pro 的 @3x 全屏像素）；加载图用 760 宽；CDN 纸面用 1200 宽；iPad 又各有一套 2048 宽（`*_ipad.webp`） |
| scale 语义不统一 | Assets.car 里 @2x 289 个、@1x 25 个、@3x 只有 17 个 → **以 @2x 为主**，与 MOODA 的"位图只出 @3x"完全相反 |
| 变体冗余 | 横版卡片一个模板 4 个背景（plain/low/mixed/image）≈ **1.6–1.8 MB/模板**；`mixed` 单张可到 737 KB |
| 命名带拼音/中文/错拼 | `daka_*_caidai_data.json`、Lottie 图层名 `正加急投递中`、`dairy_two_bg`（diary 拼成 **dairy** 且写进资产名）、API 路径 `markting/event/report`（marketing 拼错） |
| 说明性文件名进包 | 新年壁纸的文件名是中文设计稿名（`新年壁纸导出-01.jpg`），跨端资源管线里迟早出问题 |

### 4.3 字体版权（**对耳语最直接的一条**）

实测 21 个字体文件的 `fsType`（OS/2 嵌入许可位）与版权字段：

| fsType | 含义 | 他们的字体 |
| --- | --- | --- |
| 0 | 允许安装/任意嵌入 | 小赖（LXGW）、丹明A（I.Ming）、JyunsaiKaai、汇文明朝体、PFanHuTuTi、BoutiqueBitmap ×2、Cutive Mono、Della Respira |
| **8** | 仅允许"可编辑嵌入" | **方正兰亭黑 ×3（Founder）**、**AaZTGJWWTjf（字体管家/汉仪胡同）**、Bahnschrift（**微软**）、AsobiMemogaki |
| **4** | 仅允许"预览/打印嵌入" | **平方时光体**、`static-4.otf` |

- `Bahnschrift.ttf` 的 name 表里微软写明"Microsoft supplied font… may only (i) embed this font in content as permitted by the embedding restrictions; (ii) temporarily download to a printer…" —— **随包或 CDN 下发都不是这两种用途**。
- 方正兰亭三款是**商业字体**（Founder Electronic），`extra.familyName` 用的是 `FZLanTingHeiS-*-GB`。
- fsType 4/8 的共同点：**不允许把字体文件本身当资源分发**。他们做到了"包内 3 款兜底 + CDN 25 款清单"，但其中至少 7 款（方正 ×3、字体管家、微软、平方时光体、static）的再分发授权是可疑的。

> 我们的 `DesignAssets/fonts/README.md` 已经写了"7 款的字体文件里没有协议字段，转发前需确认"，**但要补一条更硬的门槛**：① 检查 `fsType`，4/8 一律不许进 CDN；② 查 name 表 ID 0/13/14 的授权与许可链接；③ 只接受 OFL/Apache/明确免费再分发，并把协议文本随包下发。小赖、汇文明朝体这类 fsType 0 的可以放心。

### 4.4 工程与安全

| 坑 | 实测 |
| --- | --- |
| 内部文档成批进包 | 本次又发现 7 份内部文档名（见 §3.1）+ 包内完整 `card.thrift`；文档含 Edith 网关、service 命名规范、错误码体系 |
| 面向内部的话术进了客户端日志 | `若依然显示已解锁，需联系后端确认/清理该测试账号`、`排查提示：…已打印到日志（TinyLog）` |
| 部分接口响应是加密的 | 缓存里有一条 `{"result":0,"success":true,"data":"o+MzzfJwjVdcBtrIBjRgx3Zm0KfmsrmA…"}`（13 KB base64 密文）→ 自研加密协议，抓包排查成本高 |
| 存储形态分散 | 4 个 sqlite（TypesettingApp / CustomBoxes / box_card_relations / tiny_kmp）+ MMKV + XYStorage + iCloud KV + `UserDefaults(cache.v2)` |
| 配置双重编码 | 7 份配置全是 `{"version":N,"config":"<JSON 字符串>"}` |
| 测试环境残留 | `TinyDebugTestVC`、"已重置为全新测试环境（模板/kaka 解锁标记 + 注册时间）" 这类重置逻辑在正式包里 |

---

## 5. 美术资产：怎么规划、怎么用、怎么加载

### 5.1 规划：一切由服务端配置驱动（7 份配置的完整 schema）

| 配置 | 内容 | 键数 / 条目 | 每条资产声明什么 |
| --- | --- | --- | --- |
| `editor_template.json` | 竖版编辑器模板（纸） | 76 / 22 模板 | `background.{top,center,bottom}`（url+width+height 三切片）、`content.layout` 四边、`h1/h2` 字体族/字号/行高/字距/颜色/描边、`date[]`（example 格式串 + font + layout + alignment）、`signature`（font + underline + layout）；**可选字段**：`decoration[]`（**22 个模板里只有 4 个有**，miles-1..4，同一张 442×538 装饰）、`image_frame[{id,frame,mask}]`（**只有 kaka-2 一个模板有**，frame 945×746）、`locked_overlay`（3 个） |
| `horizontal_card_templates.json` | 横版卡片 | 49 / 31 模板 | `background.{plain,low,mixed,image}`（**4 个变体**）、`corner_radius`、`content`（margin/alignment/font）、`tag`（分类标签样式）、`image_attachment`（尺寸/圆角/max_count/间距）、`language` |
| `system_card_templates.json` | 系统卡 + clips | 57 / 18 模板 + clips | `background.{detail,thumbnail}`（各带 corner_radius）、`clip{url,shadow_blur,shadow_dx,shadow_dy,shadow_color}`、`date`（format + **font_url**）、`signature`（format + font_url） |
| `dairy_color.json` | 日记本封面配色 | 24 / 3 类 × 4 风格 | `background`(url) + `color` + `font` + `layout` + `alignment` + `example`；三类是网格/条纹/纯色 |
| `animal_felling.json` | 角色情绪矩阵 | 21 / 8 角色 | `placeholder`(300×300) + `moods[]` + `diary_moods[]`（mood_type / mood_name / display_name / url / width / height） |
| `editor_mail_template.json` | 系统卡"动作"（运营位） | 38 / 3 动作 | `image_url` + 四边 margin + `route`（deeplink）+ `style` + `type` |
| `resource_download.json` | 字体清单 | 25 条 | `name_iOS/Android`、`url`、`md5`、`platform`、`path_iOS`、`extra.familyName` |

**两条可迁移的规划原则**：

1. **资产的"用途"由配置声明，不由文件名推断**：`image_frame` 明确标 `frame` + `mask`；`clips` 明确标 shadow 参数；`locked_overlay` 明确标是蒙层。
2. **同一份内容按"消费场景"分资产，而不是按尺寸缩**：情绪有 `moods`（卡片用）与 `diary_moods`（日记用）两套图 —— 同一个情绪在两个场景的构图不同。
3. **中段是一块"砖"，不是一段"拉伸区"**：三段素材里上/下段各画一次，中间那块按原尺寸反复铺。砖的硬约束只有一个——**能自己接上自己**：纤维纸纹的首尾行差要压到砖内噪声量级，周期图案则要求**砖高 = 周期 × 整数**（他们 rolf-1 点阵砖 940 = 11 × 85.3、rolf-2 方格砖 842 = 8 × 105.0，周期都是正方形）。这样不管纸被拉多长，砖里的纹理与格子都不会变形。我们已按这一口径重写 `PAPER_DESIGN.md` §3.3。

### 5.2 使用：三种复用方式（都值得抄，成本不同）

| 方式 | 例子 | 成本 |
| --- | --- | --- |
| **共享底 + 覆盖层** | 横版卡片 `plain / low / mixed / image` 四变体解决"图片压住装饰" | 贵：≈1.6–1.8 MB/模板（其中 `mixed` 737 KB） |
| **同一图形 + 参数** | `clips`：8 个角色的同一张图 + 服务端给的 shadow_blur/dx/dy/color | 便宜：一张图配参数 |
| **成对资产** | `frame` + `mask`（照片框）、`locked_overlay` + `background` | 中等：12 个文件 0.53 MB（photo_frame 实测） |

**判断**：他们为"装饰被图片压住"这个问题付了很重的资产税（每模板 1.6 MB 的背景变体）。**我们做同类问题时优先选第二、第三种做法**——先把装饰做成覆盖层（同画布 PNG，随内容缩放），只有覆盖层确实会挡住文字时才出第二张底图。

### 5.3 加载：三层 + 三个数字（实测）

```
L0 内存图         item.availableImage / SimpleImageManager / EditImageManager（编辑器独立）
L1 磁盘成图       Whole（完整）+ Small（缩略图），分目录
L2 附件本地       imageAttachments[].localPath / uploadStatus / orderIndex
L3 CDN            fileId → URL 批量换链 → 下载 → 渲染（ImageCDNDownloader）
模板/素材路径      SDWebImage（缓存目录按命名空间分：default / AnimalFelling）
配置              URLCache（Cache.db + fsCachedData）
```

实测数字：URLCache **86 条响应 / 46 个磁盘文件 / 1.4 MB**；SDImageCache **124 个 webp / 3.1 MB**；URLCache 里的 CDN 图片响应 **8–136 KB**，SDImageCache 里的 1200 宽纸面/背景 **12–100 KB**；唯一的异常值是系统卡节日图 **2.1 MB**（还存了两份）。

### 5.4 每模板的真实下载成本（可直接用于我们的体积预算）

| 资产组 | 实测 | 备注 |
| --- | --- | --- |
| 竖版编辑器模板（3 切片） | **0.08–0.35 MB** | `editor__laoshifu-1` 0.35 MB / `editor__miles-1` 0.10 MB |
| 声明画布与实际素材 | 声明 **1200×1438**（22/22 模板三段之和恒为 1438）；实际 top/bottom 与声明一致，**center 有 19 个比声明多 162 px**（liangliang-1 声明 138/实际 300、miles-1 声明 260/实际 422；laoshifu-1、kaka-1、kaka-2 声明 = 实际） | 因为中段是**按原尺寸反复平铺的那一段**（平铺，不是拉伸；见 teardown §5）；声明值只是布局参考：**设计稿宽度 1200 可信，高度与中段一律以素材为准** |
| 单个编辑器模板的拆解 | top ~37–133 KB + center **5–110 KB** + bottom 24–119 KB | center 最小的只有 5 KB（纯色/渐变区）；但“平”不是约束，中段只需要**首尾接得上**（teardown §5.3） |
| 横版卡片模板（4 变体） | **1.59–1.78 MB** | `tsuki-1` mixed 737 K + plain 514 K + image 514 K + low 19 K |
| 系统卡素材 | 单张最高 **2.1 MB × 2**（thumbnail 与 detail 同尺寸） | 5.48 MB / 19 个文件 |
| 情绪脸 | **3.6 KB/张**（159×159 webp），50 张共 0.18 MB | 最划算的一类资产 |
| 相框 frame+mask | **45 KB/张**（735–1020 宽），12 张 0.53 MB | — |

> 全文的 220 个 CDN webp 合计 **20.07 MB**，其中纸面 143 个文件占 **19.11 MB**（95%）。**"纸"是他们唯一的重资产**，装饰与情绪都是小图。这直接对应我们的现实：我们的纸张也是最大的一块（`DesignAssets/paper` 7.8 MB 源文件 / 运行时 4 张纸）。

### 5.5 落到耳语的具体动作

1. **给每类资产定"设计宽度"并写进 `DesignAssets/README.md`**：纸面 1200（我们现在是 2500 源 / 2074–1774 运行时，等价）、挂件 256、瓶体 724。**同一类只允许一个基准宽度**，iPad 版另开一套而不是缩放（他们 `*_ipad.webp` 就是明证：2048 宽单独出）。
2. **字体授权先过硬门槛**（§4.3 三条）。这是**发布合规**问题，不是体验问题。
3. **变体策略限量使用**：共享底 + 覆盖层 > 参数化 > 第二张底图；只有在"覆盖层会挡住文字"时才出第二张。
4. **每一类"可下载资产"都要有 md5 + 落地路径 + familyName/用途键**（他们的 `resource_download.json` 结构可以直接借），并且**包内兜底与远端清单同 md5**（命中即跳过）。
5. **像他们一样把"欠图"当成正常状态**（`isFallback` → 显示欠图提示，等正式资源替换）。我们的节日/买断素材如果分批做，就应该有这个字段，而不是"没图就不显示"。
6. **大图先问能不能平铺/降采样**：9.26 MB 单图 + 1.6 MB PNG 纹理是反面教材；我们的纸可以用切片，纹理类资产应该可平铺且用 WebP。
7. **纸的中段按"砖"做，别按"拉伸区"做**：`top + 砖（反复铺）+ bottom`。砖要么把首尾行差压到砖内噪声量级（随机纤维纸纹），要么用周期图案让砖高 = 周期 × 整数（方格/点阵/横格）——后者不管纸多长都不变形，是"图案纸"唯一正确的做法。旧口径"中段要平、靠纵向拉伸"已作废（teardown §5.3）。

### 5.6 明确不做

- 不做 KMP/Skia 跨端层（48 MB，我们是单端）。
- 不做配置中心 + AB 实验 + GSLB 竞速 + Cronet（平台遗产，我们用 CloudKit + URLSession）。
- 不做"每模板 4 个背景变体"这种资产税。
- 不引 APNG/PAG（我们已有 SpriteKit/Core Animation；他们自己的 PAG 都没用起来）。
- 不做打卡/心情周报/系统卡运营位（`TINYTYPE_TEARDOWN.md` §12、§16 已判）。

---

## 附录：本文新增证据索引

| 结论 | 证据/复现 |
| --- | --- |
| 6 个 Lottie 的规格 | `python3` 解析 `Tinytype.app/{a,b,daka_*_caidai_data,post_loading_bottom,monthly_mood_summary_entrance}.json` 的 `w/h/fr/ip/op/layers` |
| PAG 疑似死依赖 | `otool -L Tinytype` 有 `@rpath/libpag.framework/libpag`；`nm -u Tinytype \| grep -c PAG` = 0；`nm -u TinyCmpShared` 无 PAG；`find -name "*.pag"` = 0 |
| 包体结构 | `du -sh Tinytype.app/*`、`ls -l` 各文件、`du -sh Frameworks/*` |
| Assets.car 24.87 MB 与那张 9.26 MB 背景 | `assetutil --info Assets.car` 全量统计（332 rendition / 295 names / scale 分布 / 体积排序） |
| 容器落盘实测 | `du -sh` 遍历 `~/Library/Containers/com.kairuotu.tinytype/Data`；`sqlite3 *.sqlite` 查表与行数 |
| URLCache 86 条 / 46 文件 | `sqlite3 .../Caches/com.kairuotu.tinytype/Cache.db` 的 `cfurl_cache_response` / `cfurl_cache_receiver_data`；`ls fsCachedData` |
| SDImageCache 124 个 webp / 命名空间 | `find .../com.hackemist.SDImageCache`、`sips -g pixelWidth -g pixelHeight` 量尺寸 |
| 7 份服务端配置与 schema | 缓存的 `fsCachedData` JSON 解出 `data.config`（字符串再解一次），逐字段枚举 key path |
| GSLB / 双链路 / DoH / 配置中心 | `research/tinytype/strings/logs.txt` 关键词；`Cache.db` 里的 `doh.pub`、`dns.alidns.com` 记录；容器 `XYStorageCoreRoot/Infra/storage.infra.{experiment,configCenter}` |
| 习惯挑战契约 | `Tinytype.app/TINYTYPE_HABIT_CHALLENGE_API_DESIGN.md`（72 KB）逐节阅读 |
| 字体授权 | `research/tinytype/fonts/_font_meta.json` 的 `fsType` + `name[0/13/14]`；本地解析字体 name/OS-2 表 |
| 每模板下载成本 | `research/tinytype/bitmaps/{paper,decoration,photo_frame,animal_mood}` 按 `{scope}__{template}__{role}` 分组求和与单文件尺寸 |
| 硬规则字符串（8 字/20MB/999 箱等） | `research/tinytype/strings/logs.txt` |

无法复现的部分（如实记录）：`Documents/logFileV2/*.log`（1 MB）与 `marslog/*.xlog`（412 KB）是加密/二进制，本机没有可读运行日志；App 只被打开过，`typesetting_models` 与 `image_attachments` 均为 0 行，因此没有"使用中"的性能数据。全程只读，未改动原 App 与容器。
