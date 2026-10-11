import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeSheet: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: BetweenUsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [AttachmentDraft] = []
    @State private var attachmentDraft: AttachmentDraft?
    @StateObject private var mediaProgress = MediaImportProgress()
    @State private var isFetchingMedia = false
    @State private var mediaImportTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var localNotice: LocalNotice?
    @State private var didRestoreDraft = false
    @State private var didSave = false
    @State private var isShowingLifetimeUnlock = false
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var selectedDetent: PresentationDetent = .fraction(0.44)
    /// 这次写下的纸：创作时自由选，写入时冻结进卡片（§10.3）。
    @State private var paperID: PaperID = PaperRegistry.defaultPaperID
    @FocusState private var isFocused: Bool

    private let draftRepository = ComposeDraftRepository()
    private let compactDetent: PresentationDetent = .fraction(0.44)
    private let mediumDetent: PresentationDetent = .fraction(0.58)
    private let mediaGridDetent: PresentationDetent = .fraction(0.72)

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        content(paperWidth: proxy.size.width * PaperSheetView.widthRatio)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        Color.clear
                            .frame(height: 8)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(isVoiceInteractionLocked)
            }

            if isSaving {
                SavingRitualOverlay(kind: kind)
                    .transition(.opacity)
            }

            if let localNotice {
                VStack {
                    WhisperNoticeBanner(
                        title: localNotice.title,
                        message: localNotice.message,
                        dismiss: { self.localNotice = nil }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .task(id: localNotice.id) {
                        guard localNotice.autoDismiss else { return }
                        try? await Task.sleep(for: AppMotion.noticeAutoDismissDelay(message: localNotice.message))
                        if self.localNotice?.id == localNotice.id {
                            self.localNotice = nil
                        }
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .animation(.easeOut(duration: 0.22), value: localNotice?.id)
        .presentationDetents(
            [compactDetent, mediumDetent, mediaGridDetent],
            selection: $selectedDetent
        )
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .onChange(of: selectedMediaItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            mediaImportTask = Task { await importPickerItems(newValue) }
        }
        .onChange(of: mediaDrafts.count) { _, _ in
            selectedDetent = restingDetent
        }
        .onChange(of: text) { _, newValue in
            guard didRestoreDraft else { return }
            scheduleDraftSave(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawValue) == .began else { return }
            interruptActiveRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            interruptActiveRecording()
        }
        .onAppear {
            restoreDraftIfNeeded()
            selectedDetent = restingDetent
            isFocused = false
        }
        .onDisappear {
            draftSaveTask?.cancel()
            mediaImportTask?.cancel()
            mediaImportTask = nil
            if !didSave {
                draftRepository.saveText(text, spaceID: draftSpaceID, kind: kind)
            }
            recorder.discard()
            cleanupTemporaryDraft(attachmentDraft)
            for draft in mediaDrafts { cleanupTemporaryDraft(draft) }
        }
        .sheet(isPresented: $isShowingLifetimeUnlock) {
            LifetimeUnlockView(context: .quotaReached)
        }
        .interactiveDismissDisabled(isSaving || recorder.isRecording)
    }

    private var header: some View {
        HStack(alignment: .center) {
            SceneCloseControl {
                isFocused = false
                dismiss()
            }
            .opacity(isSaving || isVoiceInteractionLocked ? 0 : 1)
            .disabled(isSaving || isVoiceInteractionLocked)

            Spacer()

            Text(kind.composeTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
    }

    @ViewBuilder
    private func content(paperWidth: CGFloat) -> some View {
        MediaRitualEditor(
            kind: kind,
            selectedMediaItems: $selectedMediaItems,
            drafts: mediaDrafts,
            preparing: mediaProgress.values,
            isLoading: isFetchingMedia && mediaDrafts.isEmpty,
            allowsMedia: true,
            remove: removeMedia
        ) {
            VStack(spacing: 10) {
                paperPicker

                if let draft = attachmentDraft, draft.kind == .audio {
                    VoiceDraftPreviewPlayer(
                        url: draft.url,
                        expectedDuration: draft.duration,
                        tint: kind.tint,
                        discard: removeAttachment,
                        commit: save
                    )
                } else {
                    VoiceHoldRecorderView(
                        kind: kind,
                        recorder: recorder,
                        text: $text,
                        isFocused: $isFocused,
                        paperWidth: paperWidth,
                        hasText: hasText,
                        isDisabled: isSaving || isPreparingMedia,
                        onCommit: save,
                        onRecorded: voiceRecorded,
                        onPreviewed: voicePreviewed,
                        onCancelled: {
                            localNotice = LocalNotice(title: "录音已取消", message: "")
                        },
                        onTooShort: {
                            localNotice = LocalNotice(title: "录音太短", message: "")
                        },
                        onError: { message in
                            localNotice = LocalNotice(title: "无法录音", message: message, autoDismiss: false)
                        }
                    )
                }
            }
        }
    }

    /// 创作时选纸：两张纸各一个胶囊（左边是这张纸的缩略，右边是纸名）。
    /// 物件不参与——同一个物件想用哪张纸就用哪张（§10.3）。
    private var paperPicker: some View {
        HStack(spacing: 8) {
            ForEach(PaperRegistry.all) { spec in
                paperChip(spec)
            }

            Spacer(minLength: 0)
        }
        .disabled(isSaving || isVoiceInteractionLocked)
        .opacity(isSaving || isVoiceInteractionLocked ? 0.5 : 1)
    }

    private func paperChip(_ spec: PaperSheetSpec) -> some View {
        let isSelected = spec.id == paperID

        return Button {
            guard !isSelected else { return }
            paperID = spec.id
            RitualHaptics.selection()
        } label: {
            HStack(spacing: 8) {
                PaperThumbnail(spec: spec)

                Text(T(key: spec.nameKey))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Color.white.opacity(isSelected ? 0.92 : 0.42))
            }
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? kind.tint.opacity(0.55) : AppTheme.border,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T(key: spec.nameKey))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var draftSpaceID: String {
        store.viewModel.data.relationship?.zoneName ?? "unassigned"
    }

    private var isVoiceInteractionLocked: Bool {
        recorder.isRecording || recorder.isPreparing
    }

    /// 取文件和归一化都算「正在准备」：这段时间不能保存，也不能再挑新的。
    private var isPreparingMedia: Bool {
        isFetchingMedia || !mediaProgress.values.isEmpty
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var restingDetent: PresentationDetent {
        let visibleTiles = mediaDrafts.count < 9 ? mediaDrafts.count + 1 : mediaDrafts.count
        let rows = max(1, Int(ceil(Double(visibleTiles) / 3.0)))

        switch rows {
        case 1: return compactDetent
        case 2: return mediumDetent
        default: return mediaGridDetent
        }
    }

    private var canSave: Bool {
        guard !isSaving, !isPreparingMedia, !recorder.isRecording, !recorder.isPreparing else {
            return false
        }
        return hasText || !mediaDrafts.isEmpty || attachmentDraft?.kind == .audio
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        let snapshot = draftRepository.snapshot(spaceID: draftSpaceID, kind: kind)
        text = snapshot.text
        attachmentDraft = snapshot.attachment
        if snapshot.attachment?.kind == .image || snapshot.attachment?.kind == .video {
            mediaDrafts = snapshot.attachment.map { [$0] } ?? []
            attachmentDraft = nil
        } else if snapshot.attachment?.kind == .audio {
            text = ""
        }
        didRestoreDraft = true
    }

    private func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        let repository = draftRepository
        let spaceID = draftSpaceID
        let draftKind = kind
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            repository.saveText(value, spaceID: spaceID, kind: draftKind)
        }
    }

    private func voiceRecorded(_ draft: AttachmentDraft) {
        _ = replaceAttachment(with: draft)
    }

    private func voicePreviewed(_ draft: AttachmentDraft) {
        _ = replaceAttachment(with: draft)
    }

    private func interruptActiveRecording() {
        guard recorder.isRecording || recorder.isPreparing else { return }
        recorder.discard()
        RitualHaptics.warning()
        localNotice = LocalNotice(
            title: "录音已中断",
            message: ""
        )
    }

    private func save() {
        guard canSave else { return }
        guard store.viewModel.canAddContent else {
            isFocused = false
            RitualHaptics.warning()
            isShowingLifetimeUnlock = true
            return
        }
        isFocused = false
        isSaving = true
        let audioDrafts = attachmentDraft?.kind == .audio
            ? (attachmentDraft.map { [$0] } ?? [])
            : []
        let drafts = mediaDrafts + audioDrafts
        attachmentDraft = nil
        mediaDrafts = []

        Task {
            let result = await store.add(kind: kind, text: text, attachments: drafts, paperID: paperID)
            await MainActor.run {
                switch result {
                case .success:
                    didSave = true
                    draftSaveTask?.cancel()
                    draftRepository.clear(spaceID: draftSpaceID, kind: kind)
                    RitualHaptics.success()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 160_000_000)
                        dismiss()
                    }

                case .quotaReached:
                    attachmentDraft = drafts.first(where: { $0.kind == .audio })
                    mediaDrafts = drafts.filter { $0.kind == .image || $0.kind == .video }
                    isSaving = false
                    RitualHaptics.warning()
                    isShowingLifetimeUnlock = true

                case .failed:
                    attachmentDraft = drafts.first(where: { $0.kind == .audio })
                    mediaDrafts = drafts.filter { $0.kind == .image || $0.kind == .video }
                    isSaving = false
                    RitualHaptics.warning()
                    localNotice = LocalNotice(
                        title: "保存失败",
                        message: "草稿已保留，请重试。",
                        autoDismiss: false
                    )
                }
            }
        }
    }

    private func importPickerItems(_ items: [PhotosPickerItem]) async {
        isFocused = false
        defer { selectedMediaItems = [] }

        let availableSlots = max(0, 9 - mediaDrafts.count)
        guard availableSlots > 0 else { return }

        var didImport = false
        var failures: [Error] = []

        for item in items.prefix(availableSlots) {
            if Task.isCancelled { break }
            do {
                try await importPickerItem(item)
                didImport = true
            } catch is CancellationError {
                break
            } catch {
                failures.append(error)
            }
        }

        if didImport { RitualHaptics.selection() }
        if let failure = failures.first { showMediaImportFailure(failure) }
    }

    /// 一条媒体从取文件到归一化完成：先把格子占上，进度就长在这条草稿自己身上。
    /// 失败只丢这一条，不影响同批其他内容。
    private func importPickerItem(_ item: PhotosPickerItem) async throws {
        isFetchingMedia = true
        let file: MediaPickerFile?
        do {
            file = try await item.loadTransferable(type: MediaPickerFile.self)
        } catch {
            isFetchingMedia = false
            throw error
        }
        isFetchingMedia = false
        guard let file else { throw MediaNormalizerError.mediaUnreadable }

        let draft = AttachmentDraft(
            kind: file.kind,
            url: file.url,
            originalFilename: file.originalFilename,
            duration: nil
        )
        mediaDrafts.append(draft)
        mediaProgress.begin(draft.id)
        defer { mediaProgress.end(draft.id) }

        do {
            let progress = mediaProgress
            let normalized = try await MediaNormalizer.shared.normalize(draft) { value in
                Task { @MainActor in progress.update(draft.id, value) }
            }
            guard MediaFileStore.fileSize(at: normalized.url) <= MediaFileStore.maximumAttachmentBytes else {
                throw MediaFileError.fileTooLarge
            }
            guard let index = mediaDrafts.firstIndex(where: { $0.id == draft.id }) else {
                cleanupTemporaryDraft(normalized)
                return
            }
            mediaDrafts[index] = normalized
            if normalized.url != draft.url { cleanupTemporaryDraft(draft) }
        } catch {
            mediaDrafts.removeAll { $0.id == draft.id }
            cleanupTemporaryDraft(draft)
            throw error
        }
    }

    private func showMediaImportFailure(_ error: Error) {
        RitualHaptics.warning()
        if let normalizerError = error as? MediaNormalizerError, case .videoTooLong = normalizerError {
            localNotice = LocalNotice(title: T("视频最长 1 分钟"), message: "")
            return
        }
        localNotice = LocalNotice(title: T("无法准备媒体"), message: error.localizedDescription, autoDismiss: false)
    }

    @discardableResult
    private func replaceAttachment(with draft: AttachmentDraft) -> Bool {
        do {
            let stored = try draftRepository.storeAttachment(
                draft,
                spaceID: draftSpaceID,
                kind: kind
            )
            cleanupTemporaryDraft(attachmentDraft)
            cleanupTemporaryDraft(draft)
            attachmentDraft = stored
            return true
        } catch {
            cleanupTemporaryDraft(draft)
            localNotice = LocalNotice(
                title: "无法保存草稿",
                message: "请重新选择或录制。",
                autoDismiss: false
            )
            return false
        }
    }

    private func removeAttachment() {
        draftRepository.removeAttachment(spaceID: draftSpaceID, kind: kind)
        cleanupTemporaryDraft(attachmentDraft)
        attachmentDraft = nil
    }

    private func removeMedia(at index: Int) {
        guard mediaDrafts.indices.contains(index) else { return }
        cleanupTemporaryDraft(mediaDrafts.remove(at: index))
    }

    private func removeAllAttachments() {
        removeAttachment()
        for draft in mediaDrafts { cleanupTemporaryDraft(draft) }
        mediaDrafts = []
        selectedMediaItems = []
    }

    private func cleanupTemporaryDraft(_ draft: AttachmentDraft?) {
        guard let draft else { return }
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if draft.url.standardizedFileURL.path.hasPrefix(temporaryDirectory) {
            try? FileManager.default.removeItem(at: draft.url)
        }
    }
}

struct MediaRitualEditor<Composer: View>: View {
    let kind: ContainerKind
    @Binding var selectedMediaItems: [PhotosPickerItem]
    let drafts: [AttachmentDraft]
    /// 归一化进度（草稿 id → 0…1）；出现在这里就代表这条还在准备，不在就是好了。
    let preparing: [UUID: Double]
    let isLoading: Bool
    let allowsMedia: Bool
    let remove: (Int) -> Void
    let composer: Composer

    init(
        kind: ContainerKind,
        selectedMediaItems: Binding<[PhotosPickerItem]>,
        drafts: [AttachmentDraft],
        preparing: [UUID: Double],
        isLoading: Bool,
        allowsMedia: Bool,
        remove: @escaping (Int) -> Void,
        @ViewBuilder composer: () -> Composer
    ) {
        self.kind = kind
        _selectedMediaItems = selectedMediaItems
        self.drafts = drafts
        self.preparing = preparing
        self.isLoading = isLoading
        self.allowsMedia = allowsMedia
        self.remove = remove
        self.composer = composer()
    }

    var body: some View {
        VStack(spacing: 12) {
            if allowsMedia {
                mediaGrid
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            composer
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .opacity(isLoading ? 0.48 : 1)
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(kind.tint)
                    .padding(16)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
        }
        .allowsHitTesting(!isLoading)
    }

    private var mediaGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                MediaDraftTile(
                    draft: draft,
                    index: index,
                    preparingProgress: preparing[draft.id],
                    remove: remove
                )
            }

            if drafts.count < 9 {
                mediaPicker {
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.46))
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .contentShape(Rectangle())
                    .accessibilityLabel(T("添加图片或视频，最多 9 个"))
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        return Array(
            repeating: GridItem(.flexible(minimum: 64), spacing: 8),
            count: 3
        )
    }

    private func mediaPicker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(
            selection: $selectedMediaItems,
            maxSelectionCount: max(1, 9 - drafts.count),
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) { label() }
        .buttonStyle(SoftScaleButtonStyle())
        .disabled(isLoading || isPreparing || drafts.count >= 9)
        .accessibilityHint(T("视频最长 1 分钟"))
    }

    private var isPreparing: Bool {
        !preparing.isEmpty
    }
}

