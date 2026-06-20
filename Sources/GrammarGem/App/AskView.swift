import SwiftUI

/// The "Ask" popover: type an instruction ("make it shorter", "translate to
/// German") that the local LLM applies to the current selection, in place.
struct AskView: View {
    @EnvironmentObject private var app: AppState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask GrammarGem")
                .font(.headline)
            Text("Acts on the text selected in the frontmost app. Runs on-device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("e.g. make it more formal", text: $app.askText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { Task { await app.runAsk() } }

            HStack {
                if !app.gate.entitlements.unlimitedAIActions {
                    Text("\(app.gate.remainingAIActionsToday) free actions left today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { app.showAskDismiss() }
                Button("Run") { Task { await app.runAsk() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.askText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { focused = true }
    }
}
