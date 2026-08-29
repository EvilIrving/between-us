# App Store 首发提交材料

本文是 `0.0.1 (1)` 首发版本的 App Store Connect 内容底稿。当前构建已接入 StoreKit 2 非消耗型购买、恢复购买、免费额度拦截、单条删除释放额度，以及当前空间的双人权益同步。正式提交前仍须在 App Store Connect 创建并随版本送审对应产品。

## 买断方案

- 免费版：双方在三个容器中最多同时保留 10 条内容，删除后释放额度。
- 永久版：一次性购买后内容数量不限，不提供订阅。
- 一人购买，整个双人空间共享权益。
- 中国区：¥18 永久买断。
- 美国区：US$2.99 永久买断；其他地区采用 App Store 对等价格。

### App Store Connect 配置

- 类型：Non-Consumable。
- Product ID：`cain.com.between-us.lifetime`，必须与工程中的 `CommerceConfiguration.lifetimeProductID` 完全一致。
- Reference Name 建议：`Whisper Lifetime`。
- 不启用 App Store Family Sharing；双人共享由当前受邀共同空间负责，避免把权益扩展到与该空间无关的家庭成员。
- 中国大陆价格手动设为 ¥18，美国价格手动设为 US$2.99；其他地区使用 App Store 对等价格。
- 为简体中文、英文、日文、韩文填写本地化显示名与说明，并上传永久版购买页的审核截图。
- 确认 Paid Apps Agreement、税务与收款资料有效，选择销售地区，再把此 App 内购买与首发版本一并提交审核。
- 产品尚未在 App Store Connect 创建或可售时，应用会保留免费额度逻辑，并在购买页显示无法连接 App Store，不会伪造本地价格。

## 全局信息

- Bundle ID：`cain.com.between-us`
- SKU 建议：`between-us-ios`
- 主分类建议：生活
- 次分类建议：社交
- 隐私政策：`https://betweenus.onecat.dev/privacy/`
- 支持：`https://betweenus.onecat.dev/support/`
- 营销网址：`https://betweenus.onecat.dev/`
- 版权：需由账号持有人填写真实个人或主体名称
- 审核联系人邮箱与国际格式手机号：需由账号持有人填写

## 简体中文

### 名称

耳语

### 副标题

两个人的私密空间

### 宣传文本

把想说的话放进共同的星星瓶、胶囊盒和纸团篓。没有聊天列表，也没有连续签到。

### 描述

耳语是为两个人设计的私密空间。

它不是聊天列表。你们把文字、照片和语音放进共同养着的三个容器，等对方准备好时再亲手打开。

星星瓶收好喜欢、感谢和想分享的事；胶囊盒装下需要认真说、慢慢听的话；纸团篓接住委屈、生气和其他不开心。

在耳语里，表达不是点一下“发送”。你会写、折、封、揉、按住，再把一件东西放进容器。留下的内容会变成共同房间里看得见的积累，不会被新的消息推走。

主要功能：

• 支持文字、照片和语音
• 星星瓶、胶囊盒和纸团篓三种表达方式
• 通过 Apple iCloud 邀请另一位伴侣加入
• 本机离线保存，联网后通过 CloudKit 同步
• 通知只提示容器发生变化，不展示内容正文
• 不使用广告追踪或第三方分析 SDK
• 支持简体中文、English、日本語和 한국어

每个人使用自己的 Apple 账号。双人共享需要登录 iCloud。耳语支持 iOS 17 或更高版本的 iPhone 与 iPad。

### 关键词

情侣,伴侣,关系,私密,日记,心情,语音,照片,双人,iCloud

## English

### Name

Between us

### Subtitle

A quiet space for two

### Promotional text

Leave words, photos, and voice notes in three shared vessels. No chat feed, unread pressure, or streaks.

### Description

Between us is a private space made for two people.

It is not a chat feed. You leave words, photos, and voice notes inside three vessels you care for together, then open them when the other person is ready.

The Star Jar holds affection, gratitude, and small things worth sharing. The Capsule Box keeps conversations that deserve time and attention. The Paper Basket gives difficult feelings somewhere safe to land.

There is no Send button. You write, fold, seal, crumple, hold, and place something into a vessel. What you leave becomes a visible part of your shared room instead of another message pushed up a timeline.

Features:

• Text, photos, and voice notes
• Three distinct ways to express what you feel
• Private invitations through Apple iCloud
• Offline local saving with CloudKit sync when connected
• Discreet notifications that never reveal your content
• No advertising tracking or third-party analytics SDKs
• Simplified Chinese, English, Japanese, and Korean

Each person uses their own Apple Account. Shared spaces require iCloud. Between us supports iPhone and iPad running iOS 17 or later.

### Keywords

couples,relationship,private,journal,voice,photos,two,iCloud,shared

## 日本語

### 名前

ささやき

### サブタイトル

ふたりだけの静かな共有空間

### プロモーションテキスト

ことば、写真、声を、ふたりで育てる3つの入れものへ。チャットの流れも、未読のプレッシャーも、連続記録もありません。

### 説明

ささやきは、ふたりのための静かな共有空間です。

チャットのタイムラインではありません。ことばや写真、声を3つの入れものに残し、相手が受け取れるときに、手で開きます。

星のびんには、好きな気持ちや感謝、伝えたい小さなことを。カプセルボックスには、ゆっくり向き合いたい話を。紙くずかごには、悲しさや怒り、言葉にしにくい気持ちを預けられます。

