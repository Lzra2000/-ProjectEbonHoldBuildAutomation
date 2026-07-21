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

choices[1] = { spellId = 20, quality = 2 }
ProjectEbonhold.PerkUI.UpdateSinglePerk(0, choices[1])
assertEqual(#generations, 2, "replacement observation did not advance generation")

print("Standalone ProjectEbonhold request-only integration passed.")
