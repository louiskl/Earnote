# Architektur

Stand: 0.9.5. Die Logik liegt in einem lokalen Swift Package, die Mac-App ist eine dünne Hülle darum.
Die Bibliothek liegt in SwiftData und kann über iCloud (CloudKit) synchronisiert werden – abschaltbar, standardmäßig aus;
Audio bleibt in jedem Fall als lokale Datei liegen. Mindestversion: macOS 15, iOS 26. Swift-6-Sprachmodus.

## Module und erlaubte Abhängigkeiten

```
Earnote (Mac-App)  ──►  EarnoteML  ──►  EarnoteCore
        └──────────────────────────────►  EarnoteCore
```

| Modul | Darf verwenden | Enthält |
|---|---|---|
| **EarnoteCore** (`Packages/EarnoteKit/Sources/EarnoteCore`) | Foundation, AVFoundation, Security, OSLog, Observation, SwiftData. **Kein** AppKit/UIKit/SwiftUI, keine Core-Audio-HAL-APIs, keine Drittanbieter-Pakete | Modelle (`Recording`, `Transcript`, `RecordingCategory`, `AppSettings` …), KI-Clients für Netzwerk-Anbieter, `Summarizer`, `LLMFactory`, `Transcriber`-Protokoll, `TranscriptCleanup`, Audio-Dateien (`ResamplingReader`, `AudioMixer`, `EnergyEnvelope`), Export (Markdown, Obsidian, Notion), `Storage`, `Log`, `Keychain`, Datenmodell der Bibliothek (`Library…`), `LibraryRepository`, `AudioStore`, `FileLibraryImporter`, `ProcessingPipeline`, `ProcessingQueue`, `DeviceCapabilities` |
| **EarnoteML** (`Packages/EarnoteKit/Sources/EarnoteML`) | EarnoteCore, WhisperKit, mlx-swift-lm, swift-transformers, swift-huggingface. Kein SwiftUI | `WhisperModelManager`, `WhisperKitCache` (hält WhisperKit im Actor – der Typ ist nicht `Sendable`), `WhisperTranscriber`, `LocalModelCatalog` (sechs wählbare Modelle), `LocalModelManager`, `LocalLLMCache`, `LocalLLMClient`, Tokenizer-Brücke |
| **Earnote** (App-Target) | alles, dazu Sparkle | Aufnahme (Mikrofon, Systemton, Live-Mitschrift), Call-Erkennung, Apple Intelligence, CLI-Clients, Ziele mit Plattformbezug (Apple Notizen/Erinnerungen/Things/Bear/Craft), Mitteilungen, Stores, `AppEnvironment`, Views, `AppUpdater` (Sparkle), `CloudSyncStatus`, `GlobalShortcut`, `CalendarTitles` |

Plattform- und ML-Code wird über Protokolle aus EarnoteCore eingehängt:
`LLMClientProvider` (lokales Modell, Apple Intelligence, Claude Code, Codex), `TranscriberProvider` (Whisper, Apple-Spracherkennung), `DestinationProvider` (zusätzliche Exportziele).

## Wer besitzt welchen Zustand

| Zustand | Art (Guidelines Abschnitt 18) | Besitzer |
|---|---|---|
| Aufnahmen, Bereiche | gemeinsamer Domänenzustand, persistent (später synchronisiert) | `LibraryStore` (`@MainActor @Observable`, App) hält den Stand im Speicher und schreibt der Reihe nach über `LibraryRepository` |
| Einstellungen | persistente Vorliebe, pro Gerät | `LibraryStore.settings` über `SettingsRepository` (UserDefaults, nicht synchronisiert) |
| Vorgaben der Organisation | beim Start gelesen, unveränderlich | `ManagedSettings` (Konfigurationsprofil, siehe [VERWALTUNG.md](VERWALTUNG.md)); liegt über den Einstellungen, `LLMFactory` verweigert gesperrte Anbieter |
| Audiodateien | lokale Dateien, nie synchronisiert | `AudioStore` |
| Laufende Aufnahme, Pause, Pegel, Live-Mitschrift | Anwendungsdienst | `RecordingController` (`@MainActor @Observable`, App); Pegel und Live-Text in eigenen `ObservableObject`s, damit nur deren Anzeigen neu zeichnen |
| Warteschlange, laufende Verarbeitung, Fortschritt | Anwendungsdienst, nur im Speicher | `ProcessingQueue` (`@MainActor @Observable`, Core); der Fortschritt existiert nur im Speicher und wird nie gespeichert |
| Auswahl, Bereichsfilter, Notiz/Transkript, Inspector | Fensterzustand | `@SceneStorage` im `MainWindow` – jedes Fenster hat seinen eigenen Stand  |
| Download-Zustand der Modelle | Anwendungsdienst | `WhisperModelManager.shared`, `LocalModelManager.shared` (bestehende Singletons, vorerst belassen) |
| Vorverdichtetes Material einer laufenden Aufnahme | nur im Speicher, bis die Warteschlange es abholt | `PreCondensedStore` (Actor, von `AppEnvironment` an Recorder und Pipeline übergeben) |
| Stand des iCloud-Abgleichs | Anwendungsdienst, nur im Speicher | `CloudSyncStatus` wertet `NSPersistentCloudKitContainer.eventChangedNotification` aus |
| Updates | Anwendungsdienst | `AppUpdater` um Sparkles `SPUStandardUpdaterController`; Appcast unter `docs/appcast.xml`, EdDSA-signiert |

