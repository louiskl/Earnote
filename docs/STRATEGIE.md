# Earnote – Strategie: Zielgruppen, Geld, Vertrieb

> Stand: 25.09.2026 · Geld und Pro **entschieden** (Abschnitt 2), Rest Vorlage · gepflegt vom Architekten.
> Ergänzt [ROADMAP.md](ROADMAP.md) (was gebaut wird) und [LAUNCH.md](LAUNCH.md) (fertige Texte für Kanäle).

## Der Satz, auf den alles hinausläuft

**Earnote schreibt deine Vorlesung mit – kostenlos, ohne Konto und ohne dass deine Aufnahme hochgeladen wird.**

Alles, was folgt, muss diesen Satz stärken. Was ihn schwächt (Abo, Konto, Server, Werbung, beschnittene
Gratisfassung), kommt nicht.

---

## 1. Zielgruppen

| | Studierende (zuerst) | Schülerinnen und Schüler (danach) |
|---|---|---|
| Geräte | MacBook + iPhone, selten iPad | **iPad + iPhone, selten ein Mac**. Schul-iPads meist ohne M-Chip (iPad 9./10. Gen., 3–4 GB) |
| Situation | 90-Minuten-Vorlesung, Seminar, Lerngruppe, Calls | 45/90-Minuten-Unterricht, Referate, Nachhilfe, Lernvideos |
| Was sie wollen | Mitschrift, Lernzettel, Karteikarten vor der Klausur | Hefteintrag, Zusammenfassung in einfacher Sprache, Abfragen vor der Arbeit |
| Wo die Notiz entsteht | Mac (lokal), iPhone mit Mac, Google/OpenRouter | **iPad/iPhone mit Apple Intelligence oder Mac** – Cloud-Schlüssel meist nicht erlaubt (unten) |
| Wie man sie erreicht | Kommilitonen, Fachschaft, Reddit, Mac-Verzeichnisse | TikTok/Instagram („Study-Tok“), Lehrkräfte, Schul-IT über Apple School Manager |
| Recht | Einverständnis der Lehrperson | Einverständnis der Lehrkraft **und** Regeln der Schule; unter 16 keine eigene Einwilligung in Datenverarbeitung (bei Earnote unkritisch, weil nichts erhoben wird) |

**Wichtig für Schüler: Google und OpenRouter verlangen ein Mindestalter von 18 Jahren** („You must be 18 years of age or
older to use the APIs“ bzw. „at least 18 years of age“). Der Weg „Kostenlos mit Google“ ist für die meisten Schüler
also ausgeschlossen. Für sie bleiben:

1. **Apple Intelligence** auf dem Gerät – nur iPhone 15 Pro/16/17 und iPads mit M-Chip oder A17 Pro.
2. **Der Mac der Familie** (Weg B).
3. ~~Ein kleines lokales Modell für Geräte mit 4–6 GB~~ – **getestet und verworfen (25.09.2026):** Qwen3 1.7B am iPhone 15
   schafft kurze Aufnahmen (12 s → Notiz in ~20 s), bei 30+ Minuten bewegt sich der Fortschritt kaum. Zu langsam für Vorlesungen.

**Empfehlung:** Studierende bleiben Zielgruppe Nummer eins bis zum Mac-Launch und zur iPhone-1.1. Schüler kommen danach –
vor allem mit neueren Geräten (Apple Intelligence) oder dem Mac der Familie. Die Altersgrenze von Google/OpenRouter nennen
wir ehrlich, ohne Umwege zu empfehlen.

---

## 2. Geld verdienen, ohne den Kern zu verkaufen

### Grundsatz (entschieden 24./25.09.2026)
Kein Abo, nie. Aufnehmen, Transkript, Notiz, Export, Sync, Karteikarten, Lernzettel bleiben kostenlos und vollständig –
auch in Zukunft. Geld kommt aus drei freiwilligen Wegen:

