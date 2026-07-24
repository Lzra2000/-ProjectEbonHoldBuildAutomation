-- Headless coverage for Echo Journal -> EbonBuilds shared-loadout bridge.
-- Maps PE PerkService shared loadouts to ephemeral pseudo-builds; asserts
-- they never land in remoteBuilds / ListPublic (no peer rebroadcast).

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
EbonBuildsDB = { builds = {}, remoteBuilds = {} }
EbonBuildsCharDB = {}

local sharedList = nil
local requestCalls = {}

EbonBuilds.ProjectAPI = {
    GetCapabilities = function()
        return { sharedLoadouts = true }
    end,
    GetSharedEchoLoadouts = function()
        return sharedList
    end,
    RequestSharedEchoLoadouts = function(classToken)
        requestCalls[#requestCalls + 1] = tostring(classToken or "")
        return true
    end,
}

EbonBuilds.Build = {
    LOCKED_SLOTS = 6,
    ListPublic = function()
        local out = {}
        for _, b in pairs(EbonBuildsDB.builds) do
            if b.isPublic then out[#out + 1] = b end
        end
        for _, b in pairs(EbonBuildsDB.remoteBuilds) do
            out[#out + 1] = b
        end
        return out
    end,
}

EbonBuilds.Quality = { ORDER = { 3, 2, 1, 0 } }
EbonBuilds.EchoCatalog = {
    GetBySpellId = function() return nil end,
}
EbonBuilds.Weights = {
    ResolveLegacyName = function() return nil end,
}
EbonBuilds.EchoProjection = {
    GetEntry = function(_, refKey)
        refKey = tostring(refKey or "")
        if not refKey:match("^[gs]:%d+$") then return nil end
        return { refKey = refKey, displayName = "Echo " .. refKey }
    end,
    ResolveSpell = function(_, spellId)
        spellId = tonumber(spellId)
        if not spellId then return nil end
        local refKey = "g:" .. tostring(spellId)
        return { refKey = refKey, displayName = "Echo " .. refKey }, { spellId = spellId, refKey = refKey }
    end,
}
EbonBuilds.SpecData = {
    SHAMAN = {
        { name = "Elemental" },
        { name = "Enhancement" },
        { name = "Restoration" },
    },
}

assert(loadfile("modules/integration/SharedLoadoutBridge.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/recommendations/CommunityEligibility.lua"))("EbonBuilds", EbonBuilds)

local Bridge = EbonBuilds.SharedLoadoutBridge
local Eligibility = EbonBuilds.CommunityEligibility

------------------------------------------------------------------------
-- MapLoadoutToBuild
------------------------------------------------------------------------
do
    local build = Bridge.MapLoadoutToBuild({
        name = "BiS",
        author = "Alashaman",
        class = "SHAMAN",
        echoes = {
            { spellId = 990001, quality = 3, stacks = 1 },
            { spellId = 990002, quality = 2, stacks = 2 },
            990003,
        },
    })
    check(build ~= nil, "maps a valid loadout")
    equal(build.id, "pe-shared:Alashaman:SHAMAN:BiS", "stable pe-shared id")
    equal(build.title, "BiS", "title from loadout name")
    equal(build.author, "Alashaman", "author preserved")
    equal(build.class, "SHAMAN", "class preserved")
    check(build.spec == nil, "no invented talent-spec")
    check(build.peSharedLoadout == true, "peSharedLoadout marker")
    equal(#build.lockedEchoes, 3, "all echoes become lockedEchoes")
    equal(build.lockedEchoes[1], 990001, "first locked spellId")
    equal(build.lockedEchoes[3], 990003, "bare spellId entries accepted")
    check(Bridge.IsPseudoId(build.id), "IsPseudoId recognizes bridge ids")
end

do
    check(Bridge.MapLoadoutToBuild(nil) == nil, "nil loadout -> nil")
    check(Bridge.MapLoadoutToBuild({ name = "Empty", author = "x", class = "MAGE", echoes = {} }) == nil,
        "empty echoes -> nil")
    check(Bridge.MapLoadoutToBuild({ author = "x", class = "MAGE", echoes = { { spellId = 1 } } }) == nil,
        "missing name -> nil")
end

------------------------------------------------------------------------
-- Cache / ListPseudoBuilds / no DB pollution
------------------------------------------------------------------------
do
    sharedList = {
        {
            name = "14.7m sec", author = "Noizegoat", class = "SHAMAN",
            echoes = { { spellId = 1001, quality = 3, stacks = 1 } },
        },
        {
            name = "Bear", author = "Blondesse", class = "SHAMAN",
            echoes = { { spellId = 1002, quality = 2, stacks = 1 } },
        },
        {
            name = "Arcane BiS", author = "MageGuy", class = "MAGE",
            echoes = { { spellId = 2001, quality = 3, stacks = 1 } },
        },
    }
    local count = Bridge.RefreshFromService()
    equal(count, 3, "RefreshFromService caches three loadouts")
    local shaman = Bridge.ListPseudoBuilds("SHAMAN")
    equal(#shaman, 2, "class filter returns shaman only")
    equal(#Bridge.ListPseudoBuilds(), 3, "unfiltered list is complete")

    check(next(EbonBuildsDB.remoteBuilds) == nil, "bridge never writes remoteBuilds")
    check(next(EbonBuildsDB.builds) == nil, "bridge never writes builds")
    equal(#EbonBuilds.Build.ListPublic(), 0, "ListPublic stays empty (no peer rebroadcast)")
end

------------------------------------------------------------------------
-- CommunityEligibility: PE only on class-wide widen
------------------------------------------------------------------------
do
    local exact = Eligibility.CollectSources("SHAMAN", 2)
    equal(#exact, 0, "exact Enhance ignores peSharedLoadout sources")

    local classWide = Eligibility.CollectSources("SHAMAN", 2, { anySpec = true })
    equal(#classWide, 2, "anySpec admits PE shaman loadouts")

    local sources, meta = Eligibility.ResolveSources("SHAMAN", 2)
    check(meta.widened == true, "ResolveSources widens when only PE loadouts exist")
    equal(meta.cohortScope, "class", "cohort scope is class-wide")
    equal(#sources, 2, "widened cohort includes PE shaman loadouts")
end

------------------------------------------------------------------------
-- Request forwards to ProjectAPI
------------------------------------------------------------------------
do
    requestCalls = {}
    check(Bridge.Request("SHAMAN") == true, "Request succeeds when capability present")
    equal(#requestCalls, 1, "one RequestSharedEchoLoadouts call")
    equal(requestCalls[1], "SHAMAN", "class token forwarded")
end

------------------------------------------------------------------------
-- UI lists stay separate; Evidence still sees both
------------------------------------------------------------------------
do
    EbonBuildsDB.remoteBuilds.peer1 = {
        id = "uuid-peer", title = "Bear", author = "Grass", class = "SHAMAN",
        spec = 2, isPublic = true, lockedEchoes = { 1 }, lastModified = "2026-07-24",
    }
    local peer = EbonBuilds.Build.ListPublic()
    equal(#peer, 1, "peer ListPublic is remote only")
    equal(peer[1].title, "Bear", "peer list has the synced build")

    local journal = Bridge.ListPseudoBuilds()
    equal(#journal, 3, "journal list is bridge-only")
    local journalTitles = {}
    for _, b in ipairs(journal) do journalTitles[b.title] = true end
    check(journalTitles.Bear == true, "journal still has PE Bear (not collapsed into peer UI)")
    check(journalTitles["14.7m sec"] == true, "unique PE title on journal list")

    -- Same-title peer + PE may both exist as separate UI sources; Evidence
    -- CollectSources still admits PE on class-wide widen.
    local classWide = Eligibility.CollectSources("SHAMAN", 2, { anySpec = true })
    local hasPeer, hasPe = false, false
    for _, b in ipairs(classWide) do
        if b.id == "uuid-peer" then hasPeer = true end
        if b.peSharedLoadout then hasPe = true end
    end
    check(hasPeer, "Evidence cohort includes peer build")
    check(hasPe, "Evidence cohort still includes Echo Journal loadouts")
end

if failures > 0 then
    io.stderr:write(string.format("SHARED LOADOUT BRIDGE FAIL: %d assertion(s)\n", failures))
    os.exit(1)
end
print("SHARED LOADOUT BRIDGE OK")
