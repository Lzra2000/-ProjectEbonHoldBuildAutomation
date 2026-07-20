-- EbonBuilds: modules/integration/ProjectEbonholdAPI.lua
-- Narrow, defensive adapter around the ProjectEbonhold public API surface.
-- Do not register server handlers here: ProjectEbonhold.onEventReceived stores
-- one handler per event and a second registration would replace its own handler.

EbonBuilds.ProjectAPI = {}

local API = EbonBuilds.ProjectAPI
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local function Service()
    return ProjectEbonhold and ProjectEbonhold.PerkService
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
    return pcall(service.RequestEchoDiscovery)
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
    local ok = pcall(service.RequestSharedEchoLoadouts, tostring(classToken or ""):upper())
    return ok
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
    }
end
