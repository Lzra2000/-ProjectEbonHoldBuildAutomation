-- Read-only SavedVariables heap profiler. The input files are executed only in
-- this standalone Lua process; nothing is serialized or written back.
--
--   texlua tests/profile_savedvariables.lua <account EbonBuilds.lua> [character EbonBuilds.lua]

local accountPath = arg and arg[1]
local characterPath = arg and arg[2]
assert(accountPath and accountPath ~= "", "account SavedVariables path is required")

local function CollectKB()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

local function LoadSavedVariables(path)
    local before = CollectKB()
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk()
    chunk = nil
    return CollectKB() - before
end

local function CountMap(value)
    local count = 0
    for _ in pairs(type(value) == "table" and value or {}) do count = count + 1 end
    return count
end

local function SessionCounts()
    local runs, events, choices = 0, 0, 0
    for _, session in ipairs(EbonBuildsDB.sessions or {}) do
        runs = runs + 1
        for _, entry in ipairs(session.logs or {}) do
            events = events + 1
            choices = choices + #(entry.choices or {})
        end
    end
    return runs, events, choices
end

local accountRetainedKB = LoadSavedVariables(accountPath)
local characterRetainedKB = 0
if characterPath and characterPath ~= "" then characterRetainedKB = LoadSavedVariables(characterPath) end

EbonBuildsDB = type(EbonBuildsDB) == "table" and EbonBuildsDB or {}
EbonBuildsCharDB = type(EbonBuildsCharDB) == "table" and EbonBuildsCharDB or {}
local runs, events, choices = SessionCounts()
local remoteBefore = CountMap(EbonBuildsDB.remoteBuilds)
local recommendationsBefore = CountMap(EbonBuildsDB.recommendationCache)

local addon = { Runtime = {} }
assert(loadfile("core/Database.lua"))("EbonBuilds", addon)
UnitName = UnitName or function() return "Profiler" end
GetRealmName = GetRealmName or function() return "Profiler" end
local beforeCompactionKB = CollectKB()

addon.Database.Adopt()
local compactedFields = 0
for _, session in ipairs(EbonBuildsDB.sessions or {}) do
    compactedFields = compactedFields + addon.Database._CompactSessionForTests(session)
end
local removedRemoteBuilds = addon.Database.PruneRemoteBuilds()

-- RecommendationService.Get already rejects every snapshot from an older
-- global source revision. Mirror current Init/Invalidate compaction without
-- loading the recommendation subsystem or changing the source file.
local sourceRevision = tonumber(EbonBuildsDB.recommendationSourceRevision) or 1
for key, snapshot in pairs(EbonBuildsDB.recommendationCache or {}) do
    if type(snapshot) ~= "table" or tonumber(snapshot.schema) ~= 6
        or tonumber(snapshot.sourceRevision) ~= sourceRevision then
        EbonBuildsDB.recommendationCache[key] = nil
    end
end

local afterCompactionKB = CollectKB()
local remoteAfter = CountMap(EbonBuildsDB.remoteBuilds)
local recommendationsAfter = CountMap(EbonBuildsDB.recommendationCache)

print("EbonBuilds SavedVariables retained-memory profile (standalone Lua proxy; disk is read-only)")
print(string.format("Account load retained: %+0.2f KB", accountRetainedKB))
if characterPath and characterPath ~= "" then
    print(string.format("Current-character load retained: %+0.2f KB", characterRetainedKB))
end
print(string.format("Runs=%d events=%d choices=%d", runs, events, choices))
print(string.format("In-memory compaction recovered: %+0.2f KB", beforeCompactionKB - afterCompactionKB))
print(string.format("Redundant session fields removed: %d", compactedFields))
print(string.format("Remote builds: %d -> %d (removed %d)", remoteBefore, remoteAfter, removedRemoteBuilds))
print(string.format("Recommendation cohorts: %d -> %d", recommendationsBefore, recommendationsAfter))
print("NOTE: numbers are comparative Lua-heap proxies, not WoW GetAddOnMemoryUsage readings.")
