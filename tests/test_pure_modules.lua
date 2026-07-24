-- Unit coverage for the pure-logic build modules: Quality, Weights,
-- Scoring, and EchoPolicy. These run without the Echo catalog or any UI --
-- only the modules under test plus modules/data/Families.lua, which Scoring
-- resolves at call time. Deterministic, no I/O beyond loading the modules.

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
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
        string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
EbonBuildsDB = { builds = {}, globalSettings = {} }
EbonBuildsCharDB = {}

-- Minimal WoW API surface for CanonicalName fallbacks.
local spellNames = { [777001] = "Fallback Echo - Rare" }
function GetSpellInfo(spellId) return spellNames[tonumber(spellId)] end
ProjectEbonhold = {
    PerkDatabase = {
        [777001] = { groupId = 7001, quality = 2, comment = "Fallback Echo - Rare", families = {} },
        [777002] = { groupId = 7002, quality = 3, comment = "Epic Only Echo - Epic", families = {} },
    },
}

assert(loadfile("modules/data/Quality.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/weights/Weights.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/data/Families.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/Scoring.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/EchoPolicy.lua"))("EbonBuilds", EbonBuilds)

------------------------------------------------------------------------
-- Quality
------------------------------------------------------------------------
do
    local Q = EbonBuilds.Quality
    equal(#Q.ORDER, 4, "four supported qualities")
    equal(Q.ORDER[1], 3, "intent-first order starts at Epic")
    equal(Q.ORDER[4], 0, "intent-first order ends at Common")
    equal(Q.LABELS[0], "Common", "Common label")
    equal(Q.LABELS[3], "Epic", "Epic label")
    check(Q.IsValid(0) and Q.IsValid(1) and Q.IsValid(2) and Q.IsValid(3), "ranks 0..3 are valid")
    check(not Q.IsValid(4), "rank 4 is invalid")
    check(not Q.IsValid(-1), "rank -1 is invalid")
    check(not Q.IsValid(nil), "nil rank is invalid")
    check(not Q.IsValid("2"), "string rank is invalid (numeric keys only)")

    -- RGB tables must be derived exactly from the hex definitions.
    for quality, hex in pairs(Q.HEX) do
        local r, g, b = Q.GetRGB(quality)
        near(r, tonumber(hex:sub(1, 2), 16) / 255, "R channel matches hex for rank " .. quality)
        near(g, tonumber(hex:sub(3, 4), 16) / 255, "G channel matches hex for rank " .. quality)
        near(b, tonumber(hex:sub(5, 6), 16) / 255, "B channel matches hex for rank " .. quality)
    end
    -- Unknown ranks fall back to Common rather than erroring in a render path.
    local r, g, b = Q.GetRGB(99)
    near(r, 1, "unknown rank falls back to Common R")
    near(g, 1, "unknown rank falls back to Common G")
    near(b, 1, "unknown rank falls back to Common B")

    equal(Q.Colorize("X", 3), "|cffa335eeX|r", "Epic colorize uses the Epic hex")
    equal(Q.Colorize("X", 99), "|cffffffffX|r", "unknown rank colorizes as Common")
    equal(Q.Colorize(nil, 0), "|cffffffffnil|r", "nil text is stringified, never a Lua error")

    equal(Q.OfSpell(777002), 3, "OfSpell reads the perk database quality")
    equal(Q.OfSpell(999999), nil, "unknown spell has no quality")
    equal(Q.OfSpell(nil), nil, "nil spell has no quality")
end

------------------------------------------------------------------------
-- Weights: validation
------------------------------------------------------------------------
do
    local W = EbonBuilds.Weights
    equal(W.Validate(25), 25, "plain integer accepted")
    equal(W.Validate(-25), -25, "negative integer accepted")
    equal(W.Validate(0), 0, "zero accepted")
    equal(W.Validate("  42  "), 42, "surrounding whitespace trimmed")
    equal(W.Validate("+7"), 7, "explicit plus sign accepted")
    equal(W.Validate("-0"), 0, "negative zero normalizes to zero")
    equal(W.Validate(W.MIN_VALUE), W.MIN_VALUE, "minimum boundary accepted")
    equal(W.Validate(W.MAX_VALUE), W.MAX_VALUE, "maximum boundary accepted")
    check(W.Validate(W.MAX_VALUE + 1) == nil, "value above maximum rejected")
    check(W.Validate(W.MIN_VALUE - 1) == nil, "value below minimum rejected")
    check(W.Validate(2.5) == nil, "decimal number rejected")
    check(W.Validate("1.5") == nil, "decimal string rejected")
    check(W.Validate("1e3") == nil, "scientific notation rejected")
    check(W.Validate("") == nil, "empty string rejected")
    check(W.Validate("   ") == nil, "whitespace-only string rejected")
    check(W.Validate("abc") == nil, "non-numeric string rejected")
    check(W.Validate("12abc") == nil, "trailing garbage rejected")
    check(W.Validate(0 / 0) == nil, "NaN rejected")
    check(W.Validate(math.huge) == nil, "positive infinity rejected")
    check(W.Validate(-math.huge) == nil, "negative infinity rejected")
    check(W.Validate(true) == nil, "boolean rejected")
    check(W.Validate(nil) == nil, "nil rejected")
    check(W.Validate({}) == nil, "table rejected")
end

------------------------------------------------------------------------
-- Weights: name helpers
------------------------------------------------------------------------
do
    local W = EbonBuilds.Weights
    equal(W.StripQualitySuffix("Arcane Bond - Epic"), "Arcane Bond", "Epic suffix stripped")
    equal(W.StripQualitySuffix("Arcane Bond - Rare"), "Arcane Bond", "Rare suffix stripped")
    equal(W.StripQualitySuffix("Arcane Bond - Uncommon"), "Arcane Bond", "Uncommon suffix stripped")
    equal(W.StripQualitySuffix("Arcane Bond - Common"), "Arcane Bond", "Common suffix stripped")
    equal(W.StripQualitySuffix("Arcane Bond"), "Arcane Bond", "no suffix is untouched")
    equal(W.StripQualitySuffix("Arcane Bond - Legendary"), "Arcane Bond - Legendary",
        "unknown suffix is preserved")
    equal(W.StripQualitySuffix("Epic - Epic"), "Epic", "name equal to a rank label still strips once")
    equal(W.StripQualitySuffix(nil), "", "nil name yields empty string")

    -- Control-byte discriminators must stay out of every visible string.
    equal(W.VisibleName("Iron Constitution" .. string.char(0) .. "2"), "Iron Constitution",
        "NUL discriminator removed")
    equal(W.VisibleName("Iron Constitution" .. string.char(1) .. "suffix"), "Iron Constitution",
        "low control byte removed")
    equal(W.VisibleName("Iron Constitution" .. string.char(127)), "Iron Constitution",
        "DEL byte removed")
    equal(W.VisibleName("  Padded  "), "Padded", "whitespace trimmed")
    equal(W.VisibleName(nil), "", "nil name yields empty string")

    equal(W.CanonicalName(777001), "Fallback Echo", "canonical name strips the quality suffix")
    equal(W.CanonicalName("777001"), "Fallback Echo", "numeric string spell id accepted")
    equal(W.CanonicalName(999999), nil, "unknown spell has no canonical name")
    equal(W.CanonicalName("not a number"), nil, "non-numeric input has no canonical name")
end

------------------------------------------------------------------------
-- Weights: entry normalization and reads
------------------------------------------------------------------------
do
    local W = EbonBuilds.Weights

    local uniform = W.MakeUniform(12)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER) do
        equal(uniform[quality], 12, "MakeUniform sets rank " .. quality)
    end
    equal(W.MakeUniform("bogus")[0], 0, "invalid uniform input becomes zero")

    local legacy = W.NormalizeEntry(7)
    equal(legacy[3], 7, "legacy number copies to Epic")
    equal(legacy[0], 7, "legacy number copies to Common")

    local partial = W.NormalizeEntry({ [3] = 30, default = 4 })
    equal(partial[3], 30, "explicit rank kept")
    equal(partial[2], 4, "missing rank falls back to default")
    equal(partial[0], 4, "missing Common falls back to default")

    local stringKeys = W.NormalizeEntry({ ["2"] = 15 })
    equal(stringKeys[2], 15, "string rank keys are read")

    local unknownRank = W.NormalizeEntry({ [2] = 5, [7] = 99 })
    equal(unknownRank[7], 99, "unknown numeric rank data survives normalization")
    equal(unknownRank[2], 5, "known rank still normalized")
    equal(unknownRank[3], 0, "missing rank defaults to zero without a default field")

    local invalidValues = W.NormalizeEntry({ [3] = "junk", [2] = 1.5, default = "-8" })
    equal(invalidValues[3], -8, "invalid rank value falls back to validated default")
    equal(invalidValues[2], -8, "decimal rank value falls back to validated default")

    equal(W.GetFromWeights(nil, "X", 3), 0, "nil weights table reads zero")
    equal(W.GetFromWeights({}, "X", 3), 0, "missing entry reads zero")
    equal(W.GetFromWeights({ X = 9 }, "X", 3), 9, "legacy scalar read")
    equal(W.GetFromWeights({ X = "9" }, "X", 0), 9, "legacy string scalar read")
    equal(W.GetFromWeights({ X = { [3] = 20 } }, "X", 3), 20, "rank-specific read")
    equal(W.GetFromWeights({ X = { ["3"] = 21 } }, "X", 3), 21, "string rank key read")
    equal(W.GetFromWeights({ X = { default = 5 } }, "X", 2), 5, "default fallback read")
    equal(W.GetFromWeights({ X = { [3] = 20, default = 5 } }, "X", nil), 5,
        "quality-less read prefers the default")
    equal(W.GetFromWeights({ X = { [1] = 3 } }, "X", nil), 3,
        "quality-less read falls back to the first defined rank in ORDER")

    check(not W.HasNonZero(nil), "nil entry has no value")
    check(not W.HasNonZero(0), "zero scalar has no value")
    check(not W.HasNonZero({ [3] = 0, [2] = 0, [1] = 0, [0] = 0 }), "all-zero table has no value")
    check(W.HasNonZero(-1), "negative scalar counts")
    check(W.HasNonZero({ [1] = 4 }), "single non-zero rank counts")
    check(W.HasNonZero("5"), "non-zero string scalar counts")
    check(not W.HasNonZero("0"), "zero string scalar has no value")

    local weights = { X = { [3] = 5, [2] = 40, [1] = -2, [0] = 0 } }
    equal(W.MaxFromWeights(weights, "X"), 40, "unfiltered max across ranks")
    equal(W.MaxFromWeights(weights, "X", { [1] = true, [0] = true }), 0,
        "max respects the available-quality filter")
    equal(W.MaxFromWeights(weights, "X", { [1] = true }), -2,
        "a single negative available rank is reported as-is")
    equal(W.MaxFromWeights(weights, "missing"), 0, "missing entry max is zero")
    equal(W.DescribeFromWeights(weights, "X", { [3] = true, [0] = true }),
        "Epic=5, Common=0", "describe follows intent-first order and the filter")
