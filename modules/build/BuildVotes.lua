local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/BuildVotes.lua
-- Responsibility: community upvotes for public builds (issue #8) --
-- "acknowledge that a build is well made and give the creator some
-- credits", and let browsers separate cared-for builds from someone's
-- experiments.
--
-- Trust model, stated plainly: there is no server, so the only
-- non-forgeable fact is WHO SENT a message -- WoW authenticates the
-- sender name on both addon messages and channel lines. Votes are
-- therefore DIRECT-WITNESS ONLY: every client broadcasts exclusively
-- its own vote ("I, <sender>, upvote build X"), never relayed lists of
-- other people's votes (a relayed list would be trivially forgeable).
-- The count a player sees is the number of DISTINCT VOTERS this client
-- has itself heard from -- an honest local tally that converges as
-- people play together, not a global number. One vote per character
-- per build; retractable.
--
-- Wire format (versioned): VOT|1|<buildId>:<1|0>;...

EbonBuilds.BuildVotes = {}
local M = EbonBuilds.BuildVotes

local WIRE_VERSION = "1"
local MAX_VOTERS_PER_BUILD = 200
local ANNOUNCE_INTERVAL = 600      -- re-announce own votes (seconds), so players who log in later still hear them
local ANNOUNCE_INITIAL_DELAY = 45  -- after login, once the sync channel is up
local MAX_IDS_PER_MESSAGE = 30
M._MAX_VOTERS_PER_BUILD = MAX_VOTERS_PER_BUILD

-- Same harness-safe clock + deterministic eviction pattern as
-- EchoDeltaSync: monotonic fallback when time() is missing, sequence
-- tie-breaker for entries landing in the same second.
local fallbackClock = 0
local function Now()
    if time then return time() end
    fallbackClock = fallbackClock + 1
    return fallbackClock
end
local seqCounter = 0
local function NextSeq()
    seqCounter = seqCounter + 1
    return seqCounter
end

-- Votes HEARD (all voters, account-wide -- the tally belongs to the
-- build, not to one character's view of it).
local function Store()
    EbonBuildsDB.buildVotes = EbonBuildsDB.buildVotes or {}
    return EbonBuildsDB.buildVotes
end

-- Votes CAST (this character's own).
local function MyStore()
    EbonBuildsCharDB.myBuildVotes = EbonBuildsCharDB.myBuildVotes or {}
    return EbonBuildsCharDB.myBuildVotes
end

local function ValidId(id)
    return type(id) == "string" and id ~= "" and not id:find("[:;|]")
end

------------------------------------------------------------------------
-- Wire format
------------------------------------------------------------------------

-- Serialize(entries): entries = { {id=, on=true|false}, ... } -> payload | nil
function M.Serialize(entries)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    local parts = {}
    for _, e in ipairs(entries) do
        if type(e) == "table" and ValidId(e.id) then
            parts[#parts + 1] = e.id .. ":" .. (e.on and "1" or "0")
        end
    end
    if #parts == 0 then return nil end
    return "VOT|" .. WIRE_VERSION .. "|" .. table.concat(parts, ";")
end

-- Parse(payload) -> entries | nil. Defensive: behind the fuzzed
-- dispatch path, garbage parses to nil, never to an error.
function M.Parse(payload)
    if type(payload) ~= "string" then return nil end
    local version, body = payload:match("^VOT|([^|]+)|(.+)$")
    if version ~= WIRE_VERSION or not body then return nil end
    local entries = {}
    for chunk in body:gmatch("[^;]+") do
        local id, flag = chunk:match("^([^:;|]+):([01])$")
        if id then
            entries[#entries + 1] = { id = id, on = flag == "1" }
        end
    end
    if #entries == 0 then return nil end
    return entries
end

------------------------------------------------------------------------
-- Tally (heard votes)
------------------------------------------------------------------------

local function EvictIfNeeded(voters)
    local count, oldestName, oldestT, oldestSeq = 0, nil, math.huge, math.huge
    for name, rec in pairs(voters) do
        count = count + 1
        local t = (type(rec) == "table" and tonumber(rec.t)) or 0
        local seq = (type(rec) == "table" and tonumber(rec.seq)) or 0
        if t < oldestT or (t == oldestT and seq < oldestSeq) then
            oldestT, oldestSeq, oldestName = t, seq, name
        end
    end
    if count > MAX_VOTERS_PER_BUILD and oldestName then
        voters[oldestName] = nil
    end
end

function M.MergeVote(voter, buildId, on)
    if type(voter) ~= "string" or voter == "" then return end
    if not ValidId(buildId) then return end
    local store = Store()
    if on then
        store[buildId] = store[buildId] or {}
        store[buildId][voter] = { t = Now(), seq = NextSeq() }
        EvictIfNeeded(store[buildId])
    elseif store[buildId] then
        store[buildId][voter] = nil
        if not next(store[buildId]) then store[buildId] = nil end
    end
end

-- Count(buildId): distinct voters this client has heard. An honest
-- local tally, not a global number (see the header).
function M.Count(buildId)
    local voters = Store()[buildId]
    if not voters then return 0 end
    local n = 0
    for _ in pairs(voters) do n = n + 1 end
    return n
end

-- Inbound: every VOT message carries the SENDER's own votes only.
function M.HandleBroadcast(payload, sender)
    if type(sender) ~= "string" or sender == "" then return end
    local entries = M.Parse(payload)
    if not entries then return end
    for _, e in ipairs(entries) do
        M.MergeVote(sender, e.id, e.on)
    end
end

------------------------------------------------------------------------
-- Own votes
------------------------------------------------------------------------

local function PlayerName()
    return (UnitName and UnitName("player")) or "player"
end

function M.HasVoted(buildId)
    return MyStore()[buildId] == true
end

local function BroadcastEntries(entries)
    if not (EbonBuilds.Sync and EbonBuilds.Sync.BroadcastVotes) then return end
    local payload = M.Serialize(entries)
    if payload then EbonBuilds.Sync.BroadcastVotes(payload) end
end

-- Toggle(buildId) -> new state. Applies locally at once (the voter is a
-- witness of their own vote) and broadcasts the change.
function M.Toggle(buildId)
    if not ValidId(buildId) then return false end
    local my = MyStore()
    local newState = not my[buildId]
    my[buildId] = newState or nil
    M.MergeVote(PlayerName(), buildId, newState)
    BroadcastEntries({ { id = buildId, on = newState } })
    return newState
end

-- Re-announce all currently-cast votes, batched. Votes only spread to
-- players who are online to hear them -- the periodic announce is what
-- lets a vote reach people who log in later.
function M.AnnounceMyVotes()
    local batch = {}
    for id in pairs(MyStore()) do
        batch[#batch + 1] = { id = id, on = true }
        if #batch >= MAX_IDS_PER_MESSAGE then
            BroadcastEntries(batch)
            batch = {}
        end
    end
    if #batch > 0 then BroadcastEntries(batch) end
end

if EbonBuilds.Scheduler and EbonBuilds.Scheduler.Every and EbonBuilds.Scheduler.After then
    EbonBuilds.Scheduler.After("BuildVotes.initialAnnounce", ANNOUNCE_INITIAL_DELAY, function()
        local ok, err = pcall(M.AnnounceMyVotes)
        if not ok and EbonBuilds.ErrorLog then EbonBuilds.ErrorLog.Record("BuildVotes.initialAnnounce", tostring(err)) end
    end)
    EbonBuilds.Scheduler.Every("BuildVotes.announce", ANNOUNCE_INTERVAL, function()
        local ok, err = pcall(M.AnnounceMyVotes)
        if not ok and EbonBuilds.ErrorLog then EbonBuilds.ErrorLog.Record("BuildVotes.announce", tostring(err)) end
    end)
end

------------------------------------------------------------------------
-- Self-tests
------------------------------------------------------------------------

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    EbonBuilds.Debug.RegisterTest("BuildVotes wire format roundtrips and rejects garbage", function()
        local payload = M.Serialize({ { id = "abc-123", on = true }, { id = "def-456", on = false } })
        if not payload then error("expected payload") end
        local entries = M.Parse(payload)
        if not entries or #entries ~= 2 then error("roundtrip failed") end
        if entries[1].id ~= "abc-123" or entries[1].on ~= true then error("entry 1 wrong") end
        if entries[2].id ~= "def-456" or entries[2].on ~= false then error("entry 2 wrong") end
        for _, garbage in ipairs({ "", "VOT|", "VOT|2|a:1", "VOT|1|", "VOT|1|noflag", "VOT|1|bad:2", "TOM|1|a:1" }) do
            if M.Parse(garbage) ~= nil then error("accepted garbage: " .. garbage) end
        end
        if M.Serialize({ { id = "evil:id", on = true } }) ~= nil then error("must refuse ids containing separators") end
    end)

    EbonBuilds.Debug.RegisterTest("BuildVotes counts distinct voters, dedupes, and honors retraction", function()
        EbonBuildsDB.buildVotes = {}
        M.MergeVote("Alice", "build-x", true)
        M.MergeVote("Alice", "build-x", true)  -- same voter twice: still one
        M.MergeVote("Bob", "build-x", true)
        if M.Count("build-x") ~= 2 then error("expected 2 distinct voters, got " .. M.Count("build-x")) end
        M.MergeVote("Alice", "build-x", false) -- retraction
        if M.Count("build-x") ~= 1 then error("retraction not honored") end
        if M.Count("build-unknown") ~= 0 then error("unknown build must count 0") end
        EbonBuildsDB.buildVotes = {}
    end)

    EbonBuilds.Debug.RegisterTest("BuildVotes evicts the oldest voter past the cap", function()
        EbonBuildsDB.buildVotes = {}
        for i = 1, M._MAX_VOTERS_PER_BUILD + 1 do
            M.MergeVote("Voter" .. i, "crowded", true)
        end
        if M.Count("crowded") ~= M._MAX_VOTERS_PER_BUILD then
            error("expected cap of " .. M._MAX_VOTERS_PER_BUILD .. ", got " .. M.Count("crowded"))
        end
        if EbonBuildsDB.buildVotes["crowded"]["Voter1"] then error("oldest voter should have been evicted") end
        EbonBuildsDB.buildVotes = {}
    end)

    EbonBuilds.Debug.RegisterTest("BuildVotes.Toggle casts, counts locally, and retracts", function()
        EbonBuildsDB.buildVotes = {}
        EbonBuildsCharDB.myBuildVotes = {}
        local on = M.Toggle("toggle-build")
        if on ~= true or not M.HasVoted("toggle-build") then error("first toggle should cast") end
        if M.Count("toggle-build") ~= 1 then error("own vote must count locally at once") end
        local off = M.Toggle("toggle-build")
        if off ~= false or M.HasVoted("toggle-build") then error("second toggle should retract") end
        if M.Count("toggle-build") ~= 0 then error("retracted vote must not count") end
        EbonBuildsDB.buildVotes = {}
        EbonBuildsCharDB.myBuildVotes = {}
    end)
end
