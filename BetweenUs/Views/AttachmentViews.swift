import AVFoundation
import AVKit
import ImageIO
import SwiftUI
import UIKit

/// 附件图片的解码入口。
/// 手机拍的照片常见 4000×3000，原图直接解成位图是几十 MB：卡在视图求值里会拖掉整屏帧，
/// 连着解几张就能把内存顶到警告线。这里统一按显示尺寸下采样，结果进内存缓存，同一张图并发只解一次。
@MainActor
final class AttachmentImageStore {
    static let shared = AttachmentImageStore()

    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    private var pixelSizes: [String: CGSize] = [:]

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
    }

    /// 已经下采样好的图；命中时视图直接显示，不必再等一次加载。
    func cached(for url: URL, maxPixel: CGFloat) -> UIImage? {
        images.object(forKey: key(url, maxPixel) as NSString)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = key(url, maxPixel)
        if let image = images.object(forKey: key as NSString) { return image }
        if let pending = loading[key] { return await pending.value }
        let task = Task.detached(priority: .userInitiated) {
            AttachmentImageStore.downsampled(url: url, maxPixel: maxPixel)
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            images.setObject(image, forKey: key as NSString, cost: image.bitmapCost)
        }
        return image
    }

    /// 只读文件头拿像素尺寸，不解码像素：用来在图片到达之前先把版位占住。
    func pixelSize(for url: URL) -> CGSize? {
        if let size = pixelSizes[url.path] { return size }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return nil }
        let size = CGSize(width: width, height: height)
        pixelSizes[url.path] = size
        return size
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> String {
        "\(url.path)|\(Int(maxPixel))"
    }

    private nonisolated static func downsampled(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension UIImage {
    /// 下采样之后的位图占用，用来给缓存记成本。
    var bitmapCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

/// 附件里的图片：缓存命中立即出图，未命中在后台按显示尺寸解码。
/// 视图求值里不再出现同步解原图的路径。
struct AttachmentImage<Placeholder: View>: View {
    let url: URL
    let maxPixel: CGFloat
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL,
        maxPixel: CGFloat,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixel = maxPixel
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image ?? AttachmentImageStore.shared.cached(for: url, maxPixel: maxPixel) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            image = await AttachmentImageStore.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}

struct AttachmentDraftPreview: View {
    let draft: AttachmentDraft
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 14) {
                preview
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                        .lineLimit(2)
                }

                Spacer(minLength: 42)
            }
            .padding(13)
            .background(Color.white.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            }

            Button {
                RitualHaptics.selection()
                remove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.56))
                    .clipShape(Circle())
            }
            .buttonStyle(SoftScaleButtonStyle())
            .padding(10)
            .accessibilityLabel(T("移除附件"))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if draft.kind == .image {
            AttachmentImage(url: draft.url, maxPixel: 720) { kindIconPlaceholder }
        } else {
            kindIconPlaceholder
        }
    }

    private var kindIconPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.44)
            Image(systemName: draft.kind.systemImage)
                .font(.title2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var metadataText: String {
        if let duration = draft.duration {
            return T("录音时长 %@", duration.formattedDuration)
        }
        return draft.originalFilename ?? T("已准备")
    }
}

struct AttachmentContentView: View {
    let attachment: AttachmentMetadata
    var tint: Color = ContainerKind.capsule.tint
    var openMedia: (() -> Void)?

    private let mediaStore = MediaFileStore()

    var body: some View {
        let url = mediaStore.url(for: attachment)
        Group {
            if !mediaStore.fileExists(for: attachment) {
                unavailable
            } else {
                switch attachment.kind {
                case .image:
                    ImageAttachmentView(url: url, openImage: openMedia)
                case .video:
                    VideoAttachmentView(url: url, openVideo: openMedia)
                case .audio:
                    AudioAttachmentView(url: url, expectedDuration: attachment.duration, tint: tint)
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 11) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 28, weight: .light))
            Text("正在从 iCloud 下载附件")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 148)
        .background(Color.white.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        }
    }
}

struct AttachmentCollectionView: View {
    let attachments: [AttachmentMetadata]
    var tint: Color = ContainerKind.capsule.tint
    /// 纸面用（§5）：显式几何。传入后录音行与单张图的高度由度量给出，
    /// 保证「排版算出的纸高」与「实际渲染」用同一组数字。
    var paperMetrics: PaperMediaMetrics? = nil

    private let mediaStore = MediaFileStore()
    @State private var mediaViewerRequest: MediaViewerRequest?

