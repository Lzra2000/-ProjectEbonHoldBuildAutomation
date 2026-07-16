# EbonBuilds — FAQ & Changelog

*This file is updated with every release. Latest version: 2.24 — also available in-game via* `/ebb faq`

---

## FAQ

### My reroll behavior feels different after updating. Is that a bug?
No — two intentional changes affect it:

1. **The peak score no longer includes the novelty bonus.** Previously the peak was inflated at run start (when everything is novel), which made percentage thresholds progressively unreachable as the run consumed novelty — freeze and reroll would quietly stop firing mid-run. The peak is now a stable reference for the whole run. Your percentage settings now mean what they say, but the absolute thresholds shifted.
2. Old builds get the new settings keys backfilled automatically on login (Classic reroll mode, so behavior stays as-is until you opt in to Smart mode).

If your thresholds feel off, press **Reset thresholds to default** once (it actually persists now — see below) and re-tune.

### I pressed "Reset thresholds to default" and nothing changed. Why?
That was a real bug, fixed in 2.0. Previously, every change in the Settings tab (including Reset) only lived in a temporary editing copy and was silently discarded unless you also pressed Save on the form tab. **Now all Settings-tab changes persist immediately** when editing an existing build: sliders (on release), reset button, reroll mode, family whitelist, ban list, and ban-all mode.

### What is Smart Reroll and should I use it?
A new opt-in reroll mode (button in the Automation tab: *"Reroll mode: Classic (sum) / Smart (expected value)"*).

- **Classic** (default): reroll when the *sum* of all three offered scores is below *Auto-reroll %* of the peak, unless the guard blocks it.
- **Smart**: reroll when the *best* offered echo is worse than X% of what an average reroll's best offer would be worth — computed exactly from your weights across every echo and quality tier your class can roll.

Smart mode is immune to the classic mode's two failure modes: a single mega-weighted echo skewing the peak, and quality-bonus noise inflating the sum. Frozen and carried echoes are ignored on both sides of the comparison (they survive a reroll anyway). **Recommended: Smart mode at 95%** — that literally means "only reroll when this screen is worse than an average roll," which is never a losing trade statistically.

### What are good Classic-mode settings?
If you stay on Classic: Auto-reroll (sum) ~25–30%, Reroll guard ~30%, Auto-freeze ~15–20%, Auto-banish ~5%. The Settings tab now shows a live warning when your guard sits below your freeze threshold (junk echoes would block rerolls that could find freeze-worthy ones) or when banish sits at/above freeze.

### My weighted class-specific echoes were ignored by automation. Fixed?
Yes (2.0). Weights are stored under the database name (e.g. *"Warrior - Voidsteel Bulwark"*), but automation looked them up under the in-game spell name (*"Voidsteel Bulwark"*) — so class-prefixed echoes silently scored with weight 0. All lookups now go through one canonical name function, and a regression test pins it.

### Automation froze an echo and then immediately picked it. Fixed?
Yes (2.0). Selecting now excludes echoes frozen this round — the whole point of spending the freeze charge is to take something else on this screen and collect the frozen echo later. Carried echoes from previous screens remain selectable, as intended.

### How do I report a problem so it can actually be fixed?
1. `/ebb debug` — turns on decision tracing (confirmation in chat)
2. Play until the problem happens
3. `/ebb debuglog` — opens a window with the full trace, pre-selected: Ctrl+C and paste it in your report

The log shows the peak, every threshold as an absolute number, every offered echo with score/weight/frozen state, and the reason behind every action or non-action. It's plain text, capped at the last 500 lines, and costs nothing while disabled.

### The Missing tab showed duplicates / owned echoes as missing. Fixed?
Yes (2.0): quality-tier grouping works now (one entry per echo line, owning any tier removes the line from Missing), the list no longer empties after every level-1 reset, and an empty spellbook at login shows "Requesting data..." instead of listing everything as missing.

### Why are there 6 locked-echo slots now?
The addon supports 6 locked slots everywhere (wizard, editor, overview, sync, export/import). Note: whether the **server** honors a 6th lock is a Project Ebonhold question — the addon side is ready.

### What do the colors mean?
Standard WoW rarity colors everywhere: white Common, green Uncommon, blue Rare, purple Epic, orange Legendary — on echo names in the table, picker, wizard, logbook, and as rings around locked-echo icons in build cards. Class colors follow the standard palette.

