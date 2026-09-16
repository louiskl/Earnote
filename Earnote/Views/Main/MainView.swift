import EarnoteCore
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case all, category(UUID), openTasks, failed
}

/// Hauptfenster im Arc-Stil: farbiger Hintergrund, Seitenleiste direkt darauf, Inhalt auf einer schwebenden Karte.
/// Passt sich der Fenstergröße an – schmal wird aus zwei Spalten eine, die Seitenleiste lässt sich einklappen.
struct MainView: View {
    @EnvironmentObject var app: AppState
    @State private var sidebar: SidebarItem = .all
    @State private var search = ""
    @State private var showSidebar = true
    @State private var showOnboarding = false
    @State private var dropTargeted = false
    @State private var editingCategory: RecordingCategory?
    @State private var addingCategory = false

    /// Farbe des Fensterhintergrunds: die des gewählten Bereichs, sonst die Koralle der App
    private var tint: Color {
        if case .category(let id) = sidebar, let c = app.category(id) { return c.color }
        return Theme.brand
    }

    private var currentCategory: RecordingCategory? {
        if case .category(let id) = sidebar { return app.category(id) }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let sidebarVisible = showSidebar && geo.size.width >= 700
            HStack(spacing: 0) {
                if sidebarVisible {
                    EarnoteSidebar(selection: $sidebar, search: $search, showSidebar: $showSidebar,
                                   editingCategory: $editingCategory, addingCategory: $addingCategory)
                        .frame(width: 236)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if !sidebarVisible { collapsedBar }
                    ContentCard(filter: sidebar, search: search,
                                compact: geo.size.width - (sidebarVisible ? 236 : 0) < 760)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.cardBackground)
                                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                        )
                        .padding(.top, sidebarVisible ? Theme.Space.s : 0)
                        .padding([.bottom, .trailing], Theme.Space.s)
                        .padding(.leading, sidebarVisible ? 0 : Theme.Space.s)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: sidebarVisible)
        }
        // Nur der Hintergrund blendet die Farbe über – sonst würden Liste und Texte mitanimieren
        .background(Backdrop(tint: tint).animation(.easeInOut(duration: 0.6), value: tint).ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay { if dropTargeted { dropOverlay } }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .interactiveDismissDisabled()
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(category: category) { editingCategory = nil }
                .environmentObject(app)
        }
        .sheet(isPresented: $addingCategory) {
            AddCategorySheet { created in
                addingCategory = false
                if let created { sidebar = .category(created.id) }
            }
            .environmentObject(app)
        }
        .alert("Hinweis", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } })) {
            Button("OK") { app.lastError = nil }
        } message: {
            Text(app.lastError ?? "")
        }
        .onAppear { if !app.settings.onboardingCompleted { showOnboarding = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { showSidebar.toggle() }
        }
        .onChange(of: app.categories) { _, categories in
            // Gelöschter Bereich war ausgewählt → zurück zu „Alle“
            if case .category(let id) = sidebar, !categories.contains(where: { $0.id == id }) { sidebar = .all }
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    /// Schmale Leiste über der Karte, wenn die Seitenleiste eingeklappt ist (lässt Platz für die Fensterknöpfe).
    private var collapsedBar: some View {
        HStack(spacing: Theme.Space.s) {
            Button { withAnimation { showSidebar = true } } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(RoundIconButtonStyle(size: 26, fill: .white.opacity(0.35)))
                .help("Seitenleiste einblenden (⌃⌘S)")
            Spacer()
            if !app.isRecording { RecordPill(category: currentCategory, compact: true) }
        }
        .padding(.leading, 78)
        .padding(.trailing, Theme.Space.s)
        .frame(height: 42)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
            )
            .overlay(
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 34, weight: .medium))
                    Text("Loslassen zum Transkribieren").font(Theme.Font.heading)
                }
                .foregroundStyle(Theme.accent)
            )
            .padding(Theme.Space.l)
            .allowsHitTesting(false)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in app.importAudio([url], category: currentCategory) }
            }
        }
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("\(AppInfo.bundleIdentifier).showOnboarding")
    static let toggleSidebar = Notification.Name("\(AppInfo.bundleIdentifier).toggleSidebar")
}

