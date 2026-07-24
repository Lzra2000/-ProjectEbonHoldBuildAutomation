-- Expanded unit coverage for BoardDecision, Automation scoring hooks, IntentQueue
-- guards, freeze-first reroll locks, and deterministic tie-break ordering.

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
local function truthy(value, message)
    check(value and true or false, message)
end

local now = 1000
function GetTime() return now end

ProjectEbonhold = { Perks = {} }
EbonBuildsDB = { globalSettings = { evalDelay = 2 } }

local addon = {
    Build = {
        GetActive = function() return { class = "MAGE", stats = {} } end,
        IsAutomationEnabled = function() return true end,
    },
    ManualTraining = { IsEnabled = function() return false end },
    ProjectAPI = {
        GetCurrentChoice = function() return {} end,
        GetPendingAction = function()
            local perks = ProjectEbonhold.Perks
            if perks.pendingSelectSpellId ~= nil then return "select" end
            if perks.pendingBanishIndex ~= nil then return "banish" end
            if perks.pendingFreezeIndex ~= nil then return "freeze" end
            if perks.pendingReroll then return "reroll" end
            if perks.pendingBuildSlotRequest then return "slot" end
            return nil
        end,
    },
    Scheduler = { CRITICAL = 1, After = function() return true end, Cancel = function() return true end },
    DebugLog = { Add = function() end, AddF = function() end, IsEnabled = function() return false end },
    Toast = { Show = function() end, ShowAutomationResult = function() end },
    Session = { LogAction = function() end },
    EchoProjection = {
        ResolveOfferedSpell = function(_, spellId)
            return { refKey = "ref" .. spellId, displayName = "Echo " .. spellId }, { quality = 0 }
        end,
    },
    Weights = { GetForSpell = function() return 10 end },
    Scoring = {
        Score = function() return 100 end,
        ScorePerQuality = function() return 100 end,
    },
}

bit = bit or {
    band = function() return 0 end,
    bor = function() return 0 end,
}

assert(loadfile("modules/build/Scoring.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/BoardStateMachine.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/IntentQueue.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/Automation.lua"))("EbonBuilds", addon)

local S = addon.Scoring
local BSM = addon.AutomationBoardStateMachine
local D = addon.AutomationBoardDecision
local IQ = addon.AutomationIntentQueue

local function Slot(id, score, flags)
    local slot = { spellId = id, name = "Echo " .. tostring(id), score = score, isValid = true }
    for key, value in pairs(flags or {}) do slot[key] = value end
    return slot
end

local function Board(slots, options)
    local board = {
        slots = slots,
        isValid = true,
        isStable = true,
        maxFrozen = 2,
        freezeThreshold = 120,
        freezeResources = 2,
        canReroll = true,
        canBanish = false,
        frozenThisBoardBySlot = {},
        frozenThisBoardEchoIDs = {},
    }
    for key, value in pairs(options or {}) do board[key] = value end
    for i, slot in ipairs(slots) do
        slot.index = slot.index or i
        if slot.frozenThisBoard then
            board.frozenThisBoardBySlot[i] = true
            board.frozenThisBoardEchoIDs[slot.spellId] = true
        end
    end
    D.RefreshFrozenState(board)
    if BSM then BSM.Attach(board, board) end
    return board
end

local function Decision(board, expected, message)
    local result = D.Decide(board)
    equal(result.action, expected, message)
    return result
end

