# Earnote – Roadmap

> Stand: 25.09.2026 (0.9.24) · gepflegt vom Architekten · Versionen sind Arbeitsstände, öffentlich wird erst 1.0.
> Zielgruppen, Geld, Vertrieb: [STRATEGIE.md](STRATEGIE.md) · Pro-Funktionen im Detail: [PRO.md](PRO.md)
> Beta läuft: [Releases](https://github.com/louiskl/Earnote/releases) · [Anleitung für Tester](BETA.md)
> Leitlinien: [DESIGN_GUIDELINES.md](DESIGN_GUIDELINES.md) · Aufbau: [ARCHITECTURE.md](ARCHITECTURE.md)

**Ziel von 1.0:** Eine ausgereifte, native Mac-App, mit der Studierende ohne Technik-Kenntnisse und ohne KI-Abo Vorlesungen, Meetings und Calls mitschreiben lassen – kostenlos, privat, lokal.

## Der rote Faden

**Earnote macht eine Sache sehr gut: Aufnahme rein, verständliche Notiz raus.** Alles andere ist Beiwerk und
muss sich diesem Weg unterordnen. Wer die App zum ersten Mal öffnet, soll sie ohne Erklärung benutzen können –
auch nach Pro, Designs und iPad.

### Regeln gegen Überladung (gelten für jede neue Funktion)
1. **Der Hauptweg bleibt frei.** Aufnehmen → Notiz lesen braucht nie mehr als zwei Tipps. Nichts Neues schiebt
   sich davor (kein Banner, kein Pflicht-Blatt, kein zusätzlicher Schritt).
2. **Kein neuer Ort ohne Not.** Drei Tabs am iPhone, eine Seitenleiste am iPad/Mac – das bleibt so. Eine neue
   Funktion bekommt einen Platz im bestehenden Gerüst (Notiz, Bereich, Aufnahme, Einstellungen), keinen eigenen Tab.
3. **Da, wo man sie braucht.** Funktionen erscheinen im Zusammenhang (Radar im Bereich, Fragen in der Notiz,
   „Wichtig“ beim Aufnehmen) – nicht als Liste von Möglichkeiten irgendwo anders.
4. **Menüs haben eine Obergrenze.** Das Menü „Mehr“ einer Notiz: höchstens 8 Einträge in höchstens 3 Gruppen.
   Die Symbolleiste einer Ansicht: höchstens 3 Knöpfe. Wer mehr will, muss etwas zusammenfassen oder streichen.
5. **Einstellungen nur für Entscheidungen, die die meisten einmal treffen.** Gute Standardwerte statt Schalter.
   Seltenes wandert unter „Weitere Optionen“. Jede neue Einstellung braucht einen Grund, warum ein Standard nicht reicht.
6. **Pro wirbt leise.** Höchstens ein Hinweis pro Situation, nie während einer Aufnahme, nie als Unterbrechung
   (`FeedbackMoment`). Gesperrtes zeigt ein Schloss, keine Werbetafel.
7. **Zwei Fragen vor jedem Feature:** Würde eine Erstnutzerin es vermissen, wenn es fehlt? Was wird dafür
   einfacher oder fällt weg?
8. **Aufräum-Stufe nach jeder Funktionswelle.** Nach zwei, drei neuen Funktionen folgt eine Version, die nur
   ordnet, streicht und vereinfacht – bevor es weitergeht.
9. **Drei Geräte, ein Stand.** Mac, iPhone und iPad sind *ein* Produkt: eine Versionsnummer, eine Release-Note mit
   allen drei, gleiche Begriffe in der Oberfläche. Eine neue Funktion kommt auf allen dreien in derselben Version –
   oder steht mit Grund in der Tabelle „Gleichstand“. Logik gehört in den Kern (`EarnoteCore`), damit jede Plattform
   nur ihre Oberfläche baut. Eine Version gilt erst als fertig, wenn alle drei gebaut und veröffentlicht sind.

### Gleichstand (Stand 25.09.2026)

Was nicht überall gleich ist – und warum. Jede Zeile ist entweder **Plattform** (geht dort nicht, bleibt so) oder
**Rückstand** (soll aufholen, mit Ziel-Version).

| Funktion | Mac | iPhone | iPad | Art |
|---|---|---|---|---|
| Veröffentlichte Version | 0.9.23 | 0.9.24 (TestFlight) | 0.9.24 (TestFlight) | **Rückstand**: Mac 0.9.24 veröffentlichen |
| Pro: Sprecher, Fragen, „Wichtig“ + Klausur-Radar, Übersetzen | – | ✅ | ✅ | **Rückstand**: am Mac frei geben (Vorschlag, Offene Entscheidungen), vor Mac 1.0 |
| Dankeschön-Paket (Designs, App-Symbole) | – | ✅ | ✅ | offen: am Mac frei oder weglassen |
| Live-Mitschrift während der Aufnahme | ✅ | – | – | **Rückstand**: iPhone/iPad (IPHONE.md, 1.2) |
| Transkription | Whisper | Apple-Spracherkennung | Apple-Spracherkennung | Plattform (Whisper auf M-iPads: IPAD.md P3, nach Bedarf) |
| Systemton, Call-Erkennung, Menüleiste | ✅ | – | – | Plattform |
| Apple Notizen, Bear, Craft, Things als Ziel | ✅ | Teilen-Menü | Teilen-Menü | Plattform (nur per AppleScript) |
| Live-Aktivität, Action-Taste, Widgets | – | ✅ | teils | Plattform |
| Oberflächensprachen | DE, EN | DE, EN | DE, EN | gleich – neue Sprachen immer auf allen dreien |

---

## Überblick

| Phase | Inhalt | Version | Status |
|---|---|---|---|
| 0 | Fundament: Code gesichert, Umbenennung Earmark → Earnote, Datenübernahme | 0.2.0 | ✅ fertig |
| 1a | Kern herauslösen: `EarnoteKit` (Core + ML), `AppState` zerlegt, schnelle Tests, iOS-Build-Beweis | 0.3.0 | ✅ fertig |
| 1b | Datenmodell: SwiftData, iCloud-tauglich, macOS 15, Speicher aufgeteilt | 0.4.0 | ✅ fertig |
| 1c | Aufnahme robust + Mikrofon auswählen | 0.5.0 | ✅ fertig |
| 2a | Neues natives Hauptfenster (Seitenleiste, Liste, Notiz, Inspector, Toolbar, Befehle, Suche, Teilen) | 0.6.0 | ✅ fertig |
| 2b | Farbe zurück, Aufnahme-Bühne, Menüleiste, Call-Banner, signierte und notarisierte Version | 0.7.0 | ✅ fertig |
| 2c | Einstellungen und Einrichtungsassistent nativ, altes Design-System entfernt | 0.7.1 | ✅ fertig |
| 3a–3g | Notiz bearbeiten, Begriffe korrigieren & Wörterbuch, PDF-Lernzettel, Suche im Transkript, saubere Transkripte, Export je Ziel | 0.7.2–0.7.5 | ✅ fertig |
| 3h | Schneller fertig: Transkription läuft schon während der Aufnahme | 0.8.0 | ✅ fertig |
| 4a | Härtefälle, öffentliches Repository, Beta-Auslieferung, Sprecherlabels nur bei Calls | 0.8.1–0.8.5 | ✅ fertig |
| 4b | Reif für andere: Player, englische Oberfläche, Nebeneinander, Suche, Kürzel, Kalender | 0.9.0–0.9.2 | ✅ fertig |
| 4c | Lernhilfen, Aufgaben-Ziele, Modellwahl, Vorverdichten, Review, Swift 6 | 0.9.3 | ✅ fertig |
| 4d | Feinschliff: Hilfe-Menü, Speicher aufräumen, ⌘G in der Notiz, Fassade entfernt, letzte Notizen in der Menüleiste | 0.9.6 | ✅ fertig |
| 4e | Stabilität: vier Abstürze, Tonverlust, iCloud-Schema, Wächter gegen stummes Scheitern | 0.9.7–0.9.13 | ✅ fertig |
| 4f | Während der Beta: Strom sparen in der Vorlesung, Wellenform in der Menüleiste, iCloud-Duplikate, Konfigurationsprofil, App-Build in der CI | 0.9.14 | ✅ fertig |
| 4g | Während der Beta: Absturz bei Gerätewechsel behoben, Karteikarten in der Notiz, Vereinfachen | 0.9.15 | ✅ fertig |
| 4h | Während der Beta: lokale KI gibt Speicher frei, Hinweis im Stromsparmodus, Qwen3 4B überall, weniger erfundene Namen/Aufgaben/Fristen | 0.9.16 | ✅ fertig |
| 4i | Während der Beta: Notiz beim Entstehen, kürzere Notizen, geprüfte Fragen/Aufgaben/Entscheidungen, 4–8 Karteikarten mit Fortschritt | 0.9.17 | ✅ fertig |
| 4j | Während der Beta: Neu schreiben ohne Datenverlust, Vereinfachen und Karteikarten aus der Notiz | 0.9.18 | ✅ fertig |
| 4k | Während der Beta: Übersicht im Hintergrund mit Knopf und ⇧⌘U, feste Zeilenhöhe in der Liste, schönere PDFs mit earnote.dev | 0.9.19 | ✅ fertig |
| 4l | Während der Beta: lokale KI lädt beim ersten Start von selbst, „Earnote empfehlen …“, Website mit gemessenen Zeiten | 0.9.20 | ✅ fertig |
| 4m | Während der Beta: lange Vorlesungen 4× schneller (Abschnitte 32k), gleichmäßige Gliederung, Vorverdichten auf Akku, Systemton-Umschalter | 0.9.21 | ✅ fertig |
| 4n | Englische Oberfläche vollständig (≈90 Texte), Call-Erkennung im Browser, „Earnote unterstützen“ | 0.9.22 | ✅ fertig |
| **Beta** | **Zwei Wochen mit Kommilitonen, danach 1.0** | 0.9.13–0.9.22 | ▶ **läuft seit 22.09.2026** |
| 5 | Launch: Website, Demo-Video, Homebrew, Beta mit Kommilitonen, Markenrecherche | 1.0 RC | ▶ teils fertig (Website, Homebrew, Updates) |
| 6a | iPhone-App: Aufnahme, Notiz, Export-Ziele, Abgleich mit dem Mac (Weg B), TestFlight | 0.9.22–0.9.23 | ✅ fertig |
| 6b | iPad: Seitenleiste, Liste und Notiz nebeneinander, Menüleiste, Tastenkürzel, Fenster | 0.9.23 | ✅ fertig (Test auf M1-iPads läuft) |
| 6c | Dankeschön-Paket (Farben, Designs, App-Symbole), „Neu in Earnote“, Bewertung, **Earnote Pro** (Sprecher, Fragen, Klausur-Radar, Übersetzen) | 0.9.24 | ✅ gebaut, ▶ Test auf dem iPhone |
| **7** | **Prüfen und aufräumen** – 0.9.24 auf Geräten testen, Menüs und Einstellungen ordnen, Einstiegsfrage „Wofür nutzt du Earnote?“ | 0.9.25 | ▶ gebaut ([#29](https://github.com/louiskl/Earnote/pull/29)), Test auf Geräten offen |
| 🚀 | **Launch: Earnote 1.0 auf Mac, iPhone und iPad** | 1.0 | **Di 13.10.2026** |
| 8 | Pro, zweite Welle – nur nach Aufräumen und Launch, eine Funktion nach der anderen | 1.2+ | geplant |
| 9 | Mac App Store prüfen (Sandbox), Kurs-Gruppen teilen | später | nach Launch |
| 10 | Organisationen: Lizenz für Kanzleien, Praxen, Firmen – nie ein Server | – | auf Zuruf |

---

## ✅ Phase 0 – Fundament (0.2.0)
- Stand gesichert, Git-Historie sauber, Tag `v0.1.1-earmark-final`
- Name zentral in `AppInfo`, Bundle-ID `app.earnote.Earnote`
- Einmalige Datenübernahme aus „Earmark“ (Ordner, Einstellungen, Schlüsselbund)
- Fehler behoben: importierte Audiodateien, vertauschtes Whisper-Modell, Wiederholungsschleifen

## ✅ Phase 1a – Kern herauslösen (0.3.0)
- Lokales Package `EarnoteKit`: `EarnoteCore` (ohne Oberfläche, läuft auf dem iPad) und `EarnoteML` (Whisper, MLX)
- `AppState` zerlegt in `LibraryStore`, `RecordingController`, `ProcessingQueue`, `ProcessingPipeline`, `AppEnvironment`
- Kern-Tests in Sekunden statt Minuten; Absturz bei völlig stiller Aufnahme behoben

## ✅ Phase 1b – Datenmodell (0.4.0)
- SwiftData-Schema V1, CloudKit-kompatibel (Sync noch aus)
- Transkript als ein Block pro Aufnahme, Notiz mit KI-Original, Wörterbuch-Modell vorbereitet
- Audio bleibt lokal (`AudioStore`), Bibliothek im `LibraryRepository`
- Bereich löschen lässt Aufnahmen stehen; Mindestversion macOS 15

---

## ✅ Phase 1c – Aufnahme robust + Mikrofon auswählen (0.5.0)
Anlass: Das USB-Mikrofon der Webcam hing, jede Aufnahme brach mit „avfaudio-Fehler 35“ ab.
- [x] Mikrofon in den Einstellungen und im Menüleisten-Menü auswählen („Systemstandard“ oder ein bestimmtes Gerät)
- [x] Gewähltes Gerät fehlt oder reagiert nicht → automatisch auf ein funktionierendes Mikrofon ausweichen und das verständlich sagen
- [x] Ein Wiederholungsversuch beim Start, sauberes Aufräumen auch beim Stopp aus der Pause
- [x] Aufnahme während eines laufenden Teams-/Zoom-Calls zuverlässig (vom Nutzer bestätigt)
- [x] Verständliche Fehlermeldungen ohne Fehlernummern; Diagnose im Log
- [x] Sicherheitsregeln für Tests mit echten Daten in `CLAUDE.md`

## ✅ Phase 2a/2b – Natives Mac-Hauptfenster (0.6, 0.7)
- [x] Stabiles Gerüst: `NavigationSplitView` (Seitenleiste → Aufnahmeliste → Notiz) + **Inspector**
- [x] Seitenleiste als echte Source List: Bibliothek (Alle, Offene Aufgaben, Probleme, Ohne Bereich) und Bereiche
- [x] Aufnahmeliste kompakt, Detail zeigt Notiz und Transkript, Inspector zeigt Bereich, Datum, Dauer, Quelle, Modell, Export-Status
- [x] Echte **Toolbar** (Aufnehmen/Stopp, Pause, Teilen, Inspector), **Menübefehle** und **Tastenkürzel**, Kontextmenüs
- [x] `.searchable` über Titel, Notizen und Transkripte
- [x] Views lesen direkt per `@Query`; `LibraryStore` schreibt nur noch
- [x] **Fassade `AppState` entfernt (0.9.5)**: Menüleisten-Symbol liest `LibraryStore` und
      `RecordingController` direkt, der Call-Hinweis bekommt nur noch eine Funktion zum Starten.
      104 Zeilen Weiterreichen weniger.
- [x] Auswahl als Fensterzustand; mehrere Fenster möglich
- [x] Einstellungen als native `Form`; Einrichtungsassistent überarbeitet
- [x] Menüleisten-App und Call-Pop-up aufgeräumt (Call-Hinweis zuletzt in 0.9.3)
- [x] Eigenes Design-System, Karten und Verläufe entfernt (übrig: `Support/Brand.swift`)
- [x] Leer-, Lade- und Fehlerzustände; schmale und breite Fenster; Dark Mode; Tastaturbedienung
- [x] Anti-Vibecoding-Review (Guidelines Abschnitt 28) – zuletzt in 0.9.3

## ✅ Phase 2c – Einstellungen und Assistent nativ (0.7.1)
- [x] Einstellungen als Szene mit sieben Tabs, jeder ein `Form` mit `.formStyle(.grouped)`; neuer Tab „Aufnahme“
- [x] Einrichtungsassistent: fünf Schritte, Kopfzeile, Inhalt, Knopfzeile – ohne Verläufe, Kacheln und eigene Knopfstile
- [x] Ziele-Schritt aus dem Assistenten entfernt (Export ist optional und steckt in den Einstellungen)
- [x] Whisper-Vorbereitung sichtbar: „Für diesen Mac vorbereiten“ (läuft nach dem Download automatisch), Status „Bereit“
- [x] Bereichs-Editor als `Form`; Vorlagen-Auswahl als Häkchenliste
- [x] Altes Design-System gelöscht (`DesignSystem.swift`, `Components.swift`, `Views/Legacy/`), übrig: `Support/Brand.swift`
- [x] Einstellungen und Assistent lesen `LibraryStore`/`RecordingController` direkt (`AppState` ist seit 0.9.5 ganz entfernt)
- [ ] Vom Nutzer zu prüfen: erster Durchlauf des Assistenten, Whisper-Vorbereitung auf dem eigenen Mac

## ✅ Phase 3 – Funktionen für 1.0 (0.7–0.8)
**3a Notiz bearbeiten (0.7.2, Fehler behoben in 0.7.3)**
- [x] Notiz direkt bearbeiten (⌘E), Titel über die Liste ändern, „Auf KI-Fassung zurücksetzen“
- [x] „Neu zusammenfassen …“ mit anderem Bereich, zusätzlicher Anweisung und wahlweise neuem Transkript

**3b Namen & Begriffe korrigieren + Wörterbuch (0.7.2)**
- [x] „Namen & Begriffe korrigieren“: eine Ersetzung gilt in Titel, Notiz und Transkript
- [x] Wörterbuch pro Bereich und global (Einstellungen › Wörterbuch), Korrekturen wandern auf Wunsch hinein
- [x] Wörterbuch als Kontext für Whisper (Prompt) und für die KI – Fehler entstehen gar nicht erst
- [ ] Vom Nutzer zu prüfen: Wirkt der Whisper-Prompt bei echten Vorlesungen? (Apple-Spracherkennung kennt keine Begriffsliste)

**3c PDF & Teilen (0.7.3)**
- [x] Sauberes PDF im Lernzettel-Layout („Als PDF sichern …“), mehrseitig
- [x] Drucken (⌘P) über den Druckdialog von macOS
- [x] Teilen über das macOS-Teilen-Menü (Notiz als Text in der Toolbar; PDF nach dem Sichern aus dem Finder)

**3d Suche (0.7.4)**
- [x] Volltextsuche in Transkripten: Fundstellen hervorgehoben, Sprung zur ersten Stelle, Anzahl der Treffer
- [x] Fundstellen auch in der Notiz hervorgehoben

**3e Transkript-Qualität (0.7.4)**
- [x] Erfundene Sätze bei Stille filtern: Abspann-Floskeln immer, Höflichkeitsfloskeln nur allein in einer Pause
- [x] „Keine Sprache erkannt“ statt Fantasie-Notiz (unter drei gesprochenen Wörtern wird nichts zusammengefasst)
- [x] Sprachaktivität vor der Transkription: Ist fast durchgehend Stille, läuft Whisper gar nicht erst
- [ ] Vom Nutzer zu prüfen: Verschwinden die erfundenen Sätze bei echten Aufnahmen – und bleibt echter Inhalt stehen?

**3f Erster Start ohne Wartefalle (0.7.2 und 0.7.5)**
- [x] Whisper-Modell direkt nach dem Download für den Chip vorbereiten (einmalig, mehrere Minuten)
- [x] Klare Anzeige im Assistenten („Läuft noch im Hintergrund“), im Hauptfenster und in der Menüleiste, solange geladen oder vorbereitet wird

**3g Export (0.7.5)**
- [x] Export-Status pro Ziel im Inspector – auch für Ziele, in die noch nie exportiert wurde
- [x] Einzelnes Ziel erneut exportieren („Erneut“), erfolgreiche Exporte bleiben stehen
- [x] Hinweis mit „Einrichten …“, wenn ein Ziel eingeschaltet, aber nicht fertig eingerichtet ist
- [x] Nebenbei: Einstellungen einer älteren Version verlieren keine Ziele mehr (fehlende Felder bekommen Standardwerte)

**3h Schneller fertig (0.8.0)**
- [x] Transkribieren läuft schon während der Aufnahme (abschnittsweise, Schnitt am letzten fertigen Satz)
- [x] Nach dem Stopp bleibt nur der letzte Abschnitt – die Warteschlange schreibt direkt die Notiz
- [x] Schalter „Schon während der Aufnahme transkribieren“ (Einstellungen › Aufnahme)
- [x] Hinweis während der Verarbeitung: zugeklappter Mac schläft und pausiert sie
- [ ] Vom Nutzer zu prüfen: Wie viel schneller ist eine 90-Minuten-Vorlesung wirklich fertig?
- [x] faster-whisper geprüft und verworfen: CTranslate2 hat kein Metal-Backend und liefe auf dem Mac
      nur auf der CPU – langsamer als WhisperKit, dazu mit Python-Abhängigkeit

## ✅ Phase 4a – Härtefälle und Beta-Auslieferung (0.8.1–0.8.5)
- [x] Festplatte voll: unter 300 MB startet keine Aufnahme, unter 1,5 GB Hinweis mit Restlaufzeit,
      beim Vollaufen wird sauber beendet statt abgebrochen
- [x] Mac schläft ein (Deckel zu): Aufnahme wird beendet und gespeichert; während der Verarbeitung weist
      eine Zeile darauf hin, dass ein zugeklappter Mac die Verarbeitung pausiert
- [x] Kein Ton seit einer Minute → Hinweis mit nächstem Schritt, statt einer stummen Aufnahme am Ende
- [x] Whisper-Download abbrechbar, halb geladene Modelle werden entfernt
- [x] Öffentliches Repository (MIT), Kern-Tests in der CI, Kurzanleitung für Beta-Tester
- [x] „Fehler melden“ als vorausgefülltes GitHub-Issue, „Diagnose kopieren“, Protokoll zeigen
- [x] Update-Hinweis (tägliche Abfrage der GitHub-Releases, abschaltbar) und `docs/DATENSCHUTZ.md`
- [x] Zeiten im Protokoll: Transkription mit Echtzeit-Faktor, Notiz, Ladezeit des lokalen Modells
- [x] Sprecherlabels nur noch bei echten Calls (an echten Vorlesungen nachgewiesen fehlerhaft)
- [x] Gerät gewechselt (0.9.12 nachgewiesen) · [ ] Berechtigung entzogen am echten Mac durchspielen

**Gemessen an zwei echten Vorlesungen (M1 Air, 16 GB):** Whisper large-v3-turbo transkribiert mit
**≈ 12× Echtzeit** (60 Min. Ton in 5 Min.), die Notiz der lokalen KI braucht 6–7 Minuten. Die gefühlte
Stunde Wartezeit kam vom zugeklappten Deckel, nicht von der Rechenleistung.

## ✅ Phase 4b – Reif für andere (0.9.0–0.9.2)
Ziel: Was eine fremde Person in der ersten Woche braucht, ohne zu fragen.

**Anhören und finden**
- [x] **Audio-Player (0.9.0)**: schmale Leiste unter Notiz und Transkript (Pause, ±15 Sekunden, Position),
      jede Zeitmarke in Transkript und Notiz springt an ihre Stelle, der laufende Absatz wird hervorgehoben,
      Bedienung auch über das Menü „Aufnahme“ (⌥Leertaste, ⌥←, ⌥→)
- [x] **Notiz und Transkript nebeneinander (0.9.2)**: dritte Ansicht „Beides“ (⌘3) als natives `HSplitView`;
      ein Klick auf eine Zeitmarke in der Notiz spielt die Stelle, das Transkript scrollt mit
- [x] **Vorwärts/rückwärts durch die Fundstellen (0.9.2)**: ⌘G und ⇧⌘G blättern im Transkript,
      die Kopfzeile zählt mit („Fundstelle 3 von 12“)

**Für alle verständlich**
- [x] **Englische Oberfläche (0.9.1)**: Deutsch steht im Quelltext und bleibt Standard, Englisch liegt als
      `en.lproj/Localizable.strings` daneben – 316 Texte der App und 79 aus dem Kern (Status, Fehlermeldungen,
      Vorlagen, Ziele). Der Projektgenerator bindet jede weitere Sprache automatisch ein.
- [x] **Erster Start ohne Internet (0.9.2)**: vor jedem Modell-Download wird geprüft, ob überhaupt ein Netz
      da ist – sonst steht sofort „Keine Internetverbindung“ mit „Erneut laden“ statt eines stummen Wartens
- [x] Anti-Vibecoding-Review über alle neuen Ansichten (Guidelines Abschnitt 28) – siehe Phase 4c

**Alltag**
- [x] **Kalender-Anbindung (0.9.2)**: Läuft ein Termin, heißt die Aufnahme wie er (Einstellungen › Aufnahme,
      fragt beim Einschalten nach Zugriff). **Kalender einzeln wählbar** – der Arbeitskalender bleibt
      draußen, Uni und Outlook zählen. Ganztägige, abgesagte, beendete und sehr lange Termine
      („Arbeit 9–17 Uhr“, über vier Stunden) zählen nicht; bei mehreren gewinnt der kürzeste.
      Vor dem Start steht der gefundene Titel im Fenster der Menüleiste und in den Einstellungen.
- [ ] Kalender später: Teilnehmende als Sprecher-Hinweis, Termin-Notizen als Kontext für die KI
- [x] **Globales Tastenkürzel (0.9.2)**: ⌃⌥⌘R startet und stoppt die Aufnahme aus jeder App heraus
      (fest vergeben, abschaltbar in Einstellungen › Aufnahme; belegt eine andere App dasselbe Kürzel,
      steht das im Protokoll)
- [x] Aufnahme aus der Menüleiste mit Bereichswahl: die Bereiche stehen als Liste im Menüleisten-Fenster,
      ein Klick wählt, der nächste nimmt auf

---

## ✅ Phase 4c – Letzter Schliff vor 1.0 (0.9.3)

**Zielgruppen schärfen**
- [x] **Karteikarten (0.9.3)**: Die KI schreibt Frage-Antwort-Karten als Abschnitt in die Notiz
      („Frage :: Antwort“), dadurch im Editor änderbar und ohne eigenes Datenmodell.
      „Karteikarten sichern (Anki) …“ schreibt eine CSV, die Anki direkt importiert.
- [x] **Aufgaben nach Apple Erinnerungen, Things und Todoist (0.9.3)**: je Bereich eine eigene Liste
      bzw. ein Projekt; Structured liest die Erinnerungslisten mit, eine eigene Anbindung braucht es nicht.
- [x] **Logseq (0.9.3)**: Seite im Graphen als Aufzählung mit Eigenschaften und TODO-Blöcken
- [x] **Semester-Zusammenfassung (0.9.3)**: Rechtsklick auf einen Bereich › „Übersicht erstellen …“ –
      Zeitraum wählen (Monat, drei, sechs Monate, alles), optional eine eigene Anweisung. Die KI liest
      die fertigen Notizen und schreibt Überblick, Themen, roten Faden, Prüfungshinweise und offene
      Aufgaben. Die Übersicht landet als eigener Eintrag im Bereich – lesbar, druckbar, exportierbar.
- [x] **Formeln bleiben stehen (0.9.3)**: Ein einzelnes Sternchen ist in Markdown ein Kursiv-Zeichen –
      aus „A*v = λ*v“ wurde beim Anzeigen „Av = λv“. Jetzt wird es geschützt (fett und Code bleiben
      unberührt), und die KI wird angewiesen, Formeln in Code-Zeichen zu setzen.
- [x] **Kurzprotokoll (0.9.3)**: „Kurzprotokoll kopieren“ und „Kurzprotokoll als Mail …“ –
      Titel, Kurzfassung, Ergebnisse und Aufgaben, ohne Themenblöcke und Transkript.
- [x] **Einfach erklärt (0.9.3)**: Schalter in Einstellungen › KI – kurze Sätze, alltägliche Wörter,
      Fachbegriffe werden beim ersten Mal erklärt
- [x] **Als Mail weiterschicken (0.9.3)**: öffnet einen Mail-Entwurf mit Titel und Notiz (geschickt wird nichts)
- [x] **Schule**: kleinere Modelle für ältere Macs – Qwen3 1.7B (1 GB) steht in der Modellauswahl

**Qualität und Modelle**
- [x] **Modellauswahl (0.9.3)**: sechs lokale Modelle von Qwen3 1.7B (1 GB, alte Macs) bis
      Qwen3 30B A3B (17 GB, ab 32 GB RAM), dazu Gemma 3 in zwei Größen. Jedes Modell zeigt Größe,
      Speicherbedarf und wofür es taugt; Modelle, die nicht in den Speicher passen, sind als solche
      gekennzeichnet statt versteckt.
- [x] **Automatische Wahl nach Gerät (0.9.3)**: „Automatisch“ nimmt, was zum Arbeitsspeicher passt
      (bis 16 GB Qwen3 4B, darüber Qwen2.5 7B). Ein bereits geladenes Modell geht der Empfehlung vor –
      ein Update zwingt niemanden zu einem neuen Download.
- [x] Modellvergleich an echten Vorlesungen (23.09.2026): Qwen3 4B schreibt echte Lernfragen und erfasst mehr Inhalt
      als Qwen2.5 7B, in derselben Zeit und mit halb so viel Arbeitsspeicher → Empfehlung überall Qwen3 4B
- [x] **Vorverdichten während der Aufnahme (0.9.3)**: Sobald wieder ein Block von ~20 000 Zeichen
      (grob 25 Minuten) transkribiert ist, verdichtet die KI ihn schon zu Arbeitsnotizen. Nach dem Stopp
      bleibt nur der Rest plus die eigentliche Notiz. Läuft nur auf Macs ab 16 GB (sonst liegen Whisper
      und Sprachmodell gleichzeitig im Speicher) und nur, wenn „Schon während der Aufnahme transkribieren“
      an ist. Schlägt es fehl, wird nach dem Stopp normal verdichtet – ohne dass jemand etwas merkt.
- [x] **3-Stunden-Vorlesung Ende-zu-Ende bestanden** (21.09.2026, vom Nutzer gefahren): keine Abstürze,
      Verarbeitung durchgelaufen
- [x] **Swift-6-Sprachmodus (0.9.3)** für Kern, ML und App. WhisperKit bleibt jetzt im Actor,
      statt das nicht-sendable Modell herauszureichen.
- [x] **Datenübernahme aus „Earmark“ entfernt (0.9.3)** – sie hat ihren Zweck erfüllt; rund 400 Zeilen
      weniger, die niemand mehr braucht. Wer noch einen Earmark-Ordner hat, muss vor dem Update
      auf 0.9.3 einmal eine ältere Version starten.

---

## ✅ Phase 4d – Feinschliff nach der Beta-Auslieferung (0.9.5–0.9.6)
- [x] **Hilfe-Menü**: Apples Platzhalter „Earnote-Hilfe“ führte ins Leere. Jetzt: Projektseite,
      Anleitung für Tester, Fehler melden, Datenschutz, Quelltext.
- [x] **Speicher aufräumen**: Einstellungen › Allgemein zeigt, wie viel die Audiodateien belegen,
      und löscht auf Wunsch den Ton alter Aufnahmen (älter als ein Monat, drei Monate oder alles).
      Notizen und Transkripte bleiben. Ein Semester Vorlesungen sind sonst schnell 30 GB.
- [x] **Notiz-Fundstellen mit ⌘G**: Die Suche blättert jetzt auch durch die Notiz, nicht nur durch
      das Transkript. Stehen beide nebeneinander, führt das Transkript den Zähler.
- [x] **Letzte Notizen in der Menüleiste (0.9.6)**: Das Menüleisten-Fenster zeigt die drei neuesten
      Aufnahmen; ein Klick öffnet sie im Hauptfenster. Die README versprach das seit Monaten.
- [x] **Fassade `AppState` aufgelöst**: siehe Phase 2a/2b

## ✅ Phase 4e – Stabilität (0.9.7–0.9.13)

Alles aus echten Abstürzen des Nutzers, nicht aus Tests. Jeder Punkt wurde am Gerät nachgeprüft.

- [x] **Absturz im Mikrofontest (0.9.7)**: Der Pegel-Block der Einstellungen erbte die MainActor-Isolation.
      Core Audio ruft ihn auf seinem eigenen Thread auf, und Swift 6 bricht dort ab. `@Sendable` macht ihn
      isolationsfrei.
- [x] **Absturz beim Aufnahmestart (0.9.9)**: `installTap` las das Eingangsformat erneut, ohne es zu prüfen.
      Fiel das Gerät dazwischen weg, warf AVFoundation eine Obj-C-Ausnahme, die Swift nicht fangen kann.
- [x] **Absturz beim Gerätewechsel im Call (0.9.11)**: Der Neustart lief mitten in der
      `AVAudioEngineConfigurationChange`-Meldung, die die Engine aus ihrem eigenen Thread verschickt,
      während sie ihre Sperren hält. Jetzt um 0,6 s aufgeschoben – das fasst zugleich die Meldungsflut
      zusammen, mit der Bluetooth-Kopfhörer beim Profilwechsel um sich werfen.
- [x] **Tonverlust beim Mikrofonwechsel (0.9.12)** – der schwerste Fehler des Tages: Der Tap wurde mit dem
      Format angebracht, das `outputFormat(forBus:)` meldete. Nach einem Gerätewechsel ist das noch das
      Format des **alten** Geräts, und der Tap liefert danach stumm gar nichts mehr. Die Aufnahme lief
      weiter, die Datei wuchs nicht. Gemessen: zwölf Gerätewechsel unter laufender Aufnahme – vorher blieb
      die Datei bei 59,7 s stehen, jetzt wächst sie um 30 von 35 Sekunden weiter.
- [x] **Unruhiges Gerät wird getauscht (0.9.12)**: Wer sich dreimal in einer Minute neu meldet, verliert
      jedes Mal gut eine Sekunde Ton. Earnote weicht dann auf ein stabiles Mikrofon aus und sagt es.
- [x] **iCloud-Schema vollständig (0.9.10)**: Production kannte `CD_editedAt` auf `CD_LibraryNote` nicht,
      weil das Schema nebenbei beim Hochladen echter Daten entstand. CloudKit lehnte dadurch **jeden**
      Export ab (CKError 12/2006). `CloudSchemaSetup` legt über `initializeCloudKitSchema` jeden Typ mit
      jedem Feld an; seit dem erneuten Deploy läuft der Abgleich.
- [x] **Standard-Bereich „Ohne Bereich“ (0.9.8)**: Aufnahmen müssen nicht mehr in einem Bereich landen –
      neu ist das die Voreinstellung.

**Vorbeugend statt reaktiv (0.9.13)** – damit diese Fehlerklassen nicht wiederkommen:
- [x] **Obj-C-Ausnahmen werden abgefangen**: AVFoundation meldet Audiofehler als `NSException`, und jede
      ungefangene beendet die App sofort – drei der vier Abstürze waren genau das. `AudioExceptions.m`
      macht daraus einen normalen Fehler, den der Ersatzgerät-Weg auffängt. Mit Test abgesichert.
- [x] **Wächter auf den Datenfluss**: Der bisherige Wächter sah auf den *Pegel* – der bleibt aber beim
      letzten Wert stehen, wenn gar nichts mehr ankommt. Jetzt zählt, wann zuletzt wirklich ein Puffer
      eintraf; zehn Sekunden Funkstille melden sich sofort statt gar nicht.
- [x] **Hinweis bei Telefonqualität**: Bluetooth-Kopfhörer fallen auf 16–24 kHz, sobald sie gleichzeitig
      Ton ausgeben. Earnote sagt das einmal je Aufnahme und nennt den besseren Weg.

**Vor 1.0 noch geprüft**
- [x] **Barrierefreiheit durchgegangen (22.09.2026)**: Die Oberfläche war schon gut instrumentiert –
      Aufnahme-Bühne mit gesprochenem Zustand, Laufzeit und Mitschrift, Listenzeilen als eine Einheit,
      Überschriften in der Notiz als Überschriften, Symbole ohne Bedeutung ausgeblendet. Zwei echte
      Lücken geschlossen: das Symbol in der **Menüleiste** (VoiceOver las „waveform“ statt des Zustands)
      und die drei Knöpfe der **Abspielleiste**.
- [x] **Modell-Download prüft den Platz** und meldet Fehler verständlich statt mit URLSession-Wortlaut
- [x] **Strom sparen während der Vorlesung (22.09.2026)**: macOS meldete „erheblicher Energieverbrauch“ –
      während einer Aufnahme liefen Live-Mitschrift, Whisper und teils das Sprachmodell gleichzeitig,
      dazu eine Wellenform mit 20 Bildern pro Sekunde. Jetzt: Wellenform und Puls ruhen, sobald das Fenster
      verdeckt oder zu ist; ohne sichtbaren Pegel tickt die Anzeige zweimal statt zehnmal pro Sekunde, und
      die Laufzeit meldet sich nur bei neuer Sekunde. Auf Akku oder im Stromsparmodus sind Live-Mitschrift
      und Vorverdichten aus (einzeln einschaltbar, Einstellungen › Aufnahme › Akku). Neu als Schalter:
      „Aufnahmen erst am Netzteil verarbeiten“ mit „Jetzt verarbeiten“ in der Liste.
- [x] Am echten Mac nachgemessen (24.09.2026, vom Nutzer): Aufnahmen in Vorlesungen deutlich angenehmer, Akku hält gut durch
- [x] Mit eingeschaltetem VoiceOver einmal durch die App gegangen (24.09.2026, vom Nutzer): passt

---

## Wann ist die Mac-App fertig? (Abnahme für 1.0)

Nicht „wenn nichts mehr einfällt“, sondern wenn diese Punkte abgehakt sind:

**Funktion**
- [x] Phase 4c abgeschlossen (Lernhilfen, Aufgaben nach Erinnerungen, Modellwahl, Vorverdichten)
- [x] **Anti-Vibecoding-Review (0.9.3)**: Call-Hinweis auf Systemtypografie und -material umgestellt,
      Farbverlauf am Knopf entfernt, Sonderschrift der Laufzeit ersetzt, Blätter vereinheitlicht,
      lange Menüs in Untermenüs („Karteikarten“, „Weitergeben“) gegliedert.

**Belastbarkeit** – an echten Daten nachgewiesen, nicht nur im Test
- [x] **3-Stunden-Vorlesung Ende-zu-Ende bestanden** (21.09.2026, vom Nutzer gefahren): keine Abstürze,
      Verarbeitung durchgelaufen
- [x] Teams- und Zoom-Calls am echten Mac aufgenommen (Systemton, Call-Erkennung) – vom Nutzer bestätigt
- [x] **Gerät gewechselt (0.9.12)**: zwölf Wechsel unter laufender Aufnahme am echten Mac, Datei wächst durch
- [x] **Härtefälle im Code geprüft (22.09.2026)**: Deckel zu → `willSleep` beendet die Aufnahme sauber
      und lässt sie verarbeiten; Platte voll → unter 300 MB wird gestoppt und gemeldet (mit Test);
      Berechtigung entzogen → vor dem Start Hinweis samt Weg in die Systemeinstellungen, währenddessen
      greift der Wächter auf den Datenfluss nach zehn Sekunden
- [x] Dieselben drei Fälle am echten Mac durchgespielt (24.09.2026, vom Nutzer): Deckel zu, Mikrofonrecht
      entzogen und Platte voll – die App reagiert jeweils richtig
- [ ] Zwei Wochen Beta mit 5–10 Kommilitonen ohne Datenverlust und ohne Absturz (**gestartet 22.09.2026**, Ende ~06.10.2026)
- [x] Swift-6-Sprachmodus an, `LegacyMigration` entfernt

**Drumherum**
- [x] Screenshots hell/dunkel in beiden Sprachen (Website, Stand 0.9.13) und Homebrew-Tap
- [x] Demo-Video (24.09.2026, auf Website und im README)
- [x] Markenrecherche Earnote abgeschlossen – frei (25.09.2026)

Erst wenn alle drei Blöcke stehen, wird aus 0.9.x die 1.0 – und erst danach beginnt Phase 6.

---

## Phase 5 – Launch (1.0 RC → 1.0)

**Name & Recht** (liegt beim Nutzer)
- [x] Markenrecherche Earnote (DPMA, EUIPO, USPTO; Klassen 9, 41, 42) – frei (25.09.2026)
- [x] Domain: **earnote.dev** (22.09.2026) – gekauft vor Abschluss der Markenrecherche
- [x] Instagram-/TikTok-Namen gesichert (25.09.2026)
- [x] Impressum und Datenschutzhinweis für die Website (`docs/impressum.html`, verlinkt aus beiden Sprachen)

**Website** (Hauptweg zum Download)
- [x] **Steht: [earnote.dev](https://earnote.dev/)** – statisch über GitHub Pages
      aus `docs/`, zweisprachig (`index.html` englisch, `de.html` deutsch), ohne Framework und ohne Tracking
- [x] Inhalt: Was es macht · Screenshot in der jeweiligen Sprache · Download-Knopf auf das neueste Release ·
      „bleibt auf deinem Mac“ · Voraussetzungen · FAQ · Link zu GitHub
- [x] **Impressum nach § 5 TMG** als eigene Seite (`impressum.html`), aus beiden Sprachen verlinkt
- [x] Demo-Video (75 s, `docs/assets/demo-en.mp4`) – als Hero auf beiden Sprachseiten
- [x] Screenshots in Hell und Dunkel, deutsch und englisch (Stand 0.9.13, `docs/assets/`)

**Verteilung**
- [x] **Direkt-Download** als Hauptweg: notarisierte DMG über GitHub Releases
- [x] **Homebrew (0.9.3)**: eigener Tap [louiskl/homebrew-earnote](https://github.com/louiskl/homebrew-earnote) –
      `brew tap louiskl/earnote && brew trust louiskl/earnote && brew install --cask earnote`.
      Der offizielle `homebrew-cask` nimmt Selbsteinreichungen erst ab 225 Sternen (oder 90 Forks/Watchern)
      und einem mindestens 30 Tage alten Repository auf – das kommt später.
- [x] **Automatische Updates (0.9.4)**: Sparkle 2.10 – einmal am Tag Appcast prüfen, Änderungen zeigen,
      auf Zuspruch installieren. Update-Datei EdDSA-signiert, `build_release.sh` erzeugt sie mit.
- [ ] Eintragen: ✅ AlternativeTo, openalternative.co, MacUpdate (eingereicht 24.09.) · awesome-mac PR #2951, awesome-macOS PR #1136 offen ·
      Reddit: neues Konto wird gefiltert – erst Karma sammeln, dann r/LocalLLaMA, r/opensource, r/Studium, r/macapps · Product Hunt, Show HN nach 1.0
- [ ] Hochschule: Fachschaften, Uni-Newsletter, Instagram/TikTok – die Zielgruppe sitzt dort, nicht auf HN

**Beta**
- [x] **5–10 Kommilitonen angeschrieben (22.09.2026)** – echte Vorlesungen, [Anleitung](BETA.md) verteilt
- [ ] Rückmeldungen einarbeiten, danach 1.0

## ✅ Phase 6 – iPad & iPhone (0.9.22–0.9.23, im App Store als 1.1)

> **24.09.2026: Start des iPhone-Plans parallel zur Beta beschlossen** (Nutzer). Plan, Funktionsliste,
> Onboarding und Architektur: **[IPHONE.md](IPHONE.md)**. Die Mac-Beta hat weiter Vorrang. iPad: **[IPAD.md](IPAD.md)** (Entwurf).

**Warum erst nach 1.0:** iCloud-Sync und eine zweite Oberfläche verdoppeln die Fehlerfläche. Solange die
Mac-App noch täglich wächst, würde jede Änderung zweimal anfallen. Der Kern (`EarnoteCore`) baut schon
heute für iOS – das bleibt die Eintrittskarte, und der iOS-Build läuft bei jeder Änderung mit.

**Reihenfolge, wenn es losgeht**
1. iCloud-Sync auf dem Mac einschalten und zwei Wochen allein damit laufen (Duplikate, Konflikte, Status)
2. iPhone als Begleit-App: nur aufnehmen und hochladen – kleiner Umfang, sofort nützlich
3. iPad eigenständig mit Whisper und lokalem Modell (M-Chip)

- [x] **iCloud-Sync läuft (22.09.2026 nachgewiesen)**: Container, Berechtigungen und Profil stehen,
      das Schema ist in Production. Zwei Bibliotheken auf demselben Mac gleichen sich ab – eine leere
      Bibliothek bekam Aufnahme und Notiz aus der Cloud. Schalter bleibt vorerst als „in Erprobung“
      gekennzeichnet und aus der Beta-Empfehlung heraus.
- [x] **Sync-Status**: Einstellungen › Allgemein zeigt „Wird verbunden … / Gleicht ab … / Aktuell (Uhrzeit)“
      bzw. den Fehlertext; jedes Ereignis steht auch im Protokoll.
- [ ] Zwei Wochen Dauerlauf auf zwei Macs (Duplikate, Konflikte, Löschungen), danach Freigabe für alle
- [x] **Duplikat-Bereinigung (22.09.2026)**: Nach jedem Empfang aus iCloud führt Earnote Bereiche mit
      gleichem Namen oder gleicher ID zusammen; Aufnahmen und Wörterbuch wandern mit, doppelte
      Wörterbuch-Einträge werden vereint. Beide Macs behalten denselben Bereich (der älteste, bei
      Gleichstand die kleinste ID) – sonst löschte jeder den des anderen. Standardbereiche haben jetzt
      feste IDs. Läuft nur mit eingeschaltetem Sync. Am echten Mac-Paar noch nachzuweisen.
- [x] **iOS-App auf demselben Kern (24.09.2026)**: eigenes Projekt `EarnoteiOS.xcodeproj` (`scripts/generate_ios_xcodeproj.py`), baut mit EarnoteCore, WhisperKit und MLX, Grundgerüst läuft im Simulator
- [x] **iPhone-App** (24./25.09.2026): Aufnahme mit Sperrbildschirm und Live-Aktivität, Notiz auf dem Gerät, mit dem Mac
      (Weg B, per Push) oder mit Google/OpenRouter; Export-Ziele wie am Mac; TestFlight
- [x] **iPad-Oberfläche** (25.09.2026): Seitenleiste, Liste und Notiz nebeneinander, Menüleiste, Tastenkürzel, Fenster ([IPAD.md](IPAD.md))
- [ ] **iPad auf M-Chip testen** (lokales Modell, 30+ Minuten, Stage Manager) – M1-Tester über TestFlight
- [ ] Whisper auf M-iPads (IPAD.md P3) – nur, wenn die Tester es brauchen

## ✅ Phase 6c – Dankeschön-Paket und Earnote Pro (0.9.24)

> Entschieden 25.09.2026 (Nutzer). Details: [PRO.md](PRO.md), Strategie: [STRATEGIE.md](STRATEGIE.md) Abschnitt 2.

- [x] **Dankeschön-Paket** für jedes Trinkgeld: 4 Farben, 3 Designs (Retro, Notizbuch, Terminal), 8 App-Symbole
      (u. a. Regenbogen) – Einstellungen › Aussehen; das Earnote-Rot bleibt kostenlos
- [x] **„Neu in Earnote“** einmal je Version, **Apples Bewertungsdialog** ab 3 Notizen, Dankeschön-Paket höchstens
      monatlich – nie während einer Aufnahme (`FeedbackMoment`)
- [x] **Earnote Pro** (9,99 € einmalig, Familienfreigabe, 3 Probeversuche je Funktion): Sprechererkennung auf dem
      Gerät, Fragen zur Notiz, „Wichtig“-Knopf + Klausur-Radar, Übersetzen
- [ ] Auf dem iPhone prüfen: Kauf (Sandbox), Sprecher mit 2–3 echten Stimmen (Dauer, Akku), Fragen und Übersetzen
      mit echter KI, „Wichtig“ auf dem Sperrbildschirm
- [ ] Mac: Pro gibt es dort nicht (kein App Store, keine In-App-Käufe) – offen, ob die Funktionen am Mac frei
      kommen oder erst mit dem Mac App Store (Offene Entscheidungen)

## Phase 7 – Prüfen und aufräumen (0.9.25)

**Warum jetzt:** In zwei Tagen kamen iPad, Designs, Pro und vier neue Funktionen dazu. Bevor irgendetwas Neues
kommt, wird geordnet (Regel 8). Ziel: Eine Erstnutzerin findet sich sofort zurecht, Fortgeschrittene finden alles.

**Bestandsaufnahme (Stand 0.9.24, iPhone)**
| Ort | Heute | Problem |
|---|---|---|
| Notiz › Mehr | ~15 Einträge: PDF, Karteikarten ×2, Anki, Bearbeiten, Begriffe korrigieren, KI-Fassung, Übersetzen, Sprecher, Vereinfachen, Neu zusammenfassen, Umbenennen, Bereich, Fenster, Löschen | über der Grenze von 8 (Regel 4) |
| Einstellungen | So entsteht die Notiz · Mac · Aufnahme (6 Zeilen) · Export · Akku · Earnote Pro · Aussehen/Unterstützen · Über | lang, Pro und Aussehen verstreut |
| Symbolleiste der Notiz | Fragen · Teilen · Mehr (+ iPad: Transkript daneben) | ok |
| Aufnahme-Blatt | Wichtig · Pause · Stopp | ok |

**Aufräumen** (PR [#29](https://github.com/louiskl/Earnote/pull/29), im Simulator durchgesehen: iPhone hell/dunkel, größte Schrift, iPad)
- [x] **Notiz-Menü:** 7 statt ~15 Einträge in drei Gruppen – *Lernen* (Lernzettel, Karteikarten ▸, Übersetzen) ·
      *Bearbeiten* (Notiz bearbeiten, Namen korrigieren …, Neu schreiben …) · Löschen. „Neu schreiben …“ fasst Vereinfachen,
      Neu zusammenfassen und die KI-Fassung zusammen, „Namen korrigieren …“ Begriffe und Sprecher.
- [x] **Notiz-Kopf im Inhalt:** Titel groß (antippen benennt um), Bereich als Menü daneben. Dabei behoben: iOS 26 klappte
      Fragen/Teilen/Mehr bei langem Titel in ein „…“ zusammen – „Fragen zur Notiz“ war am iPhone praktisch unsichtbar.
- [x] **iPad:** „Beides“ als dritte Stelle im Umschalter statt eines vierten Knopfs
- [x] **Einstellungen:** oben Notiz-Weg, Aufnahme, Export; Gruppe *Earnote* (Pro, Aussehen, Unterstützen, Über);
      ganz unten „Weitere Optionen“ (Mac-Abgleich, Audio behalten, Akku, Einstiegsfrage). Google gewählt ohne
      Schlüssel warnt jetzt orange statt ein Häkchen zu zeigen.
- [x] **Einstiegsfrage „Wofür nutzt du Earnote?“** – Uni · Schule · Arbeit: passende Bereiche (neu: „Unterricht“),
      Schule schaltet „Einfach erklärt“ ein, Arbeit die Sprechererkennung und blendet das Klausur-Radar aus
- [x] **Onboarding:** spricht alle an (nicht nur Vorlesungen), einheitliche Knöpfe, kein ✨, Abschluss „Alles bereit“
- [x] **Größte Schrift:** Liste und Notiz-Kopf brechen um statt abzuschneiden
- [x] **Pro-Blätter:** Probeversuche ehrlich („noch 2 Mal kostenlos“, bei 0 der Weg zu Pro); Übersetzen als halbes Blatt;
      Pro-Seite mit dem eigenen App-Symbol und lesbarem Hinweis, wenn der App Store nicht antwortet
- [x] **Klausur-Radar:** erklärt sich selbst; Titel einer Vorlesung öffnete die Notiz nicht (behoben)
- [x] **Mac:** gleiche Begriffe („Neu schreiben …“, „Namen korrigieren …“)
- [ ] Rückmeldungen der TestFlight-Tester und der M1-iPad-Tester einarbeiten
- [x] Bereichs-Emojis: am echten iPhone richtig (25.09.2026), nur der Simulator zeigt „?“ – App-Store-Screenshots daher vom Gerät oder mit einem Simulator, der Emojis zeigt
- [ ] Offen für eine spätere Runde: Aufnahme-Blatt und Live-Aktivität am echten Gerät durchsehen, VoiceOver-Durchgang

## 🚀 Launch – Earnote 1.0 auf Mac, iPhone und iPad: **Di 13.10.2026**

> Entschieden 25.09.2026 (Nutzer): zwei Wochen früher als geplant, alle drei Geräte als **1.0**. Bis zum Launch
> **keine neuen Funktionen** – nur Fehler, Feinschliff, Gleichstand und die Einreichung.

| Wann | Nutzer | Architekt/Entwicklung |
|---|---|---|
| **Fr 25. – So 27.09.** | 0.9.25 am iPhone testen | Fehler aus dem Test sofort beheben |
| **Mo 28.09. – Do 01.10.** | App Store Connect: Version 1.0, Datenschutz („Keine Daten erfasst“), Altersfreigabe, Pro + Trinkgelder an die Version, Einträge ES/FR/IT · iCloud-Abgleich auf zwei Geräten laufen lassen | **0.9.26**: Fehler, Pro-Funktionen am Mac frei, Dankeschön-Paket am Mac, App-Store-Screenshots (iPhone 6,9″, iPad 13″), Prüfhinweise, Durchgang am Gerät (Aufnahme-Blatt, Live-Aktivität, VoiceOver) |
| **Fr 02. – So 04.10.** | 1.0 einmal komplett durchspielen | **1.0-Kandidat** auf allen drei Geräten, Mac-Beta-Rückmeldungen bis hierhin |
| **Mo 05.10.** | **Einreichen** (iPhone/iPad, mit Pro und Trinkgeldern) | — |
| **05.–09.10.** | Prüfung (meist 1–3 Tage), Rückfragen beantworten | Ablehnungsgründe sofort beheben |
| **~09.10.** | Mac 1.0 veröffentlichen (`publish_release.sh`) | Website/README auf App Store, „Earnote empfehlen“ mit App-Store-Link |
| **Di 13.10.** | **Launch:** Fachschaften, r/Studium, Kurzvideos ([LAUNCH.md](LAUNCH.md)) | Fehler aus den ersten Tagen |

Puffer: 09.–13.10. für eine Ablehnung (beim ersten Mal mit In-App-Käufen häufig, meist Kleinigkeiten).

**Nebenher (Nutzer):**
- [x] Bank- und Steuerdaten in App Store Connect (vor 25.09.)
- [x] Vertrag für kostenpflichtige Apps aktiv (W-8BEN eingereicht 25.09.)
- [x] Small Business Program beantragt (15 % statt 30 % Provision, 25.09.2026)
- [x] Markenrecherche „Earnote“ (DPMA, TMview, USPTO; Klassen 9, 41, 42): **keine Treffer** (25.09.2026). Anmeldung (DPMA ~290 €) bewusst aufgeschoben – ab dem Launch gilt Werktitelschutz (§ 5 MarkenG); anmelden, sobald Earnote Geld bringt oder vor großer Werbung
- [x] Instagram-/TikTok-Namen gesichert (25.09.2026)

**Was dafür später kommt:** Mac-Beta-Rückmeldungen nach dem 04.10. → erstes Update nach dem Launch ·
Oberfläche auf ES/FR/IT → nach dem Launch (die App-Store-Einträge in diesen Sprachen kommen mit).

**Checkliste Einreichung**
- [ ] App-Store-Einreichung iPhone + iPad (Texte: [APPSTORE.md](APPSTORE.md)); Trinkgelder und Earnote Pro
      gehen mit der Version zur Prüfung (Screenshot des Pro-Hinweises für die Prüfinformationen)
- [ ] Screenshots iPhone 6,9″ und iPad 13″ (Emojis vom echten Gerät, der Simulator zeigt „?“)
- [ ] Mac 1.0 (Phase 5)
- [ ] Website und README: App-Store-Link statt TestFlight
- [ ] App-Store-Eintrag zusätzlich auf Spanisch (auch Mexiko, zählt für die US-Suche), Französisch, Italienisch –
      Texte fertig in [APPSTORE.md](APPSTORE.md) „Weitere Sprachen“; die Oberfläche bleibt dort Englisch

## Mehr Sprachen (nach 0.9.25)

**Warum:** Am iPhone läuft die Suche im App Store je Sprache – jede Sprache ist ein eigener Markt.
**Reihenfolge:** 1. App-Store-Eintrag (zum Launch, oben) · 2. Oberfläche auf Spanisch, Französisch, Italienisch –
erst nach dem Aufräumen in 0.9.25, sonst wird doppelt übersetzt, und **gleichzeitig auf Mac, iPhone und iPad** (Regel 9)
· 3. je Sprache eine echte Vorlesung durch die ganze Kette (Transkript, Notiz, Karteikarten) prüfen, bevor die Sprache
beworben wird · 4. weitere Sprachen nur nach den Aufrufen je Land in App Store Connect.
- [ ] Portugiesisch fehlt noch in Spracherkennung und „Sprache der Notiz“ – erst ergänzen und prüfen, dann eintragen

## Phase 8 – Pro, zweite Welle (1.2+)

Erst nach Aufräumen und Launch, **eine Funktion nach der anderen**, jede mit festem Platz (Regel 2 und 3).
Sortiert nach „würden Leute dafür zahlen“ und Aufwand:

| # | Funktion | Für wen | Platz in der App | Aufwand |
|---|---|---|---|---|
| 1 | **Protokoll verschicken** – Aufgaben je Person (aus den erkannten Sprechern), ein Tipp schickt es an alle; „erstellt mit Earnote“ wirbt mit | Arbeit, Lerngruppen | Teilen-Menü der Notiz | klein |
| 2 | **Vorlesung zum Anhören** – die Notiz als 5-Minuten-Podcast, Stimme vom Gerät, offline | alle, v. a. Pendler | Abspielleiste der Notiz | klein–mittel |
| 3 | **Probeklausur mit Korrektur** – aus allen Vorlesungen eines Bereichs, Antworten getippt oder gesprochen, KI korrigiert mit Verweis auf die Vorlesung | Uni, Schule | Klausur-Radar | mittel |
| 4 | **Lernplan bis zur Klausur** – Klausurtermin eintragen, Karteikarten mit wachsenden Abständen, täglich „8 Karten für heute“ | Uni, Schule | Bereich (Klausurtermin), Mitteilung | mittel |
| 5 | **Apple Watch** – Aufnahme starten und „Wichtig“ am Handgelenk | Uni | eigene Watch-App, sonst nichts Neues | mittel |
| 6 | **Live-Untertitel** – Text läuft während der Aufnahme mit, „30 s zurück“ (Mac hat Live-Transkription schon) | internationale und schwerhörige Studierende | Aufnahme-Blatt | mittel |

Weitere Ideen (ohne Reihenfolge): Folien/Skript (PDF) importieren, damit die KI Fachbegriffe kennt und auf
Folienseiten verweist · Semester-Rückblick als teilbares Bild · Lernzettel-Designs fürs PDF (Cornell, kompakt).

**Was nie Pro wird:** Aufnehmen, Transkript, Notiz, Export, Abgleich, PDF-Lernzettel, Karteikarten – alles, was
heute kostenlos ist (entschieden 25.09.2026).

## Phase 9 – Später (Mac App Store, Kurs-Gruppen)

**Mac App Store prüfen** – erst nach 1.0, mit offenem Ausgang. Was dagegen spricht:
- Die Sandbox verlangt für den Systemton (Core-Audio-Process-Tap) und für AppleScript zu Apple Notizen,
  Bear und Craft Ausnahmegenehmigungen, die im Review begründet werden müssen
- Der Obsidian-Vault ist ein beliebiger Ordner: dafür bräuchte es „security-scoped bookmarks“ statt Pfaden
- Updates außerhalb des Stores (Sparkle, eigene DMG) fallen weg; jede Fehlerbehebung wartet auf ein Review
- Nutzen wäre Auffindbarkeit und Vertrauen – bei einer kostenlosen, quelloffenen App kein Geld

**Kurs-Gruppen**
- [ ] Bereich mit Kommilitonen teilen (iCloud-Freigabe, nur Apple-Geräte)

## Phase 10 – Organisationen (nach 1.0, auf Zuruf)

> **Stand 25.09.2026:** Für Einzelne gibt es inzwischen **Earnote Pro** am iPhone/iPad (Phase 6c) – zusätzliche
> Funktionen, nichts Bestehendes wird gesperrt. Der folgende Abschnitt gilt weiter für Organisationen.

**Der Satz, auf den alles hinausläuft:** Eine Mac-App. Für Menschen kostenlos, für Organisationen
kostenpflichtig. **Niemals ein Server.**

### Warum überhaupt

Wer Aufnahmen aus rechtlichen Gründen nicht hochladen darf, hat heute kein brauchbares Werkzeug:
Ärztinnen und Psychotherapeuten (§ 203 StGB), Anwälte, Steuerberater, Betriebsräte, Journalisten mit
Quellenschutz, Behörden, Forschung mit Ethikauflage – und ganz gewöhnliche Firmen, deren Meetings
nicht auf fremden KI-Servern landen sollen. Für diese Gruppe ist „läuft vollständig lokal“ kein
netter Zusatz, sondern die Bedingung, unter der sie so etwas überhaupt einsetzen dürfen.

### Keine beschnittene Fassung

Was heute kostenlos ist, bleibt es. Einzelne bezahlen für zusätzliche Funktionen (Earnote Pro, Phase 6c);
Organisationen bezahlen den **kommerziellen Einsatz** und das, was ausschließlich sie brauchen:

- Verteilung per MDM (`.pkg` für Jamf/Intune)
- Vorgaben per Konfigurationsprofil, vom Nutzer nicht änderbar – vor allem: **Cloud-KI zentral sperren**
- Mehrplatzlizenzen, Rechnung mit Umsatzsteuer
- Aufbewahrungsrichtlinien und Nachweis, wer was exportiert hat
- Support mit zugesagter Reaktionszeit

### Lizenz ohne Nachweis

Kostenlos für private und studentische Nutzung, Pro-Lizenz für den Einsatz in einer Organisation –
**ohne Prüfung, ohne Konto, ohne Immatrikulationsbescheinigung.** Das trägt, weil dieselbe
Compliance-Abteilung, die den Cloud-Upload verbietet, auch unlizenzierte Software verbietet. Wer
wegen der Vertraulichkeit kauft, riskiert nicht 49 € wegen einer Lizenzprüfung. In den Einstellungen
steht ein ruhiger Satz dazu – keine Countdown-Fenster, keine Bettelei.

Preis-Richtung: **einmalig statt monatlich** (etwa 49 € je Platz, Staffel ab fünf, ein Jahr Updates).
Ein Abo wäre absurd gegen Wettbewerber, die genau daran scheitern.

### Was ausdrücklich nicht kommt

| | Warum nicht |
|---|---|
| **Konten und zentrale Verwaltung** | Was die IT will – Ausrollen, Vorgaben, Lizenznachweis – geht auf dem Mac über MDM und eine signierte Lizenzdatei. Kein Backend, keine laufenden Kosten. |
| **SaaS / eigener Server** | Kostet monatlich, erzwingt ein Abo, macht aus Earnote einen Auftragsverarbeiter nach DSGVO (AV-Verträge, TOMs, Meldepflichten) – und zerstört den einzigen Satz, der die App verkauft. |
| **Teilen über fremde Server** | Falls Teams je teilen wollen: gemeinsamer iCloud-Bereich oder ein Ordner, den der Kunde selbst betreibt. Daten und Verantwortung bleiben beim Kunden. |

### Windows und Linux

**Zurückgestellt, nicht abgelehnt.** Viele Studierende haben kein MacBook, der Bedarf ist real. Aber
es wäre keine Portierung, sondern ein zweites Produkt: WhisperKit läuft auf CoreML, das Sprachmodell
auf MLX, die Oberfläche in SwiftUI – nichts davon existiert außerhalb von Apple. Eine Windows-Fassung
hieße whisper.cpp, llama.cpp und eine neue Oberfläche, also Monate, in denen die Mac-App stillsteht.

Reihenfolge: **erst iPad und iPhone** (gleicher Kern, gleiches Ökosystem, Phase 6 – läuft), danach neu
bewerten. Ein Zwischenweg wäre eine schlanke Windows-Begleitung, die nur aufnimmt und die Datei einem
Mac zur Verarbeitung gibt – das ist der Punkt, an dem es sich lohnen könnte, zuerst nachzudenken.

### Technische Vorbereitung (klein, aber rechtzeitig)

- [x] **Konfigurationsprofil kann Einstellungen vorgeben** (22.09.2026): `ManagedSettings` liest fünf flache
      Schlüssel (`AllowCloudAI`, `CheckForUpdates`, `SyncWithCloud`, `KeepAudioFiles`, `ShowConsentReminder`)
      nur, wenn ein Profil sie erzwingt, und legt sie über die gespeicherten Einstellungen. Gesperrte Schalter
      sind ausgegraut („Von deiner Organisation vorgegeben“), gesperrte Cloud-KI steht nicht zur Wahl und wird
      zusätzlich in `LLMFactory` abgewiesen. Anleitung für IT-Abteilungen: [VERWALTUNG.md](VERWALTUNG.md)
- [ ] Beim Schnitt zwischen offen und geschlossen aufpassen: Der Kern bleibt MIT, spätere
      Organisations-Funktionen kommen in ein eigenes, geschlossenes Modul (**Open Core**).
      Einmal unter MIT Veröffentlichtes bleibt frei – künftige Teile dürfen anders lizenziert werden.
- [ ] Vor allem anderen: **Markenrecherche abschließen.** Ohne Namensrechte lässt sich nichts verkaufen.

### Wann

**Nicht vor 1.0, und auch dann erst auf Zuruf von außen.** Das verlässlichste Signal ist die erste
E-Mail aus einer Kanzlei, Praxis oder IT-Abteilung. Bis dahin gilt: Nachfragen sammeln, nichts bauen.

## Später / Ideen
- Sprechererkennung auch am Mac (FluidAudio läuft dort schon, Phase 6c) – statt „Ich / Andere“
- Weitere Ziele: Google Docs, OneNote, Anytype, Webhooks; Notion-Anmeldung ohne Token
- Öffentlicher Link zum Teilen einer Notiz
- Ältere iPads ohne M-Chip (über den Mac oder einen eigenen API-Schlüssel)
- Ältere Macs mit Intel-Chip: x86-Build ohne MLX, Apple-Spracherkennung + Cloud-KI (nach dem iPhone prüfen)
- Echo-Unterdrückung bei Lautsprecher-Calls
- GitHub Sponsors als frühes Signal, ob überhaupt jemand freiwillig zahlt (siehe Phase 8)

---

## Offene Entscheidungen

| Frage | Empfehlung | Fällig bis |
|---|---|---|
| Launch-Termin | ✅ **entschieden 25.09.2026: Di 13.10.2026**, Einreichung Mo 05.10. (Plan im Abschnitt „Launch“) | ✅ |
| Start von iPad/iPhone | **iPhone: Planung ab 24.09.2026 parallel zur Beta** ([IPHONE.md](IPHONE.md)); Bauen nach Freigabe des Plans, Mac-Beta hat Vorrang. iPad danach mit eigenem Plan | laufend |
| Mac App Store | **Vorerst nein.** Direkt-Download plus Homebrew deckt die Zielgruppe ab; die Sandbox würde Systemton und Export einschränken. Nach 1.0 neu bewerten | nach 1.0 |
| Windows/Linux | **Zurückgestellt.** Kein Port, sondern ein zweites Produkt (CoreML, MLX, SwiftUI gibt es dort nicht). Erst iPad/iPhone, danach neu bewerten – zuerst denkbar: schlanke Windows-Begleitung, die nur aufnimmt | nach 1.1 |
| Geld verdienen | ✅ **entschieden 25.09.2026:** Nie ein Abo. Alles Heutige bleibt kostenlos. Trinkgeld (3 Stufen) schaltet das Dankeschön-Paket frei; **Earnote Pro 9,99 € einmalig** für zusätzliche Funktionen (iPhone/iPad). Organisationen: Phase 10. Kein Server, keine Konten | ✅ |
| Pro am Mac | ✅ **entschieden 25.09.2026:** Pro-Funktionen am Mac **frei** (DMG, Open Source – kein Lizenzsystem). Das **Dankeschön-Paket** (Farben, Designs, App-Symbole) gibt es am Mac für eine Unterstützung über Ko-fi oder GitHub Sponsors – auf Vertrauen, ohne Prüfung (kein Server). Neu bewerten, falls der Mac in den App Store geht | ✅ |
| Versionsnummer zum Launch | ✅ **entschieden 25.09.2026: alle drei als 1.0** (Regel 9) – ein Produkt, eine Nummer | ✅ |
| Einstiegsfrage „Wofür nutzt du Earnote?“ | Ja – in Phase 7, als Hebel gegen Überladung | 0.9.25 |
| Lokales Standardmodell | Qwen3 4B auf allen Macs (Modellvergleich 23.09.2026) | ✅ entschieden |

## Erledigte Entscheidungen (Auszug)
Earnote als Name (vorbehaltlich Prüfung) · MIT & kostenlos · Zielgruppe Studierende · eigenständige Bibliothek,
Export optional · WhisperKit + lokales MLX-Modell als Standard · native macOS-Oberfläche nach Design-Guidelines ·
SwiftData mit iCloud-tauglichem Schema · Audio wird nie synchronisiert · macOS 15 als Mindestversion ·
öffentliches GitHub-Repository unter `louiskl/Earnote` · Veröffentlichung als notarisierte DMG vom Mac aus,
nicht über die CI (das Zertifikat bleibt lokal) · englische Oberfläche (0.9.1) · Sparkle für Updates (0.9.4) ·
Domain earnote.dev (22.09.2026)

---

## iCloud-Sync – Einrichtung und Schema-Pflege

**Stand 22.09.2026: Schritte 1–5 erledigt, der Abgleich läuft** (siehe Phase 6). Offen ist nur Schritt 6.
Die Liste bleibt als Anleitung stehen – Schritt 5 muss nach **jeder Schema-Änderung** wiederholt werden,
und das Profil aus Schritt 3 liegt nur lokal (`scripts/*.provisionprofile` steht in `.gitignore`).

1. ✅ **iCloud-Container anlegen**: `iCloud.app.earnote.Earnote` (Certificates, Identifiers & Profiles › Identifiers › iCloud Containers)
2. ✅ **App-ID `app.earnote.Earnote`** um die Fähigkeit **iCloud (CloudKit)** erweitern und den Container zuordnen
3. ✅ **Provisioning-Profil vom Typ „Developer ID“** mit dieser App-ID erzeugen, herunterladen und in `scripts/`
   ablegen; `build_release.sh` muss es als `embedded.provisionprofile` in die App kopieren
4. ✅ **Erledigt, sobald das Profil liegt:** `Earnote-iCloud.entitlements` und der Einbau des Profils
   in `build_release.sh` stehen schon – beides schaltet sich automatisch ein.
5. ✅ **CloudKit-Schema anlegen und nach Production übernehmen.** Eine mit Developer ID signierte App
   spricht die Production-Umgebung, dort lässt sich aber kein Schema anlegen. Deshalb über die Entwicklungsumgebung:

   ```bash
   EARNOTE_ICLOUD_DEV_TEAM=KZJJ4FFKXJ python3 scripts/generate_xcodeproj.py
   open Earnote.xcodeproj      # Schema: EARNOTE_INIT_CLOUD_SCHEMA=1 setzen, ⌘R – die App legt das
                               # Schema an, schreibt es ins Protokoll und beendet sich
   python3 scripts/generate_xcodeproj.py   # danach wieder auf den Normalfall zurück
   ```

   Danach in der [CloudKit-Konsole](https://icloud.developer.apple.com/) den Container wählen und
   unter *Schema* → **Deploy Schema Changes** nach Production übernehmen.

   **Warum `EARNOTE_INIT_CLOUD_SCHEMA` und nicht einfach den Schalter anmachen:** Lässt man das
   Schema nebenbei beim Hochladen echter Daten entstehen, fehlen alle Felder, die dabei zufällig
   leer waren. Genau das ist am 22.09.2026 passiert – Production kannte `CD_editedAt` auf
   `CD_LibraryNote` nicht, und CloudKit lehnte **jeden** Export ab
   („Cannot create or modify field … in production schema“, CKError 12/2006). `CloudSchemaSetup`
   legt über `initializeCloudKitSchema` jeden Typ mit jedem Feld an. Nach jeder Schema-Änderung
   wiederholen.
6. [ ] Zwei Wochen allein auf zwei Macs laufen lassen (Duplikate, Konflikte, Löschungen), erst dann für Tester freigeben

Fehlt das Profil (z. B. auf einem neuen Build-Mac), bleibt der Schalter wirkungslos: Die App fällt beim Start auf den lokalen Speicher zurück
und schreibt den Grund ins Protokoll. Ein Datenverlust kann dabei nicht entstehen.
