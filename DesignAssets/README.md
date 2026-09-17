# 资产源文件

核心物件的源目录。这里的文件名与运行时资产名一一对应，正式运行时资产在 `BetweenUs/Assets.xcassets`；改完源文件要同步过去。

位图负责身份、材质和配准，代码负责物理、开合、揭示与状态。三个物件的画布、瓶口和槽位由代码里的度量常量统一定义，源图按同一套归一化坐标出图：

- 星星瓶：`StarJarMetrics`
- 胶囊瓶：`CapsuleJarMetrics`
- 纸团篓：`TrashBinPhysicsSystem`

## capsule

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `Capsule_Closed` | 256×256 | 封好的胶囊，投入与揭示飞行使用 |
| `Capsule_Top` / `Capsule_Bottom` | 256×256 | 打开后分离的上下两半 |
| `Capsule_Open_00`–`04` | 724×724 | 合盖到全开的连续帧；`00` 是静置外观，`04` 是可见内腔的物理承载帧 |

胶囊三张 token 画布为 256×256；`Capsule_Closed` 不透明主体约 75×228，对应 `CapsuleJarMetrics.tokenAspect`。

## starjar

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `StarJar_Body` | 724×724 | 星星瓶瓶身，同时是出瓶结局的前景层 |
| `StarJar_Lid` | 724×724 | 瓶盖 |
| `01/`–`05/` `StarCharm_{Style}_{Emotion}` | 256×256 | 五系列 × 六情绪的挂件位图 |

`Style` 为 `Candy`、`Silver`、`Handmade`、`Iridescent`、`Gift`，`Emotion` 为 `Joy`、`Love`、`Missing`、`Thanks`、`Comfort`、`Hope`。目录编号 01–05 与 `StarCharm.styles` 的顺序一致，改名会让已保存的星星找不到自己的挂件。

## trash

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `PaperBin_Body` | 724×724 | 篓身，同时是纸团飞出的前景层 |
| `PaperBin_Lip` | 724×724 | 篓口 |
| `PaperBall_01`–`10` | 256×256 | 纸团位图，`TrashBinPhysicsSystem.imageNames` 循环取用 |

代码已引用但还不在目录里的：`PaperBin_Lid`（`TrashBinVisual` 与 `TrashBinForegroundLayer` 的篓盖），同样在 `Exports/layout.json` 里。

## paper

| 文件 | 原始画布 | 运行时画布 | 用途 |
| --- | --- | --- | --- |
| `Paper01` | 2500×2870 | 2074×2709 | 打开内容后展开的纸条纸面 |
| `Paper03` | 2651×2866 | 2519×2294 | 同上 |
| `Paper04` | 2500×2665 | 1774×2545 | 同上 |
| `Paper05` | 2500×2500 | 1640×2500 | 同上 |
| `Paper06` | 2500×2500 | 1768×2500 | 同上 |

同步到运行时资产时按 alpha 边界裁掉透明留白，只保留纸面本身：裁完图片即纸面，右上角即纸面右上角。
因此源文件与 `Paper0X.imageset/Paper0X.png` 画布不同，这是唯一一处允许两者不一致的资产。

纸面比例各不相同，卡片宽度取屏宽 80%，高度按纸面自身比例推导（`NotePaper.cardSize`），关闭按钮统一落在纸面右上角。