    var body: some View {
        let visualMedia = attachments.filter { $0.kind == .image || $0.kind == .video }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        VStack(spacing: 10) {
            // 录音排在最上面：它是这条内容的主表达，照片和视频跟在它后面。
            ForEach(Array(audioAttachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentContentView(attachment: attachment, tint: tint, openMedia: nil)
                    .frame(height: paperMetrics?.audioRowHeight)
            }

            if visualMedia.count > 1 {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: 7),
                    count: visualMedia.count == 2 ? 2 : 3
                )
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(Array(visualMedia.enumerated()), id: \.offset) { index, attachment in
                        SavedMediaTile(
                            attachment: attachment,
                            url: mediaStore.url(for: attachment),
                            isAvailable: mediaStore.fileExists(for: attachment),
                            index: index,
                            open: { openMedia(at: index) }
                        )
                    }
                }
            } else if let attachment = visualMedia.first {
                AttachmentContentView(
                    attachment: attachment,
                    tint: tint,
                    openMedia: { openMedia(at: 0) }
                )
                .frame(height: paperMetrics?.singleVisualHeight(for: attachment))
            }
        }
        .fullScreenCover(item: $mediaViewerRequest) { request in
            FullScreenMediaViewer(
                items: visualMedia.enumerated().map { index, attachment in
                    MediaViewerItem(
                        id: index,
                        kind: attachment.kind,
                        url: mediaStore.url(for: attachment)
                    )
                },
                initialIndex: request.initialIndex
            )
        }
    }

    private func openMedia(at index: Int) {
        RitualHaptics.selection()
        mediaViewerRequest = MediaViewerRequest(initialIndex: index)
    }
}

private struct SavedMediaTile: View {
    let attachment: AttachmentMetadata
    let url: URL
    let isAvailable: Bool
    let index: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if !isAvailable {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.title2)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.42))
                    } else if attachment.kind == .video {
                        VideoPosterView(url: url)
                    } else {
                        AttachmentImage(url: url, maxPixel: 640) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.42))
                        }
                    }
                }
                .overlay {
                    if attachment.kind == .video, isAvailable {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.38))
                            .clipShape(Circle())
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if attachment.kind == .image, isAvailable {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.32))
                            .clipShape(Circle())
                            .padding(7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(
            attachment.kind == .video
                ? T("播放视频")
                : T("查看第 %d 张照片", index + 1)
        )
    }
}

private struct ImageAttachmentView: View {
    let url: URL
    let openImage: (() -> Void)?

    private static let maxPixel: CGFloat = 1_500
    private static let maximumHeight: CGFloat = 430

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? AttachmentImageStore.shared.cached(for: url, maxPixel: Self.maxPixel) {
                if let openImage {
                    Button(action: openImage) {
                        displayedImage(image)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.34))
                                    .clipShape(Circle())
                                    .padding(10)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("放大查看照片"))
                } else {
                    displayedImage(image)
                }
            } else if failed {
                unavailable
            } else {
                // 尺寸先由文件头定下来，图到达时版面不会跳。
                Color.clear
                    .aspectRatio(reservedAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maximumHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            image = await AttachmentImageStore.shared.image(for: url, maxPixel: Self.maxPixel)
            failed = image == nil
        }
    }

    private var reservedAspect: CGFloat {
        guard let size = AttachmentImageStore.shared.pixelSize(for: url), size.height > 0 else {
            return 3.0 / 4.0
        }
        return size.width / size.height
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.title2)
            Text("照片暂时无法显示")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private func displayedImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: Self.maximumHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MediaViewerRequest: Identifiable {
    let id = UUID()
    let initialIndex: Int
}

private struct MediaViewerItem: Identifiable {
    let id: Int
    let kind: AttachmentKind
    let url: URL
}

private struct ViewerImagePage: View {
    let url: URL
    let onSingleTap: () -> Void
    let onZoomChanged: (Bool) -> Void

    // 全屏可以放大到五倍，留够裁切余量；仍然按显示尺寸解码，不把原图整张读进来。
    private static let maxPixel: CGFloat = 2_560

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? AttachmentImageStore.shared.cached(for: url, maxPixel: Self.maxPixel) {
                ZoomableImageView(
                    image: image,
                    onSingleTap: onSingleTap,
                    onZoomChanged: onZoomChanged
                )
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                    Text(T("照片暂时无法显示"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.72))
            } else {
                ProgressView()
                    .tint(.white.opacity(0.72))
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            image = await AttachmentImageStore.shared.image(for: url, maxPixel: Self.maxPixel)
            failed = image == nil
        }
    }
}

