# 资产源文件

核心物件的源目录。这里的文件名与运行时资产名一一对应，正式运行时资产在 `BetweenUs/Assets.xcassets`；改完源文件要同步过去。

位图负责身份、材质和配准，代码负责物理、开合、揭示与状态。三个物件的画布、瓶口和槽位都由代码里的度量常量统一定义，源图必须按同一套归一化坐标出图：

- 星星瓶：`StarJarMetrics`
- 胶囊瓶：`CapsuleJarMetrics`
- 纸团篓：`TrashBinPhysicsSystem`

## capsule

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `CapsuleJar_Body` | 1254×1254 | 透明玻璃瓶身，出瓶时作为前景遮挡层 |
| `CapsuleJar_Lid` | 512×512 | 瓶盖，满画布定位，只做开合旋转与抬起 |
| `Capsule_Closed` | 192×512 | 封好的胶囊，投入与揭示飞行使用 |
| `Capsule_Top` / `Capsule_Bottom` | 192×512 | 打开后分离的上下两半 |

胶囊三张是 192×512 的窄长画布，对应 `CapsuleJarMetrics.tokenAspect`。目录里目前是 512×512 正方形，放进方框时会被留白压缩，需要按 192×512 重新导出后替换。

## starjar

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `StarJar_Body` | 724×724 | 星星瓶瓶身，同时是出瓶结局的前景层 |
| `01/`–`05/` `StarCharm_{Style}_{Emotion}` | 256×256 | 五系列 × 六情绪的挂件位图 |

`Style` 为 `Candy`、`Silver`、`Handmade`、`Iridescent`、`Gift`，`Emotion` 为 `Joy`、`Love`、`Missing`、`Thanks`、`Comfort`、`Hope`。目录编号 01–05 与 `StarCharm.styles` 的顺序一致，改名会让已保存的星星找不到自己的挂件。

## trash

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `PaperBin_Body` | 724×724 | 篓身，同时是纸团飞出的前景层 |
| `PaperBin_Lid` | 512×512 | 篓盖，满画布定位，只做开合旋转与位移 |
| `PaperBall_01`–`10` | 256×256 | 纸团位图，`TrashBinPhysicsSystem.imageNames` 循环取用 |

## paper

| 文件 | 画布 | 用途 |
| --- | --- | --- |
| `Note_Paper_01`–`06` | 2500×2500 / 4813×1693 | 打开纸团后展开的纸条卡片纸面 |

这六张还是原始出图，尺寸与体积都远超一张卡片所需，需要一轮正式导出。
