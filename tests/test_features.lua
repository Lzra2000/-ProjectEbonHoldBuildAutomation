-- Standalone regression tests for rank-specific Echo weights, negative values,
-- whitelist persistence/protection, and export/import migration behavior.
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

EbonBuilds = {}
EbonBuildsDB = { builds = {} }
EbonBuildsCharDB = {}

local spellNames = {
    [100] = "Scorching Wounds",
    [101] = "Arcane Bond",
    [102] = "Protected Tank Echo",
    [103] = "Scorching Wounds",
    [104] = "Scorching Wounds",
    [105] = "Locked Warrior Echo",
    [110] = "Ranked Echo",
    [112] = "Ranked Echo",
    [200858] = "Class Variant Echo",
    [300858] = "Class Variant Echo",
}

ProjectEbonhold = {
    PerkDatabase = {
        [100] = { comment = "Scorching Wounds - Common", quality = 0, families = { "Caster" }, classMask = 128 },
        [101] = { comment = "Arcane Bond - Rare", quality = 2, families = { "Caster" }, classMask = 128 },
        [102] = { comment = "Protected Tank Echo - Uncommon", quality = 1, families = { "Tank" }, classMask = 128 },
        [103] = { comment = "Scorching Wounds - Uncommon", quality = 1, families = { "Caster" }, classMask = 128 },
        [104] = { comment = "Scorching Wounds - Rare", quality = 2, families = { "Caster" }, classMask = 128 },
        [105] = { comment = "Locked Warrior Echo - Common", quality = 0, families = { "Melee" }, classMask = 1 },
        [110] = { comment = "Ranked Echo - Common", quality = 0, families = { "Caster" }, classMask = 128 },
        [112] = { comment = "Ranked Echo - Rare", quality = 2, families = { "Caster" }, classMask = 128 },
        [200858] = { comment = "Class Variant Echo - Common", quality = 0, families = { "Caster" }, classMask = 0 },
        [300858] = { comment = "Class Variant Echo - Common", quality = 0, families = { "Caster" }, classMask = 128 },
    },
    PerkService = {
        SelectPerk = function(spellId) ProjectEbonhold._selected = spellId end,
        GetGrantedPerks = function() return {} end,
        GetCurrentChoice = function() return ProjectEbonhold._choices or {} end,
        BanishPerk = function(index)
            ProjectEbonhold._banished = index
            return true
        end,
        RequestReroll = function() return false end,
        FreezePerk = function() return false end,
    },
}

function GetSpellInfo(spellId) return spellNames[spellId] end
function UnitName() return "Tester" end
function UnitClass() return "Mage", "MAGE" end
function GetTalentTabInfo() return nil, nil, 0 end
function date() return "2026-07-17 12:00:00" end
function time() return 123456789 end
StaticPopupDialogs = {}
function StaticPopup_Show() end
bit = {
    band = function(a, b) return a & b end,
    bor = function(a, b) return a | b end,
}

EbonBuilds.DebugLog = {
    IsEnabled = function() return false end,
    Add = function() end,
    AddF = function() end,
}
EbonBuilds.Toast = { ShowAutomationResult = function() end, Show = function() end }
EbonBuilds.Session = { LogAction = function() end, GetActiveSession = function() return EbonBuilds.Session._activeSession end }

-- Load only the modules needed by these tests.
dofile("modules/data/Quality.lua")
dofile("modules/weights/Weights.lua")
dofile("modules/build/Build.lua")
dofile("modules/build/EchoPolicy.lua")
dofile("modules/build/Scoring.lua")
dofile("modules/build/ExportImport.lua")
dofile("modules/build/EWL.lua")
dofile("modules/automation/Calibration.lua")
dofile("modules/automation/EchoPerformance.lua")
dofile("modules/automation/Automation.lua")
dofile("modules/automation/ManualTraining.lua")

