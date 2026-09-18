import EarnoteCore
import SwiftData
import SwiftUI

/// Hauptfenster: Seitenleiste | Aufnahmeliste | Detail, dazu der Inspector.
/// Das Gerüst bleibt immer gleich; nur der Inhalt der Spalten wechselt. Auswahl und Ansicht gehören dem Fenster.
struct MainWindow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder

    @SceneStorage("sidebarFilter") private var filterRaw = LibraryFilter.all.rawValue
    @SceneStorage("selectedRecording") private var selectedRaw = ""
    @SceneStorage("detailMode") private var detailModeRaw = DetailMode.note.rawValue
    @SceneStorage("inspectorShown") private var inspectorShown = true

    @State private var searchText = ""
    @State private var searchResults: Set<UUID>?
    @State private var renamingRecordingID: UUID?
    @State private var renamingCategoryID: UUID?
    @State private var editingCategory: RecordingCategory?
    @State private var pendingDeletion: UUID?
    @State private var confirmDiscard = false
    @State private var showOnboarding = false
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
                        onNewCategory: newCategory)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            RecordingListView(filter: filter.wrappedValue, selection: selection, searchResults: searchResults,
                              searchText: searchText, renamingID: $renamingRecordingID,
                              onDelete: { pendingDeletion = $0 })
                .navigationSplitViewColumnWidth(min: 260, ideal: 330, max: 520)
        } detail: {
            RecordingDetailView(recordingID: selection.wrappedValue, mode: detailMode.wrappedValue)
        }
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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .interactiveDismissDisabled()
        }
        .alert("Hinweis", isPresented: hintShown) {
            Button("OK") { recorder.lastError = nil; library.lastError = nil }
        } message: {
            Text(recorder.lastError ?? library.lastError ?? "")
        }
        .onAppear { if !library.settings.onboardingCompleted { showOnboarding = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
        .onChange(of: library.categories.map(\.id)) { _, ids in
            // Gelöschter Bereich war ausgewählt → zurück zu „Alle Aufnahmen“
            if let id = selectedCategoryID, !ids.contains(id) { filter.wrappedValue = .all }
        }
        .focusedSceneValue(\.mainWindow, context)
        // Mit Inspector brauchen vier Spalten mehr Platz; ohne ihn darf das Fenster kleiner werden.
        .frame(minWidth: inspectorShown ? 1100 : 840, minHeight: 560)
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
                          focusSearch: { searchFocused = true })
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
