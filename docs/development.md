# Development

<p class="ebb-lead">
Contributor setup, the script toolbox, and where to find the full contributing guide.
</p>

Full contributor guide: [CONTRIBUTING.md](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/blob/main/CONTRIBUTING.md). This page is the short map.

## Setup

```
sh scripts/dev-setup.sh      # lua5.1, zip (Debian/Ubuntu)
sh scripts/install-hooks.sh  # optional pre-commit hook
sh scripts/check.sh          # fast local loop (skips 70k board sim)
sh scripts/check.sh --full   # what CI runs
```

On Windows: `powershell -File scripts/check.ps1` (or `bash scripts/check.sh` from Git Bash). No build step -- the repo root already is the addon folder structure.

**Filtering & debugging:** see [Local checks & CI debugging](dev-testing.md) for `--only`, `VERBOSE=1`, Actions annotations, and common failure classes (architecture `RegisterEvent`, `and nil or` lint, 3.3.5a API scan).

## The script toolbox

| Script | What it does |
|---|---|
| `check.sh` / `check.ps1` | Syntax + test suite + TOC + 3.3.5a API + headers (`--full` = CI; `--only` for one group) |
| `build-dist.sh` | Packages `dist/EbonBuilds.zip` (+ optional `dist/Auctionator.zip`; see `vendor/Auctionator/CREDITS.md`) |
| `verify-package.sh` | Post-build smoke: TOC paths inside the zip, locale UTF-8 BOM rejection, required media, no dev leaks |
| `check-load-order.sh` | Flags file-scope references to modules the `.toc` hasn't loaded yet |
| `find-orphans.sh` | Files the TOC never loads (hard fail) and exports with no visible caller (review list) |
| `i18n-report.sh` | Per-language translation coverage, missing and orphaned keys |
| `new-locale.sh <code>` | Scaffolds a new locale file from every real call site |
| `triage-error.sh <file\|->` | Pasted error dump -> source context + `git log -L` per mentioned line |
| `release.sh` / `ship.sh` | Version bump, checks, tag / plus push; the pushed tag triggers the Release workflow (maintainers) |

The test suite includes a sync fuzzer (`tests/test_sync_fuzz.lua`): thousands of deterministic hostile payloads against the inbound message handlers every CI run. The 70k board simulation is opt-in locally (`--full`) and always on in CI.

## Conventions worth knowing before a PR

File headers name the file and its single responsibility. Everything hangs off `EbonBuilds.<Module>`; test-only hooks are `_`-prefixed. User-interaction handlers get wrapped in `EbonBuilds.ErrorLog.Protect` so failures land in the in-game Error log instead of vanishing. User-facing changes get a changelog entry in `CHANGELOG.md` -- plain and specific, no marketing language.

## Design notes

- [Automation server redesign](automation-server-redesign.md) — approved target architecture (server as decision authority, client as executor). Design only until the tracked work packages land.
