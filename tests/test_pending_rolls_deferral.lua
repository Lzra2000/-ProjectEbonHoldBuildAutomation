-- Coverage for #61 / #67: PE pending rolls, auto-accept deferral, slot-busy.
-- Run from addon root: lua5.1 tests/test_pending_rolls_deferral.lua

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("PENDING ROLLS FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

local now = 1000
function GetTime() return now end
function time() return 1700000000 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitName() return "Tester" end
function UnitLevel() return 50 end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

EbonBuildsDB = { globalSettings = { evalDelay = 2 }, sessions = {}, builds = {} }
EbonBuildsCharDB = {}
EbonBuilds = {}

local function loadAddonFile(path)
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    local ok, result = pcall(chunk, "EbonBuilds", EbonBuilds)
    if not ok then error(path .. ": " .. tostring(result)) end
end

------------------------------------------------------------------------
-- ProjectAPI: slot-busy TTL boundary + auto-accept choice scanning
------------------------------------------------------------------------
do
    local optionSettings = { autoAcceptLoadoutEchoes = true }
    local loadoutSpellIds = {}
    ProjectEbonholdOptionsService = {
        GetSetting = function(_, key) return optionSettings[key] end,
    }
    ProjectEbonhold = {
        PerkDatabase = {},
        PerkUI = {
            Show = function() end,
            Hide = function() end,
            ResetSelection = function() end,
            UpdateSinglePerk = function() end,
        },
        Perks = {},
        PerkService = {
            GetCurrentChoice = function() return {} end,
            IsSpellInActiveEchoLoadout = function(spellId)
                return loadoutSpellIds[tonumber(spellId)] == true
            end,
            GetPendingRollsCount = function() return 4 end,
            GetRollsDebugInfo = function() return 10, 3, 4 end,
        },
    }

    loadAddonFile("core/EventHub.lua")
    loadAddonFile("modules/integration/ProjectEbonholdAPI.lua")
    check(EbonBuilds.ProjectAPI.Init(), "ProjectAPI init")

    ProjectEbonhold.Perks.pendingBuildSlotRequest = "activate"
    ProjectEbonhold.Perks.pendingBuildSlotRequestAt = now
    equal(EbonBuilds.ProjectAPI.GetPendingAction(), "slot", "slot busy at TTL start")
    now = now + 3
    equal(EbonBuilds.ProjectAPI.GetPendingAction(), "slot", "slot busy exactly at 3s TTL")
    now = now + 0.01
    check(EbonBuilds.ProjectAPI.GetPendingAction() == nil, "slot busy clears after TTL")
    check(ProjectEbonhold.Perks.pendingBuildSlotRequest == nil, "expired slot flag cleared on read")

    local choices = {
        { spellId = 501, quality = 0 },
        { spellId = 502, quality = 1 },
    }
    loadoutSpellIds[502] = true
    check(EbonBuilds.ProjectAPI.WillAutoAcceptChoice(choices),
        "auto-accept matches later choice in board")
    loadoutSpellIds[502] = nil
    check(not EbonBuilds.ProjectAPI.WillAutoAcceptChoice(choices),
        "auto-accept off when no loadout overlap")
end

------------------------------------------------------------------------
-- IntentQueue: build-slot server pending blocks new intents (#67)
------------------------------------------------------------------------
do
    now = 2000
    ProjectEbonhold = { Perks = {} }
    EbonBuilds.ProjectAPI = {
        GetPendingAction = function()
            if ProjectEbonhold.Perks.pendingBuildSlotRequest then return "slot" end
            return nil
        end,
    }
    assert(loadfile("modules/automation/IntentQueue.lua"))("EbonBuilds", EbonBuilds)
    local IQ = EbonBuilds.AutomationIntentQueue
    IQ.Reset()

    ProjectEbonhold.Perks.pendingBuildSlotRequest = "upload"
    local accepted, reason = IQ.TryBegin("select", {
        offerId = "offer-slot",
        identityFingerprint = "board-slot",
        targetSlot = 1,
        serverPendingAction = "slot",
    })
    equal(accepted, false, "select blocked while build-slot request in flight")
    equal(reason, "server_pending_slot", "slot block reason code")
    equal(IQ.DescribeBlock("server_pending_slot"),
        "ProjectEbonhold build-slot request in flight",
        "slot block user message")

    ProjectEbonhold.Perks.pendingBuildSlotRequest = nil
    accepted = IQ.TryBegin("freeze", {
        offerId = "offer-slot",
        identityFingerprint = "board-slot",
        targetSlot = 2,
    })
    equal(accepted, true, "intent accepted after slot busy clears")
    IQ.Reset()
end

------------------------------------------------------------------------
-- Automation: defer when PE will auto-accept; warn once per login
------------------------------------------------------------------------
do
    now = 3000
    EbonBuildsDB.globalSettings.evalDelay = 2

    local choices = { { spellId = 7001, quality = 0 }, { spellId = 7002, quality = 1 } }
    local selectCalls = 0
    local toastMessages = {}
    local scheduled = {}
    local scheduledDelays = {}

    ProjectEbonholdOptionsService = {
        GetSetting = function(_, key) return key == "autoAcceptLoadoutEchoes" end,
    }
    ProjectEbonhold = {
        PerkUI = {
            Show = function() end,
            Hide = function() end,
            ResetSelection = function() end,
            UpdateSinglePerk = function() end,
        },
        PerkService = {
            GetCurrentChoice = function() return choices end,
            SelectPerk = function() selectCalls = selectCalls + 1; return true end,
            IsSpellInActiveEchoLoadout = function(spellId) return tonumber(spellId) == 7001 end,
            GetPendingRollsCount = function() return 9 end,
        },
    }

    function hooksecurefunc(owner, methodName, postHook)
        local original = owner[methodName]
        owner[methodName] = function(...)
            local results = { original(...) }
            postHook(...)
            return unpack(results)
        end
    end

    EbonBuilds.Build = {
        GetActive = function() return { id = "build-auto", stats = {} } end,
        IsAutomationEnabled = function() return true end,
    }
    EbonBuilds.ManualTraining = { IsEnabled = function() return false end }
    EbonBuilds.Scheduler = {
        CRITICAL = 1,
        INTERACTIVE = 2,
        After = function(id, delay, callback)
            scheduled[id] = callback
            scheduledDelays[id] = delay
            return true
        end,
        Cancel = function(id) scheduled[id] = nil; return true end,
    }
    EbonBuilds.EventHub = { On = function() return true end }
    EbonBuilds.DebugLog = {
        Add = function() end,
        AddF = function() end,
        IsEnabled = function() return false end,
    }
    EbonBuilds.Toast = {
        Show = function(message) toastMessages[#toastMessages + 1] = message end,
    }

    loadAddonFile("modules/integration/ProjectEbonholdAPI.lua")
    check(EbonBuilds.ProjectAPI.Init(), "Automation ProjectAPI init")
    loadAddonFile("modules/automation/BoardDecision.lua")
    loadAddonFile("modules/automation/Automation.lua")
    check(EbonBuilds.Automation.Init(), "Automation init")

    EbonBuilds.Automation.ResetInitialActionDelay()
    EbonBuilds.Automation._MarkInitialActionDelayCompleteForTests()
    EbonBuilds.Automation._ResetObservedBoardForTests(EbonBuilds.AutomationBoardDecision.STATE.IDLE)

    check(EbonBuilds.Automation.Evaluate(), "Evaluate defers on auto-accept loadout echo")
    equal(selectCalls, 0, "auto-accept deferral did not call SelectPerk")
    check(type(scheduled["automation.evaluate"]) == "function",
        "auto-accept deferral rescheduled evaluation")
    equal(scheduledDelays["automation.evaluate"], 2, "auto-accept deferral eval delay")
    equal(EbonBuilds.Automation._GetBoardStateForTests().state,
        EbonBuilds.AutomationBoardDecision.STATE.WAITING_FOR_BOARD_UPDATE,
        "auto-accept deferral board state")

    check(#toastMessages >= 1, "auto-accept conflict warning shown")
    check(toastMessages[1]:find("Auto%-Accept Loadout Echoes", 1, false) ~= nil,
        "auto-accept warning mentions PE option")
    EbonBuilds.Automation.WarnPeAutoAcceptConflict()
    equal(#toastMessages, 1, "auto-accept warning only once per login")

    ProjectEbonholdOptionsService = {
        GetSetting = function() return false end,
    }
    check(not EbonBuilds.Automation.IsPeAutoAcceptLoadoutEnabled(),
        "IsPeAutoAcceptLoadoutEnabled false when option off")
end

------------------------------------------------------------------------
-- Automation: ResolvePendingAction waits on server slot busy (#67)
------------------------------------------------------------------------
do
    now = 4000
    EbonBuildsDB.globalSettings.evalDelay = 2

    local slotPending = true
    ProjectEbonhold = { Perks = {} }
    EbonBuilds.ProjectAPI = {
        GetPendingAction = function()
            return slotPending and "slot" or nil
        end,
    }
    EbonBuilds.Scheduler = {
        CRITICAL = 1,
        After = function() return true end,
        Cancel = function() return true end,
    }
    EbonBuilds.Build = {
        GetActive = function() return { id = "build-slot-wait" } end,
        IsAutomationEnabled = function() return true end,
    }
    EbonBuilds.ManualTraining = { IsEnabled = function() return false end }
    EbonBuilds.DebugLog = {
        Add = function() end,
        AddF = function() end,
        IsEnabled = function() return false end,
    }

    loadAddonFile("modules/automation/BoardDecision.lua")
    loadAddonFile("modules/automation/IntentQueue.lua")
    loadAddonFile("modules/automation/Automation.lua")

    EbonBuilds.Automation._ResetObservedBoardForTests(EbonBuilds.AutomationBoardDecision.STATE.EVALUATING)
    local board = { identityFingerprint = "board-slot-wait" }
    equal(EbonBuilds.Automation._ResolvePendingActionForTests(board), "waiting",
        "ResolvePendingAction waits on server slot busy")
    equal(EbonBuilds.Automation._GetBoardStateForTests().state,
        EbonBuilds.AutomationBoardDecision.STATE.WAITING_FOR_BOARD_UPDATE,
        "server slot pending sets WAITING_FOR_BOARD_UPDATE")

    slotPending = false
    equal(EbonBuilds.Automation._ResolvePendingActionForTests(board), "none",
        "ResolvePendingAction clears after slot busy ends")
end

------------------------------------------------------------------------
-- Session: runMetadata carries pendingRollsCount from ProjectAPI (#67)
------------------------------------------------------------------------
do
    now = 5000
    EbonBuildsDB.sessions = {}
    EbonBuildsDB.currentSessionIndex = nil

    EbonBuilds.EventHub = {
        Bump = function() end,
    }
    EbonBuilds.SessionHistory = { OnHistoryChanged = function() end }
    EbonBuilds.Build = {
        GetActive = function() return { id = "build-meta", title = "Meta Build", revision = 1 } end,
        StrategyChecksum = function() return "stub-hash" end,
    }
    EbonBuilds.Database = {
        CharacterKey = function() return "Tester-Paladin" end,
    }
    EbonBuilds.ProjectAPI = {
        GetRunData = function()
            return { soulPoints = 12, hasReachedMaxLevel = false, catchupMultiplierPct = 0 }
        end,
        GetIntensityData = function()
            return { intensity = 1, areaNameReaper = "A", zoneNameReaper = "Z" }
        end,
        GetPendingRollsCount = function() return 6 end,
    }
    EbonBuilds.Scheduler = {
        BACKGROUND = 3,
        Every = function() return true end,
    }
    EbonBuilds.WoWEvents = {
        On = function(eventName, callback)
            if eventName == "PLAYER_ENTERING_WORLD" then
                callback()
            end
            return true
        end,
    }

    loadAddonFile("modules/session/Session.lua")
    EbonBuilds.Session.Init()

    local session = EbonBuildsDB.sessions[1]
    check(session ~= nil, "session created on entering world")
    check(session.runMetadata ~= nil, "runMetadata present on new session")
    equal(session.runMetadata.pendingRollsCount, 6, "pendingRollsCount stored in runMetadata")
    equal(session.runMetadata.intensity, 1, "intensity still routed through metadata")

    EbonBuilds.ProjectAPI.GetPendingRollsCount = nil
    EbonBuildsDB.currentSessionIndex = nil
    EbonBuildsDB.sessions = {}
    EbonBuilds.WoWEvents = {
        On = function(eventName, callback)
            if eventName == "PLAYER_ENTERING_WORLD" then callback() end
            return true
        end,
    }
    EbonBuilds.Session.Init()
    session = EbonBuildsDB.sessions[1]
    check(session and session.runMetadata and session.runMetadata.pendingRollsCount == nil,
        "missing rolls API omits pendingRollsCount from metadata")
end

if failures > 0 then
    io.stderr:write(string.format("\n%d pending rolls deferral test(s) failed.\n", failures))
    os.exit(1)
end

print("test_pending_rolls_deferral: ok")
