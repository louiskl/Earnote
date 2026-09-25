import EarnoteCore
import SwiftUI

/// Tab „Bereiche“ – das Gegenstück zur Seitenleiste der Mac-App: Bibliothek (Alle, Offene Aufgaben, Ohne Bereich,
/// Probleme) und die Bereiche mit Zählern. Ein Bereich zeigt seine Aufnahmen, die Übersicht und die Karteikarten.
struct LibraryView: View {
    @Binding var path: NavigationPath
    @Environment(LibraryStore.self) private var library
    @Environment(\.skin) private var skin
    @State private var creating = false
    @State private var editing: RecordingCategory?

    private var counts: LibraryCounts { LibraryListing.counts(library.recordings) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Bibliothek") {
                    row(.all, "Alle Aufnahmen", symbol: "tray.full.fill", color: skin.tint)
                    row(.openTasks, "Offene Aufgaben", symbol: "checklist", color: .orange)
                    row(.uncategorized, "Ohne Bereich", symbol: "tray.fill", color: .gray)
                    if counts.problems > 0 {
                        row(.problems, "Probleme", symbol: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                Section("Bereiche") {
                    ForEach(library.categories) { category in
                        NavigationLink(value: LibraryFilter.category(category.id)) {
                            LabeledContent {
                                Text("\(counts.count(for: .category(category.id)))").monospacedDigit()
                            } label: {
                                Label { Text(category.name) } icon: { CategoryBadge(category: category, size: 30) }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Bearbeiten", systemImage: "pencil") { editing = category }.tint(skin.tint)
                        }
                        .contextMenu {
                            Button("Bearbeiten", systemImage: "pencil") { editing = category }
                            Button("Löschen", systemImage: "trash", role: .destructive) { library.deleteCategory(category.id) }
                        }
                    }
                    .onMove { from, to in
                        var ids = library.categories.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        library.setCategoryOrder(ids)
                    }
                    .onDelete { offsets in
                        for index in offsets { library.deleteCategory(library.categories[index].id) }
                    }
                    Button("Neuer Bereich", systemImage: "plus.circle.fill") { creating = true }
                }
            }
            .paper()
            .navigationTitle("Bereiche")
            .toolbar { EditButton() }
            .navigationDestination(for: LibraryFilter.self) { FilteredRecordingsView(filter: $0) }
            .navigationDestination(for: UUID.self) { RecordingDetailView(id: $0) }
            .sheet(isPresented: $creating) { NewCategorySheet() }
            .sheet(item: $editing) { CategoryEditor(category: $0) }
        }
    }

    private func row(_ filter: LibraryFilter, _ title: LocalizedStringKey, symbol: String, color: Color) -> some View {
        NavigationLink(value: filter) {
            LabeledContent {
                Text("\(counts.count(for: filter))").monospacedDigit()
            } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(color.gradient, in: .circle)
                }
            }
        }
    }
}

/// Aufnahmen eines Filters. Für Bereiche zusätzlich: Übersicht erstellen, Karteikarten lernen, bearbeiten.
struct FilteredRecordingsView: View {
    let filter: LibraryFilter
    /// Split-Ansicht (iPad-Seitenleiste): Auswahl statt Stapel
    var selection: Binding<UUID?>? = nil
    @Environment(LibraryStore.self) private var library
    @State private var editing: RecordingCategory?
    @State private var deck: LearnDeck?
    @State private var cardCount = 0
    @State private var showsRadar = false
    @State private var showsPro = false

    private var category: RecordingCategory? {
        if case .category(let id) = filter { return library.category(id) }
        return nil
    }

    var body: some View {
        RecordingList(filter: filter, selection: selection)
            .paper()
            .navigationTitle(title)
            .toolbar {
                // Nur zum Lernen: Wer Earnote für die Arbeit nutzt, sieht kein Klausur-Radar (Einstiegsfrage)
                if category != nil, library.settings.usage?.isLearning ?? true {
                    // Anschauen kostet keinen Probeversuch – die zählen beim Markieren
                    Button("Klausur-Radar", systemImage: "scope") {
                        if Pro.isUnlocked || Pro.triesLeft(.examRadar) > 0 { showsRadar = true } else { showsPro = true }
                    }
                }
                if let category {
                    Menu("Mehr", systemImage: "ellipsis") {
                        Button("Übersicht erstellen", systemImage: "doc.text.magnifyingglass") {
                            _ = library.summarizeCategory(category.id, since: nil)
                        }
                        .disabled(library.overviewSourceCount(category.id) < 2)
                        Button("Karteikarten lernen", systemImage: "rectangle.on.rectangle.angled") {
                            Task { deck = await FlashcardDeck.load(for: filter, title: category.name, library: library) }
                        }
                        .disabled(cardCount == 0)
                        Divider()
                        Button("Bereich bearbeiten", systemImage: "pencil") { editing = category }
                    }
                }
            }
            .navigationDestination(item: $deck) { FlashcardSession(deck: $0) }
            .navigationDestination(isPresented: $showsRadar) {
                if let category { ExamRadarView(category: category) }
            }
            .sheet(isPresented: $showsPro) { ProSheet(highlight: .examRadar) }
            .sheet(item: $editing) { CategoryEditor(category: $0) }
            .task(id: library.recordings.map(\.summaryPreview).hashValue) {
                cardCount = await FlashcardDeck.load(for: filter, title: "", library: library)?.cards.count ?? 0
            }
    }

