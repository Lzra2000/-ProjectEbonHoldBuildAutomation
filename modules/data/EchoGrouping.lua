local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoGrouping.lua
-- Deterministic, provenance-aware navigation taxonomy for Build Wizard Echoes.
-- Grouping is presentation metadata only; canonical Echo identity remains refKey.

EbonBuilds.EchoGrouping = {}

local Grouping = EbonBuilds.EchoGrouping
local Semantics = EbonBuilds.EchoSemantics

Grouping.GROUP_DAMAGE       = 1
Grouping.GROUP_SURVIVAL     = 2
Grouping.GROUP_RESOURCES    = 3
Grouping.GROUP_CONTROL      = 4
Grouping.GROUP_UTILITY      = 5
Grouping.GROUP_EQUIPMENT    = 6
Grouping.GROUP_OTHER        = 7
Grouping.GROUP_UNCLASSIFIED = 8

Grouping.PROVENANCE_REVIEWED       = 1
Grouping.PROVENANCE_INFERRED       = 2
Grouping.PROVENANCE_STALE_INFERRED = 3
Grouping.PROVENANCE_UNKNOWN        = 4

Grouping.GROUP_ORDER = {
    Grouping.GROUP_DAMAGE,
    Grouping.GROUP_SURVIVAL,
    Grouping.GROUP_RESOURCES,
    Grouping.GROUP_CONTROL,
    Grouping.GROUP_UTILITY,
    Grouping.GROUP_EQUIPMENT,
    Grouping.GROUP_OTHER,
    Grouping.GROUP_UNCLASSIFIED,
}

local GROUP_INFO = {
    [Grouping.GROUP_DAMAGE] = {
        key = "DAMAGE", label = "Damage",
        description = "Direct, periodic, burst, execute, proc, and area damage effects.",
    },
    [Grouping.GROUP_SURVIVAL] = {
        key = "SURVIVAL", label = "Survival",
        description = "Defense, healing, shields, recovery, and reactive protection.",
    },
    [Grouping.GROUP_RESOURCES] = {
        key = "RESOURCES", label = "Resources",
        description = "Resource generation, cooldown flow, haste, and rotation tempo.",
    },
    [Grouping.GROUP_CONTROL] = {
        key = "CONTROL", label = "Control",
        description = "Control, interrupts, movement, and positioning effects.",
    },
    [Grouping.GROUP_UTILITY] = {
        key = "UTILITY", label = "Utility",
        description = "Group support, ally effects, auras, debuffs, pets, and summons.",
    },
    [Grouping.GROUP_EQUIPMENT] = {
        key = "EQUIPMENT", label = "Equipment",
        description = "Equipment unlocks and equipment-specific interactions.",
    },
    [Grouping.GROUP_OTHER] = {
        key = "OTHER", label = "Other",
        description = "Legitimate miscellaneous Echoes that do not fit a major function group.",
    },
    [Grouping.GROUP_UNCLASSIFIED] = {
        key = "UNCLASSIFIED", label = "Needs classification",
        description = "Known Echoes whose mechanical classification is incomplete or unavailable.",
    },
}

-- Manual overrides are deliberately isolated from recommendation/community data.
-- Keys are stable refKeys. Only reviewed ambiguous cases belong here.
local PRIMARY_OVERRIDES = {
    -- ["g:123"] = Grouping.GROUP_SURVIVAL,
}

local function Has(mask, flag)
    return Semantics and Semantics.Has(mask, flag)
end

local function Tuple(entry)
    return entry and entry.semantics or nil
end

local function Purpose(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[1] or 0, flag)
end

local function Mechanic(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[2] or 0, flag)
end

local function Target(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[3] or 0, flag)
end

local function Profile(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[4] or 0, flag)
end

local function Trigger(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[5] or 0, flag)
end

local function Synergy(entry, flag)
    local tuple = Tuple(entry)
    return tuple and Has(tuple[6] or 0, flag)
end

local function InferredProvenance()
    local source = Semantics and Semantics.SourceInfo and Semantics.SourceInfo() or nil
    if source and source.status == "version_mismatch" then
        return Grouping.PROVENANCE_STALE_INFERRED
    end
    return Grouping.PROVENANCE_INFERRED
end

function Grouping.Resolve(entry)
    if not entry or not entry.refKey then
        return Grouping.GROUP_UNCLASSIFIED, Grouping.PROVENANCE_UNKNOWN
    end

    local override = PRIMARY_OVERRIDES[entry.refKey]
    if override then
        return override, Grouping.PROVENANCE_REVIEWED
    end

    local tuple = entry.semantics
    local purpose = tuple and tonumber(tuple[1]) or 0
    if purpose == 0 or not Semantics then
        return Grouping.GROUP_UNCLASSIFIED, Grouping.PROVENANCE_UNKNOWN
    end

    local provenance = InferredProvenance()
    if Has(purpose, Semantics.PURPOSE.EQUIPMENT) then
        return Grouping.GROUP_EQUIPMENT, provenance
    end
    if Has(purpose, Semantics.PURPOSE.DAMAGE) then
        return Grouping.GROUP_DAMAGE, provenance
    end
    if Has(purpose, Semantics.PURPOSE.DEFENSE) or Has(purpose, Semantics.PURPOSE.HEALING) then
        return Grouping.GROUP_SURVIVAL, provenance
    end
    if Has(purpose, Semantics.PURPOSE.RESOURCE) then
        return Grouping.GROUP_RESOURCES, provenance
    end
    if Has(purpose, Semantics.PURPOSE.CONTROL) or Has(purpose, Semantics.PURPOSE.MOBILITY) then
        return Grouping.GROUP_CONTROL, provenance
    end
    if Has(purpose, Semantics.PURPOSE.UTILITY) then
        return Grouping.GROUP_UTILITY, provenance
    end
    return Grouping.GROUP_OTHER, provenance
