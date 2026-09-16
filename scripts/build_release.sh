#!/bin/bash
# Baut Earmark.app (Release, Universal) und packt sie in dist/Earmark.dmg.
#
#   ./scripts/build_release.sh
#
# Ohne weitere Angaben wird ad-hoc signiert: läuft auf jedem Mac, beim ersten Start
# fragt macOS aber einmalig nach („Datenschutz & Sicherheit › Dennoch öffnen“).
#
# Mit Apple Developer Program (Developer-ID-Zertifikat) entfällt diese Warnung:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="earmark-notary" \
#   ./scripts/build_release.sh
# Das Notary-Profil einmalig anlegen mit:
#   xcrun notarytool store-credentials earmark-notary --apple-id … --team-id TEAMID
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/Earmark.app"
DMG="$DIST/Earmark.dmg"

SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$DEVELOPER_ID")"
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID"
               CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp")
    echo "▸ Signiere mit: $DEVELOPER_ID"
else
    echo "▸ Kein DEVELOPER_ID gesetzt – signiere ad-hoc"
fi

echo "▸ Baue Earmark (Release) …"
xcodebuild -project Earmark.xcodeproj -scheme Earmark -configuration Release \
    -derivedDataPath "$BUILD" -destination 'generic/platform=macOS' \
    "${SIGN_ARGS[@]}" clean build | grep -E "error:|warning: .*Earmark/|BUILD" || true
[[ -d "$APP" ]] || { echo "✗ Build fehlgeschlagen"; exit 1; }

codesign --verify --strict "$APP"

echo "▸ Erzeuge DMG …"
rm -rf "$DIST"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname Earmark -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "▸ Notarisiere (dauert ein paar Minuten) …"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
echo "✓ Fertig: $DMG  (Earmark $VERSION, $(du -h "$DMG" | cut -f1))"
