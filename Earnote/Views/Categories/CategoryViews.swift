import EarnoteCore
import SwiftUI

// MARK: - Vorlagen auswählen

/// Kachel-Auswahl aus Vorlagen, gruppiert nach Arbeit / Studium / Privat.
/// Wer „Vorlesung“ wählt, kann direkt seine Fächer eintragen – jedes wird ein eigener Bereich.
struct CategoryTemplatePicker: View {
    @Binding var selected: Set<String>
    @Binding var subjects: [String]
    /// Vorlagen, die schon als Bereich existieren (werden als „vorhanden“ gezeigt)
    var existingNames: Set<String> = []

    @State private var subjectInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            ForEach(CategoryTemplate.Group.allCases) { group in
                VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
                    Text(group.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Theme.Space.s + 2)], spacing: Theme.Space.s + 2) {
                        ForEach(CategoryTemplate.all.filter { $0.group == group }) { template in
                            tile(template)
                        }
                    }
                    if group == .study && selected.contains("lecture") {
                        subjectsEditor
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
    }

    private func tile(_ template: CategoryTemplate) -> some View {
        let isOn = selected.contains(template.id)
        let exists = existingNames.contains(template.name)
        let color = Color(hex: template.colorHex) ?? .gray
        return Button {
            guard !exists else { return }
            if isOn { selected.remove(template.id) } else { selected.insert(template.id) }
        } label: {
            HStack(spacing: Theme.Space.m) {
                EmojiBadge(emoji: template.emoji, color: color, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(Theme.Font.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(exists ? "Schon vorhanden" : template.detail)
                        .font(Theme.Font.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn || exists ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? color : Color.secondary.opacity(exists ? 0.5 : 0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? color.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? color.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: isOn ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(exists ? 0.6 : 1)
        .hoverLift(1.01)
    }

    private var subjectsEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            HStack(spacing: Theme.Space.s) {
                Text("🎒")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deine Fächer oder Module").font(Theme.Font.body.weight(.semibold))
                    Text("Jedes Fach bekommt einen eigenen Bereich. Du kannst das auch leer lassen.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: Theme.Space.s) {
                TextField("z. B. Mathe II, Statistik, BWL …", text: $subjectInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    .onSubmit(addSubjects)
                Button("Hinzufügen", action: addSubjects)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(subjectInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !subjects.isEmpty {
                FlowChips(items: subjects.enumerated().map { i, name in
                    (id: name, label: "\(CategoryTemplate.subjectEmojis[i % CategoryTemplate.subjectEmojis.count]) \(name)")
                }) { name in
                    subjects.removeAll { $0 == name }
                }
            }
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#8B5CF6")!.opacity(0.07)))
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

/// Entfernbare Plaketten in umbrechenden Zeilen
struct FlowChips: View {
    let items: [(id: String, label: String)]
    let onRemove: (String) -> Void

    var body: some View {
        WrapLayout(spacing: Theme.Space.s) {
            ForEach(items, id: \.id) { item in
                HStack(spacing: 5) {
                    Text(item.label).font(Theme.Font.small.weight(.medium))
                    Button { onRemove(item.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 5)
                .background(Capsule().fill(Theme.cardBackground))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }
}

/// Einfaches Umbruch-Layout: Elemente nebeneinander, bei Platzmangel in die nächste Zeile.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Bereich hinzufügen

struct AddCategorySheet: View {
    @EnvironmentObject var app: AppState
    let onDone: (RecordingCategory?) -> Void

    @State private var selected: Set<String> = []
    @State private var subjects: [String] = []
    @State private var custom: RecordingCategory?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bereich hinzufügen").font(Theme.Font.title)
                    Text("Wähle Vorlagen oder leg einen eigenen an.").font(Theme.Font.body).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    custom = RecordingCategory(name: "", emoji: "⭐️", symbol: "star.fill",
                                               colorHex: RecordingCategory.colorChoices.randomElement()!, instructions: "")
                } label: {
                    Label("Eigener Bereich", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Theme.Space.xl)

            ScrollView {
                CategoryTemplatePicker(selected: $selected, subjects: $subjects,
                                       existingNames: Set(app.categories.map(\.name)))
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.xl)
            }

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { onDone(nil) }.buttonStyle(SecondaryButtonStyle())
                Button(addTitle) {
                    let added = app.addCategories(templates: selected, subjects: subjects)
                    onDone(added.first)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected.isEmpty && subjects.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.l)
        }
        .frame(width: 680, height: 620)
        .sheet(item: $custom) { category in
            CategoryEditorSheet(category: category, isNew: true) { custom = nil }
                .environmentObject(app)
        }
        .onChange(of: app.categories.count) { old, new in
            // Eigener Bereich wurde im Editor gesichert → Blatt schließen und dorthin springen
            if new > old, custom != nil { onDone(app.categories.last) }
        }
    }

    private var addTitle: String {
        let count = selected.count + subjects.count - (selected.contains("lecture") && !subjects.isEmpty ? 1 : 0)
        return count <= 1 ? "Hinzufügen" : "\(count) Bereiche hinzufügen"
    }
}

// MARK: - Bereich bearbeiten

struct CategoryEditorSheet: View {
    @EnvironmentObject var app: AppState
    @State var category: RecordingCategory
    var isNew = false
    let onDone: () -> Void

    @State private var customEmoji = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.l) {
                category.badge(size: 64)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: category.emoji)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name, z. B. „Mathe II“", text: $category.name)
                        .textFieldStyle(.plain)
                        .font(.system(.title, weight: .bold))
                    Text(isNew ? "Neuer Bereich" : "Bereich bearbeiten").font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }

            section("Emoji") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 10), spacing: 6) {
                    ForEach(RecordingCategory.emojiChoices, id: \.self) { emoji in
                        Button { category.emoji = emoji } label: {
                            Text(emoji).font(.system(size: 19))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(category.displayEmoji == emoji ? category.color.opacity(0.25) : Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    Text("Anderes Emoji:").font(Theme.Font.caption).foregroundStyle(.secondary)
                    TextField("😀", text: $customEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: customEmoji) { _, value in
                            // Nur das erste Zeichen übernehmen – Emojis können aus mehreren Codepunkten bestehen
                            if let first = value.first { category.emoji = String(first) }
                        }
                    Text("⌃⌘Leertaste öffnet die Emoji-Auswahl").font(Theme.Font.caption).foregroundStyle(.tertiary)
                }
            }

            section("Farbe") {
                HStack(spacing: Theme.Space.s + 2) {
                    ForEach(RecordingCategory.colorChoices, id: \.self) { hex in
                        let color = Color(hex: hex) ?? .gray
                        Button { category.colorHex = hex } label: {
                            Circle().fill(color).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.white, lineWidth: category.colorHex == hex ? 3 : 0))
                                .shadow(color: color.opacity(category.colorHex == hex ? 0.6 : 0), radius: 4)
                                .scaleEffect(category.colorHex == hex ? 1.1 : 1)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: category.colorHex)
                    }
                }
            }

            section("Worauf soll die KI achten?") {
                TextEditor(text: $category.instructions)
                    .font(Theme.Font.small)
                    .scrollContentBackground(.hidden)
                    .frame(height: 90)
                    .padding(Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                Text("Optional, z. B. „Prüfungsrelevante Formeln hervorheben“. Gute Notizen gibt es auch ohne.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }

            let enabled = Destinations.all.filter { app.settings.destinations.enabled.contains($0.id) }
            if !enabled.isEmpty {
                section("Ablegen in") {
                    HStack {
                        ForEach(enabled) { d in
                            Toggle(d.name, isOn: Binding(
                                get: { category.destinationIDs.contains(d.id) },
                                set: { if $0 { category.destinationIDs.insert(d.id) } else { category.destinationIDs.remove(d.id) } }))
                            .toggleStyle(.checkbox)
                        }
                    }
                    Text("Nichts ausgewählt = alle aktiven Ziele.").font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                if !isNew && app.categories.count > 1 {
                    Button("Löschen", role: .destructive) {
                        app.categories.removeAll { $0.id == category.id }
                        onDone()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Abbrechen", action: onDone).buttonStyle(SecondaryButtonStyle())
                Button(isNew ? "Anlegen" : "Sichern") {
                    category.name = category.name.trimmingCharacters(in: .whitespaces)
                    if let i = app.categories.firstIndex(where: { $0.id == category.id }) {
                        app.categories[i] = category
                    } else {
                        app.categories.append(category)
                    }
                    onDone()
                }
                .buttonStyle(PrimaryButtonStyle(color: category.color))
                .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.Font.small.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
