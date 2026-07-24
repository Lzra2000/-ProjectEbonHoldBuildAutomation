-- Round-trip and rejection coverage for modules/build/ExportImport.lua and
-- the EWL generation gate. Uses the same production loading chain as
-- tests/test_features.lua so migration, catalog resolution, and policy
-- validation run against real code, not stubs.

unpack = unpack or table.unpack

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

EbonBuilds = { Runtime = {} }
EbonBuildsDB = { builds = {}, globalSettings = {} }
EbonBuildsCharDB = {}

local spellNames = {
    [990001] = "Test Ranked Echo",
    [990002] = "Test Ranked Echo",
    [990003] = "Test Ranked Echo",
    [990010] = "Warrior Only Echo",
}

ProjectEbonhold = {
    addonVersion = 37,
    modVersion = "v37.test",
    PerkDatabase = {
        [990001] = { groupId = 9001, quality = 0, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Common", families = { "Caster" } },
        [990002] = { groupId = 9001, quality = 1, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Uncommon", families = { "Caster" } },
        [990003] = { groupId = 9001, quality = 2, classMask = 128, requiredSpell = 0,
            comment = "Test Ranked Echo - Rare", families = { "Caster" } },
        [990010] = { groupId = 9002, quality = 0, classMask = 1, requiredSpell = 0,
            comment = "Warrior Only Echo - Common", families = { "Melee" } },
    },
    PerkService = { GetGrantedPerks = function() return {} end },
    PerkUI = { Show = function() end },
}

local function Noop() end
-- Catch-all frame stub: any method exists, count/number getters return 0
-- (EWL's tooltip scanner calls SetOwner/ClearLines/SetHyperlink/NumLines).
function CreateFrame()
    return setmetatable({}, {
        __index = function(_, key)
            if key == "NumLines" then return function() return 0 end end
            return Noop
        end,
    })
end
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
function date() return "2026-07-24 12:00:00" end
function time() return 123456789 end
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
bit = { band = Band, bor = function(a, b) return (tonumber(a) or 0) + (tonumber(b) or 0) end,
    bnot = function(value) return 4294967295 - (tonumber(value) or 0) end }

EbonBuilds.EventHub = { On = Noop, Bump = Noop }
EbonBuilds.Scheduler = {
    BACKGROUND = 3, MAINTENANCE = 4,
    Every = function() return true end,
    After = function(_, _, fn) fn(); return true end,
}
EbonBuilds.DebugLog = { IsEnabled = function() return false end, Add = Noop, AddF = Noop }
EbonBuilds.Toast = { Show = Noop, ShowAutomationResult = Noop }
EbonBuilds.Session = { LogAction = Noop, GetActiveSession = function() return nil end }

assert(loadfile("core/RingBuffer.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/Quality.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/weights/Weights.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/Build.lua"))("EbonBuilds", EbonBuilds)
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

EbonBuilds.EchoCatalog.Init()
EbonBuilds.EchoEligibilityEvidence.Init()

local EI = EbonBuilds.ExportImport

-- Local base64 encoder to craft hostile payloads independent of the
-- module's own encoder (mirrors RFC 4648, standard alphabet).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Encode64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = (a or 0) * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = B64:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        out[#out + 1] = B64:sub(math.floor((n % 262144) / 4096) + 1, math.floor((n % 262144) / 4096) + 1)
        out[#out + 1] = (i + 1 <= #data) and B64:sub(math.floor((n % 4096) / 64) + 1, math.floor((n % 4096) / 64) + 1) or "="
        out[#out + 1] = (i + 2 <= #data) and B64:sub((n % 64) + 1, (n % 64) + 1) or "="
    end
    return table.concat(out)
end
------------------------------------------------------------------------
-- JSON encoder/decoder round trips
------------------------------------------------------------------------
do
    local decoded = EI.JSONDecode(EI.JSONEncode({
        text = "quote\" backslash\\ newline\n tab\t",
        number = -42,
        big = 123456,
        truthy = true,
        falsy = false,
        list = { 1, 2, 3 },
        nested = { inner = { deep = "value" } },
    }))
    equal(decoded.text, "quote\" backslash\\ newline\n tab\t", "string escapes round-trip")
    equal(decoded.number, -42, "negative number round-trips")
    equal(decoded.truthy, true, "true round-trips")
    equal(decoded.falsy, false, "false round-trips")
    equal(#decoded.list, 3, "array length round-trips")
    equal(decoded.list[3], 3, "array content round-trips")
    equal(decoded.nested.inner.deep, "value", "nested object round-trips")

    -- Hidden Echo-variant control bytes must survive as \u00XX escapes.
    local hidden = "Iron Constitution" .. string.char(0) .. "2"
    local json = EI.JSONEncode({ [hidden] = 5 })
    check(json:find("\\u0000", 1, true), "NUL byte is escaped as \\u0000")
    local hiddenBack = EI.JSONDecode(json)
    equal(hiddenBack[hidden], 5, "control-byte key round-trips")

    -- JSON object keys are strings by spec; numeric Lua keys must coerce back.
    local numericKeys = EI.JSONDecode(EI.JSONEncode({ qualityBonus = { [0] = 1, [3] = 9 } }))
    equal(numericKeys.qualityBonus[0], 1, "numeric key 0 coerces back to a number")
    equal(numericKeys.qualityBonus[3], 9, "numeric key 3 coerces back to a number")
    local negativeKey = EI.JSONDecode('{"-2":7}')
    equal(negativeKey[-2], 7, "negative integer-looking key coerces back")

    equal(EI.JSONEncode(0 / 0), "null", "NaN encodes as null")
    equal(EI.JSONEncode(math.huge), "null", "infinity encodes as null")
    equal(EI.JSONDecode("null"), nil, "null decodes to nil")
    equal(EI.JSONDecode(""), nil, "empty string decodes to nil")
    equal(EI.JSONDecode('"\\u0041"'), "A", "unicode escape decodes")
end

------------------------------------------------------------------------
-- DecodeBuild input hardening
------------------------------------------------------------------------
do
    local function CraftedDecode(tbl)
        return EI.DecodeBuild(Encode64(EI.JSONEncode(tbl)))
    end

    check(EI.DecodeBuild(nil) == nil, "nil input rejected")
    check(EI.DecodeBuild("") == nil, "empty input rejected")
    check(EI.DecodeBuild("not base64 at all!!") == nil, "invalid base64 characters rejected")
    check(EI.DecodeBuild("abc") == nil, "wrong base64 length rejected")
    check(EI.DecodeBuild(Encode64("this is not json")) == nil, "non-JSON payload rejected")
    check(EI.DecodeBuild(string.rep("A", 98308)) == nil, "oversized payload rejected")

    check(CraftedDecode({ v = 99, title = "Future" }) == nil, "future export version rejected")
    check(CraftedDecode({ v = 4, class = "GNOME" }) == nil, "invalid class token rejected")
    check(CraftedDecode({ v = 4, class = "MAGE", lockedEchoes = { [0] = 990001 } }) == nil,
        "locked slot index below range rejected")
    check(CraftedDecode({ v = 4, class = "MAGE", lockedEchoes = { [99] = 990001 } }) == nil,
        "locked slot index above range rejected")
    check(CraftedDecode({ v = 4, class = "MAGE", lockedEchoes = { [1] = -5 } }) == nil,
        "negative locked spell id rejected")
    check(CraftedDecode({ v = 4, class = "MAGE", lockedEchoes = { [1] = 990010 } }) == nil,
        "provably cross-class locked Echo rejected")
    check(CraftedDecode({ v = 4, class = "MAGE",
        echoWeights = { ["Test Ranked Echo"] = { [9] = 5 } } }) == nil,
        "unknown weight rank rejected")
    check(CraftedDecode({ v = 4, class = "MAGE",
        echoWeights = { ["Test Ranked Echo"] = { [2] = 9999999 } } }) == nil,
        "out-of-range weight rejected")
    check(CraftedDecode({ v = 4, class = "MAGE",
        echoWeights = { [string.rep("N", 200)] = 5 } }) == nil,
        "oversized weight key rejected")
    check(CraftedDecode({ v = 4, class = "MAGE",
        echoWeightsByRef = { ["not-a-ref"] = { [2] = 5 } } }) == nil,
        "malformed refKey rejected")
    check(CraftedDecode({ v = 4, class = "MAGE",
        settings = { echoPolicies = { ["g:9001"] = "explode_on_sight" } } }) == nil,
        "unknown Echo policy rejected")

    -- Excessively deep trees must be refused before any allocation storm.
    local bomb = { v = 4, class = "MAGE", settings = {} }
    local cursor = bomb.settings
    for _ = 1, 12 do
        cursor.next = {}
        cursor = cursor.next
    end
    check(CraftedDecode(bomb) == nil, "deep settings tree rejected")

    -- Legitimate builds still decode after all that hostility.
    check(CraftedDecode({ v = 4, class = "MAGE", title = "Still fine" }) ~= nil,
        "well-formed minimal payload decodes")
end

------------------------------------------------------------------------
-- Full build export -> import round trip
------------------------------------------------------------------------
do
    local hidden = "Iron Constitution" .. string.char(0) .. "2"
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.qualityBonus[3] = 25
    settings.qualityBonusMode[3] = true
    settings.familyBonus["Caster"] = 6
    settings.echoWhitelist["g:9001"] = true
    settings.echoPolicies["g:9001"] = EbonBuilds.EchoPolicy.NEVER_PICK
    settings.autoBanishPct = 33

    local build = EbonBuilds.Build.NewObject({
        title = "Round Trip Fixture",
        class = "MAGE",
        spec = 2,
        comments = "Original comment",
        lockedEchoes = { 990003 },
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint(),
        echoWeightsByRef = { ["g:9001"] = { [0] = -4, [1] = 0, [2] = 18, [3] = 7 } },
        echoWeights = { [hidden] = { [0] = 15 }, ["Zero Weight Echo"] = { [0] = 0 } },
        settings = settings,
        isPublic = true,
        validated = true,
        author = "Tester",
        characterSnapshot = { classToken = "MAGE", talents = {} },
    })

    local encoded = EI.ExportBuild(build)
    check(type(encoded) == "string" and #encoded > 0, "export produces a base64 string")
    check(not encoded:find("[^A-Za-z0-9+/=]"), "export contains only base64 characters")

    local decoded = EI.DecodeBuild(encoded)
    check(decoded ~= nil, "exported build decodes")
    equal(decoded.title, "Round Trip Fixture", "title round-trips")
    equal(decoded.class, "MAGE", "class round-trips")
    equal(decoded.spec, 2, "spec round-trips")
    equal(decoded.comments, "Original comment", "comments round-trip")
    equal(decoded.isPublic, true, "public flag round-trips")
    equal(decoded.validated, true, "validated flag round-trips")
    equal(decoded.author, "Tester", "author round-trips")
    equal(decoded.lockedEchoes[1], 990003, "locked Echo round-trips")
    equal(decoded.echoWeightsByRef["g:9001"][0], -4, "negative Common ref weight round-trips")
    equal(decoded.echoWeightsByRef["g:9001"][2], 18, "Rare ref weight round-trips")
    equal(decoded.echoWeightsByRef["g:9001"][3], 7, "Epic ref weight round-trips")
    equal(decoded.echoWeights[hidden][0], 15, "hidden control-byte legacy key round-trips")
    check(decoded.echoWeights["Zero Weight Echo"] == nil, "all-zero weights are filtered from export")
    equal(decoded.settings.qualityBonus[3], 25, "numeric qualityBonus key survives JSON round trip")
    equal(decoded.settings.qualityBonusMode[3], true, "quality bonus mode round-trips")
    equal(decoded.settings.familyBonus["Caster"], 6, "family bonus round-trips")
    equal(decoded.settings.autoBanishPct, 33, "threshold setting round-trips")
    check(decoded.settings.echoWhitelist["g:9001"], "protection whitelist round-trips")
    equal(decoded.settings.echoPolicies["g:9001"], EbonBuilds.EchoPolicy.NEVER_PICK,
        "Echo policy round-trips")
    equal(decoded.characterSnapshot.classToken, "MAGE", "character snapshot round-trips")
    check(decoded.id ~= build.id, "imported build receives its own identity")
    equal(decoded.importedFrom, "Tester", "import provenance is recorded")

    -- Effective values must be identical after migration on the importing
    -- client: what the exporter scored is what the importer scores.
    EbonBuilds.Weights.MigrateBuild(decoded)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER) do
        equal(EbonBuilds.Weights.GetForRef(decoded, "g:9001", quality),
            EbonBuilds.Weights.GetForRef(build, "g:9001", quality),
            "effective g:9001 rank " .. quality .. " weight matches after import migration")
    end

    -- Double round trip: exporting the import must preserve the same data.
    local doubleDecoded = EI.DecodeBuild(EI.ExportBuild(decoded))
    check(doubleDecoded ~= nil, "second-generation export decodes")
    equal(doubleDecoded.echoWeightsByRef["g:9001"][2], 18, "second-generation ref weight intact")
    equal(doubleDecoded.settings.echoPolicies["g:9001"], EbonBuilds.EchoPolicy.NEVER_PICK,
        "second-generation policy intact")

    -- Oversized text fields are clamped, not refused.
    local clamped = EI.DecodeBuild(Encode64(EI.JSONEncode({
        v = 4, class = "MAGE",
        title = string.rep("T", 500),
        comments = string.rep("c", 5000),
        author = string.rep("a", 500),
    })))
    check(clamped ~= nil, "oversized text fields decode")
    equal(#clamped.title, 80, "title clamped to 80 characters")
    equal(#clamped.comments, 4000, "comments clamped to 4000 characters")
    equal(#clamped.author, 80, "author clamped to 80 characters")
end

------------------------------------------------------------------------
-- EWL generation gate
------------------------------------------------------------------------
do
    local unresolvedBuild = EbonBuilds.Build.NewObject({
        title = "Unresolved fixture",
        class = "MAGE",
        echoSchema = 3,
        echoWeightsByRef = { ["g:9001"] = { [0] = 5, [1] = 0, [2] = 0, [3] = 0 } },
        unresolvedEchoWeights = {
            { legacyName = "Ghost Echo", reason = "MISSING_ALIAS", weights = { [0] = 5 } },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local text, err, info = EbonBuilds.EWL.Generate(unresolvedBuild)
    equal(text, nil, "unresolved references block EWL export")
    check(tostring(err):find("UNRESOLVED_ECHO_REFERENCES", 1, true), "gate names the failure class")
    equal(info and info.unresolvedCount, 1, "gate reports the unresolved count")

    local emptyBuild = EbonBuilds.Build.NewObject({
        title = "Empty fixture",
        class = "MAGE",
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local emptyText, emptyErr = EbonBuilds.EWL.Generate(emptyBuild)
    equal(emptyText, nil, "a build without weights or locks exports nothing")
    check(tostring(emptyErr):find("no locked or weighted", 1, true), "empty build error is explicit")

    check(select(1, EbonBuilds.EWL.Generate(nil)) == nil, "nil build is refused")
end

if failures > 0 then
    io.stderr:write(string.format("%d export/import test(s) failed.\n", failures))
    os.exit(1)
end
print("Export/import coverage passed: JSON round trips, hostile-payload rejection, full build round trip, and the EWL gate.")
