# 字体使用场景

字体文件在同名目录下，只作为源文件与素材备份。App 不内置这些字体：安装后按需从 CDN 下载，下载完成再注册使用。下面表里的语言、数量、大小都是下载成本，不是包体。

## 分发方式

**内置一款兜底，其余全部走 CDN。**

| 内置字体 | 文件 | 大小 | 为什么是它 |
| --- | --- | --- | --- |
| 霞鹜文楷 | `LXGWWenKai-Regular.ttf` | 24.4 MB | 15 款里覆盖最全（简繁中文、日文、韩文、注音、拉丁全齐），也是其中唯一适合正文长读的字形 |

小赖和 851 手写杂书体同样全覆盖，但一个是呆萌手账体、一个是潦草草稿体，拿来当全 App 的兜底字体气质不对；霞鹜文楷是三者里唯一中性的，缺字时也不会显得突兀。

其余 14 款共 23 个文件、约 230 MB，全部按需下发：

- **按当前角色下载，不做首启预热**。用到哪款下哪款，切换角色时再下另一款；单文件 0.1–27.3 MB，一次最多下一款。
- **落地路径固定**，放 Application Support 而不是 Caches。Caches 被系统清掉后字体文件消失，会直接报 `InvalidFilePath`；路径定下后不要再改，CoreText 按注册时的路径找字体。
- **下载包里要带协议文本**（OFL 的 `OFL.txt`、Homemade Apple 的 Apache-2.0、其余的作者声明）。OFL 要求分发时随附协议与版权声明，只靠 App 内一个链接不算。
- **转发前先确认再分发授权**。下面 7 款的字体文件里没有协议字段，能否放到自家 CDN 需要回发布页确认：汇文明朝体、寒蝉手拙体、851 手写杂书体、江西拙楷体、平方手书体、沐瑶软笔手写体、沐瑶随心手写体。可确认的只有：Caveat、源柔黑体、霞鹜文楷、霞鹜漫黑、悠哉、小赖、得意黑是 OFL 1.1，Homemade Apple 是 Apache 2.0。
- **下载失败或未下载完时用内置那款顶着**，不要因为字体没到位就阻塞写作和查看。

## 星星瓶 · 心动、撒娇、雀跃

| 字体 | 支持语言 | 使用场景 | 数量 | 大小 |
| --- | --- | --- | --- | --- |
| 小赖字体 Xiaolai | 简繁中文、日文、韩文、英文 | 撒娇、黏人、日常小欢喜。呆萌手账体，卸下防备的憨甜 | 2 | 42.4 MB |
| 悠哉字体 Yozai | 简繁中文、日文、英文 | 感谢、轻声告白、小确幸。干净透明的日系轻手写，不腻 | 3 | 43.9 MB |
| 沐瑶软笔手写体 Muyao-Softbrush | 简体中文、英文 | 夸奖、崇拜、庆祝。圆润毛笔触，像把爱意喊出来 | | 4.3 MB |
| 得意黑 SmileySans | 简体中文、日文假名、英文 | 惊喜、元气、俏皮。适合一句很酷又很甜的短句 | | 1.9 MB |

## 胶囊瓶 · 坦诚、深情、承诺

| 字体 | 支持语言 | 使用场景 | 数量 | 大小 |
| --- | --- | --- | --- | --- |
| 霞鹜文楷 LXGWWenKai | 简繁中文、日文、韩文、英文 | 认真沟通、承诺、长文。字字推心置腹，长文最舒服的一款 | 3 | 75.6 MB |
| 汇文明朝体 HuiwenMincho | 简繁中文、日文、英文 | 郑重、岁月沉淀、纪念日。复古活字宋体，安静而庄重 | | 23.3 MB |
| 江西拙楷体 JiangxiZhuokai | 简体中文、英文 | 诚恳道歉、笨拙的爱。木刻手楷，不擅言辞但每句都刻在心里 | | 9.5 MB |
| 源柔黑体 GenJyuuGothic | 繁体中文、日文、英文（简体缺字） | 理智平和、温柔建议。去掉锋芒的圆角黑体 | | 10.1 MB |
| 霞鹜漫黑 LXGWMarkerGothic | 简繁中文、日文、英文 | 商量现实安排、温柔建议。圆角记号笔黑，更松、更像随手写 | | 3.0 MB |

## 纸团篓 · 委屈、脆弱、宣泄

| 字体 | 支持语言 | 使用场景 | 数量 | 大小 |
| --- | --- | --- | --- | --- |
| 寒蝉手拙体 ChillZhuo | 简体中文、英文（假名不全） | 委屈、别扭、情绪发泄。边缘颤抖飞白，像快没水的笔写下的字 | | 3.8 MB |
| 851 手写杂书体 851tegakizatsu | 简繁中文、日文、韩文、英文 | 脆弱、无助、想被抱抱。高低不一的潦草草稿 | | 27.3 MB |
| 平方手书体 PingfangShoushuti | 简体中文、英文 | 生气吐槽、冷战心声。连笔快写，倾斜带毛刺 | | 4.5 MB |

## 生活碎碎念 · 烟火温度

