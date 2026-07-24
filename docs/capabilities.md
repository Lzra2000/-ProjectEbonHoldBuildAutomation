# ProjectAPI capability flags

`EbonBuilds.ProjectAPI.GetCapabilities()` returns a read-only table of booleans
(and `addonVersion` / `actionConfirmation` strings) so UI and automation can
**soft-fail** when an older ProjectEbonhold build is installed. Probes use
`type(fn) == "function"` against live globals — never version numbers alone.

Reference PE client audited: `Interface/AddOns/ProjectEbonhold` (MPQ work copy,
2026-07). Automation redesign flags marked **planned** are intentionally `false`
until ProjectEbonhold exports them.

## Flag matrix

| Flag | Probe (present ⇒ true) | PE export / notes |
|------|------------------------|-------------------|
| `addonVersion` | number | `ProjectEbonhold.addonVersion` |
| `perkDatabase` | table | `ProjectEbonhold.PerkDatabase` |
| `perkData` | fn | `ProjectEbonhold.GetPerkData` |
| `totalPerkCount` | fn | `ProjectEbonhold.GetTotalPerkCount` |
| `descriptions` | fn | `_G.utils.GetSpellDescription` |
| `discoveredEchoes` | fn | `PerkService.GetDiscoveredEchoes` |
| `discoveryRequest` | fn | `PerkService.RequestEchoDiscovery` |
| `discoveryMutators` | fn ×2 | `AddDiscoveredEcho` + `RemoveDiscoveredEcho` |
| `activeLoadout` | fn ×2 | `SetActiveEchoLoadout` + `IsSpellInActiveEchoLoadout` (wishlist + server build match) |
| `sharedLoadouts` | fn ×2 | `RequestSharedEchoLoadouts` + `GetSharedEchoLoadouts` |
| `serverBuildSlots` | fn | `UploadServerBuildSlot` |
| `serverBuildSlotsEnabled` | runtime | `AreServerBuildSlotsEnabled()` when upload exists |
| `uploadServerBuildSlot` | fn | same as `serverBuildSlots` (legacy alias) |
| `activateServerBuildSlot` | fn | `ActivateServerBuildSlot` |
| `pendingBuildSlot` | fn | any of `UploadServerBuildSlot`, `SaveServerBuildSlot`, `RequestServerBuildSlots` |
| `tomeToggle` | fn ×2 | `ToggleTomeEcho` + `IsTomeEchoDisabled` |
| `lockedPerks` | fn | `GetLockedPerks` |
| `lockPerk` / `unlockPerk` | fn | `LockPerk` / `UnlockPerk` |
| `maxPermanentEchoes` | fn | `GetMaximumPermanentEchoes` |
| `snapshotEchoes` | fn | `SnapshotCurrentEchoes` |
| `pendingFlags` | Perks + fn | `ProjectEbonhold.Perks` table + `SelectPerk` (in-flight `pending*` fields) |
| `pendingRollsCount` | fn | `GetPendingRollsCount` |
| `rollsDebugInfo` | fn | `GetRollsDebugInfo` |
| `autoAcceptLoadoutEchoes` | fn | `ProjectEbonholdOptionsService.GetSetting` |
| `runData` | table/fn | `_G.EbonholdPlayerRunData` or `PlayerRunService.GetCurrentData` |
| `intensityData` | table/fn | `_G.EbonholdIntensityData` or `PlayerRunService.GetIntensityData` |
| `actionConfirmation` | string | `"request_only"` when `PerkService` exists; else `"unavailable"` |
| `boardState` | module | EbonBuilds `AutomationBoardStateMachine` (client derive path) |
| `serverBoardState` | Perks | `Perks.GetBoardState()` or `Perks.boardState` — **not in current PE** |
| `intentQueueClient` | module | EbonBuilds `AutomationIntentQueue` |
| `serverIntentAck` | Perks fn | `Perks.GetIntentAck` — **not in current PE** |
| `serverPolicy` | — | always `false` until PE policy oracle lands (**planned**) |

## PE PerkService exports without a dedicated flag

EbonBuilds wraps or calls these opportunistically; absence is handled with
nil/false returns, not capability gates:

- Action requests: `RequestChoice`, `SelectPerk`, `BanishPerk`, `FreezePerk`,
  `RequestReroll`, `RequestGrantedPerks`
- Choice read: `GetCurrentChoice` (always attempted when `PerkService` exists)
- Local library: `GetEchoLoadouts`, `SaveEchoLoadout`, `DeleteEchoLoadout`,
  `UpdateEchoLoadout`, `ExportEchoLoadout`, `ImportEchoLoadout`
- Community: `PublishEchoLoadout`, `UnpublishEchoLoadout`
- Server slots (partial): `GetServerBuildSlots`, `RequestServerBuildSlots`,
  `SaveServerBuildSlot`, `RenameServerBuildSlot`, `DeleteServerBuildSlot`, …

## UI consumers

| Module | Flags checked |
|--------|---------------|
| `BuildOverview.lua` | `lockPerk`, `unlockPerk`, `lockedPerks`, `maxPermanentEchoes`, `snapshotEchoes` |
| `TomeAtlasView.lua` | `tomeToggle` |

Automation reads pending state via `GetPendingAction()` / `GetBoardState()` rather
than capability flags directly, but relies on `pendingFlags` / `pendingBuildSlot`
being accurate for duplicate-request avoidance.

## Tests

- `tests/test_project_api.lua` — integration + gating regressions
- `tests/test_capabilities_audit.lua` — full PE-shaped mock vs expected flags
