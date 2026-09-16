import SwiftUI
import SwiftData

struct BookRoute: Hashable {
    let bookID: UUID
    var voteID: UUID? = nil
}

private struct NoteDraft: Identifiable {
    let id = UUID()
    var voteID: UUID?
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 150))], spacing: 24) {
                    ForEach(books) { book in
                        NavigationLink(value: BookRoute(bookID: book.id)) {
                            VStack(alignment: .leading, spacing: 24) {
                                Image(systemName: "book.closed").font(.title)
                                Text(book.identity?.name ?? "").font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(.black)
                            .padding(24)
                            .frame(minHeight: 180)
                            .background(paperColor(book.coverStyleID == "peach" ? 1 : book.coverStyleID == "lavender" ? 2 : 0),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.1)).frame(width: 8) }
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(24)
            }
        }
        .navigationTitle("tab.scrapbooks")
    }
}

struct ScrapbookView: View {
    let route: BookRoute
    @Query private var books: [Scrapbook]
    @Query private var entries: [TextEntry]
    @State private var draft: NoteDraft?
    @State private var detail: TextEntry?
    @State private var handledInitialRoute = false
    @State private var addedID: UUID?
    @State private var showAdded = false

    init(route: BookRoute) {
        self.route = route
        let id = route.bookID
        _books = Query(filter: #Predicate<Scrapbook> { $0.id == id })
        _entries = Query(filter: #Predicate<TextEntry> { $0.scrapbookID == id }, sort: \TextEntry.sequence)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 28) {
                    if entries.isEmpty {
                        ContentUnavailableView("book.empty", systemImage: "note.text",
                                               description: Text("book.empty.help"))
                    }
                    ForEach(entries) { entry in
                        Button { detail = entry } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(entry.body).lineLimit(8).multilineTextAlignment(.leading)
                                Text("note.readMore").font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                            .foregroundStyle(.black)
                            .background(paperColor(entry.paperStyle))
                            .overlay(alignment: .top) {
                                Rectangle().fill(.brown.opacity(0.25)).frame(width: 64, height: 18).offset(y: -9)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, entry.sequence % 2 == 0 ? 0 : 16)
                        .padding(.trailing, entry.sequence % 2 == 0 ? 16 : 0)
                        .id(entry.id)
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: entries.count) { _, _ in
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
            Button { draft = NoteDraft() } label: {
                Image(systemName: "plus").font(.title2.bold()).padding(20)
            }
            .buttonStyle(.borderedProminent).clipShape(Circle()).padding(20)
            .accessibilityLabel(Text("note.add"))
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
            if let voteID = route.voteID { draft = NoteDraft(voteID: voteID) }
        }
        .fullScreenCover(item: $draft) { draft in
            TextEntryEditor(bookID: route.bookID, voteID: draft.voteID,
                            submissionID: draft.id, style: ((entries.last?.paperStyle ?? -1) + 1) % 3) {
                addedID = $0
            }
        }
        .sheet(item: $detail) { entry in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.addedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: entry.timeZoneID) ?? .gmt)))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(entry.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.padding(24)
                }
                .navigationTitle("note.detail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("common.close") { detail = nil } }
            }
            .presentationDetents([.medium, .large])
        }
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
