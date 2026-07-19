-- EbonBuilds: modules/gear/GearScore.lua
-- Scores gear against per-class/spec stat priorities (a "gearscore"-style
-- system), so builds can show equipped gear quality and AutoSell/Missing
-- can compare "is this item actually an upgrade" instead of only "is it
-- worth 0 copper."
--
-- Stat weights are a DESIGN CHOICE, not a fact -- these are reasonable
-- WotLK 3.3.5a baseline priorities (roughly matching well-established
-- Wrath theorycrafting), not perfectly min-maxed for every fight. They're
-- meant to be directionally useful out of the box and easy to override
-- later, the same spirit as this addon's other "sensible defaults, tune
-- to taste" settings (see Scoring.lua's quality bonuses).
--
-- GetItemStats(itemLink) returns a table keyed by the game's own literal
-- stat identifier strings (e.g. "ITEM_MOD_STRENGTH_SHORT"). We key our
-- weight tables the same way so no translation layer is needed.

EbonBuilds.GearScore = {}

------------------------------------------------------------------------
-- Equipment slots (standard WotLK inventory slot ids)
------------------------------------------------------------------------

EbonBuilds.GearScore.SLOTS = {
    { id = 1,  name = "Head" },      { id = 2,  name = "Neck" },
    { id = 3,  name = "Shoulder" },  { id = 5,  name = "Chest" },
    { id = 6,  name = "Waist" },     { id = 7,  name = "Legs" },
    { id = 8,  name = "Feet" },      { id = 9,  name = "Wrist" },
    { id = 10, name = "Hands" },     { id = 11, name = "Finger1" },
    { id = 12, name = "Finger2" },   { id = 13, name = "Trinket1" },
    { id = 14, name = "Trinket2" },  { id = 15, name = "Back" },
    { id = 16, name = "MainHand" },  { id = 17, name = "SecondaryHand" },
    { id = 18, name = "Ranged" },
}

------------------------------------------------------------------------
-- Stat weights per "CLASS_Spec" key. 1.0 is the baseline unit; higher
-- means the stat matters more for that spec's core rotation/role.
------------------------------------------------------------------------

local W = {}

local function Set(key, weights)
    W[key] = weights
end

-- Warrior
Set("WARRIOR_Arms", { ITEM_MOD_STRENGTH_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.35, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.9, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=1.0, ITEM_MOD_EXPERTISE_RATING_SHORT=0.9, ITEM_MOD_STAMINA_SHORT=0.15 })
Set("WARRIOR_Fury",  { ITEM_MOD_STRENGTH_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.35, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.85, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_EXPERTISE_RATING_SHORT=0.9, ITEM_MOD_STAMINA_SHORT=0.15 })
Set("WARRIOR_Protection", { ITEM_MOD_STAMINA_SHORT=1.0, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=1.0, ITEM_MOD_DODGE_RATING_SHORT=0.7, ITEM_MOD_PARRY_RATING_SHORT=0.7, ITEM_MOD_BLOCK_RATING_SHORT=0.6, RESISTANCE0_NAME=0.3, ITEM_MOD_STRENGTH_SHORT=0.2 })

-- Paladin
Set("PALADIN_Holy", { ITEM_MOD_INTELLECT_SHORT=0.7, ITEM_MOD_SPIRIT_SHORT=0.6, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.5, ITEM_MOD_MANA_REGENERATION_SHORT=0.6, ITEM_MOD_STAMINA_SHORT=0.15 })
Set("PALADIN_Protection", { ITEM_MOD_STAMINA_SHORT=1.0, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=1.0, ITEM_MOD_DODGE_RATING_SHORT=0.6, ITEM_MOD_PARRY_RATING_SHORT=0.6, ITEM_MOD_BLOCK_RATING_SHORT=0.6, ITEM_MOD_STRENGTH_SHORT=0.2 })
Set("PALADIN_Retribution", { ITEM_MOD_STRENGTH_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.8, ITEM_MOD_HASTE_RATING_SHORT=0.6, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.9, ITEM_MOD_EXPERTISE_RATING_SHORT=0.8, ITEM_MOD_STAMINA_SHORT=0.15 })

-- Hunter
Set("HUNTER_BeastMastery", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.4, ITEM_MOD_RANGED_ATTACK_POWER_SHORT=0.4, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.8, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.6 })
Set("HUNTER_Marksmanship", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.4, ITEM_MOD_RANGED_ATTACK_POWER_SHORT=0.4, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.85, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.7 })
Set("HUNTER_Survival", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.4, ITEM_MOD_RANGED_ATTACK_POWER_SHORT=0.4, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.8, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.9 })

-- Rogue
Set("ROGUE_Assassination", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.85, ITEM_MOD_HASTE_RATING_SHORT=0.6, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=1.0, ITEM_MOD_EXPERTISE_RATING_SHORT=0.9 })
Set("ROGUE_Combat", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.8, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_EXPERTISE_RATING_SHORT=1.0, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.7 })
Set("ROGUE_Subtlety", { ITEM_MOD_AGILITY_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.9, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_EXPERTISE_RATING_SHORT=0.8 })

