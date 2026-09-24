# Earnote für iPhone – Plan

> Stand: 24.09.2026 · **Grundentscheidungen freigegeben** (Abschnitt 9) · gepflegt vom Architekten.
> Start parallel zur Mac-Beta. Die Beta hat Vorrang, gemeldete Fehler am Mac gehen vor.
> iPad: eigener Plan in [IPAD.md](IPAD.md).

## Die Idee in einem Satz

Das iPhone liegt in der Vorlesung auf dem Tisch: Aufnahme starten, Bildschirm aus. Danach ist die
Notiz da, und unterwegs lernst du mit den Karteikarten. Die Bibliothek ist dieselbe wie auf dem Mac.

---

## 1. Grundentscheidungen (Vorschlag)

| # | Frage | Vorschlag | Warum |
|---|---|---|---|
| 1 | Begleiter oder eigenständig? | **Beides:** mit Mac ist das iPhone Begleiter (der Mac verarbeitet), ohne Mac eigenständig. Jederzeit umstellbar ✅ | Mit iOS 26 transkribiert das iPhone selbst (SpeechAnalyzer), und neue iPhones schaffen ein 4B-Modell. Ein reiner Begleiter wäre ohne Mac nutzlos, und die meisten Studierenden haben nur ein iPhone. |
| 2 | Mindestversion | **iOS 26** (iPhone 11 und neuer) | SpeechAnalyzer, `BGContinuedProcessingTask`, Foundation Models, Liquid-Glass-Oberfläche. Der Kern ist ohnehin auf iOS 26 ausgelegt. |
| 3 | Wo entsteht die Notiz? | **Drei Wege, automatisch vorgeschlagen** (Abschnitt 2) | Neue iPhones lokal, ältere über den Mac oder mit eigenem Cloud-Schlüssel |
| 4 | Verteilung | **App Store + TestFlight** | Auf dem iPhone gibt es keinen anderen Weg. Datenschutz-Etikett: „Keine Daten erfasst“. |
| 5 | Code | **Selbes Repo, selber Kern**, neues Target `Earnote iOS` | `EarnoteCore` baut schon für iOS, `EarnoteML` (WhisperKit, MLX) läuft auf iOS |
| 6 | Sync | **iCloud, abschaltbar**; die App funktioniert auch ohne | Sync muss am Mac erst seinen Dauerlauf bestehen (Roadmap Phase 6) |
| 7 | Audio | **Bleibt auf dem Gerät.** Einzige Ausnahme: Weg B (der Mac verarbeitet), die Datei wird danach gelöscht | Versprechen „Audio wird nie synchronisiert“ bleibt im Normalfall bestehen |
| 8 | Geld | **Kein Abo, nie.** App kostenlos und vollständig nutzbar; Trinkgeld und optionale Einmalkäufe für Extras ✅ | „Kein Abo“ ist der Unterschied zu Otter & Co. – siehe Abschnitt 9 |

---

## 2. Wo die Notiz entsteht – drei Wege

| Weg | Für wen | Transkription | Notiz | Was verlässt das iPhone |
|---|---|---|---|---|
| **A · Auf diesem iPhone** | iPhone 15 Pro und neuer (8 GB) | SpeechAnalyzer (Apple, auf dem Gerät) | Qwen3 4B über MLX oder Apple Intelligence (Foundation Models) | nichts |
| **B · Mit meinem Mac** | jedes iPhone + Mac mit Earnote | auf dem Mac (Whisper) | auf dem Mac (lokale KI) | Audio über die eigene iCloud zum eigenen Mac, danach gelöscht |
| **C · Cloud-KI mit eigenem Schlüssel** | jedes iPhone | SpeechAnalyzer (auf dem Gerät) | Claude, OpenAI, Gemini, Mistral per API-Schlüssel | nur der Text an den gewählten Anbieter |

- **Standard (freigegeben 24.09.2026):**
  1. **Earnote läuft auf einem Mac derselben iCloud → Weg B.** Das iPhone ist Begleiter: Es nimmt auf, das Audio geht über
     iCloud zum Mac, der Mac verarbeitet, die Notiz kommt zurück, das Audio wird danach aus iCloud gelöscht.
  2. **Kein Mac, iPhone 15 Pro oder neuer → Weg A**, alles auf dem iPhone.
  3. **Kein Mac, älteres iPhone → Weg C** mit eigenem Schlüssel (Gemini empfohlen). Ob ein kleineres lokales Modell
     (z. B. Qwen3 1.7B) auf iPhones mit 6 GB brauchbar ist, klärt die Messung (Abschnitt 7).
  
  In den Einstellungen lässt sich der Weg jederzeit ändern, auch mit Mac: z. B. „auf dem iPhone verarbeiten“ oder
  „mit Gemini“, wenn der Mac gerade nicht läuft.
