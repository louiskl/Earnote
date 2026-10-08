# Produktplan nach 1.0 – Ideen, Einordnung, Fahrplan

> Stand 07.10.2026 · erstellt im Marketing-Chat (Claude), Entscheidungen von Louis markiert.
> Earnote 1.0 ist seit Anfang Oktober im App Store (iPhone, iPad, Mac M1+), Mac-DMG 1.0, offizieller Launch 13.10.
> Dieses Dokument ist der Auftrag für den Produkt-/Entwicklungs-Chat. Es ergänzt [ROADMAP.md](ROADMAP.md)
> (Phase 8) und [PRO.md](PRO.md) und muss mit deren Regeln zusammenpassen (Regeln gegen Überladung, Regel 9
> „Drei Geräte, ein Stand“, „Was nie Pro wird“).

## Ziel

Mehr Downloads **und** mehr Pro-Käufe, weil Pro echten Mehrwert hat – nicht aus Sympathie (Louis, 07.10.:
„Die Nutzer sollen Pro wegen des Mehrwerts kaufen, nicht nur um mich zu supporten.“). Neue Funktionen kommen
**schnell**, im Takt des Semesters: jetzt laufen die Vorlesungen, ab Mitte Januar die Klausurphase.

## Scope – was Earnote ist (Louis, 07.10.2026)

**Earnote schreibt für dich mit.** Vorlesung, Unterricht oder Meeting aufnehmen oder importieren – Transkript,
Notiz, Karteikarten und PDF kommen von selbst. Lokal, privat, **die komplette Kette, kostenlos, ohne Abo**.
Wir wollen in dieser Nische die beste App sein – keine eierlegende Wollmilchsau der Lern-Apps, nichts, was
überladen oder halbfertig wirkt.

**Was uns abhebt:** die ganze Kette in einer App (Aufnahme → Transkript → Notiz → Lernen/Weitergeben), lokale KI,
alles Wichtige kostenlos, Pro als Einmalkauf statt Abo.

**Filter für jede neue Funktion** – sie kommt nur, wenn sie mindestens eins davon tut:
1. Die Mitschrift wird **besser** (genauer, vollständiger: Folien, Formeln, Tafelfoto, Sprecher).
2. **Mehr kommt rein** (Import, Aufzeichnungen der Uni, weniger Tippen beim Start).
3. **Der Weg danach wird kürzer** (die Notiz landet fertig dort, wo sie gebraucht wird: Klausurlernen aus den
   eigenen Vorlesungen, Protokoll, Export für Word/Anki/MAXQDA).

**Und keins davon:** eigener Ort oder eigenes Lernsystem (Lernplan, Quiz-App, Vokabeltrainer), Coaching
(Referat/Bewerbung üben), Spielerei für Screenshots. Earnote übergibt lieber an Apps, die das schon gut können.

## Leitlinien für Pro oder kostenlos

- **Kostenlos bleibt der Hauptweg:** aufnehmen/importieren → Transkript → Notiz → Karteikarten → PDF → teilen.
  Alles, was heute kostenlos ist, bleibt es (entschieden 25.09.2026).
- **Kostenlos wird auch alles, was Earnote verbreitet** (Teilen, Widgets, Rückblick): Jede geteilte Datei wirbt.
- **Pro ist, was vor der Klausur oder bei der Arbeit spürbar Stunden spart** – meist ein zusätzlicher KI-Schritt
  oder ein Spezialformat. Jede Pro-Funktion ist dreimal gratis (`Pro.freeTries`).
- **Mac:** Pro-Funktionen sind dort frei (entschieden 25.09.2026), Funktionen kommen trotzdem auf alle drei
  Geräte in derselben Version (Regel 9).

## Brainstorming – alle Ideen, eingeordnet

**Nutzen** 1–5 (wie sehr es Studierende begeistert bzw. ein Kaufgrund ist) · **Aufwand** S (≤ 2 Tage) ·
M (≤ 1 Woche) · L (> 1 Woche) · **Prio** A = jetzt, B = dieses Semester, C = später, – = vorerst nicht.

