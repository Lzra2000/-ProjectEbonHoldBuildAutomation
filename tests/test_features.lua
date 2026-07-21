-- Current-architecture integration tests for canonical Echo identity,
-- exact-variant eligibility, refKey persistence, scoring, automation and EWL.
-- Run from the addon root with: texlua tests/test_features.lua

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
local function contains(list, value)
    for _, item in ipairs(list or {}) do if item == value then return true end end
    return false
end

EbonBuilds = { Runtime = {} }
EbonBuildsDB = { builds = {}, globalSettings = {} }
EbonBuildsCharDB = {}

local spellNames = {
    [200246] = "Blood Mirror",       -- intentionally wrong runtime name
    [201388] = "Blood Mirror",
    [200756] = "Overtime Conversion",
    [990001] = "Test Ranked Echo",
    [990002] = "Test Ranked Echo",
    [990003] = "Test Ranked Echo",
    [990010] = "Warrior Only Echo",
}

ProjectEbonhold = {
    addonVersion = 37,
    modVersion = "v37.test",
    PerkDatabase = {
        [200246] = { groupId = 10, quality = 3, classMask = 1535, requiredSpell = 0,
            comment = "Blood Mirror", families = { "Tank" } },
        [201388] = { groupId = 296, quality = 3, classMask = 1535, requiredSpell = 301388,
            comment = "Blood Mirror - Epic", families = { "Tank" } },
        [200756] = { groupId = 189, quality = 3, classMask = 1405, requiredSpell = 0,
            comment = "Overtime Conversion - Epic", families = { "Caster DPS", "Melee DPS", "Ranged DPS" } },
        [990001] = { groupId = 9001, quality = 0, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Common", families = { "Caster" } },
        [990002] = { groupId = 9001, quality = 1, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Uncommon", families = { "Caster" } },
        [990003] = { groupId = 9001, quality = 2, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Rare", families = { "Caster" } },
        [990010] = { groupId = 9002, quality = 0, classMask = 1, requiredSpell = 0,
            comment = "Warrior Only Echo - Common", families = { "Melee" } },
    },
    PerkService = {
        SelectPerk = function(spellId) ProjectEbonhold._selected = spellId end,
        GetGrantedPerks = function() return ProjectEbonhold._granted or {} end,
        GetCurrentChoice = function() return ProjectEbonhold._choices or {} end,
        GetDiscoveredEchoes = function() return {} end,
        BanishPerk = function(index) ProjectEbonhold._banished = index; return true end,
        RequestReroll = function() return false end,
        FreezePerk = function() return false end,
    },
    PerkUI = {
        Show = function() end,
        UpdateSinglePerk = function() end,
    },
}

local function Noop() end
local function FrameStub()
    return { RegisterEvent = Noop, SetScript = Noop, Show = Noop, Hide = Noop }
end
function CreateFrame() return FrameStub() end
function hooksecurefunc() end
function GetSpellInfo(spellId) return spellNames[tonumber(spellId)] end
function UnitName() return "Tester" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 80 end
function GetTalentTabInfo() return nil, nil, 0 end
function GetRealmName() return "TestRealm" end
function GetTime() return 0 end
function InCombatLockdown() return false end
function debugprofilestop() return 0 end
function date() return "2026-07-21 12:00:00" end
function time() return 123456789 end
function StaticPopup_Show() end
StaticPopupDialogs = {}
_G.utils = {}

local function Band(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 and bbit == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end
local function Bor(a, b, ...)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 or bbit == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    if select("#", ...) > 0 then return Bor(result, ...) end
    return result
end
bit = {
    band = Band,
    bor = Bor,
    bnot = function(value) return 4294967295 - (tonumber(value) or 0) end,
}

local eventListeners = {}
EbonBuilds.EventHub = {
    On = function(event, fn)
        eventListeners[event] = eventListeners[event] or {}
        eventListeners[event][#eventListeners[event] + 1] = fn
    end,
    Bump = function(event, ...)
        for _, fn in ipairs(eventListeners[event] or {}) do fn(...) end
    end,
}
EbonBuilds.Scheduler = {
    BACKGROUND = 3,
    MAINTENANCE = 4,
    Every = function() return true end,
    After = function(_, _, fn) fn(); return true end,
}
EbonBuilds.DebugLog = { IsEnabled = function() return false end, Add = Noop, AddF = Noop }
EbonBuilds.Toast = { Show = Noop, ShowAutomationResult = Noop }
EbonBuilds.Session = { LogAction = Noop, GetActiveSession = function() return nil end }

-- Load the real production chain, not a pre-projection compatibility subset.
assert(loadfile("core/RingBuffer.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/Quality.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/weights/Weights.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/Build.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/integration/ProjectEbonholdAPI.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoIdentityData.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoSemanticsData.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoCorrectionFacts.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoSemantics.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoIdentity.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoIdentityResolver.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoCatalog.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoEligibilityEvidence.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoEligibilityResolver.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/EchoProjection.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/EchoPolicy.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/Families.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/Scoring.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/ExportImport.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/EWL.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/Calibration.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/EchoSamples.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/EchoPerformance.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/ManualTraining.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/Automation.lua"))("EbonBuilds", EbonBuilds)

EbonBuilds.EchoCatalog.Init()
EbonBuilds.EchoEligibilityEvidence.Init()

-- Core quality and settings contracts.
do
    equal(#EbonBuilds.Quality.ORDER, 4, "four supported Echo qualities")
    equal(EbonBuilds.Quality.ORDER[1], 3, "Epic is first")
    local fresh = EbonBuilds.Build.NewBuildSettings()
    equal(fresh.rerollMode, "ev", "new builds use Smart reroll mode")
    equal(EbonBuilds.Build.DefaultSettings().rerollMode, "sum", "legacy defaults remain Classic")
end

-- The reviewed Overtime correction is consumed by the generic exact-variant resolver.
do
    local mageEntry, mageVariant = EbonBuilds.EchoProjection.ResolveSpell("MAGE", 200756)
    check(mageEntry and mageVariant, "Overtime Conversion is available to Mage")
    equal(mageVariant and mageVariant.spellId, 200756, "Mage resolves the exact Overtime spell")
    check(EbonBuilds.EchoProjection.ResolveSpell("PALADIN", 200756) == nil,
        "Overtime Conversion remains unavailable to Paladin")
    equal(EbonBuilds.EchoEligibilityResolver.GetEffectiveMask(200756), 1533,
        "Overtime Conversion effective mask is all classes except Paladin")
end

-- Runtime-name collision cannot merge canonical Echo identities.
do
    local crimson = EbonBuilds.EchoCatalog.GetByRef("g:10")
    local mirror = EbonBuilds.EchoCatalog.GetByRef("g:296")
    equal(crimson and crimson.displayName, "Crimson Reprisal", "Crimson Reprisal keeps its canonical name")
    equal(mirror and mirror.displayName, "Blood Mirror", "Blood Mirror keeps its canonical name")
    equal(EbonBuilds.EchoCatalog.GetRefForSpell(200246), "g:10", "Crimson exact spell keeps g:10")
    equal(EbonBuilds.EchoCatalog.GetRefForSpell(201388), "g:296", "Blood Mirror exact spell keeps g:296")
    local bloodRefs = EbonBuilds.EchoCatalog.FindRefs("Blood Mirror")
    equal(#bloodRefs, 1, "safe Blood Mirror lookup is unambiguous")
    equal(bloodRefs[1], "g:296", "safe Blood Mirror lookup selects the canonical identity")
    local legacyRefs = EbonBuilds.EchoCatalog.FindLegacyRefs("Blood Mirror")
    check(contains(legacyRefs, "g:10") and contains(legacyRefs, "g:296"),
        "legacy collision lookup quarantines both possible identities")
end

-- Exact variants remain authoritative inside a group.
do
    local entry = EbonBuilds.EchoProjection.GetEntry("MAGE", "g:9001")
    check(entry ~= nil, "synthetic ranked Echo is present in the Mage projection")
    equal(#(entry and entry.availableVariants or {}), 3, "all three exact Mage variants remain available")
    local spellId, quality = EbonBuilds.EchoProjection.GetBestVariant("MAGE", "g:9001", 990001)
    equal(spellId, 990001, "available preferred exact variant is retained")
    equal(quality, 0, "preferred Common quality is retained")
    check(EbonBuilds.EchoProjection.ResolveSpell("MAGE", 990003) ~= nil, "Rare exact variant resolves")
    check(EbonBuilds.EchoProjection.ResolveSpell("WARRIOR", 990003) == nil, "Mage variant is not widened to Warrior")
end

-- Rank-specific values migrate to refKey storage and survive inactive eligibility.
do
    local build = EbonBuilds.Build.NewObject({
        title = "Migration",
        class = "MAGE",
        echoWeights = { ["Test Ranked Echo"] = { [0] = -10, [1] = 5, [2] = 30 } },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    EbonBuilds.Weights.MigrateBuild(build)
    check(type(build.echoWeightsByRef["g:9001"]) == "table", "legacy name migrates to stable refKey")
    equal(EbonBuilds.Weights.GetForRef(build, "g:9001", 0), -10, "Common value survives migration")
    equal(EbonBuilds.Weights.GetForRef(build, "g:9001", 1), 5, "Uncommon value survives migration")
    equal(EbonBuilds.Weights.GetForRef(build, "g:9001", 2), 30, "Rare value survives migration")

    local paladin = EbonBuilds.Build.NewObject({
        title = "Inactive preserved",
        class = "PALADIN",
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint(),
        echoWeightsByRef = { ["g:189"] = { [0] = 22, [1] = 22, [2] = 22, [3] = 22 } },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    EbonBuilds.Weights.MigrateBuild(paladin)
    check(type(paladin.echoWeightsByRef["g:189"]) == "table",
        "valid Overtime configuration survives while inactive for Paladin")
end

-- Automation reads the value for the exact offered quality through the projection.
do
    local build = EbonBuilds.Build.NewObject({
        title = "Automation rank scoring",
        class = "MAGE",
        echoSchema = 3,
        echoWeightsByRef = { ["g:9001"] = { [0] = -10, [1] = 5, [2] = 30, [3] = 0 } },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 990001, quality = 0 }, build.settings).score, -10,
        "automation applies Common weight")
    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 990002, quality = 1 }, build.settings).score, 5,
        "automation applies Uncommon weight")
    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 990003, quality = 2 }, build.settings).score, 30,
        "automation applies Rare weight")
end

-- Scoring iterates the canonical available quality set.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    local name, peak = EbonBuilds.Scoring.ComputePeak("MAGE", settings, function(refKey, quality)
        if refKey ~= "g:9001" then return 0 end
        return ({ [0] = 50, [1] = 5, [2] = -10 })[quality]
    end)
    equal(name, "Test Ranked Echo", "peak identifies canonical ranked Echo")
    equal(peak, 50, "Common can define the peak")
    local stats = EbonBuilds.Scoring.ComputeOutcomeStats("MAGE", settings, function(refKey, quality)
        if refKey ~= "g:9001" then return 0 end
        return ({ [0] = 50, [1] = 5, [2] = -10 })[quality]
    end)
    check(stats.mean > 0, "outcome statistics include exact available ranks")
    check(stats.evBest3 >= stats.mean, "best-of-three expectation is at least the single-offer mean")
end

-- Whitelist and conditional policy storage are refKey-based.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.echoWhitelist["g:9001"] = true
    settings.echoBanList[990001] = "Test Ranked Echo"
    check(EbonBuilds.Scoring.IsWhitelisted(990001, settings), "spell resolves to refKey whitelist")
    check(not EbonBuilds.Scoring.IsBanned(990001, settings), "whitelist overrides direct ban")
    check(EbonBuilds.EchoPolicy.Set(settings, 990001, EbonBuilds.EchoPolicy.NEVER_PICK),
        "policy accepts exact spell and stores canonical ref")
    equal(settings.echoPolicies["g:9001"], EbonBuilds.EchoPolicy.NEVER_PICK,
        "policy is stored under stable refKey")
end

-- EWL serializes exact resolved variant IDs while validating class eligibility.
do
    EchoWishlist = {
        catalog = {
            {
                id = 990001, spellId = 990001, name = "Test Ranked Echo", quality = 2, classMask = 128,
                _variants = {
                    { id = 990002, spellId = 990002, name = "Test Ranked Echo", quality = 1, classMask = 128 },
                    { id = 990003, spellId = 990003, name = "Test Ranked Echo", quality = 2, classMask = 128 },
                },
            },
            { id = 200756, spellId = 200756, name = "Overtime Conversion", quality = 3, classMask = 1405 },
            { id = 990010, spellId = 990010, name = "Warrior Only Echo", quality = 0, classMask = 1 },
        },
    }
    local build = EbonBuilds.Build.NewObject({
        title = "EWL exact eligibility",
        class = "MAGE",
        lockedEchoes = { 990003, 990010 },
        echoSchema = 3,
        echoWeightsByRef = {
            ["g:9001"] = { [0] = 1, [1] = 2, [2] = 3, [3] = 0 },
            ["g:189"] = { [0] = 0, [1] = 0, [2] = 0, [3] = 12 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local ewl, err, info = EbonBuilds.EWL.Generate(build)
    equal(err, nil, "EWL generation succeeds")
    check(ewl and ewl:find("990003:1", 1, true), "locked rank serializes the exact resolved spell ID")
    check(ewl and not ewl:find("990001:1", 1, true), "retained family ID is not substituted for the exact locked rank")
    check(ewl and ewl:find("200756:0", 1, true), "Mage Overtime weight is exported")
    check(ewl and not ewl:find("990010:1", 1, true), "class-invalid locked Echo is omitted")
    equal(info.locked, 1, "only the eligible locked family is counted")
    equal(info.normal, 1, "one weighted non-locked family is counted")
    equal(#info.unresolved, 1, "invalid locked exact spell is reported once")
end

-- Export/import retains canonical ref weights and policies.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.echoWhitelist["g:9001"] = true
    settings.echoPolicies["g:9001"] = EbonBuilds.EchoPolicy.NEVER_PICK
    local build = EbonBuilds.Build.NewObject({
        title = "Round trip",
        class = "MAGE",
        echoSchema = 3,
        echoWeightsByRef = { ["g:9001"] = { [0] = -4, [1] = 6, [2] = 18, [3] = 0 } },
        settings = settings,
    })
    local encoded = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded, err = EbonBuilds.ExportImport.DecodeBuild(encoded)
    equal(err, nil, "build export/import decodes")
    equal(decoded.echoWeightsByRef["g:9001"][0], -4, "negative Common value round-trips")
    equal(decoded.echoWeightsByRef["g:9001"][2], 18, "Rare value round-trips")
    check(decoded.settings.echoWhitelist["g:9001"], "refKey whitelist round-trips")
    equal(decoded.settings.echoPolicies["g:9001"], EbonBuilds.EchoPolicy.NEVER_PICK,
        "refKey policy round-trips")
end

-- Validation remains integer-only and negative-capable.
do
    equal(EbonBuilds.Weights.Validate("-25"), -25, "negative integer is accepted")
    check(EbonBuilds.Weights.Validate("1.5") == nil, "decimal is rejected")
    check(EbonBuilds.Weights.Validate(1000000) == nil, "out-of-range value is rejected")
end

if failures > 0 then
    io.stderr:write(string.format("%d test(s) failed.\n", failures))
    os.exit(1)
end
print("All current feature tests passed.")
