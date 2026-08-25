import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: DearUsStore

    var body: some View {
        Group {
            switch store.viewModel.phase {
            case .loading:
                LoadingView()
            case .needsICloud(let message):
                ICloudRequiredView(message: message)
            case .needsRelationship:
                RelationshipOnboardingView()
            case .ready:
                HomeView()
            }
        }
        .task {
            await store.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dearUsSharingFailed)) { notification in
            guard let error = notification.object as? Error else { return }
            Task { await store.reportSharingFailure(error) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dearUsSharingStopped)) { _ in
            Task { await store.sharingDidStop() }
        }
        .sheet(item: shareSheetBinding) { payload in
            CloudSharingView(share: payload.share, container: payload.container)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let notice = store.viewModel.notice {
                WhisperNoticeBanner(
                    title: notice.title,
                    message: notice.message,
                    dismiss: {
                        Task { await store.clearNotice() }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: store.viewModel.notice?.id)
    }

    private var shareSheetBinding: Binding<ShareSheetPayload?> {
        Binding(
            get: { store.viewModel.shareSheet },
            set: { newValue in
                guard newValue == nil else { return }
                Task { await store.dismissShareSheet() }
            }
        )
    }
}

private struct LoadingView: View {
    @State private var bottleBreathes = false

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            VStack(spacing: 20) {
                StarBottleIllustration(count: 5)
                    .frame(width: 142, height: 164)
                    .scaleEffect(bottleBreathes ? 1.025 : 0.98)
                    .shadow(color: ContainerKind.star.tint.opacity(0.16), radius: 22, y: 12)

                VStack(spacing: 8) {
                    ProgressView()
                        .tint(AppTheme.secondaryText)
                    Text("正在打开你们的共同房间")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: bottleBreathes)
            .onAppear { bottleBreathes = true }
        }
    }
}