### Lernen und Klausur

| Idee | Was genau | Nutzen | Aufwand | Pro/Free | Prio |
|---|---|---|---|---|---|
| **Folien einbinden** ⭐ Louis | PDF-Folien/Skript zur Aufnahme legen. Die KI kennt Fachbegriffe und Formeln von den Folien, die Notiz verweist auf „Folie 12“, Tippen öffnet die Folie. Folientext bleibt auf dem Gerät (PDFKit) | 5 | M–L | **Pro** | **A** |
| **Probeklausur je Fach** ⭐ Louis | Aus allen Notizen eines Bereichs 10–20 Prüfungsfragen (Wissen, Verständnis, Rechnen), Antwort tippen oder sprechen, KI korrigiert mit Verweis auf Vorlesung und Stelle im Transkript. Platz: Klausur-Radar | 5 | M | **Pro** | **A** |
| Mündliche Prüfung üben | Earnote stellt eine Frage per Sprache, du antwortest laut, Feedback: was gefehlt hat. Baut auf Probeklausur auf | 5 | M | Pro | B |
| Klausurtermin + Countdown | Termin je Bereich eintragen, Countdown im Bereich und als Widget, Klausur-Radar sortiert danach | 3 | S | Free | **A** |
| Vorlesung zum Anhören | Notiz als 5-Minuten-Hörfassung mit der Gerätestimme, offline, für Bahn und Spaziergang | 4 | S–M | Pro | B |
| Mindmap der Vorlesung | Notiz als Mindmap ansehen und als Bild/PDF teilen | 3 | M | Pro | C |
| Lernzettel-Designs | PDF als Cornell, kompakt (1 Seite) oder Spickzettel-Format | 3 | S | Pro | B |
| Glossar je Fach | Alle Begriffe und Definitionen eines Bereichs an einer Stelle, durchsuchbar | 3 | S–M | Free | C |
| Semester-Übersicht am iPhone | Gibt es am Mac schon (Gleichstand) | 3 | S | Free | B |
| Lernplan mit Wiederholung | Karten nach Abständen, „heute fällig“ | – | M | – | **– (Louis: nicht interessant)** |

### Aufnahme und Import

| Idee | Was genau | Nutzen | Aufwand | Pro/Free | Prio |
|---|---|---|---|---|---|
| **Vorlesungsvideo importieren** | **Geht schon** über „Teilen“ (EarnoteShare nimmt `public.movie`). Fehlt: ein sichtbarer Knopf „Datei importieren“ in der App (Dateien-App, Downloads aus Moodle/ILIAS), Hinweis im Onboarding/Leerzustand. Viele Hochschulen stellen Aufzeichnungen bereit – das umgeht das Aufnahmeverbot im Hörsaal | 5 | S | Free | **A** |
| Tafelfoto in die Notiz | Während der Aufnahme fotografieren, Bild landet an der passenden Zeitstelle, Text per Vision-OCR in die Notiz | 4 | M | Free (Foto) / Pro (OCR in Notiz) | B |
| Live-Untertitel am iPhone | Gleichstand zum Mac (IPHONE.md 1.2), „30 s zurück“ | 3 | M | Free | B |
| Apple Watch | Aufnahme starten/stoppen, „Wichtig“ am Handgelenk | 3 | M | Free (Wichtig = Pro) | C |
| Stundenplan-Erkennung | Aufnahme bekommt Fach und Titel aus dem Kalender (Mac kann das) | 3 | S | Free | B |

### Arbeit, Interviews, Gruppen

