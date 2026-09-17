# 纸张排版与信纸策略

记录日期：2026-09-18
状态：策略讨论稿，尚未落地。用于确定「一张纸一份规格」的模型、字段、命名与推进顺序。

已确认的产品取舍（本次讨论定下的）：

1. **绝对不滚动**。超出单页容量就翻页，多页时界面要露出底下叠着的纸边（轻微交叉错位）。
2. **全 App 禁用文本选择与复制**。需要复制的地方由业务显式提供按钮。
3. **关闭按钮位置进纸张规格**。每张纸比例、留白、装饰都不同，不能统一成一个常量。
4. **资产现状**：`Note_Paper_*` 已改为 `Paper01` ~ `Paper06`，各图尺寸不同（例如 2500×2870、2651×2866），必须按各自原图比例独立计算。
5. **容量按 ~20 种纸设计**。字段要支持按语言、容器类型、书写方向做语义过滤。
6. **字体已有规划**（见 `DesignAssets/fonts/README.md`）：内置霞鹜文楷兜底，其余 14 款按角色从 CDN 按需下载。字体按角色引用，不写死字体名。

---

你看得很透，而且把最关键的几条体验底线和扩展边界直接钉死了：

1. **绝对不滚动，只做物理翻页 / 叠纸**：多页时底下露出纸边（微旋转错位），翻页揭开下一张。
2. **全局禁用文本长按选择与复制**：全 App 统一，有需要由业务显式提供"复制"动作按钮。
3. **关闭按钮必须进纸张策略**：每张纸比例、空白区、装饰挂件都不同，按钮位置必须是单图专属参数。
4. **资产现状已更新**：`Note_Paper_*` 已重命名为 `Paper01` ~ `Paper06`，尺寸各不相同（如 2500×2870、2651×2866），必须按各自原图比例独立计算。
5. **容量扩展到 ~20 种纸**：字段必须支持语义过滤（语言、情感容器、书写方向），避免把不适用的纸推给特定语言或场景。
6. **字体策略已有清晰设计**：`DesignAssets/fonts/README.md` 已把 15 款字体按三个物件和语言分发规划完毕，默认内置「霞鹜文楷」，其余 CDN 按需加载。

结合这套最新输入，未来支撑 ~20 款纸张的可扩展策略与完整规格字段整理如下：

---

### 一、 核心架构：纸样资产与策略模型 (`PaperSheetSpec`)

不再写死任何几何常数，每张纸是独立的一套"纸面描述符"。

```swift
/// 纸张全局唯一身份，解耦数组下标与哈希取模
enum PaperID: String, Codable, CaseIterable, Sendable {
    case paper01 = "Paper01"
    case paper03 = "Paper03"
    case paper04 = "Paper04"
    case paper05 = "Paper05"
    case paper06 = "Paper06"
    // 未来直接在这里扩展至 20 种：case paper07 = "Paper07" ...
}

/// 排版方向
enum PaperWritingDirection: String, Codable, Sendable {
    case horizontalLTR   // 现代横排：左至右，上至下
    case verticalRTL     // 传统竖排：右至左，上至下（如 Paper05 仿古竖线格）
}

/// 纸张规格定义（全参数采用原图 0.0 ~ 1.0 的归一化坐标系统）
struct PaperSheetSpec: Identifiable, Sendable {
    let id: PaperID
    let assetName: String

    // 1. 物理尺寸与比例（由真实图片资产尺寸决定）
    let pixelSize: CGSize              // 例如 (2500, 2870)
    var aspectRatio: CGFloat { pixelSize.width / pixelSize.height }

    // 2. 纸体有效可视区域与倾斜角（用于叠纸与投影）
    let paperBounds: CGRect            // 刨去四周纯透明留白后的纸张轮廓
    let visualTiltDegree: Double       // 纸张自身视觉倾角（如 Paper03 的斜角）

    // 3. 关闭按钮专属锚点（解决每张纸不能做成一样的问题）
    let closeButtonAnchor: PaperControlAnchor

    // 4. 专属书写排版区域
    let layout: PaperTextLayoutSpec

    // 5. 装饰物 / 挂件 / 禁区规则
    let keepOutZones: [CGRect]         // 避让图钉、回形针、自带星星、破洞等
    let tokenPlacement: PaperTokenRule // 星星挂件 / 纸团印章的覆盖/悬挂点

    // 6. 适用条件与业务过滤（供未来挑纸、切语言时过滤）
    let filterRules: PaperFilterRule
}
```

---

### 二、 拆解重点子模块字段设计

#### 1. 关闭按钮专属定位 (`PaperControlAnchor`)

关闭按钮不仅坐标不同，由于纸边缘可能有图钉（Paper03）或回形针（Paper01），按钮的视觉对齐基准也不同：

```swift
struct PaperControlAnchor: Sendable {
    /// 归一化中心点 (x: 0.0 ~ 1.0, y: 0.0 ~ 1.0)
    let normalizedPosition: CGPoint
    /// 适用的视觉风格（浅色纸配微透深底灰叉，深色/复古纸配金属质感或米白圆底）
    let style: CloseButtonStyle
}
```

#### 2. 书写区与翻页容量 (`PaperTextLayoutSpec`)

解决"翻页"与"竖排/横排"的核心布局参数：

