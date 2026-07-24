#!/usr/bin/env sh
# MANUAL FALLBACK -- the normal path is .github/workflows/release.yml,
# which publishes the Release automatically when a v* tag is pushed. Use
# this script only when Actions is unavailable. It creates the Release
# (a pushed tag alone is NOT a GitHub Release, only a ref) and uploads
# dist/*.zip release assets.
#
#   GITHUB_TOKEN=ghp_xxx sh scripts/publish-github-release.sh 3.06
#
# Title is the short form "EbonBuilds <version>"; release notes come from the
# matching "### <version>" section of CHANGELOG.md. Run after scripts/release.sh
# (which requires that section to exist) and after pushing the tag.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: GITHUB_TOKEN=... sh scripts/publish-github-release.sh <version>   (e.g. 3.06)" >&2
    exit 1
fi
VERSION="$1"
TAG="v$VERSION"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is not set. Export a token with 'repo' scope first." >&2
    exit 1
fi

REPO="$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
if [ -z "$REPO" ]; then
    echo "Could not determine owner/repo from 'origin' remote." >&2
    exit 1
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Local tag $TAG not found -- run scripts/release.sh first." >&2
    exit 1
fi

if [ ! -f dist/EbonBuilds.zip ]; then
    echo "dist/EbonBuilds.zip not found -- building it now."
    sh scripts/build-dist.sh
fi

# Pull the notes: from "### $VERSION" up to (not including) the next "### ".
NOTES="$(awk -v ver="^### $VERSION " '
    $0 ~ ver { found=1; print; next }
    found && /^### / { exit }
    found { print }
' CHANGELOG.md)"

if [ -z "$NOTES" ]; then
    echo "No '### $VERSION' section found in CHANGELOG.md -- add a changelog entry first." >&2
    exit 1
fi

TITLE="EbonBuilds $VERSION"

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/EbonBuilds.zip"
EXTRA_LINES=""
if [ -f dist/Auctionator.zip ]; then
    ATR_URL="https://github.com/$REPO/releases/download/$TAG/Auctionator.zip"
    EXTRA_LINES="${EXTRA_LINES}$(printf '\n')Optional affix shopping: [Download Auctionator.zip]($ATR_URL) — extract to \`Interface/AddOns/Auctionator\` (EbonBuilds enables bridge features when present)."
fi
if [ -f dist/Details.zip ]; then
    DET_URL="https://github.com/$REPO/releases/download/$TAG/Details.zip"
    EXTRA_LINES="${EXTRA_LINES}$(printf '\n')**Details! suite (recommended):** [Download Details.zip]($DET_URL) — full pack (Details core + plugins + TinyThreat + ProjectEbonhold). Extract so each folder lands top-level under \`Interface/AddOns/\`."
fi
if [ -f dist/Details_TinyThreat.zip ]; then
    TT_URL="https://github.com/$REPO/releases/download/$TAG/Details_TinyThreat.zip"
    EXTRA_LINES="${EXTRA_LINES}$(printf '\n')Legacy single-plugin: [Details_TinyThreat.zip]($TT_URL) — prefer Details.zip when available."
fi
if [ -f dist/Details_ProjectEbonhold.zip ]; then
    PE_URL="https://github.com/$REPO/releases/download/$TAG/Details_ProjectEbonhold.zip"
    EXTRA_LINES="${EXTRA_LINES}$(printf '\n')Legacy single-plugin: [Details_ProjectEbonhold.zip]($PE_URL) — prefer Details.zip when available."
fi
BODY="**Install:** [Download EbonBuilds.zip]($DOWNLOAD_URL)$(printf '\n')Extract it and drop the \`EbonBuilds\` folder into \`Interface/AddOns/\`.$EXTRA_LINES
$(printf '\n')$(printf '%s' "$NOTES")"

PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE"' EXIT
python3 - "$TAG" "$TITLE" "$BODY" > "$PAYLOAD_FILE" <<'PYEOF'
import json, sys
tag, title, body = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"tag_name": tag, "name": title, "body": body, "draft": False, "prerelease": False}))
PYEOF

RESPONSE="$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d @"$PAYLOAD_FILE")"

URL="$(printf '%s' "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('html_url',''))" 2>/dev/null || true)"

if [ -z "$URL" ]; then
    echo "Failed to create release. Response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

UPLOAD_URL="$(printf '%s' "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['upload_url'].split('{')[0])")"

upload_zip() {
    name=$1
    path=$2
    ASSET="$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/zip" \
        --data-binary @"$path" \
        "$UPLOAD_URL?name=$name")"
    ASSET_STATE="$(printf '%s' "$ASSET" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || true)"
    if [ "$ASSET_STATE" != "uploaded" ]; then
        echo "$name upload failed -- upload $path manually. Response:" >&2
        echo "$ASSET" >&2
        exit 1
    fi
}

upload_zip EbonBuilds.zip dist/EbonBuilds.zip
[ -f dist/Auctionator.zip ] && upload_zip Auctionator.zip dist/Auctionator.zip
[ -f dist/Details.zip ] && upload_zip Details.zip dist/Details.zip
[ -f dist/Details_TinyThreat.zip ] && upload_zip Details_TinyThreat.zip dist/Details_TinyThreat.zip
[ -f dist/Details_ProjectEbonhold.zip ] && upload_zip Details_ProjectEbonhold.zip dist/Details_ProjectEbonhold.zip

echo "Published: $URL"