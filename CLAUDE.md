# Earnote

Native macOS-App (später iPad/iPhone): nimmt Vorlesungen, Meetings und Calls auf, transkribiert lokal mit WhisperKit und schreibt Notizen mit einem eingebauten MLX-Modell. Zielgruppe: Studierende ohne Technik-Kenntnisse. Kostenlos, Open Source (MIT), privat.

## Verbindlich für jede UI-Arbeit
Lies vor jeder Änderung an der Oberfläche **[docs/DESIGN_GUIDELINES.md](docs/DESIGN_GUIDELINES.md)** und halte dich daran:
native macOS-Strukturen (NavigationSplitView, Toolbar, Inspector, Commands, Settings-Scene, searchable) statt eigener Karten, Verläufe und nachgebauter Komponenten.
Bei nicht-trivialen Features zuerst den Architekturvorschlag aus Abschnitt 20 liefern, danach implementieren, danach den Review aus Abschnitt 28 durchgehen.

## Struktur (Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md))
- `Packages/EarnoteKit/Sources/EarnoteCore` – Modelle, Datenmodell der Bibliothek (`Library/`), KI-Clients, Summarizer, Export, Speicher, Pipeline, Warteschlange
- `Packages/EarnoteKit/Sources/EarnoteML` – WhisperKit und lokales MLX-Modell
- `Earnote/` – Mac-App: Stores (`LibraryStore`, `RecordingController`), `AppEnvironment`, Audioaufnahme, Views
- `AppState` ist nur eine Übergangs-Fassade für die alten Views – keine neue Logik dort einbauen

## Abhängigkeitsregeln
- `EarnoteCore`: nur Foundation, AVFoundation, Security, OSLog, Observation, SwiftData. Kein AppKit/UIKit/SwiftUI, keine Drittanbieter-Pakete.
- Keine `@Model`-Objekte über Actor-Grenzen geben: das `LibraryRepository` liefert nur Snapshots (`Recording`, `Summary` …) und IDs.
- `EarnoteML`: `EarnoteCore` + WhisperKit/MLX, kein SwiftUI.
- Plattform-Code (AppleScript, `NSWorkspace`, Core Audio, Apple Intelligence, CLI) bleibt im App-Target und wird über Protokolle eingehängt (`LLMClientProvider`, `TranscriberProvider`, `DestinationProvider`).
- Neue Stores/Services bekommen ihre Abhängigkeiten übergeben (siehe `AppEnvironment`), keine neuen `.shared`-Singletons.

## Datenmodell (SwiftData, später iCloud)
- Bibliothek (Aufnahmen, Transkripte, Notizen, Bereiche, Exporte, Wörterbuch) in SwiftData; Audio und Einstellungen bleiben lokal.
- CloudKit-Regeln für jedes `@Model`: Attribute optional oder mit Standardwert · kein `.unique`/`#Unique` · Beziehungen optional mit expliziter Inverse, keine `.deny`-Regel · Enums als String-Rohwert · große Daten `.externalStorage` · eigene `id: UUID`.
- Schema-Änderungen nur über eine neue `EarnoteSchemaV…` mit Stufe im `EarnoteMigrationPlan`.

## Arbeitsweise
- Oberflächentexte auf Deutsch, einfach und für Einsteiger verständlich.
- Neue/entfernte Swift-Dateien im App-Ordner `Earnote/`: `python3 scripts/generate_xcodeproj.py` ausführen (Package-Dateien brauchen das nicht).
- Build: `xcodebuild -project Earnote.xcodeproj -scheme Earnote -configuration Debug build`
- Kern-Tests (schnell, ohne WhisperKit/MLX): `cd Packages/EarnoteKit && swift test --test-product EarnoteKitPackageTests`
  (ein einfaches `swift test` baut zusätzlich WhisperKit und MLX und dauert viele Minuten)
- App-Tests (Datenübernahme, Whisper-Auswahl): `xcodebuild test -project Earnote.xcodeproj -scheme Earnote -destination 'platform=macOS'`
- iOS-Beweis für den Kern: `cd Packages/EarnoteKit && xcodebuild build -scheme EarnoteCore -destination 'generic/platform=iOS'`
- Release: `./scripts/build_release.sh` → `dist/Earnote.dmg`
