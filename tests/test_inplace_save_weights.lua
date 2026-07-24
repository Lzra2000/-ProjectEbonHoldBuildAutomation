-- Regression: Street0r Discord report — second Save after tab switch lost
-- priority edits until /reload. AcceptSavedBuild must keep the live pending
-- weight table identities and still reflect the committed SavedVariables
-- values so every Save updates both the canonical store and the editor model.
--
-- Run: lua5.1 tests/test_inplace_save_weights.lua

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
    },
    PerkService = {
        SelectPerk = function() end,
        GetGrantedPerks = function() return {} end,
        GetCurrentChoice = function() return {} end,
        GetDiscoveredEchoes = function() return {} end,
        BanishPerk = function() return true end,
        RequestReroll = function() return false end,
        FreezePerk = function() return false end,
    },
    PerkUI = { Show = function() end, UpdateSinglePerk = function() end },
}

local function Noop() end
local function FrameStub()
    return { RegisterEvent = Noop, SetScript = Noop, Show = Noop, Hide = Noop, IsShown = function() return false end }
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
function date() return "2026-07-24 12:00:00" end
function time() return 123456789 end
function StaticPopup_Show() end
StaticPopupDialogs = {}

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
bit = {
    band = Band,
    bor = function(a, b)
        a, b = tonumber(a) or 0, tonumber(b) or 0
        local result, place = 0, 1
        while a > 0 or b > 0 do
            local abit, bbit = a % 2, b % 2
            if abit == 1 or bbit == 1 then result = result + place end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
        end
        return result
    end,
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
    INTERACTIVE = 1,
    Every = function() return true end,
    After = function(_, _, fn) if fn then fn() end; return true end,
    Cancel = Noop,
}
EbonBuilds.DebugLog = { IsEnabled = function() return false end, Add = Noop, AddF = Noop }
EbonBuilds.Toast = { Show = Noop }
EbonBuilds.Session = { LogAction = Noop, GetActiveSession = function() return nil end, MarkStrategyChanged = Noop }
EbonBuilds.ViewRouter = { Current = function() return "buildTabs" end, Show = Noop, Register = Noop }
EbonBuilds.L = setmetatable({}, { __index = function(_, key) return key end })
EbonBuilds.Theme = {
    TEXT_PRIMARY = { 1, 1, 1 },
    TEXT_MUTED = { 0.6, 0.6, 0.6 },
    WARNING = { 1, 0.8, 0 },
    CreateButton = function() return FrameStub() end,
    CreateTab = function() return FrameStub() end,
    ApplyPanel = Noop,
    SetTabSelected = Noop,
    SetButtonAccent = Noop,
    ClearButtonAccent = Noop,
    AttachTooltip = Noop,
    BindScrollWheel = Noop,
    SetInputState = Noop,
    CreatePageHeader = function() return { _title = {} } end,
    UpdatePageHeader = Noop,
}

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
assert(loadfile("modules/build/EchoReferenceMigration.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/CharacterSnapshot.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/ui/BuildForm.lua"))("EbonBuilds", EbonBuilds)

EbonBuilds.EchoCatalog.Init()
EbonBuilds.EchoEligibilityEvidence.Init()
-- BuildForm.Init builds WoW frames; Prepare/AcceptSavedBuild only need the
-- module load for the draft helpers under test.

local REF = "g:9001"

local function OpenEditor(build)
    EbonBuilds.Build.SetActive(build.id)
    EbonBuilds.BuildForm.Prepare({ mode = "edit", build = build })
end

local function SaveLikeOnSave()
    local id = EbonBuilds.BuildForm.GetEditingBuildId()
    local live = EbonBuilds.Build.Get(id)
    local baseRevision = live and (tonumber(live.revision) or 1) or 1
    local weights = EbonBuilds.Runtime.pendingWeights
    local refWeights = EbonBuilds.Runtime.pendingRefWeights
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local saved = EbonBuilds.Build.Save(id, {
        title = "Street0r Save Repro",
        class = "MAGE",
        spec = 1,
        comments = "",
        lockedEchoes = { nil, nil, nil, nil, nil, nil },
        settings = settings,
        isPublic = false,
        echoWeights = weights,
        echoWeightsByRef = refWeights,
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint and EbonBuilds.EchoCatalog.GetFingerprint(),
        baseRevision = baseRevision,
    })
    check(saved ~= nil, "Build.Save must succeed (baseRevision=" .. tostring(baseRevision) .. ")")
    EbonBuilds.BuildTabs.OnBuildSaved(saved)
    return saved
