import EarnoteCore
import SwiftUI
import UniformTypeIdentifiers

/// Tab „Aufnahmen“: alle Aufnahmen nach Tagen – wie in Sprachmemos. Bereiche und Filter stehen im Tab „Bereiche“.
/// In breiter Größe (iPad) Liste und Notiz nebeneinander; schmale Fenster fallen von selbst auf den Stapel zurück.
struct RecordingsView: View {
    @Binding var path: [UUID]
    @Binding var showsSettings: Bool
    @Binding var importing: Bool

    var body: some View {
        RecordingSplit(path: $path) { list(selection: $0) }
    }

    private func list(selection: Binding<UUID?>?) -> some View {
        RecordingList(filter: .all, selection: selection)
            .paper()
            .navigationTitle("Aufnahmen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importieren", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
    }
}

/// Liste und Notiz: in breiter Größe (iPad) nebeneinander, sonst als Stapel. Entschieden wird nur nach Größenklasse,
/// nie nach Gerät (DESIGN_GUIDELINES 31) – Slide Over und schmale Fenster am iPad bekommen den Stapel.
struct RecordingSplit<Content: View>: View {
    @Binding var path: [UUID]
    @ViewBuilder var list: (Binding<UUID?>?) -> Content
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                list(Binding(get: { path.last }, set: { path = $0.map { [$0] } ?? [] }))
            } detail: {
                // Gelöschte Aufnahme: zurück zum Hinweis statt „nicht gefunden“
                if let id = path.last, library.recording(id) != nil {
                    // Eigener Stapel je Notiz: Karteikarten öffnen sich in der rechten Spalte
                    NavigationStack { RecordingDetailView(id: id) }.id(id)
                } else {
                    ContentUnavailableView("Keine Aufnahme ausgewählt", systemImage: "waveform",
                                           description: Text("Wähle links eine Aufnahme."))
                }
            }
        } else {
            NavigationStack(path: $path) {
                list(nil)
                    .navigationDestination(for: UUID.self) { RecordingDetailView(id: $0) }
            }
        }
    }
}

/// Aufnahmen eines Filters nach Tagen – im Tab „Aufnahmen“ und in jedem Bereich
struct RecordingList: View {
    let filter: LibraryFilter
    /// Nur in der Split-Ansicht (iPad): Auswahl statt Navigationsstapel
    var selection: Binding<UUID?>? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(ProcessingQueue.self) private var queue
    @State private var pendingDeletion: UUID?

    private var items: [Recording] { library.recordings.filter { filter.matches($0) } }

    private var category: RecordingCategory? {
        if case .category(let id) = filter { return library.category(id) }
        return nil
    }

