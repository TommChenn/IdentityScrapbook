//
//  ContentView.swift
//  IdentityScrapbook
//
//  Created by Tom  on 2026/09/16.
//

import SwiftUI
import SwiftData

struct VoteHomeView: View {
    var onSaveMoment: (UUID, UUID) -> Void
    @State private var pendingMoment: (UUID, UUID)?
    @Query(sort: \Identity.createdAt) private var identities: [Identity]
    @State private var showingCreation = false
    @State private var selectedIdentity: Identity?

    var body: some View {
        NavigationStack {
            Group {
                if identities.isEmpty {
                    ContentUnavailableView {
                        Label("identity.empty.title", systemImage: "leaf")
                    } description: {
                        Text("identity.empty.description")
                    } actions: {
                        Button("identity.create") { showingCreation = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(identities) { identity in
                        Button { selectedIdentity = identity } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(identity.name).font(.title3.bold())
                            ForEach(identity.actions.sorted { $0.sortOrder < $1.sortOrder }) { action in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.level == .minimum ? "action.minimum" : "action.normal")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(action.actionText)
                                }
                            }
                            if identity.scrapbook != nil {
                                Label("scrapbook.ready", systemImage: "book.closed")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("vote.identity.hint"))
                    }
                }
            }
            .navigationTitle("identity.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("identity.create", systemImage: "plus") { showingCreation = true }
                }
            }
            .sheet(isPresented: $showingCreation) { CreateIdentityView() }
            .sheet(item: $selectedIdentity, onDismiss: {
                if let pendingMoment {
                    self.pendingMoment = nil
                    onSaveMoment(pendingMoment.0, pendingMoment.1)
                }
            }) { identity in
                VoteView(identity: identity) { voteID in
                    guard let book = identity.scrapbook else { return }
                    pendingMoment = (book.id, voteID)
                    selectedIdentity = nil
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var tab = 0
    @State private var bookPath: [BookRoute] = []

    var body: some View {
        TabView(selection: $tab) {
            VoteHomeView { bookID, voteID in
                bookPath = [BookRoute(bookID: bookID, voteID: voteID)]
                tab = 1
            }
            .tabItem { Label("tab.vote", systemImage: "checkmark.seal") }.tag(0)
            NavigationStack(path: $bookPath) {
                ScrapbookShelfView()
                    .navigationDestination(for: BookRoute.self) { route in
                        ScrapbookView(route: route).id(route)
                    }
            }
            .tabItem { Label("tab.scrapbooks", systemImage: "books.vertical") }.tag(1)
        }
    }
}

#Preview {
    ContentView().modelContainer(try! IdentityStore.makeContainer(inMemory: true))
}
