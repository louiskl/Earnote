#if canImport(FoundationModels)
import EarnoteCore
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct AppleIntelligenceClient: StructuredNotesClient {
    static var availabilityText: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "Dieser Mac unterstützt Apple Intelligence nicht."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence ist in den Systemeinstellungen nicht aktiviert."
            case .modelNotReady: return "Das Apple-Modell wird noch geladen. Bitte später erneut versuchen."
            @unknown default: return "Apple Intelligence ist nicht verfügbar."
            }
        }
    }

    func complete(system: String, prompt: String) async throws -> String {
        if let problem = Self.availabilityText { throw LLMError(message: problem) }
        let session = LanguageModelSession(instructions: system)
        return try await Self.translatingErrors {
            try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2)).content
        }
    }

    func completeNotes(system: String, prompt: String) async throws -> NotesDraft {
        if let problem = Self.availabilityText { throw LLMError(message: problem) }
        let session = LanguageModelSession(instructions: system)
        let notes = try await Self.translatingErrors {
            try await session.respond(to: prompt, generating: GeneratedNotes.self,
                                      options: GenerationOptions(temperature: 0.2)).content
        }
        return NotesDraft(kind: notes.kind,
                          title: GeneratedNotes.isEcho(notes.title, of: GeneratedNotes.titleGuide) ? "" : notes.title,
                          summary: GeneratedNotes.isEcho(notes.summary, of: GeneratedNotes.summaryGuide) ? "" : notes.summary,
                          topics: notes.topics.map { NotesDraft.Topic(heading: $0.heading, points: $0.points) },
                          decisions: notes.decisions, tasks: notes.tasks, openQuestions: notes.openQuestions)
    }

    private static func translatingErrors<T>(_ body: @escaping () async throws -> T) async throws -> T {
        do {
            // Ein einzelner Aufruf dauert normalerweise unter zwei Minuten. Hängt das Modell,
            // soll das nicht die ganze Warteschlange blockieren.
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await body() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 300_000_000_000)
                    throw LLMError(message: "Apple Intelligence hat nach 5 Minuten nicht geantwortet.")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw ContextWindowExceeded()
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            throw LLMError(message: "Apple Intelligence hat diese Aufnahme aus Sicherheitsgründen nicht zusammengefasst. "
                + "Wähle für solche Inhalte in den Einstellungen einen anderen KI-Anbieter.")
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw LLMError(message: "Apple Intelligence unterstützt die Sprache dieser Aufnahme nicht.")
        }
    }
}

/// Die Felder werden in dieser Reihenfolge erzeugt. Deshalb kommen Kurzfassung und Titel zuletzt:
/// Das Modell fasst erst zusammen, nachdem es den Inhalt durchgearbeitet hat.
/// Die Obergrenzen verhindern, dass das Modell in einer Schleife immer neue Einträge erzeugt.
@available(macOS 26.0, *)
@Generable
struct GeneratedNotes {
    @Guide(description: "Was für eine Aufnahme ist das tatsächlich, unabhängig von der gewählten Kategorie?",
           .anyOf(["Meeting oder Besprechung", "Gespräch oder Telefonat", "Interview", "Vorlesung oder Unterricht",
                   NotesDraft.passiveKind, "Sprachnotiz", "Sonstiges"]))
    var kind: String
    @Guide(description: "Die Themen, die tatsächlich vorkamen, in ihrer Reihenfolge", .maximumCount(10))
    var topics: [GeneratedTopic]
    @Guide(description: "Was ausdrücklich entschieden oder vereinbart wurde, je ein ganzer Satz. Leer, wenn nichts entschieden wurde.", .maximumCount(8))
    var decisions: [String]
    @Guide(description: "Aufgaben, die jemand ausdrücklich übernommen, zugesagt oder sich vorgenommen hat. Mit Person und Frist, wenn genannt. Leer, wenn es keine gibt.", .maximumCount(12))
    var tasks: [String]
    @Guide(description: "Fragen, die ausdrücklich offen geblieben sind. Leer, wenn es keine gibt.", .maximumCount(6))
    var openQuestions: [String]
    @Guide(description: GeneratedNotes.summaryGuide)
    var summary: String
    @Guide(description: GeneratedNotes.titleGuide)
    var title: String

    // Kleine Modelle schreiben die Beschreibung manchmal wörtlich ab – daran wird das erkannt.
    static let summaryGuide = "Zusammenfassung des Inhalts und des Ergebnisses in ein bis drei eigenen Sätzen"
    static let titleGuide = "Konkreter Titel, der den Inhalt benennt, höchstens 70 Zeichen, ohne Datum"

    static func isEcho(_ value: String, of guide: String) -> Bool {
        let v = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), g = guide.lowercased()
        return v.contains(String(g.prefix(25))) || (v.count >= 12 && g.contains(v))
    }
}

@available(macOS 26.0, *)
@Generable
struct GeneratedTopic {
    @Guide(description: "Kurze Überschrift des Themas")
    var heading: String
    @Guide(description: "Was dazu gesagt wurde, sinngemäß in ganzen Sätzen, mit Begründungen, Zahlen, Namen und Terminen", .maximumCount(8))
    var points: [String]
}
#endif