-- Scoring normally receives this data from the UI data module. Keep the test
-- fixture UI-free while still exercising every available quality rank.
-- Intent-first defaults apply only to newly created builds, while the legacy
-- default factory remains suitable for migrating existing saved builds.
do
    local qualityOrder = EbonBuilds.Quality.ORDER
    equal(#qualityOrder, 4, "only four supported Echo ranks are exposed")
    equal(qualityOrder[1], 3, "Epic is the first/left-most quality")
    equal(qualityOrder[2], 2, "Rare follows Epic")
    equal(qualityOrder[3], 1, "Uncommon follows Rare")
    equal(qualityOrder[4], 0, "Common is the right-most quality")
    equal(EbonBuilds.Quality.LABELS[4], nil, "unsupported rank 4 is not presented")

    local fresh = EbonBuilds.Build.NewBuildSettings()
    equal(fresh.rerollMode, "ev", "new builds start in Smart mode")
    equal(fresh.banishEVPct, 60, "new builds use Balanced banish intent")
    equal(fresh.rerollEVPct, 95, "new builds use Balanced reroll intent")
    equal(fresh.freezeEVPct, 110, "new builds use Balanced freeze intent")
    equal(fresh.freezePenaltyPct, 8, "new builds use the Balanced freeze penalty")

    local legacy = EbonBuilds.Build.DefaultSettings()
    equal(legacy.rerollMode, "sum", "legacy/default migration behavior remains Classic")
    check(type(legacy.echoPolicies) == "table", "default settings include conditional Echo policies")
end

EbonBuilds.EchoTableRows = {
    BuildSortedList = function()
        return {
            {
                spellId = 100,
                name = "Scorching Wounds",
                quality = 2,
                qualities = { [0] = true, [1] = true, [2] = true },
                spellIds = { [0] = 100, [1] = 103, [2] = 104 },
                families = { "Caster" },
                classMask = 128,
            },
        }
    end,
}


-- EWL export mirrors EchoWishlist catalog semantics: rank/class variants map to
-- one retained catalog spellId, saved rows use :1, and ordering follows the
-- EchoWishlist wishlist comparator instead of build slot or weight order.
do
    EchoWishlist = {
        catalog = {
            {
                id = 100, spellId = 100, name = "Scorching Wounds", quality = 2, classMask = 128,
                _variants = {
                    { id = 103, spellId = 103, name = "Scorching Wounds", quality = 1, classMask = 128 },
                    { id = 104, spellId = 104, name = "Scorching Wounds", quality = 2, classMask = 128 },
                },
            },
            { id = 101, spellId = 101, name = "Arcane Bond", quality = 2, classMask = 128 },
            { id = 102, spellId = 102, name = "Protected Tank Echo", quality = 1, classMask = 128 },
            { id = 105, spellId = 105, name = "Locked Warrior Echo", quality = 0, classMask = 1 },
            {
                id = 110, spellId = 110, name = "Ranked Echo", quality = 2, classMask = 128,
                _variants = {
                    { id = 112, spellId = 112, name = "Ranked Echo", quality = 2, classMask = 128 },
                },
            },
            {
                id = 300858, spellId = 300858, name = "Class Variant Echo", quality = 0, classMask = 128,
                _variants = {
                    { id = 200858, spellId = 200858, name = "Class Variant Echo", quality = 0, classMask = 0 },
                },
            },
        },
    }

    local build = EbonBuilds.Build.NewObject({
        title = "EWL fixture",
        class = "MAGE",
        lockedEchoes = { 104, 105 },
        echoWeights = {
            ["Scorching Wounds"] = { [0] = 10, [1] = 0, [2] = -5, [3] = 4 },
            ["Protected Tank Echo"] = { [1] = 7 },
            ["Ranked Echo"] = { [0] = 3, [2] = 8 },
            ["Class Variant Echo"] = { [0] = 6 },
            ["Arcane Bond"] = { [2] = 0 },
            ["Missing Echo"] = { [3] = 9 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local ewl, err, info = EbonBuilds.EWL.Generate(build)
    equal(err, nil, "EWL generation succeeds for a weighted build")
    equal(ewl, "EWL1:MAGE:100:1,105:1,110:0,102:0,300858:0",
        "EWL uses retained catalog IDs and EchoWishlist ordering")
    equal(info.catalogSource, "EchoWishlist", "installed EchoWishlist catalog is the source of truth")
    equal(info.total, 5, "EWL includes two saved and three weighted catalog rows")
    equal(info.locked, 2, "all configured locked families are marked saved")
    equal(info.normal, 3, "remaining weighted families use status 0")
    equal(#info.unresolved, 1, "an unmatched weighted family is reported once")
    equal(info.unresolved[1].name, "Missing Echo", "the unresolved family name is retained")
    check(not ewl:find("104:1", 1, true), "a locked rank alias resolves to the retained catalog ID")
    check(not ewl:find("112:0", 1, true), "the strongest rank ID is not substituted for the catalog ID")
    check(not ewl:find("200858:0", 1, true), "a class alias resolves to the retained catalog row")
    check(not ewl:find("101:0", 1, true), "an all-zero Echo is omitted")
end

-- Imported Project Ebonhold builds can contain hidden control-byte suffixes
-- in their internal Echo keys. EWL matching must use the safe player-facing
-- name and must never pass the raw key to the client's lowercasing helpers.
do
    EchoWishlist = {
        catalog = {
            { id = 120, spellId = 120, name = "Mind Expansion", quality = 2, classMask = 256 },
            { id = 121, spellId = 121, name = "Iron Constitution", quality = 1, classMask = 256 },
        },
    }

    local build = EbonBuilds.Build.NewObject({
        title = "Control-byte EWL regression",
        class = "WARLOCK",
        lockedEchoes = {},
        echoWeights = {
            ["Mind Expansion\0" .. "1"] = { [0] = 7 },
            ["Iron Constitution\0" .. "2"] = { [0] = 5 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
    })

    local realLower = string.lower
    string.lower = function(value)
        value = tostring(value or "")
        for index = 1, #value do
            local byte = value:byte(index)
            if byte and (byte < 32 or byte == 127) then
                error("unsafe control byte passed to string.lower")
            end
        end
        return realLower(value)
    end

    local ok, ewl, err, info = pcall(function()
        local generated, generationError, generationInfo = EbonBuilds.EWL.Generate(build)
        return generated, generationError, generationInfo
    end)
    string.lower = realLower

    check(ok, "EWL export never lowercases raw control-byte Echo keys")
    equal(err, nil, "control-byte EWL generation succeeds")
    equal(ewl, "EWL1:WARLOCK:120:0,121:0", "control-byte variants resolve through visible catalog names")
    equal(info and info.unresolved and #info.unresolved or -1, 0, "control-byte Echo keys are not reported as unresolved")
end

-- Regression for the reported Death Knight export. The build contained the
-- 200745 rank alias, but EchoWishlist retains 200744 for that family. Saved
-- rows are sorted by EWL metadata rather than locked-slot order.
do
    EchoWishlist = {
        catalog = {
            { id = 200960, spellId = 200960, name = "A", quality = 0, classMask = 32 },
            { id = 200844, spellId = 200844, name = "B", quality = 0, classMask = 32 },
            { id = 201254, spellId = 201254, name = "C", quality = 0, classMask = 32 },
            { id = 201356, spellId = 201356, name = "D", quality = 0, classMask = 32 },
            { id = 201324, spellId = 201324, name = "E", quality = 0, classMask = 32 },
            {
                id = 200744, spellId = 200744, name = "F", quality = 0, classMask = 32,
                _variants = {
                    { id = 200745, spellId = 200745, name = "F", quality = 1, classMask = 32 },
                },
            },
        },
    }

    local build = EbonBuilds.Build.NewObject({
        title = "Reported DK canonical regression",
        class = "DEATHKNIGHT",
        lockedEchoes = { 200960, 201254, 200844, 201356, 201324, 200745 },
        echoWeights = {},
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local ewl, err, info = EbonBuilds.EWL.Generate(build)
    equal(err, nil, "saved-only EWL generation succeeds")
    equal(ewl,
        "EWL1:DEATHKNIGHT:200960:1,200844:1,201254:1,201356:1,201324:1,200744:1",
        "saved variants resolve to canonical IDs and EWL ordering")
    equal(info.locked, 6, "all six reported saved families are counted")
    equal(info.normal, 0, "saved-only export has no status-0 entries")
end

-- Negative-value validation and malformed input.
do
    local value, err = EbonBuilds.Weights.Validate("-25")
    equal(value, -25, "negative whole numbers are accepted")
    equal(err, nil, "valid negative input has no error")
    check(EbonBuilds.Weights.Validate("") == nil, "empty input is rejected")
    check(EbonBuilds.Weights.Validate("1.5") == nil, "decimal input is rejected because legacy weights are integers")
    check(EbonBuilds.Weights.Validate("abc") == nil, "malformed input is rejected")
    check(EbonBuilds.Weights.Validate(EbonBuilds.Weights.MAX_VALUE + 1) == nil, "out-of-range positive input is rejected")
    check(EbonBuilds.Weights.Validate(EbonBuilds.Weights.MIN_VALUE - 1) == nil, "out-of-range negative input is rejected")
end

-- Runtime scoring reads the value that belongs to the offered quality.
do
    local build = EbonBuilds.Build.NewObject({
        title = "Rank scoring",
        class = "MAGE",
        echoWeights = {
            ["Scorching Wounds"] = { [0] = -10, [1] = 5, [2] = 30 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    EbonBuildsDB._isEditingBuild = nil

    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 100, quality = 0 }, build.settings).score, -10,
        "automation applies the Common value")
    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 103, quality = 1 }, build.settings).score, 5,
        "automation applies the Uncommon value")
    equal(EbonBuilds.Automation._ScoreChoice({ spellId = 104, quality = 2 }, build.settings).score, 30,
        "automation applies the Rare value")
end

-- Peak and outcome calculations evaluate each available rank independently.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    local rankWeights = { [0] = 50, [1] = 5, [2] = -10 }
    local name, peak = EbonBuilds.Scoring.ComputePeak("MAGE", settings, function(_, quality)
        return rankWeights[quality]
    end)
    equal(name, "Scorching Wounds", "peak identifies the rank-specific Echo")
    equal(peak, 50, "Common can define the peak even when Rare is the highest available quality")

    local stats = EbonBuilds.Scoring.ComputeOutcomeStats("MAGE", settings, function(_, quality)
        return rankWeights[quality]
    end)
    equal(stats.mean, 15, "outcome mean includes independent Common, Uncommon, and Rare values")
end

-- Explicit ban-list automation also yields to the per-Echo whitelist.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.autoBanishPct = 0
    settings.autoRerollPct = 0
    settings.autoFreezePct = 200
    settings.echoBanList[100] = "Scorching Wounds"
    settings.echoWhitelist["Scorching Wounds"] = true

    local build = EbonBuilds.Build.NewObject({
        title = "Explicit ban protection",
        class = "MAGE",
        echoWeights = {
            ["Scorching Wounds"] = { [0] = 100 },
            ["Arcane Bond"] = { [2] = 10 },
        },
        settings = settings,
        automationEnabled = true,
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    ProjectEbonhold._choices = {
        { spellId = 100, quality = 0 },
        { spellId = 101, quality = 2 },
    }
    EbonholdPlayerRunData = {
        remainingBanishes = 1,
        totalRerolls = 0, usedRerolls = 0,
        totalFreezes = 0, usedFreezes = 0,
    }
    EbonBuilds.Automation.GetPeak = function() return 100 end
    EbonBuilds.Automation._ResetFreezeRound()

    ProjectEbonhold._banished = nil
    ProjectEbonhold._selected = nil
    check(EbonBuilds.Automation.Evaluate(), "explicit-ban protected evaluation completes")
    equal(ProjectEbonhold._banished, nil, "whitelisted Echo is not explicitly banished")
    equal(ProjectEbonhold._selected, 100, "whitelisted Echo remains selectable")

    build.settings.echoWhitelist["Scorching Wounds"] = nil
    build.settings.echoBanList[100] = "Scorching Wounds"
    ProjectEbonhold._banished = nil
    ProjectEbonhold._selected = nil
    check(EbonBuilds.Automation.Evaluate(), "explicit-ban unprotected evaluation completes")
    equal(ProjectEbonhold._banished, 0, "explicit ban fires after whitelist removal")
end

-- Legacy single weights migrate without changing effective values.
do
    local migrated = EbonBuilds.Weights.NormalizeEntry(17)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER) do
        equal(migrated[quality], 17, "legacy weight copied to " .. EbonBuilds.Quality.LABELS[quality])
    end
end

-- Partial/malformed rank tables use the documented safe fallback behavior.
do
    local normalized = EbonBuilds.Weights.NormalizeEntry({ [0] = -8, [1] = "bad", default = 6 })
    equal(normalized[0], -8, "valid explicit rank survives normalization")
    equal(normalized[1], 6, "invalid rank uses valid default fallback")
    equal(normalized[3], 6, "missing rank uses valid default fallback")

    local noDefault = EbonBuilds.Weights.NormalizeEntry({ [2] = "bad" })
    equal(noDefault[2], 0, "invalid rank without a default falls back to zero")

    local hiddenLegacy = EbonBuilds.Weights.NormalizeEntry({ [0] = 1, [4] = 77 })
    equal(hiddenLegacy[4], 77, "unsupported numeric rank data is preserved without being presented")
end

-- Rank values are independent, negative-capable, and use the existing storage path.
do
    local storage = {}
    local originalGetActiveWeights = EbonBuilds.Build.GetActiveWeights
    EbonBuilds.Build.GetActiveWeights = function() return storage end
    check(EbonBuilds.Weights.Set("Scorching Wounds", -10, 0), "Common rank saves")
    check(EbonBuilds.Weights.Set("Scorching Wounds", 5, 1), "Uncommon rank saves")
    check(EbonBuilds.Weights.Set("Scorching Wounds", 30, 2), "Rare rank saves")
    equal(EbonBuilds.Weights.Get("Scorching Wounds", 0), -10, "Common remains independent")
    equal(EbonBuilds.Weights.Get("Scorching Wounds", 1), 5, "Uncommon remains independent")
    equal(EbonBuilds.Weights.Get("Scorching Wounds", 2), 30, "Rare remains independent")
    EbonBuilds.Build.GetActiveWeights = originalGetActiveWeights
end

-- Whitelist migration wins over ban-list conflicts and survives normalization.
do
    local build = {
        settings = {
            echoWhitelist = { ["Scorching Wounds"] = true },
            echoBanList = { [100] = "Scorching Wounds", [101] = "Arcane Bond" },
        },
        echoWeights = { ["Scorching Wounds"] = -4 },
    }
    EbonBuilds.Build.NormalizeData(build)
    check(build.settings.echoWhitelist["Scorching Wounds"], "whitelist state survives normalization")
    equal(build.settings.echoBanList[100], nil, "whitelisted echo is removed from conflicting ban list")
    check(build.settings.echoBanList[101] ~= nil, "unrelated banned echo is preserved")
    equal(build.echoWeights["Scorching Wounds"][0], -4, "legacy negative weight migrates")

    local repaired = {
        settings = {
            echoWhitelist = {
                [100] = true,
                ["Scorching Wounds - Rare"] = true,
                ["Arcane Bond"] = "false",
            },
            echoBanList = { ["101"] = "Arcane Bond" },
        },
    }
    EbonBuilds.Build.NormalizeData(repaired)
    check(repaired.settings.echoWhitelist["Scorching Wounds"], "numeric and suffix-bearing whitelist keys canonicalize")
    check(not repaired.settings.echoWhitelist["Arcane Bond"], "malformed false-like whitelist values do not enable protection")
    check(repaired.settings.echoBanList[101] ~= nil, "numeric-string ban-list keys canonicalize to numbers")
end

-- Scoring and automation treat an individual whitelist as absolute ban protection.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.echoWhitelist["Scorching Wounds"] = true
    settings.echoBanList[100] = "Scorching Wounds"
    settings.echoBanList[101] = "Arcane Bond"

    check(EbonBuilds.Scoring.IsWhitelisted(100, settings), "spellId resolves to whitelisted canonical name")
    check(EbonBuilds.Scoring.IsWhitelisted("100", settings), "numeric-string spellId resolves to whitelisted canonical name")
    check(not EbonBuilds.Scoring.IsBanned(100, settings), "whitelist overrides direct ban-list membership")
    check(EbonBuilds.Scoring.IsBanned(101, settings), "non-whitelisted ban remains active")
    settings.echoBanList[101] = nil
    settings.echoBanList["101"] = "Arcane Bond"
    check(EbonBuilds.Scoring.IsBanned(101, settings), "legacy string spell-id ban keys remain effective")

    local scored = {
        { spellId = 100, data = ProjectEbonhold.PerkDatabase[100], score = 20, index = 1 },
        { spellId = 101, data = ProjectEbonhold.PerkDatabase[101], score = 10, index = 2 },
    }
    EbonBuilds.Automation._AnnotateScored(scored, settings, {})
    check(scored[1].isWhitelisted and scored[1].isProtected and not scored[1].isBanned,
        "automation annotation protects whitelisted entries")

    ProjectEbonhold._selected = nil
    local selected = EbonBuilds.Automation._TrySelect(scored, settings, { stats = {} })
    check(selected, "selection succeeds")
    equal(ProjectEbonhold._selected, 100, "whitelisted banned entry is not filtered from selection")
end

-- End-to-end automatic banishing skips a whitelisted negative-score Echo.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.autoBanishPct = 50
    settings.autoRerollPct = 0
    settings.autoFreezePct = 200
    settings.echoWhitelist["Scorching Wounds"] = true

    local build = EbonBuilds.Build.NewObject({
        title = "Automation protection",
        class = "MAGE",
        echoWeights = {
            ["Scorching Wounds"] = { [0] = -100 },
            ["Arcane Bond"] = { [2] = 100 },
        },
        settings = settings,
        automationEnabled = true,
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    EbonBuildsDB._isEditingBuild = nil
    ProjectEbonhold._choices = {
        { spellId = 100, quality = 0 },
        { spellId = 101, quality = 2 },
    }
    EbonholdPlayerRunData = {
        remainingBanishes = 1,
        totalRerolls = 0, usedRerolls = 0,
        totalFreezes = 0, usedFreezes = 0,
    }
    EbonBuilds.Automation.GetPeak = function() return 100 end

    ProjectEbonhold._banished = nil
    ProjectEbonhold._selected = nil
    check(EbonBuilds.Automation.Evaluate(), "automation completes with a whitelisted low score")
    equal(ProjectEbonhold._banished, nil, "automatic threshold banish skips whitelisted Echo")
    equal(ProjectEbonhold._selected, 101, "automation continues to normal selection")

    build.settings.echoWhitelist["Scorching Wounds"] = nil
    ProjectEbonhold._banished = nil
    ProjectEbonhold._selected = nil
    check(EbonBuilds.Automation.Evaluate(), "automation evaluates the unprotected case")
    equal(ProjectEbonhold._banished, 0, "same low-score Echo is banished once whitelist is disabled")
end

-- Family protection remains intact alongside the new per-entry whitelist.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.banishFamilyWhitelist.Tank = true
    local scored = { { spellId = 102, data = ProjectEbonhold.PerkDatabase[102], score = 1, index = 1 } }
    EbonBuilds.Automation._AnnotateScored(scored, settings, {})
    check(scored[1].isProtected, "existing family whitelist behavior is preserved")
end

-- Conditional Echo policy resolution is deterministic and canonicalized.
do
    local P = EbonBuilds.EchoPolicy
    equal(P.Resolve(P.NORMAL, false), "normal", "Normal policy uses standard rules")
    equal(P.Resolve(P.BANISH_ON_SIGHT, false), "banish", "Banish on Sight activates before first selection")
    equal(P.Resolve(P.BANISH_ON_SIGHT, true), "normal", "Banish on Sight deactivates after first selection")
    equal(P.Resolve(P.BANISH_AFTER_PICK, false), "normal", "Banish After Pick waits for first selection")
    equal(P.Resolve(P.BANISH_AFTER_PICK, true), "banish", "Banish After Pick activates after selection")
    equal(P.Resolve(P.IGNORE_AFTER_PICK, true), "exclude", "Ignore After Pick excludes selected Echoes")
    equal(P.Resolve(P.NEVER_PICK, false), "exclude", "Never Pick is always a hard exclusion")

    local settings = EbonBuilds.Build.DefaultSettings()
    settings.echoWhitelist["Scorching Wounds"] = true
    settings.echoPolicies["Scorching Wounds - Common"] = P.BANISH_ON_SIGHT
    local build = { settings = settings, echoWeights = {} }
    EbonBuilds.Build.NormalizeData(build)
    equal(P.Get(build.settings, "Scorching Wounds"), P.BANISH_ON_SIGHT, "policy keys canonicalize across quality suffixes")
    check(not build.settings.echoWhitelist["Scorching Wounds"], "specific banish policy clears conflicting explicit protection")
end

-- Current-run selection state is recovered from both session logs and granted perks.
do
    ProjectEbonhold.PerkService.GetGrantedPerks = function() return { ["Arcane Bond"] = 1 } end
    EbonBuilds.Session._activeSession = {
        logs = {
            { action = "Select", targetIndex = 1, choices = { { index = 1, spellId = 100 } } },
        },
    }
    local selected = EbonBuilds.EchoPolicy.SelectedNames()
    check(selected["Scorching Wounds"], "selected Echo is recovered from the active Logbook session")
    check(selected["Arcane Bond"], "selected Echo is recovered from granted-perk state")
    EbonBuilds.Session._activeSession = nil
    ProjectEbonhold.PerkService.GetGrantedPerks = function() return {} end
end

-- Hard exclusion policies are never violated by the selection fallback.
do
    local P = EbonBuilds.EchoPolicy
    local settings = EbonBuilds.Build.DefaultSettings()
    P.Set(settings, "Scorching Wounds", P.NEVER_PICK)
    local scored = {
        { spellId = 100, data = ProjectEbonhold.PerkDatabase[100], score = 100, index = 1 },
        { spellId = 101, data = ProjectEbonhold.PerkDatabase[101], score = 10, index = 2 },
    }
    EbonBuilds.Automation._AnnotateScored(scored, settings, {}, {})
    check(scored[1].policyBlocked and scored[1].policyEffect == "exclude", "Never Pick annotates the offer as blocked")
    ProjectEbonhold._selected = nil
    local ok = EbonBuilds.Automation._TrySelect(scored, settings, { stats = {} })
    check(ok, "selection still succeeds when another eligible Echo exists")
    equal(ProjectEbonhold._selected, 101, "Never Pick prevents selecting the higher-scoring blocked Echo")

    P.Set(settings, "Arcane Bond", P.NEVER_PICK)
    EbonBuilds.Automation._AnnotateScored(scored, settings, {}, {})
    ProjectEbonhold._selected = nil
    local blocked, _, reason = EbonBuilds.Automation._TrySelect(scored, settings, { stats = {} })
    check(not blocked and reason == "policy_blocked", "all policy-blocked offers pause instead of violating the build")
    equal(ProjectEbonhold._selected, nil, "no blocked Echo is selected as a fallback")
end

-- Mandatory policy banishes precede score thresholds and selection.
do
    local P = EbonBuilds.EchoPolicy
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.autoBanishPct = 0
    settings.autoRerollPct = 0
    settings.autoFreezePct = 200
    P.Set(settings, "Scorching Wounds", P.BANISH_ON_SIGHT)
    local build = EbonBuilds.Build.NewObject({
        title = "Policy automation", class = "MAGE",
        echoWeights = { ["Scorching Wounds"] = { [0] = 100 }, ["Arcane Bond"] = { [2] = 10 } },
        settings = settings, automationEnabled = true,
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    ProjectEbonhold._choices = { { spellId = 100, quality = 0 }, { spellId = 101, quality = 2 } }
    EbonholdPlayerRunData = { remainingBanishes = 1, totalRerolls = 0, usedRerolls = 0, totalFreezes = 0, usedFreezes = 0 }
    ProjectEbonhold._banished = nil
    ProjectEbonhold._selected = nil
    check(EbonBuilds.Automation.Evaluate(), "Banish on Sight performs a mandatory policy action")
    equal(ProjectEbonhold._banished, 0, "policy target is banished even though it has the highest score")
    equal(ProjectEbonhold._selected, nil, "policy banish happens before selection")

    build.settings.echoPolicies = {}
    P.Set(build.settings, "Scorching Wounds", P.BANISH_AFTER_PICK)
    ProjectEbonhold.PerkService.GetGrantedPerks = function() return { ["Scorching Wounds"] = 1 } end
    ProjectEbonhold._banished = nil
    check(EbonBuilds.Automation.Evaluate(), "Banish After Pick activates from current-run selection state")
    equal(ProjectEbonhold._banished, 0, "Banish After Pick targets the previously selected Echo")
    ProjectEbonhold.PerkService.GetGrantedPerks = function() return {} end
end

-- Export/import round-trip preserves negative and rank-specific values plus whitelist state.
do
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.echoWhitelist["Scorching Wounds"] = true
    EbonBuilds.EchoPolicy.Set(settings, "Arcane Bond", EbonBuilds.EchoPolicy.IGNORE_AFTER_PICK)
    local build = EbonBuilds.Build.NewObject({
        title = "Round Trip",
        class = "MAGE",
        echoWeights = {
            ["Scorching Wounds"] = { [0] = -10, [1] = 5, [2] = 30, [3] = 0 },
        },
        settings = settings,
    })
    local encoded = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(encoded)
    check(decoded ~= nil, "exported build decodes")
    equal(decoded.echoWeights["Scorching Wounds"][0], -10, "negative Common value survives export/import")
    equal(decoded.echoWeights["Scorching Wounds"][1], 5, "Uncommon value survives export/import")
    equal(decoded.echoWeights["Scorching Wounds"][2], 30, "Rare value survives export/import")
    check(decoded.settings.echoWhitelist["Scorching Wounds"], "whitelist survives export/import")
    equal(EbonBuilds.EchoPolicy.Get(decoded.settings, "Arcane Bond"), EbonBuilds.EchoPolicy.IGNORE_AFTER_PICK, "conditional policy survives export/import")
end


-- Manual Training records and suggests the exact offered rank.
do
    local build = EbonBuilds.Build.NewObject({
        title = "Training rank test",
        class = "MAGE",
        echoWeights = {
            ["Scorching Wounds"] = { [0] = 0, [1] = 5, [2] = 10 },
            ["Arcane Bond"] = { [2] = 20 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
        manualTrainingEnabled = true,
    })
    EbonBuildsDB.builds[build.id] = build
    EbonBuildsCharDB.activeBuildId = build.id
    EbonBuildsCharDB.manualTraining = nil
    ProjectEbonhold._choices = {
        { spellId = 100, quality = 0 },
        { spellId = 101, quality = 2 },
    }
    for _ = 1, 3 do EbonBuilds.ManualTraining._OnPlayerSelect(100) end
    local suggestions = EbonBuilds.ManualTraining.SuggestWeightAdjustments(build)
    local byKey = {}
    for _, suggestion in ipairs(suggestions) do
        byKey[suggestion.name .. ":" .. tostring(suggestion.quality)] = suggestion
    end
    local raise = byKey["Scorching Wounds:0"]
    local lower = byKey["Arcane Bond:2"]
    check(raise ~= nil, "manual training suggests the picked Common rank")
    equal(raise and raise.suggestedWeight, 10, "manual training raises only Common by one nudge")
    check(lower ~= nil, "manual training identifies the passed-over Rare rank")
    equal(lower and lower.suggestedWeight, 10, "manual training lowers only Rare by one nudge")
    equal(EbonBuilds.ManualTraining.GetSampleCount(build.id), 3, "manual training sample count persists")

    EbonBuildsCharDB.manualTraining[build.id] = {
        preferredOverHigher = { ["Scorching Wounds"] = 3 },
        passedOverForLower = {},
        totalSelects = 3,
    }
    local legacy = EbonBuilds.ManualTraining.SuggestWeightAdjustments(build)
    check(legacy[1] and legacy[1].quality == nil and legacy[1].applyAllRanks,
        "legacy family-level training data remains readable as an all-ranks suggestion")
end

-- Appearance tracking combines personal and class-matched community data.
do
    EbonBuilds.Calibration.ClearAppearance()
    EbonBuilds.Calibration.RecordEvaluation()
    EbonBuilds.Calibration.RecordEvaluation()
    EbonBuilds.Calibration.RecordAppearance("Scorching Wounds")
    local personal = EbonBuilds.Calibration.GetAppearanceStats("Scorching Wounds")
    equal(math.floor((personal and personal.pct or 0) + 0.5), 50, "personal appearance rate is calculated")

    EbonBuilds.Calibration.SetAppearanceSharingEnabled(true)
    EbonBuilds.Calibration.MergeAppearanceContribution("Peer", "MAGE", 2, { ["Scorching Wounds"] = 2 })
    local combined = EbonBuilds.Calibration.GetAppearanceStats("Scorching Wounds")
    equal(math.floor((combined and combined.pct or 0) + 0.5), 75, "community appearance data merges by class")

    local payload = EbonBuilds.Calibration.SerializeAppearanceBatch("MAGE", { "Scorching Wounds" })
    local class, evals, counts = EbonBuilds.Calibration.ParseAppearanceBatch(payload)
    equal(class, "MAGE", "appearance payload preserves class")
    equal(evals, 2, "appearance payload preserves evaluation count")
    equal(counts["Scorching Wounds"], 1, "appearance payload preserves Echo count")
end

-- Offer appearance remains available while Autopilot yields to Manual Training,
-- and duplicate ranks of the same Echo count once per evaluation.
do
    local build = EbonBuilds.Build.GetActive()
    build.automationEnabled = false
    build.manualTrainingEnabled = true
    ProjectEbonhold._choices = {
        { spellId = 100, quality = 0 },
        { spellId = 103, quality = 1 },
        { spellId = 101, quality = 2 },
    }
    EbonBuilds.Calibration.ClearAppearance()
    check(not EbonBuilds.Automation.Evaluate(), "Manual Training yields to the native picker")
    local scorching = EbonBuilds.Calibration.GetAppearanceStats("Scorching Wounds")
    local arcane = EbonBuilds.Calibration.GetAppearanceStats("Arcane Bond")
    equal(scorching and scorching.totalEvals, 1, "manual offer records one evaluation")
    equal(math.floor((scorching and scorching.pct or 0) + 0.5), 100,
        "duplicate ranks of one Echo count once in an evaluation")
    equal(math.floor((arcane and arcane.pct or 0) + 0.5), 100,
        "other offered Echoes are recorded while Autopilot is off")
    build.manualTrainingEnabled = false
end

-- DPS suggestions remain family-level and never assume a scalar weight.
do
    local originalCatalog = EbonBuilds.EchoTableRows.BuildBestByName
    EbonBuilds.EchoTableRows.BuildBestByName = function()
        return {
            ["Scorching Wounds"] = { quality = 2, qualities = { [0] = true, [1] = true, [2] = true }, classMask = 128 },
            ["Arcane Bond"] = { quality = 2, qualities = { [2] = true }, classMask = 128 },
        }
    end
    local build = EbonBuilds.Build.GetActive()
    build.echoWeights = {
        ["Scorching Wounds"] = { [0] = 0, [1] = 5, [2] = 10 },
        ["Arcane Bond"] = { [2] = 10 },
    }
    EbonBuildsCharDB.echoPerformance = {
        ["Scorching Wounds"] = { sum = 1000, count = 10 },
        ["Arcane Bond"] = { sum = 2400, count = 12 },
    }
    EbonBuildsCharDB.echoPerformanceCommunity = {}
    local suggestions = EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
    check(#suggestions > 0, "DPS data can produce suggestions with rank tables")
    check(suggestions[1].applyAllRanks == true and suggestions[1].quality == nil,
        "DPS suggestions are explicitly family-level")
    EbonBuilds.EchoTableRows.BuildBestByName = originalCatalog
end

-- Auto-apply combines family and rank-specific deltas without scalarizing.
do
    local build = EbonBuilds.Build.GetActive()
    build.echoWeights = {
        ["Scorching Wounds"] = { [0] = 0, [1] = 5, [2] = 20 },
    }
    EbonBuildsCharDB.calibration = {
        autoTuneEnabled = true,
        autoApplyWeights = true,
        samplesSinceLastTune = 19,
        samples = {},
        bestSamples = {},
    }
    local insufficient = function() return { insufficientData = true, sampleCount = 0 } end
    local oldB, oldR, oldF = EbonBuilds.Calibration.SuggestBanish, EbonBuilds.Calibration.SuggestReroll, EbonBuilds.Calibration.SuggestFreeze
    local oldSB, oldSR, oldSF = EbonBuilds.Calibration.SuggestSmartBanish, EbonBuilds.Calibration.SuggestSmartReroll, EbonBuilds.Calibration.SuggestSmartFreeze
    EbonBuilds.Calibration.SuggestBanish = insufficient
    EbonBuilds.Calibration.SuggestReroll = insufficient
    EbonBuilds.Calibration.SuggestFreeze = insufficient
    EbonBuilds.Calibration.SuggestSmartBanish = insufficient
    EbonBuilds.Calibration.SuggestSmartReroll = insufficient
    EbonBuilds.Calibration.SuggestSmartFreeze = insufficient

    local oldPerfEnabled = EbonBuilds.EchoPerformance.IsEnabled
    local oldPerfSuggest = EbonBuilds.EchoPerformance.SuggestWeightAdjustments
    local oldTrainSuggest = EbonBuilds.ManualTraining.SuggestWeightAdjustments
    EbonBuilds.EchoPerformance.IsEnabled = function() return true end
    EbonBuilds.EchoPerformance.SuggestWeightAdjustments = function()
        return { { name = "Scorching Wounds", applyAllRanks = true, qualities = { [0] = true, [1] = true, [2] = true }, delta = 10, currentWeight = 20, suggestedWeight = 30 } }
    end
    EbonBuilds.ManualTraining.SuggestWeightAdjustments = function()
        return { { name = "Scorching Wounds", quality = 2, delta = -10, currentWeight = 20, suggestedWeight = 10 } }
    end

    EbonBuilds.Calibration.MaybeAutoTune()
    check(type(build.echoWeights["Scorching Wounds"]) == "table", "auto-apply preserves the rank table")
    equal(EbonBuilds.Weights.GetFromWeights(build.echoWeights, "Scorching Wounds", 0), 10,
        "family-level delta applies to Common")
    equal(EbonBuilds.Weights.GetFromWeights(build.echoWeights, "Scorching Wounds", 1), 15,
        "family-level delta applies to Uncommon")
    equal(EbonBuilds.Weights.GetFromWeights(build.echoWeights, "Scorching Wounds", 2), 20,
        "opposing Rare deltas cancel before saving")

    EbonBuilds.Calibration.SuggestBanish, EbonBuilds.Calibration.SuggestReroll, EbonBuilds.Calibration.SuggestFreeze = oldB, oldR, oldF
    EbonBuilds.Calibration.SuggestSmartBanish, EbonBuilds.Calibration.SuggestSmartReroll, EbonBuilds.Calibration.SuggestSmartFreeze = oldSB, oldSR, oldSF
    EbonBuilds.EchoPerformance.IsEnabled = oldPerfEnabled
    EbonBuilds.EchoPerformance.SuggestWeightAdjustments = oldPerfSuggest
    EbonBuilds.ManualTraining.SuggestWeightAdjustments = oldTrainSuggest
end

-- Quality and Family Bonus suggestions compare DPS-per-final-score-point
-- across tiers, and Family Bonus must exclude multi-family Echoes rather
-- than guess at how to split a stacked modifier between them.
do
    local originalCatalog = EbonBuilds.EchoTableRows.BuildBestByName
    EbonBuilds.EchoTableRows.BuildBestByName = function()
        local t = {}
        for i = 1, 5 do t["Tank" .. i] = { quality = 2, families = { "Tank" }, classMask = 128, spellId = 9000 + i } end
        for i = 1, 5 do t["Caster" .. i] = { quality = 2, families = { "Caster DPS" }, classMask = 128, spellId = 9100 + i } end
        for i = 1, 5 do t["Multi" .. i] = { quality = 2, families = { "Tank", "Caster DPS" }, classMask = 128, spellId = 9200 + i } end
        return t
    end

    local build = EbonBuilds.Build.GetActive()
    build.class = "MAGE"
    build.settings.familyBonus = { Tank = 0, Caster = 10 }
    build.settings.familyBonusMode = {}
    build.settings.qualityBonus = build.settings.qualityBonus or {}
    build.settings.qualityBonusMode = build.settings.qualityBonusMode or {}
    build.echoWeights = {}
    for i = 1, 5 do build.echoWeights["Tank" .. i] = 100 end
    for i = 1, 5 do build.echoWeights["Caster" .. i] = 100 end
    for i = 1, 5 do build.echoWeights["Multi" .. i] = 100 end

    EbonBuilds.EchoPerformance.Clear()
    EbonBuildsCharDB.echoPerformance = {}
    for i = 1, 5 do EbonBuildsCharDB.echoPerformance["Tank" .. i] = { sum = (2000 + i * 5) * 10, count = 10 } end
    for i = 1, 5 do EbonBuildsCharDB.echoPerformance["Caster" .. i] = { sum = (1000 + i * 5) * 10, count = 10 } end
    for i = 1, 5 do EbonBuildsCharDB.echoPerformance["Multi" .. i] = { sum = (5000 + i * 5) * 10, count = 10 } end
    EbonBuildsCharDB.echoPerformanceCommunity = {}

    local familySuggestions = EbonBuilds.EchoPerformance.SuggestFamilyBonusAdjustment(build)
    check(#familySuggestions == 2, "Family Bonus flags exactly the two pure-family tiers")
    local byFamily = {}
    for _, s in ipairs(familySuggestions) do byFamily[s.family] = s end
    check(byFamily.Tank and byFamily.Tank.suggestedBonus > byFamily.Tank.currentBonus,
        "higher-value pure-Tank tier is suggested upward")
    check(byFamily.Caster and byFamily.Caster.suggestedBonus < byFamily.Caster.currentBonus,
        "lower-value pure-Caster tier is suggested downward")

    -- SuggestQualityBonusAdjustment had no test at all before this, and was
    -- missing its final `return suggestions` -- every real call (once
    -- enough tracked samples exist to pass the earlier guard clauses) threw
    -- "attempt to get length of a nil value" at the call site instead of
    -- returning results. Reuses the family fixture but spreads quality
    -- tiers instead of families so real per-tier suggestions get generated.
    EbonBuilds.EchoTableRows.BuildBestByName = function()
        local t = {}
        for i = 1, 5 do t["Rare" .. i] = { quality = 2, families = { "Tank" }, classMask = 128, spellId = 9300 + i } end
        for i = 1, 5 do t["Uncommon" .. i] = { quality = 1, families = { "Tank" }, classMask = 128, spellId = 9400 + i } end
        return t
    end
    build.echoWeights = {}
    for i = 1, 5 do build.echoWeights["Rare" .. i] = 100 end
    for i = 1, 5 do build.echoWeights["Uncommon" .. i] = 100 end
    EbonBuilds.EchoPerformance.Clear()
    EbonBuildsCharDB.echoPerformance = {}
    for i = 1, 5 do EbonBuildsCharDB.echoPerformance["Rare" .. i] = { sum = (2000 + i * 5) * 10, count = 10 } end
    for i = 1, 5 do EbonBuildsCharDB.echoPerformance["Uncommon" .. i] = { sum = (1000 + i * 5) * 10, count = 10 } end
    EbonBuildsCharDB.echoPerformanceCommunity = {}

    local okQuality, qualitySuggestions = pcall(EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment, build)
    check(okQuality, "SuggestQualityBonusAdjustment does not error: " .. tostring(qualitySuggestions))
    check(okQuality and type(qualitySuggestions) == "table", "SuggestQualityBonusAdjustment returns a table, not nil")
    check(okQuality and #qualitySuggestions == 2, "Quality Bonus flags exactly the two quality tiers")

    EbonBuilds.EchoTableRows.BuildBestByName = originalCatalog
end

-- Theme.CreateCheckbox must match UICheckButtonTemplate's click contract:
-- an OnClick handler set by a call site reads the NEW state, because the
-- toggle happens in PreClick (which fires first). Getting this wrong would
-- silently invert every converted checkbox in the addon.
do
    local function NewWidgetStub()
        local scripts = {}
        local stub
        stub = setmetatable({
            SetScript = function(self, name, fn) scripts[name] = fn end,
            GetScript = function(self, name) return scripts[name] end,
            HookScript = function(self, name, fn)
                local prev = scripts[name]
                scripts[name] = function(...)
                    if prev then prev(...) end
                    fn(...)
                end
            end,
            Click = function(self)
                if scripts.PreClick then scripts.PreClick(self) end
                if scripts.OnClick then scripts.OnClick(self) end
                if scripts.PostClick then scripts.PostClick(self) end
            end,
            CreateTexture = function() return NewWidgetStub() end,
            CreateFontString = function() return NewWidgetStub() end,
        }, { __index = function() return function() return 0 end end })
        return stub
    end

    local originalCreateFrame = CreateFrame
    CreateFrame = function() return NewWidgetStub() end
    if not EbonBuilds.Theme then
        dofile("modules/ui/Theme.lua")
    end

    local cb = EbonBuilds.Theme.CreateCheckbox(NewWidgetStub(), "contract test")
    local observedOnClick = "never ran"
    cb:SetScript("OnClick", function(self)
        observedOnClick = self:GetChecked() and "checked" or "unchecked"
    end)

    check(cb:GetChecked() == nil, "themed checkbox starts unchecked (nil, matching native GetChecked)")
    cb:Click()
    equal(observedOnClick, "checked", "call-site OnClick observes the NEW state after first click")
    check(cb:GetChecked() == 1, "checked state reads as 1, matching native GetChecked truthiness")
    cb:Click()
    equal(observedOnClick, "unchecked", "call-site OnClick observes the NEW state after second click")
    cb:SetChecked(true)
    check(cb:GetChecked() == 1, "SetChecked(true) works without a click")
    cb:SetChecked(false)
    check(cb:GetChecked() == nil, "SetChecked(false) works without a click")

    CreateFrame = originalCreateFrame
end

-- "AI report" button (modules/ui/BuildTabs.lua -> ExportImport.lua): one
-- test per layer, so a future regression here is pinpointed by which layer
-- fails instead of "the button does nothing" with no further clue.
do
    -- Layer 1: content/logic (ExportImport.GenerateAIText) -- no UI at all.
    local build = EbonBuilds.Build.Create({
        title = "AI Report Test",
        class = "MAGE",
        spec = 1,
        echoWeights = { ["Scorching Wounds"] = { [0] = 5 } },
        settings = EbonBuilds.Build.NewBuildSettings(),
    })

    local okPlain, textPlain = pcall(EbonBuilds.ExportImport.GenerateAIText, build)
    check(okPlain, "GenerateAIText does not error for a plain build")
    check(okPlain and type(textPlain) == "string" and #textPlain > 0,
        "GenerateAIText returns non-empty text for a plain build")
    check(okPlain and not textPlain:find("Conditional Echo policies", 1, true),
        "GenerateAIText omits the policy section when no policy is set")

    EbonBuilds.EchoPolicy.Set(build.settings, "Scorching Wounds", EbonBuilds.EchoPolicy.BANISH_ON_SIGHT)
    local okPolicy, textPolicy = pcall(EbonBuilds.ExportImport.GenerateAIText, build)
    check(okPolicy, "GenerateAIText does not error once an Echo policy is set")
    check(okPolicy and textPolicy:find("Conditional Echo policies", 1, true) ~= nil,
        "GenerateAIText includes the policy section once a policy is set")
    check(okPolicy and textPolicy:find("Scorching Wounds", 1, true) ~= nil,
        "GenerateAIText's policy section names the affected Echo")

    local okNilBuild, textNilBuild = pcall(EbonBuilds.ExportImport.GenerateAIText, nil)
    check(okNilBuild and textNilBuild == "", "GenerateAIText(nil) is a safe no-op, not an error")

    -- Layer 2: dialog assembly (ExportImport.ShowAIExportDialog) -- exercises
    -- the same CreateFrame/EditBox path a real click reaches, using the
    -- lenient test_load-style stub since only "does it error" matters here.
    local function NewLooseStub()
        local stub
        stub = setmetatable({
            SetScript = function() end,
            HookScript = function() end,
            CreateFontString = function() return NewLooseStub() end,
            CreateTexture = function() return NewLooseStub() end,
        }, { __index = function(_, key)
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            return function() return NewLooseStub() end
        end })
        return stub
    end
    local originalCreateFrame1 = CreateFrame
    CreateFrame = function() return NewLooseStub() end
    if not EbonBuilds.Theme then dofile("modules/ui/Theme.lua") end
    local okDialog, dialogErr = pcall(EbonBuilds.ExportImport.ShowAIExportDialog, build)
    CreateFrame = originalCreateFrame1
    check(okDialog, "ShowAIExportDialog does not error: " .. tostring(dialogErr))

    -- Layer 3: click-handler logic (BuildTabs._TriggerExportAI) -- calls the
    -- exact function the button's OnClick invokes, without needing a real
    -- clickable widget, and verifies it resolves the right build.
    if not EbonBuilds.BuildTabs then dofile("modules/ui/BuildTabs.lua") end
    local capturedBuild = "not called"
    local originalShowAI = EbonBuilds.ExportImport.ShowAIExportDialog
    EbonBuilds.ExportImport.ShowAIExportDialog = function(b) capturedBuild = b end

    EbonBuilds.BuildTabs._SetContextForTest({ mode = "edit", build = build })
    EbonBuilds.BuildTabs._TriggerExportAI()
    check(capturedBuild == build, "click handler uses state.context.build when editing that build")

    capturedBuild = "not called"
    EbonBuilds.BuildTabs._SetContextForTest(nil)
    EbonBuilds.Build.SetActive(build.id)
    EbonBuilds.BuildTabs._TriggerExportAI()
    check(capturedBuild == build, "click handler falls back to the active build with no edit context")

    capturedBuild = "not called"
    EbonBuilds.Build.SetActive(nil)
    local okNoBuild = pcall(EbonBuilds.BuildTabs._TriggerExportAI)
    check(okNoBuild, "click handler does not error with no context and no active build")
    check(capturedBuild == "not called", "click handler is a silent no-op with no build available (by design)")

    EbonBuilds.ExportImport.ShowAIExportDialog = originalShowAI

    -- Layer 4: widget wiring (Theme.CreateButton + ClickTrace) -- the layer
    -- Click Trace itself exists to diagnose: does a real click even reach
    -- the handler Theme.CreateButton wires up, alongside its own
    -- HookScript-based click logger, without one silently swallowing the
    -- other.
    local function NewClickableStub()
        local hooks = {}
        local handlers = {}
        local stub
        stub = setmetatable({
            SetScript = function(self, name, fn) handlers[name] = fn end,
            GetScript = function(self, name) return handlers[name] end,
            -- Real WoW HookScript handlers survive later SetScript calls on
            -- the same event -- that guarantee is exactly what lets
            -- Theme.CreateButton's ClickTrace hook keep observing clicks
            -- after a caller (e.g. BuildTabs.lua) sets its own OnClick.
            HookScript = function(self, name, fn)
                hooks[name] = hooks[name] or {}
                hooks[name][#hooks[name] + 1] = fn
            end,
            Click = function(self)
                if handlers.OnClick then handlers.OnClick(self) end
                if hooks.OnClick then
                    for _, fn in ipairs(hooks.OnClick) do fn(self) end
                end
            end,
            GetText = function() return "AI report" end,
            SetText = function() end,
            CreateFontString = function() return NewClickableStub() end,
            CreateTexture = function() return NewClickableStub() end,
        }, { __index = function(_, key)
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            return function() return NewClickableStub() end
        end })
        return stub
    end
    local originalCreateFrame2 = CreateFrame
    CreateFrame = function() return NewClickableStub() end
    local btn = EbonBuilds.Theme.CreateButton(nil)
    local realHandlerRan = false
    btn:SetScript("OnClick", function() realHandlerRan = true end)
    local traceRan = false
    EbonBuilds.ClickTrace = { Log = function() traceRan = true end }
    btn:Click()
    CreateFrame = originalCreateFrame2
    EbonBuilds.ClickTrace = nil
    check(realHandlerRan, "Theme.CreateButton: a real click still fires the caller's own OnClick handler")
    check(traceRan, "Theme.CreateButton: a real click also reaches the ClickTrace hook, neither shadows the other")

    -- Layer 5: error capture. The original bug report was "nothing happens
    -- and /ebb errors is empty" -- that combination is only possible
    -- because nothing wrapped this click path in ErrorLog.Protect, so a
    -- real error would go straight to WoW's own (usually disabled) error
    -- display and never reach EbonBuilds' own log. Confirms the mechanism
    -- BuildTabs.lua now wraps the button in actually captures a failure.
    if not EbonBuilds.ErrorLog then dofile("core/ErrorLog.lua") end
    EbonBuildsCharDB.errorLog = {}
    local throwingTrigger = EbonBuilds.ErrorLog.Protect("test.ExportAI", function()
        error("simulated failure inside GenerateAIText")
    end)
    throwingTrigger()
    local logged = EbonBuilds.ErrorLog.GetAll()
    check(#logged == 1, "ErrorLog.Protect captures a real error instead of letting it vanish")
    check(#logged == 1 and logged[1].message:find("simulated failure", 1, true) ~= nil,
        "captured error entry keeps the original error message")
end

if failures > 0 then
    io.stderr:write(string.format("%d test(s) failed.\n", failures))
    os.exit(1)
end

print("All EbonBuilds feature tests passed.")
