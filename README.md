<p align="center">
  <img src="assets/banner.svg" alt="EbonBuilds — Echo automation for ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="CI checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="License"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <b>English</b> | <a href="docs/readme/README.de.md">Deutsch</a> | <a href="docs/readme/README.ru.md">Русский</a> | <a href="docs/readme/README.pt-BR.md">Português (Brasil)</a> | <a href="docs/readme/README.es.md">Español</a> | <a href="docs/readme/README.fr.md">Français</a> | <a href="docs/readme/README.pl.md">Polski</a>
</p>

**EbonBuilds** is a World of Warcraft **3.3.5a** client addon for players on **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)** private servers. You define a build — echo weights, policies, and autopilot intent — and EbonBuilds scores every echo choice screen (Banish / Reroll / Freeze / Select) on your behalf, records what happened, and turns real run data into reviewable tuning suggestions.

Built for ProjectEbonhold raiders and echo grinders who want consistent automation without giving up control: every action is logged, recommendations require your approval, and Manual Training Mode lets the addon learn from deliberate picks.

## Quick install

1. Download **`EbonBuilds.zip`** from the [latest release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Extract the archive. The folder must be named **`EbonBuilds`** (matching `EbonBuilds.toc`).
3. Copy it to `World of Warcraft/Interface/AddOns/`.
4. Restart the game or run `/reload`.

**Server requirement:** ProjectEbonhold ships its own server addon. Install **ProjectEbonhold** or **ProjectEbonhold Enhanced** on the client as provided by your server — EbonBuilds depends on it for echo boards, affix data, and several integration features. Without it, EbonBuilds will not function.

**Optional:** **[Details!](https://www.curseforge.com/wow/addons/details)** enables DPS-based weight suggestions and richer stats. Combat DPS logging in the Logbook (v3.84+) works without Details! when enabled under Settings. **[Auctionator](vendor/Auctionator/)** (vendored 2.6.3 for 3.3.5a) adds affix shopping, AH search shortcuts, and buyout price hints when installed alongside EbonBuilds.

Open the addon with **`/ebb`** or **`/ebonbuilds`**.

## Features

| Area | What you get |
| --- | --- |
| **Autopilot** | Intent presets (Save charges / Balanced / Chase upgrades), per-echo scoring, run-persistent freeze tracking, and a decision-first **Logbook** with reasoning and charge usage. |
| **Builds** | Per-echo weights (including per-quality ranks), locked/banned slots, character snapshots (talents, glyphs, gear), Tuning Advisor, Manual Training Mode, EchoWishlist (`EWL1`) export, and plain-text **Export (AI)** dumps. |
| **Public Builds** | Browse community builds, inspect priorities and snapshots, vote, import, and (when the server supports it) save or apply **server loadouts**. |
| **Affixes** | Affix reference panel, bag affix dots (default bags, Bagnon, Combuctor), gear modeling in the Character tab, and optional Auctionator AH search / price hints. |
| **DPS & stats** | Optional combat DPS samples attached to runs and shown in the Logbook; Details!-backed DPS tracking and appearance-rate sync when installed and consented. Stats workspace with Summary, Actions, Echoes, and evidence-backed Recommendations. |
| **Locales** | Build editor UI in German, Spanish, French, Polish, Brazilian Portuguese, and Russian — auto-detected from the client or overridden via Settings. |

Other notable tools: **Tome Atlas** (community drop locations), **Missing Echoes** (weighted echoes you have not learned yet), whole-run **budget pacing**, and optional auto-sell while vendoring.

<p align="center">
  <img src="assets/how-it-works.svg" alt="Define a build, Autopilot acts on choice screens, data is tracked, the Tuning Advisor suggests adjustments, and the loop repeats" width="100%">
</p>

## Screenshots

| Build editor — priorities | Build overview & Autopilot |
| --- | --- |
| <img src="assets/screenshots/editor-priorities.png" alt="Echo priorities editor" width="100%"> | <img src="assets/screenshots/build-overview.png" alt="Build overview" width="100%"> |

| Logbook | Stats — recommendations |
| --- | --- |
| <img src="assets/screenshots/logbook.png" alt="Decision logbook" width="100%"> | <img src="assets/screenshots/stats-recommendations.png" alt="Evidence-backed recommendations" width="100%"> |

More screenshots and a full UI tour live in [`assets/screenshots/`](assets/screenshots/) and on the [documentation site](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Documentation & support

| Resource | Link |
| --- | --- |
| Documentation (Getting Started, Settings, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Releases & changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](CHANGELOG.md) |
| Bug reports & feature requests | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Security | [`SECURITY.md`](SECURITY.md) |

When reporting bugs, attach output from **Settings → Windows & tools → Error log** or **Debug log** — it is the fastest path to a fix.

## Development

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, conventions, and the pre-PR checklist.

For local checks, CI parity, and debugging failing Actions runs, see **[`docs/dev-testing.md`](docs/dev-testing.md)**. Quick entry points:

```sh
sh scripts/dev-setup.sh    # one-time toolchain (Debian/Ubuntu; use WSL on Windows)
sh scripts/check.sh        # fast local loop (syntax, tests, .toc, 3.3.5a API lint)
sh scripts/check.sh --full # full suite CI runs before merge
sh scripts/build-dist.sh   # produces dist/EbonBuilds.zip
```

The repository root is the addon folder (`EbonBuilds.toc`, `core/`, `modules/` at the top level). Release tags trigger [`.github/workflows/release.yml`](.github/workflows/release.yml), which publishes `EbonBuilds.zip` on GitHub Releases.

`media/minimap_icon.tga`, `media/vote_icon.tga`, `media/vote_icon_off.tga`, and `media/affix_pip.tga` have real sources: `python3 scripts/generate-media.py` (requires [Pillow](https://pillow.readthedocs.io/)) regenerates them from code — the minimap icon from the same ring geometry as `docs/img/logo.svg`, the vote chevrons and affix pip from simple vector shapes — so no texture is a hand-edited binary with no way back to its design.

## License

See [`LICENSE`](LICENSE). Personal and private-server community use is permitted for unmodified official releases. Redistributing modified versions under the EbonBuilds name, or commercial use, requires prior permission from the copyright holder.
