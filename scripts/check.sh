#!/usr/bin/env sh
# Runs the same checks as .github/workflows/lua-syntax.yml, locally and in
# one command, so a broken build is caught before pushing instead of in CI.
#
#   sh scripts/check.sh                 # fast local loop (skips 70k board sim)
#   sh scripts/check.sh --full          # what CI runs (includes slow sim)
#   sh scripts/check.sh --only tests
#   sh scripts/check.sh --only architecture
#   FILTER=api VERBOSE=1 sh scripts/check.sh
#
# Requires: lua5.1 (syntax check AND test suite -- the tests run on the
# same Lua version as the WoW 3.3.5a client). See scripts/dev-setup.sh and
# docs/dev-testing.md. On Windows use Git Bash or: powershell scripts/check.ps1
set -eu
cd "$(dirname "$0")/.."

FULL="${EBB_FULL:-0}"
FILTER="${FILTER:-${EBB_FILTER:-}}"
VERBOSE="${VERBOSE:-${EBB_VERBOSE:-0}}"
ANNOTATE="${EBB_ANNOTATE:-0}"
LOG_DIR="${EBB_LOG_DIR:-.cache/check-logs}"

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    ANNOTATE=1
fi

usage() {
    cat <<'EOF'
Usage: sh scripts/check.sh [options]

Options:
  --full              Full suite (includes 70k board simulation; CI uses this)
  --only <check>      Run one check group (see below)
  --verbose, -v       Extra context (tool paths, timings, skip reasons)
  --help, -h          Show this help

Check groups for --only / FILTER:
  syntax       Lua 5.1 syntax (luac5.1 -p) over core/modules (not tests/)
  tests        tests/run.sh (honours --full / FILTER for individual files)
  toc          Every .lua listed in EbonBuilds.toc exists on disk
  package      Build dist/EbonBuilds.zip and run scripts/verify-package.sh
  api          Post-3.3.5a WoW API blocklist (scripts/check-335a-api.sh)
  headers      File header convention in core/ and modules/
  media        Required media/*.tga files exist on disk
  architecture Convenience alias -> tests with filter "architecture"
  <name>       Any other value is passed to tests/run.sh --only <name>

Environment:
  FILTER / EBB_FILTER     Same as --only
  EBB_FULL=1              Same as --full
  VERBOSE / EBB_VERBOSE=1 Same as --verbose
  EBB_LOG_DIR             Log directory (default .cache/check-logs)
  EBB_ANNOTATE=1          Emit GitHub Actions ::error annotations

Examples:
  sh scripts/check.sh --only architecture
  sh scripts/check.sh --only freeze
  VERBOSE=1 sh scripts/check.sh --only api
  sh scripts/check.sh --full
  powershell -File scripts/check.ps1 --only tests

Common failure classes (see docs/dev-testing.md):
  architecture RegisterEvent  -> use core/WoWEvents.lua, not frame:RegisterEvent
  and-nil-or lint             -> explicit if/else toggles (issue #39)
  3.3.5a API scan             -> no SetShown/C_Timer/IsInGroup/...
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --full) FULL=1; shift ;;
        --only)
            if [ $# -lt 2 ]; then echo "ERROR: --only needs a name" >&2; exit 2; fi
            FILTER="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        -*)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2 ;;
        *)
            FILTER="$1"; shift ;;
    esac
done

mkdir -p "$LOG_DIR"
RUN_STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo manual)
SUMMARY_LOG="$LOG_DIR/check-${RUN_STAMP}.log"
: > "$SUMMARY_LOG"

want() {
    # want <group-name> â€” true if FILTER empty or equals this group
    group=$1
    [ -z "$FILTER" ] && return 0
    [ "$FILTER" = "$group" ] && return 0
    return 1
}

# Non-group filters (e.g. architecture, freeze) mean "tests only".
is_known_group() {
    case "$1" in
        syntax|tests|toc|api|headers|media|package|architecture) return 0 ;;
        *) return 1 ;;
    esac
}

run_tests_only=0
if [ -n "$FILTER" ] && ! is_known_group "$FILTER"; then
    run_tests_only=1
fi
if [ "$FILTER" = "architecture" ]; then
    run_tests_only=1
fi

overall_fail=0
failed_checks=""

log() {
    printf '%s\n' "$*" | tee -a "$SUMMARY_LOG"
}

log_err() {
    printf '%s\n' "$*" | tee -a "$SUMMARY_LOG" >&2
}

annotate_line() {
    # annotate_line file [line] message
    [ "$ANNOTATE" = "1" ] || return 0
    file=$1; shift
    line=""
    case "${1:-}" in
        [0-9]*) line=$1; shift ;;
    esac
    msg=$(printf '%s' "$*" | tr '\n' ' ')
    if [ -n "$line" ]; then
        printf '::error file=%s,line=%s::%s\n' "$file" "$line" "$msg"
    else
        printf '::error file=%s::%s\n' "$file" "$msg"
    fi
}

if [ "$VERBOSE" = "1" ]; then
    log "VERBOSE: cwd=$(pwd)"
    log "VERBOSE: FULL=$FULL FILTER=${FILTER:-<all>} ANNOTATE=$ANNOTATE"
    log "VERBOSE: lua5.1=$(command -v lua5.1 2>/dev/null || echo missing)"
    log "VERBOSE: luac5.1=$(command -v luac5.1 2>/dev/null || echo missing)"
    log "VERBOSE: log dir=$LOG_DIR summary=$SUMMARY_LOG"
fi

# ---- 1. Syntax -------------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want syntax; then
    log "== Lua 5.1 syntax check (excludes tests/) =="
    if ! command -v luac5.1 >/dev/null 2>&1; then
        log_err "luac5.1 not found -- run: sh scripts/dev-setup.sh"
        log_err "Re-run: sh scripts/check.sh --only syntax"
        exit 1
    fi
    fail=0
    LUA_LIST="$LOG_DIR/lua-files-${RUN_STAMP}.txt"
    # Prefer find; fall back to a simple walk if find is missing (rare).
    if command -v find >/dev/null 2>&1; then
        find . -name "*.lua" -not -path "./tests/*" -not -path "./.git/*" -not -path "./.cache/*" -not -path "./site/*" > "$LUA_LIST"
    else
        printf '%s\n' core/*.lua modules/*/*.lua > "$LUA_LIST"
    fi
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        syn_log="$LOG_DIR/syntax-$(echo "$f" | tr '/\\' '__')-${RUN_STAMP}.log"
        set +e
        luac5.1 -p "$f" >"$syn_log" 2>&1
        rc=$?
        set -e
        if [ "$rc" -ne 0 ]; then
            log_err "SYNTAX ERROR: $f"
            cat "$syn_log" | tee -a "$SUMMARY_LOG" >&2
            # luac messages look like: luac5.1: path.lua:12: syntax error
            lineno=$(sed -n 's/.*\.lua:\([0-9][0-9]*\):.*/\1/p' "$syn_log" | head -n 1)
            msg=$(tr '\n' ' ' < "$syn_log")
            if [ -n "$lineno" ]; then
                annotate_line "$f" "$lineno" "$msg"
            else
                annotate_line "$f" "$msg"
            fi
            fail=1
        fi
    done < "$LUA_LIST"
    if [ "$fail" -eq 0 ]; then
        log "OK: no syntax errors"
    else
        overall_fail=1
        failed_checks="$failed_checks syntax"
        log_err "FAILED: syntax -- re-run: sh scripts/check.sh --only syntax"
    fi
    log ""
fi

# ---- 2. Tests --------------------------------------------------------------
if want tests || [ "$run_tests_only" -eq 1 ]; then
    log "== Test suite (tests/run.sh, lua5.1) =="
    test_args=""
    if [ "$FULL" = "1" ]; then
        test_args="$test_args --full"
    fi
    if [ "$VERBOSE" = "1" ]; then
        test_args="$test_args --verbose"
    fi
    # Map check-level filters onto the test runner.
    test_filter=""
    if [ "$run_tests_only" -eq 1 ]; then
        test_filter="$FILTER"
    elif [ "$FILTER" = "architecture" ]; then
        test_filter="architecture"
    elif [ "$FILTER" = "tests" ]; then
        test_filter=""
    fi
    if [ -n "$test_filter" ]; then
        test_args="$test_args --only $test_filter"
    fi

    export EBB_LOG_DIR="$LOG_DIR"
    export EBB_ANNOTATE="$ANNOTATE"
    set +e
    # shellcheck disable=SC2086
    sh tests/run.sh $test_args
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        log "OK: test suite passed"
    else
        overall_fail=1
        failed_checks="$failed_checks tests"
        log_err "FAILED: tests -- re-run: sh tests/run.sh $test_args"
        log_err "Or one file: sh tests/run.sh --only <name>   (see docs/dev-testing.md)"
    fi
    log ""
fi

# ---- 3. TOC ----------------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want toc; then
    log "== Every .toc file exists on disk =="
    fail=0
    TOC_LIST="$LOG_DIR/toc-files-${RUN_STAMP}.txt"
    awk '{ sub(/\r$/, ""); if ($0 ~ /^[^[:space:]]+\.lua$/) print }' EbonBuilds.toc > "$TOC_LIST"
    while IFS= read -r line; do
        [ -f "$line" ] || {
            log_err "MISSING: $line (listed in EbonBuilds.toc)"
            annotate_line "EbonBuilds.toc" "MISSING TOC entry on disk: $line"
            fail=1
        }
    done < "$TOC_LIST"
    if [ "$fail" -eq 0 ]; then
        log "OK: all TOC files present"
    else
        overall_fail=1
        failed_checks="$failed_checks toc"
        log_err "FAILED: toc -- re-run: sh scripts/check.sh --only toc"
    fi
    log ""
fi

# ---- 4. 3.3.5a API ---------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want api; then
    log "== No post-3.3.5a WoW API calls =="
    api_log="$LOG_DIR/api-${RUN_STAMP}.log"
    set +e
    sh scripts/check-335a-api.sh >"$api_log" 2>&1
    rc=$?
    set -e
    cat "$api_log" | tee -a "$SUMMARY_LOG"
    if [ "$rc" -ne 0 ]; then
        overall_fail=1
        failed_checks="$failed_checks api"
        # Annotate each matching file line from the scanner output.
        if [ "$ANNOTATE" = "1" ]; then
            # shellcheck disable=SC2162
            grep -E '^\s+[^:]+\.lua:' "$api_log" 2>/dev/null | while IFS= read line; do
                line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | tr -d '\r')
                file=$(printf '%s' "$line" | cut -d: -f1)
                lineno=$(printf '%s' "$line" | cut -d: -f2)
                rest=$(printf '%s' "$line" | cut -d: -f3-)
                case "$lineno" in
                    [0-9]*) annotate_line "$file" "$lineno" "post-3.3.5a API: $rest" ;;
                    *) annotate_line "$file" "post-3.3.5a API: $line" ;;
                esac
            done
        fi
        log_err "FAILED: api -- re-run: sh scripts/check.sh --only api"
        log_err "Or: sh scripts/check-335a-api.sh"
    fi
    log ""
