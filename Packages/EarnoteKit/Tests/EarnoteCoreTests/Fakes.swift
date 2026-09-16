import AVFoundation
import Foundation
import XCTest
@testable import EarnoteCore

/// Thread-sicherer Behälter für Zustand, den Fakes aus beliebigen Tasks ändern.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func mutate<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

// MARK: - KI

struct LLMCall: Sendable { var system: String; var prompt: String }

/// Antwortet über eine Funktion und merkt sich alle Aufrufe.
final class FakeLLMClient: LLMClient, @unchecked Sendable {
    let calls = Locked<[LLMCall]>([])
    private let respond: @Sendable (LLMCall, Int) async throws -> String

    init(_ respond: @escaping @Sendable (LLMCall, Int) async throws -> String) {
        self.respond = respond
    }

    convenience init(answer: String) { self.init { _, _ in answer } }

    func complete(system: String, prompt: String) async throws -> String {
        let call = LLMCall(system: system, prompt: prompt)
        let index = calls.mutate { $0.append(call); return $0.count - 1 }
        return try await respond(call, index)
    }

    /// Verdichtungsaufrufe erkennt man am System-Prompt für Arbeitsnotizen.
    static func isCondense(_ call: LLMCall) -> Bool { call.system.contains("Arbeitsnotizen") }
}

struct FakeLLMProvider: LLMClientProvider {
    let client: any LLMClient
    func makeClient(for config: AIConfig) throws -> (any LLMClient)? { client }
}

// MARK: - Transkription

final class FakeTranscriber: Transcriber, TranscriberProvider, @unchecked Sendable {
    let engineName = "Fake"
    /// IDs der Audiodateien (Ordnername = Aufnahme-ID) in Aufrufreihenfolge
    let transcribed = Locked<[String]>([])
    private let result: @Sendable (URL) async throws -> [TranscriptSegment]

    init(_ result: @escaping @Sendable (URL) async throws -> [TranscriptSegment] = { _ in FakeTranscriber.speech }) {
        self.result = result
    }

    static let speech = [TranscriptSegment(start: 0, end: 2, text: "Wir treffen uns am Montag.")]

    func makeTranscriber(for settings: AppSettings) async throws -> any Transcriber { self }

    func transcribe(audio url: URL, language: String,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        transcribed.mutate { $0.append(url.deletingLastPathComponent().lastPathComponent) }
        let segments = try await result(url)
        progress(1)
        return segments
    }
}

// MARK: - Export

final class FakeDestination: Destination, @unchecked Sendable {
    let exports = Locked(0)
    private let behavior: @Sendable () throws -> String?

    init(_ behavior: @escaping @Sendable () throws -> String? = { "fake://ok" }) {
        self.behavior = behavior
    }

    func export(_ payload: ExportPayload) async throws -> String? {
        exports.mutate { $0 += 1 }
        return try behavior()
    }
}

struct FakeDestinations: DestinationProvider {
    let destinations: [String: FakeDestination]

    var all: [DestinationInfo] {
        destinations.keys.sorted().map { DestinationInfo(id: $0, name: $0.capitalized, symbol: "", detail: "") }
    }
    func make(_ id: String) -> (any Destination)? { destinations[id] }
    func setupProblem(_ id: String, _ settings: DestinationSettings) -> String? { nil }
}

// MARK: - Umgebung

/// Temporärer Datenordner mit Repository; wird nach dem Test gelöscht.
final class TestFolder {
    let root: URL
    let repository: FileRecordingRepository

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repository = FileRecordingRepository(storage: Storage(root: root))
        Log.url = root.appendingPathComponent("test.log")
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Legt eine importierte Aufnahme mit echter Audiodatei an (laut oder stumm).
    func importedRecording(silent: Bool = false, title: String = "Import") throws -> Recording {
        let source = root.appendingPathComponent("\(UUID().uuidString).wav")
        try Self.writeAudio(to: source, amplitude: silent ? 0 : 0.5)
        var rec = Recording(title: title, status: .queued)
        rec.importedFileName = try repository.importAudio(from: source, for: rec.id)
        rec.endedAt = rec.startedAt.addingTimeInterval(1)
        repository.insert(rec)
        return rec
    }

    /// Eine Sekunde Sinuston (oder Stille) als 16-kHz-WAV
    static func writeAudio(to url: URL, amplitude: Float, seconds: Double = 1) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 2 * .pi * 440 / 16_000)
        }
        try file.write(from: buffer)
    }
}

/// Aufnahme-Zustand für Pipeline-Tests ohne Warteschlange: Änderungen werden wie in der App gespeichert.
final class RecordingState: @unchecked Sendable {
    let current: Locked<Recording?>
    let statuses = Locked<[RecordingStatus]>([])
    private let repository: FileRecordingRepository

    init(_ recording: Recording, repository: FileRecordingRepository) {
        current = Locked(recording)
        self.repository = repository
    }

    var recording: Recording { current.get()! }

    var events: ProcessingEvents {
        ProcessingEvents(
            recording: { [self] _ in current.get() },
            update: { [self] _, change in
                let updated: Recording? = current.mutate { value in
                    guard var r = value else { return nil }
                    change(&r)
                    value = r
                    return r
                }
                if let updated {
                    statuses.mutate { if $0.last != updated.status { $0.append(updated.status) } }
                    repository.update(updated)
                }
            },
            progress: { _, _ in })
    }
}

/// Bibliothek für Warteschlangen-Tests (entspricht dem LibraryStore der App)
@MainActor
final class TestLibrary: RecordingLibrary {
    var recordings: [Recording]
    var settings: AppSettings
    let repository: FileRecordingRepository

    init(repository: FileRecordingRepository, settings: AppSettings) {
        self.repository = repository
        self.settings = settings
        recordings = repository.loadRecordings().sorted { $0.startedAt > $1.startedAt }
    }

    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func category(_ id: UUID?) -> RecordingCategory? { nil }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        repository.update(recordings[i])
    }

    func setProgressInMemory(_ id: UUID, _ progress: Double) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].progress = progress
    }

    func delete(_ id: UUID, queue: ProcessingQueue) {
        queue.remove(id)
        repository.delete(id)
        recordings.removeAll { $0.id == id }
    }
}

extension AppSettings {
    /// Lokale KI (Fake) und ein einzelnes Exportziel
    static func testing(destinations: Set<String> = ["a"]) -> AppSettings {
        var s = AppSettings()
        s.ai.provider = .localModel
        s.destinations.enabled = destinations
        return s
    }
}

extension XCTestCase {
    /// Wartet, bis die Bedingung erfüllt ist (höchstens `timeout` Sekunden).
    @MainActor
    func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool,
                   file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Zeitüberschreitung beim Warten", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