end

-- Also wire a minimal BuildTabs.OnBuildSaved so the production path is covered
-- when the full UI module is not loaded.
EbonBuilds.BuildTabs = EbonBuilds.BuildTabs or {}
EbonBuilds.BuildTabs.OnBuildSaved = function(savedBuild)
    savedBuild = savedBuild or EbonBuilds.Build.GetActive()
    if not savedBuild then return end
    if savedBuild.id then
        savedBuild = EbonBuilds.Build.Get(savedBuild.id) or savedBuild
    end
    EbonBuilds.BuildForm.AcceptSavedBuild(savedBuild)
end
EbonBuilds.BuildTabs.ClearDirty = Noop
EbonBuilds.BuildTabs.MarkDirty = Noop

do
    local build = EbonBuilds.Build.Create({
        title = "Street0r Save Repro",
        class = "MAGE",
        spec = 1,
        comments = "",
        echoWeights = {},
        echoWeightsByRef = {
            [REF] = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
        },
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint and EbonBuilds.EchoCatalog.GetFingerprint(),
    })
    OpenEditor(build)

    local pendingRefBefore = EbonBuilds.Runtime.pendingRefWeights
    check(type(pendingRefBefore) == "table", "editor starts with a pending ref-weight draft")

    -- First edit + save
    local ok = EbonBuilds.Weights.SetForRef(EbonBuilds.Build.GetActive(), REF, 50, 0)
    check(ok, "first priority edit applies")
    local saved1 = SaveLikeOnSave()
    check(saved1 ~= nil, "first Save returns the build")
    equal(EbonBuilds.Weights.GetFromWeights(saved1.echoWeightsByRef, REF, 0), 50,
        "first Save persists priority 50 into SavedVariables")
    check(EbonBuilds.Runtime.pendingRefWeights == pendingRefBefore,
        "AcceptSavedBuild keeps the same pendingRefWeights table identity")
    equal(EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), REF, 0), 50,
        "live editor model shows first save")

    -- Simulate tab switch remount: read again from pending (OnShow path)
    equal(EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), REF, 0), 50,
        "tab remount still shows first save")

    -- Second edit + save (the reported failure)
    ok = EbonBuilds.Weights.SetForRef(EbonBuilds.Build.GetActive(), REF, 99, 0)
    check(ok, "second priority edit applies")
    equal(EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), REF, 0), 99,
        "live draft has second edit before Save")
    check(EbonBuilds.Runtime.pendingRefWeights == pendingRefBefore,
        "second edit still targets the original pending table")

    local saved2 = SaveLikeOnSave()
    check(saved2 ~= nil, "second Save returns the build")
    equal(EbonBuilds.Weights.GetFromWeights(saved2.echoWeightsByRef, REF, 0), 99,
        "second Save persists priority 99 into SavedVariables")
    local canonical = EbonBuilds.Build.Get(saved2.id)
    equal(EbonBuilds.Weights.GetFromWeights(canonical.echoWeightsByRef, REF, 0), 99,
        "canonical Build.Get matches second Save")
    check(EbonBuilds.Runtime.pendingRefWeights == pendingRefBefore,
        "AcceptSavedBuild still keeps pendingRefWeights identity after second Save")
    equal(EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), REF, 0), 99,
        "live editor model shows second save")

    -- Tab switch away and back (refresh from pending / GetForRef)
    equal(EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), REF, 0), 99,
        "after tab remount values stay at second save (not reset to first)")
end

-- Orphan-pointer contract: swapping Runtime.pendingRefWeights without adopting
-- into the old table must not be what AcceptSavedBuild does anymore.
do
    local formSource
    local file = assert(io.open("modules/ui/BuildForm.lua", "r"))
    formSource = file:read("*a")
    file:close()
    check(formSource:find("AdoptTableInPlace", 1, true) ~= nil,
        "AcceptSavedBuild uses in-place draft adoption")
    check(formSource:find("AdoptSettingsInPlace", 1, true) ~= nil,
        "AcceptSavedBuild preserves settings table identity")
end

if failures > 0 then
    io.stderr:write(string.format("%d failure(s) in test_inplace_save_weights.lua\n", failures))
    os.exit(1)
end
print("OK: in-place Save keeps pending weight identity across repeated priority edits")
