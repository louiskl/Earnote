import EarnoteCore
import SwiftUI
import UniformTypeIdentifiers

/// Tab „Aufnahmen“: nach Tagen gruppiert, Filter nach Bereich, Einstellungen in der Symbolleiste.
struct RecordingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PhoneRecorder.self) private var recorder
    @SceneStorage("recordings.category") private var categoryFilter = ""
    @State private var showsSettings = false
    @State private var pendingDeletion: UUID?
    @State private var importing = false

    private var filtered: [Recording] {
        guard let id = UUID(uuidString: categoryFilter) else { return library.recordings }
        return library.recordings.filter { $0.categoryID == id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !library.isLoaded {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Aufnahme", systemImage: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing)
                    } description: {
                        Text("Tippe unten auf „Aufnehmen“. Danach steht hier deine Notiz.")
                    } actions: {
                        if !recorder.isRecording {
                            Button("Jetzt aufnehmen", systemImage: "record.circle") {
                                Task { await recorder.start(category: UUID(uuidString: categoryFilter).flatMap { library.category($0) }) }
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    List {
                        ForEach(LibraryListing.groupedByDay(filtered)) { section in
                            Section(section.title) {
                                ForEach(section.items) { recording in
                                    NavigationLink(value: recording.id) {
                                        RecordingRow(recording: recording)
                                    }
                                    .swipeActions {
                                        Button("Löschen", systemImage: "trash", role: .destructive) { pendingDeletion = recording.id }
                                    }
                                    .contextMenu { RecordingMenu(id: recording.id, onDelete: { pendingDeletion = recording.id }) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: UUID.self) { RecordingDetailView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importieren", systemImage: "square.and.arrow.down") { importing = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Bereich", systemImage: categoryFilter.isEmpty ? "line.3.horizontal.decrease.circle"
                                                                         : "line.3.horizontal.decrease.circle.fill") {
                        Picker("Bereich", selection: $categoryFilter) {
                            Text("Alle Aufnahmen").tag("")
                            ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag($0.id.uuidString) }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsSheet() }
            // Audio und Video aus der Dateien-App (Sprachmemos, Aufnahmen anderer Apps)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                AudioImport.run(urls, into: library, category: UUID(uuidString: categoryFilter).flatMap { library.category($0) })
            }
            .confirmationDialog("Aufnahme löschen?", isPresented: Binding(get: { pendingDeletion != nil },
                                                                           set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let id = pendingDeletion { library.delete(id) }
                }
            } message: {
                Text("Aufnahme, Transkript und Notiz werden gelöscht.")
            }
        }
    }

    private var title: String {
        UUID(uuidString: categoryFilter).flatMap { library.category($0)?.name } ?? String(localized: "Aufnahmen")
    }
}

/// Eine Zeile: Titel, Zeit und Länge bzw. Stand der Verarbeitung, eine Zeile Vorschau.
struct RecordingRow: View {
    let recording: Recording
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryBadge(category: library.category(recording.categoryID))
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recording.displayTitle)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(recording.startedAt, format: .dateTime.hour().minute())
                if recording.duration < 1 && recording.status != .recording {
                    Text("·")
                    Text("Übersicht")
                } else if recording.status != .recording {
                    Text("·")
                    Text(Duration.seconds(recording.duration).formatted(.units(allowed: recording.duration < 60 ? Set([.seconds]) : Set([.hours, .minutes]), width: .abbreviated)))
                }
                if let category = library.category(recording.categoryID) {
                    Text("·")
                    Text(category.name).lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            status
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        switch recording.status {
        case .recording:
            Label("Nimmt auf", systemImage: "record.circle").font(.subheadline).foregroundStyle(.tint)
        case .failed:
            Label(recording.errorMessage ?? String(localized: "Fehler bei der Verarbeitung"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.orange).lineLimit(2)
        case let status where status.isBusy:
            ProgressView(value: recording.progress) { Text(status.label).font(.caption) }
        default:
            if let preview = recording.summaryPreview, !preview.isEmpty {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

/// Aktionen für eine Aufnahme – im Kontextmenü der Liste und im Menü der Notiz
struct RecordingMenu: View {
    let id: UUID
    var onDelete: () -> Void
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Menu("Bereich", systemImage: "folder") {
            Picker("Bereich", selection: Binding(get: { library.recording(id)?.categoryID },
                                                 set: { library.setCategory(id, $0) })) {
                Text("Ohne Bereich").tag(UUID?.none)
                ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
            }
        }
        if library.recording(id)?.status == .failed {
            Button("Erneut versuchen", systemImage: "arrow.clockwise") { library.enqueue(id) }
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

/// Fremde Dateien sind am iPhone nur mit Freigabe lesbar – solange kopiert wird, gilt sie.
enum AudioImport {
    @MainActor
    static func run(_ urls: [URL], into library: LibraryStore, category: RecordingCategory?) {
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        library.importAudio(urls, category: category)
    }
}

/// Symbol des Bereichs weiß auf einem Kreis in dessen Farbe – wie die Listen in Erinnerungen
struct CategoryBadge: View {
    let category: RecordingCategory?

    var body: some View {
        Image(systemName: category?.symbol ?? "waveform")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(category.map { Color(hex: $0.colorHex) } ?? Color.gray, in: .circle)
            .accessibilityHidden(true)
    }
}
