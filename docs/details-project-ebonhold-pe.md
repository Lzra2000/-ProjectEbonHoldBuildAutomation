# Details!: Project Ebonhold (Echo DPS + Procs)

Lean **Details!** companion for Project Ebonhold on WoW **3.3.5a**.
Does **not** ship the Details! core (~22 MB) — install Details separately.

    Kurzanleitung: [Deutsch](#deutsch-kurzfassung)

## What it fixes

| Area | Before | After |
|------|--------|-------|
| **Echo DPS** | Echo/secondary hits look like anonymous custom spell IDs in the Details spell list | Labeled `Name (Echo)`; optional breakdown API for EbonBuilds EchoPerformance |
| **Procs** | Proc damage has no link to the cast that triggered it | Labeled `ProcName [SourceCast]`; Custom Display **PE Proc Sources**; **click a row** for a DPS-style breakdown (hits, other sources, other procs from that cast) |
| **Icons** | PE custom spells often lack client DBC icons | Icons from `GetSpellInfo`, then ProjectEbonhold `PerkDatabase` / `GetPerkData` (server sync), cached |
| **Core** | Stock Details defaults | Soft PE defaults (`override_spellids` on, percent on); TinyThreat-style shim, not a full fork |

## Install

1. Ensure **Details!** is in `Interface/AddOns/Details`.
2. Prefer **`Details.zip`** (full suite), or download **`Details_ProjectEbonhold.zip`** alone from the
   [latest release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest)
   (when attached) **or** copy `vendor/Details_ProjectEbonhold/` from this repo.
3. Folder name must be exactly **`Details_ProjectEbonhold`**.
4. `/reload`. Optional: Details window → Custom → **PE Proc Sources**.
5. Toggles: `/detailspe echoes`, `/detailspe procs`.

Works alongside **Details_TinyThreat** (threat plugin) and EbonBuilds
**Track DPS by echo** (EchoPerformance).

## Deutsch (Kurzfassung)

**Details!: Project Ebonhold** kennzeichnet Echo-Schaden in Details als
`(Echo)` und zeigt bei Procs, **welcher Spell** sie ausgelöst hat
(`Proc [Quell-Spell]`). Zusätzlich gibt es die Custom-Anzeige
**PE Proc Sources** (scrollbar / höhere Fensterhöhe; Spell-Icons aus
`GetSpellInfo` bzw. PE-Perk-Datenbank; echte Prozent-Spalte).
**Klick auf eine Zeile** öffnet eine Zusammenfassung wie bei DPS: was hat
welchen Proc ausgelöst (Schaden, Hits, weitere Quellen / weitere Procs).

1. Details!-Core muss bereits unter `Interface/AddOns/Details` liegen
   (oder die komplette Suite **`Details.zip`** entpacken).
2. Companion `Details_ProjectEbonhold` (1.0.3-pe1) unter
   `Interface/AddOns/Details_ProjectEbonhold` — liegt auch in **Details.zip**.
3. `/reload` — Labels erscheinen in der Spell-Aufschlüsselung automatisch.
4. Details-Fenster → Attribut **Custom** → **PE Proc Sources** → Zeile anklicken.

Siehe auch: [Details!: Tiny Threat (PE)](details-tinythreat-pe.md).
