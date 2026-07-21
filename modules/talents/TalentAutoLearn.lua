local addonName, EbonBuilds = ...

-- EbonBuilds: modules/talents/TalentAutoLearn.lua
-- Combat-aware, one-action-at-a-time talent-plan executor. A talent request is
-- not reported as successful until PLAYER_TALENT_UPDATE verifies the rank.

EbonBuilds.TalentAutoLearn = {}
local TalentAutoLearn = EbonBuilds.TalentAutoLearn

local STATE_IDLE = "IDLE"
local STATE_WAIT_COMBAT = "WAIT_COMBAT"
local STATE_REQUESTED = "REQUESTED"
local state = STATE_IDLE
local pendingCandidate
local pendingPoints

function TalentAutoLearn.ComputeNextTalent(planTabs, readCurrent)
    if not planTabs or type(readCurrent) ~= "function" then return nil end
    for tabIndex = 1, 3 do
        local planTab = planTabs[tabIndex]
        if planTab and planTab.ranks then
            local indices = {}
            for index in pairs(planTab.ranks) do indices[#indices + 1] = index end
            table.sort(indices)
            for listIndex = 1, #indices do
                local talentIndex = indices[listIndex]
                local wantRank = planTab.ranks[talentIndex]
                local name, currentRank, maxRank, available = readCurrent(tabIndex, talentIndex)
                currentRank = currentRank or 0
                if name and wantRank > currentRank and available and (not maxRank or currentRank < maxRank) then
                    return {
                        tabIndex = tabIndex,
                        talentIndex = talentIndex,
                        name = name,
                        fromRank = currentRank,
                        toRank = currentRank + 1,
                        wantRank = wantRank,
                    }
                end
            end
        end
    end
    return nil
end

local function RealReadCurrent(tabIndex, talentIndex)
    local name, _, _, _, currentRank, maxRank, _, available = GetTalentInfo(tabIndex, talentIndex)
    return name, currentRank, maxRank, available
end

local function CurrentCandidate()
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or not build.talents or not build.talents.tabs then return nil, "off" end
    local mode = build.talentAutoLearnMode or "off"
    if mode == "off" then return nil, mode end
    if not GetUnspentTalentPoints or GetUnspentTalentPoints() <= 0 then return nil, mode end
    return TalentAutoLearn.ComputeNextTalent(build.talents.tabs, RealReadCurrent), mode
end

local function SameCandidate(left, right)
    return left and right
        and left.tabIndex == right.tabIndex
        and left.talentIndex == right.talentIndex
        and left.fromRank == right.fromRank
        and left.toRank == right.toRank
end

local function ResetPending()
    EbonBuilds.Scheduler.Cancel("talentAutoLearn.verifyTimeout")
    pendingCandidate = nil
    pendingPoints = nil
    state = STATE_IDLE
end

local function ScheduleReconsider(delay)
    EbonBuilds.Scheduler.After("talentAutoLearn.reconsider", delay or 0.1, function()
        TalentAutoLearn.MaybePrompt()
    end, EbonBuilds.Scheduler.INTERACTIVE, false, "TalentAutoLearn")
end

local function AttemptLearn(expected)
    if state == STATE_REQUESTED then return false end
    if InCombatLockdown and InCombatLockdown() then
        state = STATE_WAIT_COMBAT
        return false
    end

    local candidate = CurrentCandidate()
    if not candidate then ResetPending(); return false end
    if expected and not SameCandidate(expected, candidate) then
        ResetPending()
        ScheduleReconsider(0)
        return false
    end

    local points = GetUnspentTalentPoints and GetUnspentTalentPoints() or 0
    if points <= 0 then ResetPending(); return false end

    pendingCandidate = candidate
    pendingPoints = points
    state = STATE_REQUESTED
    LearnTalent(candidate.tabIndex, candidate.talentIndex)

    EbonBuilds.Scheduler.After("talentAutoLearn.verifyTimeout", 1.5, function()
        if state == STATE_REQUESTED then
            if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
                EbonBuilds.ErrorLog.Record("TalentAutoLearn", "Talent request was not confirmed by PLAYER_TALENT_UPDATE")
            end
            ResetPending()
            ScheduleReconsider(0.1)
        end
    end, EbonBuilds.Scheduler.INTERACTIVE, false, "TalentAutoLearn")
    return true
end

function TalentAutoLearn.MaybePrompt()
    if state == STATE_REQUESTED then return end
    if InCombatLockdown and InCombatLockdown() then
        state = STATE_WAIT_COMBAT
        return
    end
    if StaticPopup_Visible and StaticPopup_Visible("EBONBUILDS_CONFIRM_LEARN_TALENT") then return end

    local candidate, mode = CurrentCandidate()
    if not candidate then
        if state ~= STATE_WAIT_COMBAT then state = STATE_IDLE end
        return
    end

    state = STATE_IDLE
    if mode == "auto" then
        AttemptLearn(candidate)
        return
    end

    StaticPopupDialogs["EBONBUILDS_CONFIRM_LEARN_TALENT"] = {
        text = string.format("Learn %s (rank %d)?\nFrom this build's saved talent plan.", candidate.name, candidate.toRank),
        button1 = "Learn it",
        button2 = "Not now",
        OnAccept = function()
            AttemptLearn(candidate)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EBONBUILDS_CONFIRM_LEARN_TALENT")
end

local function OnTalentUpdate()
    if state ~= STATE_REQUESTED or not pendingCandidate then
        TalentAutoLearn.MaybePrompt()
        return
    end

    local _, currentRank = RealReadCurrent(pendingCandidate.tabIndex, pendingCandidate.talentIndex)
    local points = GetUnspentTalentPoints and GetUnspentTalentPoints() or pendingPoints
    if (tonumber(currentRank) or 0) >= pendingCandidate.toRank
        and (pendingPoints == nil or points < pendingPoints or currentRank > pendingCandidate.fromRank) then
        local learnedName = pendingCandidate.name
        local learnedRank = pendingCandidate.toRank
        ResetPending()
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show(string.format("Auto-learned %s (rank %d)", learnedName, learnedRank))
        end
        ScheduleReconsider(0.1)
    end
end

function TalentAutoLearn.Init()
    EbonBuilds.WoWEvents.On("CHARACTER_POINTS_CHANGED", function()
        if state ~= STATE_REQUESTED then TalentAutoLearn.MaybePrompt() end
    end, "TalentAutoLearn")
    EbonBuilds.WoWEvents.On("PLAYER_TALENT_UPDATE", function()
        OnTalentUpdate()
    end, "TalentAutoLearn")
    EbonBuilds.WoWEvents.On("PLAYER_REGEN_ENABLED", function()
        if state == STATE_WAIT_COMBAT then
            state = STATE_IDLE
            TalentAutoLearn.MaybePrompt()
        end
    end, "TalentAutoLearn")
end

TalentAutoLearn._MaybePrompt = TalentAutoLearn.MaybePrompt
TalentAutoLearn._AttemptLearn = AttemptLearn
TalentAutoLearn._State = function() return state end
