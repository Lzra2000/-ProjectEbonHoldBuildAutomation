local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/Automation.lua
-- Responsibility: evaluate offered echo choices against the active build's
-- automation thresholds and execute the optimal action (banish -> reroll ->
-- freeze -> select). Secure post-hooks suppress the native choice surface only
-- while Autopilot owns the board and restore it on every fallback path.

EbonBuilds.Automation = {}

local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local function GetEvalDelay()
    return (EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.evalDelay) or 2
end

local pendingChoices    = nil
local trainingNoticeShown = false -- once-per-session Manual Training notice (see the eval timer)
local hookInstalled       = false
local freezeRoundActive    = false  -- true after freeze batch, cleared on select
local locallyFrozenIndices = {}     -- indices frozen this round, for penalty tracking
local cachedPeak           = nil    -- locked at first evaluation of the run
local lastNoActionReason    = nil

------------------------------------------------------------------------
-- Native ProjectEbonhold choice-surface guard
------------------------------------------------------------------------

-- The native ProjectEbonhold choice UI can expose either its compact entry
-- button or its hide/show button depending on the installed build.  Treat the
-- whole surface as one unit instead of relying on one label or one frame name.
-- This guard is presentation-only: it never decides whether automation may
-- run and it never waits for an action acknowledgement.
local nativeChoiceSuppressed = false
local nativeFallbackInProgress = false
local guardedNativeButtons = {}
local REQUEST_FALLBACK_ID = "automation.requestFallback"
local REQUEST_FALLBACK_DELAY = 6
local REPLACEMENT_RESET_CLEAR_ID = "automation.replacementResetClear"
local replacementResetPending = false

local function GetNativeFrame(name)
    local frame = _G and _G[name]
    if not frame or type(frame.Hide) ~= "function" then return nil end
    return frame
end

local function IsNativeEchoTooltipOwner(owner)
    if not owner then return false end
    local chooseButton = GetNativeFrame("PerkChooseButton")
    local hideButton = GetNativeFrame("PerkHideButton")
    local root = GetNativeFrame("ProjectEbonholdPerkFrame")
    local current = owner
    for _ = 1, 10 do
        if current == chooseButton or current == hideButton or current == root then return true end
        if type(current.GetParent) ~= "function" then break end
        local ok, parent = pcall(current.GetParent, current)
        if not ok or not parent or parent == current then break end
        current = parent
    end
    return false
end

local function HideNativeEchoTooltip()
    local tooltip = _G and _G.GameTooltip
    if not tooltip or type(tooltip.Hide) ~= "function" then return end
    local owner
    if type(tooltip.GetOwner) == "function" then
        local ok, value = pcall(tooltip.GetOwner, tooltip)
        if ok then owner = value end
    end
    if IsNativeEchoTooltipOwner(owner) then tooltip:Hide() end
end

local function HasCurrentChoice()
    local api = EbonBuilds.ProjectAPI
    local choices = api and type(api.GetCurrentChoice) == "function" and api.GetCurrentChoice() or nil
    return type(choices) == "table" and #choices > 0
end

local function ShouldSuppressNativeChoice()
    if nativeFallbackInProgress then return false end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive() or nil
    if not build or not EbonBuilds.Build.IsAutomationEnabled(build) then return false end
    if EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build) then return false end
    return true
end

local function HideNativeFrame(frame)
    if not frame then return end
    if type(frame.EnableMouse) == "function" then frame:EnableMouse(false) end
    frame:Hide()
end

local function InstallNativeButtonGuard(frame)
    if not frame or guardedNativeButtons[frame] then return end
    guardedNativeButtons[frame] = true
    local function OnNativeButtonShown(self)
        if nativeChoiceSuppressed and ShouldSuppressNativeChoice() then
            HideNativeFrame(self)
            HideNativeEchoTooltip()
        end
    end
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", OnNativeButtonShown)
    elseif type(hooksecurefunc) == "function" and type(frame.Show) == "function" then
        hooksecurefunc(frame, "Show", OnNativeButtonShown)
    end
end

local function SuppressNativeChoiceSurface()
    if not ShouldSuppressNativeChoice() then return false end
    nativeChoiceSuppressed = true

    local chooseButton = GetNativeFrame("PerkChooseButton")
    local hideButton = GetNativeFrame("PerkHideButton")
    local root = GetNativeFrame("ProjectEbonholdPerkFrame")
    InstallNativeButtonGuard(chooseButton)
    InstallNativeButtonGuard(hideButton)
    HideNativeFrame(chooseButton)
    HideNativeFrame(hideButton)

    -- The root can stay allocated, but hiding it guarantees that card mouse
    -- regions and stale tooltips cannot remain reachable below the Autopilot
    -- banner. ProjectEbonhold rebuilds it normally for a manual fallback.
    if root and type(root.Hide) == "function" then root:Hide() end
    HideNativeEchoTooltip()
    return true
end

local function ShowNativeChoiceFallback()
    nativeChoiceSuppressed = false
    local choices = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCurrentChoice
        and EbonBuilds.ProjectAPI.GetCurrentChoice() or nil
    local ui = ProjectEbonhold and ProjectEbonhold.PerkUI
    if type(choices) ~= "table" or #choices == 0 or not ui or type(ui.Show) ~= "function" then
        return false
    end

    -- Use ProjectEbonhold's own renderer so the correct button/card variant is
    -- restored even when a server build uses a different label or frame.
    nativeFallbackInProgress = true
    local ok, err = pcall(ui.Show, choices)
    nativeFallbackInProgress = false
    if not ok then
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("Automation.NativeFallback", err)
        end
        return false
    end

    local chooseButton = GetNativeFrame("PerkChooseButton")
    local hideButton = GetNativeFrame("PerkHideButton")
    if chooseButton and type(chooseButton.EnableMouse) == "function" then chooseButton:EnableMouse(true) end
    if hideButton and type(hideButton.EnableMouse) == "function" then hideButton:EnableMouse(true) end
    return true
