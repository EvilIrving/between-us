# 1.1.0 交付校验

该 ZIP 在 Linux 构建环境中完成以下静态校验；解压后可在工程根目录运行 `python3 Scripts/validate_project.py` 复验：

- 33 个 Swift 文件全部通过 `swiftc -parse`。
- `Info.plist`、entitlements 和 Privacy Manifest 通过 plist 解析。
- App Icon 为 1024 × 1024 PNG，Asset Catalog JSON 可解析。
- Xcode 工程中的所有 Swift 文件均有文件引用，并且在 Sources Build Phase 中恰好出现一次。
- 版本号为 1.1.0，构建号为 2，最低系统为 iOS 17.0。
- `RitualDepositControl`、`HoldToOpenControl`、`VoiceHoldRecorderView`、左滑取消阈值、十分之一秒时长、首次权限准备、小屏滚动与 VoiceOver 辅助动作均存在。
- 核心 Views 中没有 `.alert`、`.confirmationDialog` 或旧的分段筛选 Picker。
- CloudKit Store、数据模型、App 同步入口、entitlements 与隐私配置和提供的 1.0.0 工程逐文件比对未发生变化；1.1.0 不需要 Schema 迁移。
- 文件清单会检查重复路径、缺失路径、过期路径与 SHA-256；ZIP 在生成后执行解压复验和再次静态校验。

本环境没有 macOS、Xcode、iOS SDK、代码签名身份和你的 CloudKit 容器，因此没有声称完成以下项目：

- `xcodebuild` 编译、Archive 或 App Store 签名。
- 麦克风权限弹窗、真实音量电平和触觉反馈的真机验证。
- 两台设备、两个 Apple 账号的邀请与 CKShare 联调。
- Production CloudKit Schema、APNs 和 TestFlight 验收。

这些项目必须按 `CLOUDKIT_SETUP.md` 与 `RELEASE_CHECKLIST.md` 在 macOS 和真机完成。
