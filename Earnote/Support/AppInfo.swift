import Foundation

/// Name und Kennungen der App an einer Stelle. Oberflächentexte verwenden `AppInfo.name`
/// statt eines festen Strings, damit ein Namenswechsel nur hier passiert.
enum AppInfo {
    /// Anzeigename
    static let name = "Earnote"
    static let bundleIdentifier = "app.earnote.Earnote"
    /// Ordner unter ~/Library/Application Support
    static let supportFolderName = "Earnote"
    static let keychainService = "app.earnote.secrets"
    static let logFileName = "earnote.log"

    /// Nach dem Hochladen auf GitHub hier die eigene Repository-Adresse eintragen.
    static let repository = URL(string: "https://github.com/YOUR-USERNAME/earnote")!

    // MARK: Frühere Werte (bis Version 0.1.1 hieß die App „Earmark“) – nur für die Datenübernahme

    static let legacyBundleIdentifier = "app.earmark.Earmark"
    static let legacySupportFolderName = "Earmark"
    static let legacyKeychainService = "app.earmark.secrets"
}
