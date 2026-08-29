import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeSheet: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: DearUsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var imageDrafts: [AttachmentDraft] = []
    @State private var attachmentDraft: AttachmentDraft?
    @State private var isLoadingAttachment = false
    @State private var isSaving = false
    @State private var localNotice: LocalNotice?
    @State private var didRestoreDraft = false
    @State private var didSave = false
    @State private var draftSaveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private let maxLength = 4_000
    private let draftRepository = ComposeDraftRepository()

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            GeometryReader { proxy in
                let editorHeight = min(430, max(300, proxy.size.height - 312))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        content
                            .frame(maxWidth: .infinity)
                            .frame(height: editorHeight)
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
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .animation(.easeOut(duration: 0.22), value: localNotice?.id)
        .onChange(of: selectedMediaItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await importPickerItems(newValue) }
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > maxLength {
                text = String(newValue.prefix(maxLength))
                return
            }
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
            isFocused = attachmentDraft?.kind != .audio
        }
        .onDisappear {
            draftSaveTask?.cancel()
            if !didSave {
                draftRepository.saveText(text, spaceID: draftSpaceID, kind: kind)
            }
            recorder.discard()
            cleanupTemporaryDraft(attachmentDraft)
            for draft in imageDrafts { cleanupTemporaryDraft(draft) }
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
    private var content: some View {
        PhotoRitualEditor(
            kind: kind,
            selectedMediaItems: $selectedMediaItems,
            drafts: attachmentDraft?.kind == .audio ? [] : imageDrafts,
            isLoading: isLoadingAttachment,
            allowsPhotos: attachmentDraft?.kind != .audio,
            remove: removeImage
        ) {
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
                    hasComposeContent: hasTextOrImages,
                    isDisabled: isSaving || isLoadingAttachment,
                    onCommit: save,
                    onRecorded: voiceRecorded,
                    onPreviewed: voicePreviewed,
                    onCancelled: {
                        localNotice = LocalNotice(title: "已取消", message: "录音未保存。")
                    },
                    onTooShort: {
                        localNotice = LocalNotice(title: "录音太短", message: "请按住并多说一点。")
                    },
                    onError: { message in
                        localNotice = LocalNotice(title: "无法录音", message: message)
                    }
                )
            }
        }
    }

    private var draftSpaceID: String {
        store.viewModel.data.relationship?.zoneName ?? "unassigned"
    }

    private var isVoiceInteractionLocked: Bool {
        recorder.isRecording || recorder.isPreparing
    }

    private var hasTextOrImages: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageDrafts.isEmpty
    }

    private var canSave: Bool {
        guard !isSaving, !isLoadingAttachment, !recorder.isRecording, !recorder.isPreparing else {
            return false
        }
        return hasTextOrImages || attachmentDraft?.kind == .audio
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        let snapshot = draftRepository.snapshot(spaceID: draftSpaceID, kind: kind)
        text = snapshot.text
        attachmentDraft = snapshot.attachment
        if snapshot.attachment?.kind == .image {
            imageDrafts = snapshot.attachment.map { [$0] } ?? []
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
        guard replaceAttachment(with: draft) else { return }
        save()
    }

    private func voicePreviewed(_ draft: AttachmentDraft) {
        _ = replaceAttachment(with: draft)
    }

    private func interruptActiveRecording() {
        guard recorder.isRecording || recorder.isPreparing else { return }
        recorder.discard()
        RitualHaptics.warning()
        localNotice = LocalNotice(
            title: "录音停下来了",
            message: "系统中断了这段语音，它没有被放进容器。"
        )
    }

    private func save() {
        guard canSave else { return }
        isFocused = false
        isSaving = true
        let drafts = attachmentDraft?.kind == .audio
            ? (attachmentDraft.map { [$0] } ?? [])
            : imageDrafts
        attachmentDraft = nil
        imageDrafts = []

        Task {
            let success = await store.add(kind: kind, text: text, attachments: drafts)
            await MainActor.run {
                if success {
                    didSave = true
                    draftSaveTask?.cancel()
                    draftRepository.clear(spaceID: draftSpaceID, kind: kind)
                    RitualHaptics.success()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 160_000_000)
                        dismiss()
                    }
                } else {
                    if drafts.first?.kind == .audio {
                        attachmentDraft = drafts.first
                    } else {
                        imageDrafts = drafts
                    }
                    isSaving = false
                    RitualHaptics.warning()
                    localNotice = LocalNotice(
                        title: "保存失败",
                        message: "草稿已保留，可以立即重试。"
                    )
                }
            }
        }
    }

    private func importPickerItems(_ items: [PhotosPickerItem]) async {
        isFocused = false
        isLoadingAttachment = true
        defer {
            isLoadingAttachment = false
            selectedMediaItems = []
        }

        let availableSlots = max(0, 9 - imageDrafts.count)
        guard availableSlots > 0 else { return }
        var imported: [AttachmentDraft] = []

        do {
            for item in items.prefix(availableSlots) {
                guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                      let data = try await item.loadTransferable(type: Data.self) else {
                    throw MediaImportError.unavailable
                }
                guard Int64(data.count) <= MediaFileStore.maximumAttachmentBytes else {
                    throw MediaFileError.fileTooLarge
                }

                let fileExtension = type.preferredFilenameExtension ?? "jpg"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dear-us-\(UUID().uuidString.lowercased()).\(fileExtension)")
                try data.write(to: url, options: .atomic)
                imported.append(AttachmentDraft(
                    kind: .image,
                    url: url,
                    originalFilename: "照片.\(fileExtension)"
                ))
            }
            imageDrafts.append(contentsOf: imported)
            RitualHaptics.selection()
        } catch {
            for draft in imported { cleanupTemporaryDraft(draft) }
            localNotice = LocalNotice(title: "无法读取照片", message: error.localizedDescription)
        }
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
                message: "请重新选择或录制。"
            )
            return false
        }
    }

    private func removeAttachment() {
        draftRepository.removeAttachment(spaceID: draftSpaceID, kind: kind)
        cleanupTemporaryDraft(attachmentDraft)
        attachmentDraft = nil
    }

    private func removeImage(at index: Int) {
        guard imageDrafts.indices.contains(index) else { return }
        cleanupTemporaryDraft(imageDrafts.remove(at: index))
    }

    private func removeAllAttachments() {
        removeAttachment()
        for draft in imageDrafts { cleanupTemporaryDraft(draft) }
        imageDrafts = []
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

private struct WhisperPaperEditor: View {
    let kind: ContainerKind
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let maxLength: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: kind == .paper ? 19 : 28, style: .continuous)
                .fill(AppTheme.paper.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: kind == .paper ? 19 : 28, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 22, y: 12)
                .rotationEffect(.degrees(kind == .paper ? -0.7 : 0))

            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .focused(isFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineSpacing(6)
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                if text.count > maxLength - 400 {
                    Text("还可以写 \(maxLength - text.count) 个字")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.54))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
            }

            if text.isEmpty {
                Text(kind.placeholder)
                    .font(.system(size: 18, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.40))
                    .lineSpacing(6)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 25)
                    .allowsHitTesting(false)
            }

            if kind == .paper {
                PaperCreaseShape(seed: 7)
                    .stroke(AppTheme.secondaryText.opacity(0.07), lineWidth: 1)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 270, maxHeight: 410)
        .padding(.vertical, 6)
    }
}

