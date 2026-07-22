-- Development-only retained-memory and UI-object construction profiler.
-- This file is intentionally absent from EbonBuilds.toc.  Run it from the
-- repository root with a Lua 5.1-compatible interpreter:
--
--   texlua tests/profile_memory.lua
--
-- Lua heap deltas are local-runtime proxies, not WoW's C-side frame cost.
-- Frame/region counts identify construction paths that must be verified in the
-- 3.3.5a client with UpdateAddOnMemoryUsage/GetAddOnMemoryUsage.

unpack = unpack or table.unpack

local function CollectKB()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

local function SortedRows(rows, field)
    local copy = {}
    for index = 1, #rows do copy[index] = rows[index] end
    table.sort(copy, function(left, right)
        return math.abs(left[field] or 0) > math.abs(right[field] or 0)
    end)
    return copy
end

local profile = {
    loadOnly = true,
    files = {},
    objects = {},
    objectsByModule = {},
    scripts = setmetatable({}, { __mode = "k" }),
    scriptOwners = setmetatable({}, { __mode = "k" }),
    shown = setmetatable({}, { __mode = "k" }),
    currentModule = "file-scope",
}

function profile:ObjectCreated(kind)
    self.objects[kind] = (self.objects[kind] or 0) + 1
    local module = self.currentModule or "unattributed"
    local bucket = self.objectsByModule[module]
    if not bucket then bucket = {}; self.objectsByModule[module] = bucket end
    bucket[kind] = (bucket[kind] or 0) + 1
end

function profile:SetScript(object, scriptName, callback)
    local scripts = self.scripts[object]
    if not scripts then scripts = {}; self.scripts[object] = scripts end
    scripts[scriptName] = callback
    local owners = self.scriptOwners[object]
    if not owners then owners = {}; self.scriptOwners[object] = owners end
    owners[scriptName] = self.currentModule or "unattributed"
end

function profile:GetScript(object, scriptName)
    local scripts = self.scripts[object]
    return scripts and scripts[scriptName]
end

function profile:SetShown(object, shown)
    self.shown[object] = shown and true or false
end

function profile:IsShown(object)
    local shown = self.shown[object]
    if shown == nil then return true end
    return shown
end

function profile:BeforeFile(file)
    self.currentFile = file
    self.currentModule = "file-scope:" .. file
    self.fileBefore = CollectKB()
end

function profile:AfterCompile()
    self.fileCompiled = CollectKB()
end

function profile:AfterExecute(file)
    local after = CollectKB()
    self.files[#self.files + 1] = {
        file = file,
        compileKB = (self.fileCompiled or self.fileBefore) - self.fileBefore,
        retainedKB = after - self.fileBefore,
    }
    self.currentFile = nil
    self.currentModule = "post-load"
end

function profile:AfterLoad(files)
    self.loadedFileCount = #files
    self.afterLoadKB = CollectKB()
end

EBONBUILDS_TEST_MEMORY_PROFILE = profile
local suiteBeforeKB = CollectKB()
local smoke, smokeError = loadfile("tests/test_load.lua")
assert(smoke, smokeError)
smoke()
local loadedKB = CollectKB()

local moduleRows = {}
local originalStart = EbonBuilds.Modules.Start
EbonBuilds.Modules.Start = function(name)
    profile.currentModule = name
    local before = CollectKB()
    local beforeObjects = 0
    for _, count in pairs(profile.objects) do beforeObjects = beforeObjects + count end
    local ok, result = originalStart(name)
    local after = CollectKB()
    local afterObjects = 0
    for _, count in pairs(profile.objects) do afterObjects = afterObjects + count end
    moduleRows[#moduleRows + 1] = {
        name = name,
        retainedKB = after - before,
        objects = afterObjects - beforeObjects,
    }
    profile.currentModule = "scheduler"
    return ok, result
end

local now = 0
GetTime = function() return now end
debugprofilestop = function() return now * 1000 end

