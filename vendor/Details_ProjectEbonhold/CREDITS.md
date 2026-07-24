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
- **Left-click** a PE Proc Sources row opens the **real** Details!
  `DetailsPlayerDetailsWindow` (Player Details! Breakdown): Sources fill the
  spell-bar panel, Other procs fill the Targets panel, right-side detail blocks
  show damage/hits/average. Custom displays (attribute 5) do not call
  `AbreJanelaInfo` — this companion hooks `row_singleclick_overwrite[5]` and
  populates the native frame instead (no custom scroll-frame chrome).

### Icons

- `PE.GetSpellIcon` / Echo labels prefer client spell DB, then ProjectEbonhold
  perk records (server API), then EbonBuilds `ProjectAPI.GetPerkData`.
- Results cached in `DetailsProjectEbonholdDB.iconCache`.

### PE defaults

- Ensures `override_spellids` stays enabled (merge related multi-hit skills).
- Enables right-text percent so Details does not show empty `()` brackets.
- Sets `overall_clear_newboss = false` so **Overall Data** is not wiped on every
  new raid boss (stock Details default clears it; that felt like data not saving).
  Players who want auto-wipe can re-enable Details options → Overall →
  **Clear On New Raid Boss** / deDE **Bei neuem Schlachtzugsboss löschen**.
- Applied once per account (`defaultsApplied`, `defaultsOverallClearNewBoss`);
  does not reset skins/windows. New keys can land in later PE versions without
  re-stomping older defaults.

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

## 1.0.11-pe1

PE Proc Sources Breakdown Targets chrome: own a single "Procs from source:"
header (re-anchor stock `info.targets`, sweep stray SummaryWindowWidgets labels),
hook stock "No Targets" Show so Fade/skin cannot overlay sibling proc bars.
Custom Display script_version 11.

## 1.0.10-pe1

PE Proc Sources Breakdown interaction: hide the Player Details status strip so
it no longer overlaps Targets / steals clicks; disable empty-Targets
`StartMoving` (mouse hang); lift classic-skin Targets above the footer; wire
sibling proc/source row clicks to `OpenBreakdown`; keep tab frames mouse-inert
and suppress stock "No Targets" art under proc lists. Custom Display
script_version 10.

## 1.0.9-pe1

PE Proc Sources Breakdown layout polish: denser right-side detail blocks
(native field order, source-share bar, sibling source/proc slots), include the
focused proc in the Targets panel, dock Breakdown beside the meter with
left-flip when it would clip the screen. Custom Display script_version 9.

## 1.0.8-pe1

PE Proc Sources first-click opens native **Player Details! Breakdown** without
needing a prior DPS-bar click (prewarm `CriaJanelaInfo`, no chat hint). Layout:
dock Breakdown beside the Details instance, hide unused right-side void panels,
fill a third detail block when sibling sources/procs exist. Custom Display
script_version 8.

## 1.0.7-pe1

Soft default: `overall_clear_newboss = false` so Details **Overall Data** is kept
across raid bosses (stock Details wipes it on each new boss). One-shot via
`DetailsProjectEbonholdDB.defaultsOverallClearNewBoss` so existing PE installs
pick it up once. Re-enable wipe in Details options if desired.

## 1.0.6-pe1

**PE Proc Sources** now works on Details segment **Overall Data**: attributions are
stored per combat (`pe_proc_attribution`), merged into overall when Details adds
the segment, and the Custom Display passes the selected `combat` into
`GetProcRows` / click breakdown. Survives `/reload` with Details' combat
SavedVariables. Custom Display script_version 7.

## 1.0.5-pe1

PE Proc Sources click now opens the **real** Details `DetailsPlayerDetailsWindow`
(Player Details! Breakdown) instead of a custom framed popup — removes leaked
`UIPanelScrollFrameTemplate` scroll icons, restores Targets panel / native header
chrome. Custom Display script_version 6.

## 1.0.4-pe1

PE Proc Sources click summary restyled to match native Details **Player Details! Breakdown**: status bars with spell icons, amount + percent columns, gold title chrome, Sources / Other procs sections. Custom Display script_version 5.

## 1.0.3-pe1

Left-click PE Proc Sources rows open an attribution summary (damage, hits, average, sibling sources/procs). Custom Display script_version 4.
