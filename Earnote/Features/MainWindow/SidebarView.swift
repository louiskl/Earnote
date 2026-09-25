import EarnoteCore
import SwiftData
import SwiftUI

/// Seitenleiste als Source List: Bibliothek und Bereiche, je mit Anzahl.
struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.categoryTint) private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\LibraryCategory.sortIndex), SortDescriptor(\LibraryCategory.createdAt)])
    private var categories: [LibraryCategory]
    @Query private var recordings: [LibraryRecording]

    @Binding var filter: LibraryFilter
    @Binding var renamingCategoryID: UUID?
    let onEdit: (UUID) -> Void
    let onNewCategory: () -> Void
    /// Übersicht über einen Bereich erstellen (öffnet das Blatt im Hauptfenster)
    let onSummarize: (UUID) -> Void
    let onExamRadar: (UUID) -> Void

    @State private var pendingDeletion: LibraryCategory?

    var body: some View {
        let counts = LibraryListing.counts(recordings)
        List(selection: Binding(get: { filter }, set: { if let value = $0 { filter = value } })) {
            Section("Bibliothek") {
                LibraryRow(title: "Alle Aufnahmen", systemImage: "tray.full", count: counts.all)
                    .tag(LibraryFilter.all)
                LibraryRow(title: "Offene Aufgaben", systemImage: "checklist", count: counts.openTasks)
                    .tag(LibraryFilter.openTasks)
                LibraryRow(title: "Ohne Bereich", systemImage: "tray", count: counts.uncategorized)
                    .tag(LibraryFilter.uncategorized)
                if counts.problems > 0 {
                    LibraryRow(title: "Probleme", systemImage: "exclamationmark.triangle", count: counts.problems)
                        .tag(LibraryFilter.problems)
                }
            }
            // Ohne eigene Bereiche keine leere Überschrift; der Knopf unten legt den ersten an.
            if !categories.isEmpty {
                Section("Bereiche") {
                    ForEach(categories) { category in
                        CategoryRow(category: category, count: counts.count(for: .category(category.id)),
                                    isRenaming: renamingCategoryID == category.id,
                                    onRename: { library.renameCategory(category.id, to: $0); renamingCategoryID = nil },
                                    onCancelRename: { renamingCategoryID = nil })
                            .tag(LibraryFilter.category(category.id))
                            .contextMenu {
                                Button("Umbenennen") { renamingCategoryID = category.id }
                                Button("Bearbeiten …") { onEdit(category.id) }
                                Divider()
                                Button("Übersicht erstellen …") { onSummarize(category.id) }
                                Button("Klausur-Radar") { onExamRadar(category.id) }
                                Divider()
                                Button("Löschen …", role: .destructive) { pendingDeletion = category }
                            }
                    }
                    .onMove(perform: move)
                }
            }
        }
        .listStyle(.sidebar)
        // Die Seitenleiste nimmt die Farbe des gewählten Bereichs auf – dezent, damit Text lesbar bleibt.
        .scrollContentBackground(.hidden)
        .background(tint.opacity(0.16))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: tint)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button(action: onNewCategory) {
                    Label("Neuer Bereich", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Neuen Bereich anlegen (⇧⌘N)")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .confirmationDialog(pendingDeletion.map { "Bereich „\($0.name)“ löschen?" } ?? "",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Löschen", role: .destructive) {
                if let category = pendingDeletion { library.deleteCategory(category.id) }
                pendingDeletion = nil
            }
        } message: {
            Text("Die Aufnahmen bleiben erhalten.")
        }
    }


    private func move(from source: IndexSet, to destination: Int) {
        var ids = categories.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        library.setCategoryOrder(ids)
    }
}

private struct LibraryRow: View {
    /// `LocalizedStringKey`, damit die Namen der Bibliothek mitübersetzt werden
    let title: LocalizedStringKey
    let systemImage: String
    let count: Int

    var body: some View {
        Label(title, systemImage: systemImage)
            .badge(count)
            .accessibilityLabel(Text(title) + Text(", \(count)"))
    }
}

private struct CategoryRow: View {
    let category: LibraryCategory
    let count: Int
    let isRenaming: Bool
    let onRename: (String) -> Void
    let onCancelRename: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Label {
            if isRenaming {
                TextField("Name des Bereichs", text: $draft)
                    .focused($focused)
                    .onSubmit { onRename(draft) }
                    .onExitCommand(perform: onCancelRename)
                    .onAppear { draft = category.name; focused = true }
            } else {
                Text(category.name)
            }
        } icon: {
            CategoryBadge(emoji: category.emoji, symbol: category.symbol,
                         tint: category.tint)
        }
        .badge(isRenaming ? 0 : count)
        .accessibilityLabel("\(category.name), \(count) Aufnahmen")
    }
}
