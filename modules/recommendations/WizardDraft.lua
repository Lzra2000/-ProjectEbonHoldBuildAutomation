-- EbonBuilds: modules/recommendations/WizardDraft.lua
-- Runtime-only, revisioned Build Wizard state keyed by versioned Echo refs.

EbonBuilds.WizardDraft = {}

local Draft = EbonBuilds.WizardDraft

Draft.SCHEMA = 4
Draft.IMPORTANCE = { "Essential", "Strong", "Useful", "Neutral", "Avoid" }
Draft.STYLES = { "Recommendation-focused", "Balanced", "Quality-focused" }
Draft.DEFAULT_INCLUDED_IMPORTANCE = "Useful"
Draft.PRIMARY_FAMILY_BONUS = 20
Draft.SECONDARY_FAMILY_BONUS = 10

local STYLE_WEIGHTS = {
    -- Avoid is policy-only. It applies Never Pick but never contributes a
    -- negative scoring weight, regardless of the Use toggle. Every Wizard
    -- scoring value stays on a 10-point grid so generated weights and scores
    -- are always divisible by 10.
    ["Recommendation-focused"] = { Essential = 80, Strong = 50, Useful = 20, Neutral = 0, Avoid = 0 },
    ["Balanced"]               = { Essential = 60, Strong = 40, Useful = 20, Neutral = 0, Avoid = 0 },
    ["Quality-focused"]        = { Essential = 40, Strong = 30, Useful = 20, Neutral = 0, Avoid = 0 },
}
local STYLE_QUALITY = {
    -- Recommendation-focused keeps quality as a small tie-breaker, Balanced
    -- gives each rank a meaningful step, and Quality-focused lets rarity
    -- dominate. All bonuses remain divisible by 10.
    ["Recommendation-focused"] = { [3] = 10, [2] = 0,  [1] = 0,  [0] = 0 },
    ["Balanced"]               = { [3] = 30, [2] = 20, [1] = 10, [0] = 0 },
    ["Quality-focused"]        = { [3] = 60, [2] = 40, [1] = 20, [0] = 0 },
}

local function DerivedPolicyForImportance(importance)
    local api = EbonBuilds.EchoPolicy
    if importance == "Avoid" then return api and api.NEVER_PICK or "never_pick" end
    return api and api.NORMAL or "normal"
end

local function SyncDerivedPolicy(echo)
    if not echo then return end
    echo.derivedPolicy = DerivedPolicyForImportance(echo.importance)
end

local function Invalidate(draft)
    draft.calibration.status = "stale"
    draft._summaryCache = nil
end

local function Bump(draft)
    if draft._batchDepth and draft._batchDepth > 0 then
        draft._batchDirty = true
        Invalidate(draft)
        return
    end
    draft.revision = (tonumber(draft.revision) or 0) + 1
    Invalidate(draft)
end

function Draft.BeginBatch(draft)
    draft._batchDepth = (tonumber(draft._batchDepth) or 0) + 1
end

function Draft.EndBatch(draft)
    draft._batchDepth = math.max(0, (tonumber(draft._batchDepth) or 1) - 1)
    if draft._batchDepth == 0 and draft._batchDirty then
        draft._batchDirty = nil
        draft.revision = (tonumber(draft.revision) or 0) + 1
        Invalidate(draft)
    end
end

local function ProjectionEntry(classToken, refKey)
    return EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.GetEntry(classToken, refKey) or nil
end

local function ResolveItem(classToken, item)
    if not item then return nil end
    local preferredId = tonumber(item.lockedSpellId or item.spellId)
    if preferredId then
        local entry, variant = EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.ResolveSpell(classToken, preferredId)
        if entry and variant then return entry, variant end
    end
    local name = item.name or item.sourceName or item.comment
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindLegacyRefs(name) or {}
    if #refs ~= 1 then return nil end
    local spellId, _, definition, variant = EbonBuilds.EchoProjection.GetBestVariant(classToken, refs[1], preferredId)
    if not spellId or not definition or not variant then return nil end
    local entry = ProjectionEntry(classToken, definition.refKey)
    return entry, variant
end

local function ResolveKey(draft, value)
    value = tostring(value or "")
    if draft.echoes[value] then return value end
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindLegacyRefs(value) or {}
    local found
    for _, refKey in ipairs(refs) do
        if draft.echoes[refKey] then
            if found then return nil end
            found = refKey
        end
    end
    return found
