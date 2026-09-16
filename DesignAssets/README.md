# 资产源文件

核心物件的源目录。这里的文件名与运行时资产名一一对应，正式运行时资产在 `BetweenUs/Assets.xcassets`；改完源文件要同步过去。

位图负责身份、材质和配准，代码负责物理、开合、揭示与状态。三个物件的画布、瓶口和槽位由代码里的度量常量统一定义，源图按同一套归一化坐标出图：

- 星星瓶：`StarJarMetrics`
- 胶囊瓶：`CapsuleJarMetrics`
- 纸团篓：`TrashBinPhysicsSystem`

## capsule

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `Capsule_Closed` | 512×512 | 封好的胶囊，投入与揭示飞行使用 |
| `Capsule_Top` / `Capsule_Bottom` | 512×512 | 打开后分离的上下两半 |
| `Capsule_Open_00`–`04` | 724×724 | 开瓶过程的连续帧 |

代码已引用但还不在目录里的：`CapsuleJar_Body`、`CapsuleJar_Lid`（`CapsuleJarForeground` 与 `CapsuleJarVisual` 的瓶盖）。两张都在导出清单 `Exports/layout.json` 里。

胶囊三张 token 的正式画布是 192×512，对应 `CapsuleJarMetrics.tokenAspect`；目录里目前是 512×512 正方形，放进窄长方框会留白压缩。

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

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `Note_Paper_01`–`06` | 2500×2500 / 4813×1693 | 打开纸团后展开的纸条卡片纸面 |

这六张是原始出图，尺寸和体积都远超一张卡片所需。