// MARK: - Seitenleiste

struct EarnoteSidebar: View {
    @EnvironmentObject var app: AppState
    @Binding var selection: SidebarItem
    @Binding var search: String
    @Binding var showSidebar: Bool
    @Binding var editingCategory: RecordingCategory?
    @Binding var addingCategory: Bool

    private var selectedCategory: RecordingCategory? {
        if case .category(let id) = selection { return app.category(id) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Oberste Zeile: links sitzen die Fensterknöpfe, rechts das Einklappen
            HStack {
                Spacer()
                Button { withAnimation { showSidebar = false } } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(RoundIconButtonStyle(size: 26, fill: .clear, foreground: .secondary))
                    .help("Seitenleiste ausblenden (⌃⌘S)")
            }
            .frame(height: 30)
            .padding(.top, 8)

            GlassSearchField(text: $search, prompt: "Aufnahmen durchsuchen")

            if app.isRecording {
                SidebarRecordingCard()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                RecordPill(category: selectedCategory)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarRow(icon: .symbol("tray.full.fill"), title: "Alle Aufnahmen",
                               count: app.recordings.count, selected: selection == .all) { selection = .all }
                    let openTasks = app.recordings.filter { $0.taskCount > 0 }.count
                    SidebarRow(icon: .symbol("checklist"), title: "Offene Aufgaben",
                               count: openTasks, selected: selection == .openTasks) { selection = .openTasks }
                    let failed = app.recordings.filter { $0.status == .failed }.count
                    if failed > 0 {
                        SidebarRow(icon: .symbol("exclamationmark.triangle.fill"), title: "Probleme",
                                   count: failed, selected: selection == .failed) { selection = .failed }
                    }

                    HStack {
                        Text("Bereiche").font(Theme.Font.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { addingCategory = true } label: { Image(systemName: "plus") }
                            .buttonStyle(RoundIconButtonStyle(size: 22, fill: .clear, foreground: .secondary))
                            .help("Bereich hinzufügen")
                    }
                    .padding(.horizontal, Theme.Space.s + 2)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, 2)

                    ForEach(app.categories) { category in
                        SidebarRow(icon: .emoji(category.displayEmoji, category.color), title: category.name,
                                   count: app.recordings.filter { $0.categoryID == category.id }.count,
                                   selected: selection == .category(category.id)) {
                            selection = .category(category.id)
                        }
                        .contextMenu {
                            Button("Bearbeiten …") { editingCategory = category }
                            Button("Als Standard verwenden") { app.settings.defaultCategoryID = category.id }
                            Divider()
                            Button("Löschen", role: .destructive) { app.categories.removeAll { $0.id == category.id } }
                                .disabled(app.categories.count <= 1)
                        }
                    }
                }
            }

            HStack(spacing: Theme.Space.xs) {
                Button { ImportHelper.pickAndImport(into: app) } label: { Image(systemName: "tray.and.arrow.down") }
                    .buttonStyle(RoundIconButtonStyle(size: 30, fill: .white.opacity(0.35)))
                    .help("Audiodatei importieren (⌘I)")
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(RoundIconButtonStyle(size: 30, fill: .white.opacity(0.35)))
                    .help("Einstellungen (⌘,)")
                Spacer()
                ProcessingIndicator()
            }
            .padding(.bottom, Theme.Space.m)
        }
        .padding(.horizontal, Theme.Space.m)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.isRecording)
    }
}

/// Zeile in der Seitenleiste – ausgewählt als helle „Tab“-Fläche wie bei Arc.
struct SidebarRow: View {
    enum Icon {
        case symbol(String)
        case emoji(String, Color)
    }

