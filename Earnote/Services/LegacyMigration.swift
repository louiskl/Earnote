import Foundation
import Security

/// Übernimmt Daten aus der Zeit, als die App „Earmark“ hieß, vor jeder Initialisierung von Storage,
/// Log, AppState und Modell-Verwaltungen. Kann nach dem öffentlichen Launch plus einigen Versionen
/// entfernt werden. Alte Schlüsselbund-Einträge bleiben als Rückfallmöglichkeit erhalten.
enum LegacyMigration {
    private static let versionKey = "legacyMigrationVersion"

    static func runIfNeeded() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let old = UserDefaults(suiteName: AppInfo.legacyBundleIdentifier)?
            .persistentDomain(forName: AppInfo.legacyBundleIdentifier) ?? [:]
        run(defaults: .standard, legacyValues: old, supportBase: base, documents: documents,
            migrateSecrets: { migrateKeychain(&$0) }) { message in
            // Kein Log/Storage-Zugriff: Bei einem fehlgeschlagenen Umzug darf hier kein neuer
            // Zielordner entstehen, der den nächsten Versuch blockiert.
            let new = base.appendingPathComponent(AppInfo.supportFolderName)
            let legacy = base.appendingPathComponent(AppInfo.legacySupportFolderName)
            let folder = fm.fileExists(atPath: new.path) ? new : legacy
            guard fm.fileExists(atPath: folder.path) else { return }
            let url = folder.appendingPathComponent(AppInfo.logFileName)
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] INFO: \(message)\n"
            do {
                let data = Data(line.utf8)
                if fm.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch { NSLog("Datenübernahme: Protokoll konnte nicht geschrieben werden: %@", error.localizedDescription) }
        }
    }

    /// Getrennte Eingaben erlauben Tests in temporären Ordnern, ohne Nutzerdaten oder Schlüssel anzufassen.
    static func run(defaults: UserDefaults, legacyValues: [String: Any], supportBase: URL,
                    documents: URL, migrateSecrets: (inout [String]) -> Bool, log: (String) -> Void) {
        guard defaults.integer(forKey: versionKey) < 1 else { return }
        let fm = FileManager.default
        let old = supportBase.appendingPathComponent(AppInfo.legacySupportFolderName, isDirectory: true)
        let new = supportBase.appendingPathComponent(AppInfo.supportFolderName, isDirectory: true)
        var report: [String] = []
        var complete = true
        var rewritePaths = false
        if fm.fileExists(atPath: old.path) {
            if fm.fileExists(atPath: new.path) {
                report.append("Datenordner übersprungen (beide Ordner vorhanden; nichts überschrieben)")
            } else {
                do {
                    try fm.moveItem(at: old, to: new) // Modelle sind mehrere GB groß: niemals kopieren.
                    rewritePaths = true
                    report.append("Datenordner verschoben")
                } catch {
                    complete = false
                    report.append("Datenordner nicht verschoben: \(error.localizedDescription)")
                }
            }
        } else {
            // Auch einen unterbrochenen Lauf nach dem Verschieben sicher fortsetzen.
            rewritePaths = fm.fileExists(atPath: new.path)
        }
        if rewritePaths {
            complete = renameLegacyFiles(in: new, report: &report) && complete
        }

        // Alle persistenten App-Schlüssel, einschließlich Fensterzuständen. Explizite neue Werte gewinnen.
        // Ermittelt im Code: settings, categories, whisper.installed und systemAudioRequested.
        var copied = 0, skipped = 0
        for (key, value) in legacyValues where key != versionKey {
            if defaults.object(forKey: key) == nil {
                // Eine Anfrage unter der alten Bundle-ID ist keine Freigabe für die neue App.
                defaults.set(key == "systemAudioRequested" ? false : value, forKey: key)
                copied += 1
            } else { skipped += 1 }
        }
        if !legacyValues.isEmpty { report.append("Einstellungen: \(copied) übernommen, \(skipped) bereits vorhanden") }
        if rewritePaths {
            let oldPath = old.path, newPath = new.path
            if let installed = defaults.dictionary(forKey: "whisper.installed") {
                defaults.set(rewrite(installed, from: oldPath, to: newPath), forKey: "whisper.installed")
            }
            // settings enthält u. a. Exportpfade als JSON. Nur Pfade innerhalb des verschobenen
            // Support-Ordners ändern; externe Vaults/Markdown-Ordner und unbekannte Felder erhalten.
            if let data = defaults.data(forKey: "settings") {
                do {
                    let json = try JSONSerialization.jsonObject(with: data)
                    let updated = rewrite(json, from: oldPath, to: newPath)
                    defaults.set(try JSONSerialization.data(withJSONObject: updated), forKey: "settings")
                } catch {
                    complete = false
                    report.append("Einstellungspfade nicht angepasst: \(error.localizedDescription)")
                }
            }
            report.append("Pfade im verschobenen Datenordner angepasst")
        }
        complete = keepMarkdownFolder(defaults: defaults, documents: documents, report: &report) && complete
        complete = migrateSecrets(&report) && complete
        if complete { defaults.set(1, forKey: versionKey) }
        report.append(complete ? "abgeschlossen (Version 1)" : "unvollständig; nächster Start versucht offene Schritte erneut")
        // Neuinstallation: keine Ordner anlegen; lediglich das Versionsflag speichern.
        log("Übernahme aus „\(AppInfo.legacySupportFolderName)“: " + report.joined(separator: "; "))
    }

    private static func renameLegacyFiles(in root: URL, report: inout [String]) -> Bool {
        let fm = FileManager.default
        var complete = true
        func rename(_ old: URL, _ new: URL) {
            guard fm.fileExists(atPath: old.path) else { return }
            guard !fm.fileExists(atPath: new.path) else {
                report.append("\(old.lastPathComponent) übersprungen (Ziel vorhanden)")
                return
            }
            do {
                try fm.moveItem(at: old, to: new)
                report.append("\(old.lastPathComponent) umbenannt")
            } catch {
                complete = false
                report.append("\(old.lastPathComponent) nicht umbenannt: \(error.localizedDescription)")
            }
        }
        rename(root.appendingPathComponent("earmark.log"), root.appendingPathComponent(AppInfo.logFileName))
        let models = root.appendingPathComponent("Models/llm")
        if fm.fileExists(atPath: models.path) {
            do {
                for folder in try fm.contentsOfDirectory(at: models, includingPropertiesForKeys: nil) {
                    rename(folder.appendingPathComponent(".earmark-complete"), folder.appendingPathComponent(".complete"))
                }
            } catch {
                complete = false
                report.append("Modell-Markierungen nicht lesbar: \(error.localizedDescription)")
            }
        }
        return complete
    }

    private static func rewrite(_ value: Any, from old: String, to new: String) -> Any {
        if let path = value as? String {
            if path == old { return new }
            if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
        } else if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { rewrite($0, from: old, to: new) }
        } else if let array = value as? [Any] {
            return array.map { rewrite($0, from: old, to: new) }
        }
        return value
    }

    /// Den bisher impliziten Exportordner unter Dokumente beibehalten.
    private static func keepMarkdownFolder(defaults: UserDefaults, documents: URL, report: inout [String]) -> Bool {
        let folder = documents.appendingPathComponent(AppInfo.legacySupportFolderName)
        guard FileManager.default.fileExists(atPath: folder.path), let data = defaults.data(forKey: "settings") else { return true }
        do {
            guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var destinations = settings["destinations"] as? [String: Any],
                  (destinations["markdownFolderPath"] as? String ?? "").isEmpty else { return true }
            destinations["markdownFolderPath"] = folder.path
            settings["destinations"] = destinations
            defaults.set(try JSONSerialization.data(withJSONObject: settings), forKey: "settings")
            report.append("bisheriger Markdown-Ordner beibehalten")
            return true
        } catch {
            report.append("Markdown-Ordner nicht übernommen: \(error.localizedDescription)")
            return false
        }
    }

    /// Attribute aller Einträge auflisten; Geheimnisse einzeln lesen und niemals protokollieren/löschen.
    private static func migrateKeychain(_ report: inout [String]) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppInfo.legacyKeychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return true }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            report.append("Schlüsselbund nicht lesbar (Status \(status))")
            return false
        }
        var copied = 0, existing = 0, failed = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { failed += 1; continue }
            let target: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: AppInfo.keychainService,
                kSecAttrAccount as String: account,
            ]
            let targetStatus = SecItemCopyMatching(target as CFDictionary, nil)
            if targetStatus == errSecSuccess { existing += 1; continue }
            guard targetStatus == errSecItemNotFound else {
                failed += 1
                report.append("Schlüsselbund-Ziel nicht prüfbar (Status \(targetStatus))")
                continue
            }
            var source = target
            source[kSecAttrService as String] = AppInfo.legacyKeychainService
            source[kSecReturnData as String] = true
            source[kSecMatchLimit as String] = kSecMatchLimitOne
            var dataResult: AnyObject?
            let readStatus = SecItemCopyMatching(source as CFDictionary, &dataResult)
            guard readStatus == errSecSuccess, let data = dataResult as? Data else {
                failed += 1
                report.append("Schlüsselbund-Eintrag nicht lesbar (Status \(readStatus))")
                continue
            }
            var add = target
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus == errSecSuccess { copied += 1 }
            else if addStatus == errSecDuplicateItem { existing += 1 }
            else {
                failed += 1
                report.append("Schlüsselbund-Eintrag nicht kopiert (Status \(addStatus))")
            }
        }
        report.append("Schlüsselbund: \(copied) übernommen, \(existing) vorhanden, \(failed) fehlgeschlagen")
        return failed == 0
    }
}
