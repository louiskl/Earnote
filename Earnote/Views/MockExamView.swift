import EarnoteCore
import SwiftUI

/// Probeklausur je Fach – am Mac als Blatt über dem Hauptfenster, am iPhone/iPad als Seite im Stapel.
/// Ein Form mit allen Fragen statt eines eigenen Assistenten: blättern, zurückspringen und Diktieren kommen vom System.
struct MockExamView: View {
    let categoryID: UUID
    /// Vor dem Start gefragt (iPhone: Pro-Versuch verbrauchen). false = nicht starten.
    var allowStart: () -> Bool = { true }
    /// Notiz zeigen (Mac: im Hauptfenster). nil = am iPhone im Stapel öffnen.
    var onOpen: ((UUID) -> Void)?

    @Environment(LibraryStore.self) private var library

    private enum Phase: Equatable {
        case intro, asking, answering, grading(done: Int), result, failed(String)
    }

    @State private var phase: Phase = .intro
    @State private var sourceCount = 0
    @State private var loaded = false
    @State private var sources: [MockExam.Source] = []
    @State private var questions: [MockExam.Question] = []
    @State private var answers: [String] = []
    @State private var grades: [MockExam.Grade] = []
    @State private var viaGoogle = false
    @State private var providerName = ""
    @State private var savedID: UUID?
    @State private var work: Task<Void, Never>?
    #if os(iOS)
    @State private var opened: OpenedNote?
    #endif

    private var categoryName: String { library.category(categoryID)?.name ?? "" }
    private var language: String { library.settings.ai.summaryLanguage }
    private var total: Int { grades.reduce(0) { $0 + $1.points } }

