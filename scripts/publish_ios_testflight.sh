#!/bin/bash
# Lädt die iPhone-App zu TestFlight hoch – in einem Rutsch:
#
#   ./scripts/publish_ios_testflight.sh
#
# 1. baut das Archiv (Release, Team KZJJ4FFKXJ), Xcode signiert automatisch
# 2. lädt es zu App Store Connect hoch; nach 10–30 Minuten Verarbeitung erscheint es in TestFlight
#
# Braucht einmalig:
#   - scripts/AuthKey.p8            API-Schlüssel aus App Store Connect (Benutzer und Zugriff › Integrationen)
#   - scripts/appstoreconnect.env   ASC_KEY_ID=… und ASC_ISSUER_ID=… (beides von derselben Seite)
#   - die App in App Store Connect (Meine Apps › + › Neue App, Bundle-ID app.earnote.Earnote)
# Beide Dateien stehen in .gitignore und verlassen den Mac nie.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail() { echo "✗ $1" >&2; exit 1; }

KEY="$ROOT/scripts/AuthKey.p8"
ENV="$ROOT/scripts/appstoreconnect.env"
[[ -f "$KEY" ]] || fail "API-Schlüssel fehlt: scripts/AuthKey.p8"
[[ -f "$ENV" ]] || fail "scripts/appstoreconnect.env fehlt (ASC_KEY_ID und ASC_ISSUER_ID)"
# shellcheck disable=SC1090
source "$ENV"
[[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || fail "ASC_KEY_ID oder ASC_ISSUER_ID fehlt in scripts/appstoreconnect.env"
git check-ignore -q "$KEY" || fail "scripts/AuthKey.p8 ist nicht in .gitignore – abgebrochen"

VERSION="$(sed -nE 's/^MARKETING_VERSION = "([0-9.]+)"/\1/p' scripts/generate_xcodeproj.py)"
# TestFlight verlangt je Hochladen eine neue Buildnummer – Datum und Uhrzeit sind immer größer als die letzte
BUILD="$(date +%Y%m%d%H%M)"
ARCHIVE="$ROOT/dist/EarnoteiOS.xcarchive"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

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
