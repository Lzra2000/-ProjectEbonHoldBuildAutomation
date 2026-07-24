# Details_ProjectEbonhold (Project Ebonhold fine-tune layer)

Lean companion add-on for **Details!** on **WoW 3.3.5a (Interface 30300)** /
**Project Ebonhold**. It does **not** vendor the ~22 MB Details! core.

## Why this exists

On PE, Echo perks and many item/enchant procs show up in Details! as opaque
secondary spell IDs. Players cannot tell:

1. which hits came from an **Echo**, or
2. **which cast/aura triggered** a proc.

This layer labels Echo damage, attributes procs to their likely source cast,
and applies a small set of PE-safe Details defaults.

## Upstream

Requires an installed **Details!** core (`Interface/AddOns/Details`) — the same
WotLK / Interface 30300 pack already used on the PE client. EbonBuilds does not
ship Details! itself.

Pattern modelled after `vendor/Details_TinyThreat/` (PE shim + CREDITS, optional
release zip).

## Files

| File | Role |
|------|------|
| `DetailsProjectEbonholdCore.lua` | Pure helpers (testable offline) |
| `DetailsProjectEbonhold.lua` | Boot, PE defaults, `/detailspe` |
| `DetailsProjectEbonholdEcho.lua` | Echo spell labels + Echo damage API |
| `DetailsProjectEbonholdProcs.lua` | CLEU proc attribution + Custom Display |
| `Details_ProjectEbonhold.toc` | Load order / deps |
| `CREDITS.md` | This document |

## Behaviour

### Echo DPS (labels + API)

- Marks PE custom-band / granted Echo spells in the Details spell breakdown as
  `Name (Echo)`.
- Exposes `DetailsProjectEbonhold.Echo.GetPlayerEchoDamage()` for EbonBuilds
  **EchoPerformance** (optional spell-attributed samples).

### Proc attribution

- Watches 3.3.5a `COMBAT_LOG_EVENT_UNFILTERED` for the player's casts/auras.
- Secondary damage within ~1.5s that was **not** itself cast is treated as a
  proc and labeled `ProcName [SourceCast]` (plain brackets — Details
  `GetOnlyName` mangles any `-` / `<-` in actor names into `(<`).
- Installs Details Custom Display **PE Proc Sources** (Attributes → Custom):
  scrollable list, spell icons (client `GetSpellInfo` then PE `PerkDatabase` /
  `GetPerkData` from the server sync), real `%` column, no empty `()` when
  source is unknown.
- **Left-click** a PE Proc Sources row opens a breakdown panel (amount, hits,
  average, other sources of that proc, other procs from the same cast). Custom
  displays (Details attribute 5) do not open the normal DPS player-details
  window — this companion hooks `row_singleclick_overwrite[5]` for that index.

### Icons

- `PE.GetSpellIcon` / Echo labels prefer client spell DB, then ProjectEbonhold
  perk records (server API), then EbonBuilds `ProjectAPI.GetPerkData`.
- Results cached in `DetailsProjectEbonholdDB.iconCache`.

### PE defaults

- Ensures `override_spellids` stays enabled (merge related multi-hit skills).
- Enables right-text percent so Details does not show empty `()` brackets.
- Applied once per account (`DetailsProjectEbonholdDB.defaultsApplied`); does
  not reset skins/windows.

## Slash

- `/detailspe` — status
- `/detailspe echoes` — toggle Echo labels
- `/detailspe procs` — toggle proc tracking

## Install

1. Install **Details!** into `Interface/AddOns/Details` if missing.
2. Extract `dist/Details_ProjectEbonhold.zip` so the folder is exactly
   `Interface/AddOns/Details_ProjectEbonhold`.
3. `/reload`, confirm add-on list shows **Details!: Project Ebonhold**.
4. In Details: open a window → attribute menu → **Custom** → **PE Proc Sources**
   (optional). Player spell breakdowns show `(Echo)` / `[Source]` labels
   automatically when tracking is on. Mousewheel scrolls long PE Proc Sources
   lists; hover a bar for attribution tooltip; **click** a bar for the
   breakdown summary.

## Residual risks

- Proc → source linking is **heuristic** (time window after cast/aura), not
  server-authoritative. Multi-proc bursts can credit the most recent cast.
- Echo damage whose spell id is outside the PE custom band and not in the
  granted-perk list will not get an `(Echo)` suffix until it appears as a
  granted perk or PE-band combat hit.
- Custom Display scripts run inside Details' sandbox; if Details updates break
  `InstallCustomObject`, labels still work via spellcache.

## 1.0.3-pe1

Left-click PE Proc Sources rows open an attribution summary (damage, hits, average, sibling sources/procs). Custom Display script_version 4.
