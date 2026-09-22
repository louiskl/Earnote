#!/bin/bash
# Veröffentlicht die Fassung, die in scripts/generate_xcodeproj.py steht, in einem Rutsch:
#
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="earnote-notary" \
#   ./scripts/publish_release.sh
#
# 1. baut, signiert und notarisiert (build_release.sh) – samt signierter appcast.xml
# 2. legt das GitHub-Release v<Version> mit dist/Earnote.dmg und docs/releases/<Version>.md an
# 3. committet appcast.xml, README und Website-Version und pusht nach main –
#    erst jetzt bieten die Apps das Update an (das Release mit der DMG steht da schon)
# 4. hebt den Homebrew-Tap auf die neue Version (Version und sha256)
#
# Braucht die GitHub-CLI (`brew install gh`, einmal `gh auth login`). Bricht vor dem ersten
# Schritt nach außen ab, wenn etwas fehlt, und fragt vor dem Veröffentlichen noch einmal nach.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "✗ $1" >&2; exit 1; }

VERSION="$(sed -nE 's/^MARKETING_VERSION = "([0-9.]+)"/\1/p' scripts/generate_xcodeproj.py)"
[[ -n "$VERSION" ]] || fail "Version in scripts/generate_xcodeproj.py nicht gefunden"
NOTES="docs/releases/$VERSION.md"
TAG="v$VERSION"

echo "▸ Prüfe Voraussetzungen für Earnote $VERSION …"
command -v gh >/dev/null || fail "GitHub-CLI fehlt: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || fail "GitHub-CLI nicht angemeldet: gh auth login"
[[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]] \
    || fail "DEVELOPER_ID und NOTARY_PROFILE setzen – veröffentlicht wird nur signiert und notarisiert"
[[ -f "$NOTES" ]] || fail "Release-Notizen fehlen: $NOTES"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Nicht auf main"
[[ -z "$(git status --porcelain)" ]] || fail "Es gibt ungesicherte Änderungen (git status)"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main ist nicht auf dem Stand von origin/main (git pull)"
if gh release view "$TAG" >/dev/null 2>&1; then fail "Release $TAG gibt es schon"; fi

read -r -p "Earnote $VERSION bauen und veröffentlichen? [j/N] " answer
[[ "$answer" == "j" || "$answer" == "J" ]] || { echo "Abgebrochen."; exit 0; }

./scripts/build_release.sh

# Ohne neue appcast.xml käme das Update bei niemandem an – dann lieber gar nicht veröffentlichen
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" docs/appcast.xml \
    || fail "appcast.xml enthält $VERSION nicht (Sparkle nicht gefunden?) – nichts veröffentlicht"

echo "▸ Lege GitHub-Release $TAG an …"
gh release create "$TAG" dist/Earnote.dmg --target main --title "Earnote $VERSION" --notes-file "$NOTES"

echo "▸ Update-Datei, README und Website auf $VERSION …"
/usr/bin/sed -i "" -E "s/\*\*beta\*\* \([0-9.]+\)/**beta** ($VERSION)/" README.md
/usr/bin/sed -i "" -E "s/\"softwareVersion\": \"[0-9.]+\"/\"softwareVersion\": \"$VERSION\"/" docs/index.html docs/de.html
git add docs/appcast.xml README.md docs/index.html docs/de.html
git commit -q -m "Veröffentlicht: $VERSION"
git push -q origin main

echo "▸ Hebe den Homebrew-Tap …"
SHA="$(shasum -a 256 dist/Earnote.dmg | cut -d' ' -f1)"
TAP="$(mktemp -d)"
gh repo clone louiskl/homebrew-earnote "$TAP" -- -q --depth 1
/usr/bin/sed -i "" -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/earnote.rb"
git -C "$TAP" commit -q -am "Earnote $VERSION"
git -C "$TAP" push -q
rm -rf "$TAP"

echo "✓ Earnote $VERSION ist veröffentlicht: Release, Update für die Apps, Website und Homebrew."
