-- Capability audit: GetCapabilities probes vs ProjectEbonhold.PerkService exports
-- (reference client perks_service.lua, 2026-07 MPQ work copy).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("CAPABILITIES AUDIT FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end
local function assertTrue(value, message)
    if not value then fail(message) end
end
local function assertFalse(value, message)
    if value then fail(message) end
end

function UnitClass() return "Paladin", "PALADIN" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 1000 end

-- Minimal PE-shaped globals matching the audited server addon surface.
ProjectEbonholdOptionsService = {
    GetSetting = function(_, key) return key == "autoAcceptLoadoutEchoes" and false or nil end,
}
_G.utils = { GetSpellDescription = function() return "desc" end }
EbonholdPlayerRunData = { remainingBanishes = 1 }
EbonholdIntensityData = { intensity = 0 }

local perks = {
    pendingSelectSpellId = nil,
    pendingBanishIndex = nil,
    pendingFreezeIndex = nil,
    pendingReroll = nil,
    pendingBuildSlotRequest = nil,
    pendingBuildSlotRequestAt = 0,
}

local function noop() return true end
local function noopTable() return {} end

ProjectEbonhold = {
    addonVersion = 42,
    GetPerkData = function() return {} end,
    GetTotalPerkCount = function() return 100 end,
    PerkDatabase = { [1] = { quality = 0 } },
    Perks = perks,
    PerkService = {
        SelectPerk = noop,
        GetCurrentChoice = noopTable,
        GetDiscoveredEchoes = noopTable,
        RequestEchoDiscovery = noop,
        AddDiscoveredEcho = noop,
        RemoveDiscoveredEcho = noop,
        SetActiveEchoLoadout = noop,
        IsSpellInActiveEchoLoadout = function() return false end,
        RequestSharedEchoLoadouts = noop,
        GetSharedEchoLoadouts = noopTable,
        UploadServerBuildSlot = noop,
        ActivateServerBuildSlot = noop,
        AreServerBuildSlotsEnabled = function() return true end,
        SaveServerBuildSlot = noop,
        RequestServerBuildSlots = noop,
        ToggleTomeEcho = noop,
        IsTomeEchoDisabled = function() return false end,
        GetLockedPerks = noopTable,
        LockPerk = noop,
        UnlockPerk = noop,
        GetMaximumPermanentEchoes = function() return 2 end,
        SnapshotCurrentEchoes = noopTable,
        GetPendingRollsCount = function() return 1 end,
        GetRollsDebugInfo = function() return 80, 0, 79 end,
    },
    PlayerRunService = {
        GetCurrentData = function() return EbonholdPlayerRunData end,
        GetIntensityData = function() return EbonholdIntensityData end,
    },
}

local addon = {}
local function loadAddonFile(path)
    local chunk, err = loadfile(path)
    if not chunk then fail(err) end
    local ok, result = pcall(chunk, "EbonBuilds", addon)
    if not ok then fail(path .. ": " .. tostring(result)) end
end

loadAddonFile("core/EventHub.lua")
loadAddonFile("modules/automation/BoardStateMachine.lua")
loadAddonFile("modules/integration/ProjectEbonholdAPI.lua")

local caps = addon.ProjectAPI.GetCapabilities()

local expectedTrue = {
    "perkDatabase", "perkData", "totalPerkCount", "descriptions",
    "discoveredEchoes", "discoveryRequest", "discoveryMutators",
    "activeLoadout", "sharedLoadouts",
    "serverBuildSlots", "serverBuildSlotsEnabled", "uploadServerBuildSlot",
    "activateServerBuildSlot", "pendingBuildSlot",
    "tomeToggle", "lockedPerks", "lockPerk", "unlockPerk",
    "maxPermanentEchoes", "snapshotEchoes",
    "pendingFlags", "pendingRollsCount", "rollsDebugInfo",
    "autoAcceptLoadoutEchoes", "runData", "intensityData", "boardState",
}

for _, key in ipairs(expectedTrue) do
    assertTrue(caps[key], "full PE mock: expected caps." .. key .. " = true")
end

local expectedFalse = {
    "serverBoardState", "serverIntentAck", "serverPolicy",
}

for _, key in ipairs(expectedFalse) do
    assertFalse(caps[key], "current PE ref: caps." .. key .. " must stay false")
end

assertTrue(caps.addonVersion == 42, "addonVersion passthrough")
assertTrue(caps.actionConfirmation == "request_only", "actionConfirmation mode")

-- Strip build-slot APIs: pendingBuildSlot must drop while pendingFlags remains.
ProjectEbonhold.PerkService.UploadServerBuildSlot = nil
ProjectEbonhold.PerkService.SaveServerBuildSlot = nil
ProjectEbonhold.PerkService.RequestServerBuildSlots = nil
caps = addon.ProjectAPI.GetCapabilities()
assertFalse(caps.pendingBuildSlot, "pendingBuildSlot without build-slot family")
assertTrue(caps.pendingFlags, "pendingFlags still valid with SelectPerk")

-- Strip SelectPerk: pendingFlags must clear even if Perks table exists.
ProjectEbonhold.PerkService.SelectPerk = nil
caps = addon.ProjectAPI.GetCapabilities()
assertFalse(caps.pendingFlags, "pendingFlags without SelectPerk")

-- activeLoadout requires both wishlist setters and loadout match probe.
ProjectEbonhold.PerkService.SelectPerk = noop
ProjectEbonhold.PerkService.IsSpellInActiveEchoLoadout = nil
caps = addon.ProjectAPI.GetCapabilities()
assertFalse(caps.activeLoadout, "activeLoadout needs IsSpellInActiveEchoLoadout")

print("Capability audit passed (PE ref alignment).")
