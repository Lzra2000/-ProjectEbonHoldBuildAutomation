-- Fuzz test for Sync.lua's inbound message handlers. Feeds thousands of
-- malformed, truncated, and hostile payloads to DispatchAddon and
-- HandleChannelMessage -- the exact surface PR #1's control-byte crash
-- lived on. Anything an arbitrary player can put on a channel or in a
-- SendAddonMessage must never raise: at worst it gets ignored.
--
-- Deterministic: fixed seed, so a failure reproduces exactly. On failure
-- it prints the seed, iteration, and an escaped dump of the offending
-- payload -- everything needed to turn it into a named regression test.
-- Run from the addon root with: texlua tests/test_sync_fuzz.lua

unpack = unpack or table.unpack

local SEED = 20260719
local ITERATIONS = 4000

EbonBuilds = {}
EbonBuildsDB = { builds = {}, publicBuilds = {}, globalSettings = {} }
EbonBuildsCharDB = {}

-- Minimal WoW API surface Sync.lua touches. Send-side stubs swallow
-- output; the fuzzer only cares that receive-side never raises.
local now = 0
function GetTime() now = now + 0.1 return now end
function UnitName() return "Fuzzer" end
function SendAddonMessage() end
function SendChatMessage() end
function RegisterAddonMessagePrefix() end
function GetChannelName() return 0 end
function IsInGuild() return false end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function CreateFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
StaticPopupDialogs = {}
function StaticPopup_Show() end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
bit = bit or { band = function(a, b) return a % (b + b) >= b and b or 0 end }

