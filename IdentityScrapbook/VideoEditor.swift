import SwiftUI
import PhotosUI
import AVKit
import CoreTransferable
import SwiftData

nonisolated struct PickedVideo: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let bytes = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= VideoFiles.maxBytes else { throw VideoFiles.ImportError.tooLarge }
            let folder = URL.temporaryDirectory.appendingPathComponent("video-draft-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("video").appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            do { try FileManager.default.copyItem(at: received.file, to: target) }
            catch { try? FileManager.default.removeItem(at: folder); throw error }
            return PickedVideo(url: target)
        }
    }
}

struct VideoEditor: View {
    let bookID: UUID
    let voteID: UUID?
    let submissionID: UUID
    var onSaved: (UUID) -> Void
    var onPickerCancelled: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var picker = false
    @State private var started = false
    @State private var source: URL?
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var saving = false
    @State private var discard = false
    @State private var failure: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let player { VideoPlayer(player: player).frame(height: 300) }
                    else if loading { ProgressView("video.loading").padding(40) }
                    else { ContentUnavailableView("video.choose", systemImage: "video") }
                    Button("video.choose") { picker = true }.disabled(loading || saving)
                    Text("video.limits").font(.footnote).foregroundStyle(.secondary)
                    if saving { ProgressView("video.saving") }
                }.padding(24)
            }
            .navigationTitle("video.add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { if source != nil || loading { discard = true } else { dismiss() } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("note.save") { Task { await save() } }.disabled(source == nil || loading || saving)
                }
            }
            .photosPicker(isPresented: $picker, selection: $selection, matching: .videos)
            .task { if !started { started = true; picker = true } }
            .task(id: selection) { await loadSelection() }
            .onChange(of: picker) { old, new in
                if old && !new && selection == nil && source == nil { onPickerCancelled(); dismiss() }
            }
            .confirmationDialog("draft.discard.title", isPresented: $discard, titleVisibility: .visible) {
                Button("draft.discard", role: .destructive) { dismiss() }
                Button("draft.keep", role: .cancel) { }
            }
            .alert("video.error", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("common.ok", role: .cancel) { failure = nil }
            } message: { if let failure { Text(failure) } }
        }
        .interactiveDismissDisabled(source != nil || loading || saving)
        .onDisappear { cleanDraft() }
    }

    private func loadSelection() async {
        guard let selection else { return }
        loading = true
        cleanDraft()
        var imported: URL?
        do {
            guard let picked = try await selection.loadTransferable(type: PickedVideo.self) else { throw VideoFiles.ImportError.unsupported }
            imported = picked.url
            _ = try await VideoFiles.inspect(picked.url)
            try Task.checkCancellation()
            source = picked.url
            player = AVPlayer(url: picked.url)
            loading = false
        } catch {
            if let imported { try? FileManager.default.removeItem(at: imported.deletingLastPathComponent()) }
            guard !Task.isCancelled else { return }
            loading = false
            switch error {
            case VideoFiles.ImportError.tooLong, VideoFiles.ImportError.tooLarge: failure = "video.limits"
            default: failure = "video.loadError"
            }
        }
    }

    private func save() async {
        guard !saving, !loading, let source else { return }
        saving = true
        player?.pause()
        do {
            let id = try await VideoStore.add(source, bookID: bookID, voteID: voteID, submissionID: submissionID, in: context.container)
            onSaved(id)
            dismiss()
        } catch { saving = false; failure = "save.error.description" }
    }

    private func cleanDraft() {
        player?.pause(); player = nil
        if let source { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        source = nil
    }
}

struct VideoThumbnail: View {
    let entry: VideoEntry
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Label("video.missing", systemImage: "video.slash").padding() }
            else { ProgressView().padding(40) }
            if image != nil {
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                    .shadow(radius: 3).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(CGFloat(entry.pixelWidth) / CGFloat(max(entry.pixelHeight, 1)), contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            Text(Duration.seconds(entry.duration).formatted(.time(pattern: .minuteSecond)))
                .font(.caption.monospacedDigit()).padding(6).background(.black.opacity(0.7), in: Capsule())
                .foregroundStyle(.white).padding(8)
        }
        .accessibilityLabel(Text("video.memory"))
        .task(id: entry.id) {
            let url = VideoFiles.root.appendingPathComponent(entry.thumbnailKey)
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            image = data.flatMap(UIImage.init(data:))
            failed = image == nil
        }
    }
}

struct VideoDetail: View {
    let entry: VideoEntry
    @State private var playing = false
    @State private var missing = false
    var body: some View {
        VStack(spacing: 20) {
            VideoThumbnail(entry: entry)
            Button("video.play") {
                if FileManager.default.fileExists(atPath: VideoFiles.root.appendingPathComponent(entry.videoKey).path) { playing = true }
                else { missing = true }
            }.buttonStyle(.borderedProminent)
            if missing { Text("video.missing") }
        }
        .fullScreenCover(isPresented: $playing) {
            MoviePlayback(url: VideoFiles.root.appendingPathComponent(entry.videoKey))
        }
    }
}

private struct NativeMoviePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { }
}

private struct MoviePlayback: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        NativeMoviePlayer(player: player).ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("common.close") { dismiss() }.buttonStyle(.borderedProminent).padding()
            }
            .onAppear { player.play() }
            .onDisappear { player.pause() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player.pause() } }
    }
}