private struct FullScreenMediaViewer: View {
    let items: [MediaViewerItem]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex: Int
    @State private var controlsVisible = true
    @State private var isCurrentImageZoomed = false
    @State private var dismissOffset: CGFloat = 0

    init(items: [MediaViewerItem], initialIndex: Int) {
        self.items = items
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(Double(max(CGFloat(0.32), 1 - abs(dismissOffset) / 560)))
                .ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(items.indices, id: \.self) { index in
                    mediaPage(item: items[index], isActive: selectedIndex == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dismissOffset)
            .scaleEffect(1 - min(abs(dismissOffset) / 2400, 0.08))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(SoftScaleButtonStyle())
                    .accessibilityLabel(T("关闭"))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                if items.count > 1, !currentItemIsVideo {
                    Text("\(selectedIndex + 1) / \(items.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.34))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
            .opacity((controlsVisible || currentItemIsVideo) ? 1 : 0)
            .allowsHitTesting(controlsVisible || currentItemIsVideo)
        }
        .statusBarHidden(true)
        .presentationBackground(.clear)
        .simultaneousGesture(dismissGesture)
        .onDisappear { Task { await PlaybackAudioSession.shared.deactivate() } }
        .onChange(of: selectedIndex) { _, _ in
            isCurrentImageZoomed = false
            withAnimation(.easeOut(duration: 0.16)) {
                controlsVisible = true
            }
        }
    }

    @ViewBuilder
    private func mediaPage(item: MediaViewerItem, isActive: Bool) -> some View {
        switch item.kind {
        case .image:
            ViewerImagePage(
                url: item.url,
                onSingleTap: toggleControls,
                onZoomChanged: { isCurrentImageZoomed = $0 }
            )
            .ignoresSafeArea()
        case .video:
            FullScreenVideoPage(url: item.url, isActive: isActive)
                .ignoresSafeArea()
        case .audio:
            EmptyView()
        }
    }

    /// 系统播放器自带底部控制条，视频页不再叠加页码。
    private var currentItemIsVideo: Bool {
        items.indices.contains(selectedIndex) && items[selectedIndex].kind == .video
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isCurrentImageZoomed,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                guard !isCurrentImageZoomed,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                let projected = value.predictedEndTranslation.height
                if abs(value.translation.height) > 120 || abs(projected) > 260 {
                    RitualHaptics.soft()
                    if reduceMotion {
                        dismiss()
                    } else {
                        let target = value.translation.height < 0 ? -760.0 : 760.0
                        withAnimation(.easeOut(duration: 0.18)) {
                            dismissOffset = target
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            dismiss()
                        }
                    }
                } else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.34, dampingFraction: 0.84)) {
                        dismissOffset = 0
                    }
                }
            }
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void
    let onZoomChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap, onZoomChanged: onZoomChanged)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.isEnabled = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.imageView?.image = image
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            context.coordinator.imageView?.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
        context.coordinator.centerImage()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void
        var onZoomChanged: (Bool) -> Void

        init(onSingleTap: @escaping () -> Void, onZoomChanged: @escaping (Bool) -> Void) {
            self.onSingleTap = onSingleTap
            self.onZoomChanged = onZoomChanged
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            scrollView.panGestureRecognizer.isEnabled = isZoomed
            onZoomChanged(isZoomed)
            centerImage()
        }

        func centerImage() {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            var center = CGPoint(
                x: scrollView.contentSize.width / 2,
                y: scrollView.contentSize.height / 2
            )
            if scrollView.contentSize.width < boundsSize.width {
                center.x = boundsSize.width / 2
            }
            if scrollView.contentSize.height < boundsSize.height {
                center.y = boundsSize.height / 2
            }
            imageView.center = center
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(2.5, scrollView.maximumZoomScale)
            let location = gesture.location(in: imageView)
            let zoomSize = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let zoomRect = CGRect(
                x: location.x - zoomSize.width / 2,
                y: location.y - zoomSize.height / 2,
                width: zoomSize.width,
                height: zoomSize.height
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }
    }
}

private struct VideoAttachmentView: View {
    let url: URL
    let openVideo: (() -> Void)?

    var body: some View {
        Button {
            openVideo?()
        } label: {
            VideoPosterView(url: url)
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.42))
                        .clipShape(Circle())
                        .overlay { Circle().stroke(.white.opacity(0.24), lineWidth: 1) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(openVideo == nil)
        .accessibilityLabel(T("播放视频"))
    }
}

