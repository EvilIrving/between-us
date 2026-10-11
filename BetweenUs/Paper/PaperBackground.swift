import SwiftUI
import UIKit

/// 纸面：上段 + 中段（那块砖按原尺寸反复铺满）+ 下段（§3.1）。
///
/// 三段都来自同一张 1200×1800 的整图，按设计稿像素切出来各自摆放：
/// 上、下段各画一次，中段铺 `bands` 块砖。**中段绝不做任何缩放**——砖是 1:1 摆上去的，
/// 所以纸纹尺度恒定、接缝只在砖的边界上（切点已按 §3.3 三条判据挑过）。
struct PaperBackground: View {
    let spec: PaperSheetSpec
    let paperWidth: CGFloat
    /// 中段铺几块砖（≥ 1），来自 `spec.bandCount(forContent:)`。
    let bands: Int

    private var scale: CGFloat { paperWidth / spec.pixelSize.width }

    var paperHeight: CGFloat {
        (spec.top + CGFloat(max(1, bands)) * spec.center + spec.bottom) * scale
    }

    var body: some View {
        VStack(spacing: 0) {
            band(y: 0, height: spec.top)
            ForEach(0..<max(1, bands), id: \.self) { _ in
                band(y: spec.top, height: spec.center)
            }
            band(y: spec.top + spec.center, height: spec.bottom)
        }
        .frame(width: paperWidth, height: paperHeight, alignment: .top)
        .clipped()
    }

    private func band(y: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: PaperImageSlicer.band(spec: spec, y: y, height: height))
            .interpolation(.high)
            .frame(width: paperWidth, height: height * scale)
    }
}

/// 纸的缩略图：就是这张纸本身按比例缩小（不另做图），用在中段一块砖的自然高度上。
struct PaperThumbnail: View {
    let spec: PaperSheetSpec
    var width: CGFloat = 22

    var body: some View {
        PaperBackground(spec: spec, paperWidth: width, bands: 1)
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 0.5)
            }
    }
}

/// 从整图里按设计稿像素切出一段。裁切只做 CGImage 视图，不复制像素；缩放任交给视图。
enum PaperImageSlicer {
    private static let cache = NSCache<NSString, UIImage>()

    static func band(spec: PaperSheetSpec, y: CGFloat, height: CGFloat) -> UIImage {
        let key = "\(spec.assetName)#\(Int(y))+\(Int(height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = UIImage(named: spec.assetName) else { return UIImage() }
        let width = spec.pixelSize.width
        guard height > 0,
              let cgImage = source.cgImage?.cropping(
                to: CGRect(x: 0, y: y, width: width, height: height)
              )
        else { return source }
        let band = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        cache.setObject(band, forKey: key)
        return band
    }
}
