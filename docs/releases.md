# Releases

EbonBuilds ships as versioned zip downloads on GitHub. Each release page includes
install instructions, release notes pulled from [CHANGELOG.md](../CHANGELOG.md),
and an **`EbonBuilds.zip`** asset you can install directly.

[Download the latest release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest){ .md-button .md-button--primary }
[All releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases){ .md-button }

## Install from a release zip

1. Open the [releases page](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) and download **`EbonBuilds.zip`** from the **Assets** section (not "Source code").
2. Extract the archive. You should get a single folder named `EbonBuilds`.
3. Copy `EbonBuilds` into your WoW add-ons directory:

    ```
    World of Warcraft/Interface/AddOns/EbonBuilds/
    ```

4. Restart the client or run `/reload`.

Requires **ProjectEbonhold** or **ProjectEbonhold Enhanced**. Some features additionally use **Details!** if installed. Step-by-step first-run guidance is in [Getting Started](getting-started.md).

## How releases work

| What | Where |
|------|-------|
| Latest downloadable build | [GitHub Releases — latest](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) |
| Full version history | [Changelog](changelog.md) (mirrors `CHANGELOG.md`) |
| In-game "What's new" | Top entry from `CHANGELOG.md`, regenerated at release time |
| Version in the client | `## Version:` line in `EbonBuilds.toc` |

Pushing a `v*` tag (for example `v3.84`) triggers the [Release workflow](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/release.yml): full checks, `dist/EbonBuilds.zip` build, and publication to GitHub Releases with notes extracted from the matching `### <version>` block in `CHANGELOG.md`.

## Recent releases

| Version | Date | Summary |
|---------|------|---------|
| [3.84](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.84) | 2026-07-24 | Bag dots, freeze persistence, server loadouts, combat DPS in the Logbook |
| [3.83](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.83) | 2026-07-24 | Autopilot / ProjectEbonhold API alignment and community bug-fix wave |
| [3.82](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.82) | 2026-07-21 | Public Builds: full character view, search, and sort |

Older entries are listed in the [full changelog](changelog.md).

## Updating

Download the new zip, extract it, and replace your existing `Interface/AddOns/EbonBuilds` folder. Your builds and settings live in SavedVariables and are not removed by updating the add-on files.

If the in-game updater reports a newer version in use around you, compare your installed `EbonBuilds.toc` version with the [latest release tag](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
