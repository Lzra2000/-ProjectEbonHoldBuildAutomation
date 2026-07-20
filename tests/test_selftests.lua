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
function time() return 1 end
function date() return "2026-07-17 12:00:00" end
function GetChannelName() return 0 end
function JoinChannelByName() end
function SendAddonMessage() end
function GetItemInfo() return nil end
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
    if line:match("%.lua$") then files[#files + 1] = line end
end

for _, file in ipairs(files) do
    local ok, err = pcall(dofile, file)
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

EbonBuilds.Debug.RegisterTest("Theme.CreateButton buttons are auto-protected", function()
    local btn = EbonBuilds.Theme.CreateButton(NewObject())
    local ok = pcall(function()
        btn:SetScript("OnClick", function() error("click boom") end)
        btn:GetScript("OnClick")()
    end)
    if not ok then error("a Theme.CreateButton OnClick handler was not auto-protected") end
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
