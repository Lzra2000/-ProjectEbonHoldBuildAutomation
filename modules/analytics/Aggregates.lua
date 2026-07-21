local addonName, EbonBuilds = ...

-- EbonBuilds: modules/analytics/Aggregates.lua
-- Incremental per-build/per-strategy summaries. Raw logs remain bounded.

EbonBuilds.Aggregates = {}

local Aggregates = EbonBuilds.Aggregates
local SCHEMA = 1
local MAX_REVISIONS = 8

local function NewTotals()
    return {
        completedRuns = 0, interruptedRuns = 0, mixedRuns = 0,
        decisions = 0, selectedScoreSum = 0, selectedScoreCount = 0,
        soulAshSum = 0,
        actionCounts = { Select = 0, Banish = 0, Reroll = 0, Freeze = 0, Manual = 0 },
        resourceSpent = { banish = 0, reroll = 0, freeze = 0 },
        manualDisagreements = 0,
    }
end

local function EnsureBuild(buildId)
    EbonBuildsDB.buildAggregates = EbonBuildsDB.buildAggregates or {}
    local aggregate = EbonBuildsDB.buildAggregates[buildId]
    if not aggregate then
        aggregate = { v = SCHEMA, lifetime = NewTotals(), revisions = {}, lastReviewedRunAt = 0 }
        EbonBuildsDB.buildAggregates[buildId] = aggregate
    end
    aggregate.lifetime = aggregate.lifetime or NewTotals()
    aggregate.revisions = aggregate.revisions or {}
    aggregate.lastReviewedRunAt = tonumber(aggregate.lastReviewedRunAt) or 0
    return aggregate
end

local function NormalizeAction(action)
    action = tostring(action or "")
    if action:find("^Select") then return "Select" end
    if action:find("^Banish") then return "Banish" end
    if action:find("^Reroll") then return "Reroll" end
    if action:find("^Freeze") then return "Freeze" end
    if action:find("^Manual") then return "Manual" end
    return nil
end

local function AddSession(totals, session)
    if session.completed then totals.completedRuns = totals.completedRuns + 1
    else totals.interruptedRuns = totals.interruptedRuns + 1 end
    if session.mixedStrategy then totals.mixedRuns = totals.mixedRuns + 1 end
    totals.soulAshSum = totals.soulAshSum + (tonumber(session.soulAshes) or 0)

    for _, entry in ipairs(session.logs or {}) do
        totals.decisions = totals.decisions + 1
        local action = NormalizeAction(entry.action)
        if action then totals.actionCounts[action] = (totals.actionCounts[action] or 0) + 1 end
        if action == "Banish" then totals.resourceSpent.banish = totals.resourceSpent.banish + 1 end
        if action == "Reroll" then totals.resourceSpent.reroll = totals.resourceSpent.reroll + 1 end
        if action == "Freeze" then totals.resourceSpent.freeze = totals.resourceSpent.freeze + 1 end

        local decision = entry.decision or {}
        if decision.flags and decision.flags.manualDisagreement then
            totals.manualDisagreements = totals.manualDisagreements + 1
        end
        if action == "Select" or action == "Manual" then
            local choice = entry.choices and entry.choices[entry.targetIndex or 0]
            if choice and tonumber(choice.score) then
                totals.selectedScoreSum = totals.selectedScoreSum + tonumber(choice.score)
                totals.selectedScoreCount = totals.selectedScoreCount + 1
            end
        end
    end
end

local function PruneRevisionBuckets(aggregate)
    local keys = {}
    for revision in pairs(aggregate.revisions) do keys[#keys + 1] = tonumber(revision) or 0 end
    if #keys <= MAX_REVISIONS then return end
    table.sort(keys, function(a, b) return a > b end)
    for index = MAX_REVISIONS + 1, #keys do
        aggregate.revisions[keys[index]] = nil
        aggregate.revisions[tostring(keys[index])] = nil
    end
end

function Aggregates.OnRunEnded(session)
    if not session or session._aggregateSchema == SCHEMA then return false end
    local buildId = session.buildId
    if not buildId then return false end
    local aggregate = EnsureBuild(buildId)
    AddSession(aggregate.lifetime, session)

    if not session.mixedStrategy then
        local revision = tonumber(session.strategyRevision) or 1
        local bucket = aggregate.revisions[revision]
        if not bucket then
            bucket = NewTotals()
            bucket.strategyHash = session.strategyHash
            bucket.firstSeen = session.startTime
            bucket.lastSeen = session.endTime or session.startTime
            aggregate.revisions[revision] = bucket
        end
        bucket.lastSeen = session.endTime or time()
        AddSession(bucket, session)
    end
    PruneRevisionBuckets(aggregate)
    session._aggregateSchema = SCHEMA
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("EVIDENCE_REVISION_CHANGED", buildId) end
    return true
end

function Aggregates.Get(buildId)
    if not buildId then return nil end
    return EnsureBuild(buildId)
end

function Aggregates.GetRevision(build)
    if not build then return nil end
    local aggregate = EnsureBuild(build.id)
    return aggregate.revisions[tonumber(build.strategyRevision) or 1]
end

function Aggregates.MarkReviewed(buildId, endedAt)
    local aggregate = EnsureBuild(buildId)
    aggregate.lastReviewedRunAt = math.max(aggregate.lastReviewedRunAt or 0, tonumber(endedAt) or time())
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("EVIDENCE_REVISION_CHANGED", buildId) end
end

function Aggregates.Init()
    EbonBuildsDB.buildAggregates = EbonBuildsDB.buildAggregates or {}
    local started = false
    local complete = false
    local databaseReadyToken

    local function Finish()
        if complete then return false end
        complete = true
        if databaseReadyToken and EbonBuilds.EventHub then
            EbonBuilds.EventHub.Off(databaseReadyToken)
            databaseReadyToken = nil
        end
        if EbonBuilds.Database then EbonBuilds.Database.SchedulePrune() end
        if EbonBuilds.EventHub then
            EbonBuilds.EventHub.Bump("ANALYTICS_BACKFILL_COMPLETE")
        end
        return false
    end

    local function StartBackfill()
        if started then return end
        started = true
        local cursor = 1
        local function Backfill()
            local sessions = EbonBuildsDB.sessions or {}
            local processed = 0
            while cursor <= #sessions and processed < 8 do
                local session = sessions[cursor]
                if session and session.endTime then Aggregates.OnRunEnded(session) end
                cursor = cursor + 1
                processed = processed + 1
            end
            if cursor <= #sessions then return 0.05 end
            return Finish()
        end
        EbonBuilds.Scheduler.Every("aggregates.backfill", 0.2, Backfill,
            EbonBuilds.Scheduler.MAINTENANCE, false, "Aggregates")
    end

    Aggregates.IsBackfillComplete = function() return complete end

    if EbonBuilds.Database and EbonBuilds.Database.IsReady and EbonBuilds.Database.IsReady() then
        StartBackfill()
    elseif EbonBuilds.EventHub then
        databaseReadyToken = EbonBuilds.EventHub.On("DATABASE_READY", function()
            StartBackfill()
        end, "Aggregates")
    end
    return true
end
