-- Standalone ProjectEbonhold integration tests. The unmodified base addon
-- exposes request methods and read-only choice state, but no safe multi-listener
-- acknowledgement API. EbonBuilds must therefore never block later requests on
-- inferred UI transitions.
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("PROJECT API FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end
local function assertTrue(value, message)
    if not value then fail(message) end
end
local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end
local function assertFalse(value, message)
    if value then fail(message) end
end

function UnitClass() return "Paladin", "PALADIN" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local now = 1000
function GetTime() return now end

function hooksecurefunc(owner, methodName, postHook)
    local original = owner[methodName]
    owner[methodName] = function(...)
        local results = { original(...) }
        postHook(...)
        return unpack(results)
    end
end

local choices
local calls = { select = 0, banish = 0, freeze = 0, reroll = 0 }
local loadoutSpellIds = {}
local optionSettings = { autoAcceptLoadoutEchoes = false }

ProjectEbonholdOptionsService = {
    GetSetting = function(_, key)
        return optionSettings[key]
    end,
}

ProjectEbonhold = {
    PerkDatabase = {},
    PerkUI = {
        Show = function() end,
        Hide = function() end,
        ResetSelection = function() end,
        UpdateSinglePerk = function() end,
    },
    PerkService = {
        GetCurrentChoice = function() return choices end,
        SelectPerk = function(spellId)
            calls.select = calls.select + 1
            if not choices then return false end
            for index = 1, #choices do
                if choices[index].spellId == spellId then return true end
            end
            return false
        end,
        BanishPerk = function(index)
            calls.banish = calls.banish + 1
            return choices and choices[index + 1] ~= nil
        end,
        FreezePerk = function(index)
            calls.freeze = calls.freeze + 1
            return choices and choices[index + 1] ~= nil
        end,
        RequestReroll = function()
            calls.reroll = calls.reroll + 1
            return choices ~= nil
        end,
        GetPendingRollsCount = function()
            return 7
        end,
        GetRollsDebugInfo = function()
            return 12, 5, 7
        end,
        IsSpellInActiveEchoLoadout = function(spellId)
            return loadoutSpellIds[tonumber(spellId)] == true
        end,
    },
    PlayerRunService = {
        GetCurrentData = function()
            return {
                remainingBanishes = 3,
                totalRerolls = 10,
                usedRerolls = 2,
                totalFreezes = 4,
                usedFreezes = 1,
                soulPoints = 42,
                hasReachedMaxLevel = false,
                catchupMultiplierPct = 0,
            }
        end,
        GetIntensityData = function()
            return { intensity = 2, areaNameReaper = "a", zoneNameReaper = "z" }
        end,
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
assertTrue(addon.ProjectAPI.Init(), "standalone request adapter did not initialize")
assertEqual(addon.ProjectAPI.GetCapabilities().actionConfirmation, "request_only", "wrong action mode")
assertTrue(not addon.ProjectAPI.HasActionObservers(), "unmodified base addon was reported as acknowledgement-capable")

local caps = addon.ProjectAPI.GetCapabilities()
assertTrue(caps.boardState, "boardState capability missing")
assertTrue(not caps.serverBoardState, "serverBoardState should be false without PE boardState")
local derived = addon.ProjectAPI.GetBoardState({
    choices = { { spellId = 1 }, { spellId = 2, justFrozen = true } },
    frozenCount = 1,
})
assertEqual(derived and derived.state, "CONFIRMED", "GetBoardState did not derive CONFIRMED")
assertEqual(derived and derived.source, "derived", "GetBoardState source should be derived")

assertTrue(caps.pendingRollsCount, "pendingRollsCount capability missing")
assertTrue(caps.rollsDebugInfo, "rollsDebugInfo capability missing")
assertTrue(caps.autoAcceptLoadoutEchoes, "autoAcceptLoadoutEchoes capability missing")
assertTrue(caps.runData, "runData capability missing")
assertTrue(caps.intensityData, "intensityData capability missing")

local generations = {}
addon.EventHub.On("PROJECT_CHOICE_CHANGED", function(_, generation)
    generations[#generations + 1] = generation
end, "ProjectAPITest")

choices = { { spellId = 10, quality = 1 }, { spellId = 11, quality = 0 } }
ProjectEbonhold.PerkUI.Show(choices)
assertEqual(#generations, 1, "choice observation did not fire")

-- Requests are forwarded directly and are not serialized behind an inferred
-- pendingAction record. ProjectEbonhold's own service remains responsible for
-- rejecting genuinely duplicated or invalid requests.
assertTrue(addon.ProjectAPI.RequestSelect(10), "select request was rejected locally")
assertTrue(addon.ProjectAPI.RequestBanish(0), "banish request was rejected locally")
assertTrue(addon.ProjectAPI.RequestFreeze(1), "freeze request was rejected locally")
assertTrue(addon.ProjectAPI.RequestReroll(), "reroll request was rejected locally")
assertEqual(calls.select, 1, "select was not forwarded")
assertEqual(calls.banish, 1, "banish was not forwarded")
assertEqual(calls.freeze, 1, "freeze was not forwarded")
assertEqual(calls.reroll, 1, "reroll was not forwarded")
assertTrue(addon.ProjectAPI.GetPendingAction() == nil, "adapter retained a blocking pending action")

-- The server distribution tracks one in-flight request per action on
-- ProjectEbonhold.Perks. The adapter must surface these flags so automation
-- waits instead of firing a duplicate request that the service would refuse.
ProjectEbonhold.Perks = {}
assertTrue(addon.ProjectAPI.GetCapabilities().pendingFlags, "pendingFlags capability missing after Perks exists")
assertTrue(addon.ProjectAPI.GetCapabilities().pendingBuildSlot, "pendingBuildSlot capability missing after Perks exists")
assertTrue(addon.ProjectAPI.GetPendingAction() == nil, "empty server pending flags reported an action")
ProjectEbonhold.Perks.pendingSelectSpellId = 10
assertEqual(addon.ProjectAPI.GetPendingAction(), "select", "in-flight select was not reported")
ProjectEbonhold.Perks.pendingSelectSpellId = nil
ProjectEbonhold.Perks.pendingBanishIndex = 0
assertEqual(addon.ProjectAPI.GetPendingAction(), "banish", "in-flight banish was not reported")
ProjectEbonhold.Perks.pendingBanishIndex = nil
ProjectEbonhold.Perks.pendingFreezeIndex = 2
assertEqual(addon.ProjectAPI.GetPendingAction(), "freeze", "in-flight freeze was not reported")
ProjectEbonhold.Perks.pendingFreezeIndex = nil
ProjectEbonhold.Perks.pendingReroll = true
assertEqual(addon.ProjectAPI.GetPendingAction(), "reroll", "in-flight reroll was not reported")
ProjectEbonhold.Perks.pendingReroll = nil
assertTrue(addon.ProjectAPI.GetPendingAction() == nil, "cleared server pending flags still reported an action")

-- Build-slot busy flag (save/activate/upload) must block like action pending.
ProjectEbonhold.Perks.pendingBuildSlotRequest = "save"
ProjectEbonhold.Perks.pendingBuildSlotRequestAt = now
assertEqual(addon.ProjectAPI.GetPendingAction(), "slot", "busy build-slot request was not reported")
now = now + 4
assertTrue(addon.ProjectAPI.GetPendingAction() == nil, "expired build-slot request still blocked")
assertTrue(ProjectEbonhold.Perks.pendingBuildSlotRequest == nil, "expired build-slot flag was not cleared")

assertEqual(addon.ProjectAPI.GetPendingRollsCount(), 7, "pending rolls count was not wrapped")
local level, picksMade, rollsLeft = addon.ProjectAPI.GetRollsDebugInfo()
assertEqual(level, 12, "rolls debug level mismatch")
assertEqual(picksMade, 5, "rolls debug picksMade mismatch")
assertEqual(rollsLeft, 7, "rolls debug rollsLeft mismatch")

assertFalse(addon.ProjectAPI.IsAutoAcceptLoadoutEchoes(), "auto-accept default should be off")
assertFalse(addon.ProjectAPI.WillAutoAcceptChoice(choices), "auto-accept should not fire when option is off")
optionSettings.autoAcceptLoadoutEchoes = true
assertTrue(addon.ProjectAPI.IsAutoAcceptLoadoutEchoes(), "auto-accept option was not detected")
assertFalse(addon.ProjectAPI.WillAutoAcceptChoice(choices), "auto-accept should require a loadout match")
loadoutSpellIds[10] = true
assertTrue(addon.ProjectAPI.WillAutoAcceptChoice(choices), "auto-accept loadout match was missed")
optionSettings.autoAcceptLoadoutEchoes = false
assertFalse(addon.ProjectAPI.WillAutoAcceptChoice(choices), "auto-accept still matched after option off")

local runData = addon.ProjectAPI.GetRunData()
assertTrue(runData and runData.remainingBanishes == 3, "run data was not routed through ProjectAPI")
local intensity = addon.ProjectAPI.GetIntensityData()
assertTrue(intensity and intensity.intensity == 2, "intensity data was not routed through ProjectAPI")

-- Missing APIs stay nil/false so legacy paths remain unchanged.
ProjectEbonhold.PerkService.GetPendingRollsCount = nil
ProjectEbonhold.PerkService.GetRollsDebugInfo = nil
ProjectEbonholdOptionsService = nil
assertTrue(addon.ProjectAPI.GetPendingRollsCount() == nil, "missing rolls count should be nil")
local missingLevel = addon.ProjectAPI.GetRollsDebugInfo()
assertTrue(missingLevel == nil, "missing rolls debug should be nil")
assertFalse(addon.ProjectAPI.IsAutoAcceptLoadoutEchoes(), "missing options service should report auto-accept off")
assertFalse(addon.ProjectAPI.GetCapabilities().autoAcceptLoadoutEchoes, "missing options capability should be false")

choices[1] = { spellId = 20, quality = 2 }
ProjectEbonhold.PerkUI.UpdateSinglePerk(0, choices[1])
assertEqual(#generations, 2, "replacement observation did not advance generation")

------------------------------------------------------------------------
-- Server build-slot bridge (#57): mapping + capability-gated stubs
------------------------------------------------------------------------

-- lockedEchoes -> designed slot payload {spellId, stacks, locked}
do
    addon.Build = { LOCKED_SLOTS = 6 }
    ProjectEbonhold.PerkDatabase = {
        [101] = { quality = 2, classMask = 128 }, -- Mage
        [102] = { quality = 1, classMask = 1 },   -- Warrior only
        [103] = { quality = 0, classMask = 128 },
    }
    bit = bit or {
        band = function(a, b)
            local r, p = 0, 1
            while a > 0 and b > 0 do
                local aa, bb = a % 2, b % 2
                if aa == 1 and bb == 1 then r = r + p end
                a, b, p = (a - aa) / 2, (b - bb) / 2, p * 2
            end
            return r
        end,
    }

    local echoes, skipped = addon.ProjectAPI.MapLockedEchoesToServerSlot(
        { 101, nil, 102, 103 }, { classToken = "MAGE", lockAll = true })
    assertEqual(#echoes, 2, "class-invalid locked echo should be skipped")
    assertEqual(skipped, 1, "skipped count for warrior-only echo")
    assertEqual(echoes[1].spellId, 101, "first mapped spellId")
    assertEqual(echoes[1].stacks, 1, "default stacks")
    assertTrue(echoes[1].locked == true, "locked flag for designed slot")
    assertEqual(echoes[2].spellId, 103, "second mapped spellId")

    local wish = addon.ProjectAPI.MapLockedEchoesToWishlist({ 101, 103 })
    assertEqual(#wish, 2, "wishlist mapping count")
    assertEqual(wish[1].quality, 2, "wishlist quality from PerkDatabase")
    assertEqual(wish[1].stacks, 1, "wishlist stacks")
end

-- Capability gating: missing Upload => not enabled; present + flag off => disabled
do
    local caps = addon.ProjectAPI.GetCapabilities()
    assertTrue(not caps.serverBuildSlots, "upload absent should clear serverBuildSlots capability")

    local uploads = {}
    ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
        uploads[#uploads + 1] = { slot = slot, name = name, echoes = echoes }
        return true
    end
    ProjectEbonhold.PerkService.ActivateServerBuildSlot = function(slot)
        return true
    end
    ProjectEbonhold.PerkService.GetServerBuildSlots = function()
        return { { id = 1, name = "A" } }
    end
    ProjectEbonhold.PerkService.AreServerBuildSlotsEnabled = function()
        return false
    end
    ProjectEbonhold.PerkService.SetActiveEchoLoadout = function(loadout)
        return loadout and loadout.echoes and #loadout.echoes > 0
    end

    caps = addon.ProjectAPI.GetCapabilities()
    assertTrue(caps.serverBuildSlots, "Upload present should advertise serverBuildSlots")
    assertTrue(not caps.serverBuildSlotsEnabled, "disabled flag should surface")
    assertTrue(not addon.ProjectAPI.UploadServerBuildSlot(0, "x", { { spellId = 1, stacks = 1, locked = true } }),
        "upload must refuse when slots disabled")

    ProjectEbonhold.PerkService.AreServerBuildSlotsEnabled = function() return true end
    assertTrue(addon.ProjectAPI.AreServerBuildSlotsEnabled(), "enabled probe")
    assertTrue(addon.ProjectAPI.UploadServerBuildSlot(0, "My Loadout", {
        { spellId = 101, stacks = 1, locked = true },
    }), "upload should forward when enabled")
    assertEqual(#uploads, 1, "upload call count")
    assertEqual(uploads[1].slot, 0, "new designed slot uses 0")
    assertEqual(uploads[1].name, "My Loadout", "upload name")
    assertEqual(uploads[1].echoes[1].spellId, 101, "upload echo payload")

    local ok, err, info = addon.ProjectAPI.UploadBuildAsServerSlot({
        title = "Public Mage",
        class = "MAGE",
        author = "OtherPlayer",
        lockedEchoes = { 101, 102 },
        -- Weights / snapshot must never be read by the upload path.
        echoWeights = { [101] = 99 },
        characterSnapshot = { talents = { tabs = {} }, gear = { { itemId = 1 } } },
    }, 0)
    assertTrue(ok, "UploadBuildAsServerSlot should succeed")
    assertEqual(err, nil, "no error key")
    assertEqual(info.count, 1, "only class-usable echoes uploaded")
    assertEqual(info.skipped, 1, "warrior echo skipped")
    assertEqual(#uploads, 2, "second upload from helper")
    assertEqual(uploads[2].echoes[1].locked, true, "designed locked flag")
end

-- Foreign + Auto-Accept warn flag; wishlist apply does not touch snapshots
do
    ProjectEbonholdOptionsService = {
        GetSetting = function(_, key)
            return key == "autoAcceptLoadoutEchoes"
        end,
    }
    function UnitName() return "Me" end

    assertTrue(addon.ProjectAPI.IsForeignBuild({ author = "Other", lockedEchoes = { 101 } }),
        "other author is foreign")
    assertTrue(addon.ProjectAPI.IsForeignBuild({ importedFrom = "pub-1" }),
        "importedFrom marks foreign")
    assertTrue(not addon.ProjectAPI.IsForeignBuild({ author = "Me" }), "own author is local")
    assertTrue(addon.ProjectAPI.IsAutoAcceptLoadoutEchoesEnabled(), "auto-accept probe")

    local ok, err, info = addon.ProjectAPI.ApplyBuildAsWishlist({
        title = "Foreign",
        class = "MAGE",
        author = "Other",
        lockedEchoes = { 101 },
        characterSnapshot = { gear = { { itemId = 99 } } },
    })
    assertTrue(ok, "wishlist apply ok")
    assertEqual(err, nil, "wishlist err")
    assertTrue(info.autoAcceptWarn, "foreign + auto-accept should warn")
end

-- Trust: mapping/upload helpers never call LearnTalent / EquipItem
do
    local apiSrc = assert(io.open("modules/integration/ProjectEbonholdAPI.lua", "rb"))
    local text = apiSrc:read("*a")
    apiSrc:close()
    assertTrue(not text:find("LearnTalent%s*%(", 1), "ProjectAPI must not call LearnTalent")
    assertTrue(not text:find("EquipItemByName", 1, true) and not text:find("EquipItem%s*%(", 1),
        "ProjectAPI must not auto-equip")
    assertTrue(text:find("characterSnapshot are intentionally ignored", 1, true),
        "upload helper documents snapshot ignore")
    assertTrue(text:find("MapLockedEchoesToServerSlot", 1, true), "mapping helper missing")
    assertTrue(text:find("UploadBuildAsServerSlot", 1, true), "upload helper missing")
end

print("Standalone ProjectEbonhold request-only integration passed.")

------------------------------------------------------------------------
-- Tome toggle + LockPerk family + SnapshotCurrentEchoes wrappers (#62)
------------------------------------------------------------------------

local tomeCalls = { toggle = 0, lock = 0, unlock = 0 }
local disabledTomes = {}
local lockedPerks = {}
local maxPermanent = 2
ProjectEbonhold.PerkDatabase = {
    [5001] = { requiredSpell = 105001, quality = 2 },
    [5002] = { requiredSpell = 105002, quality = 1 },
}
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function(spellId)
    return disabledTomes[spellId] == true
end
ProjectEbonhold.PerkService.ToggleTomeEcho = function(spellId)
    tomeCalls.toggle = tomeCalls.toggle + 1
    if disabledTomes[spellId] then
        disabledTomes[spellId] = nil
    else
        disabledTomes[spellId] = true
    end
    return true
end
ProjectEbonhold.PerkService.GetLockedPerks = function()
    return lockedPerks
end
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function()
    return maxPermanent
end
ProjectEbonhold.PerkService.LockPerk = function(spellId, count)
    tomeCalls.lock = tomeCalls.lock + 1
    lockedPerks[#lockedPerks + 1] = { spellId = spellId, stack = count or 1, quality = 2 }
    return true
end
ProjectEbonhold.PerkService.UnlockPerk = function(spellId)
    tomeCalls.unlock = tomeCalls.unlock + 1
    for i = #lockedPerks, 1, -1 do
        if lockedPerks[i].spellId == spellId then
            table.remove(lockedPerks, i)
        end
    end
    return true
end
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function()
    return {
        { spellId = 5001, quality = 2, stacks = 3 },
        { spellId = 5002, quality = 1, stacks = 1 },
    }
end
ProjectEbonhold.PerkService.AddDiscoveredEcho = function(spellId)
    return true
end
ProjectEbonhold.PerkService.RemoveDiscoveredEcho = function(spellId)
    return true
end

local caps = addon.ProjectAPI.GetCapabilities()
assertTrue(caps.tomeToggle, "tomeToggle capability missing")
assertTrue(caps.lockedPerks, "lockedPerks capability missing")
assertTrue(caps.lockPerk, "lockPerk capability missing")
assertTrue(caps.unlockPerk, "unlockPerk capability missing")
assertTrue(caps.maxPermanentEchoes, "maxPermanentEchoes capability missing")
assertTrue(caps.snapshotEchoes, "snapshotEchoes capability missing")
assertTrue(caps.discoveryMutators, "discoveryMutators capability missing")

assertEqual(addon.ProjectAPI.FindEchoSpellIdByTomeItem(105001), 5001, "tome item -> echo spellId")
assertEqual(addon.ProjectAPI.FindEchoSpellIdByTomeItem(105002), 5002, "second tome item -> echo spellId")
assertTrue(addon.ProjectAPI.FindEchoSpellIdByTomeItem(999999) == nil, "unknown tome item should miss")

assertTrue(not addon.ProjectAPI.IsTomeEchoDisabled(5001), "tome should start enabled")
assertTrue(addon.ProjectAPI.ToggleTomeEcho(5001), "toggle should accept")
assertEqual(tomeCalls.toggle, 1, "toggle was not forwarded")
assertTrue(addon.ProjectAPI.IsTomeEchoDisabled(5001), "tome should be disabled after toggle")
assertTrue(addon.ProjectAPI.ToggleTomeEcho(5001), "re-enable toggle should accept")
assertTrue(not addon.ProjectAPI.IsTomeEchoDisabled(5001), "tome should be enabled again")

assertEqual(addon.ProjectAPI.GetMaximumPermanentEchoes(), 2, "max permanent echoes")
assertEqual(#(addon.ProjectAPI.GetLockedPerks() or {}), 0, "locked perks should start empty")
assertTrue(addon.ProjectAPI.LockPerk(5001), "lock should accept")
assertEqual(tomeCalls.lock, 1, "lock was not forwarded")
assertEqual(#(addon.ProjectAPI.GetLockedPerks() or {}), 1, "locked perks after lock")
assertTrue(addon.ProjectAPI.UnlockPerk(5001), "unlock should accept")
assertEqual(tomeCalls.unlock, 1, "unlock was not forwarded")
assertEqual(#(addon.ProjectAPI.GetLockedPerks() or {}), 0, "locked perks after unlock")

local snap = addon.ProjectAPI.SnapshotCurrentEchoes()
assertTrue(type(snap) == "table" and #snap == 2, "snapshot should return two echoes")
assertEqual(snap[1].spellId, 5001, "snapshot first spellId")
assertTrue(addon.ProjectAPI.AddDiscoveredEcho(5001), "AddDiscoveredEcho should accept")
assertTrue(addon.ProjectAPI.RemoveDiscoveredEcho(5001), "RemoveDiscoveredEcho should accept")

-- Capability-gate: missing methods must report false / nil gracefully.
ProjectEbonhold.PerkService.ToggleTomeEcho = nil
ProjectEbonhold.PerkService.IsTomeEchoDisabled = nil
ProjectEbonhold.PerkService.GetLockedPerks = nil
ProjectEbonhold.PerkService.LockPerk = nil
ProjectEbonhold.PerkService.UnlockPerk = nil
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = nil
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = nil
ProjectEbonhold.PerkService.AddDiscoveredEcho = nil
ProjectEbonhold.PerkService.RemoveDiscoveredEcho = nil
local oldCaps = addon.ProjectAPI.GetCapabilities()
assertTrue(not oldCaps.tomeToggle, "missing tome APIs must clear tomeToggle")
assertTrue(not oldCaps.lockedPerks, "missing GetLockedPerks must clear lockedPerks")
assertTrue(not oldCaps.snapshotEchoes, "missing Snapshot must clear snapshotEchoes")
assertTrue(not addon.ProjectAPI.ToggleTomeEcho(5001), "toggle without API must no-op")
assertTrue(not addon.ProjectAPI.IsTomeEchoDisabled(5001), "disabled query without API must be false")
assertTrue(addon.ProjectAPI.GetLockedPerks() == nil, "locked perks without API must be nil")
assertEqual(addon.ProjectAPI.GetMaximumPermanentEchoes(), 0, "max without API must be 0")
assertTrue(not addon.ProjectAPI.LockPerk(5001), "lock without API must no-op")
assertTrue(not addon.ProjectAPI.UnlockPerk(5001), "unlock without API must no-op")
assertTrue(addon.ProjectAPI.SnapshotCurrentEchoes() == nil, "snapshot without API must be nil")

print("Tome toggle + LockPerk family wrappers passed.")
