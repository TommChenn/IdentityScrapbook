import SwiftUI
import SwiftData

struct BookRoute: Hashable {
    let bookID: UUID
    var voteID: UUID? = nil
}

private enum MemoryFormat { case text, photo, video, audio }

private struct NoteDraft: Identifiable {
    let id = UUID()
    var voteID: UUID?
    var format: MemoryFormat = .text
}

private enum BookItem: Identifiable {
    case text(TextEntry), photo(PhotoEntry), video(VideoEntry), audio(AudioEntry)
    var id: UUID { switch self { case .text(let e): e.id; case .photo(let e): e.id; case .video(let e): e.id; case .audio(let e): e.id } }
    var sequence: Int { switch self { case .text(let e): e.sequence; case .photo(let e): e.sequence; case .video(let e): e.sequence; case .audio(let e): e.sequence } }
    var date: Date { switch self { case .text(let e): e.addedAt; case .photo(let e): e.addedAt; case .video(let e): e.addedAt; case .audio(let e): e.addedAt } }
    var isSticker: Bool { if case .photo(let photo) = self { return photo.isSticker }; return false }
    var timeZone: String { switch self { case .text(let e): e.timeZoneID; case .photo(let e): e.timeZoneID; case .video(let e): e.timeZoneID; case .audio(let e): e.timeZoneID } }
}

func paperColor(_ style: Int) -> Color {
    [Color(red: 0.94, green: 0.96, blue: 0.79),
     Color(red: 1, green: 0.88, blue: 0.82),
     Color(red: 0.88, green: 0.86, blue: 0.97)][abs(style % 3)]
}

