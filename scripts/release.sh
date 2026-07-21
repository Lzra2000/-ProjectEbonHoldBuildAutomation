#!/usr/bin/env sh
# Release helper enforcing the project's standing convention: every release
# bumps EbonBuilds.toc's version, documents itself in CHANGELOG.md, passes
# the full check suite, and is committed + tagged.
#
#   sh scripts/release.sh 3.06
#
# Does NOT push -- review the commit/tag and push yourself:
#   git push origin main && git push origin v3.06
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: sh scripts/release.sh <new-version>   (e.g. 3.06)" >&2
    exit 1
fi
NEW_VERSION="$1"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree not clean -- commit or stash your changes first." >&2
    git status --short
    exit 1
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"

if [ -n "$LAST_TAG" ]; then
    if git diff --quiet "$LAST_TAG" -- CHANGELOG.md 2>/dev/null; then
        echo "CHANGELOG.md has not changed since $LAST_TAG." >&2
        echo "Convention: every release documents its changes in a '### <version>' CHANGELOG.md entry (shown in-game as What's New). Update it before releasing." >&2
        exit 1
    fi
fi

echo "== Bumping version: EbonBuilds.toc, docs/faq.md header =="
if ! grep -q "^## Version:" EbonBuilds.toc; then
    echo "Could not find '## Version:' line in EbonBuilds.toc" >&2
    exit 1
fi
sed -i.bak "s/^## Version: .*/## Version: $NEW_VERSION/" EbonBuilds.toc && rm -f EbonBuilds.toc.bak

if grep -q "Latest version: " docs/faq.md; then
    sed -i.bak "s/Latest version: [^ ]*/Latest version: $NEW_VERSION/" docs/faq.md && rm -f docs/faq.md.bak
fi

echo ""
echo "== Running full check suite =="
echo "== Regenerating in-game FAQ pages from docs/faq.md + CHANGELOG.md =="
sh scripts/build-faq-pages.sh
sh scripts/check.sh

echo ""
echo "== Building dist/EbonBuilds.zip (smoke test only -- the release asset is built and uploaded by .github/workflows/release.yml) =="
sh scripts/build-dist.sh

echo ""
echo "== Committing and tagging =="
git add EbonBuilds.toc CHANGELOG.md docs/faq.md modules/data/FAQContent.lua
git commit -q -m "chore(release): bump version to $NEW_VERSION"
git tag "v$NEW_VERSION" -m "v$NEW_VERSION"

echo ""
echo "Done. Review with 'git show HEAD' then push:"
echo "  git push origin main && git push origin v$NEW_VERSION"
echo "Pushing the tag triggers .github/workflows/release.yml, which runs the"
echo "checks, builds the zip, and publishes the GitHub Release with the asset."
echo "Manual fallback if Actions is unavailable:"
echo "  GITHUB_TOKEN=... sh scripts/publish-github-release.sh $NEW_VERSION"
