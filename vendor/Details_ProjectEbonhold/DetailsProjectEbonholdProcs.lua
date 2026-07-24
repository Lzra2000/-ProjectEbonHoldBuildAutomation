-- DetailsProjectEbonholdProcs.lua
-- Attribute secondary/proc damage to the player cast that likely triggered it,
-- and surface a Details! Custom Display "PE Proc Sources".
-- Target: WoW 3.3.5a / build 12340 CLEU (no CombatLogGetCurrentEventInfo).

local PE = DetailsProjectEbonhold
local Core = DetailsProjectEbonholdCore

PE.Procs = PE.Procs or {}
local Procs = PE.Procs

local wipe = wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local PLAYER_GUID
local recentCasts = {} -- { {spellId=, name=, t=}, ... }
local recentCastIds = {} -- set of spellIds currently in the window
local attribution = {} -- [procId] = { [sourceId] = amount }
local MAX_RECENT = 24

local function Db()
    DetailsProjectEbonholdDB = DetailsProjectEbonholdDB or {}
    return DetailsProjectEbonholdDB
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function PruneRecent(now)
    local window = Core.PROC_ATTRIBUTION_WINDOW
    local kept = {}
    wipe(recentCastIds)
    for i = 1, #recentCasts do
        local e = recentCasts[i]
        if e and (now - (e.t or 0)) <= window * 2 then
            kept[#kept + 1] = e
            if e.spellId then
                recentCastIds[e.spellId] = true
            end
        end
    end
    recentCasts = kept
end

local function RememberCast(spellId, spellName)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 10 then
        return
    end
    local now = Now()
    PruneRecent(now)
    recentCasts[#recentCasts + 1] = {
        spellId = spellId,
        name = spellName or PE.GetSpellName(spellId),
        t = now,
    }
    recentCastIds[spellId] = true
    while #recentCasts > MAX_RECENT do
        table.remove(recentCasts, 1)
    end
end

local function IsPlayerSource(guid, flags)
    if PLAYER_GUID and guid == PLAYER_GUID then
        return true
    end
    -- COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400, AFFILIATION_MINE = 0x00000001
    if type(flags) == "number" and bit and bit.band then
        local MINE = 0x00000001
        local PLAYER = 0x00000400
        if bit.band(flags, MINE) ~= 0 and bit.band(flags, PLAYER) ~= 0 then
            return true
        end
        -- Also accept the player's pet/guardian as "our" casts for attribution.
        local PET = 0x00001000
        local GUARDIAN = 0x00002000
        if bit.band(flags, MINE) ~= 0 and (bit.band(flags, PET) ~= 0 or bit.band(flags, GUARDIAN) ~= 0) then
            return true
        end
    end
    return false
end

function Procs.ResetCombatAttribution()
    attribution = {}
end

function Procs.GetAttribution()
    return attribution
end

function Procs.GetProcRows()
    return Core.BuildProcRows(attribution, function(id)
        return PE.GetSpellName(id)
    end)
end

local function AnnotateProcSpell(procId, sourceName)
    local base = PE.GetSpellName(procId)
    -- Strip prior attribution suffixes for a clean re-label.
    base = base:gsub(" %(← .-%)", ""):gsub(" %(Proc%)", ""):gsub(" %(Echo%)", "")
    local label
    if Core.IsPeCustomSpellId(procId) then
        -- Prefer "EchoName (Echo) (← SourceCast)" in the spell breakdown.
        label = Core.FormatEchoLabel(base)
        if type(sourceName) == "string" and sourceName ~= "" then
            label = string.format("%s (← %s)", label, sourceName)
        end
    else
        label = Core.FormatProcLabel(base, sourceName)
    end
    PE.SetSpellLabel(procId, label, PE.GetSpellIcon(procId))
end

local function OnDamage(spellId, spellName, amount)
    spellId = tonumber(spellId)
    amount = tonumber(amount) or 0
    if not spellId or amount <= 0 then
        return
    end
    local now = Now()
    PruneRecent(now)
    if not Core.IsLikelyProc(spellId, recentCastIds) then
        return
    end
    local sourceId, sourceName = Core.ResolveProcSource(recentCasts, now)
    if not sourceId then
        -- Still mark PE custom-band damage as Echo even without a cast source.
        if Core.IsPeCustomSpellId(spellId) and Db().labelEchoes ~= false then
            PE.SetSpellLabel(spellId, Core.FormatEchoLabel(spellName or PE.GetSpellName(spellId)), PE.GetSpellIcon(spellId))
        end
        return
    end
    attribution = Core.RecordProcDamage(attribution, spellId, sourceId, amount)
    AnnotateProcSpell(spellId, sourceName)
end

-- 3.3.5a CLEU: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
local function OnCombatLog(_, _, timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
    if Db().trackProcs == false then
        return
    end
    if not IsPlayerSource(srcGUID, srcFlags) then
        return
    end
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_CAST_START" then
        local spellId, spellName = ...
        RememberCast(spellId, spellName)
        return
    end
    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        -- Offensive buffs applied to the player can also be proc sources
        -- (trinkets, weapon enchants). Only remember auras on self.
        local spellId, spellName = ...
        if dstGUID == srcGUID or (PLAYER_GUID and dstGUID == PLAYER_GUID) then
            RememberCast(spellId, spellName)
        end
        return
    end
    if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
        or subevent == "RANGE_DAMAGE" or subevent == "DAMAGE_SHIELD" then
        local spellId, spellName, _, amount = ...
        OnDamage(spellId, spellName, amount)
    end
end

local CUSTOM_NAME = "PE Proc Sources"
local CUSTOM_VERSION = 1

local function InstallCustomDisplay()
    if Db().installCustomDisplays == false then
        return
    end
    local details = PE.GetDetails()
    if type(details) ~= "table" or type(details.InstallCustomObject) ~= "function" then
        return
    end
    local object = {
        name = CUSTOM_NAME,
        icon = [[Interface\Icons\Spell_Shadow_ShadowWordDominate]],
        attribute = false,
        spellid = false,
        author = "Details PE / EbonBuilds",
        desc = "Proc / Echo secondary damage attributed to the cast that likely triggered it (Project Ebonhold).",
        source = false,
        target = false,
        script_version = CUSTOM_VERSION,
        script = [[
local combat, instance_container, instance = ...
local total, top, amount = 0, 0, 0
local pe = DetailsProjectEbonhold
if not pe or not pe.Procs or not pe.Procs.GetProcRows then
    return 0, 0, 0
end
local rows = pe.Procs.GetProcRows()
for i = 1, #rows do
    local row = rows[i]
    local value = row.amount or 0
    if value > 0 then
        local actor = { nome = row.key, name = row.key, classe = "UNKNOW" }
        instance_container:AddValue(actor, value)
        total = total + value
        if value > top then top = value end
        amount = amount + 1
    end
end
return total, top, amount
]],
        tooltip = [[
local actor, combat, instance = ...
GameCooltip:AddLine(actor.nome or actor.name or "Proc")
GameCooltip:AddLine("Attributed to the cast/aura that likely triggered this secondary hit.")
GameCooltip:AddLine("Project Ebonhold Details PE fine-tune.")
]],
        total_script = [[
local value, top, total, combat, instance = ...
return value
]],
        percent_script = [[
local value, top, total, combat, instance = ...
if not total or total == 0 then return "0%" end
return string.format("%.1f", value / total * 100) .. "%"
]],
    }
    pcall(details.InstallCustomObject, details, object)
end

function Procs.Init()
    PLAYER_GUID = UnitGUID and UnitGUID("player")
    Procs.ResetCombatAttribution()
    InstallCustomDisplay()

    local f = CreateFrame("Frame")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            PLAYER_GUID = UnitGUID and UnitGUID("player")
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            Procs.ResetCombatAttribution()
            recentCasts = {}
            wipe(recentCastIds)
            return
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog(self, event, ...)
        end
    end)
end
