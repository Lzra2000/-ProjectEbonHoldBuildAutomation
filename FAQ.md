# EbonBuilds — FAQ & Changelog

*This file is updated with every release. Latest version: 3.20 — also available in-game via* `/ebb faq`

---

## FAQ


### How do I generate an Echo Wish List (EWL)?
Open the build's **Overview** and click **Export EWL**, or use `/ebb ewl` for the active build. The addon creates a standard `EWL1:<CLASS>:` import string.

EWL export mirrors the EchoWishlist addon's catalog rules. A configured locked Echo marks its **catalog family** as saved with `:1`; it does not force that particular quality-rank spell ID. For example, a locked `200745` variant can correctly export as the family's retained EWL ID `200744`.

Each remaining Echo family with at least one non-zero rank weight is exported once with `:0`. Quality and class aliases are merged into the same player-facing Echo row, preventing duplicate rank IDs. When EchoWishlist is installed, its live catalog is used directly; otherwise EbonBuilds builds a compatible catalog from Project Ebonhold data.

Rows use EchoWishlist's ordering: saved first, then currently tome-locked rows, quality descending, and name ascending. The dialog warns when a weighted family cannot be matched to a class-compatible catalog row.

The EWL format stores the spell ID and locked status only; it does **not** carry the numeric EbonBuilds weight itself.

### How do the redesigned Stats and Logbook work?
The **Stats** tab is now an analysis workspace with four focused views:

- **Summary** — average selected score, resource use per level, weighted-Echo coverage, and evidence confidence.
- **Echoes** — sortable weighted priorities with final score, appearance rate, pick share, DPS evidence, and personal/community sample counts.
- **Actions** — Select, Banish, Reroll, Freeze, and Manual decision patterns plus recorded pick quality.
- **Recommendations** — evidence-backed Manual Training, DPS, and quality-modifier suggestions.

Click an Echo row, action card, or recommendation evidence button to open the **Logbook** with matching temporary filters.

The Logbook now uses decision-first rows: **Time, Action, Decision, Explanation, Charges**. Clicking a row opens the full three-offer score breakdown. Filters include action, automatic/manual source, important decisions, text search, and optional level grouping. Older logs remain compatible, but the UI does not invent thresholds or score components that were never recorded.


### What does the Missing tab show by default?
The Missing tab now opens in **Weighted priorities** view. This includes only Echoes that have at least one non-zero rank value in the current build, whether that value is positive or negative. The view includes learned and unlearned weighted Echoes so you can immediately see which important priorities are still missing.

Use the view selector for broader checks:

- **Weighted missing** — only weighted Echoes that are not learned.
- **All missing** — every unlearned Echo available to the build's class.
- **Learned + missing** — learned and unlearned Echoes for the class.

All-zero Echoes are excluded from both weighted views.


### How do I hide Echoes I have not learned?
Use **Learned only** in the second row of the Priorities filter bar. While active, the list hides Echoes for which the character has not learned any rank. The filter reads Project Ebonhold's discovered-Echo data first and falls back to the Echoes spellbook on older server builds. If spellbook data is still loading, the addon temporarily leaves the list unfiltered rather than incorrectly hiding everything.


### What is Manual Training Mode?
Enable **Training** from the active build overview. While it is on, Autopilot yields to the native Echo picker and EbonBuilds observes what you choose. When your manual choice repeatedly disagrees with the current scoring, the addon produces a rank-specific raise or lower suggestion. Older 2.57 family-level observations remain compatible and are treated as an equal nudge to every available rank. Use `/ebb cleartraining` to clear the active build's training history.

### What are Echo appearance rates?
EbonBuilds records how often each Echo family appears on a choice screen. Local recording is automatic and lightweight. **Share echo appearance rates** in `/ebb tuning` is a separate opt-in control that exchanges aggregate, class-matched counts with other users. Appearance data is shown in Echo icon tooltips and Export (AI). **Sync Now** sends a few enabled DPS and/or appearance batches immediately instead of waiting for the periodic broadcast.

### What does Auto-apply weight suggestions do?
This option is off by default and also requires **Continuous auto-tune**. It applies DPS and Manual Training suggestions using signed deltas while preserving the separate Common, Uncommon, Rare, and Epic values. Rank-specific training observations change only that rank. Family-level DPS or legacy observations apply the same delta to each available rank. Opposing signals are combined first, so they cancel rather than silently overwriting one another.

### Can I give Epic, Rare, Uncommon, and Common versions different Echo values?
Yes (2.50). The **Priorities** tab now shows one signed whole-number field for every quality rank that a particular echo can actually roll. For example, Scorching Wounds can use a negative Common value, a modest Uncommon value, and a high Rare value. Unavailable ranks remain blank. Existing single-value builds migrate automatically by copying the old value to every rank, preserving their previous scoring behavior.

Use the single **Protect** button beside an Echo when automation must not banish it. The button reads **Protected** while active, removes conflicting priority-ban entries, and saves with the build across reloads, export/import, and sync. Values remain integers because the original editor only supported whole numbers; the accepted range is -999999 through 999999.

### My reroll behavior feels different after updating. Is that a bug?
No — two intentional changes affect it:

1. **The peak score no longer includes the novelty bonus.** Previously the peak was inflated at run start (when everything is novel), which made percentage thresholds progressively unreachable as the run consumed novelty — freeze and reroll would quietly stop firing mid-run. The peak is now a stable reference for the whole run. Your percentage settings now mean what they say, but the absolute thresholds shifted.
2. Existing builds keep their saved automation model and thresholds. Newly created builds use the Balanced Smart profile.

If your thresholds feel off, open **Autopilot** and choose **Balanced** for a dependable baseline, then adjust only the action that feels wrong.

### Why do Autopilot changes save before I press Save build?
Autopilot and per-Echo Protect controls save immediately so the rules shown on screen are always the rules automation will use. Build identity, Echo values, and modifiers still use the normal **Save build / Cancel** workflow. The footer reminds you which controls are immediate.

### What is Smart automation and should I use it?
Open **Autopilot** and choose an intent preset. New builds start with **Balanced**, which uses the Smart expected-value model. Existing builds keep their previously saved mode and thresholds.

- **Smart:** reroll compares the best current Echo with the expected best result of a fresh three-Echo screen; banish compares one Echo with an average random offer; freeze compares strong offers with an expected best-of-three.
- **Classic:** retains the older peak-percentage and three-score-sum behavior under **Advanced**.

Smart mode is less sensitive to one extreme weight or quality-bonus noise. Frozen and carried Echoes are ignored during reroll comparisons because they survive the reroll. Each Autopilot action card translates its percentage into a live score cutoff, so the result is understandable without manually calculating it.

### What are good Classic-mode settings?
If you stay on Classic: Auto-reroll (sum) ~25–30%, Reroll guard ~30%, Auto-freeze ~15–20%, Auto-banish ~5%. Autopilot > Advanced explains when your guard sits below your freeze threshold (junk echoes would block rerolls that could find freeze-worthy ones) or when banish sits at/above freeze.

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
Standard WoW rarity colors everywhere: purple Epic, blue Rare, green Uncommon, and white Common — shown in descending value order across Echo editors, pickers, logs, and locked-Echo rings. Class colors follow the standard palette.

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
Choose a preset in the **Autopilot** tab. Smart mode measures decisions against expected values computed from your weights: rerolls compare the best offer against an average reroll, banish compares one card against an average random card, and freeze compares offers against the expected best of a future screen. New builds start on the Balanced Smart profile; existing builds retain their saved behavior, and Classic remains available under Advanced.

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

### The Missing tab has no way to re-check what I've learned. New?
Fixed (2.25): a **Refresh** button next to Show: All/Missing only. Unlike Affixes' Refresh (which asks the server), this one is a local spellbook re-scan -- Echoes come straight from your own client's spellbook, no server round-trip needed. Previously the only way to force a re-check was leaving the tab and coming back.

If the tab says "0 learned" and that looks wrong: the count only reflects what your current character's spellbook "Echoes" category actually contains right now. A fresh character (or one who just reset) legitimately shows 0 until the server grants that category. Try Refresh first; if it's still 0 after you know you've picked up an echo, that's worth a bug report (`/ebb errors`).

### New: Apply to Character (2.26)
Build Overview has a new **Apply to Character** button. It sends this build's locked echoes to the server's native Active Echo Loadout (`ProjectEbonhold.PerkService.SetActiveEchoLoadout`) -- the game's own echo-pick screen then highlights choices that match, directly in-game, without needing to alt-tab to EbonBuilds while picking. Needs at least one locked echo in the build; works on both ProjectEbonhold and ProjectEbonhold Enhanced.

### Why is "learned" detection more reliable now? (2.26)
The Missing tab and Tome Atlas both used to determine what you've learned by scanning your spellbook's "Echoes" tab -- it works, but needs the tab to actually be populated (hence the old retry-and-wait behavior) and matches by spell name. As of 2.26 both now prefer `ProjectEbonhold.PerkService.GetDiscoveredEchoes()`, an authoritative, spellId-keyed list backed by a SavedVariables cache -- available instantly, no waiting. The spellbook scan is kept as an automatic fallback for servers without that API.

