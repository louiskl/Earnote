# Demo-Video: Drehbuch und Anleitung

Ziel: **45–60 Sekunden**, stumm verständlich, zeigt in drei Schritten, was Earnote macht.
Werkzeug: Screen Studio. Aufwand: etwa zwei Stunden beim ersten Mal, davon die Hälfte Vorbereitung.

Wichtigster Grundsatz: **Nicht in einem Stück drehen.** Du nimmst sechs kurze Takes auf und setzt sie
zusammen. Jeder Take darf misslingen und wird einfach wiederholt – das ist der Unterschied zwischen
einem Nachmittag Frust und einer Stunde Arbeit.

---

## 1. Vorbereitung (30 Minuten, einmalig)

### Mac ruhigstellen

- **Nicht stören** einschalten (Kontrollzentrum › Fokus). Eine Benachrichtigung im Bild bedeutet:
  Take neu.
- Menüleiste aufräumen: alles Private ausblenden. Ohnehin nimmst du nur das App-Fenster auf, aber
  wenn du doch einmal den Bildschirm zeigst, ist es zu spät.
- **Hell**, nicht dunkel. Die Website ist hell, das Video soll dazu passen – und heller Text ist auf
  dem Handy besser lesbar.

### Demo-Bibliothek statt echter Daten

**Nimm niemals deine echte Bibliothek auf.** Darin stehen echte Vorlesungen und Namen. Dafür gibt es
eine vorbereitete Beispielbibliothek – sechs Aufnahmen über mehrere Tage, vier Bereiche, Aufgaben,
Karteikarten, ein Teams-Meeting und eine Semester-Übersicht:

```bash
EARNOTE_SANDBOX=~/Desktop/earnote-demo EARNOTE_DEMO_LIBRARY=1 EARNOTE_APPEARANCE=light \
  ~/Library/Developer/Xcode/DerivedData/Earnote-*/Build/Products/Debug/Earnote.app/Contents/MacOS/Earnote \
  -AppleLanguages '(en-US)' -AppleLocale en_US
```

Für die deutsche Fassung `-AppleLanguages '(de-DE)' -AppleLocale de_DE`, für Dunkel
`EARNOTE_APPEARANCE=dark`. Ein neuer Ordner bei `EARNOTE_SANDBOX` heißt: frische Bibliothek.

**Soll im Video eine Zeitmarke angeklickt werden**, braucht die oberste Aufnahme eine Tonspur:
`EARNOTE_DEMO_AUDIO=/Pfad/zur/aufnahme.m4a` zusätzlich setzen. Am einfachsten: vorher selbst eine
kurze Aufnahme im Testbereich machen und deren `mix.caf` nehmen.

Der Demo-Modus steckt nur im Debug-Build – der liegt bereits gebaut in DerivedData.

### Fenstergröße

Stell das Earnote-Fenster auf ungefähr **1440 × 900**. Nicht größer: Auf deinem Ultrawide wirkt alles
winzig, und auf dem Handy liest dann niemand mehr etwas.

### Sprache: erst Englisch

Das Hauptvideo auf **Englisch** – Product Hunt, Hacker News, Reddit und internationale Blogs sind die
Kanäle mit Reichweite. Die deutsche Fassung ist danach schnell gedreht, weil du den Ablauf dann im
Kopf hast. Für Fachschaft und Instagram nimmst du die.

---

## 2. Screen Studio einrichten