end

------------------------------------------------------------------------
-- Weights: reference-key normalization
------------------------------------------------------------------------
do
    local W = EbonBuilds.Weights
    local normalized = W.NormalizeRefWeights({
        ["g:12"] = { [3] = 9 },
        ["s:34"] = 4,
        ["not-a-ref"] = { [3] = 1 },
        [56] = { [3] = 1 },
    })
    equal(normalized["g:12"][3], 9, "group refKey survives")
    equal(normalized["s:34"][0], 4, "spell refKey scalar normalizes to all ranks")
    check(normalized["not-a-ref"] == nil, "malformed refKey dropped")
    check(normalized[56] == nil, "numeric key dropped")
end

------------------------------------------------------------------------
-- Scoring: quality and family modifiers
------------------------------------------------------------------------
do
    local S = EbonBuilds.Scoring
    local function Settings(overrides)
        local s = {
            qualityBonus = {}, qualityBonusMode = {},
            familyBonus = {}, familyBonusMode = {},
            banishFamilyWhitelist = {},
        }
        for key, value in pairs(overrides or {}) do s[key] = value end
        return s
    end
    local noFamily = { families = {} }

    equal(S.ScorePerQuality(noFamily, 10, Settings(), 3), 10, "no modifiers yields the raw weight")
    equal(S.ScorePerQuality(noFamily, nil, Settings(), 3), 0, "nil weight scores zero")

    equal(S.ScorePerQuality(noFamily, 10, Settings({ qualityBonus = { [3] = 25 } }), 3), 35,
        "additive quality bonus")
    equal(S.ScorePerQuality(noFamily, 10, Settings({
        qualityBonus = { [3] = 3 }, qualityBonusMode = { [3] = true },
    }), 3), 30, "multiplicative quality bonus adds base*(v-1)")
    equal(S.ScorePerQuality(noFamily, 10, Settings({
        qualityBonus = { [3] = 0 }, qualityBonusMode = { [3] = true },
    }), 3), 10, "multiplicative zero is treated as no-op, not annihilation")
    equal(S.ScorePerQuality(noFamily, -10, Settings({
        qualityBonus = { [3] = 2 }, qualityBonusMode = { [3] = true },
    }), 3), -20, "multiplicative bonus scales negative weights too")

    local casterEntry = { families = { "Caster DPS" } }
    equal(S.ScorePerQuality(casterEntry, 10, Settings({ familyBonus = { Caster = 6 } }), 0), 16,
        "family alias normalizes to its canonical id")
    local dualEntry = { families = { "Caster", "Melee" } }
    equal(S.ScorePerQuality(dualEntry, 10, Settings({
        familyBonus = { Caster = 6, Melee = 4 },
    }), 0), 20, "every matching family modifier stacks")
    equal(S.ScorePerQuality(dualEntry, 10, Settings({
        familyBonus = { Caster = 6, Melee = 4 },
        banishFamilyWhitelist = { Caster = true },
    }), 0), 16, "family whitelist restricts which bonuses apply")
    equal(S.ScorePerQuality(noFamily, 10, Settings({
        familyBonus = { ["No family"] = 5 },
    }), 0), 15, "family-less entries receive the No-family bonus")
    equal(S.ScorePerQuality(noFamily, 10, Settings({
        familyBonus = { ["No family"] = 5 },
        banishFamilyWhitelist = { Caster = true },
    }), 0), 10, "whitelist without No-family excludes family-less entries")

    equal(S.Score({ families = {}, quality = 3 }, 10, Settings({ noveltyValue = 7 })), 17,
        "novelty bonus is additive by default")
    equal(S.Score({ families = {}, quality = 3 }, 10,
        Settings({ noveltyValue = 2, noveltyMode = true })), 20,
        "multiplicative novelty adds base*(v-1)")