end

local function RefreshNativeChoiceGuard()
    if not HasCurrentChoice() then
        nativeChoiceSuppressed = false
        HideNativeEchoTooltip()
        return
    end
    if ShouldSuppressNativeChoice() then
        SuppressNativeChoiceSurface()
    else
        ShowNativeChoiceFallback()
    end
end

local function CancelRequestFallback()
    if EbonBuilds.Scheduler then EbonBuilds.Scheduler.Cancel(REQUEST_FALLBACK_ID) end
end

local function ClearReplacementResetPending()
    replacementResetPending = false
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.Cancel(REPLACEMENT_RESET_CLEAR_ID)
    end
end

local function ExpectReplacementReset()
    replacementResetPending = true
    if not EbonBuilds.Scheduler then return end

    -- ProjectEbonhold currently calls ResetSelection immediately after a
    -- successful banish replacement. Keep the marker narrowly scoped so an
    -- unrelated later reset can never be mistaken for that success path.
    EbonBuilds.Scheduler.After(REPLACEMENT_RESET_CLEAR_ID, 0.50, function()
        replacementResetPending = false
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "Automation")
end

local function ArmRequestFallback()
    if not EbonBuilds.Scheduler then return end
    EbonBuilds.Scheduler.After(REQUEST_FALLBACK_ID, REQUEST_FALLBACK_DELAY, function()
        if HasCurrentChoice() and ShouldSuppressNativeChoice() then
            ShowNativeChoiceFallback()
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                EbonBuilds.Toast.Show("Autopilot request is still pending -- native Echo controls restored")
            end
        end
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "Automation")
end

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function StartEvalTimer()
    RefreshNativeChoiceGuard()
    EbonBuilds.Scheduler.After("automation.evaluate", GetEvalDelay(), function()
        local build = EbonBuilds.Build.GetActive()
        local wasActive = build and EbonBuilds.Build.IsAutomationEnabled(build)
        local isTraining = build and EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build)
        if EbonBuilds.Automation.Evaluate() then
            pendingChoices = nil
            lastNoActionReason = nil
            return
        end

        -- No request was accepted. Rebuild the native choice surface through
        -- ProjectEbonhold itself so the player always has a working fallback.
        CancelRequestFallback()
        ShowNativeChoiceFallback()
        if pendingChoices then
            if wasActive and isTraining then
                if not trainingNoticeShown then
                    trainingNoticeShown = true
                    EbonBuilds.Toast.Show("Automation paused: Manual Training is ON for this build (its toggle on the build overview turns it off)")
                end
            elseif wasActive and lastNoActionReason then
                EbonBuilds.Toast.Show(lastNoActionReason)
            end
        end
        pendingChoices = nil
        lastNoActionReason = nil
    end, EbonBuilds.Scheduler.CRITICAL, true, "Automation")
end

-- Returns the cached peak (computed at first evaluation of the current run).
-- The peak includes novelty and is locked for the duration of the run so
-- threshold percentages remain stable.
function EbonBuilds.Automation.GetPeak()
    if cachedPeak then return cachedPeak end
    local build = EbonBuilds.Build.GetActive()
    if not build then return 1 end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local _, score = EbonBuilds.Scoring.ComputePeak(build.class, settings)
    cachedPeak = (score and score > 0) and score or 1
    return cachedPeak
end

-- Cached expected value of the best of 3 random offers ("smart reroll"
-- reference). Same lifetime as the peak: reset on new run, build switch,
-- and build save.
local cachedStats = nil   -- { mean, evBest3 }

function EbonBuilds.Automation.GetOutcomeStats()
    if cachedStats then return cachedStats end
    local build = EbonBuilds.Build.GetActive()
    if not build then return { mean = 0, evBest3 = 0 } end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    cachedStats = EbonBuilds.Scoring.ComputeOutcomeStats(build.class, settings)
    return cachedStats
end

function EbonBuilds.Automation.GetRerollEV()
    return EbonBuilds.Automation.GetOutcomeStats().evBest3
end

function EbonBuilds.Automation.ResetPeakCache()
    cachedPeak = nil
    cachedStats = nil
end

-- Shared charge-based pacing: scales a threshold based on how many
-- charges of a resource (Banish/Reroll/Freeze) remain, so each lever gets
-- progressively more conservative as ITS OWN budget runs low, instead of
-- spending it however a static threshold happens to fire early and
-- having none left when a truly good/bad echo shows up late in the run.
--
-- direction "below" (Banish, Reroll -- these trigger when a score is
-- UNDER the threshold): pacing shrinks from 1.0 (full charges) toward
-- conservativeScale (<1, at 0 charges) as charges deplete, making the
-- threshold stricter (harder to trigger) when charges are scarce.
-- direction "above" (Freeze -- triggers when a score is OVER the
-- threshold): pacing grows from 1.0 toward conservativeScale (>1, at 0
-- charges), same effect (harder to trigger) via the opposite curve shape.
--
-- cap is an absolute "comfortable" charge count, not a fraction of the
-- run's starting total -- deliberately: having 8 rerolls left feels the
-- same whether the run started with 18 or 30, so charges beyond the cap
-- don't make the addon any more aggressive.
local function ChargePacing(remaining, cap, conservativeScale, direction)
    cap = cap or 8
    local ratio = math.min(math.max(remaining or 0, 0), cap) / cap
    if direction == "above" then
        return conservativeScale - (conservativeScale - 1) * ratio
    else
        return conservativeScale + (1 - conservativeScale) * ratio
    end
end

