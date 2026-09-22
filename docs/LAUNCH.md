# Launch-Mappe

Fertige Texte zum Kopieren. Alles hier ist Entwurf – ändere den Ton, wenn er nicht nach dir klingt,
aber ändere nicht die Fakten: Sie stimmen mit der App überein und sind nachgeprüft.

**Reihenfolge, die funktioniert:** erst Kommilitonen (Beta) → dann Hochschule (Fachschaft, Newsletter)
→ dann Reddit/Foren → zuletzt Product Hunt und Hacker News. Andersherum verpufft es: Die großen
Plattformen wollen sehen, dass es die App schon benutzt.

---

## Der Kern in einem Satz

Für jeden Kanal derselbe Gedanke, nur anders lang:

- **Fünf Wörter:** Vorlesung aufnehmen, fertige Notiz lesen.
- **Ein Satz:** Earnote nimmt Vorlesungen und Meetings auf, transkribiert sie mit Whisper direkt
  auf dem Mac und schreibt daraus eine strukturierte Notiz – ohne Konto, ohne Abo, ohne Cloud.
- **Der Unterschied zum Rest:** Alle anderen schicken deine Vorlesung auf einen Server und verlangen
  ein Abo. Earnote rechnet auf deinem Mac und kostet nichts.

**Drei Dinge, die immer vorkommen sollten:** kostenlos · läuft lokal (Datenschutz) · für Studierende gebaut.

---

## 1. Kommilitonen (zuerst!)

Kurznachricht, WhatsApp oder Signal:

> Ich hab eine Mac-App gebaut, die Vorlesungen aufnimmt und dir danach die Mitschrift schreibt –
> komplett auf dem Rechner, ohne Konto und kostenlos. Würdest du die zwei Wochen benutzen und mir
> sagen, was nervt? Installation: `brew install --cask louiskl/earnote/earnote` oder
> https://louiskl.github.io/Earnote/

Dazu die [Anleitung für Tester](BETA.md) schicken. Mehr braucht es nicht.

---

## 2. Fachschaft / Uni-Newsletter (E-Mail)

**Betreff:** Kostenloses Tool für Vorlesungsmitschriften – von einem Studenten aus dem Fachbereich

> Hallo zusammen,
>
> ich studiere hier und habe in den letzten Monaten eine Mac-App entwickelt: **Earnote** nimmt eine
> Vorlesung auf und schreibt daraus eine strukturierte Notiz mit Zusammenfassung, Themen und
> Aufgaben. Besonders ist, dass alles **lokal auf dem eigenen Rechner** läuft – keine Aufnahme wird
> hochgeladen, es gibt kein Konto und keine Kosten. Der Quelltext ist offen (MIT).
>
> Ich dachte, das könnte für unsere Kommilitoninnen und Kommilitonen interessant sein – besonders
> für alle, die mitschreiben und gleichzeitig zuhören müssen, und für internationale Studierende,
> die dem Tempo nicht immer folgen können.
>
> Seite: https://louiskl.github.io/Earnote/
> Quelltext: https://github.com/louiskl/Earnote
>
> Wenn ihr es in den Newsletter oder auf Instagram nehmen mögt, freue ich mich. Ich stelle es auch
> gern kurz in einer Sitzung vor.
>
> Viele Grüße
> Louis

**Warum das zieht:** „von einem Studenten von hier" schlägt jede Werbung. Voraussetzung ehrlich
nennen (Mac mit Apple Silicon), sonst gibt es Enttäuschung.

---

## 3. Reddit

### r/macapps (englisch)

**Titel:** Earnote – records lectures and meetings, transcribes and summarises them entirely on your Mac (free, MIT)

> I'm a student and got tired of choosing between listening and taking notes, so I built this.
>
> Earnote records the microphone and system audio, transcribes with Whisper and writes a structured
> note with a local model. No account, no subscription, nothing is uploaded – the only network
> traffic is downloading the models once and the daily update check.
>
> - Transcription starts while you are still recording, so a 90-minute lecture is done a few minutes
>   after you stop
> - Notes, tasks as checkboxes, flashcards, PDF study sheets
> - Exports to Markdown, Obsidian, Notion, Apple Notes, Bear, Craft, Logseq, Reminders, Things, Todoist
> - Click any timestamp in the note to hear that moment
> - German and English interface
>
> Requirements: macOS 15, Apple Silicon. Free, MIT licensed, signed and notarised.
>
> https://louiskl.github.io/Earnote/
>
> Happy to answer anything – and I'd genuinely like to hear what breaks for you.

