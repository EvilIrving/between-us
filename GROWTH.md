# Growth Context

*Last updated: 2026-08-30*

## Product
- **Name:** 耳语 / Between us
- **One-liner:** 把两个人的心意，留在共同的星星瓶、胶囊盒和纸团篓里。
- **What it does:** 耳语是一款原生 iOS 双人关系应用。两个人可以把文字、图片、视频和语音留在共同的星星瓶、胶囊盒与纸团篓里，看着星星、胶囊和纸团随着双方留下的内容慢慢变多。它不使用聊天时间线、任务、金币或连续签到，而是通过写、折、封、揉、按住与放入等动作，让表达更像一件被认真留下的东西。
- **Category:** iOS couples app / private relationship app / 双人关系应用

## Platform & distribution
- **Platform / requirements:** iPhone 与 iPad，iOS 17 或更高版本；核心双人共享需要 iCloud 与 CloudKit。
- **App languages:** 简体中文、英文、日文、韩文；支持跟随系统或在设置中切换。
- **How it ships / installs:** 正式版本计划通过 Apple App Store 发布；发布前测试计划通过 TestFlight 提供。
- **Updates:** App Store 自动或手动更新。
- **Repo:** https://github.com/EvilIrving/between-us
- **Site:** https://betweenus.onecat.dev（Cloudflare Pages）

## Pricing model
- 免费版的空间最多同时留下 10 件，按双方留下的星星、胶囊和纸团总数计算；删除单件内容或清空全部内容后会立即腾出位置。
- 只提供一次性永久买断，不提供任何订阅。买断后取消内容数量上限。
- 一人购买后，两人所在的空间同时解锁。
- 确认首发价格：中国区 ¥18，海外以美国区 US$2.99 为基准使用 App Store 对等价格。
- 静态价格文案按语言展示：简体中文只显示 ¥18；英文、日文、韩文只显示 US$2.99。应用内购买按钮仍显示 StoreKit 返回的实际结算价格。
- 当前构建已接入 StoreKit 2 永久买断、恢复购买、10 条额度拦截、单条删除释放额度和空间权益同步；正式销售仍依赖 App Store Connect 中的非消耗型产品 `cain.com.between-us.lifetime` 完成配置并通过审核。

## Audience
- **Who it's for:** 希望在即时聊天之外，保留一个安静、私密表达空间的伴侣与亲密关系双方。
- **Why they reach for it:** 想认真留下一段文字、一张图片、一段视频或一段声音，又不希望这份表达被聊天流、已读状态或连续签到变成压力。

## Differentiators (ranked, all true)
- 不是聊天时间线：双方共同养着星星瓶、胶囊盒与纸团篓，内容以物件而非消息存在。
- 表达通过写、折、封、揉、按住、滑动和放入等连续动作完成，不依赖标准表单与发送按钮。
- 不使用任务、金币、等级、胜负或连续签到制造关系压力。
- 原生 SwiftUI 应用，使用 Apple CloudKit 的双人共享、离线缓存与同步，不依赖第三方 SDK 或自建业务服务器。
- 支持文字、图片、视频和语音；提醒不展示内容正文。

## Competitors / alternatives

首轮官网不做未经调研的竞品比较。正式发布定位研究后再补充。

| Name | Model | Honest strength | How we differ |
|------|-------|-----------------|---------------|
| | | | |

## Channels
- **Where this audience is:** App Store、TestFlight、Product Hunt；中文内容可在小红书与即刻展示真实使用场景，英文内容可在适合独立应用与 iOS 应用发现的社区发布。具体社区在 launch 阶段核对规则后确定。
- **Languages to publish in:** 简体中文与英文。

## Voice
- **Tone:** 安静、克制、具体，有温度但不煽情；面向普通用户，不使用 SaaS 或游戏化话术。
- **Words to use / avoid:** 使用“放进去”“共同房间”“星星瓶里多了一颗星星”“留下一件东西”；面向用户时不要使用抽象的“容器”，应具体说“星星瓶、胶囊盒、纸团篓”或“空间”。避免“发送”“收到消息”“回复”“未读”“打卡”“连续天数”“养成任务”。中文不滥用破折号，英文不用 em dash。

## Proof points (REAL only)

暂无公开用户数、下载量、评价或媒体背书，不在公开页面使用虚构数字。

## Links
- **Download / availability:** https://betweenus.onecat.dev/download/
- **Privacy:** https://betweenus.onecat.dev/privacy/
- **Support:** https://betweenus.onecat.dev/support/
- **Social handles / accounts:** 待补充。
- **Press / contact:** 待补充。
