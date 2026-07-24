-- Architecture regression tests for the Phase 4 foundation.
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("ARCHITECTURE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertTrue(value, message)
    if not value then fail(message) end
end

local function read(path)
    local file, err = io.open(path, "rb")
    if not file then fail(err or ("unable to read " .. path)) end
    local text = file:read("*a")
    file:close()
    return text
end

local tocFiles = {}
for line in io.lines("EbonBuilds.toc") do
    line = line:gsub("\r$", "")
    if line:match("^%S+%.lua$") then tocFiles[#tocFiles + 1] = line end
end
assertTrue(#tocFiles > 0, "TOC contains no Lua files")

for _, path in ipairs(tocFiles) do
    local text = read(path)
    assertTrue(text:match("^local addonName, EbonBuilds = %.%.%."), path .. " does not use the private TOC namespace")
    assertTrue(not text:find("EbonBuilds%s*=%s*EbonBuilds%s*or%s*{}"), path .. " recreates a global addon table")
    if path ~= "core/WoWEvents.lua" then
        assertTrue(not text:find(":RegisterEvent%s*%(", 1),
            path .. " calls frame:RegisterEvent(...) — route Blizzard events through core/WoWEvents.lua (EbonBuilds.WoWEvents.On/Off) so one-shot listeners can Off() cleanly and architecture stays centralized. Raw RegisterEvent breaks the ADDON_LOADED one-shot contract used by BagAffixDots (Bagnon/Combuctor late-load).")
    end
end

-- Lint: ban post-3.3.5a (build 12340) APIs that LLMs / retail muscle memory reach for.
-- Mirrors scripts/check-335a-api.sh but fails inside the Lua suite with file context.
local post335a = {
    { "C_Timer%.", "C_Timer (MoP+) — use EbonBuilds.Scheduler or a Frame OnUpdate ticker" },
    { "C_Map%.", "C_Map (retail) — use GetMapInfo/UpdateMapHighlight/GetPlayerMapPosition" },
    { "C_ChatInfo%.", "C_ChatInfo (retail) — use SendAddonMessage / ChatFrame filters" },
    { ":SetShown%s*%(", "Region:SetShown (Cataclysm+) — use Show()/Hide()" },
    { "IsInGroup%s*%(", "IsInGroup (MoP+) — use GetNumPartyMembers()/GetNumRaidMembers()" },
    { "IsInRaid%s*%(", "IsInRaid (MoP+) — use GetNumRaidMembers() > 0" },
    { "GetNumGroupMembers%s*%(", "GetNumGroupMembers (MoP+) — use GetNumPartyMembers()/GetNumRaidMembers()" },
}
for _, path in ipairs(tocFiles) do
    if path ~= "modules/data/FAQContent.lua" then
        local text = read(path)
        for _, rule in ipairs(post335a) do
            assertTrue(not text:find(rule[1]),
                path .. " uses " .. rule[2])
        end
    end
end

-- Forward-declaration contract for WorldIntegration RefreshMapPanel (nil upvalue crash class).
do
    local world = read("modules/ui/WorldIntegration.lua")
    local decl = world:find("local RefreshMapPanel[%s,\n]")
    local assign = world:find("function RefreshMapPanel%(")
    assertTrue(decl and assign and decl < assign,
        "WorldIntegration.lua must forward-declare `local RefreshMapPanel` before `function RefreshMapPanel()` (SetMapPanelEnabled/SetMapEnabled call it earlier)")
end

-- Lint: ban the `x and nil or y` pattern in shipped code. In Lua the
-- `and nil` branch can never be taken (nil is falsy), so the expression
-- ALWAYS evaluates to `y`. Written as a toggle (`x = x and nil or true`)
-- it produces a switch that turns on but never off -- exactly the bug
-- class behind issue #39 (Caster protection, the Echo family filter, and
-- the talent-snapshot comparison). Line comments are stripped before
-- matching so the explanatory comments at the fixed sites don't trip it.
--
-- Allowlisted occurrences (exact counts, so NEW instances still fail):
--   * modules/data/FAQContent.lua -- user-facing FAQ text that describes
--     the historical bug inside a string literal.
--   * modules/automation/ManualTraining.lua -- `q == "legacy" and nil or
--     tonumber(q)`: harmless because tonumber("legacy") is nil anyway, so
--     the expression equals plain tonumber(q); kept until that file is
--     touched for other reasons.
local allowedAndNilOr = {
    ["modules/data/FAQContent.lua"] = 1,
    ["modules/automation/ManualTraining.lua"] = 1,
}
for _, path in ipairs(tocFiles) do
    local text = read(path):gsub("\r\n", "\n")
    local found = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local code = line:gsub("%-%-.*$", "")
        local position = 1
        while true do
            local matchStart = code:find("and%s+nil%s+or%s", position)
            if not matchStart then break end
            found = found + 1
            position = matchStart + 1
        end
    end
    local allowed = allowedAndNilOr[path] or 0
    if found > allowed then
        fail(string.format(
            "%s contains %d `and nil or` expression(s) (%d allowlisted). This always evaluates to the `or` branch; write an explicit if/else toggle instead (issue #39).",
            path, found, allowed))
    end
end

local automation = read("modules/automation/Automation.lua")
assertTrue(not automation:find("PerkUI%.Show%s*="), "Automation replaces the native ProjectEbonhold UI")
assertTrue(automation:find("hooksecurefunc%(PerkUI, %\"Show%\""), "Automation does not securely observe the native UI")

local projectAPI = read("modules/integration/ProjectEbonholdAPI.lua")
assertTrue(not projectAPI:find("ProjectEbonhold%.onEventReceived%s*%(", 1), "ProjectAPI replaces a ProjectEbonhold server handler")
assertTrue(not projectAPI:find("observeServerEvent", 1, true), "ProjectAPI depends on a modified ProjectEbonhold bridge")
assertTrue(projectAPI:find("actionConfirmation = service and %\"request_only%\""),
    "ProjectAPI does not declare request-only standalone integration")
assertTrue(not projectAPI:find("pendingAction", 1, true),
    "ProjectAPI still blocks actions behind inferred acknowledgement state")
assertTrue(projectAPI:find("UploadServerBuildSlot", 1, true),
    "ProjectAPI missing server build-slot upload wrapper (#57)")
assertTrue(projectAPI:find("MapLockedEchoesToServerSlot", 1, true),
    "ProjectAPI missing lockedEchoes -> server slot mapping (#57)")
assertTrue(not projectAPI:find("LearnTalent%s*%("),
    "ProjectAPI must not LearnTalent from foreign snapshots (#57)")

local sync = read("modules/sync/Sync.lua")
assertTrue(not sync:find("UpdateFromPublic%(existing"), "peer sync can overwrite a local build")
assertTrue(sync:find("pcall%(HandleRequest, sender,"), "sync requests do not bind replies to the transport sender")

local database = read("core/Database.lua")
assertTrue(database:find("sourceAccountSchema"), "database migration does not preserve source schema")
assertTrue(database:find("MigrationCoroutine"), "database has no resumable migration entry point")

-- Minimal frame stub used by the centralized WoW event router.
local frames = {}
local function NewFrame()
    local frame = { registered = {}, scripts = {}, visible = true }
    function frame:RegisterEvent(eventName) self.registered[eventName] = true end
    function frame:UnregisterEvent(eventName) self.registered[eventName] = nil end
    function frame:SetScript(scriptName, callback) self.scripts[scriptName] = callback end
    function frame:Show() self.visible = true end
    function frame:Hide() self.visible = false end
    function frame:IsShown() return self.visible end
    return frame
end
function CreateFrame()
    local frame = NewFrame()
    frames[#frames + 1] = frame
    return frame
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local addon = {}
local function loadAddonFile(path)
    local chunk, err = loadfile(path)
    if not chunk then fail(err) end
    local ok, result = pcall(chunk, "EbonBuilds", addon)
    if not ok then fail(path .. ": " .. tostring(result)) end
end

loadAddonFile("core/EventHub.lua")
local eventOrder = {}
local firstToken
firstToken = addon.EventHub.On("BUILD_LIBRARY_CHANGED", function()
    eventOrder[#eventOrder + 1] = "first"
    addon.EventHub.Off(firstToken)
end, "first")
addon.EventHub.On("BUILD_LIBRARY_CHANGED", function()
    eventOrder[#eventOrder + 1] = "second"
end, "second")
addon.EventHub.Emit("BUILD_LIBRARY_CHANGED")
assertTrue(table.concat(eventOrder, ",") == "first,second", "EventHub skipped a listener after self-unsubscribe")
eventOrder = {}
addon.EventHub.Emit("BUILD_LIBRARY_CHANGED")
assertTrue(table.concat(eventOrder, ",") == "second", "EventHub retained an inactive listener")

loadAddonFile("core/WoWEvents.lua")
local wowOrder = {}
local wowFirst
wowFirst = addon.WoWEvents.On("PLAYER_LOGIN", function()
    wowOrder[#wowOrder + 1] = "first"
    addon.WoWEvents.Off(wowFirst)
end, "first")
addon.WoWEvents.On("PLAYER_LOGIN", function()
    wowOrder[#wowOrder + 1] = "second"
end, "second")
addon.WoWEvents.EmitForTests("PLAYER_LOGIN")
assertTrue(table.concat(wowOrder, ",") == "first,second", "WoWEvents skipped a listener after self-unsubscribe")
wowOrder = {}
addon.WoWEvents.EmitForTests("PLAYER_LOGIN")
assertTrue(table.concat(wowOrder, ",") == "second", "WoWEvents retained an inactive listener")


-- Combat-blocked scheduler jobs must be parked without keeping OnUpdate alive.
local currentTime = 0
local inCombat = true
function GetTime() return currentTime end
function debugprofilestop() return currentTime * 1000 end
function InCombatLockdown() return inCombat end
loadAddonFile("core/Scheduler.lua")
local schedulerFrame = frames[#frames]
local ranDeferred = false
addon.Scheduler.After("architecture.combatDeferred", 0, function()
    ranDeferred = true
end, addon.Scheduler.INTERACTIVE, false, "ArchitectureTest")
assertTrue(schedulerFrame.visible, "scheduler did not activate for queued work")
schedulerFrame.scripts.OnUpdate(schedulerFrame, 0)
assertTrue(not ranDeferred, "combat-blocked scheduler job ran in combat")
assertTrue(not schedulerFrame.visible, "parked combat job kept OnUpdate active")
inCombat = false
addon.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
assertTrue(schedulerFrame.visible, "PLAYER_REGEN_ENABLED did not wake parked work")
schedulerFrame.scripts.OnUpdate(schedulerFrame, 0)
assertTrue(ranDeferred, "parked scheduler job did not run after combat")

print("Architecture invariants passed: private namespace, centralized events (RegisterEvent ban), post-3.3.5a API ban, stable dispatch, native UI fallback, sync ownership, RefreshMapPanel forward-decl, and the `and nil or` toggle ban.")
