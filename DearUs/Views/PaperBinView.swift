import SwiftUI

struct PaperBinView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var papersSettle = false

    var body: some View {
        ContainerDetailShell(
            kind: .paper,
            title: "纸团篓",
            subtitle: "这里不会把委屈突然推到你面前。只有你主动按住、愿意接住时，它才会展开。"
        ) {
            VStack(spacing: 19) {
                ZStack {
                    AppTheme.glow(for: .paper)
                        .frame(height: 300)
                        .opacity(canOpen ? 0.76 : 0.38)

                    PaperBinIllustration(count: sharedCount)
                        .frame(height: 284)
                        .padding(.horizontal, 12)
                        .offset(y: papersSettle ? 1 : -3)
                        .rotationEffect(.degrees(isOpening ? 1.6 : 0))
                        .scaleEffect(isOpening ? 1.035 : 1)
                        .shadow(color: ContainerKind.paper.tint.opacity(0.12), radius: 22, y: 16)
                }
                .animation(.spring(response: 0.44, dampingFraction: 0.74), value: isOpening)
                .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: papersSettle)
                .onAppear { papersSettle = true }
                .accessibilityLabel("共同纸团篓，里面积累了 \(sharedCount) 个纸团")

                ExchangeBalanceView(
                    kind: .paper,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                VStack(spacing: 8) {
                    HoldToOpenControl(
                        kind: .paper,
                        title: "我现在愿意接住一个",
                        inactiveTitle: unavailableWhisper,
                        duration: 1.55,
                        isEnabled: canOpen,
                        isWorking: isOpening,
                        onComplete: openPaper
                    )

                    if canOpen {
                        Text("任何时候松开，都不会打开")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.52))
                    }
                }

                RitualDivider(text: "也可以先照顾自己的感受")

                RitualActionToken(
                    kind: .paper,
                    title: "揉一个自己的纸团，先把它放下",
                    subtitle: "写发生了什么、你的感受，以及你希望对方知道什么"
                ) {
                    showCompose = true
                }
                .padding(.bottom, 4)
            }
        }
        .fullScreenCover(isPresented: $showCompose) {
            ComposeSheet(kind: .paper)
        }
        .fullScreenCover(item: $revealedItem) { item in
            RevealSheet(item: item)
        }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: .paper) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: .paper) }
    private var sharedCount: Int { data.count(kind: .paper) }
    private var canOpen: Bool { credits > 0 && unopenedCount > 0 && !isOpening }

    private var balanceWhisper: String {
        if credits > 0, unopenedCount > 0 {
            return "这里确实有一份感受，但它不会催促，也不会在通知里暴露内容。"
        }
        if credits == 0, unopenedCount > 0 {
            return "交换不是惩罚。先诚实放下自己的感受，再决定何时接住对方。"
        }
        if credits > 0 {
            return "你已经放下了一次；现在没有新的纸团需要你承担。"
        }
        return "今天没有需要处理的事，也是一种平静。"
    }

    private var unavailableWhisper: String {
        if credits == 0 { return "先放下一个自己的纸团" }
        return "现在没有需要展开的纸团"
    }

    private func openPaper() {
        guard canOpen else { return }
        isOpening = true
        Task {
            try? await Task.sleep(nanoseconds: 460_000_000)
            let item = await store.openNext(kind: .paper)
            await MainActor.run {
                isOpening = false
                revealedItem = item
            }
        }
    }
}