| Idee | Was genau | Nutzen | Aufwand | Pro/Free | Prio |
|---|---|---|---|---|---|
| **Interview-Export für die Abschlussarbeit** | Transkript nach Regeln (z. B. Dresing & Pehl): Sprecherkürzel, Zeitmarken je Absatz, Zeilennummern, als DOCX/RTF/TXT für MAXQDA/Word | 5 (Nische) | S–M | **Pro** | **A** |
| Protokoll verschicken | Aufgaben je Person (aus Sprechern), ein Tipp schickt es per Mail/Nachricht, „erstellt mit Earnote“ | 4 | S | Pro | B |
| Vorlagen | Daily, 1:1, Kundengespräch, Interview-Leitfaden, Vereinssitzung – steuern Aufbau der Notiz | 3 | S–M | Free (fertige) / Pro (eigene) | B |
| Fragen über ein ganzes Fach | Chat über alle Notizen eines Bereichs („Was hat der Prof zu Eigenwerten gesagt?“) | 4 | M | Pro | B |

### Teilen und Wachstum (alles Free)

| Idee | Was genau | Nutzen | Aufwand | Prio |
|---|---|---|---|---|
| Karteikarten-Stapel teilen | Als Datei/AirDrop, öffnet direkt in Earnote, sonst App-Store-Link | 4 | M | B |
| Semester-Rückblick | Teilbares Bild wie „Wrapped“: Stunden aufgenommen, Fächer, Karten gelernt | 4 | S | C (Ende Februar) |
| Widgets | Klausur-Countdown, letzte Notiz, „Aufnahme starten“ | 3 | S | A (mit Countdown) |
| Kurs-Gruppen | Bereich mit Kommilitonen teilen (iCloud-Freigabe) | 4 | L | C |

## Nach dem Scope-Filter (07.10.2026)

**Bleibt:** Import sichtbar · Pro sichtbar · Folien einbinden · Interview-Export · Protokoll verschicken ·
Probeklausur je Fach (lernen aus den *eigenen* Vorlesungen, Platz im Klausur-Radar) · Anki-Export der Karteikarten
(**gibt es schon** auf allen drei Geräten – nur bewerben) · Formeln in Notiz und PDF (neu, Free) · Stundenplan-Erkennung am iPhone · Tafelfoto · Live-Untertitel
am iPhone · später Fragen über ein ganzes Fach, Apple Watch.

**Fliegt raus** (eigenes Lernsystem, Coaching oder nur Beiwerk): Klausurtermin + Countdown-Widget, Mündliche
Prüfung / Sprechen üben, Vorlesung zum Anhören, Mindmap, Lernzettel-Designs, Glossar, Lernplan, Karteikarten-Stapel
in Earnote teilen (Anki-Export deckt es ab), Semester-Rückblick, Vorlagen (Bereichs-Anweisungen decken es ab),
Diktat-Modus, Wochenrückblick, Kurs-Gruppen.

## Versionierung

- **Eine Nummer für Mac, iPhone und iPad** (Regel 9). Mac per Sparkle/DMG, iPhone/iPad über App Store Connect.
- **1.0.x = nur Fehler**, jederzeit, so oft wie nötig (Review dauert meist 1–2 Tage).
- **1.x = Funktions-Update**, Takt **alle zwei Wochen**, Einreichen montags, live bis Donnerstag.
- **Regel 8 (Aufräumen):** nach drei Funktions-Updates eine kurze Aufräum-Version.
- Jede Version: Release-Notiz in `docs/releases/<Version>.md`, „Neu in Earnote“ in der App, ROADMAP-Zeile.
- Während der Klausurphase (ca. 18.01.–28.02.) **keine großen Umbauten**, nur Fehler und Kleines.

## Fahrplan

