-- Tome draw-pool toggle, LockPerk / UnlockPerk, and SnapshotCurrentEchoes coverage
-- for ProjectEbonhold integration (#68 / #62). Headless Lua 5.1 (WoW 3.3.5a).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("TOME_LOCKPERK FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertTrue(value, message)
    if not value then fail(message) end
end

local function assertFalse(value, message)
    if value then fail(message) end
end

local function assertEq(a, b, message)
    if a ~= b then
        fail((message or "not equal") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

local function assertNil(value, message)
    if value ~= nil then fail(message or ("expected nil, got " .. tostring(value))) end
end

local function read_file(path)
    local file, err = io.open(path, "rb")
    if not file then fail(err or ("unable to read " .. path)) end
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

local function source_has(path, fragments, label)
    local source = read_file(path)
    for _, fragment in ipairs(fragments) do
        if not source:find(fragment, 1, true) then
            fail(label .. " missing fragment in " .. path .. ": " .. fragment)
        end
    end
end

------------------------------------------------------------------------
-- ProjectAPI wrapper edge cases (pcall safety, arity, heuristics)
------------------------------------------------------------------------

function UnitClass() return "Mage", "MAGE" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

ProjectEbonhold = {
    PerkDatabase = {
        [6001] = { requiredSpell = 106001, quality = 2 },
        [6002] = { quality = 1 }, -- no requiredSpell; 100000 heuristic applies
    },
    PerkUI = { Show = function() end, Hide = function() end },
    PerkService = {},
}

local addon = {}
local function loadAddonFile(path)
    local chunk, err = loadfile(path)
    if not chunk then fail(err) end
    local ok, result = pcall(chunk, "EbonBuilds", addon)
    if not ok then fail(path .. ": " .. tostring(result)) end
end

loadAddonFile("core/EventHub.lua")
loadAddonFile("modules/integration/ProjectEbonholdAPI.lua")
assertTrue(addon.ProjectAPI.Init(), "ProjectAPI did not initialize")

local API = addon.ProjectAPI

-- requiredSpell lookup and itemId - 100000 fallback
assertEq(API.FindEchoSpellIdByTomeItem(106001), 6001, "requiredSpell mapping")
assertEq(API.FindEchoSpellIdByTomeItem(106002), 6002, "100000 offset heuristic")
assertNil(API.FindEchoSpellIdByTomeItem(nil), "nil tome item")
assertNil(API.FindEchoSpellIdByTomeItem(1), "unknown tome item")

local lockArgs = {}
ProjectEbonhold.PerkService.LockPerk = function(spellId, count)
    lockArgs[#lockArgs + 1] = { spellId = spellId, count = count }
    return true
end
ProjectEbonhold.PerkService.UnlockPerk = function(spellId) return spellId == 6001 end
ProjectEbonhold.PerkService.ToggleTomeEcho = function(spellId) return spellId == 6001 end
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function() return false end
ProjectEbonhold.PerkService.GetLockedPerks = function() return { { spellId = 6001, quality = 2 } } end
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function() return 2 end
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function()
    return { { spellId = 6001, quality = 2, stacks = 1 } }
end

assertTrue(API.LockPerk(6001, 3), "LockPerk accepts custom count")
assertEq(lockArgs[1].count, 3, "LockPerk forwards count")
assertFalse(API.LockPerk(nil), "LockPerk rejects nil spellId")
assertFalse(API.LockPerk("bad"), "LockPerk rejects non-numeric spellId")
assertTrue(API.UnlockPerk(6001), "UnlockPerk forwards")
assertFalse(API.UnlockPerk(nil), "UnlockPerk rejects nil")
assertTrue(API.ToggleTomeEcho(6001), "ToggleTomeEcho forwards")
assertFalse(API.ToggleTomeEcho(nil), "ToggleTomeEcho rejects nil")
assertFalse(API.IsTomeEchoDisabled(nil), "IsTomeEchoDisabled rejects nil")

local snap = API.SnapshotCurrentEchoes()
assertTrue(type(snap) == "table" and #snap == 1, "Snapshot returns table")
assertEq(snap[1].spellId, 6001, "Snapshot spellId")

-- pcall failures must not throw; wrappers return safe defaults.
ProjectEbonhold.PerkService.LockPerk = function() error("boom") end
ProjectEbonhold.PerkService.UnlockPerk = function() error("boom") end
ProjectEbonhold.PerkService.ToggleTomeEcho = function() error("boom") end
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function() error("boom") end
ProjectEbonhold.PerkService.GetLockedPerks = function() error("boom") end
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function() error("boom") end
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function() error("boom") end

assertFalse(API.LockPerk(6001), "LockPerk pcall error -> false")
assertFalse(API.UnlockPerk(6001), "UnlockPerk pcall error -> false")
assertFalse(API.ToggleTomeEcho(6001), "ToggleTomeEcho pcall error -> false")
assertFalse(API.IsTomeEchoDisabled(6001), "IsTomeEchoDisabled pcall error -> false")
assertNil(API.GetLockedPerks(), "GetLockedPerks pcall error -> nil")
assertEq(API.GetMaximumPermanentEchoes(), 0, "GetMaximumPermanentEchoes pcall error -> 0")
assertNil(API.SnapshotCurrentEchoes(), "SnapshotCurrentEchoes pcall error -> nil")

ProjectEbonhold.PerkService.GetLockedPerks = function() return "not-a-table" end
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function() return 42 end
assertNil(API.GetLockedPerks(), "GetLockedPerks non-table -> nil")
assertNil(API.SnapshotCurrentEchoes(), "Snapshot non-table -> nil")

ProjectEbonhold.PerkService.ToggleTomeEcho = function() return false end
assertFalse(API.ToggleTomeEcho(6001), "ToggleTomeEcho explicit false -> false")

print("ProjectAPI tome/lock/snapshot edge cases passed.")

------------------------------------------------------------------------
-- Snapshot draft mapping (BuildOverview Snapshot Run contract)
------------------------------------------------------------------------

EbonBuilds = EbonBuilds or {}
EbonBuildsDB = { builds = {} }
EbonBuildsCharDB = {}
EbonBuilds.Runtime = {}
EbonBuilds.L = setmetatable({}, { __index = function(_, k) return k end })
EbonBuilds.EventHub = addon.EventHub
EbonBuilds.Scheduler = { After = function(_, _, fn) fn(); return true end }

function GetTime() return 0 end
function time() return 1234567890 end
function date() return "2026-07-24 12:00:00" end
function hooksecurefunc() end
function UnitName() return "Tester" end
function UnitLevel() return 1 end
function GetRealmName() return "TestRealm" end
function GetTalentTabInfo() return nil, nil, 0 end
function InCombatLockdown() return false end
function StaticPopup_Show() end
StaticPopupDialogs = {}

assert(loadfile("modules/data/Quality.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/weights/Weights.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/build/Build.lua"))("EbonBuilds", EbonBuilds)

local function MapSnapshotToLockedEchoes(list)
    local locked = { nil, nil, nil, nil, nil, nil }
    for i = 1, math.min(EbonBuilds.Build.LOCKED_SLOTS, #list) do
        locked[i] = tonumber(list[i].spellId)
    end
    return locked
end

local seven = {}
for i = 1, 7 do seven[i] = { spellId = 6000 + i, quality = 0, stacks = 1 } end
local mapped = MapSnapshotToLockedEchoes(seven)
assertEq(#mapped, EbonBuilds.Build.LOCKED_SLOTS, "locked slot array length")
assertEq(mapped[1], 6001, "first snapshot echo mapped")
assertEq(mapped[6], 6006, "sixth snapshot echo mapped")
assertNil(mapped[7], "overflow beyond LOCKED_SLOTS is dropped")

local draft = EbonBuilds.Build.Create({
    title = EbonBuilds.L["Run Snapshot"],
    class = "MAGE",
    lockedEchoes = MapSnapshotToLockedEchoes({
        { spellId = 6001, quality = 2, stacks = 3 },
        { spellId = 6002, quality = 1, stacks = 1 },
    }),
    comments = string.format(EbonBuilds.L["Imported from current run (%d unique echoes)."], 2),
    startPaused = true,
})
assertTrue(draft and draft.id, "snapshot draft created")
assertEq(draft.lockedEchoes[1], 6001, "draft locked echo 1")
assertEq(draft.lockedEchoes[2], 6002, "draft locked echo 2")
assertFalse(EbonBuilds.Build.IsAutomationEnabled(draft), "snapshot draft starts with automation off")

print("Snapshot draft mapping passed.")

------------------------------------------------------------------------
-- LockPerk gesture guards (mirrors BuildOverview right-click handler)
------------------------------------------------------------------------

local function LockGuardReason(api, spellId)
    local caps = api.GetCapabilities()
    if not (caps and caps.lockPerk and caps.lockedPerks and caps.maxPermanentEchoes) then
        return "unsupported"
    end
    local locked = api.GetLockedPerks() or {}
    local maxSlots = api.GetMaximumPermanentEchoes()
    if maxSlots <= 0 then return "no_slots" end
    if #locked >= maxSlots then return "full" end
    for _, lp in ipairs(locked) do
        if tonumber(lp.spellId) == tonumber(spellId) then return "duplicate" end
    end
    return "ok"
end

ProjectEbonhold.PerkService.GetLockedPerks = function() return {} end
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function() return 2 end
ProjectEbonhold.PerkService.LockPerk = function() return true end
ProjectEbonhold.PerkService.UnlockPerk = function() return true end
ProjectEbonhold.PerkService.ToggleTomeEcho = function() return true end
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function() return false end
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function() return {} end

assertEq(LockGuardReason(API, 6001), "ok", "empty slots allow lock")

ProjectEbonhold.PerkService.GetLockedPerks = function()
    return { { spellId = 6001 }, { spellId = 6002 } }
end
assertEq(LockGuardReason(API, 6003), "full", "full permanent slots block lock")

ProjectEbonhold.PerkService.GetLockedPerks = function()
    return { { spellId = 6001 } }
end
assertEq(LockGuardReason(API, 6001), "duplicate", "duplicate spell blocked")

ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function() return 0 end
assertEq(LockGuardReason(API, 6001), "no_slots", "zero max slots blocked")

ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = nil
ProjectEbonhold.PerkService.GetLockedPerks = nil
ProjectEbonhold.PerkService.LockPerk = nil
assertEq(LockGuardReason(API, 6001), "unsupported", "missing APIs blocked")

print("LockPerk gesture guards passed.")

------------------------------------------------------------------------
-- Tome toggle level-1 gate (TryToggleTomePool contract)
------------------------------------------------------------------------

local tomeToggleCalls = 0
local playerLevel = 80
function UnitLevel() return playerLevel end
ProjectEbonhold.PerkService.ToggleTomeEcho = function(spellId)
    tomeToggleCalls = tomeToggleCalls + 1
    return spellId == 7001
end
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function() return false end

local function TryToggleTomePoolSim(item, caps)
    if not item or item.kind ~= "tome" or not item.owned or not item.spellId then return "skip" end
    if not (caps and caps.tomeToggle) then return "no_cap" end
    if (UnitLevel("player") or 1) ~= 1 then return "not_l1" end
    if API.ToggleTomeEcho(item.spellId) then return "toggled" end
    return "rejected"
end

local caps = API.GetCapabilities()
assertEq(TryToggleTomePoolSim({ kind = "tome", owned = true, spellId = 7001 }, caps), "not_l1",
    "non-L1 player cannot toggle")
playerLevel = 1
tomeToggleCalls = 0
assertEq(TryToggleTomePoolSim({ kind = "tome", owned = true, spellId = 7001 }, caps), "toggled",
    "L1 player toggles")
assertEq(tomeToggleCalls, 1, "toggle forwarded at L1")
assertEq(TryToggleTomePoolSim({ kind = "tome", owned = false, spellId = 7001 }, caps), "skip",
    "unowned tomes ignored")
assertEq(TryToggleTomePoolSim({ kind = "tome", owned = true, spellId = 7001 }, { tomeToggle = false }),
    "no_cap", "capability gate blocks toggle")

print("Tome toggle L1 gate passed.")

------------------------------------------------------------------------
-- Static UI / API source contracts (#68 / #62)
------------------------------------------------------------------------

source_has("modules/ui/TomeAtlasView.lua", {
    "local function TomeToggleCapable()",
    "IsTomeEchoDisabled(spellId)",
    "local function TryToggleTomePool(item)",
    'UnitLevel("player") or 1) ~= 1',
    "ToggleTomeEcho(item.spellId)",
    "tomeAtlas.tomeToggleRefresh",
    'button == "RightButton"',
    "draw pool OFF",
    "Right-click to toggle draw pool (level 1 only)",
}, "TomeAtlasView")

source_has("modules/ui/BuildOverview.lua", {
    "GetLockedPerks()",
    "GetMaximumPermanentEchoes()",
    "Permanent locks:",
    "Right-click to lock permanently on character",
    "Permanent lock slots full",
    "Already permanently locked",
    "UnlockPerk(self._spellId)",
    "LockPerk(self._spellId)",
    "SnapshotCurrentEchoes()",
    'EbonBuilds.L["Snapshot Run"]',
    "startPaused = true",
    "caps.snapshotEchoes",
}, "BuildOverview")

source_has("modules/integration/ProjectEbonholdAPI.lua", {
    "function API.IsTomeEchoDisabled(spellId)",
    "function API.ToggleTomeEcho(spellId)",
    "function API.GetLockedPerks()",
    "function API.GetMaximumPermanentEchoes()",
    "function API.LockPerk(spellId, count)",
    "function API.UnlockPerk(spellId)",
    "function API.SnapshotCurrentEchoes()",
    "tomeToggle = service",
    "lockPerk = service",
    "snapshotEchoes = service",
}, "ProjectEbonholdAPI")

source_has("modules/data/FAQContent.lua", {
    "ToggleTomeEcho",
    "IsTomeEchoDisabled",
    "GetLockedPerks",
    "LockPerk",
    "SnapshotCurrentEchoes",
    "#68 / #62",
}, "FAQContent")

print("Static tome/lock/snapshot source contracts passed.")
print("TOME_LOCKPERK OK")
