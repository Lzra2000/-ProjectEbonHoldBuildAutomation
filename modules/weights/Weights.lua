local addonName, EbonBuilds = ...

-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write and migrate rank-specific echo weights stored on
-- the active build. Legacy single-number entries remain readable and are
-- migrated to one value per quality without changing their effective score.

EbonBuilds.Weights = {}

local W = EbonBuilds.Weights

-- Preserve the old six-digit positive range and extend it symmetrically for
-- negative values. Echo weights remain whole numbers; decimal input was not
-- supported by the project before this migration.
W.MIN_VALUE = -999999
W.MAX_VALUE =  999999

------------------------------------------------------------------------
-- Canonical echo name
------------------------------------------------------------------------

local QUALITY_SUFFIXES = {}
local function EscapePattern(value)
    return tostring(value):gsub("([^%w])", "%%%1")
end
for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
    local label = EbonBuilds.Quality.LABELS[quality]
    if label then QUALITY_SUFFIXES[#QUALITY_SUFFIXES + 1] = " %- " .. EscapePattern(label) .. "$" end
end

function W.StripQualitySuffix(name)
    name = tostring(name or "")
    for _, pattern in ipairs(QUALITY_SUFFIXES) do
        local stripped = name:match("^(.+)" .. pattern)
        if stripped then return stripped end
    end
    return name
end

-- Some Project Ebonhold database comments append an invisible control-byte
-- discriminator to otherwise identical player-facing Echo names. Keep that
-- suffix in storage keys so distinct variants do not collapse, but never pass
-- it to FontStrings, search, or WoW's locale string helpers.
function W.VisibleName(name)
    name = tostring(name or "")
    for index = 1, #name do
        local byte = name:byte(index)
        if byte and (byte < 32 or byte == 127) then
            name = name:sub(1, index - 1)
            break
        end
    end
    return name:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Compatibility display name for an exact spell. The real player-facing
-- source name is authoritative; ProjectEbonhold comments are legacy aliases.
function W.CanonicalName(spellId)
    spellId = tonumber(spellId)
    if not spellId then return nil end
    if EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId then
        local variant = EbonBuilds.EchoCatalog.GetBySpellId(spellId)
        if variant and variant.sourceName and variant.sourceName ~= "" then
            return variant.sourceName
        end
    end
    if EbonBuilds.EchoIdentity and EbonBuilds.EchoIdentity.GetBundledSpell then
        local bundled = EbonBuilds.EchoIdentity.GetBundledSpell(spellId)
        if bundled and bundled.sourceName then return bundled.sourceName end
    end
    local raw = GetSpellInfo and GetSpellInfo(spellId)
    if not raw then
        local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase
            and (ProjectEbonhold.PerkDatabase[spellId] or ProjectEbonhold.PerkDatabase[tostring(spellId)])
        raw = data and data.comment
    end
    if not raw then return nil end
    return W.VisibleName(W.StripQualitySuffix(raw))
end

------------------------------------------------------------------------
-- Validation / normalization
------------------------------------------------------------------------

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function W.Validate(value)
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "Enter a finite whole number."
        end
        if math.floor(value) ~= value then
            return nil, "Whole numbers only; decimals are not supported."
        end
    elseif type(value) == "string" then
        local raw = Trim(value)
        if raw == "" then return nil, "A value is required." end
        if not raw:match("^[+-]?%d+$") then
            return nil, "Enter a whole number, for example -10, 0, or 25."
        end
        value = tonumber(raw)
    else
        return nil, "Enter a numeric value."
    end

    if not value then return nil, "Enter a valid whole number." end
    if value < W.MIN_VALUE or value > W.MAX_VALUE then
        return nil, string.format("Value must be between %d and %d.", W.MIN_VALUE, W.MAX_VALUE)
    end
    return math.floor(value), nil
end

function W.MakeUniform(value)
    local valid = W.Validate(value)
    if valid == nil then valid = 0 end
    local out = {}
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        out[quality] = valid
    end
    return out
end

-- Normalizes malformed, partial, legacy, and imported values defensively.
-- Missing rank-specific values fall back to `default` when present, otherwise
-- to zero. A legacy number is copied to every quality rank.
function W.NormalizeEntry(value)
    if type(value) == "number" or type(value) == "string" then
        local valid = W.Validate(value)
        return W.MakeUniform(valid or 0)
    end

    local out = {}
    local fallback = 0
    if type(value) == "table" then
        local maybeDefault = value.default
        local validDefault = W.Validate(maybeDefault)
        if validDefault ~= nil then fallback = validDefault end
    end

    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        local raw = type(value) == "table" and (value[quality] ~= nil and value[quality] or value[tostring(quality)]) or nil
        local valid = W.Validate(raw)
        out[quality] = valid ~= nil and valid or fallback
    end

    -- Keep unknown numeric rank data intact for forward/backward compatibility,
    -- but do not expose it in the current four-rank interface. This prevents a
    -- UI-only rank change from destroying values during edit, import, or sync.
    if type(value) == "table" then
        for rawKey, rawValue in pairs(value) do
            local numericKey = type(rawKey) == "number" and rawKey
                or (type(rawKey) == "string" and rawKey:match("^%d+$") and tonumber(rawKey))
            if numericKey and not EbonBuilds.Quality.IsValid(numericKey) then
                local valid = W.Validate(rawValue)
                if valid ~= nil then out[numericKey] = valid end
            end
        end
    end
    return out
end

function W.NormalizeWeights(weights)
    local out = {}
    if type(weights) ~= "table" then return out end
    for name, value in pairs(weights) do
        if type(name) == "string" and name ~= "" then
            out[name] = W.NormalizeEntry(value)
        end
    end
    return out
end

function W.CloneWeights(weights)
    return W.NormalizeWeights(weights)
end

function W.Init()
    -- Storage lives on each build. Migration runs from Build.Migrate after all
    -- modules have loaded.
end

------------------------------------------------------------------------
-- Reads / writes
------------------------------------------------------------------------

function W.GetFromWeights(weights, echoName, quality)
    if type(weights) ~= "table" then return 0 end
    local entry = weights[echoName]
    if type(entry) == "number" or type(entry) == "string" then
        local valid = W.Validate(entry)
        return valid or 0
    end
    if type(entry) ~= "table" then return 0 end

    if quality ~= nil then
        local raw = entry[quality]
        if raw == nil then raw = entry[tostring(quality)] end
        local valid = W.Validate(raw)
        if valid ~= nil then return valid end
        local fallback = W.Validate(entry.default)
        return fallback or 0
    end

    local fallback = W.Validate(entry.default)
    if fallback ~= nil then return fallback end
    for _, rank in ipairs(EbonBuilds.Quality.ORDER or {}) do
        local valid = W.Validate(entry[rank])
        if valid ~= nil then return valid end
    end
    return 0
end

function W.Get(echoName, quality)
    return W.GetFromWeights(EbonBuilds.Build.GetActiveWeights(), echoName, quality)
end

-- Writes one rank when quality is provided. Calls without quality preserve the
-- old API by assigning the same value to every quality rank.
function W.Set(echoName, value, quality)
    local valid, err = W.Validate(value)
    if valid == nil then return false, err end
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return false, "No active build." end

    if quality == nil then
        weights[echoName] = W.MakeUniform(valid)
    else
        if not EbonBuilds.Quality.IsValid(quality) then
            return false, "Unknown quality rank."
        end
        local entry = W.NormalizeEntry(weights[echoName])
        entry[quality] = valid
        weights[echoName] = entry
    end

    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    return true
end

function W.HasNonZero(entry)
    if type(entry) == "number" or type(entry) == "string" then
        local valid = W.Validate(entry)
        return valid ~= nil and valid ~= 0
    end
    if type(entry) ~= "table" then return false end
    local normalized = W.NormalizeEntry(entry)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if normalized[quality] ~= 0 then return true end
    end
    return false
end

function W.MaxFromWeights(weights, echoName, qualities)
    local best = nil
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if not qualities or qualities[quality] then
            local value = W.GetFromWeights(weights, echoName, quality)
            if best == nil or value > best then best = value end
        end
    end
    return best or 0
end

function W.DescribeFromWeights(weights, echoName, qualities)
    local parts = {}
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if not qualities or qualities[quality] then
            local label = EbonBuilds.Quality.LABELS[quality] or tostring(quality)
            parts[#parts + 1] = label .. "=" .. tostring(W.GetFromWeights(weights, echoName, quality))
        end
    end
    return table.concat(parts, ", ")
end


------------------------------------------------------------------------
-- Versioned reference weights
------------------------------------------------------------------------

function W.NormalizeRefWeights(weights)
    local out = {}
    if type(weights) ~= "table" then return out end
    for refKey, value in pairs(weights) do
        if type(refKey) == "string" and refKey:match("^[gs]:%d+$") then
            out[refKey] = W.NormalizeEntry(value)
        end
    end
    return out
end

function W.CloneRefWeights(weights)
    return W.NormalizeRefWeights(weights)
end

local function ActiveBuild()
    return EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive() or nil
end


local function EffectiveRefWeights(build)
    if EbonBuilds.Runtime and EbonBuilds.Runtime.isEditingBuild and type(EbonBuilds.Runtime.pendingRefWeights) == "table" then
        return EbonBuilds.Runtime.pendingRefWeights
    end
    return type(build) == "table" and build.echoWeightsByRef or nil
end

local function EffectiveLegacyWeights(build)
    if EbonBuilds.Runtime and EbonBuilds.Runtime.isEditingBuild and type(EbonBuilds.Runtime.pendingWeights) == "table" then
        return EbonBuilds.Runtime.pendingWeights
    end
    return type(build) == "table" and build.echoWeights or nil
end

local function ResolveRefByName(name, classToken)
    if not EbonBuilds.EchoCatalog then return nil, "CATALOG_UNAVAILABLE" end
    local refs = EbonBuilds.EchoCatalog.FindLegacyRefs
        and EbonBuilds.EchoCatalog.FindLegacyRefs(name)
        or EbonBuilds.EchoCatalog.FindRefs(name)
    if #refs == 1 then return refs[1] end
    if #refs > 1 then return nil, "AMBIGUOUS_ALIAS", refs end
    return nil, "MISSING_ALIAS"
end

function W.ResolveLegacyName(build, name)
    return ResolveRefByName(name, build and build.class)
end

function W.GetForRef(build, refKey, quality)
    if type(build) ~= "table" then build = ActiveBuild() end
    refKey = tostring(refKey or "")
    local refWeights = EffectiveRefWeights(build)
    if type(refWeights) == "table" and refWeights[refKey] ~= nil then
        return W.GetFromWeights(refWeights, refKey, quality)
    end
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    if definition then
        local legacy = EffectiveLegacyWeights(build) or {}
        if legacy[definition.sourceName] ~= nil then
            local resolved = ResolveRefByName(definition.sourceName, build and build.class)
            if resolved == refKey then return W.GetFromWeights(legacy, definition.sourceName, quality) end
        end
        for _, alias in ipairs(definition.aliases or {}) do
            if legacy[alias] ~= nil then
                local resolved = ResolveRefByName(alias, build.class)
                if resolved == refKey then return W.GetFromWeights(legacy, alias, quality) end
            end
        end
    end
    return 0
end

function W.GetForSpell(build, spellId, quality)
    if type(build) ~= "table" then build = ActiveBuild() end
    if not build then return 0 end
    local refKey = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(spellId)
    if refKey then return W.GetForRef(build, refKey, quality) end
    local name = W.CanonicalName(spellId)
    return name and W.GetFromWeights(build.echoWeights or {}, name, quality) or 0
end

-- Returns whether a canonical Echo reference has at least one non-zero rank
-- value in the effective build configuration.  Consumers must use this
-- accessor instead of reading echoWeightsByRef directly: imported/legacy
-- builds may still carry valid name-keyed values, and the editor may expose a
-- pending reference table while the durable build remains unchanged.
function W.HasNonZeroForRef(build, refKey)
    if type(build) ~= "table" then build = ActiveBuild() end
    if not build or not refKey then return false end
    local order = EbonBuilds.Quality and EbonBuilds.Quality.ORDER or { 3, 2, 1, 0 }
    for _, quality in ipairs(order) do
        local value = tonumber(W.GetForRef(build, refKey, quality)) or 0
        if value ~= 0 then return true end
    end
    return false
end

function W.SetForRef(build, refKey, value, quality)
    if type(build) ~= "table" then build = ActiveBuild() end
    local pending = EbonBuilds.Runtime and EbonBuilds.Runtime.isEditingBuild and type(EbonBuilds.Runtime.pendingRefWeights) == "table"
    if type(build) ~= "table" and not pending then return false, "No build." end
    local valid, err = W.Validate(value)
    if valid == nil then return false, err end
    refKey = tostring(refKey or "")
    if not refKey:match("^[gs]:%d+$") then return false, "Unknown Echo reference." end
    local refWeights = EffectiveRefWeights(build)
    if not refWeights then
        build.echoWeightsByRef = build.echoWeightsByRef or {}
        refWeights = build.echoWeightsByRef
    end
    if quality == nil then
        refWeights[refKey] = W.MakeUniform(valid)
    else
        if not EbonBuilds.Quality.IsValid(quality) then return false, "Unknown quality rank." end
        local entry = W.NormalizeEntry(refWeights[refKey])
        entry[quality] = valid
        refWeights[refKey] = entry
    end
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    if definition then
        local legacyWeights = EffectiveLegacyWeights(build)
        if not legacyWeights and build then build.echoWeights = build.echoWeights or {}; legacyWeights = build.echoWeights end
        local resolved = ResolveRefByName(definition.sourceName, build and build.class)
        if legacyWeights and resolved == refKey then
            legacyWeights[definition.sourceName] = W.NormalizeEntry(refWeights[refKey])
        end
    end
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    return true
end

-- Returns one normalized effective entry for a canonical Echo reference.
-- This deliberately reads through GetForRef instead of returning the raw
-- schema table. A build may have an allocated but incomplete
-- echoWeightsByRef table while still carrying authoritative legacy/imported
-- name-keyed values; direct table reads make those builds appear empty.
function W.GetEntryForRef(build, refKey)
    if type(build) ~= "table" then build = ActiveBuild() end
    if type(build) ~= "table" or not refKey then return W.MakeUniform(0) end
    local entry = {}
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        entry[quality] = W.GetForRef(build, refKey, quality)
    end
    return entry
end

-- Iterates the union of canonical reference storage and unambiguous legacy
-- name storage. Consumers receive normalized effective rank values, so every
-- UI and analytics view observes the same configuration as scoring and
-- Autopilot. Ambiguous legacy aliases remain quarantined rather than guessed.
function W.IterateResolved(build)
    local keys, seen = {}, {}
    if type(build) ~= "table" then return function() end end

    local refWeights = EffectiveRefWeights(build) or {}
    local legacyWeights = EffectiveLegacyWeights(build) or {}
    for refKey in pairs(refWeights) do
        if type(refKey) == "string" and refKey:match("^[gs]:%d+$") then
            seen[refKey] = true
            keys[#keys + 1] = refKey
        end
    end
    for legacyName in pairs(legacyWeights) do
        local refKey = ResolveRefByName(legacyName, build.class)
        if refKey and not seen[refKey] then
            seen[refKey] = true
            keys[#keys + 1] = refKey
        end
    end

    table.sort(keys)
    local index = 0
    return function()
        index = index + 1
        local refKey = keys[index]
        if not refKey then return nil end
        return refKey, W.GetEntryForRef(build, refKey)
    end
end

local function EntriesEqual(a, b)
    a, b = W.NormalizeEntry(a), W.NormalizeEntry(b)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if a[quality] ~= b[quality] then return false end
    end
    return true
end

local function CurrentReference(refKey)
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey)
    if not definition then return nil end
    return {
        definition.spellId,
        definition.canonicalName or definition.sourceName,
        definition.descriptionHash or 0,
        definition.identitySignature or 0,
    }
end

local function CopyUnresolved(source)
    local out = {}
    for _, item in ipairs(type(source) == "table" and source or {}) do
        if type(item) == "table" then
            out[#out + 1] = {
                legacyName = item.legacyName,
                refKey = item.refKey,
                reason = item.reason,
                candidates = item.candidates,
                weights = W.NormalizeEntry(item.weights),
            }
        end
    end
    return out
end

local function AddMigrated(targetWeights, targetRefs, unresolved, targetRef, sourceKey, weights, reason)
    if not targetRef then
        unresolved[#unresolved + 1] = {
            refKey = sourceKey,
            reason = reason or "UNRESOLVED_REFERENCE",
            weights = W.NormalizeEntry(weights),
        }
        return false
    end
    local existing = targetWeights[targetRef]
    if existing and not EntriesEqual(existing, weights) then
        unresolved[#unresolved + 1] = {
            refKey = sourceKey,
            reason = "REFERENCE_COLLISION",
            candidates = { targetRef },
            weights = W.NormalizeEntry(weights),
        }
        return false
    end
    targetWeights[targetRef] = W.NormalizeEntry(weights)
    targetRefs[targetRef] = CurrentReference(targetRef)
    return true
end

local function RecoverUnresolved(source, targetWeights, targetRefs, unresolved)
    for _, item in ipairs(type(source) == "table" and source or {}) do
        if type(item) == "table" and item.reason == "CROSS_CLASS_REFERENCE" then
            local candidate = type(item.candidates) == "table" and item.candidates[1] or item.refKey
            candidate = tostring(candidate or "")
            if candidate:match("^[gs]:%d+$") and EbonBuilds.EchoCatalog.GetByRef(candidate) then
                AddMigrated(targetWeights, targetRefs, unresolved, candidate,
                    item.refKey or item.legacyName, item.weights, nil)
            else
                unresolved[#unresolved + 1] = {
                    legacyName = item.legacyName,
                    refKey = item.refKey,
                    reason = "CATALOG_REFERENCE_MISSING",
                    candidates = item.candidates,
                    weights = W.NormalizeEntry(item.weights),
                }
            end
        elseif type(item) == "table" then
            unresolved[#unresolved + 1] = {
                legacyName = item.legacyName,
                refKey = item.refKey,
                reason = item.reason,
                candidates = item.candidates,
                weights = W.NormalizeEntry(item.weights),
            }
        end
    end
end

local function ReconcileSchemaTwo(build, currentFingerprint)
    local sourceWeights = W.NormalizeRefWeights(build.echoWeightsByRef or {})
    local sourceRefs = type(build.echoRefs) == "table" and build.echoRefs or {}
    local migrated, refs, unresolved = {}, {}, {}

    for oldRef, weights in pairs(sourceWeights) do
        local stored = sourceRefs[oldRef]
        local storedSpellId = type(stored) == "table" and tonumber(stored[1]) or nil
        local storedName = type(stored) == "table" and stored[2] or nil
        local storedHash = type(stored) == "table" and tonumber(stored[3]) or 0
        local storedSignature = type(stored) == "table" and tonumber(stored[4]) or 0
        local current = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(oldRef)
        local exact = storedSpellId and EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(storedSpellId)
        local targetRef, reason

        if exact then
            targetRef = exact.refKey
        elseif current and stored then
            local sameName = EbonBuilds.EchoIdentity and
                EbonBuilds.EchoIdentity.NormalizeSearch(current.canonicalName or current.sourceName) ==
                EbonBuilds.EchoIdentity.NormalizeSearch(storedName)
            local sameHash = storedHash == 0 or tonumber(current.descriptionHash) == 0
                or storedHash == tonumber(current.descriptionHash)
            local sameSignature = storedSignature == 0 or tonumber(current.identitySignature) == 0
                or storedSignature == tonumber(current.identitySignature)
            if sameName and sameHash and sameSignature then targetRef = oldRef
            else reason = "CATALOG_IDENTITY_MISMATCH" end
        elseif storedName then
            local resolved, resolveReason, candidates = ResolveRefByName(storedName)
            if resolved then targetRef = resolved
            else
                unresolved[#unresolved + 1] = {
                    refKey = oldRef,
                    legacyName = storedName,
                    reason = resolveReason or "CATALOG_REFERENCE_MISSING",
                    candidates = candidates,
                    weights = W.NormalizeEntry(weights),
                }
            end
        elseif current then
            reason = "MISSING_REFERENCE_METADATA"
        else
            reason = "CATALOG_REFERENCE_MISSING"
        end

        if targetRef then
            AddMigrated(migrated, refs, unresolved, targetRef, oldRef, weights, nil)
        elseif not storedName or reason == "CATALOG_IDENTITY_MISMATCH" or reason == "MISSING_REFERENCE_METADATA" then
            unresolved[#unresolved + 1] = {
                refKey = oldRef,
                legacyName = storedName,
                reason = reason or "UNRESOLVED_REFERENCE",
                weights = W.NormalizeEntry(weights),
            }
        end
    end

    RecoverUnresolved(build.unresolvedEchoWeights, migrated, refs, unresolved)
    build.echoWeightsByRef = migrated
    build.echoRefs = refs
    build.unresolvedEchoWeights = #unresolved > 0 and unresolved or nil
    build.echoCatalogFingerprint = currentFingerprint
    build.echoSchema = 3
    return true
end

local function ValidateCurrentSchemaThree(build, currentFingerprint)
    local migrated, refs, unresolved = {}, {}, {}
    for refKey, weights in pairs(W.NormalizeRefWeights(build.echoWeightsByRef or {})) do
        if EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey) then
            migrated[refKey] = W.NormalizeEntry(weights)
            refs[refKey] = CurrentReference(refKey) or (type(build.echoRefs) == "table" and build.echoRefs[refKey])
        else
            unresolved[#unresolved + 1] = {
                refKey = refKey,
                reason = "CATALOG_REFERENCE_MISSING",
                weights = W.NormalizeEntry(weights),
            }
        end
    end
    RecoverUnresolved(build.unresolvedEchoWeights, migrated, refs, unresolved)
    build.echoWeightsByRef = migrated
    build.echoRefs = refs
    build.unresolvedEchoWeights = #unresolved > 0 and unresolved or nil
    build.echoCatalogFingerprint = currentFingerprint or build.echoCatalogFingerprint
    build.echoSchema = 3
    return true
end

function W.MigrateBuild(build)
    if type(build) ~= "table" then return false, "INVALID_BUILD" end
    local currentFingerprint = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint() or nil

    if tonumber(build.echoSchema) == 3 and type(build.echoWeightsByRef) == "table" then
        if not currentFingerprint or build.echoCatalogFingerprint == currentFingerprint then
            return ValidateCurrentSchemaThree(build, currentFingerprint)
        end
        return ReconcileSchemaTwo(build, currentFingerprint)
    end
    if tonumber(build.echoSchema) == 2 and type(build.echoWeightsByRef) == "table" then
        return ReconcileSchemaTwo(build, currentFingerprint)
    end

    local migrated, refs, unresolved = {}, {}, {}
    for legacyName, raw in pairs(build.echoWeights or {}) do
        local refKey, reason, candidates = ResolveRefByName(legacyName, build.class)
        if refKey then
            local normalized = W.NormalizeEntry(raw)
            if migrated[refKey] then
                if not EntriesEqual(migrated[refKey], normalized) then
                    unresolved[#unresolved + 1] = {
                        legacyName = legacyName,
                        reason = "COLLISION",
                        candidates = { refKey },
                        weights = normalized,
                    }
                end
            else
                migrated[refKey] = normalized
                refs[refKey] = CurrentReference(refKey)
            end
        else
            unresolved[#unresolved + 1] = {
                legacyName = legacyName,
                reason = reason or "UNRESOLVED",
                candidates = candidates,
                weights = W.NormalizeEntry(raw),
            }
        end
    end

    -- Atomic commit: no build fields are changed until every legacy entry has
    -- been resolved or quarantined in temporary tables.
    build.echoWeightsByRef = migrated
    build.echoRefs = refs
    build.unresolvedEchoWeights = #unresolved > 0 and unresolved or nil
    build.echoCatalogFingerprint = currentFingerprint
    build.echoSchema = 3
    return true
end

-- Override the compatibility accessor after all legacy helpers are defined.
local LegacyGet = W.Get
function W.Get(echoName, quality)
    local build = ActiveBuild()
    if build then
        local refKey = ResolveRefByName(echoName, build.class)
        if refKey then return W.GetForRef(build, refKey, quality) end
    end
    return LegacyGet(echoName, quality)
end
