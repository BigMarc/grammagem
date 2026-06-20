import SwiftUI

// MARK: - Dictionary

struct DictionaryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var gate: FeatureGate
    @EnvironmentObject private var dictionary: PersonalDictionary
    @State private var newWord = ""
    @State private var message: String?

    var body: some View {
        DetailScaffold(
            title: "Personal Dictionary",
            subtitle: "Words GrammarGem should never “correct” — names, brands, jargon."
        ) {
            Card {
                HStack {
                    TextField("Add a word…", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message {
                    Label(message, systemImage: "lock").font(.caption).foregroundStyle(.orange)
                }
                let cap = gate.entitlements.dictionaryCap
                Text(cap == Int.max
                     ? "\(dictionary.entries.count) entries · unlimited"
                     : "\(dictionary.entries.count) / \(cap) entries")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Card {
                if dictionary.entries.isEmpty {
                    Text("No entries yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(dictionary.entries, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(role: .destructive) { app.removeDictionaryEntry(word) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                        if word != dictionary.entries.last { Divider() }
                    }
                }
            }
        }
    }

    private func add() {
        switch app.addDictionaryEntry(newWord) {
        case .allowed: newWord = ""; message = nil
        case .denied(let m): message = m
        }
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var gate: FeatureGate
    @EnvironmentObject private var snippets: SnippetStore
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        DetailScaffold(
            title: "Snippets",
            subtitle: "Type a short trigger, expand it into anything. Stored only on this Mac."
        ) {
            if gate.snippetsEnabled {
                Card {
                    HStack(alignment: .top) {
                        TextField("Trigger (e.g. ;addr)", text: $trigger).textFieldStyle(.roundedBorder).frame(width: 160)
                        TextField("Expansion…", text: $expansion, axis: .vertical)
                            .lineLimit(1...4).textFieldStyle(.roundedBorder)
                        Button("Add") {
                            snippets.add(trigger: trigger, expansion: expansion)
                            trigger = ""; expansion = ""
                        }
                        .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty
                                  || expansion.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Card {
                    if snippets.snippets.isEmpty {
                        Text("No snippets yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(snippets.snippets) { s in
                            HStack(alignment: .top) {
                                Text(s.trigger).font(.callout.monospaced()).foregroundStyle(GG.emerald)
                                Text(s.expansion).foregroundStyle(.secondary).lineLimit(2)
                                Spacer()
                                Button(role: .destructive) { snippets.remove(s) } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                            if s.id != snippets.snippets.last?.id { Divider() }
                        }
                    }
                }
            } else {
                Card {
                    HStack { Text("Text expansion").font(.headline); UpgradeBadge() }
                    Text("Snippets are part of the lifetime license. Save your common replies, addresses, and boilerplate, and expand them with a keystroke anywhere.")
                        .foregroundStyle(.secondary)
                    Button("Unlock snippets") { app.showMainWindow(select: .license) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
