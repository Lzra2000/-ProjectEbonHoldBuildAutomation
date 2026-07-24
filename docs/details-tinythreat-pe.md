# Details!: Tiny Threat (Project Ebonhold)

<p class="ebb-lead">
Optional <strong>Details!</strong> plugin for threat bars on WoW <strong>3.3.5a</strong> (Interface 30300).
Vendored separately from EbonBuilds — requires the Details! core add-on.
</p>

!!! info "Deutsch"
    Kurzanleitung: [Details!: Tiny Threat (PE) — Deutsch](#deutsch-kurzfassung)

## What it is

**Details!: Tiny Threat** is a Details! plugin that shows group threat on your current target inside a Details! window. EbonBuilds ships a **Project Ebonhold fork** (`v1.07-pe1`) with defensive guards around threat and group APIs that can be flaky on custom 3.3.5a cores.

EbonBuilds does **not** require Tiny Threat. It is optional for players who already use Details! and want a lightweight threat meter.

## Requirements

| Add-on | Folder | Shipped with EbonBuilds? |
| --- | --- | --- |
| **Details!** (core) | `Interface/AddOns/Details` | No — install separately |
| **Details_TinyThreat** (plugin) | `Interface/AddOns/Details_TinyThreat` | Optional — `Details_TinyThreat.zip` on [releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) when vendored |

Both must sit **alongside** `EbonBuilds` under `World of Warcraft/Interface/AddOns/` (or your PE client’s equivalent path).

## Install from a GitHub release

Prefer **`Details.zip`** (full suite including TinyThreat). When only `Details_TinyThreat.zip` is attached to a release:

1. Download **`Details_TinyThreat.zip`** from the [latest release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) (alongside `EbonBuilds.zip`).
2. Extract the archive. The folder inside must be named **`Details_TinyThreat`** (matching `Details_TinyThreat.toc`).
3. Copy it to `Interface/AddOns/`.
4. Ensure **Details!** is already installed in `Interface/AddOns/Details`.
5. `/reload` or restart the client.
6. In Details!, open the orange cogwheel → **Plugins** → enable **Tiny Threat** on a window.

## Install from a PE client bundle zip

Some Project Ebonhold client bundles ship a zip named **`Details_TinyThreat (2).zip`**. That archive often contains **Details! core plus several plugins**, not Tiny Threat alone.

1. Extract the zip to a temporary folder.
2. Copy **only** the **`Details_TinyThreat`** subfolder into `Interface/AddOns/`.
3. **Rename** the folder if Windows left it as `Details_TinyThreat (2)` or similar — the folder name **must** be exactly **`Details_TinyThreat`** or the client will not load the add-on.
4. If you do not already have Details!, also copy the **`Details`** folder from the same bundle into `Interface/AddOns/Details`.
5. Do **not** duplicate sibling plugins (Chart Viewer, TimeLine, etc.) unless you intend to use them — they are unrelated to Tiny Threat.
6. `/reload`, then enable the plugin from Details! as above.

## Verify in-game

- Add-ons list shows **Details!: Tiny Threat (Project Ebonhold)** without a “Dependency missing” error for Details.
- Slash commands: `/tinythreat` or `/tt`.
- In combat, with a hostile target, threat bars appear on the Details! window where you enabled the plugin.

## Fork notes

Source lives under `vendor/Details_TinyThreat/` on branch [`feat/details-tinythreat-pe`](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/tree/feat/details-tinythreat-pe). See [`vendor/Details_TinyThreat/CREDITS.md`](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/blob/feat/details-tinythreat-pe/vendor/Details_TinyThreat/CREDITS.md) for upstream credit and PE-specific changes (`DetailsTinyThreatProjectEbonhold.lua`).

Build packaging: `scripts/build-dist.sh` emits `dist/Details.zip` (full suite) plus legacy `dist/Details_TinyThreat.zip` when the vendor suite is present.

---

## Deutsch (Kurzfassung)

**Details!: Tiny Threat (PE)** ist ein optionales **Details!-Plugin** für Bedrohungsanzeige auf **WoW 3.3.5a**. Es läuft **nur mit installiertem Details!-Core** (`Interface/AddOns/Details`); EbonBuilds liefert Details! nicht mit.

**Installation**

1. **`Details_TinyThreat.zip`** aus dem [Release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) entpacken **oder** aus einem Client-Bundle nur den Unterordner **`Details_TinyThreat`** übernehmen.
2. Ordner nach `Interface/AddOns/` legen — Name exakt **`Details_TinyThreat`** (nicht `Details_TinyThreat (2)`).
3. Details! muss bereits in `Interface/AddOns/Details` liegen.
4. `/reload`, dann im Details!-Zahnrad unter **Plugins** aktivieren.

Vollständige Anleitung (Englisch): diese Seite — [Details!: Tiny Threat (Project Ebonhold)](details-tinythreat-pe.md).
