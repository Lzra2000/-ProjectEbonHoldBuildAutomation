local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/ProjectEbonholdAPI.lua
-- Read-only compatibility adapter around the ProjectEbonhold globals that are
-- already exposed by the installed addon. EbonBuilds never replaces a
-- ProjectEbonhold handler and never calls onEventReceived(), because that API
-- stores one callback per event and would overwrite ProjectEbonhold's owner.
--
-- Actions use the request methods exposed by ProjectEbonhold.PerkService.
-- The unmodified addon does not expose a safe multi-listener acknowledgement
-- API, so EbonBuilds must never block later automation on inferred UI events.

EbonBuilds.ProjectAPI = {}

local API = EbonBuilds.ProjectAPI
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local initialized = false
local observationHooksInstalled = false
local choiceGeneration = 0
local showGeneration = 0
local hideGeneration = 0
local resetGeneration = 0
local replacementGeneration = 0
local requestSequence = 0

local function Service()
    return ProjectEbonhold and ProjectEbonhold.PerkService
end

local function Emit(signal, ...)
    if EbonBuilds.EventHub and EbonBuilds.EventHub.Bump then
        EbonBuilds.EventHub.Bump(signal, ...)
    end
end

local function BeginAction(action, target, invoker)
    if type(invoker) ~= "function" then return false end

    requestSequence = requestSequence + 1
    local requestId = requestSequence
    local ok, accepted = pcall(invoker)
    if not ok then
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("ProjectAPI." .. tostring(action), accepted)
        end
        return false
    end
    if accepted == false then return false end

    -- The installed ProjectEbonhold build exposes request methods but no safe
    -- multi-listener acknowledgement API. Return local request acceptance and
    -- let its own pending flags/server handlers remain authoritative. Blocking
    -- all later automation behind inferred UI transitions caused permanent
    -- stalls when one transition was absent or reordered.
    return true, requestId, choiceGeneration
end

function API.GetPlayerClassToken()
    local _, classToken = UnitClass("player")
    return classToken and tostring(classToken):upper() or nil
end

function API.GetCurrentChoice()
    local service = Service()
    if not service or type(service.GetCurrentChoice) ~= "function" then return nil end
    local ok, result = pcall(service.GetCurrentChoice)
    return ok and type(result) == "table" and result or nil
end

function API.GetDiscoveryState()
    local service = Service()
    if not service or type(service.GetDiscoveredEchoes) ~= "function" then return nil, false end
    local ok, result = pcall(service.GetDiscoveredEchoes)
    if not ok or type(result) ~= "table" then return nil, false end
    local live = ProjectEbonhold and ProjectEbonhold.Perks
        and type(ProjectEbonhold.Perks.discoveredEchoes) == "table"
    return result, live and true or false
end

function API.GetAddonVersion()
    return tonumber(ProjectEbonhold and ProjectEbonhold.addonVersion)
end

function API.GetModVersion()
    return ProjectEbonhold and ProjectEbonhold.modVersion or nil
end

function API.GetPerkDatabase()
    return ProjectEbonhold and ProjectEbonhold.PerkDatabase or nil
end

function API.GetPerkData(spellId)
    spellId = tonumber(spellId)
    if not spellId or not ProjectEbonhold then return nil end
    if type(ProjectEbonhold.GetPerkData) == "function" then
        local ok, result = pcall(ProjectEbonhold.GetPerkData, spellId)
        if ok and type(result) == "table" then return result end
    end
    local database = ProjectEbonhold.PerkDatabase
    return database and (database[spellId] or database[tostring(spellId)]) or nil
end

function API.GetSpellDescription(spellId, maxLength, stacks)
    spellId = tonumber(spellId)
    if not spellId then return nil end
    local helper = _G.utils and _G.utils.GetSpellDescription
    if type(helper) ~= "function" then return nil end
    local ok, description = pcall(helper, spellId, tonumber(maxLength) or 500, tonumber(stacks) or 1)
    if ok and type(description) == "string" and description ~= "" then return description end
    return nil
end

function API.ClassMask(classToken)
    return CLASS_BITS[tostring(classToken or ""):upper()]
end

function API.IsPerkAvailableForClass(spellId, classToken)
    spellId = tonumber(spellId)
    if EbonBuilds.EchoEligibilityResolver and EbonBuilds.EchoCatalog then
        local state = EbonBuilds.EchoEligibilityResolver.ResolveVariant(spellId, classToken)
        return EbonBuilds.EchoEligibilityResolver.IsAvailableState(state)
    end
    local classMask = API.ClassMask(classToken)
    if not spellId or not classMask then return false end
    local data = API.GetPerkData(spellId)
    local availableMask = tonumber(data and data.classMask) or 0
    return availableMask ~= 0 and bit.band(availableMask, classMask) ~= 0
end

function API.GetTotalPerkCount()
    if ProjectEbonhold and type(ProjectEbonhold.GetTotalPerkCount) == "function" then
        local ok, result = pcall(ProjectEbonhold.GetTotalPerkCount)
        if ok then return tonumber(result) or 0 end
    end
    local count = 0
    for _ in pairs(API.GetPerkDatabase() or {}) do count = count + 1 end
    return count
end

function API.RequestEchoDiscovery()
    local service = Service()
    if not service or type(service.RequestEchoDiscovery) ~= "function" then return false end
    local ok, result = pcall(service.RequestEchoDiscovery)
    return ok and result ~= false
