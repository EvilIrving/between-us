import SwiftUI

enum LifetimeUnlockContext: Equatable {
    case settings
    case quotaReached
    case preview
}

struct LifetimeUnlockView: View {
    let context: LifetimeUnlockContext

    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    objectsShelf
                        .padding(.top, 22)

                    Text(title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 19)

                    if !isUnlocked {
                        usagePill
                            .padding(.top, 17)
                    }

                    benefits
                        .padding(.top, 24)

                    actions
                        .padding(.top, 25)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .task {
            guard !isUnlocked else { return }
            await store.loadLifetimeProduct()
        }
    }

    private var header: some View {
        HStack {
            SceneCloseControl { dismiss() }
            Spacer()

            Text("永久版".localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.40))
                .clipShape(Capsule())
        }
        .padding(.top, 9)
    }

    private var objectsShelf: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.roomTable.opacity(0.20))
                .frame(width: 256, height: 5)
                .shadow(color: Color.black.opacity(0.07), radius: 7, y: 4)

            HStack(alignment: .bottom, spacing: 22) {
                RitualObjectGlyph(kind: .star, size: 78, filled: true)
                RitualObjectGlyph(kind: .capsule, size: 78, filled: true)
                RitualObjectGlyph(kind: .paper, size: 78, filled: true)
            }
            .padding(.bottom, 4)
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }

    private var usagePill: some View {
        Text("已经留下 %d / %d".localized(
            store.viewModel.data.items.count,
            CommerceConfiguration.freeItemLimit
        ))
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(ContainerKind.star.tint.opacity(0.88))
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(ContainerKind.star.tint.opacity(0.10))
        .clipShape(Capsule())
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit(
                systemName: "person.2.fill",
                title: "一起解锁",
                detail: "一人买断，两个人都能用。被邀请的一方不用再买。"
            )
            divider
            benefit(
                systemName: "infinity",
                title: "不再限量",
                detail: "星星、胶囊和纸团，想留多少都可以。"
            )
            divider
            benefit(
                systemName: "checkmark.seal.fill",
                title: "只买一次",
                detail: "没有月付，也没有年付。"
            )
        }
        .padding(.horizontal, 15)
        .background(Color.white.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.66), lineWidth: 1)
        }
    }

    private func benefit(systemName: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ContainerKind.star.tint.opacity(0.86))
                .frame(width: 38, height: 38)
                .background(ContainerKind.star.tint.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(detail.localized)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.secondaryText.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 51)
    }

    @ViewBuilder
    private var actions: some View {
        if isUnlocked {
            Button {
                RitualHaptics.success()
                dismiss()
            } label: {
                Text("继续使用".localized)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(ContainerKind.star.tint.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(SoftScaleButtonStyle())
        } else {
            VStack(spacing: 12) {
                Button {
                    RitualHaptics.selection()
                    Task {
                        if store.viewModel.purchase.productLoadFailed {
                            await store.loadLifetimeProduct()
                        } else {
                            await store.purchaseLifetime()
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        if isPrimaryActionWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(primaryActionTitle)
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(ContainerKind.star.tint.opacity(primaryActionEnabled ? 0.92 : 0.50))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: ContainerKind.star.tint.opacity(0.14), radius: 14, y: 7)
                }
                .buttonStyle(SoftScaleButtonStyle())
                .disabled(!primaryActionEnabled)

                Button {
                    RitualHaptics.selection()
                    Task { await store.restoreLifetimePurchase() }
                } label: {
                    Text("恢复购买".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                        .frame(height: 38)
                }
                .buttonStyle(SoftScaleButtonStyle())
                .disabled(isAnyActionWorking)

                purchasePolicyLinks
            }
        }
    }

    private var purchasePolicyLinks: some View {
        HStack(spacing: 8) {
            Link("购买说明".localized, destination: Self.purchasesURL)
            Text("·")
            Link("使用条款".localized, destination: Self.termsURL)
            Text("·")
            Link("隐私政策".localized, destination: Self.privacyURL)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
        .tint(AppTheme.secondaryText.opacity(0.68))
        .multilineTextAlignment(.center)
    }

    private var isUnlocked: Bool {
        if context == .preview {
            return store.viewModel.purchase.ownsLifetimePurchase
        }
        return store.viewModel.hasUnlimitedContent
    }

    private var title: String {
        if isUnlocked {
            if store.viewModel.purchase.ownsLifetimePurchase,
               store.viewModel.data.sharedSpaceEntitlement == nil {
                return "这台设备已解锁".localized
            }
            return "已经解锁".localized
        }
        if context == .quotaReached { return "已经放满".localized }
        return "一直留着".localized
    }

    private var primaryActionTitle: String {
        switch store.viewModel.purchase.activity {
        case .loadingProduct:
            return "正在连接 App Store".localized
        case .purchasing:
            return "正在等待 App Store".localized
        case .restoring:
            return "正在恢复".localized
        case .pending:
            return "等待购买确认".localized
        case .idle:
            if store.viewModel.purchase.productLoadFailed {
                return "重新连接 App Store".localized
            }
            if let price = store.viewModel.purchase.displayPrice {
                return "%@ 永久解锁".localized(price)
            }
            return "永久解锁".localized
        }
    }

    private var isPrimaryActionWorking: Bool {
        switch store.viewModel.purchase.activity {
        case .loadingProduct, .purchasing, .restoring: return true
        case .idle, .pending: return false
        }
    }

    private var isAnyActionWorking: Bool {
        store.viewModel.purchase.activity != .idle
    }

    private var primaryActionEnabled: Bool {
        switch store.viewModel.purchase.activity {
        case .idle: return true
        case .loadingProduct, .purchasing, .restoring, .pending: return false
        }
    }

    private static let purchasesURL = URL(string: "https://betweenus.onecat.dev/purchases/")!
    private static let termsURL = URL(string: "https://betweenus.onecat.dev/terms/")!
    private static let privacyURL = URL(string: "https://betweenus.onecat.dev/privacy/")!
}
