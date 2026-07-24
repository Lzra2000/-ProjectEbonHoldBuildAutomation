-- EchoPerformance / Details! optional integration hardening tests.
-- Run from addon root: texlua tests/test_echo_performance_harden.lua

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

EbonBuilds = { Runtime = {} }
EbonBuildsDB = { builds = {}, globalSettings = {} }
EbonBuildsCharDB = { consent = { performanceVersion = 1, performanceEnabled = true } }

ProjectEbonhold = {
    PerkService = {
        GetGrantedPerks = function() return { [990001] = { spellId = 990001 } } end,
    },
}

local function Noop() end
function CreateFrame() return { RegisterEvent = Noop, SetScript = Noop, Show = Noop, Hide = Noop } end
function UnitName() return "Tester" end
function UnitAffectingCombat() return true end
function GetSpellInfo(spellId) return "Test Echo " .. tostring(spellId) end
function time() return 123456789 end

EbonBuilds.Scheduler = { BACKGROUND = 3, Every = function() return true end }
EbonBuilds.DebugLog = { IsEnabled = function() return false end, Add = Noop }
EbonBuilds.Weights = {
    MIN_VALUE = 0, MAX_VALUE = 100,
    StripQualitySuffix = function(v) return v end,
    CanonicalName = function(v) return "Echo-" .. tostring(v) end,
}
EbonBuilds.Build = {
    GetActive = function()
        return { id = "b1", class = "MAGE", title = "Test", settings = {} }
    end,
    DefaultSettings = function() return {} end,
}
EbonBuilds.EchoCatalog = {
    GetBySpellId = function(id) return { displayName = "Echo-" .. id, sourceName = "Echo-" .. id } end,
    FindLegacyRefs = function() return {} end,
}
EbonBuilds.EchoSamples = {
    Record = function() error("EchoSamples.Record should be pcall-wrapped") end,
    EvidenceValue = function() return nil, "insufficient" end,
    FamilyDelta = function() return nil end,
}
EbonBuilds.EchoTableRows = { BuildBestByName = function() return {} end }
EbonBuilds.EchoProjection = { GetAvailable = function() return {} end }
EbonBuilds.Quality = { ORDER = { 3, 2, 1, 0 }, LABELS = {}, IsValid = function() return true end }
EbonBuilds.Families = { OrderedIds = function() return {} end, IsDps = function() return false end }
EbonBuilds.Scoring = { ScorePerQuality = function() return 0 end }

assert(loadfile("modules/automation/EchoPerformance.lua"))("EbonBuilds", EbonBuilds)
EbonBuilds.EchoPerformance.Init()

-- Without Details: soft-fail, no throw.
Details = nil
equal(EbonBuilds.EchoPerformance.IsDetailsAvailable(), false, "missing Details is unavailable")
EbonBuilds.EchoPerformance.Sample() -- must not throw despite EchoSamples.Record error stub

-- Broken Details table: probe must not throw.
Details = setmetatable({}, {
    __index = function() error("Details broken") end,
})
equal(EbonBuilds.EchoPerformance.IsDetailsAvailable(), false, "broken Details reports unavailable")

-- Working Details stub.
Details = {
    GetCurrentCombat = function()
        return {
            GetCombatTime = function() return 10 end,
            GetActor = function(_, __, name)
                if name == "Tester" then
                    return { total = 10000, Tempo = function() return 10 end }
                end
            end,
        }
    end,
}
DETAILS_ATTRIBUTE_DAMAGE = 1
equal(EbonBuilds.EchoPerformance.IsDetailsAvailable(), true, "working Details API detected")

local status = EbonBuilds.EchoPerformance.GetTrackingStatus()
equal(status, "no_samples", "enabled + Details but no samples yet")

EbonBuildsCharDB.echoPerformance = { ["Echo-990001"] = { sum = 80000, count = 10 } }
status = select(1, EbonBuilds.EchoPerformance.GetTrackingStatus())
equal(status, "collecting", "samples without evidence stats stays collecting")
equal(EbonBuilds.EchoPerformance.HasStoredStats(), true, "stored stats detected")

-- Details PE spell-attributed path: soft-fail when absent, accumulate when present.
DetailsProjectEbonhold = {
    Echo = {
        GetPlayerEchoDamage = function()
            return { ["Echo-990001"] = 2500 }
        end,
    },
}
EbonBuildsCharDB.echoPerformance = {}
EbonBuilds.EchoPerformance.Sample()
local peEntry = EbonBuildsCharDB.echoPerformance["Echo-990001"]
check(peEntry ~= nil, "sample created with Details PE present")
equal(peEntry and peEntry.spellSum, 2500, "spell-attributed echo damage recorded")
equal(peEntry and peEntry.spellCount, 1, "spell-attributed sample count")
DetailsProjectEbonhold = nil

equal(EbonBuilds.EchoPerformance.ParseBatch(nil), nil, "nil payload rejected")
equal(EbonBuilds.EchoPerformance.ParseBatch("not-prf"), nil, "invalid payload rejected")
local class, entries = EbonBuilds.EchoPerformance.ParseBatch("PRF|MAGE|Echo-A:1000:5")
equal(class, "MAGE", "valid PRF class parsed")
equal(#entries, 1, "valid PRF entry parsed")

EbonBuilds.EchoPerformance.HandleBroadcast("PRF|MAGE|Echo-A:1000:5", "Peer")
equal(EbonBuilds.EchoPerformance.SyncNow(), false, "SyncNow without Sync module is soft-fail")

EbonBuilds.EchoPerformance.SetEnabled(false)
equal(select(1, EbonBuilds.EchoPerformance.GetTrackingStatus()), "disabled", "disabled status")

if failures > 0 then
    io.stderr:write(string.format("\n%d failure(s)\n", failures))
    os.exit(1)
end
print("test_echo_performance_harden: all checks passed")
