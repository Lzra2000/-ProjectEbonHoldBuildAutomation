#!/usr/bin/env sh
# Translation-drift report for the README locales (docs/readme/): for each
# translation, how far its last edit lags behind README.md, and which link
# targets differ. Link URLs are language-neutral, so a target present in
# README.md but absent from a translation is real drift, not translation
# freedom. Report-only -- translations lag by nature, so this is a picture
# for translators (like scripts/i18n-report.sh), not a CI gate.
#
#   sh scripts/readme-drift.sh
set -eu
cd "$(dirname "$0")/.."

extract_links() {
    # Markdown targets + href attributes; strip anchors; local-path noise
    # (banner, language switcher) differs by location on purpose -- skip it.
    { grep -oE '\]\(([^)]+)\)' "$1" | sed 's/^](//; s/)$//'
      grep -oE 'href="[^"]+"' "$1" | sed 's/^href="//; s/"$//'
    } | sed 's/#.*//; s|^\(\.\./\)*||' | grep -vE '^(README|docs/readme/README|assets/)' | grep -v '^$' | sort -u
}

ref_date="$(git log -1 --format=%cs -- README.md)"
echo "README.md last changed: $ref_date"
echo ""
extract_links README.md > /tmp/ebb_readme_links.txt

for f in docs/readme/README.*.md; do
    lang="$(basename "$f" .md | sed 's/^README\.//')"
    d="$(git log -1 --follow --format=%cs -- "$f")"
    behind="$(git rev-list --count "$(git log -1 --follow --format=%H -- "$f")..HEAD" -- README.md)"
    echo "== $lang  (last changed: $d, README.md commits since: $behind) =="
    extract_links "$f" > /tmp/ebb_tr_links.txt
    missing="$(comm -23 /tmp/ebb_readme_links.txt /tmp/ebb_tr_links.txt || true)"
    extra="$(comm -13 /tmp/ebb_readme_links.txt /tmp/ebb_tr_links.txt || true)"
    [ -n "$missing" ] && { echo "  links in README.md but not here:"; echo "$missing" | sed 's/^/    /'; }
    [ -n "$extra" ] && { echo "  links here but not in README.md:"; echo "$extra" | sed 's/^/    /'; }
    [ -z "$missing$extra" ] && echo "  link targets match"
    echo ""
done
