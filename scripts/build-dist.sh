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
#
# Optional companions (when present under vendor/ or DETAILS_SUITE_DIR):
#   Auctionator.zip
#   Details.zip                 — full Details! suite (core + plugins + PE forks)
#   Details_TinyThreat.zip      — legacy single-plugin zip (compat)
#   Details_ProjectEbonhold.zip — legacy single-plugin zip (compat)
#
# DETAILS_SUITE_DIR: optional path to Interface/AddOns (or a folder that
# contains the Details* AddOn directories). When set, suite folders are
# copied from there; PE forks under vendor/ always overlay TinyThreat and
# ProjectEbonhold. When unset, suite folders are taken from vendor/.
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
rm -f dist/EbonBuilds.zip dist/Auctionator.zip dist/Details.zip \
    dist/Details_TinyThreat.zip dist/Details_ProjectEbonhold.zip

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

# Full Details! suite (primary Details release asset).
DETAILS_SUITE_ADDONS="Details Details_3DModelsPaths Details_ChartViewer Details_DataStorage Details_DeathGraphs Details_EncounterDetails Details_SunderCount Details_TimeLine Details_TinyThreat Details_ProjectEbonhold"
DETAILS_SUITE_SRC=""
if [ -n "${DETAILS_SUITE_DIR:-}" ] && [ -f "${DETAILS_SUITE_DIR}/Details/Details.toc" ]; then
    DETAILS_SUITE_SRC="$DETAILS_SUITE_DIR"
elif [ -f vendor/Details/Details.toc ]; then
    DETAILS_SUITE_SRC="vendor"
fi

if [ -n "$DETAILS_SUITE_SRC" ]; then
    DETAILS_STAGE="$STAGE/details_suite"
    mkdir -p "$DETAILS_STAGE"
    missing=0
    for name in $DETAILS_SUITE_ADDONS; do
        src=""
        # PE forks always prefer vendor/ when present.
        if [ "$name" = "Details_TinyThreat" ] || [ "$name" = "Details_ProjectEbonhold" ]; then
            if [ -f "vendor/$name/$name.toc" ]; then
                src="vendor/$name"
            fi
        fi
        if [ -z "$src" ]; then
            if [ -f "$DETAILS_SUITE_SRC/$name/$name.toc" ] || { [ "$name" = "Details" ] && [ -f "$DETAILS_SUITE_SRC/Details/Details.toc" ]; }; then
                src="$DETAILS_SUITE_SRC/$name"
            fi
        fi
        if [ -z "$src" ] || [ ! -d "$src" ]; then
            echo "::error:: Details suite missing AddOn folder: $name (src=$DETAILS_SUITE_SRC)" >&2
            missing=1
            continue
        fi
        mkdir -p "$DETAILS_STAGE/$name"
        cp -r "$src"/. "$DETAILS_STAGE/$name/"
        if [ -d "$DETAILS_STAGE/$name/Interface" ] || [ -d "$DETAILS_STAGE/$name/AddOns" ]; then
            echo "::error:: Details suite folder $name contains nested Interface/AddOns — refuse to ship" >&2
            missing=1
            continue
        fi
        if [ ! -f "$DETAILS_STAGE/$name/$name.toc" ]; then
            echo "::error:: Details suite missing root TOC: $name/$name.toc" >&2
            missing=1
            continue
        fi
    done
    if [ "$missing" -eq 0 ]; then
        (
            cd "$DETAILS_STAGE"
            # shellcheck disable=SC2086
            zip -rq -X "$OLDPWD/dist/Details.zip" $DETAILS_SUITE_ADDONS
        )
        echo "Built dist/Details.zip ($(du -h dist/Details.zip | cut -f1)) — full Details! suite (core + plugins + PE TinyThreat/ProjectEbonhold); extract top-level folders into Interface/AddOns/"
    else
        echo "::error:: Details.zip not built (missing suite folders)" >&2
        exit 1
    fi
fi

if [ -d vendor/Details_TinyThreat ] && [ -f vendor/Details_TinyThreat/Details_TinyThreat.toc ]; then
    TT_PKG="$STAGE/Details_TinyThreat"
    mkdir -p "$TT_PKG"
    cp -r vendor/Details_TinyThreat/. "$TT_PKG/"
    (cd "$STAGE" && zip -rq -X "$OLDPWD/dist/Details_TinyThreat.zip" Details_TinyThreat)
    echo "Built dist/Details_TinyThreat.zip ($(du -h dist/Details_TinyThreat.zip | cut -f1)) — legacy single-plugin zip; prefer Details.zip; see vendor/Details_TinyThreat/CREDITS.md"
fi

if [ -d vendor/Details_ProjectEbonhold ] && [ -f vendor/Details_ProjectEbonhold/Details_ProjectEbonhold.toc ]; then
    PE_PKG="$STAGE/Details_ProjectEbonhold"
    mkdir -p "$PE_PKG"
    cp -r vendor/Details_ProjectEbonhold/. "$PE_PKG/"
    (cd "$STAGE" && zip -rq -X "$OLDPWD/dist/Details_ProjectEbonhold.zip" Details_ProjectEbonhold)
    echo "Built dist/Details_ProjectEbonhold.zip ($(du -h dist/Details_ProjectEbonhold.zip | cut -f1)) — legacy single-plugin zip; prefer Details.zip; see vendor/Details_ProjectEbonhold/CREDITS.md"
fi

echo "Built dist/EbonBuilds.zip ($(du -h dist/EbonBuilds.zip | cut -f1))"

sh scripts/verify-package.sh