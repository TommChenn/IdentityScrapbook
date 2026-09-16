import SwiftUI
import SwiftData

struct CreateIdentityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var minimum = ""
    @State private var normal = ""
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var showDiscardConfirmation = false

    private var canSave: Bool {
        [name, minimum, normal].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasDraft: Bool { !name.isEmpty || !minimum.isEmpty || !normal.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("identity.name") {
                    TextField("identity.name.example", text: $name, axis: .vertical)
                }
                Section {
                    TextField("action.minimum.example", text: $minimum, axis: .vertical)
                } header: {
                    Text("action.minimum")
                } footer: {
                    Text("action.minimum.help")
                }
                Section {
                    TextField("action.normal.example", text: $normal, axis: .vertical)
                } header: {
                    Text("action.normal")
                } footer: {
                    Text("action.normal.help")
                }
                Section {
                    Label("scrapbook.automatic", systemImage: "book.closed")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("identity.create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        if hasDraft { showDiscardConfirmation = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(!canSave || isSaving)
                }
            }
            .interactiveDismissDisabled(hasDraft || isSaving)
            .confirmationDialog("draft.discard.title", isPresented: $showDiscardConfirmation,
                                titleVisibility: .visible) {
                Button("draft.discard", role: .destructive) { dismiss() }
                Button("draft.keep", role: .cancel) { }
            }
            .alert("save.error.title", isPresented: $showSaveError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text("save.error.description")
            }
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        do {
            try IdentityStore.create(name: name, minimum: minimum, normal: normal,
                                     in: modelContext.container)
            dismiss()
        } catch {
            isSaving = false
            showSaveError = true
        }
    }
}
