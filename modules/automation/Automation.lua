-- EbonBuilds: modules/automation/Automation.lua
-- Responsibility: evaluate offered echo choices against the active build's
-- automation thresholds and execute the optimal action (banish -> reroll ->
-- freeze -> select). Pre-hooks PerkUI.Show so automation runs before the
-- native UI appears.

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

local evalTimerFrame    = nil
local evalTimerElapsed  = 0
local evalTimerActive   = false
local pendingChoices    = nil
local trainingNoticeShown = false -- once-per-session Manual Training notice (see the eval timer)
local origPerkUIShow    = nil
local freezeRoundActive    = false  -- true after freeze batch, cleared on select
local locallyFrozenIndices = {}     -- indices frozen this round, for penalty tracking
local cachedPeak           = nil    -- locked at first evaluation of the run
local lastNoActionReason    = nil

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function StartEvalTimer()
    if not evalTimerFrame then
        evalTimerFrame = CreateFrame("Frame")
        evalTimerFrame:SetScript("OnUpdate", function(self, dt)
            evalTimerElapsed = evalTimerElapsed + dt
            if evalTimerElapsed >= GetEvalDelay() then
                evalTimerActive = false
                evalTimerFrame:Hide()
                local build = EbonBuilds.Build.GetActive()
                local wasActive = build and build.automationEnabled
                local isTraining = build and EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build)
                if EbonBuilds.Automation.Evaluate() then
                    pendingChoices = nil
                    lastNoActionReason = nil
                    return
                end
                -- Automation couldn't act, show the native perk UI. Only
                -- explain why if automation was actually on for this build.
                -- Manual Training gets its own notice, once per session:
                -- total silence made "Training: ON" indistinguishable from
                -- a broken addon (real report: "automation doesn't pick
                -- anything anymore" with both toggles on), but repeating
                -- it every choice screen would nag people deliberately
                -- training. Once per login is the middle ground.
                if pendingChoices and origPerkUIShow then
                    if wasActive and isTraining then
                        if not trainingNoticeShown then
                            trainingNoticeShown = true
                            EbonBuilds.Toast.Show("Automation paused: Manual Training is ON for this build (its toggle on the build overview turns it off)")
                        end
                    elseif wasActive then
                        EbonBuilds.Toast.Show(lastNoActionReason or "Automation: no rule matched, choose manually")
                    end
                    origPerkUIShow(pendingChoices)
                end
                pendingChoices = nil
                lastNoActionReason = nil
            end
        end)
    end
    evalTimerElapsed = 0
    evalTimerActive = true
    evalTimerFrame:Show()
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
    local spellId = choice.spellId
    local name = GetSpellInfo(spellId)
    if not name then return nil end
    local data = ProjectEbonhold.PerkDatabase[spellId]
    if not data then return nil end
    local entry = {
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        families  = data.families,
        classMask = data.classMask,
    }
    -- Weights are keyed by the DB comment (e.g. "Warrior - Voidsteel
    -- Bulwark"), NOT the spell name -- for class-specific echoes those
    -- differ, and a spell-name lookup silently returned 0.
    local weight = EbonBuilds.Weights.Get(EbonBuilds.Weights.CanonicalName(spellId), choice.quality) or 0
    -- Novelty only applies if the player has never picked this echo (by name,
    -- across all quality tiers). Once picked, all qualities lose the bonus.
    local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
    local isNovel = not granted or not granted[name]
    local score
    if isNovel then
        score = EbonBuilds.Scoring.Score(entry, weight, settings)
    else
        score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    end
    -- Freeze penalty: frozen and carried echoes get a score reduction so they
    -- are deprioritized in subsequent evaluations until eventually picked.
    if (choice.isFrozen or choice.isCarried) and settings.freezePenaltyPct and settings.freezePenaltyPct > 0 then
        score = score * (1 - settings.freezePenaltyPct / 100)
    end
    return {
        index     = 0,
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        score     = score,
        entry     = entry,
        data      = data,
        isFrozen  = choice.isFrozen,
        isCarried = choice.isCarried,
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
    local name = GetSpellInfo(lockedId)
    if not name then return 0 end
    local data = ProjectEbonhold.PerkDatabase[lockedId]
    if not data then return 0 end
    local entry = {
        spellId   = lockedId,
        name      = name,
        quality   = data.quality or 0,
        families  = data.families,
        classMask = data.classMask,
    }
    local w = EbonBuilds.Weights.Get(EbonBuilds.Weights.CanonicalName(lockedId), data.quality or 0) or 0
    return EbonBuilds.Scoring.Score(entry, w, settings)
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

    ProjectEbonhold.PerkService.SelectPerk(pick.spellId)
    RecordPick(build, pick)
    return true, pick
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
        if not build.automationEnabled then return false end

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
                    EbonBuilds.Weights.Get(EbonBuilds.Weights.CanonicalName(s.spellId), s.quality) or 0,
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
                    ProjectEbonhold.PerkService.SelectPerk(s.spellId)
                    RecordPick(build, s)
                    EbonBuilds.DebugLog.AddF("-> SELECT locked-match [%d] %s", s.index, s.name)
                    LogAndToast(scored, "Select (Locked)", s.index)
                    return true
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
                    local ok = ProjectEbonhold.PerkService.BanishPerk(s.index - 1)
                    if ok then
                        RecordBanish(build, s)
                        table.sort(scored, function(a, b) return a.index < b.index end)
                        EbonBuilds.DebugLog.AddF("-> BANISH policy [%d] %s (%s)", s.index, s.name, tostring(s.policy))
                        LogAndToast(scored, "Banish", s.index)
                        return true
                    end
                end
            end

            -- Ban-list echoes first (these have minimum priority)
            for _, s in ipairs(scored) do
                if IsActionable(s) and s.isBanned then
                    if not s.isProtected then
                        local ok = ProjectEbonhold.PerkService.BanishPerk(s.index - 1)
                        if ok then
                            RecordBanish(build, s)
                            table.sort(scored, function(a, b) return a.index < b.index end)
                            EbonBuilds.DebugLog.AddF("-> BANISH [%d] %s (score %.0f)", s.index, s.name, s.score or 0)
                            LogAndToast(scored, "Banish", s.index)
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
                        local ok = ProjectEbonhold.PerkService.BanishPerk(s.index - 1)
                        if ok then
                            RecordBanish(build, s)
                            table.sort(scored, function(a, b) return a.index < b.index end)
                            EbonBuilds.DebugLog.AddF("-> BANISH [%d] %s (score %.0f)", s.index, s.name, s.score or 0)
                            LogAndToast(scored, "Banish", s.index)
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
                    local ok = ProjectEbonhold.PerkService.RequestReroll()
                    if ok then
                        UpdateStat(build, "rerollsUsed")
                        EbonBuilds.DebugLog.Add("-> REROLL (EV)")
                        LogAndToast(scored, "Reroll", 0)
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
                        local ok = ProjectEbonhold.PerkService.RequestReroll()
                        if ok then
                            UpdateStat(build, "rerollsUsed")
                            EbonBuilds.DebugLog.Add("-> REROLL")
                            LogAndToast(scored, "Reroll", 0)
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
                local ok = ProjectEbonhold.PerkService.FreezePerk(lowest.index - 1)
                if ok then
                    UpdateStat(build, "freezesUsed")
                    locallyFrozenIndices[lowest.index] = true

                    -- Optimistically update runData so the toast and session log
                    -- reflect the correct remaining freeze count immediately.
                    if runData and runData.usedFreezes ~= nil then
                        runData.usedFreezes = runData.usedFreezes + 1
                    end

                    EbonBuilds.DebugLog.AddF("-> FREEZE [%d] %s (score %.0f)", lowest.index, lowest.name, lowest.score or 0)
                    LogAndToast(scored, "Freeze", lowest.index)
                    freezeRoundActive = true
                    StartEvalTimer()
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
        locallyFrozenIndices = {}
        freezeRoundActive = false
        if ok and pick then
            EbonBuilds.DebugLog.AddF("-> SELECT [%d] %s (score %.0f)", pick.index, pick.name, pick.score or 0)
            LogAndToast(scored, "Select", pick.index)
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

    local result = body()
    evalInProgress = false
    return result
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

function EbonBuilds.Automation.Init()
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return end
    if ProjectEbonhold.PerkUI._ebonBuildsHooked then return end

    local PerkUI = ProjectEbonhold.PerkUI

    -- Pre-hook Show: suppress the native UI and start a delayed evaluation.
    -- A timer gives the game time to fully set up the choice data before
    -- automation tries to act on it, preventing race conditions that cause
    -- the perk window to disappear without any action being taken.
    origPerkUIShow = PerkUI.Show
    PerkUI.Show = function(choices)
        pendingChoices = choices
        -- Stats: every genuinely new choice screen counts its offered echoes.
        local build = EbonBuilds.Build.GetActive()
        if build and build.stats and type(choices) == "table" then
            build.stats.echoesSeen = (build.stats.echoesSeen or 0) + #choices
        end
        -- New choice screen: server state (isFrozen/isCarried) is now the
        -- source of truth. Stale local freeze markers from the previous
        -- screen would penalize and freeze-block whatever new echo happens
        -- to sit at the same index.
        locallyFrozenIndices = {}
        freezeRoundActive = false
        StartEvalTimer()
    end

    -- Post-hook UpdateSinglePerk: called after a banish replacement animates
    -- the card. Start a fresh timer so automation can chain actions (e.g.
    -- banish the replacement if it is also below threshold).
    hooksecurefunc(PerkUI, "UpdateSinglePerk", function()
        StartEvalTimer()
    end)

    PerkUI._ebonBuildsHooked = true
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