| Weg | Preis | Was man bekommt | Wo |
|---|---|---|---|
| **Trinkgeld** | drei Stufen (klein/mittel/riesig) | das **Dankeschön-Paket**: 4 Farben, 3 Designs (Retro, Notizbuch, Terminal), 8 App-Symbole (u. a. Regenbogen) | iPhone/iPad |
| **Earnote Pro** | **9,99 € einmalig**, Familienfreigabe | Sprechererkennung, Fragen zur Notiz, „Wichtig“ + Klausur-Radar, Übersetzen – plus Dankeschön-Paket. Jede Funktion 3× kostenlos zum Ausprobieren | iPhone/iPad |
| **Ko-fi / GitHub Sponsors** | frei | Dank | Mac, Website |

Details und Technik: [PRO.md](PRO.md). Zweite Pro-Welle und Reihenfolge: [ROADMAP.md](ROADMAP.md) Phase 8.

**Apple-Regeln:** Am iPhone/iPad läuft alles, was freigeschaltet wird, per In-App-Kauf (Richtlinie 3.1.1) – kein Link zu
Ko-fi in der iOS-App. Am Mac (außerhalb des App Store) gibt es keine In-App-Käufe; ob die Pro-Funktionen dort frei kommen,
ist offen (Abschnitt 7).

**Erwartung ehrlich:** Bei Einmalkäufen neben einer guten Gratis-App kaufen typischerweise **2–5 %** der aktiven Nutzer,
nicht 10–20 %. Rechnung: 9,99 € − 19 % USt − 15 % Apple ≈ **7,10 €** je Kauf. Rund 40 Käufe im Jahr decken
Apple-Konto (99 €) und ein KI-Abo für eigene Tests; bei 5.000 aktiven Nutzern und 3 % wären es ~1.000 € im Jahr.
Reichweite schlägt Preis – deshalb bleibt die Gratis-Fassung stark.

---

## 3. Vertrieb und Marketing

### Reihenfolge
1. **Jetzt – TestFlight-Beta (Oktober):** öffentlicher Link, 20–30 Plätze, an Kommilitonen und deren Freunde.
   Ziel: echte Vorlesungen, Abstürze finden, zwei, drei Zitate für den App Store.
2. **Mac 1.0 + iPhone 1.1 zum Semesterstart (Mitte/Ende Oktober):** Website mit iPhone-Abschnitt, App Store,
   Show HN/Product Hunt (englisch) und r/Studium (deutsch, sobald das Reddit-Konto genug Karma hat).
3. **Winter – Klausurenphase (Januar/Februar):** Karteikarten und Lernzettel in den Vordergrund: „Aus 12 Vorlesungen
   ein Lernplan“. Das ist der Moment, in dem Studierende am meisten suchen.
4. **Danach – Schüler:** sobald es den Weg ohne Cloud-Schlüssel für normale iPads gibt.

### Kanäle, die zur Zielgruppe passen
| Kanal | Wofür | Aufwand |
|---|---|---|
| **App Store selbst** (Suche) | Wichtigster Kanal für iPhone/iPad. Schlüsselwörter: *Vorlesung mitschreiben, Transkription, Mitschrift, Karteikarten, Lernzettel, Diktiergerät, Aufnahme Notizen* | einmalig gute Screenshots + Untertitel |
| **Kurze Videos** (TikTok, Instagram Reels, YouTube Shorts) | „90 Minuten Vorlesung → Karteikarten in 2 Minuten“ – zeigen statt erklären. Muss nicht die eigene Person zeigen: Bildschirmaufnahme + Text reicht | 1 Video pro Woche |
| **Mundpropaganda** | läuft schon (Freunde leiten weiter). Verstärken: „Earnote empfehlen …“ im Menü gibt es; am iPhone fehlt es noch | klein |
| **Lehrkräfte / Schul-IT** (später) | Kostenlos + „keine Daten erfasst“ ist für deutsche Schulen ein echtes Argument (DSGVO). Verteilung über Apple School Manager kostet Schulen nichts | Datenschutz-Einseiter für Schulen |
| **Mac-Presse und Verzeichnisse** | erledigt (AlternativeTo, openalternative, MacUpdate), awesome-Listen offen | – |