private struct PhotoRitualEditor<Composer: View>: View {
    let kind: ContainerKind
    @Binding var selectedMediaItems: [PhotosPickerItem]
    let drafts: [AttachmentDraft]
    let isLoading: Bool
    let allowsPhotos: Bool
    let remove: (Int) -> Void
    let composer: Composer

    init(
        kind: ContainerKind,
        selectedMediaItems: Binding<[PhotosPickerItem]>,
        drafts: [AttachmentDraft],
        isLoading: Bool,
        allowsPhotos: Bool,
        remove: @escaping (Int) -> Void,
        @ViewBuilder composer: () -> Composer
    ) {
        self.kind = kind
        _selectedMediaItems = selectedMediaItems
        self.drafts = drafts
        self.isLoading = isLoading
        self.allowsPhotos = allowsPhotos
        self.remove = remove
        self.composer = composer()
    }

    var body: some View {
        VStack(spacing: 12) {
            if allowsPhotos {
                photoGrid
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 12)

            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var photoGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .center, spacing: 8) {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                PhotoDraftTile(
                    draft: draft,
                    index: index,
                    remove: remove
                )
            }

            if drafts.count < 9 {
                photoPicker {
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.46))
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .contentShape(Rectangle())
                    .accessibilityLabel("添加照片，最多 9 张")
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        return Array(
            repeating: GridItem(.flexible(minimum: 64, maximum: 104), spacing: 8),
            count: 3
        )
    }

    private func photoPicker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(
            selection: $selectedMediaItems,
            maxSelectionCount: max(1, 9 - drafts.count),
            matching: .images,
            photoLibrary: .shared()
        ) { label() }
        .buttonStyle(SoftScaleButtonStyle())
        .disabled(isLoading || drafts.count >= 9)
    }
}

private struct PhotoDraftTile: View {
    let draft: AttachmentDraft
    let index: Int
    let remove: (Int) -> Void

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = UIImage(contentsOfFile: draft.url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.36))
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
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
                .accessibilityLabel("移除第 \(index + 1) 张照片")
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
}

private enum MediaImportError: LocalizedError {
    case unavailable

    var errorDescription: String? { "系统没有返回可读取的照片。" }
}
