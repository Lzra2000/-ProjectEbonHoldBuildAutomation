-- EbonBuilds: modules/data/EchoProjection.lua
-- Strict selected-class projection over the shared Echo catalog. Every catalog
-- definition is retained as available, unverified, or unavailable; no class
-- lookup is allowed to fall back to another class variant.

EbonBuilds.EchoProjection = {}

local Projection = EbonBuilds.EchoProjection
local Identity = EbonBuilds.EchoIdentity
local cache = {}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function MakeEntry(definition, selected, availability, scopedVariants)
    -- A class projection is more than a membership filter.  It must also expose
    -- only the quality variants that are valid for that class so every consumer
    -- (Wizard, editor, picker, learned filter, and rank columns) sees the same
    -- canonical Echo surface.
    local variants = scopedVariants
    if type(variants) ~= "table" or #variants == 0 then
        variants = definition.variants or {}
    end

    local qualities, spellIds, variantsBySpellId = {}, {}, {}
    local familySet = {}
    for _, variant in ipairs(variants) do
        variantsBySpellId[variant.spellId] = variant
        local quality = tonumber(variant.quality) or 0
        qualities[quality] = true
        local previous = spellIds[quality]
        if not previous or variant.spellId < previous then spellIds[quality] = variant.spellId end
        for _, family in ipairs(variant.families or {}) do familySet[family] = true end
    end

    local families = {}
    for family in pairs(familySet) do families[#families + 1] = family end
    table.sort(families)
    if #families == 0 then families = definition.families or {} end

    local entry = {
        key = definition.refKey,
        refKey = definition.refKey,
        groupId = definition.groupId,
        name = selected and selected.localizedName or definition.sourceName,
        sourceName = definition.sourceName,
        displayName = selected and selected.localizedName or definition.sourceName,
        aliases = definition.aliases,
        searchBlob = definition.searchBlob,
        semantics = selected and selected.semantics or definition.semantics,
        families = families,
        qualities = qualities,
        spellIds = spellIds,
        variants = variants,
        variantsBySpellId = variantsBySpellId,
        spellId = selected and selected.spellId or definition.spellId,
        representativeSpellId = selected and selected.spellId or definition.spellId,
        quality = selected and selected.quality or definition.quality,
        classMask = selected and selected.classMask or 0,
        icon = selected and selected.icon or definition.icon,
        availability = availability,
        availabilitySource = selected and selected.sourceKind or "BUNDLED",
        internalComment = selected and selected.internalComment or nil,
    }
    return entry
end

local function SortEntries(a, b)
    local an, bn = string.lower(a.displayName or ""), string.lower(b.displayName or "")
    if an ~= bn then return an < bn end
    return tostring(a.refKey) < tostring(b.refKey)
end

local function Build(classToken)
    classToken = tostring(classToken or ""):upper()
    local catalogRevision = EbonBuilds.EchoCatalog.GetRevision()
    local existing = cache[classToken]
    if existing and existing.catalogRevision == catalogRevision then return existing end

    local projection = {
        classToken = classToken,
        catalogRevision = catalogRevision,
        available = {}, unverified = {}, conflicted = {}, unavailable = {},
        entriesByKey = {}, allEntriesByKey = {}, variantByKey = {},
        availableCount = 0, unverifiedCount = 0, conflictedCount = 0, unavailableCount = 0,
        fullCount = 0,
    }
    local nameCounts = {}

    for _, definition in ipairs(EbonBuilds.EchoCatalog.GetSortedList() or {}) do
        projection.fullCount = projection.fullCount + 1
        local selected
        local hasUnknown = false
        local availableVariants, unknownVariants = {}, {}
        for _, variant in ipairs(definition.variants or {}) do
            local variantAvailability = EbonBuilds.EchoCatalog.GetAvailability(variant, classToken)
            if variantAvailability == Identity.AVAILABLE or variantAvailability == Identity.CONFLICTED then
                availableVariants[#availableVariants + 1] = variant
                if not selected then selected = variant end
            elseif variantAvailability == Identity.UNKNOWN then
                hasUnknown = true
                unknownVariants[#unknownVariants + 1] = variant
            end
        end

        local availability, scopedVariants
        if selected then
            availability = selected.availabilityConflict and Identity.CONFLICTED or Identity.AVAILABLE
            scopedVariants = availableVariants
        elseif hasUnknown then
            availability = Identity.UNKNOWN
            scopedVariants = unknownVariants
        else
            availability = Identity.UNAVAILABLE
            scopedVariants = definition.variants
        end

        local entry = MakeEntry(definition, selected, availability, scopedVariants)
        projection.allEntriesByKey[entry.refKey] = entry
        if availability ~= Identity.UNAVAILABLE then projection.entriesByKey[entry.refKey] = entry end
        if selected then projection.variantByKey[entry.refKey] = selected.spellId end

        if availability == Identity.AVAILABLE then
            projection.available[#projection.available + 1] = entry
            projection.availableCount = projection.availableCount + 1
            local normalized = Identity.NormalizeSearch(entry.displayName)
            nameCounts[normalized] = (nameCounts[normalized] or 0) + 1
        elseif availability == Identity.CONFLICTED then
            projection.available[#projection.available + 1] = entry
            projection.conflicted[#projection.conflicted + 1] = entry
            projection.availableCount = projection.availableCount + 1
            projection.conflictedCount = projection.conflictedCount + 1
            local normalized = Identity.NormalizeSearch(entry.displayName)
            nameCounts[normalized] = (nameCounts[normalized] or 0) + 1
        elseif availability == Identity.UNKNOWN then
            projection.unverified[#projection.unverified + 1] = entry
            projection.unverifiedCount = projection.unverifiedCount + 1
        else
            projection.unavailable[#projection.unavailable + 1] = entry
            projection.unavailableCount = projection.unavailableCount + 1
        end
    end

    for _, entry in ipairs(projection.available) do
        if (nameCounts[Identity.NormalizeSearch(entry.displayName)] or 0) > 1 then
            local semantic = EbonBuilds.EchoSemantics and EbonBuilds.EchoSemantics.Summary(entry.semantics, 2) or nil
            entry.disambiguator = semantic and semantic ~= "Unclassified" and semantic
                or ("Implementation " .. tostring(entry.refKey))
        end
    end

    table.sort(projection.available, SortEntries)
    table.sort(projection.unverified, SortEntries)
    table.sort(projection.conflicted, SortEntries)
    table.sort(projection.unavailable, SortEntries)
    cache[classToken] = projection
    return projection
end

function Projection.Invalidate()
    for key in pairs(cache) do cache[key] = nil end
end

function Projection.Get(classToken) return Build(classToken) end
function Projection.GetAvailable(classToken) return Build(classToken).available end
function Projection.GetUnverified(classToken) return Build(classToken).unverified end
function Projection.GetUnavailable(classToken) return Build(classToken).unavailable end
function Projection.GetConflicted(classToken) return Build(classToken).conflicted end
function Projection.GetEntry(classToken, refKey) return Build(classToken).entriesByKey[tostring(refKey or "")] end
function Projection.GetAnyEntry(classToken, refKey) return Build(classToken).allEntriesByKey[tostring(refKey or "")] end
function Projection.GetRevision(classToken) return Build(classToken).catalogRevision end

function Projection.GetBestVariant(classToken, refKey, preferredSpellId)
    local entry = Projection.GetEntry(classToken, refKey)
    if not entry then return nil, 0, nil, nil end
    return EbonBuilds.EchoCatalog.GetBestByRef(refKey, classToken, preferredSpellId)
end

function Projection.ResolveSpell(classToken, spellId)
    local variant = EbonBuilds.EchoCatalog.GetBySpellId(spellId)
    if not variant then return nil end
    local entry = Projection.GetEntry(classToken, variant.refKey)
    if not entry then return nil end
    local availability = EbonBuilds.EchoCatalog.GetAvailability(variant, classToken)
    if availability ~= Identity.AVAILABLE and availability ~= Identity.CONFLICTED then return nil end
    return entry, variant
end

function Projection.Find(classToken, query, includeUnverified, includeUnavailable)
    local projection = Build(classToken)
    local normalized = Identity.NormalizeSearch(query)
    local out = {}
    local function Scan(list)
        for _, entry in ipairs(list or {}) do
            if normalized == "" or string.find(entry.searchBlob or "", normalized, 1, true) then
                out[#out + 1] = entry
            end
        end
    end
    Scan(projection.available)
    if includeUnverified then Scan(projection.unverified) end
    if includeUnavailable then Scan(projection.unavailable) end
    return out
end

function Projection.Counts(classToken)
    local projection = Build(classToken)
    return projection.availableCount, projection.unverifiedCount, projection.conflictedCount,
        projection.unavailableCount, projection.fullCount
end

Projection.CLASS_ORDER = CLASS_ORDER
