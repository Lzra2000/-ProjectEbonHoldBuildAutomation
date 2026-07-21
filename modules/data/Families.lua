local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/Families.lua
-- Responsibility: the single source of truth for Echo families. Before
-- this module, four places each held their own idea of what a family
-- is: Scoring had a private normalization map, SettingsView a private
-- display list, EchoSamples a substring hack for "Caster DPS", and the
-- family suggestions excluded multi-family Echoes outright. Everything
-- family-shaped now goes through here: the canonical list (with order
-- and DPS-role flags), normalization of every catalog variant, and
-- resolving an Echo entry to its canonical family set.

EbonBuilds.Families = {}

local M = EbonBuilds.Families

M.NO_FAMILY = "No family"

-- Canonical families, in display order. isDps marks the damage roles --
-- the ones DPS evidence can legitimately say something about.
M.LIST = {
    { id = "Tank",          label = "Tank",          isDps = false },
    { id = "Survivability", label = "Survivability", isDps = false },
    { id = "Healer",        label = "Healer",        isDps = false },
    { id = "Caster",        label = "Caster",        isDps = true },
    { id = "Melee",         label = "Melee",         isDps = true },
    { id = "Ranged",        label = "Ranged",        isDps = true },
    { id = M.NO_FAMILY,     label = M.NO_FAMILY,     isDps = false },
}

local BY_ID = {}
for _, def in ipairs(M.LIST) do BY_ID[def.id] = def end

-- Every name variant the server/catalog has produced, mapped to its
-- canonical id. Unknown strings normalize to nil (callers decide
-- whether that means "ignore" or "No family").
local ALIASES = {
    ["Tank"] = "Tank",
    ["Survivability"] = "Survivability", ["Survival"] = "Survivability",
    ["Healer"] = "Healer", ["Healing"] = "Healer",
    ["Caster"] = "Caster", ["Caster DPS"] = "Caster", ["CasterDPS"] = "Caster",
    ["Melee"] = "Melee",   ["Melee DPS"] = "Melee",   ["MeleeDPS"] = "Melee",
    ["Ranged"] = "Ranged", ["Ranged DPS"] = "Ranged", ["RangedDPS"] = "Ranged",
    ["None"] = M.NO_FAMILY, ["No family"] = M.NO_FAMILY, ["No Family"] = M.NO_FAMILY,
}

-- One string in, canonical id (or nil) out. Trims whitespace; exact
-- alias match first, then a forgiving prefix match ("Caster ...")
-- so a future server variant degrades to the right family instead of
-- silently becoming unknown.
function M.Normalize(name)
    if type(name) ~= "string" then return nil end
    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
    if ALIASES[trimmed] then return ALIASES[trimmed] end
    for _, def in ipairs(M.LIST) do
        if def.id ~= M.NO_FAMILY and trimmed:sub(1, #def.id) == def.id then
            return def.id
        end
    end
    return nil
end

function M.IsKnown(id)
    return BY_ID[id] ~= nil
end

function M.IsDps(id)
    local def = BY_ID[id]
    return def ~= nil and def.isDps == true
end

function M.Label(id)
    local def = BY_ID[id]
    return def and def.label or tostring(id)
end

-- Display order for UIs (SettingsView's role emphasis, banish
-- protection, etc). Returns a fresh array of ids.
function M.OrderedIds()
    local out = {}
    for _, def in ipairs(M.LIST) do out[#out + 1] = def.id end
    return out
end

-- Resolve a catalog entry's families array to its canonical family
-- set: deduplicated, sorted, unknown variants dropped. An entry with
-- no resolvable family gets { "No family" } so every Echo belongs
-- somewhere -- the same contract Scoring's fallback always had.
function M.Of(entry)
    local seen, out = {}, {}
    if entry and type(entry.families) == "table" then
        for _, raw in ipairs(entry.families) do
            local id = M.Normalize(raw)
            if id and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    if #out == 0 then out[1] = M.NO_FAMILY end
    table.sort(out)
    return out
end

-- Does this entry belong to at least one damage-role family?
function M.HasDpsRole(entry)
    for _, id in ipairs(M.Of(entry)) do
        if M.IsDps(id) then return true end
    end
    return false
end