local function PumpOnUpdates(step)
    now = now + (step or 0.05)
    local callbacks = {}
    for object, scripts in pairs(profile.scripts) do
        if scripts.OnUpdate then callbacks[#callbacks + 1] = { object, scripts.OnUpdate } end
    end
    for index = 1, #callbacks do callbacks[index][2](callbacks[index][1], step or 0.05) end
end

profile.currentModule = "bootstrap-registration"
local bootstrapBefore = CollectKB()

-- The bundled identity rows are used to create a representative read-only
-- ProjectEbonhold runtime database.  Its cost is reported separately because
-- those records are owned by the required addon in the real client, not by
-- EbonBuilds.  Reconciliation still needs realistic runtime-present flags so
-- class projections contain the same available/unavailable mix as production.
local externalFixtureBefore = CollectKB()
ProjectEbonhold.addonVersion = EbonBuilds.EchoIdentityData.SOURCE_ADDON_VERSION
for spellId, row in pairs(EbonBuilds.EchoIdentityData.spells or {}) do
    ProjectEbonhold.PerkDatabase[spellId] = {
        groupId = row[1],
        quality = row[2],
        classMask = row[3],
        requiredSpell = row[4],
        comment = row[5],
    }
end
local externalFixtureKB = CollectKB()

assert(EbonBuilds.Start(), "EbonBuilds.Start() did not schedule initialization")
local bootstrapScheduledKB = CollectKB()

local ticks = 0
while not EbonBuilds.InitPipeline.IsComplete() and ticks < 500 do
    PumpOnUpdates(0.05)
    ticks = ticks + 1
end
assert(EbonBuilds.InitPipeline.IsComplete(), "initialization pipeline did not complete")

-- Finish zero-delay reconciliation/migration work.  Repeating idle jobs remain
-- scheduled, as they do in the client; the loop stops once the major one-shot
-- owners report ready.
local settleTicks = 0
while settleTicks < 500 do
    local catalogReady = not EbonBuilds.EchoCatalog.IsReconciling()
    local databaseReady = EbonBuilds.Database.IsReady()
    local aggregatesReady = not EbonBuilds.Aggregates.IsBackfillComplete
        or EbonBuilds.Aggregates.IsBackfillComplete()
    if catalogReady and databaseReady and aggregatesReady then break end
    PumpOnUpdates(0.05)
    settleTicks = settleTicks + 1
end
local initializedKB = CollectKB()

local function ObjectCount()
    local count = 0
    for _, value in pairs(profile.objects) do count = count + value end
    return count
end

local toggleObjectsBefore = ObjectCount()
for _ = 1, 50 do
    EbonBuilds.MainWindow.Toggle()
    EbonBuilds.MainWindow.Toggle()
end
local toggleObjectsAfter = ObjectCount()

-- Repeating scheduler jobs keep its OnUpdate frame active even while their
-- due time is in the future.  Measure the protected-handler allocation burst
-- without allowing automatic GC, then prove whether it is collectible.
local schedulerObject, schedulerOnUpdate
for object, scripts in pairs(profile.scripts) do
    local owners = profile.scriptOwners[object]
    local owner = owners and owners.OnUpdate or ""
    if scripts.OnUpdate and owner:find("core/Scheduler.lua", 1, true) then
        schedulerObject, schedulerOnUpdate = object, scripts.OnUpdate
        break
    end
end
local idleUpdateBefore = CollectKB()
local idleUpdateImmediate = idleUpdateBefore
local idleUpdateAfterGC = idleUpdateBefore
if schedulerOnUpdate then
    collectgarbage("stop")
    for _ = 1, 10000 do schedulerOnUpdate(schedulerObject, 0) end
    idleUpdateImmediate = collectgarbage("count")
    collectgarbage("restart")
    idleUpdateAfterGC = CollectKB()
end

local projectionRows = {}
local classOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
for index = 1, #classOrder do
    profile.currentModule = "projection:" .. classOrder[index]
    local before = CollectKB()
    local clockBefore = os.clock()
    local projection = EbonBuilds.EchoProjection.Get(classOrder[index])
    local elapsedMs = (os.clock() - clockBefore) * 1000
    local after = CollectKB()
    projectionRows[#projectionRows + 1] = {
        name = classOrder[index],
        retainedKB = after - before,
        entries = projection.fullCount or 0,
        available = projection.availableCount or 0,
        elapsedMs = elapsedMs,
    }
end
local allProjectionsKB = CollectKB()
EbonBuilds.EchoProjection.Invalidate()
local projectionsInvalidatedKB = CollectKB()

-- Reproduce the confirmed Missing-page UI leak path. The first refresh may
-- grow its high-water pool; the next fifty must create zero additional
-- Buttons/Textures/FontStrings for the same result set.
profile.currentModule = "scenario:missing-refresh"
local missingBuild = EbonBuilds.Build.NewObject({
    id = "memory-profile-missing", title = "Memory Profile", class = "MAGE",
    settings = EbonBuilds.Build.NewBuildSettings(), echoWeights = {},
})
EbonBuilds.BuildOverview._SetMissingViewForTests("catalog")
local missingObjectsBefore = ObjectCount()
EbonBuilds.BuildOverview._RefreshMissingForTests(missingBuild, true)
local missingObjectsAfterFirst = ObjectCount()
local missingPoolAfterFirst = EbonBuilds.BuildOverview._MissingRowPoolSizeForTests()
for _ = 1, 50 do EbonBuilds.BuildOverview._RefreshMissingForTests(missingBuild, true) end
local missingObjectsAfterRepeated = ObjectCount()
local missingPoolAfterRepeated = EbonBuilds.BuildOverview._MissingRowPoolSizeForTests()

local function PrintTop(title, rows, field, count)
    print("\n" .. title)
    local sorted = SortedRows(rows, field)
    for index = 1, math.min(count or 15, #sorted) do
        local row = sorted[index]
        print(string.format("%2d  %+9.2f KB  %s", index, row[field] or 0, row.file or row.name or "?"))
    end
end

print("EbonBuilds development memory profile (Lua heap proxy)")
print(string.format("TOC files: %d", profile.loadedFileCount or 0))
print(string.format("Load retained: %+0.2f KB", loadedKB - suiteBeforeKB))
print(string.format("Representative external PerkDatabase fixture: %+0.2f KB (not EbonBuilds-owned in client)", externalFixtureKB - externalFixtureBefore))
print(string.format("Bootstrap registration/schedule: %+0.2f KB", bootstrapScheduledKB - externalFixtureKB))
print(string.format("Initialized and settled: %+0.2f KB (excluding external fixture)", initializedKB - externalFixtureKB))
print(string.format("All ten class projections: %+0.2f KB", allProjectionsKB - initializedKB))
print(string.format("Projection cache recovered after invalidation: %+0.2f KB", allProjectionsKB - projectionsInvalidatedKB))
print(string.format("Pipeline ticks: %d; settle ticks: %d", ticks, settleTicks))
print(string.format("10,000 idle Scheduler OnUpdates: immediate %+0.2f KB; post-GC %+0.2f KB",
    idleUpdateImmediate - idleUpdateBefore, idleUpdateAfterGC - idleUpdateBefore))
print(string.format("Main window open/close x50: %d new object proxies", toggleObjectsAfter - toggleObjectsBefore))
print(string.format("Missing page: first refresh created %d object proxies for %d rows; next 50 created %d and pool ended at %d",
    missingObjectsAfterFirst - missingObjectsBefore, missingPoolAfterFirst,
    missingObjectsAfterRepeated - missingObjectsAfterFirst, missingPoolAfterRepeated))

PrintTop("Largest file-scope retained deltas", profile.files, "retainedKB", 20)
PrintTop("Largest compiled-chunk deltas", profile.files, "compileKB", 15)
PrintTop("Largest module-init retained deltas", moduleRows, "retainedKB", 20)

print("\nClass projection retained deltas")
for index = 1, #projectionRows do
    local row = projectionRows[index]
    print(string.format("%-12s %+9.2f KB  %7.2f ms  entries=%d available=%d",
        row.name, row.retainedKB, row.elapsedMs, row.entries, row.available))
end

print("\nUI object proxies constructed by module init")
local ownerRows = {}
for owner, kinds in pairs(profile.objectsByModule) do
    local count = 0
    for _, value in pairs(kinds) do count = count + value end
    ownerRows[#ownerRows + 1] = { owner = owner, count = count }
end
table.sort(ownerRows, function(left, right) return left.count > right.count end)
for index = 1, math.min(20, #ownerRows) do
    print(string.format("%-38s %6d", ownerRows[index].owner, ownerRows[index].count))
end

print("\nConstructed UI object proxies (headless counts; excludes C-side bytes)")
local objectRows = {}
for kind, count in pairs(profile.objects) do objectRows[#objectRows + 1] = { kind = kind, count = count } end
table.sort(objectRows, function(left, right) return left.count > right.count end)
for index = 1, #objectRows do
    print(string.format("%-28s %6d", objectRows[index].kind, objectRows[index].count))
end

print("\nNOTE: collectgarbage('count') measures this Lua runtime only. WoW frame/texture/font-string C allocations and actual SavedVariables must be measured in the 3.3.5a client.")
