# Datenschutz bei Earnote

Kurz: **Earnote sammelt nichts.** Aufnahmen, Transkripte und Notizen bleiben auf deinem Mac, es gibt keine
Konten, keine Analyse, keine Telemetrie und keinen Server, der zu Earnote gehört.

## Wo deine Daten liegen

| Was | Wo |
|---|---|
| Aufnahmen (Audio) | `~/Library/Application Support/Earnote/Recordings/` – werden **nie** synchronisiert |
| Transkripte, Notizen, Bereiche, Wörterbuch | SwiftData-Datenbank im selben Ordner |
| Einstellungen | Systemeinstellungen der App (`defaults`), nicht in der Cloud |
| API-Schlüssel (nur bei Cloud-KI) | macOS-Schlüsselbund |
| Protokoll | `earnote.log` im Datenordner, nur lokal, ohne Gesprächsinhalte |

Audiodateien kannst du unter *Einstellungen › Allgemein* automatisch löschen lassen, sobald die Notiz fertig ist.

## Wann Earnote ins Netz geht

1. **Modelle laden** (einmalig): Whisper von Hugging Face, das lokale Sprachmodell von Hugging Face.
2. **Update-Prüfung** (einmal am Tag): eine Anfrage an `api.github.com` nach der neuesten Version.
   Abschaltbar unter *Einstellungen › Allgemein*. Übertragen wird dabei nichts über dich außer der
   technisch unvermeidbaren IP-Adresse.
3. **Nur wenn du es ausdrücklich einstellst:**
   - eine **Cloud-KI** (Claude, OpenAI, Gemini, Mistral, eigener Server): Dann geht der Transkripttext an
     diesen Anbieter. Die App weist im Einstellungsfenster darauf hin.
   - ein **Export-Ziel** wie Notion: Dann gehen Titel, Notiz und – falls aktiviert – das Transkript dorthin.

Mit der Voreinstellung (lokale KI, Markdown-Ordner) verlässt kein Wort aus deinen Aufnahmen den Mac.

## Aufnehmen und Recht

Das nichtöffentlich gesprochene Wort ist geschützt (§ 201 StGB). Hol vor jeder Aufnahme das Einverständnis
aller Beteiligten ein – bei Vorlesungen also auch der dozierenden Person. Earnote blendet dazu vor jeder
Aufnahme einen Hinweis ein, der sich abschalten lässt; die Verantwortung liegt bei dir.

## Löschen

Eine Aufnahme löschst du im Fenster mit ⌘⌫ – Audio, Transkript und Notiz verschwinden zusammen.
Alles auf einmal: den Ordner `~/Library/Application Support/Earnote` in den Papierkorb legen.
Bereits exportierte Notizen (Notion, Obsidian …) musst du dort selbst löschen.
