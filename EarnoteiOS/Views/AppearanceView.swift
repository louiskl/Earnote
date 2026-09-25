import EarnoteCore
import SwiftUI
import UIKit

/// Aussehen der App (Dankeschön-Paket). Farben tauschen nur den Akzent; Designs zusätzlich Schriftart, Papierton
/// hinter den Listen und – bei „Terminal“ – das dunkle Erscheinungsbild. Bedienelemente bleiben immer die des Systems
/// (DESIGN_GUIDELINES Abschnitt 30).
enum AppSkin: String, CaseIterable, Identifiable {
    case standard, ozean, salbei, lavendel, mitternacht
    case retro, notizbuch, terminal

    static let key = "appearance.skin"
    static let colors: [AppSkin] = [.standard, .ozean, .salbei, .lavendel, .mitternacht]
    static let designs: [AppSkin] = [.retro, .notizbuch, .terminal]
    var id: Self { self }
    var isFree: Bool { self == .standard }

    var name: LocalizedStringKey {
        switch self {
        case .standard: "Earnote-Rot"
        case .ozean: "Ozean"
        case .salbei: "Salbei"
        case .lavendel: "Lavendel"
        case .mitternacht: "Mitternacht"
        case .retro: "Retro"
        case .notizbuch: "Notizbuch"
        case .terminal: "Terminal"
        }
    }

    /// Kurz, wonach ein Design aussieht
    var detail: LocalizedStringKey? {
        switch self {
        case .retro: "Runde Schrift, warme 70er-Farben"
        case .notizbuch: "Serifenschrift auf Papier, Tintenblau"
        case .terminal: "Grün auf Schwarz, Schreibmaschinenschrift"
        default: nil
        }
    }

    var tint: Color {
        switch self {
        case .standard: Color("AccentColor")
        case .ozean: Color(hex: "#2F7CF6")
        case .salbei: Color(hex: "#23946A")
        case .lavendel: Color(hex: "#8657EC")
        case .mitternacht: Color(hex: "#5563DE")
        case .retro: .adaptive(light: "#D2601A", dark: "#F08A3C")
        case .notizbuch: .adaptive(light: "#1F4E9C", dark: "#7FA6F0")
        case .terminal: Color(hex: "#3DDC6B")
        }
    }

    /// Die beiden Nebenfarben des fließenden Verlaufs (`BrandGlow`) neben dem Akzent
    var glow: (Color, Color) {
        switch self {
        case .standard: (.orange, .pink)
        case .ozean: (.cyan, .indigo)
        case .salbei: (.mint, .teal)
        case .lavendel: (.pink, .indigo)
        case .mitternacht: (.indigo, .purple)
        case .retro: (Color(hex: "#E8B031"), Color(hex: "#8C3B1E"))
        case .notizbuch: (.teal, .indigo)
        case .terminal: (.mint, .green)
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .retro: .rounded
        case .notizbuch: .serif
        case .terminal: .monospaced
        default: .default
        }
    }

    /// Papierton hinter Listen und Formularen (nil = Systemhintergrund)
    var paper: Color? {
        switch self {
        case .retro: .adaptive(light: "#F5EBD9", dark: "#241B13")
        case .notizbuch: .adaptive(light: "#F8F4EA", dark: "#1C1A17")
        case .terminal: Color(hex: "#040805")
        default: nil
        }
    }

    var colorScheme: ColorScheme? { self == .terminal ? .dark : nil }
}

extension Color {
    /// Eigene Farbe für hellen und dunklen Modus
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

extension View {
    /// Papierton eines Designs hinter den Hauptansichten (Aufnahmen, Bereiche, Suche, Notiz). Blätter wie die
    /// Einstellungen bleiben Systemoberfläche.
    func paper() -> some View { modifier(PaperBackground()) }
}

private struct PaperBackground: ViewModifier {
    @Environment(\.skin) private var skin

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(skin.paper == nil ? .automatic : .hidden)
            .background { skin.paper?.ignoresSafeArea() }
    }
}

/// App-Symbol auf dem Home-Bildschirm (Dankeschön-Paket). Die Symbole erzeugt scripts/make_ios_icon_variants.swift.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "Standard", ozean = "Ozean", salbei = "Salbei", lavendel = "Lavendel", mitternacht = "Mitternacht", hell = "Hell"
    case regenbogen = "Regenbogen", retro = "Retro", terminal = "Terminal"

    var id: Self { self }
    var isFree: Bool { self == .standard }
    var name: LocalizedStringKey { LocalizedStringKey(rawValue) }
    /// Name im Asset-Katalog (nil = Haupt-Icon)
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }
    var preview: Image { Image("IconPreview-\(rawValue)") }

    @MainActor static var current: AppIconChoice {
        allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .standard
    }
}

