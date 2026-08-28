import SwiftUI

struct CapsuleBoxView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        ContainerDetailShell(
            kind: .capsule,
            title: "胶囊盒",
            subtitle: "留下一件，才能打开一件。"
        ) {
            VStack(spacing: 19) {
                ZStack {
                    AppTheme.glow(for: .capsule)
                        .frame(height: 300)
                        .opacity(canOpen ? 0.92 : 0.48)

                    FunctionalContainerPlaceholder(
                        kind: .capsule,
                        count: sharedCount,
                        isActive: canOpen
                    )
                    .frame(width: 224, height: 250)
                    .padding(.horizontal, 8)
                    .rotation3DEffect(
                            .degrees(isOpening ? 8 : 0),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.45
                        )
                        .scaleEffect(isOpening ? 1.04 : 1)
                        .shadow(color: ContainerKind.capsule.tint.opacity(0.13), radius: 24, y: 16)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOpening)
                .accessibilityLabel("共同胶囊盒，里面积累了 \(sharedCount) 颗胶囊")

                ExchangeBalanceView(
                    kind: .capsule,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                HoldToOpenControl(
                    kind: .capsule,
                    title: "按住打开",
                    inactiveTitle: unavailableWhisper,
                    duration: 0.78,
                    isEnabled: canOpen,
                    isWorking: isOpening,
                    onComplete: openCapsule
                )

                RitualDivider(text: "留下新的")

                RitualActionToken(
                    kind: .capsule,
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
            ComposeSheet(kind: .capsule)
        }
        .fullScreenCover(item: $revealedItem) { item in
            RevealSheet(item: item)
        }
    }

    private var data: AppData { store.viewModel.data }
    private var credits: Int { data.activeCredits(kind: .capsule) }
    private var unopenedCount: Int { data.unopenedCountFromCounterpart(kind: .capsule) }
    private var sharedCount: Int { data.count(kind: .capsule) }
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

    private func openCapsule() {
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
            let item = await store.openNext(kind: .capsule)
            guard !Task.isCancelled else { return }
            isOpening = false
            revealedItem = item
            openingTask = nil
        }
    }
}
