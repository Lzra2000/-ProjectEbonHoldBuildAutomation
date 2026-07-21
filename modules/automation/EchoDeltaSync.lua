local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/EchoDeltaSync.lua
-- Responsibility: the delta-based community performance exchange. The
-- legacy PRF wire format ships raw per-echo sum/count aggregates --
-- confounded by construction (see EchoSamples.lua's header), and pooling
-- them ACROSS players adds gear/skill/fight-type variance on top, which
-- is why community data has deliberately influenced nothing so far.
-- This module ships each player's own with/without DELTAS instead: a
-- delta is a within-player contrast (the player's gear and skill sit on
-- both sides of the subtraction), so combining deltas across players is
-- a defensible estimate in a way pooled raw DPS never was. Only deltas
-- that are locally RELIABLE (both sides past EchoSamples'
-- MIN_SAMPLES_PER_SIDE) are ever broadcast -- noise stays home.
--
-- Wire format (versioned, unlike PRF -- lesson learned):
--   PRD|1|<class>|name:delta:nWith:nWithout;...
-- Transition plan: PRD is broadcast alongside legacy PRF (old clients
-- keep understanding PRF, new clients prefer PRD evidence). Once the
-- population has upgraded, PRF and the legacy community store go away.

EbonBuilds.EchoDeltaSync = {}
local M = EbonBuilds.EchoDeltaSync

local WIRE_VERSION = "1"
M.WIRE_VERSION = WIRE_VERSION

-- Bounds: per-echo sender cap (oldest evicted), staleness horizon, and
-- the reliability bar for the AGGREGATED community delta.
local MAX_SENDERS_PER_ECHO = 12
local STALE_SECONDS        = 14 * 24 * 3600
local MIN_PEERS            = 2
local WEIGHT_CAP           = 50   -- one very-grindy peer must not drown out the rest
M._MAX_SENDERS_PER_ECHO = MAX_SENDERS_PER_ECHO

-- In-game, time() always exists. The test harness doesn't provide it,
-- and a constant 0 would make every fresh insert look like the oldest
-- entry -- so the fallback is a monotonic counter, preserving insert
-- order for the timestamp-based eviction.
local fallbackClock = 0
local function Now()
    if time then return time() end
    fallbackClock = fallbackClock + 1
    return fallbackClock
end

-- Strictly increasing insert sequence: the eviction tie-breaker for
-- entries that share the same second (a burst of inbound batches easily
-- does), so "oldest" is deterministic instead of pairs()-order luck.
local seqCounter = 0
local function NextSeq()
    seqCounter = seqCounter + 1
    return seqCounter
end

local function Store()
    EbonBuildsCharDB.echoDeltaCommunity = EbonBuildsCharDB.echoDeltaCommunity or {}
    return EbonBuildsCharDB.echoDeltaCommunity
end

------------------------------------------------------------------------
-- Wire format
------------------------------------------------------------------------

-- SerializeBatch(class, deltas): deltas = { {name=, delta=, nWith=, nWithout=}, ... }
-- Returns nil when there is nothing reliable to say.
function M.SerializeBatch(class, deltas)
    if not class or type(deltas) ~= "table" or #deltas == 0 then return nil end
    local parts = {}
    for _, d in ipairs(deltas) do
        if type(d.name) == "string" and d.name ~= ""
            and type(d.delta) == "number"
            and type(d.nWith) == "number" and d.nWith > 0
            and type(d.nWithout) == "number" and d.nWithout > 0 then
            parts[#parts + 1] = string.format("%s:%.1f:%d:%d", d.name, d.delta, d.nWith, d.nWithout)
        end
    end
    if #parts == 0 then return nil end
    return "PRD|" .. WIRE_VERSION .. "|" .. class .. "|" .. table.concat(parts, ";")
end

-- ParseBatch(payload) -> class, entries | nil. Defensive on purpose:
-- this sits behind the same fuzzed dispatch path as every other inbound
-- handler, so garbage must parse to nil, never to an error.
function M.ParseBatch(payload)
    if type(payload) ~= "string" then return nil end
    local version, class, body = payload:match("^PRD|([^|]+)|([^|]+)|(.+)$")
    if version ~= WIRE_VERSION or not class then return nil end
    local entries = {}
    for entry in body:gmatch("[^;]+") do
        local name, delta, nWith, nWithout = entry:match("^(.+):(%-?%d+%.?%d*):(%d+):(%d+)$")
        local d, nw, no = tonumber(delta), tonumber(nWith), tonumber(nWithout)
        if name and d and nw and no and nw > 0 and no > 0 then
            entries[#entries + 1] = { name = name, delta = d, nWith = nw, nWithout = no }
        end
    end
    if #entries == 0 then return nil end
    return class, entries
end

------------------------------------------------------------------------
-- Community store (per character, bounded)
------------------------------------------------------------------------

local function EvictIfNeeded(perEcho)
    local count, oldestSender, oldestT, oldestSeq = 0, nil, math.huge, math.huge
    for sender, rec in pairs(perEcho) do
        count = count + 1
        local t = (type(rec) == "table" and tonumber(rec.t)) or 0
        local seq = (type(rec) == "table" and tonumber(rec.seq)) or 0
        if t < oldestT or (t == oldestT and seq < oldestSeq) then
            oldestT, oldestSeq, oldestSender = t, seq, sender
        end
    end
    if count > MAX_SENDERS_PER_ECHO and oldestSender then
        perEcho[oldestSender] = nil
    end
end

function M.MergeContribution(sender, class, name, delta, nWith, nWithout)
    if type(sender) ~= "string" or sender == "" then return end
    if type(class) ~= "string" or class == "" then return end
    if type(name) ~= "string" or name == "" then return end
    if type(delta) ~= "number" or type(nWith) ~= "number" or type(nWithout) ~= "number" then return end
    if nWith <= 0 or nWithout <= 0 then return end
    local store = Store()
    store[class] = store[class] or {}
    store[class][name] = store[class][name] or {}
    -- Latest snapshot per sender replaces the previous one -- a delta is
    -- a statement about the sender's WHOLE current sample ring, not an
    -- increment, so summing successive snapshots would double count.
    store[class][name][sender] = { d = delta, nw = nWith, no = nWithout, t = Now(), seq = NextSeq() }
    EvictIfNeeded(store[class][name])
end

-- Called by Sync's dispatcher for every inbound PRD message. Same
-- consent/enable gate as the legacy PRF path.
function M.HandleBroadcast(payload, sender)
    if not (EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled and EbonBuilds.EchoPerformance.IsEnabled()) then return end
    local class, entries = M.ParseBatch(payload)
    if not class then return end
    for _, e in ipairs(entries) do
        M.MergeContribution(tostring(sender or ""), class, e.name, e.delta, e.nWith, e.nWithout)
    end
end

function M.Clear()
    EbonBuildsCharDB.echoDeltaCommunity = {}
end

------------------------------------------------------------------------
-- Aggregation: what the community's deltas add up to for one echo.
------------------------------------------------------------------------

-- CommunityDelta(class, name, now) -> nil | { delta, peers, nWith,
-- nWithout, reliable }. Sample-weighted mean of per-peer deltas, weight
-- = min(nWith, nWithout) capped at WEIGHT_CAP. reliable only with >=
-- MIN_PEERS distinct peers AND both summed sides past EchoSamples'
-- MIN_SAMPLES_PER_SIDE -- the same bar local evidence has to clear.
function M.CommunityDelta(class, name, now)
    if type(class) ~= "string" or type(name) ~= "string" then return nil end
    local perEcho = Store()[class] and Store()[class][name]
    if not perEcho then return nil end
    now = now or Now()
    local weightedSum, weightTotal, peers, sumWith, sumWithout = 0, 0, 0, 0, 0
    for _, rec in pairs(perEcho) do
        if type(rec) == "table" and type(rec.d) == "number"
            and type(rec.nw) == "number" and type(rec.no) == "number"
            and (now - (tonumber(rec.t) or 0)) <= STALE_SECONDS then
            local w = math.min(rec.nw, rec.no, WEIGHT_CAP)
            weightedSum = weightedSum + rec.d * w
            weightTotal = weightTotal + w
            peers = peers + 1
            sumWith, sumWithout = sumWith + rec.nw, sumWithout + rec.no
        end
    end
    if peers == 0 or weightTotal == 0 then return nil end
    local minSide = (EbonBuilds.EchoSamples and EbonBuilds.EchoSamples.MIN_SAMPLES_PER_SIDE) or 10
    return {
        delta = weightedSum / weightTotal,
        peers = peers,
        nWith = sumWith,
        nWithout = sumWithout,
        reliable = peers >= MIN_PEERS and sumWith >= minSide and sumWithout >= minSide,
    }
end

------------------------------------------------------------------------
-- Broadcast: rotate through the locally-reliable deltas, a few at a time.
------------------------------------------------------------------------

local broadcastCursor = 1

-- Names that actually occur in the local sample ring -- bounded by the
-- ring, so this never iterates the whole catalog.
local function LocalSampleNames()
    local seen, names = {}, {}
    if not (EbonBuilds.RingBuffer and EbonBuildsCharDB and EbonBuildsCharDB.echoPerfSampleRing) then return names end
    EbonBuilds.RingBuffer.ForEach(EbonBuildsCharDB.echoPerfSampleRing, function(sample)
        if type(sample) == "table" and type(sample.set) == "table" then
            for i = 1, #sample.set do
                local n = sample.set[i]
                if type(n) == "string" and not seen[n] then
                    seen[n] = true
                    names[#names + 1] = n
                end
            end
        end
    end)
    table.sort(names)
    return names
end

-- SendOneBatch(batchSize): serialize up to batchSize locally-RELIABLE
-- deltas starting at the rotation cursor and hand them to Sync. Returns
-- true when something was sent. Shares Sync.BroadcastPerfBatch -- the
-- payload is self-tagged, exactly like PRF.
function M.SendOneBatch(batchSize)
    if not (EbonBuilds.Sync and EbonBuilds.Sync.BroadcastPerfBatch) then return false end
    if not (EbonBuilds.EchoSamples and EbonBuilds.EchoSamples.Delta) then return false end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or not build.class then return false end
    local names = LocalSampleNames()
    if #names == 0 then return false end
    batchSize = batchSize or 6

    local deltas, scanned = {}, 0
    while #deltas < batchSize and scanned < #names do
        local idx = ((broadcastCursor - 1 + scanned) % #names) + 1
        local d = EbonBuilds.EchoSamples.Delta(names[idx])
        if d and d.reliable then
            deltas[#deltas + 1] = { name = names[idx], delta = d.delta, nWith = d.nWith, nWithout = d.nWithout }
        end
        scanned = scanned + 1
    end
    broadcastCursor = ((broadcastCursor - 1 + scanned) % #names) + 1
    local payload = M.SerializeBatch(build.class, deltas)
    if not payload then return false end
    EbonBuilds.Sync.BroadcastPerfBatch(payload)
    return true
end

------------------------------------------------------------------------
-- Self-tests
------------------------------------------------------------------------

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    EbonBuilds.Debug.RegisterTest("EchoDeltaSync wire format roundtrips and rejects garbage", function()
        local payload = M.SerializeBatch("WARRIOR", {
            { name = "Crimson Reprisal", delta = 123.4, nWith = 20, nWithout = 15 },
            { name = "Blood Mirror", delta = -50, nWith = 12, nWithout = 30 },
        })
        if not payload then error("expected a payload") end
        local class, entries = M.ParseBatch(payload)
        if class ~= "WARRIOR" or #entries ~= 2 then error("roundtrip failed: " .. tostring(payload)) end
        if entries[1].name ~= "Blood Mirror" and entries[1].name ~= "Crimson Reprisal" then error("names lost") end
        for _, garbage in ipairs({ "", "PRD|", "PRD|2|WARRIOR|x:1:1:1", "PRD|1|WARRIOR|", "PRF|WARRIOR|a:1:1", "PRD|1|WARRIOR|name-without-numbers" }) do
            if M.ParseBatch(garbage) ~= nil then error("accepted garbage: " .. garbage) end
        end
    end)

    EbonBuilds.Debug.RegisterTest("EchoDeltaSync community aggregation gates on peers and sample floors", function()
        M.Clear()
        M.MergeContribution("PeerA", "MAGE", "Test Echo", 100, 20, 20)
        local one = M.CommunityDelta("MAGE", "Test Echo")
        if not one or one.reliable then error("a single peer must never be reliable") end
        M.MergeContribution("PeerB", "MAGE", "Test Echo", 200, 20, 20)
        local two = M.CommunityDelta("MAGE", "Test Echo")
        if not two or not two.reliable then error("two peers past the floors should be reliable") end
        if two.delta < 100 or two.delta > 200 then error("weighted mean out of range: " .. tostring(two.delta)) end
        M.MergeContribution("PeerC", "MAGE", "Thin Echo", 500, 1, 1)
        M.MergeContribution("PeerD", "MAGE", "Thin Echo", 500, 1, 1)
        local thin = M.CommunityDelta("MAGE", "Thin Echo")
        if thin and thin.reliable then error("sample floor must hold even with two peers") end
        M.Clear()
    end)

    EbonBuilds.Debug.RegisterTest("EchoDeltaSync evicts the oldest sender past the cap", function()
        M.Clear()
        for i = 1, M._MAX_SENDERS_PER_ECHO + 1 do
            M.MergeContribution("Peer" .. i, "DRUID", "Crowded Echo", i, 10, 10)
        end
        local store = EbonBuildsCharDB.echoDeltaCommunity["DRUID"]["Crowded Echo"]
        local count = 0
        for _ in pairs(store) do count = count + 1 end
        if count ~= M._MAX_SENDERS_PER_ECHO then error("expected cap of " .. M._MAX_SENDERS_PER_ECHO .. ", got " .. count) end
        if store["Peer1"] then error("oldest sender should have been evicted") end
        M.Clear()
    end)
end
