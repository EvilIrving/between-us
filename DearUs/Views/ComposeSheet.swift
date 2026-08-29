import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ComposeMode: String, CaseIterable, Identifiable {
    case text
    case photo
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "写"
        case .photo: return "照片"
        case .voice: return "语音"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "pencil.line"
        case .photo: return "photo"
        case .voice: return "waveform"
        }
    }
}

struct ComposeSheet: View {
    let kind: ContainerKind

    @EnvironmentObject private var store: DearUsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var mode: ComposeMode = .text
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var imageDrafts: [AttachmentDraft] = []
    @State private var attachmentDraft: AttachmentDraft?
    @State private var isLoadingAttachment = false
    @State private var isSaving = false
    @State private var isPreparingVoicePermission = false
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

                        modeSelector
                            .padding(.horizontal, 26)
                            .padding(.top, 8)
                            .opacity(isVoiceInteractionLocked ? 0.22 : 1)
                            .allowsHitTesting(!isVoiceInteractionLocked && !isSaving)

                        if mode != .voice || attachmentDraft?.kind == .audio {
                            RitualDepositControl(
                                kind: kind,
                                isEnabled: canSave,
                                isWorking: isSaving,
                                instruction: depositInstruction,
                                onGestureBegan: { isFocused = false },
                                onCommit: save
                            )
                            .padding(.horizontal, 28)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                        } else {
                            Text("松手即保存")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.58))
                                .frame(height: 38)
                                .padding(.bottom, 10)
                        }
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
        .animation(.easeOut(duration: 0.16), value: mode)
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
            guard didRestoreDraft, mode != .voice else { return }
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
            isFocused = mode == .text
        }
        .onDisappear {
            draftSaveTask?.cancel()
            if !didSave, mode != .voice {
                draftRepository.saveText(text, spaceID: draftSpaceID, kind: kind)
            }
            recorder.discard()
            cleanupTemporaryDraft(attachmentDraft)
            for draft in imageDrafts { cleanupTemporaryDraft(draft) }
        }
        .interactiveDismissDisabled(isSaving || isPreparingVoicePermission || recorder.isRecording || recorder.isPreparing)
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
        switch mode {
        case .text:
            WhisperPaperEditor(
                kind: kind,
                text: $text,
                isFocused: $isFocused,
                maxLength: maxLength
            )
        case .photo:
            PhotoRitualEditor(
                kind: kind,
                text: $text,
                selectedMediaItems: $selectedMediaItems,
                drafts: imageDrafts,
                isLoading: isLoadingAttachment,
                isFocused: $isFocused,
                remove: removeImage
            )
        case .voice:
            if let draft = attachmentDraft, draft.kind == .audio {
                VoicePreparedView(kind: kind, draft: draft, discard: removeAttachment)
            } else {
                VoiceHoldRecorderView(
                    kind: kind,
                    recorder: recorder,
                    isDisabled: isSaving || isPreparingVoicePermission,
                    onRecorded: voiceRecorded,
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
                .frame(maxHeight: 440)
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(ComposeMode.allCases) { candidate in
                RitualModeToken(
                    systemImage: candidate.systemImage,
                    title: candidate.title,
                    isSelected: mode == candidate,
                    tint: kind.tint,
                    action: { selectMode(candidate) }
                )
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.38))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.70), lineWidth: 1) }
    }

    private var draftSpaceID: String {
        store.viewModel.data.relationship?.zoneName ?? "unassigned"
    }

    private var isVoiceInteractionLocked: Bool {
        mode == .voice && (isPreparingVoicePermission || recorder.isPreparing || recorder.isRecording)
    }

    private var canSave: Bool {
        guard !isSaving, !isLoadingAttachment, !recorder.isRecording, !recorder.isPreparing else {
            return false
        }
        switch mode {
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo:
            return !imageDrafts.isEmpty
        case .voice:
            return attachmentDraft?.kind == .audio
        }
    }

    private var depositInstruction: String {
        if mode == .voice, attachmentDraft?.kind == .audio {
            return "向上拖动重试"
        }
        if canSave { return "向上拖动放入" }
        switch mode {
        case .text: return "先写下内容"
        case .photo: return "先选择照片"
        case .voice: return "按住开始录音"
        }
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        let snapshot = draftRepository.snapshot(spaceID: draftSpaceID, kind: kind)
        text = snapshot.text
        attachmentDraft = snapshot.attachment
        if snapshot.attachment?.kind == .image {
            imageDrafts = snapshot.attachment.map { [$0] } ?? []
            attachmentDraft = nil
            mode = .photo
        } else if snapshot.attachment?.kind == .audio {
            mode = .voice
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

    private func selectMode(_ newMode: ComposeMode) {
        guard newMode != mode,
              !isSaving,
              !isPreparingVoicePermission,
              !recorder.isPreparing,
              !recorder.isRecording else { return }
        isFocused = false
        if newMode == .voice {
            draftSaveTask?.cancel()
            draftRepository.saveText(text, spaceID: draftSpaceID, kind: kind)
        }
        recorder.discard()
        removeAllAttachments()
        let previousMode = mode
        mode = newMode
        if newMode == .voice {
            text = ""
        } else if previousMode == .voice {
            text = draftRepository.text(spaceID: draftSpaceID, kind: kind)
        }

        if newMode == .text {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                isFocused = true
            }
        } else if newMode == .voice {
            isPreparingVoicePermission = true
            Task { @MainActor in
                let granted = await recorder.preparePermission()
                guard mode == .voice else {
                    isPreparingVoicePermission = false
                    return
                }
                isPreparingVoicePermission = false
                if !granted {
                    localNotice = LocalNotice(
                        title: "暂时听不见",
                        message: recorder.errorMessage ?? "请在系统设置中允许麦克风访问。"
                    )
                }
            }
        }
    }

    private func voiceRecorded(_ draft: AttachmentDraft) {
        guard replaceAttachment(with: draft) else { return }
        save()
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
        let drafts = mode == .photo ? imageDrafts : (attachmentDraft.map { [$0] } ?? [])
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
                    if mode == .photo {
                        imageDrafts = drafts
                    } else {
                        attachmentDraft = drafts.first
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard mode == .photo, !imageDrafts.isEmpty else { return }
                isFocused = true
            }
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

private struct PhotoRitualEditor: View {
    let kind: ContainerKind
    @Binding var text: String
    @Binding var selectedMediaItems: [PhotosPickerItem]
    let drafts: [AttachmentDraft]
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let remove: (Int) -> Void

    var body: some View {
        Group {
            if drafts.isEmpty {
                emptyPicker
            } else {
                selectedPhotos
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var emptyPicker: some View {
        photoPicker {
            VStack(spacing: 13) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(kind.tint)

                Text("选择照片")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Text("一次最多选择 9 张")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.58))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(kind.tint.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(kind.tint.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 7]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var selectedPhotos: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "pencil.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kind.tint.opacity(0.72))
                    .padding(.top, 3)

                TextField("继续写点什么…", text: $text, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1...3)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(kind.tint.opacity(0.16))
                    .frame(height: 1)
            }

            HStack(spacing: 12) {
                Text("\(drafts.count) 张照片")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.64))

                Spacer()

                if drafts.count < 9 {
                    photoPicker {
                        Label("添加照片", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(kind.tint)
                            .frame(height: 30)
                    }
                }
            }

            LazyVGrid(columns: gridColumns, alignment: .center, spacing: 8) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    PhotoDraftTile(
                        draft: draft,
                        index: index,
                        remove: remove
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var gridColumns: [GridItem] {
        let columnCount = min(3, max(1, drafts.count))
        let maximumWidth: CGFloat
        switch columnCount {
        case 1: maximumWidth = 236
        case 2: maximumWidth = 150
        default: maximumWidth = 96
        }
        return Array(
            repeating: GridItem(.flexible(minimum: 64, maximum: maximumWidth), spacing: 8),
            count: columnCount
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    RitualHaptics.selection()
                    remove(index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.46))
                        .clipShape(Circle())
                }
                .buttonStyle(SoftScaleButtonStyle())
                .padding(6)
                .accessibilityLabel("移除第 \(index + 1) 张照片")
            }
    }
}

private struct VoicePreparedView: View {
    let kind: ContainerKind
    let draft: AttachmentDraft
    let discard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                AppTheme.glow(for: kind)
                    .frame(width: 220, height: 180)
                RitualObjectGlyph(kind: kind, size: 104, filled: true)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 7) {
                Text("语音草稿已保留")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("\((draft.duration ?? 0).formattedDuration) · 向上拖动重试")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
            }

            Button {
                RitualHaptics.selection()
                discard()
            } label: {
                Text("删除并重录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.30))
                    .clipShape(Capsule())
            }
            .buttonStyle(SoftScaleButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: 420)
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
