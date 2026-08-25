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
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var attachmentDraft: AttachmentDraft?
    @State private var isLoadingAttachment = false
    @State private var isSaving = false
    @State private var isPreparingVoicePermission = false
    @State private var localNotice: LocalNotice?
    @FocusState private var isFocused: Bool

    private let maxLength = 4_000

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        DepositTargetView(kind: kind, isActive: isSaving)
                            .frame(height: 78)
                            .padding(.top, 2)

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

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
                            .padding(.bottom, 6)
                        } else {
                            Text("语音松手后会直接放进去")
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
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: mode)
        .animation(.easeOut(duration: 0.22), value: localNotice?.id)
        .onChange(of: selectedMediaItem) { _, newValue in
            guard let newValue else { return }
            Task { await importPickerItem(newValue) }
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > maxLength {
                text = String(newValue.prefix(maxLength))
            }
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                isFocused = true
            }
        }
        .onDisappear {
            recorder.discard()
            cleanupTemporaryDraft(attachmentDraft)
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

            VStack(spacing: 3) {
                Text(kind.composeTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text(helperLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
                    .multilineTextAlignment(.center)
            }

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
                selectedMediaItem: $selectedMediaItem,
                draft: attachmentDraft,
                isLoading: isLoadingAttachment,
                remove: removeAttachment
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
                        localNotice = LocalNotice(title: "没有留下", message: "这段语音已经被揉掉了。")
                    },
                    onTooShort: {
                        localNotice = LocalNotice(title: "再多说一点点", message: "录音太短，没有放进容器。")
                    },
                    onError: { message in
                        localNotice = LocalNotice(title: "暂时听不见", message: message)
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
        .background(Color.white.opacity(0.24))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1) }
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
            return attachmentDraft?.kind == .image
        case .voice:
            return attachmentDraft?.kind == .audio
        }
    }

    private var helperLine: String {
        switch kind {
        case .star: return "把喜欢折得小一点"
        case .capsule: return "把想提醒的事轻轻封住"
        case .paper: return "先把感受从心里拿出来"
        }
    }

    private var depositInstruction: String {
        if mode == .voice, attachmentDraft?.kind == .audio {
            return "把保留下来的语音向上推，再试一次"
        }
        switch kind {
        case .star: return canSave ? "把星星向上推，放进瓶口" : "写下一点什么，星星才会成形"
        case .capsule: return canSave ? "把胶囊向上推，收进盒子" : "准备好内容，胶囊才会合上"
        case .paper: return canSave ? "把纸团向上推，先放在这里" : "说清感受，再把它揉起来"
        }
    }

    private func selectMode(_ newMode: ComposeMode) {
        guard newMode != mode,
              !isSaving,
              !isPreparingVoicePermission,
              !recorder.isPreparing,
              !recorder.isRecording else { return }
        isFocused = false
        recorder.discard()
        removeAttachment()
        mode = newMode

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
        replaceAttachment(with: draft)
        save()
    }

    private func interruptActiveRecording() {
        guard recorder.isRecording else { return }
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
        let draft = attachmentDraft
        attachmentDraft = nil

        Task {
            let success = await store.add(kind: kind, text: text, attachment: draft)
            await MainActor.run {
                if success {
                    RitualHaptics.success()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 520_000_000)
                        dismiss()
                    }
                } else {
                    attachmentDraft = draft
                    isSaving = false
                    RitualHaptics.warning()
                    localNotice = LocalNotice(
                        title: "还没有放进去",
                        message: "内容仍留在这里，可以稍后再试。"
                    )
                }
            }
        }
    }

    private func importPickerItem(_ item: PhotosPickerItem) async {
        isFocused = false
        isLoadingAttachment = true
        defer {
            isLoadingAttachment = false
            selectedMediaItem = nil
        }

        do {
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
            replaceAttachment(
                with: AttachmentDraft(
                    kind: .image,
                    url: url,
                    originalFilename: "照片.\(fileExtension)"
                )
            )
            RitualHaptics.selection()
        } catch {
            localNotice = LocalNotice(title: "这张照片没有拿进来", message: error.localizedDescription)
        }
    }

    private func replaceAttachment(with draft: AttachmentDraft) {
        cleanupTemporaryDraft(attachmentDraft)
        attachmentDraft = draft
    }

    private func removeAttachment() {
        cleanupTemporaryDraft(attachmentDraft)
        attachmentDraft = nil
    }

    private func cleanupTemporaryDraft(_ draft: AttachmentDraft?) {
        guard let draft else { return }
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if draft.url.standardizedFileURL.path.hasPrefix(temporaryDirectory) {
            try? FileManager.default.removeItem(at: draft.url)
        }
    }
}

