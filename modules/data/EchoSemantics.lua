local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoSemantics.lua
-- Compact runtime access to description-derived Echo classifications.

EbonBuilds.EchoSemantics = {}

local Semantics = EbonBuilds.EchoSemantics
local Data = EbonBuilds.EchoSemanticsData or { byGroup = {} }
local summaryCache = {}

Semantics.PURPOSE = {
    DAMAGE = 1, HEALING = 2, DEFENSE = 4, RESOURCE = 8,
    MOBILITY = 16, CONTROL = 32, UTILITY = 64, EQUIPMENT = 128,
}
Semantics.MECHANIC = {
    DIRECT = 1, PERIODIC = 2, PROC = 4, STAT = 8, AURA = 16,
    ABSORB = 32, COOLDOWN = 64, RESOURCE_GENERATION = 128,
    DUPLICATION = 256, EQUIPMENT_UNLOCK = 512, SUMMON = 1024,
    CONVERSION = 2048, DEBUFF = 4096, STACKING = 8192,
    TRIGGERED_CAST = 16384, SHIELD = 32768,
}
Semantics.TARGET = {
    SINGLE_TARGET = 1, CLEAVE = 2, AREA = 4, SELF = 8,
    ALLY = 16, GROUP = 32, PET = 64,
}
Semantics.PROFILE = {
    BURST = 1, SUSTAINED = 2, RAMPING = 4,
    EXECUTE = 8, REACTIVE = 16, PASSIVE = 32,
}
Semantics.TRIGGER = {
    DAMAGE_DEALT = 1, DIRECT_DAMAGE = 2, PERIODIC_DAMAGE = 4,
    HEAL_DONE = 8, CRITICAL_STRIKE = 16, RESOURCE_SPENT = 32,
    ABILITY_USED = 64, COOLDOWN_USED = 128, ENEMY_KILLED = 256,
    DAMAGE_TAKEN = 512, LOW_HEALTH = 1024, AVOIDANCE = 2048,
    CAST = 4096, INTERRUPT = 8192, MOVEMENT = 16384, BLOCK = 32768,
}
Semantics.SYNERGY = {
    PHYSICAL = 1, FIRE = 2, FROST = 4, ARCANE = 8, NATURE = 16,
    SHADOW = 32, HOLY = 64, DOT = 128, HOT = 256, HASTE = 512,
    CRITICAL_STRIKE = 1024, PET = 2048, MELEE_ATTACK = 4096,
    RANGED_ATTACK = 8192, SPELL_DAMAGE = 16384, HEALING = 32768,
    ARMOR = 65536, HEALTH = 131072, MANA = 262144, RAGE = 524288,
    ENERGY = 1048576, RUNIC_POWER = 2097152, DISEASE = 4194304,
    POISON = 8388608, BLEED = 16777216, SHIELD = 33554432,
}
Semantics.ROLE = {
    MELEE_DPS = 1, RANGED_DPS = 2, CASTER_DPS = 4,
    HEALER = 8, TANK = 16, SURVIVABILITY = 32,
}

local function Has(mask, flag)
    return bit.band(tonumber(mask) or 0, tonumber(flag) or 0) ~= 0
end

Semantics.Has = Has

local function TupleForGroup(groupId)
    return Data.byGroup and Data.byGroup[tonumber(groupId)] or nil
end

function Semantics.GetByGroup(groupId)
    return TupleForGroup(groupId)
end

function Semantics.GetBySpellId(spellId)
    spellId = tonumber(spellId)
    local data = spellId and EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetPerkData(spellId) or nil
    local exact = spellId and Data.bySpell and Data.bySpell[spellId] or nil
    if exact then return exact, data end
    return data and TupleForGroup(data.groupId), data or nil
end

function Semantics.SourceInfo()
    local runtimeVersion = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetAddonVersion()
    local sourceVersion = tonumber(Data.sourceAddonVersion)
    local status = "unknown"
    if runtimeVersion and sourceVersion then
        status = runtimeVersion == sourceVersion and "current" or "version_mismatch"
    end
    return {
        schema = tonumber(Data.schema) or 0,
        sourceAddonVersion = sourceVersion,
        runtimeAddonVersion = runtimeVersion,
        sourceSpellCount = tonumber(Data.sourceSpellCount) or 0,
        sourceGroupCount = tonumber(Data.sourceGroupCount) or 0,
        sourceFingerprint = Data.sourceFingerprint,
        status = status,
    }
end

