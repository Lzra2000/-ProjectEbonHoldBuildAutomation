-- Select Logbook dedup: log only after Board-Ack; Intent TTL retries must not
-- spam identical Select rows while the offer identity is unchanged.

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("SELECT DEDUP FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

local now = 1000
function GetTime() return now end

EbonBuildsDB = { globalSettings = { evalDelay = 2 } }

local loggedActions = {}
local selectRequests = 0
local liveChoices = {
    { spellId = 200744, quality = 3 },
    { spellId = 102, quality = 0 },
}
local build = { stats = { picks = 0, qualityPicks = {}, mostPicked = {} } }

local addon = {
    Build = {
        GetActive = function() return build end,
        IsAutomationEnabled = function() return true end,
    },
    ManualTraining = { IsEnabled = function() return false end },
    ProjectAPI = {
        GetCurrentChoice = function() return liveChoices end,
        RequestSelect = function()
            selectRequests = selectRequests + 1
            return true
        end,
        RequestBanish = function() return true end,
        RequestReroll = function() return true end,
        GetPendingAction = function() return nil end,
    },
    Scheduler = {
        CRITICAL = 1,
        INTERACTIVE = 2,
        After = function() return true end,
        Cancel = function() return true end,
    },
    DebugLog = {
        Add = function() end,
        AddF = function() end,
        IsEnabled = function() return false end,
    },
    Toast = { Show = function() end, ShowAutomationResult = function() end },
    Session = {
        LogAction = function(_, action, targetIndex)
            loggedActions[#loggedActions + 1] = { action = action, targetIndex = targetIndex }
        end,
    },
    Scoring = {
        GetEffectiveSettings = function() return {} end,
        IsBanned = function() return false end,
        IsWhitelisted = function() return false end,
        IsBetterCandidate = function() return false end,
    },
}

assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/IntentQueue.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/Automation.lua"))("EbonBuilds", addon)

local D = addon.AutomationBoardDecision
local IQ = addon.AutomationIntentQueue

local function MakeBoard(identity, spellId)
    local raw = {
        slots = {
            { index = 1, spellId = spellId or 200744, isFrozen = false, isCarried = false },
            { index = 2, spellId = 102, isFrozen = false, isCarried = false },
        },
        isValid = true,
        isStable = true,
    }
    local board = {
        slots = {
            { index = 1, spellId = spellId or 200744, name = "Unstable Infusion", score = 205, isValid = true },
            { index = 2, spellId = 102, name = "Other", score = 50, isValid = true },
        },
        isValid = true,
        isStable = true,
        fingerprint = D.Fingerprint(raw),
        identityFingerprint = identity,
        frozenCount = 0,
        maxFrozen = 2,
        freezeResources = 0,
        canReroll = true,
        canBanish = true,
        pickIsAcceptable = true,
        rerollThreshold = 100,
    }
    return board
end

------------------------------------------------------------------------
-- Select does not Logbook until Board-Ack
------------------------------------------------------------------------
do
    loggedActions = {}
    selectRequests = 0
    build.stats = { picks = 0, qualityPicks = {}, mostPicked = {} }
    addon.Automation._ResetFreezeRound()
    addon.Automation._MarkInitialActionDelayCompleteForTests()
    IQ.Reset()
    now = 2000

    local board = MakeBoard("board-a", 200744)
    check(addon.Automation._ExecuteDecisionForTests(build, board, {
        action = "SELECT",
        target = board.slots[1],
        reason = "highest",
    }), "first Select request accepted")
    equal(selectRequests, 1, "SelectPerk requested once")
    equal(#loggedActions, 0, "Select must not Logbook before Board-Ack")
    equal(build.stats.picks or 0, 0, "pick stats must wait for Board-Ack")

    local state = addon.Automation._GetBoardStateForTests()
    equal(state.pendingAction, "select", "pending select stored")
    equal(state.selectAttemptIdentity, "board-a", "select attempt identity stored")
    check(state.pendingLogDecision ~= nil, "deferred Logbook decision stored")
end

------------------------------------------------------------------------
-- Identical Select on unchanged board is deduped (TTL retry path)
------------------------------------------------------------------------
do
    now = 2010
    local board = MakeBoard("board-a", 200744)
    -- Simulate Intent TTL clearing the in-flight intent + pendingAction while
    -- leaving the selectAttempt markers (ResolveIntentQueueAck timeout path).
    local state = addon.Automation._GetBoardStateForTests()
    state.pendingAction = nil
    state.pendingActionIdentity = nil
    state.pendingActionFingerprint = nil
    IQ.Reset()

    local beforeLogs = #loggedActions
    local beforeRequests = selectRequests
    check(addon.Automation._ExecuteDecisionForTests(build, board, {
        action = "SELECT",
        target = board.slots[1],
        reason = "retry",
    }), "deduped Select still returns true (wait)")
    equal(selectRequests, beforeRequests, "identical Select must not re-request")
    equal(#loggedActions, beforeLogs, "identical Select must not Logbook")
end

------------------------------------------------------------------------
-- Board-Ack commits exactly one Logbook Select
------------------------------------------------------------------------
do
    local board = MakeBoard("board-b", 200744)
    equal(addon.Automation._ResolvePendingActionForTests(board), "changed",
        "identity change acknowledges deferred Select")
    equal(#loggedActions, 1, "Board-Ack logs Select exactly once")
    equal(loggedActions[1].action, "Select", "Board-Ack uses Select action")
    equal(loggedActions[1].targetIndex, 1, "Board-Ack logs correct target")
    equal(build.stats.picks, 1, "pick stats recorded on Board-Ack")

    local state = addon.Automation._GetBoardStateForTests()
    check(state.pendingLogDecision == nil, "deferred decision cleared after ack")
    check(state.selectAttemptIdentity == nil, "select attempt cleared after ack")
end

------------------------------------------------------------------------
-- Intent TTL alone must not Logbook a Select
------------------------------------------------------------------------
do
    loggedActions = {}
    selectRequests = 0
    build.stats = { picks = 0, qualityPicks = {}, mostPicked = {} }
    addon.Automation._ResetFreezeRound()
    IQ.Reset()
    now = 3000

    local board = MakeBoard("board-ttl", 200744)
    check(addon.Automation._ExecuteDecisionForTests(build, board, {
        action = "SELECT",
        target = board.slots[1],
        reason = "ttl",
    }), "Select accepted before TTL")
    equal(#loggedActions, 0, "pre-TTL Select not logged")

    now = now + 9
    equal(addon.Automation._ResolvePendingActionForTests(board), "none",
        "TTL on unchanged board does not count as Board-Ack")
    equal(#loggedActions, 0, "Intent TTL must not Logbook Select")

    -- Dedup still blocks a re-request on the same board.
    local before = selectRequests
    check(addon.Automation._ExecuteDecisionForTests(build, board, {
        action = "SELECT",
        target = board.slots[1],
        reason = "post-ttl",
    }), "post-TTL dedup wait")
    equal(selectRequests, before, "post-TTL identical Select still deduped")
    equal(#loggedActions, 0, "post-TTL identical Select still not logged")
end

if failures > 0 then
    io.stderr:write(string.format("SELECT DEDUP: %d failure(s)\n", failures))
    os.exit(1)
end
print("Verified Select Logbook commits only after Board-Ack and identical TTL retries are deduped.")
