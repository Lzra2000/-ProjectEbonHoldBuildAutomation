-- Unit coverage for WP3 client intent queue (#52).

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

local now = 1000
function GetTime() return now end

ProjectEbonhold = { Perks = {} }
EbonBuilds = { ProjectAPI = {} }

function EbonBuilds.ProjectAPI.GetPendingAction()
    local perks = ProjectEbonhold.Perks
    if perks.pendingSelectSpellId ~= nil then return "select" end
    if perks.pendingBanishIndex ~= nil then return "banish" end
    if perks.pendingFreezeIndex ~= nil then return "freeze" end
    if perks.pendingReroll then return "reroll" end
    return nil
end

assert(loadfile("modules/automation/IntentQueue.lua"))("EbonBuilds", EbonBuilds)
local IQ = EbonBuilds.AutomationIntentQueue

local function Snapshot(overrides)
    local snapshot = {
        offerId = "offer-1",
        identityFingerprint = "board-a",
        targetSlot = 1,
    }
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do snapshot[key] = value end
    end
    return snapshot
end

------------------------------------------------------------------------
-- TryBegin exclusivity
------------------------------------------------------------------------
do
    IQ.Reset()
    local accepted, id = IQ.TryBegin("select", Snapshot())
    equal(accepted, true, "first select intent accepted")
    check(type(id) == "number", "select intent id is numeric")

    accepted = IQ.TryBegin("banish", Snapshot({ targetSlot = 2 }))
    equal(accepted, false, "second intent rejected while one is in flight")
    equal(IQ.IsBlocking(Snapshot()), true, "queue blocks while in flight")

    accepted = IQ.TryBegin("select", Snapshot())
    equal(accepted, false, "duplicate select intent rejected")
end

------------------------------------------------------------------------
-- Server pending flags block new intents
------------------------------------------------------------------------
do
    IQ.Reset()
    ProjectEbonhold.Perks.pendingReroll = true
    local accepted = IQ.TryBegin("reroll", Snapshot())
    equal(accepted, false, "new intent blocked while PE reroll pending")
    equal(IQ.GetInFlight(), nil, "blocked intent did not enter queue")
    ProjectEbonhold.Perks.pendingReroll = nil
end

------------------------------------------------------------------------
-- Ack via board identity change
------------------------------------------------------------------------
do
    IQ.Reset()
    local accepted = IQ.TryBegin("banish", Snapshot({ targetSlot = 2 }))
    equal(accepted, true, "banish intent accepted for ack test")
    equal(IQ.PollAck(Snapshot({ identityFingerprint = "board-b" })), "board_ack",
        "identity change clears in-flight intent")
    equal(IQ.GetInFlight(), nil, "queue empty after board ack")
end

------------------------------------------------------------------------
-- Ack via pending-flag drop
------------------------------------------------------------------------
do
    IQ.Reset()
    local accepted = IQ.TryBegin("select", Snapshot())
    equal(accepted, true, "select intent accepted for pending ack test")

    ProjectEbonhold.Perks.pendingSelectSpellId = 101
    equal(IQ.PollAck(Snapshot()), "waiting", "server pending keeps intent in flight")

    ProjectEbonhold.Perks.pendingSelectSpellId = nil
    equal(IQ.PollAck(Snapshot()), "pending_ack", "pending-flag drop acks intent")
    equal(IQ.GetInFlight(), nil, "queue empty after pending ack")
end

------------------------------------------------------------------------
-- Timeout clears stale intent
------------------------------------------------------------------------
do
    IQ.Reset()
    now = 1000
    local accepted = IQ.TryBegin("freeze", Snapshot({ targetSlot = 1 }))
    equal(accepted, true, "freeze intent accepted for timeout test")
    local startedAt = IQ.GetInFlight().startedAt
    now = startedAt + 8
    equal(IQ.PollAck(Snapshot()), "waiting", "intent still in flight at exact TTL boundary")
    equal(IQ.IsBlocking(Snapshot()), true, "IsBlocking true at exact TTL boundary")
    now = startedAt + 9
    equal(IQ.PollAck(Snapshot()), "timeout", "intent times out just after TTL")
    equal(IQ.GetInFlight(), nil, "queue empty after timeout")
    equal(IQ.IsBlocking(Snapshot()), false, "IsBlocking false after timeout")
    equal(IQ.PollAck(Snapshot()), "none", "PollAck returns none when queue empty")

    accepted = IQ.TryBegin("select", Snapshot())
    equal(accepted, true, "new intent accepted after timeout cleared queue")
end

------------------------------------------------------------------------
-- TryBegin clears timed-out intent before accepting
------------------------------------------------------------------------
do
    IQ.Reset()
    now = 2000
    IQ.TryBegin("select", Snapshot())
    now = now + 9
    local accepted = IQ.TryBegin("select", Snapshot())
    equal(accepted, true, "TryBegin clears timed-out intent and accepts fresh select")
end

------------------------------------------------------------------------
-- Mid-board constraintsHash clear (stale prefs)
------------------------------------------------------------------------
do
    IQ.Reset()
    now = 3000
    local accepted, id1 = IQ.TryBegin("select", Snapshot({ constraintsHash = "hash-a" }))
    equal(accepted, true, "select with hash-a accepted")
    equal(IQ.GetInFlight().constraintsHash, "hash-a", "constraintsHash stored on in-flight intent")

    local id2
    accepted, id2 = IQ.TryBegin("banish", Snapshot({ targetSlot = 2, constraintsHash = "hash-b" }))
    equal(accepted, true, "changed constraintsHash clears stale intent and accepts banish")
    check(id2 ~= id1, "new intent gets fresh id after constraints clear")
    equal(IQ.GetInFlight().action, "banish", "banish replaces cleared select")
    equal(IQ.GetInFlight().constraintsHash, "hash-b", "new constraintsHash stored")

    IQ.Reset()
    accepted, id1 = IQ.TryBegin("freeze", Snapshot({ constraintsHash = "hash-a" }))
    equal(accepted, true, "freeze with hash-a accepted")
    accepted, id2 = IQ.TryBegin("freeze", Snapshot({ constraintsHash = "hash-c" }))
    equal(accepted, true, "changed hash clears duplicate freeze and accepts refresh")
    check(id2 > id1, "intent id increments after constraints stale clear")

    IQ.Reset()
    IQ.TryBegin("select", Snapshot({ constraintsHash = "hash-a" }))
    accepted = IQ.TryBegin("reroll", Snapshot({ constraintsHash = "hash-a" }))
    equal(accepted, false, "unchanged hash keeps one-in-flight guard")

    IQ.Reset()
    IQ.TryBegin("select", Snapshot({ constraintsHash = "hash-a" }))
    accepted = IQ.TryBegin("banish", Snapshot({ targetSlot = 2 }))
    equal(accepted, false, "missing snapshot hash does not clear in-flight intent")

    equal(IQ.DescribeBlock("constraints_stale"),
        "Autopilot prefs changed mid-board; intent cleared",
        "constraints_stale block message")
end

------------------------------------------------------------------------
-- One-in-flight exclusivity (explicit)
------------------------------------------------------------------------
do
    IQ.Reset()
    now = 4000
    local actions = { "select", "freeze", "banish", "reroll" }
    for _, action in ipairs(actions) do
        IQ.Reset()
        local snap = Snapshot({ targetSlot = 2 })
        local accepted, id = IQ.TryBegin(action, snap)
        equal(accepted, true, action .. " accepted as sole in-flight intent")
        equal(IQ.GetInFlight().action, action, "GetInFlight action matches " .. action)
        equal(IQ.GetInFlight().id, id, "GetInFlight id matches TryBegin return")

        for _, other in ipairs(actions) do
            if other ~= action then
                accepted = IQ.TryBegin(other, snap)
                equal(accepted, false, other .. " blocked while " .. action .. " in flight")
            end
        end
        equal(IQ.BlockReason(), "intent_in_flight:" .. action,
            "BlockReason names in-flight action for " .. action)
        equal(IQ.GetInFlight().action, action, "original intent unchanged after rejects")
    end
end

------------------------------------------------------------------------
-- TryBegin rejection reason codes
------------------------------------------------------------------------
do
    IQ.Reset()
    local accepted, reason = IQ.TryBegin("invalid", Snapshot())
    equal(accepted, false, "invalid action rejected")
    equal(reason, "invalid_action", "invalid action reason code")

    IQ.Reset()
    IQ.TryBegin("select", Snapshot())
    accepted, reason = IQ.TryBegin("select", Snapshot())
    equal(accepted, false, "duplicate select rejected with reason")
    equal(reason, "duplicate_intent", "duplicate intent reason code")

    IQ.Reset()
    IQ.TryBegin("select", Snapshot())
    accepted, reason = IQ.TryBegin("banish", Snapshot({ targetSlot = 2 }))
    equal(accepted, false, "different action rejected while in flight")
    equal(reason, "intent_in_flight", "intent_in_flight reason code")
end

------------------------------------------------------------------------
-- BuildSnapshot includes board fields
------------------------------------------------------------------------
do
    local snap = IQ.BuildSnapshot({
        offerId = "offer-x",
        identityFingerprint = "fp-x",
        serverPendingAction = "freeze",
        constraintsHash = "deadbeef",
    }, { index = 3 })
    equal(snap.offerId, "offer-x", "BuildSnapshot offerId")
    equal(snap.identityFingerprint, "fp-x", "BuildSnapshot identityFingerprint")
    equal(snap.targetSlot, 3, "BuildSnapshot targetSlot from target.index")
    equal(snap.serverPendingAction, "freeze", "BuildSnapshot serverPendingAction")
    equal(snap.constraintsHash, "deadbeef", "BuildSnapshot constraintsHash")
end

if failures > 0 then
    io.stderr:write(string.format("test_intent_queue: %d failure(s)\n", failures))
    os.exit(1)
end

print("test_intent_queue: ok")
