# Earnote Pro

> Stand: 07.10.2026 · Kauf auf iPhone und iPad. Am Mac (DMG, kein App Store) sind die Pro-Funktionen frei (entschieden 25.09.2026).
> Neue Pro-Funktionen und Takt: [PRODUKTPLAN.md](PRODUKTPLAN.md), [ROADMAP.md](ROADMAP.md) Phase 8.

## Grundsatz
Alles, was Earnote heute kostenlos kann, bleibt kostenlos: Aufnehmen, Transkript, Notiz, Export, Abgleich, PDF,
Karteikarten. Kostenlos wird auch alles, was Earnote verbreitet (Teilen, Widgets, Rückblick). Pro ist, was vor der
Klausur oder bei der Arbeit spürbar Stunden spart – Kaufgrund ist der Nutzen, nicht Unterstützung. Jede Pro-Funktion ist dreimal gratis. Einmalzahlung (9,99 €), kein Abo – Earnote hat keine
laufenden Kosten pro Nutzer (eigene KI-Schlüssel oder lokale KI).

## Kauf
- Produkt `app.earnote.Earnote` (so in App Store Connect angelegt, nicht änderbar), Nicht-Verbrauchsartikel, Familienfreigabe an
- `Pro` (EarnoteiOS/Services/Pro.swift): Merker `pro`, Probeversuche je Funktion (`Pro.freeTries` = 3), Pro-Hinweis `ProView`/`ProSheet`
- Alle Käufe laufen durch `TipJar` (ein Zuhörer auf `Transaction.updates`); Pro schaltet auch das Dankeschön-Paket frei, eine Erstattung nimmt Pro wieder weg
- Test-Fassungen: Einstellungen › Test › „Pro freischalten“

## Funktionen
| Funktion | Stand | Wo |
|---|---|---|
| Fragen zur Notiz (Chat) | ✅ | `NoteChat` (Kern, getestet), `NoteChatView`; Knopf in der Notiz. Die KI bekommt die Notiz und die 3 Transkript-Minuten mit den meisten Wörtern der Frage. Ein Gespräch = ein Probeversuch |
| „Wichtig!“ + Klausur-Radar | ✅ | Knopf „Wichtig“ in der Aufnahme und in der Live-Aktivität (`MarkImportantIntent`) → `marks.json` im Ordner der Aufnahme (`ImportantMarks`). Die Verarbeitung gibt der KI die markierten Stellen mit Zitat (25 s davor) → Abschnitt „Wichtig für die Klausur“. `ExamRadarView` je Bereich sammelt die Prüfungs-Abschnitte aller Notizen (`ExamRadar.items`, ohne KI), teilbar. Probeversuch: erste Markierung je Aufnahme. Grenze: Markierungen bleiben auf dem Gerät (Weg B kennt sie nicht) |
| Übersetzen | ✅ | „Mehr › Übersetzen …“ in der Notiz: Notiz oder ganzes Transkript in 12 Sprachen (`Translation`, stückweise zu 5000 Zeichen, Zeitmarken bleiben). Übersetzte Notiz kann die bisherige ersetzen („Auf KI-Fassung zurücksetzen“ holt sie zurück). Ein Versuch je Übersetzung |
| Sprechererkennung | ✅ | FluidAudio 0.17.4 (Apache 2.0, ohne Binär-Trait) in EarnoteML: `FluidSpeakerDiarizer` (Offline-Pipeline pyannote + WeSpeaker + VBx, liest die Datei stückweise). Die Warteschlange erkennt nach der Transkription (Einstellung „Sprecher erkennen“), `Speakers.assign` trägt „Sprecher 1, 2 …“ ein (Stimmen < 2 % Redezeit fallen weg). Nachträglich: „Mehr › Sprecher erkennen“; „Sprecher benennen …“ ändert Transkript und Notiz. Ein Versuch je Aufnahme (`Pro.GatedDiarizer`). **Messung** (M1 Air, künstliches Gespräch mit 2 Stimmen): 30 min Audio in 46 s, 343 von 344 Redebeiträgen richtig; Modelle ~0,5 s aus dem Cache |
| Pro sichtbar machen | geplant 1.1 | Hinweis nach fertiger Notiz passend zur Aufnahme (neuer `FeedbackMoment`, ab 2. Notiz, höchstens alle 14 Tage, höchstens 4×), „PRO“-Abzeichen mit Restversuchen am Platz der Funktion, `ProSheet` zeigt die Funktion, von der man kam. Kein Gesicht, keine erfundenen Zahlen |
| Folien einbinden | geplant 1.2 | PDF zur Aufnahme (PDFKit, bleibt auf dem Gerät), KI kennt Fachbegriffe, Notiz verweist auf „Folie 12“ |
| Interview-Export | geplant 1.3 | Transkript nach Dresing & Pehl (Sprecherkürzel, Zeitmarken, Zeilennummern) für MAXQDA/Word |
| Protokoll verschicken | geplant 1.3 | Aufgaben je Person aus den Sprechern, Teilen-Menü der Notiz |
| Probeklausur je Fach | geplant 1.5 | 10–20 Fragen aus allen Notizen eines Bereichs, KI korrigiert mit Verweis auf Vorlesung; im Klausur-Radar |
| Mündliche Prüfung, Vorlesung zum Anhören, Lernzettel-Designs | geplant 1.6 | siehe PRODUKTPLAN.md |