---

### How does the Tome Atlas work? (new in 2.2)
An AtlasLoot-style **community drop database** for echo tomes. When you loot a tome, the addon records the mob and zone automatically and shares the observation with other EbonBuilds users (over the sync channel and guild). Data from other players arrives live as drops happen and whenever anyone syncs (Public Builds > Reload). Duplicate reports merge via max-count, so nothing ever double-counts.

**Using it:** open via the *Tome Atlas* button in the left panel or `/ebb atlas`. Search by tome, mob, or zone. Toggle *"Show: Missing only"* to hide everything you already collected (matched against your Echoes spellbook — any quality tier counts as collected). The `(x3)` behind a source shows how often the community saw that drop.

**For new players:** filter to *Missing only* and farm the zones with the most entries — that's your collection route.

### What changed about syncing in 2.3?
Reliability and efficiency, same protocol on the wire (old versions stay compatible):

- **Lost transfers recover.** Previously a single dropped message meant that build silently never arrived. Now the receiver notices a stalled transfer, asks the sender to retransmit (up to 2 attempts), and falls back to other players offering the same build.
- **No duplicate downloads.** When several players offer the same build during one sync, it is requested from only one of them.
- **Flood protection.** Responders answer at most one sync request per player per 30 seconds.
- **Feedback.** A toast summarizes each sync ("Sync complete: N build(s) received"), and with `/ebb debug` enabled the full sync traffic appears in the debug log.
- Retransmit requests can only ever re-send **public** builds you own -- a forged request cannot extract private data.

### What is Smart mode? (extended in 2.4)
Toggle in the Automation tab. In Smart mode every automation decision is measured against **expected values computed exactly from your weights** instead of percentages of the peak: rerolls compare the best offer against an average reroll (default 95%, automatically paced by remaining charges from 100% down to 60%), banish removes cards worth less than an average random card (default 60%), and freeze saves cards beating the expected best of a future screen (default 110%). Classic mode remains the default and unchanged.

### How do build chat links work? (new in 2.4)
Open a build and press **Chat Link** — a token like `[EbonBuilds: Pyro Mage V2]` lands in your chat box and can be sent anywhere (say, guild, party, whisper). Other EbonBuilds users see it as a clickable link: clicking opens the build if they already have it, otherwise it is fetched automatically from any online player who owns it. Only **public** builds are ever served. Players without the addon simply see the plain text.

### Where should I farm for missing tomes? (new in 2.4)
The Tome Atlas now shows a **"Best farming"** line ranking zones by how many of *your* missing tomes have known sources there. Filter, fly, farm.

### My Tome Atlas contributions never seemed to reach anyone. Fixed?
Yes (2.5). If you had zero public builds, the sync responder returned before ever reaching the tome-sharing step -- your drop observations never went out. Fixed, and the Tome Atlas view now has its own **Sync** button next to the filter, so refreshing atlas data no longer requires a detour through Public Builds.

### The Tome Atlas search box and buttons overlapped. Fixed?
Yes (2.6). The search row and the count/filter/sync row now anchor to a single reference frame instead of independent fixed offsets, so they can't drift into each other again. The search box also has real placeholder text now ("Search tome, mob, or zone...").

### Can I see the full drop list for a tome, not just the top 3?
Yes (2.6). Hover any tome row: the tooltip shows the item itself (icon, quality) plus every known source, not just the three shown inline.

### What are Affixes, and how is that different from Echoes?
Project Ebonhold has two separate progression systems. **Echoes** are the run-based perks EbonBuilds has always been about. **Affixes** are a permanent, character-bound unlock applied to gear (weapon procs, armor stats) -- a different system entirely, previously only visible through third-party tooltip-scanning tools. EbonBuilds now reads it directly from the server's own data feed, so there's no guessing involved.

### How do I use the Affixes tab? (new in 2.7)
Open via the **Affixes** button in the left panel or `/ebb affix`. Every known affix is listed with a green dot (learned) or red dot (missing). Search by name, toggle *"Show: Missing only"*, and hover any entry for its full tooltip, weapon/armor restriction, apply cost, and use count. Press **Refresh** to request an updated list from the server (throttled to avoid spamming it).

