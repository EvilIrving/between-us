import SwiftUI

struct CapsuleBoxView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var boxBreathes = false

    var body: some View {
        ContainerDetailShell(
            kind: .capsule,
            title: "胶囊盒",
            subtitle: "鼓励、建议和认真想说的事，不必挤进一次仓促的聊天里。"
        ) {
            VStack(spacing: 19) {
                ZStack {
                    AppTheme.glow(for: .capsule)
                        .frame(height: 300)
                        .opacity(canOpen ? 0.92 : 0.48)

                    CapsuleBoxIllustration(count: sharedCount)
                        .frame(height: 278)
                        .padding(.horizontal, 8)
                        .rotation3DEffect(
                            .degrees(isOpening ? 8 : (boxBreathes ? 1.2 : -1.2)),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.45
                        )
                        .scaleEffect(isOpening ? 1.04 : 1)
                        .shadow(color: ContainerKind.capsule.tint.opacity(0.13), radius: 24, y: 16)
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isOpening)
                .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: boxBreathes)
                .onAppear { boxBreathes = true }
                .accessibilityLabel("共同胶囊盒，里面积累了 \(sharedCount) 颗胶囊")

                ExchangeBalanceView(
                    kind: .capsule,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                HoldToOpenControl(
                    kind: .capsule,
                    title: "按住，打开一颗",
                    inactiveTitle: unavailableWhisper,
                    duration: 0.78,
                    isEnabled: canOpen,
                    isWorking: isOpening,
                    onComplete: openCapsule
                )

                RitualDivider(text: "或者")

                RitualActionToken(
                    kind: .capsule,
                    title: "拿一颗空胶囊，封进想说的事",
                    subtitle: "它不会要求对方立刻回复"
                ) {
                    showCompose = true
                }
                .padding(.bottom, 4)
            }
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
        if credits > 0, unopenedCount > 0 {
            return "盒子里有一颗已经准备好，被你在不匆忙的时候打开。"
        }
        if credits == 0, unopenedCount > 0 {
            return "先封进一件你也认真想说的事，交换才会发生。"
        }
        if credits > 0 {
            return "你已经留下了一颗；对方准备好时，盒子会再变重。"
        }
        return "暂时没有胶囊，也不代表你们没有在彼此身边。"
    }

    private var unavailableWhisper: String {
        if credits == 0 { return "先封一颗自己的胶囊" }
        return "盒子里暂时没有新的胶囊"
    }

    private func openCapsule() {
        guard canOpen else { return }
        isOpening = true
        Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            let item = await store.openNext(kind: .capsule)
            await MainActor.run {
                isOpening = false
                revealedItem = item
            }
        }
    }
}