extension EnvironmentValues {
    /// Die gewählte Farbe – für Stellen, die eine `Color` brauchen (Verlauf, Glas); sonst reicht `.tint`
    @Entry var skin: AppSkin = .standard
}

/// Setzt Akzent und `skin` für ein Fenster. Ohne Trinkgeld (z. B. nach einer Erstattung) gilt wieder das Earnote-Rot.
struct Skinned: ViewModifier {
    @AppStorage(AppSkin.key) private var skin: AppSkin = .standard
    @AppStorage(TipJar.supporterKey) private var isSupporter = false

    func body(content: Content) -> some View {
        let active = isSupporter || skin.isFree ? skin : .standard
        content
            .tint(active.tint)
            .fontDesign(active.fontDesign)
            .preferredColorScheme(active.colorScheme)
            .environment(\.skin, active)
    }
}

/// Einstellungen › Aussehen: Farbe und App-Symbol. Das Standard-Aussehen ist kostenlos, der Rest ist das Dankeschön-Paket.
struct AppearanceView: View {
    @AppStorage(AppSkin.key) private var skin: AppSkin = .standard
    @AppStorage(TipJar.supporterKey) private var isSupporter = false
    @State private var icon = AppIconChoice.current
    @State private var showsSupporter = false
    @State private var iconFailed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            if !isSupporter {
                Section {
                    Button("Dankeschön-Paket ansehen", systemImage: "gift") { showsSupporter = true }
                } footer: {
                    Text("Das Earnote-Rot ist kostenlos. Die anderen Farben und Symbole gibt es als Dankeschön für ein Trinkgeld – egal, wie groß.")
                }
            }
            Section("Farbe") {
                ForEach(AppSkin.colors) { option in
                    skinRow(option) { Circle().fill(option.tint).frame(width: 28, height: 28) }
                }
            }
            Section {
                ForEach(AppSkin.designs) { option in
                    skinRow(option) {
                        Text(verbatim: "Aa")
                            .font(.system(.callout, design: option.fontDesign).weight(.semibold))
                            .foregroundStyle(option.tint)
                            .frame(width: 40, height: 40)
                            .background(option.paper ?? .clear, in: .rect(cornerRadius: 9))
                            .environment(\.colorScheme, option.colorScheme ?? colorScheme)
                    }
                }
            } header: {
                Text("Design")
            } footer: {
                Text("Ein Design ändert Farbe, Schrift und Hintergrund der ganzen App.")
            }
            Section {
                ForEach(AppIconChoice.allCases) { option in
                    OptionRow(name: option.name, isFree: option.isFree, isSelected: icon == option, isLocked: !option.isFree && !isSupporter) {
                        option.preview.resizable().frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 9))
                    } action: {
                        if option.isFree || isSupporter { setIcon(option) } else { showsSupporter = true }
                    }
                }
            } header: {
                Text("App-Symbol")
            } footer: {
                Text("iOS bestätigt den Wechsel des Symbols mit einer kurzen Meldung.")
            }
        }
        .navigationTitle("Aussehen")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsSupporter) { SupporterView(showsAppearanceLink: false) }
        .alert("Das Symbol ließ sich nicht ändern. Versuch es gleich noch einmal.", isPresented: $iconFailed) {}
    }

    private func skinRow(_ option: AppSkin, @ViewBuilder preview: () -> some View) -> some View {
        OptionRow(name: option.name, detail: option.detail, isFree: option.isFree, isSelected: skin == option,
                  isLocked: !option.isFree && !isSupporter, preview: preview) {
            if option.isFree || isSupporter { skin = option } else { showsSupporter = true }
        }
    }

    private func setIcon(_ option: AppIconChoice) {
        Task {
            // iOS meldet manchmal einen Fehler, obwohl das Symbol gewechselt hat – maßgeblich ist, was danach gilt
            try? await UIApplication.shared.setAlternateIconName(option.iconName)
            icon = .current
            iconFailed = icon != option
        }
    }
}

/// Eine Zeile zum Auswählen: Vorschau, Name, darunter „Kostenlos“ oder „Dankeschön-Paket“, Haken bei der Auswahl
private struct OptionRow<Preview: View>: View {
    let name: LocalizedStringKey
    var detail: LocalizedStringKey?
    let isFree: Bool
    let isSelected: Bool
    let isLocked: Bool
    @ViewBuilder let preview: Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                preview.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if isFree {
                        Text("Kostenlos").font(.caption).foregroundStyle(.secondary)
                    } else if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    } else if isLocked {
                        Text("Dankeschön-Paket").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                } else if isLocked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Gesperrt")
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