local PURPOSE_ORDER = {
    { Semantics.PURPOSE.DAMAGE, "Damage" },
    { Semantics.PURPOSE.HEALING, "Healing" },
    { Semantics.PURPOSE.DEFENSE, "Defense" },
    { Semantics.PURPOSE.RESOURCE, "Resource" },
    { Semantics.PURPOSE.MOBILITY, "Mobility" },
    { Semantics.PURPOSE.CONTROL, "Control" },
    { Semantics.PURPOSE.EQUIPMENT, "Equipment" },
    { Semantics.PURPOSE.UTILITY, "Utility" },
}
local PROFILE_ORDER = {
    { Semantics.PROFILE.EXECUTE, "Execute" },
    { Semantics.PROFILE.RAMPING, "Ramping" },
    { Semantics.PROFILE.REACTIVE, "Reactive" },
    { Semantics.PROFILE.BURST, "Burst" },
    { Semantics.PROFILE.SUSTAINED, "Sustained" },
    { Semantics.PROFILE.PASSIVE, "Passive" },
}
local MECHANIC_ORDER = {
    { Semantics.MECHANIC.DUPLICATION, "Duplication" },
    { Semantics.MECHANIC.EQUIPMENT_UNLOCK, "Equipment unlock" },
    { Semantics.MECHANIC.ABSORB, "Absorb" },
    { Semantics.MECHANIC.COOLDOWN, "Cooldown" },
    { Semantics.MECHANIC.PERIODIC, "Periodic" },
    { Semantics.MECHANIC.STACKING, "Stacking" },
    { Semantics.MECHANIC.DEBUFF, "Debuff" },
    { Semantics.MECHANIC.AURA, "Aura" },
    { Semantics.MECHANIC.SUMMON, "Summon" },
    { Semantics.MECHANIC.RESOURCE_GENERATION, "Resource generation" },
    { Semantics.MECHANIC.STAT, "Stat" },
    { Semantics.MECHANIC.PROC, "Proc" },
    { Semantics.MECHANIC.DIRECT, "Direct" },
}
local TARGET_ORDER = {
    { Semantics.TARGET.CLEAVE, "Cleave" },
    { Semantics.TARGET.AREA, "Area" },
    { Semantics.TARGET.GROUP, "Group" },
    { Semantics.TARGET.ALLY, "Ally" },
    { Semantics.TARGET.PET, "Pet" },
    { Semantics.TARGET.SINGLE_TARGET, "Single target" },
}
local SYNERGY_ORDER = {
    { Semantics.SYNERGY.DOT, "DoT" },
    { Semantics.SYNERGY.HOT, "HoT" },
    { Semantics.SYNERGY.HASTE, "Haste" },
    { Semantics.SYNERGY.CRITICAL_STRIKE, "Critical" },
    { Semantics.SYNERGY.PHYSICAL, "Physical" },
    { Semantics.SYNERGY.FIRE, "Fire" },
    { Semantics.SYNERGY.FROST, "Frost" },
    { Semantics.SYNERGY.ARCANE, "Arcane" },
    { Semantics.SYNERGY.NATURE, "Nature" },
    { Semantics.SYNERGY.SHADOW, "Shadow" },
    { Semantics.SYNERGY.HOLY, "Holy" },
    { Semantics.SYNERGY.PET, "Pet" },
    { Semantics.SYNERGY.SHIELD, "Shield" },
    { Semantics.SYNERGY.ARMOR, "Armor" },
    { Semantics.SYNERGY.MANA, "Mana" },
    { Semantics.SYNERGY.RAGE, "Rage" },
    { Semantics.SYNERGY.ENERGY, "Energy" },
    { Semantics.SYNERGY.RUNIC_POWER, "Runic Power" },
}

local function AppendFirst(parts, mask, ordered)
    for _, entry in ipairs(ordered) do
        if Has(mask, entry[1]) then
            parts[#parts + 1] = entry[2]
            return true
        end
    end
    return false
end

function Semantics.Summary(tuple, maxParts)
    if not tuple then return "Unclassified" end
    maxParts = math.max(1, math.min(5, tonumber(maxParts) or 3))
    local cacheKey = table.concat({ tostring(tuple), tostring(maxParts) }, ":")
    if summaryCache[cacheKey] then return summaryCache[cacheKey] end

    local parts = {}
    AppendFirst(parts, tuple[1], PURPOSE_ORDER)
    if #parts < maxParts then AppendFirst(parts, tuple[4], PROFILE_ORDER) end
    if #parts < maxParts then AppendFirst(parts, tuple[2], MECHANIC_ORDER) end
    if #parts < maxParts then AppendFirst(parts, tuple[3], TARGET_ORDER) end
    if #parts < maxParts then AppendFirst(parts, tuple[6], SYNERGY_ORDER) end
    if #parts == 0 then parts[1] = "Unclassified" end

    local text = table.concat(parts, " · ")
    summaryCache[cacheKey] = text
    return text
end

function Semantics.SummaryForSpell(spellId, maxParts)
    return Semantics.Summary((Semantics.GetBySpellId(spellId)), maxParts)
end

function Semantics.AddTooltip(spellId)
    local tuple = Semantics.GetBySpellId(spellId)
    if not tuple then return end
    GameTooltip:AddLine("Mechanical profile", 1, 0.82, 0)
    GameTooltip:AddLine(Semantics.Summary(tuple, 5), 0.74, 0.82, 0.95, true)
    local source = Semantics.SourceInfo()
    if source.status == "version_mismatch" then
        GameTooltip:AddLine("Classification data was generated for ProjectEbonhold addon version "
            .. tostring(source.sourceAddonVersion) .. "; the installed version is "
            .. tostring(source.runtimeAddonVersion) .. ".", 1, 0.63, 0.25, true)
    end
end
