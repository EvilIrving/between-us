import SwiftUI
import UIKit

/// 打开一条内容后的纸面覆盖层。纸的规格在 `BetweenUs/Paper/`，这里只管容器层：
/// 遮罩、屏幕级的关闭按钮、纸的滚动舞台，以及调用方要挂在屏幕层的控件。
/// 关掉再回首页、关掉留在抽屉，都是同一个覆盖层，纸面本身不因来源不同而变。
struct ContainerRevealOverlay<ScreenLayer: View>: View {
    let item: SecretItem
    let onDismiss: () -> Void
    let onRespond: () -> Void
    /// 屏幕层占的高度：纸的舞台让出这一段，长纸滚动时不会被控件压住。
    let screenLayerHeight: CGFloat    /// 屏幕层控件（纸张规格 §1.4：控件不属于纸，浮在纸之上）。
    let screenLayer: () -> ScreenLayer

    init(
        item: SecretItem,
        onDismiss: @escaping () -> Void,
        onRespond: @escaping () -> Void,
        screenLayerHeight: CGFloat = 0,
        @ViewBuilder screenLayer: @escaping () -> ScreenLayer
    ) {
        self.item = item
        self.onDismiss = onDismiss
        self.onRespond = onRespond
        self.screenLayerHeight = screenLayerHeight
        self.screenLayer = screenLayer
    }

    private var spec: PaperSheetSpec { PaperRegistry.spec(for: item.paperID) }

    var body: some View {
        GeometryReader { canvas in
            let stageHeight = max(0, canvas.size.height - screenLayerHeight)
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                // 纸的舞台在上、屏幕层在下，同一列布局：长纸的滚动视口正好停在控件上沿，
                // 不会滑到控件底下被裁掉一行。屏幕层为空时这一列就是满屏的纸。
                VStack(spacing: 0) {
                    PaperSheetView(item: item, onRespond: onRespond)
                        .frame(width: canvas.size.width, height: stageHeight)

                    screenLayer()
                        .frame(height: screenLayerHeight)
                }
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .transaction { $0.animation = nil }
    }

    /// 关闭按钮不属于纸面规格：固定屏幕右上角，不随纸滚动（§7）。
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spec.prefersDarkCloseIcon
                    ? AppTheme.primaryText.opacity(0.72)
                    : Color.white)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(spec.prefersDarkCloseIcon
                        ? Color.white.opacity(0.55)
                        : Color.black.opacity(0.34))
                }
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .padding(.trailing, 6)
        .padding(.top, 6)
        .accessibilityLabel(T("关闭"))
    }
}

/// 只要纸、不要额外屏幕层控件的调用方（首页房间、三个物件详情页）。
extension ContainerRevealOverlay where ScreenLayer == EmptyView {
    init(item: SecretItem, onDismiss: @escaping () -> Void, onRespond: @escaping () -> Void) {
        self.init(item: item, onDismiss: onDismiss, onRespond: onRespond, screenLayer: { EmptyView() })
    }
}