end

function Grouping.GetInfo(groupID)
    return GROUP_INFO[tonumber(groupID)] or GROUP_INFO[Grouping.GROUP_OTHER]
end

function Grouping.GetLabel(groupID)
    return Grouping.GetInfo(groupID).label
end

function Grouping.GetDescription(groupID)
    return Grouping.GetInfo(groupID).description
end

function Grouping.GetKey(groupID)
    return Grouping.GetInfo(groupID).key
end

function Grouping.GetProvenanceLabel(provenance)
    if provenance == Grouping.PROVENANCE_REVIEWED then return "Reviewed" end
    if provenance == Grouping.PROVENANCE_INFERRED then return "Inferred" end
    if provenance == Grouping.PROVENANCE_STALE_INFERRED then return "Stale classification" end
    return "Unknown"
end

Grouping.SUBGROUP_ALL = "ALL"

local SUBGROUPS = {
    [Grouping.GROUP_DAMAGE] = {
        { key = "ALL", label = "All" },
        { key = "SUSTAINED", label = "Sustained" },
        { key = "BURST", label = "Burst" },
        { key = "EXECUTE", label = "Execute" },
        { key = "PERIODIC", label = "Periodic" },
        { key = "AREA", label = "Area/Cleave" },
        { key = "PROC", label = "Proc" },
        { key = "DIRECT", label = "Direct" },
    },
    [Grouping.GROUP_SURVIVAL] = {
        { key = "ALL", label = "All" },
        { key = "DEFENSE", label = "Defense" },
        { key = "HEALING", label = "Healing" },
        { key = "SHIELD", label = "Shield/Absorb" },
        { key = "REACTIVE", label = "Reactive" },
        { key = "LOW_HEALTH", label = "Low health" },
    },
    [Grouping.GROUP_RESOURCES] = {
        { key = "ALL", label = "All" },
        { key = "GENERATION", label = "Generation" },
        { key = "COOLDOWN", label = "Cooldowns" },
        { key = "HASTE", label = "Haste" },
        { key = "MANA", label = "Mana" },
        { key = "RAGE", label = "Rage" },
        { key = "ENERGY", label = "Energy" },
        { key = "RUNIC_POWER", label = "Runic Power" },
    },
    [Grouping.GROUP_CONTROL] = {
        { key = "ALL", label = "All" },
        { key = "CONTROL", label = "Control" },
        { key = "INTERRUPT", label = "Interrupt" },
        { key = "MOVEMENT", label = "Movement" },
        { key = "MOBILITY", label = "Mobility" },
    },
    [Grouping.GROUP_UTILITY] = {
        { key = "ALL", label = "All" },
        { key = "GROUP", label = "Group" },
        { key = "ALLY", label = "Ally" },
        { key = "AURA", label = "Aura" },
        { key = "DEBUFF", label = "Debuff" },
        { key = "PET", label = "Pet/Summon" },
    },
    [Grouping.GROUP_EQUIPMENT] = {
        { key = "ALL", label = "All" },
        { key = "UNLOCK", label = "Unlock" },
        { key = "INTERACTION", label = "Interaction" },
    },
    [Grouping.GROUP_OTHER] = {
        { key = "ALL", label = "All" },
    },
    [Grouping.GROUP_UNCLASSIFIED] = {
        { key = "ALL", label = "All" },
    },
}

function Grouping.GetSubgroups(groupID)
    return SUBGROUPS[tonumber(groupID)] or SUBGROUPS[Grouping.GROUP_OTHER]
end