`AppEnvironment` erzeugt beim Start einmal Repositories, Provider, Pipeline, Warteschlange und Stores und verdrahtet sie
(z. B. „Einstellung geändert → Call-Erkennung umschalten / Zusammenfassung mit neuem Anbieter neu starten“).
Neue Typen bekommen ihre Abhängigkeiten übergeben und greifen nicht auf Singletons zu.

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

## Datenmodell

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

**Synchronisiert (iCloud, wenn eingeschaltet):** alles oben, in der privaten Datenbank des Nutzers
(Container `iCloud.app.earnote.Earnote`). **Immer lokal:** Audiodateien (`AudioStore`, `Recordings/<id>/`) und Einstellungen
(UserDefaults). Der Schalter steht in Einstellungen › Allgemein und wirkt ab dem nächsten Start; fehlt die Berechtigung,
öffnet `LibraryContainer.make` den Speicher ohne CloudKit weiter, statt die Bibliothek gar nicht zu öffnen.
**Doppelte nach dem Abgleich:** CloudKit kennt keine eindeutigen Attribute, also legen zwei Macs dieselben
Standardbereiche zweimal an. Nach dem Start und nach jedem Empfang (`CloudSyncStatus.onImportFinished`) ruft
`LibraryStore.mergeSyncDuplicates` `LibraryRepository.mergeDuplicates` auf: gleiche ID oder gleicher Name
(`LibraryMerge.key`) wird ein Bereich, Aufnahmen und Wörterbuch wandern mit. Der Überlebende ist auf jedem Gerät
derselbe (ältester, dann kleinste ID), sonst löschten sich die Geräte gegenseitig die Bereiche.

**CloudKit-Regeln für jedes Modell:** jedes Attribut optional oder mit Standardwert · keine eindeutigen Attribute · jede Beziehung
optional mit expliziter Inverse, keine `.deny`-Regel · Enums als String-Rohwert · große Daten mit `.externalStorage` ·
eigene stabile `id: UUID` bei allem, was die App selbst adressiert (Aufnahme, Bereich, Wörterbuch – Transkript, Notiz und
Export hängen an genau einer Aufnahme und brauchen keine). `CloudKitSchemaTests` prüft diese Regeln über die Schema-API.

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
- App-Tests (`Tests/`): Whisper-Modellauswahl (`WhisperSelectionTests`), Formathilfen und Suchzähler des Hauptfensters
  sowie die Terminauswahl des Kalenders (`MainWindowTests`), Katalog und Vorauswahl der lokalen Modelle
  (`LocalModelCatalogTests`), Lernzettel als PDF (`NoteDocumentTests`), Bereiche im `LibraryStore`
  (`LibraryStoreCategoryTests`): `xcodebuild test -project Earnote.xcodeproj -scheme Earnote -destination 'platform=macOS'`.

## Selbstaktualisierung, iCloud und Hintergrundarbeit

- **Updates:** `AppUpdater` kapselt Sparkles `SPUStandardUpdaterController`. Die Update-Datei (`docs/appcast.xml`) wird
  von `scripts/build_release.sh` erzeugt und mit einem EdDSA-Schlüssel signiert (privat im Schlüsselbund, öffentlich in
  der `Info.plist`); ausgeliefert über GitHub Pages. Sparkle vergleicht die Buildnummer, die der Projektgenerator aus
  der Version ableitet (0.9.5 → 905).
- **iCloud:** `LibraryContainer.make(url:syncsWithCloud:)` entscheidet beim Start; `CloudSyncStatus` zeigt den Stand.
  Die Signatur braucht dafür `Earnote-iCloud.entitlements` und ein Developer-ID-Profil unter `scripts/` – beides
  schaltet sich im Release-Skript von selbst zu, wenn das Profil da ist.
- **Vorverdichten:** `LiveCondenser` (Core) verdichtet während der Aufnahme fertige Blöcke des Transkripts mit derselben
  Stufe wie die Warteschlange (`Summarizer.condense`). Das Ergebnis liegt im `PreCondensedStore`, bis die Pipeline es
  abholt; fehlt es, läuft alles wie bisher.

## Nächste Schritte

- **Phase 2c erledigt:** Einstellungen (`Views/Settings/`) und Einrichtungsassistent (`Views/Onboarding/`) sind native
  `Form`-Ansichten und lesen `LibraryStore`/`RecordingController` direkt. Das eigene Design-System
  (`Views/Components/`, `Views/Legacy/`) ist gelöscht; geblieben ist `Support/Brand.swift` für Zeichen und Call-Hinweis.
- **Phase 3a/3b erledigt:** Notiz bearbeiten und zurücksetzen (`LibraryRepository.restoreGeneratedNote`), Korrekturen
  (`correctTerm` über Titel, Notiz und Transkript) und das Wörterbuch (`Glossary`, `TermCorrection`). Die Pipeline gibt
  die Begriffe an Spracherkennung (`Transcriber.transcribe(hints:)`) und KI (`SummaryContext.glossary`) weiter.
- **iCloud erledigt (0.9.5):** Container, Berechtigungen, Profil und Schema stehen; der Abgleich ist zwischen zwei
  Bibliotheken nachgewiesen. Offen: zwei Wochen Dauerlauf auf zwei Macs und das Zusammenführen doppelter Bereiche.
- **Offen:** iPad und iPhone (Phase 6) auf demselben Kern – `EarnoteCore` baut bei jeder Änderung gegen iOS mit.
