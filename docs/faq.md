# FAQ

<p class="ebb-lead">
Detailed, searchable explanations of every EbonBuilds feature.
Updated with each release (currently <strong>3.86.1</strong>) — also available in-game via
<strong>Settings → Windows &amp; Tools</strong>.
See the <a href="changelog.md">Changelog</a>, <a href="releases.md">Releases</a> page, or
<a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases">GitHub releases</a>
for version history.
</p>

Jump to a category: [Getting Started](#getting-started) · [Automation & Decision Models](#automation-decision-models) · [Stats, Logbook & Missing Tab](#stats-logbook-missing-tab) · [Tome Atlas](#tome-atlas) · [Affixes & Character](#affixes-character) · [Sync, Sharing & Public Builds](#sync-sharing-public-builds) · [Settings, Diagnostics & Troubleshooting](#settings-diagnostics-troubleshooting)

## Getting Started
The basics -- reading the UI and getting help.

### How does the grouped Echo priority selector work?
Build Wizard Step 3 now separates Echoes into functional groups instead of showing one oversized list. The left navigation includes Recommended, Included, Modified, build-changing, Damage, Survival, Resources, Control, Utility, Equipment, Other, and diagnostic views. Search defaults to **All groups**, while the active group and subgroup remain available for focused browsing.

Each Echo has an independent **Priority** and **Use** control. Enabling Use on a Neutral Echo assigns the Useful preset automatically, giving it a real positive weight. Disabling Use always resets the Echo to **Neutral +0**. Selecting **Avoid** is policy-only: its weight remains 0 and the build receives the canonical **Never Pick** policy for that Echo. Priority rows are virtualized and recycled, preserving smooth scrolling and consistent visual state.

### How do I generate an Echo Wish List (EWL)?
Open the build's **Overview** and click **Export EWL** (also available in Settings under Build for the active build). The addon creates a standard `EWL1:<CLASS>:` import string.

EWL export mirrors the EchoWishlist addon's catalog rules. A configured locked Echo marks its **catalog family** as saved with `:1`; it does not force that particular quality-rank spell ID. For example, a locked `200745` variant can correctly export as the family's retained EWL ID `200744`.

Each remaining Echo family with at least one non-zero rank weight is exported once with `:0`. Quality and class aliases are merged into the same player-facing Echo row, preventing duplicate rank IDs. When EchoWishlist is installed, its live catalog is used directly; otherwise EbonBuilds builds a compatible catalog from Project Ebonhold data.

Rows use EchoWishlist's ordering: saved first, then currently tome-locked rows, quality descending, and name ascending. The dialog warns when a weighted family cannot be matched to a class-compatible catalog row.

The EWL format stores the spell ID and locked status only; it does **not** carry the numeric EbonBuilds weight itself.

### What do the colors mean?
Standard WoW rarity colors everywhere: purple Epic, blue Rare, green Uncommon, and white Common — shown in descending value order across Echo editors, pickers, logs, and locked-Echo rings. Class colors follow the standard palette.

### How do I know a Settings toggle actually saved?
As of 2.24, clicking Save in the gear-icon Settings dialog shows a toast confirming what was saved (e.g. "Settings saved (Auto-sell ON, Bag dots OFF)") -- previously it just closed the popup with no feedback at all.

### How do I report a problem so it can actually be fixed?
1. the Debug log (Settings, Windows & Tools) — turns on decision tracing (confirmation in chat)
2. Play until the problem happens
3. Settings — opens a window with the full trace, pre-selected: Ctrl+C and paste it in your report

The log shows the peak, every threshold as an absolute number, every offered echo with score/weight/frozen state, and the reason behind every action or non-action. It's plain text, capped at the last 500 lines, and costs nothing while disabled.

## Automation & Decision Models
How Autopilot decides, and how to tune it.

### What is Manual Training Mode?
Enable **Training** from the active build overview. While it is on, Autopilot yields to the native Echo picker and EbonBuilds observes what you choose. When your manual choice repeatedly disagrees with the current scoring, the addon produces a rank-specific raise or lower suggestion. Clear the active build's training history in Settings under Build.

### Does running a build on Autopilot train its values, or do I need Training Mode?
Autopilot never changes your weights by itself. Running the same build on Autopilot only *executes* the values you configured and *collects evidence* along the way (offer samples for the Tuning Advisor, action statistics, optional DPS data). Turning that evidence into changed values always goes through an explicit, reviewable step:

- **Manual Training Mode** learns from your *manual* picks: while Training is on, Autopilot yields and the addon compares what you chose against what it would have scored, then proposes rank-specific raises or lowers.
- **Tuning proposals and the Tuning Advisor** turn collected evidence into suggestions with a visible Apply button — nothing is written to the build until you apply it.

So no: autopiloting a build does not silently train it. Use Training Mode when you want the addon to learn from your own choices, or review the advisor's proposals when you want evidence-based adjustments.

**Autopilot vs Training at a glance:** only one can act on a choice screen. With **Autopilot ON** and **Training OFF**, EbonBuilds picks for you. With **Training ON**, Autopilot steps aside and you pick manually while the addon learns from your choices — a once-per-session toast reminds you the first time it happens. They are not two ways to train the same thing: Autopilot executes your saved weights; Training proposes weight changes from your manual picks.

### What do automatic tuning proposals do?
**Prepare tuning proposals** is off by default. It periodically stages a small evidence-based proposal, but never changes the live build by itself. Review the current evidence and use the visible Apply controls deliberately. Rank-specific Manual Training evidence remains separate from family-level DPS evidence, and conflicting signals are combined rather than silently overwriting one another.

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

### What is Smart mode, and how is it different from Classic?
Choose under **Settings -> Advanced controls -> Decision model**. Smart is recommended and is what new builds start on; Classic is the older model, kept only for builds already tuned around it.

**The core difference:** Classic compares an offer against a single fixed number -- the highest score your build could ever roll ("peak"). Smart instead compares an offer against what you'd realistically get if you *didn't* act -- the average of your other options right now, or the expected best of a future reroll/screen. A build's peak only happens under a rare, near-perfect roll, so under Classic, thresholds tuned as a percentage of it end up meaning different things depending how close to that ceiling the current offer already is. Smart's comparison point moves with the actual situation instead of staying fixed, so a threshold behaves the same way whether the run has been lucky or unlucky so far.

**Worked example:** say your build's peak score is 200. An offer scores 105.
- *Classic* asks: is 105 a high enough percentage of 200 (52%)? If your select threshold is 50%, this barely clears it -- looks marginal.
- *Smart* asks instead: is 105 better than what you'd expect from rerolling or waiting (say, an average reroll nets ~65)? 105 beats that comfortably, so Smart is confident selecting it, even though the same offer looked borderline against the fixed peak.

In short: Classic asks "how close to perfect is this?", Smart asks "is this better than my realistic alternative right now?" -- which is closer to the actual decision being made.

### My weighted class-specific echoes were ignored by automation. Fixed?
Yes (2.0). Weights are stored under the database name (e.g. *"Warrior - Voidsteel Bulwark"*), but automation looked them up under the in-game spell name (*"Voidsteel Bulwark"*) — so class-prefixed echoes silently scored with weight 0. All lookups now go through one canonical name function, and a regression test pins it.

### Automation froze an echo and then immediately picked it. Fixed?
Yes (2.0). Selecting now excludes echoes frozen this round — the whole point of spending the freeze charge is to take something else on this screen and collect the frozen echo later. Carried echoes from previous screens remain selectable, as intended.

### Tuning Advisor: self-calibrating thresholds (2.33, Smart mode support in 2.34)
Settings opens a window comparing your Banish/Reroll/Freeze thresholds against what your build has actually been offered, not just the theoretical scoring model. EbonBuilds records the score (as % of peak) of every echo automation evaluates, always-on and lightweight, into a per-character sample buffer. Once it has at least 30 samples, the advisor computes what threshold your CURRENT setting actually corresponds to (e.g. "rejects ~13% of real offers") and suggests a value to hit a sensible target (~15% for Banish, ~45% for Reroll, ~10% for Freeze), with an Apply button that writes it straight to your active build.

Works with **both Classic and Smart (EV) mode**, covering Banish, Reroll, and Freeze in both. Smart mode's fields are a % of mean/evBest3/EV rather than peak directly -- the advisor converts through the current mean/peak, evBest3/peak, or EV/peak ratio so both modes analyze against comparable underlying data (cross-checked: a Classic and a Smart suggestion targeting the same percentile land on the same real threshold). Smart Reroll's suggestion (2.48) uses its own sample stream with each evaluation's charge-pacing multiplier divided back out, since its live threshold moves with remaining charges -- the same pacing behavior as before, just now something the advisor can actually analyze. "Clear Collected Data" is worth using after a major reweight, since old samples reflect the previous weighting.

### Whole-run budget pacing (2.36)
Automation now spends its Banish/Reroll/Freeze charges with the REST OF THE RUN in mind, not just the current offer in isolation. Smart Reroll already did this (get pickier as reroll charges run low); as of 2.36, Banish, Freeze, and Classic Reroll all get the same treatment:

- **Banish**: with plenty of charges left, banishes anything below the usual threshold; with few left, only banishes clearly-bad echoes, so the last few aren't burned early on borderline picks.
- **Reroll** (Classic mode, previously had no pacing at all): same idea -- pickier as charges run low.
- **Freeze**: with plenty of charges left, freezes anything above the usual threshold; with few left, only freezes genuinely excellent finds.

All three use the same shared curve (`ChargePacing`), just with per-lever comfort caps and conservativeness. the Debug log (Settings, Windows & Tools) now also shows the pacing multiplier actually applied to each threshold in the EVAL header, for troubleshooting.

Known limitation: the Tuning Advisor's "current threshold rejects/catches X%" figure is computed against the *base* (unpaced) threshold value -- it's still a useful approximation, but not perfectly exact now that the real applied threshold shifts with remaining charges throughout a run.

### Why are there 6 locked-echo slots now?
The addon supports 6 locked slots everywhere (wizard, editor, overview, sync, export/import). Note: whether the **server** honors a 6th lock is a Project Ebonhold question — the addon side is ready.

## Stats, Logbook & Missing Tab
Tracking what happened and what you're still missing.

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

### What are Echo appearance rates?
EbonBuilds records how often each Echo family appears on a choice screen. Local recording is automatic and lightweight. **Share echo appearance rates** in the Tuning Advisor (Settings, Windows & Tools) is a separate opt-in control that exchanges aggregate, class-matched counts with other users. Appearance data is shown in Echo icon tooltips and Export (AI). **Sync Now** sends a few enabled DPS and/or appearance batches immediately instead of waiting for the periodic broadcast.

### The Missing tab showed duplicates / owned echoes as missing. Fixed?
Yes (2.0): quality-tier grouping works now (one entry per echo line, owning any tier removes the line from Missing), the list no longer empties after every level-1 reset, and an empty spellbook at login shows "Requesting data..." instead of listing everything as missing.

### The Missing tab said "Requesting data..." forever. Fixed?
Yes (2.9). The tab reads your spellbook's "Echoes" category to know what you own -- but that category only exists once you've learned at least one echo, so a fresh character (or one who just reset) has no such tab, and the check used to wait for something that would never arrive. It now retries automatically every 1.5s, and after 15 seconds gives up waiting and shows the full list anyway. If that fallback triggers, it's logged in Settings for reference.

### The Missing tab only showed what I don't have. Now what? (2.19)
The Missing tab now works like the Affixes tab: a green or red dot on each icon shows learned vs. not-learned status, and a **Show: All / Show: Missing only** toggle switches between "everything for my class" and the classic missing-only view. Owned echoes show "Learned" in green where the drop source used to be; missing ones are unchanged (drop source, score). A count label at the top reads "X learned, Y missing" (or just "Y missing" when the filter is on).

### The Missing tab has no way to re-check what I've learned. New?
Fixed (2.25): a **Refresh** button next to Show: All/Missing only. Unlike Affixes' Refresh (which asks the server), this one is a local spellbook re-scan -- Echoes come straight from your own client's spellbook, no server round-trip needed. Previously the only way to force a re-check was leaving the tab and coming back.

If the tab says "0 learned" and that looks wrong: the count only reflects what your current character's spellbook "Echoes" category actually contains right now. A fresh character (or one who just reset) legitimately shows 0 until the server grants that category. Try Refresh first; if it's still 0 after you know you've picked up an echo, that's worth a bug report (`the Error log (Settings, Windows & Tools)`).

### Why is "learned" detection more reliable now? (2.26)
The Missing tab and Tome Atlas both used to determine what you've learned by scanning your spellbook's "Echoes" tab -- it works, but needs the tab to actually be populated (hence the old retry-and-wait behavior) and matches by spell name. As of 2.26 both now prefer `ProjectEbonhold.PerkService.GetDiscoveredEchoes()`, an authoritative, spellId-keyed list backed by a SavedVariables cache -- available instantly, no waiting. The spellbook scan is kept as an automatic fallback for servers without that API.

### New: Apply to Character (2.26)
Build Overview has a new **Apply to Character** button. It sends this build's locked echoes to the server's native Active Echo Loadout (`ProjectEbonhold.PerkService.SetActiveEchoLoadout`) -- the game's own echo-pick screen then highlights choices that match, directly in-game, without needing to alt-tab to EbonBuilds while picking. Needs at least one locked echo in the build; works on both ProjectEbonhold and ProjectEbonhold Enhanced.

### Track DPS by echo (2.40) -- needs Details!
The Tuning Advisor has a second checkbox: **Track DPS by echo** (opt-in per character since 3.23), requires the Details! damage meter addon. When on, every 10 seconds while you're in combat it samples your current DPS (via Details' documented public API) and credits it to every echo you currently have active. Over time this builds a rough real-performance average per echo -- shown in Export (AI) alongside the theoretical scoring once you've collected some data.