### Why couldn't I see my own public build in Public Builds?
It used to be deliberately hidden there (you already have it in your left sidebar, so browsing it again seemed redundant) -- but that also meant there was no easy way to confirm a build actually published successfully. As of 2.29, your own public builds show up in Public Builds too, tagged **(You)** next to your name, with the Import button replaced by a disabled "Yours" label. If it's not there after making a build public, that's a real sign something's wrong (check the title-collision popup from 2.18 -- your build gets auto-unpublished if the exact title is already public under someone else).

### Tuning Advisor: self-calibrating thresholds (2.33, Smart mode support in 2.34)
`/ebb tuning` opens a window comparing your Banish/Reroll/Freeze thresholds against what your build has actually been offered, not just the theoretical scoring model. EbonBuilds records the score (as % of peak) of every echo automation evaluates, always-on and lightweight, into a per-character sample buffer. Once it has at least 30 samples, the advisor computes what threshold your CURRENT setting actually corresponds to (e.g. "rejects ~13% of real offers") and suggests a value to hit a sensible target (~15% for Banish, ~45% for Reroll, ~10% for Freeze), with an Apply button that writes it straight to your active build.

Works with **both Classic and Smart (EV) mode**, covering Banish, Reroll, and Freeze in both. Smart mode's fields are a % of mean/evBest3/EV rather than peak directly -- the advisor converts through the current mean/peak, evBest3/peak, or EV/peak ratio so both modes analyze against comparable underlying data (cross-checked: a Classic and a Smart suggestion targeting the same percentile land on the same real threshold). Smart Reroll's suggestion (2.48) uses its own sample stream with each evaluation's charge-pacing multiplier divided back out, since its live threshold moves with remaining charges -- the same pacing behavior as before, just now something the advisor can actually analyze. "Clear Collected Data" is worth using after a major reweight, since old samples reflect the previous weighting.

### Continuous auto-tune (2.35) -- do I have to keep clicking Apply?
Not if you don't want to. `/ebb tuning` has a **Continuous auto-tune** checkbox (off by default). Turn it on and thresholds nudge themselves toward their suggested value automatically -- a small gradual step (25% of the gap) every ~20 newly-recorded offers, never an instant jump. You'll get a toast every time it actually adjusts something, so you're never left wondering why automation's behavior changed. It's deliberately gradual and rate-limited so it can't overreact to a short noisy streak; simulated tests show it converges smoothly to a stable value over a few hundred samples rather than oscillating.

### Whole-run budget pacing (2.36)
Automation now spends its Banish/Reroll/Freeze charges with the REST OF THE RUN in mind, not just the current offer in isolation. Smart Reroll already did this (get pickier as reroll charges run low); as of 2.36, Banish, Freeze, and Classic Reroll all get the same treatment:

- **Banish**: with plenty of charges left, banishes anything below the usual threshold; with few left, only banishes clearly-bad echoes, so the last few aren't burned early on borderline picks.
- **Reroll** (Classic mode, previously had no pacing at all): same idea -- pickier as charges run low.
- **Freeze**: with plenty of charges left, freezes anything above the usual threshold; with few left, only freezes genuinely excellent finds.

All three use the same shared curve (`ChargePacing`), just with per-lever comfort caps and conservativeness. `/ebb debug` now also shows the pacing multiplier actually applied to each threshold in the EVAL header, for troubleshooting.

Known limitation: the Tuning Advisor's "current threshold rejects/catches X%" figure is computed against the *base* (unpaced) threshold value -- it's still a useful approximation, but not perfectly exact now that the real applied threshold shifts with remaining charges throughout a run.

### Export (AI) -- new button (2.38, full class echo list + descriptions in 2.39)
Next to the regular Export button (build edit screen, any tab) is a new **Export (AI)** button. Regular Export produces a compact Base64 string meant for another EbonBuilds client to Import -- not something a human or a general AI chat can read. Export (AI) instead produces a plain-text dump: quality/family/novelty bonuses, automation thresholds (with mode-appropriate labels), locked echoes, banned echoes, and -- as of 2.39 -- **every echo your class can get, not just the ones you've weighted**, each with its quality, family, current weight, and actual effect description (pulled from the real spell tooltip where cached; otherwise a note to hover it once in-game first). If you've collected any Tuning Advisor data, that's included too. Meant to be copied and pasted into an external AI chat to ask for tuning suggestions on which echoes are actually worth weighting for your spec; it isn't a format EbonBuilds can import back in.

### Track DPS by echo (2.40) -- needs Details!
`/ebb tuning` has a second checkbox: **Track DPS by echo**, off by default, requires the Details! damage meter addon. When on, every 10 seconds while you're in combat it samples your current DPS (via Details' documented public API) and credits it to every echo you currently have active. Over time this builds a rough real-performance average per echo -- shown in Export (AI) alongside the theoretical scoring once you've collected some data.

This is deliberately approximate, not a controlled measurement: echoes stack together and fight difficulty/duration/execution vary a lot run to run, so it can't isolate any single echo's true causal effect. Treat it as a rough supplementary signal to combine with the scoring model and Tuning Advisor data, not a replacement for either. If Details! isn't installed, the checkbox tells you and won't enable.

## Changelog

### 3.21 (2026-07-19) -- Gear upgrade hints on item tooltips

The GearScore API that 3.20's orphan review deliberately kept ("a coherent gear-upgrade API waiting to be wired up") is now wired up.

