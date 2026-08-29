# Between us 交互设计说明

> 更新：2026-08-30

## 设计目标

产品需要具有“共同养着一些东西”的持续吸引力，但不能变成有任务、等级、金币或胜负的游戏。养成感来自三个真实物件随关系积累而变化，而不是来自外部奖励。

核心语言统一为：

- 不说“发送”，说“放进去”。
- 不说“收到消息”，说“容器发生了变化”。
- 不说“回复”，说“也留下一件自己的东西”。
- 不展示时间线，不把双方表达串成聊天线程。
- 不用强红点催促，纸团尤其不制造必须立即处理的压力。

## 场景分层

### 共同房间

首页负责维持关系的长期存在感，只展示三个容器、微弱变化和进入入口。容器内容数量直接反映积累，避免数字仪表盘。

### 容器场景

每个容器只有两个核心动作：

1. 直接持续按住容器本体，从共同容器中取出一件；进度同时驱动盖口或容器形变。
2. 拿起一个空白物件，进入制作场景。

交换额度仍由 Store 计算，但界面用光、珠点和自然语言表达，不把它呈现为游戏货币。

### 制作场景

文字、图片/视频和语音不是三个附件按钮，而是三种不同的创作姿态。模式切换会移除当前媒体草稿，避免一条内容叠加复杂附件。

## 文字状态机

```text
empty → editing → ready → dragging → thresholdReached → saving → dismissed
                       ↘ cancelledDrag → ready
                       ↘ saveFailed → ready
```

向上拖动未超过阈值时不保存；越过阈值时触发一次中等触觉反馈，松手后执行 Store 写入。

## 图片与视频状态机

```text
empty → systemPhotoPicker → importing → preview → ready → dragging → saving
                   ↘ cancel → empty       ↘ remove → empty
                                            ↘ saveFailed → preview
```

系统 PhotosPicker 用于选择图片和视频，选择完成后立即回到自定义媒体场景。图片使用相纸预览，视频使用明确的播放标识。

## 语音状态机

```text
enterVoiceMode
  → requestingPermission
      → denied → inlineHint → idleUnavailable
      → granted → idleReady
idleReady
  → fingerDown
  → preparingSession
  → recording
      → slideLeftBelowThreshold → recording
      → slideLeftPastThreshold → armedToCancel
          → slideBack → recording
          → release → discard
      → slideUpPastThreshold → lockedRecording
          → release → lockedRecording
          → tapPause → stop → preview
              → playOrScrub → preview
              → discard → idleReady
              → deposit → save
      → releaseUnderMinimumDuration → discard + hint
      → normalRelease → stop + save
          → saveSuccess → dismiss
          → saveFailed → retainedDraft
              → dragUpRetry → save
              → discard → idleReady
```

关键规则：

- 长按开始，松手完成，向左滑取消。
- 上滑越过阈值后锁定；松手继续录音，点击暂停图标停止并进入预览。
- 录音状态不展示删除或发送按钮；预览在同一录音舞台原地切换为播放、可拖动波形和删除重录，最终仍使用制作场景的放入手势。
- 录音手势生命周期只由 `idle / holding / locking / locked / producingDraft` 单一阶段驱动；停止是 recorder 与正式音频草稿之间的状态边界。
- 第一次进入语音模式时先请求权限；只有权限准备完成后才允许开始按住。
- 录音会话仍使用会话标识保护，按住状态消失后即使异步启动返回也会立即丢弃。
- 红点只代表 `AVAudioRecorder` 已真实进入录音状态。
- 计时每 50 ms 更新，显示到十分之一秒。
- 音量波形来自 `averagePower(forChannel:)` 的归一化结果。
- 正常松手后直接写入当前容器，不增加确认步骤。
- 权限准备、录音器准备和真实录音期间，关闭控件与模式切换暂时失效，避免会话被中途拆断。
- VoiceOver 不要求复刻滑动手势，提供开始、完成与取消三个等价辅助动作。
- 来电、系统音频中断或进入后台会丢弃未完成录音、复位手势状态，并给出非模态说明。

## 打开状态机

星星与胶囊采用短持续按住，纸团采用更长持续按住：

```text
idle → pressing → progress → completed → storeOpen → unsealAnimation → content
          ↘ releasedEarly → idle
```

纸团中途松手永远不打开，以替代“你确定吗”的系统弹窗。持续按住本身同时承担主动选择、冷静时间和误触保护。

## 回应

打开内容后不出现回复输入框。回应入口进入同类制作场景，因此双方表达仍是两个独立物件，而不是一条消息下面的往返讨论。

## 触觉层级

- 模式切换、轻触物件：selection。
- 开始长按、开始录音：soft/medium impact。
- 越过保存或取消阈值：medium/warning。
- 成功放入或完成打开：success。

触觉只确认状态变化，不作为奖励或连续刺激。

## 系统 UI 的保留边界

以下系统 UI 保留，因为它们属于系统权限或共享边界，而不是产品核心体验：

- PhotosPicker。
- CloudKit 的系统共享面板。
- 麦克风权限弹窗。
- 跳转系统设置。

核心流程不使用系统 Alert、confirmationDialog、Form、分段 Picker、标准提交按钮或消息式回复框。制作场景允许在小屏和键盘出现时滚动，但放入与录音手势优先于滚动识别。

## 本地化

- 界面支持简体中文、英文、日文和韩文，并可跟随系统语言。
- 用户在设置中切换语言后立即刷新当前界面，不要求重启 App。
- 功能状态与操作标签优先保持短句；布局必须允许英文、日文和韩文自然伸缩，不依赖固定中文字符宽度。
- 麦克风权限说明等系统文案与应用内语言资源保持同一组语言覆盖。
