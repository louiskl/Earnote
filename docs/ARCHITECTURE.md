# Architektur

Stand: Phase 1b. Die Logik liegt in einem lokalen Swift Package, die Mac-App ist eine dünne Hülle darum.
Die Bibliothek liegt in SwiftData (iCloud-tauglich, Sync noch aus), Audio als lokale Dateien. Mindestversion: macOS 15, iOS 26.

## Module und erlaubte Abhängigkeiten

```
Earnote (Mac-App)  ──►  EarnoteML  ──►  EarnoteCore
        └──────────────────────────────►  EarnoteCore
```

| Modul | Darf verwenden | Enthält |
|---|---|---|
| **EarnoteCore** (`Packages/EarnoteKit/Sources/EarnoteCore`) | Foundation, AVFoundation, Security, OSLog, Observation, SwiftData. **Kein** AppKit/UIKit/SwiftUI, keine Core-Audio-HAL-APIs, keine Drittanbieter-Pakete | Modelle (`Recording`, `Transcript`, `RecordingCategory`, `AppSettings` …), KI-Clients für Netzwerk-Anbieter, `Summarizer`, `LLMFactory`, `Transcriber`-Protokoll, `TranscriptCleanup`, Audio-Dateien (`ResamplingReader`, `AudioMixer`, `EnergyEnvelope`), Export (Markdown, Obsidian, Notion), `Storage`, `Log`, `Keychain`, Datenmodell der Bibliothek (`Library…`), `LibraryRepository`, `AudioStore`, `FileLibraryImporter`, `ProcessingPipeline`, `ProcessingQueue`, `DeviceCapabilities` |
| **EarnoteML** (`Packages/EarnoteKit/Sources/EarnoteML`) | EarnoteCore, WhisperKit, mlx-swift-lm, swift-transformers, swift-huggingface. Kein SwiftUI | `WhisperModelManager`, `WhisperKitCache`, `WhisperTranscriber`, `LocalModelManager`, `LocalLLMCache`, `LocalLLMClient`, Tokenizer-Brücke |
| **Earnote** (App-Target) | alles | Aufnahme (Mikrofon, Systemton, Live-Mitschrift), Call-Erkennung, Apple Intelligence, CLI-Clients, Apple Notizen/Bear/Craft, Mitteilungen, Stores, `AppEnvironment`, Views, `LegacyMigration` |

Plattform- und ML-Code wird über Protokolle aus EarnoteCore eingehängt:
`LLMClientProvider` (lokales Modell, Apple Intelligence, Claude Code, Codex), `TranscriberProvider` (Whisper, Apple-Spracherkennung), `DestinationProvider` (zusätzliche Exportziele).

## Wer besitzt welchen Zustand

| Zustand | Art (Guidelines Abschnitt 18) | Besitzer |
|---|---|---|
| Aufnahmen, Bereiche | gemeinsamer Domänenzustand, persistent (später synchronisiert) | `LibraryStore` (`@MainActor @Observable`, App) hält den Stand im Speicher und schreibt der Reihe nach über `LibraryRepository` |
| Einstellungen | persistente Vorliebe, pro Gerät | `LibraryStore.settings` über `SettingsRepository` (UserDefaults, nicht synchronisiert) |
| Audiodateien | lokale Dateien, nie synchronisiert | `AudioStore` |
| Laufende Aufnahme, Pause, Pegel, Live-Mitschrift | Anwendungsdienst | `RecordingController` (`@MainActor @Observable`, App); Pegel und Live-Text in eigenen `ObservableObject`s, damit nur deren Anzeigen neu zeichnen |
| Warteschlange, laufende Verarbeitung, Fortschritt | Anwendungsdienst, nur im Speicher | `ProcessingQueue` (`@MainActor @Observable`, Core); der Fortschritt existiert nur im Speicher und wird nie gespeichert |
| Auswahl, Bereichsfilter, Notiz/Transkript, Inspector | Fensterzustand | `@SceneStorage` im `MainWindow` – jedes Fenster hat seinen eigenen Stand (`LibraryStore.selection` wird nur noch von den alten Views benutzt) |
| Download-Zustand der Modelle | Anwendungsdienst | `WhisperModelManager.shared`, `LocalModelManager.shared` (bestehende Singletons, vorerst belassen) |

