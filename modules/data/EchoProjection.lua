local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoProjection.lua
-- Canonical class projection over exact resolved spell variants. Group rows are
-- derived views; consumers may only select/export variants from the resolved
-- available variant collections exposed here.

EbonBuilds.EchoProjection = {}

local Projection = EbonBuilds.EchoProjection
local Identity = EbonBuilds.EchoIdentity
local cache = {}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function SortEntries(a, b)
    local an = string.lower(a.displayName or a.sourceName or "")
    local bn = string.lower(b.displayName or b.sourceName or "")
    if an ~= bn then return an < bn end
    return tostring(a.refKey) < tostring(b.refKey)
end

local function IsAvailable(state)
    return EbonBuilds.EchoEligibilityResolver
        and EbonBuilds.EchoEligibilityResolver.IsAvailableState(state)
        or state == Identity.AVAILABLE or state == Identity.CONFLICTED
end

local function MakeEntry(definition, classToken)
    local availableVariants, unverifiedVariants, unavailableVariants = {}, {}, {}
    local availableBySpell, availableByQuality, stateBySpell = {}, {}, {}
    local variantsBySpellId = {}
    local qualities, spellIds, familySet = {}, {}, {}
    local representative
    local representativeState, representativeReason, representativeFlags, representativeConfidence, representativeDiscrepancy
    local effectiveGroupMask = 0

    for _, variant in ipairs(definition.variants or {}) do
        local state, reason, declaredMask, effectiveMask, flags, confidence, discrepancy =
            EbonBuilds.EchoEligibilityResolver.ResolveVariant(variant, classToken)
        variantsBySpellId[variant.spellId] = variant
        stateBySpell[variant.spellId] = {
            state = state,
            reason = reason,
            declaredMask = declaredMask,
            effectiveMask = effectiveMask,
            evidenceFlags = flags,
            confidence = confidence,
            discrepancyFlags = discrepancy,
        }
        if IsAvailable(state) then
            availableVariants[#availableVariants + 1] = variant
            availableBySpell[variant.spellId] = variant
            local quality = tonumber(variant.quality) or 0
            if not availableByQuality[quality] then availableByQuality[quality] = variant end
            qualities[quality] = true
            spellIds[quality] = spellIds[quality] and math.min(spellIds[quality], variant.spellId) or variant.spellId
            effectiveGroupMask = bit.bor(effectiveGroupMask, tonumber(effectiveMask) or 0)
            if not representative then
                representative = variant
                representativeState = state
                representativeReason = reason
                representativeFlags = flags
                representativeConfidence = confidence
                representativeDiscrepancy = discrepancy
            end
            for _, family in ipairs(variant.families or {}) do familySet[family] = true end
        elseif state == Identity.UNKNOWN then
            unverifiedVariants[#unverifiedVariants + 1] = variant
        else
            unavailableVariants[#unavailableVariants + 1] = variant
        end
    end

    local groupState, groupReason
    local scopedVariants
    if representative then
        groupState = representativeState
        groupReason = representativeReason
        scopedVariants = availableVariants
    elseif #unverifiedVariants > 0 then
        groupState = Identity.UNKNOWN
        groupReason = stateBySpell[unverifiedVariants[1].spellId].reason
        scopedVariants = unverifiedVariants
        representative = unverifiedVariants[1]
    else
        groupState = Identity.UNAVAILABLE
        groupReason = #unavailableVariants > 0 and stateBySpell[unavailableVariants[1].spellId].reason or "NO_VARIANTS"
        scopedVariants = unavailableVariants
        representative = unavailableVariants[1]
    end

    local families = {}
    for family in pairs(familySet) do families[#families + 1] = family end
    table.sort(families)
    if #families == 0 then families = definition.families or {} end

    local displayName = definition.displayName or definition.canonicalName or definition.sourceName
    local entry = {
        key = definition.refKey,
        refKey = definition.refKey,
        groupId = definition.groupId,
        identitySignature = definition.identitySignature,

        canonicalName = definition.canonicalName or definition.sourceName,
        name = displayName,
        displayName = displayName,
        sourceName = definition.sourceName,
        safeAliases = definition.safeAliases or definition.aliases or {},
        aliases = definition.safeAliases or definition.aliases or {},
        quarantinedAliases = definition.quarantinedAliases or {},
        searchBlob = definition.searchBlob,

        allVariants = definition.variants or {},
        variants = scopedVariants,
        variantsBySpellId = variantsBySpellId,
        availableVariants = availableVariants,
        unverifiedVariants = unverifiedVariants,
        unavailableVariants = unavailableVariants,
        availableVariantBySpellId = availableBySpell,
        availableVariantByQuality = availableByQuality,
        variantStateBySpellId = stateBySpell,

        qualities = qualities,
        spellIds = spellIds,
        spellId = representative and representative.spellId or definition.spellId,
        representativeSpellId = representative and representative.spellId or definition.spellId,
        quality = representative and representative.quality or definition.quality,
        icon = representative and representative.icon or definition.icon,
        effectiveMask = effectiveGroupMask,

        semantics = representative and representative.semantics or definition.semantics,
        families = families,
        requiredSpell = representative and representative.requiredSpell or 0,
        functionallyReady = not representative or (tonumber(representative.requiredSpell) or 0) == 0
            or (IsSpellKnown and IsSpellKnown(representative.requiredSpell)) or false,

        availability = groupState,
        availabilityState = groupState,
        availabilityReason = groupReason,
        evidenceFlags = representativeFlags or 0,
        confidence = representativeConfidence or 0,
        discrepancyFlags = representativeDiscrepancy or 0,
        availabilitySource = representative and representative.sourceKind or "BUNDLED",
        internalComment = representative and representative.internalComment or nil,
    }
    return entry
end

local function Build(classToken)
    classToken = tostring(classToken or ""):upper()
    local catalogRevision = EbonBuilds.EchoCatalog.GetRevision()
    local identityRevision = EbonBuilds.EchoIdentityResolver and EbonBuilds.EchoIdentityResolver.GetRevision() or 0
    local eligibilityRevision = EbonBuilds.EchoEligibilityEvidence and EbonBuilds.EchoEligibilityEvidence.GetRevision() or 0
    local fingerprint = EbonBuilds.EchoCatalog.GetFingerprint()
    local existing = cache[classToken]
    if existing and existing.catalogRevision == catalogRevision
        and existing.identityRevision == identityRevision
        and existing.eligibilityRevision == eligibilityRevision
        and existing.catalogFingerprint == fingerprint then
        return existing
    end

    local projection = {
        classToken = classToken,
        catalogRevision = catalogRevision,
        identityRevision = identityRevision,
        eligibilityRevision = eligibilityRevision,
        catalogFingerprint = fingerprint,
        available = {}, unverified = {}, conflicted = {}, unavailable = {},
        entriesByKey = {}, allEntriesByKey = {}, entriesBySpellId = {},
        availableCount = 0, unverifiedCount = 0, conflictedCount = 0,
        unavailableCount = 0, fullCount = 0,
    }
    local nameCounts = {}

    for _, definition in ipairs(EbonBuilds.EchoCatalog.GetSortedList() or {}) do
        projection.fullCount = projection.fullCount + 1
        local entry = MakeEntry(definition, classToken)
        projection.allEntriesByKey[entry.refKey] = entry
        if IsAvailable(entry.availability) then projection.entriesByKey[entry.refKey] = entry end
        for spellId, variant in pairs(entry.availableVariantBySpellId) do
            projection.entriesBySpellId[spellId] = { entry = entry, variant = variant }
        end

        if IsAvailable(entry.availability) then
            projection.available[#projection.available + 1] = entry
            projection.availableCount = projection.availableCount + 1
            if entry.availability == Identity.CONFLICTED then
                projection.conflicted[#projection.conflicted + 1] = entry
                projection.conflictedCount = projection.conflictedCount + 1
            end
            local normalized = Identity.NormalizeSearch(entry.displayName)
            nameCounts[normalized] = (nameCounts[normalized] or 0) + 1
        elseif entry.availability == Identity.UNKNOWN then
            projection.unverified[#projection.unverified + 1] = entry
            projection.unverifiedCount = projection.unverifiedCount + 1
        else
            projection.unavailable[#projection.unavailable + 1] = entry
            projection.unavailableCount = projection.unavailableCount + 1
        end
    end

    for _, entry in ipairs(projection.available) do
        if (nameCounts[Identity.NormalizeSearch(entry.displayName)] or 0) > 1 then
            entry.disambiguator = "Echo " .. tostring(entry.refKey)
        end
    end

    table.sort(projection.available, SortEntries)
    table.sort(projection.unverified, SortEntries)
    table.sort(projection.conflicted, SortEntries)
    table.sort(projection.unavailable, SortEntries)
    cache[classToken] = projection
    return projection
end

function Projection.Invalidate(classToken)
    if classToken then cache[tostring(classToken):upper()] = nil
    else Clear(cache) end
end

function Projection.Get(classToken) return Build(classToken) end
function Projection.GetAvailable(classToken) return Build(classToken).available end
function Projection.GetUnverified(classToken) return Build(classToken).unverified end
function Projection.GetUnavailable(classToken) return Build(classToken).unavailable end
function Projection.GetConflicted(classToken) return Build(classToken).conflicted end
function Projection.GetEntry(classToken, refKey) return Build(classToken).entriesByKey[tostring(refKey or "")] end
function Projection.GetAnyEntry(classToken, refKey) return Build(classToken).allEntriesByKey[tostring(refKey or "")] end
function Projection.GetRevision(classToken)
    local projection = Build(classToken)
    return tostring(projection.catalogRevision) .. ":" .. tostring(projection.identityRevision)
        .. ":" .. tostring(projection.eligibilityRevision)
end

function Projection.GetBestVariant(classToken, refKey, preferredSpellId)
    local entry = Projection.GetEntry(classToken, refKey)
    if not entry or #entry.availableVariants == 0 then return nil, 0, nil, nil end
    preferredSpellId = tonumber(preferredSpellId)
    if preferredSpellId then
        local preferred = entry.availableVariantBySpellId[preferredSpellId]
        if preferred then
            return preferred.spellId, preferred.quality,
                EbonBuilds.EchoCatalog.GetByRef(entry.refKey), preferred
        end
    end
    local variant = entry.availableVariants[1]
    return variant.spellId, variant.quality, EbonBuilds.EchoCatalog.GetByRef(entry.refKey), variant
end

function Projection.ResolveSpell(classToken, spellId)
    spellId = tonumber(spellId)
    local resolved = spellId and Build(classToken).entriesBySpellId[spellId]
    if not resolved then return nil end
    return resolved.entry, resolved.variant,
        resolved.entry.variantStateBySpellId[spellId]
end

function Projection.ResolveOfferedSpell(classToken, spellId)
    local variant = EbonBuilds.EchoCatalog.GetBySpellId(spellId)
    if not variant then return nil end
    local state = EbonBuilds.EchoEligibilityResolver.ResolveVariant(variant, classToken)
    if not IsAvailable(state) then return nil end
    return EbonBuilds.EchoCatalog.GetByRef(variant.refKey), variant, state
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

-- Projection invalidation is immediate and cheap; renderer notification is
-- keyed and deferred outside combat. This prevents an Echo offer from causing
-- full list sorting or pooled-row rebinding in the choice/selection hot path.
local pendingProjectionReason = {}
local projectionNotifyCallbacks = {}
local PROJECTION_NOTIFY_ALL = "echoProjection.notify.all"

local function EmitProjectionChanged(classToken)
    local key = classToken or "ALL"
    local reason = pendingProjectionReason[key]
    pendingProjectionReason[key] = nil
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("ECHO_PROJECTION_CHANGED", classToken, reason)
    end
end

for _, classToken in ipairs(CLASS_ORDER) do
    local captured = classToken
    projectionNotifyCallbacks[captured] = function()
        EmitProjectionChanged(captured)
    end
end
local function EmitAllProjectionChanged()
    EmitProjectionChanged(nil)
end

local function ScheduleProjectionChanged(classToken, reason)
    local key = classToken or "ALL"
    pendingProjectionReason[key] = reason or pendingProjectionReason[key] or "changed"
    if not EbonBuilds.Scheduler then
        EmitProjectionChanged(classToken)
        return
    end
    local taskId = classToken and ("echoProjection.notify." .. classToken) or PROJECTION_NOTIFY_ALL
    local callback = classToken and projectionNotifyCallbacks[classToken] or EmitAllProjectionChanged
    EbonBuilds.Scheduler.After(taskId, 0, callback, EbonBuilds.Scheduler.BACKGROUND, false)
end

if EbonBuilds.EventHub then
    EbonBuilds.EventHub.On("ECHO_CATALOG_CHANGED", function()
        Projection.Invalidate()
        ScheduleProjectionChanged(nil, "catalog")
    end)
    EbonBuilds.EventHub.On("ECHO_IDENTITY_CHANGED", function()
        Projection.Invalidate()
        ScheduleProjectionChanged(nil, "identity")
    end)
    EbonBuilds.EventHub.On("ECHO_ELIGIBILITY_CHANGED", function(_, _, classToken)
        Projection.Invalidate(classToken)
        ScheduleProjectionChanged(classToken, "eligibility")
    end)
end
