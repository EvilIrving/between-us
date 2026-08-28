import SwiftUI

struct StarJarView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        ContainerDetailShell(
            kind: .star,
            title: "星星瓶",
            subtitle: "留下一件，才能打开一件。"
        ) {
            VStack(spacing: 18) {
                ZStack {
                    AppTheme.glow(for: .star)
                        .frame(height: 380)
                        .opacity(canDraw ? 1 : 0.46)

                    FunctionalContainerPlaceholder(
                        kind: .star,
                        count: sharedCount,
                        isActive: canDraw
                    )
                    .frame(width: 224, height: 286)
                    .rotationEffect(.degrees(isOpening ? -2.2 : 0))
                    .scaleEffect(isOpening ? 1.035 : 1)
                    .shadow(color: ContainerKind.star.tint.opacity(0.13), radius: 26, y: 18)
                }
                .accessibilityLabel("共同星星瓶，里面积累了 \(sharedCount) 颗星星")
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOpening)

                ExchangeBalanceView(
                    kind: .star,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                HoldToOpenControl(
                    kind: .star,
                    title: "按住打开",
                    inactiveTitle: unavailableWhisper,
                    duration: 0.72,
                    isEnabled: canDraw,
                    isWorking: isOpening,
                    onComplete: drawStar
                )
                .padding(.top, 2)

                RitualDivider(text: "留下新的")
                    .padding(.vertical, 2)

                RitualActionToken(
                    kind: .star,
                    title: "留下一件",
                    subtitle: "文字、照片或语音"
                ) {
                    showCompose = true
                }
                .padding(.bottom, 4)
            }
        }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            isOpening = false
        }
        .fullScreenCover(isPresented: $showCompose) {
            ComposeSheet(kind: .star)
        }
        .fullScreenCover(item: $revealedItem) { item in
            RevealSheet(item: item)
        }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: .star) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: .star) }
    private var sharedCount: Int { data.count(kind: .star) }
    private var canDraw: Bool { credits > 0 && unopenedCount > 0 && !isOpening }

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

    private func drawStar() {
        guard canDraw else { return }
        isOpening = true
        openingTask?.cancel()
        openingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let item = await store.drawStar()
            guard !Task.isCancelled else { return }
            isOpening = false
            revealedItem = item
            openingTask = nil
        }
    }
}

struct ExchangeBalanceView: View {
    let kind: ContainerKind
    let credits: Int
    let waiting: Int
    let status: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                BalanceValue(
                    value: credits,
                    label: "可打开",
                    tint: kind.tint
                )

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1, height: 32)

                BalanceValue(
                    value: waiting,
                    label: "待打开",
                    tint: kind.tint
                )
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.70))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
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
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? tint : AppTheme.secondaryText.opacity(0.48))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
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