| Version | Einreichen | Inhalt | Pro/Free | Marketing dazu |
|---|---|---|---|---|
| 1.0.x | laufend | Fehler aus Launch-Feedback, Bewertungen, Abstürze | – | Antworten auf Kommentare |
| **1.1** | Mo 26.10. (live vor 31.10.) | Vorlesungen importieren sichtbar · Pro sichtbar machen · Feinschliff aus dem Launch-Feedback | Free + Pro-Hinweise | Video „Deine Uni lädt Vorlesungen hoch? So lernst du daraus“ |
| **1.2** | Mo 09.11. | **Folien einbinden** | Pro | „Folien + Aufnahme = perfekte Notiz“, Presse-Nachfass |
| **1.3** | Mo 23.11. | Interview-Export (Abschlussarbeit) · Protokoll verschicken | Pro / Pro | Bachelorarbeit-Videos; Anki-Export (gibt es schon) für Medizin/Jura bewerben |
| 1.4 | Mo 30.11. | Aufräumen (Regel 8): Menüs, Texte, Geschwindigkeit, Akku | – | – |
| **1.5** | Mo 14.12. | **Probeklausur je Fach** | Pro | „Probeklausur aus deinen Vorlesungen“ – über Weihnachten |
| 1.6 | Mo 11.01. | Formeln in Notiz und PDF · Stundenplan-Erkennung am iPhone | Free | MINT-Content zur Klausurphase |
| – | 18.01.–28.02. | Klausurphase: nur Fehler | – | – |
| 1.7+ | März | Tafelfoto · Live-Untertitel am iPhone · Aufräumen | Free / Pro (OCR) | Sommersemester-Start |
| später | – | Fragen über ein ganzes Fach · Apple Watch | Pro / Free | – |

## Pro sichtbar machen (gehört in 1.1)

Heute erscheint die Pro-Seite erst, wenn die drei Versuche einer Funktion verbraucht sind – die meisten sehen Pro
nie. Plan (ohne Foto, ohne „unterstütz mich“, nur Nutzen):
1. **Pro-Hinweis passend zur Aufnahme** nach einer fertigen Notiz (neuer `FeedbackMoment`, ab der 2. Notiz,
   höchstens alle 14 Tage, höchstens 4×): die eine Pro-Funktion, die bei *dieser* Aufnahme hilft (mehrere
   Stimmen → Sprecher, Klausur-Abschnitt → Radar, fremde Sprache → Übersetzen, Folien vorhanden → Folien …),
   Knopf „Ausprobieren – noch N× gratis“.
2. **Pro-Funktionen an ihrem Platz zeigen** mit kleinem „PRO“-Abzeichen und Restversuchen („Noch 2 von 3 gratis“).
3. **ProSheet** zeigt oben die Funktion, von der man kam, mit einem konkreten Beispiel. „Einmalig · kein Abo“ bleibt.
4. Dankeschön-Paket-Hinweis nicht mehr gleichzeitig mit Pro-Hinweisen.
Keine erfundenen Zahlen, keine künstliche Verknappung. Roadmap-Regel 6 („Pro wirbt leise“) gilt weiter.

## Offene Fragen an Louis (vor dem Bauen klären)

1. Preis: Bleibt Pro bei 9,99 €, wenn Folien und Probeklausur dazukommen? (Vorschlag: ja bis 1.5, dann neu bewerten –
   Bestandskunden behalten alles.)
2. Folien einbinden: nur PDF, oder auch PowerPoint/Keynote? (Vorschlag: nur PDF; PPTX → „als PDF exportieren“.)
3. Probeklausur: Darf die Korrektur auch die Cloud-KI (eigener Google-Schlüssel) nutzen, wenn das Gerät zu schwach ist?
4. Interview-Export: welches Format zuerst – Dresing & Pehl als DOCX? (Vorschlag: DOCX + TXT.)

## Arbeitsweise für den Entwicklungs-Chat

- Je Funktion: Architekturvorschlag (DESIGN_GUIDELINES Abschnitt 20) → Louis sagt ja → bauen → Review
  (Abschnitt 28) → ein Branch, ein PR. Logik in `EarnoteCore` mit Tests, Oberfläche je Plattform.
- ROADMAP.md (Phase 8, Überblickstabelle, Gleichstand) und PRO.md bei jeder Entscheidung nachziehen.
- Den Marketing-Chat informieren, sobald eine Version eingereicht ist (Videos und Posts werden darauf geplant).