- **Abos (ChatGPT Plus, Claude Pro) gehen auf dem iPhone nicht.** Anbieter lassen fremde Apps nur mit
  API-Schlüssel zu, also mit Zahlung pro Nutzung. Auf dem Mac geht es, weil Earnote dort die installierten Programme
  Claude Code und Codex nutzt. Gemini hat ein kostenloses Kontingent und ist deshalb der einfachste
  Einstieg für Weg C. Die Clients (`AnthropicClient`, OpenAI, Gemini, Mistral) liegen schon im Kern.
- **Transkription in der Cloud ist nicht vorgesehen.** SpeechAnalyzer läuft auf jedem iPhone mit iOS 26
  lokal, und so geht Audio nie an einen Anbieter.
- **Ältere Macs (Intel):** Das ist eine eigene Frage. Nötig wären ein x86-Build ohne MLX,
  die Apple-Spracherkennung und Cloud-KI. Das wird nach dem iPhone geprüft.

---

## 3. Funktionen – vollständige Liste

Priorität: **1.1** = erste Version im App Store · **1.2** = direkt danach · **später** = Idee, nicht geplant.

### Aufnehmen
| Funktion | Prio |
|---|---|
| Aufnahme starten mit einem Tipp, Bereich wählen (Vorlesung, Meeting …), Pause, Fortsetzen, Stopp | 1.1 |
| **Weiter aufnehmen bei ausgeschaltetem Bildschirm und im Hintergrund** (Background Audio) | 1.1 |
| Unterbrechungen: Anruf, Wecker, Siri → automatisch pausieren, danach fortsetzen, mit Hinweis | 1.1 |
| Mikrofone: eingebaut, AirPods, USB-C, Lightning; Wechsel während der Aufnahme in derselben Datei | 1.1 |
| Aufnahme übersteht App-Absturz und Neustart (Datei in Abschnitten, nichts geht verloren) | 1.1 |
| Pegel, Warnung „seit einer Minute nichts zu hören“, Warnung bei wenig Speicher, sauberer Stopp bei vollem Speicher | 1.1 |
| Einverständnis-Hinweis vor der ersten Aufnahme (§ 201 StGB) | 1.1 |
| ✅ Stromsparmodus berücksichtigen: ohne Ladekabel wird erst später verarbeitet, „Jetzt verarbeiten“ in der Liste (Live-Mitschrift gibt es noch nicht) | 1.1 |
| Live-Mitschrift während der Aufnahme (SpeechAnalyzer, einschaltbar) | 1.2 |
| **Markieren „Das ist wichtig“** mit einem Tipp oder über die Action-Taste → erscheint als Prüfungshinweis in der Notiz | 1.2 |
| Foto von Tafel oder Folie während der Aufnahme, erscheint an der richtigen Stelle im Transkript | später |
| Titel aus dem Kalender (wie am Mac `CalendarTitles`) | 1.2 |
| Erinnerung zum Vorlesungsbeginn aus dem Kalender: „Analysis beginnt – aufnehmen?“ | später |

### System: Sperrbildschirm, Dynamic Island, Mitteilungen, Kurzbefehle
| Funktion | Prio |
|---|---|
| **Live-Aktivität** auf dem Sperrbildschirm und in der Dynamic Island: Laufzeit, Bereich, Knöpfe Pause/Stopp (App Intents) | 1.1 |
| Fortschritt der Verarbeitung („Notiz wird geschrieben … 45 %“), über die Systemanzeige von `BGContinuedProcessingTask` | 1.1 |
| Mitteilung „Notiz fertig“ mit Titel; Tippen öffnet die Notiz | 1.1 |
| **Steuerelement** fürs Kontrollzentrum und den Sperrbildschirm: „Aufnahme starten“ (ControlWidget) | 1.1 |
| **App Intents:** „Aufnahme starten/stoppen“, „Letzte Notiz zeigen“; damit gehen Siri, Kurzbefehle und die Action-Taste | 1.1 |
| ✅ Widgets: „Aufnehmen“ (Home klein, Sperrbildschirm rund), „Letzte Notizen“ (klein, mittel, Sperrbildschirm), „Offene Aufgaben“ (klein, mittel, Sperrbildschirm rund/rechteckig/Zeile); Tippen springt in die Notiz bzw. die Aufgaben | 1.1 |
| Apple Watch: Aufnahme starten/stoppen | später |

