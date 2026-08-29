import SwiftUI

struct ContainerDetailShell<Content: View>: View {
    let kind: ContainerKind
    let title: String
    let subtitle: String
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        kind: ContainerKind,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SceneCloseControl(label: "回到共同房间") {
                            dismiss()
                        }

                        Spacer()

                        Text(title)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Color.clear
                            .frame(width: 42, height: 42)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 30)
                        .padding(.top, 7)
                        .padding(.bottom, 3)

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

/// Shared state and interaction shell for all three containers.
struct ContainerRitualScene: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        ContainerDetailShell(
            kind: kind,
            title: kind.title,
            subtitle: sceneSubtitle
        ) {
            VStack(spacing: 14) {
                ContainerHoldStage(
                    kind: kind,
                    count: sharedCount,
                    duration: AppMotion.holdDuration(for: kind),
                    isEnabled: canOpen,
                    isWorking: isOpening,
                    title: canOpen ? "按住容器打开" : unavailableWhisper,
                    onComplete: openNext
                )
                .frame(height: kind == .capsule ? 236 : 272)

                ExchangeBalanceView(
                    kind: kind,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                RitualActionToken(
                    kind: kind,
                    title: "留下一件",
                    subtitle: "文字、照片或语音"
                ) {
                    showCompose = true
                }
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            isOpening = false
        }
        .fullScreenCover(isPresented: $showCompose) {
            ComposeSheet(kind: kind)
        }
        .fullScreenCover(item: $revealedItem) { item in
            RevealSheet(item: item)
        }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: kind) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: kind) }
    private var sharedCount: Int { data.count(kind: kind) }
    private var canOpen: Bool { credits > 0 && unopenedCount > 0 && !isOpening }

    private var sceneSubtitle: String {
        switch kind {
        case .star, .capsule: return "留下一件，才能打开一件。"
        case .paper: return "慢慢按住，确定后再打开。"
        }
    }

    private var balanceWhisper: String {
        if credits > 0, unopenedCount > 0 { return "可以打开一件" }
        if credits == 0, unopenedCount > 0 { return "先留下一件" }
        if credits > 0 { return "等待对方留下内容" }
        return "还没有内容"
    }

    private var unavailableWhisper: String {
        if credits == 0 { return "先留下一件" }
        return "没有待打开内容"
    }

    private func openNext() {
        guard canOpen else { return }
        isOpening = true
        openingTask?.cancel()
        openingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let item = await store.openNext(kind: kind)
            guard !Task.isCancelled else { return }
            isOpening = false
            revealedItem = item
            openingTask = nil
        }
    }
}

private struct ContainerHoldStage: View {
    let kind: ContainerKind
    let count: Int
    let duration: TimeInterval
    let isEnabled: Bool
    let isWorking: Bool
    let title: String
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HoldToCompleteSurface(
            duration: duration,
            isEnabled: isEnabled,
            isWorking: isWorking,
            onComplete: onComplete
        ) { progress, isPressing in
            VStack(spacing: 8) {
                ZStack {
                    AppTheme.glow(for: kind)
                        .opacity(isEnabled ? 0.86 : 0.34)

                    ContainerVisual(
                        kind: kind,
                        count: count,
                        style: .detail,
                        interactionProgress: reduceMotion ? 0 : progress,
                        isActive: isEnabled || isPressing
                    )
                    .padding(.horizontal, kind == .capsule ? 18 : 36)
                    .padding(.vertical, 8)
                }

                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(kind.tint.opacity(0.12))
                        Capsule()
                            .fill(kind.tint)
                            .scaleEffect(x: progress, anchor: .leading)
                    }
                    .frame(width: 52, height: 5)

                    Text(isWorking ? "正在打开" : title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isEnabled ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.54))
                }
                .frame(height: 20)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title)，里面积累了 \(count) 件内容。\(title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("持续按住完成，提前松开取消")
        .accessibilityAction {
            guard isEnabled, !isWorking else { return }
            onComplete()
        }
    }
}

struct ExchangeBalanceView: View {
    let kind: ContainerKind
    let credits: Int
    let waiting: Int
    let status: String

    var body: some View {
        HStack(spacing: 0) {
            BalanceValue(value: credits, label: "可打开", tint: kind.tint)
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 34)
            BalanceValue(value: waiting, label: "待打开", tint: kind.tint)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 34)

            Text(status)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 15)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("可打开 \(credits) 次，还有 \(waiting) 件内容等你打开。\(status)")
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
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
        }
        .frame(width: 66)
        .accessibilityLabel("\(label) \(value) 件")
    }
}

struct RitualDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.46))
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}