fi

# ---- 5. Headers ------------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want headers; then
    log "== File header convention (core/ and modules/) =="
    fail=0
    if command -v find >/dev/null 2>&1; then
        header_list=$(find core modules -name "*.lua")
    else
        header_list=$(printf '%s\n' core/*.lua modules/*/*.lua)
    fi
    for f in $header_list; do
        [ -f "$f" ] || continue
        if ! head -5 "$f" | grep -qE "^-- (EbonBuilds:|Generated)"; then
            log_err "MISSING HEADER: $f (expected '-- EbonBuilds: <path>' or '-- Generated ...' in the first 5 lines)"
            annotate_line "$f" "1" "Missing file header convention"
            fail=1
        fi
    done
    if [ "$fail" -eq 0 ]; then
        log "OK: all file headers present"
    else
        overall_fail=1
        failed_checks="$failed_checks headers"
        log_err "FAILED: headers -- re-run: sh scripts/check.sh --only headers"
    fi
    log ""
fi


# ---- 6. Media TGAs ---------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want media; then
    log "== Required media TGAs present =="
    fail=0
    for f in media/minimap_icon.tga media/vote_icon.tga media/vote_icon_off.tga media/affix_pip.tga; do
        [ -f "$f" ] || {
            log_err "MISSING: $f (run: python3 scripts/generate-media.py)"
            annotate_line "$f" "Missing media TGA (run: python3 scripts/generate-media.py)"
            fail=1
        }
    done
    if [ "$fail" -eq 0 ]; then
        log "OK: all media TGAs present"
    else
        overall_fail=1
        failed_checks="$failed_checks media"
        log_err "FAILED: media -- re-run: sh scripts/check.sh --only media"
        log_err "Or: python3 scripts/generate-media.py"
    fi
    log ""
