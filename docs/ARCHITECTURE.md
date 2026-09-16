# Architektur

Stand: Phase 1a. Die Logik liegt in einem lokalen Swift Package, die Mac-App ist eine dünne Hülle darum.
Ziel: Das iPad kann denselben Kern nutzen, und die Ablage lässt sich in Phase 1b tauschen, ohne die Pipeline anzufassen.

## Module und erlaubte Abhängigkeiten

```
Earnote (Mac-App)  ──►  EarnoteML  ──►  EarnoteCore
        └──────────────────────────────►  EarnoteCore
```

| Modul | Darf verwenden | Enthält |
|---|---|---|
| **EarnoteCore** (`Packages/EarnoteKit/Sources/EarnoteCore`) | Foundation, AVFoundation, Security, OSLog, Observation. **Kein** AppKit/UIKit/SwiftUI, keine Core-Audio-HAL-APIs, keine Drittanbieter-Pakete | Modelle (`Recording`, `Transcript`, `RecordingCategory`, `AppSettings` …), KI-Clients für Netzwerk-Anbieter, `Summarizer`, `LLMFactory`, `Transcriber`-Protokoll, `TranscriptCleanup`, Audio-Dateien (`ResamplingReader`, `AudioMixer`, `EnergyEnvelope`), Export (Markdown, Obsidian, Notion), `Storage`, `Log`, `Keychain`, Repositories, `ProcessingPipeline`, `ProcessingQueue`, `DeviceCapabilities` |
| **EarnoteML** (`Packages/EarnoteKit/Sources/EarnoteML`) | EarnoteCore, WhisperKit, mlx-swift-lm, swift-transformers, swift-huggingface. Kein SwiftUI | `WhisperModelManager`, `WhisperKitCache`, `WhisperTranscriber`, `LocalModelManager`, `LocalLLMCache`, `LocalLLMClient`, Tokenizer-Brücke |
| **Earnote** (App-Target) | alles | Aufnahme (Mikrofon, Systemton, Live-Mitschrift), Call-Erkennung, Apple Intelligence, CLI-Clients, Apple Notizen/Bear/Craft, Mitteilungen, Stores, `AppEnvironment`, Views, `LegacyMigration` |

Plattform- und ML-Code wird über Protokolle aus EarnoteCore eingehängt:
`LLMClientProvider` (lokales Modell, Apple Intelligence, Claude Code, Codex), `TranscriberProvider` (Whisper, Apple-Spracherkennung), `DestinationProvider` (zusätzliche Exportziele).

## Wer besitzt welchen Zustand

| Zustand | Art (Guidelines Abschnitt 18) | Besitzer |
|---|---|---|
| Aufnahmen, Kategorien, Einstellungen | gemeinsamer Domänenzustand, persistent | `LibraryStore` (`@MainActor @Observable`, App) über `RecordingRepository` / `SettingsRepository` |
| Laufende Aufnahme, Pause, Pegel, Live-Mitschrift | Anwendungsdienst | `RecordingController` (`@MainActor @Observable`, App); Pegel und Live-Text in eigenen `ObservableObject`s, damit nur deren Anzeigen neu zeichnen |
| Warteschlange, laufende Verarbeitung, Fortschritt | Anwendungsdienst, nur im Speicher | `ProcessingQueue` (`@MainActor @Observable`, Core); der Fortschritt wird in der Aufnahme nur im Speicher geändert und beim nächsten Statuswechsel mitgespeichert |
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
5. **Ablage:** `FileRecordingRepository` schreibt dasselbe Format wie bisher: ein Ordner pro Aufnahme mit
   `meta.json`, `transcript.json`, `summary.md`, `summary.md.json` und den Audiodateien.
   Einstellungen und Kategorien liegen unverändert als JSON unter `settings` und `categories` in UserDefaults.

## Tests

- `EarnoteCoreTests`: `cd Packages/EarnoteKit && swift test --test-product EarnoteKitPackageTests` – schnell, mit Fakes und temporären Ordnern, ohne WhisperKit/MLX.
- App-Tests (`Tests/Phase0Tests.swift`): Datenübernahme aus „Earmark“ und Whisper-Modellauswahl.

## Nächste Schritte

- **Phase 1b – Datenmodell:** `RecordingRepository`/`SettingsRepository` mit SwiftData implementieren (inkl. Übernahme der JSON-Dateien),
  Entscheidung macOS 14.4 vs. 15. Pipeline und Warteschlange bleiben unverändert.
- **Phase 2 – Oberfläche:** Views nach den Design-Guidelines neu bauen, direkt auf `LibraryStore`/`RecordingController`/`ProcessingQueue`
  zugreifen, Auswahl in den Fensterzustand verlegen, `AppState` entfernen.
