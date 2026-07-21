local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/CommunityAggregator.lua
-- Bounded, incremental aggregation of public build strategy signals.

EbonBuilds.CommunityAggregator = {}

local Aggregator = EbonBuilds.CommunityAggregator
local MAX_RECORDS = 256
local MAX_PER_AUTHOR = 2
local LOCK_LIMIT = 6
local PRIORITY_LIMIT = 24
local OPTIONAL_LIMIT = 8
local AVOID_LIMIT = 8

local function Permille(value, total)
    if total <= 0 then return 0 end
    return math.floor((value * 1000 / total) + 0.5)
end

local function Confidence(originCount)
    if originCount >= 20 then return "high" end
    if originCount >= 8 then return "medium" end
    return "low"
end

function Aggregator.Begin(classToken, spec, sourceRevision)
    return {
        class = tostring(classToken or "UNKNOWN"):upper(),
        spec = math.max(1, math.min(3, tonumber(spec) or 1)),
        cohortKey = EbonBuilds.CommunityEligibility.CohortKey(classToken, spec),
        sourceRevision = tonumber(sourceRevision) or 1,
        sources = EbonBuilds.CommunityEligibility.CollectSources(classToken, spec),
        cursor = 1,
        origins = {},
        authorCounts = {},
        candidates = {},
        originCount = 0,
        observedRecordCount = 0,
        defensiveOriginCount = 0,
        standardOriginCount = 0,
        unresolvedEntryCount = 0,
        affectedOrigins = 0,
    }
end

local function ProcessBuild(work, build)
    local record = EbonBuilds.CommunityEligibility.BuildRecord(build)
    if not record.originKey or work.origins[record.originKey] then return end
    local authorCount = work.authorCounts[record.authorKey] or 0
    if authorCount >= MAX_PER_AUTHOR or work.originCount >= MAX_RECORDS then return end

    work.origins[record.originKey] = true
    work.authorCounts[record.authorKey] = authorCount + 1
    work.originCount = work.originCount + 1
    work.observedRecordCount = work.observedRecordCount + 1
    if (record.unresolvedEntries or 0) > 0 then
        work.unresolvedEntryCount = work.unresolvedEntryCount + record.unresolvedEntries
        work.affectedOrigins = work.affectedOrigins + 1
    end
    if record.defensiveProfile then
        work.defensiveOriginCount = work.defensiveOriginCount + 1
    else
        work.standardOriginCount = work.standardOriginCount + 1
    end

    for _, signal in ipairs(record.signals or {}) do
        local candidate = work.candidates[signal.refKey]
        if not candidate then
            candidate = {
                refKey = signal.refKey, name = signal.name, present = 0, positive = 0, negative = 0,
                top = 0, locked = 0, protected = 0,
                defensivePresent = 0, defensivePositive = 0, defensiveNegative = 0,
                standardPresent = 0, standardPositive = 0, standardNegative = 0,
                lockedSpellIds = {},
            }
            work.candidates[signal.refKey] = candidate
        end
        if signal.present then
            candidate.present = candidate.present + 1
            if record.defensiveProfile then candidate.defensivePresent = candidate.defensivePresent + 1
            else candidate.standardPresent = candidate.standardPresent + 1 end
        end
        if signal.positive then
            candidate.positive = candidate.positive + 1
            if record.defensiveProfile then candidate.defensivePositive = candidate.defensivePositive + 1
            else candidate.standardPositive = candidate.standardPositive + 1 end
        end
        if signal.negative then
            candidate.negative = candidate.negative + 1
            if record.defensiveProfile then candidate.defensiveNegative = candidate.defensiveNegative + 1
            else candidate.standardNegative = candidate.standardNegative + 1 end
        end
        if signal.topGroup then candidate.top = candidate.top + 1 end
        if signal.locked then candidate.locked = candidate.locked + 1 end
        if signal.locked and signal.lockedSpellId then
            candidate.lockedSpellIds[signal.lockedSpellId] = (candidate.lockedSpellIds[signal.lockedSpellId] or 0) + 1
        end
        if signal.protected then candidate.protected = candidate.protected + 1 end
    end
end