### Was bewusst nicht gemacht wird
Keine bezahlte Werbung, keine Influencer-Deals, keine Plakate an der Hochschule (passt nicht zum Stil des Projekts).

---

## 4. Positionierung gegen Wettbewerber

| | Otter, Notta, Fireflies, Goodnotes-KI | Earnote |
|---|---|---|
| Preis | Abo, meist 10–20 € im Monat | kostenlos |
| Daten | Aufnahme geht auf fremde Server | bleibt auf dem Gerät (oder in der eigenen iCloud) |
| Konto | Pflicht | keins |
| Offline | nein | ja (Mac, neue iPhones) |
| Ziel | Meetings in Firmen | Vorlesungen und Lernen |

Die Botschaft ist nicht „besser als Otter“, sondern „für dich gemacht, nicht für Meetings in Firmen“.

---

## 5. Produkt: was die Zielgruppen am meisten weiterbringt

Sortiert nach Wirkung, nicht nach Aufwand.

1. ~~Kleines lokales Modell für Geräte mit 4–6 GB~~ – am iPhone 15 gemessen und verworfen (25.09.2026, zu langsam bei
   langen Aufnahmen). Nebenbefund behoben: Qwen3 1.7B dachte vor jeder Notiz minutenlang still nach (PR #22).
2. **iPad-Oberfläche** (Seitenleiste, Split-Ansicht, Tastatur) – Plan in [IPAD.md](IPAD.md).
3. **Automatisch erneut versuchen**, wenn Google/OpenRouter kurz ausfallen oder das Netz weg ist – statt Fehler
   in der Liste (in Arbeit).
4. **Folien neben der Aufnahme:** PDF der Vorlesung importieren, Notiz verweist auf die Folienseite. Für Studierende
   der größte inhaltliche Sprung – die KI kennt dann Formeln und Fachbegriffe.
5. **Klausur-Vorbereitung über mehrere Vorlesungen:** aus allen Notizen eines Bereichs einen Lernplan und ein
   Quiz machen („Übersicht“ gibt es schon – das wäre der nächste Schritt).
6. ~~„Earnote empfehlen“ am iPhone~~ – ✅ gebaut (Einstellungen › Über); nach dem Launch auf den App-Store-Link umstellen.
7. **Einstiegsfrage „Wofür nutzt du Earnote?“** (Uni · Schule · Arbeit) – passt Bereiche und Notiz-Stil an und blendet
   Unpassendes aus. Macht die App für jede Gruppe passend, ohne sie für alle voller zu machen (ROADMAP Phase 7).

---

## 6. Kennzahlen – ohne Tracking

Earnote zählt nichts. Was trotzdem messbar ist:
- Downloads der DMG (GitHub, `scripts/stats.sh`), Besucher der Website (GoatCounter, ohne Cookies)
- App Store Connect: Installationen, Absturzberichte, Bewertungen – liefert Apple ohne eigenes Tracking
- TestFlight: Tester, Sitzungen, Feedback
- Trinkgeld- und Pro-Käufe (App Store Connect), Ko-fi, Sponsors

---

## 7. Offene Entscheidungen

| Frage | Vorschlag |
|---|---|
| Schüler als Zielgruppe | Ja, **nach** Mac 1.0 und iPhone 1.1 – über neuere Geräte (Apple Intelligence) und den Mac der Familie |
| Extras / Pro | ✅ entschieden 25.09.2026: Dankeschön-Paket für jedes Trinkgeld, Earnote Pro 9,99 € einmalig (Abschnitt 2) |
| Pro am Mac | Vorschlag: frei lassen (DMG, Open Source), neu bewerten mit dem Mac App Store |
| Kleines lokales Modell | ✅ entschieden 25.09.2026: **nein** – am iPhone 15 zu langsam für lange Aufnahmen |
| Launch-Termin | Semesterstart Ende Oktober, wenn die Beta keine groben Fehler zeigt |