`AppEnvironment` erzeugt beim Start einmal Repositories, Provider, Pipeline, Warteschlange und Stores und verdrahtet sie
(z. B. „Einstellung geändert → Call-Erkennung umschalten / Zusammenfassung mit neuem Anbieter neu starten“).
Neue Typen bekommen ihre Abhängigkeiten übergeben und greifen nicht auf Singletons zu.

`AppState` ist nur noch eine Fassade (unter 100 Zeilen) für die verbliebenen alten Views (Einstellungen, Menüleiste,
Einrichtungsassistent, Bereichs-Editor) mit `@EnvironmentObject var app: AppState`. Sie leitet weiter und gibt Änderungen
der Stores als `objectWillChange` weiter. Das neue Hauptfenster benutzt sie nicht; sie wird in Phase 2b entfernt.

Beim Beenden wartet der `AppDelegate` über `LibraryStore.waitForPendingWrites()` auf noch laufende Schreibvorgänge
(`applicationShouldTerminate` → `.terminateLater`), damit eine gerade angelegte oder umbenannte Sache nicht verloren geht.

## Datenfluss: Aufnahme → Pipeline → Export

1. **Aufnahme:** `RecordingController.startRecording` legt über `LibraryStore.insert` eine `Recording` an; `RecordingSession`
   schreibt `mic.caf` und `system.caf` in den Ordner, den das Repository vorgibt. Import: `LibraryStore.importAudio` kopiert
   die Datei über das Repository.
2. **Stopp:** Status `queued`, `ProcessingQueue.enqueue`.
3. **Warteschlange:** verarbeitet nacheinander. Erneutes Einreihen oder Löschen bricht den laufenden Durchgang ab;
   beim Start setzt `resumeInterruptedWork` unterbrochene Aufnahmen fort. Ist nichts mehr zu tun, gibt `onDrain` die Modelle frei.
4. **Pipeline** (`ProcessingPipeline`, an keinen Actor gebunden, alle Abhängigkeiten injiziert):
   Mischen (0–6 %) → Stille-Prüfung → Transkription (bis 60 %) → Sprecher „Ich“/„Andere“ → Zusammenfassung (bis 95 %)
   → Export je Ziel (bereits erfolgreiche werden übersprungen, nicht eingerichtete gelten nicht als Fehler) → Audio löschen,
   wenn gewünscht → `done`/`failed` und Mitteilung. Nach jedem langen Schritt wird auf Abbruch geprüft, damit kein veralteter Stand gespeichert wird.
   Statuswechsel und Fortschritt meldet sie über `ProcessingEvents` zurück.
5. **Ablage:** Aufnahme, Transkript, Notiz und Exporte landen in der Bibliothek (`LibraryRepository`), das Audio im
   Ordner der Aufnahme (`AudioStore`). Einstellungen liegen unverändert als JSON unter `settings` in UserDefaults.
   Löschen einer Aufnahme entfernt den Datensatz (mit Transkript, Notiz, Exporten) und den Audio-Ordner.

## Datenmodell (Phase 1b)

Gespeichert wird mit **SwiftData** in `Application Support/Earnote/Library.store`. Der `ModelContainer` entsteht einmal in
`AppEnvironment`; alle Zugriffe laufen über den Actor `SwiftDataLibraryRepository` (`@ModelActor`). Das Schema ist versioniert
(`EarnoteSchemaV1`, `EarnoteMigrationPlan`) und liegt in `EarnoteCore/Library`.

