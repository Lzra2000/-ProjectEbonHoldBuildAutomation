# WP3 intent queue — client stepping stone (#52)

**Status:** partial (EbonBuilds client); server ack channel pending  
**Parent:** [#49](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/49) · [#52](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/52)  
**Design:** [`automation-server-redesign.md`](automation-server-redesign.md) §2 (intent queue) + §3 (API sketch)  
**Builds on:** [#67](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/pull/67) `GetPendingAction()` / `ProjectEbonhold.Perks` pending flags

## What shipped in EbonBuilds

| Piece | Location |
|---|---|
| One in-flight intent (select / freeze / banish / reroll) | `modules/automation/IntentQueue.lua` |
| Duplicate intent rejection | same module (`TryBegin`) |
| Ack via board identity change, PE pending drop, freeze confirm, or 8s TTL | `PollAck` + `Automation.ResolvePendingAction` / `CommitConfirmedFreeze` |
| Wired into Autopilot execution | `Automation.ExecuteDecision`, `RequestFreeze` |
| Unit tests | `tests/test_intent_queue.lua`, `tests/test_freeze_persistence.lua` |

### Client ack signals (today)

Until ProjectEbonhold publishes explicit intent acks, EbonBuilds clears the queue when:

| Signal | Source | Meaning |
|---|---|---|
| `identityFingerprint` changed | Autopilot board observation | Board offer updated (select / banish / reroll / new choice) |
| `GetPendingAction()` cleared after being set | PE `Perks` pending flags | Server finished handling the in-flight PE request |
| Freeze confirmed / abandoned | `Automation.CommitConfirmedFreeze` (+ board-change / recovery-give-up paths) | Freeze does not change identity; freeze-wait returns before `PollAck`, so confirmation must clear the queue explicitly |
| Intent TTL (8s) | `IntentQueue` | Avoid permanent stall if neither signal arrives |

While an intent is in flight, Autopilot **does not** submit a second `Request*` for any action type.

## Still required from ProjectEbonhold / server core

These items complete [#52](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/52) acceptance criteria; they are **not** in this client PR:

1. **CS intent request + SS ack** — new AddonMsg event IDs on `AAM0x9` (chunk-safe); payload includes `intentId`, `offerId`, `action`, `constraintsHash`.
2. **Ack body** — `intentStatus=accepted|rejected`, echoed `intentId`, `boardState`, policy verb, stable `reasonCode` / reason string.
3. **Server-side exclusivity** — reject a second intent while one is in-flight (mirror today's PE pending flags, but server-visible and Logbook-friendly).
4. **Apply after ack** — on `accepted`, PE may still call existing `REQUEST_FREEZE_PERK` / select / banish / reroll, or a single validated apply API.
5. **Capability gate** — e.g. `ProjectAPI.GetCapabilities().serverIntentAck = true` so EbonBuilds waits on SS ack instead of client-derived signals.
6. **Remove long poll-only recovery** — when acks are authoritative, freeze/board recovery loops can shrink (WP1 + WP3 overlap).

### Suggested PE surface (sketch)

```lua
-- ProjectEbonhold.PerkService (server-maintained)
function PerkService:SubmitAutomationIntent(intentId, offerId, action, targetSlot, constraintsHash)
  -- CS intent; returns local accept/reject only
end

-- SS handler -> ProjectEbonhold.Perks or EventHub fan-out
-- intentAck = { intentId, status = "accepted"|"rejected", boardState, reasonCode, reason }

function Perks:GetIntentAck()
  return self.lastIntentAck
end
```

EbonBuilds must **not** replace `ProjectEbonhold.onEventReceived` (adapter rules from #42).

## Compatibility

| Client | Server | Behavior |
|---|---|---|
| This PR | Current PE (no intent ack) | Client intent queue + `GetPendingAction()` guard |
| Old EbonBuilds | Any | Unchanged (no `IntentQueue`) |
| Future client | PE with intent ack | SS ack primary; client queue becomes thin wrapper |

Existing suites (`test_freeze_first.lua`, `test_project_api.lua`, …) must stay green; new coverage is in `test_intent_queue.lua`.
