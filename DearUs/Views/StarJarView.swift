import SwiftUI

struct StarJarView: View {
    @EnvironmentObject private var store: DearUsStore
    @State private var showCompose = false
    @State private var revealedItem: SecretItem?
    @State private var isOpening = false
    @State private var bottleTilts = false

    var body: some View {
        ContainerDetailShell(
            kind: .star,
            title: "星星瓶",
            subtitle: "每折好一颗自己的星星，瓶子才愿意把对方的一颗交给你。"
        ) {
            VStack(spacing: 18) {
                ZStack {
                    AppTheme.glow(for: .star)
                        .frame(height: 380)
                        .opacity(canDraw ? 1 : 0.46)

                    StarPhysicsView(starCount: sharedCount)
                        .frame(height: 390)
                        .rotationEffect(.degrees(isOpening ? -2.2 : (bottleTilts ? 0.45 : -0.45)))
                        .scaleEffect(isOpening ? 1.035 : 1)
                        .shadow(color: ContainerKind.star.tint.opacity(0.13), radius: 26, y: 18)
                }
                .accessibilityLabel("共同星星瓶，里面积累了 \(sharedCount) 颗星星")
                .animation(.spring(response: 0.42, dampingFraction: 0.70), value: isOpening)
                .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: bottleTilts)
                .onAppear { bottleTilts = true }

                ExchangeBalanceView(
                    kind: .star,
                    credits: credits,
                    waiting: unopenedCount,
                    status: balanceWhisper
                )

                HoldToOpenControl(
                    kind: .star,
                    title: "闭上眼，抽一颗",
                    inactiveTitle: unavailableWhisper,
                    duration: 0.72,
                    isEnabled: canDraw,
                    isWorking: isOpening,
                    onComplete: drawStar
                )
                .padding(.top, 2)

                RitualDivider(text: "或者")
                    .padding(.vertical, 2)

                RitualActionToken(
                    kind: .star,
                    title: "拿一张空纸，折一颗自己的",
                    subtitle: "文字、照片或一段按住说出的语音"
                ) {
                    showCompose = true
                }
                .padding(.bottom, 4)
            }
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
        if credits > 0, unopenedCount > 0 {
            return "瓶子里有从未见过的光，也记得你曾经留下过什么。"
        }
        if credits == 0, unopenedCount > 0 {
            return "它知道里面有新星星，但想先等你也认真留下一颗。"
        }
        if credits > 0 {
            return "你已经留好了交换的心意；等对方也想起一句话。"
        }
        return "空一点也没关系，喜欢不是每天都要完成的任务。"
    }

    private var unavailableWhisper: String {
        if credits == 0 { return "先折一颗自己的星星" }
        return "对方还没有留下新的星星"
    }

    private func drawStar() {
        guard canDraw else { return }
        isOpening = true
        Task {
            try? await Task.sleep(nanoseconds: 360_000_000)
            let item = await store.drawStar()
            await MainActor.run {
                isOpening = false
                revealedItem = item
            }
        }
    }
}

struct ExchangeBalanceView: View {
    let kind: ContainerKind
    let credits: Int
    let waiting: Int
    let status: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                WhisperBeads(
                    kind: kind,
                    count: credits,
                    title: "你留下的交换心意"
                )

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1, height: 32)

                WhisperBeads(
                    kind: kind,
                    count: waiting,
                    title: "等你打开的内容"
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

private struct WhisperBeads: View {
    let kind: ContainerKind
    let count: Int
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < min(count, 5) ? kind.tint.opacity(0.82) : Color.white.opacity(0.42))
                        .frame(width: 7, height: 7)
                        .overlay { Circle().stroke(kind.tint.opacity(0.18), lineWidth: 1) }
                }
                if count > 5 {
                    Text("+")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(kind.tint)
                }
            }

            Text(count == 0 ? "还没有" : "\(count) 份")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
        }
        .accessibilityLabel("\(title) \(count) 份")
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
