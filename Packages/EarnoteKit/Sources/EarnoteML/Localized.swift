import Foundation

/// Übersetzung für die wenigen Texte aus EarnoteML (Modellbeschreibungen).
/// Deutsch steht im Code und ist zugleich der Schlüssel, siehe EarnoteCore/Support/Localized.swift.
func t(_ german: String.LocalizationValue) -> String {
    String(localized: german, bundle: .module)
}
