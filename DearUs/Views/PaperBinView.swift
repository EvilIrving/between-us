import SwiftUI

struct PaperBinView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        ContainerDetailShell(
            kind: .paper,
            title: "纸团篓",
            subtitle: "只有持续按住，内容才会打开。"
        ) {
            VStack(spacing: 19) {
                ZStack {
                    AppTheme.glow(for: .paper)
                        .frame(height: 340)
                        .opacity(canOpen ? 0.76 : 0.38)

                    FunctionalContainerPlaceholder(
                        kind: .paper,
                        count: sharedCount,
                        isActive: canOpen
                    )
                    .frame(width: 224, height: 276)
                    .rotationEffect(.degrees(isOpening ? 2.5 : 0))
                    .scaleEffect(isOpening ? 1.04 : 1)
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.74), value: isOpening)
                .accessibilityLabel("共同纸团篓，里面积累了 \(sharedCount) 个纸团")

                ExchangeBalanceView(
                    kind: .paper,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                HoldToOpenControl(
                    kind: .paper,
                    title: "按住打开",
                    inactiveTitle: unavailableWhisper,
                    duration: 1.55,
                    isEnabled: canOpen,
                    isWorking: isOpening,
                    onComplete: openPaper
                )

                RitualDivider(text: "留下新的")

                RitualActionToken(
                    kind: .paper,
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
        if credits > 0, unopenedCount > 0 { return "可以打开一件" }
        if credits == 0, unopenedCount > 0 { return "先留下一件" }
        if credits > 0 { return "等待对方留下内容" }
        return "还没有内容"
    }

    private var unavailableWhisper: String {
        if credits == 0 { return "先留下一件" }
        return "没有待打开内容"
    }

    private func openPaper() {
        guard canOpen else { return }
        isOpening = true
        openingTask?.cancel()
        openingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let item = await store.openNext(kind: .paper)
            guard !Task.isCancelled else { return }
            isOpening = false
            revealedItem = item
            openingTask = nil
        }
    }
}
