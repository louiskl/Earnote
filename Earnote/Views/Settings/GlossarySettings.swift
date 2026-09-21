import EarnoteCore
import SwiftUI

/// Wörterbuch: Namen und Fachbegriffe, die oft falsch erkannt werden.
/// \(AppInfo.name) gibt sie der Spracherkennung und der KI mit – so entstehen die Fehler gar nicht erst.
struct GlossarySettings: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Form {
            Section {
                if library.glossary.isEmpty {
                    Text("Noch keine Begriffe. Trag Namen von Dozierenden, Fachbegriffe oder Abkürzungen ein, die \(AppInfo.name) falsch schreibt.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.glossary) { term in
                    GlossaryRow(term: term)
                }
            } header: {
                Text("Namen und Fachbegriffe")
            } footer: {
                Text("Die Begriffe gehen als Hinweis in die Spracherkennung und in die KI. „Oft falsch erkannt als“ hilft zusätzlich beim Korrigieren fertiger Notizen.")
            }
            Section {
                Button("Begriff hinzufügen") { library.addGlossaryTerm(GlossaryTerm(term: "")) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Eine Zeile: Begriff, bekannte Hörfehler und der Bereich, in dem er gilt.
private struct GlossaryRow: View {
    @Environment(LibraryStore.self) private var library
    let term: GlossaryTerm

    @State private var name = ""
    @State private var variants = ""
    @State private var categoryID: UUID?
    /// Erst nach dem Übernehmen der gespeicherten Werte darf zurückgeschrieben werden –
    /// sonst speichert schon das Füllen der Felder einen halb leeren Eintrag.
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Begriff", text: $name, prompt: Text("z. B. Professor Meyer"))
                Button {
                    library.deleteGlossaryTerm(term.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Begriff entfernen")
                .accessibilityLabel("Begriff „\(name)“ entfernen")
            }
            TextField("Oft falsch erkannt als", text: $variants, prompt: Text("Maier, Mayer – durch Komma getrennt"))
            Picker("Gilt für", selection: $categoryID) {
                Text("Alle Bereiche").tag(UUID?.none)
                ForEach(library.categories) { Text("\($0.displayEmoji)  \($0.name)").tag(Optional($0.id)) }
            }
        }
        .onAppear {
            name = term.term
            variants = term.variants.joined(separator: ", ")
            categoryID = term.categoryID
            loaded = true
        }
        .onChange(of: name) { _, _ in save() }
        .onChange(of: variants) { _, _ in save() }
        .onChange(of: categoryID) { _, _ in save() }
    }

    private func save() {
        guard loaded else { return }
        var updated = term
        updated.term = name.trimmingCharacters(in: .whitespaces)
        updated.variants = variants.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updated.categoryID = categoryID
        library.updateGlossaryTerm(updated)
    }
}