    var body: some View {
        content
            .navigationTitle("Probeklausur")
            #if os(iOS)
            .navigationSubtitle(categoryName)
            .navigationDestination(item: $opened) { RecordingDetailView(id: $0.id) }
            #endif
            .toolbar { toolbar }
            .task {
                sourceCount = await library.mockExamSources(categoryID).count
                loaded = true
                #if DEBUG
                // Nur Debug, für Prüfungen ohne Klicks: `EARNOTE_DEMO_EXAM_AUTO=1` startet, beantwortet die erste Hälfte
                // der Fragen mit der Frage selbst (damit es etwas zu korrigieren gibt), gibt ab und sichert
                if ProcessInfo.processInfo.environment["EARNOTE_DEMO_EXAM_AUTO"] != nil { start() }
                #endif
            }
            #if DEBUG
            .onChange(of: phase) { _, new in
                guard ProcessInfo.processInfo.environment["EARNOTE_DEMO_EXAM_AUTO"] != nil else { return }
                if new == .result { save(); return }
                guard new == .answering else { return }
                for i in answers.indices where i < answers.count / 2 { answers[i] = questions[i].text }
                Task { try? await Task.sleep(for: .seconds(3)); submit() }
            }
            #endif
            .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .intro: intro
        case .asking:
            ProgressView("Earnote stellt die Fragen …").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .answering: answering
        case .grading(let done):
            ProgressView(value: Double(done), total: Double(max(1, questions.count))) {
                Text("Earnote korrigiert … \(done) von \(questions.count)")
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result: result
        case .failed(let message):
            ContentUnavailableView {
                Label("Das hat nicht geklappt", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Noch einmal") { start() }
            }
        }
    }

    // MARK: Phasen

    @ViewBuilder private var intro: some View {
        if loaded && sourceCount == 0 {
            ContentUnavailableView {
                Label("Noch keine Vorlesungen", systemImage: "graduationcap")
            } description: {
                Text("Sobald es in „\(categoryName)“ fertige Notizen gibt, stellt Earnote daraus eine Probeklausur zusammen.")
            }
        } else {
            Form {
                Section {
                    Text("Earnote stellt \(MockExam.defaultCount) Fragen aus deinen Notizen in „\(categoryName)“ – was als prüfungsrelevant gilt, zuerst. Du antwortest in eigenen Worten, danach korrigiert die KI und sagt dir, in welcher Vorlesung die Antwort steht.")
                    LabeledContent("Vorlesungen", value: "\(sourceCount)")
                }
                Section {
                    Button("Probeklausur starten") { start() }
                        .disabled(!loaded)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var answering: some View {
        Form {
            ForEach(questions.indices, id: \.self) { index in
                Section {
                    Text(questions[index].text)
                    TextField("Deine Antwort", text: $answers[index], axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text(header(index))
                }
            }
            if viaGoogle {
                Section {} footer: {
                    Text("Fragen und Korrektur über Google (dein Schlüssel) – die KI auf diesem Gerät ist für eine Klausur zu klein.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var result: some View {
        Form {
            Section {
                LabeledContent("Ergebnis", value: String(localized: "\(total) von \(questions.count * MockExam.maxPoints) Punkten"))
                ProgressView(value: Double(total), total: Double(max(1, questions.count * MockExam.maxPoints)))
            }
            ForEach(questions.indices, id: \.self) { index in
                Section {
                    Text(questions[index].text).bold()
                    let answer = answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(answer.isEmpty ? String(localized: "Keine Antwort") : answer)
                        .foregroundStyle(.secondary)
                    if index < grades.count {
                        gradeLabel(grades[index])
                        Text(grades[index].feedback)
                    }
                    if let s = questions[index].source, s < sources.count {
                        Button("Steht in: \(sources[s].title)", systemImage: "doc.text") { open(sources[s].recordingID) }
                    }
                } header: {
                    Text(header(index))
                }
            }
            Section {
                Button("Neue Probeklausur", systemImage: "arrow.clockwise") { start() }
            }
        }
        .formStyle(.grouped)
    }

    private func gradeLabel(_ grade: MockExam.Grade) -> some View {
        let symbol = grade.points == MockExam.maxPoints ? "checkmark.circle.fill"
            : grade.points > 0 ? "circle.lefthalf.filled" : "xmark.circle.fill"
        let color: Color = grade.points == MockExam.maxPoints ? .green : grade.points > 0 ? .orange : .red
        return Label("\(grade.points) von \(MockExam.maxPoints) Punkten", systemImage: symbol)
            .foregroundStyle(color)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch phase {
        case .answering:
            ToolbarItem(placement: .confirmationAction) {
                Button("Abgeben") { submit() }
            }
        case .result:
            ToolbarItem(placement: .confirmationAction) {
                Button(savedID == nil ? "Als Notiz sichern" : "Gesichert") { save() }
                    .disabled(savedID != nil)
            }
        default:
            ToolbarItem(placement: .primaryAction) { EmptyView() }
        }
    }

    private func header(_ index: Int) -> String {
        let kind = questions[index].kind
        return kind.isEmpty ? String(localized: "Frage \(index + 1)") : String(localized: "Frage \(index + 1) · \(kind)")
    }

    // MARK: Ablauf

    private func start() {
        guard allowStart() else { return }
        work?.cancel()
        savedID = nil
        grades = []
        phase = .asking
        work = Task {
            do {
                guard let ai = try library.mockExamAI() else {
                    phase = .failed(String(localized: "Für eine Probeklausur braucht es eine KI. Wähle in den Einstellungen unter „KI“ eine aus."))
                    return
                }
                viaGoogle = ai.viaGoogle
                providerName = ai.viaGoogle ? AIProviderKind.gemini.label : library.settings.ai.provider.label
                let all = await library.mockExamSources(categoryID)
                let (found, used) = try await MockExam.questions(client: ai.client, sources: all, language: language,
                                                                 limit: ai.limit)
                try Task.checkCancellation()
                guard !found.isEmpty else {
                    phase = .failed(String(localized: "Die KI hat keine Fragen geliefert. Versuch es noch einmal."))
                    return
                }
                sources = used
                questions = found
                answers = Array(repeating: "", count: found.count)
                phase = .answering
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func submit() {
        phase = .grading(done: 0)
        work = Task {
            do {
                guard let ai = try library.mockExamAI() else { return }
                var result: [MockExam.Grade] = []
                for (index, question) in questions.enumerated() {
                    let source = question.source.flatMap { $0 < sources.count ? sources[$0] : nil }
                    result.append(try await MockExam.grade(client: ai.client, question: question, answer: answers[index],
                                                           source: source, language: language, limit: ai.limit))
                    try Task.checkCancellation()
                    phase = .grading(done: index + 1)
                }
                grades = result
                phase = .result
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        let title = String(localized: "Probeklausur – \(categoryName)")
        let markdown = MockExam.markdown(title: title, date: Date(), questions: questions, answers: answers,
                                         grades: grades, sources: sources)
        savedID = library.saveMockExam(categoryID: categoryID, title: title, markdown: markdown, provider: providerName)
    }

    private func open(_ id: UUID) {
        if let onOpen { onOpen(id); return }
        #if os(iOS)
        opened = OpenedNote(id: id)
        #endif
    }
}

#if os(iOS)
/// Notiz, die aus dem Ergebnis heraus geöffnet wird
private struct OpenedNote: Identifiable, Hashable { let id: UUID }
#endif
