import Foundation

/// Übersetzung für Texte aus dem Kern. Deutsch steht im Code und ist zugleich der Schlüssel;
/// weitere Sprachen liegen unter `Resources/<sprache>.lproj/Localizable.strings`.
///
/// Der Kern kennt keine Oberfläche, liefert aber Texte, die Menschen lesen: Status einer Aufnahme,
/// Fehlermeldungen, Namen der Vorlagen und Ziele.
func t(_ german: String.LocalizationValue) -> String {
    String(localized: german, bundle: .module)
}
