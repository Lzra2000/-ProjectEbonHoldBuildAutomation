# Local checks & CI debugging

<p class="ebb-lead">
Run the same checks CI runs, filter a single failure, and read GitHub Actions output.
Companion to <a href="development.md">Development</a> and
<a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/blob/main/CONTRIBUTING.md">CONTRIBUTING.md</a>.
</p>

## Quick start

```sh
sh scripts/dev-setup.sh          # once (Debian/Ubuntu apt: lua5.1 + zip)
sh scripts/check.sh              # fast local loop (skips the 70k board sim)
sh scripts/check.sh --full       # what CI runs (includes the slow sim)
```

**Windows (this repo is often developed on Windows):**

```powershell
# From PowerShell — finds Git Bash and forwards args:
.\scripts\check.ps1
.\scripts\check.ps1 --full
.\scripts\check.ps1 --only architecture

# Or in Git Bash:
bash scripts/check.sh --only tests
```

`scripts/dev-setup.sh` is apt-only. On Windows use WSL and run it there, or
install Lua 5.1 so `lua5.1` / `luac5.1` are on `PATH` (Git Bash will see the
same PATH after `check.ps1` prepends `.cache/bin` if you drop binaries there).

## What CI runs

Workflow: [`.github/workflows/lua-syntax.yml`](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/blob/main/.github/workflows/lua-syntax.yml) (job name **Checks**).

1. `sh scripts/dev-setup.sh`
2. `sh scripts/check.sh --full --verbose` with `EBB_ANNOTATE=1`
3. `sh scripts/build-dist.sh`
4. On failure: uploads `.cache/check-logs/` as a workflow artifact

Lua test failures also emit GitHub Actions `::error file=...,line=...::`
annotations when possible, so they show up on the PR Files changed view.

## Filter a single check or test

| Goal | Command |
|---|---|
| Syntax only | `sh scripts/check.sh --only syntax` |
| All unit/integration tests (fast) | `sh scripts/check.sh --only tests` |
| Architecture scanner | `sh scripts/check.sh --only architecture` |
| One test file by name | `sh tests/run.sh --only freeze_recovery` |
| 3.3.5a API blocklist | `sh scripts/check.sh --only api` |
| TOC paths exist | `sh scripts/check.sh --only toc` |
| File headers | `sh scripts/check.sh --only headers` |
| Full suite including 70k sim | `sh scripts/check.sh --full` |
| Verbose runner context | `VERBOSE=1 sh scripts/check.sh --only tests` |

`FILTER=architecture sh scripts/check.sh` is equivalent to `--only architecture`.

`tests/run.sh` auto-discovers `tests/test_*.lua`. New test files from other
branches land in the suite without editing the runner (slow suites are named
explicitly and stay behind `--full`).

## Interpreting failures

### Architecture — `RegisterEvent` outside WoWEvents

`tests/test_architecture.lua` requires every TOC Lua file to use the private
namespace and forbids `frame:RegisterEvent(...)` outside `core/WoWEvents.lua`.

- **Symptom:** `ARCHITECTURE FAIL: modules/....lua registers a Blizzard event outside WoWEvents`
- **Fix:** register through `EbonBuilds.WoWEvents` (central frame + stable listener dispatch).
- **Re-run:** `sh scripts/check.sh --only architecture`

### `and nil or` toggle lint

Same architecture test bans `x and nil or y` in shipped code. In Lua the
`and nil` branch is never taken, so the expression always yields `y` — the
bug class behind issue #39 (toggles that only turn on).

- **Symptom:** `... contains N \`and nil or\` expression(s)`
- **Fix:** write an explicit `if/else` toggle. FAQ / documented historical
  strings may be allowlisted with an exact count in the test.
- **Re-run:** `sh scripts/check.sh --only architecture`

### Post-3.3.5a API scan

`scripts/check-335a-api.sh` greps for APIs that do not exist on build 12340
(e.g. `SetShown`, `C_Timer`, `IsInGroup`). The test stub may no-op unknown
methods, so this scanner catches what unit tests miss.

- **Symptom:** `NOT AVAILABLE IN 3.3.5a: ...` plus file:line hits
- **Fix:** use the 3.3.5a alternative printed next to each pattern
- **Re-run:** `sh scripts/check.sh --only api`

### Slow board simulation

`tests/test_freeze_first_simulation.lua` walks ~70k boards. Local `check.sh`
skips it unless `--full` / `EBB_FULL=1`. CI always passes `--full`.

- **Re-run only the sim:** `sh tests/run.sh --only freeze_first_simulation`
  (explicit filter runs it even without `--full`)

### Sync fuzzer

`tests/test_sync_fuzz.lua` prints seed, iteration, and escaped payload on
failure — turn that into a named regression next to the fix.

## Logs & debug mode

- Per-run logs: `.cache/check-logs/` (gitignored)
- `VERBOSE=1` / `--verbose`: tool paths, timings, skip reasons, summary paths; also sets
  `LUA_INIT=@tests/verbose_init.lua` so each test process traces `loadfile()` calls
- CI artifact name: `check-logs-<run_id>` (download from the failed Actions run)

Windows tip: drop Lua 5.1 binaries into `.cache/bin/` (`lua5.1.exe`, `luac5.1.exe`);
`scripts/check.ps1` prepends that directory automatically.

## Related scripts (not in the default check)

| Script | When to run |
|---|---|
| `sh scripts/check-load-order.sh` | After adding file-scope cross-module refs |
| `sh scripts/find-orphans.sh` | TOC orphans / unused exports |
| `sh scripts/i18n-report.sh` | Full locale coverage picture |
| `sh scripts/triage-error.sh` | Pasted in-game error dump → source context |
