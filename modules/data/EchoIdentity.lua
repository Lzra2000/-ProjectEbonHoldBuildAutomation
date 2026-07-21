local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoIdentity.lua
-- Stable identity helpers shared by the catalog, migration, search and UI.
-- Names are display/search metadata. Current-catalog priority identity is a
-- group reference (g:<groupId>); malformed runtime records fall back to an
-- exact spell reference (s:<spellId>).

EbonBuilds.EchoIdentity = {}

local Identity = EbonBuilds.EchoIdentity
local Data = EbonBuilds.EchoIdentityData or { groups = {}, spells = {} }

Identity.SCHEMA = tonumber(Data.SCHEMA) or 2
Identity.SOURCE_FINGERPRINT = Data.SOURCE_FINGERPRINT or "unknown"
Identity.AVAILABLE = 1
Identity.UNAVAILABLE = 2
Identity.UNKNOWN = 3
Identity.CONFLICTED = 4

local CLASS_PREFIXES = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight",
    "DeathKnight", "Shaman", "Mage", "Warlock", "Druid",
}
local QUALITY_SUFFIXES = { "Common", "Uncommon", "Rare", "Epic" }

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Identity.VisibleName(value)
    value = tostring(value or "")
    value = value:gsub("[%z\1-\31\127]", "")
    return Trim(value:gsub("%s+", " "))
end

function Identity.StripQualitySuffix(value)
    value = Identity.VisibleName(value)
    for _, quality in ipairs(QUALITY_SUFFIXES) do
        local escaped = quality:gsub("([^%w])", "%%%1")
        local stripped = value:match("^(.+)%s*%-%s*" .. escaped .. "$")
        if stripped then return Trim(stripped) end
    end
    return value
end

function Identity.StripClassPrefix(value)
    value = Identity.VisibleName(value)
    for _, className in ipairs(CLASS_PREFIXES) do
        local escaped = className:gsub("([^%w])", "%%%1")
        local stripped = value:match("^" .. escaped .. "%s*%-%s*(.+)$")
        if stripped then return Trim(stripped) end
    end
    return value
end

function Identity.NormalizeSearch(value)
    value = Identity.VisibleName(value)
    value = value:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    value = Identity.StripClassPrefix(Identity.StripQualitySuffix(value))
    return string.lower(value)
end

function Identity.RefKey(groupId, spellId)
    groupId = tonumber(groupId)
    if groupId and groupId > 0 then return "g:" .. tostring(math.floor(groupId)) end
    spellId = tonumber(spellId)
    if spellId and spellId > 0 then return "s:" .. tostring(math.floor(spellId)) end
    return nil
end

function Identity.ParseRef(refKey)
    local prefix, value = tostring(refKey or ""):match("^([gs]):(%d+)$")
    value = tonumber(value)
    if not prefix or not value then return nil, nil end
    return prefix, value
end

function Identity.GetBundledSpell(spellId)
    local raw = Data.spells and Data.spells[tonumber(spellId)]
    if not raw then return nil end
    local group = Data.groups and Data.groups[tonumber(raw[1])]
    return {
        spellId = tonumber(spellId),
        groupId = tonumber(raw[1]),
        quality = tonumber(raw[2]) or 0,
        classMask = tonumber(raw[3]) or 0,
        requiredSpell = tonumber(raw[4]) or 0,
        internalComment = raw[5],
        sourceName = group and group[1] or nil,
        descriptionHash = group and tonumber(group[2]) or 0,
    }
end

function Identity.GetBundledGroup(groupId)
    local raw = Data.groups and Data.groups[tonumber(groupId)]
    if not raw then return nil end
    return {
        groupId = tonumber(groupId),
        sourceName = raw[1],
        descriptionHash = tonumber(raw[2]) or 0,
    }
end

function Identity.DisplayAvailability(value)
    if value == Identity.AVAILABLE then return "Available" end
    if value == Identity.UNAVAILABLE then return "Unavailable" end
    if value == Identity.CONFLICTED then return "Conflicted" end
    return "Unverified"
end
