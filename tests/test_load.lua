-- TOC-order smoke test. It stubs the WoW 3.3.5 API just enough to verify that
-- every addon module loads in the shipped order without file-scope errors.

unpack = unpack or table.unpack

EbonBuilds = EbonBuilds or {}

EbonBuildsDB = EbonBuildsDB or {}
EbonBuildsCharDB = EbonBuildsCharDB or {}

local function Noop() end

-- Optional development-only hooks used by tests/profile_memory.lua.  The
-- ordinary smoke test leaves this nil, so its behavior and allocation profile
-- stay unchanged.
local TestMemoryProfile = rawget(_G, "EBONBUILDS_TEST_MEMORY_PROFILE")
local function MemoryProfileCall(method, ...)
    local callback = TestMemoryProfile and TestMemoryProfile[method]
    if callback then return callback(TestMemoryProfile, ...) end
end

local function NormalizeNewlines(value)
    return tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
end
local function NewObject(kind)
    local object
    object = setmetatable({}, {
        __index = function(_, key)
            -- Frame-private state should behave like a real Lua table: an
            -- unset `_field` is nil, not a callable WoW API method.
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            if key == "loadingLabel" or key == "emptyLabel" then return nil end
            if key == "CreateFontString" then
                return function() return NewObject("FontString") end
            elseif key == "CreateTexture" then
                return function() return NewObject("Texture") end
            elseif key == "CreateAnimationGroup" then
                return function() return NewObject("AnimationGroup") end
            elseif key == "GetStatusBarTexture" then
                return function() return NewObject("StubStatusBarTexture") end
            elseif key == "SetScript" and TestMemoryProfile then
                return function(self, scriptName, callback)
                    MemoryProfileCall("SetScript", self, scriptName, callback)
                end
            elseif key == "GetScript" and TestMemoryProfile then
                return function(self, scriptName)
                    return MemoryProfileCall("GetScript", self, scriptName)
                end
            elseif key == "Show" and TestMemoryProfile then
                return function(self) MemoryProfileCall("SetShown", self, true) end
            elseif key == "Hide" and TestMemoryProfile then
                return function(self) MemoryProfileCall("SetShown", self, false) end
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
            elseif key == "IsShown" and TestMemoryProfile then
                return function(self) return MemoryProfileCall("IsShown", self) end
            elseif key == "GetChecked" or key == "IsShown" then
                return function() return false end
            elseif key == "GetStringHeight" or key == "GetStringWidth" then
                return function() return 10 end
            elseif key == "GetName" then
                return function() return nil end
            end
            return Noop
        end,
    })
    MemoryProfileCall("ObjectCreated", kind or "Object")
    return object
end

function CreateFrame(frameType) return NewObject("Frame:" .. tostring(frameType or "Frame")) end
UIParent = NewObject("External:UIParent")
GameTooltip = NewObject("External:GameTooltip")
DEFAULT_CHAT_FRAME = NewObject("External:ChatFrame")
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

