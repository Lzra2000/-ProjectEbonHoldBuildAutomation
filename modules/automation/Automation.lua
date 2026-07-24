local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/Automation.lua
-- Responsibility: evaluate offered echo choices against the active build's
-- automation thresholds and execute one freeze-first action at a time. Secure
-- post-hooks suppress the native choice surface only
-- while Autopilot owns the board and restore it on every fallback path.

EbonBuilds.Automation = {}

local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local INITIAL_ACTION_DELAY = 2.5
local FREEZE_RECOVERY_POLL_DELAY = 0.75

local function GetEvalDelay(minimum)
    local delay = (EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.evalDelay) or 2
    if minimum and delay < minimum then return minimum end
    return delay
end

local pendingChoices    = nil
local trainingNoticeShown = false -- once-per-session Manual Training notice (see the eval timer)
local hookInstalled       = false
local cachedPeak           = nil    -- locked at first evaluation of the run
local lastNoActionReason    = nil
local initialActionDelayPending = false

local function IsInitialRunLevel()
    return type(UnitLevel) == "function" and tonumber(UnitLevel("player")) == 1
end

local Decision = EbonBuilds.AutomationBoardDecision
local IntentQueue = EbonBuilds.AutomationIntentQueue
local Constraints = EbonBuilds.AutomationConstraints
local MAX_FREEZE_CONFIRM_POLLS = 3
local MAX_FREEZE_RECOVERY_POLLS = 2
local boardState = {
    state = Decision.STATE.IDLE,
    revision = 0,
    fingerprint = nil,
    identityFingerprint = nil,
    frozenCount = 0,
    frozenBySlot = {},
    -- Run-persistent Echo IDs that the client accepted or confirmed as frozen.
    -- Survives board-identity changes and PerkUI hide/show within a run so
    -- servers that omit isFrozen cannot reopen rerolls while a freeze is held.
    -- Cleared when the Echo is picked or the run ends.
    frozenEchoIDs = {},
    frozenThisBoardBySlot = {},
    frozenThisBoardEchoIDs = {},
    pendingFreezeSlot = nil,
    pendingFreezeEchoID = nil,
    pendingFreezeFingerprint = nil,
    pendingFreezeIdentity = nil,
    pendingFreezeChecks = 0,
    pendingFreezeUsedCount = nil,
    pendingAction = nil,
    pendingActionFingerprint = nil,
    pendingActionIdentity = nil,
    frozenStateUncertain = false,
    uncertainFreezeSlot = nil,
    uncertainFreezeEchoID = nil,
    uncertainFreezeIdentity = nil,
    uncertainFreezeChecks = 0,
    uncertainFreezeUsedCount = nil,
    failedFreezeBySlot = {},
}

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

