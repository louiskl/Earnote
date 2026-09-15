<p align="center">
  <img src="Earmark/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" alt="Earmark icon">
</p>

<h1 align="center">Earmark</h1>

<p align="center">
  <b>Free, open-source AI meeting notes for macOS.</b><br>
  Records meetings, calls and lectures, transcribes them <i>on your Mac</i> and writes structured notes into Notion, Obsidian, Apple Notes and more.
</p>

<p align="center">
  <a href="#deutsch">🇩🇪 Deutsch</a> · <a href="#english">🇬🇧 English</a>
</p>

---

## English

### Why Earmark?

AI meeting notes are great, but usually tied to one app and a monthly subscription. Earmark is a native Mac app that does the same job for free and lets **you** choose:

- **where the transcription runs**: always locally (Apple Speech on macOS 26 or Whisper via WhisperKit)
- **which AI writes the notes**: Apple Intelligence, Ollama, LM Studio, Claude, OpenAI, Gemini, Mistral, any OpenAI‑compatible server, or your existing Claude Code / Codex subscription
- **where the notes end up**: Notion, Obsidian, Apple Notes, a Markdown folder, Bear, Craft

### Features

| | |
|---|---|
| 🎙 **Microphone + system audio** | Captures the other participants in Zoom, Teams, Meet … using Core Audio process taps. No BlackHole or other virtual audio device. |
| 📞 **Call detection** | Earmark notices when Zoom, Teams, Webex, FaceTime, Slack or a browser call uses your mic and offers to record with a small pop-up. It can also stop the recording when the call ends. |
| 🗂 **Your own categories** | Lecture, client call, interview … each with its own icon, color, summary instructions and export targets. |
| 🗣 **Speaker separation** | Labels segments as “Me” / “Others” by comparing mic and system audio. |
| ⏱ **Long recordings** | Handles 3+ hour lectures. Audio is processed in chunks and long transcripts are summarized with map-reduce. |
| 🧭 **Setup assistant** | Guides you through permissions, model download, AI provider and export targets. No terminal needed. |
| 🔝 **Menu bar** | Start or stop recordings, see live levels and recent notes. |
| 📥 **Import** | Drag any audio file into the window to transcribe it. |

### Requirements

- macOS 14.4 or later on Apple Silicon (Intel works but is slow)
- macOS 26 or later for Apple Speech and Apple Intelligence

### Install

Download the latest `Earmark.dmg` from [Releases](../../releases) and drag Earmark into *Applications*.
Builds that aren't notarized need a one-time *right-click › Open*, or *System Settings › Privacy & Security › Open Anyway*.

### Build from source

1. Install **Xcode 26** from the App Store.
2. Open `Earmark.xcodeproj`. Xcode resolves the WhisperKit package automatically.
3. Press **⌘R**.

If you add or remove source files, regenerate the project with `python3 scripts/generate_xcodeproj.py`.

### Privacy

- Audio and transcripts stay in `~/Library/Application Support/Earmark`.
- Only the transcript text is sent to the AI provider **you** choose. With Apple Intelligence, Ollama or LM Studio, nothing leaves your Mac.
- API keys are stored in the macOS Keychain.

> ⚖️ **Recording other people may require their consent** (in Germany, for example, § 201 StGB applies). Always ask first. Earmark shows a reminder.

### Contributing

PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [roadmap](docs/ROADMAP.md).

---

## Deutsch

**Earmark** ist eine kostenlose, quelloffene Mac-App für KI-Notizen aus Meetings, Calls und Vorlesungen. Sie ist eine Alternative zu Notion AI Meeting Notes, mit freier Wahl von KI und Ablage.

- **Aufnahme** von Mikrofon und Systemton (Zoom, Teams, Meet …), ohne Zusatzsoftware
- **Call-Erkennung** mit Pop-up („Zoom erkannt – aufnehmen?“), automatisches Stoppen am Ende des Calls
- **Lokale Transkription** mit Apple-Spracherkennung (ab macOS 26) oder Whisper
- **Zusammenfassung** mit Apple Intelligence, Ollama, LM Studio, Claude, OpenAI, Gemini, Mistral oder über ein bestehendes Claude-Code- bzw. Codex-Abo
- **Ablage** in Notion, Obsidian, Apple Notizen, einem Markdown-Ordner, Bear oder Craft
- **Eigene Kategorien** mit eigenen Anweisungen für die Zusammenfassung (z. B. Vorlesung mit Prüfungshinweisen und Lernzettel)
- **Sprecher-Unterscheidung** in „Ich“ und „Andere“
- **Einrichtungsassistent** und Bedienung über die Menüleiste, ganz ohne Terminal

**Installation:** `Earmark.dmg` unter [Releases](../../releases) herunterladen und in den Programme-Ordner ziehen.
**Selbst bauen:** `Earmark.xcodeproj` in Xcode öffnen und mit ⌘R starten.

> ⚖️ Bitte vor jeder Aufnahme das Einverständnis aller Beteiligten einholen (§ 201 StGB).

## License

[MIT](LICENSE)