| Modell | Inhalt | Beziehungen (Löschregel) |
|---|---|---|
| `LibraryRecording` | `id`, Titel, `isTitleCustom`, Zeiten, Pausen, Quelle, Sprache, `originRaw`, Systemton, importierte Datei, `statusRaw`, Fehler, `createdAt`/`modifiedAt`. **Kein Fortschritt.** | `category` → Bereich (nullify); `transcript` (cascade); `note` (cascade); `exports` (cascade) |
| `LibraryTranscript` | Engine, alle Segmente als ein JSON-Block (`.externalStorage`), `plainText` für die Suche, `wordCount` | `recording` (Inverse) |
| `LibraryNote` | aktuelle Fassung (`title`, `markdown`) und KI-Original (`generatedTitle`, `generatedMarkdown`), Anbieter, Modell, Aufgaben, Vorschau, `editedAt` | `recording` (Inverse) |
| `LibraryCategory` | `id`, Name, Emoji, Symbol, Farbe, Anweisungen, Ziele, `sortIndex` | `recordings` (nullify: Aufnahmen bleiben, ohne Bereich); `glossary` (cascade) |
| `LibraryGlossaryTerm` | `id`, Begriff, Hörfehler-Varianten, Notiz (noch ungenutzt) | `category` (nil = überall) |
| `LibraryExport` | Ziel, `stateRaw` (success/skipped/failed), Meldung, Link, Datum | `recording` (Inverse) |

**Synchronisierbar (später iCloud):** alles oben. **Lokal:** Audiodateien (`AudioStore`, `Recordings/<id>/`) und Einstellungen
(UserDefaults). iCloud-Sync ist vorbereitet, aber aus (`cloudKitDatabase: .none`), bis ein Apple-Entwicklerkonto existiert.

**CloudKit-Regeln für jedes Modell:** jedes Attribut optional oder mit Standardwert · keine eindeutigen Attribute · jede Beziehung
optional mit expliziter Inverse, keine `.deny`-Regel · Enums als String-Rohwert · große Daten mit `.externalStorage` ·
eigene stabile `id: UUID`. Ein Test (`LibrarySchemaTests`) prüft das über die Schema-API.

**Snapshot-Prinzip:** `@Model`-Objekte verlassen nie den Actor des Repositorys. Pipeline, Stores und Views arbeiten mit den
Werttypen `Recording`, `Transcript`, `Summary`, `RecordingCategory`, `ExportResult`, `GlossaryTerm`; die Modelle haben dafür
`snapshot()` und `apply(_:)`. Die Aufnahmeliste lädt Notiz-Kennzahlen, Exporte und Bereich vorab, aber nie die Transkripte.

**Übernahme alter Daten:** Beim Start liest `FileLibraryImporter` im Hintergrund einmalig `Recordings/*/meta.json`,
`transcript.json`, `summary.md.json` und die Bereiche aus UserDefaults (`categories`); erst danach lädt der `LibraryStore`.
IDs und Reihenfolge bleiben, die frühere Namens-Reparatur wird einmal angewandt, verwaiste Bereichs-Zuordnungen werden gelöst,
unterbrochene Aufnahmen wieder eingereiht, der Fortschritt verworfen. Gespeichert wird in Etappen; schon vorhandene IDs werden
übersprungen. Das Flag `libraryImportVersion` wird erst nach einem fehlerfreien Lauf gesetzt. Die alten Dateien werden nie
verändert oder gelöscht (Rückfallmöglichkeit). Ohne gespeicherte Bereiche werden die Standardbereiche angelegt.

## Mikrofon und Aufnahme (Phase 1c)

| Typ | Ort | Aufgabe |
|---|---|---|
| `AudioInputDeviceInfo`, `MicrophonePlan`, `MicrophoneEvent` | EarnoteCore (`Audio/MicrophoneSelection.swift`) | Plattformneutrale Geräteinfo, Ausweich-Reihenfolge (gewähltes Gerät → Systemstandard → eingebautes → andere echte Mikrofone, Bluetooth zuletzt, nie virtuelle) und verständliche Texte ohne Fehlernummern. Mit Tests. |
| `AudioInputDevices` | App (`Audio/`) | Core Audio: Eingabegeräte, Systemstandard, Änderungen beobachten (`@Observable`); räumt beim Start öffentliche Überbleibsel früherer Sitzungen auf |
| `MicRecorder` | App | Nimmt ein bestimmtes Gerät auf (`kAudioOutputUnitProperty_CurrentDevice`), jede (Neu-)Start mit frischer `AVAudioEngine`; wechselt bei Geräteverlust oder Konfigurationsänderung in derselben Datei auf ein Ersatzgerät |
| `RecordingSession` | App | Startet nach `MicrophonePlan` (erstes Gerät mit zweitem Versuch nach 400 ms, dann Ausweichgeräte), protokolliert jeden Versuch, räumt in fester Reihenfolge auf |
| `MicrophoneLevelMonitor` | App | Pegeltest in den Einstellungen; läuft nur, solange sie offen sind und keine Aufnahme läuft |

