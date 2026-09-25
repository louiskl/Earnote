import AppKit
import EarnoteCore
import SwiftUI

/// Aussehen (Dankeschön-Paket, wie am iPhone): Farbe des Fensters, Designs für die Notiz und ein anderes App-Symbol
/// im Dock. Freigeschaltet für eine Unterstützung über Ko-fi oder GitHub Sponsors – auf Vertrauen, ohne Konto und
/// ohne Server (ROADMAP, entschieden 25.09.2026). Bedienelemente bleiben die des Systems (DESIGN_GUIDELINES).
/// ponytail: Farbwerte doppelt zu `AppSkin` am iPhone (dort mit UIKit) – in den Kern ziehen, wenn ein drittes Gerät kommt.
enum MacSkin: String, CaseIterable, Identifiable {
    case system, rot, ozean, salbei, lavendel, mitternacht
    case retro, notizbuch, terminal

    static let key = "appearance.skin.mac"
    static let supporterKey = "supporter.mac"
    static let colors: [MacSkin] = [.system, .rot, .ozean, .salbei, .lavendel, .mitternacht]
    static let designs: [MacSkin] = [.retro, .notizbuch, .terminal]

    var id: Self { self }
    /// Systemfarbe und Earnote-Rot gibt es für alle
    var isFree: Bool { self == .system || self == .rot }

    var name: LocalizedStringKey {
        switch self {
        case .system: "Systemfarbe"
        case .rot: "Earnote-Rot"
        case .ozean: "Ozean"
        case .salbei: "Salbei"
        case .lavendel: "Lavendel"
        case .mitternacht: "Mitternacht"
        case .retro: "Retro"
        case .notizbuch: "Notizbuch"
        case .terminal: "Terminal"
        }
    }

    var detail: LocalizedStringKey? {
        switch self {
        case .retro: "Runde Schrift, warme 70er-Farben"
        case .notizbuch: "Serifenschrift auf Papier, Tintenblau"
        case .terminal: "Grün auf Schwarz, Schreibmaschinenschrift"
        default: nil
        }
    }

    /// Akzent, wenn kein Bereich mit eigener Farbe gewählt ist
    var tint: Color {
        switch self {
        case .system: .accentColor
        case .rot: Brand.tint
        case .ozean: Color(hex: "#2F7CF6")!
        case .salbei: Color(hex: "#23946A")!
        case .lavendel: Color(hex: "#8657EC")!
        case .mitternacht: Color(hex: "#5563DE")!
        case .retro: .adaptive(light: "#D2601A", dark: "#F08A3C")
        case .notizbuch: .adaptive(light: "#1F4E9C", dark: "#7FA6F0")
        case .terminal: Color(hex: "#3DDC6B")!
        }
    }

    /// Schrift der Notiz
    var fontDesign: Font.Design {
        switch self {
        case .retro: .rounded
        case .notizbuch: .serif
        case .terminal: .monospaced
        default: .default
        }
    }

    /// Papierton hinter der Notiz (nil = Systemhintergrund)
    var paper: Color? {
        switch self {
        case .retro: .adaptive(light: "#F5EBD9", dark: "#241B13")
        case .notizbuch: .adaptive(light: "#F8F4EA", dark: "#1C1A17")
        case .terminal: Color(hex: "#040805")
        default: nil
        }
    }

    var colorScheme: ColorScheme? { self == .terminal ? .dark : nil }

    /// Gewählte Farbe bzw. Design – ohne Unterstützung nur die freien
    @MainActor static func current(_ defaults: UserDefaults = AppEnvironment.preferences) -> MacSkin {
        let skin = MacSkin(rawValue: defaults.string(forKey: key) ?? "") ?? .system
        return skin.isFree || defaults.bool(forKey: supporterKey) ? skin : .system
    }
}

/// App-Symbol im Dock (solange Earnote läuft – mehr erlaubt macOS Apps außerhalb des App Store nicht)
enum DockIcon: String, CaseIterable, Identifiable {
    case standard = "Standard", ozean = "Ozean", salbei = "Salbei", lavendel = "Lavendel", mitternacht = "Mitternacht"
    case hell = "Hell", regenbogen = "Regenbogen", retro = "Retro", terminal = "Terminal"

    static let key = "appearance.dockIcon"
    var id: Self { self }
    var name: LocalizedStringKey { LocalizedStringKey(rawValue) }

