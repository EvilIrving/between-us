import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: BetweenUsStore

    var body: some View {
        ZStack {
            switch store.viewModel.phase {
            case .loading:
                LoadingView()
            case .needsICloud(let message):
                ICloudRequiredView(message: message)
            case .needsRelationship, .ready:
                // 还没有空间、创建者还没等到对方、或者这一刻正在连接，都落在连接页上。
                // 两个人真正都在空间里之后，房间才出现。
                if store.viewModel.showsConnectionPage {
                    ConnectionView(mode: .live)
                } else {
                    HomeView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.viewModel.phase)
        .animation(.easeInOut(duration: 0.5), value: store.viewModel.showsConnectionPage)
        .task {
            await store.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .betweenUsSharingFailed)) { notification in
            guard let error = notification.object as? Error else { return }
            Task { await store.reportSharingFailure(error) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .betweenUsSharingStopped)) { _ in
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
    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: .star)

            VStack(spacing: 20) {
                ContainerVisual(kind: .star, count: 5, style: .compact)
                    .frame(width: 142, height: 164)

                VStack(spacing: 8) {
                    ProgressView()
                        .tint(AppTheme.secondaryText)
                    Text("正在加载")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }
}
