#!/usr/bin/env sh
# MANUAL FALLBACK -- the normal path is .github/workflows/release.yml,
# which publishes the Release automatically when a v* tag is pushed. Use
# this script only when Actions is unavailable. It creates the Release
# (a pushed tag alone is NOT a GitHub Release, only a ref) and uploads
# dist/EbonBuilds.zip as a release asset.
#
#   GITHUB_TOKEN=ghp_xxx sh scripts/publish-github-release.sh 3.06
#
# Pulls the release title/notes straight from the matching "### <version>"
# section of CHANGELOG.md, so run this after scripts/release.sh (which
# requires that section to exist) and after pushing the tag.
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

TITLE="$(printf '%s\n' "$NOTES" | head -1 | sed 's/^### //')"
CHANGES="$(printf '%s\n' "$NOTES" | tail -n +2)"

# The asset download URL is deterministic; the asset itself is uploaded
# right after the release is created below.
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/EbonBuilds.zip"
BODY="**Install:** [Download EbonBuilds.zip]($DOWNLOAD_URL)$(printf '\n')Extract it and drop the \`EbonBuilds\` folder into \`Interface/AddOns/\`.
$(printf '%s' "$CHANGES")"

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
ASSET="$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary @dist/EbonBuilds.zip \
    "$UPLOAD_URL?name=EbonBuilds.zip")"
ASSET_STATE="$(printf '%s' "$ASSET" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || true)"
if [ "$ASSET_STATE" != "uploaded" ]; then
    echo "Release created but asset upload failed -- upload dist/EbonBuilds.zip manually on the release page. Response:" >&2
    echo "$ASSET" >&2
    exit 1
fi

echo "Published: $URL"
