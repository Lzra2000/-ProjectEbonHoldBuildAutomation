local addonName, EbonBuilds = ...

-- EbonBuilds: modules/app/Readiness.lua
-- Derived Plan/Run/Review state. Nothing in this projection is persisted.

EbonBuilds.Readiness = {}

local Readiness = EbonBuilds.Readiness

local function Add(list, code, value)
    list[#list + 1] = { code = code, value = value }
end

local function WeightedCount(build)
    local count = 0
    for _, entry in pairs(build and build.echoWeights or {}) do
        if EbonBuilds.Weights.HasNonZero(entry) then count = count + 1 end
    end
    return count
end

local function LockCount(build)
    local count = 0
    for index = 1, EbonBuilds.Build.LOCKED_SLOTS do
        if build.lockedEchoes and build.lockedEchoes[index] then count = count + 1 end
    end
    return count
end

local function LatestCompletedRun(buildId)
    for _, session in ipairs(EbonBuilds.Session.GetSessions()) do
        if session.buildId == buildId and session.endTime then return session end
    end
    return nil
end

local function EvidenceTier(bucket)
    if not bucket or (bucket.decisions or 0) < 5 then return "INSUFFICIENT" end
    if (bucket.completedRuns or 0) < 3 or (bucket.decisions or 0) < 20 then return "EARLY" end
    if (bucket.completedRuns or 0) >= 5 and (bucket.decisions or 0) >= 100 then return "STRONG_PERSONAL" end
    return "SUPPORTED"
end

function Readiness.Get(build)
    local projection = {
        state = "INCOMPLETE",
        blockers = {},
        notices = {},
        nextAction = "SELECT_BUILD",
        lockCount = 0,
        weightedCount = 0,
        evidenceTier = "INSUFFICIENT",
        reviewPending = false,
    }
    if not build then
        Add(projection.blockers, "NO_ACTIVE_BUILD")
        return projection
    end

    projection.buildId = build.id
    projection.revision = build.revision or 1
    projection.strategyRevision = build.strategyRevision or 1
    projection.lockCount = LockCount(build)
    projection.weightedCount = WeightedCount(build)
    projection.autopilotEnabled = EbonBuilds.Build.IsAutomationEnabled(build)
    projection.trainingEnabled = EbonBuilds.Build.IsTrainingEnabled(build)

    if not (ProjectEbonhold and ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkService) then
        Add(projection.blockers, "PROJECT_EBONHOLD_UNAVAILABLE")
    end
    if not build.id or not build.class or not build.settings then
        Add(projection.blockers, "INVALID_BUILD")
    end
    local playerClass = select(2, UnitClass("player"))
    if playerClass and build.class and playerClass ~= build.class then
        Add(projection.blockers, "CLASS_MISMATCH", playerClass)
    end

    if projection.lockCount < EbonBuilds.Build.LOCKED_SLOTS then
        Add(projection.notices, "LOCKS_OPTIONAL", projection.lockCount)
    end
    if projection.weightedCount == 0 then Add(projection.notices, "NO_WEIGHTED_PRIORITIES") end
    if not projection.autopilotEnabled then Add(projection.notices, "AUTOPILOT_PAUSED") end

    local bucket = EbonBuilds.Aggregates.GetRevision(build)
    projection.evidenceTier = EvidenceTier(bucket)
    projection.completedRuns = bucket and bucket.completedRuns or 0
    projection.decisionCount = bucket and bucket.decisions or 0

    local latest = LatestCompletedRun(build.id)
    local aggregate = EbonBuilds.Aggregates.Get(build.id)
    projection.latestRun = latest
    projection.reviewPending = latest and (latest.endTime or 0) > (aggregate.lastReviewedRunAt or 0) or false

    if #projection.blockers > 0 then
        projection.nextAction = "RESOLVE_BLOCKER"
    elseif projection.reviewPending then
        projection.nextAction = "REVIEW_RUN"
    elseif not projection.autopilotEnabled then
        projection.nextAction = "ENABLE_AUTOPILOT"
    elseif projection.weightedCount == 0 then
        projection.nextAction = "SET_PRIORITIES"
    else
        projection.nextAction = "RUN_BUILD"
    end

    if #projection.blockers == 0 then
        if projection.completedRuns >= 3 and projection.evidenceTier == "SUPPORTED" then
            projection.state = "SUPPORTED"
        elseif projection.completedRuns >= 5 and projection.evidenceTier == "STRONG_PERSONAL" then
            projection.state = "SUPPORTED"
        elseif projection.completedRuns >= 1 then
            projection.state = "TESTED"
        else
            projection.state = "READY"
        end
    end
    return projection
end
