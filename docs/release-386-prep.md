# EbonBuilds 3.86 release prep

!!! warning "Draft only — do not tag or publish"
    This page tracks **3.86 release readiness**. It is **not** a shipped version.
    Do **not** run `scripts/release.sh`, push a `v3.86` tag, or create a GitHub Release
    until you intentionally complete the pre-tag checklist below.

Last updated from `main` after **v3.85** (`v3.85..HEAD`), **2026-07-24** (post-[#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/102) merge).

## Readiness summary

| Area | Status |
|------|--------|
| **Tag / GitHub Release** | **Ready** — no EbonBuilds blockers; pre-tag checklist remains |
| **CHANGELOG `### 3.86`** | Draft on `main`; catch-up in this PR |
| **Merged since v3.85** | Ready to ship (see table below) |
| **Open blockers (EbonBuilds)** | **None** — [#96](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/96) and [#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/102) merged |
| **Recently cleared** | [#96](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/96) ([PR #96](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/96)); [#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/102) ([PR #102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/102)); [#94](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/94) ([PR #94](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/94)); [#97](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/97) ([PR #97](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/97)) |

!!! note "PE-side follow-up (not an EbonBuilds blocker)"
    [#112](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/112) tracks ProjectEbonhold loading `item_purchase.lua` so the **Shop/Vendor** affix path can appear. **Anvil** acquisition shipped in [#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/102); Vendor buttons stay hidden until PE loads the vendor popup — soft-fail, no errors.

### Merged to `main` since v3.85 (ready)

| PR | Summary |
|----|---------|
| [#88](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/88) | WotLK-inspired docs artwork and hero chrome |
| [#89](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/89) | WP3 client `IntentQueue` stepping stone |
| [#90](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/90) | WP2 shared automation tie-break policy |
| [#92](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/92) | Auctionator 2.6.3-pe1 ProjectEbonhold adaptation |
| [#93](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/93) | WP4 client dry-run simulator |
| [#94](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/94) | BoardDecision / Automation test coverage expansion |
| [#96](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/96) | ProjectEbonhold capability audit (`GetCapabilities` probes) |
| [#97](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/97) | WP5 client constraints packing (`AutomationConstraints`) |
| [#98](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/98) | CI dist zip package smoke check |
| [#99](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/99) | Pages link fixes; releases doc aligned with v3.85 |
| [#100](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/100) | Restore full in-game FAQ after MkDocs title regression |
| [#101](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/101) | SessionHistory logbook UX reliability pass |
| [#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/102) | Affix acquisition: ProjectEbonhold Anvil bridge |
| [#103](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/103) | Vendored Details!: Tiny Threat PE fork + install docs |
| [#104](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/104) | Harden Combuctor bag affix quality-dot integration |
| [#105](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/105) | Changelog catch-up (WP4; capability audit documented ahead of code) |
| [#107](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/107) | Harden AutoSell `GetAuctionItemClasses` for 3.3.5a |

## Draft GitHub Release body (DO NOT PUBLISH)

Short title at publish time: **`EbonBuilds 3.86`**

Body below matches the target `### 3.86` section in [Changelog](changelog.md)
**plus** the install preamble that `scripts/publish-github-release.sh` / the Release
workflow prepends. Replace `(Unreleased)` with the ship date when cutting the release.

---

**Install:** [Download EbonBuilds.zip](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/download/v3.86/EbonBuilds.zip)  
Extract it and drop the `EbonBuilds` folder into `Interface/AddOns/`.

Optional affix shopping: [Download Auctionator.zip](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/download/v3.86/Auctionator.zip) — extract to `Interface/AddOns/Auctionator` (EbonBuilds enables bridge features when present).

Optional threat meter: [Download Details_TinyThreat.zip](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/download/v3.86/Details_TinyThreat.zip) — extract to `Interface/AddOns/Details_TinyThreat` alongside Details!; see [Details!: Tiny Threat (PE)](details-tinythreat-pe.md).

### 3.86 (Unreleased) -- Automation stepping stones, Auctionator PE, and reliability fixes

Follow-up to 3.85: client-side automation work packages WP2–WP5 from the server-authoritative Autopilot redesign, Auctionator ProjectEbonhold adaptation, optional Details!: Tiny Threat PE fork, ProjectEbonhold Anvil affix acquisition bridge, expanded BoardDecision test coverage, reliability fixes for bag dots / AutoSell / SessionHistory / FAQ, and original WotLK-inspired GitHub Pages branding.

#### Added

- **Intent queue WP3 (#89 / #52):** new `IntentQueue` module — one in-flight autopilot intent (select/freeze/banish/reroll) with duplicate blocking; ack via board identity fingerprint, `GetPendingAction()` pending-flag drop, or 8s TTL. Wired into `Automation.ExecuteDecision` / `RequestFreeze` ahead of server intent-ack support. `ProjectAPI.GetCapabilities` exposes `intentQueueClient` and `serverIntentAck`. Docs in `docs/intent-queue-wp3.md`; tests in `tests/test_intent_queue.lua`.
- **Shared tie-break policy WP2 (#90 / #51):** centralized score → optional PE `rank` → slot index → spell ID → frozen-preference ordering in `Scoring` (`CompareCandidates` / `IsBetterCandidate`), wired through `BoardDecision` and `Automation.TrySelect` so equal-weight boards pick deterministically and align with the server redesign. Optional per-card `rank` from ProjectEbonhold offers; missing ranks fall back to slot-index ordering. `DebugServerRankMismatch` flags rank disagreements. Tests in `tests/test_tie_break.lua`.
- **Dry-run simulator WP4 (#93 / #53):** new `AutomationDryRun` module — pure offline evaluator returning policy verdicts (`select`/`freeze`/`banish`/`reroll`/`wait`) from board snapshots without calling ProjectEbonhold `Request*`. Transcript parser/replay for fixture directives and DebugLog/Logbook line hooks; checked-in #38-class fixture. Docs in `docs/dry-run-wp4.md`; tests in `tests/test_dry_run.lua`.
- **Constraints client WP5 (#97 / #54):** new `AutomationConstraints` module packs Autopilot prefs (protect families, echo policies, thresholds, bans/whitelist, reroll hints) into a versioned table, compact wire blob, and stable `constraintsHash`. Constraints attach on each board eval; `IntentQueue` stores the hash on in-flight intents and clears the queue when prefs change mid-board. `GetCapabilities()` exposes `constraintsClient`; `serverConstraints` and `serverPolicy` stay false until ProjectEbonhold ships upload/policy. Docs in `docs/constraints-wp5.md`; tests in `tests/test_constraints.lua`.
- **WotLK-inspired docs artwork (#88):** locally generated hero background, runic dividers, slate texture, favicon, and feature-card icon silhouettes via `scripts/generate-docs-art.py` — no Blizzard client assets. Homepage hero, framed sections, and gold/frost chrome in `extra.css`; favicon updated in `mkdocs.yml`.
- **Auctionator ProjectEbonhold adaptation (#92):** vendored fork **2.6.3-pe1** with affix search helpers (`AtrPE_BuildAffixSearchQuery`), PE hooks for **EbonBuilds Affixes** shopping-list sync, defensive AH scan/query wrappers, and **AuctionatorBridge** query delegation. Tests in `tests/test_auctionator_pe.lua`.
- **Details!: Tiny Threat PE fork (#103):** optional vendored `Details_TinyThreat` for WotLK 3.3.5a with PE compatibility fixes (threat/name API polyfills, realm-qualified names in `Threater()`). Ships as `Details_TinyThreat.zip` when the release workflow includes it; install guide in `docs/details-tinythreat-pe.md`.
- **Affix Anvil bridge (#102):** new `ProjectEbonholdAffixBridge` soft integration with PE ExtractionService / Enchanted Anvil — capability-gated **Anvil** / **Shop** row buttons and toolbar shortcuts on the Affixes tab (Vendor hidden until PE loads `ItemPurchasePopup`; see [#112](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/112)). Tests in `tests/test_pe_affix_bridge.lua`.

#### Changed

- **Automation server redesign docs:** WP2 tie-break chain, WP3 intent-queue stepping stone, WP4 dry-run transcript schema, and WP5 constraints wire format documented in `docs/automation-server-redesign.md`, `docs/intent-queue-wp3.md`, `docs/dry-run-wp4.md`, and `docs/constraints-wp5.md` to match landed client behavior.
- **ProjectEbonhold capability audit (#96):** tightened `ProjectAPI.GetCapabilities()` probes against live PE exports (`pendingFlags` requires `Perks` + `SelectPerk`; `pendingBuildSlot` follows the build-slot API family; `activeLoadout` requires both loadout setters and spell checks); explicit `serverPolicy = false` placeholder for the planned server oracle. Documented server-side gaps in `docs/capabilities.md`. Tests in `tests/test_capabilities_audit.lua`.
- **BoardDecision test coverage (#94):** `tests/test_board_decision_coverage.lua` — freeze-first reroll locks, equal-score tie-break ordering (slot index, server rank, frozen preference), pending/slot-busy waits via BSM + IntentQueue, and freeze-penalty threshold scoring through mocked BoardDecision/Automation paths.
- **SessionHistory logbook UX (#101):** harden Logbook rendering against nil access and scroll edge cases during long runs.
- **Docs site (#99):** fix broken GitHub Pages links and align the releases page with v3.85 shipping state.

#### Fixed

- **In-game FAQ content (#100):** restore the full generated FAQ after an MkDocs title change truncated in-game pages.
- **Combuctor bag affix dots (#104):** harden quality-dot integration for 3.3.5a quality detection and combat-lockdown / taint safety on Combuctor item buttons.
- **AutoSell auction categories (#107):** harden `GetAuctionItemClasses` edge cases so locale/category filters stay stable on 3.3.5a clients.

---

## Pre-tag checklist

- [x] EbonBuilds blockers [#96](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/96) and [#102](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/102) merged
- [ ] Move `### 3.86 (Unreleased)` → `### 3.86 (<date>)` in `CHANGELOG.md`
- [ ] Run `sh scripts/release.sh 3.86` (bumps `.toc`, regenerates FAQ / What's New, tags locally — **review before push**)
- [ ] Push `main` + `v3.86` tag (triggers Release workflow — **only when ready**)
- [ ] Verify `EbonBuilds.zip`, `Auctionator.zip`, and `Details_TinyThreat.zip` assets on the published release page
