# Earnote Pro

> Stand: 25.09.2026 · iPhone und iPad. Der Mac (DMG, kein App Store) bekommt Pro vorerst nicht.

## Grundsatz
Alles, was Earnote heute kostenlos kann, bleibt kostenlos: Aufnehmen, Transkript, Notiz, Export, Abgleich, PDF,
Karteikarten. Pro sind Funktionen, die darüber hinausgehen. Einmalzahlung (9,99 €), kein Abo – Earnote hat keine
laufenden Kosten pro Nutzer (eigene KI-Schlüssel oder lokale KI).

## Kauf
- Produkt `app.earnote.Earnote.pro`, Nicht-Verbrauchsartikel, Familienfreigabe an
- `Pro` (EarnoteiOS/Services/Pro.swift): Merker `pro`, Probeversuche je Funktion (`Pro.freeTries` = 3), Pro-Hinweis `ProView`/`ProSheet`
- Alle Käufe laufen durch `TipJar` (ein Zuhörer auf `Transaction.updates`); Pro schaltet auch das Dankeschön-Paket frei, eine Erstattung nimmt Pro wieder weg
- Test-Fassungen: Einstellungen › Test › „Pro freischalten“

## Funktionen
| Funktion | Stand | Wo |
|---|---|---|
| Fragen zur Notiz (Chat) | ✅ | `NoteChat` (Kern, getestet), `NoteChatView`; Knopf in der Notiz. Die KI bekommt die Notiz und die 3 Transkript-Minuten mit den meisten Wörtern der Frage. Ein Gespräch = ein Probeversuch |
| „Wichtig!“ + Klausur-Radar | ✅ | Knopf „Wichtig“ in der Aufnahme und in der Live-Aktivität (`MarkImportantIntent`) → `marks.json` im Ordner der Aufnahme (`ImportantMarks`). Die Verarbeitung gibt der KI die markierten Stellen mit Zitat (25 s davor) → Abschnitt „Wichtig für die Klausur“. `ExamRadarView` je Bereich sammelt die Prüfungs-Abschnitte aller Notizen (`ExamRadar.items`, ohne KI), teilbar. Probeversuch: erste Markierung je Aufnahme. Grenze: Markierungen bleiben auf dem Gerät (Weg B kennt sie nicht) |
| Übersetzen | ✅ | „Mehr › Übersetzen …“ in der Notiz: Notiz oder ganzes Transkript in 12 Sprachen (`Translation`, stückweise zu 5000 Zeichen, Zeitmarken bleiben). Übersetzte Notiz kann die bisherige ersetzen („Auf KI-Fassung zurücksetzen“ holt sie zurück). Ein Versuch je Übersetzung |
| Sprechererkennung | geplant | |
