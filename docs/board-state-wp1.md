# WP1 board state — client stepping stone (#50)

**Status:** partial (EbonBuilds client); server authority pending  
**Parent:** [#49](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/49) · [#50](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/50)  
**Design:** [`automation-server-redesign.md`](automation-server-redesign.md) §2

## What shipped in EbonBuilds

| Piece | Location |
|---|---|
| Lifecycle states `OPEN` / `FROZEN_PENDING` / `CONFIRMED` / `SPENT` | `modules/automation/BoardStateMachine.lua` |
| Derivation from existing PE + Autopilot signals | same module (`Derive` / `Attach`) |
| Hard reroll block in `FROZEN_PENDING` and `CONFIRMED` | `BoardDecision.CanReroll`, `Automation.ExecuteDecision` |
| `ProjectAPI.GetBoardState()` + capabilities | `modules/integration/ProjectEbonholdAPI.lua` |
| Unit tests | `tests/test_board_state_machine.lua` |

### Derivation inputs (today)

Until ProjectEbonhold publishes authoritative `boardState`, EbonBuilds derives lifecycle from:

| Signal | Typical source | Maps to |
|---|---|---|
| `pendingFreezeSlot`, `frozenStateUncertain` | Autopilot runtime | `FROZEN_PENDING` |
| `ProjectEbonhold.Perks.pendingFreezeIndex` | PE pending flags | `FROZEN_PENDING` |
| `isFrozen` / `justFrozen` on choice entries | `SEND_PLAYER_PERK_CHOICE` / `SEND_FREEZE_PERK_RESULT` | `CONFIRMED` |
| `frozenEchoIDs` (run-persistent, #59) | Autopilot after accepted freeze | `CONFIRMED` |
| Empty board + in-flight select | PE pending / Autopilot | `SPENT` |
| None of the above on a visible board | — | `OPEN` |

When `Perks.boardState` or `Perks.GetBoardState()` appears on a future PE build, EbonBuilds prefers that value (`source = "server"`) and keeps derivation as fallback only.

### Reroll freeze-lock

While lifecycle is `FROZEN_PENDING` or `CONFIRMED`, Autopilot **never** submits `RequestReroll`, regardless of score thresholds. This encodes the #38 invariant ahead of server-side rejection.

Guaranteed cards (`isGuaranteed` / wire flag `3`) do not by themselves change lifecycle; they remain selectable and do not create a freeze lock unless a real freeze was confirmed.

## Still required from ProjectEbonhold / server core

These items complete [#50](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/50) acceptance criteria; they are **not** in this client PR:

1. **Server-owned state machine** — track per-`offerId`: `OPEN → FROZEN_PENDING → CONFIRMED → SPENT` on the core, not reconstructed in the client.
2. **Reject illegal intents** — `REQUEST_REROLL` (and document banish/second-freeze while pending) rejected with a stable machine-readable `reasonCode` while state is `FROZEN_PENDING` or `CONFIRMED`.
3. **Publish `boardState` + `offerId`** — new SS field or extension on choice/result bodies; expose via `ProjectEbonhold.Perks.boardState` or `Perks.GetBoardState()`.
4. **Capability / version gate** — so EbonBuilds sets `GetCapabilities().serverBoardState = true` and stops treating derivation as primary.
5. **Logbook surfacing** — server `reasonCode` on reject/transition (client already logs derived lifecycle in DebugLog when enabled).
6. **Dry-run fixture** — replay a #38-class transcript and assert zero rerolls in pending/confirmed (WP4 overlap).

### Suggested PE surface (sketch)

```lua
-- ProjectEbonhold.Perks (server-maintained)
offerId = "<monotonic or wire id>"
boardState = "OPEN" | "FROZEN_PENDING" | "CONFIRMED" | "SPENT"
boardStateReasonCode = "freeze_lock_pending" | ...

-- optional
function Perks:GetBoardState()
  return { state = self.boardState, offerId = self.offerId, reasonCode = self.boardStateReasonCode }
end
```

Server core must transition `FROZEN_PENDING → CONFIRMED` on successful `SEND_FREEZE_PERK_RESULT` **without** requiring a full board resend (preserve #42 / `justFrozen` path).

## Compatibility

| Client | Server | Behavior |
|---|---|---|
| This PR | Current PE (no `boardState`) | Derived lifecycle; reroll hard-blocked on pending/confirmed |
| Old EbonBuilds | Any | Unchanged (no `BoardStateMachine`) |
| This PR | Future PE with `boardState` | Server value wins; derivation is fallback |

Existing suites (`test_freeze_first.lua`, `test_freeze_recovery.lua`, …) must stay green; new coverage is in `test_board_state_machine.lua`.
