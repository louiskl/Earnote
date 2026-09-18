import SwiftUI

/// Markenfarbe von Earnote. Bewusst nur an zwei Stellen: am Zeichen der App und am
/// einen Hauptknopf im Call-Hinweis. Alles andere nutzt die Farbe des Bereichs oder die Systemfarben.
enum Brand {
    static let gradient = LinearGradient(colors: [Color(hex: "#FF5A4E")!, Color(hex: "#FF7A59")!],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
}