local function GetRunData()
    if EbonholdPlayerRunData and EbonholdPlayerRunData.remainingBanishes ~= nil then
        return EbonholdPlayerRunData
    end
    if ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then return get() end
    end
    return nil
end

local function ScoreChoice(choice, settings)
    local spellId = tonumber(choice and choice.spellId)
    if not spellId then return nil end
    local build = EbonBuilds.Build.GetActive()
    if not build or not EbonBuilds.EchoProjection then return nil end
    local definition, variant = EbonBuilds.EchoProjection.ResolveOfferedSpell(build.class, spellId)
    if not definition or not variant then return nil end

    local raw = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId] or nil
    local name = definition.displayName or definition.canonicalName or definition.sourceName or tostring(spellId)
    local quality = tonumber(choice.quality) or tonumber(variant.quality) or 0
    local entry = {
        refKey = definition.refKey,
        spellId = spellId,
        name = name,
        quality = quality,
        families = variant.families or definition.families,
    }
    local weight = EbonBuilds.Weights.GetForSpell(build, spellId, quality) or 0

    -- Exact-spell evidence avoids merging same-name Echoes such as Crimson
    -- Reprisal and Blood Mirror. Fall back to ProjectEbonhold's name map only
    -- for older server builds that have not synchronized discovery data.
    local evidenceFlags = EbonBuilds.EchoEligibilityEvidence
        and EbonBuilds.EchoEligibilityEvidence.GetFlags(build.class, spellId) or 0
    local discoveredFlag = EbonBuilds.EchoEligibilityEvidence
        and EbonBuilds.EchoEligibilityEvidence.FLAG_DISCOVERED or 0
    local grantedFlag = EbonBuilds.EchoEligibilityEvidence
        and EbonBuilds.EchoEligibilityEvidence.FLAG_GRANTED or 0
    local isNovel = bit.band(evidenceFlags, bit.bor(discoveredFlag, grantedFlag)) == 0
    if isNovel and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks then
        local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
        local runtimeName = GetSpellInfo(spellId)
        if granted and (granted[name] or (runtimeName and granted[runtimeName])) then isNovel = false end
    end

    local score
    if isNovel then
        score = EbonBuilds.Scoring.Score(entry, weight, settings)
    else
        score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
    end
    if (choice.isFrozen or choice.isCarried) and settings.freezePenaltyPct and settings.freezePenaltyPct > 0 then
        score = score * (1 - settings.freezePenaltyPct / 100)
    end
    return {
        index = 0, spellId = spellId, name = name, quality = quality,
        score = score, entry = entry, data = raw or variant,
        isFrozen = choice.isFrozen, isCarried = choice.isCarried,
    }
end

local function NormFamily(f) return FAMILY_MAP[f] end

local function IsFamilyProtected(data, whitelist)
    if not whitelist or next(whitelist) == nil then return false end
    local families = data.families
    if not families or #families == 0 then
        return whitelist["No family"] or false
    end
    for _, fam in ipairs(families) do
        local key = NormFamily(fam) or fam
        if whitelist[key] then return true end
    end
    return false
end

local function ScoreLockedEcho(lockedId, settings)
    lockedId = tonumber(lockedId)
    local build = EbonBuilds.Build.GetActive()
    if not lockedId or not build or not EbonBuilds.EchoProjection then return 0 end
    local definition, variant = EbonBuilds.EchoProjection.ResolveSpell(build.class, lockedId)
    if not definition or not variant then return 0 end
    local quality = tonumber(variant.quality) or 0
    local entry = {
        refKey = definition.refKey,
        spellId = lockedId,
        name = definition.displayName or definition.canonicalName or definition.sourceName,
        quality = quality,
        families = variant.families or definition.families,
    }
    local weight = EbonBuilds.Weights.GetForSpell(build, lockedId, quality) or 0
    return EbonBuilds.Scoring.Score(entry, weight, settings)
end

local function UpdateStat(build, key)
    if build and build.stats then
        build.stats[key] = (build.stats[key] or 0) + 1
    end
end

-- Detailed pick bookkeeping for the Stats tab: per-quality pick counts and
-- a name -> count map for "Most picked". (These fields were initialized in
-- EnsureStats but never written before.)
local function RecordPick(build, s)
    UpdateStat(build, "picks")
    if not (build and build.stats and s) then return end
    local st = build.stats
    st.qualityPicks = st.qualityPicks or {}
    local q = s.quality or 0
    st.qualityPicks[q] = (st.qualityPicks[q] or 0) + 1
    if s.name then
        st.mostPicked = st.mostPicked or {}
        st.mostPicked[s.name] = (st.mostPicked[s.name] or 0) + 1
    end
end

local function RecordBanish(build, s)
    UpdateStat(build, "banishesUsed")
    if not (build and build.stats and s and s.name) then return end
    local st = build.stats
    st.mostBanned = st.mostBanned or {}
    st.mostBanned[s.name] = (st.mostBanned[s.name] or 0) + 1
end

local function LogAndToast(scored, action, targetIndex)
    EbonBuilds.Toast.ShowAutomationResult(scored, action, targetIndex)
    EbonBuilds.Session.LogAction(scored, action, targetIndex)
end

local function CommitDecision(decision)
    if not decision then return end
    local action = decision.action
    if action == "select" then
        RecordPick(decision.build, decision.entry)
        locallyFrozenIndices = {}
        freezeRoundActive = false
    elseif action == "banish" then
        RecordBanish(decision.build, decision.entry)
    elseif action == "reroll" then
        UpdateStat(decision.build, "rerollsUsed")
    elseif action == "freeze" then
        UpdateStat(decision.build, "freezesUsed")
        locallyFrozenIndices[decision.targetIndex] = true
        freezeRoundActive = true
        local runData = GetRunData()
        if runData and runData.usedFreezes ~= nil then
            runData.usedFreezes = runData.usedFreezes + 1
        end
    end

    LogAndToast(decision.scored, decision.displayAction, decision.targetIndex or 0)
    if action == "freeze" then StartEvalTimer() end
