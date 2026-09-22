# Earnote in Organisationen verwalten

Earnote liest ein paar Vorgaben aus einem **Konfigurationsprofil** (MDM, z. B. Jamf Pro, Intune, Kandji,
Mosyle). Vorgegebene Schalter sind in den Einstellungen ausgegraut und tragen den Hinweis
„Von deiner Organisation vorgegeben“. Nutzer können sie nicht ändern.

- **Domäne (Payload-Typ):** `app.earnote.Earnote`
- **Gilt ab dem nächsten Start** von Earnote.
- Welche Vorgaben gerade gelten, steht beim Start im Protokoll (Hilfe › Protokoll zeigen).

## Schlüssel

| Schlüssel | Typ | Wirkung |
|---|---|---|
| `AllowCloudAI` | Bool | `false`: Keine KI, die das Transkript vom Mac schickt – also keine Cloud-Anbieter (Claude, OpenAI, Gemini, Mistral), kein eigener OpenAI-kompatibler Server, kein Claude Code und kein Codex. Übrig bleiben die lokale KI, Apple Intelligence, Ollama und LM Studio. War ein gesperrter Anbieter eingestellt, schreibt Earnote die Notizen mit der lokalen KI. |
| `CheckForUpdates` | Bool | Tägliche Suche nach Updates. `false`, wenn Updates über das MDM verteilt werden. |
| `SyncWithCloud` | Bool | Bibliothek über iCloud abgleichen. `false` hält alles auf dem Mac. |
| `KeepAudioFiles` | Bool | `false`: Audiodateien werden nach der Verarbeitung gelöscht, nur Transkript und Notiz bleiben. |
| `ShowConsentReminder` | Bool | Hinweis zum Einverständnis vor jeder Aufnahme. |

Nicht gesetzte Schlüssel bleiben dem Nutzer überlassen. Ein Wert, den jemand selbst mit `defaults write`
setzt, gilt **nicht** als Vorgabe – Earnote wertet nur Werte aus, die macOS als verwaltet meldet.

## Beispielprofil

Sperrt Cloud-KI und iCloud-Sync. Die beiden `PayloadUUID` durch eigene ersetzen (`uuidgen`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>app.earnote.Earnote</string>
            <key>PayloadIdentifier</key>
            <string>com.example.earnote.settings</string>
            <key>PayloadUUID</key>
            <string>00000000-0000-0000-0000-000000000001</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>AllowCloudAI</key>
            <false/>
            <key>SyncWithCloud</key>
            <false/>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Earnote: nur lokale KI</string>
    <key>PayloadIdentifier</key>
    <string>com.example.earnote</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>00000000-0000-0000-0000-000000000002</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
```

Zum Ausprobieren ohne MDM: als `.mobileconfig` sichern, doppelklicken und unter
Systemeinstellungen › Allgemein › Geräteverwaltung installieren. Danach Earnote neu starten.
