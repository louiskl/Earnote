#!/bin/bash
# Baut Earnote.app (Release, Universal) und packt sie in dist/Earnote.dmg.
#
#   ./scripts/build_release.sh
#
# Ohne weitere Angaben wird ad-hoc signiert: läuft auf jedem Mac, beim ersten Start
# fragt macOS aber einmalig nach („Datenschutz & Sicherheit › Dennoch öffnen“).
#
# Mit Apple Developer Program (Developer-ID-Zertifikat) entfällt diese Warnung:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="earnote-notary" \
#   ./scripts/build_release.sh
# Das Notary-Profil einmalig anlegen mit:
#   xcrun notarytool store-credentials earnote-notary --apple-id … --team-id TEAMID
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/Earnote.app"
DMG="$DIST/Earnote.dmg"

# iCloud-Sync: nur mit Profil vom Typ „Developer ID“, das die CloudKit-Berechtigung enthält.
# Liegt es unter scripts/Earnote.provisionprofile, wird es in die App gelegt und die erweiterten
# Berechtigungen werden verwendet – sonst bleibt alles wie bisher (ohne iCloud).
PROFILE="$ROOT/scripts/Earnote.provisionprofile"
ENTITLEMENTS="Earnote/Resources/Earnote.entitlements"
if [[ -f "$PROFILE" ]]; then
    ENTITLEMENTS="Earnote/Resources/Earnote-iCloud.entitlements"
    echo "▸ Profil gefunden – baue mit iCloud-Berechtigung"
fi

# Die Berechtigungen kommen aus dem Projekt; mit iCloud-Profil wird die fertige App unten neu
# signiert. Als Build-Einstellung würde der Pfad für jedes Paket-Ziel mitgelten und dort ins Leere zeigen.
SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$DEVELOPER_ID")"
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID"
               CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime")
    echo "▸ Signiere mit: $DEVELOPER_ID"
else
    echo "▸ Kein DEVELOPER_ID gesetzt – signiere ad-hoc"
fi

echo "▸ Baue Earnote (Release) …"
# Das Protokoll geht in eine Datei, damit ein Fehlschlag nicht in einer Pipe verschwindet:
# Vorher lief das Skript weiter und hätte aus einer alten App eine DMG gebaut.
mkdir -p "$BUILD"
LOG="$BUILD/build.log"
rm -rf "$APP"
if ! xcodebuild -project Earnote.xcodeproj -scheme Earnote -configuration Release \
        -derivedDataPath "$BUILD" -destination 'generic/platform=macOS' \
        "${SIGN_ARGS[@]}" clean build > "$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u | head -20
    echo "✗ Build fehlgeschlagen – vollständiges Protokoll: $LOG"
    exit 1
fi
grep -E "warning: .*Earnote/" "$LOG" | sort -u | head -5 || true
[[ -d "$APP" ]] || { echo "✗ Build lieferte keine App"; exit 1; }

# Das Profil muss in der App liegen, sonst gilt die iCloud-Berechtigung beim Start nicht.
# Nach dem Kopieren muss neu signiert werden – die Signatur deckt den Inhalt ab.
if [[ -f "$PROFILE" ]]; then
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    if [[ -n "${DEVELOPER_ID:-}" ]]; then
        codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime \
                 --entitlements "$ROOT/$ENTITLEMENTS" "$APP"
    fi
fi

codesign --verify --strict "$APP"

echo "▸ Erzeuge DMG …"
rm -rf "$DIST"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname Earnote -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "▸ Notarisiere (dauert ein paar Minuten) …"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        echo "▸ Prüfe Signatur und Notarisierung …"
        codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime|Timestamp" || true
        spctl -a -t open --context context:primary-signature -v "$DMG" || true
        xcrun stapler validate "$DMG"
    fi
fi

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"

# Sparkle: Update-Datei (appcast.xml) erzeugen und signieren. Sie liegt unter docs/ und wird
# über GitHub Pages ausgeliefert – dieselbe Adresse, die in der Info.plist als SUFeedURL steht.
# Der private Schlüssel liegt im Schlüsselbund (einmalig mit Sparkles `generate_keys` angelegt).
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*artifacts/sparkle/Sparkle/bin/generate_appcast" -print -quit 2>/dev/null || true)"
if [[ -n "$SPARKLE_BIN" ]]; then
    echo "▸ Erzeuge und signiere appcast.xml …"
    APPCAST_DIR="$BUILD/appcast"
    rm -rf "$APPCAST_DIR"; mkdir -p "$APPCAST_DIR"
    cp "$DMG" "$APPCAST_DIR/Earnote-$VERSION.dmg"
    "$SPARKLE_BIN" \
        --download-url-prefix "https://github.com/louiskl/Earnote/releases/download/v$VERSION/" \
        --link "https://louiskl.github.io/Earnote/" \
        --full-release-notes-url "https://github.com/louiskl/Earnote/releases" \
        -o "$ROOT/docs/appcast.xml" "$APPCAST_DIR"
    # Die Datei im Release heißt immer Earnote.dmg – in der Update-Datei muss derselbe Name stehen.
    /usr/bin/sed -i "" "s|/Earnote-$VERSION.dmg|/Earnote.dmg|g" "$ROOT/docs/appcast.xml"
    echo "  → docs/appcast.xml (committen und pushen, damit Updates ankommen)"
else
    echo "▸ Kein Sparkle gefunden – appcast.xml unverändert (einmal in Xcode bauen hilft)"
fi

echo "✓ Fertig: $DMG  (Earnote $VERSION, $(du -h "$DMG" | cut -f1))"
