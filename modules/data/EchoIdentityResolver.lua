local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoIdentityResolver.lua
-- Canonical Echo identity and safe alias resolution. Runtime spell names are
-- presentation metadata only and may not overwrite a bundled canonical Echo.

EbonBuilds.EchoIdentityResolver = {}

local Resolver = EbonBuilds.EchoIdentityResolver
local Identity = EbonBuilds.EchoIdentity

local safeIndex = {}
local quarantinedIndex = {}
local diagnostics = {}
local revision = 0

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function AddBucket(index, normalized, refKey)
    if not normalized or normalized == "" or not refKey then return end
    local bucket = index[normalized]
    if not bucket then bucket = {}; index[normalized] = bucket end
    bucket[refKey] = true
end

local function AddUnique(list, seen, value)
    value = Identity.VisibleName(value)
    if value == "" then return end
    local normalized = Identity.NormalizeSearch(value)
    if normalized == "" or seen[normalized] then return end
    seen[normalized] = true
    list[#list + 1] = value
end

local function HashText(hash, value)
    value = tostring(value or "")
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 4294967296
    end
    return hash
end

local function DefinitionSignature(definition)
    if type(definition) ~= "table" then return 0 end
    local hash = 5381
    hash = HashText(hash, definition.groupId or 0)
    hash = HashText(hash, Identity.NormalizeSearch(definition.canonicalName or definition.sourceName))
    hash = HashText(hash, definition.descriptionHash or 0)
    for _, variant in ipairs(definition.variants or {}) do
        hash = HashText(hash, variant.spellId or 0)
        hash = HashText(hash, variant.quality or 0)
        hash = HashText(hash, variant.staticClassMask or variant.classMask or 0)
        hash = HashText(hash, variant.requiredSpell or 0)
    end
    return hash
end

local function IsAliasSafe(normalized, refKey, canonicalBuckets, runtimeBuckets)
    if normalized == "" then return false end
    local canonical = canonicalBuckets[normalized]
    if canonical then
        local onlySelf = true
        for otherRef in pairs(canonical) do
            if otherRef ~= refKey then onlySelf = false; break end
        end
        if not onlySelf then return false end
    end
    local runtime = runtimeBuckets[normalized]
    if runtime then
        local onlySelf = true
        for otherRef in pairs(runtime) do
            if otherRef ~= refKey then onlySelf = false; break end
        end
        if not onlySelf then return false end
    end
    return true
end

function Resolver.Finalize(definitions)
    Clear(safeIndex)
    Clear(quarantinedIndex)
    Clear(diagnostics)

    local canonicalBuckets, runtimeBuckets = {}, {}
    for _, definition in ipairs(definitions or {}) do
        definition.canonicalName = Identity.VisibleName(definition.sourceName or definition.name)
        AddBucket(canonicalBuckets, Identity.NormalizeSearch(definition.canonicalName), definition.refKey)
        for _, variant in ipairs(definition.variants or {}) do
            variant.runtimeSpellName = Identity.VisibleName(variant.localizedName)
            local normalized = Identity.NormalizeSearch(variant.runtimeSpellName)
            if normalized ~= "" then AddBucket(runtimeBuckets, normalized, definition.refKey) end
            local comment = Identity.StripClassPrefix(Identity.StripQualitySuffix(variant.internalComment))
            normalized = Identity.NormalizeSearch(comment)
            if normalized ~= "" then AddBucket(runtimeBuckets, normalized, definition.refKey) end
        end
    end

    for _, definition in ipairs(definitions or {}) do
        local safeAliases, safeSeen = {}, {}
        local quarantinedAliases, quarantineSeen = {}, {}
        AddUnique(safeAliases, safeSeen, definition.canonicalName)

        local chosenLocalized
        for _, variant in ipairs(definition.variants or {}) do
            local runtimeName = variant.runtimeSpellName
            local runtimeNorm = Identity.NormalizeSearch(runtimeName)
            if runtimeNorm ~= "" and IsAliasSafe(runtimeNorm, definition.refKey, canonicalBuckets, runtimeBuckets) then
                variant.safeLocalizedName = runtimeName
                AddUnique(safeAliases, safeSeen, runtimeName)
                if not chosenLocalized then chosenLocalized = runtimeName end
            elseif runtimeNorm ~= "" then
                variant.safeLocalizedName = nil
                AddUnique(quarantinedAliases, quarantineSeen, runtimeName)
                AddBucket(quarantinedIndex, runtimeNorm, definition.refKey)
                diagnostics[#diagnostics + 1] = {
                    kind = "NAME_COLLISION",
                    refKey = definition.refKey,
                    spellId = variant.spellId,
                    canonicalName = definition.canonicalName,
                    runtimeName = runtimeName,
                }
            end

            local comment = Identity.StripClassPrefix(Identity.StripQualitySuffix(variant.internalComment))
            local commentNorm = Identity.NormalizeSearch(comment)
            if commentNorm ~= "" and IsAliasSafe(commentNorm, definition.refKey, canonicalBuckets, runtimeBuckets) then
                AddUnique(safeAliases, safeSeen, comment)
            elseif commentNorm ~= "" then
                AddUnique(quarantinedAliases, quarantineSeen, comment)
                AddBucket(quarantinedIndex, commentNorm, definition.refKey)
            end
        end

        definition.safeAliases = safeAliases
        definition.aliases = safeAliases -- compatibility: only safe aliases leave the resolver
        definition.quarantinedAliases = quarantinedAliases
        definition.safeLocalizedName = chosenLocalized
        definition.displayName = chosenLocalized or definition.canonicalName
        definition.name = definition.displayName
        definition.identitySignature = DefinitionSignature(definition)

        for _, alias in ipairs(safeAliases) do
            AddBucket(safeIndex, Identity.NormalizeSearch(alias), definition.refKey)
        end
        AddBucket(safeIndex, Identity.NormalizeSearch(definition.refKey), definition.refKey)
        for _, variant in ipairs(definition.variants or {}) do
            AddBucket(safeIndex, tostring(variant.spellId), definition.refKey)
        end
    end

    revision = revision + 1
    return revision
end

local function RefsFromBucket(bucket)
    local refs = {}
    for refKey in pairs(bucket or {}) do refs[#refs + 1] = refKey end
    table.sort(refs)
    return refs
end

function Resolver.FindRefs(value)
    local normalized = Identity.NormalizeSearch(value)
    if normalized == "" then normalized = tostring(value or "") end
    return RefsFromBucket(safeIndex[normalized])
end

function Resolver.FindLegacyRefs(value)
    local normalized = Identity.NormalizeSearch(value)
    if normalized == "" then normalized = tostring(value or "") end
    local combined = {}
    for refKey in pairs(safeIndex[normalized] or {}) do combined[refKey] = true end
    for refKey in pairs(quarantinedIndex[normalized] or {}) do combined[refKey] = true end
    return RefsFromBucket(combined)
end

function Resolver.GetSignature(definitionOrRef)
    local definition = type(definitionOrRef) == "table" and definitionOrRef
        or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(definitionOrRef))
    return definition and (definition.identitySignature or DefinitionSignature(definition)) or 0
end

function Resolver.GetCanonicalName(refKey)
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    return definition and definition.canonicalName or nil
end

function Resolver.GetDisplayName(refKey)
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    return definition and definition.displayName or nil
end

function Resolver.GetQuarantinedAliases(refKey)
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    return definition and definition.quarantinedAliases or nil
end

function Resolver.GetDiagnostics() return diagnostics end
function Resolver.GetRevision() return revision end
