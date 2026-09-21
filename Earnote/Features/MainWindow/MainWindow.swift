import EarnoteCore
import EarnoteML
import SwiftData
import SwiftUI

/// Hauptfenster: Seitenleiste | Aufnahmeliste | Detail, dazu der Inspector.
/// Das Gerüst bleibt immer gleich; nur der Inhalt der Spalten wechselt. Auswahl und Ansicht gehören dem Fenster.
struct MainWindow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @SceneStorage("sidebarFilter") private var filterRaw = LibraryFilter.all.rawValue
    @SceneStorage("selectedRecording") private var selectedRaw = ""
    @SceneStorage("detailMode") private var detailModeRaw = DetailMode.note.rawValue
    @SceneStorage("inspectorShown") private var inspectorShown = true

    @State private var searchText = ""
    @State private var searchResults: Set<UUID>?
    @State private var renamingRecordingID: UUID?
    @State private var renamingCategoryID: UUID?
    @State private var editingCategory: RecordingCategory?
    /// Bereich, für den gerade eine Übersicht erstellt wird (Blatt)
    @State private var summarizingCategoryID: UUID?
    @State private var pendingDeletion: UUID?
    @State private var confirmDiscard = false
    @State private var showOnboarding = false
    /// Anfrage „Notiz dieser Aufnahme bearbeiten“. Die Notizansicht nimmt sie entgegen und setzt sie zurück;
    /// so bleibt der Bearbeiten-Zustand dort, wo der Editor steht, und nie bei einer anderen Aufnahme.
    @State private var noteEditRequest: UUID?
    /// Abspielen der gewählten Aufnahme – gehört dem Fenster
    @State private var player = AudioPlayer()
    /// Fundstellen der laufenden Suche – gezählt von der Ansicht, weitergeblättert über ⌘G
    @State private var searchCursor = SearchCursor()
    @State private var noteSheet: NoteSheet?
    @FocusState private var searchFocused: Bool

    private var filter: Binding<LibraryFilter> {
        Binding(get: { LibraryFilter(rawValue: filterRaw) ?? .all }, set: { filterRaw = $0.rawValue })
    }

    private var selection: Binding<UUID?> {
        Binding(get: { UUID(uuidString: selectedRaw) }, set: { selectedRaw = $0?.uuidString ?? "" })
    }

    private var detailMode: Binding<DetailMode> {
        Binding(get: { DetailMode(rawValue: detailModeRaw) ?? .note }, set: { detailModeRaw = $0.rawValue })
    }

    private var selectedCategoryID: UUID? {
        if case .category(let id) = filter.wrappedValue { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(filter: filter, renamingCategoryID: $renamingCategoryID,
                        onEdit: { id in editingCategory = library.category(id) },
                        onNewCategory: newCategory,
                        onSummarize: { summarizingCategoryID = $0 })
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            RecordingListView(filter: filter.wrappedValue, selection: selection, searchResults: searchResults,
                              searchText: searchText, renamingID: $renamingRecordingID,
                              onDelete: { pendingDeletion = $0 })
                .navigationSplitViewColumnWidth(min: 260, ideal: 330, max: 520)
        } detail: {
            RecordingDetailView(recordingID: selection.wrappedValue, mode: detailMode.wrappedValue,
                                editRequest: noteEditRequest,
                                onEditStarted: { noteEditRequest = nil },
                                searchText: searchResults == nil ? "" : searchText,
                                searchCursor: searchCursor)
                .safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar() }
        }
        // Farbe kommt aus dem gewählten Bereich: Auswahl, Haken und Knöpfe übernehmen sie.
        .tint(windowTint)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: activeCategory?.id)
        .inspector(isPresented: $inspectorShown) {
            RecordingInspector(recordingID: selection.wrappedValue)
                .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
        }
        .toolbar {
            MainToolbar(selectedRecordingID: selection.wrappedValue, selectedCategoryID: selectedCategoryID,
                        detailMode: detailMode, inspectorShown: $inspectorShown,
                        onDelete: { if let id = selection.wrappedValue { pendingDeletion = id } })
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Titel, Notizen, Transkripte")
        .searchFocused($searchFocused)
        .task(id: searchText) { await runSearch() }
        .confirmationDialog(deletionTitle, isPresented: isDeletionPending) {
            Button("Löschen", role: .destructive) {
                if let id = pendingDeletion {
                    if selection.wrappedValue == id { selection.wrappedValue = nil }
                    library.delete(id)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Audio, Transkript und Notiz werden entfernt. Das lässt sich nicht rückgängig machen.")
        }
        .confirmationDialog("Aufnahme verwerfen?", isPresented: $confirmDiscard) {
            Button("Verwerfen", role: .destructive) { recorder.cancelRecording() }
        } message: {
            Text("Die laufende Aufnahme wird beendet und nicht gespeichert.")
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(category: category) { editingCategory = nil }
        }
        .sheet(item: Binding(get: { summarizingCategoryID.map(IdentifiableID.init) },
                             set: { summarizingCategoryID = $0?.id })) { wrapped in
            CategorySummarySheet(categoryID: wrapped.id) { newID in
                selection.wrappedValue = newID
                detailMode.wrappedValue = .note
            }
        }
        .sheet(item: $noteSheet) { sheet in
            if let id = selection.wrappedValue {
                switch sheet {
                case .summarizeAgain: SummarizeAgainSheet(recordingID: id)
                case .correctTerms: CorrectTermSheet(recordingID: id)
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .interactiveDismissDisabled()
        }
        .alert("Hinweis", isPresented: hintShown) {
            Button("OK") { recorder.lastError = nil; library.lastError = nil }
        } message: {
            Text(recorder.lastError ?? library.lastError ?? "")
        }
        .onAppear {
            if !library.settings.onboardingCompleted { showOnboarding = true }
            #if DEBUG
            demoSelectionIfRequested()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
        .onChange(of: library.categories.map(\.id)) { _, ids in
            // Gelöschter Bereich war ausgewählt → zurück zu „Alle Aufnahmen“
            if let id = selectedCategoryID, !ids.contains(id) { filter.wrappedValue = .all }
        }
        .environment(\.categoryTint, windowTint)
        .environment(\.noteActions, noteActions)
        .environment(player)
        // Andere Aufnahme gewählt: den Ton der vorherigen nicht weiterlaufen lassen
        .onChange(of: selection.wrappedValue, initial: true) { _, id in loadAudio(id) }
        // Beim Start steht die Auswahl aus dem Fensterzustand schon fest, die Bibliothek ist aber noch
        // nicht geladen – dann gäbe es ohne diesen zweiten Versuch nie einen Player.
        .onChange(of: library.isLoaded) { _, _ in loadAudio(selection.wrappedValue) }
        .onChange(of: recorder.activeRecordingID) { _, active in if active != nil { player.stop() } }
        // Das Transkript zeigt keinen Editor; die Notiz einer anderen Aufnahme auch nicht (Vergleich über die ID)
        .onChange(of: detailMode.wrappedValue) { _, mode in
            if !mode.showsNote { noteEditRequest = nil }
            // Ohne sichtbares Transkript gibt es nichts zu blättern (⌘G bliebe sonst im Menü aktiv)
            if !mode.showsTranscript { searchCursor.reset(count: 0) }
        }
        .focusedSceneValue(\.mainWindow, context)
        // Mit Inspector brauchen vier Spalten mehr Platz; ohne ihn darf das Fenster kleiner werden.
        .frame(minWidth: inspectorShown ? 1100 : 840, minHeight: 560)
    }

    /// Bereich der Seitenleiste – oder der Bereich der gewählten Aufnahme
    private var activeCategory: RecordingCategory? {
        if let id = selectedCategoryID { return library.category(id) }
        guard let recordingID = selection.wrappedValue else { return nil }
        return library.category(library.recording(recordingID)?.categoryID)
    }

    private var windowTint: Color {
        activeCategory?.tint ?? .accentColor
    }

    private var context: MainWindowContext {
        MainWindowContext(selectedRecordingID: selection.wrappedValue, selectedCategoryID: selectedCategoryID,
                          detailMode: detailMode, inspectorShown: $inspectorShown,
                          isEditingText: searchFocused || renamingRecordingID != nil || renamingCategoryID != nil,
                          isRecording: recorder.isRecording, isPaused: recorder.isPaused,
                          activeRecordingID: recorder.activeRecordingID,
                          requestDelete: { if let id = selection.wrappedValue { pendingDeletion = id } },
                          requestDiscardRecording: { confirmDiscard = true },
                          newCategory: newCategory,
                          focusSearch: { searchFocused = true },
                          noteActions: noteActions,
                          playback: player.hasAudio
                              ? PlaybackCommands(isPlaying: player.isPlaying,
                                                 playPause: { player.playPause() },
                                                 skip: { player.skip($0) })
                              : nil,
                          search: searchCursor.count > 0
                              ? SearchNavigation(next: { searchCursor.next() },
                                                 previous: { searchCursor.previous() })
                              : nil)
    }

    private var noteActions: NoteActions {
        NoteActions(edit: { id in
                        selection.wrappedValue = id
                        detailMode.wrappedValue = .note
                        noteEditRequest = id
                    },
                    summarizeAgain: { noteSheet = .summarizeAgain },
                    correctTerms: { noteSheet = .correctTerms },
                    restoreGenerated: { if let id = selection.wrappedValue { library.restoreGeneratedNote(id) } })
    }

    #if DEBUG
    /// Nur Debug-Build, für Bildschirmfotos: erste Aufnahme auswählen (`EARNOTE_DEMO_LIBRARY=1`) und auf Wunsch
    /// den Inspector zeigen (`EARNOTE_DEMO_INSPECTOR`), suchen (`EARNOTE_DEMO_SEARCH`), die Vorbereitungs-Zeile
    /// zeigen (`EARNOTE_DEMO_PREPARING`) oder eine Notiz-Aktion öffnen (`EARNOTE_NOTE_ACTION=edit|summarize|correct|pdf`).
    private func demoSelectionIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["EARNOTE_DEMO_LIBRARY"] != nil else { return }
        Task { @MainActor in
            // Warten, bis die Bibliothek (inklusive Beispielaufnahme) wirklich da ist
            for _ in 0..<40 where library.recordings.isEmpty {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Immer setzen: ein gespeicherter Fensterzustand aus einem früheren Lauf zeigt sonst auf eine
            // Aufnahme, die es in diesem Sandkasten nicht gibt – und die Liste räumt die Auswahl wieder ab.
            selection.wrappedValue = library.recordings.first?.id
            if env["EARNOTE_DEMO_INSPECTOR"] != nil { inspectorShown = true; detailMode.wrappedValue = .note }
            // Nur Debug: Ansicht festlegen („note“, „transcript“, „both“) – für Bildschirmfotos
            if let mode = env["EARNOTE_DEMO_MODE"].flatMap(DetailMode.init(rawValue:)) { detailMode.wrappedValue = mode }
            // Nur Debug: die Vorbereitungs-Zeile zeigen, ohne ein Modell zu laden
            if env["EARNOTE_DEMO_PREPARING"] != nil { WhisperModelManager.shared.preparing = "large-v3-v20240930_turbo" }
            if let query = env["EARNOTE_DEMO_SEARCH"] {
                searchText = query
                detailMode.wrappedValue = .transcript
            }
            switch env["EARNOTE_NOTE_ACTION"] {
            case "edit": if let id = library.recordings.first?.id { noteActions.edit(id) }
            case "summarize": noteActions.summarizeAgain()
            case "correct": noteActions.correctTerms()
            case "pdf":
                // Nur Debug: PDF erzeugen und den Pfad ins Protokoll schreiben
                if let id = selection.wrappedValue, let url = await NoteDocument.temporaryPDF(id, library: library) {
                    Log.info("Demo-PDF: \(url.path)")
                }
            default: break
            }
        }
    }
    #endif

    /// Audiodatei der gewählten Aufnahme bereitstellen (oder den Player leeren)
    private func loadAudio(_ id: UUID?) {
        guard let id, let recording = library.recording(id), recording.status != .recording else {
            player.stop()
            return
        }
        player.load(id, url: library.audio.playbackURL(for: recording))
    }

    private func newCategory() {
        let category = library.addCategory()
        filter.wrappedValue = .category(category.id)
        renamingCategoryID = category.id
    }

    /// Kurz warten, während getippt wird; gesucht wird im Hintergrund in der Datenbank.
    private func runSearch() async {
        let query = SearchText.normalized(searchText)
        guard !query.isEmpty else { searchResults = nil; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let ids = await library.search(query)
        guard !Task.isCancelled else { return }
        searchResults = ids
    }

    private var isDeletionPending: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var deletionTitle: String {
        let name = pendingDeletion.flatMap { library.recording($0) }?.displayTitle
        return name.map { "„\($0)“ löschen?" } ?? "Aufnahme löschen?"
    }

    private var hintShown: Binding<Bool> {
        Binding(get: { recorder.lastError != nil || library.lastError != nil },
                set: { if !$0 { recorder.lastError = nil; library.lastError = nil } })
    }
}