### The Missing tab said "Requesting data..." forever. Fixed?
Yes (2.9). The tab reads your spellbook's "Echoes" category to know what you own -- but that category only exists once you've learned at least one echo, so a fresh character (or one who just reset) has no such tab, and the check used to wait for something that would never arrive. It now retries automatically every 1.5s, and after 15 seconds gives up waiting and shows the full list anyway. If that fallback triggers, it's logged in `/ebb debuglog` for reference.

### My build disappeared after logging in later. What happened?
This was a real bug, fixed in 2.11 -- not something you did wrong. Saving a build compares its stored author name to your current character name to decide whether it's yours or someone else's. `UnitName("player")` can occasionally come back from the game in a different format (with or without the realm attached) after a reconnect. That mismatch made the addon think your OWN build belonged to someone else, "forked" it into a new slot, and removed the old one.

**Nothing was truly deleted.** The build kept existing under a different id, tagged with a "copied from `<your name>`" note. If you still have a build like that, it's yours -- rename it and clear the copied-from note via Edit Build. The comparison is now realm-suffix-tolerant, so this can't happen again.

### What do /ebb autosell, /ebb bagdots, /ebb errors and /ebb clicktrace do? (new in 2.12)
Four small standalone tools:

- **`/ebb autosell`** — toggle. Auto-sells 0-copper junk items while a vendor window is open. An item carrying an affix you haven't learned yet is always protected, even if it sells for nothing. Off by default; opt in explicitly.
- **`/ebb bagdots`** — toggle. Draws a colored dot on bag items whose gear affix you're missing: red for a brand-new affix line, purple for a rank you're missing on one you already partly have. On by default.
- **`/ebb errors`** — opens a small always-on error log (last 20 entries), separate from `/ebb debug`. Useful as a first step when something breaks and you don't have debug tracing already running.
- **`/ebb clicktrace`** — diagnostic for "I clicked a button and nothing happened." Logs every themed button click and view transition, so a bug report can show whether the click even reached EbonBuilds or was intercepted before that.

### Why did Reload get faster / show fewer builds? (2.13)
The Public Builds **Reload** button now only requests builds for the class currently selected in the dropdown (your own class by default), instead of every class from every peer on every reload. Switch the dropdown to "All Classes" if you want the old everything-at-once behavior back. This cuts sync traffic and page count dramatically on classes many players share builds for.

### What do the checkboxes in the gear-icon Settings dialog do? (new in 2.16)
That's the small "EbonBuilds Settings" popup (gear icon next to the window's close button, not the per-build Automation tab). It now covers:

- **Action delay** — how long automation waits before acting on a new echo screen. Very low values may cause the addon to malfunction.
- **Toast duration** — how long pick/reroll/freeze/banish notifications stay on screen.
- **Auto-sell junk at vendors** — same as `/ebb autosell`, now with a persistent checkbox instead of only a slash command.
- **Bag affix dots** — same as `/ebb bagdots`, likewise now a checkbox here.

The dialog scrolls if it ever grows past the window (same fix as the FAQ window in 2.14), so more settings can be added here later without risk of overflow.

### Why do I get a popup saying my build's name is taken? (new in 2.18)
Public Builds used to fill up with dozens of near-identical entries -- the same title from many different authors, e.g. "[WIP] Scourgebeast's Solo DK v1.1" by five different people. The actual cause: importing someone's public build, then making even a tiny edit and saving, silently forks your copy under your own name (an existing, intentional data-loss protection from 2.11) -- but it used to keep the original title and public status, so every edited import quietly added another duplicate to the list.

As of 2.18, saving (or creating) a build checks whether its exact title is already public under a *different* author. If so:
- Your copy is automatically un-published (not deleted -- just no longer shared).
- A popup explains the name is taken and who it belongs to.
- Rename it (Edit Build) and it can be made public again under its own name.

This is a best-effort, client-side check -- there's no central registry, so it's based on what your own client has seen. Existing duplicates already in Public Builds are also cleaned up automatically: the browser (and what gets relayed to other players) now collapses same-titled entries down to the earliest-known one.

### The Missing tab only showed what I don't have. Now what? (2.19)
The Missing tab now works like the Affixes tab: a green or red dot on each icon shows learned vs. not-learned status, and a **Show: All / Show: Missing only** toggle switches between "everything for my class" and the classic missing-only view. Owned echoes show "Learned" in green where the drop source used to be; missing ones are unchanged (drop source, score). A count label at the top reads "X learned, Y missing" (or just "Y missing" when the filter is on).

### Tome Atlas: category system and non-tome items (new in 2.20)
Two changes:

1. **Non-tome items could show up in the Atlas.** Local loot was always filtered to actual tomes before recording, but data arriving from *other players* via sync went straight in unvalidated -- a bug on a peer's end could inject any item into everyone's Atlas. Both the write path (`Merge`, the network-received one) and the read path (`List`, so anything already-stored gets cleaned up immediately too) now check the item name is actually a tome.
2. **New: Group by Tome / Zone / Mob**, plus a Zone filter dropdown. "By Tome" is the classic view (one row per tome, its sources). "By Zone" shows one row per zone with every tome known to drop there. "By Mob" shows one row per mob with everything it drops. The zone dropdown narrows any of the three views to a single zone. Search still matches tome, mob, or zone text in every mode.

### I deleted a build I imported and it vanished from Public Builds too. Fixed?
Yes (2.21). Importing a public build used to delete Public Builds' cached copy of the original, on the (wrong) assumption that was needed to hide it from the browse list -- it isn't; the list already hides anything you have an up-to-date local copy of on its own. That deletion's only real effect was that if you later deleted your imported copy, the original public build was gone from your Public Builds list entirely until someone synced it to you again. The cache is no longer deleted on import, so deleting your local copy now makes the original reappear immediately.

### EbonBuilds won't even enable / greyed out in the addon list with ProjectEbonhold Enhanced. Fixed?
Yes (2.22). The `.toc` declared a hard `## Dependencies: ProjectEbonhold` -- WoW's client won't let you enable an addon at all if a hard dependency's exact folder name isn't found, and "ProjectEbonhold Enhanced" ships under a different folder name even though it provides the same API. Switched to `## OptionalDeps: ProjectEbonhold, ProjectEbonholdEnhanced`, which still makes sure whichever one you have loads first (so EbonBuilds sees it), but no longer blocks enabling EbonBuilds if the folder name doesn't match exactly. No more manually editing the `.toc` by hand after every update.

### Sync is flooding my chat with "[EbonBuilds Sync] Build ... stored in remote" spam. Fixed?
Yes (2.23). Several internal sync diagnostics (one line per build received, one line per REQ broadcast, channel-index bookkeeping) were printing to general chat unconditionally instead of only when `/ebbsync verbose` is on -- always been there, but the 2.15 staggered all-classes sync made it much worse, since a single "All Classes" Reload can now pull in dozens of builds and fires the REQ-sent line up to 10x (once per class) instead of once. All of that moved behind the existing verbose toggle; real problems (a build failing to assemble) now go to `/ebb errors` instead of the chat window. Command output (`/ebbsync status`, `/ebbsync reset`, etc.) and cooldown/actionable messages are unaffected -- you'll still see those.

### The game froze / hung after syncing with Tome Atlas open. Fixed?
Yes (2.24), most likely cause found and fixed. Tome Atlas (and Public Builds) re-rendered its entire list synchronously on every single incoming synced entry -- normally one build/tome is no big deal, but a real sync can stream in dozens to 100+ in a burst over a few seconds, especially since 2.15's staggered all-classes sync. Each render re-scans your spellbook and rebuilds/sorts the whole list (worse in "Group: Zone"/"Group: Mob" mode), so doing that dozens of times in rapid succession is exactly the kind of thing that makes a client stutter hard or lock up. Both views now coalesce bursty refresh requests into at most one actual render every 0.3s, however many sync messages arrive in between.

### How do I know a Settings toggle actually saved?
As of 2.24, clicking Save in the gear-icon Settings dialog shows a toast confirming what was saved (e.g. "Settings saved (Auto-sell ON, Bag dots OFF)") -- previously it just closed the popup with no feedback at all.

## Changelog

### 2.24 (2026-07-16) -- fix Tome Atlas/Public Builds freeze during sync, Settings save feedback