| Einstellung | Wert | Warum |
|---|---|---|
| Aufnahmebereich | **Fenster**, nicht Bildschirm | Ultrawide-Vollbild ist auf dem Handy unlesbar |
| Bildrate | 60 fps | weiche Zooms |
| Automatischer Zoom | an | genau der Effekt, für den du das Programm hast |
| Cursor-Größe | etwa 150 % | auf dem Handy sonst unsichtbar |
| Cursor bei Stillstand ausblenden | an | ruhigeres Bild |
| Hintergrund | dezenter Verlauf, hell | dein Rot (#E8453B) nur sparsam |
| Abstand/Schatten | mittel | Fenster soll schweben, nicht kleben |
| Mikrofon | **aus** | kein Kommentar, das Video läuft stumm |
| Systemton | **aus** | sonst hörst du dich selbst aus der Aufnahme |
| Kamera | siehe unten | |

### Kamera: ja, aber nur außen

Dein Gesicht am Anfang für acht Sekunden und am Ende für fünf – **nicht während der Demo.** Während
du die App zeigst, verdeckt die Blase genau das, worauf es ankommt. Menschen unterstützen Menschen:
Die zwei Einstellungen mit dir sind auf Product Hunt mehr wert als jede Funktion, die du zeigst.

Wenn dir das unangenehm ist, lass sie weg. Ein Video ohne Gesicht ist besser als eines, in dem du
verkrampft wirkst.

---

## 3. Die Takes

### Take 1 — Die Aufnahme beginnt (5 Sek.)

Menüleisten-Symbol anklicken, **„Aufnehmen"** drücken. Der rote Punkt erscheint, die Zeit läuft.

*Nicht hetzen.* Nach dem Klick zwei Sekunden stehen bleiben, damit der Zoom nachkommt.

### Take 2 — Es läuft (8 Sek.)

Hauptfenster, Laufzeit läuft, Wellenform bewegt sich. Sprich dabei drei, vier Sätze – irgendetwas
Fachliches, das die KI später zusammenfassen kann. Zum Beispiel:

> „Heute geht es um Eigenwerte. Ein Eigenwert ist der Faktor, um den ein Eigenvektor gestreckt wird.
> Man berechnet ihn über das charakteristische Polynom. Wichtig für die Klausur am zwölften Februar."

**Sprich wirklich** – es soll ja eine echte Notiz entstehen. Die Tonspur schneidest du später weg.

### Take 3 — Stopp (4 Sek.)

Auf **Stopp** klicken. Die Aufnahme wandert in die Liste, der Status wechselt auf „Wird transkribiert".

### Take 4 — Die Verarbeitung (10 Sek. Rohmaterial)

Einfach laufen lassen und aufnehmen, wie der Fortschrittsbalken wandert und der Status von
„Transkribiert" auf „Fasst zusammen" springt. Das kürzt du später auf zwei Sekunden – **hier
entsteht der Zeitraffer, der dein Video ehrlich und trotzdem kurz macht.**

### Take 5 — Die fertige Notiz (12 Sek.)

Die Notiz steht: Überschrift, Zusammenfassung, Themen, Aufgaben zum Abhaken. Langsam scrollen –
**halb so schnell, wie es sich richtig anfühlt.** Dann eine Aufgabe abhaken.

### Take 6 — Die Zeitmarke (8 Sek.)

Auf „Beides" schalten, im Transkript auf eine Zeitmarke klicken, der Ton springt an die Stelle, die
Zeile wird hervorgehoben.

**Das ist der Moment, bei dem die Leute „oh" denken.** Nimm ihn zweimal auf und nimm den besseren.

### Take 7 — Der Beweis (6 Sek.)

Einstellungen öffnen, zum Bereich **KI** – dort steht „Lokale KI", kein Konto, kein Anmeldefeld.
Kurz stehen lassen.

Das ist dein Alleinstellungsmerkmal, und es braucht keine Erklärung, wenn man es sieht.

---

## 4. Schnitt

### Reihenfolge und Längen

| Abschnitt | Länge | Material |
|---|---|---|
| Gesicht: „Hi, ich bin Louis, Student. Ich hab das gebaut, weil …" | 8 Sek. | Kamera |
| Aufnahme startet | 4 Sek. | Take 1 |
| Es läuft | 5 Sek. | Take 2 |
| Stopp | 3 Sek. | Take 3 |
| Verarbeitung im Zeitraffer | 3 Sek. | Take 4, stark gerafft |
| Die Notiz | 10 Sek. | Take 5 |
| Zeitmarke anklicken | 7 Sek. | Take 6 |
| Lokale KI | 5 Sek. | Take 7 |
| Gesicht + Adresse | 5 Sek. | Kamera |
| **Gesamt** | **50 Sek.** | |

### Zooms

Screen Studio setzt sie automatisch auf deine Klicks. Danach die Zeitleiste durchgehen und
**aufräumen statt hinzufügen**: Zwei Zooms in zwei Sekunden machen seekrank. Faustregel: ein Zoom
alle vier bis fünf Sekunden, und bei der Notiz lieber ganz herausgezoomt bleiben, damit man die
Struktur sieht.

### Tempo

Alles darf langsamer wirken, als es sich beim Schneiden anfühlt. Du kennst die App – dein Zuschauer
sieht sie zum ersten Mal und braucht pro Bild ungefähr doppelt so lange wie du.

---

## 5. Untertitel

Screen Studio erzeugt ein Transkript und setzt es als Untertitel – **lokal auf deinem Mac, nichts
wird hochgeladen.** Das passt zu Earnote und du kannst es im Zweifel sogar erwähnen.

- **Eingebrannt, nicht als Datei.** Auf Reddit, LinkedIn und Product Hunt gibt es keine
  Untertitelspur – eine `.srt` daneben sieht niemand.
- Groß genug fürs Handy: lieber zu groß als zu klein, zwei Zeilen maximal.
- Unten mittig, aber **nicht ganz am Rand** – Instagram und TikTok legen dort ihre Bedienelemente drüber.
- Nach dem Erzeugen **einmal durchlesen.** Namen und Fachbegriffe erwischt jede Spracherkennung falsch,
  auch diese.

Für die Passagen ohne Sprache (Take 1 bis 7) setzt du stattdessen **kurze Texteinblendungen**:

| Wann | Text (EN) | Text (DE) |
|---|---|---|
| Aufnahme startet | Start the recording | Aufnahme starten |
| Während der Aufnahme | Earnote writes along | Earnote schreibt mit |
| Verarbeitung | 90 minutes → ready in three | 90 Minuten → in drei fertig |
| Notiz | Summary, topics, tasks | Zusammenfassung, Themen, Aufgaben |
| Zeitmarke | Every timestamp is a button | Jede Zeitmarke ist ein Knopf |
| Einstellungen | Everything stays on your Mac | Alles bleibt auf deinem Mac |
| Schluss | Free · Open source · earnote.dev | Kostenlos · Open Source · earnote.dev |

Drei bis fünf Wörter pro Einblendung. Wer mehr liest, schaut nicht mehr hin.

---

## 6. Ton

**Keine Musik.** Auf Reddit, LinkedIn und Product Hunt laufen Videos stumm – wenn deine Aussage an
der Musik hängt, ist sie für vier von fünf Zuschauern weg. Und Musik aus einer Mediathek klingt
nach Werbung, was genau der Eindruck ist, den du nicht willst.

Deine Sprache aus Take 2 schneidest du weg. Was bleibt: die acht Sekunden, in denen du selbst ins
Bild sprichst – mit Untertiteln.

---

## 7. Exportieren

| Wohin | Format | Hinweise |
|---|---|---|
| **Website** (oben statt des Bildes) | MP4, 1920 breit, **ohne Ton**, Endlosschleife | unter 5 MB halten, sonst lädt die Seite träge |
| **Product Hunt** | MP4, 1080p | erstes Bild zählt – dein Gesicht oder die fertige Notiz |
| **Reddit** | MP4, 1080p, direkt hochladen | kein YouTube-Link, der wird schlechter ausgespielt |
| **Instagram / TikTok** | 9:16, Screen Studios vertikaler Export | passt die Zooms selbst an |
| **YouTube** | 4K, als „nicht gelistet" | nur als Link für Creator und Presse |
| **GitHub-README** | GIF unter 10 MB **oder** Verweis aufs MP4 | GitHub spielt MP4 im README nicht ab |

---

## 8. Die fünf häufigsten Fehler

1. **Zu schnell.** Der mit Abstand häufigste. Im Zweifel jeden Abschnitt eine Sekunde länger.
2. **Zu viel zeigen.** Karteikarten, PDF-Lernzettel, Export nach Notion – alles gut, alles hier
   falsch. Drei Schritte: aufnehmen, warten, lesen. Der Rest steht auf der Website.
3. **Echte Daten im Bild.** Demo-Modus benutzen. Einmal kurz die echte Bibliothek zu sehen, und du
   drehst alles neu.
4. **Benachrichtigung im Bild.** „Nicht stören" an, bevor du anfängst.
5. **Untertitel nicht gegengelesen.** Ein falsch geschriebener Fachbegriff im ersten Video ist
   ausgerechnet dort peinlich, wo du für Transkriptqualität wirbst.

---

## 9. Vor dem Hochladen

- [ ] Auf dem Handy angeschaut – stumm. Verstanden, worum es geht?
- [ ] Erstes Bild aussagekräftig (nicht schwarz, nicht Schreibtisch)
- [ ] Untertitel gegengelesen, Namen und Begriffe richtig
- [ ] Keine echten Daten, keine Namen, keine Benachrichtigungen im Bild
- [ ] `earnote.dev` am Ende, lang genug zum Lesen (drei Sekunden)
- [ ] Unter 60 Sekunden
- [ ] Vertikale Fassung für Instagram und TikTok exportiert

---

**Wenn es fertig ist:** schick es mir. Ich baue es auf der Website oben ein, schreibe den passenden
Abschnitt ins README und hake die offenen Punkte in Roadmap und [Launch-Mappe](LAUNCH.md) ab.