「送信」ボタンはありません。書く、折る、封をする、丸める、長押しする、入れものにしまう。残したものはメッセージに流されず、ふたりの部屋に少しずつ積み重なります。

主な機能：

• ことば、写真、音声に対応
• 気持ちに合わせた3つの入れもの
• Apple iCloudを使った招待と共有
• オフライン保存とCloudKit同期
• 内容を本文に表示しない控えめな通知
• 広告トラッキング、外部解析SDKなし
• 简体中文、English、日本語、한국어に対応

それぞれが自分のApple Accountを使います。共有にはiCloudへのサインインが必要です。iOS 17以降のiPhoneとiPadに対応しています。

### キーワード

ふたり,カップル,関係,日記,気持ち,音声,写真,共有,iCloud

## 한국어

### 이름

속삭임

### 부제

둘만의 조용한 공간

### 홍보 문구

글과 사진, 목소리를 함께 돌보는 세 개의 보관함에 남겨 보세요. 채팅 목록도, 읽지 않음의 압박도, 연속 기록도 없습니다.

### 설명

속삭임은 두 사람을 위한 조용하고 사적인 공간입니다.

채팅 타임라인이 아닙니다. 글과 사진, 음성을 세 개의 보관함에 남기고, 상대가 준비되었을 때 직접 열어 봅니다.

별 병에는 좋아하는 마음과 고마움, 나누고 싶은 작은 일을 담습니다. 캡슐 상자에는 천천히 듣고 진지하게 이야기할 내용을 넣습니다. 종이 뭉치 바구니에는 서운함과 화, 말하기 어려운 감정을 내려놓을 수 있습니다.

‘보내기’ 버튼은 없습니다. 쓰고, 접고, 봉하고, 구기고, 길게 누른 뒤 보관함에 넣습니다. 남긴 내용은 새 메시지에 밀려나지 않고 둘만의 공간에 차곡차곡 쌓입니다.

주요 기능:

• 글, 사진, 음성 지원
• 감정에 맞춘 세 가지 보관함
• Apple iCloud를 통한 비공개 초대
• 오프라인 저장과 CloudKit 동기화
• 내용 본문을 표시하지 않는 알림
• 광고 추적 및 타사 분석 SDK 없음
• 简体中文, English, 日本語, 한국어 지원

각자 자신의 Apple Account를 사용합니다. 공간에는 iCloud 로그인이 필요합니다. iOS 17 이상이 설치된 iPhone과 iPad를 지원합니다.

### 키워드

커플,연인,관계,일기,감정,음성,사진,공유,iCloud

## App Review Notes

```text
Between us uses Apple iCloud and CloudKit for its two-person space. The app does not have an app-specific username or password.

To review the core experience without a second device or Apple Account:
1. On the first screen, tap “Local Preview”.
2. The preview loads sample content into all three vessels.
3. Reviewers can open existing items, add text or a photo, record a voice note, inspect the drawer and settings, and leave the preview.

Local Preview stores data only on the review device, does not sync to iCloud, and does not enforce the space quota.

To test the real shared flow, use two devices signed in to different Apple Accounts. On the first device, hold “Invite” to create a space and present Apple’s iCloud sharing sheet. Open the invitation on the second device. The app has no public profiles, user search, random matching, or anonymous chat.

To review the non-consumable In-App Purchase, create or join a real iCloud space, then open Settings > Content Space > Free. The free space can keep up to 10 items at once. The product `cain.com.between-us.lifetime` removes that limit permanently. After one person completes a verified purchase, the current CloudKit space is marked as unlocked; the invited person receives unlimited access through that space state and does not need to purchase or restore separately. “Restore Purchases” is available on the purchase screen.

Microphone permission is requested only after the reviewer chooses the voice mode. Notifications are optional and never include the user’s text, photos, or audio.
```

## App Privacy 填写底稿

采用保守口径，App 将用户主动创建的数据长期保存在其设备和 Apple CloudKit 中，因此不要在 App Store Connect 选择“本 App 不收集数据”。

| 数据类型 | 用途 | 与用户关联 | 用于追踪 |
|---|---|---:|---:|
| 用户 ID（CloudKit 用户记录标识） | App 功能 | 是 | 否 |
| 其他用户内容（文字） | App 功能 | 是 | 否 |
| 照片或视频 | App 功能 | 是 | 否 |
| 音频数据 | App 功能 | 是 | 否 |

不申报广告、营销、第三方分析、跨 App 追踪、联系人、位置、健康、支付或浏览历史。

## 年龄分级填写底稿

- App 内控制：无家长控制、无年龄验证。
- 功能能力：包含邀请制双人用户内容与私密交流；无公开信息流、陌生人匹配、匿名聊天或网页浏览。
- 内容描述：开发者不提供暴力、色情、药物、赌博或恐怖内容。
- 用户可以自行写入文字、照片和语音，因此用户生成内容与交流能力按实际情况选择“是”。
- 不选择 Made for Kids。

最终分级以 App Store Connect 问卷计算结果为准，不在商店文案中自行承诺具体年龄数字。

## 截图文案与顺序

商店截图必须重新从当前应用以 App Store 接受的原始设备分辨率截取，不使用官网的 `804 × 1748` WebP 放大。

1. 首页：三个容器，不是一串消息
2. 星星瓶：把喜欢折成一颗星星
3. 胶囊盒：把认真沟通装进胶囊
4. 纸团篓：让难说的话有地方落下
5. 制作：写下，再亲手放进去
6. 打开：准备好时，再慢慢打开

优先准备简体中文与英文两套；日文和韩文可复用同一组真实界面后替换叠加文案。
