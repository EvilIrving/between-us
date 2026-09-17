import SwiftUI

struct ContainerDetailShell<Content: View>: View {
    let kind: ContainerKind
    let title: String
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        kind: ContainerKind,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SceneCloseControl(label: "返回首页") {
                            dismiss()
                        }

                        Spacer()

                        Text(title.localized)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Color.clear
                            .frame(width: 42, height: 42)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    content
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ContainerRitualScene: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: BetweenUsStore

    @State private var showCompose = false
    @State private var isOpening = false
    @State private var openedItem: SecretItem?

    var body: some View {
        ZStack {
            ContainerDetailShell(kind: kind, title: kind.title) {
                VStack(spacing: 14) {
                    containerStage
                        .frame(height: 272)

                    ExchangeBalanceView(
                        kind: kind,
                        credits: credits,
                        waiting: unopenedCount
                    )

                    RitualActionToken(kind: kind, title: kind.homeActionTitle) {
                        showCompose = true
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            }
            .disabled(openedItem != nil)
            .accessibilityHidden(openedItem != nil)

            if let openedItem {
                ContainerRevealOverlay(
                    item: openedItem,
                    onDismiss: { self.openedItem = nil },
                    onRespond: {
                        self.openedItem = nil
                        showCompose = true
                    }
                )
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeSheet(kind: kind)
        }
    }

    private var containerStage: some View {
        VStack(spacing: 8) {
            ContainerVisual(kind: kind, count: sharedCount, style: .detail)
                .padding(.horizontal, kind == .star ? 0 : 36)
                .padding(.vertical, kind == .star ? 0 : 8)

            if kind != .star || !hasOpenableItem {
                Text(stageTitle.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                    .frame(height: 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if kind == .star { openNext() }
        }
        .onLongPressGesture(minimumDuration: AppMotion.holdDuration(for: kind)) {
            if kind != .star { openNext() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("%@，里面积累了 %d 件内容。%@".localized(kind.title, sharedCount, stageTitle.localized))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openNext() }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: kind) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: kind) }
    private var sharedCount: Int { data.count(kind: kind) }
    private var hasOpenableItem: Bool { credits > 0 && unopenedCount > 0 }
    private var stageTitle: String {
        if credits == 0 { return kind.creditRequirementTitle }
        if unopenedCount == 0 { return kind.emptyWaitingTitle }
        return kind.openActionTitle
    }

    private func openNext() {
        guard !isOpening, openedItem == nil else { return }
        guard hasOpenableItem else {
            RitualHaptics.warning()
            return
        }
        isOpening = true
        Task { @MainActor in
            defer { isOpening = false }
            guard let item = await store.openNext(kind: kind) else {
                RitualHaptics.warning()
                return
            }
            openedItem = item
        }
    }
}

struct ExchangeBalanceView: View {
    let kind: ContainerKind
    let credits: Int
    let waiting: Int

    var body: some View {
        HStack(spacing: 0) {
            BalanceValue(value: credits, label: "可打开", tint: kind.tint)
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 34)
            BalanceValue(value: waiting, label: "待打开", tint: kind.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("可打开 %d 次，还有 %d 件内容等你打开".localized(credits, waiting))
    }
}

private struct BalanceValue: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? tint : AppTheme.secondaryText.opacity(0.48))
            Text(label.localized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("%@ %d 件".localized(label.localized, value))
    }
}

struct RitualDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
            Text(text.localized)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.46))
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}
