# Earnote

Native macOS-App (später iPad/iPhone): nimmt Vorlesungen, Meetings und Calls auf, transkribiert lokal mit WhisperKit und schreibt Notizen mit einem eingebauten MLX-Modell. Zielgruppe: Studierende ohne Technik-Kenntnisse. Kostenlos, Open Source (MIT), privat.

## Verbindlich für jede UI-Arbeit
Lies vor jeder Änderung an der Oberfläche **[docs/DESIGN_GUIDELINES.md](docs/DESIGN_GUIDELINES.md)** und halte dich daran:
native macOS-Strukturen (NavigationSplitView, Toolbar, Inspector, Commands, Settings-Scene, searchable) statt eigener Karten, Verläufe und nachgebauter Komponenten.
Bei nicht-trivialen Features zuerst den Architekturvorschlag aus Abschnitt 20 liefern, danach implementieren, danach den Review aus Abschnitt 28 durchgehen.

## Arbeitsweise
- Oberflächentexte auf Deutsch, einfach und für Einsteiger verständlich.
- Neue/entfernte Swift-Dateien: `python3 scripts/generate_xcodeproj.py` ausführen.
- Build: `xcodebuild -project Earnote.xcodeproj -scheme Earnote -configuration Debug build`