Die Auswahl liegt pro Gerät in `AppSettings.microphoneDeviceUID` (nil = Systemstandard) und `microphoneDeviceName`
(für die Anzeige „(nicht verbunden)“). Hinweise erscheinen über den bestehenden Hinweis-Dialog (`lastError`), bei
Wechseln während der Aufnahme zusätzlich als Mitteilung. Technische Details (Domäne, Code, Gerät, Format, Versuche)
stehen nur im Protokoll.

## Hauptfenster (Phase 2a)

Eine `WindowGroup(id: "main")` mit `MainWindow`; mehrere Fenster (⌘N) sind möglich und voneinander unabhängig.
`Settings`-Scene und `MenuBarExtra` bleiben wie bisher.

| Typ | Ort | Aufgabe |
|---|---|---|
| `MainWindow` | `Features/MainWindow/` | `NavigationSplitView` (Seitenleiste \| Liste \| Detail) plus `.inspector`, Suche, Dialoge, Fensterzustand (`@SceneStorage`), `focusedSceneValue` für die Menübefehle |
| `SidebarView` | `Features/MainWindow/` | Quellenliste: Bibliothek (Alle, Offene Aufgaben, Ohne Bereich, Probleme) und Bereiche mit Zählern, Umbenennen an Ort und Stelle, Reihenfolge per Ziehen |
| `RecordingListView`, `RecordingRow` | `Features/MainWindow/` | Nach Tagen gruppierte Liste (`@Query`), maximal drei Zeilen je Eintrag, laufende Aufnahme und Verarbeitungsfortschritt, Kontextmenü, Import per Ziehen |
| `RecordingDetailView`, `NoteView`, `TranscriptView`, `LiveRecordingView` | `Features/MainWindow/` | Notiz (Aufgaben direkt abhaken), Transkript (nachgeladen), laufende Aufnahme mit Pegeln und Live-Mitschrift, Zustände für „wird verarbeitet“, „fehlgeschlagen“, „keine Notiz“ |
| `RecordingInspector` | `Features/MainWindow/` | `Form` mit Info, Verarbeitung, Export, Audio |
| `MainToolbar` | `Features/MainWindow/` | Aufnehmen (mit Bereichs- und Mikrofonwahl, während der Aufnahme Pause/Stopp), Notiz/Transkript, Teilen, weitere Aktionen, Inspector |
| `MainWindowContext`, `EarnoteCommands` | `App/Commands/` | Menüs „Ablage“, „Aufnahme“, „Notiz“, „Bearbeiten“, „Darstellung“; die Befehle wirken über `@FocusedValue` auf das vorderste Fenster |

Regeln: Views lesen die Bibliothek direkt über `@Query` auf dem gemeinsamen `ModelContainer`, geschrieben wird nur über
`LibraryStore`. Der Fortschritt kommt aus `ProcessingQueue.progress`. `LibraryFilter`, Zähler, Tagesgruppen, Suche
(`SearchText`) und die Notiz-Blöcke (`NoteMarkdown`) liegen mit Tests in EarnoteCore (`Library/`), nicht in den Views.

## Tests

- `EarnoteCoreTests`: `cd Packages/EarnoteKit && swift test --test-product EarnoteKitPackageTests` – schnell, mit Fakes und temporären Ordnern, ohne WhisperKit/MLX.
- App-Tests (`Tests/`): Datenübernahme aus „Earmark“ und Whisper-Modellauswahl (`Phase0Tests`), Formathilfen des Hauptfensters (`MainWindowTests`).

## Nächste Schritte

- **Phase 2b – restliche Oberfläche:** Einstellungen, Einrichtungsassistent, Menüleistenfenster und Call-Hinweis nach den
  Design-Guidelines neu bauen, danach `AppState` und die Views unter `Views/Legacy/` entfernen.
- **Später – iCloud:** mit Entwicklerkonto `cloudKitDatabase` einschalten; Audio bleibt lokal.
