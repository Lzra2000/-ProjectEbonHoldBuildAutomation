local addonName, EbonBuilds = ...

-- EbonBuilds: modules/app/Review.lua
-- Lazy, evidence-bound post-run summary. It never invents causal prose.

EbonBuilds.Review = {}

local Review = EbonBuilds.Review

local function Matches(session, build)
    return session and build and ((session.buildId and session.buildId == build.id)
        or (not session.buildId and session.buildTitle == build.title))
end

function Review.Latest(build)
    if not build then return nil end
    for _, session in ipairs(EbonBuilds.Session.GetSessions()) do
        if Matches(session, build) and session.endTime then return session end
    end
    return nil
end

local function Importance(entry)
    local flags = entry and entry.decision and entry.decision.flags or {}
    if flags.lastCharge then return 600 end
    if flags.manualDisagreement then return 500 end
    if entry and entry.decision and entry.decision.policy then return 400 end
    if flags.closeDecision then return 300 end
    if flags.modifierOverride then return 200 end
    return 0
end

function Review.Build(build, session)
    session = session or Review.Latest(build)
    if not session then return nil end
    local notable = {}
    local actions = { Select = 0, Banish = 0, Reroll = 0, Freeze = 0, Manual = 0 }
    for _, entry in ipairs(session.logs or {}) do
        local action = tostring(entry.action or "")
        local key = action:find("^Select") and "Select"
            or action:find("^Banish") and "Banish"
            or action:find("^Reroll") and "Reroll"
            or action:find("^Freeze") and "Freeze"
            or action:find("^Manual") and "Manual"
        if key then actions[key] = actions[key] + 1 end
        local score = Importance(entry)
        if score > 0 then notable[#notable + 1] = { score = score, entry = entry } end
    end
    table.sort(notable, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.entry.timestamp or 0) < (b.entry.timestamp or 0)
    end)
    local top = {}
    for index = 1, math.min(3, #notable) do top[index] = notable[index].entry end
    return {
        runId = session.id,
        endTime = session.endTime,
        completed = session.completed == true,
        mixedStrategy = session.mixedStrategy == true,
        maxLevel = session.maxLevel or 1,
        decisions = #(session.logs or {}),
        soulAshes = session.soulAshes or 0,
        actions = actions,
        notable = top,
        strategyRevision = session.strategyRevision,
    }
end

function Review.MarkReviewed(build, session)
    if not build then return end
    session = session or Review.Latest(build)
    if session then EbonBuilds.Aggregates.MarkReviewed(build.id, session.endTime) end
end