private struct MediaDraftTile: View {
    let draft: AttachmentDraft
    let index: Int
    /// 归一化进度 0…1；nil 表示这条已经准备好。
    let preparingProgress: Double?
    let remove: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPreparing: Bool {
        preparingProgress != nil
    }

    /// 准备中的内容从半透明里慢慢显出来：进度长在这条草稿自己身上，不另起进度控件。
    private var contentOpacity: Double {
        guard let preparingProgress else { return 1 }
        return 0.38 + 0.62 * min(max(preparingProgress, 0), 1)
    }

    private var draftPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.08)
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.56))
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if draft.kind == .image {
                    AttachmentImage(url: draft.url, maxPixel: 640) { draftPlaceholder }
                } else {
                    draftPlaceholder
                }
            }
            .opacity(contentOpacity)
            .animation(reduceMotion ? nil : .linear(duration: 0.2), value: contentOpacity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !isPreparing {
                    Button {
                        RitualHaptics.selection()
                        remove(index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.34))
                            .clipShape(Circle())
                    }
                    .buttonStyle(SoftScaleButtonStyle())
                    .padding(5)
                    .accessibilityLabel(T("移除第 %d 个媒体", index + 1))
                }
            }
            .overlay {
                if isPreparing {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(T("正在准备媒体"))
                }
            }
    }
}

private struct SavingRitualOverlay: View {
    let kind: ContainerKind

    var body: some View {
        ZStack {
            Color.white.opacity(0.22)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(kind.tint)

                Text("正在保存")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .allowsHitTesting(true)
    }
}

private struct LocalNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// 失败类通知常驻到点按关闭，短暂状态默认自动收起。
    var autoDismiss = true
}

/// 媒体归一化的进度账本：写在字典里就代表这条草稿还在准备，去掉就是准备好了。
/// 归一化在别的执行器上跑，进度通过这个 @MainActor 对象回到界面。
@MainActor
private final class MediaImportProgress: ObservableObject {
    @Published private(set) var values: [UUID: Double] = [:]

    func begin(_ id: UUID) {
        values[id] = 0
    }

    func update(_ id: UUID, _ value: Double) {
        guard values[id] != nil else { return }
        values[id] = value
    }

    func end(_ id: UUID) {
        values[id] = nil
    }
}
