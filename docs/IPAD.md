# Earnote für iPad – Plan

> Stand: 24.09.2026 · **Entwurf, noch nicht freigegeben** (offene Entscheidungen in Abschnitt 6) · gepflegt vom Architekten.
> P1 beginnt bewusst erst nach der iPhone-1.1: Mit `TARGETED_DEVICE_FAMILY = 1,2` verlangt App Review auch iPad-Screenshots und eine gute iPad-Oberfläche.
> Baut auf der iPhone-App auf ([IPHONE.md](IPHONE.md)). Die Mac-Beta und die iPhone-1.1 haben Vorrang.

## Die Idee in einem Satz

Das iPad ist der Mac für unterwegs: eigenständig, mit Whisper und lokaler KI auf M-Chips. Die Oberfläche hat
eine Seitenleiste wie am Mac, Tastatur und Fenster funktionieren, und aufgenommen wird wie am iPhone.

---

## 1. Grundentscheidungen (Vorschlag)

| # | Frage | Vorschlag | Warum |
|---|---|---|---|
| 1 | Eigene App oder dieselbe? | **Dieselbe App** (`EarnoteiOS`, `TARGETED_DEVICE_FAMILY = 1,2`), ein Eintrag im App Store | Ein Kauf, ein Trinkgeld, eine Bundle-ID. Alles, was das iPhone kann (Aufnahme, Live-Aktivität, Teilen, Ladekabel, Trinkgeld), läuft ohne Umbau mit |
| 2 | Mindestversion | **iPadOS 26** | Gleicher Kern wie am iPhone; iPadOS 26 bringt die Menüleiste und freie Fenster |
| 3 | Transkription | M-Chip: **Whisper** (WhisperKit, wie am Mac). Sonst Apples Spracherkennung | Auf M-Chips genauso gut wie am Mac, bei Fachbegriffen besser als SpeechAnalyzer |
| 4 | Notiz | M-Chip mit 8 GB oder mehr: **lokales Modell** (Weg A). Sonst Weg B oder C wie am iPhone | Gleiche Wege wie am iPhone, `DeviceCapabilities` entscheidet |
| 5 | Ausrichtung | **Alle Ausrichtungen**, jede Fenstergröße | Am iPad Pflicht; das iPhone bleibt im Hochformat |

---

## 2. Oberfläche (nativ iPadOS)

Die Wurzel ist **eine** `TabView` mit `.tabViewStyle(.sidebarAdaptable)`. Am iPhone bleiben es Tabs, am iPad wird daraus
eine Seitenleiste mit den Einträgen aus dem Tab „Bereiche“ (Alle, Offene Aufgaben, Ohne Bereich, Probleme, jeder Bereich).
So gibt es keine zweite Wurzel, die auseinanderläuft.

```
iPad, breites Fenster
┌ Seitenleiste ─────┬ Liste ───────────────┬ Notiz ──────────────────────┐
│ Alle              │ Heute                │ Titel · Bereich · Dauer      │
│ Offene Aufgaben   │  Analysis II  ▸      │ [Notiz | Transkript]         │
│ Ohne Bereich      │  Team-Meeting        │ …                            │
│ Bereiche          │ Gestern              │                              │
│  📐 Analysis      │  …                   │ Abspielleiste                │
│  💻 Informatik    │                      │                              │
└───────────────────┴──────────────────────┴──────────────────────────────┘
Aufnahme: tabViewBottomAccessory (wie am iPhone), in der Seitenleiste unten
```

- **Tab „Aufnahmen“ in breiter Größe:** `NavigationSplitView` (Liste | Notiz) statt `NavigationStack`. Schmale Fenster
  (Slide Over, ein Drittel des Bildschirms) fallen von selbst auf den Stapel zurück.
- **Transkript** als `inspector` neben der Notiz, wenn Platz ist. Tippen spielt die Stelle ab, wie am Mac.
- **Menüleiste und Tastatur (iPadOS 26):** `commands` wie am Mac: ⌘N Aufnahme, Leertaste Pause, ⌘F Suche, ⌘, Einstellungen,
  ⌘⌫ Löschen. Die Befehle aus `Earnote/App/` werden, wo möglich, geteilt.
