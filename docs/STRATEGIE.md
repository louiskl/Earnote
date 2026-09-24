# Earnote – Strategie: Zielgruppen, Geld, Vertrieb

> Stand: 25.09.2026 · **Vorlage zur Entscheidung** (offene Punkte in Abschnitt 7) · gepflegt vom Architekten.
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
3. **Ein kleines lokales Modell** für Geräte mit 4–6 GB – gibt es noch nicht (Abschnitt 5, Punkt 1). Das ist die
   Lücke, die über die Schüler-Zielgruppe entscheidet – und nebenbei auch iPhone 11–15 ohne Pro ohne Cloud nutzbar macht.

**Empfehlung:** Studierende bleiben Zielgruppe Nummer eins bis zum Mac-Launch und zur iPhone-1.1. Schüler werden
danach gezielt angegangen – aber erst, wenn es einen Weg ohne Cloud-Schlüssel für normale iPads gibt. Sonst wäre die
erste Erfahrung für die meisten: „geht bei mir nicht“.

---

## 2. Geld verdienen, ohne den Kern zu verkaufen

### Grundsatz (entschieden 24.09.2026)
Kein Abo, nie. Aufnehmen, Transkript, Notiz, Export, Sync, Karteikarten, Lernzettel bleiben kostenlos und vollständig.
Bezahlt wird freiwillig: **Trinkgeld** und **Extras**, die schön oder bequem sind, aber niemandem fehlen.

### Was es dafür schon gibt
- Mac: Ko-fi und GitHub Sponsors (Hilfe-Menü, Einstellungen › Über, Website, README)
- iPhone: Trinkgeld per In-App-Kauf (StoreKit 2, drei Stufen) – **Produkte in App Store Connect fehlen noch**

### Vorschlag „Earnote Extras“ – ein Einmalkauf
Ein einziges Paket statt vieler Kleinkäufe: einfacher zu verstehen, kein Gefühl von „Nickel-and-Diming“.

| Extra | Warum es passt | Aufwand |
|---|---|---|
| **Weitere App-Icons** (hell, dunkel, getönt, Retro, Semesterfarben) | beliebt, schadet niemandem | klein (iOS `setAlternateIconName`, Mac `NSApp.applicationIconImage`) |
| **Lernzettel-Designs** fürs PDF (Cornell, kompakt, Karteikarten zum Ausschneiden) | Studierende drucken vor Klausuren | mittel (Vorlagen in `NotePDF`) |
| **Akzentfarben** für die App und die Live-Aktivität | Personalisierung | klein |
| **Semester-Rückblick** (Stunden aufgenommen, Fächer, Karteikarten gelernt) als teilbares Bild | macht Werbung für Earnote, fühlt sich wie ein Geschenk an | mittel |
| **Unterstützer-Abzeichen** in Einstellungen › Über | Dank, sonst nichts | klein |

**Nicht als Extra:** Sprecherlabels, Export-Ziele, Sync, längere Aufnahmen, bessere Modelle – das sind Funktionen,
die Menschen brauchen, und genau solche Sperren verärgern die, die Earnote weiterempfehlen.

**Preis:** Extras einmalig **4,99 €** (Familienfreigabe an). Trinkgeld 1,99 € / 4,99 € / 9,99 €, Trinkgeld schaltet die
Extras ebenfalls frei – wer gibt, bekommt etwas zurück.

**Apple-Regeln:** Am iPhone/iPad muss alles, was in der App freigeschaltet wird, per In-App-Kauf laufen (Richtlinie
3.1.1) – kein Link zu Ko-fi in der iOS-App (so umgesetzt). Am Mac (außerhalb des App Store) ist das frei; der einfachste
Weg: **Extras am Mac ohne Kauf freigeben** und dort weiter auf Ko-fi/Sponsors setzen. Ein Lizenzsystem für ein paar
App-Icons lohnt sich nicht und widerspricht dem Open-Source-Charakter (jeder kann den Code ohnehin selbst bauen).

**Erwartung ehrlich:** Bei freiwilligen Zahlungen geben typischerweise 1–3 % der aktiven Nutzer etwas. Bei 1.000
aktiven Nutzern sind das grob 10–30 Käufe im Monat – ein Zeichen, kein Einkommen. Geld in nennenswerter Höhe kommt
erst über Reichweite (App Store) oder später über Organisationen (ROADMAP Phase 8: Pro-Lizenz für Kanzleien, Praxen,
Firmen – einmalig, ohne Server).

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

1. **Kleines lokales Modell für Geräte mit 4–6 GB** (iPhone 11–15, iPad ohne M-Chip). Kandidat: Qwen3 1.7B (4-Bit,
   ca. 1 GB) über MLX. Notizen werden einfacher, aber „ohne Internet, ohne Konto, ohne Alter 18“. Erst messen
   (Speicher, Dauer, Qualität bei 90 Minuten mit Vorverdichten), dann entscheiden. **Entscheidet über Schüler.**
2. **iPad-Oberfläche** (Seitenleiste, Split-Ansicht, Tastatur) – Plan in [IPAD.md](IPAD.md).
3. **Automatisch erneut versuchen**, wenn Google/OpenRouter kurz ausfallen oder das Netz weg ist – statt Fehler
   in der Liste (in Arbeit).
4. **Folien neben der Aufnahme:** PDF der Vorlesung importieren, Notiz verweist auf die Folienseite. Für Studierende
   der größte inhaltliche Sprung – die KI kennt dann Formeln und Fachbegriffe.
5. **Klausur-Vorbereitung über mehrere Vorlesungen:** aus allen Notizen eines Bereichs einen Lernplan und ein
   Quiz machen („Übersicht“ gibt es schon – das wäre der nächste Schritt).
6. **„Earnote empfehlen“ am iPhone** (Teilen-Blatt mit App-Store-Link) – kleinster Wachstumshebel.

---

## 6. Kennzahlen – ohne Tracking

Earnote zählt nichts. Was trotzdem messbar ist:
- Downloads der DMG (GitHub, `scripts/stats.sh`), Besucher der Website (GoatCounter, ohne Cookies)
- App Store Connect: Installationen, Absturzberichte, Bewertungen – liefert Apple ohne eigenes Tracking
- TestFlight: Tester, Sitzungen, Feedback
- Trinkgeld/Extras-Käufe, Ko-fi, Sponsors

---

## 7. Offene Entscheidungen

| Frage | Vorschlag |
|---|---|
| Schüler als Zielgruppe | Ja, **nach** Mac 1.0 und iPhone 1.1 – und erst mit einem Weg ohne Cloud-Schlüssel für normale iPads |
| Extras | Ein Paket „Earnote Extras“ für 4,99 € einmalig, Trinkgeld schaltet es mit frei, am Mac frei |
| Erste Extras | App-Icons + Unterstützer-Abzeichen (klein), danach Lernzettel-Designs |
| Kleines lokales Modell | Messbank bauen (wie beim Modellvergleich 23.09.2026) mit Qwen3 1.7B auf iPhone 15 |
| Launch-Termin | Semesterstart Ende Oktober, wenn die Beta keine groben Fehler zeigt |
