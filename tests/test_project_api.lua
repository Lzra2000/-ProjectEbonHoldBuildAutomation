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

function UnitClass() return "Paladin", "PALADIN" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

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
loadAddonFile("modules/integration/ProjectEbonholdAPI.lua")
assertTrue(addon.ProjectAPI.Init(), "standalone request adapter did not initialize")
assertEqual(addon.ProjectAPI.GetCapabilities().actionConfirmation, "request_only", "wrong action mode")
assertTrue(not addon.ProjectAPI.HasActionObservers(), "unmodified base addon was reported as acknowledgement-capable")

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