    var body: some View {
        Group {
            if !library.isLoaded {
                ProgressView()
            } else if items.isEmpty {
                empty
            } else {
                List(selection: selection) {
                    if filter == .all, queue.processingID == nil, queue.isWaitingForPower {
                        WaitingForPowerSection()
                    }
                    ForEach(LibraryListing.groupedByDay(items)) { section in
                        Section(section.title) {
                            ForEach(section.items) { recording in
                                NavigationLink(value: recording.id) {
                                    // Im Bereich selbst wäre sein Name in jeder Zeile doppelt
                                    RecordingRow(recording: recording, showsCategory: category == nil)
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

    @ViewBuilder private var empty: some View {
        switch filter {
        case .openTasks:
            ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checkmark.circle",
                                   description: Text("Aufgaben aus deinen Notizen erscheinen hier, bis du sie abhakst."))
        case .problems:
            ContentUnavailableView("Keine Probleme", systemImage: "checkmark.seal",
                                   description: Text("Alle Aufnahmen wurden verarbeitet."))
        default:
            ContentUnavailableView {
                Label("Noch keine Aufnahme", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative.reversing)
            } description: {
                Text("Tippe unten auf „Aufnehmen“. Danach steht hier deine Notiz.")
            } actions: {
                if !recorder.isRecording {
                    Button("Jetzt aufnehmen", systemImage: "record.circle") {
                        Task { await recorder.start(category: category) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        }
    }
}

/// „Erst am Ladekabel“ oder Stromsparmodus: Die Aufnahmen warten – oder beginnen auf Wunsch gleich
private struct WaitingForPowerSection: View {
    @Environment(ProcessingQueue.self) private var queue
    @Environment(PhonePower.self) private var power

    var body: some View {
        Section {
            Label {
                if queue.pending.count == 1 {
                    Text("Eine Aufnahme wartet aufs Ladekabel")
                } else {
                    Text("\(queue.pending.count) Aufnahmen warten aufs Ladekabel")
                }
            } icon: {
                Image(systemName: "powerplug")
            }
            Button("Jetzt verarbeiten", systemImage: "play.fill") { queue.processNow() }
        } footer: {
            if power.isLowPowerMode {
                Text("Der Stromsparmodus ist an. Die Notiz entsteht, sobald das iPhone lädt.")
            } else {
                Text("Die Notiz entsteht, sobald das iPhone lädt – auch nachts bei geschlossener App.")
            }
        }
    }
}

/// Eine Zeile: Titel, Zeit und Länge bzw. Stand der Verarbeitung, eine Zeile Vorschau.
struct RecordingRow: View {
    let recording: Recording
    var showsCategory = true
    @Environment(LibraryStore.self) private var library
    @Environment(HandoffSender.self) private var handoffs
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Größte Schrift (Barrierefreiheit): kein Symbol, dafür darf alles umbrechen – wie in Mail und Notizen
    private var isLarge: Bool { typeSize.isAccessibilitySize }

    private var category: RecordingCategory? { showsCategory ? library.category(recording.categoryID) : nil }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isLarge { CategoryBadge(category: library.category(recording.categoryID)) }
            details
        }
    }

    private var durationText: String? {
        guard recording.status != .recording else { return nil }
        if recording.duration < 1 { return String(localized: "Übersicht") }
        return Duration.seconds(recording.duration).formatted(.units(allowed: recording.duration < 60 ? Set([.seconds]) : Set([.hours, .minutes]), width: .abbreviated))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recording.displayTitle)
                .font(.headline)
                .lineLimit(isLarge ? 4 : 2)
            if isLarge {
                Text([recording.startedAt.formatted(.dateTime.hour().minute()), durationText,
                      category?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
            HStack(spacing: 6) {
                Text(recording.startedAt, format: .dateTime.hour().minute())
                    .fixedSize()
                if recording.duration < 1 && recording.status != .recording {
                    Text("·")
                    Text("Übersicht")
                } else if recording.status != .recording {
                    Text("·")
                    Text(Duration.seconds(recording.duration).formatted(.units(allowed: recording.duration < 60 ? Set([.seconds]) : Set([.hours, .minutes]), width: .abbreviated)))
                        // In schmalen Spalten (iPad-Liste) lieber den Bereich kürzen als die Dauer umbrechen
                        .fixedSize()
                }
                if let category {
                    Text("·")
                    Text(category.name).lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            }
            // Das Symbol vor dem Text wird bei größter Schrift riesig und nimmt dem Text die halbe Zeile
            if isLarge { status.labelStyle(.titleOnly) } else { status }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        switch recording.status {
        case .recording:
            Label("Nimmt auf", systemImage: "record.circle").font(.subheadline).foregroundStyle(.tint)
        case .failed:
            Label(recording.errorMessage ?? String(localized: "Fehler bei der Verarbeitung"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.orange).lineLimit(isLarge ? 6 : 2)
        case let status where status.isBusy:
            ProgressView(value: recording.progress) { Text(status.label).font(.caption) }
        case .waitingForMac:
            if handoffs.pending[recording.id]?.state == .failed {
                Label("Dein Mac konnte sie nicht übernehmen", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange)
            } else {
                Label("Wartet auf deinen Mac", systemImage: "laptopcomputer")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        default:
            if let preview = recording.summaryPreview, !preview.isEmpty {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(isLarge ? 3 : 2)
            }
        }
    }
}

/// Aktionen für eine Aufnahme – im Kontextmenü der Liste und im Menü der Notiz
struct RecordingMenu: View {
    let id: UUID
    /// In der Notiz steht der Bereich im Titelmenü – dort nicht doppelt
    var showsCategory = true
    var showsWindow = true
    var onDelete: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(HandoffSender.self) private var handoffs
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if supportsMultipleWindows && showsWindow {
            Button("In neuem Fenster öffnen", systemImage: "macwindow.badge.plus") { openWindow(id: NoteWindow.id, value: id) }
            Divider()
        }
        if showsCategory {
            Menu("Bereich", systemImage: "folder") { CategoryPicker(id: id) }
        }
        if library.recording(id)?.status == .failed {
            Button("Erneut versuchen", systemImage: "arrow.clockwise") { library.enqueue(id) }
        }
        if library.recording(id)?.status == .waitingForMac {
            Button("Auf dem iPhone verarbeiten", systemImage: "iphone") { handoffs.processHere(id) }
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

/// Bereich einer Aufnahme wählen – im Kontextmenü der Liste und im Titelmenü der Notiz
struct CategoryPicker: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Picker("Bereich", systemImage: "folder", selection: Binding(get: { library.recording(id)?.categoryID },
                                                                    set: { library.setCategory(id, $0) })) {
            Text("Ohne Bereich").tag(UUID?.none)
            ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
        }
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

/// Zeichen des Bereichs (Emoji wie am Mac) auf einem Kreis in dessen Farbe – wie die Listen in Erinnerungen
struct CategoryBadge: View {
    let category: RecordingCategory?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let category {
                Text(category.displayEmoji).font(.system(size: size * 0.5))
            } else {
                Image(systemName: "waveform").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(category.map { Color(hex: $0.colorHex).opacity(0.22) } ?? Color.secondary.opacity(0.15), in: .circle)
        .accessibilityHidden(true)
    }
}
