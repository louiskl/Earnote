import AppKit
import EarnoteCore

/// Hell, dunkel oder wie das System – gilt für die ganze App.
@MainActor
enum Appearance {
    static func apply(_ choice: AppearanceChoice) {
        #if DEBUG
        // Für Tests: EARNOTE_APPEARANCE=dark|light übersteuert die Einstellung
        switch ProcessInfo.processInfo.environment["EARNOTE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua); return
        case "light": NSApp.appearance = NSAppearance(named: .aqua); return
        default: break
        }
        #endif
        switch choice {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
