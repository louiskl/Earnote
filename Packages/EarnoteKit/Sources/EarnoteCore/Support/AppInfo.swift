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

    /// Öffentliches Repository – Quellcode, Fehlermeldungen und die Update-Datei für Sparkle.
    public static let repository = URL(string: "https://github.com/louiskl/Earnote")!
    /// Projektseite, Anleitung und Datenschutzhinweise (Hilfe-Menü)
    public static let website = URL(string: "https://louiskl.github.io/Earnote/")!
    public static let betaGuide = URL(string: "https://github.com/louiskl/Earnote/blob/main/docs/BETA.md")!
    public static let privacyPage = URL(string: "https://github.com/louiskl/Earnote/blob/main/docs/DATENSCHUTZ.md")!
}
