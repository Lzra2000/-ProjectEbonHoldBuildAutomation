#!/usr/bin/env sh
# Post-build smoke check for dist/EbonBuilds.zip (and optional Auctionator.zip).
# Validates every TOC-listed path exists inside the zip, rejects UTF-8 BOM on
# shipped locale files, and ensures dev-only paths did not leak into the package.
#
#   sh scripts/build-dist.sh && sh scripts/verify-package.sh
#   sh scripts/verify-package.sh --build   # build first when dist/ is missing
#
# Optional companion: vendor/Auctionator/ is documented in vendor/Auctionator/CREDITS.md
# and ships as dist/Auctionator.zip when the vendored tree is present.
set -eu
cd "$(dirname "$0")/.."

BUILD_FIRST=0
SKIP_AUCTIONATOR=0
while [ $# -gt 0 ]; do
    case "$1" in
        --build) BUILD_FIRST=1; shift ;;
        --skip-auctionator) SKIP_AUCTIONATOR=1; shift ;;
        --help|-h)
            cat <<'EOF'
Usage: sh scripts/verify-package.sh [--build] [--skip-auctionator]

  --build             Run scripts/build-dist.sh first if dist/EbonBuilds.zip is missing
  --skip-auctionator  Do not validate dist/Auctionator.zip even when present
EOF
            exit 0 ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2 ;;
    esac
done

if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi

if [ ! -f dist/EbonBuilds.zip ]; then
    if [ "$BUILD_FIRST" -eq 1 ]; then
        sh scripts/build-dist.sh
    else
        echo "dist/EbonBuilds.zip not found -- run: sh scripts/build-dist.sh" >&2
        exit 1
    fi
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

fail=0
annotate() {
    printf '::error::%s\n' "$1" >&2
}

has_utf8_bom() {
    [ "$(head -c 3 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')" = "efbbbf" ]
}

check_locale_boms() {
    root=$1
    label=$2
    # shellcheck disable=SC2044
    for f in $(find "$root" \( -path '*/locales/*.lua' -o -path '*/Locales/*.lua' \) 2>/dev/null); do
        [ -f "$f" ] || continue
        if has_utf8_bom "$f"; then
            rel=${f#"$root"/}
            echo "BOM FAIL: $label locale has UTF-8 BOM: $rel" >&2
            annotate "$label locale has UTF-8 BOM: $rel"
            fail=1
        fi
    done
}

verify_toc_package() {
    toc=$1
    pkg_root=$2
    label=$3

    [ -f "$toc" ] || {
        echo "PACKAGE FAIL: missing $label .toc at $toc" >&2
        annotate "missing $label .toc in package"
        fail=1
        return
    }

    toc_list="$STAGE/${label}-toc.txt"
    if [ "$label" = "EbonBuilds" ]; then
        awk '{ sub(/\r$/, ""); if ($0 ~ /^[^[:space:]]+\.lua$/) print }' "$toc" > "$toc_list"
    else
        awk '{ sub(/\r$/, ""); gsub(/\\/, "/"); if ($0 ~ /^[^#[:space:]].+\.(lua|xml)$/) print }' "$toc" > "$toc_list"
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ ! -f "$pkg_root/$path" ]; then
            echo "PACKAGE FAIL: $label TOC entry missing from zip: $path" >&2
            annotate "$label TOC entry missing from zip: $path"
            fail=1
        fi
    done < "$toc_list"

    check_locale_boms "$pkg_root" "$label"
}

echo "== Verifying dist/EbonBuilds.zip =="
unzip -q dist/EbonBuilds.zip -d "$STAGE"
EB_ROOT="$STAGE/EbonBuilds"
verify_toc_package "$EB_ROOT/EbonBuilds.toc" "$EB_ROOT" "EbonBuilds"

for forbidden in docs tests .github README.md CHANGELOG.md; do
    if [ -e "$EB_ROOT/$forbidden" ]; then
        echo "PACKAGE FAIL: dev-only path leaked into EbonBuilds.zip: $forbidden" >&2
        annotate "dev-only path leaked into EbonBuilds.zip: $forbidden"
        fail=1
    fi
done

for required in media/minimap_icon.tga media/vote_icon.tga media/vote_icon_off.tga media/affix_pip.tga; do
    if [ ! -f "$EB_ROOT/$required" ]; then
        echo "PACKAGE FAIL: required media missing from EbonBuilds.zip: $required" >&2
        annotate "required media missing from EbonBuilds.zip: $required"
        fail=1
    fi
done

if [ "$SKIP_AUCTIONATOR" -eq 0 ] && [ -f dist/Auctionator.zip ]; then
    echo ""
    echo "== Verifying optional dist/Auctionator.zip =="
    unzip -q dist/Auctionator.zip -d "$STAGE"
    ATR_ROOT="$STAGE/Auctionator"
    verify_toc_package "$ATR_ROOT/Auctionator.toc" "$ATR_ROOT" "Auctionator"
    echo "Optional Auctionator bundle verified — see vendor/Auctionator/CREDITS.md"
elif [ -d vendor/Auctionator ] && [ -f vendor/Auctionator/Auctionator.toc ] && [ ! -f dist/Auctionator.zip ]; then
    echo ""
    echo "WARN: vendor/Auctionator present but dist/Auctionator.zip was not built" >&2
    annotate "vendor/Auctionator present but dist/Auctionator.zip missing"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo ""
    echo "Package smoke check FAILED." >&2
    exit 1
fi

echo ""
echo "Package smoke check OK (EbonBuilds TOC paths, locale BOMs, media, no dev leaks)."
if [ -f dist/Auctionator.zip ]; then
    echo "Optional Auctionator.zip included — install separately; see vendor/Auctionator/CREDITS.md"
fi
