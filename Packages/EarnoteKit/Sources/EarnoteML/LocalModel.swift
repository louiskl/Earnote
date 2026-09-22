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

    /// Das Modell, das die App gerade benutzt. Wird von der App aus den Einstellungen gesetzt.
    @Published public var selected: LocalModelInfo = LocalModelCatalog.standard {
        didSet {
            guard oldValue.id != selected.id else { return }
            Self.current = selected
            isInstalled = Self.isInstalled(selected)
            progress = 0
            // Das alte Modell hängt sonst im Speicher, obwohl ein anderes gefragt ist
            Task { await LocalLLMCache.shared.release() }
        }
    }

    /// Damit auch die nicht-isolierten Helfer wissen, um welches Modell es geht
    nonisolated(unsafe) public private(set) static var current: LocalModelInfo = LocalModelCatalog.standard

    @Published public private(set) var isInstalled = LocalModelManager.isInstalled(LocalModelCatalog.standard)
    @Published public private(set) var isDownloading = false
    @Published public private(set) var progress: Double = 0
    @Published public var lastError: String?

    private var downloadTask: Task<Void, Never>?

    /// Welche Modelle schon geladen sind – für die Auswahl in den Einstellungen
    public var installedModels: Set<String> {
        Set(LocalModelCatalog.all.filter { Self.isInstalled($0) }.map(\.id))
    }

    // MARK: Voraussetzungen

    nonisolated public static var memoryGB: Double { DeviceCapabilities.memoryGB }

    /// Apple Silicon mit mindestens 8 GB Arbeitsspeicher
    nonisolated public static var isSupported: Bool { DeviceCapabilities.supportsLocalModel }

    nonisolated public static var unsupportedReason: String? { DeviceCapabilities.localModelUnsupportedReason }

    nonisolated public static func folder(_ model: LocalModelInfo) -> URL {
        Storage.standard.modelsDir.appendingPathComponent("llm", isDirectory: true)
            .appendingPathComponent(model.id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// Ordner des gerade gewählten Modells
    nonisolated public static var folder: URL { folder(current) }

    /// Wird erst nach vollständigem Download geschrieben – ein abgebrochener Download gilt nicht als installiert.
    nonisolated private static func completeMarker(_ model: LocalModelInfo) -> URL {
        folder(model).appendingPathComponent(".complete")
    }
    nonisolated public static func isInstalled(_ model: LocalModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: completeMarker(model).path)
    }

    nonisolated public static var installed: Bool { isInstalled(current) }

    /// Liegen alle Dateien vollständig im Ordner? Prüft Konfiguration, Tokenizer und jede Gewichtsdatei,
    /// die im Index aufgeführt ist.
    nonisolated public static func filesComplete(_ model: LocalModelInfo) -> Bool {
        let fm = FileManager.default
        let folder = folder(model)
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

    nonisolated public static var filesComplete: Bool { filesComplete(current) }

    // MARK: Download

    public func download() { download(selected) }

    public func download(_ model: LocalModelInfo) {
        guard !isDownloading, !Self.isInstalled(model), Self.isSupported else { return }
        selected = model
        isDownloading = true
        progress = 0
        lastError = nil
        downloadTask = Task {
            defer { isDownloading = false; downloadTask = nil }
            // Ohne Netz hängt der Download sonst minutenlang, ohne etwas zu sagen
            guard await Reachability.isOnline() else {
                lastError = Reachability.offlineMessage
                Log.error("Lokales Modell: keine Internetverbindung")
                return
            }
            if let tooLittle = DiskSpace.blocksDownload(ofGigabytes: model.sizeGB,
                                                        availableBytes: Storage.standard.availableBytes) {
                lastError = tooLittle
                Log.error("Lokales Modell: zu wenig Speicherplatz für \(model.sizeText)")
                return
            }
            do {
                guard let repo = Repo.ID(rawValue: model.id) else { return }
                let folder = Self.folder(model)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if !Self.filesComplete(model) {
                    // Kein zusätzlicher Cache: die Dateien liegen genau einmal im App-Ordner
                    let client = HubClient(cache: nil)
                    do {
                        _ = try await client.downloadSnapshot(
                            of: repo, to: folder,
                            matching: ["*.json", "*.safetensors", "*.jinja", "*.txt"],
                            progressHandler: { [weak self] p in self?.progress = p.fractionCompleted })
                    } catch HubCacheError.snapshotRequiresCacheOrDestination(_) where Self.filesComplete(model) {
                        // swift-huggingface 0.10 meldet ohne Cache ganz am Ende diesen Fehler, obwohl alle
                        // Dateien fertig im Zielordner liegen. Maßgeblich ist, was tatsächlich angekommen ist.
                    }
                }
                try Task.checkCancellation()
                guard Self.filesComplete(model) else {
                    throw LLMError(message: "Das Modell wurde nicht vollständig geladen. Bitte erneut versuchen.")
                }
                try Data().write(to: Self.completeMarker(model))
                isInstalled = Self.isInstalled(selected)
                progress = 1
                Log.info("Lokales Modell geladen: \(model.id) (\(model.sizeText))")
            } catch is CancellationError {
                Log.info("Download des lokalen Modells abgebrochen")
            } catch {
                // Der technische Wortlaut gehört ins Protokoll, nicht in die Oberfläche
                lastError = String(localized: "Der Download ist fehlgeschlagen. Prüfe die Internetverbindung und versuch es noch einmal.")
                Log.error("Lokales Modell: \(error.localizedDescription)")
            }
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    public func delete() { delete(selected) }

    public func delete(_ model: LocalModelInfo) {
        cancelDownload()
        Task { await LocalLLMCache.shared.release() }
        try? FileManager.default.removeItem(at: Self.folder(model))
        isInstalled = Self.isInstalled(selected)
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
