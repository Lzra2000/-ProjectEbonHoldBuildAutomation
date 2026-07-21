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
        assertTrue(not text:find(":RegisterEvent%s*%(", 1), path .. " registers a Blizzard event outside WoWEvents")
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

print("Architecture invariants passed: private namespace, centralized events, stable dispatch, native UI fallback, and sync ownership.")
