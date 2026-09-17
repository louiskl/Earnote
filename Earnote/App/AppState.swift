import Combine
import EarnoteCore
import Observation
import SwiftUI

/// Übergang bis Phase 2b, dann entfernen.
/// Dünne Fassade über LibraryStore und RecordingController für die noch alten Views (Einstellungen,
/// Einrichtungsassistent, Bereichs-Editor, Menüleiste, Call-Pop-up). Das Hauptfenster nutzt sie nicht mehr.
/// Enthält keine eigene Logik.
@MainActor
final class AppState: ObservableObject {
    let library: LibraryStore
    let recorder: RecordingController
    let llm: LLMFactory
    private var cancellables = Set<AnyCancellable>()

    init(library: LibraryStore, recorder: RecordingController, llm: LLMFactory) {
        self.library = library
        self.recorder = recorder
        self.llm = llm
        recorder.detector.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        forwardChanges()
    }

    /// Änderungen der beobachtbaren Stores als `objectWillChange` weitergeben.
    private func forwardChanges() {
        withObservationTracking {
            _ = library.settings; _ = library.categories; _ = library.recordings
            _ = library.selection; _ = library.lastError
            _ = recorder.activeRecordingID; _ = recorder.isPaused; _ = recorder.lastError
        } onChange: { [weak self] in
            // Wird vor der Änderung aufgerufen – genau wie `objectWillChange`. Danach neu beobachten.
            MainActor.assumeIsolated { self?.objectWillChange.send() }
            Task { @MainActor [weak self] in self?.forwardChanges() }
        }
    }

    // MARK: Zustand

    var settings: AppSettings {
        get { library.settings }
        set { library.settings = newValue }
    }
    var categories: [RecordingCategory] {
        get { library.categories }
        set { library.categories = newValue }
    }
    var recordings: [Recording] { library.recordings }
    var selection: UUID? {
        get { library.selection }
        set { library.selection = newValue }
    }
    var lastError: String? {
        get { recorder.lastError ?? library.lastError }
        set { recorder.lastError = newValue; library.lastError = newValue }
    }
    var activeRecordingID: UUID? { recorder.activeRecordingID }
    var isPaused: Bool { recorder.isPaused }
    var isRecording: Bool { recorder.isRecording }
    var activeRecording: Recording? { recorder.activeRecording }
    var meter: LiveMeter { recorder.meter }
    var live: LiveTranscript { recorder.live }
    var detector: MeetingDetector { recorder.detector }
    var audioInputs: AudioInputDevices { recorder.audioInputs }

    func recording(_ id: UUID) -> Recording? { library.recording(id) }
    func category(_ id: UUID?) -> RecordingCategory? { library.category(id) }
    func transcript(_ id: UUID) async -> Transcript? { await library.transcript(id) }
    func summary(_ id: UUID) async -> Summary? { await library.summary(id) }
    func hasAudio(_ id: UUID) -> Bool { library.hasAudio(id) }

    // MARK: Aufnahme

    func startRecording(category: RecordingCategory?, title: String = "", sourceApp: String? = nil, byCall: Bool = false) {
        recorder.startRecording(category: category, title: title, sourceApp: sourceApp, byCall: byCall)
    }
    func pauseRecording() { recorder.pauseRecording() }
    func resumeRecording() { recorder.resumeRecording() }
    func togglePause() { recorder.togglePause() }
    func stopRecording() { recorder.stopRecording() }
    func cancelRecording() { recorder.cancelRecording() }

    // MARK: Bibliothek

    func importAudio(_ urls: [URL], category: RecordingCategory?) { library.importAudio(urls, category: category) }
    func enqueue(_ id: UUID, next: Bool = false) { library.enqueue(id, next: next) }
    func reprocess(_ id: UUID, retranscribe: Bool) { library.reprocess(id, retranscribe: retranscribe) }
    func reexport(_ id: UUID) { library.reexport(id) }
    func rename(_ id: UUID, to title: String) { library.rename(id, to: title) }
    func updateSummaryText(_ id: UUID, markdown: String) { library.updateSummaryText(id, markdown: markdown) }
    func setCategory(_ id: UUID, _ categoryID: UUID?) { library.setCategory(id, categoryID) }
    func deleteAudio(_ id: UUID) { library.deleteAudio(id) }
    func delete(_ id: UUID) { library.delete(id) }
    func revealInFinder(_ id: UUID) { library.revealInFinder(id) }
    @discardableResult
    func addCategories(templates: Set<String>, subjects: [String]) -> [RecordingCategory] {
        library.addCategories(templates: templates, subjects: subjects)
    }
}
