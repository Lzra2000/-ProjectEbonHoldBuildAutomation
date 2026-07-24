-- Runs every self-test registered via EbonBuilds.Debug.RegisterTest (see
-- core/Debug.lua) after loading the full addon in TOC order.
--
-- Separate stub from tests/test_load.lua on purpose: that stub's CreateFrame
-- discards SetScript/HookScript into a shared no-op, which is fine for a
-- pure load-order smoke test but can't verify that a handler actually ran
-- (or was actually caught) -- which is exactly what core/Debug.lua's
-- self-tests below need. This stub adds real per-frame script storage
-- instead, and is otherwise a deliberate near-duplicate of test_load.lua's
-- API surface so both files can evolve independently.

unpack = unpack or table.unpack

EbonBuilds = EbonBuilds or {}

local function Noop() end

local function NewObject()
    local scripts = {}
    return setmetatable({}, {
        __index = function(_, key)
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            if key == "SetScript" then
                return function(_, scriptType, handler) scripts[scriptType] = handler end
            elseif key == "GetScript" then
                return function(_, scriptType) return scripts[scriptType] end
            elseif key == "HookScript" then
                return function(_, scriptType, handler)
                    local previous = scripts[scriptType]
                    scripts[scriptType] = function(...)
                        if previous then previous(...) end
                        return handler(...)
                    end
                end
            elseif key == "CreateFontString" or key == "CreateTexture" or key == "GetStatusBarTexture" then
                return function() return NewObject() end
            elseif key == "GetChildren" or key == "GetRegions" then
                return function() return end
            elseif key == "GetWidth" then
                return function() return 600 end
            elseif key == "GetHeight" then
                return function() return 400 end
            elseif key == "GetCenter" then
                return function() return 400, 300 end
            elseif key == "GetMinMaxValues" then
                return function() return 0, 100 end
            elseif key == "GetValue" or key == "GetVerticalScrollRange" or key == "GetCursorPosition" then
                return function() return 0 end
            elseif key == "GetText" then
                return function() return "" end
            elseif key == "GetChecked" or key == "IsShown" then
                return function() return false end
            elseif key == "IsEnabled" then
                return function() return 1 end
            elseif key == "IsMouseOver" then
                return function() return false end
            elseif key == "GetStringHeight" or key == "GetStringWidth" then
                return function() return 10 end
            elseif key == "GetName" then
                return function() return nil end
            end
            return Noop
        end,
    })
end

function CreateFrame() return NewObject() end
UIParent = NewObject()
GameTooltip = NewObject()
DEFAULT_CHAT_FRAME = NewObject()
StaticPopupDialogs = {}
SlashCmdList = {}
UISpecialFrames = {}
CLASS_ICON_TCOORDS = {}

function RegisterAddonMessagePrefix() end
function hooksecurefunc() end
function PanelTemplates_TabResize() end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function PanelTemplates_EnableTab() end
function tinsert(t, value) table.insert(t, value) end
function strtrim(value) return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "") end
function strlower(value) return string.lower(tostring(value or "")) end
function GetSpellInfo(id) return "Spell " .. tostring(id), nil, "icon" end
function GetTalentTabInfo() return nil, nil, 0 end
function UnitName() return "Tester" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 80 end
function UnitGUID() return "GUID" end
function GetTime() return 0 end
function debugstack(level) return "selftest stack frame at level " .. tostring(level) end
local profileClock = 0
function debugprofilestop()
    profileClock = profileClock + 1
    return profileClock
end
function time() return 1 end
function date() return "2026-07-17 12:00:00" end
function GetChannelName() return 0 end
function JoinChannelByName() end
function SendAddonMessage() end
function GetItemInfo() return nil end
-- 3.3.5a auction class order (localized on real clients; English here for stubs).
function GetAuctionItemClasses()
    return "Weapon", "Armor", "Container", "Consumable", "Glyph",
        "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem",
        "Miscellaneous", "Quest"