### Verarbeiten
| Funktion | Prio |
|---|---|
| Drei Wege A/B/C (Abschnitt 2), Vorschlag je nach Gerät | 1.1 |
| Läuft nach dem Stopp im Hintergrund weiter (`BGContinuedProcessingTask`); wird es abgebrochen, geht es beim nächsten Öffnen weiter | 1.1 |
| ✅ Option „Erst am Ladekabel verarbeiten“ (`BGProcessingTask` mit `requiresExternalPower`, z. B. nachts) | 1.1 |
| Modell-Download im WLAN mit Größenangabe (~2,5 GB), Platzprüfung, Löschen in den Einstellungen | 1.1 |
| Dieselben Prüfungen wie am Mac: keine erfundenen Namen, Aufgaben, Fristen (`TaskCheck`, `QuestionCheck`) – kommen aus dem Kern | 1.1 |
| Wörterbuch (Fachbegriffe) wird an Transkription und KI weitergegeben | 1.1 |

### Bibliothek und Lesen
| Funktion | Prio |
|---|---|
| Liste nach Tagen, Filter nach Bereich, Suche in Titel, Notiz und Transkript | 1.1 |
| Notiz lesen, Aufgaben abhaken, bearbeiten, KI-Fassung wiederherstellen | 1.1 |
| Transkript mit Zeitmarken; Tippen spielt die Stelle ab; Abspielleiste mit 15 s zurück und 1×/1,5×/2× | 1.1 |
| Teilen über das Teilen-Menü: PDF-Lernzettel, Markdown, Text (für Notion, Apple Notizen, WhatsApp …) | 1.1 |
| Notiz neu schreiben, vereinfachen (aus der Notiz statt aus dem Audio) | 1.2 |
| Übersicht über einen Bereich (vor der Prüfung) | 1.2 |
| Bereiche anlegen, umbenennen, sortieren, Vorlagen | 1.1 |
| Löschen mit Bestätigung, Wischgesten, Kontextmenüs | 1.1 |
| Direkte Exporte (Obsidian, Notion …) wie am Mac | später – am iPhone reicht das Teilen-Menü |

### Lernen
| Funktion | Prio |
|---|---|
| Karteikarten erzeugen (4–8, wie am Mac) | 1.1 |
| **Karteikarten lernen:** Karte umdrehen, „wusste ich / wusste ich nicht“, schwierige Karten öfter | 1.1 |
| Einfache Wiederholung nach Abstand (fällig heute), Widget „3 Karten fällig“ | 1.2 |
| Anki-Export | 1.2 |

### Importieren
| Funktion | Prio |
|---|---|
| Audio und Video aus der Dateien-App importieren | 1.1 |
| ✅ **„Mit Earnote teilen“** aus Sprachmemos, WhatsApp-Sprachnachrichten, Dateien (Share Extension `EarnoteShare`, Übergabe über den App-Group-Ordner) | 1.1 |

### Sync mit dem Mac
| Funktion | Prio |
|---|---|
| Bibliothek über iCloud (vorhandenes SwiftData-Schema, Container `iCloud.app.earnote.Earnote`) | 1.1 |
| Status „Gleicht ab … / Aktuell“ in den Einstellungen | 1.1 |
| Übergabe an den Mac (Weg B): Audio in einen Übergabebereich, der Mac verarbeitet, die Notiz kommt zurück, das Audio wird gelöscht | 1.1 |
| Doppelte Bereiche zusammenführen (vorhanden: `mergeDuplicates`) | 1.1 |
| Karteikarten-Lernstand synchronisieren | 1.2 |

### Einstellungen (in der App, als Blatt)
Notiz-Weg und Modell (mit Speicherbedarf, Löschen) · Sprache der Notiz · Aufnahme (Audio behalten,
bei Anruf pausieren, Live-Mitschrift) · Akku (erst am Ladekabel) · Mitteilungen · iCloud · Bereiche ·
Wörterbuch · Cloud-Schlüssel (Schlüsselbund) · Über, Earnote unterstützen, Fehler melden (Diagnose).

---

## 3a. Abgleich mit der Mac-App (24.09.2026)

