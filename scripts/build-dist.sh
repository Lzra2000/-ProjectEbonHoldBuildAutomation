#!/usr/bin/env sh
# Packages the addon source into dist/EbonBuilds.zip, ready to drop into
# Interface/AddOns/EbonBuilds.
#
# Included: EbonBuilds.toc, core/, modules/, media/ -- everything the .toc
# actually loads plus custom textures. The in-game FAQ ships as the
# generated modules/data/FAQContent.lua; its sources (docs/faq.md,
# CHANGELOG.md) stay repo-only.
# Excluded: repo/dev-only files that don't belong in an installed addon --
# docs/, CHANGELOG.md, READMEs (all locales), tests/, .github/,
# .gitignore, .git, dist/ itself, and scripts/.
set -eu
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

PKG="$STAGE/EbonBuilds"
mkdir -p "$PKG"

cp EbonBuilds.toc "$PKG/"
cp -r core "$PKG/"
cp -r modules "$PKG/"
[ -d media ] && cp -r media "$PKG/"

mkdir -p dist
rm -f dist/EbonBuilds.zip dist/Auctionator.zip dist/Details_TinyThreat.zip dist/Details_ProjectEbonhold.zip

# Verify every file the .toc references made it into the package before
# zipping, so a stale build script can't silently ship a broken addon.
awk '{ sub(/\r$/, ""); if ($0 ~ /^[^[:space:]]+\.lua$/) print }' EbonBuilds.toc > "$STAGE/toc_files.txt"
fail=0
while IFS= read -r f; do
    [ -f "$PKG/$f" ] || { echo "::error:: TOC file missing from package: $f" >&2; fail=1; }
done < "$STAGE/toc_files.txt"
[ "$fail" -eq 0 ] || exit 1

(cd "$STAGE" && zip -rq -X "$OLDPWD/dist/EbonBuilds.zip" EbonBuilds)

if [ -d vendor/Auctionator ] && [ -f vendor/Auctionator/Auctionator.toc ]; then
    ATR_PKG="$STAGE/Auctionator"
    mkdir -p "$ATR_PKG"
    cp -r vendor/Auctionator/. "$ATR_PKG/"
    (cd "$STAGE" && zip -rq -X "$OLDPWD/dist/Auctionator.zip" Auctionator)
    echo "Built dist/Auctionator.zip ($(du -h dist/Auctionator.zip | cut -f1)) — Project Ebonhold fork; see vendor/Auctionator/CREDITS.md"
fi

if [ -d vendor/Details_TinyThreat ] && [ -f vendor/Details_TinyThreat/Details_TinyThreat.toc ]; then
    TT_PKG="$STAGE/Details_TinyThreat"
    mkdir -p "$TT_PKG"
    cp -r vendor/Details_TinyThreat/. "$TT_PKG/"
    (cd "$STAGE" && zip -rq -X "$OLDPWD/dist/Details_TinyThreat.zip" Details_TinyThreat)
    echo "Built dist/Details_TinyThreat.zip ($(du -h dist/Details_TinyThreat.zip | cut -f1)) — Project Ebonhold fork; requires Details! core; see vendor/Details_TinyThreat/CREDITS.md"
fi

if [ -d vendor/Details_ProjectEbonhold ] && [ -f vendor/Details_ProjectEbonhold/Details_ProjectEbonhold.toc ]; then
    PE_PKG="$STAGE/Details_ProjectEbonhold"
    mkdir -p "$PE_PKG"
    cp -r vendor/Details_ProjectEbonhold/. "$PE_PKG/"
    (cd "$STAGE" && zip -rq -X "$OLDPWD/dist/Details_ProjectEbonhold.zip" Details_ProjectEbonhold)
    echo "Built dist/Details_ProjectEbonhold.zip ($(du -h dist/Details_ProjectEbonhold.zip | cut -f1)) — Details PE fine-tune (Echo/procs); requires Details! core; see vendor/Details_ProjectEbonhold/CREDITS.md"
fi

echo "Built dist/EbonBuilds.zip ($(du -h dist/EbonBuilds.zip | cut -f1))"

sh scripts/verify-package.sh