    let icon: Icon
    let title: String
    var count: Int = 0
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s + 2) {
                Group {
                    switch icon {
                    case .symbol(let name):
                        Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    case .emoji(let emoji, _):
                        Text(emoji).font(.system(size: 15))
                    }
                }
                .frame(width: 22)
                Text(title)
                    .font(Theme.Font.body.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").font(Theme.Font.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(selected ? 0.78 : (hovering ? 0.32 : 0)))
                    .shadow(color: .black.opacity(selected ? 0.07 : 0), radius: 3, y: 1)
            )
            .overlay(alignment: .leading) {
                if selected, case .emoji(_, let color) = icon {
                    Capsule().fill(color).frame(width: 3, height: 16).offset(x: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

/// Der große Aufnahme-Knopf: startet im gerade gewählten Bereich, das Menü rechts wählt einen anderen.
struct RecordPill: View {
    @EnvironmentObject var app: AppState
    var category: RecordingCategory?
    var compact = false
    @State private var hovering = false

    private var target: RecordingCategory? {
        category ?? app.category(app.settings.defaultCategoryID) ?? app.categories.first
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                app.startRecording(category: target, sourceApp: app.detector.activeCallApp)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    ZStack {
                        Circle().fill(.white.opacity(0.3)).frame(width: 18, height: 18)
                        Circle().fill(.white).frame(width: 8, height: 8)
                    }
                    Text(compact ? "Aufnehmen" : "Aufnahme starten")
                        .font(Theme.Font.body.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                    if !compact { Spacer(minLength: 0) }
                }
                .padding(.leading, Theme.Space.m)
                .padding(.trailing, compact ? Theme.Space.s : 0)
                .padding(.vertical, compact ? 6 : 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(app.categories) { c in
                    Button("\(c.displayEmoji)  \(c.name)") {
                        app.startRecording(category: c, sourceApp: app.detector.activeCallApp)
                    }
                }
            } label: {
                Text(target?.displayEmoji ?? "🎙️")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.25)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, Theme.Space.s)
            .help("In anderem Bereich aufnehmen")
        }
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Color(hex: "#FF7A59")!], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Theme.accent.opacity(hovering ? 0.45 : 0.3), radius: hovering ? 12 : 8, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .fixedSize(horizontal: compact, vertical: true)
    }
}

/// Dunkle Mini-Karte in der Seitenleiste, solange aufgenommen wird
struct SidebarRecordingCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var meter: LiveMeter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            HStack(spacing: Theme.Space.s) {
                if app.isPaused {
                    Image(systemName: "pause.fill").font(.system(size: 10)).foregroundStyle(.orange).frame(width: 14)
                } else {
                    PulsingDot(size: 6).frame(width: 14)
                }
                Text(app.isPaused ? "Pausiert" : "Aufnahme läuft")
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(TimeFormat.duration(meter.elapsed))
                    .font(Theme.Font.number(15))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Waveform(level: max(meter.mic, meter.system), color: Theme.accent, bars: 24, height: 18, muted: app.isPaused)
                .frame(maxWidth: .infinity)
            HStack(spacing: Theme.Space.s) {
                Button { app.selection = app.activeRecordingID } label: {
                    Text("Ansehen").font(Theme.Font.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                Spacer()
                PauseButton(compact: true)
                    .buttonStyle(RoundIconButtonStyle(size: 28, fill: .white.opacity(0.14), foreground: .white))
                Button { app.stopRecording() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(RoundIconButtonStyle(size: 28, fill: Theme.accent, foreground: .white))
                    .help("Stoppen & auswerten")
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Theme.stageRaised, Theme.stage], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selection = app.activeRecordingID }
    }
}

/// Kleine Anzeige unten in der Seitenleiste, solange im Hintergrund verarbeitet wird
struct ProcessingIndicator: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let busy = app.recordings.filter { $0.status.isBusy }
        if let first = busy.first {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(busy.count > 1 ? "\(busy.count) in Arbeit" : "\(Int(first.progress * 100)) %")
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.4)))
            .help(first.status.label)
            .onTapGesture { app.selection = first.id }
        }
    }
}

// MARK: - Inhaltskarte

struct ContentCard: View {
    @EnvironmentObject var app: AppState
    let filter: SidebarItem
    let search: String
    /// Schmales Fenster: Liste und Detail nicht nebeneinander, sondern nacheinander
    let compact: Bool

    private var showsLive: Bool {
        guard let active = app.activeRecordingID else { return false }
        return app.selection == active || (app.selection == nil && !compact)
    }