| Mac-App | iPhone vorher | Entscheidung |
|---|---|---|
| Seitenleiste: Alle, Offene Aufgaben, Ohne Bereich, Probleme, Bereiche mit Zählern | nur Filter-Menü | **Tab „Bereiche“** als Gegenstück zur Seitenleiste – ersetzt den Tab „Lernen“, der am Mac kein Gegenstück hatte |
| Bereich anlegen aus Vorlagen, Emoji, Farbe, Anweisungen für die KI | nur Name | **Bereichs-Editor** wie am Mac, Vorlagen beim Anlegen |
| Übersicht über einen Bereich | – | **im Bereich**: „Übersicht erstellen“ |
| Karteikarten erzeugen, in der Notiz, als Anki-Datei | erzeugen, eigener Lern-Tab | **in Notiz und Bereich**: erzeugen, lernen, als Anki-Datei teilen |
| Lernzettel als PDF mit Fußzeile | – | **PDF teilen** (gleicher Aufbau, Fußzeile „Erstellt mit Earnote · earnote.dev“) |
| Neu zusammenfassen mit Anweisung, auch neu transkribieren; Vereinfachen | nur Vereinfachen | **„Neu zusammenfassen …“** mit Anweisung |
| Notiz bearbeiten, auf KI-Fassung zurücksetzen | – | **übernommen** |
| Namen & Begriffe korrigieren, Wörterbuch | – | **übernommen** (Korrigieren in der Notiz, Wörterbuch in den Einstellungen) |
| Export an Notion, Obsidian, Apple Notizen … | Teilen-Menü | bleibt beim **Teilen-Menü** (am iPhone der übliche Weg) |
| Call-Erkennung, Systemton, Menüleiste, Kurzprotokoll per Mail | – | **nicht am iPhone** (gibt es dort nicht bzw. Teilen-Menü reicht) |
| Live-Mitschrift während der Aufnahme | – | 1.2 (braucht echtes Gerät zum Testen) |

**Aufnahme-Bildschirm:** Uhr in normaler, runder Schrift statt dünn; der Verlauf dahinter bewegt sich mit dem Pegel;
die Live-Aktivität zeigt einen Pegel (iOS erlaubt dort nur Aktualisierungen im Sekundentakt, deshalb ruhige Balken
statt Echtzeit). Vorbilder: Apple Sprachmemos (Aufnahme, Liste), Bevel (runde Zahlen, ruhige Verläufe), unsere Mac-App.

---

## 4. Onboarding (erster Start)

Kurz, fünf Schritte, jeder überspringbar außer dem Mikrofon.

1. **Willkommen:** „Earnote schreibt deine Vorlesungen mit.“ Drei Zeilen mit dem, was es kann, und dem Hinweis „Bleibt auf deinem iPhone“. Knopf **Los geht's**.
2. **Mikrofon:** erst erklären, dann die Systemabfrage. Wird sie abgelehnt, steht der Weg in die Einstellungen da.
3. **Mitteilungen:** „Damit du weißt, wann die Notiz fertig ist.“ Das ist optional.
4. **Wie soll die Notiz entstehen?** Der passende Weg ist vorausgewählt (A, B oder C).
   - Bei A beginnt der Download im WLAN im Hintergrund. Aufnehmen geht sofort.
   - B erscheint nur, wenn iCloud an ist und die Bibliothek eines Macs gefunden wurde.
   - Bei C gibt es Schlüssel-Eingabe und einen Link „Wo bekomme ich einen Schlüssel?“, empfohlen wird Gemini.
5. **Fertig:** Bereiche aus Vorlagen wählen (Vorlesung ist vorausgewählt), den Einverständnis-Hinweis lesen, **Erste Aufnahme**.

Mit Earnote auf dem Mac und eingeschaltetem iCloud übernimmt das iPhone Bereiche und Wörterbuch
vom Mac, statt neue anzulegen.

---

## 5. Oberfläche (nativ iOS)

Die Design-Richtlinien gelten sinngemäß: **native Strukturen statt eigener Karten**. Für iOS heißt das
`TabView`, `NavigationStack`, `List`, Blätter, Wischgesten, Kontextmenüs, Dynamic Type, Hell/Dunkel und
das Liquid Glass von iOS 26 nur dort, wo das System es selbst setzt. `DESIGN_GUIDELINES.md` bekommt
dafür einen eigenen iOS-Abschnitt, bevor die erste Ansicht entsteht.

```
TabView (iOS 26, Liquid-Glass-Tableiste)
├─ Aufnahmen      NavigationStack: Liste (nach Tagen, Filter „Bereich“ im Menü) → Notiz | Transkript
├─ Lernen         Bereiche → Karteikarten lernen · Übersicht
└─ Suche          (Tab mit Suchrolle, sucht in allem)

Unten über der Tableiste: tabViewBottomAccessory
  ohne Aufnahme:  ● Aufnehmen               (Tippen startet, langes Drücken: Bereich wählen)
  bei Aufnahme:   0:42:13 · Analysis  ⏸ ■   (Tippen öffnet die Aufnahme-Ansicht)

Aufnahme-Ansicht (Blatt, groß): Laufzeit, Pegel, Bereich, Live-Mitschrift (falls an),
                                Markieren, Pause, Stopp
Einstellungen: Zahnrad in der Symbolleiste von „Aufnahmen“ → Blatt mit Form
```

- **Notiz-Ansicht:** Oben wählt ein Segmented Picker zwischen Notiz und Transkript. Die Symbolleiste enthält
  Teilen und das Menü „Mehr“ (Karteikarten, Vereinfachen, PDF, Löschen). Die Abspielleiste wird nur eingeblendet, wenn es Audio gibt.
