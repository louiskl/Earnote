import EarnoteCore
import SwiftUI

/// Übersetzen (Earnote Pro): Notiz oder ganzes Transkript in eine andere Sprache. Das Ergebnis lässt sich teilen;
/// eine übersetzte Notiz kann die bisherige ersetzen („Auf KI-Fassung zurücksetzen“ holt das Original zurück).
struct TranslationSheet: View {
    let id: UUID
    let note: Summary
    let transcript: Transcript?
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var what = What.note
    @State private var language = ""
    @State private var result: String?
    @State private var progress: Double?
    @State private var error: String?
    @State private var showsPro = false
    @State private var detent = PresentationDetent.medium
    @State private var task: Task<Void, Never>?

    enum What: Hashable { case note, transcript }

    var body: some View {
        NavigationStack {
            Form {
                // Eigener Abschnitt ohne Hintergrund – in der Sprach-Gruppe hinterließ er eine leere weiße Leiste
                if transcript != nil {
                    Section {
                        Picker("Was", selection: $what) {
                            Text("Notiz").tag(What.note)
                            Text("Transkript").tag(What.transcript)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    Picker("Sprache", selection: $language) {
                        ForEach(Translation.languages, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                    Button {
                        start()
                    } label: {
                        if let progress {
                            ProgressView(value: progress) { Text("Wird übersetzt …") }
                        } else {
                            Label("Übersetzen", systemImage: "character.bubble")
                        }
                    }
                    .disabled(progress != nil)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if what == .transcript {
                            Text("Ein langes Transkript übersetzt die KI Stück für Stück – mit lokaler KI kann das einige Minuten dauern.")
                        }
                        ProTriesNote(feature: .translate)
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                if let result {
                    Section {
                        NoteContentView(markdown: result) { _ in }
                            .textSelection(.enabled)
                    } header: {
                        Text("Übersetzung")
                    }
                }
            }
            .navigationTitle("Übersetzen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { task?.cancel(); dismiss() } }
                if let result {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ShareLink(item: result) { Label("Teilen", systemImage: "square.and.arrow.up") }
                        if what == .note {
                            Button("Als Notiz übernehmen", systemImage: "doc.on.doc") {
                                library.updateSummaryText(id, markdown: result)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .onChange(of: what) { result = nil }
            .onChange(of: language) { result = nil }
            .onAppear {
                // Meist will man in die andere Sprache: deutsche Notizen nach Englisch, alles andere nach Deutsch
                if language.isEmpty { language = library.settings.ai.summaryLanguage == "Deutsch" ? "Englisch" : "Deutsch" }
            }
            .sheet(isPresented: $showsPro) { ProSheet(highlight: .translate) }
        }
        // Erst halb hoch (drei Zeilen), mit dem Ergebnis ganz – dann muss niemand selbst ziehen
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: result) { if result != nil { detent = .large } }
    }

    private func start() {
        guard Pro.use(.translate) else { showsPro = true; return }
        let client: any LLMClient
        do {
            guard let made = try library.llm.make(library.settings.ai) else {
                error = String(localized: "Zum Übersetzen braucht es eine KI auf diesem Gerät. Wähle sie in den Einstellungen unter „So entsteht die Notiz“.")
                return
            }
            client = made
        } catch {
            self.error = error.localizedDescription
            return
        }
        error = nil
        result = nil
        progress = 0
        let what = what, language = language, note = note, transcript = transcript
        task = Task {
            defer { progress = nil }
            let report: @Sendable (Double) -> Void = { value in Task { @MainActor in progress = value } }
            do {
                switch what {
                case .note:
                    result = try await Translation.note(note.markdown, to: language, client: client, progress: report)
                case .transcript:
                    guard let transcript else { return }
                    result = try await Translation.transcript(transcript, to: language, client: client, progress: report)
                        .joined(separator: "\n\n")
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