end

local function SubmitAction(action, build, scored, targetIndex, entry, displayAction)
    local api = EbonBuilds.ProjectAPI
    if not api then return false end

    local accepted
    if action == "select" then
        accepted = api.RequestSelect(entry and entry.spellId)
    elseif action == "banish" then
        accepted = api.RequestBanish((targetIndex or 1) - 1)
    elseif action == "reroll" then
        accepted = api.RequestReroll()
    elseif action == "freeze" then
        accepted = api.RequestFreeze((targetIndex or 1) - 1)
    end
    if not accepted then return false end

    -- ProjectEbonhold's public service return value means the request was
    -- accepted locally and sent. Do not hold the automation engine behind a
    -- speculative acknowledgement watcher: older server builds expose no
    -- reliable multi-listener result API, and a missed transition would block
    -- every later level-up. Native service pending flags still prevent duplicate
    -- requests, while the watchdog below restores manual controls if the server
    -- never advances the board.
    CommitDecision({
        action = action,
        build = build,
        scored = scored,
        targetIndex = targetIndex or 0,
        entry = entry,
        displayAction = displayAction or action,
    })
    ArmRequestFallback()
    return true
end

------------------------------------------------------------------------
-- Action attempts (called in priority order)
------------------------------------------------------------------------

local function IsActionable(s)
    return s and not s.isFrozen and not s.isCarried and not locallyFrozenIndices[s.index] and not s.policyBlocked
end

