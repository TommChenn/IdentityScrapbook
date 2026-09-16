//
//  IdentityScrapbookApp.swift
//  IdentityScrapbook
//
//  Created by Tom  on 2026/09/16.
//

import SwiftUI
import SwiftData

@main
struct IdentityScrapbookApp: App {
    var body: some Scene {
        WindowGroup {
            StorageRootView()
        }
    }
}

private struct StorageRootView: View {
    @State private var container: ModelContainer?
    @State private var failed = false

    var body: some View {
        Group {
            if let container {
                ContentView().modelContainer(container)
            } else if failed {
                ContentUnavailableView {
                    Label("storage.error.title", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("storage.error.description")
                } actions: {
                    Button("common.retry", action: load)
                }
            } else {
                ProgressView()
            }
        }
        .task { if container == nil && !failed { load() } }
    }

    private func load() {
        do {
            container = try IdentityStore.makeContainer()
            failed = false
        } catch {
            failed = true
        }
    }
}
