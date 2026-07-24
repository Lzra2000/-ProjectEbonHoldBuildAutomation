# WP5 constraints — client stepping stone (#54)

**Status:** partial (EbonBuilds client); server upload pending  
**Parent:** [#49](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/49) · [#54](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/54)  
**Design:** [`automation-server-redesign.md`](automation-server-redesign.md) §2 (constraints) + §4–5  
**Builds on:** WP1 board state, WP3 intent queue

## What shipped in EbonBuilds

| Piece | Location |
|---|---|
| Versioned constraints table + wire blob + hash | `modules/automation/Constraints.lua` |
| Attached to each evaluated board | `Automation.BuildBoard` → `Constraints.AttachToBoard` |
| `constraintsHash` on client intents | `IntentQueue.TryBegin` / `BuildSnapshot` |
| Stale-hash guard mid-board | `IntentQueue` clears in-flight intent when prefs hash changes |
| `Automation.GetConstraints()` | `modules/automation/Automation.lua` |
| Capabilities | `GetCapabilities().constraintsClient = true`, `serverConstraints = false` until PE ships upload |
| Unit tests | `tests/test_constraints.lua` |

### Packed prefs (v1)

Soft server inputs (honored when they do not violate hard rules):

| Field | Source |
|---|---|
| `protectFamilies` | Settings → protected families (`banishFamilyWhitelist`) |
| `echoPolicies` | Per-Echo policies (`EchoPolicy`) |
| Thresholds | `autoBanishPct`, `autoRerollPct`, `rerollGuardPct`, EV percents, `autoFreezePct`, `freezePenaltyPct`, `noveltyValue` |
| `rerollMode` | `sum` (classic) or `ev` (smart) |
| `echoBanList` / `echoWhitelist` | Explicit bans and preserves |
| `maxRerolls` | Remaining reroll charges from run data (hint, not a hard cap) |

Wire example:

```
v=1;rerollMode=ev;freezePenaltyPct=10;protectFamilies=caster,tank;policy=g:296:bos,s:101:np;maxRerolls=8
```

### Client behavior today

- Autopilot still runs the full client decide path (`serverPolicy = false`).
- Every board evaluation attaches the current constraints object and hash locally.
- Intent queue stores `constraintsHash` on each in-flight intent for future PE upload.

## Still required from ProjectEbonhold / server core

1. Constraints upload API (chunk-safe AddonMsg).
2. Ack / refresh on stale `constraintsHash` mid-board.
3. `serverConstraints` capability when PE accepts uploads.
4. `serverPolicy` capability to retire parallel decide (full WP5 acceptance).

See [`automation-server-redesign.md`](automation-server-redesign.md) for the target API sketch.