**Regeln:** Als Entwickler kennzeichnen, nicht in jedem Kommentar verlinken, auf Kritik sachlich
antworten. Beste Zeit: Dienstag bis Donnerstag, vormittags US-Zeit.

### r/Studium oder r/de (deutsch)

**Titel:** Ich habe eine kostenlose App gebaut, die Vorlesungen mitschreibt – läuft komplett offline auf dem Mac

> Mich hat genervt, dass man entweder zuhört oder mitschreibt. Also habe ich Earnote gebaut:
> aufnehmen, und ein paar Minuten später steht die Notiz da – Zusammenfassung, Themen, Aufgaben zum
> Abhaken, auf Wunsch Karteikarten und ein Lernzettel als PDF.
>
> Das Besondere: Es läuft **komplett auf dem eigenen Mac**. Keine Aufnahme geht in eine Cloud, kein
> Konto, kein Abo, Quelltext offen. Kostet nichts und wird auch nichts kosten.
>
> Voraussetzung ist leider ein Mac mit M-Chip (macOS 15+), weil Transkription und KI lokal rechnen.
>
> https://louiskl.github.io/Earnote/
>
> **Ein Hinweis, der mir wichtig ist:** Vorlesungen aufzunehmen ist nicht überall erlaubt. Frag
> vorher die dozierende Person – die App blendet vor jeder Aufnahme einen Hinweis dazu ein.

---

## 4. Product Hunt

- **Name:** Earnote
- **Tagline (60 Zeichen):** Lecture notes that write themselves — on your Mac
- **Topics:** Mac · Productivity · Education · Artificial Intelligence · Privacy

**Beschreibung:**

> Earnote records your lectures, meetings and calls, transcribes them with Whisper and turns the
> result into a structured note — summary, topics, decisions and tasks as checkboxes.
>
> Everything runs on your Mac. No account, no subscription, no server. The transcript starts while
> you are still recording, so the note is ready minutes after you stop.
>
> Free and open source (MIT), built by a student who got tired of typing along.

**Erster Kommentar (wichtiger als die Beschreibung):**

> Hi 👋 I'm Louis, a student.
>
> I built Earnote because every tool I tried wanted my lectures on their servers and €15 a month for
> it. That felt wrong for something as personal as a recording of my own classes — and unaffordable
> on a student budget.
>
> So Earnote does the whole thing locally: Whisper for the transcript, a small language model for the
> note, both on your Mac. The only time it talks to the internet is to download the models once.
>
> The hard part wasn't the AI, it was everything around it: keeping a 90-minute recording alive when
> AirPods switch profiles mid-call, getting spoken German technical terms spelled right, and making
> it usable for people who don't care how any of it works.
>
> It's free and MIT licensed. I'd love to hear where it falls apart for you.

**Launch-Tag:** Dienstag oder Mittwoch, 00:01 Uhr pazifischer Zeit. Vorher 10–20 Leute bitten,
am Launch-Tag reinzuschauen – nicht „upvoten", sondern kommentieren; das zählt mehr.

---

## 5. Hacker News (Show HN)

HN verzeiht keine Werbesprache. Nüchtern, technisch, ehrlich über Grenzen.

**Titel:** Show HN: Earnote – local lecture transcription and note-taking for macOS

> I'm a student and built this because the existing tools upload your recordings and charge a
> subscription.
>
> Earnote records microphone plus system audio, runs WhisperKit (large-v3-turbo, CoreML) for the
> transcript and an MLX model (Qwen3 4B or Qwen2.5 7B depending on your RAM) for the note. Both run
> on Apple Silicon, nothing leaves the machine.
>
> Some things that turned out harder than expected:
>
> - Transcribing while recording: the audio is condensed into chunks during the recording, so a
>   90-minute lecture finishes minutes after you stop instead of taking another 20
> - Spoken technical terms: a glossary feeds Whisper's prompt tokens, and corrections apply to title,
>   note and transcript at once
> - Whisper hallucinating on silence — quiet passages get filtered out before the model sees them
> - Keeping a recording alive across device changes: Bluetooth headphones switch profile mid-call and
>   AVAudioEngine throws Objective-C exceptions that Swift cannot catch, which kills the process
>
> Swift 6, SwiftData, no third-party dependencies outside WhisperKit/MLX/Sparkle. MIT.
>
> https://github.com/louiskl/Earnote
>
> Limitations: macOS 15+, Apple Silicon only, and the models need ~4 GB of disk.

---

## 6. Verzeichnisse (einmal eintragen, wirkt lange)