local function Sequence(board, limit)
    local actions = {}
    for _ = 1, limit or 8 do
        local result = D.Decide(board)
        local suffix = result.target and (":" .. tostring(result.target.index)) or ""
        actions[#actions + 1] = result.action .. suffix
        if result.action == "FREEZE" then
            result.target.isFrozen = true
            board.frozenThisBoardBySlot[result.target.index] = true
            board.frozenThisBoardEchoIDs[result.target.spellId] = true
            board.freezeResources = math.max(0, board.freezeResources - 1)
            D.RefreshFrozenState(board)
        else
            break
        end
    end
    return table.concat(actions, ",")
end

------------------------------------------------------------------------
-- Frozen Echo state blocks reroll (zero-frozen invariant)
------------------------------------------------------------------------
do
    local zeroFrozen = Board({ Slot(101, 10, { isAvoided = true }) })
    local allowed, reason = D.CanReroll(zeroFrozen)
    equal(allowed, true, "reroll allowed with exactly zero frozen Echoes")
    Decision(zeroFrozen, "REROLL", "zero-frozen no-pick board may reroll")

    local oneFrozen = Board({ Slot(101, 10, { isFrozen = true, isAvoided = true }) })
    allowed, reason = D.CanReroll(oneFrozen)
    equal(allowed, false, "reroll blocked when one Echo is frozen")
    truthy(reason and (reason:find("confirmed freeze", 1, true)
        or reason:find("frozen Echo", 1, true)),
        "one-frozen reroll reason mentions confirmed freeze or frozen Echo")

    local carriedOnly = Board({
        Slot(101, 150, { isCarried = true }),
        Slot(102, 20, { isAvoided = true }),
    }, { pickIsAcceptable = false })
    allowed = D.CanReroll(carriedOnly)
    equal(allowed, false, "carried Echo counts toward frozenCount and blocks reroll")

    local runPersistent = Board({
        Slot(101, 50, { isAvoided = true }),
        Slot(102, 40, { isAvoided = true }),
    }, { runFrozenEchoIDs = { [101] = true } })
    D.RefreshFrozenState(runPersistent)
    equal(runPersistent.frozenCount, 1, "runFrozenEchoIDs increments frozenCount without isFrozen flag")
    allowed, reason = D.CanReroll(runPersistent)
    equal(allowed, false, "run-persistent frozen Echo blocks reroll")
    truthy(reason and (reason:find("confirmed freeze", 1, true)
        or reason:find("frozen", 1, true)),
        "run-persistent reroll reason mentions confirmed freeze or frozen state")

    local lifecycleBoard = Board({
        Slot(101, 50, { isValid = true, score = 50 }),
        Slot(102, 150, { isFrozen = true, isValid = true, score = 150 }),
    }, { pickIsAcceptable = false })
    allowed, reason = D.CanReroll(lifecycleBoard)
    equal(allowed, false, "BSM CONFIRMED lifecycle blocks CanReroll")
    truthy(reason and reason:find("confirmed freeze", 1, true),
        "lifecycle reroll block reason mentions confirmed freeze")

    local pendingFreeze = Board({ Slot(101, 10, { isAvoided = true }) }, {
        pendingFreezeSlot = 1, pendingFreezeEchoID = 101,
    })
    equal(D.CanReroll(pendingFreeze), false, "pending freeze confirmation blocks reroll")
    Decision(pendingFreeze, "WAIT_FOR_FREEZE", "Decide waits while freeze confirmation is pending")

    local unsecured = Board({ Slot(101, 160), Slot(102, 130) })
    allowed, reason = D.CanReroll(unsecured)
    equal(allowed, false, "unsecured freeze candidate blocks reroll")
    truthy(reason and reason:find("freezing", 1, true),
        "unsecured freeze reroll reason mentions freezing requirement")
end

------------------------------------------------------------------------
-- Equal-score tie-break order (select vs freeze paths)
------------------------------------------------------------------------
do
    local left = Slot(101, 150, { index = 1 })
    local right = Slot(102, 150, { index = 2 })
    check(S.IsBetterCandidate(left, right, { preferFrozen = true }),
        "select tie-break prefers lower slot index on equal score")
    equal(D.FindBestLegalPick(Board({ left, right })).index, 1,
        "BoardDecision select honors slot-index fallback")

    local frozenLeft = Slot(101, 150, { index = 1, isFrozen = true, isCarried = true })
    local freshRight = Slot(102, 150, { index = 2 })
    check(S.IsBetterCandidate(frozenLeft, freshRight, { preferFrozen = true }),
        "select tie-break prefers frozen/carried on equal score")
    check(D._IsBetter(frozenLeft, freshRight),
        "BoardDecision select path prefers frozen/carried on equal score")
    check(D._IsBetterFreezeCandidate(frozenLeft, freshRight),
        "freeze tie-break keeps lower slot index when frozen pref is off")
    check(not D._IsBetterFreezeCandidate(freshRight, frozenLeft),
        "freeze tie-break rejects higher slot index on equal score")

    equal(Sequence(Board({ Slot(101, 150), Slot(102, 150), Slot(103, 150) })),
        "FREEZE:2,FREEZE:3,SELECT:1",
        "equal-score freeze-first sequence is slot-deterministic without ranks")

    local rankedEqual = Board({
        Slot(101, 150, { rank = 3 }),
        Slot(102, 150, { rank = 2 }),
        Slot(103, 150, { rank = 1 }),
    })
    equal(Sequence(rankedEqual), "FREEZE:2,FREEZE:1,SELECT:3",
        "server ranks reorder freeze/select while staying deterministic")

    local dupFresh = Slot(102, 150, { index = 2, rank = 1 })
    local dupFrozen = Slot(102, 150, { index = 3, rank = 1, isFrozen = true })
    check(D._IsBetter(dupFresh, dupFrozen),
        "select path resolves duplicate-echo ties by slot before frozen pref")
    check(D._IsBetterFreezeCandidate(dupFresh, dupFrozen),
        "freeze path resolves duplicate-echo ties by slot index alone")
end

------------------------------------------------------------------------
-- Pending action / slot-busy wait paths
------------------------------------------------------------------------
do
    Decision(Board({ Slot(101, 160), Slot(102, 130) }, { pendingAction = "select" }),
        "WAIT", "pendingAction blocks Decide with WAIT")

    Decision(Board({ Slot(101, 160), Slot(102, 130) }, {
        pendingFreezeSlot = 2, pendingFreezeEchoID = 102,
    }), "WAIT_FOR_FREEZE", "pendingFreezeSlot blocks Decide with WAIT_FOR_FREEZE")

    local bsmPending = Board({ Slot(101, 160), Slot(102, 130) }, { pendingFreezeSlot = 2 })
    BSM.Attach(bsmPending, bsmPending)
    equal(bsmPending.lifecycleState, BSM.STATE.FROZEN_PENDING, "BSM derives FROZEN_PENDING from pending slot")
    Decision(bsmPending, "WAIT_FOR_FREEZE", "Decide waits on FROZEN_PENDING lifecycle")

    IQ.Reset()
    ProjectEbonhold.Perks.pendingBuildSlotRequest = "save"
    local accepted, reason = IQ.TryBegin("select", IQ.BuildSnapshot({ offerId = "o1" }, { index = 1 }))
    equal(accepted, false, "IntentQueue rejects new intent while build-slot request is pending")
    equal(reason, "server_pending_slot", "slot-busy maps to server_pending_slot reason code")
    equal(IQ.DescribeBlock(reason), "ProjectEbonhold build-slot request in flight",
        "slot-busy block message is user-facing")
    ProjectEbonhold.Perks.pendingBuildSlotRequest = nil

    IQ.Reset()
    accepted = IQ.TryBegin("freeze", IQ.BuildSnapshot({ offerId = "o1", identityFingerprint = "a" },
        { index = 2 }))
    equal(accepted, true, "first freeze intent accepted")
    accepted = IQ.TryBegin("select", IQ.BuildSnapshot({ offerId = "o1", identityFingerprint = "a" },
        { index = 1 }))
    equal(accepted, false, "second intent rejected while one is in flight")
    equal(IQ.IsBlocking(IQ.BuildSnapshot({ identityFingerprint = "a" })), true,
        "IntentQueue remains blocking until ack")
end

------------------------------------------------------------------------
-- Freeze penalty applies only below the freeze threshold (Automation scoring)
------------------------------------------------------------------------
do
    -- _ScoreChoice reads EbonBuilds.Scoring at call time; stub only the score
    -- functions so penalty math is deterministic while CompareCandidates stays real.
    addon.Scoring.Score = function() return 100 end
    addon.Scoring.ScorePerQuality = function() return 100 end
    local penaltySettings = { freezePenaltyPct = 10 }
    local worthyCarry = addon.Automation._ScoreChoice(
        { spellId = 401, quality = 0, isCarried = true, isFrozen = true }, penaltySettings, 90)
    equal(worthyCarry.score, 100, "freeze-worthy carry keeps full score (no penalty)")

    local weakCarry = addon.Automation._ScoreChoice(
        { spellId = 402, quality = 0, isCarried = true, isFrozen = true }, penaltySettings, 110)
    equal(weakCarry.score, 90, "below-threshold carry receives freeze penalty")

    local freshOffer = addon.Automation._ScoreChoice(
        { spellId = 404, quality = 0 }, penaltySettings, 110)
    equal(freshOffer.score, 100, "fresh offers are never freeze-penalized")

    -- BoardDecision consumes already-penalized slot scores from BuildBoard.
    local penalizedBoard = Board({
        Slot(501, 90, { isCarried = true, isFrozen = true }),
        Slot(502, 95),
        Slot(503, 20),
    }, { freezeThreshold = 120, freezeResources = 0, pickIsAcceptable = true })
    local penalizedPick = D.FindBestLegalPick(penalizedBoard)
    equal(penalizedPick.index, 2, "penalized carry loses select to a stronger fresh Echo")

    local strongCarryBoard = Board({
        Slot(601, 130, { isCarried = true, isFrozen = true }),
        Slot(602, 125),
        Slot(603, 20),
    }, { freezeThreshold = 120, freezeResources = 0 })
    equal(D.FindBestLegalPick(strongCarryBoard).index, 1,
        "still-freeze-worthy carry score wins over fresh secondary")
end

if failures > 0 then
    io.stderr:write(string.format("\ntest_board_decision_coverage: %d failure(s)\n", failures))
    os.exit(1)
end

print("test_board_decision_coverage: ok")
