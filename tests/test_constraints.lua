-- Unit coverage for WP5 client constraints packing (#54).

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

EbonBuilds = {
    EchoPolicy = {
        NORMAL = "normal",
        BANISH_ON_SIGHT = "banish_on_sight",
        NEVER_PICK = "never_pick",
        Normalize = function(settings)
            settings.echoPolicies = settings.echoPolicies or {}
        end,
    },
    Build = {
        EnsureSettings = function() end,
    },
}

assert(loadfile("modules/automation/Constraints.lua"))("EbonBuilds", EbonBuilds)
local C = EbonBuilds.AutomationConstraints

local sampleSettings = {
    rerollMode = "ev",
    autoBanishPct = 20,
    autoRerollPct = 120,
    rerollGuardPct = 90,
    rerollEVPct = 95,
    banishEVPct = 60,
    freezeEVPct = 110,
    autoFreezePct = 80,
    freezePenaltyPct = 10,
    banishFamilyWhitelist = { Caster = true, Tank = true },
    echoPolicies = {
        ["g:296"] = "banish_on_sight",
        ["s:101"] = "never_pick",
    },
    echoBanList = { [501] = true, [502] = true },
    echoWhitelist = { ["g:42"] = true },
}

local runData = {
    totalRerolls = 12,
    usedRerolls = 4,
    remainingBanishes = 3,
    totalFreezes = 6,
    usedFreezes = 1,
}

do
    local first = C.FromSettings(sampleSettings, { runData = runData })
    local second = C.FromSettings(sampleSettings, { runData = runData })
    check(type(first.hash) == "string" and #first.hash == 8, "hash is 8 hex chars")
    equal(first.hash, second.hash, "identical prefs produce stable hash")
    equal(first.table.v, 1, "schema version is 1")
    equal(first.table.maxRerolls, 8, "maxRerolls derived from run data")
end

do
    local changed = C.FromSettings({ rerollMode = "ev", freezePenaltyPct = 11 })
    local baseline = C.FromSettings({ rerollMode = "ev", freezePenaltyPct = 10 })
    check(changed.hash ~= baseline.hash, "hash changes when freezePenaltyPct changes")
end

do
    local packed = C.FromSettings(sampleSettings, { runData = runData })
    check(packed.wire:match("^v=1;"), "wire starts with version")
    local parsed = C.Parse(packed.wire)
    check(parsed ~= nil, "parse succeeded")
    equal(parsed.autoBanishPct, 20, "round-trip autoBanishPct")
    equal(parsed.maxRerolls, 8, "round-trip maxRerolls")
end

do
    local parsed = C.Parse("v=2;rerollMode=ev")
    equal(parsed, nil, "unsupported major version rejected")
end

do
    local minimal = C.FromSettings({
        rerollMode = "ev",
        freezePenaltyPct = 10,
        banishFamilyWhitelist = { Caster = true, Tank = true },
        echoPolicies = {
            ["g:296"] = "banish_on_sight",
            ["s:101"] = "never_pick",
        },
    }, { runData = { totalRerolls = 12, usedRerolls = 4 } })
    check(C.FitsAddonMsg(minimal.wire), "typical constraints wire fits soft limit")
end

do
    function GetTime() return 1000 end
    ProjectEbonhold = { Perks = {} }
    EbonBuilds.ProjectAPI = { GetPendingAction = function() return nil end }
    assert(loadfile("modules/automation/IntentQueue.lua"))("EbonBuilds", EbonBuilds)
    local IQ = EbonBuilds.AutomationIntentQueue
    IQ.Reset()
    local accepted = IQ.TryBegin("select", {
        identityFingerprint = "board-a",
        constraintsHash = "abc12345",
    })
    equal(accepted, true, "intent accepted with constraintsHash")
    equal(IQ.GetInFlight().constraintsHash, "abc12345", "constraintsHash stored")
end

if failures > 0 then
    io.stderr:write(string.format("test_constraints: %d failure(s)\n", failures))
    os.exit(1)
end

print("test_constraints: ok")
