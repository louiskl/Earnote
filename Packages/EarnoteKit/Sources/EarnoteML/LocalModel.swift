import EarnoteCore
import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: - Verwaltung

/// Das eingebaute lokale Sprachmodell: läuft komplett auf dem Mac (Apple Silicon, MLX).
/// Einmal laden, danach funktioniert es ohne Konto, ohne Kosten und ohne Internet –
/// und kein Wort aus dem Meeting verlässt das Gerät.
@MainActor
public final class LocalModelManager: ObservableObject {
    public static let shared = LocalModelManager()

    public struct ModelInfo: Sendable {
        public let repository: String
        public let name: String
        public let sizeText: String
    }

    /// Qwen3 4B (Instruct 2507, 4 Bit): gutes Deutsch, hält sich an Vorgaben, verarbeitet lange Transkripte am Stück.
    public static let standard = ModelInfo(repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                                    name: "Qwen3 4B", sizeText: "2,3 GB")

    @Published public private(set) var isInstalled = LocalModelManager.installed
    @Published public private(set) var isDownloading = false
    @Published public private(set) var progress: Double = 0
    @Published public var lastError: String?

    private var downloadTask: Task<Void, Never>?

    // MARK: Voraussetzungen

    nonisolated public static var memoryGB: Double { DeviceCapabilities.memoryGB }

    /// Apple Silicon mit mindestens 8 GB Arbeitsspeicher
    nonisolated public static var isSupported: Bool { DeviceCapabilities.supportsLocalModel }

    nonisolated public static var unsupportedReason: String? { DeviceCapabilities.localModelUnsupportedReason }

    nonisolated public static var folder: URL {
        Storage.standard.modelsDir.appendingPathComponent("llm", isDirectory: true)
            .appendingPathComponent(standard.repository.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// Wird erst nach vollständigem Download geschrieben – ein abgebrochener Download gilt nicht als installiert.
    nonisolated private static var completeMarker: URL { folder.appendingPathComponent(".complete") }
    /// Name der Markierung vor der Umbenennung der App (wird bei der Datenübernahme umbenannt)
    nonisolated private static var legacyCompleteMarker: URL { folder.appendingPathComponent(".earmark-complete") }

    nonisolated public static var installed: Bool {
        FileManager.default.fileExists(atPath: completeMarker.path)
            || FileManager.default.fileExists(atPath: legacyCompleteMarker.path)
    }

    /// Liegen alle Dateien vollständig im Ordner? Prüft Konfiguration, Tokenizer und jede Gewichtsdatei,
    /// die im Index aufgeführt ist.
    nonisolated public static var filesComplete: Bool {
        let fm = FileManager.default
        for name in ["config.json", "tokenizer.json", "tokenizer_config.json"]
        where !fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
            return false
        }
        let index = folder.appendingPathComponent("model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let map = json["weight_map"] as? [String: String] {
            return Set(map.values).allSatisfy { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
        return fm.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path)
    }

    // MARK: Download

    public func download() {
        guard !isDownloading, !isInstalled, Self.isSupported else { return }
        isDownloading = true
        progress = 0
        lastError = nil
        downloadTask = Task {
            defer { isDownloading = false; downloadTask = nil }
            do {
                guard let repo = Repo.ID(rawValue: Self.standard.repository) else { return }
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                if !Self.filesComplete {
                    // Kein zusätzlicher Cache: die Dateien liegen genau einmal im App-Ordner
                    let client = HubClient(cache: nil)
                    do {
                        _ = try await client.downloadSnapshot(
                            of: repo, to: Self.folder,
                            matching: ["*.json", "*.safetensors", "*.jinja", "*.txt"],
                            progressHandler: { [weak self] p in self?.progress = p.fractionCompleted })
                    } catch HubCacheError.snapshotRequiresCacheOrDestination(_) where Self.filesComplete {
                        // swift-huggingface 0.10 meldet ohne Cache ganz am Ende diesen Fehler, obwohl alle
                        // Dateien fertig im Zielordner liegen. Maßgeblich ist, was tatsächlich angekommen ist.
                    }
                }
                try Task.checkCancellation()
                guard Self.filesComplete else {
                    throw LLMError(message: "Das Modell wurde nicht vollständig geladen. Bitte erneut versuchen.")
                }
                try Data().write(to: Self.completeMarker)
                isInstalled = true
                progress = 1
                Log.info("Lokales Modell geladen: \(Self.standard.repository)")
            } catch is CancellationError {
                Log.info("Download des lokalen Modells abgebrochen")
            } catch {
                lastError = "Download fehlgeschlagen: \(error.localizedDescription)"
                Log.error("Lokales Modell: \(error.localizedDescription)")
            }
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    public func delete() {
        cancelDownload()
        Task { await LocalLLMCache.shared.release() }
        try? FileManager.default.removeItem(at: Self.folder)
        isInstalled = false
        progress = 0
    }

    /// Wartet auf einen laufenden Download (z. B. wenn eine Aufnahme fertig ist, während das Modell noch lädt).
    public func waitForDownload() async {
        while isDownloading {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Modell im Speicher

/// Hält das geladene Modell, solange Aufnahmen verarbeitet werden, und gibt den Speicher danach frei.
public actor LocalLLMCache {
    public static let shared = LocalLLMCache()
    private var container: ModelContainer?

    public func container() async throws -> ModelContainer {
        if let container { return container }
        let started = Date()
        let loaded = try await LLMModelFactory.shared.loadContainer(from: LocalModelManager.folder,
                                                                     using: TransformersTokenizerLoader())
        container = loaded
        Log.info(String(format: "Lokales Modell in den Speicher geladen (%.0f s)", Date().timeIntervalSince(started)))
        return loaded
    }

    public func release() {
        container = nil
    }
}

// MARK: - Client

public struct LocalLLMClient: LLMClient {
    public init() {}

    public func complete(system: String, prompt: String) async throws -> String {
        if let reason = LocalModelManager.unsupportedReason { throw LLMError(message: reason) }
        if !LocalModelManager.installed {
            await LocalModelManager.shared.waitForDownload()
            guard LocalModelManager.installed else {
                throw LLMError(message: "Das lokale Modell ist noch nicht geladen. "
                    + "Öffne die Einstellungen unter „KI“ und klicke auf „Laden“.")
            }
        }
        let container = try await LocalLLMCache.shared.container()
        let session = ChatSession(container, instructions: system,
                                  generateParameters: GenerateParameters(maxTokens: 4_000, temperature: 0.3, topP: 0.9))
        let started = Date()
        let answer = try await session.respond(to: prompt)
        let seconds = Date().timeIntervalSince(started)
        Log.info(String(format: "Lokale KI: %d Zeichen hinein, %d heraus, %.0f s", prompt.count, answer.count, seconds))
        return answer.removingThinkBlocks
    }
}

// MARK: - Tokenizer-Anbindung
//
// mlx-swift-lm kennt Tokenizer nur über ein Protokoll. Diese kleine Brücke verbindet es mit swift-transformers –
// genau das, was sonst die MLXHuggingFace-Makros erzeugen würden (die man in Xcode erst freischalten müsste).

struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
