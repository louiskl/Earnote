import EarnoteCore
import Foundation
import WhisperKit

/// Verwaltet die Whisper-Modelle (Download, Auswahl).
@MainActor
public final class WhisperModelManager: ObservableObject {
    public static let shared = WhisperModelManager()

    public struct ModelInfo: Identifiable, Hashable, Sendable {
        public let id: String
        public var title: String
        public var detail: String
    }

    /// Kuratierte Auswahl – die tatsächlich verfügbaren Namen werden online abgeglichen.
    public static let curated: [ModelInfo] = [
        ModelInfo(id: "large-v3-v20240930_turbo", title: "Large v3 Turbo", detail: "Beste Qualität, schnell · ca. 1,6 GB · empfohlen"),
        ModelInfo(id: "large-v3-v20240930_626MB", title: "Large v3 Turbo (komprimiert)", detail: "Sehr gut, weniger Speicher · ca. 0,6 GB"),
        ModelInfo(id: "small", title: "Small", detail: "Schnell, gute Qualität · ca. 0,5 GB"),
        ModelInfo(id: "base", title: "Base", detail: "Sehr schnell, einfache Qualität · ca. 0,15 GB"),
    ]

    @Published public var downloading: String?
    @Published public var downloadProgress: Double = 0
    @Published public var lastError: String?
    @Published public private(set) var installed: [String: URL] = [:]
    @Published public var available: [String] = []
    /// Modell, das gerade für den Chip vorbereitet wird
    @Published public var preparing: String?
    /// Modelle, die schon für diesen Mac vorbereitet sind
    @Published public private(set) var prepared: Set<String> = []

    private let repo = "argmaxinc/whisperkit-coreml"
    private var installedKey = "whisper.installed"
    private var preparedKey = "whisper.prepared"

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: installedKey) as? [String: String] {
            installed = saved.compactMapValues { path in
                FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
            }
        }
        prepared = Set(UserDefaults.standard.stringArray(forKey: preparedKey) ?? []).intersection(installed.keys)
    }

    public var recommendedModel: String {
        let rec = WhisperKit.recommendedModels().default
        return rec.isEmpty ? Self.curated[0].id : rec
    }

    public func installedFolder(for model: String) -> (model: String, folder: URL)? {
        let available = installed.filter { FileManager.default.fileExists(atPath: $0.value.path) }
        if let url = available[model] { return (model, url) }
        guard let fallback = available.keys.sorted().first, let folder = available[fallback] else { return nil }
        Log.info("Whisper-Modell „\(model)“ fehlt; verwende installiertes Modell „\(fallback)“.")
        return (fallback, folder)
    }

    public func refreshAvailable() async {
        do {
            available = try await WhisperKit.fetchAvailableModels(from: repo)
        } catch {
            Log.error("Modellliste: \(error.localizedDescription)")
        }
    }

    /// Zu einer Kurz-ID den vollen Modellnamen im Repository finden.
    public func resolve(_ model: String) -> String {
        if available.contains(model) { return model }
        return available.first { $0.hasSuffix(model) } ?? model
    }

    public func download(_ model: String) async -> Bool {
        downloading = model
        downloadProgress = 0
        lastError = nil
        defer { downloading = nil }
        if available.isEmpty { await refreshAvailable() }
        do {
            let variant = resolve(model)
            let folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: Storage.standard.modelsDir,
                from: repo,
                progressCallback: { progress in
                    Task { @MainActor in self.downloadProgress = progress.fractionCompleted }
                })
            installed[model] = folder
            UserDefaults.standard.set(installed.mapValues(\.path), forKey: installedKey)
            Log.info("Whisper-Modell geladen: \(variant) → \(folder.path)")
            return true
        } catch {
            lastError = "Download fehlgeschlagen: \(error.localizedDescription)"
            Log.error(lastError!)
            return false
        }
    }

    /// Lädt das Modell einmal vollständig, damit macOS es für den Chip übersetzt. Das passiert sonst
    /// unsichtbar bei der ersten Transkription und dauert auf älteren Macs viele Minuten.
    /// Danach wird der Speicher wieder freigegeben – die Übersetzung bleibt auf der Festplatte.
    @discardableResult
    public func prepare(_ model: String) async -> Bool {
        guard preparing == nil, let installed = installedFolder(for: model), installed.model == model else { return false }
        preparing = model
        lastError = nil
        defer { preparing = nil }
        do {
            _ = try await WhisperKitCache.shared.kit(for: installed.folder)
            await WhisperKitCache.shared.release()
            prepared.insert(model)
            UserDefaults.standard.set(Array(prepared), forKey: preparedKey)
            Log.info("Whisper-Modell vorbereitet: \(model)")
            return true
        } catch {
            lastError = "Das Modell konnte nicht vorbereitet werden: \(error.localizedDescription)"
            Log.error(lastError!)
            return false
        }
    }

    public func delete(_ model: String) {
        guard let url = installed[model] else { return }
        Task { await WhisperKitCache.shared.release() }
        try? FileManager.default.removeItem(at: url)
        installed[model] = nil
        prepared.remove(model)
        UserDefaults.standard.set(installed.mapValues(\.path), forKey: installedKey)
        UserDefaults.standard.set(Array(prepared), forKey: preparedKey)
    }
}

/// Hält das geladene Whisper-Modell zwischen den Aufnahmen einer Warteschlange im Speicher.
/// Das Laden dauert – beim allerersten Mal mehrere Minuten, weil macOS das Modell für den Chip optimiert.
public actor WhisperKitCache {
    public static let shared = WhisperKitCache()
    private var folder: URL?
    private var kit: WhisperKit?

    public func kit(for folder: URL) async throws -> WhisperKit {
        if let kit, self.folder == folder { return kit }
        kit = nil
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, prewarm: false, load: true, download: false)
        let loaded = try await WhisperKit(config)
        kit = loaded
        self.folder = folder
        return loaded
    }

    /// Speicher freigeben, wenn nichts mehr zu tun ist.
    public func release() {
        kit = nil
        folder = nil
    }
}