- **Verarbeitung:** In der Liste steht der Fortschritt in der Zeile. In der Notiz-Ansicht erscheint der Entwurf, während er
  entsteht, wie am Mac (`DraftNoteView`-Logik aus `ProcessingQueue.drafts`).
- **Leere Zustände:** `ContentUnavailableView` für „Noch keine Aufnahme“, „Keine Treffer“ und „Keine Karteikarten“.

---

## 6. Architektur (Vorschlag nach Design-Richtlinien Abschnitt 20)

| Punkt | Antwort |
|---|---|
| **Scenes** | `WindowGroup` mit `TabView`. Dazu WidgetKit-Extension (Live-Aktivität, Widgets, Steuerelement), App Intents, Share Extension |
| **Hauptaufgabe** | Aufnehmen, ohne hinzusehen; danach lesen und lernen |
| **Layout** | Tabs → `NavigationStack` → Detail. Keine Split-Ansicht (die kommt mit dem iPad) |
| **Auswahl** | Navigationspfad je Tab (`@SceneStorage` bzw. `NavigationPath`), die laufende Aufnahme global im `PhoneRecorder` |
| **Befehle** | App Intents statt Menüs: Aufnahme starten/stoppen/pausieren, letzte Notiz; dazu Kontextmenüs und Wischgesten in der Liste |
| **Symbolleiste** | Liste: Filter, Einstellungen. Notiz: Teilen, Mehr |
| **Zustand** | siehe Tabelle unten |
| **Native Komponenten** | `TabView`, `tabViewBottomAccessory`, `List`, `searchable`, `ContentUnavailableView`, `ShareLink`, ActivityKit, `ControlWidget`, `BGContinuedProcessingTask` |
| **Eigene Darstellung** | nur die Pegelanzeige und die umdrehbare Karteikarte |

### Module

```
Earnote iOS (App-Target)  ──►  EarnotePlatform (neu)  ──►  EarnoteCore
Earnote (Mac)             ──►  EarnotePlatform        ──►  EarnoteCore
beide                     ──►  EarnoteML
```

| Modul | Inhalt |
|---|---|
| `EarnoteCore` | unverändert: Modelle, Bibliothek, Pipeline, Warteschlange, Summarizer, Cloud-KI-Clients |
| `EarnoteML` | unverändert: WhisperKit, MLX. Auf iOS mit „Increased Memory Limit“ |
| **`EarnotePlatform`** (neu) | Apple-Frameworks ohne Oberfläche, die beide Apps brauchen: `AppleSpeechTranscriber` (heute im Mac-Target), Apple Intelligence (`FoundationModels`), Mitteilungen. Kein SwiftUI, AppKit oder UIKit |
| **App-neutrale Stores** | `LibraryStore` und die Verdrahtung aus `AppEnvironment` sind großteils plattformneutral. Was kein AppKit braucht, wandert nach `EarnotePlatform`, damit es nicht doppelt existiert |
| `Earnote iOS` | `PhoneRecorder` (`AVAudioSession` + `AVAudioEngine`), Live-Aktivität, Intents, Oberfläche |

### Wer besitzt welchen Zustand
| Zustand | Besitzer |
|---|---|
| Bibliothek | `LibraryStore` (geteilt), SwiftData, `@Query` in den Ansichten |
| Laufende Aufnahme, Pegel, Unterbrechungen | `PhoneRecorder` (`@MainActor @Observable`, iOS) |
| Live-Aktivität | `RecordingActivity` hört auf `PhoneRecorder` und `ProcessingQueue` |
| Verarbeitung | `ProcessingQueue` + `ProcessingPipeline` (Kern, unverändert), im Hintergrund über einen `BackgroundProcessor` |
| Einstellungen | `SettingsRepository` pro Gerät (neu: Notiz-Weg A/B/C) |
| Karteikarten-Lernstand | **neu im Schema** (`EarnoteSchemaV2`, CloudKit-Regeln), erst 1.1 lokal, 1.2 synchronisiert |

### Übergabe an den Mac (Weg B) – Kurzfassung, Entwurf in Abschnitt 6a
- **Neu:** Das iPhone legt die Aufnahme mit dem Status `waitingForMac` an, die Audiodatei (AAC, ~30 MB pro Stunde) landet
  als Asset in der privaten iCloud-Datenbank (Feld mit `.externalStorage` an einem eigenen Übergabe-Modell).
- Der Mac sieht beim Abgleich neue Übergaben, lädt das Audio, verarbeitet es und schreibt Transkript und Notiz zurück.
  Danach löscht er das Übergabe-Objekt, sodass das Audio aus iCloud verschwindet.
