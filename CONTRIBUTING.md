# Contributing to EbonBuilds

Player support (FAQ, bug reports, Discussions): [`SUPPORT.md`](SUPPORT.md).

## Setup

```bash
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git
cd ProjectEbonHoldBuildAutomation
sh scripts/dev-setup.sh      # installs lua5.1, zip (Debian/Ubuntu apt)
sh scripts/install-hooks.sh  # optional: runs scripts/check.sh before every commit
```

Windows: use WSL for `dev-setup.sh`, then run checks with `bash scripts/check.sh` or `powershell -File scripts/check.ps1`.

`dev-setup.sh` uses `apt-get` (Debian/Ubuntu). On other distros, install `lua5.1`, `texlive-binaries`, and `zip` yourself.

No build step for day-to-day work — the repo root is already the addon folder `Interface/AddOns/` expects. Symlink or copy it in and `/reload`.

## Checks (`scripts/check.sh`)

```bash
sh scripts/check.sh              # fast local loop (skips 70k board sim)
sh scripts/check.sh --full       # matches CI — run before opening a PR
sh scripts/check.sh --only architecture
```

`--full` is what CI runs: Lua 5.1 syntax, full test suite (`tests/run.sh`), `.toc` file existence, 3.3.5a API blocklist, and file-header convention. Day-to-day, omit `--full` for speed. Filter with `--only` / `FILTER=`; failure notes live in [`docs/dev-testing.md`](docs/dev-testing.md).

With `install-hooks.sh`, checks run on every commit (`git commit --no-verify` to skip once).

Further tooling under `scripts/`:

- `check-load-order.sh` — cross-module references at file scope must load after their defining module in the `.toc`
- `find-orphans.sh` — Lua files not in the `.toc`, or exports with no visible caller
- `i18n-report.sh` — per-locale translation coverage
- `triage-error.sh <file|-` — paste an in-game error dump for source context and recent commits
- `ship.sh` — release + push + publish (maintainers only)

Sync inbound messages are fuzzed in `tests/test_sync_fuzz.lua`. If it fails, it prints seed, iteration, and payload — turn that into a named regression test with the fix.

## Pull requests

- **Branch from `main`**, keep PRs focused — one logical change when you can.
- **Explain why**, not only what changed. Link issues (`Fixes #123`) when applicable.
- **Run `sh scripts/check.sh --full`** before opening; the PR template checklist covers the rest.
- **User-facing changes:** `CHANGELOG.md` entry at the top (`### <version>`), plus `docs/faq.md` when players need an explanation. Match existing tone — specific, no marketing language.
- **New UI strings** in `BuildTabs.lua` / `MainWindow.lua`: add keys to all six `modules/i18n/locales/*.lua` files (or accept English fallback and let `check.sh` flag gaps).
- **Tests:** add or update coverage when the change is testable; not every UI tweak needs one.
- **Draft PRs** welcome for early feedback on larger work.

The [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) has the full checklist.

## Project conventions

- **File header.** Every module starts with:
  ```lua
  -- EbonBuilds: modules/path/File.lua
  -- Responsibility: one line, what this file owns.
  ```
- **Namespace, not globals.** Everything hangs off `EbonBuilds.<Module>`. Internal helpers are `local function` at file scope.
- **Test hooks.** Expose hard-to-reach internals as `EbonBuilds.Module._DoTheThing` with a `_` prefix — see `EbonBuilds.Session` or `EbonBuilds.BuildTabs._TriggerExportAI`.
- **Error visibility.** Wrap user-facing handlers in `EbonBuilds.ErrorLog.Protect("Source.Name", fn)` when they are not trivially safe.
- **Releases.** Version bumps go through `sh scripts/release.sh <version>` (maintainers). Regular PRs do not need to touch version or tags.

## Adding a translation

UI strings use `EbonBuilds.L["English string"]` (`modules/i18n/Locale.lua`). Currently wired in `modules/ui/BuildTabs.lua` and `modules/ui/MainWindow.lua`.

**New language:**

```bash
sh scripts/new-locale.sh itIT
```

Then: add the file to `EbonBuilds.toc`, add the code to `SUPPORTED_LOCALES` in `Locale.lua` (and `ALIASES` if needed).

Game terms (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) stay in English in every locale.

## Code of conduct

Be direct and constructive. Harassment and bad-faith behavior are not welcome — see [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## License note

Contribution terms are under discussion ([#18](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/18)). By opening a PR you agree your contribution may be used in the project; final licensing will be clarified when #18 closes.
