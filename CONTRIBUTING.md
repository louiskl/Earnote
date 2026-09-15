# Contributing to Earmark

Thanks for helping! A few notes:

## Project layout

```
Earmark/
  App/            App entry, central AppState (recording + processing pipeline)
  Audio/          Mic recording, Core Audio system tap, mixing/resampling
  Transcription/  WhisperKit and Apple SpeechAnalyzer engines
  AI/             LLM providers + map-reduce summarizer
  Destinations/   Notion, Obsidian, Apple Notes, Markdown, Bear, Craft
  Services/       Call detection, storage, keychain, notifications
  Views/          SwiftUI (main window, onboarding, settings, menu bar, pop-up)
scripts/generate_xcodeproj.py   regenerates Earmark.xcodeproj
```

## Adding things

- **New AI provider:** add a case to `AIProviderKind` and a client that implements `LLMClient`, then wire it up in `LLMFactory`.
- **New export target:** implement `Destination`, add it to `Destinations.all` and `Destinations.make`, and add its settings UI in `DestinationsPanel`.
- **New call app:** add its bundle-ID prefix to `MeetingDetector.knownApps`.

After you add or remove files, run `python3 scripts/generate_xcodeproj.py`.

## Style

- SwiftUI and Swift 5 language mode, macOS 14.4 deployment target
- Gate macOS 26 APIs with `#if canImport(FoundationModels)` plus `if #available(macOS 26.0, *)`
- UI text is currently German. Localization PRs are very welcome.
