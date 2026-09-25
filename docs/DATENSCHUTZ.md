# Datenschutz bei Earnote

Kurz: **Earnote sammelt nichts.** Aufnahmen, Transkripte und Notizen bleiben auf deinem Gerät (Mac oder iPhone), es gibt keine
Konten, keine Analyse, keine Telemetrie und keinen Server, der zu Earnote gehört.

## Wo deine Daten liegen

| Was | Wo |
|---|---|
| Aufnahmen (Audio) | Mac: `~/Library/Application Support/Earnote/Recordings/`, iPhone: im Container der App – werden nicht synchronisiert (Ausnahme: „Mit meinem Mac“, siehe unten) |
| Transkripte, Notizen, Bereiche, Wörterbuch | SwiftData-Datenbank im selben Ordner; nur mit eingeschaltetem iCloud-Abgleich zusätzlich in **deiner** privaten iCloud |
| Einstellungen | Systemeinstellungen der App (`defaults`), nicht in der Cloud |
| API-Schlüssel (nur bei Cloud-KI) | Schlüsselbund des Geräts |
| Protokoll | `earnote.log` im Datenordner, nur lokal, ohne Gesprächsinhalte |

Audiodateien kannst du unter *Einstellungen › Allgemein* automatisch löschen lassen, sobald die Notiz fertig ist.
Dort steht auch, wie viel Platz sie belegen, und dort löschst du den Ton alter Aufnahmen auf einmal.

## Wann Earnote ins Netz geht

1. **Modelle laden** (einmalig): Whisper von Hugging Face, das lokale Sprachmodell von Hugging Face, am iPhone/iPad mit eingeschalteter Sprechererkennung (Earnote Pro) deren Modelle (FluidInference, einige MB). Die Stimmen werden auf dem Gerät unterschieden, nichts davon verlässt es.
2. **Update-Prüfung** (einmal am Tag): eine Anfrage an `earnote.dev` nach der Update-Datei. Gibt es eine
   neuere Version, zeigt Earnote sie mit ihren Änderungen an und lädt sie **erst nach deiner Zustimmung**
   von GitHub. Die Update-Datei ist kryptografisch signiert, damit keine fremde Fassung untergeschoben werden kann.
   Abschaltbar unter *Einstellungen › Allgemein*. Übertragen wird dabei nichts über dich außer der
   technisch unvermeidbaren IP-Adresse.
3. **Nur wenn du es ausdrücklich einstellst:**
   - der **iCloud-Abgleich** (*Einstellungen › Allgemein*, standardmäßig aus): Dann liegen Transkripte, Notizen,
     Bereiche und Wörterbuch zusätzlich in deiner **privaten** iCloud-Datenbank, sichtbar nur für dich und deine
     Geräte mit derselben Apple-ID. Earnote hat darauf keinen Zugriff. Audiodateien werden nicht synchronisiert.
   - **„Mit meinem Mac“ am iPhone**: Die Aufnahme (Audio) liegt vorübergehend in deiner privaten iCloud, bis dein
     Mac sie verarbeitet hat; danach löscht der Mac sie dort.
   - eine **Cloud-KI** (Google Gemini, OpenRouter, Claude, OpenAI, Mistral, eigener Server): Dann geht der
     Transkripttext an diesen Anbieter, nie das Audio. Die App weist in den Einstellungen darauf hin. Google nutzt den
     Text in der EU, der Schweiz und Großbritannien auch im kostenlosen Kontingent nicht zum Training, anderswo schon;
     bei kostenlosen Modellen über OpenRouter dürfen die Anbieter ihn dafür verwenden. Google und OpenRouter setzen ein
     Alter ab 18 Jahren voraus.
   - ein **Export-Ziel** wie Notion: Dann gehen Titel, Notiz und – falls aktiviert – das Transkript dorthin.

Mit der Voreinstellung (KI auf dem Gerät, Markdown-Ordner) verlässt kein Wort aus deinen Aufnahmen das Gerät.

**TestFlight und App Store (iPhone):** Installation, Trinkgeld-Käufe und Testversionen laufen über Apple. In
TestFlight stellt Apple Absturzberichte und von dir abgeschicktes Feedback bereit; genutzt wird das nur zum
Beheben von Fehlern.

## Aufnehmen und Recht

Das nichtöffentlich gesprochene Wort ist geschützt (§ 201 StGB). Hol vor jeder Aufnahme das Einverständnis
aller Beteiligten ein – bei Vorlesungen also auch der dozierenden Person. Earnote blendet dazu vor jeder
Aufnahme einen Hinweis ein, der sich abschalten lässt; die Verantwortung liegt bei dir.

## Löschen

Eine Aufnahme löschst du im Fenster mit ⌘⌫ – Audio, Transkript und Notiz verschwinden zusammen.
Alles auf einmal: den Ordner `~/Library/Application Support/Earnote` in den Papierkorb legen.
Bereits exportierte Notizen (Notion, Obsidian …) musst du dort selbst löschen.
