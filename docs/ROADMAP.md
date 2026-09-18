# Earnote – Roadmap

> Stand: 18.09.2026 · gepflegt vom Architekten · Versionen sind Arbeitsstände, öffentlich wird erst 1.0.
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
| 2b | Farbe zurück (Bereichsfarben), Aufnahme-Bühne mit Pegel und Live-Text, Menüleiste ohne „Zuletzt“, zentrales Call-Banner, signierte und notarisierte Version | 0.7.0 | ✅ fertig |
| **2c** | **Einstellungen und Einrichtungsassistent nativ (inkl. Whisper-Vorbereitung), altes Design-System entfernt** | 0.7.1 | ▶ **fertig, Test durch den Nutzer offen** |
| 3 | Funktionen für 1.0: Bearbeiten, Korrigieren & Wörterbuch, PDF-Lernzettel, Transkript-Qualität | 0.8 | ▶ **3a und 3b fertig** |
| 4 | Qualität & Modelle: Benchmark, automatische Modellwahl, Härtetests | 0.9 | geplant |
| 5 | Beta mit Kommilitonen · **parallel dazu Phase 6 (iPad/iPhone)** | 1.0 RC | geplant |
| 🚀 | **Launch Earnote 1.0 für Mac** | 1.0 | |
| 6 | iPad eigenständig, iPhone als Begleit-App, iCloud-Sync | 1.1 | **startet parallel zur Mac-Beta** |
| 7 | Kurs-Gruppen: Bereiche mit Kommilitonen teilen | 1.2 | nach Launch |

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

**3f Erster Start ohne Wartefalle**
- [ ] Whisper-Modell direkt nach dem Download für den Chip vorbereiten (einmalig ~15 Min. auf M1) – mit klarer Anzeige im Einrichtungsassistenten

**3g Export**
- [ ] Export-Status pro Ziel im Inspector, einzelnes Ziel erneut exportieren
- [ ] Hinweis, wenn ein Ziel nicht eingerichtet ist

## Phase 4 – Qualität & Modelle (0.9)
- [ ] **Referenz-Aufnahmen** (vom Nutzer): kurze Notiz, 90-Min.-Vorlesung mit Fachbegriffen, Zoom-/Teams-Call
- [ ] Modellvergleich mit echten Vorlesungen: Qwen3 4B / 8B / 14B, Gemma 3 4B – Lernzettel nebeneinander bewerten
- [ ] Automatische Modellwahl nach Gerät (Arbeitsspeicher, Chip)
- [ ] 3-Stunden-Vorlesung Ende-zu-Ende: Dauer, Speicher, Akku, Wärme
- [ ] Härtefälle: Festplatte voll, Berechtigung entzogen, Download abgebrochen, Mac schläft ein, Gerät gewechselt
- [ ] „Ich / Andere“-Sprechererkennung prüfen
- [ ] Swift-6-Sprachmodus
- [ ] `LegacyMigration` (Earmark → Earnote) entfernen

## Phase 5 – Launch-Vorbereitung (1.0 RC)
**Name & Recht**
- [ ] Markenrecherche Earnote (DPMA, EUIPO, USPTO; Klassen 9 und 42), Domain, GitHub-/Instagram-/TikTok-Namen sichern
- [ ] Impressum und Datenschutzerklärung; Hinweis auf § 201 StGB prüfen

**Verteilung**
- [ ] Apple-Entwicklerkonto (99 $/Jahr) → signieren und notarisieren (keine „Dennoch öffnen“-Hürde mehr)
- [ ] Automatische Updates (Sparkle), Build und Release über GitHub Actions
- [ ] Button „Feedback senden“ (GitHub Issues)

**Test**
- [ ] Beta mit 5–10 Kommilitonen über 1–2 Wochen, echte Vorlesungen
- [ ] Rückmeldungen einarbeiten

**Schaufenster**
- [ ] Öffentliches GitHub-Repo, README mit GIF und Screenshots, MIT-Lizenz, Beitragsregeln
- [ ] One-Page-Website, Buy Me a Coffee und GitHub Sponsors
- [ ] Ein Demo-Video (30–60 s), überall wiederverwendet

## 🚀 Launch 1.0 (Mac)
- Reddit (r/macapps, r/Studium, r/ObsidianMD, r/Notion), Show HN, Product Hunt, openalternative.co, AlternativeTo, awesome-mac
- E-Mail an Mac-Blogs (iFun, Macwelt, t3n)
- Danach: 1–2 Std./Woche für Fehlermeldungen, alle paar Wochen ein Update

## Phase 6 – iPad & iPhone (1.1)
- [ ] iCloud-Sync einschalten (CloudKit), Duplikat-Bereinigung, Sync-Status
- [ ] iOS-App-Target auf demselben Kern
- [ ] **iPad eigenständig** (M-Chip): Whisper + lokales Modell auf dem Gerät, „Increased Memory Limit“, Hintergrund-Aufgaben
- [ ] **iPhone als Begleit-App**: nimmt auf, Mac verarbeitet, fertige Notiz wieder auf dem iPhone lesbar
- [ ] Oberfläche für iPad und iPhone

## Phase 7 – Kurs-Gruppen (1.2)
- [ ] Bereich mit Kommilitonen teilen (iCloud-Freigabe, nur Apple-Geräte)

## Später / Ideen
- Englische Oberfläche (String Catalog)
- Echte Sprechererkennung (Sprecher 1/2/3)
- Kalender-Anbindung (Titel und Teilnehmende aus dem Termin)
- Globales Tastenkürzel zum Aufnehmen
- Weitere Ziele: Google Docs, OneNote, Logseq, Anytype, Todoist, Webhooks; Notion-Anmeldung ohne Token
- Öffentlicher Link zum Teilen
- Ältere iPads ohne M-Chip (über Mac oder eigenen API-Schlüssel)
- Echo-Unterdrückung bei Lautsprecher-Calls

---

## Offene Entscheidungen

| Frage | Empfehlung | Fällig bis |
|---|---|---|
| Launch-Termin | **Fast-Track:** Beta mit Kommilitonen Anfang Oktober, Launch zum Vorlesungsbeginn Ende Oktober – nur wenn die Beta keine groben Fehler zeigt; sonst Anfang Januar vor der Klausurenphase | nach Phase 3 |
| Apple-Entwicklerkonto | ✅ **verlängert am 17.09.** – noch: Zertifikat + Notarisierung einrichten; ohne Developer-ID fragt macOS nach jedem Update erneut nach der Mikrofon-Erlaubnis, und die „Dennoch öffnen“-Hürde bleibt | sofort |
| Sprache der Oberfläche beim Launch | nur Deutsch, Texte aber schon im String Catalog | Phase 2 |
| Lokales Standardmodell | nach Benchmark mit echten Vorlesungen | Phase 4 |
| Ältere iPads unterstützen | nein zum Start | Phase 6 |
| Name final | nach Markenrecherche | vor Phase 5 |

## Erledigte Entscheidungen (Auszug)
Earnote als Name (vorbehaltlich Prüfung) · MIT & kostenlos · Zielgruppe Studierende · eigenständige Bibliothek, Export optional · WhisperKit + lokales MLX-Modell als Standard · native macOS-Oberfläche nach Design-Guidelines · SwiftData mit iCloud-tauglichem Schema · Audio wird nie synchronisiert · macOS 15 als Mindestversion
