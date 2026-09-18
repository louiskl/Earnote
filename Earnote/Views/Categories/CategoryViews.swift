import EarnoteCore
import SwiftUI

/// Vorlagen für Bereiche auswählen (Einrichtungsassistent): Häkchen pro Vorlage, gruppiert nach Alltag.
/// Wer „Vorlesung“ wählt, kann direkt seine Fächer eintragen – jedes wird ein eigener Bereich.
struct CategoryTemplateList: View {
    @Binding var selected: Set<String>
    @Binding var subjects: [String]
    /// Vorlagen, die schon als Bereich existieren
    var existingNames: Set<String> = []

    @State private var subjectInput = ""

    var body: some View {
        Form {
            ForEach(CategoryTemplate.Group.allCases) { group in
                Section(group.rawValue) {
                    ForEach(CategoryTemplate.all.filter { $0.group == group }) { template in
                        let exists = existingNames.contains(template.name)
                        Toggle(isOn: binding(for: template)) {
                            Text("\(template.emoji)  \(template.name)")
                            Text(exists ? "Ist schon angelegt" : template.detail)
                        }
                        .disabled(exists)
                    }
                    if group == .study && selected.contains("lecture") { subjectRows }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var subjectRows: some View {
        LabeledContent("Deine Fächer") {
            HStack {
                TextField("z. B. Mathe II, Statistik", text: $subjectInput)
                    .onSubmit(addSubjects)
                Button("Hinzufügen", action: addSubjects)
                    .disabled(subjectInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        ForEach(Array(subjects.enumerated()), id: \.element) { index, name in
            LabeledContent {
                Button("Entfernen") { subjects.removeAll { $0 == name } }
                    .buttonStyle(.link)
            } label: {
                Text("\(CategoryTemplate.subjectEmojis[index % CategoryTemplate.subjectEmojis.count])  \(name)")
            }
        }
        Text("Jedes Fach bekommt einen eigenen Bereich. Du kannst das auch leer lassen und später ergänzen.")
            .font(.callout).foregroundStyle(.secondary)
    }

    private func binding(for template: CategoryTemplate) -> Binding<Bool> {
        Binding(get: { selected.contains(template.id) || existingNames.contains(template.name) },
                set: { on in
                    if on { selected.insert(template.id) } else { selected.remove(template.id) }
                })
    }

    /// Mehrere Fächer auf einmal: durch Komma getrennt
    private func addSubjects() {
        let names = subjectInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !subjects.contains($0) }
        subjects.append(contentsOf: names)
        subjectInput = ""
    }
}

// MARK: - Bereich bearbeiten

/// Bereich bearbeiten: Name, Zeichen, Farbe, Hinweise für die KI und die Ziele.
struct CategoryEditorSheet: View {
    @Environment(LibraryStore.self) private var library
    @State var category: RecordingCategory
    var isNew = false
    let onDone: () -> Void

    private var enabledDestinations: [DestinationInfo] {
        Destinations.all.filter { library.settings.destinations.enabled.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $category.name, prompt: Text("z. B. Mathe II"))
                    Picker("Zeichen", selection: emoji) {
                        ForEach(RecordingCategory.emojiChoices, id: \.self) { Text($0).tag($0) }
                        // Ein eigenes Emoji aus einer älteren Version bleibt wählbar
                        if !RecordingCategory.emojiChoices.contains(category.displayEmoji) {
                            Text(category.displayEmoji).tag(category.displayEmoji)
                        }
                    }
                    LabeledContent("Farbe") { colorSwatches }
                }
                Section {
                    TextEditor(text: $category.instructions)
                        .font(.body)
                        .frame(height: 90)
                } header: {
                    Text("Worauf soll die KI achten?")
                } footer: {
                    Text("Optional, z. B. „Prüfungsrelevante Formeln hervorheben“. Gute Notizen gibt es auch ohne.")
                }
                if !enabledDestinations.isEmpty {
                    Section {
                        ForEach(enabledDestinations) { destination in
                            Toggle(destination.name, isOn: Binding(
                                get: { category.destinationIDs.contains(destination.id) },
                                set: { on in
                                    if on { category.destinationIDs.insert(destination.id) }
                                    else { category.destinationIDs.remove(destination.id) }
                                }))
                        }
                    } header: {
                        Text("Notizen ablegen in")
                    } footer: {
                        Text("Nichts ausgewählt: \(AppInfo.name) nutzt alle eingeschalteten Ziele.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew && library.categories.count > 1 {
                    Button("Bereich löschen", role: .destructive) {
                        library.categories.removeAll { $0.id == category.id }
                        onDone()
                    }
                }
                Spacer()
                Button("Abbrechen", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Anlegen" : "Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
    }

    private var emoji: Binding<String> {
        Binding(get: { category.displayEmoji }, set: { category.emoji = $0 })
    }

    private var colorSwatches: some View {
        HStack(spacing: 8) {
            ForEach(RecordingCategory.colorChoices, id: \.self) { hex in
                Button { category.colorHex = hex } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: category.colorHex == hex ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Farbe \(hex)")
                .accessibilityAddTraits(category.colorHex == hex ? .isSelected : [])
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
        onDone()
    }
}