end

------------------------------------------------------------------------
-- EchoPolicy: pure policy resolution
------------------------------------------------------------------------
do
    local P = EbonBuilds.EchoPolicy

    check(P.IsValid(P.NORMAL) and P.IsValid(P.BANISH_ON_SIGHT) and P.IsValid(P.BANISH_AFTER_PICK)
        and P.IsValid(P.IGNORE_AFTER_PICK) and P.IsValid(P.NEVER_PICK), "all five policies validate")
    check(not P.IsValid("made_up"), "unknown policy is invalid")
    check(not P.IsValid(nil), "nil policy is invalid")
    equal(#P.ORDER, 5, "policy order lists exactly five policies")
    for _, policy in ipairs(P.ORDER) do
        check(P.DEFINITIONS[policy] ~= nil, "definition exists for " .. policy)
    end
    equal(P.Definition("garbage").label, "Normal", "unknown policy resolves the Normal definition")

    -- The full Resolve matrix: policy x selected-state.
    local matrix = {
        { P.NORMAL,            false, "normal" },
        { P.NORMAL,            true,  "normal" },
        { P.BANISH_ON_SIGHT,   false, "banish" },
        { P.BANISH_ON_SIGHT,   true,  "normal" },
        { P.BANISH_AFTER_PICK, false, "normal" },
        { P.BANISH_AFTER_PICK, true,  "banish" },
        { P.IGNORE_AFTER_PICK, false, "normal" },
        { P.IGNORE_AFTER_PICK, true,  "exclude" },
        { P.NEVER_PICK,        false, "exclude" },
        { P.NEVER_PICK,        true,  "exclude" },
    }
    for _, row in ipairs(matrix) do
        equal(P.Resolve(row[1], row[2]), row[3],
            string.format("Resolve(%s, selected=%s)", row[1], tostring(row[2])))
    end
    equal(P.Resolve("unknown", true), "normal", "unknown policy resolves as normal")

    check(P.IsBanishPolicy(P.BANISH_ON_SIGHT), "banish-on-sight is a banish policy")
    check(P.IsBanishPolicy(P.BANISH_AFTER_PICK), "banish-after-pick is a banish policy")
    check(not P.IsBanishPolicy(P.NEVER_PICK), "never-pick spends no banish")
    check(not P.IsBanishPolicy(P.IGNORE_AFTER_PICK), "ignore-after-pick spends no banish")

    -- SetRef writes only under validated canonical keys.
    local settings = { echoPolicies = {} }
    check(P.SetRef(settings, "g:42", P.NEVER_PICK), "canonical group ref accepted")
    equal(settings.echoPolicies["g:42"], P.NEVER_PICK, "policy stored under refKey")
    check(P.SetRef(settings, "s:9", P.BANISH_ON_SIGHT), "canonical spell ref accepted")
    check(not P.SetRef(settings, "42", P.NEVER_PICK), "bare number key rejected")
    check(not P.SetRef(settings, "g:", P.NEVER_PICK), "malformed ref rejected")
    check(not P.SetRef(settings, "x:42", P.NEVER_PICK), "unknown ref prefix rejected")
    check(not P.SetRef(nil, "g:42", P.NEVER_PICK), "nil settings rejected")
    check(P.SetRef(settings, "g:42", "bogus"), "invalid policy coerces to Normal")
    check(settings.echoPolicies["g:42"] == nil, "coerced Normal removes the stored entry")
    check(P.SetRef(settings, "s:9", P.NORMAL), "explicit Normal accepted")
    check(settings.echoPolicies["s:9"] == nil, "explicit Normal removes the stored entry")
    check(P.EnsureNeverPick(settings, "g:77"), "EnsureNeverPick stores the exclusion")
    equal(settings.echoPolicies["g:77"], P.NEVER_PICK, "EnsureNeverPick uses never_pick")

    -- CanonicalName never treats a storage refKey as a display name.
    equal(P.CanonicalName("g:296"), nil, "group storage key is not a display name")
    equal(P.CanonicalName("s:200246"), nil, "spell storage key is not a display name")
    equal(P.CanonicalName("Arcane Bond - Epic"), "Arcane Bond",
        "display names are rank-stripped")
    equal(P.CanonicalName("  Arcane Bond  "), "Arcane Bond", "display names are trimmed")
    equal(P.CanonicalName(""), nil, "empty name resolves to nil")
    equal(P.CanonicalName(777001), "Fallback Echo", "numeric spell resolves through Weights")

    equal(P.Get({ echoPolicies = { ["g:1"] = P.NEVER_PICK } }, "unresolvable name"), P.NORMAL,
        "unresolvable value reads Normal without erroring")
    equal(P.Get(nil, "anything"), P.NORMAL, "nil settings read Normal")

    local summary = P.Summary({ echoPolicies = {
        a = P.BANISH_ON_SIGHT, b = P.BANISH_ON_SIGHT, c = P.NEVER_PICK, d = "junk",
    } })
    equal(summary.total, 3, "summary counts only valid non-normal policies")
    equal(summary[P.BANISH_ON_SIGHT], 2, "summary counts per policy")
    equal(summary[P.NEVER_PICK], 1, "summary counts never-pick")
    equal(P.SummaryText({}), "No custom policies", "empty settings summarize as none")
    equal(P.SummaryText({ echoPolicies = { a = P.NEVER_PICK } }),
        "1 custom: 0 sight, 0 after, 0 ignore, 1 never", "summary text format is stable")

    equal(P.EffectText(P.NEVER_PICK, false),
        "Active: this Echo is excluded from automatic selection.", "never-pick effect text")
    equal(P.EffectText(P.BANISH_ON_SIGHT, true),
        "Inactive after selection: this Echo is treated normally.", "spent on-sight effect text")
end

if failures > 0 then
    io.stderr:write(string.format("%d pure-module test(s) failed.\n", failures))
    os.exit(1)
end
print("Pure-module coverage passed: Quality, Weights, Scoring, and EchoPolicy contracts.")