- Ist kein Mac erreichbar, sagt das iPhone das nach 24 Stunden und bietet Weg A oder C an.
- Dafür braucht es eine Schema-Stufe, die nach den CloudKit-Regeln gebaut und am Mac zuerst ausgerollt wird.

---

## 6a. Weg B im Detail (24.09.2026)

> **Stand:** B1 (Kern), B2 (Mac) und B3 (iPhone) als Code da. Die CI baut Kern, Mac-App und iPhone-App (PR louiskl/earnote#6). Die offenen Fragen unten sind
> vorerst mit den Vorschlägen beantwortet. Weiter geht es mit dem Bauen und den Kern-Tests am Mac, danach mit B3 (iPhone).

**Ziel:** Das iPhone nimmt auf, der eigene Mac schreibt Transkript und Notiz, das Audio verschwindet danach aus iCloud.

**Datenmodell – neue Stufe `EarnoteSchemaV2`** (leichte Migration, nur neue Modelle, CloudKit-Regeln aus CLAUDE.md):

| Modell | Felder (alle optional oder mit Standardwert) | Zweck |
|---|---|---|
| `LibraryHandoff` | `id: UUID`, `recordingID: UUID?`, `createdAt`, `fromDevice: String`, `audio: Data?` (`.externalStorage`), `audioFormat = "m4a"`, `state = "waiting"` (String: waiting/claimed/failed), `claimedBy: String?`, `claimedAt: Date?`, `errorMessage: String?` | Das Audio auf dem Weg zum Mac. Keine Beziehung zur Aufnahme, nur die ID – so braucht es keine Inverse, und Löschen ist einfach |
| `LibraryDevice` | `id: UUID`, `name`, `platform` (mac/iphone/ipad), `canProcess: Bool = false`, `lastSeen: Date` | Woran das iPhone erkennt, dass ein Mac da ist (Onboarding, Weg-Vorschlag). Der Mac meldet sich höchstens stündlich |

- Neuer Status `RecordingStatus.waitingForMac` (Rohwert als String). Ältere Mac-Versionen kennen ihn nicht: Deshalb **zuerst der Mac mit V2 ausrollen**, erst danach schreibt das iPhone solche Aufnahmen. Beim Lesen fällt ein unbekannter Status auf `.queued` zurück.
- Audio: Das iPhone nimmt als PCM auf (~170 MB/h). Vor der Übergabe wird nach AAC 64 kbit/s komprimiert (~30 MB/h, im Kern über `FormatConverter`). CloudKit-Assets vertragen das auch bei 3 Stunden.

**Ablauf**
1. iPhone: Stopp → Aufnahme mit `waitingForMac`, Audio komprimieren, `LibraryHandoff` anlegen. In der Liste steht „Wartet auf deinen Mac“, daneben „Auf dem iPhone verarbeiten“.
2. Mac: Ein `HandoffWatcher` im App-Target reagiert auf Änderungen aus iCloud, setzt `claimedBy`/`claimedAt` und prüft nach 60 s, ob der Anspruch noch seiner ist. So verarbeiten zwei Macs nie dieselbe Aufnahme; Ansprüche älter als 2 h verfallen.
3. Mac: Audio als importierte Datei in den eigenen `FileAudioStore`, einreihen und **sofort** `LibraryHandoff` löschen. Damit ist
   das Audio aus iCloud weg, sobald es sicher auf dem Mac liegt, und nicht erst nach der Verarbeitung. Scheitert die Übernahme,
   wird die Übergabe als `failed` markiert, und das iPhone bietet an, selbst zu verarbeiten (sein Audio hat es noch).
4. Mac: verarbeitet mit den **Einstellungen des Macs** (Whisper, lokale KI, Wörterbuch). Transkript und Notiz kommen über den
   normalen Abgleich zurück aufs iPhone. „Audio behalten“ gilt auf dem Mac wie sonst auch.
5. iPhone: Nach 24 h ohne Anspruch gibt es eine Mitteilung „Dein Mac hat die Aufnahme noch nicht abgeholt“ mit „Auf dem iPhone verarbeiten“ (Weg A oder C).

**Wo der Code hingehört**
- Kern (`EarnoteCore`): Schema V2 und Migration, `LibraryRepository` bekommt Snapshots `Handoff`/`Device` sowie `createHandoff`, `claimHandoff`, `finishHandoff`; die reine Regel „wer darf verarbeiten“ als Funktion mit Tests.
- Mac-App: `HandoffWatcher`, das Melden als Gerät, der Status in der Seitenleiste.
- iPhone: Komprimieren und Übergeben nach dem Stopp, neuer Weg „Mit meinem Mac“ im Picker der Einstellungen, iCloud-Berechtigung (`com.apple.developer.icloud-*`, Container `iCloud.app.earnote.Earnote`).

**Reihenfolge:** B1 Kern + Tests → B2 Mac (Watcher, Release, Dauerlauf mit iCloud, Roadmap Phase 6) → B3 iPhone → B4 echte Geräte: 1 h hin, Notiz zurück, Audio weg.

| Etappe | Stand |
|---|---|
| **B1 Kern** | ✅ Code: `EarnoteSchemaV2` (+ leichte Migration), `Library/Handoff.swift` (Snapshots `Handoff`/`SyncedDevice`, `HandoffRules`, `HandoffRepository`), Status `waitingForMac`, Tests in `HandoffTests.swift` (Regeln, Speichern, Migration V1 → V2). **Offen:** `swift test` am Mac |
| **B2 Mac** | ✅ Code: `Earnote/Services/HandoffWatcher.swift` meldet den Mac stündlich als Gerät, holt nach jedem iCloud-Empfang ab, verdrahtet in `AppEnvironment`. **Offen:** Build, CloudKit-Schema neu anlegen und nach Production übernehmen (ROADMAP „iCloud-Sync“, Schritt 5), Release |
| **B3 iPhone** | ✅ Code: `EarnoteiOS/App/HandoffSender.swift` (AAC über `AVAssetExportSession`, Übergabe, Rücknahme mit „Auf dem iPhone verarbeiten“, Mitteilung nach 24 h oder bei `failed`), Einstellungen und Onboarding › „Mac“ (iCloud-Schalter, „Notizen schreibt mein Mac“, sobald ein Mac gefunden ist), Status in Liste und Notiz, iCloud- und Push-Berechtigung. `ProcessingQueue.resumes` verhindert, dass iPhone und Mac dieselbe Aufnahme verarbeiten. **Offen:** am Gerät testen; das iPhone löscht sein eigenes Audio nach der fertigen Notiz noch nicht |
| **B4 Geräte** | offen |

**Bekanntes Risiko:** Mac-Versionen ohne V2 lesen `waitingForMac` als „Wartet“ und würden die Aufnahme ohne Audio verarbeiten
(→ „Fehler“). Weil der Sync noch „in Erprobung“ ist, betrifft das nur Testgeräte. Vor B3 müssen alle eigenen Macs V2 haben.

**Fragen (vorläufig mit dem Vorschlag beantwortet, änderbar):**
1. Der Mac verarbeitet mit **seinen** Einstellungen.
2. Der Mac behält das Audio nach seiner Einstellung „Audio behalten“; aus iCloud verschwindet es immer.
3. Hinweis nach **24 h** (`HandoffRules.overdueAfter`).

---

## 7. Technische Risiken – zuerst messen (Spike, ca. eine Woche)

| Frage | Wie wir es herausfinden |
|---|---|
| Schafft ein iPhone 15 Pro, 16 oder 17 Qwen3 4B für eine 1-Stunden-Vorlesung? Wie lange, wie warm, wie viel Akku? | Die Messbank vom Mac (`scratchpad/bench`) auf iOS bringen und mit echten Transkripten messen. Vergleich mit Apple Intelligence (kleines Kontextfenster, braucht mehr Abschnitte) |
| Ist SpeechAnalyzer auf Deutsch gut genug gegenüber Whisper? | Dieselben drei Vorlesungen transkribieren und die Fehlerquote vergleichen; Whisper auf dem iPhone als Ausweg |
| Darf die Verarbeitung im Hintergrund die GPU nutzen? | `BGContinuedProcessingTask` mit GPU-Berechtigung auf echten Geräten testen |
| Hält eine Aufnahme 3 Stunden bei ausgeschaltetem Bildschirm, mit Anruf und AirPods-Wechsel? | Echte Vorlesung, vom Nutzer gefahren |
| Wie groß und wie schnell ist die Übergabe über iCloud? | 1 h AAC hin, Notiz zurück, stoppen |

Kommt bei der ersten Frage „zu langsam“ heraus, wird Weg B oder C auch auf neuen iPhones der Standard, und A bleibt eine Option.

---

## 8. Etappen

> **Stand 24.09.2026, Befunde aus dem Simulator:** Apples Spracherkennung lädt im Simulator ihr deutsches Modell nicht
> („not subscribed“) – das muss am echten iPhone geprüft werden. Die Hintergrund-Aufgabe (`BGContinuedProcessingTask`)
> lehnt der Simulator ab; auch das gilt nur am Gerät.

| Etappe | Inhalt | Ergebnis |
|---|---|---|
| **M0 – ✅ 24.09.2026** | Plan freigegeben, Entscheidungen aus Abschnitt 9, iOS-Abschnitt in den Design-Richtlinien (30), eigenes Projekt `EarnoteiOS.xcodeproj` mit Generator; Grundgerüst (Tabs, Aufnahme-Leiste) baut mit Kern, WhisperKit und MLX und läuft im Simulator | erledigt |
| **M1 – Spike** | Messungen aus Abschnitt 7 | Entscheidung über Weg A |
| **M2 – ✅ 24.09.2026** | Aufnehmen mit Bildschirm aus (Hintergrund-Audio, Pause bei Anrufen, AirPods-Wechsel, übersteht Abstürze), Bibliothek, Notiz, Transkript mit Abspielen, Lernen (Karteikarten abfragen), Suche, Einstellungen, Onboarding, Import und „Mit Earnote öffnen“, englische Oberfläche. Im Simulator durchgespielt | erledigt, am echten iPhone geprüft |
| **M3 – teilweise ✅** | ✅ Weg A und C (lokale KI, Gemini/Claude/OpenAI/Mistral), Hintergrund-Verarbeitung (`BGContinuedProcessingTask`), Live-Aktivität mit Pause/Stopp (im Simulator getestet), Steuerelement fürs Kontrollzentrum, Siri/Kurzbefehle, Mitteilungen · Weg B als Code (Abschnitt 6a), App-Icon ✅ · offen: Weg B am Gerät testen | TestFlight für Kommilitonen |
| **M4 – Lernen & Import – Code ✅** | ✅ Karteikarten lernen, Import, Share Extension, „Erst am Ladekabel“, Stromsparmodus, Trinkgeld (StoreKit 2) · ✅ **am echten iPhone geprüft (24.09.2026):** Spracherkennung, Hintergrund, Ladekabel, Stromsparmodus, Teilen aus Sprachmemos und WhatsApp · offen: Trinkgeld-Produkte in App Store Connect anlegen | vollständige 1.1 |
| **M5 – Einreichen** | Onboarding-Feinschliff, Datenschutz-Etikett, Screenshots, App Review | **Earnote 1.1 für iPhone im App Store** |

---

## 9. Entscheidungen

**Freigegeben am 24.09.2026:**

1. ✅ **Mit Mac Begleiter, ohne Mac eigenständig**; Cloud-KI (Gemini u. a.) zum Verbinden; alles in den Einstellungen umstellbar.
2. ✅ **Kein Abo.** Die App ist kostenlos und vollständig nutzbar. Geld kommt aus
   - **Trinkgeld** in der App: einmalige In-App-Käufe („Kaffee spendieren“), weil Apple externe Spendenlinks auf dem
     iPhone meist ablehnt;
   - **optionalen Einmalkäufen für Extras**, die niemand braucht, um Earnote voll zu nutzen (welche, entscheiden wir
     vor der Einreichung; Kernfunktionen kommen nie hinter eine Bezahlschranke).
   Technisch: StoreKit 2, nur Verbrauchs- und Dauerkäufe, keine Abos, kein Server, kein Konto.
3. ✅ **iCloud** zunächst aus; an, sobald im Onboarding ein Mac gefunden wird (Weg B braucht es).
4. ✅ **iOS 26**, also iPhone 11 und neuer.
5. Offen: Bundle-ID `app.earnote.Earnote` für die iPhone-App (gleicher iCloud-Container). Vorschlag: ja.
6. **Trinkgeld eingebaut** (`EarnoteiOS/Services/TipJar.swift`, Einstellungen › „Earnote unterstützen“). In App Store Connect
   drei **Verbrauchsartikel** anlegen: `app.earnote.Earnote.tip.small`, `.tip.medium`, `.tip.large` (z. B. 1,99 €, 4,99 €, 9,99 €).
   Solange es sie nicht gibt, bleibt der Abschnitt unsichtbar. Freigeschaltet wird nichts.

**Ursprüngliche Fragen:**

1. **Eigenständig mit drei Wegen** (Vorschlag) statt reiner Begleiter?
2. **Geld:** Die iPhone-App ist entweder a) kostenlos wie am Mac, mit Spenden, oder b) als „Earnote Pro“ bezahlt, etwa als Einmalkauf,
   während der Mac kostenlos bleibt. Die Roadmap (Phase 8) sagt bisher „für Menschen kostenlos,
   für Organisationen kostenpflichtig“. b) würde das für Studierende ändern. Das muss erst vor der Einreichung
   feststehen, aber die Entscheidung bestimmt, ob In-App-Käufe eingebaut werden.
3. **iCloud auf dem iPhone standardmäßig an?** Vorschlag: aus, bis der Mac-Dauerlauf bestanden ist; im Onboarding
   an, sobald ein Mac gefunden wurde.
4. **iOS 26 als Mindestversion** (iPhone 11 und neuer)?
5. **Bundle-ID** `app.earnote.Earnote` für die iPhone-App (gleicher iCloud-Container) – für das App Store Connect-Konto nötig.
