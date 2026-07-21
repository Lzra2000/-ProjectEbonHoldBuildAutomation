local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/WizardPresets.lua
-- Deterministic player-intent presets for the Build Wizard. Presets only
-- transform the local draft; they never fabricate separate community cohorts.

EbonBuilds.WizardPresets = {}

local Presets = EbonBuilds.WizardPresets
local Semantics = EbonBuilds.EchoSemantics

Presets.ORDER = { "community", "offensive", "defensive", "manual" }
Presets.DEFINITIONS = {
    community = {
        label = "Community baseline",
        description = "Keeps the strongest local community priorities and leaves defensive-associated Echoes optional.",
        scoringStyle = "Recommendation-focused",
    },
    offensive = {
        label = "Offensive emphasis",
        description = "Favors mechanically offensive Echoes while keeping community evidence visible.",
        scoringStyle = "Recommendation-focused",
    },
    defensive = {
        label = "Defensive flexibility",
        description = "Includes more defensive and survivability-oriented options without treating them as mandatory.",
        scoringStyle = "Balanced",
    },
    manual = {
        label = "Manual setup",
        description = "Starts with no individual Echo priorities selected; community evidence remains available for reference.",
        scoringStyle = "Balanced",
    },
}

local SPEC_FAMILY = {
    WARRIOR     = { "Melee", "Melee", "Tank" },
    PALADIN     = { "Healer", "Tank", "Melee" },
    HUNTER      = { "Ranged", "Ranged", "Ranged" },
    ROGUE       = { "Melee", "Melee", "Melee" },
    PRIEST      = { "Healer", "Healer", "Caster" },
    DEATHKNIGHT = { "Melee", "Melee", "Melee" },
    SHAMAN      = { "Caster", "Melee", "Healer" },
    MAGE        = { "Caster", "Caster", "Caster" },
    WARLOCK     = { "Caster", "Caster", "Caster" },
    DRUID       = { "Caster", "Melee", "Healer" },
}

function Presets.Get(key)
    return Presets.DEFINITIONS[key] or Presets.DEFINITIONS.community
end

function Presets.Label(key)
    return Presets.Get(key).label
end

function Presets.ResolvePrimaryFamily(classToken, spec)
    local row = SPEC_FAMILY[tostring(classToken or ""):upper()]
    return row and row[math.max(1, math.min(3, tonumber(spec) or 1))] or "None"
end

local function HasPurpose(echo, flag)
    if not echo or not flag or not Semantics or not Semantics.Has then return false end
    local tuple = echo.semantics
    return tuple and Semantics.Has(tuple[1], flag) or false
end

local function HasRole(echo, flag)
    if not echo or not flag or not Semantics or not Semantics.Has then return false end
    local tuple = echo.semantics
    return tuple and Semantics.Has(tuple[7], flag) or false
end

local function Offensive(echo)
    if not Semantics then return false end
    return HasPurpose(echo, Semantics.PURPOSE.DAMAGE)
        or HasRole(echo, Semantics.ROLE.MELEE_DPS)
        or HasRole(echo, Semantics.ROLE.RANGED_DPS)
        or HasRole(echo, Semantics.ROLE.CASTER_DPS)
end

local function Defensive(echo)
    if not Semantics then return false end
    return HasPurpose(echo, Semantics.PURPOSE.DEFENSE)
        or HasPurpose(echo, Semantics.PURPOSE.HEALING)
        or HasRole(echo, Semantics.ROLE.TANK)
        or HasRole(echo, Semantics.ROLE.SURVIVABILITY)
        or HasRole(echo, Semantics.ROLE.HEALER)
end

local function ApplyEcho(echo, intentKey, preserveTouched)
    local canInclusion = not preserveTouched or not echo.touchedInclusion
    local canImportance = not preserveTouched or not echo.touchedImportance
    local included = echo.suggestedIncluded == true
    local importance = echo.suggestedImportance or "Neutral"

    if intentKey == "manual" then
        included, importance = false, "Neutral"
    elseif intentKey == "offensive" then
        if echo.sourceKind == "avoid" then
            included, importance = false, "Avoid"
        elseif echo.sourceKind == "defensive" and not Offensive(echo) then
            included, importance = false, "Useful"
        elseif Offensive(echo) then
            included = echo.sourceKind == "priority" or echo.suggestedIncluded == true
            if importance == "Neutral" or importance == "Useful" then importance = "Strong" end
        elseif echo.sourceKind == "catalog" then
            included, importance = false, "Neutral"
        end
    elseif intentKey == "defensive" then
        if echo.sourceKind == "avoid" then
            included, importance = false, "Avoid"
        elseif echo.sourceKind == "defensive" or Defensive(echo) then
            included = true
            if importance == "Neutral" or importance == "Useful" then importance = "Strong" end
        elseif echo.sourceKind == "catalog" then
            included, importance = false, "Neutral"
        end
    end

    local changed = false
    if canInclusion and echo.included ~= included then echo.included, changed = included, true end
    if canImportance and echo.importance ~= importance then echo.importance, changed = importance, true end
    return changed
end

function Presets.Apply(draft, intentKey, preserveTouched)
    if not draft then return false end
    intentKey = Presets.DEFINITIONS[intentKey] and intentKey or "community"
    local changed = draft.intentKey ~= intentKey
    draft.intentKey = intentKey

    local definition = Presets.Get(intentKey)
    if (not preserveTouched or not draft.touchedScoringStyle) and draft.scoringStyle ~= definition.scoringStyle then
        draft.scoringStyle = definition.scoringStyle
        changed = true
    end
    -- Family classification remains optional. Do not apply inferred family
    -- bonuses unless the player explicitly enables one in Advanced tuning.
    if (not preserveTouched or not draft.touchedPrimaryFamily) and draft.primaryFamily ~= "None" then
        draft.primaryFamily = "None"
        changed = true
    end

    if intentKey == "manual" then
        for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
            local lock = draft.locks[slot]
            if lock and (not preserveTouched or not lock.touched) and lock.ownership == "suggested" then
                draft.locks[slot] = nil
                changed = true
            end
        end
    elseif draft.snapshot then
        for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
            local lock = draft.locks[slot]
            local item = draft.snapshot.locked and draft.snapshot.locked[slot]
            if not lock and item and not draft.lockTouched[slot] then
                local spellId = tonumber(item.lockedSpellId)
                local entry, variant
                if spellId and EbonBuilds.EchoProjection then
                    entry, variant = EbonBuilds.EchoProjection.ResolveSpell(draft.class, spellId)
                end
                if not entry and EbonBuilds.EchoCatalog then
                    local resolvedId, _, definition, resolvedVariant = EbonBuilds.EchoCatalog.GetBest(item.name, draft.class, item.lockedSpellId)
                    spellId, variant = resolvedId, resolvedVariant
                    entry = definition and EbonBuilds.EchoProjection.GetEntry(draft.class, definition.refKey)
                end
                if spellId and entry then
                    draft.locks[slot] = {
                        refKey = entry.refKey,
                        name = entry.displayName or entry.sourceName,
                        spellId = spellId,
                        ownership = "suggested",
                        touched = false,
                        recommendationIndex = slot,
                    }
                    changed = true
                end
            end
        end
    end

    for _, name in ipairs(draft.echoOrder or {}) do
        if ApplyEcho(draft.echoes[name], intentKey, preserveTouched) then changed = true end
    end
    return changed
end
