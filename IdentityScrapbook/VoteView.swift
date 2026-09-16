import SwiftUI
import SwiftData

struct VoteView: View {
    let identity: Identity
    var onSaveMoment: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var receipt: VoteReceipt?
    @State private var submissions: [UUID: UUID] = [:]
    @State private var isSaving = false
    @State private var errorMessage: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let receipt {
                        confirmation(receipt)
                    } else {
                        Text("vote.choose").font(.title2.bold())
                        ForEach(identity.actions.sorted { $0.sortOrder < $1.sortOrder }) { action in
                            Button { cast(action) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(action.level == .minimum ? "action.minimum" : "action.normal")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(action.actionText).font(.headline)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding()
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("vote.action.hint"))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .disabled(isSaving)
            .navigationTitle(identity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }.disabled(isSaving)
                }
            }
            .alert("vote.error.title", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("common.ok", role: .cancel) { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    private func confirmation(_ receipt: VoteReceipt) -> some View {
        VStack(spacing: 20) {
            Label("vote.saved", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.green, lineWidth: 2))
                .rotationEffect(.degrees(reduceMotion ? 0 : -4))
                .accessibilityAddTraits(.isHeader)
            Text(receipt.identityName).font(.headline)
            Text(receipt.actionText).multilineTextAlignment(.center)
            Button("vote.saveMoment") { onSaveMoment(receipt.id) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("vote.done") { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("vote.undo", action: undo).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .transition(reduceMotion ? .identity : .scale(scale: 0.95).combined(with: .opacity))
    }

    private func cast(_ action: HabitAction) {
        guard !isSaving, receipt == nil else { return }
        isSaving = true
        defer { isSaving = false }
        let submission = submissions[action.id] ?? UUID()
        submissions[action.id] = submission
        do {
            let saved = try VoteStore.cast(identityID: identity.id, actionID: action.id,
                                           submissionID: submission, in: context.container)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { receipt = saved }
        } catch { errorMessage = "vote.error.save" }
    }

    private func undo() {
        guard !isSaving, let receipt else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try VoteStore.undo(id: receipt.id, in: context.container)
            self.receipt = nil
            submissions = [:]
        } catch { errorMessage = "vote.error.undo" }
    }
}
