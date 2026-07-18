#!/usr/bin/env sh
# Packages the addon source into dist/EbonBuilds.zip, ready to drop into
# Interface/AddOns/EbonBuilds.
#
# Included: EbonBuilds.toc, FAQ.md, core/, modules/ -- everything the .toc
# actually loads plus the in-game FAQ source.
# Excluded: repo/dev-only files that don't belong in an installed addon --
# READMEs (all locales), UI_UX_REVIEW.md, tests/, .github/, .gitignore, .git,
# dist/ itself, and scripts/.
set -eu
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

PKG="$STAGE/EbonBuilds"
mkdir -p "$PKG"

cp EbonBuilds.toc "$PKG/"
cp FAQ.md "$PKG/"
cp -r core "$PKG/"
cp -r modules "$PKG/"

mkdir -p dist
rm -f dist/EbonBuilds.zip

# Verify every file the .toc references made it into the package before
# zipping, so a stale build script can't silently ship a broken addon.
grep -E '^\S+\.lua$' EbonBuilds.toc > "$STAGE/toc_files.txt"
fail=0
while IFS= read -r f; do
    [ -f "$PKG/$f" ] || { echo "::error:: TOC file missing from package: $f" >&2; fail=1; }
done < "$STAGE/toc_files.txt"
[ "$fail" -eq 0 ] || exit 1

(cd "$STAGE" && zip -rq -X "$OLDPWD/dist/EbonBuilds.zip" EbonBuilds)

echo "Built dist/EbonBuilds.zip ($(du -h dist/EbonBuilds.zip | cut -f1))"
