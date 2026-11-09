# Between Us (耳语)

专为两个人设计的原生 iOS 亲密关系应用。通过真实物理物件隐喻（星星瓶、胶囊瓶、纸团篓）在共享私密空间内沉淀表达与共鸣，非即时通讯工具、非情侣任务打卡或排行榜游戏。

iOS 17+ · Swift 5.9+ / SwiftUI + SpriteKit · CloudKit + CKShare 原生双人同步 · StoreKit 2 一次性买断

---

## 1. 核心定位与业务红线（Invariants）

- **表达沉淀而非即时流**：用户不是在发即时聊天，而是在双人共同空间里留下真实物件，等待对方主动发现与仪式性开启。严禁将其改造为聊天时间线、红点通知流或普通收件箱。
- **三大核心物理物件定位**：
  - **星星瓶（`StarJar`）**：喜欢、感谢、夸奖、情话与感动的细节。
  - **胶囊瓶（`Capsule`）**：鼓励、建议、请求与认真严肃的沟通。
  - **纸团篓（`PaperBin`）**：委屈、难过、生气和暂时难以当面说出的情绪。
- **反游戏化铁律**：坚决不引入连续签到、日常任务、虚拟金币、等级经验、成就榜单、情侣测评等破坏安静私密氛围的功能。
- **商业化与免费额度规则**：
  - **单次买断制**：产品 ID 为 `cain.com.between-us.lifetime`，终身买断，不做周期订阅。
  - **免费额度**：一个空间内双方累计保留上限为 10 条内容；删除旧内容即时释放额度；拦截点为「放入第 11 条」。
  - **单方购买全空间生效**：一方完成 StoreKit 购买，空间已解锁状态（`lifetimeProductID`, `lifetimeUnlockedAt`）通过 CloudKit 关系记录共享，对方设备自动激活，无需双重付费。
  - **并发宽容**：若双方在离线或弱网下同时由 9 条各写入 1 条，允许总数临时超过 10 条，两条内容均须完整保留，仅阻断后续第 11 条新增。
  - **退款与撤销安全**：若付款方发生退款，空间回退至免费版，但已有内容绝对禁止自动删除。
- **空间生命周期与中立人设**：
  - 解除连接坚决不使用“分手”等判决性词汇。
  - 创建者显示「删除空间」（执行 CloudKit Zone 删除），参与者显示「退出空间」（执行退出共享并清理本地映射）。
  - 创建者建房后即可见「删除空间」；参与者加入后方可见「退出空间」；未配对时保持在引导态。

---

## 2. 架构分层与 Layout

```
swift-between-us/
├── Config.xcconfig             # 全局构建变量（Bundle ID, Team ID, CloudKit 环境分流）
├── BetweenUs.xcodeproj         # Xcode 工程主文件
├── BetweenUs/
│   ├── App/                    # 应用程序入口、生命周期与全局依赖注入
│   ├── Models/                 # 领域模型（Message, Emotion, Space, SharingState），纯逻辑
│   ├── Storage/                # CloudKit 服务端同步、本地持久化与 CKShare 状态机
│   ├── Store/                  # StoreKit 2 交易监听、购买流程与权益恢复
│   ├── Physics/                # SpriteKit 物理引擎（StarJarPhysicsSystem, TrashBinPhysicsSystem）
│   ├── Views/                  # 业务视图（RoomView, DetailViews, PairingView, SettingsView）
│   ├── Components/             # 通用无状态 UI 组件（Banner, ActionSheets, Buttons）
│   ├── Design/                 # 设计系统度量、配色、AppMotion、DriverSpring 弹簧参数
│   ├── Paper/                  # 纸张材质纹理与手写体排版渲染
│   ├── Resources/              # 音效、本地化与字体资源
│   └── Assets.xcassets/        # 原生物件图集（瓶身、挂件、胶囊开合序列帧）
```

### 单向依赖约束
- `Models`：严禁引入 `SwiftUI`、`SpriteKit` 或持久化框架，保持纯数据结构。
- `Physics`：仅依赖物理数学与 SpriteKit 原语，专注于刚体碰撞、重力、阻尼反馈，不得持有业务 Store。
- `Storage` & `Store`：通过异步协议（Async/Await）向外提供状态与结果，不持有 View 引用。
- `Views`：通过 ViewModel 或 Store 读取状态，严禁在 View 内部直接发起裸 CloudKit 请求。

---

## 3. 真实系统底层与网络/物理约束

### 3.1 CloudKit 容器环境强隔离
- 容器 ID：`iCloud.cain.com.between-us`。
- **开发与生产隔离**：
  - `Debug` 构建映射至 `Development`（可动态修改 Schema）；
  - `Release` / `TestFlight` 必须映射至 `Production`（Schema 固化）。
  - 必须由 `BetweenUs.entitlements` 注入 `com.apple.developer.icloud-container-environment: $(ICLOUD_CONTAINER_ENVIRONMENT)`。若缺失该键，系统默认连入 `Production`，导致 Debug 包因 Schema 未就绪被静默拒绝（抛出 `CKError 15`，底层返回 `2000`）。
  - **提审与 TestFlight 前置动作**：必须在 CloudKit Dashboard 手动执行「Deploy Schema Changes to Production」。