    /// Die iPhone-Symbole sind randlos; im Dock brauchen sie die abgerundete Mac-Form mit Rand
    var image: NSImage? {
        guard self != .standard, let source = NSImage(named: "DockIcon-\(rawValue)") else { return nil }
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            // Apples Raster für Mac-Symbole: 824 von 1024 Punkten, Eckenradius ~185
            let inset = rect.insetBy(dx: rect.width * 100 / 1024, dy: rect.height * 100 / 1024)
            NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.2237, yRadius: inset.width * 0.2237).addClip()
            source.draw(in: inset)
            return true
        }
    }

    /// Gewähltes Symbol anwenden (beim Start und beim Wechsel)
    @MainActor static func apply(_ defaults: UserDefaults = AppEnvironment.preferences) {
        let icon = defaults.bool(forKey: MacSkin.supporterKey)
            ? DockIcon(rawValue: defaults.string(forKey: key) ?? "") ?? .standard : .standard
        NSApp.applicationIconImage = icon.image
    }
}

extension Color {
    /// Eigene Farbe für hellen und dunklen Modus
    static func adaptive(light: String, dark: String) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light)!)
        })
    }
}

/// Einstellungen › Aussehen
struct AppearanceSettings: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(MacSkin.key) private var skin: MacSkin = .system
    @AppStorage(MacSkin.supporterKey) private var isSupporter = false
    @AppStorage(DockIcon.key) private var dockIcon: DockIcon = .standard

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Erscheinungsbild", selection: $library.settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Farbe", selection: Binding(get: { MacSkin.colors.contains(skin) ? skin : nil },
                                                   set: { skin = $0 ?? .system })) {
                    if !MacSkin.colors.contains(skin) { Text("Aus dem Design").tag(MacSkin?.none) }
                    ForEach(MacSkin.colors.filter { isSupporter || $0.isFree }) { choice in
                        Label { Text(choice.name) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(choice.tint)
                        }
                        .tag(Optional(choice))
                    }
                }
                Picker("Design", selection: Binding(get: { MacSkin.designs.contains(skin) ? skin : nil },
                                                    set: { skin = $0 ?? .system })) {
                    Text("Keins").tag(MacSkin?.none)
                    ForEach(MacSkin.designs) { Text($0.name).tag(Optional($0)) }
                }
                .disabled(!isSupporter)
                Picker("App-Symbol im Dock", selection: $dockIcon) {
                    ForEach(DockIcon.allCases) { Text($0.name).tag($0) }
                }
                .disabled(!isSupporter)
            } header: {
                Text("Farben, Designs und App-Symbole")
            } footer: {
                if !isSupporter {
                    Text("Systemfarbe und Earnote-Rot gibt es für alle. Weitere Farben, die Designs und die App-Symbole sind ein Dankeschön für deine Unterstützung.")
                } else if let detail = skin.detail {
                    Text(detail)
                }
            }
            Section {
                HStack {
                    Link(destination: AppInfo.sponsor) { Label("Ko-fi", systemImage: "cup.and.saucer") }
                    Link(destination: URL(string: "https://github.com/sponsors/louiskl")!) {
                        Label("GitHub Sponsors", systemImage: "heart")
                    }
                }
                Toggle("Ich habe Earnote unterstützt", isOn: $isSupporter)
            } header: {
                Text("Earnote unterstützen")
            } footer: {
                Text("Earnote ist kostenlos und bleibt es. Als Dankeschön für eine Unterstützung gibt es Farben, Designs und App-Symbole – freigeschaltet auf Vertrauen, ohne Konto und ohne Prüfung.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: isSupporter) { _, on in
            if !on && !skin.isFree { skin = .system }
            DockIcon.apply()
        }
        .onChange(of: dockIcon) { DockIcon.apply() }
    }
}

/// Design des Dankeschön-Pakets auf der Notiz: Schrift, Papierton, bei „Terminal“ dunkel. Nur die Notiz –
/// Seitenleiste, Liste und Bedienelemente bleiben Systemoberfläche.
struct NoteDesign: ViewModifier {
    @AppStorage(MacSkin.key) private var raw = ""
    @AppStorage(MacSkin.supporterKey) private var isSupporter = false

    func body(content: Content) -> some View {
        let skin = MacSkin.current()
        content
            .fontDesign(skin.fontDesign)
            .background { skin.paper }
            .environment(\.colorScheme, skin.colorScheme ?? colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme
}
