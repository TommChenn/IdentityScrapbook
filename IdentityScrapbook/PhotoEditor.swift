import SwiftUI
import PhotosUI
import SwiftData

struct PhotoEditor: View {
    let bookID: UUID
    let voteID: UUID?
    let submissionID: UUID
    var onSaved: (UUID) -> Void
    var onPickerCancelled: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var pickerPresented = false
    @State private var started = false
    @State private var original: Data?
    @State private var preview: UIImage?
    @State private var caption = ""
    @State private var stickerOn = false
    @State private var stickerData: Data?
    @State private var stickerPreview: UIImage?
    @State private var processingSticker = false
    @State private var stickerFailure: StickerProcessor.ProcessingError?
    @State private var sourceRevision = UUID()
    @State private var retryRevision = 0

    private struct StickerRequest: Hashable {
        let enabled: Bool
        let source: UUID
        let retry: Int
    }
    @State private var loading = false
    @State private var saving = false
    @State private var discard = false
    @State private var errorMessage: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let preview {
                        Image(uiImage: stickerOn ? (stickerPreview ?? preview) : preview).resizable().scaledToFit()
                            .padding(12).background { ScrapbookPaper() }
                            .accessibilityLabel(Text("photo.preview"))
                    } else if loading {
                        ProgressView("photo.loading").frame(maxWidth: .infinity).padding(40)
                    } else {
                        ContentUnavailableView("photo.choose", systemImage: "photo")
                    }
                    Button("photo.choose") { pickerPresented = true }.disabled(loading || saving)
                    Toggle("sticker.toggle", isOn: $stickerOn)
                        .disabled(original == nil || loading || saving)
                    if processingSticker { ProgressView("sticker.processing") }
                    if stickerOn, let stickerFailure {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(stickerFailureMessage(stickerFailure)).font(.callout)
                            if stickerFailure.canRetry {
                                Button("common.retry") { retryRevision += 1 }
                            }
                            Button("sticker.usePhoto") { stickerOn = false }
                        }
                    }
                    TextField("photo.caption", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("photo.caption"))
                    if saving { ProgressView("photo.saving") }
                }.padding(24).disabled(saving)
            }
            .navigationTitle("photo.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        if original != nil || !caption.isEmpty || loading { discard = true } else { dismiss() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("note.save") { Task { await save() } }
                        .disabled(original == nil || preview == nil || loading || saving || (stickerOn && stickerData == nil))
                }
            }
            .photosPicker(isPresented: $pickerPresented, selection: $selection, matching: .images)
            .task {
                guard !started else { return }
                started = true
                pickerPresented = true
            }
            .task(id: selection) {
                guard let selection else { return }
                loading = true
                original = nil
                preview = nil
                stickerOn = false
                stickerData = nil
                stickerPreview = nil
                stickerFailure = nil
                processingSticker = false
                sourceRevision = UUID()
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw PhotoFiles.FileError.invalidImage
                    }
                    let small = try await Task.detached { try PhotoFiles.preview(data) }.value
                    try Task.checkCancellation()
                    guard let image = UIImage(data: small) else { throw PhotoFiles.FileError.invalidImage }
                    original = data
                    preview = image
                    loading = false
                } catch is CancellationError { return }
                catch { loading = false; errorMessage = "photo.loadError" }
            }
            .task(id: StickerRequest(enabled: stickerOn, source: sourceRevision, retry: retryRevision)) {
                guard stickerOn, let original else { processingSticker = false; return }
                guard stickerData == nil else { return }
                processingSticker = true
                stickerFailure = nil
                let worker = Task.detached(priority: .userInitiated) { try StickerProcessor.cutout(original) }
                do {
                    let data = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    guard let image = UIImage(data: data) else { throw PhotoFiles.FileError.invalidImage }
                    stickerData = data
                    stickerPreview = image
                    processingSticker = false
                } catch {
                    guard !Task.isCancelled else { return }
                    processingSticker = false
                    stickerFailure = (error as? StickerProcessor.ProcessingError) ?? .processingFailed
                }
            }
            .onChange(of: pickerPresented) { wasPresented, presented in
                if wasPresented && !presented && selection == nil && original == nil {
                    onPickerCancelled()
                    dismiss()
                }
            }
            .confirmationDialog("draft.discard.title", isPresented: $discard, titleVisibility: .visible) {
                Button("draft.discard", role: .destructive) { dismiss() }
                Button("draft.keep", role: .cancel) { }
            }
            .alert("photo.error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("common.ok", role: .cancel) { errorMessage = nil }
            } message: { if let errorMessage { Text(errorMessage) } }
        }
        .interactiveDismissDisabled(original != nil || !caption.isEmpty || loading || saving)
    }

    private func stickerFailureMessage(_ failure: StickerProcessor.ProcessingError) -> LocalizedStringKey {
        switch failure {
        case .simulatorUnavailable: "sticker.simulatorUnavailable"
        case .noSubject: "sticker.noSubject"
        case .encodingFailed: "sticker.encodingFailed"
        case .processingFailed: "sticker.failed"
        }
    }

    private func save() async {
        guard !saving, !loading, (!stickerOn || stickerData != nil), let original else { return }
        saving = true
        do {
            let id = try await PhotoStore.addPhoto(original, caption: caption, bookID: bookID,
                                                  voteID: voteID, submissionID: submissionID, in: context.container,
                                                  sticker: stickerOn ? stickerData : nil)
            onSaved(id)
            dismiss()
        } catch { saving = false; errorMessage = "save.error.description" }
    }
}

struct SavedPhoto: View {
    let entry: PhotoEntry
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Label("photo.missing", systemImage: "photo.badge.exclamationmark").padding() }
            else { ProgressView().padding(40) }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(CGFloat(entry.pixelWidth) / CGFloat(max(entry.pixelHeight, 1)), contentMode: .fit)
        .accessibilityLabel(Text("photo.preview"))
        .task(id: entry.id) {
            let previewURL = PhotoFiles.root.appendingPathComponent(entry.thumbnailKey)
            // Rebuild from the saved cutout, never from the original for a sticker.
            let sourceURL = PhotoFiles.root.appendingPathComponent(entry.stickerKey ?? entry.originalKey)
            let isSticker = entry.isSticker
            do {
                let data = try await Task.detached {
                    if let preview = try? Data(contentsOf: previewURL) { return preview }
                    let original = try Data(contentsOf: sourceURL)
                    let preview = try PhotoFiles.preview(original, preserveAlpha: isSticker)
                    try? preview.write(to: previewURL, options: .atomic)
                    return preview
                }.value
                image = UIImage(data: data)
                failed = image == nil
            } catch { failed = true }
        }
    }
}