-- Priest
Set("PRIEST_Discipline", { ITEM_MOD_INTELLECT_SHORT=0.7, ITEM_MOD_SPIRIT_SHORT=0.6, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_CRIT_RATING_SHORT=0.5, ITEM_MOD_MANA_REGENERATION_SHORT=0.7 })
Set("PRIEST_Holy", { ITEM_MOD_INTELLECT_SHORT=0.7, ITEM_MOD_SPIRIT_SHORT=0.8, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.4, ITEM_MOD_MANA_REGENERATION_SHORT=0.8 })
Set("PRIEST_Shadow", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.6, ITEM_MOD_SPIRIT_SHORT=0.2 })

-- Death Knight
Set("DEATHKNIGHT_Blood", { ITEM_MOD_STAMINA_SHORT=1.0, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=1.0, ITEM_MOD_DODGE_RATING_SHORT=0.6, ITEM_MOD_PARRY_RATING_SHORT=0.6, ITEM_MOD_STRENGTH_SHORT=0.2 })
Set("DEATHKNIGHT_Frost", { ITEM_MOD_STRENGTH_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.7, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_EXPERTISE_RATING_SHORT=0.8, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.8 })
Set("DEATHKNIGHT_Unholy", { ITEM_MOD_STRENGTH_SHORT=1.0, ITEM_MOD_ATTACK_POWER_SHORT=0.3, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.8, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_EXPERTISE_RATING_SHORT=0.7 })

-- Shaman
Set("SHAMAN_Elemental", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.7, ITEM_MOD_HASTE_RATING_SHORT=0.8 })
Set("SHAMAN_Enhancement", { ITEM_MOD_AGILITY_SHORT=0.8, ITEM_MOD_STRENGTH_SHORT=0.6, ITEM_MOD_ATTACK_POWER_SHORT=0.35, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.7, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_EXPERTISE_RATING_SHORT=0.8 })
Set("SHAMAN_Restoration", { ITEM_MOD_INTELLECT_SHORT=0.6, ITEM_MOD_SPIRIT_SHORT=0.7, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.5, ITEM_MOD_MANA_REGENERATION_SHORT=0.7 })

-- Mage
Set("MAGE_Arcane", { ITEM_MOD_INTELLECT_SHORT=0.6, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.6 })
Set("MAGE_Fire", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.9, ITEM_MOD_HASTE_RATING_SHORT=0.7 })
Set("MAGE_Frost", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_CRIT_RATING_SHORT=0.7, ITEM_MOD_HASTE_RATING_SHORT=0.8 })

-- Warlock
Set("WARLOCK_Affliction", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_CRIT_RATING_SHORT=0.5 })
Set("WARLOCK_Demonology", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_CRIT_RATING_SHORT=0.7 })
Set("WARLOCK_Destruction", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.7, ITEM_MOD_CRIT_RATING_SHORT=0.8 })

-- Druid
Set("DRUID_Balance", { ITEM_MOD_INTELLECT_SHORT=0.5, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HIT_RATING_SHORT=1.1, ITEM_MOD_HASTE_RATING_SHORT=0.8, ITEM_MOD_CRIT_RATING_SHORT=0.6 })
Set("DRUID_FeralCombat", { ITEM_MOD_AGILITY_SHORT=0.8, ITEM_MOD_STRENGTH_SHORT=0.5, ITEM_MOD_ATTACK_POWER_SHORT=0.35, ITEM_MOD_HIT_RATING_SHORT=1.0, ITEM_MOD_CRIT_RATING_SHORT=0.7, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT=0.7, ITEM_MOD_EXPERTISE_RATING_SHORT=0.7, ITEM_MOD_STAMINA_SHORT=0.5, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=0.4, ITEM_MOD_DODGE_RATING_SHORT=0.4 })
Set("DRUID_Restoration", { ITEM_MOD_INTELLECT_SHORT=0.6, ITEM_MOD_SPIRIT_SHORT=0.6, ITEM_MOD_SPELL_POWER_SHORT=1.0, ITEM_MOD_HASTE_RATING_SHORT=0.9, ITEM_MOD_CRIT_RATING_SHORT=0.4, ITEM_MOD_MANA_REGENERATION_SHORT=0.7 })

-- Item level always contributes a flat baseline component (a higher-ilvl
-- item of the same slot is usually at least a little better even before
-- stats are weighed), on top of the weighted stat sum below.
local ILVL_WEIGHT = 1.5

EbonBuilds.GearScore.STAT_WEIGHTS = W

-- Every SpecData entry in this addon already keys specs by index (1/2/3);
-- translate a build's (class, specIndex) into a "CLASS_SpecName" weight
-- key using the same spec ordering BuildOverview/BuildWizard use.
local SPEC_ORDER = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "BeastMastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    DEATHKNIGHT = { "Blood", "Frost", "Unholy" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "FeralCombat", "Restoration" },
}