-- WoW string globals, implemented faithfully -- no-op stubs here would
-- skip the real parsing paths and the fuzzer would be testing nothing.
function strsplit(delim, s)
    local out = {}
    local pattern = "([^" .. delim:gsub("%W", "%%%1") .. "]*)"
    for piece in s:gmatch(pattern .. delim:gsub("%W", "%%%1") .. "?") do
        out[#out + 1] = piece
    end
    -- gmatch yields one trailing empty capture past the end; drop it when
    -- the string doesn't actually end with the delimiter
    if #out > 1 and out[#out] == "" and s:sub(-1) ~= delim then out[#out] = nil end
    return unpack(out)
end
function strjoin(delim, ...) return table.concat({ ... }, delim) end
function strtrim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
date = os.date
time = os.time

EbonBuilds.Scheduler = { After = function() end, Every = function() end, BACKGROUND = 1 }
EbonBuilds.DebugLog = { IsEnabled = function() return false end, Add = function() end, AddF = function() end }
EbonBuilds.Toast = { Show = function() end, ShowAutomationResult = function() end }
EbonBuilds.EchoPerformance = { HandleBroadcast = function() end }
EbonBuilds.Build = {
    GetActive = function() return nil end,
    GetAll = function() return {} end,
}
EbonBuilds.ExportImport = { DecodeBuild = function() return nil, "fuzz" end, ImportBuild = function() return nil, "fuzz" end }
EbonBuilds.TomeAtlas = { SerializeAll = function() return {} end }

assert(loadfile("core/RingBuffer.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/sync/Sync.lua"))("EbonBuilds", EbonBuilds)

local dispatch = EbonBuilds.Sync._DispatchAddonForTests
local channel  = EbonBuilds.Sync._HandleChannelMessageForTests
local system   = EbonBuilds.Sync._HandleSystemMessageForTests
assert(dispatch and channel and system, "Sync test hooks are missing")

-- Plain LCG instead of math.random: identical sequences across Lua 5.1
-- and texlua's 5.3, so the printed seed reproduces everywhere.
local state = SEED
local function rnd(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return (state % n) + 1
end

local OPCODES = { "REQ", "BAT", "END", "LST", "GET", "SKP", "WNT", "PRF", "" }
local SENDERS = { "Fuzzer", "Goofylock", "", nil, "Name-Realm", "x" }

local function randomBytes(len)
    local t = {}
    for i = 1, len do t[i] = string.char(rnd(256) - 1) end
    return table.concat(t)
end

local function randomPayload()
    local mode = rnd(6)
    if mode == 1 then
        -- structurally plausible: real opcode, garbage fields
        local parts = { OPCODES[rnd(#OPCODES)] }
        for _ = 1, rnd(6) do parts[#parts + 1] = randomBytes(rnd(24)) end
        return table.concat(parts, "|")
    elseif mode == 2 then
        return randomBytes(rnd(255))                 -- pure noise, incl. control bytes
    elseif mode == 3 then
        return string.rep("|", rnd(40))              -- delimiter floods
    elseif mode == 4 then
        local real = "BAT|Fuzzer|1/3|" .. randomBytes(rnd(60))
        return real:sub(1, rnd(#real))               -- truncated mid-message
    elseif mode == 5 then
        return "END|" .. randomBytes(rnd(10)) .. "|" .. tostring(2 ^ 52) -- absurd numerics
    else
        local s = {}
        for _ = 1, rnd(30) do s[#s + 1] = string.char(rnd(31)) end -- control-byte heavy (PR #1's class)
        return table.concat(s)
    end
end

local function protectedCall(fn, label, iteration, ...)
    local args = { ... }
    local ok, err = pcall(fn, unpack(args, 1, 4))
    if not ok then
        io.stderr:write(string.format(
            "SYNC FUZZ FAIL: %s raised at iteration %d (seed %d)\n  error: %s\n  payload (escaped): %q\n",
            label, iteration, SEED, tostring(err), tostring(args[label == "HandleChannelMessage" and 1 or 2])))
        os.exit(1)
    end
end

for i = 1, ITERATIONS do
    local payload = randomPayload()
    local sender = SENDERS[rnd(#SENDERS)]
    local kind = rnd(3)
    if kind == 1 then
        protectedCall(dispatch, "DispatchAddon", i, "EbonBuilds", payload, "WHISPER", sender)
    elseif kind == 2 then
        -- wrong prefixes must also be safe (other addons share the event)
        protectedCall(dispatch, "DispatchAddon", i, randomBytes(rnd(12)), payload, "GUILD", sender)
    else
        protectedCall(channel, "HandleChannelMessage", i, payload, sender, nil, "EbonSync", nil, nil, nil, rnd(10))
    end
    if i % 10 == 0 then
        protectedCall(system, "HandleSystemMessage", i, "No player named '" .. randomBytes(rnd(20)) .. "' is currently playing.")
    end
end

-- Version ping semantics (Sync is fully loaded here with all stubs).
local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) messages[#messages + 1] = msg end }
GetAddOnMetadata = function() return "3.31" end
local ping = EbonBuilds.Sync._HandleVersionPingForTests
ping("VER|3.30", "Other")
ping("VER|garbage", "Other")
ping("VER|3.31", "Other")
assert(#messages == 0, "equal/lower/malformed versions must never notify")
ping("VER|3.32", "Other")
assert(#messages == 1 and messages[1]:find("3.32", 1, true) and messages[1]:find("github.com", 1, true),
    "a higher peer version triggers one notice with the releases link")
ping("VER|3.33", "Other")
assert(#messages == 1, "the notice fires once per session")
print("Version ping semantics passed.")

-- Requester state used to expire only when another inbound chunk happened.
-- A quiet server could therefore retain one full eligible-build array and one
-- cooldown entry per unique requester indefinitely.
EbonBuilds.Sync._ResetForTests()
EbonBuilds.Build.ListPublic = function()
    return { { id = "public-build", title = "Public", class = "MAGE", author = "Author", validated = true } }
end
for i = 1, 200 do
    local sender = "Requester" .. i
    dispatch("EbonBuilds", "REQ|" .. sender .. "|MAGE", "WHISPER", sender)
end
local retained = EbonBuilds.Sync._DebugState()
assert(retained.pendingBatches == 200 and retained.requestCooldowns == 200,
    "sync retention fixture did not create the expected requester state")
now = now + 100
EbonBuilds.Sync._CleanupExpiredForTests()
local expired = EbonBuilds.Sync._DebugState()
assert(expired.pendingBatches == 0 and expired.requestCooldowns == 0,
    "quiet sync requester state was not expired by periodic cleanup")
now = now + 4000
EbonBuilds.Sync._CleanupExpiredForTests()
assert(EbonBuilds.Sync._DebugState().peers == 0, "stale session-local peer presence was not expired")
print("Sync retention cleanup passed: pending batches, cooldowns, and stale peers are bounded while idle.")

print(string.format("Sync fuzz passed: %d hostile payloads across DispatchAddon, HandleChannelMessage, and HandleSystemMessage (seed %d).", ITERATIONS, SEED))
