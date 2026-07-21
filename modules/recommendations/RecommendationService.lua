local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/RecommendationService.lua
-- Async cache/provider boundary for wizard recommendations.

EbonBuilds.RecommendationService = {}

local Service = EbonBuilds.RecommendationService
local jobs = {}
local dirty = {}
local MAX_COHORTS = 30

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[Copy(key)] = Copy(child) end
    return out
end

local function Revision()
    return tonumber(EbonBuildsDB and EbonBuildsDB.recommendationSourceRevision) or 1
end

local function Cache()
    EbonBuildsDB.recommendationCache = EbonBuildsDB.recommendationCache or {}
    return EbonBuildsDB.recommendationCache
end

local function PruneCache()
    local cache, list = Cache(), {}
    for key, snapshot in pairs(cache) do list[#list + 1] = { key = key, snapshot = snapshot } end
    if #list <= MAX_COHORTS then return end
    table.sort(list, function(a, b) return (a.snapshot.cachedAt or 0) > (b.snapshot.cachedAt or 0) end)
    for index = MAX_COHORTS + 1, #list do cache[list[index].key] = nil end
end

function Service.CopySnapshot(snapshot)
    return Copy(snapshot)
end

function Service.Get(classToken, spec)
    local key = EbonBuilds.CommunityEligibility.CohortKey(classToken, spec)
    local snapshot = Cache()[key]
    if dirty[key] or not snapshot or tonumber(snapshot.sourceRevision) ~= Revision() then return nil end
    return snapshot
end

local function Finish(key, work)
    if tonumber(work.sourceRevision) ~= Revision() then
        local stale = jobs[key]
        jobs[key] = nil
        for _, callback in ipairs(stale and stale.callbacks or {}) do
            Service.Ensure(work.class, work.spec, callback)
        end
        return nil
    end
    local snapshot = EbonBuilds.CommunityAggregator.Finalize(work)
    snapshot.cachedAt = time and time() or 0
    Cache()[key] = snapshot
    dirty[key] = nil
    PruneCache()
    local job = jobs[key]
    jobs[key] = nil
    for _, callback in ipairs(job and job.callbacks or {}) do callback(Service.CopySnapshot(snapshot)) end
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RECOMMENDATION_READY", key) end
    return snapshot
end

function Service.Ensure(classToken, spec, callback)
    local key = EbonBuilds.CommunityEligibility.CohortKey(classToken, spec)
    local cached = Service.Get(classToken, spec)
    if cached then
        if callback then callback(Service.CopySnapshot(cached)) end
        return cached
    end
    if jobs[key] then
        if callback then jobs[key].callbacks[#jobs[key].callbacks + 1] = callback end
        return nil
    end

    local job = {
        work = EbonBuilds.CommunityAggregator.Begin(classToken, spec, Revision()),
        callbacks = callback and { callback } or {},
    }
    jobs[key] = job
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.Every("recommendations." .. key, 0.05, function()
            if EbonBuilds.CommunityAggregator.Step(job.work, 2) then
                Finish(key, job.work)
                return false
            end
            return 0.05
        end, EbonBuilds.Scheduler.BACKGROUND, true)
    else
        while not EbonBuilds.CommunityAggregator.Step(job.work, 2) do end
        return Finish(key, job.work)
    end
    return nil
end

function Service.Invalidate(classToken, spec)
    EbonBuildsDB.recommendationSourceRevision = Revision() + 1
    if classToken then
        dirty[EbonBuilds.CommunityEligibility.CohortKey(classToken, spec)] = true
    else
        for key in pairs(Cache()) do dirty[key] = true end
    end
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RECOMMENDATION_SOURCE_CHANGED") end
end

function Service.Init()
    EbonBuildsDB.recommendationCache = EbonBuildsDB.recommendationCache or {}
    EbonBuildsDB.recommendationSourceRevision = Revision()
    local staleKeys = {}
    for key, snapshot in pairs(EbonBuildsDB.recommendationCache) do
        if type(snapshot) ~= "table" or tonumber(snapshot.schema) ~= 6 then
            staleKeys[#staleKeys + 1] = key
        end
    end
    for _, key in ipairs(staleKeys) do EbonBuildsDB.recommendationCache[key] = nil end
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.On("BUILD_LIBRARY_CHANGED", function() Service.Invalidate() end)
        EbonBuilds.EventHub.On("SYNC_REVISION_CHANGED", function() Service.Invalidate() end)
    end
    PruneCache()
end

function Service.GetLimits()
    return { cohorts = MAX_COHORTS, recordsPerSlice = 2, recordsPerCohort = 256 }
end