end

local function EnsureEcho(draft, entry)
    if not entry or not entry.refKey then return nil end
    local refKey = entry.refKey
    local echo = draft.echoes[refKey]
    if not echo then
        draft.echoOrder[#draft.echoOrder + 1] = refKey
        echo = {
            refKey = refKey,
            name = entry.displayName or entry.sourceName or entry.name,
            sourceName = entry.sourceName or entry.name,
            spellId = entry.representativeSpellId or entry.spellId,
            groupId = entry.groupId,
            semantics = entry.semantics,
            availability = entry.availability,
            disambiguator = entry.disambiguator,
            included = false,
            importance = "Neutral",
            suggestedIncluded = false,
            suggestedImportance = "Neutral",
            ownership = "catalog",
            touchedInclusion = false,
            touchedImportance = false,
            autoImportanceFromUse = false,
            derivedPolicy = DerivedPolicyForImportance("Neutral"),
            sourceKind = "catalog",
        }
        draft.echoes[refKey] = echo
    end
    return echo
end

local function AddEcho(draft, item, importance, included, sourceKind, index)
    local entry, variant = ResolveItem(draft.class, item)
    if not entry then
        local unresolved = draft.unresolvedRecommendations
        if type(unresolved) ~= "table" then
            unresolved = {}
            draft.unresolvedRecommendations = unresolved
        end
        unresolved[#unresolved + 1] = {
            source = sourceKind or "catalog",
            sourceIndex = tonumber(index),
            rawSpellId = tonumber(item and (item.lockedSpellId or item.spellId)),
            rawName = item and (item.name or item.sourceName or item.comment) or nil,
            reason = "NO_CANONICAL_REFERENCE",
        }
        return nil
    end
    local echo = EnsureEcho(draft, entry)
    echo.spellId = variant and variant.spellId or echo.spellId
    echo.semantics = variant and variant.semantics or echo.semantics
    echo.included = included and true or false
    echo.importance = importance or "Neutral"
    echo.suggestedIncluded = echo.included
    echo.suggestedImportance = echo.importance
    echo.ownership = "suggested"
    echo.touchedInclusion = false
    echo.touchedImportance = false
    echo.autoImportanceFromUse = false
    SyncDerivedPolicy(echo)
    echo.sourceKind = sourceKind or "catalog"
    echo.sourceIndex = index
    return echo
end

local function AddCatalogEchoes(draft)
    local projection = EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.Get(draft.class)
    if not projection then return end
    for _, entry in ipairs(projection.available or {}) do EnsureEcho(draft, entry) end
    -- Keep unknown/conflicted records in a separate, explicitly labelled
    -- diagnostic view. They never enter Suggested or All <Class> Echoes, but
    -- they also never disappear without explanation when class data is incomplete.
    for _, entry in ipairs(projection.unverified or {}) do EnsureEcho(draft, entry) end
    draft.catalogCount = projection.availableCount or #(projection.available or {})
    draft.unverifiedCount = projection.unverifiedCount or #(projection.unverified or {})
    draft.conflictedCount = projection.conflictedCount or #(projection.conflicted or {})
    draft.unavailableCount = projection.unavailableCount or #(projection.unavailable or {})
    draft.fullCatalogCount = projection.fullCount or ((draft.catalogCount or 0) + (draft.unverifiedCount or 0) + (draft.unavailableCount or 0))
    draft.catalogRevision = projection.catalogRevision
    draft.catalogFingerprint = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint() or nil
end

function Draft.New(snapshot, classToken, spec, intentKey)
    snapshot = snapshot or {}
    local draft = {
        schema = Draft.SCHEMA,
        class = tostring(classToken or snapshot.class or "UNKNOWN"):upper(),
        spec = math.max(1, math.min(3, tonumber(spec or snapshot.spec) or 1)),
        cohortKey = snapshot.cohortKey,
        sourceRevision = snapshot.sourceRevision,
        originCount = tonumber(snapshot.originCount) or 0,
        confidence = snapshot.confidenceLevel or snapshot.confidence or "insufficient",
        snapshot = snapshot,
        step = 1,
        revision = 1,
        intentKey = intentKey or "community",
        locks = {}, lockTouched = {}, echoes = {}, echoOrder = {},
        scoringStyle = "Recommendation-focused",
        primaryFamily = "None", secondaryFamily = "None",
        touchedScoringStyle = false, touchedPrimaryFamily = false, touchedSecondaryFamily = false,
        calibration = { requestedRevision = 0, completedRevision = 0, catalogRevision = 0, status = "stale", diagnostics = {}, preview = {} },
        unresolvedRecommendations = {},
    }

    AddCatalogEchoes(draft)

    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local item = snapshot.locked and snapshot.locked[slot]
        local entry, variant = ResolveItem(draft.class, item)
        if entry and variant then
            draft.locks[slot] = {
                refKey = entry.refKey, name = entry.displayName,
                spellId = variant.spellId, ownership = "suggested",
                touched = false, recommendationIndex = slot,
            }
        end
    end

    for index, item in ipairs(snapshot.priorities or snapshot.core or {}) do
        AddEcho(draft, item, index <= 6 and "Strong" or (index <= 18 and "Useful" or "Neutral"), index <= 18, "priority", index)
    end
    for index, item in ipairs(snapshot.defensiveAssociated or snapshot.optionalSurvivability or {}) do
        local entry = ResolveItem(draft.class, item)
        if entry and draft.echoes[entry.refKey] and draft.echoes[entry.refKey].sourceKind == "catalog" then
            AddEcho(draft, item, "Useful", false, "defensive", index)
        end
    end
    for index, item in ipairs(snapshot.avoid or {}) do
        local entry = ResolveItem(draft.class, item)
        if entry and draft.echoes[entry.refKey] and draft.echoes[entry.refKey].sourceKind == "catalog" then
            AddEcho(draft, item, "Avoid", false, "avoid", index)
        end
    end

    if EbonBuilds.WizardPresets then EbonBuilds.WizardPresets.Apply(draft, draft.intentKey, false) end
    return draft
end

function Draft.Get(draft) return draft end
function Draft.Revision(draft) return tonumber(draft and draft.revision) or 0 end
function Draft.ResolveKey(draft, value) return ResolveKey(draft, value) end

function Draft.SetIntent(draft, intentKey, preserveTouched)
    if not draft or not EbonBuilds.WizardPresets then return false end
    Draft.BeginBatch(draft)
    local changed = EbonBuilds.WizardPresets.Apply(draft, intentKey, preserveTouched ~= false)
    if changed then Bump(draft) end
    Draft.EndBatch(draft)
    return changed
end

function Draft.SetLock(draft, slot, spellId, name, ownership)
    slot, spellId = tonumber(slot), tonumber(spellId)
    if not slot or slot < 1 or slot > EbonBuilds.Build.LOCKED_SLOTS or not spellId then return false end
    local entry, variant = EbonBuilds.EchoProjection.ResolveSpell(draft.class, spellId)
    if not entry or not variant then return false end
    for index = 1, EbonBuilds.Build.LOCKED_SLOTS do
        if index ~= slot and draft.locks[index] and draft.locks[index].refKey == entry.refKey then
            draft.locks[index], draft.lockTouched[index] = nil, true
        end
    end
    draft.locks[slot] = {
        refKey = entry.refKey, name = entry.displayName, spellId = spellId,
        ownership = ownership or "manual", touched = true,
    }
    draft.lockTouched[slot] = true
    Bump(draft)
    return true
end

function Draft.RemoveLock(draft, slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > EbonBuilds.Build.LOCKED_SLOTS then return false end
    if not draft.locks[slot] and draft.lockTouched[slot] then return false end
    draft.locks[slot], draft.lockTouched[slot] = nil, true
    Bump(draft)
    return true
end

function Draft.MoveLock(draft, fromSlot, toSlot)
    fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
    if not fromSlot or not toSlot or fromSlot < 1 or toSlot < 1 or fromSlot > EbonBuilds.Build.LOCKED_SLOTS or toSlot > EbonBuilds.Build.LOCKED_SLOTS or fromSlot == toSlot then return false end
    draft.locks[fromSlot], draft.locks[toSlot] = draft.locks[toSlot], draft.locks[fromSlot]
    draft.lockTouched[fromSlot], draft.lockTouched[toSlot] = true, true
    if draft.locks[fromSlot] then draft.locks[fromSlot].touched, draft.locks[fromSlot].ownership = true, "manual" end
    if draft.locks[toSlot] then draft.locks[toSlot].touched, draft.locks[toSlot].ownership = true, "manual" end
    Bump(draft)
    return true
end

function Draft.AcceptLock(draft, slot)
    local lock = draft.locks[tonumber(slot)]
    if not lock then return false end
    lock.ownership, lock.touched, draft.lockTouched[slot] = "accepted", true, true
    Bump(draft)
    return true
end

function Draft.ApplyRecommendedLocks(draft, snapshot, fillTouchedEmpty)
    local changed = false
    Draft.BeginBatch(draft)
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local current = draft.locks[slot]
        local item = snapshot and snapshot.locked and snapshot.locked[slot]
        local mayFill = not current and (not draft.lockTouched[slot] or fillTouchedEmpty)
        local mayRefresh = current and current.ownership == "suggested" and not current.touched
        if mayFill or mayRefresh then
            local entry, variant = ResolveItem(draft.class, item)
            draft.locks[slot] = entry and variant and {
                refKey = entry.refKey, name = entry.displayName, spellId = variant.spellId,
                ownership = "suggested", touched = false, recommendationIndex = slot,
            } or nil
            changed = true
        end
    end
    if changed then Bump(draft) end
    Draft.EndBatch(draft)
    return changed
end

function Draft.AddEcho(draft, value, importance, included, ownership)
    local refKey = ResolveKey(draft, value)
    if not refKey then return false end
    local echo = draft.echoes[refKey]
    echo.importance = importance or "Useful"
    echo.included = included ~= false
    echo.ownership = ownership or "manual"
    echo.touchedInclusion, echo.touchedImportance = true, true
    echo.autoImportanceFromUse = false
    SyncDerivedPolicy(echo)
    Bump(draft)
    return true
end

function Draft.SetIncluded(draft, value, included)
    local refKey = ResolveKey(draft, value)
    local echo = refKey and draft.echoes[refKey]
    if not echo then return false end

    included = included and true or false
    local changed = echo.included ~= included or not echo.touchedInclusion

    -- Yes activates a zero-weight non-Avoid Echo with the lowest useful weight.
    -- No is an explicit reset: it always clears priority to Neutral +0,
    -- regardless of whether the previous positive priority was automatic or manual.
    if included then
        if echo.importance ~= "Avoid" and Draft.WeightFor(draft, echo.importance) == 0 then
            echo.importance = Draft.DEFAULT_INCLUDED_IMPORTANCE
            echo.touchedImportance = true
            echo.autoImportanceFromUse = true
            changed = true
        end
    else
        if echo.importance ~= "Neutral" or not echo.touchedImportance then
            echo.importance = "Neutral"
            echo.touchedImportance = true
            changed = true
        end
        echo.autoImportanceFromUse = false
    end

    if not changed then return false end
    echo.included = included
    echo.touchedInclusion = true
    echo.ownership = "manual"
    SyncDerivedPolicy(echo)
    Bump(draft)
    return true
end

function Draft.SetImportance(draft, value, importance)
    local refKey = ResolveKey(draft, value)
    local echo = refKey and draft.echoes[refKey]
    if not echo or STYLE_WEIGHTS.Balanced[importance] == nil then return false end
    local changed = echo.importance ~= importance or not echo.touchedImportance
    echo.importance, echo.touchedImportance, echo.ownership = importance, true, "manual"
    echo.autoImportanceFromUse = false
    SyncDerivedPolicy(echo)
    -- Avoid changes policy only and preserves the current inclusion choice.
    if importance ~= "Avoid" and not echo.included then
        echo.included, echo.touchedInclusion, changed = true, true, true
    end
    if changed then Bump(draft) end
    return changed
end

-- Smart priority setter used by the grouped Build Wizard selector.
-- Positive priorities activate the Echo. Neutral removes it from active output.
-- Avoid is policy-only: it preserves Use and always resolves to weight 0.
function Draft.SetImportanceOnly(draft, value, importance)
    local refKey = ResolveKey(draft, value)
    local echo = refKey and draft.echoes[refKey]
    if not echo or STYLE_WEIGHTS.Balanced[importance] == nil then return false end

    local changed = echo.importance ~= importance or not echo.touchedImportance
    echo.importance = importance
    echo.touchedImportance = true
    echo.ownership = "manual"
    echo.autoImportanceFromUse = false
    SyncDerivedPolicy(echo)

    if importance == "Neutral" then
        if echo.included then
            echo.included = false
            echo.touchedInclusion = true
            changed = true
        end
    elseif importance == "Avoid" then
        -- Policy-only state: do not alter the user's Use choice.
    elseif not echo.included then
        echo.included = true
        echo.touchedInclusion = true
        changed = true
    end

    if changed then Bump(draft) end
    return changed
end

function Draft.UnresolvedCount(draft)
    local unresolved = draft and draft.unresolvedRecommendations
    if type(unresolved) == "table" then return #unresolved end
    return math.max(0, tonumber(unresolved) or 0)
end

function Draft.ResetEcho(draft, value)
    local refKey = ResolveKey(draft, value)
    local echo = refKey and draft.echoes[refKey]
    if not echo then return false end
    echo.included = echo.suggestedIncluded == true
    echo.importance = echo.suggestedImportance or "Neutral"
    echo.touchedInclusion, echo.touchedImportance = false, false
    echo.autoImportanceFromUse = false
    SyncDerivedPolicy(echo)
    echo.ownership = echo.sourceKind == "catalog" and "catalog" or "suggested"
    Bump(draft)
    return true
end

function Draft.SetScoringStyle(draft, style)
    if not STYLE_WEIGHTS[style] then return false end
    if draft.scoringStyle == style and draft.touchedScoringStyle then return false end
    draft.scoringStyle, draft.touchedScoringStyle = style, true
    Bump(draft); return true
end
function Draft.SetPrimaryFamily(draft, family)
    family = family or "None"
    if draft.primaryFamily == family and draft.touchedPrimaryFamily then return false end
    draft.primaryFamily, draft.touchedPrimaryFamily = family, true
    Bump(draft); return true
end
function Draft.SetSecondaryFamily(draft, family)
    family = family or "None"
    if draft.secondaryFamily == family and draft.touchedSecondaryFamily then return false end
    draft.secondaryFamily, draft.touchedSecondaryFamily = family, true
    Bump(draft); return true
end
function Draft.ResolvePrimaryFamily(draft)
    if draft.primaryFamily == "None" or not draft.primaryFamily then return nil end
    if draft.primaryFamily ~= "Auto" then return draft.primaryFamily end
    return EbonBuilds.WizardPresets and EbonBuilds.WizardPresets.ResolvePrimaryFamily(draft.class, draft.spec) or nil
end

function Draft.IsEntryAvailable(classToken, value)
    if type(value) == "table" then
        if value.spellId then return EbonBuilds.EchoProjection.ResolveSpell(classToken, value.spellId) ~= nil end
        if value.refKey then return EbonBuilds.EchoProjection.GetEntry(classToken, value.refKey) ~= nil end
    end
    local spellId = tonumber(value)
    return spellId and EbonBuilds.EchoProjection.ResolveSpell(classToken, spellId) ~= nil or false
end
function Draft.FilterEntriesForClass(entries, classToken)
    local filtered = {}
    for _, entry in ipairs(entries or {}) do
        if Draft.IsEntryAvailable(classToken, entry) then filtered[#filtered + 1] = entry end
    end
    return filtered
end


function Draft.Settings(draft)
    local settings = (EbonBuilds.Build.NewBuildSettings and EbonBuilds.Build.NewBuildSettings()) or EbonBuilds.Build.DefaultSettings()
    local quality = STYLE_QUALITY[draft.scoringStyle] or STYLE_QUALITY["Recommendation-focused"]
    for rank = 0, 3 do settings.qualityBonus[rank] = quality[rank] or 0 end
    local primary = Draft.ResolvePrimaryFamily(draft)
    if primary and primary ~= "None" then settings.familyBonus[primary] = Draft.PRIMARY_FAMILY_BONUS end
    local secondary = draft.secondaryFamily
    if secondary and secondary ~= "None" and secondary ~= primary then settings.familyBonus[secondary] = Draft.SECONDARY_FAMILY_BONUS end

    -- Avoid is a policy-only priority. Every Echo currently flagged Avoid
    -- receives Never Pick in the generated build settings, while its scoring
    -- weight remains exactly 0. Changing away from Avoid removes the generated
    -- policy because Settings() is rebuilt from the current draft.
    local policyApi = EbonBuilds.EchoPolicy
    if policyApi and policyApi.Set then
        for _, refKey in ipairs(draft.echoOrder or {}) do
            local echo = draft.echoes and draft.echoes[refKey]
            if echo then
                SyncDerivedPolicy(echo)
                if echo.importance == "Avoid" or echo.derivedPolicy == policyApi.NEVER_PICK then
                    if policyApi.EnsureNeverPick then policyApi.EnsureNeverPick(settings, refKey)
                    else policyApi.Set(settings, refKey, policyApi.NEVER_PICK) end
                end
            end
        end
    end

    return settings
end
function Draft.WeightFor(draft, importance)
    return (STYLE_WEIGHTS[draft.scoringStyle] or STYLE_WEIGHTS["Recommendation-focused"])[importance] or 0
end

function Draft.FormatWeight(weight)
    weight = tonumber(weight) or 0
    if weight > 0 then return "+" .. tostring(weight) end
    return tostring(weight)
end

function Draft.ImportanceWeightText(draft, importance)
    return Draft.FormatWeight(Draft.WeightFor(draft, importance))
end

function Draft.PolicyForImportance(importance)
    local policyApi = EbonBuilds.EchoPolicy
    if importance == "Avoid" and policyApi then return policyApi.NEVER_PICK end
    return policyApi and policyApi.NORMAL or "normal"
end
function Draft.StyleProfile(style)
    style = STYLE_WEIGHTS[style] and style or "Recommendation-focused"
    return { weights = STYLE_WEIGHTS[style], quality = STYLE_QUALITY[style] }
end

function Draft.MarkCalibrationRequested(draft)
    draft.calibration.requestedRevision, draft.calibration.status = draft.revision, "running"
    return draft.revision
end
function Draft.ApplyCalibration(draft, revision, preview, diagnostics)
    if tonumber(revision) ~= tonumber(draft.revision) then return false end
    draft.calibration.completedRevision, draft.calibration.preview = revision, preview or {}
    draft.calibration.diagnostics, draft.calibration.status = diagnostics or {}, "ready"
    return true
end
function Draft.Calibrate(draft)
    local catalogRevision = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRevision() or 0
    if draft.calibration.status == "ready" and tonumber(draft.calibration.completedRevision) == tonumber(draft.revision)
        and tonumber(draft.calibration.catalogRevision) == tonumber(catalogRevision) then
        return #(draft.calibration.diagnostics or {}) == 0, draft.calibration.diagnostics or {}
    end
    local revision = Draft.MarkCalibrationRequested(draft)
    local preview, diagnostics, settings, checked = {}, {}, Draft.Settings(draft), 0
    for _, refKey in ipairs(draft.echoOrder) do
        local echo = draft.echoes[refKey]
        if echo and echo.included and checked < 64 then
            local entry = EbonBuilds.EchoCatalog.GetByRef(refKey) or { name = echo.name, families = {} }
            local weight, scores = Draft.WeightFor(draft, echo.importance), {}
            for quality = 0, 3 do scores[quality] = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality) end
            preview[refKey] = scores; checked = checked + 1
            -- Avoid is enforced by Never Pick policy, not by a negative score.
        end
    end
    diagnostics.checkedEchoes = checked
    Draft.ApplyCalibration(draft, revision, preview, diagnostics)
    draft.calibration.catalogRevision = catalogRevision
    return #diagnostics == 0, diagnostics
end

local function DeviationCounts(draft)
    local manualLocks, changedPriorities, excludedRecommendations, promotedAvoids = 0, 0, 0, 0
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local lock = draft.locks[slot]
        if lock and lock.ownership == "manual" then manualLocks = manualLocks + 1 end
    end
    for _, refKey in ipairs(draft.echoOrder) do
        local echo = draft.echoes[refKey]
        if echo then
            if echo.included ~= echo.suggestedIncluded or echo.importance ~= echo.suggestedImportance then changedPriorities = changedPriorities + 1 end
            if echo.sourceKind == "priority" and echo.suggestedIncluded and not echo.included then excludedRecommendations = excludedRecommendations + 1 end
            if echo.sourceKind == "avoid" and echo.included and echo.importance ~= "Avoid" then promotedAvoids = promotedAvoids + 1 end
        end
    end
    return manualLocks, changedPriorities, excludedRecommendations, promotedAvoids
end

function Draft.CreateBuildData(draft, title)
    local legacyWeights, refWeights, refs, locked = {}, {}, {}, {}
    local avoidPolicyRefs = {}
    local legacyNameOwner = {}
    local function AddRef(refKey, weight)
        local definition = EbonBuilds.EchoCatalog.GetByRef(refKey)
        if not definition then return end
        refWeights[refKey] = EbonBuilds.Weights.MakeUniform(weight)
        refs[refKey] = { definition.spellId, definition.sourceName, definition.descriptionHash or 0 }
        if not legacyNameOwner[definition.sourceName] then
            legacyNameOwner[definition.sourceName] = refKey
            legacyWeights[definition.sourceName] = EbonBuilds.Weights.MakeUniform(weight)
        elseif legacyNameOwner[definition.sourceName] == refKey then
            legacyWeights[definition.sourceName] = EbonBuilds.Weights.MakeUniform(weight)
        else
            legacyWeights[definition.sourceName] = nil -- duplicate display names cannot be represented safely in schema 1
        end
    end
    for _, refKey in ipairs(draft.echoOrder) do
        local echo = draft.echoes[refKey]
        if echo and echo.included then AddRef(refKey, Draft.WeightFor(draft, echo.importance)) end
        if echo and echo.importance == "Avoid" then
            avoidPolicyRefs[#avoidPolicyRefs + 1] = refKey
            if not refs[refKey] then
                local definition = EbonBuilds.EchoCatalog.GetByRef(refKey)
                if definition then
                    refs[refKey] = { definition.spellId, definition.sourceName, definition.descriptionHash or 0 }
                end
            end
        end
    end
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local lock = draft.locks[slot]
        if lock and lock.spellId and lock.refKey then
            locked[slot] = lock.spellId
            if not refWeights[lock.refKey] then AddRef(lock.refKey, Draft.WeightFor(draft, "Essential")) end
        end
    end

    local specData = EbonBuilds.SpecData and EbonBuilds.SpecData[draft.class]
    local specName = specData and specData[draft.spec] and specData[draft.spec].name or "Build"
    local manualLocks, changedPriorities, excludedRecommendations, promotedAvoids = DeviationCounts(draft)
    local settings = Draft.Settings(draft)
    local policyApi = EbonBuilds.EchoPolicy
    if policyApi and policyApi.Set then
        for _, refKey in ipairs(avoidPolicyRefs) do
            if policyApi.EnsureNeverPick then policyApi.EnsureNeverPick(settings, refKey)
            else policyApi.Set(settings, refKey, policyApi.NEVER_PICK) end
        end
    end
    return {
        title = title and title ~= "" and title or (specName .. " Community Build"),
        class = draft.class, spec = draft.spec,
        comments = "Community-informed starting point. Community usage is guidance, not proven performance.",
        lockedEchoes = locked,
        echoWeights = legacyWeights,
        echoWeightsByRef = refWeights,
        echoRefs = refs,
        echoSchema = 3,
        echoCatalogFingerprint = draft.catalogFingerprint or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint()),
        settings = settings, isPublic = false, startPaused = true,
        wizardMeta = {
            schemaVersion = 2, cohortKey = draft.cohortKey, sourceRevision = draft.sourceRevision,
            originCount = draft.originCount or 0, confidence = draft.confidence or "insufficient",
            intent = draft.intentKey or "community", scoringStyle = draft.scoringStyle,
            manualLocks = manualLocks, changedPriorities = changedPriorities,
            excludedRecommendations = excludedRecommendations, promotedAvoids = promotedAvoids,
            catalogFingerprint = draft.catalogFingerprint, catalogRevision = draft.catalogRevision,
            classCatalogCount = draft.catalogCount or 0, unverifiedCount = draft.unverifiedCount or 0,
            unavailableCount = draft.unavailableCount or 0,
            unresolvedRecommendations = Draft.UnresolvedCount(draft),
            unresolvedRecommendationDetails = draft.unresolvedRecommendations,
            avoidPolicyRefs = avoidPolicyRefs,
        },
    }
end

Draft._STYLE_WEIGHTS = STYLE_WEIGHTS
Draft._STYLE_QUALITY = STYLE_QUALITY
Draft.MAX_ECHOES = nil
