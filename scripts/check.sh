#!/usr/bin/env sh
# Runs the same checks as .github/workflows/lua-syntax.yml, locally and in
# one command, so a broken build is caught before pushing instead of in CI.
#
#   sh scripts/check.sh
#
# Requires: lua5.1 (syntax check AND test suite -- the tests run on the
# same Lua version as the WoW 3.3.5a client, so version-semantics bugs
# can't hide behind a different runtime). See scripts/dev-setup.sh.
set -eu
cd "$(dirname "$0")/.."

overall_fail=0

echo "== 1/5  Lua 5.1 syntax check (excludes tests/) =="
if ! command -v luac5.1 >/dev/null 2>&1; then
    echo "luac5.1 not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi
fail=0
find . -name "*.lua" -not -path "./tests/*" -not -path "./.git/*" > /tmp/ebb_lua_files.txt
while IFS= read -r f; do
    if ! luac5.1 -p "$f"; then
        echo "SYNTAX ERROR: $f"
        fail=1
    fi
done < /tmp/ebb_lua_files.txt
if [ "$fail" -eq 0 ]; then echo "OK: no syntax errors"; else overall_fail=1; fi

echo ""
echo "== 2/5  Test suite (tests/run.sh, on lua5.1 -- the client's runtime) =="
if sh tests/run.sh; then
    echo "OK: test suite passed"
else
    overall_fail=1
fi

echo ""
echo "== 3/5  Every .toc file exists on disk =="
fail=0
awk '{ sub(/\r$/, ""); if ($0 ~ /^[^[:space:]]+\.lua$/) print }' EbonBuilds.toc > /tmp/ebb_toc_files.txt
while IFS= read -r line; do
    [ -f "$line" ] || { echo "MISSING: $line (listed in EbonBuilds.toc)"; fail=1; }
done < /tmp/ebb_toc_files.txt
if [ "$fail" -eq 0 ]; then echo "OK: all TOC files present"; else overall_fail=1; fi

echo ""
echo "== 4/5  No post-3.3.5a WoW API calls =="
if ! sh scripts/check-335a-api.sh; then
    overall_fail=1
fi

echo ""
echo "== 5/5  File header convention (core/ and modules/) =="
# Every hand-written Lua file starts with the responsibility header from
# CONTRIBUTING.md; generated data files are exempt via their own
# "-- Generated" marker (regeneration would drop a hand-added header).
fail=0
for f in $(find core modules -name "*.lua"); do
    if ! head -5 "$f" | grep -qE "^-- (EbonBuilds:|Generated)"; then
        echo "MISSING HEADER: $f (expected '-- EbonBuilds: <path>' or '-- Generated ...' in the first 5 lines)"
        fail=1
    fi
done
if [ "$fail" -eq 0 ]; then echo "OK: all file headers present"; else overall_fail=1; fi

echo ""
if [ "$overall_fail" -eq 0 ]; then
    echo "All checks passed."
else
    echo "One or more checks FAILED -- see above." >&2
fi
exit $overall_fail