    private var hasDetail: Bool {
        showsLive || (app.selection.flatMap(app.recording) != nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !compact || !hasDetail {
                RecordingListColumn(filter: filter, search: search)
                    .frame(maxWidth: compact ? .infinity : 320)
                if !compact { Divider().opacity(0.6) }
            }
            if !compact || hasDetail {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: compact)
    }

    @ViewBuilder private var detail: some View {
        if showsLive {
            LiveRecordingView(compact: compact)
        } else if let id = app.selection, app.recording(id) != nil {
            RecordingDetailView(recordingID: id, showsBack: compact)
                .id(id)
        } else {
            EmptyDetailView()
        }
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject var app: AppState
    @State private var float = false

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.28), Theme.brandSecondary.opacity(0.12), .clear],
                                         center: .center, startRadius: 2, endRadius: 90))
                    .frame(width: 180, height: 180)
                    .blur(radius: 8)
                Text("🎙️").font(.system(size: 52))
                    .offset(y: float ? -4 : 4)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: float)
            }
            .onAppear { float = true }
            VStack(spacing: Theme.Space.s) {
                Text(app.recordings.isEmpty ? "Bereit, wenn du es bist" : "Wähle eine Aufnahme")
                    .font(Theme.Font.title)
                Text(app.recordings.isEmpty
                     ? "Starte eine Aufnahme, sobald dein Meeting, Call oder deine Vorlesung beginnt.\n\(AppInfo.name) schreibt mit und macht daraus Notizen."
                     : "Oder starte eine neue – \(AppInfo.name) schreibt mit.")
                    .font(Theme.Font.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Space.l) {
                hint("⌘⇧R", "Aufnahme starten")
                hint("⌘I", "Datei importieren")
                hint("⌃⌘S", "Seitenleiste")
            }
            .padding(.top, Theme.Space.s)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            Text(text).font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Liste

struct RecordingListColumn: View {
    @EnvironmentObject var app: AppState
    let filter: SidebarItem
    let search: String

    private var items: [Recording] {
        app.recordings.filter { r in
            switch filter {
            case .all: break
            case .category(let id): if r.categoryID != id { return false }
            case .openTasks: if r.taskCount == 0 { return false }
            case .failed: if r.status != .failed { return false }
            }
            guard !search.isEmpty else { return true }
            let q = search.lowercased()
            return r.displayTitle.lowercased().contains(q) || r.title.lowercased().contains(q)
                || (r.summaryPreview?.lowercased().contains(q) ?? false)
                || (app.category(r.categoryID)?.name.lowercased().contains(q) ?? false)
        }
    }

    private var grouped: [(String, [Recording])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEEE, d. MMMM"
        var groups: [(String, [Recording])] = []
        for r in items where r.id != app.activeRecordingID {
            let key: String
            if cal.isDateInToday(r.startedAt) { key = "Heute" }
            else if cal.isDateInYesterday(r.startedAt) { key = "Gestern" }
            else { key = df.string(from: r.startedAt) }
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(r) } else { groups.append((key, [r])) }
        }
        return groups
    }

    private var header: (emoji: String, title: String, color: Color) {
        switch filter {
        case .all: return ("🗂️", "Alle Aufnahmen", Theme.brand)
        case .openTasks: return ("✅", "Offene Aufgaben", .green)
        case .failed: return ("⚠️", "Probleme", .orange)
        case .category(let id):
            let c = app.category(id)
            return (c?.displayEmoji ?? "🗂️", c?.name ?? "Bereich", c?.color ?? .gray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                EmojiBadge(emoji: header.emoji, color: header.color, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(header.title).font(Theme.Font.heading).lineLimit(1)
                    Text(items.count == 1 ? "1 Aufnahme" : "\(items.count) Aufnahmen")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if app.isRecording, let active = app.activeRecording {
                        LiveListBanner(recording: active)
                            .padding(.vertical, Theme.Space.xs)
                    }
                    ForEach(grouped, id: \.0) { title, recs in
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.top, Theme.Space.m)
                            .padding(.bottom, Theme.Space.xs)
                        ForEach(recs) { r in
                            Button { app.selection = r.id } label: {
                                RecordingCardRow(recording: r, selected: app.selection == r.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { RecordingActions(recordingID: r.id) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.l)
            }
            .overlay {
                if items.isEmpty && !app.isRecording {
                    VStack(spacing: Theme.Space.s) {
                        Text(search.isEmpty ? "🌱" : "🔍").font(.system(size: 30))
                        Text(search.isEmpty ? "Hier ist noch nichts" : "Keine Treffer")
                            .font(Theme.Font.body.weight(.semibold))
                        Text(search.isEmpty ? "Neue Aufnahmen in diesem Bereich erscheinen hier." : "Versuch es mit einem anderen Wort.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { moveSelection($0) }
    }

    /// Pfeiltasten wählen die vorige/nächste Aufnahme
    private func moveSelection(_ direction: MoveCommandDirection) {
        let ids = grouped.flatMap(\.1).map(\.id)
        guard !ids.isEmpty else { return }
        let index = app.selection.flatMap { ids.firstIndex(of: $0) }
        switch direction {
        case .up: app.selection = ids[max(0, (index ?? 1) - 1)]
        case .down: app.selection = ids[min(ids.count - 1, (index ?? -1) + 1)]
        default: break
        }
    }
}

/// Aufnahme als Karte: Bereich, Titel, Vorschau der Notizen, Dauer und offene Aufgaben
struct RecordingCardRow: View {
    @EnvironmentObject var app: AppState
    let recording: Recording
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let category = app.category(recording.categoryID)
        let color = category?.color ?? Theme.brand
        HStack(alignment: .top, spacing: Theme.Space.m) {
            EmojiBadge(emoji: category?.displayEmoji ?? "🎙️", color: color, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recording.displayTitle)
                        .font(Theme.Font.body.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: Theme.Space.s)
                    Text(recording.startedAt, style: .time)
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let preview = recording.summaryPreview, recording.status == .done {
                    Text(preview)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: Theme.Space.xs) {
                    Text(TimeFormat.duration(recording.duration))
                    if let source = recording.sourceApp { Text("· \(source)").lineLimit(1) }
                    Spacer(minLength: 0)
                    if recording.taskCount > 0 {
                        Label("\(recording.taskCount)", systemImage: "checkmark.circle")
                            .font(Theme.Font.caption.weight(.semibold))
                            .foregroundStyle(color)
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
                if recording.status != .done {
                    StatusBadge(recording: recording)
                    if recording.status.isBusy { ProgressLine(progress: recording.progress, color: color) }
                }
            }
        }
        .padding(Theme.Space.s + 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? color.opacity(0.13) : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? color.opacity(0.35) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selected)
    }
}

/// Oben in der Liste, solange aufgenommen wird – ein Klick öffnet die Live-Ansicht.
struct LiveListBanner: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var meter: LiveMeter
    let recording: Recording

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if app.isPaused {
                Image(systemName: "pause.fill").foregroundStyle(.orange).frame(width: 18)
            } else {
                PulsingDot(size: 7).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.isPaused ? "Pausiert" : "Aufnahme läuft").font(Theme.Font.small.weight(.semibold))
                Text(app.category(recording.categoryID).map { "\($0.displayEmoji) \($0.name)" } ?? "Aufnahme")
                    .font(Theme.Font.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(TimeFormat.duration(meter.elapsed))
                .font(Theme.Font.number(15))
                .contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Theme.stageRaised, Theme.stage], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selection = recording.id }
    }
}

struct RecordingActions: View {
    @EnvironmentObject var app: AppState
    let recordingID: UUID

    var body: some View {
        let hasAudio = app.hasAudio(recordingID)
        Button("Neu zusammenfassen") { app.reprocess(recordingID, retranscribe: false) }
        Button("Neu transkribieren") { app.reprocess(recordingID, retranscribe: true) }.disabled(!hasAudio)
        Button("Erneut exportieren") { app.reexport(recordingID) }
        Divider()
        Menu("Bereich") {
            ForEach(app.categories) { c in
                Button("\(c.displayEmoji)  \(c.name)") { app.setCategory(recordingID, c.id) }
            }
        }
        Button("Im Finder zeigen") { app.revealInFinder(recordingID) }
        Divider()
        Button("Löschen", role: .destructive) { app.delete(recordingID) }
    }
}