end
function GetInventoryItemLink() return nil end
function GetContainerNumSlots() return 0 end
function GetContainerItemLink() return nil end
function GetContainerItemInfo() return nil end
function UseContainerItem() end
function IsShiftKeyDown() return false end
function GetCurrentKeyBoardFocus() return nil end
function ChatEdit_InsertLink() end
function IsInGuild() return false end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumPartyMembers() return 0 end
function GetNumRaidMembers() return 0 end
function GetRealmName() return "Realm" end
function IsLoggedIn() return true end
function GetLocale() return "enUS" end
function GetMoney() return 0 end
function GetNumTalentTabs() return 3 end
function GetNumTalents() return 0 end
function GetTalentInfo() return nil end
function LearnTalent() end
function InCombatLockdown() return false end
function GetAddOnMetadata() return "2.6" end
function PlaySound() end
function ReloadUI() end

local function Band(a, b)
    a, b = a or 0, b or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 and bbit == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

local function Bor(a, b)
    a, b = a or 0, b or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 or bbit == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

bit = { band = Band, bor = Bor }
ProjectEbonhold = {
    PerkDatabase = {},
    PerkService = {},
    PerkUI = {},
    PlayerRunService = {},
}
utils = {}
EbonBuildsDB = { builds = {} }
EbonBuildsCharDB = {}