end

function API.IsSpellInActiveEchoLoadout(spellId)
    local service = Service()
    if not service or type(service.IsSpellInActiveEchoLoadout) ~= "function" then return false end
    local ok, result = pcall(service.IsSpellInActiveEchoLoadout, tonumber(spellId))
    return ok and result and true or false
end

function API.GetDiscoveredEchoes()
    local service = Service()
    if not service or type(service.GetDiscoveredEchoes) ~= "function" then return nil end
    local ok, result = pcall(service.GetDiscoveredEchoes)
    return ok and type(result) == "table" and result or nil
end

function API.GetActiveEchoLoadout()
    local service = Service()
    if not service or type(service.GetActiveEchoLoadout) ~= "function" then return nil end
    local ok, result = pcall(service.GetActiveEchoLoadout)
    return ok and type(result) == "table" and result or nil
end

function API.SetActiveEchoLoadout(loadout)
    local service = Service()
    if not service or type(service.SetActiveEchoLoadout) ~= "function" then return false end
    local ok, result = pcall(service.SetActiveEchoLoadout, loadout)
    return ok and result ~= false
end

function API.GetSharedEchoLoadouts()
    local service = Service()
    if not service or type(service.GetSharedEchoLoadouts) ~= "function" then return nil end
    local ok, result = pcall(service.GetSharedEchoLoadouts)
    return ok and type(result) == "table" and result or nil
end

function API.RequestSharedEchoLoadouts(classToken)
    local service = Service()
    if not service or type(service.RequestSharedEchoLoadouts) ~= "function" then return false end
    local ok, result = pcall(service.RequestSharedEchoLoadouts, tostring(classToken or ""):upper())
    return ok and result ~= false
end

function API.GetChoiceGeneration()
    return choiceGeneration
end

function API.GetPendingAction()
    return nil
end

function API.HasActionObservers()
    -- No reliable acknowledgement fan-out is exposed by the unmodified base
    -- addon. Kept only as a compatibility query for older EbonBuilds modules.
    return false
end

function API.RequestSelect(spellId)
    local service = Service()
    if not service or type(service.SelectPerk) ~= "function" then return false end
    spellId = tonumber(spellId)
    return BeginAction("select", spellId, function() return service.SelectPerk(spellId) end)
end

function API.RequestBanish(index)
    local service = Service()
    if not service or type(service.BanishPerk) ~= "function" then return false end
    index = tonumber(index)
    return BeginAction("banish", index, function() return service.BanishPerk(index) end)
end

function API.RequestFreeze(index)
    local service = Service()
    if not service or type(service.FreezePerk) ~= "function" then return false end
    index = tonumber(index)
    return BeginAction("freeze", index, function() return service.FreezePerk(index) end)
end

function API.RequestReroll()
    local service = Service()
    if not service or type(service.RequestReroll) ~= "function" then return false end
    return BeginAction("reroll", nil, function() return service.RequestReroll() end)
end

local function InstallObservationHooks()
    if observationHooksInstalled then return true end
    local ui = ProjectEbonhold and ProjectEbonhold.PerkUI
    if not ui or type(hooksecurefunc) ~= "function" then return false end

    if type(ui.Show) == "function" then
        hooksecurefunc(ui, "Show", function(choices)
            showGeneration = showGeneration + 1
            choiceGeneration = choiceGeneration + 1
            Emit("PROJECT_CHOICE_CHANGED", choiceGeneration, choices or API.GetCurrentChoice())
        end)
    end

    if type(ui.Hide) == "function" then
        hooksecurefunc(ui, "Hide", function()
            hideGeneration = hideGeneration + 1
        end)
    end

    if type(ui.ResetSelection) == "function" then
        hooksecurefunc(ui, "ResetSelection", function()
            resetGeneration = resetGeneration + 1
        end)
    end

    if type(ui.UpdateSinglePerk) == "function" then
        hooksecurefunc(ui, "UpdateSinglePerk", function()
            replacementGeneration = replacementGeneration + 1
            choiceGeneration = choiceGeneration + 1
            Emit("PROJECT_CHOICE_CHANGED", choiceGeneration, API.GetCurrentChoice())
        end)
    end

    observationHooksInstalled = true
    return true
end

function API.Init()
    if not initialized then initialized = true end
    InstallObservationHooks()
    return Service() ~= nil
end

function API.GetCapabilities()
    local service = Service()
    return {
        addonVersion = API.GetAddonVersion(),
        perkDatabase = API.GetPerkDatabase() ~= nil,
        perkData = ProjectEbonhold and type(ProjectEbonhold.GetPerkData) == "function" or false,
        totalPerkCount = ProjectEbonhold and type(ProjectEbonhold.GetTotalPerkCount) == "function" or false,
        descriptions = _G.utils and type(_G.utils.GetSpellDescription) == "function" or false,
        discoveredEchoes = service and type(service.GetDiscoveredEchoes) == "function" or false,
        discoveryRequest = service and type(service.RequestEchoDiscovery) == "function" or false,
        activeLoadout = service and type(service.SetActiveEchoLoadout) == "function" or false,
        sharedLoadouts = service and type(service.RequestSharedEchoLoadouts) == "function"
            and type(service.GetSharedEchoLoadouts) == "function" or false,
        actionConfirmation = service and "request_only" or "unavailable",
    }
end