This is deliberately approximate, not a controlled measurement: echoes stack together and fight difficulty/duration/execution vary a lot run to run, so it can't isolate any single echo's true causal effect. Treat it as a rough supplementary signal to combine with the scoring model and Tuning Advisor data, not a replacement for either. If Details! isn't installed, the checkbox tells you and won't enable.

## Tome Atlas

### How do I turn off the tome map integration -- or just the zone list panel?
Two switches in Settings under Addon-wide features. **Tome Atlas map integration** is the master: it controls everything on the world map at once -- the green continent highlights, the "Tomes in this zone" list, pins, and legends. **Zone tome list on the world map** controls only the list panel, per character; the panel's own X button unchecks it, and re-checking it in Settings brings the panel back.

If disabling felt like it "only worked half way" before 3.75: closing the zone panel (X or toggle) intentionally leaves the continent highlights alone -- they belong to the master switch -- but the Settings checkbox to bring the panel back had gone missing in the 3.70 settings rework, so the X was a one-way door. Fixed: the checkbox is back, and both switches apply immediately while the map is open.

Finding where to farm the tomes you don't have yet.


**Draw-pool toggles and permanent locks (3.85, #68 / #62):** On level-1 characters, Tome Atlas rows show draw-pool state; right-click toggles via `ToggleTomeEcho` / `IsTomeEchoDisabled`. Build Overview shows permanent locks from `GetLockedPerks` / `GetMaximumPermanentEchoes` with `LockPerk` / unlock gestures. **Snapshot Run** uses `SnapshotCurrentEchoes` when ProjectEbonhold exposes it.
### How does the Tome Atlas work? (new in 2.2)
An AtlasLoot-style **community drop database** for echo tomes. When you loot a tome, the addon records the mob and zone automatically and shares the observation with other EbonBuilds users (over the sync channel and guild). Data from other players arrives live as drops happen and whenever anyone syncs (Public Builds > Reload). Duplicate reports merge via max-count, so nothing ever double-counts.

**Using it:** open via the *Tome Atlas* button in the left panel. Search by tome, mob, or zone. Toggle *"Show: Missing only"* to hide everything you already collected (matched against your Echoes spellbook — any quality tier counts as collected). The `(x3)` behind a source shows how often the community saw that drop.

**For new players:** filter to *Missing only* and farm the zones with the most entries — that's your collection route.

### Where should I farm for missing tomes? (new in 2.4)
The Tome Atlas now shows a **"Best farming"** line ranking zones by how many of *your* missing tomes have known sources there. Filter, fly, farm.

### My Tome Atlas contributions never seemed to reach anyone. Fixed?
Yes (2.5). If you had zero public builds, the sync responder returned before ever reaching the tome-sharing step -- your drop observations never went out. Fixed, and the Tome Atlas view now has its own **Sync** button next to the filter, so refreshing atlas data no longer requires a detour through Public Builds.

### The Tome Atlas search box and buttons overlapped. Fixed?
Yes (2.6). The search row and the count/filter/sync row now anchor to a single reference frame instead of independent fixed offsets, so they can't drift into each other again. The search box also has real placeholder text now ("Search tome, mob, or zone...").

### Can I see the full drop list for a tome, not just the top 3?
Yes (2.6). Hover any tome row: the tooltip shows the item itself (icon, quality) plus every known source, not just the three shown inline.

### Tome Atlas: category system and non-tome items (new in 2.20)
Two changes:

1. **Non-tome items could show up in the Atlas.** Local loot was always filtered to actual tomes before recording, but data arriving from *other players* via sync went straight in unvalidated -- a bug on a peer's end could inject any item into everyone's Atlas. Both the write path (`Merge`, the network-received one) and the read path (`List`, so anything already-stored gets cleaned up immediately too) now check the item name is actually a tome.
2. **New: Group by Tome / Zone / Mob**, plus a Zone filter dropdown. "By Tome" is the classic view (one row per tome, its sources). "By Zone" shows one row per zone with every tome known to drop there. "By Mob" shows one row per mob with everything it drops. The zone dropdown narrows any of the three views to a single zone. Search still matches tome, mob, or zone text in every mode.

## Affixes & Character
Gear affixes and the visual Character tab.

### What are Affixes, and how is that different from Echoes?
Project Ebonhold has two separate progression systems. **Echoes** are the run-based perks EbonBuilds has always been about. **Affixes** are a permanent, character-bound unlock applied to gear (weapon procs, armor stats) -- a different system entirely, previously only visible through third-party tooltip-scanning tools. EbonBuilds now reads it directly from the server's own data feed, so there's no guessing involved.

### How do I use the Affixes tab? (new in 2.7)
Open via the **Affixes** button in the left panel or the Affixes reference (Settings, Windows & Tools). Every known affix is listed with a green dot (learned) or red dot (missing). Search by name, toggle *"Show: Missing only"*, and hover any entry for its full tooltip, weapon/armor restriction, apply cost, and use count. Press **Refresh** to request an updated list from the server (throttled to avoid spamming it).

### How does Auctionator integration work? (optional)
EbonBuilds optionally integrates with **Auctionator 2.6.3** (WotLK / Interface 30300) when you install it alongside EbonBuilds. The repo ships a vendored copy under `vendor/Auctionator/` (also packaged as `dist/Auctionator.zip` on release builds). EbonBuilds declares `## OptionalDeps: Auctionator` so the client loads Auctionator first when present; without it, every price/search feature soft-fails and the rest of EbonBuilds is unchanged.

When Auctionator is installed and you have scan data:

- **Affixes tab:** missing rows show an **AH** button that opens Auctionator's Buy tab and searches for gear `of <Affix Name>`. **Sync AH list** rebuilds an Auctionator shopping list named **EbonBuilds Affixes** with one search term per missing affix. Tooltips show Auctionator's affix-line price when available.
- **Item tooltips:** gear hovers include an Auctionator buyout line (exact item name, falling back to the affix line).
- **Bag affix dots:** a gold dot marks bag gear carrying a missing affix when Auctionator has a buyout price at or below that affix's apply cost (cheap learn/extract fodder).

Affixes themselves are learned by extracting corrupted gear (ProjectEbonhold's Extraction UI) or buying pre-affixed gear on the AH -- EbonBuilds does not replace either workflow; it only surfaces prices and pre-fills Auctionator searches. Open the Auction House before using **AH** / **Sync AH list** if you are not already there.

### How does the visual Character tab work?
The build editor's **Character** tab has three focused views:

- **Overview** summarizes the build's stored talent distribution, snapshotted equipment, capture identity/time, and glyph coverage.
- **Talents** renders the stored snapshot as one compact WotLK-proportioned tier-and-column tree at a time with spell icons, rank badges, and captured prerequisite branches. The normal eight tiers fit in one view; exceptionally deep data scrolls instead of overlapping. The List view provides the same saved allocation in a compact text layout.
- **Gear** places the snapshot's items in all 19 WotLK equipment slots around a character panel. It never substitutes the logged-in character's equipped items. Click a saved slot for item level, the build-spec model score, recognized weighted stats, and an explicit warning when item data or effects are only partially modeled.

The gear score is directional build guidance, not a best-in-slot verdict. Uncached saved items remain pending instead of being counted as zero or replaced with current equipment. **Adopt current snapshot** copies current gear, the complete talent-tree presentation/allocation, and glyphs into the editor draft only when the current character and edited build have the same class; a mismatch disables the action and explains why. Save commits the staged snapshot and Cancel discards it. Older rank-only snapshots are expanded automatically from the built-in 3.3.5a talent catalog, restoring their native names, icons, full trees, backgrounds, and prerequisite lines without changing the stored build.

## Sync, Sharing & Public Builds

### How do I search and sort Public Builds?
A search box above the list filters by title or author as you type. The sort dropdown next to it offers **Most Votes** (default), **Newest**, **Item Level** (average, from the author's character snapshot -- builds without one sort to the bottom), and **Trending**, which weighs votes by how recently the build was updated so a build picking up votes right now outranks an old build sitting on a larger but stale total; a build with zero votes never counts as trending just for being new.

### How do upvotes on Public Builds work? Can someone fake votes?
Click a card in Public Builds to open a read-only inspect view -- class/spec, the author's intent notes, locked Echoes, and the top configured priorities -- so you can make an informed decision before voting or importing. The vote button (top-right of the card, or inside inspect) shows a chevron icon that fills gold once you've voted, next to the count; one vote per character, click again to remove it.

Votes are direct-witness only: your client only ever broadcasts your own vote, never a relayed list of what other people supposedly voted. WoW authenticates the sender name on every addon and channel message, so nobody can broadcast a vote as someone else. The number you see is how many distinct voters your client has personally heard from -- it grows as you play alongside more people, and two players might see slightly different counts if one has synced with more of the community than the other. Public Builds sorts by vote count first, so well-regarded builds surface above someone's experiments.


### What does Inspect show me before I import or vote on a public build?
Click anywhere on a build card (not the Import or vote button) to open a read-only Inspect view: the author's intent notes, the locked Echoes, every one of the author's weighted priorities -- icon, name in its quality color, and the weight value, same as you'd see while editing your own build -- and, if the author included one, a Character summary: talent point split across the three trees, and equipped gear count with average item level. The whole panel scrolls as one, so an author's long intent notes never crowd out or hide what's below them. You can vote or import right from Inspect, without going back to the list.

The character summary only appears when the author explicitly attached one ("Adopt snapshot" on their Character tab when saving) -- it's not automatic, so plenty of public builds won't have it. When it's there, a "View full character" button opens the complete talent tree, gear paper doll, and glyphs -- the exact same view your own Character tab uses, just read-only against the author's snapshot instead of your live character.

### Does shared community DPS data actually affect my recommendations now?
Yes, since 3.76 -- and only in a specific, honest way. Previously, shared performance data was raw per-echo DPS averages pooled across players, which mixes everyone's gear, skill, and fight types together; it was collected but deliberately never allowed to influence anything. The addon now shares each player's **with/without deltas** instead: "my runs with this Echo average X more DPS than my runs without it." A delta is measured within one player, so their gear and skill sit on both sides of the comparison -- combining deltas across players is defensible in a way pooled raw DPS never was.

Guardrails: only deltas that are reliable on the sender's own data get broadcast at all; community evidence needs at least two distinct players and the same per-side sample floors your local data must clear; it is only used for Echoes where you have **no reliable local samples yet** (your own data always wins); and any recommendation built on it says so explicitly, including how many players it came from. Sharing remains opt-in via the same consent setting as before.

Sharing builds with other EbonBuilds players.

### What changed about syncing in 2.3?
Reliability and efficiency, same protocol on the wire (old versions stay compatible):

- **Lost transfers recover.** Previously a single dropped message meant that build silently never arrived. Now the receiver notices a stalled transfer, asks the sender to retransmit (up to 2 attempts), and falls back to other players offering the same build.
- **No duplicate downloads.** When several players offer the same build during one sync, it is requested from only one of them.
- **Flood protection.** Responders answer at most one sync request per player per 30 seconds.
- **Feedback.** A toast summarizes each sync ("Sync complete: N build(s) received"), and with the Debug log (Settings, Windows & Tools) enabled the full sync traffic appears in the debug log.
- Retransmit requests can only ever re-send **public** builds you own -- a forged request cannot extract private data.

### How do build chat links work? (new in 2.4)
Open a build and press **Chat Link** — a token like `[EbonBuilds: Pyro Mage V2]` lands in your chat box and can be sent anywhere (say, guild, party, whisper). Other EbonBuilds users see it as a clickable link: clicking opens the build if they already have it, otherwise it is fetched automatically from any online player who owns it. Only **public** builds are ever served. Players without the addon simply see the plain text.

### My build disappeared after logging in later. What happened?
This was a real bug, fixed in 2.11 -- not something you did wrong. Saving a build compares its stored author name to your current character name to decide whether it's yours or someone else's. `UnitName("player")` can occasionally come back from the game in a different format (with or without the realm attached) after a reconnect. That mismatch made the addon think your OWN build belonged to someone else, "forked" it into a new slot, and removed the old one.

**Nothing was truly deleted.** The build kept existing under a different id, tagged with a "copied from `<your name>`" note. If you still have a build like that, it's yours -- rename it and clear the copied-from note via Edit Build. The comparison is now realm-suffix-tolerant, so this can't happen again.

### Why do I get a popup saying my build's name is taken? (new in 2.18)
Public Builds used to fill up with dozens of near-identical entries -- the same title from many different authors, e.g. "[WIP] Scourgebeast's Solo DK v1.1" by five different people. The actual cause: importing someone's public build, then making even a tiny edit and saving, silently forks your copy under your own name (an existing, intentional data-loss protection from 2.11) -- but it used to keep the original title and public status, so every edited import quietly added another duplicate to the list.

As of 2.18, saving (or creating) a build checks whether its exact title is already public under a *different* author. If so:
- Your copy is automatically un-published (not deleted -- just no longer shared).
- A popup explains the name is taken and who it belongs to.
- Rename it (Edit Build) and it can be made public again under its own name.

This is a best-effort, client-side check -- there's no central registry, so it's based on what your own client has seen. Existing duplicates already in Public Builds are also cleaned up automatically: the browser (and what gets relayed to other players) now collapses same-titled entries down to the earliest-known one.

### I deleted a build I imported and it vanished from Public Builds too. Fixed?
Yes (2.21). Importing a public build used to delete Public Builds' cached copy of the original, on the (wrong) assumption that was needed to hide it from the browse list -- it isn't; the list already hides anything you have an up-to-date local copy of on its own. That deletion's only real effect was that if you later deleted your imported copy, the original public build was gone from your Public Builds list entirely until someone synced it to you again. The cache is no longer deleted on import, so deleting your local copy now makes the original reappear immediately.

### Why couldn't I see my own public build in Public Builds?
It used to be deliberately hidden there (you already have it in your left sidebar, so browsing it again seemed redundant) -- but that also meant there was no easy way to confirm a build actually published successfully. As of 2.29, your own public builds show up in Public Builds too, tagged **(You)** next to your name, with the Import button replaced by a disabled "Yours" label. If it's not there after making a build public, that's a real sign something's wrong (check the title-collision popup from 2.18 -- your build gets auto-unpublished if the exact title is already public under someone else).

### Sync is flooding my chat with "[EbonBuilds Sync] Build ... stored in remote" spam. Fixed?
Yes (2.23). Several internal sync diagnostics (one line per build received, one line per REQ broadcast, channel-index bookkeeping) were printing to general chat unconditionally instead of only when `/ebbsync verbose` is on -- always been there, but the 2.15 staggered all-classes sync made it much worse, since a single "All Classes" Reload can now pull in dozens of builds and fires the REQ-sent line up to 10x (once per class) instead of once. All of that moved behind the existing verbose toggle; real problems (a build failing to assemble) now go to `the Error log (Settings, Windows & Tools)` instead of the chat window. Command output (`/ebbsync status`, `/ebbsync reset`, etc.) and cooldown/actionable messages are unaffected -- you'll still see those.

### The game froze / hung after syncing with Tome Atlas open. Fixed?
Yes (2.24), most likely cause found and fixed. Tome Atlas (and Public Builds) re-rendered its entire list synchronously on every single incoming synced entry -- normally one build/tome is no big deal, but a real sync can stream in dozens to 100+ in a burst over a few seconds, especially since 2.15's staggered all-classes sync. Each render re-scans your spellbook and rebuilds/sorts the whole list (worse in "Group: Zone"/"Group: Mob" mode), so doing that dozens of times in rapid succession is exactly the kind of thing that makes a client stutter hard or lock up. Both views now coalesce bursty refresh requests into at most one actual render every 0.3s, however many sync messages arrive in between.

### Export (AI) -- new button (2.38, full class echo list + descriptions in 2.39)
Next to the regular Export button (build edit screen, any tab) is a new **Export (AI)** button. Regular Export produces a compact Base64 string meant for another EbonBuilds client to Import -- not something a human or a general AI chat can read. Export (AI) instead produces a plain-text dump: quality/family/novelty bonuses, automation thresholds (with mode-appropriate labels), locked echoes, banned echoes, and -- as of 2.39 -- **every echo your class can get, not just the ones you've weighted**, each with its quality, family, current weight, and actual effect description (pulled from the real spell tooltip where cached; otherwise a note to hover it once in-game first). If you've collected any Tuning Advisor data, that's included too. Meant to be copied and pasted into an external AI chat to ask for tuning suggestions on which echoes are actually worth weighting for your spec; it isn't a format EbonBuilds can import back in.

## Settings, Diagnostics & Troubleshooting
Toggles, logs, and fixed issues.

### Autopilot and ProjectEbonhold "Auto-Accept Loadout Echoes" both seem to pick — what should I do?
Turn **Auto-Accept Loadout Echoes** off in ProjectEbonhold's options if you want EbonBuilds Autopilot to own every pick. When that PE option is on, ProjectEbonhold auto-selects matching wishlist / active-loadout echoes about 180ms after a choice arrives — often before Autopilot would act. EbonBuilds detects the option, warns once when Autopilot is enabled, and **defers** on boards that PE will auto-accept so the two never double-select. Boards without a loadout match still run under Autopilot as usual.

Applying a **foreign** build's wishlist or server loadout while Auto-Accept is on can auto-pick that author's locked echoes in combat — EbonBuilds shows a confirmation before doing that. Your own builds are unaffected.

### Which ProjectEbonhold version does Autopilot need?
Reliable autoroll needs the **server's ProjectEbonhold distribution** aligned with EbonBuilds **3.83+** (merged as server API alignment, #42). That build tracks in-flight requests on `ProjectEbonhold.Perks` (`pendingSelectSpellId`, `pendingFreezeIndex`, `pendingBanishIndex`, `pendingReroll`, and build-slot saves), confirms freezes via the `justFrozen` card flag instead of silently losing them, and marks guaranteed build-slot injects so Autopilot does not waste freeze/banish charges on them.

**How to check:** in-game, `/run print("PE addonVersion", ProjectEbonhold and ProjectEbonhold.addonVersion, "modVersion", ProjectEbonhold and ProjectEbonhold.modVersion)` — your server team publishes the minimum pair that matches their core. EbonBuilds **3.84+** also expects `ProjectEbonholdOptionsService` (for Auto-Accept Loadout Echoes) and optional `GetPendingRollsCount` / `GetRollsDebugInfo` (#67). Older PE builds may still run, but missing pending flags or freeze confirmation is the usual cause of "Autopilot stopped mid-run" or duplicate-request stalls.

**Server + client checklist:** update the server's ProjectEbonhold addon to the build your realm advertises, keep EbonBuilds current, reload after either update, and enable the Debug log (Settings, Windows & Tools) if a run stalls — look for `Deferring: ProjectEbonhold auto-accept…`, `Waiting for pending…`, or `Freeze not confirmed`.

### Autopilot stopped mid-run — common ProjectEbonhold causes
Most "it stopped autorolling" reports trace to the client and server disagreeing about board state, not bad weights:

1. **Duplicate request while PE still has a pending flag** — ProjectEbonhold refuses a second select/freeze/banish/reroll until the first clears. EbonBuilds 3.83+ waits on `GetPendingAction()` instead of firing again; an outdated PE build that never clears those flags can still deadlock until `/reload`.
2. **Auto-Accept Loadout Echoes vs Autopilot** — when a wishlist echo is on the board, PE may select it ~180ms after the choice arrives. EbonBuilds defers rather than racing a second select (#67). Turn Auto-Accept off for full Autopilot control, or expect loadout matches to be PE-owned.
3. **Freeze confirmation drift** — if the server omits freeze flags across a board hide/show, EbonBuilds 3.84 keeps accepted freeze IDs in run-persistent state (#59), but an old PE build that never sends `justFrozen` can still make recovery noisy in the Debug log.
4. **Guaranteed build-slot card** — an active designed loadout can inject a card the server refuses to freeze or banish; Autopilot skips those actions by design (#42).
5. **Training Mode left ON** — Autopilot intentionally yields; check the build Overview toggle.

If none of that fits, capture the Debug log from the stalled screen plus your PE `addonVersion` / `modVersion` printout above.

### How do I use Combat DPS logging in the Logbook?
Settings → **Optional features** → **Combat DPS logging** (character preference, on by default since 3.84). While enabled and you have an **active build run**, the addon listens to the combat log, builds combat segments from your damage (and pet/guardian damage), and attaches DPS samples to that run in SavedVariables — strictly informational; it never feeds Autopilot or scoring.

**To record a benchmark:** start or continue a run with your build active, pull a training dummy (or any sustained fight), and stay in combat long enough for a meaningful segment — segments under ~10 seconds are discarded; segments of **60+ seconds** count as "benchmark grade" and are preferred when the Logbook picks a **best DPS** figure for the run row and summary strip. After combat ends, open the build's **Logbook**: the run browser shows best measured DPS; hover the summary DPS for a list of recent samples (duration, target name, dummy marker).

**Separate from Echo DPS tracking:** the Tuning Advisor's **Track DPS by echo** (requires Details!) credits whole-loadout DPS to individual echoes for tuning suggestions. Combat DPS logging is per-run throughput only — no Details! required, no echo attribution. Turn Combat DPS logging off in Settings if you do not want combat-log processing.

### How do I remove a build, and where are builds stored on disk?
Delete it in-game: open the build's **Overview** tab and click the red **Delete** button in the bottom-left corner; a confirmation popup follows. This is the recommended route because it also keeps public/sync bookkeeping consistent.

On disk, builds are not inside the addon folder — like all WoW addon data they live in your SavedVariables:

- Account-wide (all builds, settings, caches): `WTF\Account\<ACCOUNT NAME>\SavedVariables\EbonBuilds.lua` (variable `EbonBuildsDB`)
- Per character (character-scoped data): `WTF\Account\<ACCOUNT NAME>\<Realm>\<Character>\SavedVariables\EbonBuilds.lua` (variable `EbonBuildsCharDB`)

If you ever hand-edit these files, log out of the game first (the client rewrites them on logout, overwriting your edits) and keep a backup. Also note that a build imported from Public Builds can reappear via the community cache after a raw file edit — the in-game Delete button handles that case correctly.

### How does Auto-sell work? What do its filters and keep list do?
Auto-sell is configured under **Settings → Automation** (gear icon in the main window). It is **off by default**.

When enabled, opening a vendor triggers a sweep of your bags for **zero-copper** items that pass every filter. Items are sold one at a time (with a short delay), and WoW's vendor buyback tab gives you a same-session undo.

**Options (require Settings Save):**
- **Auto-sell junk at vendors** — master toggle.
- **Only sell Poor (gray) quality** — restricts the sweep to gray items only; when off, any quality with zero vendor price can be sold.
- **Never auto-sell Trade Goods** — on by default.
- **Never auto-sell Recipes** — on by default.

**Keep list** — click **Manage Auto-Sell Keep List...** to add exact item names that should never be sold. Per-character; saves immediately as you add or remove entries (no Settings Save needed).

**Always protected:** non-zero vendor price, unlearned affixes, gear upgrades for your active build, and keep-list names. Category filters use localized item-type names so Trade Goods / Recipe detection works on non-English clients too.

The old `/ebb autosell` slash command was removed when slash commands moved into Settings — use the checkboxes instead. See [Settings → Automation](settings.md#automation) for the full reference.

### What do the Error log and Click Trace log do? (new in 2.12)
Two diagnostic tools under **Settings → Windows & Tools**:

- **Error log** — opens a small always-on error log (last 20 entries), separate from the Debug log. Useful as a first step when something breaks and you don't have debug tracing already running.
- **Click Trace log** — diagnostic for "I clicked a button and nothing happened." Logs every themed button click and view transition, so a bug report can show whether the click even reached EbonBuilds or was intercepted before that.

### Why did Reload get faster / show fewer builds? (2.13)
The Public Builds **Reload** button now only requests builds for the class currently selected in the dropdown (your own class by default), instead of every class from every peer on every reload. Switch the dropdown to "All Classes" if you want the old everything-at-once behavior back. This cuts sync traffic and page count dramatically on classes many players share builds for.

### What do the checkboxes in the gear-icon Settings dialog do? (new in 2.16)
That's the "EbonBuilds Settings" popup (gear icon next to the window's close button, not the per-build Automation tab). Categories include General (action delay, toast duration), Automation (auto-sell with category filters and keep list, bag affix dots, debug/click-trace toggles), Interface (UI language), Windows & Tools (one-click access to guides and logs), Build (EWL export, clear training data), and Consent (DPS sharing).

Nothing applies until you click **Save** — except the auto-sell keep list, which saves immediately in its own window. A toast confirms what changed (e.g. "Settings saved (Auto-sell ON, Bag dots OFF)").

See the [Settings reference](settings.md) for every option. The dialog scrolls if it grows past the window, so more settings can be added later without overflow.

### EbonBuilds won't even enable / greyed out in the addon list with ProjectEbonhold Enhanced. Fixed?
Yes (2.22). The `.toc` declared a hard `## Dependencies: ProjectEbonhold` -- WoW's client won't let you enable an addon at all if a hard dependency's exact folder name isn't found, and "ProjectEbonhold Enhanced" ships under a different folder name even though it provides the same API. Switched to `## OptionalDeps: ProjectEbonhold, ProjectEbonholdEnhanced`, which still makes sure whichever one you have loads first (so EbonBuilds sees it), but no longer blocks enabling EbonBuilds if the folder name doesn't match exactly. No more manually editing the `.toc` by hand after every update.
