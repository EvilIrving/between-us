# 压缩口径

一条内容的体积上限 100 MB。以下参数两端共用，写在同一个 JSON 里，iOS 与 Android 读同一份。

## 目标参数

- 图片：JPEG、长边 2560、质量 0.85、sRGB 8-bit、方向烧进像素、剥掉 EXIF 里的定位与设备信息。动图不支持，取第一帧。单张 0.6 到 1.2 MB。
- 视频：MP4 容器、H.264 High@4.2、长边 1920、帧率跟随源且不超过 60、平均码率 4 Mbps、峰值 8 Mbps、关键帧间隔 2 秒、音频 AAC-LC 64 kbps 单声道、最长 60 秒，压完约 30 MB。
- 音频：M4A 容器、AAC-LC 单声道 64 kbps、44.1 kHz、最长 30 分钟，压完约 14.4 MB。

## 几个参数是这样定下来的

视频不用 HEVC。同样体积下 HEVC 的画质好三到四成，但 Android 的 CDD 只强制要求所有设备能解 H.264，HEVC 的硬解在低端机上不保证，而一条已经发出去的内容不能在对方手机上黑屏。上限提到 100 MB 之后体积不再是约束，兼容性就变成唯一的判断依据。

1080p 给 4 Mbps。1080p30 在 4 Mbps 下画面站得住，手机拍的正常题材够用；快递动的画面会更吃力，所以峰值放到 8 Mbps 留给它。60 秒约 30 MB，离 100 MB 上限还有很大余量。

音频从 32 kbps 提到 64 kbps，因为上限放开之后没有必要再压。64 kbps 单声道在 44.1 kHz 下人声接近无损，三十分钟 14.4 MB。

图片长边给到 2560 而不是 2048，同样是因为上限已经不是问题。2560 长边在手机屏幕上放大看细节还留得住，单张 0.6 到 1.2 MB，九张一条也就 9 MB。

图片出 JPEG 不出 HEIC。iPhone 的 HEIC 体积小一半，但安卓侧的 HEIF 解码依赖设备实现，风险落在对方打不开上；一两百 KB 的差价不值得。

## iOS

图片走 ImageIO。`CGImageSourceCreateThumbnailAtIndex` 带 `kCGImageSourceThumbnailMaxPixelSize: 2560` 与 `kCGImageSourceCreateThumbnailWithTransform: true`，一次拿到已转正、已缩放的结果；iPhone 拍的广色域或 HDR 静图必须用 sRGB 色彩空间重绘一遍，否则安卓上发灰。然后用 `CGImageDestination` 写 JPEG，只设 `kCGImageDestinationLossyCompressionQuality: 0.85`，不写任何元数据。

视频走 `AVAssetReader` 加 `AVAssetWriter`，不用 `AVAssetExportSession`：预设不允许指定码率。`AVAssetReaderVideoCompositionOutput` 配一个 renderSize 1920×1080 的 `AVMutableVideoComposition`，输出像素格式设 8-bit 的 420v，系统在这一步把 iPhone 的 HLG、Dolby Vision 做色调映射；`AVVideoColorPropertiesKey` 里声明 BT.709，`AVVideoCompressionPropertiesKey` 里给 `AVVideoAverageBitRateKey: 4_000_000`、`AVVideoProfileLevelH264HighAutoLevel`、`AVVideoMaxKeyFrameIntervalDurationKey: 2`。旋转通过 `AVAssetWriterInput.transform` 写进文件。

音频走 `AVAudioRecorder` 直接录成 AAC-LC 64 kbps 单声道，录完只做时长裁剪，不再转码。

## Android

图片走 `ImageDecoder`（API 28 起）。`setTargetSize` 让它在解码时就采样，不会把整张图读进内存；方向由 `ImageDecoder` 自动应用，不需要 ExifInterface 手动旋转；`decodeBitmap` 对动图只取第一帧。拿到 Bitmap 后用 `Bitmap.compress(JPEG, 85, ...)` 写出，色彩空间默认 sRGB。

视频走 Media3 Transformer，这是唯一能把 HDR 转 SDR 做对又不用自己写 OpenGL 管线的路径。`Transformer.Builder` 设 `setVideoMimeType(MimeTypes.VIDEO_H264)` 与 `setAudioMimeType(MimeTypes.AUDIO_AAC)`；码率通过 `DefaultEncoderFactory.Builder(context).setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(4_000_000).build())`；分辨率用 `Presentation.createForHeight(1080)`；HDR 用 `Composition.Builder().setHdrMode(HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)`，它从 API 29 起可用、跨机型结果一致，API 31+ 且在 HDR 拍摄白名单上的设备可以换成 `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC`，画质更好但设备不支持时会抛 `ExportException`，所以要有回落；裁剪用 `MediaItem.ClippingConfiguration` 截到 60 秒。

音频同样走 Media3 Transformer，只给音频轨，输出 m4a，参数同上。

## 两端必须一致的三件事

变帧率不处理。目标码率固定时文件体积等于码率乘时长，跟帧数无关，强行转成恒定帧率只会增加工程量。源是 60 fps 就在同样码率下每帧质量低一点。

旋转两端都烧进像素，不靠元数据。

色彩统一到 sRGB、BT.709、8-bit。iPhone 默认拍 HDR 与广色域，这一步漏掉就是对方看到一片发灰发白的画面，这是两端画质差异最大的来源，比码率重要得多。

## 失败与兜底

压完仍超 100 MB：视频降到 2.5 Mbps 重编一次，仍超就截到 30 秒；图片降到质量 0.8；音频截到 30 分钟。

编码器不可用或抛异常：视频退回 1280 长边、2.5 Mbps 再试一次，仍失败就只发文字，那条内容照常存在。

上传按 5 MB 分片，断点续传。压缩在后台做，界面不显示进度；附件在压缩与上传完成后自己出现，失败就重试，重试还没成那一条就只是文字。

## 验收

两端各取同一段 iPhone 拍的 4K HDR 60 fps 视频、一张 HEIC 广色域照片、一段 30 分钟录音，走一遍压缩，看四个数：视频 60 秒不超过 60 MB 且人脸肤色不发灰；图片长边 2560、方向正确；音频 30 分钟不超过 15 MB 且人声清楚；三者在两端解出来一致。
