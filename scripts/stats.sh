#!/bin/bash
# Zahlen zu Earnote auf einen Blick – nur lesend, braucht die angemeldete GitHub-CLI (gh).
#
#   ./scripts/stats.sh
#
# Downloads: Jede DMG zählt einmal – ob über die Website, Homebrew oder ein Update aus der App (Sparkle lädt
# dieselbe Datei). Die Zahl der neuesten Version in den ersten Tagen ist deshalb ein guter Hinweis darauf,
# wie viele Macs Earnote gerade benutzen: Wer die App offen hat, bekommt das Update angeboten.
# Besuche und Herkunft zeigt GitHub nur für die letzten 14 Tage und mit einigen Stunden Verzögerung.
set -euo pipefail
REPO="louiskl/Earnote"

echo "▸ Downloads je Version (DMG)"
gh api "repos/$REPO/releases" --paginate \
    -q '.[] | [.tag_name, .published_at[:10], ([.assets[] | select(.name | endswith(".dmg")) | .download_count] | add // 0)] | @tsv' \
    | sort -V | awk -F'\t' '{ printf "  %-9s %s  %4d\n", $1, $2, $3; sum += $3 } END { printf "  %-9s %s  %4d\n", "gesamt", "          ", sum }'

echo
echo "▸ Sterne: $(gh api "repos/$REPO" -q .stargazers_count)"
gh api -H "Accept: application/vnd.github.star+json" "repos/$REPO/stargazers" --paginate \
    -q '.[] | "  " + .starred_at[:10] + "  " + .user.login' | tail -5

echo
echo "▸ Besuche der GitHub-Seite (14 Tage)"
gh api "repos/$REPO/traffic/views" -q '"  \(.count) Aufrufe von \(.uniques) Personen"'
echo "▸ Woher sie kamen"
gh api "repos/$REPO/traffic/popular/referrers" -q '.[] | "  \(.referrer): \(.uniques) Personen"'
