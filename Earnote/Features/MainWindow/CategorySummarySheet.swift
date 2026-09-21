import EarnoteCore
import SwiftUI

/// Übersicht über einen Bereich („Was war dieses Semester in Analysis II?“).
/// Zeitraum wählen, optional eine eigene Anweisung, dann schreibt die KI aus den vorhandenen Notizen
/// eine zusammenhängende Übersicht – sie landet als neuer Eintrag in diesem Bereich.
struct CategorySummarySheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let categoryID: UUID
    /// Die fertige Übersicht auswählen, damit man sie gleich liest
    let onCreated: (UUID) -> Void

    @State private var period: Period = .semester
    @State private var instruction = ""
    @State private var running = false

    /// Zeiträume, wie Studierende denken – nicht in Tagen
    private enum Period: String, CaseIterable, Identifiable {
        case month, quarter, semester, all
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .month: return "Letzter Monat"
            case .quarter: return "Letzte drei Monate"
            case .semester: return "Letzte sechs Monate"
            case .all: return "Alle Aufnahmen"
            }
        }

        var since: Date? {
            let months: Int
            switch self {
            case .month: months = 1
            case .quarter: months = 3
            case .semester: months = 6
            case .all: return nil
            }
            return Calendar.current.date(byAdding: .month, value: -months, to: Date())
        }
    }

    private var category: RecordingCategory? { library.category(categoryID) }

    /// Wie viele Aufnahmen in den gewählten Zeitraum fallen (Übersichten zählen nicht mit)
    private var matching: Int {
        library.recordings.filter { recording in
            recording.categoryID == categoryID && recording.status == .done && recording.duration >= 1
                && (period.since.map { recording.startedAt >= $0 } ?? true)
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Bereich") {
                        Text(category?.name ?? "").foregroundStyle(.secondary)
                    }
                    Picker("Zeitraum", selection: $period) {
                        ForEach(Period.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Aufnahmen") {
                        Text(matching == 1 ? "Eine Aufnahme" : "\(matching) Aufnahmen")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Die KI liest die fertigen Notizen dieses Bereichs und schreibt daraus eine Übersicht "
                         + "mit Themen, rotem Faden und Prüfungshinweisen. Sie landet als eigener Eintrag hier.")
                }
                Section {
                    TextField("Zusätzliche Anweisung (optional)", text: $instruction, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Zum Beispiel: „Nur die Rechenwege“ oder „Mit Beispielaufgaben zu jedem Thema“.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if running {
                    ProgressView().controlSize(.small)
                    Text("Die KI liest die Notizen … das dauert ein paar Minuten.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übersicht erstellen") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(running || matching < 2)
            }
            .padding(16)
        }
        .frame(width: 520)
    }

    private func create() {
        running = true
        Task {
            let id = await library.summarizeCategory(categoryID, since: period.since, instruction: instruction)
            running = false
            if let id { onCreated(id) }
            dismiss()
        }
    }
}
