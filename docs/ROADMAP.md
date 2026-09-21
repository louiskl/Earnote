# Earnote – Roadmap

> Stand: 19.09.2026 · gepflegt vom Architekten · Versionen sind Arbeitsstände, öffentlich wird erst 1.0.
> Beta läuft: [Releases](https://github.com/louiskl/Earnote/releases) · [Anleitung für Tester](BETA.md)
> Leitlinien: [DESIGN_GUIDELINES.md](DESIGN_GUIDELINES.md) · Aufbau: [ARCHITECTURE.md](ARCHITECTURE.md)

**Ziel von 1.0:** Eine ausgereifte, native Mac-App, mit der Studierende ohne Technik-Kenntnisse und ohne KI-Abo Vorlesungen, Meetings und Calls mitschreiben lassen – kostenlos, privat, lokal.

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
| **4b** | **Reif für andere: Audio anhören, englische Oberfläche, Kalender, Modellwahl** | 0.9 | ▶ **läuft** |
| 5 | Launch: Website, Demo-Video, Homebrew, Beta mit Kommilitonen, Markenrecherche | 1.0 RC | geplant |
| 🚀 | **Launch Earnote 1.0 für Mac** | 1.0 | |
| 6 | iPad eigenständig, iPhone als Begleit-App, iCloud-Sync | 1.1 | nach Launch |
| 7 | Mac App Store prüfen (Sandbox), Kurs-Gruppen teilen | 1.2 | nach Launch |

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
- [ ] Aufnahme während eines laufenden Teams-/Zoom-Calls zuverlässig (vom Nutzer noch zu testen)
- [x] Verständliche Fehlermeldungen ohne Fehlernummern; Diagnose im Log
- [x] Sicherheitsregeln für Tests mit echten Daten in `CLAUDE.md`

## Phase 2a/2b – Natives Mac-Hauptfenster (0.6)
Vorher: Architekturvorschlag nach Guidelines Abschnitt 20, vom Nutzer abgesegnet.
- [ ] Stabiles Gerüst: `NavigationSplitView` (Seitenleiste → Aufnahmeliste → Notiz) + **Inspector**
- [ ] Seitenleiste als echte Source List: Bibliothek (Alle, Offene Aufgaben, Probleme, Ohne Bereich) und Bereiche
- [ ] Aufnahmeliste kompakt, Detail zeigt Notiz und Transkript, Inspector zeigt Bereich, Datum, Dauer, Quelle, Modell, Export-Status
- [ ] Echte **Toolbar** (Aufnehmen/Stopp, Pause, Teilen, Inspector), **Menübefehle** und **Tastenkürzel**, Kontextmenüs
- [ ] `.searchable` über Titel, Notizen und Transkripte
- [ ] Views lesen direkt per `@Query`; `LibraryStore` schreibt nur noch; Fassade `AppState` entfällt
- [ ] Auswahl als Fensterzustand; mehrere Fenster möglich
- [ ] Einstellungen als native `Form`; Einrichtungsassistent überarbeitet
- [ ] Menüleisten-App und Call-Pop-up aufgeräumt
- [ ] Eigenes Design-System, Karten und Verläufe entfernt
- [ ] Leer-, Lade- und Fehlerzustände; schmale und breite Fenster; Dark Mode; VoiceOver; Tastaturbedienung
- [ ] Anti-Vibecoding-Review (Guidelines Abschnitt 28)

## ✅ Phase 2c – Einstellungen und Assistent nativ (0.7.1)
- [x] Einstellungen als Szene mit sieben Tabs, jeder ein `Form` mit `.formStyle(.grouped)`; neuer Tab „Aufnahme“
- [x] Einrichtungsassistent: fünf Schritte, Kopfzeile, Inhalt, Knopfzeile – ohne Verläufe, Kacheln und eigene Knopfstile
- [x] Ziele-Schritt aus dem Assistenten entfernt (Export ist optional und steckt in den Einstellungen)
- [x] Whisper-Vorbereitung sichtbar: „Für diesen Mac vorbereiten“ (läuft nach dem Download automatisch), Status „Bereit“
- [x] Bereichs-Editor als `Form`; Vorlagen-Auswahl als Häkchenliste
- [x] Altes Design-System gelöscht (`DesignSystem.swift`, `Components.swift`, `Views/Legacy/`), übrig: `Support/Brand.swift`
- [x] Einstellungen und Assistent lesen `LibraryStore`/`RecordingController` direkt; `AppState` nur noch in Menüleiste und Call-Hinweis
- [ ] Vom Nutzer zu prüfen: erster Durchlauf des Assistenten, Whisper-Vorbereitung auf dem eigenen Mac

## Phase 3 – Funktionen für 1.0 (0.7–0.8)
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

**3h Schneller fertig (0.8.0)**
- [x] Transkribieren läuft schon während der Aufnahme (abschnittsweise, Schnitt am letzten fertigen Satz)
- [x] Nach dem Stopp bleibt nur der letzte Abschnitt – die Warteschlange schreibt direkt die Notiz
- [x] Schalter „Schon während der Aufnahme transkribieren“ (Einstellungen › Aufnahme)
- [x] Hinweis während der Verarbeitung: zugeklappter Mac schläft und pausiert sie
- [ ] Vom Nutzer zu prüfen: Wie viel schneller ist eine 90-Minuten-Vorlesung wirklich fertig?
- [ ] Offen: faster-whisper geprüft und verworfen (CTranslate2 hat kein Metal, läuft auf dem Mac nur auf der CPU)

**3g Export (0.7.5)**
- [x] Export-Status pro Ziel im Inspector – auch für Ziele, in die noch nie exportiert wurde
- [x] Einzelnes Ziel erneut exportieren („Erneut“), erfolgreiche Exporte bleiben stehen
- [x] Hinweis mit „Einrichten …“, wenn ein Ziel eingeschaltet, aber nicht fertig eingerichtet ist
- [x] Nebenbei: Einstellungen einer älteren Version verlieren keine Ziele mehr (fehlende Felder bekommen Standardwerte)

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
- [ ] Gerät gewechselt und Berechtigung entzogen am echten Mac durchspielen

**Gemessen an zwei echten Vorlesungen (M1 Air, 16 GB):** Whisper large-v3-turbo transkribiert mit
**≈ 12× Echtzeit** (60 Min. Ton in 5 Min.), die Notiz der lokalen KI braucht 6–7 Minuten. Die gefühlte
Stunde Wartezeit kam vom zugeklappten Deckel, nicht von der Rechenleistung.

## Phase 4b – Reif für andere (0.9)
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
- [ ] Erster Start ohne Internet: verständliche Meldung statt hängendem Download
- [ ] Anti-Vibecoding-Review über alle neuen Ansichten (Guidelines Abschnitt 28)

**Alltag**
- [ ] **Kalender-Anbindung**: Titel, Fach und Teilnehmende aus dem laufenden Termin übernehmen
- [ ] **Globales Tastenkürzel** zum Starten/Stoppen aus jeder App
- [ ] Aufnahme aus der Menüleiste mit Bereichswahl in einem Klick (heute zwei)

**Zielgruppen schärfen**
- [ ] **Studium**: Karteikarten aus der Notiz (Anki-CSV und Apple-Karteikarten), Semester-Zusammenfassung
      über mehrere Vorlesungen eines Bereichs, Formeln im Lernzettel nicht zerschießen
- [ ] **Meetings**: Aufgaben nach Apple Erinnerungen (und optional Things/Todoist), Entwurf für die
      Follow-up-Mail, Kurzprotokoll zum Weiterschicken
- [ ] **Schule**: einfachere Sprache in den Notizen (Schalter „einfach erklärt“), kleinere Modelle für
      ältere Macs

**Qualität und Modelle**
- [ ] Modellvergleich mit den echten Vorlesungen: Qwen3 4B / 8B, Gemma 3 4B – Lernzettel nebeneinander
- [ ] Automatische Modellwahl nach Gerät (Arbeitsspeicher, Chip) statt fester Voreinstellung
- [ ] Notiz beschleunigen: Vorverdichten schon während der Aufnahme, sobald das Transkript lang ist
- [ ] 3-Stunden-Vorlesung Ende-zu-Ende: Dauer, Speicher, Akku, Wärme
- [ ] Swift-6-Sprachmodus, `LegacyMigration` (Earmark → Earnote) entfernen

## Phase 5 – Launch (1.0 RC → 1.0)

**Name & Recht** (liegt beim Nutzer)
- [ ] Markenrecherche Earnote (DPMA, EUIPO, USPTO; Klassen 9 und 42)
- [ ] Domain sichern (earnote.app o. ä.), Instagram-/TikTok-Namen sichern
- [ ] Impressum und Datenschutzerklärung für die Website (die App-Seite steht in `docs/DATENSCHUTZ.md`)

**Website** (Hauptweg zum Download)
- [x] **Steht: [louiskl.github.io/Earnote](https://louiskl.github.io/Earnote/)** – statisch über GitHub Pages
      aus `docs/`, zweisprachig (`index.html` englisch, `de.html` deutsch), ohne Framework und ohne Tracking
- [x] Inhalt: Was es macht · Screenshot in der jeweiligen Sprache · Download-Knopf auf das neueste Release ·
      „bleibt auf deinem Mac“ · Voraussetzungen · FAQ · Link zu GitHub
- [x] **Impressum nach § 5 TMG** als eigene Seite (`impressum.html`), aus beiden Sprachen verlinkt
- [ ] Demo-Video (30–60 s): aufnehmen, Notiz erscheint, Lernzettel als PDF – für Website, Product Hunt, Social
- [ ] Screenshots in Hell und Dunkel, deutsch und englisch

**Verteilung**
- [ ] **Direkt-Download** als Hauptweg: notarisierte DMG über GitHub Releases (läuft bereits)
- [ ] **Homebrew Cask** (`brew install --cask earnote`) – eine Pull-Request, große Reichweite bei Mac-Nutzern
- [ ] Automatische Updates: aktuell Hinweis mit Link; Sparkle erst, wenn die Nutzerzahl es rechtfertigt
- [ ] Eintragen: AlternativeTo, openalternative.co, awesome-mac, Product Hunt, Show HN, r/macapps, r/Studium
- [ ] Hochschule: Fachschaften, Uni-Newsletter, Instagram/TikTok – die Zielgruppe sitzt dort, nicht auf HN

**Beta**
- [ ] 5–10 Kommilitonen, 1–2 Wochen, echte Vorlesungen ([Anleitung](BETA.md) liegt bereit)
- [ ] Rückmeldungen einarbeiten, danach 1.0

## Phase 6 – iPad & iPhone (1.1)
- [ ] iCloud-Sync einschalten (CloudKit), Duplikat-Bereinigung, Sync-Status
- [ ] iOS-App-Target auf demselben Kern
- [ ] **iPad eigenständig** (M-Chip): Whisper + lokales Modell auf dem Gerät, „Increased Memory Limit“
- [ ] **iPhone als Begleit-App**: nimmt auf, Mac verarbeitet, fertige Notiz wieder auf dem iPhone
- [ ] Oberfläche für iPad und iPhone

## Phase 7 – Nach dem Launch (1.2)

**Mac App Store prüfen** – erst nach 1.0, mit offenem Ausgang. Was dagegen spricht:
- Die Sandbox verlangt für den Systemton (Core-Audio-Process-Tap) und für AppleScript zu Apple Notizen,
  Bear und Craft Ausnahmegenehmigungen, die im Review begründet werden müssen
- Der Obsidian-Vault ist ein beliebiger Ordner: dafür bräuchte es „security-scoped bookmarks“ statt Pfaden
- Updates außerhalb des Stores (Sparkle, eigene DMG) fallen weg; jede Fehlerbehebung wartet auf ein Review
- Nutzen wäre Auffindbarkeit und Vertrauen – bei einer kostenlosen, quelloffenen App kein Geld

**Kurs-Gruppen**
- [ ] Bereich mit Kommilitonen teilen (iCloud-Freigabe, nur Apple-Geräte)

## Später / Ideen
- Echte Sprechererkennung (Sprecher 1/2/3) statt „Ich / Andere“
- Weitere Ziele: Google Docs, OneNote, Logseq, Anytype, Webhooks; Notion-Anmeldung ohne Token
- Öffentlicher Link zum Teilen einer Notiz
- Ältere iPads ohne M-Chip (über den Mac oder einen eigenen API-Schlüssel)
- Echo-Unterdrückung bei Lautsprecher-Calls
- Buy Me a Coffee / GitHub Sponsors, falls die App Zulauf bekommt

---

## Offene Entscheidungen

| Frage | Empfehlung | Fällig bis |
|---|---|---|
| Launch-Termin | Beta ab sofort mit Kommilitonen, Launch Ende Oktober zum Semesterstart – nur wenn die Beta keine groben Fehler zeigt; sonst Anfang Januar vor der Klausurenphase | nach Phase 4b |
| Mac App Store | **Vorerst nein.** Direkt-Download plus Homebrew deckt die Zielgruppe ab; die Sandbox würde Systemton und Export einschränken. Nach 1.0 neu bewerten | nach 1.0 |
| Englische Oberfläche | **Ja, vor dem Launch.** Ohne Englisch fällt der größte Teil der Launch-Kanäle weg | Phase 4b |
| Sparkle (automatische Updates) | Erst bei nennenswerter Nutzerzahl; bis dahin reicht der Hinweis mit Download-Link | nach 1.0 |
| Lokales Standardmodell | nach dem Modellvergleich mit echten Vorlesungen | Phase 4b |
| Domain | erst nach der Markenrecherche kaufen | vor Phase 5 |

## Erledigte Entscheidungen (Auszug)
Earnote als Name (vorbehaltlich Prüfung) · MIT & kostenlos · Zielgruppe Studierende · eigenständige Bibliothek,
Export optional · WhisperKit + lokales MLX-Modell als Standard · native macOS-Oberfläche nach Design-Guidelines ·
SwiftData mit iCloud-tauglichem Schema · Audio wird nie synchronisiert · macOS 15 als Mindestversion ·
öffentliches GitHub-Repository unter `louiskl/Earnote` · Veröffentlichung als notarisierte DMG vom Mac aus,
nicht über die CI (das Zertifikat bleibt lokal)
