# Changelog

All notable changes to **EbonBuilds** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release numbers follow the project's `3.xx` convention. Each shipped version
is a `### <version> (<date>) -- <summary>` block, newest first. Within an entry,
group changes under `#### Added`, `#### Changed`, `#### Fixed`, or `#### Security`
? never another `###` heading (release automation stops at the next `###` line).

`scripts/release.sh` refuses to tag unless this file changed. The Release workflow
and the in-game **What's new** page both read the topmost `###` entry from here.
GitHub Releases use a short title (`EbonBuilds <version>`); the release body is the
full matching `###` section from this file (plus install instructions). Install
instructions and download links also live on
[GitHub Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases)
and on the [Releases page](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/releases/).

[Unreleased]: https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/compare/v3.85...HEAD

### 3.86 (Unreleased) -- Automation stepping stones, Auctionator PE, and reliability fixes

Follow-up to 3.85: client-side automation work packages WP2?WP5 from the server-authoritative Autopilot redesign, Auctionator ProjectEbonhold adaptation, optional Details!: Tiny Threat PE fork, ProjectEbonhold Anvil affix acquisition bridge, expanded BoardDecision test coverage, reliability fixes for bag dots / AutoSell / SessionHistory / FAQ, and original WotLK-inspired GitHub Pages branding. Release prep: [docs/release-386-prep.md](docs/release-386-prep.md).

#### Added

