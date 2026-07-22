local addonName, EbonBuilds = ...

-- EbonBuilds: modules/session/Session.lua
-- Responsibility: session lifecycle management (start, end, log actions).
-- A session spans from level 1 until the player dies and resets back to
-- level 1. Logs are persisted per-session in EbonBuildsDB.sessions.

EbonBuilds.Session = {}

local POLL_INTERVAL = 2  -- seconds between level checks for reset detection
local EARLY_OFFER_MAX_LEVEL = 3
local EPIC_QUALITY = 3
local MAX_RUN_SELECTIONS = 79

local maxLevel     = 0   -- highest level seen in the active session

local function NotifyHistoryChanged()
    if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OnHistoryChanged then
        EbonBuilds.SessionHistory.OnHistoryChanged()
    end
end

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function GetRunSoulAshes()
    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end
    return (rd and rd.soulPoints) or 0
end

local function GetClassName()
    local _, class = UnitClass("player")
    return class  -- English token (WARRIOR, MAGE, etc.)
end

local function GetActiveBuildTitle()
    local build = EbonBuilds.Build.GetActive()
    return build and build.title or "No Build"
end

local function GetActiveBuildId()
    local build = EbonBuilds.Build.GetActive()
    return build and build.id or nil
end

local function CreateSession()
    local sessions = EbonBuildsDB.sessions
    local id = tostring(time()) .. "-" .. tostring(#sessions + 1)

	local build = EbonBuilds.Build.GetActive()
	local session = {
        id            = id,
        characterName = UnitName("player"),
        characterKey  = EbonBuilds.Database.CharacterKey(),
        className     = GetClassName(),
        startTime     = time(),
        endTime       = nil,
        soulAshes     = 0,
        buildId       = GetActiveBuildId(),
        buildTitle    = GetActiveBuildTitle(),
        buildRevision = build and (tonumber(build.revision) or tonumber(build.version) or 1) or nil,
        strategyRevision = build and (tonumber(build.strategyRevision) or 1) or nil,
        strategyHash  = build and (build.strategyHash or EbonBuilds.Build.StrategyChecksum(build)) or nil,
        startLevel    = UnitLevel("player"),
        logs          = {},
        completed     = false,
        completionReason = "active",
        selectionCount = 0,
        -- Original offers for the first three levels. Each level is written
        -- at most once, before any automated action or manual-mode opt-out,
        -- so rerolls and banish replacements cannot inflate the statistic.
        earlyEpicOffers = {},
        analyticsRevision = 0,
    }

    table.insert(sessions, 1, session)
    EbonBuildsDB.currentSessionIndex = 1
    maxLevel = UnitLevel("player")
    session.maxLevel = maxLevel

    -- New run: the automation peak was locked for the previous run and must
    -- be recomputed fresh (weights or settings may have changed in between).
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetInitialActionDelay then
        EbonBuilds.Automation.ResetInitialActionDelay()
    end

    NotifyHistoryChanged()
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_STARTED", session.id, session.buildId) end
    return session
end

-- Keep the live session's persisted maxLevel in step with the local tracker,
-- so a relog can restore it and death-reset detection works across logouts.
local function TrackMaxLevel(level)
    if level <= maxLevel then return end
    maxLevel = level
    local idx = EbonBuildsDB.currentSessionIndex
    local session = idx and EbonBuildsDB.sessions[idx]
    if session then session.maxLevel = maxLevel end
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

local function OnPlayerEnteringWorld()
    local level = UnitLevel("player")

    -- No active session: start one at the current level
    if not EbonBuildsDB.currentSessionIndex then
        CreateSession()
        return
    end

    -- Fresh login/reload: the local maxLevel tracker resets to 0, so restore
    -- it from the live session record. Without this, a death-reset that
    -- spans a logout (relog at level 1) would never be detected and the old
    -- session would keep accumulating a second run's logs.
    local session = EbonBuildsDB.sessions[EbonBuildsDB.currentSessionIndex]
    if session and session.maxLevel and session.maxLevel > maxLevel then
        maxLevel = session.maxLevel
    end

    -- Active session exists, but player is now level 1 after being higher:
    -- the run ended (death accepted, reset to level 1)
    if level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    -- Update max level if player leveled up while offline / zoning
    TrackMaxLevel(level)
end

local function OnPlayerLevelUp(newLevel)
    if not EbonBuildsDB.currentSessionIndex then
        -- No session yet: start one at the current level
        CreateSession()
        return
    end

    TrackMaxLevel(newLevel)
end

local function PollLevel()
    local level = UnitLevel("player")

    -- Level reset detection: player went from >1 back to 1
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    TrackMaxLevel(level)
end

local function DecisionMetadata(action, settings, build, source)
    settings = settings or (build and build.settings) or EbonBuilds.Build.DefaultSettings()
    local classToken = build and build.class
    local smart = (settings.rerollMode or "sum") == "ev"
    local threshold, reasonCode
    if tostring(action or ""):find("^Manual") then
        reasonCode = "MANUAL_CHOICE"
    elseif smart then
        local stats = EbonBuilds.Scoring.ComputeOutcomeStats(classToken, settings)
        if action == "Banish" then
            threshold = (stats.mean or 0) * (settings.banishEVPct or 0) / 100
            reasonCode = "BELOW_BANISH_THRESHOLD"
        elseif action == "Reroll" then
            threshold = (stats.evBest3 or 0) * (settings.rerollEVPct or 0) / 100
            reasonCode = "BOARD_BELOW_REROLL_THRESHOLD"
        elseif action == "Freeze" then
            threshold = (stats.evBest3 or 0) * (settings.freezeEVPct or 0) / 100
            reasonCode = "TWO_OFFERS_ABOVE_FREEZE_THRESHOLD"
        else
            reasonCode = "HIGHEST_FINAL_SCORE"
        end
    else
        local _, peak = EbonBuilds.Scoring.ComputePeak(classToken, settings)
        if action == "Banish" then
            threshold = (peak or 0) * (settings.autoBanishPct or 0) / 100
            reasonCode = "BELOW_BANISH_THRESHOLD"
        elseif action == "Reroll" then
            threshold = (peak or 0) * (settings.autoRerollPct or 0) / 100
            reasonCode = "BOARD_BELOW_REROLL_THRESHOLD"
        elseif action == "Freeze" then
            threshold = (peak or 0) * (settings.autoFreezePct or 0) / 100
            reasonCode = "TWO_OFFERS_ABOVE_FREEZE_THRESHOLD"
        else
            reasonCode = "HIGHEST_FINAL_SCORE"
        end
    end
    return {
        source = source and tostring(source):lower() ~= "automatic" and source or nil,
        model = smart and "expected value" or "classic peak",
        threshold = threshold,
        reasonCode = reasonCode,
        buildId = build and build.id or nil,
        buildTitle = build and build.title or "No Build",
    }
end

------------------------------------------------------------------------
-- Early-offer analytics
------------------------------------------------------------------------

local function ChoiceQuality(choice)
    if type(choice) ~= "table" then return nil end
    local quality = tonumber(choice.quality)
    if quality ~= nil then return quality end

    local spellId = tonumber(choice.spellId)
    local database = ProjectEbonhold and ProjectEbonhold.PerkDatabase
    local data = spellId and database and (database[spellId] or database[tostring(spellId)])
    return data and tonumber(data.quality) or nil
end

local function CountEpicChoices(choices)
    local count = 0
    for _, choice in ipairs(type(choices) == "table" and choices or {}) do
        if ChoiceQuality(choice) == EPIC_QUALITY then count = count + 1 end
    end
    return count
end

-- Records the original offer at run levels 1, 2, and 3. Automation calls this
-- immediately after reading GetCurrentChoice(), before banish/reroll/freeze or
-- any manual/autopilot early return. Repeated evaluations at the same level are
-- intentionally ignored.
function EbonBuilds.Session.RecordInitialOffer(choices)
    local level = tonumber(UnitLevel("player")) or 0
    if level < 1 or level > EARLY_OFFER_MAX_LEVEL then return false end
    if type(choices) ~= "table" or #choices == 0 then return false end

    -- Keep the same reset safety as LogAction so the first offer after a death
    -- cannot be attached to the previous run when no loading screen occurred.
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
    end

    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then
        CreateSession()
        idx = EbonBuildsDB.currentSessionIndex
    end
    local session = idx and EbonBuildsDB.sessions[idx]
    if not session then return false end

    session.earlyEpicOffers = session.earlyEpicOffers or {}
    local existing = session.earlyEpicOffers[level] or session.earlyEpicOffers[tostring(level)]
    if type(existing) == "table" and existing.tracked ~= false then return false end
    if type(existing) == "boolean" then return false end

    local build = EbonBuilds.Build.GetActive()
    local epicCount = CountEpicChoices(choices)
    session.earlyEpicOffers[level] = {
        tracked = true,
        epicSeen = epicCount > 0,
        epicCount = epicCount,
        timestamp = time(),
        buildId = build and build.id or nil,
        buildTitle = build and build.title or "No Build",
    }
    session.analyticsRevision = (tonumber(session.analyticsRevision) or 0) + 1

    if EbonBuilds.StatsView and EbonBuilds.StatsView.OnSessionAnalyticsChanged then
        EbonBuilds.StatsView.OnSessionAnalyticsChanged(build and build.id or nil)
    end
    return true
end

local function IsSelectionAction(action)
    action = tostring(action or "")
    return action:find("^Select") ~= nil or action:find("^Manual") ~= nil
end

local function RecordedSelectionCount(session)
    if not session then return 0 end

    -- Older sessions may carry a stale selectionCount (for example 2) while the
    -- log already contains dozens of finalized selections. Never return early
    -- from the saved value; use the greatest trustworthy progress signal.
    local explicit = math.max(0, tonumber(session.selectionCount) or 0)
    local highestPick, rawCount = 0, 0
    for _, entry in ipairs(session.logs or {}) do
        if IsSelectionAction(entry.action) then
            local pickIndex = tonumber(entry.pickIndex)
            if pickIndex and pickIndex > highestPick then highestPick = pickIndex end
            rawCount = rawCount + 1
        end
    end

    return math.min(MAX_RUN_SELECTIONS, math.max(explicit, highestPick, rawCount))
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Session.EndCurrentSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return end

    local session = EbonBuildsDB.sessions[idx]
    if not session then
        EbonBuildsDB.currentSessionIndex = nil
        return
    end

    session.endTime   = time()
    session.soulAshes = GetRunSoulAshes()
    local recordedSelections = RecordedSelectionCount(session)
    session.selectionCount = recordedSelections
    session.maxLevel = math.min(80, recordedSelections + 1)

    local completed = session.picksCompleted == true
        or session.completionReason == "all_picks_complete"
        or recordedSelections >= MAX_RUN_SELECTIONS
    session.completed = completed
    session.completionReason = completed and "all_picks_complete" or "interrupted"
    if completed and not session.completionTime then session.completionTime = session.endTime end

    -- Per-build run counters for the Stats tab (were never written before).
    local build = session.buildId and EbonBuilds.Build.Get(session.buildId) or nil
    if build and build.stats then
        if completed then
            build.stats.runsCompleted = (build.stats.runsCompleted or 0) + 1
        else
            build.stats.runsReset = (build.stats.runsReset or 0) + 1
        end
        if completed and not session.mixedStrategy
            and (tonumber(build.strategyRevision) or 1) == (tonumber(session.strategyRevision) or 1) then
            build.validated = true -- legacy field: a completed local run exists for this strategy revision
        end
    end

    if EbonBuilds.Aggregates then EbonBuilds.Aggregates.OnRunEnded(session) end

    EbonBuildsDB.currentSessionIndex = nil
    maxLevel = 0
    if EbonBuilds.Database then EbonBuilds.Database.SchedulePrune() end
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_ENDED", session.id, session.buildId) end
    NotifyHistoryChanged()
end

function EbonBuilds.Session.MarkStrategyChanged(build, oldHash, newHash)
    local session = EbonBuilds.Session.GetActiveSession()
    if not session or not build or session.buildId ~= build.id or #(session.logs or {}) == 0 then return false end
    if oldHash == newHash then return false end
    session.mixedStrategy = true
    session.strategyChanges = session.strategyChanges or {}
    session.strategyChanges[#session.strategyChanges + 1] = {
        timestamp = time(),
        fromHash = oldHash,
        toHash = newHash,
        toRevision = tonumber(build.strategyRevision) or 1,
    }
    session.analyticsRevision = (tonumber(session.analyticsRevision) or 0) + 1
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_STRATEGY_CHANGED", session.id, build.id) end
    return true
end

function EbonBuilds.Session.LogAction(scored, action, targetIndex, source)
    -- Detect run reset: player is level 1 but we tracked a higher peak.
    -- This catches resets that happen without a loading screen where
    -- PLAYER_ENTERING_WORLD never fires.
    local level = UnitLevel("player")
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
    end

    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then
        -- No active session yet: create one on the fly so logs are never lost
        CreateSession()
        idx = EbonBuildsDB.currentSessionIndex
        if not idx then return end
    end

    local session = EbonBuildsDB.sessions[idx]
    if not session then return end

    local selectionAction = IsSelectionAction(action)
    local priorSelectionCount = RecordedSelectionCount(session)
    local pickIndex = selectionAction and math.min(MAX_RUN_SELECTIONS, priorSelectionCount + 1) or nil
    local runLevel = math.min(80, priorSelectionCount + (selectionAction and 1 or 0) + 1)

    local build = EbonBuilds.Build.GetActive()
    local settings = build and build.settings or EbonBuilds.Build.DefaultSettings()
    local choices = {}
    for _, s in ipairs(scored) do
        local baseWeight = s.spellId and EbonBuilds.Weights.GetForSpell(build, s.spellId, s.quality) or 0
        choices[#choices + 1] = {
            index         = s.index,
            name          = s.name,
            score         = s.score,
            quality       = s.quality,
            spellId       = s.spellId,
            baseWeight    = baseWeight,
            policy        = s.policy ~= "normal" and s.policy or nil,
            policyEffect  = s.policyEffect ~= "normal" and s.policyEffect or nil,
            -- Keep the eligibility verdict with the decision evidence.  The
            -- Logbook cannot safely reconstruct these build/run-specific
            -- flags later, after the active build or selected Echoes change.
            isBanned      = s.isBanned and true or nil,
        }
    end

    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end

    local charges = {
        ban    = (rd and rd.remainingBanishes) or 0,
        reroll = (rd and ((rd.totalRerolls or 0) - (rd.usedRerolls or 0))) or 0,
        freeze = (rd and ((rd.totalFreezes or 0) - (rd.usedFreezes or 0))) or 0,
    }

    local decision = DecisionMetadata(action, settings, build, source)
    local policyTarget = choices[targetIndex or 0]
    if policyTarget and policyTarget.policyEffect == "banish" and tostring(action or ""):find("^Banish") then
        decision.reasonCode = "ECHO_POLICY_BANISH"
        decision.policy = policyTarget.policy
        decision.threshold = nil
    elseif policyTarget and policyTarget.isBanned and tostring(action or ""):find("^Banish") then
        decision.reasonCode = "ECHO_BAN_LIST"
        decision.threshold = nil
    elseif policyTarget and policyTarget.policy and policyTarget.policy ~= "normal" then
        decision.policy = policyTarget.policy
    end
    local sortedScores = {}
    for _, choice in ipairs(choices) do sortedScores[#sortedScores + 1] = tonumber(choice.score) or 0 end
    table.sort(sortedScores, function(a, b) return a > b end)
    local target = choices[targetIndex or 0]
    local maxBase, targetBase = nil, target and (target.baseWeight or 0) or nil
    for _, choice in ipairs(choices) do
        local base = tonumber(choice.baseWeight) or 0
        if maxBase == nil or base > maxBase then maxBase = base end
    end
    local normalizedAction = tostring(action or "")
    local chargeKey = normalizedAction:find("^Banish") and "ban" or normalizedAction:find("^Reroll") and "reroll" or normalizedAction:find("^Freeze") and "freeze" or nil
    decision.flags = {}
    if #sortedScores >= 2 and math.abs(sortedScores[1] - sortedScores[2]) <= 3 then decision.flags.closeDecision = true end
    if chargeKey and (charges[chargeKey] or 0) <= 1 then decision.flags.lastCharge = true end
    if targetBase ~= nil and maxBase ~= nil and targetBase < maxBase and target
        and (target.score or 0) >= sortedScores[1] then decision.flags.modifierOverride = true end
    if source == "manual" and target and sortedScores[1]
        and (tonumber(target.score) or 0) < sortedScores[1] then decision.flags.manualDisagreement = true end
    if next(decision.flags) == nil then decision.flags = nil end

    local entry = {
        timestamp   = time(),
        level       = runLevel,
        pickIndex   = pickIndex,
        action      = action,
        choices     = choices,
        targetIndex = targetIndex,
        charges     = charges,
        decision    = decision,
        eligibilitySchema = 1,
    }

    session.logs[#session.logs + 1] = entry
    if selectionAction then
        session.selectionCount = pickIndex
        session.maxLevel = runLevel
        if pickIndex >= MAX_RUN_SELECTIONS then
            session.picksCompleted = true
            session.completed = true
            session.completionReason = "all_picks_complete"
            session.completionTime = entry.timestamp
        end
    end
    session.analyticsRevision = (tonumber(session.analyticsRevision) or 0) + 1
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_EVENT_RECORDED", session.id, build and build.id or nil) end
    if EbonBuilds.StatsView and EbonBuilds.StatsView.OnSessionAnalyticsChanged then
        EbonBuilds.StatsView.OnSessionAnalyticsChanged(build and build.id or nil)
    end
    NotifyHistoryChanged()
end

function EbonBuilds.Session.GetSessions()
    return EbonBuildsDB.sessions or {}
end

function EbonBuilds.Session.GetActiveSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return nil end
    return EbonBuildsDB.sessions[idx]
end

function EbonBuilds.Session.DeleteSession(id)
    -- Refuse to delete the active session individually
    if EbonBuildsDB.currentSessionIndex then
        local active = EbonBuildsDB.sessions[EbonBuildsDB.currentSessionIndex]
        if active and active.id == id then
            return false
        end
    end

    local sessions = EbonBuildsDB.sessions
    for i, s in ipairs(sessions) do
        if s.id == id then
            if EbonBuildsDB.currentSessionIndex and i < EbonBuildsDB.currentSessionIndex then
                EbonBuildsDB.currentSessionIndex = EbonBuildsDB.currentSessionIndex - 1
            end
            table.remove(sessions, i)
            NotifyHistoryChanged()
            return true
        end
    end
    return false
end

-- Test/integration helpers. These are pure and do not mutate saved data.
EbonBuilds.Session._CountEpicChoices = CountEpicChoices
EbonBuilds.Session._EarlyOfferMaxLevel = EARLY_OFFER_MAX_LEVEL
EbonBuilds.Session._RecordedSelectionCount = RecordedSelectionCount

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.Session.Init()
    -- Ensure DB arrays exist
    EbonBuildsDB.sessions = EbonBuildsDB.sessions or {}
    if EbonBuildsDB.currentSessionIndex == nil then
        EbonBuildsDB.currentSessionIndex = nil  -- normalize falsey
    end

    EbonBuilds.WoWEvents.On("PLAYER_ENTERING_WORLD", function()
        OnPlayerEnteringWorld()
    end, "Session")
    EbonBuilds.WoWEvents.On("PLAYER_LEVEL_UP", function(_, ...)
        OnPlayerLevelUp(...)
    end, "Session")

    -- Shared scheduler polling for reset detection without a loading screen.
    EbonBuilds.Scheduler.Every("session.levelReset", POLL_INTERVAL, PollLevel,
        EbonBuilds.Scheduler.BACKGROUND, true)
end
