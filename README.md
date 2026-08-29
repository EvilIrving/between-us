# 耳语 · Between us 0.0.1

[官网](https://betweenus.onecat.dev) · [TestFlight / 下载状态](https://betweenus.onecat.dev/download/) · [隐私政策](https://betweenus.onecat.dev/privacy/) · [支持](https://betweenus.onecat.dev/support/)

“耳语”（英文名 `Between us`）是一款原生 iOS 双人关系应用。它不把关系表达做成消息列表，也不依赖任务、金币、角色或连续签到；两个人共同养着一个星星瓶、一只胶囊盒和一个纸团篓。容器会随着双方留下的文字、图片、视频和语音逐渐发生变化。

应用使用 CloudKit 双人共享、离线同步与交换打开机制。用户通过写、折、封、揉、按住、滑动和放入等连续动作完成表达。

## 当前体验

### 共同房间

首页是一个安静的共同房间。三个容器直接摆在架子上，内容数量通过瓶中星星、药盒胶囊和纸篓纸团的积累表现；有新内容时只出现微弱光点，不使用聊天红点、未读列表或“TA 发来一条消息”的叙事。

### 容器动作

- 星星瓶：持续按住瓶子抽取一颗，松手过早不会打开。
- 胶囊盒：持续按住后打开一颗，不使用传统主按钮。
- 纸团篓：持续按住更长时间才展开，任何时候松手都会中止。
- 留下自己的内容：拿起一个空白物件进入制作场景。

### 文字

文字写在一张会根据容器变化的纸面上。完成后把星星、胶囊或纸团向上推入容器口，超过触发距离后才保存；没有单独的“发送”或“确认”按钮。字符计数只在接近上限时出现。

### 图片与视频

图片与视频通过系统照片选择器加入，可附带一段简短文字，然后通过同一套向上放入动作封存。图片显示相纸预览，视频可在打开内容后直接播放。

### 语音

语音是独立的专注模式：

- 第一次进入语音模式时先完成麦克风授权，避免按住后仍在等待系统权限。
- 按住开始录音。
- 向左滑动超过取消阈值后，松手取消。
- 正常松手后直接封存到当前容器。
- 向上滑动可锁定录音；松手后继续录制，点按停止并进入试听与波形拖动。
- 红点明确表示正在录音。
- 时长以十分之一秒更新，例如 `0:02.9`。
- 波形根据 `AVAudioRecorder` 的实时电平变化。
- 录音太短、权限不可用和保存失败均有非系统弹窗式的场景内反馈。
- 保存失败时语音草稿会保留，可再次向上推入或丢弃重录。
- 从按下到松开属于专注状态，期间关闭和模式切换暂时失效。
- VoiceOver 可通过“开始录音”“完成并放入”“取消录音”三个辅助动作完成同一流程。
- 来电、音频会话中断或进入后台时会立即丢弃未完成录音，并在返回后给出场景内说明。

### 打开与回应

打开后的内容使用完整的拆星星、分开胶囊或摊平纸团动画，再展示正文与媒体。回应通过重新折一颗星星、封一颗胶囊或揉一个纸团放回共同空间完成，保持“共同容器”而非聊天线程的心智模型。

## 核心能力

- 原生 SwiftUI，最低支持 iOS 17。
- 星星瓶使用 SpriteKit 与 CoreMotion 提供轻量物理反馈。
- CloudKit 自定义记录区、区域级 `CKShare` 和系统邀请。
- 创建者私有数据库与参与者共享数据库。
- 私有/共享数据库各自的 `CKSyncEngine`。
- 离线本机缓存、待上传恢复、基础冲突合并和账号变化处理。
- 支持写入文字、图片、视频和语音。
- 容器变化和“对方已打开”弱提醒，通知不展示正文。
- 共同空间管理、参与者退出和创建者删除。
- “我的抽屉”查看自己留下的内容及打开状态。
- 界面支持简体中文、英文、日文和韩文，可跟随系统或在设置中即时切换。
- 无第三方依赖，无自建业务服务器。

## 数据

CloudKit 使用 `BetweenUsRelationship`、`BetweenUsItem` 记录类型与 `iCloud.cain.com.between-us` 容器。`BetweenUsItem.attachmentKind` 写入 `image`、`video` 或 `audio`；正文、作者标识和打开状态写入 `CKRecord.encryptedValues`，媒体使用 `CKAsset`。

## 工程结构

```text
BetweenUs/
├── App/          App 生命周期、共享邀请、推送与本地提醒
├── Models/       关系、内容、附件与界面状态模型
├── Store/        CKSyncEngine、CKShare、离线队列与冲突处理
├── Storage/      本机状态、媒体文件与实时电平录音
├── Views/        共同房间、制作、打开、抽屉和设置
├── Components/   仪式交互、长按/拖动控件、语音手势、物件插画与物理场景
├── Design/       场景色彩、材质与光影
└── Resources/    简体中文、英文、日文、韩文本地化资源
```

视觉与动效的长期标准见 [VISUAL_MOTION_DESIGN.md](VISUAL_MOTION_DESIGN.md)。核心物件采用程序化视觉系统：共享的参数曲线负责轮廓，统一材质模型负责光影，交互状态直接驱动盖口、内容物与容器形变；外部美术资源只作为背景或未来可替换增强层。

核心交互组件包括：

- `RitualDepositControl`：向上推入容器的提交手势。
- `HoldToCompleteSurface`：长按进度、取消、完成和辅助操作的共享状态机。
- `ParametricGeometry`：圆角星形、超椭圆、胶囊体、对称剖面与有机纸形的共享数学内核。
- `ContainerVisual`：首页、详情、引导与加载共同使用的参数化容器渲染器。
- `VoiceHoldRecorderView`：按住录音、左滑取消和松手完成。
- `AmbientRoomBackground`：共同房间与各容器场景的统一环境层。
- `WhisperNoticeBanner`：替代核心流程中的系统 Alert。

## 开始运行

先阅读 [CLOUDKIT_SETUP.md](CLOUDKIT_SETUP.md)，确认根目录 `Config.xcconfig` 中的团队与标识，再用 Xcode 打开 `BetweenUs.xcodeproj`。确认 iCloud、CloudKit、Push Notifications 与 Background Modes 中的 Remote notifications 已启用，然后在登录 iCloud 的真机运行。

双人分享测试应使用两台真机和两个不同的 Apple 账号。新容器需先在 Development 真机成功创建一次共享，确认 `BetweenUsRelationship`、`BetweenUsItem` 和系统类型 `cloudkit.share` 已生成，再部署到 Production。

官网是 `website/` 下的无构建静态站点，发布和下载地址配置见 [website/README.md](website/README.md)。

## 版本

工程版本为 `0.0.1`，构建号为 `1`；当前未发布改动见 [CHANGELOG.md](CHANGELOG.md)。