- **Intent queue WP3 (#89 / #52):** new `IntentQueue` module ? one in-flight autopilot intent (select/freeze/banish/reroll) with duplicate blocking; ack via board identity fingerprint, `GetPendingAction()` pending-flag drop, or 8s TTL. Wired into `Automation.ExecuteDecision` / `RequestFreeze` ahead of server intent-ack support. `ProjectAPI.GetCapabilities` exposes `intentQueueClient` and `serverIntentAck`. Docs in `docs/intent-queue-wp3.md`; tests in `tests/test_intent_queue.lua`.
- **Shared tie-break policy WP2 (#90 / #51):** centralized score ? optional PE `rank` ? slot index ? spell ID ? frozen-preference ordering in `Scoring` (`CompareCandidates` / `IsBetterCandidate`), wired through `BoardDecision` and `Automation.TrySelect` so equal-weight boards pick deterministically and align with the server redesign. Optional per-card `rank` from ProjectEbonhold offers; missing ranks fall back to slot-index ordering. `DebugServerRankMismatch` flags rank disagreements. Tests in `tests/test_tie_break.lua`.
- **Dry-run simulator WP4 (#93 / #53):** new `AutomationDryRun` module ? pure offline evaluator returning policy verdicts (`select`/`freeze`/`banish`/`reroll`/`wait`) from board snapshots without calling ProjectEbonhold `Request*`. Transcript parser/replay for fixture directives and DebugLog/Logbook line hooks; checked-in #38-class fixture. Docs in `docs/dry-run-wp4.md`; tests in `tests/test_dry_run.lua`.
- **Constraints client WP5 (#97 / #54):** new `AutomationConstraints` module packs Autopilot prefs (protect families, echo policies, thresholds, bans/whitelist, reroll hints) into a versioned table, compact wire blob, and stable `constraintsHash`. Constraints attach on each board eval; `IntentQueue` stores the hash on in-flight intents and clears the queue when prefs change mid-board. `GetCapabilities()` exposes `constraintsClient`; `serverConstraints` and `serverPolicy` stay false until ProjectEbonhold ships upload/policy. Docs in `docs/constraints-wp5.md`; tests in `tests/test_constraints.lua`.
- **WotLK-inspired docs artwork (#88):** locally generated hero background, runic dividers, slate texture, favicon, and feature-card icon silhouettes via `scripts/generate-docs-art.py` ? no Blizzard client assets. Homepage hero, framed sections, and gold/frost chrome in `extra.css`; favicon updated in `mkdocs.yml`.
- **Auctionator ProjectEbonhold adaptation (#92):** vendored fork **2.6.3-pe1** with affix search helpers (`AtrPE_BuildAffixSearchQuery`), PE hooks for **EbonBuilds Affixes** shopping-list sync, defensive AH scan/query wrappers, and **AuctionatorBridge** query delegation. Tests in `tests/test_auctionator_pe.lua`.
- **Details!: Tiny Threat PE fork (#103):** optional vendored `Details_TinyThreat` for WotLK 3.3.5a with PE compatibility fixes (threat/name API polyfills, realm-qualified names in `Threater()`). Ships as `Details_TinyThreat.zip` when the release workflow includes it; install guide in `docs/details-tinythreat-pe.md`.
- **Affix Anvil bridge (#102):** new `ProjectEbonholdAffixBridge` soft integration with PE ExtractionService / Enchanted Anvil ? capability-gated **Anvil** / **Shop** row buttons and toolbar shortcuts on the Affixes tab (Vendor hidden until PE loads `ItemPurchasePopup`; see [#112](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/112)). Tests in `tests/test_pe_affix_bridge.lua`.

#### Changed

- **Automation server redesign docs:** WP2 tie-break chain, WP3 intent-queue stepping stone, WP4 dry-run transcript schema, and WP5 constraints wire format documented in `docs/automation-server-redesign.md`, `docs/intent-queue-wp3.md`, `docs/dry-run-wp4.md`, and `docs/constraints-wp5.md` to match landed client behavior.
- **ProjectEbonhold capability audit (#96):** tightened `ProjectAPI.GetCapabilities()` probes against live PE exports (`pendingFlags` requires `Perks` + `SelectPerk`; `pendingBuildSlot` follows the build-slot API family; `activeLoadout` requires both loadout setters and spell checks); explicit `serverPolicy = false` placeholder for the planned server oracle. Documented server-side gaps in `docs/capabilities.md`. Tests in `tests/test_capabilities_audit.lua`.
- **BoardDecision test coverage (#94):** `tests/test_board_decision_coverage.lua` ? freeze-first reroll locks, equal-score tie-break ordering (slot index, server rank, frozen preference), pending/slot-busy waits via BSM + IntentQueue, and freeze-penalty threshold scoring through mocked BoardDecision/Automation paths.
- **SessionHistory logbook UX (#101):** harden Logbook rendering against nil access and scroll edge cases during long runs.
- **Docs site (#99):** fix broken GitHub Pages links and align the releases page with v3.85 shipping state.

#### Fixed

- **In-game FAQ content (#100):** restore the full generated FAQ after an MkDocs title change truncated in-game pages.
- **Combuctor bag affix dots (#104):** harden quality-dot integration for 3.3.5a quality detection and combat-lockdown / taint safety on Combuctor item buttons.
- **AutoSell auction categories (#107):** harden `GetAuctionItemClasses` edge cases so locale/category filters stay stable on 3.3.5a clients.


### 3.85 (2026-07-24) -- Autopilot reliability, Auctionator affix shopping, and UI/data refactors

[Release v3.85](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.85)

Follow-up to 3.84: ProjectEbonhold API alignment for pending rolls and tome/permanent locks, a client board state machine for freeze-lock, optional vendored Auctionator for AH affix shopping, UI monolith splits, docs/site polish, regenerated TGA UI assets, and a much larger automated test suite.

#### Added

- **Auctionator integration (#74):** optional companion AddOn (vendored Auctionator 2.6.3 for WotLK). Ships as `dist/Auctionator.zip`; EbonBuilds declares `## OptionalDeps: Auctionator`. **AuctionatorBridge** adds soft-fail buyout helpers, Affixes-tab AH search and shopping-list sync, tooltip buyout lines, and a gold bag dot for cheap missing-affix gear. Tests in `tests/test_auctionator_bridge.lua`.
- **Board state machine WP1 (#75):** client-side automation board state + freeze-lock groundwork (#50) so Autopilot tracks board lifecycle more reliably.
- **ProjectEbonhold Autopilot reliability (#67):** pending-roll handling, auto-accept, and slot-busy guards so Autopilot stops fighting in-flight server requests.
- **Tome draw-pool + permanent LockPerk APIs (#68 / #62):** Tome Atlas shows draw-pool state; right-click toggles via `ToggleTomeEcho` / `IsTomeEchoDisabled`. Build Overview surfaces permanent locks from `GetLockedPerks` / `GetMaximumPermanentEchoes`, with unlock / `LockPerk` gestures. Optional **Snapshot Run** drafts from `SnapshotCurrentEchoes`. **ProjectAPI** wrappers are capability-gated for older PE builds.
- **UI data-layer splits (#73, #85, #86):** SessionHistory, CharacterView, and BuildOverview data modules extracted from the UI monolith (issue #19).
- **TGA UI assets (#70):** regenerate in-game textures from documented sources instead of shipping opaque binaries alone.
- **Docs and community:** professional README (#76), localized README parity (#84), FAQ polish for Discord/PE topics (#72), changelog/releases docs (#79), MkDocs/Pages polish (#78, #87), community governance files (#77), and GitHub social preview image (#83).

#### Changed

- **Test suite:** shared 3.3.5a API stub harness, architecture lint hardening, maximize coverage for pure modules (#81), and AutoSell category test stubs (#80).
- **Developer experience (#69):** clearer local `check.sh` output and CI failure artifacts for debugging.

#### Fixed

- **AutoSell localized categories (#71):** category filters use `GetAuctionItemClasses` so non-English clients match the intended auction categories.


### 3.84 (2026-07-24) -- Bag dots, freeze persistence, server loadouts, and combat DPS in the Logbook

[Release v3.84](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.84)

Follow-up to 3.83: bag affix dots, map panel stability, Autopilot freeze persistence, Public Builds server loadouts, combat DPS in history, and broader test coverage.

#### Added

- **Public Builds ? server loadouts (#64):** Save as server loadout / Apply wishlist on Overview and Public Builds inspect, mapping locked Echoes into ProjectEbonhold designed slots (capability-gated).
- **Combat DPS in build history (#65 / #46):** optional `COMBAT_LOG` DPS logging attaches samples to the active run; Logbook shows best measured DPS (prefers longer benchmark segments). Toggle under Settings ? Optional features.
- **Combuctor bag affix dots (#63):** Bagnon-style hooks for Combuctor ItemSlots so red/purple/teal/BoE dots draw on Combuctor bags too.
- **Test coverage (#60):** TOC lint bans the classic Lua nil-toggle antipattern; regressions for freeze-over-reroll, toggles, Bagnon bag-dot hooks, plus pure-module and export/import coverage.

#### Fixed

- **Teal disenchant dots never appeared (#56):** bag affix dots treated `GetContainerItemInfo`'s 3rd return as item quality; on 3.3.5a that value is `locked`, so Disenchant-candidate (teal) dots never matched. Quality now comes from `GetItemInfo`. ManualTraining's broken nil-toggle expression replaced with an explicit if/else.
- **Zone panel crash with the world map open (#58):** toggling "Zone panel" called a nil `RefreshMapPanel` global. Forward-declared like the existing `ShowZonePins` fix. Minimap button drag angle now uses the minimap's effective scale instead of UIParent's.
- **Frozen Echoes forgotten mid-run (#59):** when the server omitted freeze flags across board hide/show or identity churn, Autopilot could lose which Echoes were frozen and keep rerolling. Accepted freeze IDs now live in run-persistent `frozenEchoIDs`. Logs `Freeze not confirmed` when recovery resolves an unconfirmed freeze as unfrozen.
- **Freeze penalty no longer demotes a worthy carry (#66):** while a frozen/carried Echo still scores at or above the freeze threshold, the freeze penalty is not applied ? excellent carries stop losing to slightly worse fresh offers.

### 3.83 (2026-07-24) -- Autopilot speaks the server addon's language, plus a community bug-fix wave

[Release v3.83](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/tag/v3.83)

The freeze-first engine from 3.82's groundwork (PR #41) ships together with fixes driven by Discord reports and GitHub issues.

#### Changed

- **Server ProjectEbonhold API alignment (#42):** the server's distribution of ProjectEbonhold confirms a freeze by flagging the existing card (`justFrozen`) instead of resending the board, injects a guaranteed card from the active build slot (which refuses freeze/banish requests), and tracks its own in-flight requests. Autopilot reads all three ? freezes confirm instantly instead of falling into recovery, no charge is wasted on the guaranteed card, and a locally refused duplicate request can no longer pause automation mid-run.
- **Freeze/select after freeze (#38):** equal-weight boards now freeze/select deterministically left-to-right; rerolls stay hard-blocked while anything on the board is frozen or a freeze is unconfirmed (verified against a player's Logbook export).

#### Fixed

- **"Caster: ON" could never be turned off (#39):** the family-protection toggle used `x and nil or true`, which in Lua always yields `true`. Protection now toggles both ways; the same broken pattern was fixed in the Echo table's family filter and in the talent-snapshot comparison (which always claimed "No saved talent snapshot").
- **Grey boxes on the world map (#36):** the Tome Atlas continent tint now draws zone highlights with additive blending, matching the client's own map highlight ? the highlight textures have no alpha channel, so the old blend mode painted their black background as solid grey rectangles.
- **Bag affix dots with Bagnon / Combuctor (#37):** both replace the default bag frames entirely, so the dots never drew there. The module now detects Bagnon and Combuctor (same Tuller lineage) and hooks their item-button update path; default bags are unchanged, and cached views (other characters, bank while away) deliberately show no dots.
- **Polish showed "?" for every diacritic (#40):** stock 3.3.5a fonts lack the Latin-Extended-A glyphs. The addon probes the font once per session and folds ? ? ? ? ? ? ? ? to ASCII only when they genuinely cannot render ? players with a font pack keep real diacritics, everyone else reads "Posta?" as "Postac" instead of "Posta?".

#### Added

- **FAQ:** two new entries from Discord ? whether Autopilot trains a build's values by itself (it never does; Training Mode and advisor proposals are the explicit channels), and how to delete a build plus where builds live in SavedVariables.

### 3.82 (2026-07-21) -- Public Builds: full character view, search, and sort

Two rounds of Public Builds improvements land together.

- **Full character view in Inspect:** the compact "talent points / gear count" summary now has a "View full character" button that opens the complete talent tree, gear paper doll, and glyphs -- the exact same view your own Character tab uses, read-only against the author's shared snapshot.
- **Search:** a search box above the build list filters by title or author as you type.
- **Sort:** choose how the list is ordered -- **Most Votes** (previous default), **Newest**, **Item Level** (average, from the author's snapshot), or **Trending** (recent votes outrank a larger but stale total; a build needs actual votes to trend, not just to be new).

### 3.81 (2026-07-21) -- Talents and gear now show up in Public Builds Inspect

Inspect (added in 3.77) showed a build's intent, locked Echoes, and weighted priorities -- but nothing about the character it was built for.

- New **Character** section: talent point split across the three trees, and equipped gear count with average item level -- a quick "is this actually specced and geared the way the title claims" glance while browsing.
- Only appears when the author attached one (Character tab -> "Adopt snapshot" when saving) -- it's optional, so plenty of public builds won't have it, and Inspect says so plainly when that's the case.
- This is a summary, not the full talent tree or paper doll -- for the exact picks and gear piece by piece, import the build.

### 3.80 (2026-07-21) -- A real icon on the Public Builds vote button

The vote button has shown a plain "^" character since it shipped. It's now an actual chevron icon -- filled gold once you've voted, a dim outline before -- generated from the same source and palette as the minimap icon and the website logo, so all three are provably one design instead of three separate guesses at it.

### 3.79 (2026-07-21) -- Fix: Inspect showed the build list through it, and only 8 priorities

Reported right after 3.78 with a screenshot: opening Inspect on a public build left the list visibly showing through underneath, and the priorities section was capped at 8 flat text lines.

- The Inspect panel now sits on a properly opaque top layer -- no more list content bleeding through behind it.
- Priorities are shown the way the build editor shows them: an icon, the name in its quality color, and the weight, for every configured priority -- not just the top 8, and scrollable.

### 3.78 (2026-07-21) -- Internal: minimap icon now has a real source (no visible change)

The minimap icon's pixels are unchanged -- this is repo housekeeping. `media/minimap_icon.tga` existed only as a binary file with no source, generated from `scripts/generate-media.py` now instead, using the exact ring geometry the website's logo already defines. Also fixed two leftover mentions of `texlive-binaries` in the setup docs, dropped from the toolchain back in 3.73.

### 3.77 (2026-07-21) -- Upvotes and Inspect for Public Builds (#8)

Requested by Zartris: a way to acknowledge a well-made build and tell it apart from someone's experiments. Delivered together with a new Inspect view, because an informed vote needs to see the build first.

- **Inspect:** click any card in Public Builds to open a read-only detail view -- class/spec, the author's intent notes, locked Echoes, and the top configured priorities. Vote and Import/Update live right there too.
- **Upvotes:** one vote per character, click again to remove it. Public Builds now sorts by vote count first, so builds the community rates highest surface above the rest.
- **How the count works:** there's no central server, so votes are honest by construction rather than by trust -- your client only ever broadcasts *your own* vote, never a list of what others supposedly voted (which anyone could fake). The number you see is how many distinct voters your client has personally heard from, and it fills in as you sync with more people. Two players may see slightly different counts depending on who they've played alongside -- that's expected, not a bug.
- **Also fixed:** delta-based sync data (3.76) arriving over the main sync channel was being silently dropped since release -- only the guild copy was getting through. Channel sync now delivers it correctly.

### 3.76 (2026-07-21) -- Community DPS data finally does something -- and does it honestly

Shared performance data has been collected for a long time but deliberately never influenced anything: the old format pooled raw per-echo DPS averages across players, which mixes everyone's gear, skill, and fight types into one confounded number. That ends here.

- **New sharing format:** the addon now broadcasts each player's own **with/without deltas** ("my runs with this Echo average X more DPS than my runs without it") -- and only the ones that are reliable on that player's own data. A delta is measured within one player, so their gear and skill sit on both sides of the comparison; combining deltas across players is defensible in a way pooled raw DPS never was.
- **Where it shows up:** the Tuning Advisor's weight suggestions can now draw on community evidence -- but only for Echoes where you have **no reliable local samples yet**. Your own data always wins. Community evidence needs at least two distinct players and the same per-side sample floors your local data must clear.
- **Labeled honestly:** any recommendation built on community data says so, including how many players it came from.
- **Compatibility:** the old format still broadcasts alongside the new one, so players on older versions lose nothing; the legacy path retires in a later release. Sharing remains opt-in via the same consent setting; clearing your performance data clears the community delta store with it.
- 3 new self-tests (27/27); the new inbound handler sits behind the same hostile-payload fuzzing as every other one.

### 3.75 (2026-07-21) -- Fix: disabling Tome on Map no longer "works half way" (#15)

Reported by kipsell: turning the tome map integration off left part of it behind, and closing the "Tomes in this zone" panel was a one-way door.

- The per-character **"Zone tome list on the world map"** checkbox is back in Settings under Addon-wide features. It had been lost in the 3.70 settings rework -- the panel's X button kept writing the preference, but the checkbox to undo it was gone, so a closed panel could never be brought back.
- Both map switches now apply immediately while the map is open: the master **"Tome Atlas map integration"** (green continent highlights, zone list, pins, legends) and the zone-list checkbox (just the panel).
- The master switch's tooltip now spells out exactly what it covers, so "half of it stayed" can't happen by mixing the two up.
- New self-test locking the panel toggle's roundtrip and its independence from the master switch (24/24).
- New FAQ entry under Tome Atlas explaining both switches.

### 3.74 (2026-07-21) -- Internal: Stats data layer split out (no behavior change)

The Stats workspace's data derivation -- session metrics, action analytics, early-Epic stats, weighted coverage, echo rows, recommendations, and the stats cache -- now lives in its own module (`modules/analytics/StatsData.lua`) instead of being interleaved with the rendering code in one 2815-line file. Nothing changes in what you see or how anything is computed: the full test suite, including the representative-data Stats/Logbook render and all self-tests, passes unchanged. This is groundwork (issue #19) -- the same split is planned for Session History, the Character tab, and the Build Overview, and it makes the analytics testable without the UI layer in between.

### 3.73 (2026-07-21) -- Infrastructure modernization: correct version display, smaller download, real release assets, docs site

A pair of maintenance rounds across the whole toolchain. What you'll notice in-game and on GitHub:

- **The FAQ window header shows the right version again.** It had been reading a hardcoded version string that last got updated at 3.53 -- nineteen releases of drift. The version now comes from the `.toc`, the single place releases actually bump.
- **The "greyed out with ProjectEbonhold Enhanced" FAQ answer is complete again.** The page generator had been cutting it off mid-sentence at an inline `## Dependencies:` mention; the parser is line-anchored now and the full answer ships.
- **Downloads are real release assets.** Each release page now carries `EbonBuilds.zip` as an attached asset (with a download counter) instead of linking into the git tree, and the zip itself is ~70 KB smaller -- the 178 KB FAQ source file no longer ships inside it (the in-game FAQ uses the generated pages, not the markdown).
- **Documentation moved to a searchable site:** https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/ -- getting started, every setting, the full FAQ with search, and this changelog. Replaces the wiki.
- **The repository dropped the leading dash from its name** (old links redirect). The in-game "newer version is in use around you" hint now prints the new URL.

Under the hood, for contributors: the test suite runs on Lua 5.1 -- the same runtime as the WoW client -- instead of Lua 5.3 (which promptly caught and fixed a real 5.1-only crash pattern in `Theme.lua`); the toolchain is now just `lua5.1` + `zip`; the changelog lives in `CHANGELOG.md` instead of the middle of the FAQ file; releases publish automatically from a tag push via GitHub Actions; and CI runs with read-only permissions, SHA-pinned actions, and no duplicate runs.

### 3.72 (2026-07-21) -- Error Log entries now capture a real call stack

`core/ErrorLog.lua`'s `Protect()` only ever recorded the error message itself -- for anything more than a one-line "attempt to call a nil value", there was no way to see which chain of calls actually led there.

- `Protect()` now uses `xpcall` instead of `pcall` so `debugstack()` (a WoW API function the addon had never used) can capture the real call stack from inside the error handler, before it unwinds. Lua 5.1's `xpcall` doesn't accept extra arguments for the protected function (that's a 5.2+ addition), so the call arguments are captured in a closure instead.
- Stored separately from the message (`entry.stack`), so the compact one-line-per-error view is unchanged by default.
- New **Stacks** checkbox in the Error Log window shows them inline, indented under each entry, when you actually want to dig in.
- 1 new self-test (23/23 total).

### 3.71 (2026-07-21) -- New check: module dependency graph validated in CI, not just at runtime

3.70's `core/Modules.lua` catches an unknown or circular module dependency the moment it's actually started -- but only at real runtime, module by module, as the boot pipeline reaches it. A typo'd dependency name could sit unnoticed until a player happened to load the addon and trigger that exact path.

- `Modules.ValidateGraph()`: a pure, side-effect-free walk of the whole registered dependency graph (no module's `start` function is ever called), returning every unknown-reference or circular-dependency problem it finds.
- New self-test calls the real `EbonBuilds.Start()` (the actual `core/Init.lua` registration list, not a hand-written stand-in) and validates the resulting graph -- runs in CI via `tests/test_selftests.lua` and live in-game via the Error Log window's Self-Tests button. Confirmed it actually catches a real problem by deliberately introducing a typo'd dependency name during testing, then reverting.
- 22/22 self-tests now (was 21).

### 3.70 (2026-07-21) -- Core architecture refactor merged (PR #13), with unified spam detection

A substantial contribution from ha99dfs and Juriz V, reviewed and integrated with the existing framework rather than merged as-is.

**What changed under the hood:**
- Every file now uses the private per-file namespace pattern (`local addonName, EbonBuilds = ...`) instead of a bare global -- available since patch 3.3.0, confirmed compatible with 3.3.5a.
- New dependency-graph module system (`core/Modules.lua`, `core/InitPipeline.lua`) replaces the flat, manually-ordered `Init()` dispatcher -- modules declare what they depend on instead of relying on list order.
- `core/Scheduler.lua` rewritten as an object-pooled, time-budgeted binary-heap scheduler (still the same `Scheduler.After(id, delay, callback, priority, allowCombat)` call shape, so nothing using it needed to change).
- New `core/WoWEvents.lua`: one shared event frame with stable-iteration listener dispatch, replacing dozens of modules each creating their own `CreateFrame` + `RegisterEvent` + `SetScript` for events.

**What we changed on top before merging:** the new `WoWEvents.On` dispatcher had its own error isolation but no equivalent to `core/Debug.lua`'s event-spam detection -- merging as-is would have quietly dropped that coverage for every event moved onto it. `Debug.CheckSpam(key)` is now a shared, public counter both `ProtectScript` and `WoWEvents.On` call into (`Router.On(..., spamExempt)`), so there's one definition of "too often" instead of two that could drift apart. Re-applied the spam exemption to the listeners that already needed it (Sync's `CHAT_MSG_ADDON`/`CHAT_MSG_CHANNEL`, Affix's `CHAT_MSG_ADDON`, EchoCatalog's `SPELLS_CHANGED`).

Both branches had also independently built overlapping Settings toggles after diverging -- kept all of them (they're complementary): "Sync chat messages" and "Tome Atlas map integration" master switches (new) alongside "Show tome list on the world map" and "Verbose sync logging" (3.68/3.69) -- notably the new toggles don't replace 3.69's fix; they control different, non-overlapping messages.

3 new self-tests for the spam-detection integration (21/21 total).

### 3.69 (2026-07-21) -- Verbose sync logging is now a real Settings toggle

Community report: a player had `/ebbsync verbose` on and had no idea how to turn off the resulting chat spam ("[EbonBuilds Sync] Build ... stored in remote" repeated for every build received) -- it was a bare, non-persisted slash command left over from before the addon consolidated its other toggles into Settings.

- New checkbox: Settings -> Automation -> "Verbose sync logging" (off by default).
- Now persisted per-character, so it survives a reload/relog and is discoverable without remembering a slash command.
- `/ebbsync verbose` still works and stays in sync with the checkbox.
- If you were seeing this spam: `/reload` clears it immediately either way, since the setting wasn't persisted before this version.

### 3.68 (2026-07-21) -- Zone tome-list panel can now be hidden; Mapster map-tinting fix merged

- **Fix (merged from PR #14):** continent zone tinting is now skipped entirely when Mapster is loaded, instead of rendering as oversized solid boxes. Mapster actively rescales the map frame between its windowed and quest-list presets, which desynced our cached zone-highlight geometry. The zone-level tome panel doesn't depend on that geometry and still works normally with Mapster active.
- **New, from community feedback:** the "Tomes in this zone" panel had no way to dismiss it, and a long list (11 entries reported in Sholazar Basin) could cover a meaningful chunk of the map. It now has its own close (X) button, plus a matching Settings toggle (Interface -> World Map -> "Show tome list on the world map") -- either one stays in sync with the other.

### 3.67 (2026-07-21) -- Fix: world map crashed with 'attempt to call global ShowZonePins (a nil value)'

3.65's new pin system had a Lua scoping bug: `RefreshMapPanel` calls `ShowZonePins`, but `RefreshMapPanel` is defined earlier in the file than `local function ShowZonePins` -- so at the point `RefreshMapPanel`'s body was compiled, no local `ShowZonePins` existed yet, and the reference silently resolved to a nonexistent global instead. Every world-map refresh threw the error.

- Fixed with a standard Lua forward declaration: `local ShowZonePins` up top, the later definition changed from `local function ShowZonePins(...)` (which would have shadowed the forward-declared upvalue with an unrelated new local) to a plain assignment.
- The existing self-tests didn't catch this because they only exercised the pure logic function (`PinsForZone`) directly, never the actual call chain that broke. Added a cheap sanity test that just confirms `ShowZonePins` is actually a function after full load -- would have caught this specific bug directly (18/18 self-tests now).

### 3.66 (2026-07-21) -- Fix: EchoCatalog spam warning still fired after 3.63's debounce

3.63 debounced the actual cache-clearing work, but missed that the spam warning is based on how often the *handler itself* gets called, not how much work it does -- `SPELLS_CHANGED` still calls the handler once per fire regardless of what's inside it, so the warning kept firing even though the underlying waste was already gone.

- `EchoCatalog.LifecycleFrame` is now marked spam-exempt (`ProtectScript(frame, source, true)`, same as 3.64's Sync/Affix fix) -- the handler is already as cheap as it can be; the call volume itself just reflects how often WoW fires this event, which nothing in the addon can reduce further.

### 3.65 (2026-07-21) -- Zone map: coordinate-pin system + toggle legend, ready for real location data

Inspired by looking at how a rare-spawn map-overlay addon does it (hand-painted per-target overlay images, plus a toggle legend). That specific technique doesn't fit Tome Atlas's scale, but the toggle-legend idea and a proper coordinate-pin system do -- built now, dormant until real x/y data exists.

- `EbonBuilds.WorldIntegration.SetSourceCoords(zoneName, sourceName, x, y)` registers a tome source's position on the zone map as a 0..1 fraction of width/height. No tome source has real coordinates yet, so this renders nothing today -- the moment a future data file calls it, that source's pin and legend row appear automatically.
- When a zone's coordinates exist, zoomed-in view shows a small marker per source (hover for the name) plus a **Tome markers** legend panel with a checkbox per marker to hide ones you don't care about -- the checkbox toggle idea, adapted to a coordinate system instead of pre-baked images per target.
- 3 new self-tests (17/17 total).

### 3.64 (2026-07-21) -- Sync/Affix event-spam warnings during heavy sync were false positives

A player's debug log confirmed `Sync.EventFrame` and `Affix.EventFrame` tripping the new spam detector wasn't a bug -- it was dozens of nearby players actively syncing builds at once (`CHAT_MSG_ADDON` fires for every addon message on the client, not just ours, and heavy legitimate `BLD`/`WNT`/`RTX` sync traffic easily clears 120/sec in that situation).

- `ProtectScript(frame, source, spamExempt)` gains an optional third argument: pass `true` for a frame whose handler is legitimately expected to fire very often by design, the same reasoning `OnUpdate` already gets. Applied to both `Sync.EventFrame` and `Affix.EventFrame`.
- Separately (found while investigating): `Affix.lua`'s `HandleAddonMessage` was calling `UnitName("player")` before its own cheap prefix check -- meaning every non-EbonBuilds addon message on the channel paid for a WoW API call it didn't need. The prefix check now runs first.
- 1 new self-test (14/14 total).

### 3.63 (2026-07-21) -- Fix: EchoCatalog cleared its description cache 120+ times per second

3.62's new event-spam detection caught this in the wild within hours of shipping: `SPELLS_CHANGED` is a notoriously chatty event that can fire well over a hundred times in under a second during login/zoning bursts, and the handler was clearing a cache on every single fire.

- Debounced via the Scheduler's keyed rescheduling: each fire now just pushes the actual cache-clear out by 0.5s, so it runs once after the burst settles instead of once per fire.
- A `Sync.SendChunked` "exceeds the 27 KB transfer limit" log entry seen alongside this is not a bug -- that's a deliberate safety cap (matching WoW's addon-message size constraints) correctly rejecting an oversized build instead of transferring it partway and failing.

### 3.62 (2026-07-21) -- Framework: slow-handler detection, event-spam warnings, a diagnostic HUD, and Assert()

Four additions to `core/Debug.lua`, all following the same pattern as the error-isolation work: catch a class of bug once, centrally, instead of relying on every module remembering to check for it.

- **`Debug.Time(source, fn, thresholdMs)`** wraps a function so its execution time is measured on every call; anything over the threshold (default 5ms) gets recorded to the Error Log -- spotting a slow handler without attaching a profiler.
- **Event-spam detection** is now built into `ProtectScript` itself: a handler firing 120+ times within one second (almost always over-broad event registration, not intended behavior) gets a single Error Log warning per window instead of silently running unchecked. `OnUpdate` is exempt, since firing every frame is exactly what it's for.
- **A small diagnostic HUD** (Error Log window -> new **HUD** button) shows protected-frame count, errors recorded, spam warnings, and the last self-test result -- live, no digging through separate windows.
- **`Debug.Assert(condition, message)`** for "this should never happen here" spots: records to the Error Log and returns `false` on failure instead of raising, so a violated assumption can't crash a handler any more than a caught error can.
- 5 new self-tests cover all four (13/13 total now, up from 8).

### 3.61 (2026-07-21) -- Handler protection rollout complete

Last 10 files from the repo-wide scan: `TalentAutoLearn`, `Talents`, `Session`, `EchoEligibilityEvidence`, `EchoCatalog`, `EWL`, `Sync`, `Affix`, `TomeAtlas`, `ClickTrace` all now opt into `EbonBuilds.Debug.ProtectScript`. Every frame in the addon that registers an event or UI handler is now error-isolated -- a bug in one handler can no longer take down others on the same frame or spam a red error toast.

### 3.60 (2026-07-21) -- Handler protection: EchoTable, BuildTabs, Toast, ShowcaseView, DebugLog

- `modules/ui/EchoTable.lua` -- scroll frame.
- `modules/ui/BuildTabs.lua` -- view frame.
- `modules/ui/Toast.lua` -- toast notification frame.
- `modules/ui/ShowcaseView.lua` -- drag region.
- `modules/automation/DebugLog.lua` -- drag region and edit box.
- Remaining files without coverage: WelcomeView, TalentAutoLearn, Talents, Session, EchoEligibilityEvidence, EchoCatalog, EWL, Sync, Affix, TomeAtlas, ClickTrace.

### 3.59 (2026-07-21) -- core/Init.lua and core/Scheduler.lua's handlers now protected too

A repo-wide scan of the handler-protection follow-up found 18 files with zero `ProtectScript` coverage that earlier passes had missed (that pass had only covered the highest-`SetScript`-count files under `modules/ui/`, not a full sweep). Two of them needed more than the usual one-line fix:

- `core/Init.lua` and `core/Scheduler.lua` both call `SetScript` at file scope, and both run *before* `core/Debug.lua` used to load -- so the normal "call `ProtectScript` right after `CreateFrame`" pattern silently did nothing there. `core/ErrorLog.lua` and `core/Debug.lua` now load immediately after `core/Init.lua` (previously near the end of `core/`), which fixes this for every file except `core/Init.lua` itself -- it's unconditionally the very first file loaded, so it can never depend on anything loading before it.
- `core/Init.lua` gets different, arguably more useful protection instead: every individual `Init()` call in the ADDON_LOADED dispatcher is now wrapped separately (`SafeInit`), so one module failing to initialize can no longer silently prevent every module listed after it from initializing too -- previously a single uncaught error here didn't just skip one handler call, it stopped the whole startup sequence partway through.
- `core/Scheduler.lua`'s shared OnUpdate dispatcher (every delayed/periodic task in the addon runs through it) is now `ProtectScript`-covered directly, since it loads after Debug.lua now.
- Remaining files without coverage yet: EchoTable, BuildTabs, Toast, WelcomeView, ShowcaseView, DebugLog, TalentAutoLearn, Talents, Session, EchoEligibilityEvidence, EchoCatalog, EWL, Sync, Affix, TomeAtlas, ClickTrace.

### 3.58 (2026-07-21) -- Handler protection: EchoPicker.lua

- `modules/ui/EchoPicker.lua` -- 4 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (picker row, picker window, search box, clear-search button).
- Remaining files: AffixView, BonusView.

### 3.57 (2026-07-21) -- Handler protection: PublicBuildsView.lua, ExportImport.lua

- `modules/ui/PublicBuildsView.lua` -- 3 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (icon button, main scroll frame, refresh-throttle OnUpdate timer).
- `modules/build/ExportImport.lua` -- 4 frames now opt into `ProtectScript` at creation (export and import dialogs, their respective text edit boxes).
- Remaining files: EchoPicker, AffixView, BonusView.

### 3.56 (2026-07-21) -- Fix: Auto-Sell keep-list window crashed on open

The keep-list window added in 3.49 used `Region:SetShown()` to toggle the placeholder text and the empty-list message. That method doesn't exist in 3.3.5a -- it was added in Cataclysm (4.0.1) -- so opening the window threw `attempt to call method 'SetShown' (a nil value)` every time.

- Both call sites switched to the 3.3.5a-compatible `if cond then f:Show() else f:Hide() end`.
- The test suite didn't catch this because the stub client used for testing silently accepts calls to methods that don't exist (they resolve to a no-op) -- fine for a load-order smoke test, not for catching a wrong-expansion API call.
- Added `scripts/check-335a-api.sh`, wired into `scripts/check.sh` as a new step: greps the whole addon for a set of known post-3.3.5a API calls (`SetShown`/`GetShown`, the `C_Timer` namespace, `IsInGroup`/`IsInRaid`/`GetNumGroupMembers` and friends from Mists of Pandaria's group-API rework) and fails the build if any turn up. Catches this exact class of mistake before it ships, not after a player reports it.

### 3.55 (2026-07-21) -- Unified Echo identity and exact class eligibility

- **Overtime Conversion eligibility corrected centrally.** Mage and every supported class except Paladin can use spell `200756`; the generic correction-fact pipeline validates the expected identity and source mask before applying the reviewed correction.
- **Crimson Reprisal and Blood Mirror remain separate Echoes.** Crimson Reprisal (`200246`, `g:10`) uses its canonical identity even though the runtime spell name collides with Blood Mirror (`201388`, `g:296`). Their weights, policies, locks, search results, recommendations, and exports are independent.
- **Every Echo consumer now uses one exact-variant projection.** Wizard, editor, weights, missing lists, scoring, automation, EWL, import/export, recommendations, and community validation no longer apply their own class-mask or name fallback logic.
- **Saved configuration is non-destructive.** Echo schema 3 preserves valid references regardless of temporary availability, restores prior `CROSS_CLASS_REFERENCE` entries, and quarantines ambiguous legacy name-only data instead of guessing.
- **Future false-negative server masks can self-correct locally.** Validated offers, replacements, successful selections, and live discovery evidence widen only the exact spell/class pair observed; full projection and pooled UI refreshes remain deferred outside combat.

### 3.54 (2026-07-20) -- FAQ organized into categories; login panel fixed up

**FAQ (GitHub and in-game):** all 51 questions were one flat list with no grouping at all. Sorted into 7 categories -- Getting Started, Automation & Decision Models, Stats/Logbook & Missing Tab, Tome Atlas, Affixes & Character, Sync/Sharing & Public Builds, and Settings/Diagnostics & Troubleshooting. The in-game FAQ window gets a new **Jump to** dropdown that jumps straight to a category's first page instead of clicking Next through up to 50 pages to find one topic.

**Login panel:**
- Could not be moved -- every other popup window in the addon has a drag header, this one didn't. Fixed.
- Now shows the addon's icon and a gold header rule, matching the rest of the UI.
- New "Latest: ..." teaser line pulls the newest changelog headline automatically, so what's new is visible without an extra click.
- A hardcoded gray color is now the shared `Theme.TEXT_MUTED` constant.

Both `modules/ui/FAQView.lua` and `modules/ui/LoginPanel.lua` also gained `ProtectScript` coverage -- neither had been touched by the earlier module-by-module handler-protection pass.

### 3.53 (2026-07-20) -- Live self-tests; Smart vs. Classic explained properly

**Framework:** the Error Log window (Settings -> Windows & Tools) has a new **Self-Tests** button that runs every self-test registered via `core/Debug.lua` live, right in your client -- not just in CI. Failures are recorded into the Error Log itself, so a bug report can include "ran self-tests, X failed" as a real data point. `Debug.GetStats()` now also tracks how many frames currently have `ProtectScript` coverage, for a future diagnostic view.

**Clarity:** community feedback showed the Smart-vs-Classic decision model choice wasn't landing -- the FAQ answer and in-settings tooltips explained the mechanism but not the actual difference. Rewritten with the core distinction stated plainly (Classic compares against a fixed ceiling that's rarely met; Smart compares against what you'd realistically get otherwise) plus a worked example in the FAQ. The FAQ answer's stated location for switching models was also stale (said "Autopilot tab"; it's actually Settings -> Advanced controls) -- fixed to match where the toggle actually lives.

### 3.52 (2026-07-20) -- Map overlay: matched to the rest of the UI, a few things fixed along the way

- **One accent color instead of two.** The world map's "Colored zones" legend used a hand-typed hex (`59d9a0`) that had quietly drifted from the teal already used consistently everywhere else EbonBuilds identifies itself in a tooltip (peer-version lines, gear-upgrade hints) -- now a single `Theme.PRESENCE_TEAL` constant backs all of it.
- **The zone-tomes panel now matches the rest of the addon**: gold section-style title with the same thin divider rule other panels use, instead of plain white default text; body text explicitly uses the addon's primary text color instead of an unstyled default.
- **Dead fallback code removed**: the panel's background styling had an `if Theme then ... else raw backdrop` branch left over from before Theme.lua's load order was settled -- Theme always loads first, so this never actually ran; removed rather than left as confusing dead weight.
- **Bespoke error-wrapping replaced** with `core/Debug.lua`'s `Protect()` -- this file had its own small pcall wrapper predating that module; now uses the same one everything else does.
- The map panel frame itself now also opts into `EbonBuilds.Debug.ProtectScript`, closing the last unprotected frame in this file.

### 3.51 (2026-07-20) -- Custom minimap icon; media/ now actually ships

The minimap button referenced a custom icon path (`media/minimap_icon`) that never existed -- dead code since it was added, silently falling back to a generic Blizzard gear icon (`INV_Misc_Gear_01`) every session.

- Added a real icon: three concentric gold rings over a dark circular backing (an "echo" motif, matching the addon's core mechanic), in the same gold used throughout the UI.
- `scripts/build-dist.sh` now packages `media/` into the release zip -- it didn't before, so even a correctly-pathed custom texture would have shipped broken.
- Shipped as `.tga` rather than `.blp`: the 3.3.5a client loads both, and `.tga` needs no format conversion to produce.

### 3.50 (2026-07-20) -- Handler protection: MinimapButton.lua

- `modules/ui/MinimapButton.lua` -- the minimap button itself now opts into `EbonBuilds.Debug.ProtectScript`.
- Remaining files: PublicBuildsView, ExportImport, EchoPicker, AffixView (handler protection specifically -- its search box was already fixed in 3.48), BonusView.

### 3.49 (2026-07-20) -- Auto-Sell keep-list & category filters; two new Bag Dots colors

**Auto-Sell** (Settings -> Convenience & Diagnostics) can now be tuned instead of being all-or-nothing:
- **Keep List**: a new "Manage Auto-Sell Keep List..." window lets you protect specific items by exact name, regardless of category or value. Per-character (junk on a bank alt isn't junk on a main).
- **Category filters**: "Only sell Poor (gray) quality" (off by default, matches the previous behavior), "Never auto-sell Trade Goods", and "Never auto-sell Recipes" (both on by default -- a truly zero-copper material or recipe is unusual enough that sweeping it automatically is more likely a surprise than a convenience).
- Still not a general rule engine by design (see the module's own comment) -- this is deliberately just enough control that the zero-value sweep doesn't have to be all-or-nothing, not a reimplementation of AutoDelete.

**Bag Dots** gains two colors alongside the existing affix red/purple:
- **Blue** -- Bind on Equip and still unbound. A reminder to consider trading/auctioning before equipping, vendoring, or disenchanting forfeits that option.
- **Teal** -- likely worth disenchanting rather than selling: soulbound Uncommon/Rare gear that doesn't score as an upgrade for the active build's spec (reuses the same spec-scoring `GearScore.IsUpgrade` already powers Auto-Sell's "don't sell an upgrade" check and gear-tooltip hints).
- Bind status comes from a lazy tooltip scan against Blizzard's own `ITEM_BIND_ON_EQUIP`/`ITEM_SOULBOUND` globals (locale-safe, no hardcoded English text), same low-cost per-slot caching as the existing dots.

### 3.48 (2026-07-20) -- UI consistency pass: unified search boxes and selected-state color

Two small visual inconsistencies found by a repo-wide scan, both fixed centrally instead of file-by-file.

- **Every search box now looks the same.** Affixes and Tome Atlas (both its main and zone-picker search) previously used Blizzard's native gold/parchment `InputBoxTemplate`, which visually clashed with every other search box in the addon (Build List, Echo filters) using the addon's own dark themed input style. All five now share the same look, keyboard behavior, and focus/error states.
- **A magnifying-glass search icon** (the same one Blizzard's own Friends/Guild roster search boxes use) now marks every search field in the addon -- new `Theme.AddSearchIcon(container)` helper, applied to all five.
- **The "selected" gold background tint is one constant now** (`Theme.SELECTED_BG`), not five hand-typed copies that had quietly drifted apart (Theme.lua and Build Wizard used `0.20/0.17/0.07`, Settings used `0.18/0.16/0.07`, Session History's run-browser used `0.17/0.15/0.07` -- three visibly different shades of "selected" depending which screen you were on).

### 3.47 (2026-07-20) -- Handler protection: EchoTableRows.lua, Filters.lua

- `modules/ui/EchoTableRows.lua` -- inline weight edit box and echo table row frame now opt into `EbonBuilds.Debug.ProtectScript`.
- `modules/ui/Filters.lua` -- search box, clear-search button, filter bar, and result-count hit frame now opt into `ProtectScript`.
- Remaining files, largest first: PublicBuildsView, ExportImport, EchoPicker, AffixView, BonusView, MinimapButton.

### 3.46 (2026-07-20) -- Handler protection: BuildList.lua, BuildForm.lua

- `modules/ui/BuildList.lua` -- 4 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (icon button, build list row, search box, clear-search button).
- `modules/ui/BuildForm.lua` -- 4 frames now opt into `ProtectScript` at creation (icon button, name box, description scroll frame, description edit box).
- Remaining files, largest first: EchoTableRows, Filters, PublicBuildsView, ExportImport, EchoPicker, AffixView, BonusView, MinimapButton.

### 3.45 (2026-07-20) -- Handler protection: CharacterView.lua

- `modules/ui/CharacterView.lua` -- 6 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (talent node button, row button, talent UI area, gear slot button, tab view frame, gear item-info event frame).
- Remaining files, largest first: BuildList, BuildForm, EchoTableRows, Filters, PublicBuildsView, ExportImport, EchoPicker, AffixView, BonusView, MinimapButton.

### 3.44 (2026-07-20) -- Handler protection: Calibration.lua, TomeAtlasView.lua

- `modules/automation/Calibration.lua` -- the popup's drag header now opts into `EbonBuilds.Debug.ProtectScript` (its other 9 `SetScript` calls were already covered indirectly via Theme.lua's factories).
- `modules/ui/TomeAtlasView.lua` -- 5 frames now opt into `ProtectScript` at creation (zone row, main search box, picker search box, picker row button, refresh-throttle OnUpdate timer).
- Remaining files, largest first: CharacterView, BuildList, BuildForm, EchoTableRows, Filters, PublicBuildsView, ExportImport, EchoPicker, AffixView, BonusView, MinimapButton.

### 3.43 (2026-07-20) -- Handler protection: BuildWizard.lua

- `modules/ui/BuildWizard.lua` -- 4 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (pick button, inspect button, archetype card button, build name edit box).
- Remaining files, largest first: Calibration, TomeAtlasView, CharacterView, and others.

### 3.42 (2026-07-20) -- Handler protection: MainWindow.lua

- `modules/ui/MainWindow.lua` -- 6 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (header drag region, global settings popup and its drag header, card slider, toolbar icon button, and the main addon window frame itself).
- Remaining files, largest first: BuildWizard, Calibration, TomeAtlasView, CharacterView, and others.

### 3.41 (2026-07-20) -- Handler protection: BuildWizardPriorityStep.lua

- `modules/ui/BuildWizardPriorityStep.lua` -- 5 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (dismiss overlay, grouped-priority popup, per-row inspect and evidence buttons, search box).
- Remaining files, largest first: MainWindow, BuildWizard, Calibration, TomeAtlasView, CharacterView, and others.

### 3.40 (2026-07-20) -- Handler protection: SettingsView.lua

- `modules/ui/SettingsView.lua` -- 5 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (two threshold/row sliders, an edit box, the ban-list icon button, and the settings scroll frame).
- Remaining files, largest first: BuildWizardPriorityStep, MainWindow, BuildWizard, Calibration, TomeAtlasView, CharacterView, and others.

### 3.39 (2026-07-20) -- Handler protection: StatsView.lua

- `modules/ui/StatsView.lua` -- 9 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (echo row, summary/early-epic/action metric cards, echo and recommendations scroll frames, card hit-area overlay, row frame, DPS bar segments). Covers all of the file's raw-handler `SetScript` sites; the rest were already indirectly covered by Theme.lua's factories.
- Remaining files, largest first: SettingsView, BuildWizardPriorityStep, MainWindow, BuildWizard, Calibration, TomeAtlasView, CharacterView, and others.

### 3.38 (2026-07-20) -- Handler protection: BuildOverview.lua

- `modules/ui/BuildOverview.lua` -- 6 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (icon button, status container and status frame, description scrolling-message frame, missing-retry OnUpdate timer, missing-list row buttons). Of the file's 37 `SetScript` calls, 31 were already covered indirectly through Theme.lua's widget factories (3.36) -- only these 6 raw `CreateFrame` sites were left.
- Remaining files, largest first: StatsView, SettingsView, BuildWizardPriorityStep, MainWindow, BuildWizard, Calibration, TomeAtlasView, CharacterView, and others.

### 3.37 (2026-07-20) -- Handler protection: SessionHistory.lua (1 of ~19 remaining files)

Step 3 of the handler-protection follow-up: going module by module through files that create frames directly with `CreateFrame` instead of through a Theme.lua factory (which got covered in 3.36).

- `modules/ui/SessionHistory.lua` -- 13 frames now opt into `EbonBuilds.Debug.ProtectScript` at creation (run browser rows and popup, search box, timeline rows, export/import dialog and its text fields, header sort buttons, summary rarity frame, log scroll frame, duration timer). This covers all of the file's 47 `SetScript` calls, since one `ProtectScript` call at frame creation protects every handler attached to that frame afterwards.
- Chosen first because it had the most raw (non-Theme-factory) handlers of any file in the addon.
- Remaining files, largest first: BuildOverview, StatsView, SettingsView, BuildWizardPriorityStep, MainWindow, BuildWizard, Calibration, TomeAtlasView, CharacterView, and others -- tracked as ongoing follow-up work, one file per release so each change stays reviewable and testable on its own.

### 3.36 (2026-07-20) -- Auto-protection extended to every Theme.lua widget

Step 2 of the handler-protection follow-up (3.35 only covered `CreateButton`).

- `CreateDropdown` (main button, menu frame, and each dynamically created option row), `CreateScrollBar`, `CreateHorizontalScrollBar`, `CreateCloseButton`, and `CreateCheckbox` now all opt into `EbonBuilds.Debug.ProtectScript` the same way `CreateButton` already did.
- `CreateTab` and `CreateFilterChip` needed no change -- both already build on top of `CreateButton` and were covered indirectly.
- `CreateCheckbox` needed care: it already overrides `SetScript` itself to chain its internal check-toggle logic ahead of a caller's handler. `ProtectScript` is applied *after* that override is installed, so it wraps the checkbox's existing chain instead of being silently replaced by it.
- Every widget built through Theme.lua's factories is now covered; remaining unprotected handlers are the ones individual UI modules attach to frames they create directly with `CreateFrame` instead of through a Theme factory (tracked as ongoing follow-up work, largest files first).

### 3.35 (2026-07-20) -- New: core/Debug.lua, a small internal framework layer

A follow-up to the repository audit's note that most UI handlers weren't isolated against unexpected errors (only a handful were manually wrapped in ErrorLog.Protect out of hundreds).

- **`core/Debug.lua`** adds two things on top of the existing `core/ErrorLog.lua`: `ProtectScript(frame, source)` opts a frame in once, and every handler any caller later attaches to it via `SetScript` is automatically wrapped in error isolation from then on -- no per-call-site changes needed anywhere else in the addon. A lightweight self-test registry (`RegisterTest`/`RunSelfTests`) also lets a module add its own sanity check next to the code it's testing instead of hand-editing the large shared test files.
- **`Theme.CreateButton` now opts in automatically**, so every button built through the shared theme (the vast majority of the addon's buttons) gets this protection with zero changes required in the modules that call it.
- **`tests/test_selftests.lua`** is a new test file (wired into `tests/run.sh`) that loads the full addon and runs every registered self-test; it currently covers `core/Debug.lua`'s own behavior and the `Theme.CreateButton` integration.
- This is intentionally scoped as a foundation, not a full framework migration: existing handlers elsewhere are unaffected until they're routed through `ProtectScript` (directly, or through a widget factory like `Theme.CreateButton` that already does).

### 3.34 (2026-07-20) -- Echo policy persistence fix, unified Wizard/editor catalogs (contributed)

Two correctness fixes plus a follow-up unification, contributed by Juriz V (PR #9) and ha99dfs (PR #11).

- **Echo policies (Banish/Never Pick) now actually persist.** Stable Echo references (`g:<groupId>/s:<spellId>`) were being written as a policy and then immediately deleted again during legacy-name cleanup, because the cleanup step treated the storage key itself as a display name to purge. Setting a policy no longer erases itself.
- **Picker lists resolve names correctly across every PerkDatabase layout ProjectEbonhold has shipped**, including compact array-based records used by some enhanced/client builds, not just the named-field layout. Runtime records missing a group ID recover it from the static Echo catalog by matching on name or internal comment instead of creating a duplicate one-off entry per rank/class variant, and placeholder names ("Unknown Echo", "Unknown Spell #123", etc.) are filtered out instead of showing up as real Echoes.
- **Tome Atlas continent tint made reliable** (follow-up to 3.33): the sampling grid now covers the full 0..1 range inclusive instead of missing zones at the continent texture's edges, zone names are normalized on both sides of the lookup so incidental whitespace no longer silently drops a zone's color, and the tint texture is pinned to the top overlay sublevel so it always renders above Blizzard's own zone artwork instead of depending on creation order.
- **Wizard and editor now share one Echo catalog projection.** Class-scoped quality variants (qualities, spell IDs, families) are computed per class instead of reused from the unscoped definition, so the Build Wizard's priority groups and the build editor's picker agree on exactly which quality variants are available for a class.

### 3.33 (2026-07-20) -- Continent map colors every zone with tome drops

Follow-up to 3.32's zone panel, using the approach quest-overlay addons use.

- On the continent view of the world map, every zone with recorded tome drops is tinted green (translucent, using the zone's own highlight texture), with a legend line noting that zooming in shows the list. Zone-level coloring needs zone names only -- exactly what the atlas has -- so this works without the coordinates that map pins would need.
- Under the hood: the map is sampled once per continent per session through `UpdateMapHighlight`, which answers "which zone highlight sits at this point" including the highlight texture's file, size, and position; those answers are cached and the tome-bearing zones' highlights stay shown with a tint. Zooming into a zone hides the overlays and shows 3.32's detail panel instead.
- The render path is tested against a stubbed map API: zone selection, texture choice, pixel-space geometry from sampled fractions, the translucent green tint, and overlays hiding on zone view.

### 3.32 (2026-07-20) -- Player tooltips show EbonBuilds users; world map lists the zone's tomes

Two ways the addon now shows itself in the world instead of only in its own windows.

- **Hover a player, see if they run EbonBuilds.** One tooltip line for any player your client has received addon traffic from -- "EbonBuilds 3.32" when they've announced a version (the VER ping from 3.31, now also sent over the sync channel rather than guild-only), plain "EbonBuilds user" otherwise. Session-local by design: presence is live information, nothing is stored. Cross-realm names match with or without the realm suffix.
- **Open the world map in a zone with known tome drops** and a compact panel lists every tome recorded there -- best-known source mob, total community drop count, and how many further sources exist. Data comes from the Tome Atlas, which is mob-and-zone keyed; the honest consequence is a zone panel rather than map pins, because no coordinates exist to pin (collecting kill coordinates through the community sync would be the path to real pins later). Zones without tome data show nothing at all.
- Both hooks are error-isolated like the gear tooltip: a failure lands in the Error log instead of breaking tooltips or the map.

### 3.31 (2026-07-20) -- In-game FAQ generated from FAQ.md; peer version notice

Two answers to "how do players stay current".

- **The in-game FAQ can no longer go stale.** It had been showing 2.99 content at version 3.30 -- thirty releases of drift -- because its pages were a hand-maintained copy. Pages are now GENERATED from FAQ.md at release time (`scripts/build-faq-pages.sh`, wired into release.sh): page one is always the newest changelog entry, followed by one page per FAQ question. While converting, the FAQ section itself was modernized -- five references to slash commands removed in 3.15 now point at the Settings window instead.
- **Update notice over the sync channel.** A sandboxed addon cannot ask GitHub anything (no network access), but peers are a signal: clients announce their version in a lightweight VER message, and seeing a strictly HIGHER version than yours triggers one chat notice per session with the releases link. Equal, lower, and malformed versions stay silent; the notice never repeats. Older clients ignore the unknown opcode -- the sync fuzzer already guarantees unknown opcodes are harmless, and the version-comparison semantics have their own test now.

### 3.30 (2026-07-20) -- Build Wizard reworked: grouped Echo priorities (contributed)

Contributed by ha99dfs (PR #7).

- Wizard Step 3 replaces the one oversized Echo list with functional groups (Recommended, Included, Modified, build-changing, Damage, Survival, Resources, Control, Utility, Equipment, Other, plus diagnostic views) and a search that spans all groups by default.
- Each Echo gets independent Priority and Use controls: enabling Use on a Neutral Echo assigns the Useful preset, disabling always resets to Neutral +0, and Avoid is policy-only -- weight stays 0 and the Echo receives the canonical Never Pick policy.
- Priority rows are virtualized and recycled for smooth scrolling; fixes missing Echoes, clipped borders, unreadable labels, and inconsistent row states along the way.
- Also in this release: the FAQ's EWL answer no longer references a slash command removed in 3.15.

### 3.29 (2026-07-20) -- Family system rebuilt: one source of truth, family-level evidence

The family system had grown four independent implementations: Scoring held a private normalization map, the settings UI a private display list, the sample filter a substring hack for catalog variants like "Caster DPS", and family suggestions excluded multi-family Echoes entirely because per-echo numbers can't attribute a stacked modifier. All four are gone.

- New `modules/data/Families.lua`, the single source of truth: the canonical seven families with display order and damage-role flags, normalization for every known catalog variant (plus a forgiving prefix match so future server variants degrade to the right family instead of silently becoming unknown), and canonical family-set resolution for any Echo -- deduplicated, unknown variants dropped, empty resolving to "No family" exactly as Scoring's fallback always did.
- Scoring, the settings UI, and the DPS-relevance filter all consume it now. Score math itself is deliberately unchanged: family bonuses stack per matching family exactly as before -- this release unifies identity, it does not silently change your scores.
- **Family suggestions are rebuilt on family-level with/without evidence.** A new `EchoSamples.FamilyDelta` asks, from the same whole-set samples: how do runs containing at least one Echo of this family compare against runs with none? Set membership dissolves the old exclusion -- multi-family Echoes finally count toward every family they belong to, because a run either contains the family or it doesn't. Deltas are read against the zero line with the same 10-per-side reliability gate, and non-damage families (Tank, Survivability, Healer, No family) get no DPS-based suggestions at all.
- Honest accounting from the rebuild itself: the rewrite initially swept away the sampling ticker along with the old function body -- `find-orphans.sh` flagged `Sample()` going caller-less before anything shipped, which in-game would have silently stopped all data collection. Restored, and the kind of catch that tool exists for.

### 3.28 (2026-07-19) -- Echo Performance redesigned: whole-set samples and with/without evidence

The confounding fix. The old model stored one running average per echo and credited every active echo with the loadout's whole DPS -- a mount-speed echo "earned" the damage its neighbors dealt, and more data only made that more confidently wrong. Recorded aggregates from before this release carry that flaw and cannot be reinterpreted; the suggestion layer no longer reads them.

- New `modules/automation/EchoSamples.lua`: each observation is one sample of the WHOLE active set -- every granted echo together with the DPS reading -- in a capped ring (500 samples). Questions are answered by with/without comparison across samples: runs containing echo X versus runs without it.
- **Reliability gate**: a with/without split needs at least 10 samples on each side before it counts as evidence at all. An always-active echo honestly reports "no without-side" instead of a confident number.
- **Utility filter**: echoes whose families include no damage role (Caster/Melee/Ranged, catalog variants like "Caster DPS" included) are excluded from DPS attribution and from weight/bonus suggestions entirely -- DPS evidence says nothing about a mount-speed or tanking echo, and pretending otherwise was the original bug wearing different hats.
- All three suggestion functions (weights, Quality Bonus, Family Bonus) now consume with/without deltas instead of the confounded averages. Their internal math was rebuilt for delta semantics: deviations are normalized by typical delta magnitude rather than dividing by a mean that legitimately sits at or below zero, and bonus tiers are judged against the zero line -- a delta already means "with minus without", so a clearly negative tier deserves a downward nudge regardless of how other tiers look.
- One deliberate behavioral consequence, locked in by a test: pure-Tank (and other non-damage) family tiers no longer receive DPS-based bonus suggestions at all.
- The Cavalry Instincts scenario itself is a test now: a damage echo and a mount-speed echo always active together, plus runs where only the utility echo differs -- the damage echo shows a large reliable delta, the utility echo shows an honest "insufficient".
- Transitional state, stated plainly: capture dual-writes the legacy per-echo store so older views (Tuning Advisor sample counts, AI report labels) keep working, and community sync still exchanges the legacy aggregates -- but suggestions are strictly local-evidence now, so shared community data currently influences nothing. Moving sync to shared with/without deltas (new format version) is the planned follow-up, after which the legacy store and dual-write go away.

### 3.27 (2026-07-19) -- Security policy, wiki, repo polish

Repo-only release, nothing changes in-game.

- New `SECURITY.md`: private vulnerability reporting (enabled on the repository), what actually counts as a security issue for a sandboxed WoW addon -- hostile sync payloads, malicious import strings, SavedVariables integrity, and consent around shared data -- and what's an ordinary bug instead.
- Wiki content written and versioned under `docs/wiki/`: Home, Getting Started, Settings, Localization, Development, Troubleshooting. GitHub only creates a wiki's git repository after its first page is made through the web UI, so publishing is `GITHUB_TOKEN=... sh scripts/publish-wiki.sh` after that one-time step -- the script syncs `docs/wiki/` to the wiki from then on.
- Repository description and topics set; README links the wiki and the security policy.

### 3.26 (2026-07-19) -- fix: screenshots matched to the right captions

Repo-only release, nothing changes in-game.

- 3.25's gallery had ten of the twelve screenshots attached to the wrong captions -- the upload order wasn't the filename order, and only two happened to line up by accident. Every image now actually shows what its caption says (verified against the images, not just renamed).

### 3.25 (2026-07-19) -- Screenshot tour on the repo page, all seven READMEs

Repo-only release, nothing changes in-game.

- Twelve in-game screenshots under `assets/screenshots/`, named by what they show, walking the addon's actual workflow in order: configure the build (Priorities, Modifiers, Autopilot), the Character tab (overview, complete talent trees, gear snapshot), running it (build overview, decision logbook), and learning from the data (stats summary, action statistics, recommendations, missing Echoes).
- The English README gets the full annotated tour; all six translated READMEs get the same gallery with translated section titles and captions.
- Screenshots stay out of `dist/EbonBuilds.zip` -- the packaging copies an explicit file list, so the addon download is unchanged.

### 3.24 (2026-07-19) -- Login panel: consent question and what's-new, once per version

New panel shown once after logging in, then it stays out of the way.

- It appears when the DPS-tracking consent question from 3.23 is still unanswered -- without this, an existing player whose tracking was reset to off by 3.23 would only find out by digging through Settings. Two buttons answer it ("Enable tracking & sharing" / "Keep it off"); either answer counts as answered and the panel never asks again. Changing your mind later is the same one checkbox in Settings it always was.
- It also appears once per new addon version with "What's new" (opens the changelog) and "Getting started" (opens the guide). Dismissing it marks the version as seen for that character; the same version never shows it twice.
- Nothing else: no reminders, no re-prompts, no showing up when there's nothing new to say.
- Tests cover the full decision table (unanswered consent, unseen version, seen version, version bump) and that declining counts as a real answer rather than a deferred nag.

### 3.23 (2026-07-19) -- Unified responsive editing, snapshot-first Character tab, explicit tracking consent (contributed)

Contributed by ha99dfs (PR #5), a large structural release building on 3.22's Character tab.

- The build editor is responsive across supported UI scales, and Save Build keeps you on the active tab with filters, selection, and scroll position intact instead of resetting the view.
- Stored character snapshots are now the single model behind viewed talents, glyphs, gear, and item affixes -- including viewing another character's snapshot -- backed by a complete 3.3.5a talent catalog and class-safe snapshot adoption with recovery for snapshots stored by older versions.
- New foundation layers (`core/Database.lua`, `Scheduler`, `EventHub`, `RingBuffer`, readiness/review/aggregate modules) give SavedVariables a single owner and bound all background work.
- Tuning proposals are now staged for explicit review instead of being applied to live strategies in the background.
- **Behavior change: DPS tracking and community sharing are opt-in again.** 3.13 turned tracking on by default; this release replaces that with an explicit per-character consent, and existing characters are reset to off until they opt in (Settings). The default-on approach meant data sharing happened without a deliberate choice -- this puts that choice back where it belongs. If you had tracking on and want it back, it's one checkbox.

### 3.22 (2026-07-19) -- Character tab: stored gear, full talent trees, glyphs, and snapshot adoption

New fifth tab in the build editor, "Character", closing out the last two prepared APIs from 3.20's orphan review (`GearScore.ScoreEquipped`'s scoring path and the talent capture machinery).

- **Snapshot-owned visual workspace**: Overview, Talents, and Gear always render the build's stored character snapshot, never the logged-in character. Talents uses one focused, centered four-column saved tree with compact WotLK spacing, spell icons, rank badges, captured prerequisite branches, tree tabs, an inspector, and a list fallback. A normal eight-tier tree fits in one view. Gear uses the saved item links/metadata in a responsive 19-slot paper doll with quality borders and a selected-item inspector.
- **Self-contained captures and legacy recovery**: new snapshots retain the complete talent presentation catalog and durable gear metadata needed for cross-character viewing. A compact built-in catalog reconstructs old rank-only snapshots from 3.3.5a spell IDs, producing localized names and native icons through the client while preserving the original allocation. Uncached saved items remain pending rather than becoming score zero or silently falling back to currently equipped gear.
- **3.3.5a safeguards**: the Character view has no permanent `OnUpdate`; saved-item cache retries are bounded and scheduler-coalesced, and talent/list/gear widgets are pooled while the view is open. Live equipment, talent, and glyph events do not replace or redraw the stored build snapshot.
- **Stable first render**: talent-tree centering uses the Character page's deterministic responsive geometry instead of the temporary width reported by a newly shown scroll frame, so it opens directly in its final centered position.
- **Class-safe adoption**: snapshots can be adopted only when the live character class matches the edited build. The control, BuildForm, and snapshot data layer all enforce the rule; changing the draft class removes a staged snapshot that no longer matches.
- **In-place editor saves**: Save Build commits the draft without leaving Priorities, Character, or the currently active editor tab. Filters, selection, and scroll position remain intact, and the committed build becomes the clean baseline for continued editing. Cancel remains the explicit route back to Overview.
- **Adopt snapshot**: one button writes the current gear, complete talent trees, and glyphs onto the build being edited. It follows the editor's normal draft flow -- persisted by Save, discarded by Cancel, exactly like every other edit -- and the tab shows what snapshot (if any) the build currently stores, with its capture time and a points/glyphs/items summary.
- **Snapshots travel with builds**: exported build strings and Public Builds now carry the snapshot, so a shared build can include its author's full setup rather than just weights. The roundtrip test for this immediately caught that both `DecodeBuild` and `Build.NewObject` field-filter imports -- the snapshot had to be threaded through both, and would otherwise have silently vanished on every import.
- New `modules/build/CharacterSnapshot.lua`, `modules/data/TalentCatalogData.lua`, `modules/data/TalentCatalog.lua`, and `modules/ui/CharacterView.lua`; tab label and hint translated in all six languages. Tests cover full-tree capture including rank-0 talents, all 829 fallback talents, tier/column ordering, legacy visual recovery, the glyph socket layout, adoption onto a build, the summary line, the export/import roundtrip, and the tab wiring.

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

- All six translated READMEs (Deutsch, Espa?ol, Fran?ais, Polski, Portugu?s (Brasil), ???????) now open with the same banner, status badges, and how-it-works diagram as the English one, with the language bar bolding its own language.
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

Worth knowing: enabling this also means your own tracked DPS-per-Echo data gets included in the periodic sync broadcast to your guild and current sync channel (same as it always did for anyone with tracking on) -- this default change means that now happens automatically instead of only for people who'd opted in. Turn it off any time in the Tuning Advisor (Settings, Windows & Tools).

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

- Added `scripts/publish-github-release.sh`, which creates a real GitHub Release (the page under `/releases`, with notes) for an already-pushed tag. Pushing a git tag alone only creates a ref ? it does not appear as a Release. The script pulls its title and notes directly from the matching `### <version>` section of this file.
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

- **New: `EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)`.** Compares each tracked echo's average DPS against other echoes currently sharing its exact weight value; if one deviates by 25%+ from that tier's average, suggests a modest (?10) weight nudge. Echoes from a co-active cluster larger than 3 (see 2.43) are excluded from both the comparison and the tier baseline, so one inflated/deflated group can't skew the whole tier.
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

- **New: class-filtered sync requests.** `/ebb` Public Builds Reload now sends the currently-selected class filter along with the sync request, so peers only send back builds for that class instead of their entire public/relayed collection. Old clients (pre-2.13) that receive this extra field simply ignore it and answer as before ? fully backward compatible. Tome Atlas sync (which needs all classes) is unaffected.

### 2.12 (2026-07-16)

- **Fixed: eight complete modules existed on disk but were never loaded.** `ClickTrace`, `ErrorLog`, `AffixItemScan`, `GearScore`, `Talents`, `TalentAutoLearn`, `BagAffixDots`, and `AutoSell` were fully written (including the `/ebb autosell` opt-in the code itself documented) but missing from `EbonBuilds.toc`, so none of them ever ran. All eight are now wired into the load order (dependency-safe), bootstrapped from `core/Init.lua`, and reachable via `/ebb autosell`, `/ebb bagdots`, `/ebb errors`, `/ebb clicktrace`.
- **Fixed: ClickTrace's own click-logging hook didn't exist.** Its header comment described logging every click via a hook in `Theme.CreateButton`, but that hook was never implemented ? even once loaded, it would have silently recorded nothing. Added the hook to `Theme.CreateButton` and a view-transition hook to `ViewRouter.Show`.

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
- **New: build chat links** ? `Chat Link` button on every build; clickable for addon users, click-to-fetch from any online owner (public builds only), plain text for everyone else.
- **Tome Atlas:** "Best farming" zone ranking for your missing tomes.
- **UI:** retail-style flat buttons across the entire addon (44 buttons reskinned).
- **Fixed (important):** message sanitizing could corrupt sync payloads whose fields start with `c`+hex digits (about 1 in 16 build ids!) or `r` ? silently breaking those transfers. Sanitizing is now anchored to the message start and can no longer touch payload content.

### 2.3 (2026-07-13)

- **Sync overhaul:** automatic retransmit of lost build transfers (bounded retries, multi-responder fallback), cross-responder download dedup, per-player request flood guard, sync summary toast, full sync tracing in `/ebb debug`, tome-share cap raised to 100 entries. Wire-compatible with older versions.

### 2.2 (2026-07-13)

- **New: Tome Atlas** ? community-shared drop database for echo tomes (mob + zone + observed count). Automatic recording on loot, automatic sharing via sync channel and guild, idempotent merging, search + missing-only filter, `/ebb atlas`. Old client versions safely ignore the new sync messages.

### 2.1 (2026-07-12)

- **Fixed: Pro editor Save silently failed on imported builds.** Saving a build imported from another player forks it under a new internal id (by design, so the original author's build stays intact); every save path now adopts the new id instead of writing to the deleted old one.
- **Fixed: opening the Settings tab could rewrite imported builds.** Programmatic slider refreshes clamped out-of-range values (e.g. freeze 150%) to the slider maximum and, combined with live persistence, saved the clamped value. Refreshes no longer write back.
- **Freeze and guard sliders now go up to 200%.** Since the peak excludes novelty, novel echoes can legitimately score above 100% of peak; thresholds above 100% are meaningful (e.g. "freeze only novelty-boosted hits").
- Note on flat novelty bonuses: a flat +100 novelty makes every unseen echo outrank known good ones and drains freeze/reroll charges. Prefer modest flat values or multiplier mode.

### 2.0 (2026-07-12)

**Automation correctness**
- Peak score now excludes the transient novelty bonus (stable thresholds for the whole run)
- Peak/EV caches are invalidated on build switch, build save, and new run (previously never ? stale thresholds after any change)
- Select no longer picks the echo frozen this round; local freeze state is cleared per choice screen and banish can no longer target a just-frozen echo
- No reroll while a freeze round is in flight
- Weights for class-prefixed echoes now apply (canonical name lookup shared between table and automation)

**Smart Reroll (new)**
- Opt-in expected-value reroll mode: rerolls when the best offer is below X% of the exact expected best-of-3 for your class and weights
- Mode toggle + slider in the Automation tab; Classic remains the default

**Settings tab**
- All changes persist immediately when editing an existing build (sliders on release, reset, model, family protection, priority ban list) ? fixes "reset did nothing"
- Live conflict warnings: banish ? freeze, guard < freeze
- Hover tooltips on every threshold slider with a worked example using your current peak
- Priority-order explainer (Banish ? Reroll ? Freeze ? Select) and reset-to-defaults button

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
