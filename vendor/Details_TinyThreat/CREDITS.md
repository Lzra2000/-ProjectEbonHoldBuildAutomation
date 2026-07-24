# Details_TinyThreat (vendored, Project Ebonhold fork)

This folder contains **Details!: Tiny Threat v1.07** by the **Details! Team**,
packaged for Project Ebonhold players on **WoW 3.3.5a (Interface 30300)**.

Tiny Threat is a **Details! plugin** — it does not run without the **Details!** core add-on (Interface/AddOns/Details). Prefer the release asset **Details.zip** (full suite including TinyThreat). Legacy single-plugin zip remains for compatibility.

## Upstream source

Extracted from the PE client bundle zip `Details_TinyThreat (2).zip`, which also contained
Details! core and sibling plugins. Only **Details_TinyThreat** is vendored here.

| File | Role |
|------|------|
| `Details_TinyThreat.lua` | Plugin logic (threat bars in a Details! window) |
| `enUS.lua`, `ptBR.lua` | AceLocale strings |
| `Libs/` | Embedded LibStub + AceLocale-3.0 |

## Project Ebonhold fork delta (`v1.07-pe1`)

| File | Change |
|------|--------|
| `Details_TinyThreat.toc` | PE title/version, fork notes, loads PE helper first |
| `DetailsTinyThreatProjectEbonhold.lua` | **New** — WotLK group API shims, `pcall` guards for threat/role APIs |
| `Details_TinyThreat.lua` | Uses PE helpers; WotLK plugin icon; soft-fail when Details! missing |
| `CREDITS.md` | This document |

**`DetailsTinyThreatProjectEbonhold.lua`**

- **`TT_EnsureGroupCompat`** — defines `IsInGroup`, `GetNumGroupMembers`, etc. when absent (Details! `compat.lua` normally provides these; shims keep Tiny Threat loadable in isolation during tests).
- **`TT_EnsureThreatCompat`** — polyfills `UnitDetailedThreatSituation` from `UnitThreatSituation` when the PE engine backport is absent (coarse percent/value bands).
- **`TT_EnsureNameCompat`** — defines `GetUnitName` from `UnitName` when absent (MoP API; PE client usually has it natively).
- **`TT_SafeUnitDetailedThreatSituation`** — guards flaky `UnitDetailedThreatSituation` on custom cores.
- **`TT_SafeUnitGroupRolesAssigned`** — uses DetailsFramework role helper with fallback `"NONE"`.
- **`TT_IsDetailsReady`** — soft-fail gate when Details! core is not loaded.

**Left unchanged from upstream**

- AceLocale strings, LibStub embeds, plugin options UI, slash commands (`/tinythreat`, `/tt`).
- No Retail / `C_*` APIs added.

## Install

Extract `dist/Details_TinyThreat.zip` to `Interface/AddOns/Details_TinyThreat`.
Requires **Details!** in `Interface/AddOns/Details` (not included in EbonBuilds releases).