bit = { band = Band, bor = Bor, bnot = function(value) return 4294967295 - (tonumber(value) or 0) end }
ProjectEbonhold = {
    PerkDatabase = {},
    PerkService = {},
    PerkUI = {},
    PlayerRunService = {},
}
utils = {}

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
    MemoryProfileCall("BeforeFile", file)
    local ok, err = pcall(function()
        local chunk, loadErr = loadfile(file)
        if not chunk then error(loadErr) end
        MemoryProfileCall("AfterCompile", file)
        return chunk("EbonBuilds", EbonBuilds)
    end)
    if not ok then
        io.stderr:write("LOAD FAIL " .. file .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    MemoryProfileCall("AfterExecute", file)
end

if TestMemoryProfile and TestMemoryProfile.loadOnly then
    MemoryProfileCall("AfterLoad", files)
    return
end

local uiContracts = {
    { "Theme.SetInputState", EbonBuilds.Theme and EbonBuilds.Theme.SetInputState },
    { "Theme.CreateTab", EbonBuilds.Theme and EbonBuilds.Theme.CreateTab },
    { "Theme.CreatePageHeader", EbonBuilds.Theme and EbonBuilds.Theme.CreatePageHeader },
    { "Theme.CreateFilterChip", EbonBuilds.Theme and EbonBuilds.Theme.CreateFilterChip },
    { "Theme.CreateEmptyState", EbonBuilds.Theme and EbonBuilds.Theme.CreateEmptyState },
    { "Theme.CreateDropdown", EbonBuilds.Theme and EbonBuilds.Theme.CreateDropdown },
    { "Theme.SkinSlider", EbonBuilds.Theme and EbonBuilds.Theme.SkinSlider },
    { "Theme.CreateScrollBar", EbonBuilds.Theme and EbonBuilds.Theme.CreateScrollBar },
    { "Theme.BindScrollWheel", EbonBuilds.Theme and EbonBuilds.Theme.BindScrollWheel },
    { "Theme.ScrollByMouseWheel", EbonBuilds.Theme and EbonBuilds.Theme.ScrollByMouseWheel },
    { "Theme.CreateHorizontalScrollBar", EbonBuilds.Theme and EbonBuilds.Theme.CreateHorizontalScrollBar },
    { "Filters.SetResultCount", EbonBuilds.Filters and EbonBuilds.Filters.SetResultCount },
    { "Filters.LearnedOnly", EbonBuilds.Filters and EbonBuilds.Filters.LearnedOnly },
    { "EchoTable.ValidateAndCommitAll", EbonBuilds.EchoTable and EbonBuilds.EchoTable.ValidateAndCommitAll },
    { "EchoTable.NotifyWeightChanged", EbonBuilds.EchoTable and EbonBuilds.EchoTable.NotifyWeightChanged },
    { "EchoTable.NotifyPolicyChanged", EbonBuilds.EchoTable and EbonBuilds.EchoTable.NotifyPolicyChanged },
    { "EchoTable.ApplyPolicyToFiltered", EbonBuilds.EchoTable and EbonBuilds.EchoTable.ApplyPolicyToFiltered },
    { "EchoPolicy.Resolve", EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.Resolve },
    { "EchoPolicy.SelectedNames", EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.SelectedNames },
    { "BonusView.ValidateAndCommitAll", EbonBuilds.BonusView and EbonBuilds.BonusView.ValidateAndCommitAll },
    { "BuildTabs.ShowTab", EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ShowTab },
    { "BuildTabs.MarkDirty", EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.MarkDirty },
    { "BuildTabs.ClearDirty", EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ClearDirty },
    { "EchoPicker.Show", EbonBuilds.EchoPicker and EbonBuilds.EchoPicker.Show },
    { "SettingsView.Refresh", EbonBuilds.SettingsView and EbonBuilds.SettingsView.Refresh },
    { "SettingsView.ValidateAndCommitAll", EbonBuilds.SettingsView and EbonBuilds.SettingsView.ValidateAndCommitAll },
    { "MainWindow.RefreshContext", EbonBuilds.MainWindow and EbonBuilds.MainWindow.RefreshContext },
    { "MainWindow.SetPageContext", EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetPageContext },
    { "MainWindow.SetDirtyState", EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetDirtyState },
    { "BuildList.SetSelectedNavigation", EbonBuilds.BuildList and EbonBuilds.BuildList.SetSelectedNavigation },
    { "BuildOverview._MissingViewDefinition", EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._MissingViewDefinition },
    { "BuildOverview._BuildWeightedEchoSet", EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._BuildWeightedEchoSet },
    { "StatsView.Refresh", EbonBuilds.StatsView and EbonBuilds.StatsView.Refresh },
    { "StatsView.SetView", EbonBuilds.StatsView and EbonBuilds.StatsView.SetView },
    { "EWL.Generate", EbonBuilds.EWL and EbonBuilds.EWL.Generate },
    { "EWL.ShowExportDialog", EbonBuilds.EWL and EbonBuilds.EWL.ShowExportDialog },
    { "SessionHistory.OpenWithFilters", EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OpenWithFilters },
    { "ManualTraining.SuggestWeightAdjustments", EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.SuggestWeightAdjustments },
    { "Calibration.GetAppearanceStats", EbonBuilds.Calibration and EbonBuilds.Calibration.GetAppearanceStats },
    { "Calibration.SyncAppearanceNow", EbonBuilds.Calibration and EbonBuilds.Calibration.SyncAppearanceNow },
    { "EchoPerformance.SyncNow", EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.SyncNow },
    { "ShowcaseView.Show", EbonBuilds.ShowcaseView and EbonBuilds.ShowcaseView.Show },
}
for _, contract in ipairs(uiContracts) do
    if type(contract[2]) ~= "function" then
        io.stderr:write("UI CONTRACT FAIL: " .. contract[1] .. " is missing\n")
        os.exit(1)
    end
end

print("Loaded " .. #files .. " TOC Lua files successfully.")
print("Verified " .. #uiContracts .. " UI contracts successfully.")


-- Polish diacritics (issue #40): no stock 3.3.5a client font contains the
-- Latin-Extended-A glyphs, so plPL strings must fold ą ć ę ł ń ś ź ż to
-- ASCII instead of letting the client draw "?" for each. The stub widgets
-- report the same GetStringWidth() for every probe text, which is exactly
-- what a font without those glyphs reports (missing glyphs all render as
-- the "?" glyph), so the folded form is what EbonBuilds.L must return here.
do
    if not EbonBuilds.Locale.SetLocale("plPL") then
        io.stderr:write("POLISH FOLD FAIL: plPL is not a supported locale\n")
        os.exit(1)
    end
    local expectations = {
        ["Character"] = "Postac",                       -- Postać
        ["Save build"] = "Zapisz build",                -- no diacritics: unchanged
        [" · Autopilot uses last saved settings"] =
            " · Autopilot uzywa ostatnio zapisanych ustawien",  -- używa/ustawień
    }
    for key, expected in pairs(expectations) do
        local got = EbonBuilds.L[key]
        if got ~= expected then
            io.stderr:write(string.format("POLISH FOLD FAIL: L[%q] = %q, expected %q\n",
                key, tostring(got), expected))
            os.exit(1)
        end
    end
    if EbonBuilds.L["No such key anywhere"] ~= "No such key anywhere" then
        io.stderr:write("POLISH FOLD FAIL: unknown keys must fall back to the English key\n")
        os.exit(1)
    end
    EbonBuilds.Locale.SetLocale("enUS")
    if EbonBuildsDB and EbonBuildsDB.globalSettings then
        EbonBuildsDB.globalSettings.localeOverride = nil
    end
    print("Verified Polish diacritic ASCII fallback for fonts without the glyphs.")
end


-- Hover cleanup must never overwrite a view-owned text color. Earlier the
-- shared button reset forced every ordinary button label to gold on OnLeave,
-- so muted navigation and action labels stayed yellow after the pointer left.
do
    local color = { 0.31, 0.47, 0.63, 0.91 }
    local label = {
        SetTextColor = function(_, r, g, b, a) color = { r, g, b, a } end,
        GetTextColor = function() return color[1], color[2], color[3], color[4] end,
    }
    local button = {
        _tabSelected = nil,
        IsEnabled = function() return 1 end,
        GetFontString = function() return label end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
    }
    EbonBuilds.Theme.ResetButtonVisual(button)
    if math.abs(color[1] - 0.31) > 0.001 or math.abs(color[2] - 0.47) > 0.001
        or math.abs(color[3] - 0.63) > 0.001 or math.abs(color[4] - 0.91) > 0.001 then
        io.stderr:write("HOVER RESET FAIL: ordinary button text color was overwritten\n")
        os.exit(1)
    end

    local hiddenReset = 0
    local scripts = {}
    local frame = {
        HookScript = function(_, script, handler) scripts[script] = handler end,
    }
    EbonBuilds.Theme.BindHoverReset(frame, function() hiddenReset = hiddenReset + 1 end)
    if not scripts.OnHide then
        io.stderr:write("HOVER RESET FAIL: no OnHide cleanup was installed\n")
        os.exit(1)
    end
    scripts.OnHide(frame)
    if hiddenReset ~= 1 then
        io.stderr:write("HOVER RESET FAIL: hidden widget did not clear its hover state\n")
        os.exit(1)
    end
end
print("Verified hover cleanup preserves view-owned text colors and runs on hidden widgets.")

-- WoW 3.3.5a embeds Lua 5.1, which rejects functions with more than 60
-- upvalues. Keep the Logbook UI split into small builders so a future visual
-- refactor cannot make the entire module fail to compile in-game.
do
    local builders = EbonBuilds.SessionHistory and EbonBuilds.SessionHistory._UIBuildFunctions or {}
    for name, fn in pairs(builders) do
        local count = 0
        while debug.getupvalue(fn, count + 1) do count = count + 1 end
        if count > 60 then
            io.stderr:write(string.format("LUA 5.1 UPVALUE FAIL: SessionHistory.%s has %d upvalues\n", name, count))
            os.exit(1)
        end
    end
end
print("Verified SessionHistory builders stay below the Lua 5.1 upvalue limit.")

-- Conditional Echo policies must remain visible in the Echo table and must
-- be enforced as hard automation rules rather than score-only suggestions.
do
    local requiredSources = {
        { "EbonBuilds.toc", "modules/build/EchoPolicy.lua" },
        { "modules/ui/EchoTableRows.lua", "icon = 40, quality = 70, protect = 84, policy = 104, rank = 56" },
        { "modules/ui/EchoTableRows.lua", "CreatePolicyDropdown(row)" },
        { "modules/ui/EchoTable.lua", 'CreateStaticHeader(parent, "Policy")' },
        { "modules/ui/Filters.lua", "CreatePolicyDropdown(bar)" },
        { "modules/ui/Filters.lua", "CreateBulkPolicyDropdown(bar)" },
        { "modules/automation/Automation.lua", "not s.policyBlocked" },
        { "modules/automation/Automation.lua", 'return false, nil, "policy_blocked"' },
        { "modules/session/Session.lua", 'decision.reasonCode = "ECHO_POLICY_BANISH"' },
        { "modules/session/Session.lua", "eligibilitySchema = 1" },
        { "modules/session/Session.lua", 'decision.reasonCode = "ECHO_BAN_LIST"' },
    }
    for _, definition in ipairs(requiredSources) do
        local file = assert(io.open(definition[1], "r"))
        local source = NormalizeNewlines(file:read("*a"))
        file:close()
        if not source:find(definition[2], 1, true) then
            io.stderr:write("ECHO POLICY UI FAIL: missing " .. definition[2] .. " in " .. definition[1] .. "\n")
            os.exit(1)
        end
    end
end
print("Verified conditional Echo policy controls and hard automation enforcement.")

-- The policy controls must not force Echo names into an unreadably narrow,
-- single-line column. Keep the fixed columns compact and reserve two lines for
-- the complete visible Echo name.
do
    local file = assert(io.open("modules/ui/EchoTableRows.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        "icon = 40, quality = 70, protect = 84, policy = 104, rank = 56",
        "icon = 38, quality = 64, protect = 76, policy = 92, rank = 52",
        "InstallColumnMetrics(compact and COMPACT_COLUMNS or STANDARD_COLUMNS)",
        "Rows.ROW_HEIGHT     = 60",
        "row.nameLabel:SetHeight(30)",
        "row.nameLabel:SetWordWrap(true)",
        "row.nameLabel:SetNonSpaceWrap(false)",
        "label:SetPoint(\"LEFT\", frame, \"LEFT\", 3, 0)",
        "label:SetPoint(\"RIGHT\", frame, \"RIGHT\", -3, 0)",
    }
    for _, fragment in ipairs(required) do
        if not source:find(fragment, 1, true) then
            io.stderr:write("ECHO NAME LAYOUT FAIL: missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
end
print("Verified long Echo names receive a compact, two-line table column.")

-- The compact Max value beneath each Echo name must represent the same final
-- total score shown in the rank columns, not merely the largest raw weight.
do
    local file = assert(io.open("modules/ui/EchoTableRows.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        "local function MaxTotalScore(entry)",
        "EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)",
        'row.statusLabel:SetText(string.format("Max %d", maxScore))',
        'row.statusLabel:SetText(string.format("Protected · Max %d", maxScore))',
    }
    for _, fragment in ipairs(required) do
        if not source:find(fragment, 1, true) then
            io.stderr:write("ECHO MAX SCORE FAIL: missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
    if source:find("local function MaxWeight(entry)", 1, true) then
        io.stderr:write("ECHO MAX SCORE FAIL: status still derives from raw weight\n")
        os.exit(1)
    end
end
print("Verified Echo row Max values use final total score rather than raw weight.")

-- The Echo sort control represents the complete Echo column, including the
-- icon gutter, and must remain inside the shared table header bounds.
do
    local file = assert(io.open("modules/ui/EchoTable.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        'headerFrames.name:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -3)',
        'headerFrames.name:SetPoint("TOPRIGHT", headerFrames.quality, "TOPLEFT", -2, 0)',
    }
    for _, fragment in ipairs(required) do
        if not source:find(fragment, 1, true) then
            io.stderr:write("ECHO HEADER LAYOUT FAIL: missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
end
print("Verified the Echo name sort control fills the complete header column.")

-- The run selector must remain a bounded virtualized browser. A generic
-- dropdown creates one button per session and can cover the entire screen.
do
    local file = assert(io.open("modules/ui/SessionHistory.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    if not source:find("local RUN_BROWSER_VISIBLE_ROWS = 8", 1, true)
        or not source:find("CreateRunBrowserRow", 1, true)
        or not source:find("Search level, date, duration, or events", 1, true)
        or source:find('Theme.CreateDropdown(topPanel, 500, "Choose a run"', 1, true) then
        io.stderr:write("RUN BROWSER FAIL: Logbook run selection is not using the bounded recycled-row browser\n")
        os.exit(1)
    end
end
print("Verified the Logbook run browser is fixed-height and virtualized.")

-- The decision inspector's offer cards must sit below the evidence text.
-- Anchoring the cards to the panel bottom caused flags/resources to render
-- underneath the Echo icons on compact windows.
do
    local file = assert(io.open("modules/ui/SessionHistory.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    if not source:find("local DETAIL_H = 184", 1, true)
        or not source:find('card:SetPoint("TOPLEFT", detailFlags, "BOTTOMLEFT", 0, -8)', 1, true)
        or not source:find('detailResources:SetPoint("TOPLEFT", detailFlags, "TOPRIGHT", 15, 0)', 1, true) then
        io.stderr:write("DECISION INSPECTOR FAIL: offer cards can overlap the evidence text\n")
        os.exit(1)
    end
end
print("Verified Decision Inspector offer cards stay below the evidence text.")

-- Logbook filter controls share one readable height and enough horizontal room
-- for their labels. Narrow 22-24 px controls made the search placeholder and
-- dropdown/button text appear clipped at common UI scales.
do
    local file = assert(io.open("modules/ui/SessionHistory.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        "local FILTER_TOOLBAR_H = 30",
        "local FILTER_CONTROL_H = 26",
        "local FILTER_SEARCH_W = 210",
        "local FILTER_SOURCE_W = 104",
        'placeholder:SetPoint("RIGHT", edit, "RIGHT", -2, 0)',
        'actionDropdown:SetHeight(FILTER_CONTROL_H)',
        'sourceDropdown:SetHeight(FILTER_CONTROL_H)',
        'importantButton:SetSize(FILTER_IMPORTANT_W, FILTER_CONTROL_H)',
        'groupButton:SetSize(FILTER_GROUP_W, FILTER_CONTROL_H)',
    }
    for _, token in ipairs(required) do
        if not source:find(token, 1, true) then
            io.stderr:write("LOGBOOK FILTER LAYOUT FAIL: missing " .. token .. "\n")
            os.exit(1)
        end
    end
end
print("Verified Logbook search and filter controls use unclipped shared dimensions.")

-- The collapsed Autopilot scroll child must expose both addon-wide feature
-- toggles and the advanced-controls button without clipping.
do
    local file = assert(io.open("modules/ui/SettingsView.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        "local ADVANCED_TOGGLE_H = 26",
        "local COLLAPSED_HEIGHT = 732",
        'BuildGlobalFeaturesPanel(scrollChild, -540)',
        'Theme.CreateCheckbox(panel, "Sync chat messages")',
        'Theme.CreateCheckbox(panel, "Tome Atlas map integration")',
        "advancedButton:SetSize(190, ADVANCED_TOGGLE_H)",
        'advancedButton:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -692)',
    }
    for _, token in ipairs(required) do
        if not source:find(token, 1, true) then
            io.stderr:write("AUTOPILOT TOGGLE LAYOUT FAIL: missing " .. token .. "\n")
            os.exit(1)
        end
    end
end
print("Verified the Settings tab exposes addon-wide feature toggles and the advanced-controls button.")

-- All long-form panels use the shared 3.3.5a-safe wheel router. It must
-- move away from both boundaries, and the affected panels must bind their
-- mouse-enabled content trees so nested cards/buttons cannot trap the wheel.
do
    local nextValue = EbonBuilds.Theme and EbonBuilds.Theme._NextWheelScrollValue
    if type(nextValue) ~= "function" then
        io.stderr:write("SHARED SCROLL FAIL: wheel-value helper is missing\n")
        os.exit(1)
    end
    if nextValue(100, 1, 0, 100, 34) ~= 66 then
        io.stderr:write("SHARED SCROLL FAIL: scrolling up from the bottom did not reduce the offset\n")
        os.exit(1)
    end
    if nextValue(0, -1, 0, 100, 34) ~= 34 then
        io.stderr:write("SHARED SCROLL FAIL: scrolling down from the top did not increase the offset\n")
        os.exit(1)
    end
    if nextValue(100, -1, 0, 100, 34) ~= 100 or nextValue(0, 1, 0, 100, 34) ~= 0 then
        io.stderr:write("SHARED SCROLL FAIL: wheel offsets are not clamped at the list boundaries\n")
        os.exit(1)
    end

    local requiredBindings = {
        { "modules/ui/SessionHistory.lua", "Theme.BindScrollWheel(logScroll, logBar" },
        { "modules/ui/SessionHistory.lua", "Theme.BindScrollWheel(scroll, bar, 18, edit)" },
        { "modules/ui/SettingsView.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar" },
        { "modules/ui/StatsView.lua", "Theme.BindScrollWheel(recScroll, recBar" },
        { "modules/ui/StatsView.lua", "Theme.BindScrollWheel(echoScroll, echoBar, 36, echoChild)" },
        { "modules/ui/BuildOverview.lua", "Theme.BindScrollWheel(scroll, bar, 16, child)" },
        { "modules/ui/BuildOverview.lua", "Theme.BindScrollWheel(descScroll, descBar, 20, descChild)" },
        { "modules/ui/BuildForm.lua", "Theme.BindScrollWheel(scroll, descriptionScrollBar, 28, box)" },
        { "modules/ui/BonusView.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar, 24, scrollChild)" },
        { "modules/ui/EchoPicker.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar, ROW_HEIGHT, scrollChild)" },
        { "modules/ui/PublicBuildsView.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar, 40, scrollChild)" },
        { "modules/ui/TomeAtlasView.lua", "Theme.BindScrollWheel(pickerScroll, pickerBar, 20, pickerChild)" },
        { "modules/ui/ShowcaseView.lua", "Theme.BindScrollWheel(scroll, bar, 20, child)" },
        { "modules/ui/FAQView.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar, 32, scrollChild)" },
        { "modules/ui/AffixView.lua", "Theme.BindSliderWheel(f, scrollBar, 1, scrollChild)" },
        { "modules/ui/BuildList.lua", "Theme.BindSliderWheel(scrollFrame, scrollBar, 42, scrollChild)" },
        { "modules/ui/EchoTable.lua", "Theme.BindSliderWheel(sf, bar, ROW_HEIGHT, scrollChild)" },
        { "modules/ui/TomeAtlasView.lua", "Theme.BindSliderWheel(f, scrollBar, 1, scrollChild)" },
    }
    for _, definition in ipairs(requiredBindings) do
        local file = assert(io.open(definition[1], "r"))
        local source = NormalizeNewlines(file:read("*a"))
        file:close()
        if not source:find(definition[2], 1, true) then
            io.stderr:write("SHARED SCROLL FAIL: content-tree wheel routing is missing in " .. definition[1] .. "\n")
            os.exit(1)
        end
    end

    local overviewFile = assert(io.open("modules/ui/BuildOverview.lua", "r"))
    local overviewSource = NormalizeNewlines(overviewFile:read("*a"))
    overviewFile:close()
    if not overviewSource:find('descScroll:SetVerticalScroll(value)', 1, true)
        or overviewSource:find('descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, value)', 1, true) then
        io.stderr:write("SHARED SCROLL FAIL: build description still moves its child manually instead of the native offset\n")
        os.exit(1)
    end

    local themeFile = assert(io.open("modules/ui/Theme.lua", "r"))
    local themeSource = NormalizeNewlines(themeFile:read("*a"))
    themeFile:close()
    if not themeSource:find("function T.BindSliderWheel", 1, true) then
        io.stderr:write("SHARED SCROLL FAIL: virtualized lists do not share the boundary-safe wheel router\n")
        os.exit(1)
    end

    local allowedDirectWheel = {
        ["modules/ui/BuildWizard.lua"] = true, -- mouse-only scroller; no visible scrollbar
        ["modules/ui/SessionHistory.lua"] = true, -- recycled timeline uses its own buffered renderer
        ["modules/ui/Theme.lua"] = true, -- shared router implementation
    }
    for _, file in ipairs(files) do
        if file:match("^modules/ui/") and not allowedDirectWheel[file] then
            local handle = assert(io.open(file, "r"))
            local source = NormalizeNewlines(handle:read("*a"))
            handle:close()
            if source:find('SetScript("OnMouseWheel"', 1, true) then
                io.stderr:write("SHARED SCROLL FAIL: ad-hoc mouse-wheel logic remains in " .. file .. "\n")
                os.exit(1)
            end
        end
    end
end
print("Verified shared boundary-safe scrolling across standard content panels and nested controls.")

-- Decision Inspector resources should use readable names and ASCII-safe
-- change summaries instead of compressed B/R/F transitions with an arrow
-- glyph that is not supported by every 3.3.5a client font.
do
    local formatResources = EbonBuilds.SessionHistory and EbonBuilds.SessionHistory._ResourceDisplayText
    if type(formatResources) ~= "function" then
        io.stderr:write("DECISION RESOURCE FAIL: resource display formatter is missing\n")
        os.exit(1)
    end
    local text = formatResources(
        { ban = 15, reroll = 15, freeze = 9 },
        { ban = 15, reroll = 14, freeze = 9 }
    )
    if not text:find("Used: 1 Reroll", 1, true)
        or not text:find("Banish", 1, true)
        or not text:find("Reroll", 1, true)
        or not text:find("Freeze", 1, true)
        or text:find("→", 1, true) then
        io.stderr:write("DECISION RESOURCE FAIL: resource state is not readable or ASCII-safe\n")
        os.exit(1)
    end
end
print("Verified readable Decision Inspector resource changes and remaining charges.")

-- The global settings popup must never depend on post-3.3.5 SetShown,
-- must stage edits until Save, and must expose a visible error fallback rather
-- than leaving the user with an empty panel when one category fails.
do
    local file = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local required = {
        'popup:SetSize(640, 520)',
        'popup:SetClampedToScreen(true)',
        'local function ReadSavedDraft()',
        'local function CountDirtyFields()',
        'local function ShowSettingsErrorState(err)',
        'local ok, err = pcall(builder, panel)',
        'Theme.BindScrollWheel(settingsScroll, settingsScrollBar, 32, scrollChild)',
        'closeBtn:SetScript("OnClick", CancelAndHide)',
        'EbonBuildsGlobalSettingsPopup',
        'No unsaved changes',
    }
    for _, fragment in ipairs(required) do
        if not source:find(fragment, 1, true) then
            io.stderr:write("SETTINGS POPUP FAIL: missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
    if source:find('panel:SetShown', 1, true) then
        io.stderr:write("SETTINGS POPUP FAIL: settings still relies on SetShown instead of 3.3.5-safe Show/Hide\n")
        os.exit(1)
    end
    if source:find('EbonBuilds.Locale.SetLocale(entry.code)', 1, true) then
        io.stderr:write("SETTINGS POPUP FAIL: language selection is still applied before Save\n")
        os.exit(1)
    end
end
print("Verified staged, defensive, 3.3.5-safe global Settings rendering.")

-- EWL export is available from the build overview and the Settings popup.
do
    local overviewFile = assert(io.open("modules/ui/BuildOverview.lua", "r"))
    local overviewSource = NormalizeNewlines(overviewFile:read("*a"))
    overviewFile:close()
    local mainFile = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local mainSource = NormalizeNewlines(mainFile:read("*a"))
    mainFile:close()
    if not overviewSource:find("Export EWL", 1, true) or not overviewSource:find("EWL.ShowExportDialog", 1, true) then
        io.stderr:write("EWL UI FAIL: build overview export action is missing\n")
        os.exit(1)
    end
    if not mainSource:find("EWL.ShowExportDialog", 1, true) then
        io.stderr:write("EWL SETTINGS FAIL: Settings popup export action is missing\n")
        os.exit(1)
    end
end
print("Verified EWL generation controls and Settings integration.")

-- Every /ebb subcommand removed when slash commands were consolidated into
-- the Settings popup must have a real replacement control there, and the
-- dispatcher itself must no longer branch on any of the old subcommand
-- strings (a regression guard against silently reintroducing one without
-- also removing it from Settings, ending up with the same feature in two
-- places again).
do
    local file = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()

    local mustContain = {
        "EbonBuilds.DebugLog.SetEnabled",  "EbonBuilds.DebugLog.ShowWindow",
        "EbonBuilds.ClickTrace.SetEnabled", "EbonBuilds.ClickTrace.ShowWindow",
        "EbonBuilds.ErrorLog.ShowWindow",
        "EbonBuilds.Calibration.ShowWindow",
        "EbonBuilds.ShowcaseView.Show",
        'EbonBuilds.ViewRouter.Show("tomeAtlas")',
        'EbonBuilds.ViewRouter.Show("affixes")',
        "EbonBuilds.EWL.ShowExportDialog",
        "EbonBuilds.ManualTraining.Clear",
        "EbonBuilds.Locale.SetLocale",
    }
    for _, needle in ipairs(mustContain) do
        if not source:find(needle, 1, true) then
            io.stderr:write("SETTINGS MIGRATION FAIL: Settings popup is missing a control for " .. needle .. "\n")
            os.exit(1)
        end
    end

    -- Isolate just the SlashCmdList function body so a match elsewhere in
    -- the file (e.g. inside the Settings popup itself) can't hide a
    -- leftover branch in the dispatcher.
    local dispatcherStart = source:find('SlashCmdList%["EbonBuilds"%]')
    local dispatcher = dispatcherStart and source:sub(dispatcherStart)
    if not dispatcher then
        io.stderr:write("SETTINGS MIGRATION FAIL: could not find the SlashCmdList dispatcher at all\n")
        os.exit(1)
    end
    local removedSubcommands = {
        "debug", "debuglog", "faq", "showcase", "atlas", "affix", "clicktrace",
        "errors", "tuning", "ewl", "cleartraining", "autosell", "bagdots", "locale",
    }
    for _, word in ipairs(removedSubcommands) do
        if dispatcher:find('msg == "' .. word .. '"', 1, true) then
            io.stderr:write("SETTINGS MIGRATION FAIL: /ebb " .. word .. " is still branched in the dispatcher\n")
            os.exit(1)
        end
    end
end
print("Verified every removed /ebb subcommand has a Settings popup replacement, and none remain in the dispatcher.")

-- The redesigned Settings popup has six vertical categories. Switching pages
-- uses WoW 3.3.5-safe Show/Hide calls, while every edited control writes into a
-- shared draft that Save commits regardless of which category is visible.
do
    local file = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()

    local categoriesStart = source:find("local SETTINGS_CATEGORIES = {", 1, true)
    local categoriesEnd = categoriesStart and source:find("\n}\n\nlocal function BuildSettingsPopup", categoriesStart, true)
    local categoriesSource = categoriesStart and categoriesEnd and source:sub(categoriesStart, categoriesEnd) or ""
    local expectedCategories = { "general", "automation", "features", "interface", "tools", "build" }
    local categoryCount = 0
    for _ in categoriesSource:gmatch('key%s*=%s*"[^"]+"') do
        categoryCount = categoryCount + 1
    end
    if categoryCount ~= #expectedCategories then
        io.stderr:write("SETTINGS CATEGORY FAIL: expected 6 categories, found " .. categoryCount .. "\n")
        os.exit(1)
    end
    for _, key in ipairs(expectedCategories) do
        if not categoriesSource:find('key = "' .. key .. '"', 1, true) then
            io.stderr:write("SETTINGS CATEGORY FAIL: missing category " .. key .. "\n")
            os.exit(1)
        end
    end

    if not source:find('if definition.key == key then panel:Show() else panel:Hide() end', 1, true)
        or not source:find('EbonBuilds.Theme.SetTabSelected(button, definition.key == key)', 1, true)
        or source:find('panel:SetShown(', 1, true) then
        io.stderr:write("SETTINGS CATEGORY FAIL: ShowCategory is not using 3.3.5-safe panel visibility and navigation selection\n")
        os.exit(1)
    end

    local requiredDraftFlow = {
        'if draft then draft[field] = self:GetChecked() and true or false end',
        'local function ApplyDraft()',
        'EbonBuilds.AutoSell.SetEnabled(draft.autoSell)',
        'EbonBuilds.BagAffixDots.SetEnabled(draft.bagDots)',
        'EbonBuilds.DebugLog.SetEnabled(draft.debugLog)',
        'EbonBuilds.ClickTrace.SetEnabled(draft.clickTrace)',
        'EbonBuilds.Sync.SetChatMessagesEnabled(draft.syncChatMessages)',
        'EbonBuilds.WorldIntegration.SetMapEnabled(draft.tomeAtlasMapEnabled)',
        'saveBtn:SetScript("OnClick", ApplyDraft)',
    }
    for _, fragment in ipairs(requiredDraftFlow) do
        if not source:find(fragment, 1, true) then
            io.stderr:write("SETTINGS CATEGORY FAIL: staged Save flow is missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
end
print("Verified the Settings popup's six categories use safe visibility and preserve staged changes across navigation.")

-- Optional feature toggles are persisted centrally, suppress only passive Sync
-- chat output, and disable Tome Atlas map rendering without disabling the
-- atlas database/window itself.
do
    local databaseFile = assert(io.open("core/Database.lua", "r"))
    local databaseSource = NormalizeNewlines(databaseFile:read("*a"))
    databaseFile:close()
    local syncFile = assert(io.open("modules/sync/Sync.lua", "r"))
    local syncSource = NormalizeNewlines(syncFile:read("*a"))
    syncFile:close()
    local worldFile = assert(io.open("modules/ui/WorldIntegration.lua", "r"))
    local worldSource = NormalizeNewlines(worldFile:read("*a"))
    worldFile:close()

    local requiredDefaults = {
        "globalSettings.syncChatMessages = true",
        "globalSettings.tomeAtlasMapEnabled = true",
    }
    for _, fragment in ipairs(requiredDefaults) do
        if not databaseSource:find(fragment, 1, true) then
            io.stderr:write("FEATURE TOGGLE FAIL: missing SavedVariables default " .. fragment .. "\n")
            os.exit(1)
        end
    end

    local requiredSync = {
        "function EbonBuilds.Sync.IsChatMessagesEnabled()",
        "function EbonBuilds.Sync.SetChatMessagesEnabled(enabled)",
        "if not force and not ChatMessagesEnabled() then return end",
        "local function CommandLog(msg)",
    }
    for _, fragment in ipairs(requiredSync) do
        if not syncSource:find(fragment, 1, true) then
            io.stderr:write("FEATURE TOGGLE FAIL: Sync chat toggle is missing " .. fragment .. "\n")
            os.exit(1)
        end
    end

    local requiredMap = {
        "function EbonBuilds.WorldIntegration.IsMapEnabled()",
        "function EbonBuilds.WorldIntegration.SetMapEnabled(enabled)",
        "if not MapFeatureEnabled() then",
        "HideMapFeatures()",
    }
    for _, fragment in ipairs(requiredMap) do
        if not worldSource:find(fragment, 1, true) then
            io.stderr:write("FEATURE TOGGLE FAIL: Tome Atlas map toggle is missing " .. fragment .. "\n")
            os.exit(1)
        end
    end
end
print("Verified independent Sync-chat and Tome-Atlas-map feature toggles.")

-- Missing-tab default view and weighted-priority regression contracts.
do
    local defaultView = EbonBuilds.BuildOverview._MissingViewDefinition(nil)
    if not defaultView or defaultView.key ~= "weightedMissing" or not defaultView.weightedOnly or defaultView.includeOwned then
        io.stderr:write("MISSING VIEW FAIL: weighted missing is not the default view\n")
        os.exit(1)
    end

    local weightedMissing = EbonBuilds.BuildOverview._MissingViewDefinition("weightedMissing")
    local allMissing = EbonBuilds.BuildOverview._MissingViewDefinition("missing")
    local catalog = EbonBuilds.BuildOverview._MissingViewDefinition("catalog")
    if weightedMissing.includeOwned or not weightedMissing.weightedOnly
        or allMissing.includeOwned or allMissing.weightedOnly
        or not catalog.includeOwned or catalog.weightedOnly then
        io.stderr:write("MISSING VIEW FAIL: alternate view modes have incorrect scope\n")
        os.exit(1)
    end

    local hiddenVariant = "Iron Constitution" .. string.char(0) .. "2"
    local weighted = EbonBuilds.BuildOverview._BuildWeightedEchoSet({
        ["Positive Echo"] = { [3] = 0, [2] = 5, [1] = 0, [0] = 0 },
        ["Negative Echo"] = { [3] = -4, [2] = 0, [1] = 0, [0] = 0 },
        ["Zero Echo"] = { [3] = 0, [2] = 0, [1] = 0, [0] = 0 },
        [hiddenVariant] = { [3] = 15, [2] = 15, [1] = 15, [0] = 15 },
    })
    if not weighted["positive echo"] or not weighted["negative echo"] or weighted["zero echo"]
        or not weighted["iron constitution"] then
        io.stderr:write("MISSING VIEW FAIL: non-zero rank values do not define weighted Echoes correctly\n")
        os.exit(1)
    end

    local originalDatabase = ProjectEbonhold.PerkDatabase
    local originalOwned = EbonBuilds.BuildOverview.GetOwnedEchoSets
    local originalAfter = EbonBuilds.Scheduler.After
    EbonBuilds.Scheduler.After = function(_, _, fn) fn(); return true end
    ProjectEbonhold.PerkDatabase = {
        [100] = { groupId = 9100, comment = "Spell 100 - Rare", quality = 2, classMask = 128, requiredSpell = 100100, families = {} },
        [101] = { groupId = 9101, comment = "Spell 101 - Rare", quality = 2, classMask = 128, requiredSpell = 100101, families = {} },
        [102] = { groupId = 9102, comment = "Spell 102 - Rare", quality = 2, classMask = 128, requiredSpell = 100102, families = {} },
    }
    EbonBuilds.EchoCatalog.Refresh("test_missing_view")
    EbonBuilds.BuildOverview.GetOwnedEchoSets = function()
        return { ["spell 101"] = true }, {}, { [101] = true }
    end
    local fixtureBuild = EbonBuilds.Build.NewObject({
        title = "Missing view fixture",
        class = "MAGE",
        echoWeights = {
            ["Spell 100"] = { [2] = 5 },
            ["Spell 101"] = { [2] = -3 },
            ["Spell 102"] = { [2] = 0 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
        lockedEchoes = {},
    })
    EbonBuilds.Weights.MigrateBuild(fixtureBuild)
    local weightedCatalog = EbonBuilds.BuildOverview._ComputeMissingEchoes(fixtureBuild, false, true, true)
    local weightedMissingOnly = EbonBuilds.BuildOverview._ComputeMissingEchoes(fixtureBuild, false, false, true)
    if not weightedCatalog or #weightedCatalog ~= 2 or not weightedMissingOnly or #weightedMissingOnly ~= 1 then
        io.stderr:write("MISSING VIEW FAIL: weighted filtering is not applied to the computed collection list\n")
        os.exit(1)
    end
    if weightedMissingOnly[1].name ~= "Spell 100" or weightedMissingOnly[1].owned then
        io.stderr:write("MISSING VIEW FAIL: weighted-missing view includes the wrong Echoes\n")
        os.exit(1)
    end

    -- Schema-3 builds can still legitimately rely on legacy name-keyed values
    -- after imports or interrupted reference migration.  The Missing views
    -- must use the effective Weights accessor just like the Priorities editor.
    local legacyBackedBuild = EbonBuilds.Build.NewObject({
        title = "Legacy-backed weighted view",
        class = "MAGE",
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint(),
        echoWeightsByRef = {},
        echoWeights = {
            ["Spell 100"] = { [2] = 7 },
            ["Spell 101"] = { [2] = -2 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
        lockedEchoes = {},
    })
    local legacyWeightedCatalog = EbonBuilds.BuildOverview._ComputeMissingEchoes(legacyBackedBuild, false, true, true)
    local legacyWeightedMissing = EbonBuilds.BuildOverview._ComputeMissingEchoes(legacyBackedBuild, false, false, true)
    if not legacyWeightedCatalog or #legacyWeightedCatalog ~= 2
        or not legacyWeightedMissing or #legacyWeightedMissing ~= 1
        or legacyWeightedMissing[1].name ~= "Spell 100" then
        io.stderr:write("MISSING VIEW FAIL: effective legacy/imported weights are not reported\n")
        os.exit(1)
    end
    ProjectEbonhold.PerkDatabase = originalDatabase
    EbonBuilds.EchoCatalog.Refresh("restore_missing_view")
    EbonBuilds.Scheduler.After = originalAfter
    EbonBuilds.BuildOverview.GetOwnedEchoSets = originalOwned
end
print("Verified weighted-missing default and alternate Missing views.")

-- Theme consistency and bottom-of-list regression contracts.
do
    local themeFile = assert(io.open("modules/ui/Theme.lua", "r"))
    local themeSource = NormalizeNewlines(themeFile:read("*a"))
    themeFile:close()
    if not themeSource:find('SetDisabledTexture%(""%)') then
        io.stderr:write("THEME FAIL: native disabled button texture is not cleared\n")
        os.exit(1)
    end

    local echoFile = assert(io.open("modules/ui/EchoTable.lua", "r"))
    local echoSource = NormalizeNewlines(echoFile:read("*a"))
    echoFile:close()
    if not echoSource:find("fullVisibleRows") or not echoSource:find("#filteredList %- fullVisibleRows") then
        io.stderr:write("SCROLL RANGE FAIL: Echo list range is not based on fully visible rows\n")
        os.exit(1)
    end
end
print("Verified themed controls and full last-row scroll range.")

-- Remaining legacy-scrollbar and build-title visibility regressions.
do
    local buildListFile = assert(io.open("modules/ui/BuildList.lua", "r"))
    local buildListSource = NormalizeNewlines(buildListFile:read("*a"))
    buildListFile:close()
    if buildListSource:find("UIPanelScrollFrameTemplate", 1, true) then
        io.stderr:write("BUILD LIST SCROLLBAR FAIL: native scroll-frame template is still used\n")
        os.exit(1)
    end
    if not buildListSource:find("Theme.CreateScrollBar", 1, true) then
        io.stderr:write("BUILD LIST SCROLLBAR FAIL: themed scrollbar is missing\n")
        os.exit(1)
    end
    if not buildListSource:find('surface:CreateFontString(nil, "OVERLAY", "GameFontNormal")', 1, true)
        or not buildListSource:find("Theme.TEXT_PRIMARY", 1, true) then
        io.stderr:write("BUILD TITLE FAIL: build titles are not rendered on the visible card surface with high contrast\n")
        os.exit(1)
    end

    local buildFormFile = assert(io.open("modules/ui/BuildForm.lua", "r"))
    local buildFormSource = NormalizeNewlines(buildFormFile:read("*a"))
    buildFormFile:close()
    if buildFormSource:find("UIPanelScrollFrameTemplate", 1, true)
        or buildFormSource:find("BuildFormDescriptionSFScrollBar", 1, true) then
        io.stderr:write("DESCRIPTION SCROLLBAR FAIL: legacy description scrollbar remains\n")
        os.exit(1)
    end
    if not buildFormSource:find("Theme.CreateScrollBar", 1, true) then
        io.stderr:write("DESCRIPTION SCROLLBAR FAIL: themed scrollbar is missing\n")
        os.exit(1)
    end

    for _, file in ipairs(files) do
        if file:match("^modules/ui/") then
            local handle = assert(io.open(file, "r"))
            local source = NormalizeNewlines(handle:read("*a"))
            handle:close()
            if source:find("UIPanelScrollFrameTemplate", 1, true)
                or source:find("UIPanelScrollBarTemplate", 1, true) then
                io.stderr:write("THEMED SCROLLBAR FAIL: legacy scrollbar template remains in " .. file .. "\n")
                os.exit(1)
            end
        end
    end
end
print("Verified themed scrollbars across all UI modules and visible build titles.")

-- Sorting regression: rank headers sort by the same final score displayed in
-- each row, not by raw weight. Protection must never affect the order. Echoes
-- without the selected rank use their highest available rank.
do
    local entries = {
        { name = "Epic Raw Zero", quality = 3, qualities = { [3] = true }, families = {}, protected = true },
        { name = "Rare Raw One", quality = 2, qualities = { [2] = true }, families = {}, protected = false },
        { name = "Common Raw One", quality = 0, qualities = { [0] = true }, families = {}, protected = true },
        { name = "Epic Raw Five", quality = 3, qualities = { [3] = true }, families = {}, protected = false },
    }
    local weights = {
        ["Epic Raw Zero"] = { [3] = 0 },
        ["Rare Raw One"] = { [2] = 1 },
        ["Common Raw One"] = { [0] = 1 },
        ["Epic Raw Five"] = { [3] = 5 },
    }
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.qualityBonus[3] = 10
    settings.qualityBonus[2] = 2
    settings.qualityBonus[0] = 0

    -- Final scores are Epic Zero=10, Epic Five=15, Rare One=3, Common One=1.
    -- This deliberately differs from raw weight order.
    EbonBuilds.EchoTable._SortEntriesForTest(entries, "rank:3", true, weights, settings)
    local expected = { "Epic Raw Five", "Epic Raw Zero", "Rare Raw One", "Common Raw One" }
    for i = 1, #expected do
        if entries[i].name ~= expected[i] then
            io.stderr:write(string.format("SORT FAIL at %d: expected %s, got %s\n", i, expected[i], tostring(entries[i].name)))
            os.exit(1)
        end
    end
end
print("Verified rank sorting uses final total score, highest-rank fallback, and ignores protection.")


-- Editing-performance regression: rank field commits must not call the full
-- RefreshCurrentView path synchronously. That previously recycled the active
-- pooled row during FocusLost and could recurse until the client froze.
do
    local file = assert(io.open("modules/ui/EchoTableRows.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    if source:find("EchoTable%.RefreshCurrentView%(") then
        io.stderr:write("EDIT PERFORMANCE FAIL: EchoTableRows still performs a synchronous full refresh\n")
        os.exit(1)
    end
    if not source:find("EchoTable%.NotifyWeightChanged") then
        io.stderr:write("EDIT PERFORMANCE FAIL: deferred weight-change notification is missing\n")
        os.exit(1)
    end
end
print("Verified weight edits use deferred incremental resorting without recursive full refresh.")

-- Build-list regression: populated title labels must anchor to the row-owned
-- class icon. A bare local `classBtn` only existed in CreateRow; referencing it
-- from PopulateRow resolved to nil and WoW anchored every title to UIParent,
-- where the scroll frame clipped it completely.
do
    local file = assert(io.open("modules/ui/BuildList.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    if source:find('row%._titleLabel:SetPoint%("TOPLEFT", classBtn') then
        io.stderr:write("BUILD LIST FAIL: title still uses the out-of-scope classBtn anchor\n")
        os.exit(1)
    end
    if not source:find('row%._titleLabel:SetPoint%("TOPLEFT", row%._classBtn') then
        io.stderr:write("BUILD LIST FAIL: row-owned class icon title anchor is missing\n")
        os.exit(1)
    end
    if source:find('row%._titleLabel:SetHeight%(0%)') then
        io.stderr:write("BUILD LIST FAIL: populated title height is still zero\n")
        os.exit(1)
    end
end
print("Verified build titles use visible, row-local anchors and dimensions.")

-- Learned-only filter regression: an Echo counts as learned when any one of
-- its name, group ID, or rank spell IDs is present in the ownership snapshot.
do
    local originalOwned = EbonBuilds.BuildOverview.GetOwnedEchoSets
    EbonBuilds.BuildOverview.GetOwnedEchoSets = function()
        return
            { ["learned by name"] = true },
            { [42] = true },
            { [3003] = true }
    end

    EbonBuilds.Filters._SetLearnedOnlyForTest(true)
    local entries = {
        { name = "Learned By Name", spellIds = {}, groupIds = {} },
        { name = "Learned By Group", spellIds = {}, groupIds = { [42] = true } },
        { name = "Learned By Spell", spellIds = { [2] = 3003 }, groupIds = {} },
        { name = "Not Learned", spellIds = { [1] = 4004 }, groupIds = { [99] = true } },
    }
    local filtered = EbonBuilds.Filters.Apply(entries)
    if #filtered ~= 3 then
        io.stderr:write("LEARNED FILTER FAIL: expected 3 learned Echoes, got " .. tostring(#filtered) .. "\n")
        os.exit(1)
    end
    local found = {}
    for _, entry in ipairs(filtered) do found[entry.name] = true end
    for _, expected in ipairs({ "Learned By Name", "Learned By Group", "Learned By Spell" }) do
        if not found[expected] then
            io.stderr:write("LEARNED FILTER FAIL: missing " .. expected .. "\n")
            os.exit(1)
        end
    end

    -- When the legacy spellbook source is not ready, fail open instead of
    -- hiding every Echo and presenting an apparently empty configuration.
    EbonBuilds.BuildOverview.GetOwnedEchoSets = function() return nil, nil, nil end
    local loading = EbonBuilds.Filters.Apply(entries)
    if #loading ~= #entries then
        io.stderr:write("LEARNED FILTER FAIL: loading state must not hide Echoes\n")
        os.exit(1)
    end

    EbonBuilds.Filters._SetLearnedOnlyForTest(false)
    EbonBuilds.BuildOverview.GetOwnedEchoSets = originalOwned
end
print("Verified learned-only filtering by name, group, and spell ID with safe loading fallback.")

-- Configuration-staging regression: editor settings must not save directly.
-- Save/Cancel owns build configuration; operational toggles remain separate.
do
    local file = assert(io.open("modules/ui/BuildForm.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    local beginAt = assert(source:find("function EbonBuilds.BuildForm.PersistEditingSettings", 1, true))
    local endAt = assert(source:find("function EbonBuilds.BuildForm.GetEditingLockedEchoes", beginAt, true))
    local body = source:sub(beginAt, endAt - 1)
    if body:find("Build.Save", 1, true) then
        io.stderr:write("STAGING FAIL: PersistEditingSettings still writes the saved build directly\n")
        os.exit(1)
    end
    if not body:find("MarkDirty", 1, true) then
        io.stderr:write("STAGING FAIL: staged settings do not mark the editor dirty\n")
        os.exit(1)
    end
end
print("Verified build configuration remains staged until Save.")

-- In-place-save regression: committing from Priorities (or any editor tab)
-- must keep that mounted view and establish the committed build as the new
-- draft baseline. Cancel remains the explicit route back to Overview.
do
    local formFile = assert(io.open("modules/ui/BuildForm.lua", "r"))
    local formSource = NormalizeNewlines(formFile:read("*a"))
    formFile:close()
    local saveBegin = assert(formSource:find("local function OnSave()", 1, true))
    local saveEnd = assert(formSource:find("local LoadFromBuild, ApplyStateToInputs", saveBegin, true))
    local saveBody = formSource:sub(saveBegin, saveEnd - 1)
    if saveBody:find("ViewRouter.Show", 1, true) then
        io.stderr:write("IN-PLACE SAVE FAIL: Save still routes away from the active editor tab\n")
        os.exit(1)
    end
    if not saveBody:find("BuildTabs.OnBuildSaved(savedBuild)", 1, true)
        or saveBody:find("pendingWeights = nil", 1, true)
        or not formSource:find("function EbonBuilds.BuildForm.AcceptSavedBuild(build)", 1, true) then
        io.stderr:write("IN-PLACE SAVE FAIL: committed state is not retained as the clean editor baseline\n")
        os.exit(1)
    end

    local tabsFile = assert(io.open("modules/ui/BuildTabs.lua", "r"))
    local tabsSource = NormalizeNewlines(tabsFile:read("*a"))
    tabsFile:close()
    local handlerBegin = assert(tabsSource:find("function EbonBuilds.BuildTabs.OnBuildSaved(savedBuild)", 1, true))
    local handlerEnd = assert(tabsSource:find("local function CreateTabs", handlerBegin, true))
    local handlerBody = tabsSource:sub(handlerBegin, handlerEnd - 1)
    if not handlerBody:find("state.context.tab = activeTab", 1, true)
        or not handlerBody:find("BuildForm.AcceptSavedBuild(savedBuild)", 1, true)
        or handlerBody:find("ShowTab", 1, true)
        or handlerBody:find("UnmountAll", 1, true)
        or handlerBody:find("ViewRouter", 1, true) then
        io.stderr:write("IN-PLACE SAVE FAIL: saved handler remounts or loses the active editor view\n")
        os.exit(1)
    end
end
print("Verified Save commits in place without remounting the active editor tab.")

-- Overview-shell regression: the dashboard must use themed flat tabs and a
-- shared page header rather than native parchment tab geometry.
do
    local file = assert(io.open("modules/ui/BuildOverview.lua", "r"))
    local source = NormalizeNewlines(file:read("*a"))
    file:close()
    if source:find("OptionsFrameTabButtonTemplate", 1, true) then
        io.stderr:write("OVERVIEW UI FAIL: native parchment tabs are still present\n")
        os.exit(1)
    end
    if not source:find("Theme.CreatePageHeader", 1, true) or not source:find("Theme.CreateTab", 1, true) then
        io.stderr:write("OVERVIEW UI FAIL: shared page header or flat tabs are missing\n")
        os.exit(1)
    end
end
print("Verified Build Overview uses the unified page shell and flat tabs.")


-- Connected Stats / Logbook redesign contracts.
do
    if EbonBuilds.StatsView._NormalizeAction("Select (Good Enough)") ~= "Select" then
        io.stderr:write("STATS REDESIGN FAIL: Select variants are not normalized\n")
        os.exit(1)
    end
    if EbonBuilds.SessionHistory._NormalizeAction("Reroll (Banish Chain)") ~= "Reroll" then
        io.stderr:write("LOGBOOK REDESIGN FAIL: Reroll variants are not normalized\n")
        os.exit(1)
    end
    local metrics = EbonBuilds.StatsView._SessionMetrics({
        maxLevel = 10,
        logs = {
            { action = "Select (Good Enough)", targetIndex = 1, choices = { { score = 20 } } },
            { action = "Banish", targetIndex = 1, choices = { { score = 0 } } },
            { action = "Select", targetIndex = 1, choices = { { score = 30 } } },
        },
    })
    if metrics.actions.Select ~= 2 or metrics.actions.Banish ~= 1 or math.floor(metrics.averageSelected + 0.5) ~= 25 then
        io.stderr:write("STATS REDESIGN FAIL: run metrics are incorrect\n")
        os.exit(1)
    end
    if not EbonBuilds.SessionHistory._IsImportant({ decision = { flags = { closeDecision = true } } }) then
        io.stderr:write("LOGBOOK REDESIGN FAIL: close decisions are not marked important\n")
        os.exit(1)
    end
    if EbonBuilds.SessionHistory._IsImportant({ action = "Select", charges = {} }) then
        io.stderr:write("LOGBOOK REDESIGN FAIL: routine Select was incorrectly marked important\n")
        os.exit(1)
    end

    local policySelectReason = EbonBuilds.SessionHistory._ReasonSentence({
        action = "Select",
        targetIndex = 1,
        eligibilitySchema = 1,
        choices = {
            { index = 1, name = "Quick Hands", score = 125 },
            { index = 2, name = "Glass Canon", score = 140,
                policy = "never_pick", policyEffect = "exclude" },
            { index = 3, name = "Rend", score = 85 },
        },
        decision = { reasonCode = "HIGHEST_FINAL_SCORE" },
    })
    if policySelectReason ~= "Highest eligible; Glass Canon at 140 was ineligible under the Never Pick policy" then
        io.stderr:write("LOGBOOK POLICY REASON FAIL: Select reason used an ineligible higher-valued Echo: " .. tostring(policySelectReason) .. "\n")
        os.exit(1)
    end

    local banListReason = EbonBuilds.SessionHistory._ReasonSentence({
        action = "Banish",
        targetIndex = 1,
        choices = {
            { index = 1, name = "Priority Ban", score = 105, eligibilityRecorded = true, isBanned = true, isAvoided = true },
            { index = 2, name = "Legal Echo", score = 40, eligibilityRecorded = true },
        },
        decision = { reasonCode = "ECHO_BAN_LIST", threshold = 31 },
    })
    if banListReason ~= "The priority ban list required this banish" then
        io.stderr:write("LOGBOOK POLICY REASON FAIL: priority ban was presented as a threshold banish: " .. tostring(banListReason) .. "\n")
        os.exit(1)
    end

    local conditionalBanishReason = EbonBuilds.SessionHistory._ReasonSentence({
        action = "Banish",
        targetIndex = 1,
        choices = {
            { index = 1, name = "Conditional Ban", score = 90, eligibilityRecorded = true,
                policy = "banish_after_pick", policyEffect = "banish", policyBlocked = true, isAvoided = true },
        },
        decision = { reasonCode = "ECHO_POLICY_BANISH", threshold = 31 },
    })
    if conditionalBanishReason ~= "The Banish After Pick policy required this banish" then
        io.stderr:write("LOGBOOK POLICY REASON FAIL: conditional policy was presented as a threshold banish: " .. tostring(conditionalBanishReason) .. "\n")
        os.exit(1)
    end

    local thresholdBanishReason = EbonBuilds.SessionHistory._ReasonSentence({
        action = "Banish",
        targetIndex = 1,
        choices = { { index = 1, name = "Low Echo", score = 25 } },
        decision = { reasonCode = "BELOW_BANISH_THRESHOLD", threshold = 31 },
    })
    if thresholdBanishReason ~= "25 below threshold 31" then
        io.stderr:write("LOGBOOK POLICY REASON FAIL: legacy threshold evidence changed: " .. tostring(thresholdBanishReason) .. "\n")
        os.exit(1)
    end

    local descending = {
        { name = "Low", weight = 5 },
        { name = "High", weight = 30 },
        { name = "Middle", weight = 15 },
    }
    EbonBuilds.StatsView._SortEchoRowsForTest(descending, "weight", true)
    if descending[1].name ~= "High" or descending[2].name ~= "Middle" or descending[3].name ~= "Low" then
        io.stderr:write("STATS SORT FAIL: descending numeric sort is not deterministic\n")
        os.exit(1)
    end

    local ascendingWithMissing = {
        { name = "Missing", avgDPS = nil },
        { name = "High", avgDPS = 300 },
        { name = "Low", avgDPS = 100 },
    }
    EbonBuilds.StatsView._SortEchoRowsForTest(ascendingWithMissing, "dps", false)
    if ascendingWithMissing[1].name ~= "Low" or ascendingWithMissing[2].name ~= "High" or ascendingWithMissing[3].name ~= "Missing" then
        io.stderr:write("STATS SORT FAIL: ascending sort or missing-value placement is incorrect\n")
        os.exit(1)
    end

    local earlyBuild = { id = "early-build", title = "Early Build" }
    local earlyStats = EbonBuilds.StatsView._BuildEarlyEpicStats({
        {
            buildId = earlyBuild.id,
            buildTitle = earlyBuild.title,
            earlyEpicOffers = {
                [1] = { tracked = true, epicSeen = true, epicCount = 2, buildId = earlyBuild.id },
                [2] = { tracked = true, epicSeen = false, epicCount = 0, buildId = earlyBuild.id },
            },
            logs = {},
        },
        {
            buildId = earlyBuild.id,
            buildTitle = earlyBuild.title,
            logs = {
                { level = 1, choices = { { quality = 2 }, { quality = 1 } }, decision = { buildId = earlyBuild.id } },
                { level = 2, choices = { { quality = 3 }, { quality = 0 } }, decision = { buildId = earlyBuild.id } },
                { level = 3, choices = { { quality = 3 }, { quality = 3 } }, decision = { buildId = earlyBuild.id } },
            },
        },
    }, earlyBuild)
    if earlyStats[1].tracked ~= 2 or earlyStats[1].seen ~= 1 or earlyStats[1].epicOffers ~= 2
        or earlyStats[2].tracked ~= 2 or earlyStats[2].seen ~= 1
        or earlyStats[3].tracked ~= 1 or earlyStats[3].seen ~= 1 or earlyStats[3].inferred ~= 1 then
        io.stderr:write("EARLY EPIC FAIL: direct and legacy original-offer observations were not aggregated correctly\n")
        os.exit(1)
    end

    local actionBuild = { id = "action-build", title = "Action Build" }
    local actionStats = EbonBuilds.StatsView._BuildActionAnalytics({
        {
            buildId = actionBuild.id,
            buildTitle = actionBuild.title,
            logs = {
                {
                    level = 1, action = "Select", targetIndex = 2,
                    choices = {
                        { index = 1, quality = 0, score = 1 },
                        { index = 2, quality = 3, score = 20 },
                    },
                },
                {
                    level = 2, action = "Banish", targetIndex = 1,
                    choices = {
                        { index = 1, quality = 0, score = 0 },
                        { index = 2, quality = 2, score = 18 },
                    },
                },
                {
                    level = 3, action = "Reroll", targetIndex = 0,
                    choices = {
                        { index = 1, quality = 2, score = 5 },
                        { index = 2, quality = 3, score = 7 },
                    },
                },
                {
                    level = 3, action = "Select", targetIndex = 2,
                    choices = {
                        { index = 1, quality = 1, score = 4 },
                        { index = 2, quality = 2, score = 12 },
                    },
                },
                {
                    level = 4, action = "Freeze", targetIndex = 7,
                    choices = {
                        { index = 7, score = 9 },
                        { index = 2, quality = 1, score = 3 },
                    },
                },
                {
                    level = 5, action = "Manual Select", targetIndex = 1,
                    choices = { { index = 1, quality = 3, score = 30 } },
                    decision = { source = "manual" },
                },
            },
        },
    }, actionBuild)
    if actionStats.total ~= 5 or actionStats.manualSelections ~= 1 or actionStats.qualityTracked ~= 4
        or actionStats.actions.Select.count ~= 2 or actionStats.actions.Select.qualities[3] ~= 1
        or actionStats.actions.Banish.qualities[0] ~= 1 or actionStats.actions.Reroll.qualities[3] ~= 1
        or actionStats.actions.Freeze.qualityTracked ~= 0 or actionStats.actions.Freeze.scoreTracked ~= 1
        or actionStats.actions.Select.rankHits ~= 2 or actionStats.actions.Banish.rankHits ~= 1
        or actionStats.rerollPairs ~= 1 or math.abs((actionStats.rerollAverageImprovement or 0) - 5) > 0.001 then
        io.stderr:write("ACTION ANALYTICS FAIL: action subjects, quality coverage, rankings, or reroll pairing are incorrect\n")
        os.exit(1)
    end
end
print("Verified connected Stats metrics, reliable sorting, early-Epic and action-quality aggregation, and decision-first Logbook evidence flags.")

-- Saved-data compaction keeps all rendered decision evidence while removing
-- fields that are derivable or never consumed, and remote-cache pruning must
-- remove only same-title records already hidden by Build.ListPublic().
do
    local compactSession = {
        logs = {
            {
                choices = {
                    {
                        name = "Spell 1", spellId = 1, score = 140, baseWeight = 40,
                        refKey = "g:1", families = { "Caster" }, modifierDelta = 100,
                        policy = "avoid", policyEffect = "exclude", policySelected = true,
                        eligibilityRecorded = true, isBanned = false, isAvoided = true,
                        policyBlocked = true, isProtected = false,
                    },
                },
                decision = { source = "automatic", flags = { closeDecision = false, lastCharge = true } },
            },
        },
    }
    EbonBuilds.Database._CompactSessionForTests(compactSession)
    local compactEntry = compactSession.logs[1]
    local compactChoice = compactEntry.choices[1]
    if compactEntry.eligibilitySchema ~= 1 or compactChoice.eligibilityRecorded ~= nil
        or compactChoice.refKey ~= nil or compactChoice.families ~= nil
        or compactChoice.modifierDelta ~= nil or compactChoice.policySelected ~= nil
        or compactChoice.isProtected ~= nil or compactChoice.isAvoided ~= nil
        or compactChoice.policyBlocked ~= nil or compactChoice.isBanned ~= nil
        or compactEntry.decision.source ~= nil
        or compactEntry.decision.flags.closeDecision ~= nil
        or compactEntry.decision.flags.lastCharge ~= true then
        error("session compaction removed required evidence or retained redundant fields")
    end
    local partialEvidence = { logs = { { choices = {
        { eligibilityRecorded = true }, {},
    } } } }
    EbonBuilds.Database._CompactSessionForTests(partialEvidence)
    if partialEvidence.logs[1].eligibilitySchema ~= nil
        or partialEvidence.logs[1].choices[1].eligibilityRecorded ~= true then
        error("session compaction promoted or erased partial eligibility evidence")
    end

    local savedDB = EbonBuildsDB
    EbonBuildsDB = {
        builds = {
            localAlpha = { id = "localAlpha", title = " Alpha ", isPublic = true, lastModified = "2026-01-01" },
        },
        remoteBuilds = {
            alphaTie = { id = "alphaTie", title = "ALPHA", lastModified = "2026-01-01" },
            alphaLater = { id = "alphaLater", title = "alpha", lastModified = "2026-02-01" },
            betaEarly = { id = "betaEarly", title = "Beta", lastModified = "2026-01-01" },
            betaLater = { id = "betaLater", title = " beta ", lastModified = "2026-02-01" },
            untitledA = { id = "untitledA", title = "" },
            untitledB = { id = "untitledB", title = "  " },
        },
    }
    local removed = EbonBuilds.Database.PruneRemoteBuilds()
    if removed ~= 3 or EbonBuildsDB.remoteBuilds.alphaTie ~= nil
        or EbonBuildsDB.remoteBuilds.alphaLater ~= nil
        or EbonBuildsDB.remoteBuilds.betaEarly == nil or EbonBuildsDB.remoteBuilds.betaLater ~= nil
        or EbonBuildsDB.remoteBuilds.untitledA == nil or EbonBuildsDB.remoteBuilds.untitledB == nil then
        error("remote cache title deduplication changed the visible winner or removed untitled records")
    end
    EbonBuildsDB = savedDB
end
print("Verified compact session evidence and visible-equivalent remote build cache pruning.")

-- Construct the primary UI once with API stubs. This catches missing frame
-- methods, bad module ordering, and construction-time nil access that a pure
-- TOC load cannot detect. It is not a pixel/layout test.
EbonBuildsDB = {
    builds = {}, publicBuilds = {}, globalSettings = {},
    echoPerformance = {}, communityPerformance = {},
}
EbonBuildsCharDB = { activeBuildId = nil }
local uiOK, uiErr = xpcall(function()
    EbonBuilds.MainWindow.Init()
    EbonBuilds.Toast.Init()
    EbonBuilds.Calibration.ShowWindow()
    EbonBuilds.ShowcaseView.Show()
end, debug.traceback)
if not uiOK then
    io.stderr:write("UI INIT FAIL: " .. tostring(uiErr) .. "\n")
    os.exit(1)
end
print("Initialized primary UI with WoW API stubs successfully.")

-- Exercise the redesigned views once with representative build/session data.
local analyticsOK, analyticsErr = xpcall(function()
    local analyticsOriginalDatabase = ProjectEbonhold.PerkDatabase
    local analyticsOriginalAfter = EbonBuilds.Scheduler.After
    EbonBuilds.Scheduler.After = function(_, _, fn) fn(); return true end
    ProjectEbonhold.PerkDatabase = {
        [1] = { groupId = 9201, displayName = "Spell 1", comment = "Spell 1 - Epic", quality = 3, classMask = 128, requiredSpell = 0, families = { "Caster" } },
        [2] = { groupId = 9202, displayName = "Iron Constitution", comment = "Iron Constitution" .. string.char(0) .. "2", quality = 0, classMask = 128, requiredSpell = 0, families = { "Tank" } },
    }
    EbonBuilds.EchoCatalog.Refresh("test_analytics_view")
    EbonBuilds.Scheduler.After = analyticsOriginalAfter

    local build = EbonBuilds.Build.Create({
        title = "Analytics Test",
        class = "MAGE",
        spec = 1,
        echoWeights = {
            ["Spell 1"] = { [3] = 12 },
            ["Iron Constitution" .. string.char(0) .. "2"] = { [0] = 15 },
        },
        settings = EbonBuilds.Build.NewBuildSettings(),
    })
    EbonBuilds.Weights.MigrateBuild(build)
    EbonBuilds.Build.SetActive(build.id)

    -- Refreshing a Missing-Echo result set fifty times must reuse its existing
    -- WoW widget pool. Hidden/parented frames and regions cannot be reclaimed
    -- by Lua GC on the 3.3.5a client.
    EbonBuilds.BuildOverview._RefreshMissingForTests(build, true)
    local missingPoolSize = EbonBuilds.BuildOverview._MissingRowPoolSizeForTests()
    for _ = 1, 50 do EbonBuilds.BuildOverview._RefreshMissingForTests(build, true) end
    if EbonBuilds.BuildOverview._MissingRowPoolSizeForTests() ~= missingPoolSize then
        error("Missing Echo refresh created new rows instead of reusing its existing pool")
    end

    -- Schema-3 and imported builds can have an allocated reference table that
    -- does not yet contain every still-valid legacy value. Stats must iterate
    -- the effective union instead of treating the presence of the table as an
    -- instruction to ignore name-keyed weights.
    local partialBuild = {
        id = "analytics-partial",
        title = "Analytics Partial",
        class = "MAGE",
        spec = 1,
        echoSchema = 3,
        echoCatalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint(),
        echoWeightsByRef = {},
        echoWeights = { ["Spell 1"] = { [3] = 12 } },
        settings = EbonBuilds.Build.NewBuildSettings(),
        stats = {},
    }
    local partialRows = EbonBuilds.StatsView._BuildEchoRowsForTest(partialBuild, {}, {}, {})
    local _, partialWeightedTotal = EbonBuilds.StatsView._WeightedCoverageForTest(partialBuild)
    if #partialRows ~= 1 or partialRows[1].name ~= "Spell 1" or partialRows[1].weight ~= 12
        or partialWeightedTotal ~= 1 then
        error("Stats Echoes ignored effective legacy weights when echoWeightsByRef existed but was incomplete")
    end

    EbonBuildsDB.sessions = {
        {
            id = "analytics-run",
            buildId = build.id,
            buildTitle = build.title,
            startTime = 1,
            endTime = 101,
            maxLevel = 10,
            soulAshes = 5,
            logs = {
                {
                    timestamp = 20,
                    level = 4,
                    action = "Select",
                    targetIndex = 1,
                    choices = {
                        { name = "Spell 1", score = 18, quality = 3, baseWeight = 12, modifierDelta = 6 },
                        { name = "Spell 2", score = 10, quality = 2, baseWeight = 10, modifierDelta = 0 },
                    },
                    charges = { ban = 10, reroll = 12, freeze = 8 },
                    decision = { buildId = build.id, buildTitle = build.title, source = "automatic", reasonCode = "HIGHEST_FINAL_SCORE", flags = { closeDecision = false } },
                },
                {
                    timestamp = 30,
                    level = 4,
                    action = "Banish",
                    targetIndex = 2,
                    choices = {
                        { name = "Spell 1", score = 18, quality = 3 },
                        { name = "Spell 3", score = 0, quality = 0 },
                    },
                    charges = { ban = 1, reroll = 12, freeze = 8 },
                    decision = { buildId = build.id, buildTitle = build.title, source = "automatic", reasonCode = "BELOW_BANISH_THRESHOLD", threshold = 6, flags = { lastCharge = true } },
                },
            },
        },
    }
    EbonBuildsDB.currentSessionIndex = 1
    local oldUnitLevel = UnitLevel
    UnitLevel = function() return 1 end
    EbonBuildsDB.sessions[1].earlyEpicOffers = {}
    EbonBuildsDB.sessions[1].analyticsRevision = 0
    local firstRecorded = EbonBuilds.Session.RecordInitialOffer({ { quality = 3 }, { quality = 2 }, { quality = 0 } })
    local duplicateRecorded = EbonBuilds.Session.RecordInitialOffer({ { quality = 0 }, { quality = 1 }, { quality = 2 } })
    local firstOffer = EbonBuildsDB.sessions[1].earlyEpicOffers[1]
    UnitLevel = oldUnitLevel
    EbonBuildsDB.currentSessionIndex = nil
    if not firstRecorded or duplicateRecorded or not firstOffer or not firstOffer.epicSeen or firstOffer.epicCount ~= 1 then
        error("Session first-offer tracking did not preserve the original Level 1 offer exactly once")
    end

    local oldTrainingSuggestions = EbonBuilds.ManualTraining.SuggestWeightAdjustments
    local trainingSuggestionCalls = 0
    local trainingSuggestionCount = 8
    EbonBuilds.ManualTraining.SuggestWeightAdjustments = function()
        trainingSuggestionCalls = trainingSuggestionCalls + 1
        return { { name = "Spell 1", quality = 3, direction = "raise", delta = 10, count = trainingSuggestionCount, currentWeight = 12, suggestedWeight = 22 } }
    end
    EbonBuilds.StatsView.Invalidate(build.id)
    EbonBuilds.StatsView.Refresh(build)
    local callsAfterFirstRefresh = trainingSuggestionCalls
    EbonBuilds.StatsView.Refresh(build)
    if trainingSuggestionCalls ~= callsAfterFirstRefresh then
        error("Stats cache rebuilt expensive recommendations without any data change")
    end
    EbonBuilds.StatsView.SetView("echoes")
    if EbonBuilds.StatsView._GetEchoRenderCountForTest() < 2 then
        error("Echoes panel did not safely render weighted rows with hidden Echo discriminators")
    end
    EbonBuilds.StatsView.SetView("actions")
    EbonBuilds.StatsView.SetView("recommendations")
    if trainingSuggestionCalls ~= callsAfterFirstRefresh then
        error("Recommendations view recalculated Manual Training instead of reusing the Stats cache")
    end

    local recommendations = EbonBuilds.StatsView._EnsureRecommendations()
    local manualRecommendation
    for _, recommendation in ipairs(recommendations) do
        if recommendation.echoName == "Spell 1" and recommendation.source == "Manual Training" then
            manualRecommendation = recommendation
            break
        end
    end
    if not manualRecommendation or manualRecommendation.currentValue ~= 12 or manualRecommendation.suggestedValue ~= 22 then
        error("Recommendation model did not expose a scannable current-to-recommended value transition")
    end
    if manualRecommendation.section ~= "echo" then
        error("Echo-priority recommendation was not assigned to the Echo priorities section")
    end
    local sectionCounts = EbonBuilds.StatsView._RecommendationSectionCounts({
        { section = "echo" }, { section = "echo" }, { section = "logic" },
    })
    if sectionCounts.echo ~= 2 or sectionCounts.logic ~= 1 then
        error("Recommendation section counts did not separate Echo priorities from automation logic")
    end
    EbonBuilds.StatsView._SetRecommendationSectionForTest("echo")
    EbonBuilds.StatsView._SetRecommendationFilterForTest("echo", "all")
    for _, recommendation in ipairs(EbonBuilds.StatsView._VisibleRecommendations()) do
        if recommendation.section ~= "echo" then error("Automation-logic recommendation leaked into Echo priorities") end
    end
    EbonBuilds.StatsView._SetRecommendationSectionForTest("logic")
    EbonBuilds.StatsView._SetRecommendationFilterForTest("logic", "all")
    for _, recommendation in ipairs(EbonBuilds.StatsView._VisibleRecommendations()) do
        if recommendation.section ~= "logic" then error("Echo-priority recommendation leaked into Automation logic") end
    end
    EbonBuilds.StatsView._SetRecommendationSectionForTest("echo")
    local applied, applyError = EbonBuilds.StatsView._ApplyRecommendation(manualRecommendation)
    if not applied then error("Recommendation apply failed: " .. tostring(applyError)) end
    if EbonBuilds.Weights.GetForRef(build, "g:9201", 3) ~= 22 then
        error("Recommendation apply did not update the intended canonical rank")
    end
    local stillMatches = EbonBuilds.StatsView._CurrentRecommendationMatches(manualRecommendation, build)
    if stillMatches then error("Applied recommendation was not detected as stale") end
    local undone, undoError = EbonBuilds.StatsView._UndoRecentRecommendation()
    if not undone then error("Recommendation undo failed: " .. tostring(undoError)) end
    if EbonBuilds.Weights.GetForRef(build, "g:9201", 3) ~= 12 then
        error("Recommendation undo did not restore the prior canonical rank value")
    end

    local refreshedRecommendations = EbonBuilds.StatsView._EnsureRecommendations()
    local dismissTarget
    for _, recommendation in ipairs(refreshedRecommendations) do
        if recommendation.echoName == "Spell 1" and recommendation.source == "Manual Training" then dismissTarget = recommendation break end
    end
    local dismissed, dismissError = EbonBuilds.StatsView._DismissRecommendation(dismissTarget)
    if not dismissed then error("Recommendation dismiss failed: " .. tostring(dismissError)) end
    for _, recommendation in ipairs(EbonBuilds.StatsView._EnsureRecommendations()) do
        if recommendation.echoName == "Spell 1" and recommendation.source == "Manual Training" then
            error("Dismissed recommendation remained visible without new evidence")
        end
    end
    trainingSuggestionCount = 9
    EbonBuilds.StatsView.Invalidate(build.id)
    EbonBuilds.StatsView.Refresh(build, true)
    local resurfaced = false
    for _, recommendation in ipairs(EbonBuilds.StatsView._EnsureRecommendations()) do
        if recommendation.echoName == "Spell 1" and recommendation.source == "Manual Training" then resurfaced = true break end
    end
    if not resurfaced then error("Dismissed recommendation did not return after its evidence changed") end

    EbonBuilds.StatsView.SetView("summary")
    EbonBuilds.ManualTraining.SuggestWeightAdjustments = oldTrainingSuggestions

    local originalSessions = EbonBuildsDB.sessions
    local manySessions = { originalSessions[1] }
    for index = 2, 49 do
        manySessions[#manySessions + 1] = {
            id = "browser-run-" .. tostring(index),
            buildId = build.id,
            buildTitle = build.title,
            startTime = 1 - index * 1000,
            endTime = 1 - index * 1000 + (index % 3 == 0 and 300 or 1200),
            maxLevel = index % 2 == 0 and 80 or 8,
            logs = {},
        }
    end
    EbonBuildsDB.sessions = manySessions
    EbonBuilds.SessionHistory.RefreshSessionList()
    local browser = EbonBuilds.SessionHistory._EnsureRunBrowserForTest()
    browser:Show()
    EbonBuilds.SessionHistory.RefreshRunBrowser(true)
    if EbonBuilds.SessionHistory._GetRunBrowserRowCountForTest() ~= 8 then
        error("Run browser did not keep a fixed pool of eight reusable rows")
    end
    if EbonBuilds.SessionHistory._GetRunBrowserResultCountForTest() ~= 49 then
        error("Run browser did not include all matching sessions before filtering")
    end
    EbonBuilds.SessionHistory._SetRunBrowserFilterForTest("complete", "")
    if EbonBuilds.SessionHistory._GetRunBrowserResultCountForTest() ~= 24 then
        error("Run browser Complete filter returned the wrong result count")
    end
    local fastLevel80 = {
        id = "fast-level-80",
        startTime = 100,
        endTime = 200,
        maxLevel = 80,
        logs = {},
    }
    if EbonBuilds.SessionHistory._RunIsShort(fastLevel80) then
        error("A completed Level 80 run was incorrectly classified as Short because of its duration")
    end
    local interruptedRun = {
        id = "interrupted-run",
        startTime = 100,
        endTime = 2000,
        maxLevel = 42,
        logs = {},
    }
    if not EbonBuilds.SessionHistory._RunIsShort(interruptedRun) then
        error("A finished sub-80 run was not classified as Short")
    end

    local raritySession = {
        id = "rarity-run",
        analyticsRevision = 1,
        logs = {
            { timestamp = 1, level = 1, action = "Select", targetIndex = 1, choices = { { spellId = 101, quality = 3 } } },
            { timestamp = 2, level = 2, action = "Select", targetIndex = 1, choices = { { spellId = 102, quality = 2 } } },
            { timestamp = 3, level = 3, action = "Manual", targetIndex = 1, choices = { { spellId = 103, quality = 1 } } },
            { timestamp = 4, level = 4, action = "Banish", targetIndex = 1, choices = { { spellId = 104, quality = 0 } } },
            { timestamp = 5, level = 5, action = "Select", targetIndex = 1, choices = { { spellId = 105, quality = 0 } } },
            -- Duplicate logger path at the same level but a different timestamp.
            -- This must still count as one completed pick.
            { timestamp = 6, level = 5, action = "Select", targetIndex = 1, choices = { { spellId = 105, quality = 0 } } },
            -- A manual record for the same level is authoritative if duplicate
            -- automatic and manual records disagree.
            { timestamp = 7, level = 5, action = "Manual Select", targetIndex = 1, choices = { { spellId = 107, quality = 0 } } },
            { timestamp = 8, level = 6, action = "Select", targetIndex = 1, choices = { { spellId = 106 } } },
        },
    }
    local rarity = EbonBuilds.SessionHistory._RunQualitySummary(raritySession)
    if rarity.totalSelectionCount ~= 5 or rarity.classifiedSelectionCount ~= 4
        or rarity.counts[3] ~= 1 or rarity.counts[2] ~= 1
        or rarity.counts[1] ~= 1 or rarity.counts[0] ~= 1 then
        error("Run rarity summary did not count unique selected Echo qualities correctly")
    end
    local doubledLegacyLogs = {}
    for copy = 1, 2 do
        for pick = 1, 79 do
            local quality = (pick - 1) % 4
            doubledLegacyLogs[#doubledLegacyLogs + 1] = {
                timestamp = copy * 1000 + pick,
                action = "Select",
                targetIndex = 1,
                choices = {
                    { spellId = 200000 + pick, quality = quality },
                    { spellId = 210000 + pick, quality = (quality + 1) % 4 },
                    { spellId = 220000 + pick, quality = (quality + 2) % 4 },
                },
            }
        end
    end
    local doubledLegacySession = {
        id = "doubled-legacy-run",
        analyticsRevision = 1,
        startLevel = 1,
        maxLevel = 80,
        endTime = 3000,
        logs = doubledLegacyLogs,
    }
    local doubledLegacyRarity = EbonBuilds.SessionHistory._RunQualitySummary(doubledLegacySession)
    if doubledLegacyRarity.totalSelectionCount ~= 79
        or doubledLegacyRarity.classifiedSelectionCount ~= 79
        or doubledLegacyRarity.discardedDuplicateCount ~= 79 then
        error("Run rarity summary did not collapse a duplicated legacy selection history to 79 picks")
    end
    local resumedMidRunSession = {
        id = "resumed-mid-run",
        analyticsRevision = 1,
        startLevel = 78,
        maxLevel = 80,
        logs = {
            { timestamp = 1, action = "Select", targetIndex = 1, choices = { { spellId = 301, quality = 3 } } },
            { timestamp = 2, action = "Select", targetIndex = 1, choices = { { spellId = 302, quality = 2 } } },
            { timestamp = 3, action = "Select", targetIndex = 1, choices = { { spellId = 303, quality = 1 } } },
            { timestamp = 4, action = "Select", targetIndex = 1, choices = { { spellId = 304, quality = 0 } } },
            { timestamp = 5, action = "Select", targetIndex = 1, choices = { { spellId = 305, quality = 2 } } },
        },
    }
    local resumedMidRunRarity = EbonBuilds.SessionHistory._RunQualitySummary(resumedMidRunSession)
    if resumedMidRunRarity.totalSelectionCount ~= 5
        or resumedMidRunRarity.classifiedSelectionCount ~= 5 then
        error("Run rarity summary incorrectly capped a resumed Level 80 session to maxLevel - startLevel")
    end
    local activeConstantLevelLogs = {}
    for pick = 1, 60 do
        activeConstantLevelLogs[#activeConstantLevelLogs + 1] = {
            timestamp = 4000 + pick,
            level = 80, -- legacy logger stored permanent character level
            action = "Select",
            targetIndex = 1,
            choices = { { spellId = 400000 + pick, quality = (pick - 1) % 4 } },
        }
    end
    local activeConstantLevelSession = {
        id = "active-character-level-80",
        analyticsRevision = 1,
        startLevel = 80,
        maxLevel = 80,
        logs = activeConstantLevelLogs,
    }
    local activeConstantRarity = EbonBuilds.SessionHistory._RunQualitySummary(activeConstantLevelSession)
    if activeConstantRarity.totalSelectionCount ~= 60
        or activeConstantRarity.classifiedSelectionCount ~= 60 then
        error("Active rarity summary collapsed sequential picks that shared character level 80")
    end
    if EbonBuilds.SessionHistory._RunDisplayLevel(activeConstantLevelSession) ~= 61 then
        error("Active run level was not derived from 60 finalized selections")
    end
    if EbonBuilds.SessionHistory._GetRunCompletionState(activeConstantLevelSession) ~= "active" then
        error("Live session was not kept Active when stale Level 80 metadata was present")
    end

    local activeTwoLevelLogs = {}
    for pick = 1, 60 do
        activeTwoLevelLogs[#activeTwoLevelLogs + 1] = {
            timestamp = 5000 + pick,
            level = pick <= 30 and 1 or 2, -- stale legacy progress values
            action = "Select",
            targetIndex = 1,
            choices = { { spellId = 500000 + pick, quality = (pick - 1) % 4 } },
        }
    end
    local activeTwoLevelSession = {
        id = "active-two-stale-levels",
        analyticsRevision = 1,
        selectionCount = 2, -- stale saved value from the broken migration
        startLevel = 1,
        maxLevel = 80,
        logs = activeTwoLevelLogs,
    }
    local activeTwoLevelRarity = EbonBuilds.SessionHistory._RunQualitySummary(activeTwoLevelSession)
    if activeTwoLevelRarity.totalSelectionCount ~= 60
        or activeTwoLevelRarity.classifiedSelectionCount ~= 60 then
        error("Active rarity summary collapsed 60 picks into two stale legacy levels")
    end
    if EbonBuilds.SessionHistory._RunDisplayLevel(activeTwoLevelSession) ~= 61 then
        error("Active run display trusted stale selectionCount instead of 60 finalized picks")
    end

    local doubledTotal = 0
    for quality = 0, 3 do doubledTotal = doubledTotal + (doubledLegacyRarity.counts[quality] or 0) end
    if doubledTotal ~= 79 then
        error("Run rarity quality counts exceeded the actual number of completed picks")
    end

    if not EbonBuilds.SessionHistory._RunBrowserSearchBlob(manySessions[2]):find("level 80", 1, true) then
        error("Run browser search index omitted the recorded level")
    end
    browser:Hide()
    EbonBuildsDB.sessions = originalSessions

    EbonBuilds.SessionHistory.RefreshSessionList()
    EbonBuilds.SessionHistory.RefreshLogView()
    EbonBuilds.SessionHistory.ShowDecisionDetail(EbonBuildsDB.sessions[1].logs[2])
    EbonBuilds.SessionHistory.OpenWithFilters({ echoName = "Spell 1", action = "Select", importantOnly = false })

    EbonBuilds.Scheduler.After = function(_, _, fn) fn(); return true end
    ProjectEbonhold.PerkDatabase = analyticsOriginalDatabase
    EbonBuilds.EchoCatalog.Refresh("restore_analytics_view")
    EbonBuilds.Scheduler.After = analyticsOriginalAfter
end, debug.traceback)
if not analyticsOK then
    io.stderr:write("ANALYTICS UI FAIL: " .. tostring(analyticsErr) .. "\n")
    os.exit(1)
end
print("Rendered redesigned Stats and Logbook with representative data successfully.")
