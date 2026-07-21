#!/usr/bin/env sh
# One-time setup: installs the toolchain used by scripts/check.sh,
# scripts/build-dist.sh, and CI. Debian/Ubuntu only (apt-get).
#
#   sh scripts/dev-setup.sh
set -eu

need_sudo=""
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        need_sudo="sudo"
    else
        echo "Not root and no sudo available -- install lua5.1, texlive-binaries, and zip manually." >&2
        exit 1
    fi
fi

echo "Installing lua5.1 (matches WotLK 3.3.5a's runtime -- syntax check, test suite, and FAQ page generation all run on it) and zip (dist packaging)..."
$need_sudo apt-get update -qq
$need_sudo apt-get install -y -qq lua5.1 zip

echo ""
echo "Done. Verify with: sh scripts/check.sh"