function EbonBuilds.GearScore.SpecKey(classToken, specIndex)
    local names = classToken and SPEC_ORDER[classToken]
    local name = names and names[specIndex or 1]
    if not name then return nil end
    return classToken .. "_" .. name
end

function EbonBuilds.GearScore.HasWeights(specKey)
    return specKey ~= nil and W[specKey] ~= nil
end

------------------------------------------------------------------------
-- Scoring
------------------------------------------------------------------------

-- getStats/getInfo are injected for testability (mirrors the pattern used
-- throughout this addon for GetSpellInfo/GetTalentInfo callers).
function EbonBuilds.GearScore.ScoreItem(itemLink, specKey, getStats, getInfo)
    if not itemLink or not specKey then return 0 end
    local weights = W[specKey]
    if not weights then return 0 end
    getStats = getStats or GetItemStats
    getInfo  = getInfo  or GetItemInfo

    local score = 0
    local stats = getStats(itemLink) or {}
    for statKey, value in pairs(stats) do
        local w = weights[statKey]
        if w and type(value) == "number" then
            score = score + value * w
        end
    end

    local ilvl = select(4, getInfo(itemLink))
    if ilvl then
        score = score + ilvl * ILVL_WEIGHT
    end

    return score
end

-- Returns true if newLink scores higher than currentLink for the slot
-- (currentLink may be nil -- an empty slot means anything is an upgrade).
function EbonBuilds.GearScore.IsUpgrade(newLink, currentLink, specKey, getStats, getInfo)
    if not newLink or not specKey then return false end
    if not currentLink then return true end
    local newScore = EbonBuilds.GearScore.ScoreItem(newLink, specKey, getStats, getInfo)
    local curScore = EbonBuilds.GearScore.ScoreItem(currentLink, specKey, getStats, getInfo)
    return newScore > curScore
end

-- Scores every currently-equipped item for a spec. Returns
-- { total, count, bySlot = { [slotName] = { link, score } } }.
function EbonBuilds.GearScore.ScoreEquipped(specKey, getStats, getInfo, getInvLink)
    getInvLink = getInvLink or function(slotId) return GetInventoryItemLink("player", slotId) end
    local total, count = 0, 0
    local bySlot = {}
    for _, slot in ipairs(EbonBuilds.GearScore.SLOTS) do
        local link = getInvLink(slot.id)
        if link then
            local s = EbonBuilds.GearScore.ScoreItem(link, specKey, getStats, getInfo)
            bySlot[slot.name] = { link = link, score = s }
            total = total + s
            count = count + 1
        end
    end
    return { total = total, count = count, bySlot = bySlot }
end

------------------------------------------------------------------------
-- Upgrade lookup for tooltips
------------------------------------------------------------------------

-- Where an item CAN be equipped: the game's INVTYPE_* equip-location
-- string -> candidate inventory slot ids. Dual-slot entries (rings,
-- trinkets, weapons) list both; the comparison below then runs against
-- the WEAKEST currently-equipped candidate, because that's the one the
-- new item would sensibly replace.
local INVTYPE_SLOTS = {
    INVTYPE_HEAD = { 1 },  INVTYPE_NECK = { 2 },  INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 },  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },  INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
EbonBuilds.GearScore.INVTYPE_SLOTS = INVTYPE_SLOTS

-- One call answering "is this an upgrade for me": resolves the item's
-- equip location, scores it against the weakest currently-equipped
-- candidate slot, and returns nil (not equippable / no weights / no
-- link) or { isUpgrade, delta, newScore, currentScore, slotEmpty }.
-- delta is newScore - currentScore; slotEmpty means at least one
-- candidate slot has nothing in it (anything is an upgrade then).
function EbonBuilds.GearScore.UpgradeInfo(itemLink, specKey, getStats, getInfo, getInvLink)
    if not itemLink or not specKey or not EbonBuilds.GearScore.HasWeights(specKey) then return nil end
    getInfo = getInfo or GetItemInfo
    getInvLink = getInvLink or function(slotId) return GetInventoryItemLink("player", slotId) end

    local equipLoc = select(9, getInfo(itemLink))
    local slots = equipLoc and INVTYPE_SLOTS[equipLoc]
    if not slots then return nil end

    local newScore = EbonBuilds.GearScore.ScoreItem(itemLink, specKey, getStats, getInfo)

    local worstScore, slotEmpty = nil, false
    for _, slotId in ipairs(slots) do
        local link = getInvLink(slotId)
        if not link then
            slotEmpty = true
            worstScore = 0
            break
        end
        local s = EbonBuilds.GearScore.ScoreItem(link, specKey, getStats, getInfo)
        if worstScore == nil or s < worstScore then worstScore = s end
    end

    local delta = newScore - (worstScore or 0)
    return {
        isUpgrade = slotEmpty or delta > 0,
        delta = delta,
        newScore = newScore,
        currentScore = worstScore or 0,
        slotEmpty = slotEmpty,
    }
end