local function StartEvalTimer(delayOverride)
    RefreshNativeChoiceGuard()
    local delay = delayOverride or GetEvalDelay()
    if initialActionDelayPending and delay < INITIAL_ACTION_DELAY then
        delay = INITIAL_ACTION_DELAY
    end
    EbonBuilds.Scheduler.After("automation.evaluate", delay, function()
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

function EbonBuilds.Automation.GetConstraints(context)
    if not Constraints then return nil end
    return Constraints.GetActive(context)
end

function EbonBuilds.Automation.ResetInitialActionDelay()
    -- A genuinely new run arms the one-shot pause at level 1. Once armed it
    -- intentionally survives an instant boost to level 50, while reconstructing
    -- a session later in the run cannot re-arm it.
    initialActionDelayPending = IsInitialRunLevel()
    for key in pairs(boardState.frozenEchoIDs) do boardState.frozenEchoIDs[key] = nil end
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
    if EbonBuilds.ProjectAPI and type(EbonBuilds.ProjectAPI.GetRunData) == "function" then
        return EbonBuilds.ProjectAPI.GetRunData()
    end
    if EbonholdPlayerRunData and EbonholdPlayerRunData.remainingBanishes ~= nil then
        return EbonholdPlayerRunData
    end
    if ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then return get() end
    end
    return nil
end

-- Warn once per login when Autopilot and PE auto-accept can both own picks.
local peAutoAcceptWarningShown = false

local function WarnPeAutoAcceptConflict()
    if peAutoAcceptWarningShown then return end
    local api = EbonBuilds.ProjectAPI
    if not api or type(api.IsAutoAcceptLoadoutEchoes) ~= "function" then return end
    if not api.IsAutoAcceptLoadoutEchoes() then return end
    peAutoAcceptWarningShown = true
    local message = "ProjectEbonhold Auto-Accept Loadout Echoes is ON. Autopilot defers when a loadout echo is offered -- turn that PE option off for full Autopilot control."
    if EbonBuilds.Toast and EbonBuilds.Toast.Show then
        EbonBuilds.Toast.Show(message)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[EbonBuilds]|r " .. message)
    end
end

function EbonBuilds.Automation.WarnPeAutoAcceptConflict()
    WarnPeAutoAcceptConflict()
end

function EbonBuilds.Automation.IsPeAutoAcceptLoadoutEnabled()
    local api = EbonBuilds.ProjectAPI
    return api and type(api.IsAutoAcceptLoadoutEchoes) == "function"
        and api.IsAutoAcceptLoadoutEchoes() or false
end

-- Optional freezeThreshold: when provided, skip the carry penalty while the
-- unpenalized score is still at/above the freeze bar (see BuildBoard).
local function ScoreChoice(choice, settings, freezeThreshold)
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
    -- The server ProjectEbonhold distribution confirms a freeze by setting
    -- justFrozen on the existing choice entry (no full board resend), and
    -- flags the active build slot's injected card as isGuaranteed.
    local isFrozen = (choice.isFrozen or choice.justFrozen) and true or false
    -- Freeze penalty softens carried/frozen Echoes so fresh offers can win
    -- later boards -- but only once the carry falls below the freeze bar.
    -- Applying it while the Echo is still freeze-worthy (default ~8-10%)
    -- lets mediocre fresh cards beat excellent carries and skips picks
    -- Discord users expect automation to keep.
    if (isFrozen or choice.isCarried) and settings.freezePenaltyPct and settings.freezePenaltyPct > 0 then
        local stillFreezeWorthy = freezeThreshold ~= nil and score >= freezeThreshold
        if not stillFreezeWorthy then
            score = score * (1 - settings.freezePenaltyPct / 100)
        end
    end
    return {
        index = 0, spellId = spellId, name = name, quality = quality,
        score = score, entry = entry, data = raw or variant,
        rank = tonumber(choice.rank),
        isFrozen = isFrozen, isCarried = choice.isCarried,
        isGuaranteed = choice.isGuaranteed and true or false,
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

local function AnnotateFrozenThisBoard(scored)
    if type(scored) ~= "table" then return end
    local bySlot = boardState.frozenThisBoardBySlot
    local byEcho = boardState.frozenThisBoardEchoIDs
    for _, s in ipairs(scored) do
        local index = tonumber(s.index)
        local echoID = tonumber(s.spellId) or s.echoId or s.refKey
        if (index ~= nil and bySlot and bySlot[index])
            or (echoID ~= nil and byEcho and byEcho[echoID]) then
            s.frozenThisBoard = true
        end
    end
end

local function LogAndToast(scored, action, targetIndex, appliedThreshold)
    AnnotateFrozenThisBoard(scored)
    EbonBuilds.Toast.ShowAutomationResult(scored, action, targetIndex)
    EbonBuilds.Session.LogAction(scored, action, targetIndex, nil, appliedThreshold)
end

local function CommitDecision(decision)
    if not decision then return end
    local action = decision.action
    if action == "select" then
        RecordPick(decision.build, decision.entry)
    elseif action == "banish" then
        RecordBanish(decision.build, decision.entry)
    elseif action == "reroll" then
        UpdateStat(decision.build, "rerollsUsed")
    end

    LogAndToast(decision.scored, decision.displayAction, decision.targetIndex or 0, decision.appliedThreshold)
end

local function SubmitAction(action, build, scored, targetIndex, entry, displayAction, appliedThreshold)
    local api = EbonBuilds.ProjectAPI
    if not api then return false end

    local accepted
    if action == "select" then
        accepted = api.RequestSelect(entry and entry.spellId)
    elseif action == "banish" then
        accepted = api.RequestBanish((targetIndex or 1) - 1)
    elseif action == "reroll" then
        accepted = api.RequestReroll()
    end
    if not accepted then return false end

    CommitDecision({
        action = action,
        build = build,
        scored = scored,
        targetIndex = targetIndex or 0,
        entry = entry,
        displayAction = displayAction or action,
        appliedThreshold = appliedThreshold,
    })
    ArmRequestFallback()
    return true
end

------------------------------------------------------------------------
-- Action attempts (called in priority order)
------------------------------------------------------------------------

local function IsActionable(s)
    return s and not s.isFrozen and not s.isCarried and not s.policyBlocked
end

local function TrySelect(scored, settings, build)
    local best, bestBanned
    local tieOpts = { preferFrozen = true }
    for _, s in ipairs(scored) do
        if IsActionable(s) then
            local current = EbonBuilds.Scoring.IsBanned(s.spellId, settings) and bestBanned or best
            if not current or EbonBuilds.Scoring.IsBetterCandidate(s, current, tieOpts) then
                if EbonBuilds.Scoring.IsBanned(s.spellId, settings) then bestBanned = s else best = s end
            end
        end
    end
    local pick = best or bestBanned
    if not pick then return false, nil, "policy_blocked" end

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
        s.isAvoided = s.isBanned or s.policyBlocked
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

local function ClearMap(map)
    for key in pairs(map) do map[key] = nil end
end

local function ClearPendingFreeze()
    boardState.pendingFreezeSlot = nil
    boardState.pendingFreezeEchoID = nil
    boardState.pendingFreezeFingerprint = nil
    boardState.pendingFreezeIdentity = nil
    boardState.pendingFreezeChecks = 0
    boardState.pendingFreezeUsedCount = nil
end

local function ClearPendingAction()
    boardState.pendingAction = nil
    boardState.pendingActionFingerprint = nil
    boardState.pendingActionIdentity = nil
    if IntentQueue then IntentQueue.Clear("pending_action_cleared") end
end

local function ClearFreezeUncertainty()
    boardState.frozenStateUncertain = false
    boardState.uncertainFreezeSlot = nil
    boardState.uncertainFreezeEchoID = nil
    boardState.uncertainFreezeIdentity = nil
    boardState.uncertainFreezeChecks = 0
    boardState.uncertainFreezeUsedCount = nil
end

local function MarkFrozenThisBoard(slot)
    if not slot then return end
    local index = tonumber(slot.index)
    local echoID = tonumber(slot.spellId) or slot.echoId or slot.refKey
    if index ~= nil then boardState.frozenThisBoardBySlot[index] = true end
    if echoID ~= nil then
        boardState.frozenThisBoardEchoIDs[echoID] = true
        boardState.frozenEchoIDs[echoID] = true
    end
end

local function UnmarkFrozenThisBoard(index, echoID)
    index = tonumber(index)
    echoID = tonumber(echoID) or echoID
    if index ~= nil then boardState.frozenThisBoardBySlot[index] = nil end
    if echoID ~= nil then boardState.frozenThisBoardEchoIDs[echoID] = nil end
    -- Intentionally leave boardState.frozenEchoIDs alone: a "resolved
    -- unfrozen" recovery after missing server flags must not reopen rerolls
    -- while the server may still hold the freeze. Pick / run-end clear it.
end

local function ClearRunFrozenEcho(echoID)
    echoID = tonumber(echoID) or echoID
    if echoID ~= nil then boardState.frozenEchoIDs[echoID] = nil end
end

local function ResetObservedBoard(nextState)
    boardState.state = nextState or Decision.STATE.IDLE
    boardState.fingerprint = nil
    boardState.identityFingerprint = nil
    boardState.frozenCount = 0
    ClearFreezeUncertainty()
    ClearMap(boardState.frozenBySlot)
    -- Keep boardState.frozenEchoIDs: run-persistent across board hide/show.
    ClearMap(boardState.frozenThisBoardBySlot)
    ClearMap(boardState.frozenThisBoardEchoIDs)
    ClearMap(boardState.failedFreezeBySlot)
    ClearPendingFreeze()
    ClearPendingAction()
    if IntentQueue then IntentQueue.Reset() end
end

local function ResetFreezeRound(nextState)
    ResetObservedBoard(nextState)
    ClearMap(boardState.frozenEchoIDs)
end

local function Remaining(total, used)
    return math.max(0, (tonumber(total) or 0) - (tonumber(used) or 0))
end

local function GetFreezeThreshold(settings, runData, peakScore)
    local remaining = runData and Remaining(runData.totalFreezes, runData.usedFreezes) or 0
    local pacing = ChargePacing(remaining, 6, 1.4, "above")
    if (settings.rerollMode or "sum") == "ev" then
        return EbonBuilds.Automation.GetOutcomeStats().evBest3
            * (settings.freezeEVPct or 110) / 100 * pacing
    end
    return math.floor(peakScore * (settings.autoFreezePct or 0) / 100 * pacing)
end

local function GetBanishThreshold(settings, runData, peakScore)
    local remaining = runData and (tonumber(runData.remainingBanishes) or 0) or 0
    local pacing = ChargePacing(remaining, 8, 0.7, "below")
    if (settings.rerollMode or "sum") == "ev" then
        return EbonBuilds.Automation.GetOutcomeStats().mean
            * (settings.banishEVPct or 60) / 100 * pacing
    end
    return math.floor(peakScore * (settings.autoBanishPct or 0) / 100 * pacing)
end

local function SetPickAcceptability(board, settings, runData, peakScore)
    local pick = Decision.FindBestLegalPick(board)
    if not pick then
        board.pickIsAcceptable = false
        return
    end

    local remaining = runData and Remaining(runData.totalRerolls, runData.usedRerolls) or 0
    if remaining <= 0 then
        board.pickIsAcceptable = true
        return
    end

    local pacing = ChargePacing(remaining, 8, 0.6, "below")
    if (settings.rerollMode or "sum") == "ev" then
        board.rerollThreshold = EbonBuilds.Automation.GetRerollEV()
            * (settings.rerollEVPct or 95) / 100 * pacing
        board.pickIsAcceptable = (pick.score or 0) >= board.rerollThreshold
        if peakScore > 0 and pacing > 0 and EbonBuilds.Calibration then
            EbonBuilds.Calibration.RecordBestSample(((pick.score or 0) / peakScore * 100) / pacing)
        end
        return
    end

    local guardThreshold = math.floor(peakScore * (settings.rerollGuardPct or 90) / 100 * pacing)
    local sum = 0
    local guarded = false
    for _, slot in ipairs(board.slots) do
        if Decision._IsLegalSelection(slot, board) then
            sum = sum + (slot.score or 0)
            if (slot.score or 0) >= guardThreshold then guarded = true end
        end
    end
    board.rerollThreshold = peakScore * (settings.autoRerollPct or 0) / 100 * pacing
    board.pickIsAcceptable = guarded or sum >= board.rerollThreshold
end

local function NewRawBoard(choices)
    local board = { slots = {}, isValid = type(choices) == "table", isStable = true }
    if type(choices) ~= "table" then return board end
    for i, choice in ipairs(choices) do
        local spellId = tonumber(choice and choice.spellId)
        board.slots[#board.slots + 1] = {
            index = i,
            spellId = spellId,
            rank = choice and tonumber(choice.rank) or nil,
            isFrozen = choice and (choice.isFrozen or choice.justFrozen) and true or false,
            isCarried = choice and choice.isCarried and true or false,
            isGuaranteed = choice and choice.isGuaranteed and true or false,
        }
        if not spellId then board.isValid = false end
        if choice and choice.frozenStateKnown == false then board.isStable = false end
    end
    if #board.slots == 0 then board.isValid = false end
    return board
end

local function CurrentBoardFingerprint()
    local choices = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCurrentChoice
        and EbonBuilds.ProjectAPI.GetCurrentChoice() or nil
    return Decision.Fingerprint(NewRawBoard(choices))
end

local function BuildBoard(choices, settings, build, runData, peakScore)
    local freezeThreshold = GetFreezeThreshold(settings, runData, peakScore)
    local scored = {}
    local valid = type(choices) == "table" and #choices > 0
    local stable = valid
    for i, choice in ipairs(choices or {}) do
        local s = ScoreChoice(choice, settings, freezeThreshold)
        if s then
            s.index = i
            s.isValid = true
            scored[#scored + 1] = s
        else
            valid = false
        end
        if choice and choice.frozenStateKnown == false then stable = false end
    end
    if #scored ~= #(choices or {}) then valid = false end

    local selectedNames = EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.SelectedNames() or {}
    AnnotateScored(scored, settings, build.lockedEchoes or {}, selectedNames)

    local board = {
        slots = scored,
        isValid = valid,
        isStable = stable,
        maxFrozen = Decision.MAX_FROZEN_PER_BOARD,
        freezeThreshold = freezeThreshold,
        freezeResources = runData and Remaining(runData.totalFreezes, runData.usedFreezes) or 0,
        canReroll = runData and Remaining(runData.totalRerolls, runData.usedRerolls) > 0 or false,
        canBanish = runData and (tonumber(runData.remainingBanishes) or 0) > 0 or false,
        frozenThisBoardBySlot = boardState.frozenThisBoardBySlot,
        frozenThisBoardEchoIDs = boardState.frozenThisBoardEchoIDs,
        runFrozenEchoIDs = boardState.frozenEchoIDs,
    }
    Decision.RefreshFrozenState(board)
    board.banishThreshold = GetBanishThreshold(settings, runData, peakScore)
    for _, slot in ipairs(board.slots) do
        slot.banishEligible = not slot.isAvoided and (slot.score or 0) < board.banishThreshold
    end
    SetPickAcceptability(board, settings, runData, peakScore)
    board.fingerprint = Decision.Fingerprint(board)
    board.identityFingerprint = Decision.IdentityFingerprint(board)
    if Constraints and Constraints.AttachToBoard then
        Constraints.AttachToBoard(board, build, runData)
    end
    return board
end

local function ObserveBoard(board)
    if boardState.fingerprint ~= board.fingerprint then
        boardState.revision = boardState.revision + 1
    end
    boardState.fingerprint = board.fingerprint
    boardState.identityFingerprint = board.identityFingerprint
    boardState.frozenCount = board.frozenCount
    ClearMap(boardState.frozenBySlot)
    for key, value in pairs(board.frozenBySlot or {}) do boardState.frozenBySlot[key] = value end
    -- boardState.frozenEchoIDs is run-persistent input, not an observed rebuild.
    board.revision = boardState.revision
end

local function FindFreezeSlot(board, index, echoID)
    for _, slot in ipairs(board.slots or {}) do
        local slotID = tonumber(slot.spellId) or slot.echoId or slot.refKey
        if tonumber(slot.index) == tonumber(index) and slotID == echoID then return slot end
    end
    return nil
end

local function FreezeResourceAdvanced(runData, usedCountSnapshot)
    if not runData or usedCountSnapshot == nil or runData.usedFreezes == nil then return false end
    return (tonumber(runData.usedFreezes) or 0) > (tonumber(usedCountSnapshot) or 0)
end

local function CommitConfirmedFreeze(build, board, runData, slot, usedCountSnapshot, late, source)
    UpdateStat(build, "freezesUsed")
    if runData and runData.usedFreezes ~= nil
        and tonumber(runData.usedFreezes) == tonumber(usedCountSnapshot) then
        runData.usedFreezes = (tonumber(runData.usedFreezes) or 0) + 1
        board.freezeResources = math.max(0, (board.freezeResources or 0) - 1)
    end
    MarkFrozenThisBoard(slot)
    EbonBuilds.DebugLog.AddF("Freeze confirmed%s%s: [%d] %s (%s)",
        late and " after recovery" or "",
        source == "resource" and " by server resource counter" or "",
        slot.index, slot.name, tostring(slot.spellId))
    boardState.state = Decision.STATE.EVALUATING
end

local function ResolvePendingFreeze(build, board, runData)
    if not boardState.pendingFreezeSlot then return "none" end
    local pendingStatus, slot = Decision.ClassifyPendingFreeze(board,
        boardState.pendingFreezeSlot, boardState.pendingFreezeEchoID, boardState.pendingFreezeIdentity)
    local confirmationSource = "board"
    if pendingStatus == "waiting"
        and FreezeResourceAdvanced(runData, boardState.pendingFreezeUsedCount) then
        slot = FindFreezeSlot(board, boardState.pendingFreezeSlot, boardState.pendingFreezeEchoID)
        if slot then
            pendingStatus = "confirmed"
            confirmationSource = "resource"
        end
    end
    if pendingStatus == "confirmed" then
        local usedCountSnapshot = boardState.pendingFreezeUsedCount
        ClearPendingFreeze()
        ClearFreezeUncertainty()
        CommitConfirmedFreeze(build, board, runData, slot, usedCountSnapshot, false, confirmationSource)
        return "confirmed"
    end

    if pendingStatus == "board_changed" then
        EbonBuilds.DebugLog.Add("Freeze confirmation failed: board changed after the request; stale target cleared")
        ClearPendingFreeze()
        ClearFreezeUncertainty()
        boardState.state = Decision.STATE.EVALUATING
        return "changed"
    end

    boardState.pendingFreezeChecks = boardState.pendingFreezeChecks + 1
    if boardState.pendingFreezeChecks < MAX_FREEZE_CONFIRM_POLLS then
        boardState.state = Decision.STATE.WAITING_FOR_FREEZE_CONFIRMATION
        EbonBuilds.DebugLog.AddF("Pending action: Freeze slot %d; waiting for server confirmation (%d/%d)",
            boardState.pendingFreezeSlot, boardState.pendingFreezeChecks, MAX_FREEZE_CONFIRM_POLLS)
        EbonBuilds.DebugLog.Add("Reroll status: Blocked because freeze confirmation is pending")
        StartEvalTimer()
        return "waiting"
    end

    local failedSlot = boardState.pendingFreezeSlot
    boardState.uncertainFreezeSlot = failedSlot
    boardState.uncertainFreezeEchoID = boardState.pendingFreezeEchoID
    boardState.uncertainFreezeIdentity = boardState.pendingFreezeIdentity
    boardState.uncertainFreezeUsedCount = boardState.pendingFreezeUsedCount
    boardState.uncertainFreezeChecks = 0
    boardState.failedFreezeBySlot[failedSlot] = true
    boardState.frozenStateUncertain = true
    ClearPendingFreeze()
    boardState.state = Decision.STATE.WAITING_FOR_FREEZE_CONFIRMATION
    EbonBuilds.DebugLog.AddF("Freeze confirmation delayed: slot %d entered stable-board recovery; no request will be repeated", failedSlot)
    EbonBuilds.DebugLog.Add("Reroll status: Blocked while frozen state is being rechecked")
    StartEvalTimer(FREEZE_RECOVERY_POLL_DELAY)
    return "recovering"
end

local function ResolveFreezeUncertainty(build, board, runData)
    if not boardState.frozenStateUncertain or not boardState.uncertainFreezeSlot then return "none" end

    local status, slot = Decision.ClassifyPendingFreeze(board,
        boardState.uncertainFreezeSlot, boardState.uncertainFreezeEchoID,
        boardState.uncertainFreezeIdentity)
    local confirmationSource = "board"
    if status == "waiting"
        and FreezeResourceAdvanced(runData, boardState.uncertainFreezeUsedCount) then
        slot = FindFreezeSlot(board, boardState.uncertainFreezeSlot, boardState.uncertainFreezeEchoID)
        if slot then
            status = "confirmed"
            confirmationSource = "resource"
        end
    end
    if status == "confirmed" then
        local usedCountSnapshot = boardState.uncertainFreezeUsedCount
        ClearFreezeUncertainty()
        CommitConfirmedFreeze(build, board, runData, slot, usedCountSnapshot, true, confirmationSource)
        return "confirmed"
    end
    if status == "board_changed" then
        EbonBuilds.DebugLog.Add("Freeze uncertainty cleared: board identity changed")
        ClearFreezeUncertainty()
        boardState.state = Decision.STATE.EVALUATING
        return "changed"
    end

    boardState.uncertainFreezeChecks = boardState.uncertainFreezeChecks + 1
    if boardState.uncertainFreezeChecks < MAX_FREEZE_RECOVERY_POLLS then
        boardState.state = Decision.STATE.WAITING_FOR_FREEZE_CONFIRMATION
        EbonBuilds.DebugLog.AddF("Freeze recovery: stable unfrozen read %d/%d; reroll remains blocked",
            boardState.uncertainFreezeChecks, MAX_FREEZE_RECOVERY_POLLS)
        StartEvalTimer(FREEZE_RECOVERY_POLL_DELAY)
        return "recovering"
    end

    local failedSlot = boardState.uncertainFreezeSlot
    local failedEchoID = boardState.uncertainFreezeEchoID
    UnmarkFrozenThisBoard(failedSlot, failedEchoID)
    ClearFreezeUncertainty()
    boardState.state = Decision.STATE.EVALUATING
    -- Correction for the immediate request log/toast: recovery proved the
    -- slot never received a server freeze flag across stable reads.
    EbonBuilds.DebugLog.Add("Freeze not confirmed")
    EbonBuilds.DebugLog.AddF("Freeze recovery resolved: slot %d remained unfrozen across stable reads; continuing without retry", failedSlot)
    return "resolved"
end

local function AttachRuntimeState(board, choices)
    board.pendingFreezeSlot = boardState.pendingFreezeSlot
    board.pendingFreezeEchoID = boardState.pendingFreezeEchoID
    board.frozenStateUncertain = boardState.frozenStateUncertain
    board.failedFreezeBySlot = boardState.failedFreezeBySlot
    board.frozenThisBoardBySlot = boardState.frozenThisBoardBySlot
    board.frozenThisBoardEchoIDs = boardState.frozenThisBoardEchoIDs
    board.runFrozenEchoIDs = boardState.frozenEchoIDs
    board.pendingAction = boardState.pendingAction
    board.choices = choices
    board.boardVisible = board.isValid and #(board.slots or {}) > 0

    local api = EbonBuilds.ProjectAPI
    board.serverPendingAction = api and type(api.GetPendingAction) == "function"
        and api.GetPendingAction() or nil

    local perks = ProjectEbonhold and ProjectEbonhold.Perks
    if type(perks) == "table" then
        board.serverBoardState = perks.boardState
        board.offerId = board.offerId or perks.offerId
    end

    if EbonBuilds.AutomationBoardStateMachine then
        EbonBuilds.AutomationBoardStateMachine.Attach(board, board)
    end
end

local function IntentActionFromDecision(action)
    if action == "SELECT" then return "select" end
    if action == "BANISH" then return "banish" end
    if action == "REROLL" then return "reroll" end
    if action == "FREEZE" then return "freeze" end
    return nil
end

local function BuildIntentSnapshot(board, target)
    if IntentQueue and IntentQueue.BuildSnapshot then
        local snapshot = IntentQueue.BuildSnapshot(board, target)
        snapshot.pendingAction = boardState.pendingAction
        if Constraints and (not snapshot.constraintsHash) then
            local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
            local packed = Constraints.FromBuild(build, { runData = GetRunData() })
            snapshot.constraintsHash = packed and packed.hash
        end
        return snapshot
    end
    return {
        offerId = board and board.offerId,
        identityFingerprint = board and board.identityFingerprint,
        targetSlot = target and target.index,
        serverPendingAction = board and board.serverPendingAction,
        pendingAction = boardState.pendingAction,
        constraintsHash = board and board.constraintsHash,
    }
end

local function GuardIntent(action, board, target)
    if not IntentQueue then return true end
    local intentAction = IntentActionFromDecision(action)
    if not intentAction then return true end
    local accepted, reason = IntentQueue.TryBegin(intentAction, BuildIntentSnapshot(board, target))
    if accepted then return true end
    boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
    EbonBuilds.DebugLog.Add(IntentQueue.DescribeBlock(reason))
    StartEvalTimer()
    return false
end

local function ResolveIntentQueueAck(board)
    if not IntentQueue then return "none" end
    local ack = IntentQueue.PollAck(BuildIntentSnapshot(board))
    if ack == "none" or ack == "waiting" then return ack end
    if boardState.pendingAction then
        EbonBuilds.DebugLog.Add("Intent queue ack: " .. ack
            .. " after " .. tostring(boardState.pendingAction))
        ClearPendingAction()
        boardState.state = Decision.STATE.EVALUATING
    elseif ack == "timeout" then
        EbonBuilds.DebugLog.Add("Intent queue: in-flight intent timed out; clearing block")
    end
    return ack
end

local function ResolvePendingAction(board)
    ResolveIntentQueueAck(board)
    if IntentQueue and IntentQueue.IsBlocking(BuildIntentSnapshot(board)) then
        boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
        EbonBuilds.DebugLog.Add("Intent queue: " .. (IntentQueue.BlockReason() or "waiting"))
        StartEvalTimer()
        return "waiting"
    end

    if not boardState.pendingAction then
        -- The server ProjectEbonhold distribution rejects a request while its
        -- own one is in flight (player click or its auto-accept). Wait for the
        -- flag to clear instead of firing a request that would be refused and
        -- pause the Autopilot.
        local serverPending = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetPendingAction
            and EbonBuilds.ProjectAPI.GetPendingAction() or nil
        if serverPending then
            boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
            EbonBuilds.DebugLog.Add("Pending action: " .. tostring(serverPending)
                .. " (ProjectEbonhold request in flight); duplicate request blocked")
            StartEvalTimer()
            return "waiting"
        end
        return "none"
    end
    if board.identityFingerprint ~= boardState.pendingActionIdentity then
        EbonBuilds.DebugLog.Add("Board update confirmed after " .. tostring(boardState.pendingAction))
        ClearPendingAction()
        boardState.state = Decision.STATE.EVALUATING
        return "changed"
    end
    boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
    EbonBuilds.DebugLog.Add("Pending action: " .. tostring(boardState.pendingAction)
        .. "; duplicate request blocked while waiting for board update")
    return "waiting"
end

local function LogBoardDecision(board, decision)
    if not EbonBuilds.DebugLog.IsEnabled() then return end
    local visible = {}
    for _, slot in ipairs(board.slots or {}) do
        visible[#visible + 1] = string.format("[%d] %s(%s)=%.0f%s",
            slot.index, slot.name or "?", tostring(slot.spellId or "?"), slot.score or 0,
            (slot.isFrozen or slot.isCarried) and " FROZEN" or "")
    end
    local pick = Decision.FindBestLegalPick(board)
    local freeze = Decision.FindBestFreezeCandidate(board, pick)
    EbonBuilds.DebugLog.Add("Board: " .. table.concat(visible, ", "))
    local api = EbonBuilds.ProjectAPI
    if api and type(api.GetRollsDebugInfo) == "function" then
        local level, picksMade, rollsLeft = api.GetRollsDebugInfo()
        if level or picksMade or rollsLeft then
            EbonBuilds.DebugLog.AddF("Rolls debug: level=%s picksMade=%s rollsLeft=%s",
                tostring(level or "?"), tostring(picksMade or "?"), tostring(rollsLeft or "?"))
        end
    elseif api and type(api.GetPendingRollsCount) == "function" then
        local rolls = api.GetPendingRollsCount()
        if rolls ~= nil then
            EbonBuilds.DebugLog.AddF("Pending rolls remaining: %s", tostring(rolls))
        end
    end
    EbonBuilds.DebugLog.AddF("Frozen: %d/%d", board.frozenCount or 0, board.maxFrozen or 2)
    if board.lifecycleState then
        EbonBuilds.DebugLog.AddF("Board lifecycle: %s (%s, %s)",
            tostring(board.lifecycleState),
            tostring(board.lifecycleReasonCode or "?"),
            tostring(board.lifecycleSource or "derived"))
    end
    EbonBuilds.DebugLog.Add("Pick target: " .. (pick and string.format("[%d] %s", pick.index, pick.name) or "none"))
    EbonBuilds.DebugLog.Add("Freeze candidate: " .. (freeze and string.format("[%d] %s", freeze.index, freeze.name) or "none"))
    EbonBuilds.DebugLog.Add("Pending action: " .. (board.pendingFreezeSlot and ("Freeze slot " .. board.pendingFreezeSlot) or "none"))
    EbonBuilds.DebugLog.Add("Action: " .. tostring(decision.action) .. " -- " .. tostring(decision.reason))
    if decision.action == "FREEZE" and pick then
        EbonBuilds.DebugLog.Add("Selection delayed: a qualifying unfrozen Echo must be secured first")
    end
    if (board.frozenCount or 0) > 0 then
        EbonBuilds.DebugLog.Add("Reroll status: Blocked because board contains a frozen Echo")
    elseif board.pendingFreezeSlot then
        EbonBuilds.DebugLog.Add("Reroll status: Blocked because freeze confirmation is pending")
    elseif board.frozenStateUncertain then
        EbonBuilds.DebugLog.Add("Reroll status: Blocked because frozen state is uncertain")
    end
end

local function RequestFreeze(build, board, target)
    if not GuardIntent("FREEZE", board, target) then return true end
    if board.frozenCount >= (board.maxFrozen or 2) then
        if IntentQueue then IntentQueue.Clear("freeze_blocked") end
        EbonBuilds.DebugLog.Add("Freeze blocked: board already contains two frozen Echoes")
        return false
    end
    boardState.state = Decision.STATE.REQUESTING_FREEZE
    boardState.pendingFreezeSlot = target.index
    boardState.pendingFreezeEchoID = target.spellId
    boardState.pendingFreezeFingerprint = board.fingerprint
    boardState.pendingFreezeIdentity = board.identityFingerprint
    boardState.pendingFreezeChecks = 0
    local runData = GetRunData()
    boardState.pendingFreezeUsedCount = runData and tonumber(runData.usedFreezes) or nil

    local accepted = EbonBuilds.ProjectAPI.RequestFreeze(target.index - 1)
    if not accepted then
        if IntentQueue then IntentQueue.Clear("freeze_rejected") end
        boardState.failedFreezeBySlot[target.index] = true
        ClearPendingFreeze()
        ClearFreezeUncertainty()
        boardState.state = Decision.STATE.RECOVERY
        EbonBuilds.DebugLog.AddF("Freeze request rejected locally: [%d] %s; no uncertain server request remains", target.index, target.name)
        lastNoActionReason = "Autopilot paused: Freeze request failed; choose manually"
        return false
    end

    boardState.state = Decision.STATE.WAITING_FOR_FREEZE_CONFIRMATION
    MarkFrozenThisBoard(target)
    -- Record the accepted request immediately. Confirmation can arrive late (or
    -- only through recovery), so using confirmation as the Logbook trigger can
    -- silently lose the action. CommitConfirmedFreeze deliberately does not log
    -- again; it only reconciles confirmed stats and resources.
    LogAndToast(board.slots, "Freeze", target.index, board.freezeThreshold)
    EbonBuilds.DebugLog.AddF("-> REQUEST FREEZE [%d] %s (score %.0f); waiting for confirmation",
        target.index, target.name, target.score or 0)
    EbonBuilds.DebugLog.Add("Reroll status: Blocked because freeze confirmation is pending")
    ArmRequestFallback()
    StartEvalTimer()
    return true
end

local function ExecuteDecision(build, board, decision)
    if decision.action == "WAIT" or decision.action == "WAIT_FOR_FREEZE" then return true end
    if decision.action == "RECOVERY" then
        boardState.state = Decision.STATE.RECOVERY
        lastNoActionReason = "Autopilot paused: " .. tostring(decision.reason or "no safe action")
        return false
    end

    if CurrentBoardFingerprint() ~= board.fingerprint then
        boardState.state = Decision.STATE.WAITING_FOR_BOARD
        EbonBuilds.DebugLog.Add("Action cancelled: board changed since evaluation; stale slot references cleared")
        StartEvalTimer()
        return true
    end

    if decision.action == "FREEZE" then
        return RequestFreeze(build, board, decision.target)
    end

    if decision.action == "SELECT" then
        if not GuardIntent("SELECT", board, decision.target) then return true end
        if boardState.pendingFreezeSlot or boardState.frozenStateUncertain
            or Decision.HasUnsecuredFreezeCandidate(board, decision.target) then
            EbonBuilds.DebugLog.Add("Selection blocked: a freeze is pending or an unsecured freeze candidate remains")
            StartEvalTimer()
            return true
        end
        boardState.state = Decision.STATE.SELECTING
        if SubmitAction("select", build, board.slots, decision.target.index, decision.target, "Select", board.rerollThreshold) then
            ClearRunFrozenEcho(decision.target.spellId or decision.target.echoId or decision.target.refKey)
            boardState.pendingAction = "select"
            boardState.pendingActionFingerprint = board.fingerprint
            boardState.pendingActionIdentity = board.identityFingerprint
            boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
            EbonBuilds.DebugLog.AddF("-> REQUEST SELECT [%d] %s (score %.0f)",
                decision.target.index, decision.target.name, decision.target.score or 0)
            return true
        end
    elseif decision.action == "BANISH" then
        if not GuardIntent("BANISH", board, decision.target) then return true end
        if board.frozenCount > 0 or boardState.pendingFreezeSlot or boardState.frozenStateUncertain then
            EbonBuilds.DebugLog.Add("Banish blocked: frozen-board safety guard")
            return false
        end
        boardState.state = Decision.STATE.BANISHING
        if SubmitAction("banish", build, board.slots, decision.target.index, decision.target, "Banish", board.banishThreshold) then
            boardState.pendingAction = "banish"
            boardState.pendingActionFingerprint = board.fingerprint
            boardState.pendingActionIdentity = board.identityFingerprint
            boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
            return true
        end
    elseif decision.action == "REROLL" then
        local BSM = EbonBuilds.AutomationBoardStateMachine
        if BSM and board.lifecycleState and BSM.IsRerollBlocked(board.lifecycleState) then
            EbonBuilds.DebugLog.Add(BSM.RerollBlockMessage(board.lifecycleState, board.lifecycleReasonCode)
                or "Reroll blocked: board lifecycle forbids reroll")
            return false
        end
        local allowed, reason = Decision.CanReroll(board)
        if not allowed then
            EbonBuilds.DebugLog.Add("Reroll blocked: " .. tostring(reason))
            return false
        end
        boardState.state = Decision.STATE.REROLLING
        if not GuardIntent("REROLL", board, nil) then return true end
        if SubmitAction("reroll", build, board.slots, 0, nil, "Reroll", board.rerollThreshold) then
            boardState.pendingAction = "reroll"
            boardState.pendingActionFingerprint = board.fingerprint
            boardState.pendingActionIdentity = board.identityFingerprint
            boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
            return true
        end
    end

    boardState.state = Decision.STATE.RECOVERY
    if IntentQueue then IntentQueue.Clear("request_rejected") end
    lastNoActionReason = "Autopilot request was rejected; choose manually"
    return false
end

local evalInProgress = false

function EbonBuilds.Automation.Evaluate()
    if evalInProgress then return true end
    evalInProgress = true

    local function body()
        lastNoActionReason = nil
        local build = EbonBuilds.Build.GetActive()
        if not build then return false end

        local choices = EbonBuilds.ProjectAPI.GetCurrentChoice()
        if not choices or #choices == 0 then return false end

        if EbonBuilds.Session and EbonBuilds.Session.RecordInitialOffer then
            EbonBuilds.Session.RecordInitialOffer(choices)
        end
        RecordAppearanceChoices(choices)

        if EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build) then return false end
        if not EbonBuilds.Build.IsAutomationEnabled(build) then return false end

        WarnPeAutoAcceptConflict()

        -- ProjectEbonhold auto-accepts loadout echoes ~180ms after the choice
        -- arrives, often before Autopilot's eval timer. Defer rather than race
        -- a second SelectPerk that PE would refuse and pause automation over.
        local api = EbonBuilds.ProjectAPI
        if api and type(api.WillAutoAcceptChoice) == "function" and api.WillAutoAcceptChoice(choices) then
            boardState.state = Decision.STATE.WAITING_FOR_BOARD_UPDATE
            EbonBuilds.DebugLog.Add("Deferring: ProjectEbonhold auto-accept will pick a loadout echo")
            local rolls = api.GetPendingRollsCount and api.GetPendingRollsCount() or nil
            if rolls ~= nil then
                EbonBuilds.DebugLog.AddF("Pending rolls remaining: %s", tostring(rolls))
            end
            StartEvalTimer()
            return true
        end

        -- Consume the one-shot startup latch after the first valid automation
        -- board. It may have been armed at level 1 before an instant level-50
        -- boost; every later board uses normal timing.
        initialActionDelayPending = false

        local settings = EbonBuilds.Scoring.GetEffectiveSettings()
        local runData = GetRunData()
        local peakScore = EbonBuilds.Automation.GetPeak()
        local board = BuildBoard(choices, settings, build, runData, peakScore)

        if peakScore and peakScore > 0 and EbonBuilds.Calibration then
            for _, s in ipairs(board.slots) do
                if s.score then EbonBuilds.Calibration.RecordSample(s.score / peakScore * 100) end
            end
            EbonBuilds.Calibration.MaybeAutoTune()
        end

        local pendingResult = ResolvePendingFreeze(build, board, runData)
        if pendingResult == "waiting" or pendingResult == "recovering" then return true end

        local recoveryResult = ResolveFreezeUncertainty(build, board, runData)
        if recoveryResult == "recovering" then return true end

        local actionResult = ResolvePendingAction(board)
        if actionResult == "waiting" then return true end

        if boardState.identityFingerprint and boardState.identityFingerprint ~= board.identityFingerprint then
            ClearMap(boardState.failedFreezeBySlot)
            ClearMap(boardState.frozenThisBoardBySlot)
            ClearMap(boardState.frozenThisBoardEchoIDs)
            -- Keep boardState.frozenEchoIDs across identity changes.
            boardState.frozenStateUncertain = false
            board.runFrozenEchoIDs = boardState.frozenEchoIDs
            Decision.RefreshFrozenState(board)
        end
        ObserveBoard(board)
        AttachRuntimeState(board, choices)
        boardState.state = Decision.STATE.EVALUATING

        local decision = Decision.Decide(board)
        LogBoardDecision(board, decision)
        return ExecuteDecision(build, board, decision)
    end

    local ok, result = pcall(body)
    evalInProgress = false
    if not ok then
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("Automation.Evaluate", result)
        end
        boardState.state = Decision.STATE.RECOVERY
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
            ResetObservedBoard(Decision.STATE.IDLE)
            HideNativeEchoTooltip()
        end)
    end

    if type(PerkUI.ResetSelection) == "function" then
        hooksecurefunc(PerkUI, "ResetSelection", function()
            if boardState.pendingFreezeSlot then
                -- A freeze remains unresolved until the complete board reports
                -- the target slot as frozen. Native reset ordering is not an
                -- acknowledgement and must not release selection or reroll.
                CancelRequestFallback()
                if ShouldSuppressNativeChoice() and HasCurrentChoice() then
                    SuppressNativeChoiceSurface()
                    StartEvalTimer()
                end
                return
            end
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
        EbonBuilds.EventHub.On("RUN_ENDED", function()
            ClearMap(boardState.frozenEchoIDs)
        end, "Automation")
    end
    hookInstalled = true
    return true
end

-- Exported for unit testing
EbonBuilds.Automation._ScoreChoice       = ScoreChoice
EbonBuilds.Automation._TrySelect         = TrySelect
EbonBuilds.Automation._AnnotateScored    = AnnotateScored
EbonBuilds.Automation._IsProtected       = IsFamilyProtected
EbonBuilds.Automation._ResetFreezeRound  = ResetFreezeRound
EbonBuilds.Automation._GetBoardStateForTests = function() return boardState end
EbonBuilds.Automation._GetNextEvalDelayForTests = function()
    local delay = GetEvalDelay()
    if initialActionDelayPending and delay < INITIAL_ACTION_DELAY then
        return INITIAL_ACTION_DELAY
    end
    return delay
end
EbonBuilds.Automation._MarkInitialActionDelayCompleteForTests = function()
    initialActionDelayPending = false
end
EbonBuilds.Automation._RequestFreezeForTests = RequestFreeze
EbonBuilds.Automation._ResolvePendingFreezeForTests = ResolvePendingFreeze
EbonBuilds.Automation._ResolvePendingActionForTests = ResolvePendingAction
EbonBuilds.Automation._ResolveFreezeUncertaintyForTests = ResolveFreezeUncertainty
EbonBuilds.Automation._RefreshNativeChoiceGuardForTests = RefreshNativeChoiceGuard
EbonBuilds.Automation._IsNativeChoiceSuppressedForTests = function()
    return nativeChoiceSuppressed
end
EbonBuilds.Automation._ExecuteDecisionForTests = ExecuteDecision
EbonBuilds.Automation._ResetObservedBoardForTests = ResetObservedBoard