fi

# ---- 7. Package smoke ------------------------------------------------------
if [ "$run_tests_only" -eq 0 ] && want package; then
    log "== Package smoke (build-dist + verify-package) =="
    pkg_log="$LOG_DIR/package-${RUN_STAMP}.log"
    set +e
    sh scripts/build-dist.sh >"$pkg_log" 2>&1
    rc=$?
    set -e
    cat "$pkg_log" | tee -a "$SUMMARY_LOG"
    if [ "$rc" -ne 0 ]; then
        overall_fail=1
        failed_checks="$failed_checks package"
        log_err "FAILED: package -- re-run: sh scripts/build-dist.sh && sh scripts/verify-package.sh"
        if [ "$ANNOTATE" = "1" ]; then
            grep -E '^::error::' "$pkg_log" 2>/dev/null | while IFS= read -r line; do
                printf '%s\n' "$line"
            done
        fi
    else
        log "OK: dist zip built and verified"
    fi
    log ""
fi

# ---- Summary ---------------------------------------------------------------
if [ "$overall_fail" -eq 0 ]; then
    if [ -n "$FILTER" ]; then
        log "Selected check(s) passed (filter=$FILTER)."
    else
        log "All checks passed."
        if [ "$FULL" != "1" ]; then
            log "(Fast mode: 70k board sim skipped. CI / pre-push: sh scripts/check.sh --full)"
        fi
    fi
    [ "$VERBOSE" = "1" ] && log "VERBOSE: summary log $SUMMARY_LOG"
else
    log_err "One or more checks FAILED:$failed_checks"
    log_err "Summary log: $SUMMARY_LOG"
    log_err "Docs: docs/dev-testing.md"
    if [ "$ANNOTATE" = "1" ]; then
        printf '::error::Checks failed:%s â€” see docs/dev-testing.md\n' "$failed_checks"
    fi
fi
exit $overall_fail
