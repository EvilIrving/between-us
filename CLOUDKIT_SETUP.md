# CloudKit 与开发者账号配置

本文从一个已加入 Apple Developer Program 的账号开始。工程已经包含 CloudKit、共享、推送和后台远程通知所需代码，但 Bundle ID、iCloud Container、开发团队、签名和 Production Schema 必须由你在自己的账号下配置。

## 一、确认工程标识

根目录 `Config.xcconfig` 当前绑定以下标识：

```xcconfig
APP_BUNDLE_IDENTIFIER = cain.com.between-us
CLOUDKIT_CONTAINER_ID = iCloud.cain.com.between-us
DEVELOPMENT_TEAM_ID = QZZ878S3NS
```

如果改由其他开发者团队签名，请同时替换这三个值，并在该团队下创建对应标识。Bundle ID 和 iCloud Container ID 必须唯一；确定后不要再更换 CloudKit Container ID，因为数据和分享链接都归属于该容器。

## 二、在开发者账号中建立标识

在 Apple Developer 的 Certificates, Identifiers & Profiles 中创建或确认以下资源：

1. 一个与 `APP_BUNDLE_IDENTIFIER` 完全一致的显式 App ID。
2. 一个与 `CLOUDKIT_CONTAINER_ID` 完全一致的 iCloud Container。
3. 在 App ID 上启用 iCloud，并关联该容器。
4. 在 App ID 上启用 Push Notifications。

使用 Xcode 自动签名时，部分资源可以由 Xcode创建，但仍应在开发者后台确认 App ID、容器和能力关联正确。

## 三、在 Xcode 中启用能力

用 Xcode 16 或更高版本打开 `BetweenUs.xcodeproj`，选中 `BetweenUs` Target，在 Signing & Capabilities 中完成：

1. 勾选 Automatically manage signing，并选择你的 Team。
2. 添加 iCloud capability，勾选 CloudKit，并选中与 `CLOUDKIT_CONTAINER_ID` 相同的容器。
3. 添加 Push Notifications capability。
4. 添加 Background Modes capability，只勾选 Remote notifications。
5. 检查生成的签名错误；不要让 Xcode创建另一个与配置文件不同的 iCloud Container。

工程中的 `BetweenUs.entitlements` 已声明 CloudKit 容器和 APNs 环境，`Info.plist` 已包含 `CKSharingSupported`、SceneDelegate、远程通知后台模式和麦克风用途说明。Xcode 如按你的账号重写 entitlement，以 Signing & Capabilities 面板生成的有效签名配置为准。

## 四、第一次运行与开发 Schema

使用一台已登录 iCloud 的真机运行 Debug 版本。首次启动后：

1. 创建共同空间。
2. 至少分别放入一颗星星、一颗胶囊和一个纸团。
3. 至少测试一份图片、一份视频和一份语音附件。
4. 在 CloudKit Console 选择你的容器和 Development 环境，确认自定义记录类型以及系统生成的 `cloudkit.share` 已经出现；`cloudkit.share` 只有在开发环境成功保存过一次共享后才会生成。

工程会使用以下自定义记录类型，不需要 Query Index：

| 记录类型 | 字段 | 类型与用途 |
|---|---|---|
| `BetweenUsRelationship` | `schemaVersion` | Int64，当前为 1 |
| `BetweenUsRelationship` | `createdAt` | Date/Time，关系创建时间 |
| `BetweenUsRelationship` | `ownerID` | Encrypted String，创建者的 CloudKit 用户标识 |
| `BetweenUsItem` | `schemaVersion` | Int64，当前为 1 |
| `BetweenUsItem` | `kind` | String，`star`、`capsule` 或 `paper` |
| `BetweenUsItem` | `text` | Encrypted String，正文，可为空字符串 |
| `BetweenUsItem` | `authorID` | Encrypted String，作者标识 |
| `BetweenUsItem` | `createdAt` | Date/Time，创建时间 |
| `BetweenUsItem` | `updatedAt` | Date/Time，最后状态更新时间 |
| `BetweenUsItem` | `openedByID` | Encrypted String，可选，打开者标识 |
| `BetweenUsItem` | `openedAt` | Encrypted Date/Time，可选，打开时间 |
| `BetweenUsItem` | `attachmentKind` | String，可选，`image`、`video` 或 `audio` |
| `BetweenUsItem` | `attachment` | Asset，可选，媒体文件 |
| `BetweenUsItem` | `originalFilename` | String，可选，显示用文件名 |
| `BetweenUsItem` | `duration` | Double，可选，语音时长 |
| `BetweenUsItem` | `byteCount` | Int64，可选，附件字节数 |

