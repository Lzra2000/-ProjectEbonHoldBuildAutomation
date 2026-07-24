# Details! suite (vendored for Project Ebonhold packaging)

This tree ships the **Details! Damage Meter** core and official sibling plugins
as used on the Project Ebonhold client (`Interface/AddOns/`), packaged into
`dist/Details.zip` by `scripts/build-dist.sh`.

## Included AddOns (top-level folders in Details.zip)

| Folder | Role |
|--------|------|
| `Details` | Details! core |
| `Details_3DModelsPaths` | 3D model paths plugin |
| `Details_ChartViewer` | Chart viewer |
| `Details_DataStorage` | Data storage |
| `Details_DeathGraphs` | Death graphs |
| `Details_EncounterDetails` | Encounter details |
| `Details_SunderCount` | Sunder count |
| `Details_TimeLine` | Timeline |
| `Details_TinyThreat` | PE fork — see `vendor/Details_TinyThreat/CREDITS.md` |
| `Details_ProjectEbonhold` | PE companion — see `vendor/Details_ProjectEbonhold/CREDITS.md` |

`Details_TinyThreat` and `Details_ProjectEbonhold` are overlaid from their
dedicated vendor folders (PE-corrected) when building the suite zip.

## Upstream

Details! by the **Details! Team** (Tercioo et al.). Redistributed here so
releases can ship a drop-in WotLK 3.3.5a / PE-ready suite. Prefer installing
via the release asset **Details.zip**.

Optional override for local packaging: set `DETAILS_SUITE_DIR` to an
`Interface/AddOns` path (e.g. PE client) before running `scripts/build-dist.sh`.