- Item tooltips get one extra line saying whether the hovered item scores as an upgrade for the **active build's** class and spec -- the build is the source of truth, not your current talents, so drops are judged for the spec you're building toward. Reads either "upgrade (+N vs equipped)", "upgrade (slot is empty)", or "not an upgrade (-N vs equipped)".
- Dual-slot items (rings, trinkets, one-hand weapons) compare against the weakest currently-equipped candidate slot -- the one the new item would sensibly replace. An empty candidate slot always counts as an upgrade.
- Scoring is GearScore's existing model: weighted stats per class/spec plus an item-level baseline. The weights are documented as directional defaults, not min-maxed truth.
- On by default for a character that has never touched the setting (same never-override-an-explicit-off pattern as DPS tracking's 3.13 default); toggle lives in Settings under Automation. Off, the hook costs one boolean read per hover.
- Tooltip handlers are error-isolated: a failure lands in the Error log instead of breaking hovering for the session (3.10's lesson, applied from day one here).
- New `EbonBuilds.GearScore.UpgradeInfo` does the slot resolution and comparison; `INVTYPE_SLOTS` maps every WotLK equip location. Tests cover the dual-slot weakest-candidate rule, the empty-slot rule, non-equippable items yielding no verdict, the default-on contract, and the tooltip line itself against a stub -- including that the feature off leaves tooltips untouched.

### 3.20 (2026-07-19) -- Acting on what 3.19's tooling found

Follow-up to the two findings the new scripts surfaced.

- **The "8 orphaned translation keys per locale" finding was a false alarm -- and led to a real fix elsewhere.** Before deleting them, verification showed the keys are actively used: `BuildTabs.lua` looks them up through an alias (`local L = EbonBuilds.L`), which the i18n report, `scripts/new-locale.sh`, and the locale consistency test were all blind to. All three now recognize alias lookups. Real key count went from 14 to 22, coverage is 100% in all six languages with zero orphans -- and, more importantly, a missing tab-label translation now actually fails the test suite, which it previously wouldn't have.
- **13 of the 18 uncalled exports are gone**: `Affix.LastReceivedAt`, `Build.HasRestorableDelete`, `Build.NewId`, `BuildTabs.GetActiveTab`, `BuildTabs.IsDirty`, `Filters.FocusSearch`, `MainWindow.GetRightPanel`, `Quality.Hex`, `Scoring.ComputeRerollEV`, `Session.ClearAllSessions`, `Session.DeleteLogEntry`, `Talents.PointSummary`, `Talents.TotalPoints`. Each had zero callers anywhere, including through module aliases and tests; git history keeps them if one is ever wanted back.
- **5 kept deliberately**: `GearScore.HasWeights` / `IsUpgrade` / `ScoreEquipped` (a coherent, documented gear-upgrade API waiting to be wired up), `Talents.ScanUnit` (the async inspect machinery, similarly documented and self-contained), and `Affix.IsLearned` (documented lookup utility). These read as prepared features, not leftovers.

### 3.19 (2026-07-19) -- Six pieces of developer tooling

Repo/tooling release; the only in-game-relevant piece is the new fuzz test hardening confidence in Sync's crash resistance.

- `scripts/ship.sh <version>`: release, push, and publish the GitHub Release as one command, stopping with a clear message at whichever stage fails. The token goes through a temporary credential helper, never into the remote URL. Exists because "pushed the tag but never published the Release" has already happened here once.
- `scripts/check-load-order.sh`: flags file-scope references to an `EbonBuilds.<Module>` that no earlier `.toc` file defines -- the exact trap the ErrorLog.Protect wrap fell into in 3.10. Comment- and string-aware, so keywords in either can't produce false positives; verified it catches a deliberately reintroduced violation.
- `scripts/find-orphans.sh`: Lua files the `.toc` never loads (hard failure) and exported functions with no visible caller (listed for review; `_`-prefixed test hooks exempt, tests count as callers). Currently reports 18 uncalled exports worth a look.
- `scripts/i18n-report.sh`: per-locale coverage report -- missing keys and orphaned entries. Reads each locale file by actually loading it with a stub `Register`, so it's escaping-accurate rather than grep-approximate. Immediately caught 8 orphaned keys per locale left over from the contributed settings redesign (PR #4 replaced the tab labels that BuildTabs.lua used to look up).
- `scripts/triage-error.sh`: paste an `/ebb errors` dump (file or stdin), get every mentioned `file:line` with surrounding source, the error line marked, and the last commits touching that exact range via `git log -L`. Reproduces the full context of 3.11's real crash report from just the pasted error text.
- `tests/test_sync_fuzz.lua`, now part of `tests/run.sh`: 4000 deterministic hostile payloads (control-byte floods, truncated batches, delimiter storms, absurd numerics, wrong prefixes) against `DispatchAddon`, `HandleChannelMessage`, and `HandleSystemMessage`. Uses its own LCG so the seed reproduces identically across Lua versions; on failure it prints seed, iteration, and the escaped payload. First full run passes -- the control-byte fix from PR #1 holds under pressure. Adds `_HandleChannelMessageForTests`/`_HandleSystemMessageForTests` hooks to Sync.lua, matching the existing pattern.

### 3.18 (2026-07-19) -- Settings window redesigned (contributed)

Contributed by ha99dfs (PR #4), building on 3.15's category tabs.

- The Settings popup is now a larger window (640x520) with a left-hand category navigation instead of a horizontal tab row, each category with a title and short description of what lives there.
- Settings edits are held as a draft against a baseline: nothing applies until Save, Cancel discards cleanly, and categories with an invalid value get a visible error marker in the navigation.
- The window remembers which category you had open last and clamps to the screen.
- The "Language" category is now "Interface".

### 3.17 (2026-07-19) -- Repo page design applied to all six translated READMEs

Repo-only release, nothing changes in-game.

- All six translated READMEs (Deutsch, Español, Français, Polski, Português (Brasil), Русский) now open with the same banner, status badges, and how-it-works diagram as the English one, with the language bar bolding its own language.
- While touching them anyway, their Commands and bug-reporting sections were finally brought up to date with 3.15's slash-command removal -- they'd still been showing the full table of removed `/ebb` subcommands. Each now describes the Settings popup instead, translated in the same register the rest of that README already uses.

### 3.16 (2026-07-19) -- Repo page: banner, diagram, badges

Repo-only release, nothing changes in-game.

- New `assets/banner.svg`: an original title banner (obsidian tones, a rune circle around an anvil, three fanned echo cards) drawn from scratch for this project -- no game assets are used or reproduced.
- New `assets/how-it-works.svg`: a four-step diagram of the core loop (define a build, automation acts, data is tracked, the advisor tunes) with the feedback path back to the build.
- README.md now opens with the banner, status badges (CI, latest release, WoW 3.3.5a, Lua 5.1), and the diagram. Text content is unchanged.
- `assets/` is not part of `dist/EbonBuilds.zip` -- the packaging script copies an explicit file list, so the addon download stays the same size.

### 3.15 (2026-07-19) -- Settings popup: categories instead of one long scrolling list

The Settings popup (gear icon, added in 3.14 to hold everything the removed slash commands used to do) is now five tabs -- General, Automation, Language, Windows & Tools, Build -- instead of one continuously growing scrolling list. Same widget pattern as the build editor's own tabs (`Theme.CreateTab` / `SetTabSelected`).

- No more scrollframe in this popup at all -- each category's content fits without it, which is also most of why this was worth doing: a scrolling list gets harder to scan every time something's added to it, tabs don't.
- Save still applies every category's changes at once regardless of which tab is currently showing -- switching tabs never discards a change made on another one before clicking Save.
- Updated the two existing structural tests that hard-coded the old scrollframe's exact anchoring/binding calls, and added a new one for the category mechanism itself (both panel visibility and tab highlighting toggle together, and Save reads all four toggle checkboxes' real state regardless of which panel is visible).

### 3.14 (2026-07-19) -- Contributor tooling: CI consolidation, templates, locale scaffolding

- CI (`.github/workflows/lua-syntax.yml`) now runs `scripts/dev-setup.sh` + `scripts/check.sh` + `scripts/build-dist.sh` directly, instead of duplicating the syntax/test/TOC-check logic inline. That duplication meant a fix to `scripts/check.sh` (like the shellcheck fix in 3.06) never actually reached CI -- now there's one script both contributors and CI run, so they can't drift apart again.
- New `scripts/new-locale.sh <code>`: scans the whole addon for every `EbonBuilds.L["..."]` call site and generates a starting locale file with every known key pre-filled (English placeholder as the value), grouped by source file. Adding a language used to mean manually copying an existing locale file and hoping nothing was missed; now it's one command plus filling in the values.
- New `CONTRIBUTING.md`: setup, the pre-PR checklist, and the project's actual conventions (file headers, test-hook naming, `ErrorLog.Protect`, changelog format, the release process) in one place instead of scattered across READMEs and code comments.
- New PR template with a checklist matching those conventions, and bug report / feature request issue templates (the bug report one asks for `/ebb errors` and `/ebb clicktrace` output up front, matching the README's existing bug-reporting guidance).

### 3.13 (2026-07-19) -- DPS/appearance tracking (Echo Performance) is on by default

A character that has never touched the setting now gets it enabled automatically, instead of requiring an opt-in. A character who explicitly turned it off keeps that choice -- only ever applies to a character that has never set it either way.

Worth knowing: enabling this also means your own tracked DPS-per-Echo data gets included in the periodic sync broadcast to your guild and current sync channel (same as it always did for anyone with tracking on) -- this default change means that now happens automatically instead of only for people who'd opted in. Turn it off any time with `/ebb tuning` (or `/ebb advisor`).

- `modules/automation/EchoPerformance.lua`: `Init()` now defaults `echoPerformanceEnabled` to `true` for a character seeing the setting for the first time (checked with `== nil`, not `or true`, so an explicit `false` is never overridden).
- New test covers all three starting states: never set, explicitly off, explicitly on.

### 3.12 (2026-07-19) -- Multilanguage system

Added an in-game translation system, matching the six languages this README is already available in.

- New `modules/i18n/Locale.lua`: a translation registry and a live lookup table (`EbonBuilds.L`) keyed by the original English string. A key with no translation for the active locale falls back to the English string itself instead of erroring, so a locale file can be partial without breaking anything.
- Auto-detects the language from the client's own `GetLocale()`, or a saved override via the new `/ebb locale <code>` command (`/ebb locale` alone shows the current language and lists what's available).
- Six translation files under `modules/i18n/locales/`: German, Spanish, French, Polish, Brazilian Portuguese, and Russian. Game-specific terms (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) are kept in English throughout, matching the existing README translations' own convention.
- Polish isn't an actual WoW 3.3.5a client locale, so it's only ever reachable via the `/ebb locale pl` override, the same way `README.pl.md` exists despite there being no Polish game client.
- The build editor's tabs, buttons, and tooltips are wired up as the first translated surface. Everything else still shows English for now -- extending coverage elsewhere is just adding more `EbonBuilds.L[...]` call sites and matching translation entries.
- New tests: fallback behavior, locale switching, alias resolution (`de`, `DE`, `german` all resolve to `deDE`), and a consistency check that every locale file actually defines a translation for every key the build editor looks up -- catches a forgotten translation in any of the six languages, not just whichever one happens to get tested by hand.

### 3.11 (2026-07-18) -- fix: AI report crashed for anyone with real DPS-tracking data

Root cause, confirmed from an actual in-game error report: `EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment` was missing its final `return suggestions` -- it built the table, then fell off the end of the function and returned nil instead. `GenerateAIText` then did `#bonusSuggestions` on that nil and crashed with "attempt to get length of a nil value". Its sibling function, `SuggestFamilyBonusAdjustment` a few lines down, has the identical structure and does return correctly -- this was a copy-paste omission isolated to the one function.

This only triggered once Echo Performance tracking had enough real samples to get past the function's earlier guard clauses (the reporter had 2000 samples), which is also why nothing in testing caught it before: `SuggestFamilyBonusAdjustment` had a regression test, `SuggestQualityBonusAdjustment` never did.

- `modules/automation/EchoPerformance.lua`: added the missing `return suggestions`.
- New test reproduces the exact crash against the unfixed code first (confirmed it fails with the same "attempt to get length of a nil value" the report showed), then verifies the fix returns real per-tier suggestions.

### 3.10 (2026-07-18) -- fix: /ebb errors stayed empty no matter what actually failed

Root cause found for the "AI report does nothing and /ebb errors is empty" report: `EbonBuilds.ErrorLog.Protect`, the wrapper that catches a handler's error and records it, was only ever used in two places in the whole addon (both in `AutoSell.lua`). Every UI button, including this one, ran its `OnClick` completely unwrapped -- so a real Lua error there never reached EbonBuilds' own log at all. It would only ever show up via WoW's own built-in Lua error display, which is off by default. That combination -- something visibly not working, with nothing in `/ebb errors` -- was never actually proof that nothing was failing.

- `modules/ui/BuildTabs.lua`: the "AI report" button's `OnClick` is now wrapped in `EbonBuilds.ErrorLog.Protect`, so a real failure now lands in `/ebb errors` instead of vanishing. (Deferred to button-construction time rather than file scope, since this file loads before `core/ErrorLog.lua` in `EbonBuilds.toc`.)
- New test confirms `ErrorLog.Protect` actually captures a simulated error and keeps its message, closing the gap that let this go unnoticed.
- Still investigating the original click issue itself -- this fix means the next occurrence will actually leave a trace to look at.

### 3.09 (2026-07-18) -- "AI report" button: one test per layer

Added while investigating a bug report that the "AI report" button in the build editor produces nothing and doesn't seem clickable. No root cause confirmed yet (needs `/ebb clicktrace` output to isolate whether the click is even reaching the button in-game), but this closes a real test-coverage gap found along the way: nothing previously exercised this button's own code path end to end.

- `EbonBuilds.ExportImport.GenerateAIText`: verified it doesn't error for a plain build, a build with a conditional Echo policy set, or a nil build, and that the policy section only appears (and names the right Echo) once a policy is actually set.
- `EbonBuilds.ExportImport.ShowAIExportDialog`: verified it doesn't error when assembling the dialog.
- New `EbonBuilds.BuildTabs._TriggerExportAI` / `_SetContextForTest` test hooks (same pattern as `Session.lua`'s test helpers): verified the click handler resolves the build being edited, falls back to the active build outside an edit context, and is a safe no-op with neither -- without needing a simulated real click.
- `Theme.CreateButton` + `ClickTrace`: verified a click still reaches both the caller's own `OnClick` handler and the separate `ClickTrace` hook Theme installs at button creation, confirming `HookScript` handlers survive a later `SetScript` call on the same event (the exact mechanism `exportAIBtn` in `BuildTabs.lua` relies on).
- `modules/ui/BuildTabs.lua`: extracted the button's inline `OnClick` closure into a named local function (`OnClickExportAI`) so it's independently testable -- no behavior change.

### 3.08 (2026-07-18) -- GitHub Releases always include a working download link

- `scripts/publish-github-release.sh` now prepends a pinned `Download EbonBuilds.zip` link to every release it publishes, pointing at `raw/<tag>/dist/EbonBuilds.zip` rather than `raw/main/...` -- so the link always serves the zip that actually matches that release, even after main moves on with later commits.
- Added a guard that refuses to publish if `dist/EbonBuilds.zip` isn't present in the tagged commit, so a release can never go out with a broken download link.

### 3.07 (2026-07-18) -- Publish actual GitHub Releases, not just tags

- Added `scripts/publish-github-release.sh`, which creates a real GitHub Release (the page under `/releases`, with notes) for an already-pushed tag. Pushing a git tag alone only creates a ref — it does not appear as a Release. The script pulls its title and notes directly from the matching `### <version>` section of this file.
- Wired into `scripts/release.sh`'s final output and documented in the README.

### 3.06 (2026-07-18) -- Developer tooling: packaging and local checks

- Added `scripts/build-dist.sh`, which packages `EbonBuilds.toc`, `FAQ.md`, `core/`, and `modules/` into `dist/EbonBuilds.zip`, ready to drop into `Interface/AddOns/`. No addon behavior change; internal tooling only.
- Added `scripts/check.sh`, running the full CI check suite (Lua 5.1 syntax check, test suite, `.toc` file verification) locally in one command.
- Added `scripts/dev-setup.sh` (one-time toolchain install) and `scripts/install-hooks.sh` with a `.githooks/pre-commit` hook that runs `scripts/check.sh` automatically before each commit.
- Added `scripts/release.sh`, a release helper that refuses to run unless `FAQ.md` has changed since the last tag, then bumps the version, runs the check suite, rebuilds `dist/EbonBuilds.zip`, and commits + tags.
- Documented all of the above in the README's Development section.

### 3.05 (2026-07-18) -- Conditional Echo policies

- **New: per-Echo automation policies.** Each Echo can now be set to **Normal**, **Banish on Sight**, **Banish After Pick**, **Ignore After Pick**, or **Never Pick**, giving hard automation enforcement beyond plain weight tuning. Policies apply on top of scoring rather than replacing it, so a weighted Echo can still be force-excluded or force-picked without touching its underlying value.
- Added policy filters and bulk assignment in the Echo table, so a policy can be applied to many rows at once instead of one at a time.
- Policy-driven decisions now record their reason in the Logbook and are included in AI export, so a Banish or Never Pick outcome is traceable after the fact instead of looking like an unexplained skip.
- Improved the Echo table layout for the new controls: long Echo names now wrap into a compact two-line column instead of clipping, the name sort control fills the full header width, quality labels display correctly, and the Max column now shows the final total score rather than the raw weight.

### 3.04 (2026-07-18) -- Logbook tracking, inspector layout, and shared scrolling fixes

- **Fixed: shared content-tree wheel routing was missing in the Build Overview,** which broke mouse-wheel scrolling in the redesigned workspace panels introduced in 2.99. Boundary-safe scrolling is now consistent across all standard content panels and nested controls.
- Logbook now tracks accurate Echo pick progress and rarity per run.
- The Logbook run browser is fixed-height and virtualized, keeping the list responsive for long histories instead of growing unbounded.
- Decision Inspector offer cards now render below the evidence text instead of overlapping it, and resource/charge changes are shown more readably.
- Fixed clipped Logbook search and filter controls, and fixed the collapsed Autopilot view hiding the advanced-controls toggle.
- Fixed legacy session data handling so older logs keep loading correctly under the new tracking.
- Regression tests were added for the above; full suite (52 files, 38+ UI contracts at the time) re-verified passing.

### 3.03 (2026-07-18) -- fix: settings popup (and other windows) missing elements after 3.02

- **Fixed: windows using the new themed checkbox could abort construction midway, leaving everything after the first checkbox missing** -- reported on the global settings popup as "opens, but elements are missing" (sliders present; checkboxes, Save, and Cancel gone), which matches construction stopping exactly at the first `AddCheckbox` call.
- Root cause: 3.02's checkbox toggled its state via a `PreClick` script handler. Whether `PreClick` is a valid script type for plain (non-secure) Buttons under 3.3.5 turned out to be exactly the kind of API detail not worth betting a window's construction on -- if invalid, `SetScript("PreClick", ...)` raises immediately and everything after it in the window-building function never runs.
- Rebuilt the state-toggle mechanism to use only the universally-valid `OnClick` type: the checkbox installs its own toggle as the OnClick handler and overrides `SetScript` so a call site assigning "OnClick" gets chained *after* the internal toggle. The click contract is unchanged and still covered by the 3.02 contract test (call-site handlers read the NEW state, matching `UICheckButtonTemplate`); the test passes against the new implementation.
- Also verified the theme constants the new primitives reference are all declared above their use in Theme.lua -- ruled out as an alternative cause before settling on the script-type explanation.

### 3.02 (2026-07-18) -- the redesign's visual language now covers every window

- **The unified theme from the 2.99 redesign now extends to every remaining window.** The redesign covered the main workspace (Stats, Logbook, build editor) but the standalone windows still used WotLK's native widgets: the round parchment close button on nine windows (Tuning Advisor, Debug Log, Echo Picker, FAQ, Showcase, main window, settings popup, Error Log, Click Trace, EWL export) and the parchment checkbox in five places (four Tuning Advisor toggles, the settings popup helper).
- **Two new Theme primitives, built in the redesign's own conventions**: `Theme.CreateCloseButton` (flat dark X, danger-red hover, same corner position as the native one so muscle memory keeps working) and `Theme.CreateCheckbox` (flat square, gold fill when checked, integrated label that extends the click target).
- **The checkbox reproduces `UICheckButtonTemplate`'s exact click contract**: an OnClick handler set by a call site reads the NEW state, because the toggle fires in PreClick. Getting this ordering wrong would have silently inverted every converted checkbox in the addon -- so it's covered by a dedicated contract test (with a click-simulating widget stub) rather than left to reasoning. The test's execution was proven with a deliberate canary failure before being trusted.
- No behavior changes anywhere: same anchors, same handlers, same GetChecked/SetChecked semantics -- purely the visual layer.

### 3.01 (2026-07-18) -- Manual Training now announces itself instead of looking broken

- **New: a once-per-session toast when Manual Training suppresses automation** ("Automation paused: Manual Training is ON for this build"). Previously this state was totally silent by design -- the code even had a comment explaining why (a toast on every choice screen would nag people deliberately training) -- but total silence made "Training: ON" indistinguishable from a broken addon: a real report came in as "automation doesn't pick anything anymore," and the cause turned out to be the Training toggle having been left on. Once per login is the middle ground: you find out the first time it matters, then it stays quiet.
- The existing "no rule matched, choose manually" toast for genuinely-unmatched offers is unchanged.

### 3.0 (2026-07-18) -- merge: Family Bonus tuning ported in from the parallel 2.59 branch

- This build and a separately-versioned 2.59 branch (see that entry's own changelog for its full history) had diverged after roughly the 2.54-2.58 point and developed independently -- this one toward the Stats/Logbook/EWL/test-suite work below, the other toward Manual Training refinements and a Quality/Family Bonus tuning pair. Comparing the two found exactly one capability present in 2.59 and missing here: **Family Bonus suggestions**, the family counterpart to the Quality Bonus suggestions already in this build.
- Ported `SuggestFamilyBonusAdjustment` in, but rewrote its internals rather than copying verbatim: the original 2.59 version divided DPS by a flat per-echo weight, which predates this build's per-quality-rank weight system (`Weights.GetFromWeights`) and real final-score-based comparison (`Scoring.ScorePerQuality`, matching how Quality Bonus suggestions already work here). Also caught and fixed a missing `None -> "No family"` mapping that would have silently miscategorized any echo whose family list literally contains the string `"None"` as unresolvably ambiguous instead of correctly grouping it with the no-family tier.
- Same sidestep-the-hard-problem philosophy as Quality Bonus: only echoes with exactly one matching family (or explicitly none) are used, since a multi-family echo's score already has several family modifiers stacked onto it at once, and disentangling one family's own marginal contribution from that would need real regression. Multi-family echoes are excluded from the comparison entirely rather than guessed at.
- Shown in Export (AI) right after Quality Bonus suggestions, same format and same experimental/report-only status -- no auto-apply path for either bonus type.
- Verified against this build's real Scoring/Weights pipeline (not a mock): a synthetic dataset with 5 pure-Tank echoes, 5 pure-Caster echoes, and 5 Tank+Caster multi-family echoes with a deliberately extreme DPS value confirmed the multi-family echoes are excluded from both the suggestions and the tier averages, while the two pure tiers are correctly flagged in the right direction. Full existing test suite (52 files, 38 UI contracts) re-verified passing after the change.

### 2.99 (2026-07-18) -- Consolidated UI, analytics, and workflow update

Compared with the uploaded 2.59 build:

- Reorganized the addon into a unified build workspace with clearer editing, navigation, and spacing.
- Rebuilt Stats around Summary, Echoes, Actions, and two Recommendation sections: **Echo priorities** and **Automation logic**.
- Reworked the Logbook with compact run navigation, clearer filters, deterministic sorting, actionable empty states, and a collapsible decision inspector.
- Added per-quality and negative Echo weights, per-Echo protection, faster weight editing, Weighted Missing as the default view, and safer recommendation Apply/Undo/Dismiss workflows.
- Added canonical Echo Wishlist (`EWL1`) export and WoW 3.3.5a Lua 5.1 compatibility safeguards.

### 2.98 (2026-07-17) -- Echo Wish List export
- Added standard `EWL1:<CLASS>:` generation from rank-specific build weights.
- Resolves locked rank aliases to the retained EchoWishlist catalog ID and marks that family with `:1`.
- Exports each remaining weighted Echo family once with `:0`, using the same canonical row that EchoWishlist imports and exports.
- Uses EchoWishlist's saved, unlock-state, quality, and name ordering, with class-compatible catalog filtering.
- Added **Export EWL** to the build Overview and `/ebb ewl` / `/ebb wishlist` commands.
- Added a themed selectable export dialog with entry counts and unresolved-rank warnings.


### 2.97 (2026-07-17) -- Stats performance hotfix
- Reuses the Stats cache when build and analytics data have not changed.
- Builds personal/community DPS and appearance snapshots once instead of rescanning them for every Echo.
- Normalizes analytics store names once per store rather than once per row.
- Reuses Manual Training suggestions across Summary, Echoes, and Recommendations.
- Defers expensive recommendation generation until the Recommendations view is opened.
- Incrementally updates active-session metrics when new Logbook entries are appended.
- Memoizes legacy session-to-build matching so old logs are not repeatedly rescanned.


### 2.96 (2026-07-17) -- Connected Stats and decision-first Logbook
- Replaced the old flat Stats counters with Summary, Echoes, Actions, and Recommendations views.
- Added same-build run comparison, weighted coverage, confidence labels, sortable Echo analytics, and evidence source counts.
- Added direct Stats-to-Logbook navigation for Echoes, actions, and recommendations.
- Rebuilt Logbook rows around the actual decision rather than three equal-width offer cells.
- Added a selected-session summary strip, automatic/manual source filtering, important-only filtering, and level grouping.
- Added one reusable evidence panel with recorded weight, modifier, final-score, threshold, reason, source, and importance flags.
- Added visible-row pooling for long Logbook histories.
- New sessions and decisions record build IDs and levels; Manual Training choices now enter the Logbook as manual decisions.

### 2.95 (2026-07-17) -- Weighted priorities become the default Missing view

- Missing opens with **Weighted priorities** selected.
- An Echo is weighted when at least one supported rank has a non-zero value; negative values count.
- Added **Weighted missing**, **All missing**, and **Learned + missing** view options.
- Added view-specific result counts and useful empty-state explanations.
- Existing build weights and learned-Echo data require no migration.


### 2.94 (2026-07-17) -- Reliable sidebar wheel scrolling and roomier Logbook cards
- Mouse-wheel scrolling now works over every interactive part of a saved-build card, including the class icon, locked Echo icons, active badge, and card surface.
- The Logbook session strip now uses larger three-line cards with clearer padding and a separate Active badge.
- Arrow buttons, wheel input, and the themed horizontal session scrollbar remain synchronized.
- Existing builds and historical logs require no migration.

### 2.92 (2026-07-17) -- Remaining scrollbar and build-name fixes

- Replaced the final legacy sidebar build-list scrollbar with the shared themed scrollbar.
- Replaced the build-description editor's native scrollbar with the shared themed scrollbar.
- Build-card titles now render on the card surface in high-contrast text, while class color remains on the identity stripe and icon.
- Build-list and description scrolling now use explicit ranges, clamping, and mouse-wheel behavior without native template controls.

### 2.91 (2026-07-17) -- Themed scrollbars and layout polish

- Replaced native parchment scrollbars with a shared themed scrollbar across addon pages.
- Cleared native disabled-button textures so Save build keeps the flat addon styling.
- Reworked Autopilot status spacing to prevent subtitle/button overlap.
- Corrected Echo-list maximum scroll range so the final row can be fully revealed.

### 2.89 (2026-07-17) -- Unified workspace redesign

- **New application shell:** fixed top context bar shows current page, active build, class identity, Autopilot state, and unsaved-change state.
- **Reorganized sidebar:** global Explore navigation is separated from a searchable, independently scrolling My Builds library.
- **Consistent page structure:** shared page headers, section labels, filter chips, status badges, metric cards, and empty states.
- **Priorities workflow:** debounced search, removable active-filter chips, keyboard Tab navigation, subtle selected-sort-column emphasis, and calmer protection styling.
- **Predictable editing model:** weights, modifiers, thresholds, protection, and ban rules stay staged until Save. Autopilot continues to use the last saved configuration while edits are pending.
- **Build Overview:** modern flat tabs replace the old parchment tabs, with clearer page-specific context for Overview, Stats, Missing, and Logbook.
- **Logbook:** reusable decision-detail panel shows target, base weight, modifier contribution, final score, threshold, and reason for newly recorded events. Older logs remain readable.
- **Tome Atlas and Public Builds:** clearer page hierarchy, source-confidence labels, standardized empty states, and improved acquisition context.
- **Performance rules preserved:** pooled rows, cached final-score sorting, deferred weight resorting, and no sort/refresh side effect from protection changes.

### 2.88 (2026-07-17) -- Build-name visibility fix

- Fixed the left-side build titles being anchored to a nil local variable during row population.
- Build names now anchor to each row's class icon and stay inside the scroll frame.
- Single-line titles retain a visible height instead of being set to zero.
- Long build names wrap according to the card's actual available width, with active rows reserving room for the **ACTIVE** label.
- No SavedVariables or build-data migration is required.

### 2.87 (2026-07-17) -- Fast weight editing

- Removed the synchronous full Echo-table rebuild that ran after every committed weight edit.
- Score-sorted lists now use one deferred, coalesced re-sort of the already filtered entries.
- Name and quality sorts do not re-sort at all when a weight changes.
- Enter no longer causes the same value to be applied again through the following FocusLost event.
- Unchanged values no longer rewrite SavedVariables or reset scoring caches.
- This prevents active pooled rows from being recycled during their own commit, which could recursively trigger more commits and freeze the client.

### 2.86 (2026-07-17) -- Manual Training and offer analytics merge

- Ported **Manual Training Mode** into the rank-specific 2.85 branch. Manual picks are compared with the addon's scored choice and repeated disagreements become rank-aware suggestions.
- Preserved legacy 2.57 training data. Older family-level signals safely nudge all available ranks rather than replacing the rank table.
- Added local **Echo appearance-rate tracking**, optional class-matched sharing, tooltip display, and **Sync Now** for immediate DPS/appearance batches.
- Added optional **Auto-apply weight suggestions** on top of Continuous auto-tune. DPS and training signals are combined as signed deltas before nested rank values are updated.
- Added experimental four-rank **quality modifier suggestions**. Multiplicative quality modes are skipped because additive nudges would be ambiguous there.
- Extended Export (AI) with appearance rates, rank-aware training suggestions, family-level DPS deltas, and quality-modifier suggestions.
- Added the first-login command showcase and `/ebb showcase`, `/ebb commands`, `/ebb welcome`, and `/ebb cleartraining` commands.
- Kept the modern Priorities, Learned only filter, Protect behavior, negative values, four-rank quality model, and export-v2 compatibility intact.

### 2.85 (2026-07-17) -- Learned Echo filter

- Added a **Learned only** toggle to the Priorities filter bar.
- Learned status matches by discovered spell ID, Echo group, or normalized Echo name.
- Current-run granted Echoes also count as learned for the active view.
- Older server builds use the Echoes spellbook as a fallback.
- If learned data is not ready yet, the filter fails open instead of showing an incorrect empty list.

### 2.70 (2026-07-17) -- Designing for Intent

- **Intent-first workflow:** renamed the build editor stages to Build, Priorities, Modifiers, and Autopilot, with concise guidance describing the decision each stage supports.
- **One-glance context:** the main window now shows the active build and Autopilot state. The Autopilot page summarizes readiness, peak score, average offer, and expected best result before exposing any controls.
- **Excellent defaults:** newly created builds use the Balanced Smart profile (`60 / 95 / 110`, 8% freeze penalty). Existing builds keep their stored model and thresholds without migration changes.
- **Progressive disclosure:** common automation choices are three intent presets plus Banish, Reroll, and Freeze action cards. Classic mode, guard, freeze penalty, family protection, priority bans, and fallback behavior live under Advanced and auto-expand when the build already uses them.
- **Plain-language automation:** every action card shows the effective score cutoff instead of forcing users to infer behavior from a percentage alone.
- **Simpler protection:** replaced the checkbox-style control with one per-Echo **Protect / Protected** button. The underlying saved protection state and compatibility behavior are unchanged.
- **Rank hierarchy:** quality controls and Echo rows now run left-to-right in descending value order: **EPIC, RARE, UNCOMMON, COMMON**. Unsupported higher ranks are no longer presented or referenced.
- **Reduced visual and cognitive noise:** rank, family, and unique-Echo modifiers are grouped by intent; advanced exceptions stay out of the primary workflow; pickers sort higher-quality Echoes first.

### 2.60 (2026-07-17) -- UI/UX accessibility and workflow refresh

- **Visual hierarchy and readability:** replaced translucent, inconsistent surfaces with a shared high-contrast theme, near-opaque windows, clearer cards, stronger selected tabs, consistent spacing, and an explicit primary-action treatment. The main editor is larger and clamped to the screen.
- **Accessible state communication:** active, protected, invalid, focused, success, warning, and disabled states now use text/symbols as well as color. `Protect` rows show a single explicit action button, accent, and plain-language status line.
- **Safer editing:** Echo and bonus fields validate before tab changes or Save. Invalid input receives inline feedback and focus; pooled Echo rows commit or safely restore an active edit before reuse, preventing accidental edits to a different Echo while scrolling.
- **Faster filtering and selection:** Echo filters now include a search placeholder, clear and reset controls, visible result counts, clearer dropdown labels, and larger hit targets. The Echo picker adds rank labels, a result count, empty-state guidance, a clear control, and Enter-to-select-first behavior.
- **More precise automation tuning:** every threshold slider now has a synchronized exact percentage field with whole-number/range validation and a live absolute-score label. Reroll mode names and explanations are clearer.
- **Clearer terminology:** bonus mode controls use `Add` and `Multiply` instead of ambiguous `+` and `x`; build fields, sharing state, settings sections, tooltips, onboarding text, and save feedback were rewritten around user intent.
- **Predictable feedback:** toasts use an opaque card, clearer remaining-charge labels, a visible dismiss hint, and true pause-on-hover behavior rather than restarting their timer.
- Added load-time UI contract assertions for the shared theme, form validators, tab navigation, filter result reporting, and Echo picker APIs.

### 2.50 (2026-07-17) -- per-quality Echo weights, negative values, and per-Echo protection

- **New: separate weight fields for every quality rank an Echo can roll.** Rank columns and labels are derived from the addon's existing quality definitions rather than duplicated in the editor. Unavailable ranks are shown as unavailable instead of presenting a meaningless field. Scoring, peak/EV calculations, automation, overview score previews, session tooltips, AI export, public-build copies, sync, and compact export/import now all read and preserve the matching rank's value.
- **New: signed Echo weights.** The editor now accepts whole numbers from -999999 through 999999, with inline red error state and a tooltip explaining empty, malformed, decimal, or out-of-range input. The old positive and zero behavior is unchanged. Decimal values remain unsupported because the previous implementation only accepted whole numbers.
- **New: per-Echo `Protect` control in Priorities.** It protects every quality of that Echo from explicit ban-list priority, threshold-based automatic banishing, ban-list picker inclusion, and banned-candidate filtering. Enabling it removes existing conflicting ban-list entries; imported malformed conflicts are repaired with protection precedence. The toggle is visible per row, has explanatory hover text, saves through the normal build settings path, and is included in export/import and sync.
- **Migration:** legacy numeric weights are copied to every known quality rank so old builds keep exactly the same effective weight after updating. Partial rank tables use a valid `default` fallback when present and otherwise fill missing/invalid ranks with 0. Legacy numeric-string values and suffix-bearing protection names are repaired defensively.
- **Compatibility:** rank-specific build data uses export format v2. EbonBuilds 2.50 can import old single-weight exports; older clients cannot faithfully represent different values per rank and should be updated before importing or syncing 2.50 builds.
- Added standalone regression coverage for negative/malformed values, legacy migration, independent ranks, protection precedence/protection, and export/import round-trips.

### 2.49 (2026-07-16) -- community DPS sharing (same-class, opt-in, auto-merged)

- **New: "Track + share DPS by echo" (renamed from "Track DPS by echo") now also shares your per-echo DPS averages with other EbonBuilds users of the SAME class over the existing sync channel, and merges what they share back into your own data.** Same single toggle controls both directions. Only aggregate numbers travel (per-echo average DPS + sample count) -- never raw combat logs or session data.
- **Safety measures**, since this merges data from other, untrusted clients automatically:
  - Only merges from a peer whose declared class matches your active build's class (cross-class DPS data would just be noise).
  - Rejects any single peer's claim of more than 500 samples for one echo, and rejects implausible average DPS values -- bounds a malicious or buggy client's ability to skew your data.
  - Idempotent: each peer's contribution is stored keyed by that peer and replaced (not added to) on every message, so a peer re-broadcasting the same numbers repeatedly can't inflate the total -- the merged value is always the sum of each currently-known peer's latest reported numbers, not a running total of every message ever received.
  - Self-broadcasts are ignored.
- Broadcasts a small rotating batch (6 echoes) every 3 minutes rather than one giant message, keeping each transmission short.
- Export (AI) now shows the personal/shared sample split per echo (e.g. "1234 DPS (35, 20 own+15 shared)") and notes where shared numbers come from.
- Verified in isolation: serialize/parse round-trip, legitimate same-class merge, wrong-class rejection, oversized-count rejection, idempotent re-broadcast (no double-counting), and self-broadcast rejection all behave correctly.

### 2.48 (2026-07-16) -- Smart Reroll finally supported in the Tuning Advisor

- **New: a second sample stream (`bestSamples`) records the best offered echo's score for every Smart-mode reroll evaluation, with that evaluation's charge-pacing multiplier divided back out.** Smart Reroll decides based on "best offered vs threshold," not individual echo scores, and the live threshold moves with remaining charges -- the two reasons this was flagged unsupported since 2.33. Dividing pacing back out of each sample makes them comparable to a "what would this look like at full pacing" baseline, which reduces cleanly to the same percentile-suggestion math already used everywhere else.
- `Calibration.SuggestSmartReroll(settings)` and `RecordBestSample()` added; wired into the Tuning Advisor window (replaces the old "not supported" message), Continuous Auto-Tune, and Export (AI).
- Verified in isolation: 300 synthetic evaluations with randomized pacing (0.6-1.0) and a known 45%-below-threshold true distribution -- the suggestion correctly detected the current threshold was under-rejecting (34.7% vs 45% target) and proposed raising it, the right direction.
- The actual live pacing behavior (threshold gets stricter as reroll charges run low) is unchanged -- this only fixes what the Tuning Advisor's *suggestion* is calculated from.

### 2.47 (2026-07-16) -- Echo Performance: switched to "active DPS" (Details!'s Tempo())

- **Improved: DPS sampling now prefers Details!'s "activity time" (`actor:Tempo()`) over "effective time" (`combat:GetCombatTime()`) when available.** Details' own documentation distinguishes the two: effective time is the whole combat window including movement/idle gaps, activity time excludes them. Two runs with identical actual damage output but different amounts of downtime would previously show different DPS for reasons unrelated to which echoes were active -- a real source of noise in a signal that's already documented as approximate. Falls back to effective time if `Tempo()` isn't available on a given Details version, same as before.
- Verified in isolation: with `Tempo()` present, DPS is computed from active time (50000 dmg / 60s active = 833.33, correctly ignoring a 100s total window); without it, correctly falls back to the old calculation (500.00).
- No settings change needed -- this applies automatically to anyone with Echo Performance tracking already enabled.

### 2.46 (2026-07-16) -- weight suggestions: tightened cluster filter (found from real data)

- **Fixed: most weight suggestions were actually contaminated by co-active clusters.** 2.45 trusted clusters up to 3 members, on the assumption that a couple of echoes briefly overlapping was rare. A real Export (AI) dump showed the opposite: cross-referencing the suggestion list against the same export's own cluster NOTE block showed the majority of flagged echoes (Curse of the Plaguebringer/Precision Strike/Steel Brand, Archmage's Mark/Burning Touch, Glass Canon/Resonant Build, Backstabber's Edge/Edict of the Iron Council, Brittle Forging/Contagion, and more) were sharing a signature with at least one other echo -- meaning the "suggestion" was really one data point duplicated across indistinguishable echoes, not independent evidence for any one of them.
- Tightened to require a fully unique DPS+sample-count signature (shared with nobody) before an echo is trusted for a weight suggestion. Re-verified in isolation: a 2-member cluster that would have looked like the most extreme outlier in the set is now correctly excluded entirely, leaving only genuinely distinguishable echoes.
- Expect fewer suggestions per export as a result -- that's the correct behavior. Playing more varied loadouts (per the 2.43 tip) is still what grows the pool of trustworthy, individually-distinguishable data over time.

### 2.45 (2026-07-16) -- weight suggestions from DPS data (Export (AI), read-only)

- **New: `EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)`.** Compares each tracked echo's average DPS against other echoes currently sharing its exact weight value; if one deviates by 25%+ from that tier's average, suggests a modest (±10) weight nudge. Echoes from a co-active cluster larger than 3 (see 2.43) are excluded from both the comparison and the tier baseline, so one inflated/deflated group can't skew the whole tier.
- Deliberately a **read-only report, not auto-applied** like the threshold Tuning Advisor -- weight changes are a bigger, more visible intervention, and this data carries more inherent noise (fight variance, the cluster limitation) than the offer-distribution data thresholds are tuned against. Shown in Export (AI) under a new "Weight suggestions from DPS data" section when Echo Performance tracking is on and there's enough data; the Tuning Advisor window also notes the count when suggestions exist, pointing to Export (AI).
- Verified in isolation with a mock tier containing a clear over-performer, a clear under-performer, two near-average echoes, and a 4-member cluster: the two averages were correctly left unflagged, the outliers correctly flagged with the right nudge direction, and the cluster correctly excluded from both suggestions and the tier baseline entirely.
- Confirmed for anyone wondering: Freeze has been part of Continuous Auto-Tune since 2.35, in both Classic and Smart mode -- no change needed there.

### 2.44 (2026-07-16) -- /ebb debug: no more misleading "guard" value in Smart mode

- **Fixed: the EVAL header always showed a `guard>=X` value, even in Smart (EV) mode -- but Reroll Guard is only ever checked in Classic mode's reroll logic.** Found while reviewing a real Smart-mode debug log: the header displayed a guard threshold that had zero effect on any decision, which could easily read as "guard should have blocked this reroll" when guard was never evaluated for that mode at all. This was purely a debug-log clarity issue -- no automation decisions were affected, since the dead value was never used, only displayed. The guard segment is now only shown in Classic mode's header line.

### 2.43 (2026-07-16) -- Export (AI): flags echoes tracked as an indistinguishable group

- **New: Export (AI) now detects and calls out "co-active clusters."** A real Export (AI) dump showed 11 completely different echoes sharing a byte-identical DPS value and sample count -- concrete proof of the documented limitation (DPS tracking can't isolate one echo's effect when several are active together) actually showing up in practice, in a way that wasn't obvious just from reading the numbers row by row. When two or more echoes share the exact same avg DPS + sample count (meaning every sample was taken while all of them were active together), they're now called out in a NOTE block before the echo table, so it's clear those specific numbers can't be used to compare that group against each other.
- Practical takeaway for anyone using DPS tracking: varying your active loadout across runs (rather than always running the same combo) is what lets individual echoes start showing distinguishable numbers.

### 2.42 (2026-07-16) -- fix: Tuning Advisor's Freeze target was backwards (found from a real Export (AI) dump)

- **Fixed: the Freeze suggestion's target was inverted, aiming to catch 90% of ALL offers instead of the intended top 10%.** A real Export (AI) output showed the tell: "Freeze: currently 73% -> catches ~8% (target ~90%)" -- a limited-charge resource deliberately targeting 90% catch rate makes no sense (it'd burn through charges on almost everything). The comment describing the intent ("catch roughly the top 10%") was correct, but the actual parameter passed (90) produced the opposite given how the percentile math resolves for the "above" direction. Fixed to pass 10, matching the stated intent -- re-verified with the same test data: suggestion now correctly rises toward a strict ~89% of peak (rarely triggers) instead of dropping to a nonsensical ~7%.
- This affected both Classic and Smart mode Freeze suggestions, and by extension anyone using Continuous Auto-Tune (2.35) with Freeze -- it would have been quietly LOWERING the Freeze threshold over time, the opposite of sensible behavior. Banish and Reroll targets were unaffected (their direction didn't have this inversion).
- **Also: Export (AI)'s banned-echo list no longer repeats the same name once per banned quality tier** (e.g. "Arcane Bond, Arcane Bond, Arcane Bond..." for 5 separately-banned quality tiers) -- now shows each name once with a "(x5)" count.

### 2.41 (2026-07-16) -- fix: Settings dialog description text cut off mid-sentence

- **Fixed: the explanation text under Toast Duration, Auto-sell, and Bag Affix Dots in the gear-icon Settings dialog got cut off mid-sentence with no wrap.** Those FontStrings got their wrap width from two anchor points (TOPLEFT + RIGHT-to-scrollChild) instead of an explicit `SetWidth()` -- reliable for stretching plain frames, but it wasn't resolving correctly for text word-wrap width inside this scrollframe's child, so long lines just ran off past where they'd normally wrap and got clipped by the scrollframe. Switched to explicit widths (same fix pattern already used for the Tuning Advisor's row text). Also pre-emptively applied the same fix to the Tuning Advisor's own subtitle text, which used the identical risky pattern even though it hadn't been reported as broken yet.

### 2.40 (2026-07-16) -- Echo Performance: real DPS tracking via Details!

- **New: `EbonBuilds.EchoPerformance` module.** Opt-in (off by default, new checkbox in `/ebb tuning`), requires the Details! damage meter addon. Samples current DPS every 10s in combat via Details' documented public API (`Details:GetCurrentCombat()`, `combat:GetActor()`, `actor.total`, `combat:GetCombatTime()`) and credits it to every currently-active echo (`ProjectEbonhold.PerkService.GetGrantedPerks()`), building a running average per echo, persisted per character.
- Everything touching Details! is pcall-wrapped and feature-detected -- it's a large, independently-updated third-party addon; a missing/changed API on its end degrades to "no sample" rather than an error.
- Surfaced in Export (AI): each echo line gets an "avg DPS while active (samples)" column when tracking is on and data exists, with an explicit note in the export itself that this is a rough signal, not a controlled measurement.
- Verified in isolation: DPS math correct (50000 damage / 100s = 500 DPS credited to all active echoes), default-disabled confirmed, missing-Details and no-data cases both degrade safely instead of erroring.

### 2.39 (2026-07-16) -- Export (AI): full class-eligible echo list with real effect descriptions

- **Changed: Export (AI) now lists every echo available to the build's class, not just the ones with a configured weight.** Reuses `EchoTableRows.BuildBestByName()` -- the exact same class-mask filtering and name-grouping the Echo Weights tab itself uses -- so the export is guaranteed consistent with what's on screen. Each line: name, current weight (0 if unweighted), quality, family/families, and the actual effect text (via the live spell tooltip where the client has it cached, collapsed to one line and capped at 160 characters; otherwise a note that it needs to be hovered once in-game to cache).
- Lets an external AI actually reason about *why* an echo might be worth weighting instead of only seeing bare names and numbers -- verified in isolation with a mixed-class dataset that class filtering, description formatting, and the no-description fallback all work correctly.

### 2.38 (2026-07-16) -- Export (AI): plain-text settings dump for external analysis

- **New: "Export (AI)" button** next to the existing Export button on the build edit screen. Produces a readable plain-text export (not the compact Base64 sync format) covering quality/family/novelty bonuses, automation thresholds (labeled per Classic/Smart mode), locked echoes, banned echoes, all configured echo weights, and Tuning Advisor data if any has been collected -- everything needed for an external AI to reason about the build's tuning.
- New `EbonBuilds.ExportImport.GenerateAIText(build)`, verified against a mock build in isolation (including a real bug catch: a literal `%` in a no-args text line wasn't escaping correctly, fixed before release).

### 2.37 (2026-07-16) -- Reroll Guard now paced too (found via a real debug log)

- **Fixed: the Reroll Guard threshold was static, unlike everything else 2.36 paced.** A real `/ebb debug` log showed the exact cost: at R:2 remaining, a 140/205 "Grim Resolve" (weighted, w=100) got rerolled away because the offer's *sum* was low, even though 140 alone easily beats "pretty good" -- the guard (blocks reroll if any single echo is >= 90% of peak) didn't fire because 140 < 184.5 (the static 90% mark). Same thing happened again two picks later with a 140-score "Tunnel Vision." All 3 rerolls were gone within ~10 seconds, leaving nothing for the rest of the run.
- The guard threshold now uses the same charge-pacing curve as the rest of Classic Reroll: with plenty of charges, only a near-perfect echo blocks a reroll; with few left, a merely-good one does too. Verified against the exact log scenario: at R:2, the new guard threshold is ~129 (140 blocks); at R:1, it's ~120 (140 still blocks). Both real rerolls from the log would have been prevented.
- `/ebb debug`'s EVAL header now shows the guard's actual pacing-adjusted value too.

### 2.36 (2026-07-16) -- whole-run budget pacing for Banish, Freeze, and Classic Reroll

- **New: `ChargePacing()`**, a shared helper generalizing Smart Reroll's existing charge-pacing curve (get pickier as charges run low) to Banish and Freeze in both modes, and to Classic Reroll (which previously had no pacing at all -- a real gap versus Smart mode). Banish/Reroll get stricter (lower threshold) as charges deplete; Freeze gets stricter (higher threshold) the same way, since it triggers in the opposite direction (above, not below).
- Per-lever tuning: Banish uses a comfort cap of 8 charges scaling down to 70% strictness; Reroll uses the existing 8-charge/60% curve; Freeze uses a 6-charge cap scaling up to 140% strictness.
- `/ebb debug`'s EVAL header now shows the actual pacing-adjusted threshold and multiplier for all three levers, not the un-paced base value.
- Verified in isolation: pacing curve produces the expected 0.6-1.0 (below) / 1.0-1.4 (above) range across the charge spectrum, with safe (non-negative-charge) edge-case handling.
- Known limitation documented: Tuning Advisor's rejection/catch-rate figures are computed against the base threshold, not pacing-weighted -- still directionally useful, not perfectly exact.

### 2.35 (2026-07-16) -- Tuning Advisor: continuous auto-tune (opt-in)

- **New: "Continuous auto-tune" checkbox in `/ebb tuning`.** Off by default. When on, Banish/Freeze (and Reroll in Classic mode) thresholds nudge themselves toward their suggested value automatically -- a gradual step (25% of the gap) every ~20 newly-recorded offers, not an instant jump to the suggestion. You get a toast every time it actually changes something (e.g. "Auto-tuned: Banish 22%, Freeze 15%"), consolidated into one message per pass rather than one per metric.
- Deliberately rate-limited and gradual: verified via simulation that it converges smoothly toward a stable value without oscillating, even starting from thresholds far off from the real distribution (tested from Banish 10% -> stabilized around 22-28%, Freeze 95% -> ~15-16%, Reroll 90% -> ~57-58%, over ~400 samples).
- Smart Reroll still isn't tuned (same pacing-factor limitation as the manual suggestion).

### 2.34 (2026-07-16) -- Tuning Advisor: Smart (EV) mode support

- **New: Tuning Advisor now works with Smart (EV) mode**, not just Classic. Smart mode's `banishEVPct`/`freezeEVPct` are a % of mean/evBest3 rather than peak -- added a conversion through the current mean/peak and evBest3/peak ratios (from the live scoring model) so Smart-mode thresholds can be analyzed against the same peak-relative sample data as Classic mode. Verified by cross-check: a Classic and a Smart suggestion targeting the same percentile converge on the same real (peak-relative) threshold.
- **New: Freeze row** (both modes) -- previously only Banish/Reroll were covered.
- Smart Reroll remains explicitly unsupported, with the window explaining why (dynamic pacing factor, no single static value to suggest) instead of just hiding the row.

### 2.33 (2026-07-16) -- Tuning Advisor: self-calibrating thresholds

- **New: `/ebb tuning`.** Records the score (% of peak) of every echo automation evaluates into a persistent per-character sample buffer (always-on, independent of debug capture), then suggests Banish/Reroll threshold values based on the REAL observed distribution instead of only the theoretical scoring model -- "your current 25% Banish threshold rejects about 15% of what you're actually offered; here's what 20% would target instead," with one-click Apply. Classic threshold mode only for now (Smart/EV mode uses a different baseline).
- New module `EbonBuilds.Calibration` (`modules/automation/Calibration.lua`).

### 2.32 (2026-07-16) -- Tome Atlas: authoritative tome detection, no more name-guessing

- **Fixed: ordinary stat scrolls like "Scroll of Agility" showed up in Tome Atlas alongside real echo tomes.** The 2.20 filter checked item *names* against a prefix list ("tome of", "scroll of", "libram of", ...) -- correct for real tome-teaching scrolls, but it also matched ordinary WoW consumables that happen to share the same naming convention and aren't tomes at all.
- **New: `TomeAtlas.IsTomeItemId(itemId)`** checks against the actual authoritative source instead -- `ProjectEbonhold.PerkDatabase`, where every tome-gated echo's `requiredSpell` field IS that tome's item ID (the same `tomeItemId == requiredSpellId` relationship ProjectEbonhold's own tooltip code relies on, found during the 2.26 API audit). `RecordDrop`, `Merge`, `List`, `ListZones`, `ListByZone`, `ListByMob`, and `SerializeAll` all use this now via a shared `IsTome(itemId, name)` that prefers the itemId check and only falls back to the old name heuristic if no itemId is available.
- Existing bad entries are cleaned up automatically by the same `List()` backstop pattern as the 2.20 fix -- no migration needed, they just stop showing up.

### 2.31 (2026-07-16) -- Tome Atlas: custom zone picker replaces the native dropdown

- **Changed: the Zone filter is a themed, scrollable, searchable popup now instead of the native Blizzard dropdown.** With 50+ known zones, the old `UIDropDownMenuTemplate` list ran unstyled and unbounded straight off the top/bottom of the screen with no way to scroll or search -- and it visually clashed with the rest of the dark theme. The new picker is height-capped (scrolls instead of overflowing), has a quick-filter search box, and matches the addon's own panel styling. Auto-closes when the view is hidden (tab switch or closing the window) so it can't get left floating on screen.

### 2.30 (2026-07-16) -- fix: long tome names visually overlapping the row below

- **Fixed: an unusually long tome (or mob/zone) name wrapped to a second line, colliding with the source text underneath it.** Rows are a fixed height and the title FontString had word-wrap enabled by default -- a long enough name (e.g. "Libram of Saints Departed of Arcane Mind IV") wrapped, and the wrapped second line drew right on top of the source/drop-location text below, which looked like a completely different, garbled entry mixed in. Title and source text are both single-line now (word wrap disabled); this was a rendering bug, not actually a non-tome item slipping through the 2.20 filter.

### 2.29 (2026-07-16) -- your own public builds now show in Public Builds

- **Changed: Public Builds no longer hides your own public builds.** Previously excluded entirely (redundant with the sidebar, but also meant no way to visually confirm a build actually published). Now shown, tagged "(You)" next to the author name, with the Import button disabled and labeled "Yours" instead of offering a nonsensical self-import.
- If your build still doesn't appear: check whether it's actually still `isPublic` -- see 2.18's title-collision guard, which auto-unpublishes (with a popup) a build whose exact title is already public under a different author.

### 2.28 (2026-07-16) -- fix: Group: Tome showed nothing (Zone/Mob worked fine)

- **Found via `/ebb errors`: `attempt to call global 'SourceText' (a nil value)`.** `SourceText()` was defined further down the file than `BuildTomeItems()`, its only caller -- a Lua local-function forward-reference bug (the same class of issue fixed in Build.lua back in 2.18). Since Group: Zone and Group: Mob don't use `SourceText()`, they worked fine while Group: Tome silently errored on every render (caught by 2.27's new pcall wrapper, which is exactly how this got diagnosed instead of just leaving the window permanently blank). Moved `SourceText()` above `BuildTomeItems()`.
- Thanks for grabbing the `/ebb errors` output -- that's exactly what pinned this down in one shot instead of more guessing.

### 2.27 (2026-07-16) -- hotfix: Tome Atlas / Public Builds could stay permanently blank

- **Fixed: an error anywhere in the 2.26 owned-echo detection could leave Tome Atlas or Public Builds permanently blank with no visible error.** Both views called `viewFrame:Show()` *after* `Render()` -- if Render() (which now calls the new `GetOwnedEchoSets` path) threw for any reason, that line was never reached, so the window frame itself never became visible. Most players have Lua script errors disabled by default, so this showed as "window stays empty" with nothing to go on. Render() is now pcall-wrapped everywhere it's called from these two views -- the window always becomes visible now, and if something did go wrong, it's recorded to `/ebb errors` instead of failing silently.
- If Tome Atlas was blank for you before this update: please try again, and if it's still blank, check `/ebb errors` and share what it says -- that'll point straight at the real cause.

### 2.26 (2026-07-16) -- ProjectEbonhold API audit: reliable echo detection + Apply to Character

Reviewed the full ProjectEbonhold and ProjectEbonhold Enhanced addon source (both current builds) for API EbonBuilds wasn't using yet.

- **New: `ProjectEbonhold.PerkService.GetDiscoveredEchoes()` is now the preferred source for "what have I learned."** Both the Missing tab (`ComputeMissingEchoes`) and Tome Atlas (`TomeAtlasView.BuildOwnedSet`) had their own independent, near-duplicate spellbook-tab-scanning implementations, matching by normalized spell name and requiring the "Echoes" spellbook tab to exist (hence the retry-with-timeout dance). Consolidated into one shared helper, `EbonBuilds.BuildOverview.GetOwnedEchoSets()`, that prefers the authoritative, spellId-keyed, SavedVariables-cached `GetDiscoveredEchoes()` API -- available immediately, no waiting, no name-matching guesswork -- and falls back to the old spellbook scan automatically if that API isn't present (older server builds). Fixes both the duplicate code and the "0 learned" reliability concerns raised earlier.
- **New: "Apply to Character" button (Build Overview).** Uses `ProjectEbonhold.PerkService.SetActiveEchoLoadout()` -- also present in both server variants -- to push this build's locked echoes to the server as your active loadout, so the game's own echo-selection screen highlights matching picks directly. Gracefully tells you if the server doesn't support it instead of failing silently.

### 2.25 (2026-07-16) -- Missing tab: manual Refresh button

- **New: Refresh button on the Missing tab**, next to Show: All/Missing only. Forces an immediate spellbook re-scan instead of relying on the automatic retry (which polls every 1.5s for up to 15s then gives up) or having to leave and re-enter the tab.

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
- All changes persist immediately when editing an existing build (sliders on release, reset, model, family protection, priority ban list) — fixes "reset did nothing"
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
