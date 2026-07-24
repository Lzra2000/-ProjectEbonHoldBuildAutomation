local addonName, EbonBuilds = ...

-- EbonBuilds: modules/analytics/StatsData.lua
-- Responsibility: pure data derivation for the Stats workspace -- session
-- matching and metrics, action analytics, early-Epic stats, weighted
-- coverage, echo rows, recommendations, and the per-build stats cache.
-- No frames, no rendering: everything here takes plain tables and returns
-- plain tables, which is what lets the test suite exercise it without the
-- UI stub layer. Split out of modules/ui/StatsView.lua (issue #19).

EbonBuilds.StatsData = {}
local Data = EbonBuilds.StatsData

local QUALITY_ORDER = EbonBuilds.Quality.ORDER or { 3, 2, 1, 0 }
local ACTION_KEYS = { "Select", "Banish", "Reroll", "Freeze" }
Data.ACTION_KEYS = ACTION_KEYS

-- Weak-keyed memo tables: keyed by session table identity, so a session
-- object that gets collected releases its cached match/metrics entries.
local sessionMatchMemo = setmetatable({}, { __mode = "k" })
local sessionMetricsMemo = setmetatable({}, { __mode = "k" })
local cacheGeneration = 0

-- Most-recent applied recommendation per build (for Undo and for the
-- "recently applied" marker). Owned here, aliased by the view -- both
-- sides mutate the same table, exactly as before the split.
local recentRecommendationByBuild = {}
Data.recentRecommendationByBuild = recentRecommendationByBuild

local function Round(value, decimals)
    value = tonumber(value) or 0
    local scale = 10 ^ (decimals or 0)
    if value >= 0 then return math.floor(value * scale + 0.5) / scale end
    return math.ceil(value * scale - 0.5) / scale
end

local function NormalizeAction(action)
    action = tostring(action or "")
    if action:find("^Select") then return "Select" end
    if action:find("^Banish") then return "Banish" end
    if action:find("^Reroll") then return "Reroll" end
    if action:find("^Freeze") then return "Freeze" end
    if action:find("^Manual") then return "Manual" end
    return action ~= "" and action or "Other"
end

local function SessionMatchesBuild(session, build)
    if not session or not build then return false end
    local logs = session.logs or {}
    local memo = sessionMatchMemo[session]
    local memoKey = table.concat({
        tostring(build.id or ""),
        tostring(build.title or ""),
        tostring(session.buildId or ""),
        tostring(session.buildTitle or ""),
        tostring(#logs),
        tostring(session.analyticsRevision or 0),
    }, "|")
    if memo and memo.key == memoKey then return memo.result end

    local result = false
    if session.buildId and session.buildId == build.id then
        result = true
    elseif not session.buildId and session.buildTitle and session.buildTitle == build.title then
        result = true
    else
        for _, record in pairs(type(session.earlyEpicOffers) == "table" and session.earlyEpicOffers or {}) do
            if type(record) == "table" and record.tracked ~= false
                and ((record.buildId and record.buildId == build.id)
                    or (not record.buildId and record.buildTitle and record.buildTitle == build.title)) then
                result = true
                break
            end
        end
        if not result then
            for _, entry in ipairs(logs) do
                local decision = entry.decision or {}
                if (decision.buildId and decision.buildId == build.id)
                    or (decision.buildTitle and decision.buildTitle == build.title) then
                    result = true
                    break
                end
            end
        end
    end
    sessionMatchMemo[session] = { key = memoKey, result = result }
    return result
end

local function SessionHeaderMatchesBuild(session, build)
    if not session or not build then return false end
    if session.buildId then return session.buildId == build.id end
    if session.buildTitle then return session.buildTitle == build.title end
    return false
end

local function EntryMatchesBuild(entry, session, build)
    local decision = entry and entry.decision or {}
    if decision.buildId then return decision.buildId == build.id end
    if decision.buildTitle then return decision.buildTitle == build.title end
    return SessionHeaderMatchesBuild(session, build)
end

local function MatchingSessions(build)
    local out = {}
    for _, session in ipairs((EbonBuilds.Session and EbonBuilds.Session.GetSessions and EbonBuilds.Session.GetSessions()) or {}) do
        if SessionMatchesBuild(session, build) then out[#out + 1] = session end
    end
    table.sort(out, function(a, b) return (a.startTime or 0) > (b.startTime or 0) end)
    return out
end

local function SelectedScore(entry)
    local action = NormalizeAction(entry.action)
    if action ~= "Select" and action ~= "Manual" then return nil end
    local choice = entry.choices and entry.choices[entry.targetIndex or 0]
    return choice and tonumber(choice.score) or nil
end

local function NewSessionMetrics(session)
    return {
        events = 0,
        selectedCount = 0,
        selectedSum = 0,
        actions = { Select = 0, Banish = 0, Reroll = 0, Freeze = 0, Manual = 0 },
        signals = { closeDecision = 0, lastCharge = 0, modifierOverride = 0, fallback = 0 },
        sources = { Automatic = 0, Manual = 0 },
        maxLevel = session and (session.maxLevel or 1) or 1,
    }
end

local function AddEntryMetrics(metrics, entry, session, build)
    if build and not EntryMatchesBuild(entry, session, build) then return end
    metrics.events = metrics.events + 1
    local action = NormalizeAction(entry.action)
    metrics.actions[action] = (metrics.actions[action] or 0) + 1
    local source = entry.decision and tostring(entry.decision.source or "automatic"):lower():find("manual") and "Manual" or "Automatic"
    metrics.sources[source] = (metrics.sources[source] or 0) + 1
    local flags = entry.decision and entry.decision.flags or {}
    for key in pairs(metrics.signals) do if flags[key] then metrics.signals[key] = metrics.signals[key] + 1 end end
    local selected = SelectedScore(entry)
    if selected ~= nil then
        metrics.selectedCount = metrics.selectedCount + 1
        metrics.selectedSum = metrics.selectedSum + selected
    end
end

local function FinalizeSessionMetrics(metrics, session)
    metrics.maxLevel = session and (session.maxLevel or metrics.maxLevel or 1) or 1
    metrics.averageSelected = metrics.selectedCount > 0 and metrics.selectedSum / metrics.selectedCount or 0
    metrics.resourceTotal = (metrics.actions.Banish or 0) + (metrics.actions.Reroll or 0) + (metrics.actions.Freeze or 0)
    metrics.levels = math.max(1, metrics.maxLevel - 1)
    metrics.resourcePerLevel = metrics.resourceTotal / metrics.levels
    return metrics
end

local function SessionMetrics(session, build)
    if not session then return FinalizeSessionMetrics(NewSessionMetrics(nil), nil) end
    local logs = session.logs or {}
    local buildKey = build and table.concat({
        tostring(build.id or ""), tostring(build.title or ""),
        tostring(session.buildId or ""), tostring(session.buildTitle or ""),
    }, "|") or "*"
    local memo = sessionMetricsMemo[session]
    if not memo or memo.logs ~= logs or memo.buildKey ~= buildKey or #logs < memo.processed then
        memo = { logs = logs, buildKey = buildKey, processed = 0, metrics = NewSessionMetrics(session) }
        sessionMetricsMemo[session] = memo
    end
    for i = memo.processed + 1, #logs do
        AddEntryMetrics(memo.metrics, logs[i], session, build)
    end
    memo.processed = #logs
    return FinalizeSessionMetrics(memo.metrics, session)
end

local function AggregateSessionMetrics(sessions, build)
    local aggregate = NewSessionMetrics(nil)
    aggregate.levels = 0
    aggregate.maxLevel = 1

    for _, session in ipairs(sessions or {}) do
        local metrics = SessionMetrics(session, build)
        aggregate.events = aggregate.events + (metrics.events or 0)
        aggregate.selectedCount = aggregate.selectedCount + (metrics.selectedCount or 0)
        aggregate.selectedSum = aggregate.selectedSum + (metrics.selectedSum or 0)
        aggregate.resourceTotal = (aggregate.resourceTotal or 0) + (metrics.resourceTotal or 0)
        aggregate.levels = aggregate.levels + (metrics.levels or 0)
        aggregate.maxLevel = math.max(aggregate.maxLevel, metrics.maxLevel or 1)
        for action, count in pairs(metrics.actions or {}) do
            aggregate.actions[action] = (aggregate.actions[action] or 0) + (count or 0)
        end
        for signal, count in pairs(metrics.signals or {}) do
            aggregate.signals[signal] = (aggregate.signals[signal] or 0) + (count or 0)
        end
        for source, count in pairs(metrics.sources or {}) do
            aggregate.sources[source] = (aggregate.sources[source] or 0) + (count or 0)
        end
    end

    aggregate.averageSelected = aggregate.selectedCount > 0 and aggregate.selectedSum / aggregate.selectedCount or 0
    aggregate.resourcePerLevel = aggregate.levels > 0 and aggregate.resourceTotal / aggregate.levels or 0
    return aggregate
end

local function ChoiceQuality(choice)
    if type(choice) ~= "table" then return nil end
    local quality = tonumber(choice.quality)
    if quality ~= nil and (not EbonBuilds.Quality.IsValid or EbonBuilds.Quality.IsValid(quality)) then
        return quality
    end
    local spellId = tonumber(choice.spellId)
    if spellId and ProjectEbonhold and ProjectEbonhold.PerkDatabase then
        local data = ProjectEbonhold.PerkDatabase[spellId] or ProjectEbonhold.PerkDatabase[tostring(spellId)]
        quality = data and tonumber(data.quality) or nil
        if quality ~= nil and (not EbonBuilds.Quality.IsValid or EbonBuilds.Quality.IsValid(quality)) then
            return quality
        end
    end
    return nil
end

-- New logs persist each offer's original index. Older logs did not, so retain
-- the array-index fallback for backward compatibility.
local function TargetChoice(entry)
    if type(entry) ~= "table" or type(entry.choices) ~= "table" then return nil end
    local targetIndex = tonumber(entry.targetIndex)
    if not targetIndex or targetIndex <= 0 then return nil end
    for _, choice in ipairs(entry.choices) do
        if tonumber(choice.index) == targetIndex then return choice end
    end
    return entry.choices[targetIndex]
end

local function OfferScoreRange(entry)
    local best, worst, count
    count = 0
    for _, choice in ipairs(type(entry) == "table" and type(entry.choices) == "table" and entry.choices or {}) do
        local score = tonumber(choice.score)
        if score ~= nil then
            count = count + 1
            if best == nil or score > best then best = score end
            if worst == nil or score < worst then worst = score end
        end
    end
    return best, worst, count
end

local function HighestQualityInOffer(entry)
    local bestQuality, bestScore
    for _, choice in ipairs(type(entry) == "table" and type(entry.choices) == "table" and entry.choices or {}) do
        local quality = ChoiceQuality(choice)
        local score = tonumber(choice.score)
        if quality ~= nil and (bestQuality == nil or quality > bestQuality
            or (quality == bestQuality and score ~= nil and (bestScore == nil or score > bestScore))) then
            bestQuality = quality
            bestScore = score
        end
    end
    return bestQuality
end

local function NewActionBucket()
    local qualities = {}
    for _, quality in ipairs(QUALITY_ORDER) do qualities[quality] = 0 end
    return {
        count = 0,
        qualityTracked = 0,
        qualities = qualities,
        scoreTracked = 0,
        scoreSum = 0,
        rankTracked = 0,
        rankHits = 0,
    }
end

local function NewActionAnalytics()
    local analytics = {
        actions = {},
        total = 0,
        qualityTracked = 0,
        manualSelections = 0,
        otherDecisions = 0,
        matchingRuns = 0,
        rerollPairs = 0,
        rerollImprovementSum = 0,
    }
    for _, action in ipairs(ACTION_KEYS) do analytics.actions[action] = NewActionBucket() end
    return analytics
end

local function AddActionEntry(analytics, entry, action)
    local bucket = analytics.actions[action]
    if not bucket then return end

    bucket.count = bucket.count + 1
    analytics.total = analytics.total + 1

    local subjectQuality, subjectScore
    if action == "Reroll" then
        subjectQuality = HighestQualityInOffer(entry)
        subjectScore = OfferScoreRange(entry)
    else
        local target = TargetChoice(entry)
        subjectQuality = ChoiceQuality(target)
        subjectScore = target and tonumber(target.score) or nil
    end

    if subjectQuality ~= nil then
        bucket.qualityTracked = bucket.qualityTracked + 1
        bucket.qualities[subjectQuality] = (bucket.qualities[subjectQuality] or 0) + 1
        analytics.qualityTracked = analytics.qualityTracked + 1
    end
    if subjectScore ~= nil then
        bucket.scoreTracked = bucket.scoreTracked + 1
        bucket.scoreSum = bucket.scoreSum + subjectScore
    end

    if action == "Select" or action == "Banish" then
        local target = TargetChoice(entry)
        local targetScore = target and tonumber(target.score) or nil
        local best, worst, scoredChoices = OfferScoreRange(entry)
        if targetScore ~= nil and scoredChoices > 0 then
            bucket.rankTracked = bucket.rankTracked + 1
            if action == "Select" and best ~= nil and math.abs(targetScore - best) < 0.001 then
                bucket.rankHits = bucket.rankHits + 1
            elseif action == "Banish" and worst ~= nil and math.abs(targetScore - worst) < 0.001 then
                bucket.rankHits = bucket.rankHits + 1
            end
        end
    end
end

local function BuildActionAnalytics(sessions, build)
    local analytics = NewActionAnalytics()
    analytics.matchingRuns = #(sessions or {})

    for _, session in ipairs(sessions or {}) do
        local logs = session.logs or {}
        for index, entry in ipairs(logs) do
            if EntryMatchesBuild(entry, session, build) then
                local action = NormalizeAction(entry.action)
                if action == "Manual" then
                    analytics.manualSelections = analytics.manualSelections + 1
                elseif analytics.actions[action] then
                    AddActionEntry(analytics, entry, action)
                else
                    analytics.otherDecisions = analytics.otherDecisions + 1
                end

                -- A reroll's result is the first subsequent recorded board at
                -- the same level. Pair only build-matching entries and only
                -- when both boards contain scored choices.
                if action == "Reroll" then
                    local beforeBest = OfferScoreRange(entry)
                    if beforeBest ~= nil then
                        for nextIndex = index + 1, #logs do
                            local following = logs[nextIndex]
                            if tonumber(following.level) ~= tonumber(entry.level) then break end
                            if EntryMatchesBuild(following, session, build) then
                                local afterBest = OfferScoreRange(following)
                                if afterBest ~= nil then
                                    analytics.rerollPairs = analytics.rerollPairs + 1
                                    analytics.rerollImprovementSum = analytics.rerollImprovementSum + (afterBest - beforeBest)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    analytics.qualityMissing = math.max(0, analytics.total - analytics.qualityTracked)
    analytics.qualityCoveragePct = analytics.total > 0 and analytics.qualityTracked / analytics.total * 100 or 0
    analytics.rerollAverageImprovement = analytics.rerollPairs > 0
        and analytics.rerollImprovementSum / analytics.rerollPairs or nil
    for _, action in ipairs(ACTION_KEYS) do
        local bucket = analytics.actions[action]
        bucket.sharePct = analytics.total > 0 and bucket.count / analytics.total * 100 or 0
        bucket.averageScore = bucket.scoreTracked > 0 and bucket.scoreSum / bucket.scoreTracked or nil
        bucket.rankHitPct = bucket.rankTracked > 0 and bucket.rankHits / bucket.rankTracked * 100 or nil
    end
    return analytics
end

local function AnalyticsRecordMatchesBuild(record, session, build)
    if type(record) ~= "table" then return SessionHeaderMatchesBuild(session, build) end
    if record.buildId then return record.buildId == build.id end
    if record.buildTitle then return record.buildTitle == build.title end
    return SessionHeaderMatchesBuild(session, build)
end

local function CountEpicChoices(choices)
    if EbonBuilds.Session and EbonBuilds.Session._CountEpicChoices then
        return EbonBuilds.Session._CountEpicChoices(choices)
    end
    local count = 0
    for _, choice in ipairs(type(choices) == "table" and choices or {}) do
        local quality = tonumber(choice.quality)
        if quality == nil and choice.spellId and ProjectEbonhold and ProjectEbonhold.PerkDatabase then
            local data = ProjectEbonhold.PerkDatabase[choice.spellId] or ProjectEbonhold.PerkDatabase[tostring(choice.spellId)]
            quality = data and tonumber(data.quality) or nil
        end
        if quality == 3 then count = count + 1 end
    end
    return count
end

-- Returns one run-level observation. New sessions use the explicit field;
-- older sessions are reconstructed from the first recorded decision at that
-- level, whose choices are the pre-action/original offer.
local function EarlyEpicObservation(session, level, build)
    if not session or not build then return nil end
    local stored = session.earlyEpicOffers
    local direct = type(stored) == "table" and (stored[level] or stored[tostring(level)]) or nil
    if direct ~= nil then
        if type(direct) == "table" then
            if direct.tracked == false or not AnalyticsRecordMatchesBuild(direct, session, build) then return nil end
            local epicCount = tonumber(direct.epicCount) or 0
            return {
                tracked = true,
                seen = direct.epicSeen == true or epicCount > 0,
                epicCount = epicCount,
                inferred = false,
            }
        end
        if type(direct) == "boolean" and SessionHeaderMatchesBuild(session, build) then
            return { tracked = true, seen = direct, epicCount = direct and 1 or 0, inferred = false }
        end
        return nil
    end

    local firstEntry
    for _, entry in ipairs(session.logs or {}) do
        if tonumber(entry.level) == level and type(entry.choices) == "table" and #entry.choices > 0 then
            firstEntry = entry
            break
        end
    end
    if not firstEntry or not EntryMatchesBuild(firstEntry, session, build) then return nil end
    local epicCount = CountEpicChoices(firstEntry.choices)
    return { tracked = true, seen = epicCount > 0, epicCount = epicCount, inferred = true }
end

local function BuildEarlyEpicStats(sessions, build)
    local stats = {}
    for level = 1, 3 do
        stats[level] = { seen = 0, tracked = 0, epicOffers = 0, inferred = 0 }
    end
    for _, session in ipairs(sessions or {}) do
        for level = 1, 3 do
            local observation = EarlyEpicObservation(session, level, build)
            if observation and observation.tracked then
                local bucket = stats[level]
                bucket.tracked = bucket.tracked + 1
                bucket.epicOffers = bucket.epicOffers + (observation.epicCount or 0)
                if observation.seen then bucket.seen = bucket.seen + 1 end
                if observation.inferred then bucket.inferred = bucket.inferred + 1 end
            end
        end
    end
    for level = 1, 3 do
        local bucket = stats[level]
        bucket.pct = bucket.tracked > 0 and bucket.seen / bucket.tracked * 100 or 0
    end
    return stats
end

local function EarlySampleLabel(samples)
    samples = tonumber(samples) or 0
    if samples >= 30 then return "Established sample", "success" end
    if samples >= 10 then return "Developing sample", "warning" end
    if samples > 0 then return "Low sample", "danger" end
    return "Awaiting data", nil
end

local function VisibleEchoName(name)
    if EbonBuilds.Weights and EbonBuilds.Weights.VisibleName then
        return EbonBuilds.Weights.VisibleName(name)
    end
    local value = tostring(name or "")
    for index = 1, #value do
        local byte = value:byte(index)
        if byte and (byte < 32 or byte == 127) then
            value = value:sub(1, index - 1)
            break
        end
    end
    return value
end

local function LowerVisibleEchoName(name)
    return string.lower(VisibleEchoName(name))
end

local function NormalizeEchoName(name)
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName then
        return EbonBuilds.BuildOverview._NormalizeEchoName(name)
    end
    local stripped = EbonBuilds.Weights.StripQualitySuffix(VisibleEchoName(name))
    return string.lower(stripped or "")
end

local function WeightedCoverage(build)
    local total, learned = 0, 0
    local ownedNames, ownedGroups = {}, {}
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.GetOwnedEchoSets then
        local ok, names, groups = pcall(EbonBuilds.BuildOverview.GetOwnedEchoSets)
        if ok and type(names) == "table" then ownedNames = names end
        if ok and type(groups) == "table" then ownedGroups = groups end
    end
    if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end
    for refKey, values in EbonBuilds.Weights.IterateResolved(build) do
        if EbonBuilds.Weights.HasNonZero(values) then
            total = total + 1
            local definition = EbonBuilds.EchoCatalog.GetByRef(refKey)
            local canonical = definition and NormalizeEchoName(definition.canonicalName or definition.sourceName)
            if (canonical and ownedNames[canonical])
                or (definition and definition.groupId and ownedGroups[definition.groupId]) then
                learned = learned + 1
            end
        end
    end
    return learned, total
end

local function ConfidenceLabel(samples)
    samples = tonumber(samples) or 0
    if samples >= 15 then return "High", "success" end
    if samples >= 5 then return "Medium", "warning" end
    return "Low", "danger"
end

local function BestRankData(build, storageKey, entry, isRef)
    local bestQuality, bestWeight, bestScore
    for _, quality in ipairs(QUALITY_ORDER) do
        if not entry or not entry.qualities or entry.qualities[quality] then
            local weight = isRef and EbonBuilds.Weights.GetForRef(build, storageKey, quality)
                or EbonBuilds.Weights.GetFromWeights(build.echoWeights or {}, storageKey, quality)
            local score = EbonBuilds.Scoring.ScorePerQuality(entry or { families = {} }, weight, build.settings or {}, quality)
            if bestScore == nil or score > bestScore then
                bestQuality, bestWeight, bestScore = quality, weight, score
            end
        end
    end
    return bestQuality or 0, bestWeight or 0, bestScore or 0
end

local function BuildEchoRows(build, manualSuggestions, performanceStats, appearanceStats)
    local rows = {}
    local picks = (build.stats and build.stats.mostPicked) or {}
    local totalPicks = tonumber(build.stats and build.stats.picks) or 0
    local trainingByName = {}
    for _, suggestion in ipairs(manualSuggestions or {}) do
        local old = trainingByName[suggestion.name]
        if not old or suggestion.count > old.count then trainingByName[suggestion.name] = suggestion end
    end

    local function Add(storageKey, values, entry)
        if not EbonBuilds.Weights.HasNonZero(values) then return end
        local displayName = entry and (entry.displayName or entry.canonicalName or entry.sourceName)
            or VisibleEchoName(storageKey)
        displayName = VisibleEchoName(displayName)
        local quality, weight, score = BestRankData(build, storageKey, entry, true)
        local appearance = appearanceStats and (appearanceStats[displayName] or appearanceStats[storageKey])
        local performance = performanceStats and (performanceStats[displayName] or performanceStats[storageKey])
        local pickCount = picks[displayName] or picks[storageKey] or 0
        local recommendation = trainingByName[displayName] or trainingByName[storageKey]
        rows[#rows + 1] = {
            refKey = storageKey,
            name = displayName ~= "" and displayName or "Unknown Echo",
            internalName = storageKey, sortName = LowerVisibleEchoName(displayName),
            quality = quality, weight = weight, score = score,
            appearancePct = appearance and appearance.pct or nil,
            appearanceSamples = appearance and appearance.totalEvals or 0,
            pickCount = pickCount, pickShare = totalPicks > 0 and pickCount / totalPicks * 100 or 0,
            avgDPS = performance and performance.avgDPS or nil,
            personalCount = performance and performance.personalCount or 0,
            communityCount = performance and performance.communityCount or 0,
            sampleCount = performance and performance.sampleCount or 0,
            recommendation = recommendation,
            inactive = entry and entry.availability == EbonBuilds.EchoIdentity.UNAVAILABLE or false,
        }
    end

    if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end
    for refKey, values in EbonBuilds.Weights.IterateResolved(build) do
        local entry = EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.GetAnyEntry(build.class, refKey)
            or EbonBuilds.EchoCatalog.GetByRef(refKey)
        Add(refKey, values, entry)
    end
    return rows
end

local function ClampWeight(value)
    return math.max(EbonBuilds.Weights.MIN_VALUE, math.min(EbonBuilds.Weights.MAX_VALUE, math.floor((tonumber(value) or 0) + 0.5)))
end

local function RecommendationKey(source, target, quality, field)
    return table.concat({ tostring(source or "analytics"), tostring(target or "setting"), tostring(quality ~= nil and quality or "all"), tostring(field or "") }, "|")
end

local function ResolveRecommendationRef(build, refKey, echoName)
    if refKey and EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(refKey) then return refKey end
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindLegacyRefs
        and EbonBuilds.EchoCatalog.FindLegacyRefs(echoName) or {}
    if #refs == 1 then return refs[1] end
    return nil
end

local function TargetQualities(build, refKey, explicitQualities)
    local entry = refKey and EbonBuilds.EchoProjection
        and EbonBuilds.EchoProjection.GetAnyEntry(build.class, refKey) or nil
    local available = explicitQualities or (entry and entry.qualities)
    local out = {}
    for _, quality in ipairs(QUALITY_ORDER) do
        if not available or available[quality] then out[#out + 1] = quality end
    end
    if #out == 0 then
        for _, quality in ipairs(QUALITY_ORDER) do out[#out + 1] = quality end
    end
    return out
end

local function SnapshotWeights(build, refKey, qualities)
    local values = {}
    for _, quality in ipairs(qualities or {}) do
        values[quality] = EbonBuilds.Weights.GetForRef(build, refKey, quality)
    end
    return values
end

local function RecommendationDismissalStore(buildId, create)
    if not EbonBuildsDB then return nil end
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    if create then
        EbonBuildsDB.globalSettings.statsRecommendationDismissals = EbonBuildsDB.globalSettings.statsRecommendationDismissals or {}
        EbonBuildsDB.globalSettings.statsRecommendationDismissals[buildId] = EbonBuildsDB.globalSettings.statsRecommendationDismissals[buildId] or {}
    end
    local all = EbonBuildsDB.globalSettings.statsRecommendationDismissals
    return all and all[buildId] or nil
end

local function RecommendationIsDismissed(buildId, recommendation)
    local store = RecommendationDismissalStore(buildId, false)
    local dismissed = store and store[recommendation.key]
    if not dismissed then return false end
    local unchanged = dismissed.source == recommendation.source
        and (dismissed.samples or 0) == (recommendation.samples or 0)
        and tonumber(dismissed.currentValue) == tonumber(recommendation.currentValue)
        and tonumber(dismissed.suggestedValue) == tonumber(recommendation.suggestedValue)
    if unchanged then return true end
    store[recommendation.key] = nil
    return false
end

local function AddRecommendation(out, recommendation)
    recommendation.delta = (tonumber(recommendation.suggestedValue) or 0) - (tonumber(recommendation.currentValue) or 0)
    recommendation.direction = recommendation.delta > 0 and "raise" or recommendation.delta < 0 and "lower" or "review"
    recommendation.category = recommendation.category or recommendation.direction
    if not recommendation.section then
        local applyType = recommendation.apply and recommendation.apply.type
        recommendation.section = (recommendation.category == "thresholds" or recommendation.category == "resource_rules" or applyType == "setting") and "logic" or "echo"
    end
    recommendation.key = recommendation.key or RecommendationKey(recommendation.source, recommendation.target, recommendation.quality, recommendation.field)
    recommendation.body = recommendation.reason or recommendation.body or "Review this build setting."
    out[#out + 1] = recommendation
end

local function BuildRecommendations(build, manualSuggestions)
    local out = {}

    for _, suggestion in ipairs(manualSuggestions or {}) do
        local current = tonumber(suggestion.currentWeight) or 0
        local suggested = tonumber(suggestion.suggestedWeight) or (current + (tonumber(suggestion.delta) or 0))
        local quality = suggestion.quality
        local refKey = ResolveRecommendationRef(build, suggestion.refKey, suggestion.name)
        if not refKey then refKey = suggestion.refKey end
        local qualities = quality ~= nil and { quality } or TargetQualities(build, refKey, suggestion.qualities)
        local qualityLabel = quality ~= nil and ((EbonBuilds.Quality.LABELS or {})[quality] or tostring(quality)) or nil
        AddRecommendation(out, {
            kind = suggested > current and "RAISE PRIORITY" or "LOWER PRIORITY",
            target = VisibleEchoName(suggestion.name) .. (qualityLabel and (" · " .. qualityLabel) or ""),
            currentValue = current,
            suggestedValue = suggested,
            valueFormat = "number",
            reason = suggestion.direction == "raise"
                and "Manual choices repeatedly preferred this Echo over higher-scored alternatives."
                or "Manual choices repeatedly passed over this Echo for lower-scored alternatives.",
            source = "Manual Training",
            samples = suggestion.count or 0,
            section = "echo",
            echoName = suggestion.name,
            refKey = refKey,
            quality = quality,
            apply = {
                type = "weight",
                refKey = refKey,
                echoName = suggestion.name,
                quality = quality,
                qualities = qualities,
                applyAllRanks = quality == nil,
                delta = tonumber(suggestion.delta) or (suggested - current),
                value = suggested,
                expectedValues = SnapshotWeights(build, refKey, qualities),
            },
        })
    end

    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.SuggestWeightAdjustments then
        local ok, weightSuggestions = pcall(EbonBuilds.EchoPerformance.SuggestWeightAdjustments, build)
        for _, suggestion in ipairs(ok and weightSuggestions or {}) do
            local current = tonumber(suggestion.currentWeight) or 0
            local suggested = tonumber(suggestion.suggestedWeight) or current
            local refKey = ResolveRecommendationRef(build, suggestion.refKey, suggestion.name)
            local qualities = TargetQualities(build, refKey, suggestion.qualities)
            local deviation = tonumber(suggestion.deviationPct)
            local reason
            if deviation then
                reason = string.format("Recorded DPS is %.0f%% %s that of Echoes with the same configured priority.", math.abs(deviation), deviation >= 0 and "above" or "below")
            else
                reason = "Recorded DPS differs materially from similarly weighted Echoes."
            end
            -- Community-sourced evidence is labeled as such: the player
            -- should always be able to tell "my runs say" from "other
            -- players' runs say".
            if suggestion.evidence == "community-delta" then
                local peers = tonumber(suggestion.peers)
                reason = reason .. string.format(" Based on community data%s -- you have no reliable local samples for this Echo yet.",
                    peers and string.format(" from %d players", peers) or "")
            end
            AddRecommendation(out, {
                kind = suggested > current and "RAISE PRIORITY" or "LOWER PRIORITY",
                target = VisibleEchoName(suggestion.name) ~= "" and VisibleEchoName(suggestion.name) or "Echo priority",
                currentValue = current,
                suggestedValue = suggested,
                valueFormat = "number",
                reason = reason,
                source = "Details! analytics",
                samples = suggestion.sampleCount or suggestion.count or 0,
                section = "echo",
                echoName = suggestion.name,
                refKey = refKey,
                apply = {
                    type = "weight",
                    refKey = refKey,
                    echoName = suggestion.name,
                    qualities = qualities,
                    applyAllRanks = true,
                    delta = tonumber(suggestion.delta) or (suggested - current),
                    value = suggested,
                    expectedValues = SnapshotWeights(build, refKey, qualities),
                },
            })
        end
    end

    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment then
        local ok, qualitySuggestions = pcall(EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment, build)
        for _, suggestion in ipairs(ok and qualitySuggestions or {}) do
            local current = tonumber(suggestion.currentBonus) or 0
            local suggested = tonumber(suggestion.suggestedBonus) or current
            AddRecommendation(out, {
                kind = suggested > current and "RAISE MODIFIER" or "LOWER MODIFIER",
                target = (suggestion.qualityLabel or "Quality") .. " bonus",
                currentValue = current,
                suggestedValue = suggested,
                valueFormat = "number",
                reason = "Quality-tier DPS differs from the overall tracked performance baseline.",
                source = "Details! analytics",
                samples = suggestion.tierEchoCount or 0,
                quality = suggestion.quality,
                section = "echo",
                category = suggested > current and "raise" or "lower",
                apply = {
                    type = "qualityBonus",
                    quality = suggestion.quality,
                    expected = current,
                    value = suggested,
                },
            })
        end
    end

    if EbonBuilds.Calibration then
        local settings = build.settings or EbonBuilds.Build.DefaultSettings()
        local smart = (settings.rerollMode or "sum") == "ev"
        local thresholdDefs = {
            {
                label = "Banish threshold",
                field = smart and "banishEVPct" or "autoBanishPct",
                result = smart and EbonBuilds.Calibration.SuggestSmartBanish and EbonBuilds.Calibration.SuggestSmartBanish(settings)
                    or EbonBuilds.Calibration.SuggestBanish and EbonBuilds.Calibration.SuggestBanish(settings),
            },
            {
                label = "Reroll threshold",
                field = smart and "rerollEVPct" or "autoRerollPct",
                result = smart and EbonBuilds.Calibration.SuggestSmartReroll and EbonBuilds.Calibration.SuggestSmartReroll(settings)
                    or EbonBuilds.Calibration.SuggestReroll and EbonBuilds.Calibration.SuggestReroll(settings),
            },
            {
                label = "Freeze threshold",
                field = smart and "freezeEVPct" or "autoFreezePct",
                result = smart and EbonBuilds.Calibration.SuggestSmartFreeze and EbonBuilds.Calibration.SuggestSmartFreeze(settings)
                    or EbonBuilds.Calibration.SuggestFreeze and EbonBuilds.Calibration.SuggestFreeze(settings),
            },
        }
        for _, def in ipairs(thresholdDefs) do
            local result = def.result
            if result and not result.insufficientData and result.suggestedFieldPct and result.currentFieldPct
                and math.abs(result.suggestedFieldPct - result.currentFieldPct) >= 3 then
                local current = tonumber(settings[def.field]) or tonumber(result.currentFieldPct) or 0
                local suggested = math.floor((tonumber(result.suggestedFieldPct) or current) + 0.5)
                AddRecommendation(out, {
                    kind = suggested > current and "RAISE THRESHOLD" or "LOWER THRESHOLD",
                    target = def.label,
                    currentValue = current,
                    suggestedValue = suggested,
                    valueFormat = "percent",
                    reason = "Offer calibration places the target cutoff at a different point in recorded offers.",
                    source = "Offer calibration",
                    samples = result.sampleCount or 0,
                    section = "logic",
                    category = "thresholds",
                    field = def.field,
                    apply = {
                        type = "setting",
                        field = def.field,
                        expected = current,
                        value = suggested,
                    },
                })
            end
        end
    end

    -- Dismissals survive reloads only while the underlying evidence and
    -- proposed values remain unchanged. New samples or a new recommendation
    -- automatically make the item visible again.
    for i = #out, 1, -1 do
        if RecommendationIsDismissed(build.id, out[i]) then table.remove(out, i) end
    end

    -- Applying a recommendation can leave the underlying analytics unchanged,
    -- which would otherwise immediately propose another identical nudge. Hide
    -- the same evidence-backed item until its sample count changes; the applied
    -- record remains visible in the session history with an Undo action.
    local recent = recentRecommendationByBuild[build.id]
    if recent and recent.state == "applied" then
        for i = #out, 1, -1 do
            local item = out[i]
            if item.key == recent.recommendation.key
                and item.source == recent.recommendation.source
                and (item.samples or 0) == (recent.recommendation.samples or 0) then
                table.remove(out, i)
            end
        end
    end

    table.sort(out, function(a, b)
        local ac = (a.samples or 0) >= 20 and 3 or (a.samples or 0) >= 5 and 2 or 1
        local bc = (b.samples or 0) >= 20 and 3 or (b.samples or 0) >= 5 and 2 or 1
        if ac ~= bc then return ac > bc end
        if (a.samples or 0) ~= (b.samples or 0) then return (a.samples or 0) > (b.samples or 0) end
        if math.abs(a.delta or 0) ~= math.abs(b.delta or 0) then return math.abs(a.delta or 0) > math.abs(b.delta or 0) end
        return (a.target or "") < (b.target or "")
    end)
    return out
end

local function CacheSignature(build)
    local sessions = (EbonBuilds.Session and EbonBuilds.Session.GetSessions and EbonBuilds.Session.GetSessions()) or {}
    local totalLogs, latestStart, latestId, latestEnd, analyticsRevision = 0, 0, "", 0, 0
    for _, session in ipairs(sessions) do
        totalLogs = totalLogs + #(session.logs or {})
        analyticsRevision = analyticsRevision + (tonumber(session.analyticsRevision) or 0)
        local startTime = tonumber(session.startTime) or 0
        if startTime >= latestStart then
            latestStart = startTime
            latestId = tostring(session.id or "")
            latestEnd = tonumber(session.endTime) or 0
        end
    end
    local stats = build.stats or {}
    local manualRevision = EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.GetRevision and EbonBuilds.ManualTraining.GetRevision(build.id) or 0
    local performanceRevision = EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.GetRevision and EbonBuilds.EchoPerformance.GetRevision() or 0
    local calibrationRevision = EbonBuilds.Calibration and EbonBuilds.Calibration.GetRevision and EbonBuilds.Calibration.GetRevision() or 0
    local appearanceRevision = EbonBuilds.Calibration and EbonBuilds.Calibration.GetAppearanceRevision and EbonBuilds.Calibration.GetAppearanceRevision() or 0
    return table.concat({
        tostring(build.id or ""),
        tostring(build.version or 0),
        tostring(build.modifiedAt or build.updatedAt or 0),
        tostring(#sessions), tostring(totalLogs), tostring(latestStart), latestId, tostring(latestEnd), tostring(analyticsRevision),
        tostring(stats.picks or 0), tostring(stats.bans or 0), tostring(stats.rerolls or 0), tostring(stats.freezes or 0),
        tostring(manualRevision), tostring(performanceRevision), tostring(calibrationRevision), tostring(appearanceRevision),
    }, "|")
end

local function GenerateCache(build)
    local sessions = MatchingSessions(build)
    local latest = sessions[1]
    local previous
    for i = 2, #sessions do
        if sessions[i].endTime then previous = sessions[i]; break end
    end
    local latestMetrics = SessionMetrics(latest, build)
    local previousMetrics = SessionMetrics(previous, build)
    local aggregateMetrics = AggregateSessionMetrics(sessions, build)
    local actionAnalytics = BuildActionAnalytics(sessions, build)
    local earlyEpic = BuildEarlyEpicStats(sessions, build)
    local learned, weighted = WeightedCoverage(build)
    local manualSuggestions = EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.SuggestWeightAdjustments
        and EbonBuilds.ManualTraining.SuggestWeightAdjustments(build) or {}
    local manualSamples = EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.GetSampleCount and EbonBuilds.ManualTraining.GetSampleCount(build.id) or 0
    local performanceStats = {}
    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.GetAllStats then
        local ok, stats = pcall(EbonBuilds.EchoPerformance.GetAllStats)
        if ok and type(stats) == "table" then performanceStats = stats end
    end
    local appearanceStats = EbonBuilds.Calibration and EbonBuilds.Calibration.GetAllAppearanceStats
        and EbonBuilds.Calibration.GetAllAppearanceStats(build.class) or {}
    local echoRows = BuildEchoRows(build, manualSuggestions, performanceStats, appearanceStats)
    local usefulSamples = manualSamples
    for _, row in ipairs(echoRows) do usefulSamples = usefulSamples + (row.personalCount or 0) end
    local confidence, confidenceKind = ConfidenceLabel(usefulSamples)
    cacheGeneration = cacheGeneration + 1

    return {
        buildId = build.id,
        generation = cacheGeneration,
        sessions = sessions,
        latest = latestMetrics,
        previous = previousMetrics,
        aggregate = aggregateMetrics,
        actionAnalytics = actionAnalytics,
        earlyEpic = earlyEpic,
        matchingRunCount = #sessions,
        decisionCount = aggregateMetrics.events or 0,
        weightedLearned = learned,
        weightedTotal = weighted,
        coveragePct = weighted > 0 and learned / weighted * 100 or 0,
        usefulSamples = usefulSamples,
        manualSamples = manualSamples,
        manualSuggestions = manualSuggestions,
        performanceStats = performanceStats,
        confidence = confidence,
        confidenceKind = confidenceKind,
        echoes = echoRows,
        recommendations = nil,
    }
end

-- Parameterized on purpose: which cache/build is "current" is view state,
-- so the view passes both in (its EnsureRecommendations wrapper keeps every
-- call site unchanged).
function Data.EnsureRecommendations(cache, build)
    if not cache then return {} end
    if cache.recommendations == nil then
        cache.recommendations = BuildRecommendations(build, cache.manualSuggestions)
    end
    return cache.recommendations
end

-- Public surface: every function the view and the test hooks consume.
Data.Round = Round
Data.NormalizeAction = NormalizeAction
Data.SessionMatchesBuild = SessionMatchesBuild
Data.SessionMetrics = SessionMetrics
Data.NewSessionMetrics = NewSessionMetrics
Data.AggregateSessionMetrics = AggregateSessionMetrics
Data.TargetChoice = TargetChoice
Data.NewActionBucket = NewActionBucket
Data.NewActionAnalytics = NewActionAnalytics
Data.BuildActionAnalytics = BuildActionAnalytics
Data.EarlyEpicObservation = EarlyEpicObservation
Data.BuildEarlyEpicStats = BuildEarlyEpicStats
Data.EarlySampleLabel = EarlySampleLabel
Data.VisibleEchoName = VisibleEchoName
Data.LowerVisibleEchoName = LowerVisibleEchoName
Data.WeightedCoverage = WeightedCoverage
Data.ConfidenceLabel = ConfidenceLabel
Data.BuildEchoRows = BuildEchoRows
Data.ClampWeight = ClampWeight
Data.ResolveRecommendationRef = ResolveRecommendationRef
Data.RecommendationDismissalStore = RecommendationDismissalStore
Data.BuildRecommendations = BuildRecommendations
Data.CacheSignature = CacheSignature
Data.GenerateCache = GenerateCache
