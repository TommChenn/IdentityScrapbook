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
    @State private var loading = false
    @State private var saving = false
    @State private var discard = false
    @State private var errorMessage: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit()
                            .accessibilityLabel(Text("photo.preview"))
                    } else if loading {
                        ProgressView("photo.loading").frame(maxWidth: .infinity).padding(40)
                    } else {
                        ContentUnavailableView("photo.choose", systemImage: "photo")
                    }
                    Button("photo.choose") { pickerPresented = true }.disabled(loading || saving)
                    TextField("photo.caption", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("photo.caption"))
                    if saving { ProgressView("photo.saving") }
                }.padding(24)
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
                        .disabled(original == nil || preview == nil || loading || saving)
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

    private func save() async {
        guard !saving, !loading, let original else { return }
        saving = true
        do {
            let id = try await PhotoStore.addPhoto(original, caption: caption, bookID: bookID,
                                                  voteID: voteID, submissionID: submissionID, in: context.container)
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
            let originalURL = PhotoFiles.root.appendingPathComponent(entry.originalKey)
            do {
                let data = try await Task.detached {
                    if let preview = try? Data(contentsOf: previewURL) { return preview }
                    let original = try Data(contentsOf: originalURL)
                    let preview = try PhotoFiles.preview(original)
                    try? preview.write(to: previewURL, options: .atomic)
                    return preview
                }.value
                image = UIImage(data: data)
                failed = image == nil
            } catch { failed = true }
        }
    }
}