struct ScrapbookShelfView: View {
    @Query(sort: \Scrapbook.createdAt) private var books: [Scrapbook]
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ScrollView {
            if books.isEmpty {
                ContentUnavailableView("book.emptyShelf", systemImage: "books.vertical",
                                       description: Text("book.emptyShelf.help"))
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    Text("shelf.introduction")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: textSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 32) {
                        ForEach(books) { book in
                            NavigationLink(value: BookRoute(bookID: book.id)) {
                                ScrapbookCover(name: book.identity?.name ?? "", style: book.coverStyleID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .background { ScrapbookPaper() }
        .navigationTitle("tab.scrapbooks")
    }
}

struct ScrapbookView: View {
    let route: BookRoute
    @Environment(\.dynamicTypeSize) private var textSize
    @Query private var books: [Scrapbook]
    @Query private var entries: [TextEntry]
    @State private var draft: NoteDraft?
    @Query private var photos: [PhotoEntry]
    @Query private var videos: [VideoEntry]
    @Query private var audio: [AudioEntry]
    @State private var detail: BookItem?
    @State private var choosingFormat = false
    @State private var pendingVoteID: UUID?
    @State private var reopenChooser = false

    private var items: [BookItem] {
        (entries.map(BookItem.text) + photos.map(BookItem.photo) + videos.map(BookItem.video) + audio.map(BookItem.audio)).sorted { $0.sequence < $1.sequence }
    }
    @State private var handledInitialRoute = false
    @State private var addedID: UUID?
    @State private var showAdded = false

    init(route: BookRoute) {
        self.route = route
        let id = route.bookID
        _books = Query(filter: #Predicate<Scrapbook> { $0.id == id })
        _entries = Query(filter: #Predicate<TextEntry> { $0.scrapbookID == id }, sort: \TextEntry.sequence)
        _photos = Query(filter: #Predicate<PhotoEntry> { $0.scrapbookID == id }, sort: \PhotoEntry.sequence)
        _videos = Query(filter: #Predicate<VideoEntry> { $0.scrapbookID == id }, sort: \VideoEntry.sequence)
        _audio = Query(filter: #Predicate<AudioEntry> { $0.scrapbookID == id }, sort: \AudioEntry.sequence)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 36) {
                    if items.isEmpty {
                        ContentUnavailableView("book.empty", systemImage: "note.text",
                                               description: Text("book.empty.help"))
                    }
                    ForEach(items) { entry in
                        Button { detail = entry } label: {
                            Group {
                                switch entry {
                                case .text(let note):
                                    MemoryPaper(color: paperColor(note.paperStyle)) {
                                        VStack(alignment: .leading, spacing: 18) {
                                            Text(note.body).font(.body).lineSpacing(5)
                                                .lineLimit(textSize.isAccessibilitySize ? 5 : 8)
                                                .multilineTextAlignment(.leading)
                                            HStack(alignment: .firstTextBaseline) {
                                                Image(systemName: "text.alignleft")
                                                Text("note.readMore")
                                            }
                                            .font(.caption).foregroundStyle(ScrapbookStyle.ink.opacity(0.75))
                                        }
                                    }
                                case .audio(let audio):
                                    AudioCard(entry: audio)
                                case .video(let video):
                                    VideoThumbnail(entry: video).padding(10).background(.white)
                                case .photo(let photo):
                                    VStack(alignment: .leading, spacing: 12) {
                                        if photo.isSticker {
                                            SavedPhoto(entry: photo)
                                                .shadow(color: .black.opacity(0.12), radius: 2, x: 1, y: 2)
                                        } else {
                                            SavedPhoto(entry: photo).padding(10).padding(.bottom, 14)
                                                .background(.white, in: RoundedRectangle(cornerRadius: 2))
                                                .shadow(color: .black.opacity(0.12), radius: 4, x: 1, y: 4)
                                        }
                                        if !photo.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Label {
                                                Text(photo.caption).lineLimit(4).multilineTextAlignment(.leading)
                                            } icon: { Image(systemName: "arrow.turn.left.up") }
                                            .font(.callout).lineSpacing(3)
                                            .padding(14)
                                            .foregroundStyle(ScrapbookStyle.ink)
                                            .background(ScrapbookStyle.paper, in: RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                            }
                            .overlay(alignment: .top) {
                                if !entry.isSticker {
                                    ScrapbookTape(angle: entry.sequence % 2 == 0 ? -5 : 4).offset(y: -11)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, textSize.isAccessibilitySize ? 0 : (entry.sequence % 2 == 0 ? 0 : 28))
                        .padding(.trailing, textSize.isAccessibilitySize ? 0 : (entry.sequence % 2 == 0 ? 28 : 0))
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 32)
                .padding(.bottom, 100)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background { ScrapbookPaper() }
            .onChange(of: items.count) { _, _ in
                if let addedID { proxy.scrollTo(addedID, anchor: .bottom) }
            }
            .onChange(of: addedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .navigationTitle(books.first?.identity?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            Button { pendingVoteID = nil; choosingFormat.toggle() } label: {
                Image(systemName: "plus").font(.title2.bold())
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.white)
                    .background(ScrapbookStyle.accent, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .buttonStyle(.plain).padding(20)
            .accessibilityLabel(Text("memory.add"))
            .disabled(books.isEmpty)
        }
        .overlay(alignment: .top) {
            if showAdded { Text("note.added").padding().background(.regularMaterial, in: Capsule()) }
        }
        .task(id: addedID) {
            guard addedID != nil else { return }
            showAdded = true
            try? await Task.sleep(for: .seconds(2))
            showAdded = false
        }
        .task {
            guard !handledInitialRoute else { return }
            handledInitialRoute = true
            if let voteID = route.voteID { pendingVoteID = voteID; choosingFormat = true }
        }
        .overlay(alignment: .bottomTrailing) {
            if choosingFormat {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.05).ignoresSafeArea()
                        .onTapGesture { choosingFormat = false; pendingVoteID = nil }
                    VStack(alignment: .leading, spacing: 8) {
                        Button { choose(.photo) } label: { Label("photo.add", systemImage: "photo") }
                        Button { choose(.text) } label: { Label("note.add", systemImage: "note.text") }
                        Button { choose(.video) } label: { Label("video.add", systemImage: "video") }
                        Button { choose(.audio) } label: { Label("audio.add", systemImage: "mic") }
                        Button("common.cancel") { choosingFormat = false; pendingVoteID = nil }
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.trailing, 20).padding(.bottom, 100)
                }
            }
        }
        .fullScreenCover(item: $draft, onDismiss: {
            if reopenChooser { reopenChooser = false; choosingFormat = true }
        }) { draft in
            if draft.format == .audio {
                AudioEditor(bookID: route.bookID, voteID: draft.voteID, submissionID: draft.id) { addedID = $0 }
            } else if draft.format == .video {
                VideoEditor(bookID: route.bookID, voteID: draft.voteID, submissionID: draft.id) {
                    addedID = $0
                } onPickerCancelled: {
                    pendingVoteID = draft.voteID
                    reopenChooser = true
                }
            } else if draft.format == .photo {
                PhotoEditor(bookID: route.bookID, voteID: draft.voteID, submissionID: draft.id) {
                    addedID = $0
                } onPickerCancelled: {
                    pendingVoteID = draft.voteID
                    reopenChooser = true
                }
            } else {
                TextEntryEditor(bookID: route.bookID, voteID: draft.voteID,
                                submissionID: draft.id, style: ((entries.last?.paperStyle ?? -1) + 1) % 3) {
                    addedID = $0
                }
            }
        }
        .sheet(item: $detail) { entry in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: entry.timeZone) ?? .gmt)))
                            .font(.subheadline).foregroundStyle(.secondary)
                        switch entry {
                        case .text(let note):
                            Text(note.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        case .audio(let audio):
                            AudioDetail(entry: audio)
                        case .video(let video):
                            VideoDetail(entry: video)
                        case .photo(let photo):
                            SavedPhoto(entry: photo)
                            Text(photo.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    }.padding(24)
                }
                .navigationTitle("note.detail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("common.close") { detail = nil } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func choose(_ format: MemoryFormat) {
        let voteID = pendingVoteID
        pendingVoteID = nil
        choosingFormat = false
        draft = NoteDraft(voteID: voteID, format: format)
    }

}

struct TextEntryEditor: View {
    let bookID: UUID
    let voteID: UUID?
    let submissionID: UUID
    let style: Int
    var onSaved: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var discard = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(20).foregroundStyle(.black).background(paperColor(style))
                .accessibilityLabel(Text("note.body"))
                .navigationTitle("note.add")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { if text.isEmpty { dismiss() } else { discard = true } }
                            .disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("note.save", action: save)
                            .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .confirmationDialog("draft.discard.title", isPresented: $discard, titleVisibility: .visible) {
                    Button("draft.discard", role: .destructive) { dismiss() }
                    Button("draft.keep", role: .cancel) { }
                }
                .alert("save.error.title", isPresented: $failed) {
                    Button("common.ok", role: .cancel) { }
                } message: { Text("save.error.description") }
        }
        .interactiveDismissDisabled(!text.isEmpty || saving)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        do {
            let id = try EntryStore.addText(text, bookID: bookID, voteID: voteID,
                                           submissionID: submissionID, in: context.container)
            onSaved(id)
            dismiss()
        } catch { saving = false; failed = true }
    }
}
