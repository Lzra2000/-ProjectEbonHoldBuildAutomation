-- Unit coverage for WP1 board lifecycle derivation and reroll freeze-lock.

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
assert(loadfile("modules/automation/BoardStateMachine.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", EbonBuilds)

local BSM = EbonBuilds.AutomationBoardStateMachine
local D = EbonBuilds.AutomationBoardDecision

local function Snapshot(overrides)
    local snapshot = {
        choices = {
            { spellId = 101, quality = 0 },
            { spellId = 102, quality = 0 },
        },
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = false },
        },
        frozenCount = 0,
        boardVisible = true,
    }
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do snapshot[key] = value end
    end
    return snapshot
end

local function BoardFromSnapshot(snapshot)
    local board = {
        slots = snapshot.slots,
        choices = snapshot.choices,
        frozenCount = snapshot.frozenCount or 0,
        pendingFreezeSlot = snapshot.pendingFreezeSlot,
        frozenStateUncertain = snapshot.frozenStateUncertain,
        pendingAction = snapshot.pendingAction,
        serverPendingAction = snapshot.serverPendingAction,
        runFrozenEchoIDs = snapshot.runFrozenEchoIDs,
        frozenThisBoardBySlot = snapshot.frozenThisBoardBySlot,
        frozenThisBoardEchoIDs = snapshot.frozenThisBoardEchoIDs,
        isValid = true,
        isStable = true,
        canReroll = true,
        pickIsAcceptable = false,
        freezeThreshold = 120,
        freezeResources = 2,
        maxFrozen = 2,
    }
    D.RefreshFrozenState(board)
    BSM.Attach(board, board)
    return board
end

------------------------------------------------------------------------
-- Derive transitions
------------------------------------------------------------------------
do
    local state, reason, source = BSM.Derive(Snapshot())
    equal(state, BSM.STATE.OPEN, "fresh board is OPEN")
    equal(reason, BSM.REASON.FRESH_BOARD, "fresh board reason")
    equal(source, "derived", "fresh board source")

    state = BSM.Derive(Snapshot({ pendingFreezeSlot = 2 }))
    equal(state, BSM.STATE.FROZEN_PENDING, "pending freeze slot -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({ serverPendingAction = "freeze" }))
    equal(state, BSM.STATE.FROZEN_PENDING, "server pending freeze -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({ frozenStateUncertain = true }))
    equal(state, BSM.STATE.FROZEN_PENDING, "uncertain freeze -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = true },
        },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "confirmed freeze flag -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        choices = {
            { spellId = 101, quality = 0 },
            { spellId = 102, quality = 0, justFrozen = true },
        },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "justFrozen choice -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        runFrozenEchoIDs = { [102] = true },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "run-persistent frozen echo -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        boardVisible = false,
        choices = {},
        pendingAction = "select",
    }))
    equal(state, BSM.STATE.SPENT, "select with hidden board -> SPENT")

    state = BSM.Derive(Snapshot({ serverBoardState = BSM.STATE.CONFIRMED }))
    equal(state, BSM.STATE.CONFIRMED, "server boardState wins when present")
    equal(BSM.Derive(Snapshot({ serverBoardState = BSM.STATE.CONFIRMED })), BSM.STATE.CONFIRMED,
        "server authoritative repeat")
end

------------------------------------------------------------------------
-- Reroll hard block
------------------------------------------------------------------------
do
    check(BSM.IsRerollBlocked(BSM.STATE.FROZEN_PENDING), "FROZEN_PENDING blocks reroll")
    check(BSM.IsRerollBlocked(BSM.STATE.CONFIRMED), "CONFIRMED blocks reroll")
    check(BSM.IsRerollBlocked(BSM.STATE.SPENT), "SPENT blocks reroll")
    check(not BSM.IsRerollBlocked(BSM.STATE.OPEN), "OPEN does not hard-block reroll")

    local board = BoardFromSnapshot(Snapshot({
        slots = {
            { index = 1, spellId = 101, score = 50, isValid = true },
            { index = 2, spellId = 102, score = 150, isFrozen = true, isValid = true },
        },
        frozenCount = 1,
    }))
    local allowed, reason = D.CanReroll(board)
    check(not allowed, "CanReroll rejects CONFIRMED lifecycle")
    check(reason and reason:find("confirmed freeze", 1, true) ~= nil,
        "CanReroll reason mentions confirmed freeze")

    board = BoardFromSnapshot(Snapshot({ pendingFreezeSlot = 2 }))
    allowed = D.CanReroll(board)
    check(not allowed, "CanReroll rejects FROZEN_PENDING lifecycle")
end

------------------------------------------------------------------------
-- Decide integration
------------------------------------------------------------------------
do
    local board = BoardFromSnapshot(Snapshot({ pendingFreezeSlot = 2 }))
    local decision = D.Decide(board)
    equal(decision.action, "WAIT_FOR_FREEZE", "Decide waits on FROZEN_PENDING lifecycle")
end

if failures > 0 then
    io.stderr:write(string.format("\n%d board state machine test(s) failed.\n", failures))
    os.exit(1)
end

print("test_board_state_machine: ok")
