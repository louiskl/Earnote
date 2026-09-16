import Foundation

/// Name und Kennungen der App an einer Stelle. Oberflächentexte verwenden `AppInfo.name`
/// statt eines festen Strings, damit ein Namenswechsel nur hier passiert.
public enum AppInfo {
    /// Anzeigename
    public static let name = "Earnote"
    public static let bundleIdentifier = "app.earnote.Earnote"
    /// Ordner unter ~/Library/Application Support
    public static let supportFolderName = "Earnote"
    public static let keychainService = "app.earnote.secrets"
    public static let logFileName = "earnote.log"

    /// Öffentliche Repository-Adresse. Bleibt `nil`, bis das Repository veröffentlicht ist –
    /// solange zeigt die Oberfläche keine Links dorthin.
    public static let repository: URL? = nil

    // MARK: Frühere Werte (bis Version 0.1.1 hieß die App „Earmark“) – nur für die Datenübernahme

    public static let legacyBundleIdentifier = "app.earmark.Earmark"
    public static let legacySupportFolderName = "Earmark"
    public static let legacyKeychainService = "app.earmark.secrets"
}