- **Mehrere Fenster:** `WindowGroup(for: UUID.self)` öffnet eine Notiz im eigenen Fenster, z. B. neben den Folien.
- **Ziehen und Ablegen:** Audio aus Dateien oder Finder-ähnlichen Apps ins Fenster ziehen, Notiz als Markdown herausziehen.
- **Einstellungen:** Blatt wie am iPhone; mit Menüleiste zusätzlich unter „Earnote › Einstellungen“.
- `DESIGN_GUIDELINES.md` bekommt einen **Abschnitt 31 (iPad)**, bevor die erste Ansicht entsteht.

---

## 3. Was vom iPhone kommt, was neu ist

| Bereich | Vom iPhone unverändert | Neu am iPad |
|---|---|---|
| Aufnehmen | `PhoneRecorder`, Unterbrechungen, Live-Aktivität (Sperrbildschirm), Kontrollzentrum, Siri | USB-C-Mikrofone häufiger; keine Dynamic Island, keine Action-Taste |
| Verarbeiten | Warteschlange, Hintergrund, „Erst am Ladekabel“, Stromsparmodus | Whisper auf M-Chips (`PlatformTranscribers` wählt nach Gerät) |
| Bibliothek | Liste, Notiz, Transkript, Bereiche, Suche, Lernen | Split-Ansicht, Inspector, mehrere Fenster, Drag & Drop |
| Teilen | Teilen-Menü, PDF, Anki, Share Extension | Ziehen von Notizen in andere Apps |
| Später | – | Apple Pencil: Anmerkungen in der Notiz; Folien (PDF) neben der Aufnahme, Seite zur Zeitmarke |

---

## 4. Etappen

| Etappe | Inhalt | Ergebnis |
|---|---|---|
| **P0 – teilweise ✅** | ✅ Abschnitt 31 in den Design-Richtlinien (Entwurf) · offen: Plan freigeben (Abschnitt 6) | Entscheidungen stehen |
| **P1** | `TARGETED_DEVICE_FAMILY = 1,2`, alle Ausrichtungen, `sidebarAdaptable`, Split-Ansicht im Tab „Aufnahmen“ | Läuft im iPad-Simulator, nichts ist gestreckt |
| **P2** | Menüleiste und Tastenkürzel, mehrere Fenster, Drag & Drop, Inspector fürs Transkript | Fühlt sich an wie eine iPad-App |
| **P3** | Whisper und lokales Modell auf M-Chips, Messung (Dauer, Wärme, Akku) auf einem echten iPad | Weg A mit Whisper |
| **P4** | iPad-Screenshots, App Review | Earnote für iPad im App Store (gleiche App) |

---

## 5. Risiken

| Frage | Wie wir es herausfinden |
|---|---|
| Passen WhisperKit und das 4B-Modell nacheinander in den Speicher eines iPads mit 8 GB? | Messbank wie beim iPhone (IPHONE.md Abschnitt 7), mit „Increased Memory Limit“ |
| Bleibt die Aufnahme stabil, wenn Stage Manager das Fenster verkleinert oder in den Hintergrund legt? | Manuelle Tests mit Hintergrund-Audio auf echtem Gerät |
| Wird die iPhone-Oberfläche durch `sidebarAdaptable` schlechter? | Vorher/Nachher-Screenshots am iPhone, Review nach Abschnitt 28 und 30 |

---

## 6. Offene Entscheidungen

1. **Eine App für iPhone und iPad** (Vorschlag) oder eine eigene iPad-App?
2. **Whisper als Standard auf M-iPads** (Vorschlag) oder Apples Spracherkennung wie am iPhone, mit Whisper zum Einschalten?
3. **Reihenfolge:** iPad erst nach iPhone 1.1 im App Store (Vorschlag), oder P1 schon vorher mitnehmen, damit die App von Anfang an universal ist?
