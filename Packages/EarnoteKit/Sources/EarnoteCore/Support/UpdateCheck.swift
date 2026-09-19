import Foundation

/// Eine veröffentlichte Version auf GitHub
public struct AppRelease: Sendable, Equatable {
    public let version: String
    /// Seite der Version (dort liegt auch die DMG)
    public let page: URL
    /// Direkter Link auf die DMG, falls vorhanden
    public let download: URL?

    public init(version: String, page: URL, download: URL?) {
        self.version = version
        self.page = page
        self.download = download
    }
}

/// Sucht nach einer neueren Version. Bewusst schlicht: ein Aufruf der GitHub-API, ein Vergleich,
/// ein Hinweis mit Link. Automatisch installieren (Sparkle) lohnt sich erst mit vielen Nutzern.
public enum UpdateCheck {
    /// Antwortteile, die uns interessieren
    private struct Response: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    /// Neueste Version im Repository (nil = keine veröffentlicht)
    public static func latest(repository: URL, session: URLSession = .shared) async throws -> AppRelease? {
        let path = repository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "https://api.github.com/repos/\(path)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return release(from: data)
    }

    /// Antwort auswerten – getrennt, damit es ohne Netz prüfbar ist.
    public static func release(from data: Data) -> AppRelease? {
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              parsed.draft != true, parsed.prerelease != true else { return nil }
        let dmg = parsed.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AppRelease(version: normalized(parsed.tag_name), page: parsed.html_url, download: dmg?.browser_download_url)
    }

    /// „v0.9.0“ und „0.9.0“ sind dieselbe Version.
    public static func normalized(_ version: String) -> String {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        return text
    }

    /// Vergleicht Versionen stellenweise: 0.10.0 ist neuer als 0.9.9, 0.8.1 ist nicht neuer als 0.8.1.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        normalized(version).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