function Aggregator.Step(work, maxRecords)
    maxRecords = math.max(1, tonumber(maxRecords) or 2)
    local processed = 0
    while work.cursor <= #work.sources and processed < maxRecords and work.originCount < MAX_RECORDS do
        local build = work.sources[work.cursor]
        work.cursor = work.cursor + 1
        processed = processed + 1
        ProcessBuild(work, build)
    end
    return work.cursor > #work.sources or work.originCount >= MAX_RECORDS
end

local function InsertTop(list, item, score, limit)
    local stored = {}
    for key, value in pairs(item) do stored[key] = value end
    stored.score = score
    local inserted = false
    for index = 1, #list do
        if score > list[index].score or (score == list[index].score and stored.name < list[index].name) then
            table.insert(list, index, stored)
            inserted = true
            break
        end
    end
    if not inserted then list[#list + 1] = stored end
    if #list > limit then table.remove(list) end
end

local function ResultItem(candidate, work)
    local total = work.originCount
    local modalSpellId, modalCount
    for spellId, count in pairs(candidate.lockedSpellIds or {}) do
        if not modalCount or count > modalCount or (count == modalCount and spellId < modalSpellId) then
            modalSpellId, modalCount = spellId, count
        end
    end
    return {
        refKey = candidate.refKey,
        name = candidate.name,
        positivePermille = Permille(candidate.positive, total),
        negativePermille = Permille(candidate.negative, total),
        inclusionPermille = Permille(candidate.present, total),
        lockPermille = Permille(candidate.locked, total),
        protectedPermille = Permille(candidate.protected, total),
        presentOrigins = candidate.present,
        positiveOrigins = candidate.positive,
        negativeOrigins = candidate.negative,
        topOrigins = candidate.top,
        lockOrigins = candidate.locked,
        protectedOrigins = candidate.protected,
        observedOrigins = total,
        confidence = Confidence(total),
        defensivePresentOrigins = candidate.defensivePresent,
        defensivePositiveOrigins = candidate.defensivePositive,
        defensiveNegativeOrigins = candidate.defensiveNegative,
        defensiveOrigins = work.defensiveOriginCount,
        standardPresentOrigins = candidate.standardPresent,
        standardPositiveOrigins = candidate.standardPositive,
        standardNegativeOrigins = candidate.standardNegative,
        standardOrigins = work.standardOriginCount,
        lockedSpellId = modalSpellId,
    }
end

function Aggregator.Finalize(work)
    local locked, priorities, optional, avoid = {}, {}, {}, {}
    if work.originCount >= 3 then
        for _, candidate in pairs(work.candidates) do
            local positive = Permille(candidate.positive, work.originCount)
            local negative = Permille(candidate.negative, work.originCount)
            local item = ResultItem(candidate, work)
            local defensiveRate = Permille(candidate.defensivePositive, work.defensiveOriginCount)
            local standardRate = Permille(candidate.standardPositive, work.standardOriginCount)
            local association = defensiveRate - standardRate
            item.defensiveRatePermille = defensiveRate
            item.standardRatePermille = standardRate
            item.survivabilityAssociationPermille = association

            local statisticallyDefensive = work.defensiveOriginCount >= 2
                and work.standardOriginCount >= 2
                and candidate.defensivePositive >= 2
                and defensiveRate >= 400
                and association >= 250
                and positive < 750

            -- Positive and lock recommendations reject materially negative
            -- candidates. Avoid eligibility is intentionally independent so a
            -- strong negative signal cannot disappear before classification.
            local positiveEligible = negative < 250
            if positiveEligible then
                local minimumLockOrigins = math.max(1, math.ceil(work.originCount * 0.10))
                if candidate.locked >= minimumLockOrigins and item.lockPermille >= 100 then
                    local lockScore = 6 * candidate.locked + 2 * candidate.positive + candidate.top - 2 * candidate.negative
                    item.statisticallyDefensive = statisticallyDefensive
                    item.recommendationClass = "lock"
                    InsertTop(locked, item, lockScore, LOCK_LIMIT)
                end

                local minimumPositiveOrigins = math.max(1, math.ceil(work.originCount * 0.10))
                if statisticallyDefensive then
                    local optionalScore = 4 * candidate.defensivePositive + 2 * candidate.top
                        + candidate.locked + candidate.protected - 3 * candidate.negative
                    item.statisticallyDefensive = true
                    item.recommendationClass = "defensive"
                    InsertTop(optional, item, optionalScore, OPTIONAL_LIMIT + LOCK_LIMIT)
                elseif candidate.positive >= minimumPositiveOrigins and positive >= 100 then
                    local priorityScore = 3 * candidate.top + 2 * candidate.positive
                        + candidate.locked + candidate.protected - 3 * candidate.negative
                    item.recommendationClass = "recommended"
                    InsertTop(priorities, item, priorityScore, PRIORITY_LIMIT + LOCK_LIMIT)
                end
            end

            local minimumNegativeOrigins = math.max(2, math.ceil(work.originCount * 0.10))
            if candidate.negative >= minimumNegativeOrigins and negative >= 100
                and candidate.negative > candidate.positive then
                local avoidScore = 4 * candidate.negative - candidate.positive - candidate.locked
                item.recommendationClass = "avoid"
                InsertTop(avoid, item, avoidScore, AVOID_LIMIT + LOCK_LIMIT)
            end
        end
    end
    local lockedRefs = {}
    for _, item in ipairs(locked) do lockedRefs[item.refKey] = true end
    for index = #priorities, 1, -1 do if lockedRefs[priorities[index].refKey] then table.remove(priorities, index) end end
    for index = #optional, 1, -1 do if lockedRefs[optional[index].refKey] then table.remove(optional, index) end end
    local selectedRefs = {}
    for _, item in ipairs(locked) do selectedRefs[item.refKey] = true end
    for _, item in ipairs(priorities) do selectedRefs[item.refKey] = true end
    for _, item in ipairs(optional) do selectedRefs[item.refKey] = true end
    for index = #avoid, 1, -1 do if selectedRefs[avoid[index].refKey] then table.remove(avoid, index) end end
    while #priorities > PRIORITY_LIMIT do table.remove(priorities) end
    while #optional > OPTIONAL_LIMIT do table.remove(optional) end
    while #avoid > AVOID_LIMIT do table.remove(avoid) end
    for index, item in ipairs(priorities) do
        item.tier = index <= 6 and "CORE" or "SUPPORTING"
        item.recommendedByDefault = index <= 18
    end
    for _, item in ipairs(locked) do item.recommendedByDefault = true end

    local reasonCode
    if work.originCount == 0 then reasonCode = "NO_MATCHING_BUILDS"
    elseif work.originCount < 3 then reasonCode = "NOT_ENOUGH_ORIGINS"
    elseif #priorities == 0 and #locked == 0 then reasonCode = "NO_STABLE_CORE"
    else reasonCode = "COMMUNITY_READY" end

    local confidenceLevel = "insufficient"
    if work.originCount >= 20 then confidenceLevel = "strong"
    elseif work.originCount >= 8 then confidenceLevel = "moderate"
    elseif work.originCount >= 3 then confidenceLevel = "limited" end

    return {
        schema = 6,
        cohortKey = work.cohortKey,
        class = work.class,
        spec = work.spec,
        sourceRevision = work.sourceRevision,
        originCount = work.originCount,
        observedRecordCount = work.observedRecordCount,
        confidence = Confidence(work.originCount),
        confidenceLevel = confidenceLevel,
        reasonCode = reasonCode,
        locked = locked,
        priorities = priorities,
        core = priorities,
        optionalSurvivability = optional,
        defensiveAssociated = optional,
        avoid = avoid,
        defensiveOriginCount = work.defensiveOriginCount,
        standardOriginCount = work.standardOriginCount,
        classificationMethod = "community_association_ref_v1",
        identityDiagnostics = {
            unresolvedEntries = work.unresolvedEntryCount or 0,
            affectedOrigins = work.affectedOrigins or 0,
        },
    }
end

function Aggregator.Aggregate(classToken, spec, sourceRevision)
    local work = Aggregator.Begin(classToken, spec, sourceRevision)
    while not Aggregator.Step(work, 2) do end
    return Aggregator.Finalize(work)
end
