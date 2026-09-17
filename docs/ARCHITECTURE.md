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
| Auswahl im Hauptfenster | Fensterzustand | vorerst `LibraryStore.selection`, zieht in Phase 2 in die Scene |
| Download-Zustand der Modelle | Anwendungsdienst | `WhisperModelManager.shared`, `LocalModelManager.shared` (bestehende Singletons, vorerst belassen) |

`AppEnvironment` erzeugt beim Start einmal Repositories, Provider, Pipeline, Warteschlange und Stores und verdrahtet sie
(z. B. „Einstellung geändert → Call-Erkennung umschalten / Zusammenfassung mit neuem Anbieter neu starten“).
Neue Typen bekommen ihre Abhängigkeiten übergeben und greifen nicht auf Singletons zu.

`AppState` ist nur noch eine Fassade (unter 100 Zeilen) für die bestehenden Views mit `@EnvironmentObject var app: AppState`.
Sie leitet weiter und gibt Änderungen der Stores als `objectWillChange` weiter. Sie wird in Phase 2 entfernt.

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

## Tests

- `EarnoteCoreTests`: `cd Packages/EarnoteKit && swift test --test-product EarnoteKitPackageTests` – schnell, mit Fakes und temporären Ordnern, ohne WhisperKit/MLX.
- App-Tests (`Tests/Phase0Tests.swift`): Datenübernahme aus „Earmark“ und Whisper-Modellauswahl.

## Nächste Schritte

- **Phase 2 – Oberfläche:** Views nach den Design-Guidelines neu bauen, Listen direkt mit `@Query` auf dem gemeinsamen
  `ModelContainer`, Auswahl in den Fensterzustand verlegen, `AppState` entfernen.
- **Später – iCloud:** mit Entwicklerkonto `cloudKitDatabase` einschalten; Audio bleibt lokal.