    private var title: String {
        switch filter {
        case .all: String(localized: "Alle Aufnahmen")
        case .openTasks: String(localized: "Offene Aufgaben")
        case .uncategorized: String(localized: "Ohne Bereich")
        case .problems: String(localized: "Probleme")
        case .category: category?.name ?? ""
        }
    }
}

/// Karteikarten sammeln: Sie stehen in den Notizen selbst (Abschnitt „Karteikarten“)
enum FlashcardDeck {
    @MainActor
    static func load(for filter: LibraryFilter, title: String, library: LibraryStore) async -> LearnDeck? {
        var cards: [Flashcard] = []
        for recording in library.recordings where filter.matches(recording) && recording.status == .done {
            guard let note = await library.summary(recording.id) else { continue }
            cards += Flashcards.entries(note.markdown).map(\.card)
        }
        return cards.isEmpty ? nil : LearnDeck(title: title, cards: cards)
    }
}

// MARK: - Bereiche anlegen und bearbeiten

/// Neuer Bereich: aus einer Vorlage (mit passenden Hinweisen für die KI) oder ganz eigener.
/// Wer „Vorlesung“ wählt, trägt seine Fächer ein – jedes wird ein eigener Bereich, wie am Mac.
struct NewCategorySheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var subjects = ""
    @State private var custom: RecordingCategory?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Deine Fächer, z. B. Mathe II, Statistik", text: $subjects)
                        .submitLabel(.done)
                        .onSubmit(addSubjects)
                    Button("Als Bereiche anlegen", systemImage: "graduationcap") { addSubjects() }
                        .disabled(subjectNames.isEmpty)
                } header: {
                    Text("Fächer")
                } footer: {
                    Text("Jedes Fach wird ein eigener Bereich mit den Hinweisen für Vorlesungen. Mehrere mit Komma trennen.")
                }
                ForEach(CategoryTemplate.Group.allCases) { group in
                    Section(group.label) {
                        ForEach(CategoryTemplate.all.filter { $0.group == group }) { template in
                            let exists = library.categories.contains { $0.name == template.name }
                            Button {
                                _ = library.addCategories(templates: [template.id], subjects: [])
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(template.emoji)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(Color(hex: template.colorHex).opacity(0.22), in: .circle)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name).foregroundStyle(.primary)
                                        Text(exists ? String(localized: "Ist schon angelegt") : template.detail)
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                            .disabled(exists)
                        }
                    }
                }
                Section {
                    Button("Eigener Bereich …", systemImage: "square.and.pencil") {
                        custom = RecordingCategory(name: "", emoji: "📚", symbol: "folder.fill",
                                                   colorHex: RecordingCategory.colorChoices[0], instructions: "")
                    }
                }
            }
            .navigationTitle("Neuer Bereich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .sheet(item: $custom) { CategoryEditor(category: $0, isNew: true) { dismiss() } }
        }
    }

    private var subjectNames: [String] {
        subjects.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func addSubjects() {
        guard !subjectNames.isEmpty else { return }
        _ = library.addCategories(templates: [], subjects: subjectNames)
        dismiss()
    }
}

/// Bereich bearbeiten: Name, Zeichen, Farbe und Hinweise für die KI – wie am Mac
struct CategoryEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var category: RecordingCategory
    private let isNew: Bool
    private let onSave: () -> Void

    init(category: RecordingCategory, isNew: Bool = false, onSave: @escaping () -> Void = {}) {
        _category = State(initialValue: category)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CategoryBadge(category: category, size: 52)
                        TextField("Name, z. B. Mathe II", text: $category.name)
                            .font(.title3.weight(.semibold))
                    }
                }
                Section("Zeichen") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(RecordingCategory.emojiChoices, id: \.self) { emoji in
                            Button { category.emoji = emoji } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(category.displayEmoji == emoji ? Color(hex: category.colorHex).opacity(0.25) : .clear,
                                                in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(category.displayEmoji == emoji ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Farbe") {
                    HStack {
                        ForEach(RecordingCategory.colorChoices, id: \.self) { hex in
                            Button { category.colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if category.colorHex == hex {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextEditor(text: $category.instructions)
                        .frame(minHeight: 120)
                } header: {
                    Text("Hinweise für die KI")
                } footer: {
                    Text("Worauf die Notiz in diesem Bereich achten soll, z. B. „Formeln immer mit Rechenweg“.")
                }
            }
            .navigationTitle(isNew ? "Eigener Bereich" : "Bereich bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        category.name = category.name.trimmingCharacters(in: .whitespaces)
        if let index = library.categories.firstIndex(where: { $0.id == category.id }) {
            library.categories[index] = category
        } else {
            library.categories.append(category)
        }
        dismiss()
        onSave()
    }
}