local files = {}
for line in io.lines("EbonBuilds.toc") do
    -- Windows/WSL checkouts may use CRLF. io.lines removes the newline but
    -- retains the carriage return, so normalize it before matching paths.
    line = line:gsub("\r$", "")
    if line:match("^%S+%.lua$") then files[#files + 1] = line end
end

if #files == 0 then
    io.stderr:write("LOAD FAIL: EbonBuilds.toc contained no Lua paths after normalization\n")
    os.exit(1)
end

for _, file in ipairs(files) do
    local ok, err = pcall(function()
        local chunk, loadErr = loadfile(file)
        if not chunk then error(loadErr) end
        return chunk("EbonBuilds", EbonBuilds)
    end)
    if not ok then
        io.stderr:write("LOAD FAIL " .. file .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
end

-- Self-tests for core/Debug.lua itself. Modules can add their own via
-- EbonBuilds.Debug.RegisterTest(...) anywhere in their own file; these three
-- just prove the mechanism works before anything else relies on it.

EbonBuilds.Debug.RegisterTest("Debug.Protect catches an error instead of propagating it", function()
    local protected = EbonBuilds.Debug.Protect("selftest", function() error("boom") end)
    local ok = pcall(protected)
    if not ok then error("Protect() let the error propagate to the caller") end
    local errors = EbonBuilds.ErrorLog.GetAll()
    if #errors == 0 or not tostring(errors[1].message):find("boom", 1, true) then
        error("Protect() did not record the caught error in ErrorLog")
    end
end)

EbonBuilds.Debug.RegisterTest("Debug.ProtectScript auto-wraps handlers set after the call", function()
    local frame = NewObject()
    EbonBuilds.Debug.ProtectScript(frame, "selftest.frame")
    local calls = 0
    frame:SetScript("OnClick", function() calls = calls + 1; error("handler boom") end)
    local ok = pcall(frame:GetScript("OnClick"))
    if not ok then error("a ProtectScript-wrapped handler still propagated its error") end
    if calls ~= 1 then error("wrapped handler did not run") end
end)

EbonBuilds.Debug.RegisterTest("Debug.ProtectScript is idempotent on the same frame", function()
    local frame = NewObject()
    EbonBuilds.Debug.ProtectScript(frame, "selftest.frame")
    local firstSetScript = frame.SetScript
    EbonBuilds.Debug.ProtectScript(frame, "selftest.frame")
    if frame.SetScript ~= firstSetScript then
        error("calling ProtectScript twice wrapped the handler twice")
    end
end)

EbonBuilds.Debug.RegisterTest("Debug.Time records a slow call and still returns the result", function()
    local errorsBefore = #EbonBuilds.ErrorLog.GetAll()
    local timed = EbonBuilds.Debug.Time("selftest.slow", function(x) return x * 2 end, 0)
    local result = timed(21)
    if result ~= 42 then error("Time() did not pass through the wrapped function's return value") end
    if #EbonBuilds.ErrorLog.GetAll() ~= errorsBefore + 1 then
        error("Time() did not record a call exceeding its 0ms threshold")
    end
end)

EbonBuilds.Debug.RegisterTest("Debug.Time does not record a call under its threshold", function()
    local errorsBefore = #EbonBuilds.ErrorLog.GetAll()
    local timed = EbonBuilds.Debug.Time("selftest.fast", function() end, 999999)
    timed()
    if #EbonBuilds.ErrorLog.GetAll() ~= errorsBefore then
        error("Time() recorded a call that was under its threshold")
    end
end)

EbonBuilds.Debug.RegisterTest("Debug.Assert records on failure, not on success", function()
    local errorsBefore = #EbonBuilds.ErrorLog.GetAll()
    if EbonBuilds.Debug.Assert(true, "should not fire") ~= true then
        error("Assert(true, ...) did not return true")
    end
    if #EbonBuilds.ErrorLog.GetAll() ~= errorsBefore then
        error("Assert(true, ...) recorded an error despite the condition holding")
    end
    if EbonBuilds.Debug.Assert(false, "expected failure") ~= false then
        error("Assert(false, ...) did not return false")
    end
    if #EbonBuilds.ErrorLog.GetAll() ~= errorsBefore + 1 then
        error("Assert(false, ...) did not record to the Error Log")
    end
end)

EbonBuilds.Debug.RegisterTest("ProtectScript warns once per window on event spam, not once per call", function()
    local frame = NewObject()
    EbonBuilds.Debug.ProtectScript(frame, "selftest.spam")
    local statsBefore = EbonBuilds.Debug.GetStats().spamWarningCount
    frame:SetScript("OnEvent", function() end)
    local handler = frame:GetScript("OnEvent")
    for _ = 1, 150 do handler() end
    local warned = EbonBuilds.Debug.GetStats().spamWarningCount
    if warned ~= statsBefore + 1 then
        error("expected exactly one spam warning for 150 calls in one window, got " .. tostring(warned - statsBefore))
    end
end)

EbonBuilds.Debug.RegisterTest("ProtectScript does not spam-check OnUpdate", function()
    local frame = NewObject()
    EbonBuilds.Debug.ProtectScript(frame, "selftest.onupdate")
    local statsBefore = EbonBuilds.Debug.GetStats().spamWarningCount
    frame:SetScript("OnUpdate", function() end)
    local handler = frame:GetScript("OnUpdate")
    for _ = 1, 150 do handler() end
    local warned = EbonBuilds.Debug.GetStats().spamWarningCount
    if warned ~= statsBefore then
        error("OnUpdate should be exempt from spam detection, but a warning fired")
    end
end)

EbonBuilds.Debug.RegisterTest("ProtectScript(frame, source, true) exempts any script type from spam detection", function()
    local frame = NewObject()
    EbonBuilds.Debug.ProtectScript(frame, "selftest.exempt", true)
    local statsBefore = EbonBuilds.Debug.GetStats().spamWarningCount
    frame:SetScript("OnEvent", function() end)
    local handler = frame:GetScript("OnEvent")
    for _ = 1, 150 do handler() end
    local warned = EbonBuilds.Debug.GetStats().spamWarningCount
    if warned ~= statsBefore then
        error("spamExempt=true should exempt OnEvent too, but a warning fired")
    end
end)

EbonBuilds.Debug.RegisterTest("Debug.CheckSpam is a shared counter distinct callers can reuse", function()
    local key = "selftest.sharedcounter." .. tostring({})
    local crossed = false
    for i = 1, 150 do
        if EbonBuilds.Debug.CheckSpam(key) then crossed = true end
    end
    if not crossed then error("CheckSpam never returned true across 150 calls on the same key") end
end)

EbonBuilds.Debug.RegisterTest("WoWEvents.On: non-exempt listener trips shared spam detection", function()
    local statsBefore = EbonBuilds.Debug.GetStats().spamWarningCount
    EbonBuilds.WoWEvents.On("SELFTEST_SPAM_EVENT", function() end, "selftest")
    for _ = 1, 150 do EbonBuilds.WoWEvents.EmitForTests("SELFTEST_SPAM_EVENT") end
    local warned = EbonBuilds.Debug.GetStats().spamWarningCount
    if warned ~= statsBefore + 1 then
        error("expected exactly one spam warning for 150 emits, got " .. tostring(warned - statsBefore))
    end
end)

EbonBuilds.Debug.RegisterTest("WoWEvents.On: spamExempt=true listener does not trip spam detection", function()
    local statsBefore = EbonBuilds.Debug.GetStats().spamWarningCount
    EbonBuilds.WoWEvents.On("SELFTEST_SPAM_EXEMPT_EVENT", function() end, "selftest", false, true)
    for _ = 1, 150 do EbonBuilds.WoWEvents.EmitForTests("SELFTEST_SPAM_EXEMPT_EVENT") end
    local warned = EbonBuilds.Debug.GetStats().spamWarningCount
    if warned ~= statsBefore then
        error("spamExempt=true listener should never trip spam detection, but a warning fired")
    end
end)

EbonBuilds.Debug.RegisterTest("Theme.CreateButton buttons are auto-protected", function()
    local btn = EbonBuilds.Theme.CreateButton(NewObject())
    local ok = pcall(function()
        btn:SetScript("OnClick", function() error("click boom") end)
        btn:GetScript("OnClick")()
    end)
    if not ok then error("a Theme.CreateButton OnClick handler was not auto-protected") end
end)

EbonBuilds.Debug.RegisterTest("ErrorLog.Protect captures a stack trace via debugstack", function()
    local protected = EbonBuilds.ErrorLog.Protect("selftest.stacktrace", function() error("boom with stack") end)
    pcall(protected)
    local errors = EbonBuilds.ErrorLog.GetAll()
    if not errors[1] or not errors[1].stack then
        error("Protect() did not capture a stack trace on the most recent error")
    end
    if not errors[1].stack:find("selftest stack frame", 1, true) then
        error("captured stack did not come from the stubbed debugstack()")
    end
    local compact = EbonBuilds.ErrorLog.GetText()
    if compact:find("selftest stack frame", 1, true) then
        error("GetText() with no argument should not include stack traces by default")
    end
    local verbose = EbonBuilds.ErrorLog.GetText(true)
    if not verbose:find("selftest stack frame", 1, true) then
        error("GetText(true) should include stack traces")
    end
end)

-- core/Modules.lua's Start() only catches an unknown/circular dependency
-- at real runtime, module by module, as each one actually gets started --
-- a typo'd dependency name could otherwise go unnoticed until a player
-- happens to load the addon. EbonBuilds.Start() runs the real
-- RegisterModules() registration (core/Init.lua) against the real
-- module list, so this checks the actual production graph, not a
-- hand-written stand-in for it.
EbonBuilds.Debug.RegisterTest("Module dependency graph has no unknown or circular dependencies", function()
    if not (EbonBuilds.Start and EbonBuilds.Modules and EbonBuilds.Modules.ValidateGraph) then
        error("EbonBuilds.Start/Modules.ValidateGraph not available -- can't validate the module graph")
    end
    EbonBuilds.Start()
    local result = EbonBuilds.Modules.ValidateGraph()
    if not result.ok then
        error("module dependency graph problems:\n  " .. table.concat(result.problems, "\n  "))
    end
end)

local summary = EbonBuilds.Debug.RunSelfTests()
for _, result in ipairs(summary.results) do
    if not result.ok then
        io.stderr:write("SELFTEST FAIL: " .. result.name .. " -- " .. tostring(result.err) .. "\n")
    end
end
if summary.failed > 0 then
    io.stderr:write(summary.failed .. "/" .. summary.total .. " self-tests failed.\n")
    os.exit(1)
end
print(summary.passed .. "/" .. summary.total .. " self-tests passed.")