```swift
struct PaperTextLayoutSpec: Sendable {
    let direction: PaperWritingDirection
    let writingRect: CGRect            // 归一化书写安全区域 (relative to pixelSize)

    // --- 竖排专用（如 Paper05 红竖线格） ---
    let columnCount: Int?              // 栏数（Paper05 实测 7 栏）
    let columnPitch: CGFloat?          // 栏间距与栏心归一化跨度

    // --- 横排专有（如 Paper03 撕边信纸） ---
    let linePitch: CGFloat?            // 横格线基准行高
    let textRotationDegree: Double     // 文字顺应纸张倾斜的角度（跟随纸面）

    // --- 单页容量与字体约束 ---
    let recommendedCharCapacity: Int   // 舒适单页字数阈值
    let minFontSize: CGFloat           // 紧凑排版字号下限（pt）
    let maxFontSize: CGFloat           // 常规字号上限（pt）
    let preferredFontRole: FontRole    // 默认适配的字体角色（见下文）
    let inkColorHex: String            // 墨水颜色（#2A2723 碳墨黑、#1E2B37 蓝黑墨水等）
}
```

#### 3. 字体角色矩阵与 CDN 结合 (`FontRole`)

参考刚更新的 `DesignAssets/fonts/README.md`，字体不要绑死名字，而是绑**情绪与容器角色**：

```swift
enum FontRole: String, Sendable {
    case dailyCasual       // 随手轻记（悠哉体、Caveat）
    case tenderAffection   // 撒娇黏人（小赖字体）
    case deepPromise       // 庄重长文（霞鹜文楷、汇文明朝）
    case grievanceVent     // 委屈脆弱（寒蝉手拙、851手写杂书）
    case vintageCalligraphy// 仿古竖排（适合配 Paper05 活字/楷书）
}
```

* **运行时查表**：`FontManager.shared.font(for: role, language: currentLocale)`。
* **分发兜底**：若该角色对应字体还在 CDN 下载中，无缝使用包内内置的 `LXGWWenKai-Regular` 兜底渲染，字绝不会开天窗。

#### 4. 多语言与容器类型筛选 (`PaperFilterRule`)

为未来 20 种纸提供过滤标准：

```swift
struct PaperFilterRule: Sendable {
    let supportedLocales: Set<String>  // 如 ["zh-Hans", "ja"]。英文/韩文下自动隐藏竖排纸
    let supportedContainers: [ContainerKind] // 星星瓶 / 胶囊 / 纸团篓专属
    let allowsMediaAttachments: Bool   // 有的紧凑小票纸/竖排古风信纸不允许插大图
    let isUserSelectable: Bool         // 是否开放给用户手动挑选
}
```

---

### 三、 翻页交互策略（叠纸 + 翻开物理动画）

当内容字数超出单页舒适容量（`> recommendedCharCapacity`）时：

1. **分卷分页算法（Pagination Engine）**：
   * 采用 CoreText（竖排/横排）的 `CTFramesetter` 结合 `writingRect` 自动切出多个 `CGPath`，计算每页文字跨度与断字（遵守中文禁则）。
   * **附件占用**：若含照片，第 1 页作为图文页，多出的文字从第 2 页纸纯字继续。
2. **底层叠纸视觉（Paper Stack Effect）**：
   * 翻页状态下，底层根据总页数（最多展示 2~3 层）渲染**轻度旋转与位移的底纸阴影轮廓**（如底层向左偏 2°，下底层向右偏 1.5°），用户一打开就能看出"这是一叠信纸，不止一页"。
3. **翻页交互**：
   * 支持从右下角向左上翻折滑动（或轻点右侧纸角）；
   * 被翻开的上一页带微弱透光与折角形变弹簧过渡离开，新的一页落在主舞台。

---

### 四、 规避历史 Hash 稳定性坑的规则

历史代码使用 `names[hash % count]`，一旦列表加入第 6、第 7 张纸，旧内容的纸张会全部洗牌变样。

* **持久化绑定**：
  在 `SecretItem` 写入 CloudKit 记录时，带上 `paperID: String`。
* **老数据平滑过渡方案**：
  对于旧数据中 `paperID == nil` 的条目，采用**固定冻结函数**：

  ```swift
  func legacyPaperID(for id: UUID) -> PaperID {
      // 永久锁死在老 5 张纸的固定枚举集上，绝不受未来扩展到 20 张纸的影响
      let legacyPool: [PaperID] = [.paper01, .paper03, .paper04, .paper05, .paper06]
      let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
      let index = Int(bytes[0] &+ bytes[1]) % legacyPool.count
      return legacyPool[index]
  }
  ```

  新写入的内容直接保存指定的 `paperID`（无论是系统根据容器推荐的，还是用户在信纸库里挑的），终身固定不变。

---

### 建议的分步推进节奏

既然当前不需要直接写业务逻辑，这套策略我们可以在后续需要时按以下顺序顺畅接轨：

1. **规格度量（无破坏性）**：针对新的 `Paper01` ~ `Paper06` 原图，编写静态规格表，把关闭按钮锚点、红竖线格 7 栏与倾角校准到位。
2. **排版渲染层改造**：抽离 `PaperView`，横排走统一文本框、竖排（Paper05）走 CoreText 桥接，接入禁止选中文本规则。
3. **翻页与叠纸体验**：加入叠纸层级与单页翻折手势。
4. **字体与挑选器接入**：等 CDN 与用户挑选信纸流程排期时，挂载 `PaperFilterRule` 和字体下载器。

---

### 待定 / 未覆盖

- **命名规则**：现有 `names[hash % count]` 的下标取模需要换掉（已定方向，具体命名规则待定）。
- **每张纸的实测规格**：`Paper01` ~ `Paper06` 的纸面轮廓、书写区、栏数、倾角、关闭按钮锚点尚未逐张测量；上一轮的测量基于已重命名的旧图，需对新图重做一次。
- **谁来决定用哪张纸**：暂缓。最终方向是「按容器类型推荐 + 用户可挑」，语言不适用的纸在挑选时隐藏。
