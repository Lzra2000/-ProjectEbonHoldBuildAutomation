-- Soul Ashes field fallbacks + end-of-run peak refresh.

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("SOUL ASHES FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

function time() return 1700000000 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitName() return "Tester" end
function UnitLevel() return 50 end

EbonBuildsDB = { sessions = {}, currentSessionIndex = nil }
EbonBuilds = {
    EventHub = { Bump = function() end },
    SessionHistory = { OnHistoryChanged = function() end },
    Build = {
        GetActive = function()
            return { id = "b1", title = "Test", revision = 1, strategyRevision = 1 }
        end,
        Get = function() return nil end,
        StrategyChecksum = function() return "hash" end,
        DefaultSettings = function() return {} end,
    },
    Database = {
        CharacterKey = function() return "Tester-PALADIN" end,
        SchedulePrune = function() end,
    },
    Aggregates = nil,
    ProjectAPI = {
        GetRunData = function() return nil end,
    },
    Weights = { GetForSpell = function() return 0 end },
    Automation = {
        GetPeak = function() return 100 end,
        GetOutcomeStats = function() return { peak = 100, median = 50, p75 = 75, evBest3 = 80 } end,
    },
}

local requestDataCalls = 0
ProjectEbonhold = {
    PlayerRunService = {
        GetCurrentData = function() return nil end,
        RequestData = function()
            requestDataCalls = requestDataCalls + 1
        end,
    },
    PlayerRunUI = {
        GetUIElements = function()
            return {
                soulPointsText = {
                    GetText = function() return "|cffffffff42|r" end,
                },
            }
        end,
    },
}
EbonholdPlayerRunData = nil

assert(loadfile("modules/session/Session.lua"))("EbonBuilds", EbonBuilds)

------------------------------------------------------------------------
-- soulPoints primary field
------------------------------------------------------------------------
do
    EbonBuilds.ProjectAPI.GetRunData = function()
        return { soulPoints = 12, remainingBanishes = 1 }
    end
    equal(EbonBuilds.Session._GetRunSoulAshesForTests(), 12, "reads soulPoints")
end

------------------------------------------------------------------------
-- Alternate PE field names
------------------------------------------------------------------------
do
    EbonBuilds.ProjectAPI.GetRunData = function()
        return { soulAshes = 99, remainingBanishes = 1 }
    end
    equal(EbonBuilds.Session._GetRunSoulAshesForTests(), 99, "falls back to soulAshes")

    EbonBuilds.ProjectAPI.GetRunData = function()
        return { SoulAsh = 77, remainingBanishes = 1 }
    end
    equal(EbonBuilds.Session._GetRunSoulAshesForTests(), 77, "falls back to SoulAsh")
end

------------------------------------------------------------------------
-- UI text fallback when run tables are empty
------------------------------------------------------------------------
do
    EbonBuilds.ProjectAPI.GetRunData = function() return nil end
    EbonholdPlayerRunData = {}
    ProjectEbonhold.PlayerRunService.GetCurrentData = function() return {} end
    equal(EbonBuilds.Session._GetRunSoulAshesForTests(), 42, "reads colored soulPointsText from PE UI")
end

------------------------------------------------------------------------
-- Session peak survives end-of-run zeroed PE tables
------------------------------------------------------------------------
do
    requestDataCalls = 0
    EbonBuildsDB.sessions = {
        {
            id = "run-1",
            soulAshes = 0,
            logs = {},
            selectionCount = 5,
            startTime = 1,
            buildId = "b1",
        },
    }
    EbonBuildsDB.currentSessionIndex = 1

    -- Mid-run peak from an alternate field.
    EbonBuilds.ProjectAPI.GetRunData = function()
        return { soulAshes = 1500, remainingBanishes = 2 }
    end
    equal(EbonBuilds.Session._RefreshSessionSoulAshesForTests(EbonBuildsDB.sessions[1]), 1500,
        "mid-run refresh stores peak")

    -- Death reset zeros PE tables before EndCurrentSession.
    EbonBuilds.ProjectAPI.GetRunData = function()
        return { soulPoints = 0, remainingBanishes = 0 }
    end
    EbonholdPlayerRunData = { soulPoints = 0, remainingBanishes = 0 }
    ProjectEbonhold.PlayerRunService.GetCurrentData = function()
        return { soulPoints = 0, remainingBanishes = 0 }
    end
    ProjectEbonhold.PlayerRunUI.GetUIElements = function()
        return { soulPointsText = { GetText = function() return "0" end } }
    end

    EbonBuilds.Session.EndCurrentSession()
    equal(EbonBuildsDB.sessions[1].soulAshes, 1500,
        "end-of-run keeps session peak when PE reports 0")
    check(requestDataCalls >= 1, "end-of-run requests PE run-data refresh")
    check(EbonBuildsDB.currentSessionIndex == nil, "session closed")
end

if failures > 0 then
    io.stderr:write(string.format("SOUL ASHES: %d failure(s)\n", failures))
    os.exit(1)
end
print("Verified Soul Ashes field fallbacks and end-of-run peak refresh.")