| Wo | Was |
|---|---|
| [AlternativeTo](https://alternativeto.net) | Als Alternative zu Otter.ai, Granola, Fireflies.ai eintragen |
| [openalternative.co](https://openalternative.co) | Open-Source-Alternative zu Otter.ai |
| [awesome-mac](https://github.com/jaywcjlove/awesome-mac) | Pull Request unter „Audio and Video" |
| [awesome-macos-apps](https://github.com/iCHAIT/awesome-macOS) | Pull Request |
| Homebrew | läuft bereits über den eigenen Tap |

Kurztext für alle Verzeichnisse:

> Earnote records lectures, meetings and calls and writes structured notes — transcription and AI run
> locally on your Mac. Free, open source, no account.

---

## 7. Demo-Video (30–60 Sekunden)

Ohne Sprecher, nur Bild und ein, zwei Einblendungen. Bildschirmaufnahme in 1440 × 900, hell.

| Sek. | Bild | Einblendung |
|---|---|---|
| 0–3 | Menüleiste, Klick auf „Aufnehmen", roter Punkt | „Vorlesung beginnt" |
| 3–8 | Hauptfenster, Laufzeit läuft, Wellenform, im Hintergrund erscheinen Transkriptzeilen | „Earnote schreibt mit" |
| 8–12 | Klick auf „Stopp" | |
| 12–20 | Fortschritt Transkription → Notiz, Zeitraffer | „90 Minuten – in drei Minuten fertig" |
| 20–30 | Notiz scrollen: Zusammenfassung, Themen, Aufgaben zum Abhaken | |
| 30–38 | Klick auf eine Zeitmarke → Ton springt an die Stelle | „Jede Zeitmarke ist ein Knopf" |
| 38–46 | Rechtsklick → „Lernzettel als PDF", PDF erscheint | |
| 46–52 | Einstellungen: „Lokale KI", kein Konto zu sehen | „Alles bleibt auf deinem Mac" |
| 52–58 | Schlussbild: Logo, `louiskl.github.io/Earnote`, „kostenlos · Open Source" | |

**Aufnehmen mit:** QuickTime („Neue Bildschirmaufnahme") oder ⇧⌘5. Mauszeiger einblenden, keine
Musik (läuft sonst auf Product Hunt und Reddit stumm ins Leere), lieber ein, zwei Sekunden zu lang
als hektisch. Demo-Bibliothek: Debug-Build mit `EARNOTE_SANDBOX` und `EARNOTE_DEMO_LIBRARY=1`
starten – dann sind echte Daten nicht im Bild.

---

## 8. Antworten auf die Fragen, die sicher kommen

**„Ist das legal?"**
Das nichtöffentlich gesprochene Wort ist in Deutschland geschützt (§ 201 StGB). Hol vor jeder
Aufnahme das Einverständnis ein – bei Vorlesungen auch das der dozierenden Person. Earnote blendet
vor jeder Aufnahme einen Hinweis ein. Die Verantwortung liegt beim Nutzer, und das sagt die App auch.

**„Warum kostenlos? Was ist der Haken?"**
Kein Haken. Ich habe es für mich gebaut, es läuft auf deinem Rechner und kostet mich deshalb nichts
außer der Entwicklungszeit. Es gibt keine Server, die bezahlt werden müssten, also auch kein Abo.

**„Wie gut ist die Erkennung wirklich?"**
Whisper large-v3-turbo, dasselbe Modell wie bei den meisten kostenpflichtigen Diensten. Bei
Fachbegriffen hilft das eingebaute Wörterbuch: Einmal korrigieren, danach sitzt es.

**„Windows? iPhone?"**
Windows nein – die App setzt auf Apples CoreML und MLX auf. iPad und iPhone sind nach 1.0 geplant.

**„Was ist mit Otter.ai / Granola / Fireflies?"**
Die sind ausgereifter und arbeiten im Team besser. Sie laden deine Aufnahmen aber auf ihre Server
und kosten monatlich. Earnote ist der Gegenentwurf: lokal, kostenlos, für Einzelpersonen.

**„Braucht das viel Speicher?"**
Die Modelle rund 4 GB, einmalig. Aufnahmen lassen sich automatisch löschen, sobald die Notiz steht –
in den Einstellungen steht, wie viel gerade belegt ist.

---

## 9. Was noch fehlt, bevor das alles rausgeht

- [ ] Markenrecherche abgeschlossen (DPMA, EUIPO, USPTO; Klassen 9 und 42)
- [ ] Domain gesichert, Instagram/TikTok-Namen gesichert
- [ ] Demo-Video gedreht
- [ ] Zwei Wochen Beta ohne Datenverlust und ohne Absturz