private struct DepositTargetView: View {
    let kind: ContainerKind
    let isActive: Bool
    @State private var isGlowing = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(kind.tint.opacity(isActive ? 0.26 : 0.10))
                .frame(width: isActive ? 126 : 96, height: isActive ? 38 : 26)
                .blur(radius: isActive ? 11 : 7)

            Capsule()
                .stroke(kind.tint.opacity(isActive ? 0.60 : 0.26), lineWidth: 1.5)
                .frame(width: 84, height: 24)

            Image(systemName: isActive ? "sparkles" : "arrow.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(kind.tint.opacity(isActive ? 0.92 : 0.48))
        }
        .scaleEffect(isGlowing ? 1.04 : 0.96)
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isGlowing)
        .onAppear { isGlowing = true }
        .accessibilityHidden(true)
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
                PaperCreaseOverlay()
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
    @Binding var selectedMediaItem: PhotosPickerItem?
    let draft: AttachmentDraft?
    let isLoading: Bool
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.paper.opacity(0.94))
                    .shadow(color: Color.black.opacity(0.07), radius: 22, y: 12)

                if let draft,
                   draft.kind == .image,
                   let image = UIImage(contentsOfFile: draft.url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 310)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(12)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                RitualHaptics.selection()
                                remove()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.72))
                                    .frame(width: 38, height: 38)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(SoftScaleButtonStyle())
                            .padding(20)
                            .accessibilityLabel("移除照片")
                        }
                } else {
                    PhotosPicker(
                        selection: $selectedMediaItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 15) {
                            ZStack {
                                Circle()
                                    .fill(kind.tint.opacity(0.12))
                                    .frame(width: 86, height: 86)
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(kind.tint)
                            }
                            Text("从相册拿一张照片")
                                .font(.headline)
                                .foregroundStyle(AppTheme.primaryText)
                            Text("这里只选择照片；1.1 暂停新增视频写入")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SoftScaleButtonStyle())
                    .disabled(isLoading)
                }

                if isLoading {
                    ZStack {
                        Color.white.opacity(0.58)
                        ProgressView()
                            .tint(kind.tint)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .frame(minHeight: 250, maxHeight: 340)

            if draft?.kind == .image {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "pencil.line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kind.tint.opacity(0.72))
                        .padding(.top, 3)

                    TextField("写在相纸下面的一句话，也可以留白", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(kind.tint.opacity(0.16))
                        .frame(height: 1)
                }
            }
        }
        .padding(.vertical, 6)
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
                Text("语音还好好留在这里")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("录了 \((draft.duration ?? 0).formattedDuration)，向上推可以重新放入")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
            }

            Button {
                RitualHaptics.selection()
                discard()
            } label: {
                Text("不要这一段，重新录")
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
    @State private var travelsUp = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.22)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                RitualObjectGlyph(kind: kind, size: 88, filled: true)
                    .rotationEffect(.degrees(travelsUp ? 24 : -8))
                    .offset(y: travelsUp ? -56 : 28)
                    .scaleEffect(travelsUp ? 0.52 : 1)
                    .opacity(travelsUp ? 0.24 : 1)

                Text(savingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .animation(.easeInOut(duration: 0.52), value: travelsUp)
        .onAppear { travelsUp = true }
        .allowsHitTesting(true)
    }

    private var savingText: String {
        switch kind {
        case .star: return "星星落进瓶子里了"
        case .capsule: return "胶囊被轻轻收好了"
        case .paper: return "先把这份感受放下"
        }
    }
}

private struct PaperCreaseOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.height * 0.28))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 12, y: rect.height * 0.36),
            control1: CGPoint(x: rect.width * 0.30, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.46)
        )
        path.move(to: CGPoint(x: rect.width * 0.22, y: rect.minY + 8))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.32, y: rect.maxY - 10),
            control1: CGPoint(x: rect.width * 0.44, y: rect.height * 0.28),
            control2: CGPoint(x: rect.width * 0.12, y: rect.height * 0.70)
        )
        return path
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