private struct VideoPosterView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white.opacity(0.72))
            }
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_200, height: 1_200)
            let requestedTime = CMTime(seconds: 0.08, preferredTimescale: 600)
            if let result = try? await generator.image(at: requestedTime), !Task.isCancelled {
                image = UIImage(cgImage: result.image)
            }
        }
    }
}

@MainActor
private final class VideoPlaybackSession: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
    }

    func play() {
        let position = player.currentTime().seconds
        if let duration = player.currentItem?.duration.seconds,
           duration.isFinite,
           duration > 0,
           position.isFinite,
           position >= duration - 0.05 {
            player.seek(to: .zero)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }
}

/// 最大化播放交给系统播放器，控制条、画中画、AirPlay、锁屏控制和字幕都由 AVKit 提供。
private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

/// 播放期间使用 playback 会话，退到后台或锁屏后声音继续。
/// 会话配置与激活要等到系统完成路由协商才返回，放在主线程上会顶住全屏视频的出现动画，
/// 所以播放会话的操作统一走这个串行 actor：不占主线程，停用与下次激活也按发生顺序执行。
private actor PlaybackAudioSession {
    static let shared = PlaybackAudioSession()

    private let session = AVAudioSession.sharedInstance()

    func activate() {
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct FullScreenVideoPage: View {
    @StateObject private var session: VideoPlaybackSession
    @State private var activation: Task<Void, Never>?
    let isActive: Bool

    init(url: URL, isActive: Bool) {
        _session = StateObject(wrappedValue: VideoPlaybackSession(url: url))
        self.isActive = isActive
    }

    var body: some View {
        SystemVideoPlayer(player: session.player)
            .onAppear {
                guard isActive else { return }
                startPlayback()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    startPlayback()
                } else {
                    cancelPendingPlayback()
                    session.pause()
                }
            }
            .onDisappear {
                cancelPendingPlayback()
                session.pause()
            }
    }

    // 会话先就位再起播，避免用上一次的会话类别出声；激活期间用户划走或切页时不再起播。
    private func startPlayback() {
        cancelPendingPlayback()
        activation = Task { @MainActor in
            await PlaybackAudioSession.shared.activate()
            guard !Task.isCancelled else { return }
            session.play()
        }
    }

    private func cancelPendingPlayback() {
        activation?.cancel()
        activation = nil
    }
}

@MainActor
private final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var resumeAfterSeeking = false

    init(url: URL) {
        super.init()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            self.player = nil
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func toggle() {
        guard let player else { return }
        RitualHaptics.selection()
        if player.isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            if player.currentTime >= player.duration { player.currentTime = 0 }
            player.play()
            isPlaying = true
            startTimer()
        }
        currentTime = player.currentTime
    }

    func beginSeeking() {
        guard let player else { return }
        resumeAfterSeeking = player.isPlaying
        player.pause()
        stopTimer()
        isPlaying = false
    }

    func previewSeek(progress: Double) {
        guard let player else { return }
        let clamped = min(max(progress, 0), 1)
        currentTime = clamped * player.duration
    }

    func endSeeking(progress: Double) {
        guard let player else { return }
        let clamped = min(max(progress, 0), 1)
        player.currentTime = clamped * player.duration
        currentTime = player.currentTime
        if resumeAfterSeeking {
            player.play()
            isPlaying = true
            startTimer()
        }
        resumeAfterSeeking = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        player.currentTime = 0
        stopTimer()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct AudioAttachmentView: View {
    @StateObject private var controller: AudioPlaybackController
    private let url: URL
    let expectedDuration: TimeInterval?
    let tint: Color

    init(url: URL, expectedDuration: TimeInterval?, tint: Color) {
        _controller = StateObject(wrappedValue: AudioPlaybackController(url: url))
        self.url = url
        self.expectedDuration = expectedDuration
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: controller.toggle) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(controller.isPlaying ? 0.88 : 0.72))
                        .frame(width: 52, height: 52)
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: controller.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel(controller.isPlaying ? T("暂停语音") : T("播放语音"))

            VStack(spacing: 5) {
                AudioWaveformScrubber(
                    url: url,
                    progress: controller.progress,
                    isPlaying: controller.isPlaying,
                    tint: tint,
                    beginSeeking: controller.beginSeeking,
                    previewSeek: controller.previewSeek,
                    endSeeking: controller.endSeeking
                )
                .frame(height: 36)

                HStack {
                    Text(controller.currentTime.formattedDuration)
                    Spacer()
                    Text(totalDuration.formattedDuration)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(tint.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
        .onDisappear { controller.stop() }
    }

    private var totalDuration: TimeInterval {
        controller.duration > 0 ? controller.duration : expectedDuration ?? 0
    }
}

struct VoiceDraftPreviewPlayer: View {
    @StateObject private var controller: AudioPlaybackController
    private let url: URL
    let expectedDuration: TimeInterval?
    let tint: Color
    let discard: () -> Void
    let commit: () -> Void

    init(
        url: URL,
        expectedDuration: TimeInterval?,
        tint: Color,
        discard: @escaping () -> Void,
        commit: @escaping () -> Void
    ) {
        _controller = StateObject(wrappedValue: AudioPlaybackController(url: url))
        self.url = url
        self.expectedDuration = expectedDuration
        self.tint = tint
        self.discard = discard
        self.commit = commit
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                controller.stop()
                RitualHaptics.selection()
                discard()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.42))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.68), lineWidth: 1)
                    }
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel(T("删除录音并重录"))

            HStack(spacing: 8) {
                Button(action: controller.toggle) {
                    HStack(spacing: 3) {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .offset(x: controller.isPlaying ? 0 : 1)

                        Text(displayedDuration.formattedDuration)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 22)
                    .background(Color.white.opacity(0.52))
                    .clipShape(Capsule())
                }
                .buttonStyle(SoftScaleButtonStyle())
                .accessibilityLabel(controller.isPlaying ? T("暂停语音") : T("播放语音"))

                AudioWaveformScrubber(
                    url: url,
                    progress: controller.progress,
                    isPlaying: controller.isPlaying,
                    tint: tint,
                    beginSeeking: controller.beginSeeking,
                    previewSeek: controller.previewSeek,
                    endSeeking: controller.endSeeking
                )
                .frame(height: 13)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.38))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.66), lineWidth: 1)
            }

            Button(action: commit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint)
                    .clipShape(Circle())
            }
            .buttonStyle(SoftScaleButtonStyle())
            .accessibilityLabel(T("保存并放进去"))
        }
        .frame(maxWidth: 360)
        .onDisappear { controller.stop() }
    }

    private var displayedDuration: TimeInterval {
        if controller.isPlaying || controller.currentTime > 0 {
            return controller.currentTime
        }
        return controller.duration > 0 ? controller.duration : expectedDuration ?? 0
    }
}