function Grouping.MatchesSubgroup(entry, groupID, subgroupKey)
    subgroupKey = tostring(subgroupKey or "ALL")
    if subgroupKey == "ALL" then return true end
    if not entry or not entry.semantics or not Semantics then return false end

    if groupID == Grouping.GROUP_DAMAGE then
        if subgroupKey == "SUSTAINED" then return Profile(entry, Semantics.PROFILE.SUSTAINED) end
        if subgroupKey == "BURST" then return Profile(entry, Semantics.PROFILE.BURST) end
        if subgroupKey == "EXECUTE" then return Profile(entry, Semantics.PROFILE.EXECUTE) end
        if subgroupKey == "PERIODIC" then return Mechanic(entry, Semantics.MECHANIC.PERIODIC) end
        if subgroupKey == "AREA" then return Target(entry, Semantics.TARGET.AREA) or Target(entry, Semantics.TARGET.CLEAVE) end
        if subgroupKey == "PROC" then return Mechanic(entry, Semantics.MECHANIC.PROC) end
        if subgroupKey == "DIRECT" then return Mechanic(entry, Semantics.MECHANIC.DIRECT) end
    elseif groupID == Grouping.GROUP_SURVIVAL then
        if subgroupKey == "DEFENSE" then return Purpose(entry, Semantics.PURPOSE.DEFENSE) end
        if subgroupKey == "HEALING" then return Purpose(entry, Semantics.PURPOSE.HEALING) end
        if subgroupKey == "SHIELD" then return Mechanic(entry, Semantics.MECHANIC.SHIELD)
            or Mechanic(entry, Semantics.MECHANIC.ABSORB) or Synergy(entry, Semantics.SYNERGY.SHIELD) end
        if subgroupKey == "REACTIVE" then return Profile(entry, Semantics.PROFILE.REACTIVE) end
        if subgroupKey == "LOW_HEALTH" then return Trigger(entry, Semantics.TRIGGER.LOW_HEALTH) end
    elseif groupID == Grouping.GROUP_RESOURCES then
        if subgroupKey == "GENERATION" then return Mechanic(entry, Semantics.MECHANIC.RESOURCE_GENERATION) end
        if subgroupKey == "COOLDOWN" then return Mechanic(entry, Semantics.MECHANIC.COOLDOWN) end
        if subgroupKey == "HASTE" then return Synergy(entry, Semantics.SYNERGY.HASTE) end
        if subgroupKey == "MANA" then return Synergy(entry, Semantics.SYNERGY.MANA) end
        if subgroupKey == "RAGE" then return Synergy(entry, Semantics.SYNERGY.RAGE) end
        if subgroupKey == "ENERGY" then return Synergy(entry, Semantics.SYNERGY.ENERGY) end
        if subgroupKey == "RUNIC_POWER" then return Synergy(entry, Semantics.SYNERGY.RUNIC_POWER) end
    elseif groupID == Grouping.GROUP_CONTROL then
        if subgroupKey == "CONTROL" then return Purpose(entry, Semantics.PURPOSE.CONTROL) end
        if subgroupKey == "INTERRUPT" then return Trigger(entry, Semantics.TRIGGER.INTERRUPT) end
        if subgroupKey == "MOVEMENT" then return Trigger(entry, Semantics.TRIGGER.MOVEMENT) end
        if subgroupKey == "MOBILITY" then return Purpose(entry, Semantics.PURPOSE.MOBILITY) end
    elseif groupID == Grouping.GROUP_UTILITY then
        if subgroupKey == "GROUP" then return Target(entry, Semantics.TARGET.GROUP) end
        if subgroupKey == "ALLY" then return Target(entry, Semantics.TARGET.ALLY) end
        if subgroupKey == "AURA" then return Mechanic(entry, Semantics.MECHANIC.AURA) end
        if subgroupKey == "DEBUFF" then return Mechanic(entry, Semantics.MECHANIC.DEBUFF) end
        if subgroupKey == "PET" then return Target(entry, Semantics.TARGET.PET)
            or Mechanic(entry, Semantics.MECHANIC.SUMMON) or Synergy(entry, Semantics.SYNERGY.PET) end
    elseif groupID == Grouping.GROUP_EQUIPMENT then
        if subgroupKey == "UNLOCK" then return Mechanic(entry, Semantics.MECHANIC.EQUIPMENT_UNLOCK) end
        if subgroupKey == "INTERACTION" then return Purpose(entry, Semantics.PURPOSE.EQUIPMENT)
            and not Mechanic(entry, Semantics.MECHANIC.EQUIPMENT_UNLOCK) end
    end
    return false
end

function Grouping.IsBuildChanging(entry)
    if not entry or not entry.semantics or not Semantics then return false end
    return Mechanic(entry, Semantics.MECHANIC.DUPLICATION)
        or Mechanic(entry, Semantics.MECHANIC.EQUIPMENT_UNLOCK)
        or Mechanic(entry, Semantics.MECHANIC.COOLDOWN)
        or Mechanic(entry, Semantics.MECHANIC.RESOURCE_GENERATION)
        or Mechanic(entry, Semantics.MECHANIC.TRIGGERED_CAST)
        or Mechanic(entry, Semantics.MECHANIC.STACKING)
end

function Grouping.RowMeta(entry, maxParts)
    if not entry then return "Unresolved" end
    local groupID = Grouping.Resolve(entry)
    local groupLabel = Grouping.GetLabel(groupID)
    local semantic = Semantics and Semantics.Summary(entry.semantics, maxParts or 3) or "Unclassified"
    if semantic == "Unclassified" then return groupLabel end
    if string.find(semantic, groupLabel, 1, true) == 1 then return semantic end
    return groupLabel .. " · " .. semantic
end

Grouping._PRIMARY_OVERRIDES = PRIMARY_OVERRIDES