| 字体 | 支持语言 | 使用场景 | 数量 | 大小 |
| --- | --- | --- | --- | --- |
| 霞鹜漫黑 LXGWMarkerGothic | 简繁中文、日文、英文 | 叮嘱、生活琐事。像贴在冰箱门上的即时贴 | | 3.0 MB |
| 沐瑶随心手写体 MuyaoPleased | 简体中文、英文 | 随笔、碎碎念。不卖萌也不讲书法规训的自在书写 | | 3.4 MB |

## 西文

| 字体 | 支持语言 | 使用场景 | 数量 | 大小 |
| --- | --- | --- | --- | --- |
| Caveat | 英文（仅拉丁字母） | 英文便签、轻快表白。向右上扬的连笔，有呼吸感 | 5 | 1.4 MB |
| Homemade Apple | 英文（仅拉丁字母） | 私密叮嘱、深夜留言。细铅笔草书，像塞进对方口袋的信笺 | | 0.1 MB |

## 在 App 里使用

内置的霞鹜文楷随包放在 `BetweenUs/Resources/Fonts/`；其余下载到 Application Support 下的固定目录，
拿到文件后注册，之后按 PostScript 名当内置字体用。

```swift
import CoreText

@discardableResult
func registerCustomFont(at fileURL: URL) -> Bool {
    var error: Unmanaged<CFError>?
    let registered = CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &error)
    guard !registered else { return true }

    // 已经注册过（105）不是失败，只是重复调用
    let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
    if code == CTFontManagerError.alreadyRegistered.rawValue { return true }

    print("Font registration failed: \(String(describing: error))")
    return false
}
```

```swift
// 从 CDN 取回后落在固定路径，再注册。重复调用是安全的：文件已在就只补注册
func installFont(from remote: URL, to fileURL: URL) async throws {
    if !FileManager.default.fileExists(atPath: fileURL.path) {
        let (temp, _) = try await URLSession.shared.download(from: remote)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: fileURL)
    }
    guard registerCustomFont(at: fileURL) else { throw FontError.registrationFailed }
}
```

```swift
Text("今天也想你").font(.custom("Yozai-Regular", size: 17))

// 跟随动态字体
Text("今天也想你").font(.custom("Yozai-Regular", size: 17, relativeTo: .body))
```

### PostScript 名

`Font.custom` 用的是 **PostScript 名**，不是 family 名，本库里两者经常不一样。

| 目录 | PostScript 名 |
| --- | --- |
| `LXGWWenKai/` | `LXGWWenKai-Light`、`LXGWWenKai-Regular`、`LXGWWenKai-Medium` |
| `LXGWMarkerGothic/` | `LXGWMarkerGothic-Regular` |
| `Yozai/` | `Yozai-Light`、`Yozai-Regular`、`Yozai-Medium` |
| `Xiaolai/` | `Xiaolai`、`XiaolaiMono` |
| `SmileySans/` | `SmileySans-Oblique` |
| `GenJyuuGothic/` | `GenJyuuGothic-Regular` |
| `HuiwenMincho/` | `Huiwen-mincho` |
| `JiangxiZhuokai/` | `jiangxizhuokai-Regular` |
| `ChillZhuo/` | `ChillZhuo` |
| `PingfangShoushuti/` | `PFshoushuti` |
| `MuyaoSoftbrush/` | `Muyao-Softbrush` |
| `MuyaoPleased/` | `MuyaoPleased` |
| `851tegakizatsu/` | `851tegakizatsu` |
| `Caveat/` | `Caveat-Regular`、`Caveat-Medium`、`Caveat-SemiBold`、`Caveat-Bold` |
| `HomemadeApple/` | `HomemadeApple-Regular` |

### 注意

- **`.process` 是本进程有效**，每次冷启动都要注册，作用域不要写 `.persistent`。
- **注册过的文件不能改名、移动或丢**。CoreText 按注册时的路径找字体，缺文件会报
  `InvalidFilePath`（306）。CDN 下来的字体要落在固定路径，被清掉后重新下载再注册。
- **只下载并注册当前用得到的**。15 款全下来约 254 MB，注册后 CJK 字体单个常驻 10–27 MB。
- **Caveat 只能二选一**：`Caveat-VariableFont_wght.ttf` 的 PostScript 名和
  `Caveat-Regular.ttf` 一样，`registerCustomFont` 两个都传进去时后者会拿到 105 或 305
  （`DuplicatedName`），结果不确定。要动字重就留可变版，要稳就留静态四档。
- **缺字会掉到系统字体**：江西拙楷体、平方手书体、沐瑶两款没有日文假名和繁体，源柔黑体这个构建缺
  简体常用字，混排时会看到系统字形夹在手写文字里。用之前先确认角色语言。
- **不要用 `CTFontManagerRegisterGraphicsFont`**，iOS 18 起已废弃。走 `CTFontManagerRegisterFontsForURL`。
- 另一条路是 Info.plist 的 `UIAppFonts` 静态注册，但它只适用于随包的那一款，且启动时系统会无条件
  加载（+24 MB）。CDN 下载的字体只能动态注册，也只能用 `.process` 作用域。