local function TrySelect(scored, settings, build)
    local nonBanned, eligible = {}, {}
    for _, s in ipairs(scored) do
        -- Conditional policies are hard selection rules. Unlike the legacy
        -- ban list, they are never violated merely because every card happens
        -- to be blocked on the current board.
        if not locallyFrozenIndices[s.index] and not s.policyBlocked then
            eligible[#eligible + 1] = s
            if not EbonBuilds.Scoring.IsBanned(s.spellId, settings) then
                nonBanned[#nonBanned + 1] = s
            end
        end
    end
    -- Preserve the old freeze safety fallback only for locally frozen cards;
    -- policy-blocked cards remain excluded.
    if #eligible == 0 then
        local anyPolicyBlocked = false
        for _, s in ipairs(scored) do
            if s.policyBlocked then
                anyPolicyBlocked = true
            else
                eligible[#eligible + 1] = s
                if not EbonBuilds.Scoring.IsBanned(s.spellId, settings) then nonBanned[#nonBanned + 1] = s end
            end
        end
        if anyPolicyBlocked and #eligible == 0 then return false, nil, "policy_blocked" end
    end
    local candidates = #nonBanned > 0 and nonBanned or eligible
    if #candidates == 0 then return false, nil end

    table.sort(candidates, function(a, b) return a.score > b.score end)

    local pick
    if #nonBanned == 0 and settings.echoBanAllMode == "random" then
        pick = candidates[math.random(1, #candidates)]
    else
        pick = candidates[1]
    end

    if SubmitAction("select", build, scored, pick.index, pick, "Select") then
        return true, pick
    end
    return false, nil
end

local function AnnotateScored(scored, settings, lockedList, selectedNames)
    local familyWhitelist = settings.banishFamilyWhitelist or {}
    local policyApi = EbonBuilds.EchoPolicy
    for _, s in ipairs(scored) do
        s.isWhitelisted = EbonBuilds.Scoring.IsWhitelisted(s.spellId, settings)
        s.isBanned      = EbonBuilds.Scoring.IsBanned(s.spellId, settings)
        s.isProtected   = s.isWhitelisted or IsFamilyProtected(s.data, familyWhitelist)
        if policyApi then
            s.policy = policyApi.Get(settings, s.spellId)
            s.policySelected = policyApi.IsSelected(s.spellId, selectedNames)
            s.policyEffect = policyApi.Resolve(s.policy, s.policySelected)
            s.policyBlocked = s.policyEffect == "banish" or s.policyEffect == "exclude"
        end
        s.isLocked      = false
        for _, lockedId in ipairs(lockedList) do
            if lockedId and lockedId == s.spellId then
                s.isLocked = true
                break
            end
        end
    end
end

------------------------------------------------------------------------
-- Main evaluation entry point
------------------------------------------------------------------------

local function RecordAppearanceChoices(choices)
    if not (EbonBuilds.Calibration and EbonBuilds.Calibration.RecordAppearance) then return end
    EbonBuilds.Calibration.RecordEvaluation()
    local appeared = {}
    for _, choice in ipairs(choices or {}) do
        local appearanceName = choice.spellId and EbonBuilds.Weights.CanonicalName(choice.spellId)
            or choice.name
        if appearanceName and not appeared[appearanceName] then
            appeared[appearanceName] = true
            EbonBuilds.Calibration.RecordAppearance(appearanceName)
        end
    end
end

local evalInProgress = false

function EbonBuilds.Automation.Evaluate()
    if evalInProgress then return false end
    evalInProgress = true

    local function body()
        lastNoActionReason = nil
        local build = EbonBuilds.Build.GetActive()
        if not build then return false end

        local choices = ProjectEbonhold.PerkService.GetCurrentChoice()
        if not choices or #choices == 0 then return false end

        -- First-offer analytics must run before every opt-out and before any
        -- action mutates the board. Session.RecordInitialOffer writes once per
        -- level, so repeated evaluations, rerolls, and banish replacements do
        -- not inflate the Level 1-3 Epic statistics.
        if EbonBuilds.Session and EbonBuilds.Session.RecordInitialOffer then
            EbonBuilds.Session.RecordInitialOffer(choices)
        end

        -- Appearance frequency is useful even while the player is choosing
        -- manually, so record the offer before either opt-out path below.
        RecordAppearanceChoices(choices)

        -- Manual Training Mode is independent of Autopilot. When enabled,
        -- EbonBuilds observes the native manual pick but never acts.
        if EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build) then return false end
        if not EbonBuilds.Build.IsAutomationEnabled(build) then return false end

        local settings   = EbonBuilds.Scoring.GetEffectiveSettings()
        local runData    = GetRunData()
        local lockedList = build.lockedEchoes or {}

        local peakScore = EbonBuilds.Automation.GetPeak()

        -- Score all offered choices
        local scored = {}
        for i, choice in ipairs(choices) do
            local s = ScoreChoice(choice, settings)
            if s then
                s.index = i -- 1-based
                scored[#scored + 1] = s
            end
        end
        if #scored == 0 then return false end

        -- Feed the Tuning Advisor: what does this build actually get
        -- offered, in practice? Cheap append, no analysis happens here.
        if peakScore and peakScore > 0 and EbonBuilds.Calibration then
            for _, s in ipairs(scored) do
                if s.score then
                    EbonBuilds.Calibration.RecordSample(s.score / peakScore * 100)
                end
            end
            -- Opt-in, rate-limited: only actually does anything once every
            -- TUNE_INTERVAL_SAMPLES calls, and only if the player enabled
            -- continuous auto-tune in the Tuning Advisor window.
            EbonBuilds.Calibration.MaybeAutoTune()
        end

        local selectedNames = EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.SelectedNames() or {}
        AnnotateScored(scored, settings, lockedList, selectedNames)

        if EbonBuilds.DebugLog.IsEnabled() then
            local banishRemainingDbg = (runData and runData.remainingBanishes) or 0
            local rerollRemainingDbg = (runData and ((runData.totalRerolls or 0) - (runData.usedRerolls or 0))) or 0
            local freezeRemainingDbg = (runData and ((runData.totalFreezes or 0) - (runData.usedFreezes or 0))) or 0
            local banishPacingDbg = ChargePacing(banishRemainingDbg, 8, 0.7, "below")
            local rerollPacingDbg = ChargePacing(rerollRemainingDbg, 8, 0.6, "below")
            local freezePacingDbg = ChargePacing(freezeRemainingDbg, 6, 1.4, "above")
            local isSmartDbg = (settings.rerollMode or "sum") == "ev"

            local hdrBanish, hdrFreeze, hdrReroll, hdrMode
            if isSmartDbg then
                local st = EbonBuilds.Automation.GetOutcomeStats()
                hdrMode   = "SMART"
                hdrBanish = math.floor(st.mean * (settings.banishEVPct or 60) / 100 * banishPacingDbg)
                hdrFreeze = math.floor(st.evBest3 * (settings.freezeEVPct or 110) / 100 * freezePacingDbg)
                hdrReroll = math.floor(EbonBuilds.Automation.GetRerollEV() * (settings.rerollEVPct or 95) / 100 * rerollPacingDbg)
            else
                hdrMode   = "CLASSIC"
                hdrBanish = math.floor(peakScore * (settings.autoBanishPct or 0) / 100 * banishPacingDbg)
                hdrFreeze = math.floor(peakScore * (settings.autoFreezePct or 0) / 100 * freezePacingDbg)
                hdrReroll = math.floor(peakScore * (settings.autoRerollPct or 0) / 100 * rerollPacingDbg)
            end
            -- Reroll Guard is only ever checked in Classic mode's reroll
            -- logic (Smart mode compares "best offered" directly, so the
            -- same protection is already implicit) -- showing a guard
            -- value in Smart mode's header would be pure dead information
            -- that could mislead debugging ("why didn't guard block that
            -- reroll" when it was never evaluated for this mode at all).
            if isSmartDbg then
                EbonBuilds.DebugLog.AddF("=== EVAL [%s] peak=%d | banish<%d (pace %.2f) reroll<%d (pace %.2f) freeze>%d (pace %.2f) | charges B:%d R:%d F:%d",
                    hdrMode, peakScore,
                    hdrBanish, banishPacingDbg,
                    hdrReroll, rerollPacingDbg,
                    hdrFreeze, freezePacingDbg,
                    banishRemainingDbg, rerollRemainingDbg, freezeRemainingDbg)
            else
                local hdrGuard = math.floor(peakScore * (settings.rerollGuardPct or 90) / 100 * rerollPacingDbg)
                EbonBuilds.DebugLog.AddF("=== EVAL [%s] peak=%d | banish<%d (pace %.2f) reroll<%d (pace %.2f) guard>=%d (pace %.2f) freeze>%d (pace %.2f) | charges B:%d R:%d F:%d",
                    hdrMode, peakScore,
                    hdrBanish, banishPacingDbg,
                    hdrReroll, rerollPacingDbg,
                    hdrGuard, rerollPacingDbg,
                    hdrFreeze, freezePacingDbg,
                    banishRemainingDbg, rerollRemainingDbg, freezeRemainingDbg)
            end
            for _, s in ipairs(scored) do
                EbonBuilds.DebugLog.AddF("  [%d] %s q=%d score=%.0f w=%d%s%s%s",
                    s.index, s.name, s.quality or 0, s.score or 0,
                    EbonBuilds.Weights.GetForSpell(build, s.spellId, s.quality) or 0,
                    s.isFrozen and " FROZEN" or "",
                    s.isCarried and " CARRIED" or "",
                    locallyFrozenIndices[s.index] and " localFrozen" or "")
                if s.policy and s.policy ~= "normal" then
                    EbonBuilds.DebugLog.AddF("      policy=%s selected=%s effect=%s", s.policy, tostring(s.policySelected), tostring(s.policyEffect))
                end
            end
        end

        -- PRE-CHECK: if any offered echo matches a locked echo slot, select it
        for _, s in ipairs(scored) do
            for _, lockedId in ipairs(lockedList) do
                if lockedId and lockedId == s.spellId and not s.policyBlocked then
                    if SubmitAction("select", build, scored, s.index, s, "Select (Locked)") then
                        EbonBuilds.DebugLog.AddF("-> REQUEST SELECT locked-match [%d] %s", s.index, s.name)
                        return true
                    end
                end
            end
        end

        --------------------------------------------------------------------
        -- 1. TRY BANISH (highest action priority)
        --------------------------------------------------------------------
        if runData and (runData.remainingBanishes or 0) > 0 then
            table.sort(scored, function(a, b) return a.score < b.score end)

            -- Explicit conditional policy actions take precedence over the
            -- legacy ban list and score threshold. A per-Echo policy is more
            -- specific than family protection, so it is allowed to spend the
            -- banish even when that family is otherwise protected.
            for _, s in ipairs(scored) do
                if IsActionable(s) == false and s.policyEffect == "banish"
                    and not s.isFrozen and not s.isCarried and not locallyFrozenIndices[s.index] then
                    table.sort(scored, function(a, b) return a.index < b.index end)
                    if SubmitAction("banish", build, scored, s.index, s, "Banish") then
                        EbonBuilds.DebugLog.AddF("-> REQUEST BANISH policy [%d] %s (%s)", s.index, s.name, tostring(s.policy))
                        return true
                    end
                end
            end

            -- Ban-list echoes first (these have minimum priority)
            for _, s in ipairs(scored) do
                if IsActionable(s) and s.isBanned then
                    if not s.isProtected then
                        table.sort(scored, function(a, b) return a.index < b.index end)
                        if SubmitAction("banish", build, scored, s.index, s, "Banish") then
                            EbonBuilds.DebugLog.AddF("-> REQUEST BANISH [%d] %s (score %.0f)", s.index, s.name, s.score or 0)
                            return true
                        end
                    end
                end
            end

            -- Then echoes below the banish threshold. Smart mode: a banished
            -- card is replaced by ONE random card, so banish anything worth
            -- less than banishEVPct of an average card. Classic: % of peak.
            -- Charge pacing: only clearly-bad echoes get banished once
            -- charges run low, so the last few aren't wasted on borderline
            -- picks early and then unavailable when it matters.
            local banishRemaining = (runData and runData.remainingBanishes) or 0
            local banishPacing = ChargePacing(banishRemaining, 8, 0.7, "below")
            local threshold
            if (settings.rerollMode or "sum") == "ev" then
                threshold = EbonBuilds.Automation.GetOutcomeStats().mean * (settings.banishEVPct or 60) / 100 * banishPacing
            else
                threshold = math.floor(peakScore * settings.autoBanishPct / 100 * banishPacing)
            end
            for _, s in ipairs(scored) do
                if IsActionable(s) and s.score < threshold then
                    if not s.isProtected then
                        table.sort(scored, function(a, b) return a.index < b.index end)
                        if SubmitAction("banish", build, scored, s.index, s, "Banish") then
                            EbonBuilds.DebugLog.AddF("-> REQUEST BANISH [%d] %s (score %.0f)", s.index, s.name, s.score or 0)
                            return true
                        end
                    end
                end
            end
        end

        -- Restore original display order (left-to-right by index) after the
        -- banish step may have re-sorted by score.
        table.sort(scored, function(a, b) return a.index < b.index end)

        --------------------------------------------------------------------
        -- 2. TRY REROLL
        --------------------------------------------------------------------
        -- Never reroll while a freeze round is in flight: the reroll would
        -- waste the freeze charge just spent this screen. Freeze/select
        -- below must still run, so only this step is skipped.
        if not freezeRoundActive and runData and (runData.totalRerolls or 0) - (runData.usedRerolls or 0) > 0 then
            if (settings.rerollMode or "sum") == "ev" then
                ----------------------------------------------------------------
                -- Smart mode: reroll when the best actionable offer is worse
                -- than X% of what an average reroll's best would be worth.
                -- Frozen/carried echoes survive a reroll, so they neither
                -- count as the "current best" nor argue against rerolling.
                ----------------------------------------------------------------
                local ev = EbonBuilds.Automation.GetRerollEV()
                local best = 0
                for _, s in ipairs(scored) do
                    if IsActionable(s) then
                        if s.score > best then best = s.score end
                    end
                end
                -- Charge pacing: with plenty of rerolls be generous, with the
                -- last few be picky. Scales the effective threshold from 100%
                -- (>= 8 charges) down to 60% (1 charge left).
                local remaining = (runData.totalRerolls or 0) - (runData.usedRerolls or 0)
                local pacing = ChargePacing(remaining, 8, 0.6, "below")
                local threshold = ev * (settings.rerollEVPct or 95) / 100 * pacing
                -- Feed the Tuning Advisor: normalize out this evaluation's
                -- pacing multiplier so samples from different charge states
                -- are directly comparable (see Calibration.lua's
                -- RecordBestSample for how this gets turned into a
                -- suggestion).
                if peakScore and peakScore > 0 and pacing > 0 and EbonBuilds.Calibration then
                    EbonBuilds.Calibration.RecordBestSample((best / peakScore * 100) / pacing)
                end
                EbonBuilds.DebugLog.AddF("reroll check (EV): best=%.0f vs %.0f (EV %.0f x %d%% x pacing %.2f)",
                    best, threshold, ev, settings.rerollEVPct or 95, pacing)
                if best < threshold then
                    if SubmitAction("reroll", build, scored, 0, nil, "Reroll") then
                        EbonBuilds.DebugLog.Add("-> REQUEST REROLL (EV)")
                        return true
                    end
                end
            else
                -- Legacy sum mode.
                -- Reroll guard: skip if any single echo is above the guard threshold,
                -- regardless of the sum. Prevents rerolling when one good echo is
                -- offered alongside weak ones.
                -- Charge pacing: with plenty of rerolls left, only a near-perfect
                -- echo blocks a reroll (guard stays close to its base value);
                -- with few left, a merely-good echo blocks it too (guard
                -- threshold shrinks), since burning the last rerolls chasing a
                -- marginally better screen is the costlier mistake once there's
                -- nothing left over for whatever comes next.
                local remaining = (runData.totalRerolls or 0) - (runData.usedRerolls or 0)
                local guardPacing = ChargePacing(remaining, 8, 0.6, "below")
                local guardPct = settings.rerollGuardPct or 90
                local guardThreshold = math.floor(peakScore * guardPct / 100 * guardPacing)
                local blockedByGuard = false
                for _, s in ipairs(scored) do
                    if IsActionable(s) and s.score >= guardThreshold then
                        blockedByGuard = true
                        EbonBuilds.DebugLog.AddF("reroll blocked by guard: [%d] %s %.0f >= %d (pacing %.2f)", s.index, s.name, s.score or 0, guardThreshold, guardPacing)
                        break
                    end
                end
                if not blockedByGuard then
                    local sum = 0
                    for _, s in ipairs(scored) do if IsActionable(s) then sum = sum + s.score end end
                    -- Same charge pacing concept as Smart mode: get pickier
                    -- as reroll charges run low, so it can't burn through
                    -- everything early on borderline offers.
                    local remaining = (runData.totalRerolls or 0) - (runData.usedRerolls or 0)
                    local pacing = ChargePacing(remaining, 8, 0.6, "below")
                    local rerollThreshold = peakScore * settings.autoRerollPct / 100 * pacing
                    EbonBuilds.DebugLog.AddF("reroll check: sum=%.0f vs threshold=%.0f (pacing %.2f)", sum, rerollThreshold, pacing)
                    if sum < rerollThreshold then
                        if SubmitAction("reroll", build, scored, 0, nil, "Reroll") then
                            EbonBuilds.DebugLog.Add("-> REQUEST REROLL")
                            return true
                        end
                    end
                end
            end
        end

        --------------------------------------------------------------------
        --------------------------------------------------------------------
        -- 3. TRY FREEZE
        --------------------------------------------------------------------
        -- Freeze one echo per evaluation so the server has time to confirm
        -- each freeze before the next one.  The timer re-invokes Evaluate()
        -- which scores fresh (reflecting isFrozen / isCarried state) and
        -- applies the penalty to locally-frozen echoes so their scores
        -- degrade toward the eventual pick.
        if runData and (runData.totalFreezes or 0) - (runData.usedFreezes or 0) > 0 then
            local penalty = (settings.freezePenaltyPct or 0) / 100

            -- Apply freeze penalty to echoes we already froze this round
            -- so they are deprioritised in subsequent evaluations.
            -- Only applied when the server hasn't confirmed isFrozen yet;
            -- ScoreChoice already handles the penalty once isFrozen is true.
            if penalty > 0 then
                for _, s in ipairs(scored) do
                    if locallyFrozenIndices[s.index] and not s.isFrozen then
                        s.score = math.floor(s.score * (1 - penalty))
                    end
                end
            end

            local threshold
            -- Charge pacing: only truly excellent echoes get frozen once
            -- charges run low, reserving the last few for genuinely
            -- exceptional finds instead of spending them on "pretty good".
            local freezeRemaining = (runData.totalFreezes or 0) - (runData.usedFreezes or 0)
            local freezePacing = ChargePacing(freezeRemaining, 6, 1.4, "above")
            if (settings.rerollMode or "sum") == "ev" then
                -- Freeze what beats the expected best of a future screen.
                threshold = EbonBuilds.Automation.GetOutcomeStats().evBest3 * (settings.freezeEVPct or 110) / 100 * freezePacing
            else
                threshold = math.floor(peakScore * settings.autoFreezePct / 100 * freezePacing)
            end

            -- Offered choices above freeze threshold, excluding echoes that
            -- are already frozen (server), carried, or locally frozen this round.
            local aboveChoices = {}
            for _, s in ipairs(scored) do
                if IsActionable(s) and s.score > threshold then
                    aboveChoices[#aboveChoices + 1] = s
                end
            end

            EbonBuilds.DebugLog.AddF("freeze check: %d choice(s) above %d (need 2)", #aboveChoices, threshold)
            -- Requires at least 2 offered choices above threshold so we can
            -- freeze the lowest and still select a different highest one.
            if #aboveChoices >= 2 then
                table.sort(aboveChoices, function(a, b) return a.score > b.score end)

                -- Freeze the single lowest-scored echo above the threshold.
                -- (Multiple would race the server; one-per-eval is reliable.)
                local lowest = aboveChoices[#aboveChoices]
                if SubmitAction("freeze", build, scored, lowest.index, lowest, "Freeze") then
                    EbonBuilds.DebugLog.AddF("-> REQUEST FREEZE [%d] %s (score %.0f)", lowest.index, lowest.name, lowest.score or 0)
                    return true
                end
            end
        end

        --------------------------------------------------------------------
        -- 4. SELECT (fallback)
        --------------------------------------------------------------------
        -- NOTE: locallyFrozenIndices must still be intact here so TrySelect
        -- can exclude the echo frozen this round. It gets cleared after the
        -- pick (a select ends this choice screen).
        local ok, pick, failureReason = TrySelect(scored, settings, build)
        if ok and pick then
            EbonBuilds.DebugLog.AddF("-> REQUEST SELECT [%d] %s (score %.0f)", pick.index, pick.name, pick.score or 0)
        elseif not ok then
            if failureReason == "policy_blocked" then
                lastNoActionReason = "Autopilot paused: all current offers are blocked by Echo policies"
                EbonBuilds.DebugLog.Add("-> NO ACTION (all offers blocked by Echo policies)")
            else
                EbonBuilds.DebugLog.Add("-> NO ACTION (select failed or nothing eligible)")
            end
        end
        return ok
    end

    local ok, result = pcall(body)
    evalInProgress = false
    if not ok then
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("Automation.Evaluate", result)
        end
        lastNoActionReason = "Automation error: choose manually"
        return false
    end
    return result
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

function EbonBuilds.Automation.Init()
    if hookInstalled then return true end
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return false end

    local PerkUI = ProjectEbonhold.PerkUI
    if type(PerkUI.Show) ~= "function" or type(hooksecurefunc) ~= "function" then return false end

    -- ProjectEbonhold is allowed to build its ordinary choice surface first;
    -- the post-hook then suppresses the complete surface in the same frame.
    -- This avoids replacing ProjectEbonhold code while remaining compatible
    -- with builds that use either PerkChooseButton or PerkHideButton.
    hooksecurefunc(PerkUI, "Show", function(choices)
        if nativeFallbackInProgress then return end
        ClearReplacementResetPending()
        CancelRequestFallback()
        if EbonBuilds.EchoEligibilityEvidence then
            EbonBuilds.EchoEligibilityEvidence.ObserveChoiceBoard(
                choices, EbonBuilds.EchoEligibilityEvidence.FLAG_OFFERED)
        end
        pendingChoices = choices
        local build = EbonBuilds.Build.GetActive()
        if build and build.stats and type(choices) == "table" then
            build.stats.echoesSeen = (build.stats.echoesSeen or 0) + #choices
        end
        locallyFrozenIndices = {}
        freezeRoundActive = false

        if ShouldSuppressNativeChoice() then
            SuppressNativeChoiceSurface()
            StartEvalTimer()
        else
            nativeChoiceSuppressed = false
        end
    end)

    if type(PerkUI.UpdateSinglePerk) == "function" then
        hooksecurefunc(PerkUI, "UpdateSinglePerk", function(perkIndex, perkData)
            if EbonBuilds.EchoEligibilityEvidence then
                EbonBuilds.EchoEligibilityEvidence.ObserveReplacement(perkIndex, perkData)
            end
            CancelRequestFallback()
            if ShouldSuppressNativeChoice() and HasCurrentChoice() then
                -- A successful banish updates the card and then immediately
                -- calls ResetSelection. That reset only re-enables the native
                -- card controls; it is not a request failure. Mark the paired
                -- reset so it cannot cancel the next Autopilot evaluation.
                ExpectReplacementReset()
                SuppressNativeChoiceSurface()
                StartEvalTimer()
            else
                ClearReplacementResetPending()
            end
        end)
    end

    if type(PerkUI.Hide) == "function" then
        hooksecurefunc(PerkUI, "Hide", function()
            ClearReplacementResetPending()
            CancelRequestFallback()
            if EbonBuilds.Scheduler then EbonBuilds.Scheduler.Cancel("automation.evaluate") end
            pendingChoices = nil
            nativeChoiceSuppressed = false
            HideNativeEchoTooltip()
        end)
    end

    if type(PerkUI.ResetSelection) == "function" then
        hooksecurefunc(PerkUI, "ResetSelection", function()
            if replacementResetPending then
                -- Successful banish sequence:
                --   UpdateSinglePerk -> ResetSelection
                -- Keep the evaluation scheduled by UpdateSinglePerk and undo
                -- the mouse re-enable performed by the native reset. The old
                -- implementation treated this as a rejection, exposed the
                -- Show Echoes button, and cancelled Autopilot after one action.
                ClearReplacementResetPending()
                if ShouldSuppressNativeChoice() and HasCurrentChoice() then
                    SuppressNativeChoiceSurface()
                end
                return
            end

            -- A reset without a preceding replacement is the public failure
            -- path for a rejected select/banish request. Avoid an endless retry
            -- loop and return the current board to the player.
            CancelRequestFallback()
            if EbonBuilds.Scheduler then EbonBuilds.Scheduler.Cancel("automation.evaluate") end
            if HasCurrentChoice() then ShowNativeChoiceFallback() end
        end)
    end

    if EbonBuilds.EventHub then
        local function OnRuntimeChanged()
            RefreshNativeChoiceGuard()
            if HasCurrentChoice() and ShouldSuppressNativeChoice() then
                pendingChoices = EbonBuilds.ProjectAPI.GetCurrentChoice()
                StartEvalTimer()
            else
                CancelRequestFallback()
            end
        end
        EbonBuilds.EventHub.On("BUILD_RUNTIME_CHANGED", OnRuntimeChanged, "Automation")
        EbonBuilds.EventHub.On("ACTIVE_BUILD_CHANGED", OnRuntimeChanged, "Automation")
    end
    hookInstalled = true
    return true
end

-- Exported for unit testing
EbonBuilds.Automation._ScoreChoice       = ScoreChoice
EbonBuilds.Automation._TrySelect         = TrySelect
EbonBuilds.Automation._AnnotateScored    = AnnotateScored
EbonBuilds.Automation._IsProtected       = IsFamilyProtected
EbonBuilds.Automation._ResetFreezeRound  = function()
    freezeRoundActive = false
    locallyFrozenIndices = {}
end
EbonBuilds.Automation._SetLocallyFrozenForTests = function(index)
    locallyFrozenIndices[index] = true
end
EbonBuilds.Automation._RefreshNativeChoiceGuardForTests = RefreshNativeChoiceGuard
EbonBuilds.Automation._IsNativeChoiceSuppressedForTests = function()
    return nativeChoiceSuppressed
end
