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

现役只有两张纸，源图就是本目录的两个 JPG（**没有透明留白**，画布即图片本身）：

| 文件 | 尺寸 | 设计稿画布（1200 宽） | 自然高 | 切点 `top` / `center` / `bottom` | 状态 |
| --- | --- | --- | --- | --- | --- |
| `6db56ed7….jpg` 绿框点线纸 | 1024×1536 | 1200×1800 | 483pt | 249 / **144** / 1407 | ⚠️ 中段要改图（内框线是手绘波浪线，平铺会错位） |
| `e5da8f5f….jpg` 蓝色线圈本纸 | 736×1104 | 1200×1800 | 483pt | 351 / **161** / 1288 | ✅ 可直接平铺 |

- 切法与校验见 `PAPER_DESIGN.md` §8 / §9.5；中段的硬约束（边线要直、纸纹不渐变、周期整除砖高）在 §3.3。
- 运行时资产应是三段纵向拼回的一整张（`Paper0X.imageset/Paper0X.png`）；平铺时取 `top .. top+center` 之间的那一块当砖。
- **`BetweenUs/Assets.xcassets` 里的 `Paper01` / `Paper04` / `Paper06` 与 `PaperRegistry` 还是旧纸（旧切线 + `.stretch`），本轮要换成上面两张。** 旧纸源图 `Paper0X.png` 已删（git 有历史），`Paper03` / `Paper05` 更早已删。
- 画布规则（沿用）：等比缩放到设计宽 1200 后再切；x 取完整外接框（保住装饰外伸）；y 裁掉少于画布宽 5% 的飞边。
- 两张纸比例相同（2:3）；纸宽取屏宽 80%（`PaperSheetView.widthRatio`），高度 = `top + max(砖高, 内容高) + bottom`，关闭按钮固定在屏幕右上角。
