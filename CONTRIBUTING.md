# Contributing to EbonBuilds

## Setup

```
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git
cd ProjectEbonHoldBuildAutomation
sh scripts/dev-setup.sh      # installs lua5.1, texlive-binaries (texlua), zip
sh scripts/install-hooks.sh  # optional: runs scripts/check.sh before every commit
```

`dev-setup.sh` uses `apt-get`, so it targets Debian/Ubuntu. On Windows, run everything through WSL; on other distros, install `lua5.1`, `texlive-binaries`, and `zip` with your package manager.

That's it. No build step for day-to-day development -- the repo root is already the addon folder structure `Interface/AddOns/` expects, so you can symlink or copy it straight in and reload.

## Before opening a PR

```
sh scripts/check.sh
```

Runs the same checks CI runs: Lua 5.1 syntax check, the full test suite (`tests/run.sh`), a check that every file listed in `EbonBuilds.toc` actually exists, the 3.3.5a API blocklist, and the file-header convention check. If `scripts/install-hooks.sh` is set up this runs automatically on commit (skip once with `git commit --no-verify`).

The PR template has a short checklist -- CHANGELOG.md entry for user-facing changes, translation keys for new UI strings, that kind of thing.

Further tooling, all under `scripts/`:

- `sh scripts/check-load-order.sh` -- verifies no file references an `EbonBuilds.<Module>` at file scope before the `.toc` has loaded the file defining it. Function bodies are exempt (they run post-load). This exact trap has bitten before; run it after adding cross-module references at the top of a file.
- `sh scripts/find-orphans.sh` -- lists Lua files the `.toc` never loads (hard failure: they silently don't exist in-game) and exported functions with no visible caller (listed for review only -- dynamic dispatch is invisible to it, and `_`-prefixed test hooks are exempt).
- `sh scripts/i18n-report.sh` -- per-locale translation coverage: missing keys and orphaned entries. The test suite only fails on missing; this shows the whole picture.
- `sh scripts/triage-error.sh <file|-|>` -- paste an in-game error dump, get the source context and the last commits touching each mentioned line range.
- `GITHUB_TOKEN=... sh scripts/ship.sh <version>` -- release.sh + push + publish-github-release.sh as one command (maintainers only).

The test suite also includes `tests/test_sync_fuzz.lua`: 4000 deterministic hostile payloads against Sync's inbound message handlers. If it fails, it prints the seed, iteration, and escaped payload -- turn that into a named regression test alongside the fix.

## Project conventions

- **File header.** Every module starts with:
  ```lua
  -- EbonBuilds: modules/path/File.lua
  -- Responsibility: one line, what this file owns.
  ```
- **Namespace, not globals.** Everything hangs off `EbonBuilds.<Module>`. Internal helpers are `local function` at file scope, not global.
- **Test hooks.** If something needs to be tested but isn't naturally reachable (a closure inside a button's `OnClick`, module-local state), expose it as `EbonBuilds.Module._DoTheThing = DoTheThing` -- see `EbonBuilds.Session`'s test helpers or `EbonBuilds.BuildTabs._TriggerExportAI` for the pattern. Prefix with `_` so it reads as "test/integration only," not part of the real API.
- **Errors that should be visible.** Wrap a handler in `EbonBuilds.ErrorLog.Protect("Source.Name", fn)` if it's reachable from user interaction and isn't trivially safe -- an unprotected error goes straight to WoW's own (usually disabled) Lua error display and never reaches the Error log (Settings -- Windows & tools). Most of the codebase predates this and isn't wrapped; wrapping more of it as you touch nearby code is welcome.
- **Changelog.** User-facing changes get a `### <version>` entry at the top of `CHANGELOG.md`. Look at recent entries for the tone: specific about what changed and why, no marketing language. FAQ-worthy explanations go in `docs/faq.md` (rendered on the docs site and in-game).
- **Releases.** Version bumps go through `sh scripts/release.sh <version>` (bumps `EbonBuilds.toc` + the `docs/faq.md` header, requires a `CHANGELOG.md` entry, runs `scripts/check.sh`, commits, tags). Pushing the tag triggers `.github/workflows/release.yml`, which publishes the GitHub Release and uploads the zip as a release asset; `scripts/publish-github-release.sh` is the manual fallback. Not something a regular PR needs to touch.

## Adding a translation

UI strings go through `EbonBuilds.L["English string"]`, a lookup table that falls back to English for anything untranslated -- see `modules/i18n/Locale.lua`. Currently only `modules/ui/BuildTabs.lua` and `modules/ui/MainWindow.lua` are wired up to it.

**New language:**
```
sh scripts/new-locale.sh itIT
```
Generates `modules/i18n/locales/itIT.lua` pre-filled with every known key (English placeholder as the value). Translate the values, then:
1. Add the file to `EbonBuilds.toc`, right after the other locale files.
2. Add the locale code to `SUPPORTED_LOCALES` in `modules/i18n/Locale.lua` (and `ALIASES` if a short form like `it` should work with `/ebb locale it`).

Game-specific terms (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) stay in English across every language -- check the existing locale files or `README.*.md` for how a given language already handles that.

**Extending an existing language, or adding `EbonBuilds.L[...]` to a file that isn't wired up yet:** `scripts/check.sh` (via the test suite) will flag any locale file missing a translation for a key that's actually used in `BuildTabs.lua`/`MainWindow.lua` -- run it after adding a new string to see what needs filling in across all six languages at once, instead of finding out one language at a time.

## Reporting bugs

See the README's "Reporting bugs" section -- short version: attach the Error log output (Settings -- gear icon -- Windows & tools), and the Click Trace log if a click seemed to do nothing.