`CKShare` 是 CloudKit 系统记录，不能在 Console 中手工创建；工程第一次在 Development 环境成功创建共同空间后，CloudKit 会生成对应的 `cloudkit.share` 系统类型。正文等字段通过 `CKRecord.encryptedValues` 写入，CloudKit Console 中的字段表现应与普通未加密字段不同。

## 五、双人分享测试

分享测试建议使用两台真机、两个不同的 Apple 账号，以及同一个开发团队签名出来的 App：

1. 设备 A 创建共同空间，系统共享面板会出现。
2. A 通过“信息”、邮件或复制链接把邀请发给设备 B。
3. B 打开邀请并接受，系统应切回 App，B 的数据来源显示为共享数据库。
4. A 与 B 分别放入同类内容，验证双方只有在自己留下内容后才能打开一次。
5. 验证 A 打开 B 的内容后，B 的“我的抽屉”状态会更新；开启提醒后，B 会收到不含正文的通知。
6. 断开一台设备网络，写入内容，再恢复网络，验证最终同步。
7. 测试创建者停止共享、参与者退出以及创建者彻底删除共同空间。

CloudKit 分享和静默推送在模拟器中的行为不适合作为最终验收依据。正式验收应使用真机，并确认两台设备都开启了 iCloud Drive、网络和本 App 的通知权限。


## 六、部署 Production Schema

Development 和 Production 是两套独立环境。Development 中运行成功不代表 TestFlight 可以直接使用。上传任何 TestFlight 或 App Store 构建前：

1. 进入 CloudKit Console，选择正确容器。
2. 在 Development 环境确认 `BetweenUsRelationship`、`BetweenUsItem` 以及系统类型 `cloudkit.share` 均已出现；若没有 `cloudkit.share`，先用 Debug 真机完整创建一次共同空间。
3. 使用 Deploy Schema Changes，把开发 Schema 部署到 Production。
4. 切换到 Production，确认记录类型和字段已经存在。
5. 再上传 TestFlight 构建，用两个测试账号完成一次全新创建和邀请。

Production Schema 部署后不应删除或改变已有字段类型。后续版本只新增可选字段。

## 七、签名与推送检查

Debug 真机通常使用 APNs development 环境，TestFlight 与 App Store 使用 production 环境。归档时让 Xcode 使用与你的 App ID 能力一致的 Distribution Profile，并在导出后检查最终签名 entitlement，而不是只检查源码中的 `.entitlements` 文件。

可在 macOS 终端对归档产物执行：

```bash
codesign -d --entitlements :- "/path/to/Between us.app"
```

最终结果应包含正确的 `aps-environment`、CloudKit container identifier 和 CloudKit service。若 Xcode 报 provisioning profile 与 entitlement 不匹配，优先回到 Signing & Capabilities 删除并重新添加对应能力，让自动签名重新生成配置。

## 八、常见问题

“未能找到 iCloud 容器”通常表示 `Config.xcconfig`、entitlement、Xcode capability 和开发者后台使用了不同的 Container ID。

“邀请无效”通常表示创建邀请与接受邀请的构建没有使用同一个 CloudKit Container。

Development 正常而 TestFlight 无法创建记录，通常是 Production Schema 尚未部署，或 Distribution Profile 未包含 iCloud/推送能力。

能看到内容但没有提醒，不代表同步失败。CloudKit 推送是尽力而为的变化信号，系统可能延迟后台唤醒；重新打开 App 或下拉刷新应仍能取得真实记录。

附件长期显示等待下载时，先确认 iCloud 配额、网络和单个附件是否超过 48 MB，再查看 Xcode Console 中的 CloudKit 错误。