- **Fixed (likely root cause of reported freeze/hang): Tome Atlas and Public Builds re-rendered synchronously on every single incoming sync message.** `RefreshIfMounted()` called the full render path (list rebuild + sort, spellbook rescan for owned status) directly, once per received build/tome entry. A real sync can deliver dozens to 100+ entries in a burst (worse since 2.15's staggered all-classes sync), so with either view open this could fire that expensive path dozens of times per second -- Group: Zone/Mob mode (2.20) made each one more expensive still. Both views now debounce: incoming refreshes just set a pending flag, and an OnUpdate ticker performs at most one actual render every 0.3s.
- **New: Settings dialog Save now shows a confirmation toast** (e.g. "Settings saved (Auto-sell ON, Bag dots OFF)") instead of closing silently with no feedback.

### 2.23 (2026-07-16) -- sync chat spam fixed

- **Fixed: several internal sync messages printed to general chat unconditionally**, most visibly "Build X stored in remote (author: Y)" once per synced build and "REQ sent on channel index N" once per REQ broadcast. Both existed before, but the 2.15 staggered all-classes sync turned the second one into up to 10 lines per Reload (once per class) and the first into potentially dozens during a busy sync. Moved to the existing `VerboseLog` path (gated behind `/ebbsync verbose`, off by default) along with channel-index learning/update messages. A real assembly error now records to `/ebb errors` (2.12's always-on error log) instead of only flashing through chat. User-initiated command output and cooldown/actionable messages are unchanged.

### 2.22 (2026-07-16) -- works with ProjectEbonhold Enhanced without manual .toc edits

- **Fixed: EbonBuilds couldn't be enabled at all with only "ProjectEbonhold Enhanced" installed.** `## Dependencies: ProjectEbonhold` is a hard dependency on that exact folder name -- the WoW client greys out/force-disables an addon if it's missing, regardless of whether something API-compatible is present under a different name. Changed to `## OptionalDeps: ProjectEbonhold, ProjectEbonholdEnhanced`, which still guarantees correct load order (whichever is installed loads before EbonBuilds) without hard-blocking on an exact folder match. The existing runtime check in `core/Init.lua` (disables gracefully with a chat message if the `ProjectEbonhold` global truly isn't there) is unchanged and still applies either way.

### 2.21 (2026-07-16) -- deleting an imported build no longer loses the original from Public Builds

- **Fixed: importing a public build permanently deleted the cached original from your Public Builds list.** `ImportBuild()` removed the entry from `EbonBuildsDB.remoteBuilds` "to hide it from the list" -- but the browse list (`GetFilteredBuilds`) already hides anything with an up-to-date local copy independently via `FindImportedCopy`, making that deletion redundant. Its only real effect: deleting your imported local copy afterward left the original build gone from Public Builds until the next successful sync from its author. The cache entry is no longer deleted on import -- deleting the local copy now makes the original reappear right away.

### 2.20 (2026-07-16) -- Tome Atlas: categories + non-tome item fix

- **Fixed: items received via sync were never validated as actual tomes before being stored.** `TomeAtlas.Merge()` (the network-received path) had no `IsTomeName` check, unlike the local-loot path (`OnSelfLoot` already checked before calling `RecordDrop`) -- a bug on a peer's end could inject arbitrary items into everyone's Atlas. Added the check to `Merge()`, to `RecordDrop()` itself (defense in depth), and to `List()` as a backstop that filters out anything already stored from before this fix.
- **New: category system.** `TomeAtlas.ListByZone()` and `TomeAtlas.ListByMob()` group all known drops by zone or mob; `TomeAtlas.ListZones()` feeds a new Zone filter dropdown. The view gained a "Group: Tome/Zone/Mob" cycle button and the zone dropdown, narrowing or reorganizing the list along with the existing search and Show: All/Missing toggle.

### 2.19 (2026-07-16) -- Missing tab: owned/missing status dots

- **New: the Missing tab now shows owned echoes too, not just missing ones.** Same status-dot convention as the Affixes tab (green = learned, red = not learned), plus a "Show: All" / "Show: Missing only" toggle (defaults to showing everything, matching Affixes/Tome Atlas). Owned rows show "Learned" instead of a drop source and quality-colored name at reduced opacity; missing rows are unchanged.
- `ComputeMissingEchoes()` gained an additive `includeOwned` parameter -- omitted (as all existing call sites do), behavior is unchanged, so this doesn't touch the existing missing-only contract.

### 2.18 (2026-07-16) -- stop duplicate build titles at the source

- **Fixed: editing an imported public build silently created a same-titled duplicate.** `Build.Save()`'s existing fork-on-foreign-author protection (2.11) kept the original title and public flag when forking a copy to the new author -- multiplied across many players editing the same popular build, this is what filled Public Builds with pages of near-identical entries. Saving or creating a build now checks whether its title is already public under someone else; if so the copy is un-published and a popup explains why, prompting a rename.
- **New: `EbonBuilds.Build.FindTitleOwner(title, excludeId, excludeAuthor)`** -- best-effort client-side check for whether a title is already claimed by a different author, used by both the save-time guard above and:
- **Fixed: existing duplicate titles are now collapsed in the Public Builds list.** `Build.ListPublic()` -- used by both the browsing UI and `HandleRequest` (what gets relayed to other players) -- now keeps only the earliest-known copy per exact title, cleaning up duplicates that already existed before this fix without waiting on network propagation.

### 2.17 (2026-07-16) -- Public Builds no longer resets to page 1 while syncing

- **Fixed: browsing Public Builds got snapped back to page 1 on every single incoming build during a sync.** `RefreshIfMounted()` (called once per received build) unconditionally reset the current page to 1 -- barely noticeable for one build, but the 2.15 staggered all-classes sync streams in dozens over several seconds, making it effectively impossible to browse past page 1 while a sync was still running. It now keeps you on whatever page you're viewing (only clamping down if that page no longer exists).

### 2.16 (2026-07-16) -- Settings dialog expanded

- **New: the gear-icon Settings dialog now has explanations and more toggles.** Toast duration finally has flavor text (it was the only slider without one). Auto-sell junk and Bag affix dots -- previously only reachable via `/ebb autosell` / `/ebb bagdots` with no persistent UI -- now have checkboxes with explanations here too, so you don't need to remember slash commands to turn them on. Also rebuilt as a scrollframe so it can keep growing without ever overflowing the window (same fix class as 2.14's FAQ window).
- Known gap noted for a follow-up: Talent Auto-Learn (`build.talentAutoLearnMode`, added in 2.12) still has no UI control anywhere -- it can currently only be set by editing SavedVariables directly. It's per-build, so it belongs in the Automation tab (Settings view) rather than this global popup; flagging it rather than rushing it into an already dense, absolutely-positioned panel.

### 2.15 (2026-07-16) -- staggered all-classes sync

- **New: "All Classes" Reload no longer sends one unfiltered request.** Previously, picking "All Classes" in Public Builds and hitting Reload sent a REQ with no class filter -- responders answered with their *entire* public/relayed collection, the exact flood of near-duplicate builds the 2.13 class filter was built to avoid. It now requests each of the 10 classes one at a time, 1.5s apart, so every individual request stays as cheap as a normal single-class sync while still covering everything. Counts as one use of the 30s Reload cooldown, same as before.

### 2.14 (2026-07-16) -- FAQ window overflow fix

- **Fixed: the `/ebb faq` window's text could draw straight over the game world and action bars.** The page body was a bare FontString anchored to the window with no height limit and no clipping -- fine while pages were short, but as the "What's New" page accumulated more version history (2.12, 2.13, ...) it grew taller than the fixed-size window and simply kept drawing past the bottom edge, unclipped, over whatever was underneath. Rebuilt with a proper scrollframe: the body now scrolls (mouse wheel or the scrollbar) and can never overflow the window regardless of how long a page gets.

### 2.13 (2026-07-16)

- **New: class-filtered sync requests.** `/ebb` Public Builds Reload now sends the currently-selected class filter along with the sync request, so peers only send back builds for that class instead of their entire public/relayed collection. Old clients (pre-2.13) that receive this extra field simply ignore it and answer as before — fully backward compatible. Tome Atlas sync (which needs all classes) is unaffected.

### 2.12 (2026-07-16)

- **Fixed: eight complete modules existed on disk but were never loaded.** `ClickTrace`, `ErrorLog`, `AffixItemScan`, `GearScore`, `Talents`, `TalentAutoLearn`, `BagAffixDots`, and `AutoSell` were fully written (including the `/ebb autosell` opt-in the code itself documented) but missing from `EbonBuilds.toc`, so none of them ever ran. All eight are now wired into the load order (dependency-safe), bootstrapped from `core/Init.lua`, and reachable via `/ebb autosell`, `/ebb bagdots`, `/ebb errors`, `/ebb clicktrace`.
- **Fixed: ClickTrace's own click-logging hook didn't exist.** Its header comment described logging every click via a hook in `Theme.CreateButton`, but that hook was never implemented — even once loaded, it would have silently recorded nothing. Added the hook to `Theme.CreateButton` and a view-transition hook to `ViewRouter.Show`.

### 2.11 (2026-07-14) -- important fix

- **Fixed a real data-loss bug: your own build could be silently forked away and deleted from its original slot.** `Build.Save()` decided whether a build belonged to you via an *exact* string match against `UnitName("player")`. That name can return with or without a "-Realm" suffix depending on connection state (a known client quirk around reconnects/cross-realm zones), so a later save under a different name format made the addon treat your own build as foreign: it forked it under a new id and deleted the original. The comparison is now realm-suffix- and case-insensitive, matching the same normalization already used for sync/affix name checks. Applied the same fix to two related sync comparisons (self-loopback detection, "is this build already the requester's own") that had the identical risk, though those didn't cause data loss.


### 2.10 (2026-07-14)

- **Fixed: Tome Atlas header layout collision (again, properly this time).** The subtitle, "Best farming" line, search box, and control row were anchored in a chain, each depending on the previous element's actual rendered (word-wrapped) height. A subtitle long enough to wrap pushed everything below it down by a variable amount, causing overlap. Rebuilt with fixed absolute offsets from the panel -- text length can no longer affect anything else's position. Same fix applied to the new Affixes view, which shared the identical pattern.
- **Fixed: long build titles could overflow their card in Public Builds.** Cards had a fixed height regardless of title length; a title long enough to wrap to 2 lines pushed the locked-echo icon row past the card's bottom edge, overlapping the next card in the list. Cards now measure the title first and grow to fit, mirroring the same fix the build list (left panel) already had.
- **Fixed: the same overlap risk on the build Overview page header** (title -> author/date line -> status row) -- hardened with fixed-height reservations so a long title can't push the rows below it out of alignment.


### 2.9 (2026-07-14)

- **Fixed: Missing tab could get permanently stuck on "Requesting data...".** It only re-checked when the player manually clicked away and back; if the "Echoes" spellbook category didn't exist yet (any character with zero echoes learned -- the server doesn't create empty spellbook categories), there was nothing that would ever make it recheck successfully. Now auto-retries every 1.5s while the tab is open, and after 15s falls back to showing the full echo list instead of waiting forever.


### 2.8 (2026-07-14)

- **Fixed: 6th locked-echo icon clipped in the build list.** The left-panel row layout (icon size 22px, 28px spacing) was sized for 5 locked slots; when locked slots went 5->6, the 6th icon extended ~16px past the row's visible width and was cut off by the scroll frame. Icons are now 18px with 24px spacing, fitting all 6 with margin to spare.


### 2.7 (2026-07-14)

- **New: Affix tracking.** Reads Project Ebonhold's server-fed learned-affix protocol (whisper-based addon message channel, chunked transfer) directly -- no tooltip text-scanning, no false positives from set-bonus text or embedded color codes. New Affixes tab: search, missing-only filter, hover tooltips (item/spell info, weapon-only flag, apply cost, use count), manual Refresh with cooldown. Cached per character in `EbonBuildsCharDB`.
- This is the foundation for planned follow-ups: party-wide affix comparison and build-level affix goals.


### 2.6 (2026-07-14)

- **Fixed: Tome Atlas header layout collision** -- search box, count label, filter, and sync button could visually overlap depending on content length. Rebuilt with a single anchor frame so the rows can't drift apart again.
- **New: hover tooltips on Tome Atlas rows** -- shows the tome's item tooltip (icon/quality) plus the complete source list (mob, zone, count), not just the truncated 3-source inline text.
- **New: real placeholder text** in the Tome Atlas search box.


### 2.5 (2026-07-14)

- **Fixed: players with no public builds never shared Tome Atlas data.** `HandleRequest` returned early (replying END) before reaching the tome-sharing loop whenever the responder had zero public builds -- silently dropping their drop contributions from the network.
- **New: Sync button inside the Tome Atlas view**, with the same cooldown as Public Builds' Reload.
- **UI cleanup:** the Automation toggle is now color-coded (green border when ON), Delete uses a red accent to read as a destructive action instead of a stray button, '+ New Build' gets a gold accent as the primary call-to-action, and the status/action button groups on the Overview page have clearer spacing.


### 2.4 (2026-07-13)

- **Smart mode extended:** expected-value thresholds now drive banish (vs. average card, default 60%) and freeze (vs. expected best-of-3, default 110%) alongside reroll; new sliders for both; reroll threshold auto-paces with remaining charges (100% at 8+, 60% at the last one). Debug log headers show `[SMART]`/`[CLASSIC]` with the effective absolute thresholds.
- **New: build chat links** — `Chat Link` button on every build; clickable for addon users, click-to-fetch from any online owner (public builds only), plain text for everyone else.
- **Tome Atlas:** "Best farming" zone ranking for your missing tomes.
- **UI:** retail-style flat buttons across the entire addon (44 buttons reskinned).
- **Fixed (important):** message sanitizing could corrupt sync payloads whose fields start with `c`+hex digits (about 1 in 16 build ids!) or `r` — silently breaking those transfers. Sanitizing is now anchored to the message start and can no longer touch payload content.


### 2.3 (2026-07-13)

- **Sync overhaul:** automatic retransmit of lost build transfers (bounded retries, multi-responder fallback), cross-responder download dedup, per-player request flood guard, sync summary toast, full sync tracing in `/ebb debug`, tome-share cap raised to 100 entries. Wire-compatible with older versions.


### 2.2 (2026-07-13)

- **New: Tome Atlas** — community-shared drop database for echo tomes (mob + zone + observed count). Automatic recording on loot, automatic sharing via sync channel and guild, idempotent merging, search + missing-only filter, `/ebb atlas`. Old client versions safely ignore the new sync messages.


### 2.1 (2026-07-12)

- **Fixed: Pro editor Save silently failed on imported builds.** Saving a build imported from another player forks it under a new internal id (by design, so the original author's build stays intact); every save path now adopts the new id instead of writing to the deleted old one.
- **Fixed: opening the Settings tab could rewrite imported builds.** Programmatic slider refreshes clamped out-of-range values (e.g. freeze 150%) to the slider maximum and, combined with live persistence, saved the clamped value. Refreshes no longer write back.
- **Freeze and guard sliders now go up to 200%.** Since the peak excludes novelty, novel echoes can legitimately score above 100% of peak; thresholds above 100% are meaningful (e.g. "freeze only novelty-boosted hits").
- Note on flat novelty bonuses: a flat +100 novelty makes every unseen echo outrank known good ones and drains freeze/reroll charges. Prefer modest flat values or multiplier mode.


### 2.0 (2026-07-12)

**Automation correctness**
- Peak score now excludes the transient novelty bonus (stable thresholds for the whole run)
- Peak/EV caches are invalidated on build switch, build save, and new run (previously never — stale thresholds after any change)
- Select no longer picks the echo frozen this round; local freeze state is cleared per choice screen and banish can no longer target a just-frozen echo
- No reroll while a freeze round is in flight
- Weights for class-prefixed echoes now apply (canonical name lookup shared between table and automation)

**Smart Reroll (new)**
- Opt-in expected-value reroll mode: rerolls when the best offer is below X% of the exact expected best-of-3 for your class and weights
- Mode toggle + slider in the Automation tab; Classic remains the default

**Settings tab**
- All changes persist immediately when editing an existing build (sliders on release, reset, mode, whitelist, ban list) — fixes "reset did nothing"
- Live conflict warnings: banish ≥ freeze, guard < freeze
- Hover tooltips on every threshold slider with a worked example using your current peak
- Priority-order explainer (Banish → Reroll → Freeze → Select) and reset-to-defaults button

**Diagnostics (new)**
- `/ebb debug` decision tracing, `/ebb debuglog` copyable log window

**Stats tab**
- Echoes Seen, Runs Completed/Reset, quality distribution, Most Picked/Banned now actually track (were never written); distribution percentages sum to 100%

**Missing tab**
- Quality-suffix grouping fixed (no duplicates, cross-tier owned detection works)
- No longer filtered by current level; loading state instead of false "all missing"

**Builds & UI**
- 6th locked-echo slot everywhere; sparse locked slots survive save and export/import (numeric-key JSON round-trip fixed)
- Duplicate build button; delete with 10-second Undo; wizard: class/spec selection, archetype presets, live peak preview, exact weight input, empty-echo-set warning
- Retail-style dark theme; canonical WoW rarity + class colors from one shared palette; rarity rings on locked-echo icons
- Window position remembered; ESC closes windows; run comparison deltas on session cards; score-breakdown tooltips in the Logbook
- Export button exports the build being edited (not blindly the active one); public builds sorted validated-first

**Compatibility & infrastructure**
- Full 3.3.5a API audit; automated guard test against post-WotLK APIs (this class of bug can't ship again)
- 111 automated tests