private struct AudioWaveformScrubber: View {
    let url: URL
    let progress: Double
    let isPlaying: Bool
    let tint: Color
    let beginSeeking: () -> Void
    let previewSeek: (Double) -> Void
    let endSeeking: (Double) -> Void

    @State private var scrubbingProgress: Double?
    @State private var loudness: [Float]?

    var body: some View {
        GeometryReader { proxy in
            // 条形数量按可用宽度推导；宽度变化只重采样，不重新解码音频。
            let spacing: CGFloat = 3
            let barWidth: CGFloat = 3
            let availableWidth = max(proxy.size.width, 1)
            let barCount = max(6, Int((availableWidth + spacing) / (barWidth + spacing)))
            let bars = AudioWaveformStore.resample(loudness, to: barCount)
            let displayedProgress = scrubbingProgress ?? progress
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let normalizedIndex = barCount > 1 ? Double(index) / Double(barCount - 1) : 0
                    let minimumBarHeight = max(3, proxy.size.height * 0.24)
                    let amplitude = CGFloat(bars?[index] ?? 0)
                    let barHeight = minimumBarHeight + max(0, proxy.size.height - minimumBarHeight) * amplitude
                    Capsule()
                        .fill(normalizedIndex <= displayedProgress ? tint.opacity(0.84) : AppTheme.secondaryText.opacity(0.16))
                        .frame(width: barWidth, height: barHeight)
                        .scaleEffect(y: isPlaying && abs(normalizedIndex - progress) < 0.08 ? 1.12 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        let progress = min(max(Double(value.location.x / proxy.size.width), 0), 1)
                        if scrubbingProgress == nil {
                            RitualHaptics.selection()
                            beginSeeking()
                        }
                        scrubbingProgress = progress
                        previewSeek(progress)
                    }
                    .onEnded { value in
                        guard proxy.size.width > 0 else { return }
                        let progress = min(max(Double(value.location.x / proxy.size.width), 0), 1)
                        endSeeking(progress)
                        scrubbingProgress = nil
                    }
            )
        }
        .animation(.easeOut(duration: 0.14), value: progress)
        .task(id: url) {
            loudness = await AudioWaveformStore.shared.loudness(for: url)
        }
        .accessibilityElement()
        .accessibilityLabel(T("语音播放进度"))
        .accessibilityValue(T("百分之 %d", Int(progress * 100)))
    }
}

extension TimeInterval {
    var formattedDuration: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
