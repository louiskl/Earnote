import AppKit
import Carbon.HIToolbox
import EarnoteCore

/// Ein festes Tastenkürzel, das in jeder App wirkt: ⌃⌥⌘R startet und stoppt die Aufnahme.
/// Bewusst fest vergeben – ein Aufnahmefeld für eigene Kürzel wäre eine Einstellung mehr,
/// die niemand braucht, der nur schnell mitschreiben lassen will.
@MainActor
enum GlobalShortcut {
    /// Für die Oberfläche
    static let display = "⌃⌥⌘R"

    /// Was das Kürzel auslöst – wird beim Start gesetzt (`AppDelegate`)
    static var action: () -> Void = {}

    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func apply(enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private static func register() {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), globalShortcutHandler, 1, &eventType, nil, &handler)
        // Signatur und Nummer unterscheiden das Kürzel von denen anderer Apps
        let id = EventHotKeyID(signature: OSType(0x4541_524E), id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status == noErr {
            Log.info("Globales Tastenkürzel aktiv: \(display)")
        } else {
            // Meist hat eine andere App dasselbe Kürzel belegt
            Log.error("Globales Tastenkürzel konnte nicht registriert werden (Fehler \(status))")
            hotKey = nil
        }
    }

    private static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

/// Carbon ruft eine einfache C-Funktion auf – sie reicht nur weiter.
private func globalShortcutHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                   _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { MainActor.assumeIsolated { GlobalShortcut.action() } }
    return noErr
}
