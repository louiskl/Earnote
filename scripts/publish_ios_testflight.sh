#!/bin/bash
# Lädt die iPhone-App zu TestFlight hoch – in einem Rutsch:
#
#   ./scripts/publish_ios_testflight.sh
#
# 1. baut das Archiv (Release, Team KZJJ4FFKXJ), Xcode signiert automatisch
# 2. lädt es zu App Store Connect hoch; nach 10–30 Minuten Verarbeitung erscheint es in TestFlight
#
# Signiert und lädt hoch mit dem Apple-Konto, das in Xcode angemeldet ist (Xcode › Einstellungen › Accounts) –
# genau wie der Organizer. Der API-Schlüssel (scripts/AuthKey.p8) scheiterte an der Cloud-Signierung
# („Cloud signing permission error“), weil Schlüssel ohne Admin-Rolle keine Cloud-Zertifikate nutzen dürfen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail() { echo "✗ $1" >&2; exit 1; }


VERSION="$(sed -nE 's/^MARKETING_VERSION = "([0-9.]+)"/\1/p' scripts/generate_xcodeproj.py)"
# TestFlight verlangt je Hochladen eine neue Buildnummer – Datum und Uhrzeit sind immer größer als die letzte
BUILD="$(date +%Y%m%d%H%M)"
ARCHIVE="$ROOT/dist/EarnoteiOS.xcarchive"
AUTH=(-allowProvisioningUpdates)

echo "▸ Earnote für iPhone $VERSION ($BUILD) – Projekt erzeugen …"
python3 scripts/generate_ios_xcodeproj.py >/dev/null

echo "▸ Archiv bauen …"
rm -rf "$ARCHIVE"
xcodebuild archive -project EarnoteiOS.xcodeproj -scheme EarnoteiOS -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM=KZJJ4FFKXJ CURRENT_PROJECT_VERSION="$BUILD" "${AUTH[@]}" \
    > dist/ios-archive.log 2>&1 || { tail -40 dist/ios-archive.log; fail "Archiv fehlgeschlagen (dist/ios-archive.log)"; }

echo "▸ Zu App Store Connect hochladen …"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions-iOS.plist \
    -exportPath "$ROOT/dist/ios-export" "${AUTH[@]}" \
    > dist/ios-upload.log 2>&1 || { tail -40 dist/ios-upload.log; fail "Hochladen fehlgeschlagen (dist/ios-upload.log)"; }

echo "✓ Hochgeladen: Earnote $VERSION ($BUILD). In 10–30 Minuten steht der Build in App Store Connect › TestFlight."
