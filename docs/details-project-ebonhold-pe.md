# Details!: Project Ebonhold (Echo DPS + Procs)

Lean **Details!** companion for Project Ebonhold on WoW **3.3.5a**.
Does **not** ship the Details! core (~22 MB) — install Details separately.

    Kurzanleitung: [Deutsch](#deutsch-kurzfassung)

## What it fixes

| Area | Before | After |
|------|--------|-------|
| **Echo DPS** | Echo/secondary hits look like anonymous custom spell IDs in the Details spell list | Labeled `Name (Echo)`; optional breakdown API for EbonBuilds EchoPerformance |
| **Procs** | Proc damage has no link to the cast that triggered it; custom display empty on **Overall Data** | Labeled `ProcName [SourceCast]`; Custom Display **PE Proc Sources** (per-segment + Overall aggregate); **click a row** opens the real Details (works on first click) **Player Details! Breakdown** (Sources + Other procs / Targets panel) |
| **Icons** | PE custom spells often lack client DBC icons | Icons from `GetSpellInfo`, then ProjectEbonhold `PerkDatabase` / `GetPerkData` (server sync), cached |
| **Core** | Stock Details defaults | Soft PE defaults (`override_spellids` on, percent on, `overall_clear_newboss` off so Overall Data survives raid bosses); TinyThreat-style shim, not a full fork |

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
**Klick auf eine Zeile** öffnet beim ersten Mal das echte Details-Fenster
**Player Details! Breakdown** (Quellen als Spell-Balken, weitere Procs im
Targets-Panel).

**Overall Data bleibt über Raid-Bosse hinweg:** Stock-Details löscht die
Gesamtdaten bei jedem neuen Schlachtzugsboss (`overall_clear_newboss`). Der PE-
Companion setzt das Soft-Default auf **aus**, damit die Overall-Summe über den
Raid erhalten bleibt (fühlte sich sonst an wie „Daten speichern nicht“). Wer
das alte Auto-Löschen will: Details-Optionen → Overall →
**Bei neuem Schlachtzugsboss löschen** wieder aktivieren.

1. Details!-Core muss bereits unter `Interface/AddOns/Details` liegen
   (oder die komplette Suite **`Details.zip`** entpacken).
2. Companion `Details_ProjectEbonhold` (1.0.10-pe1) unter
   `Interface/AddOns/Details_ProjectEbonhold` — liegt auch in **Details.zip**.
3. `/reload` — Labels erscheinen in der Spell-Aufschlüsselung automatisch.
4. Details-Fenster → Attribut **Custom** → **PE Proc Sources**.
5. Segment **Overall Data** wählen — Balken zeigen die Summe über alle Overall-Fights
   (wie DPS Overall). Zeile anklicken öffnet natives Player Details! Breakdown
   (dicht gefüllt; Fenster dockt neben dem Meter). Weitere Procs/Quellen in den
   linken Panels sind klickbar; unten links darf die Maus nicht hängen.

Siehe auch: [Details!: Tiny Threat (PE)](details-tinythreat-pe.md).
