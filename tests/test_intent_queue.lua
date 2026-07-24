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
    local accepted = IQ.TryBegin("freeze", Snapshot({ targetSlot = 1 }))
    equal(accepted, true, "freeze intent accepted for timeout test")
    now = now + 9
    equal(IQ.PollAck(Snapshot()), "timeout", "intent times out after TTL")
    equal(IQ.GetInFlight(), nil, "queue empty after timeout")
end

if failures > 0 then
    io.stderr:write(string.format("test_intent_queue: %d failure(s)\n", failures))
    os.exit(1)
end

print("test_intent_queue: ok")
