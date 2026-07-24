-- Focused regression coverage for run-persistent frozenEchoIDs (#59).
-- Exercises board hide/show, identity churn, recovery, pick/run-end clearing,
-- and BoardDecision integration without duplicating the full recovery suite.

local function fail(message)
    io.stderr:write("FREEZE PERSISTENCE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local function check(value, message)
    if not value then fail(message) end
end

EbonBuildsDB = { globalSettings = { evalDelay = 2 } }

local eventHandlers = {}
local build = { stats = {} }
local choices = {}
local addon = {
    Build = {
        GetActive = function() return build end,
        IsAutomationEnabled = function() return true end,
    },
    ManualTraining = { IsEnabled = function() return false end },
    ProjectAPI = {
        GetCurrentChoice = function() return choices end,
        RequestFreeze = function() return true end,
        RequestSelect = function() return true end,
        RequestReroll = function() return true end,
    },
    Scheduler = {
        CRITICAL = 1, INTERACTIVE = 2,
        After = function() return true end,
        Cancel = function() return true end,
    },
    DebugLog = {
        Add = function() end,
        AddF = function() end,
        IsEnabled = function() return false end,
    },
    Toast = { Show = function() end, ShowAutomationResult = function() end },
    Session = { LogAction = function() end },
    EventHub = {
        On = function(event, handler, _)
            eventHandlers[event] = eventHandlers[event] or {}
            eventHandlers[event][#eventHandlers[event] + 1] = handler
        end,
    },
}

assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/Automation.lua"))("EbonBuilds", addon)

local D = addon.AutomationBoardDecision
local A = addon.Automation

local function Emit(event, ...)
    for _, handler in ipairs(eventHandlers[event] or {}) do
        handler(...)
    end
end

local function Slot(index, spellId, score, flags)
    local slot = {
        index = index,
        spellId = spellId,
        name = "Echo " .. tostring(spellId),
        score = score,
        isValid = true,
    }
    for key, value in pairs(flags or {}) do slot[key] = value end
    return slot
end

local function Board(slots, overrides)
    local board = {
        slots = slots,
        isValid = true,
        isStable = true,
        maxFrozen = 2,
        freezeThreshold = 120,
        freezeResources = 2,
        canReroll = true,
        canBanish = false,
        pickIsAcceptable = false,
        frozenThisBoardBySlot = {},
        frozenThisBoardEchoIDs = {},
    }
    for key, value in pairs(overrides or {}) do board[key] = value end
    D.RefreshFrozenState(board)
    board.fingerprint = D.Fingerprint(board)
    board.identityFingerprint = D.IdentityFingerprint(board)
    return board
end

A._MarkInitialActionDelayCompleteForTests()

------------------------------------------------------------------------
-- BoardDecision: runFrozenEchoIDs merge and duplicate suppression
------------------------------------------------------------------------
do
    local runMarks = { [501] = true, [502] = true }
    local board = Board({
        Slot(1, 501, 180),
        Slot(2, 502, 150),
        Slot(3, 503, 140),
    }, { runFrozenEchoIDs = runMarks })
    equal(board.frozenCount, 2, "run-persistent marks count toward frozen capacity")
    equal(D.FindBestFreezeCandidate(board, board.slots[1]), nil,
        "full run-persistent capacity suppresses another freeze")
    local allowed = D.CanReroll(board)
    equal(allowed, false, "two run-persistent echoes block reroll")

    local partial = Board({
        Slot(1, 601, 180),
        Slot(2, 602, 150),
        Slot(3, 603, 130),
    }, { runFrozenEchoIDs = { [602] = true } })
    local freezeTarget = D.FindBestFreezeCandidate(partial, partial.slots[1])
    check(freezeTarget, "second freeze slot remains available with one run mark")
    equal(freezeTarget.spellId, 603, "run-frozen echo is not re-targeted for freeze")
    equal(freezeTarget.index, 3, "freeze candidate skips run-persistent duplicate")
end

------------------------------------------------------------------------
-- echoId key path (spellId omitted, as some projections use echoId)
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local echoBoard = Board({
        { index = 1, echoId = "ref-701", name = "Pick", score = 160, isValid = true },
        { index = 2, echoId = "ref-702", name = "Freeze", score = 130, isValid = true },
    })
    check(A._RequestFreezeForTests(build, echoBoard, echoBoard.slots[2]),
        "echoId-only freeze request was rejected")
    local state = A._GetBoardStateForTests()
    check(state.frozenEchoIDs["ref-702"], "echoId freeze recorded run-persistently")

    local nextBoard = Board({
        { index = 1, echoId = "ref-801", name = "Fresh", score = 170, isValid = true },
        { index = 2, echoId = "ref-702", name = "Still frozen", score = 130, isValid = true },
    }, { runFrozenEchoIDs = state.frozenEchoIDs })
    equal(nextBoard.frozenCount, 1, "echoId run mark survives identity churn")
    equal(D.CanReroll(nextBoard), false, "echoId run mark blocks reroll without server flags")
end

------------------------------------------------------------------------
-- ResetObservedBoard vs ResetFreezeRound
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local board = Board({ Slot(1, 901, 160), Slot(2, 902, 130) })
    check(A._RequestFreezeForTests(build, board, board.slots[2]), "setup freeze failed")
    local state = A._GetBoardStateForTests()
    check(state.frozenEchoIDs[902], "setup did not record run-persistent mark")

    A._ResetObservedBoardForTests()
    check(state.frozenEchoIDs[902], "ResetObservedBoard must keep run-persistent marks")
    check(not state.frozenThisBoardEchoIDs[902],
        "ResetObservedBoard must clear current-board marks")

    A._ResetFreezeRound()
    check(not state.frozenEchoIDs[902], "ResetFreezeRound must clear run-persistent marks")
end

------------------------------------------------------------------------
-- Recovery resolved: UnmarkFrozenThisBoard clears this-board only (#59)
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local board = Board({ Slot(1, 1001, 160), Slot(2, 1002, 130) })
    check(A._RequestFreezeForTests(build, board, board.slots[2]), "recovery setup freeze failed")
    local state = A._GetBoardStateForTests()
    state.frozenStateUncertain = true
    state.uncertainFreezeSlot = 2
    state.uncertainFreezeEchoID = 1002
    state.uncertainFreezeIdentity = board.identityFingerprint
    state.uncertainFreezeChecks = 1
    state.uncertainFreezeUsedCount = 0
    state.failedFreezeBySlot[2] = true
    state.frozenThisBoardBySlot[2] = true
    state.frozenThisBoardEchoIDs[1002] = true

    equal(A._ResolveFreezeUncertaintyForTests(build, board, { totalFreezes = 3, usedFreezes = 0 }),
        "resolved", "uncertainty recovery did not resolve")
    check(not state.frozenThisBoardEchoIDs[1002],
        "resolved recovery cleared current-board mark")
    check(state.frozenEchoIDs[1002],
        "resolved recovery must keep run-persistent mark until pick/run end")

    local rerollBoard = Board({
        Slot(1, 1101, 50, { isAvoided = true, policyBlocked = true, policyEffect = "exclude" }),
        Slot(2, 1002, 130),
    }, { runFrozenEchoIDs = state.frozenEchoIDs, pickIsAcceptable = false })
    equal(D.CanReroll(rerollBoard), false,
        "resolved recovery must not reopen reroll while run mark remains")
    equal(D.Decide(rerollBoard).action, "SELECT",
        "resolved recovery still selects through run-persistent freeze")
end

------------------------------------------------------------------------
-- Two accepted freezes without server isFrozen flags
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local first = Board({
        Slot(1, 1201, 180),
        Slot(2, 1202, 150),
        Slot(3, 1203, 130),
    })
    local decision = D.Decide(first)
    equal(decision.action, "FREEZE", "first board should freeze")
    check(A._RequestFreezeForTests(build, first, decision.target), "first freeze request failed")
    local state = A._GetBoardStateForTests()

    A._ResetObservedBoardForTests()
    local second = Board({
        Slot(1, 1301, 190),
        Slot(2, 1203, 130),
        Slot(3, 1303, 145),
    }, { runFrozenEchoIDs = state.frozenEchoIDs })
    decision = D.Decide(second)
    equal(decision.action, "FREEZE", "second board should freeze another echo")
    check(A._RequestFreezeForTests(build, second, decision.target), "second freeze request failed")
    check(state.frozenEchoIDs[1202] and state.frozenEchoIDs[1303],
        "two distinct run-persistent marks must coexist")

    A._ResetObservedBoardForTests()
    local third = Board({
        Slot(1, 1401, 200),
        Slot(2, 1202, 150),
        Slot(3, 1303, 145),
    }, { runFrozenEchoIDs = state.frozenEchoIDs, freezeResources = 0 })
    equal(third.frozenCount, 2, "two run marks enforce board capacity without server flags")
    equal(D.Decide(third).action, "SELECT", "third board selects instead of a third freeze")
    equal(D.CanReroll(third), false, "two run marks block reroll on a weak board")
end

------------------------------------------------------------------------
-- Pick clears only the selected echo's run-persistent mark
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local state = A._GetBoardStateForTests()
    state.frozenEchoIDs[1501] = true
    state.frozenEchoIDs[1502] = true

    choices = { { spellId = 1501 }, { spellId = 1502 } }
    local raw = {
        slots = {
            { index = 1, spellId = 1501, isFrozen = false },
            { index = 2, spellId = 1502, isFrozen = false },
        },
    }
    local pickBoard = Board({
        Slot(1, 1501, 170),
        Slot(2, 1502, 140),
    }, {
        fingerprint = D.Fingerprint(raw),
        identityFingerprint = D.IdentityFingerprint(raw),
        runFrozenEchoIDs = state.frozenEchoIDs,
        freezeResources = 0,
    })
    check(A._ExecuteDecisionForTests(build, pickBoard, {
        action = "SELECT",
        target = pickBoard.slots[1],
        reason = "pick non-frozen echo",
    }), "select request failed")
    check(not state.frozenEchoIDs[1501], "picked echo cleared its run mark")
    check(state.frozenEchoIDs[1502], "other run mark survived unrelated pick")
end

------------------------------------------------------------------------
-- Pending confirmation adds run-persistent mark via CommitConfirmedFreeze
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local board = Board({ Slot(1, 1601, 160), Slot(2, 1602, 130) })
    check(A._RequestFreezeForTests(build, board, board.slots[2]), "pending confirm setup failed")
    local state = A._GetBoardStateForTests()
    check(state.frozenEchoIDs[1602], "accepted request already run-persistent")

    A._ResetObservedBoardForTests()
    check(state.frozenEchoIDs[1602], "board hide/show before confirm kept run mark")

    local confirmed = Board({ Slot(1, 1601, 160), Slot(2, 1602, 130, { isFrozen = true }) })
    equal(A._ResolvePendingFreezeForTests(build, confirmed, { totalFreezes = 3, usedFreezes = 0 }),
        "confirmed", "pending freeze was not confirmed")
    check(state.frozenEchoIDs[1602], "confirmed freeze retained run-persistent mark")
end

------------------------------------------------------------------------
-- RUN_ENDED clears run-persistent marks (Init hook registration)
------------------------------------------------------------------------
do
    A._ResetFreezeRound()
    local state = A._GetBoardStateForTests()
    state.frozenEchoIDs[1701] = true

    function hooksecurefunc(_, _, fn) fn() end
    ProjectEbonhold = {
        PerkUI = {
            Show = function() end,
            Hide = function() end,
            ResetSelection = function() end,
            UpdateSinglePerk = function() end,
        },
    }
    check(A.Init(), "Automation.Init did not install hooks")
    Emit("RUN_ENDED")
    check(not state.frozenEchoIDs[1701], "RUN_ENDED must clear run-persistent frozen echoes")
end

print("Verified run-persistent frozenEchoIDs (#59): merge, recovery, reset boundaries, pick/run-end clearing, and duplicate suppression.")
