-- DetailsProjectEbonholdEcho.lua
-- Label PE Echo damage spells in Details! and expose Echo DPS breakdowns for
-- EbonBuilds EchoPerformance. Target: WoW 3.3.5a / build 12340.

local PE = DetailsProjectEbonhold
local Core = DetailsProjectEbonholdCore

PE.Echo = PE.Echo or {}
local Echo = PE.Echo

local labeledIds = {}

local function Db()
    DetailsProjectEbonholdDB = DetailsProjectEbonholdDB or {}
    return DetailsProjectEbonholdDB
end

local function ResolvePerkName(spellId, value)
    if type(value) == "table" then
        return value.name or value.comment
    end
    if type(value) == "string" then
        return value
    end
    if spellId and type(GetSpellInfo) == "function" then
        return GetSpellInfo(spellId)
    end
    return nil
end

local function CollectEchoEntries()
    local entries = {}
    local seen = {}

    local function Add(spellId, name)
        spellId = tonumber(spellId)
        if not spellId or seen[spellId] then
            return
        end
        if type(name) ~= "string" or name == "" then
            name = PE.GetSpellName(spellId)
        end
        seen[spellId] = true
        entries[#entries + 1] = { spellId = spellId, name = name }
    end

    -- Active run echoes from ProjectEbonhold (cheap, authoritative for this pull).
    local peh = _G.ProjectEbonhold
    if peh and peh.PerkService and type(peh.PerkService.GetGrantedPerks) == "function" then
        local ok, granted = pcall(peh.PerkService.GetGrantedPerks)
        if ok and type(granted) == "table" then
            for key, value in pairs(granted) do
                local spellId = tonumber(key)
                if type(value) == "table" then
                    spellId = spellId or tonumber(value.spellId) or tonumber(value.id)
                end
                Add(spellId, ResolvePerkName(spellId, value))
            end
        end
    end

    -- Label PE-band spells that actually dealt damage this combat (covers
    -- echo secondary effects whose id differs from the granted perk id).
    if PE.IsDetailsReady() then
        local details = PE.GetDetails()
        local okCombat, combat = pcall(function()
            return details:GetCurrentCombat()
        end)
        local playerName = UnitName and UnitName("player")
        if okCombat and combat and playerName then
            local okActor, actor = pcall(function()
                return combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE or 1, playerName)
            end)
            local spells = okActor and actor and actor.spells and (actor.spells._ActorTable or actor.spells)
            if type(spells) == "table" then
                for spellId in pairs(spells) do
                    spellId = tonumber(spellId)
                    if Core.IsPeCustomSpellId(spellId) then
                        local name
                        if peh and type(peh.PerkDatabase) == "table" and type(peh.PerkDatabase[spellId]) == "table" then
                            name = peh.PerkDatabase[spellId].comment or peh.PerkDatabase[spellId].name
                        end
                        Add(spellId, name)
                    end
                end
            end
        end
    end

    return entries
end

function Echo.GetEchoIndex()
    return Core.BuildEchoIndex(CollectEchoEntries())
end

function Echo.RefreshLabels()
    if Db().labelEchoes == false then
        return 0
    end
    if not PE.IsDetailsReady() then
        return 0
    end
    local entries = CollectEchoEntries()
    local n = 0
    for i = 1, #entries do
        local e = entries[i]
        local spellId = e.spellId
        if not labeledIds[spellId] then
            local icon = PE.GetSpellIcon(spellId)
            local label = Core.FormatEchoLabel(e.name)
            if PE.SetSpellLabel(spellId, label, icon) then
                labeledIds[spellId] = true
                n = n + 1
            end
        end
    end
    return n
end

-- Returns { [echoName] = damageTotal } for the player's current Details combat.
function Echo.GetPlayerEchoDamage()
    if not PE.IsDetailsReady() then
        return {}
    end
    local details = PE.GetDetails()
    local ok, combat = pcall(function()
        return details:GetCurrentCombat()
    end)
    if not ok or not combat then
        return {}
    end
    local playerName = UnitName and UnitName("player")
    if not playerName then
        return {}
    end
    local okActor, actor = pcall(function()
        return combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE or 1, playerName)
    end)
    if not okActor or type(actor) ~= "table" or type(actor.spells) ~= "table" then
        return {}
    end
    local spells = actor.spells._ActorTable or actor.spells
    if type(spells) ~= "table" then
        return {}
    end
    -- Enrich spell tables with names for name-based matching.
    local enriched = {}
    for spellId, spell in pairs(spells) do
        if type(spell) == "table" then
            enriched[spellId] = {
                total = spell.total,
                name = PE.GetSpellName(spellId),
            }
        else
            enriched[spellId] = spell
        end
    end
    return Core.MatchEchoDamage(enriched, Echo.GetEchoIndex())
end

function Echo.Init()
    Echo.RefreshLabels()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- PE grants echoes mid-run; re-label periodically while the DB grows.
    f:SetScript("OnEvent", function()
        Echo.RefreshLabels()
    end)
    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        C_Timer.NewTicker(30, function()
            Echo.RefreshLabels()
        end)
    end
end