### 3.2 CKShare 面对面配对状态机
- **权限开门规则**：在发起分享生成邀请 URL 时，必须先显式设置 `CKShare.publicPermission = .readWrite`；接收方成功接受并加入空间后，必须立即收回至 `publicPermission = .none`。若未预先开门，链接在接收方设备上会直接报 `CKErrorUnknownItem`（Error Code 11，找不到共享）。
- **异步单向解耦**：创建者在长按确认邀请后即完成阶段提交，允许退入后台；加入方无需与创建者保持同时在线或同步前台，消除面对面连线摩擦。
- **入口动态收敛**：双方均已进入空间后，界面彻底隐藏邀请与共享管理入口，不干扰日常沉浸体验。

### 3.3 真实物理质感与动效哲学
- **混合渲染**：物件核心采用高质量位图 + 代码物理驱动（非纯参数化简笔画，亦非全屏游戏）：
  - 星星瓶：`StarJar_Body` 瓶身 + 挂件位图 + `StarJarPhysicsSystem`。
  - 纸团篓：`PaperBin_Body` + `PaperBin_Lid` 篓盖 + `PaperBall_*` + `TrashBinPhysicsSystem`。
  - 胶囊瓶：`Capsule_Open_00`~`04` 序列帧 + `CapsuleJarMetrics` 统一瓶口基准。
- **动效归宿**：内容弹层必须从对应物件本体拔出，关闭时平滑缩回原物件；长按或按住交互进度必须直接展现在物件的物理形变或材质光效上，禁止悬浮外部进度条。
- **Reduce Motion 适配**：系统无障碍开启「减弱动态效果」时，物理仿真立即收敛至静态目标态，保留交互可达性。

---

## 4. 验证与构建命令

优先采用真实 iPhone 设备进行端到端体验与 CloudKit 验证，避免模拟器丢失 iCloud 真实状态。

### 4.1 真机查找与部署
```bash
# 1. 查找当前物理连接且处于就绪态的 iPhone
xcrun devicectl list devices

# 2. 面向真机执行 Debug 构建
xcodebuild \
  -scheme BetweenUs \
  -destination "id=<DEVICE_UDID>" \
  -derivedDataPath .derivedData \
  build

# 3. 安装到真机
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  .derivedData/Build/Products/Debug-iphoneos/BetweenUs.app

# 4. 启动应用
xcrun devicectl device process launch \
  --device <DEVICE_UDID> \
  cain.com.between-us
```

### 4.2 签名与 CloudKit 权限自检
```bash
# 验证安装包是否包含正确的容器与环境声明
codesign -d --entitlements :- .derivedData/Build/Products/Debug-iphoneos/BetweenUs.app
```
*必须确认含有*：
- `com.apple.developer.icloud-container-identifiers` -> `[iCloud.cain.com.between-us]`
- `com.apple.developer.icloud-container-environment` -> `Development` (Debug) 或 `Production` (Release)

---

## 5. 字段变更联动与发布规范

| 变更项 | 涉及联动文件（必须同步修改） |
| :--- | :--- |
| **共享舞台基线高度** | `Views/` 下星星瓶、胶囊瓶、纸团篓三处详情页，必须统一维持基准高度 `272`，严禁单改其一。 |
| **买断产品价格展示** | 1. 简体中文页面与商店介绍：严格统一展示 `¥18`；<br>2. 英文、日文、韩文：严格统一展示 `US$2.99`（禁止同语言并列）；<br>3. 应用内按钮：必须实时拉取 `Product.displayPrice`。 |
| **版本号升级** | 1. `Config.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)；<br>2. `BetweenUs/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`)；<br>3. 官网与更新记录中的版本号声明。 |
| **胶囊瓶开合尺寸** | 调整 `CapsuleJarMetrics` 时，必须同步校验 `Capsule_Open_00`~`04` 图像边界与锚点映射。 |

---

## 6. 历史踩坑与故障归因分类

### 1. CloudKit 写入抛出 `CKError 15` (Server Rejected Request) / 内部错误 `2000`
- **归因**：构建包的 Entitlements 缺少 `com.apple.developer.icloud-container-environment`，或包连到了尚未部署 Schema 的 `Production` 环境。
- **判据**：通过 `codesign -d --entitlements` 查看二进制文件中的环境标记；若为 Release 包，确认 CloudKit Dashboard 是否已完成 Schema 部署。

### 2. 面对面扫码或点击邀请链接报 `CKErrorUnknownItem` (Code 11)
- **归因**：创建方在生成邀请记录时，未将 `CKShare.publicPermission` 预设为 `.readWrite`，系统默认的私有权限使未加入者无法读取该 RecordZone。
- **判据**：检查创建分享的代码路径，确保在生成 URL 前设置 publicPermission，且在对方成功 accept 后及时将其收回为 `.none`。

### 3. 双机联调无法配对或同步无反应
- **归因**：测试设备使用了相同的 Apple ID，或者两台设备一台装了 Debug 包（Development）、另一台装了 TestFlight 包（Production）。
- **判据**：配对双方必须为两套独立的 Apple Account，且两端客户端必须处于完全相同的 CloudKit 环境。

### 4. Swift 编译器遇到复杂闭包/视图推导断言崩溃 (Crash)
- **归因**：嵌套复杂泛型或未标注类型的深层 SwiftUI 表达式耗尽编译器推导栈。
- **处置**：保留一行可 grep 的 `// Intended: <本来要编译成的语义>`，将复杂表达式拆解为局部显式类型常量，先保障业务继续推进，并反馈 Apple Feedback Assistant。
