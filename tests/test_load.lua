-- TOC-order smoke test. It stubs the WoW 3.3.5 API just enough to verify that
-- every addon module loads in the shipped order without file-scope errors.

unpack = unpack or table.unpack

local function Noop() end
local function NewObject()
    return setmetatable({}, {
        __index = function(_, key)
            -- Frame-private state should behave like a real Lua table: an
            -- unset `_field` is nil, not a callable WoW API method.
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            if key == "CreateFontString" or key == "CreateTexture" or key == "GetStatusBarTexture" then
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
        { "modules/ui/SettingsView.lua", "Theme.BindScrollWheel(scrollFrame, scrollBar" },
        { "modules/ui/StatsView.lua", "Theme.BindScrollWheel(recScroll, recBar" },
        { "modules/ui/BuildOverview.lua", "Theme.BindScrollWheel(scroll, bar, 16, child)" },
    }
    for _, definition in ipairs(requiredBindings) do
        local file = assert(io.open(definition[1], "r"))
        local source = file:read("*a")
        file:close()
        if not source:find(definition[2], 1, true) then
            io.stderr:write("SHARED SCROLL FAIL: content-tree wheel routing is missing in " .. definition[1] .. "\n")
            os.exit(1)
        end
    end
end
print("Verified shared boundary-safe scrolling for Logbook, Autopilot, Recommendations, and Missing Echoes.")

-- The first global-settings control must be anchored at the visible top of
-- the scroll child. Anchoring to BOTTOMLEFT makes the modal appear blank.
do
    local file = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local source = file:read("*a")
    file:close()
    if not source:find('if yAnchor == scrollChild then', 1, true)
        or not source:find('label:SetPoint("TOPLEFT", scrollChild, "TOPLEFT"', 1, true) then
        io.stderr:write("SETTINGS POPUP FAIL: first setting is not anchored to the visible top of the scroll child\n")
        os.exit(1)
    end
end
print("Verified global Settings controls begin inside the visible viewport.")

-- EWL export is available from the build overview and slash command.
do
    local overviewFile = assert(io.open("modules/ui/BuildOverview.lua", "r"))
    local overviewSource = overviewFile:read("*a")
    overviewFile:close()
    local mainFile = assert(io.open("modules/ui/MainWindow.lua", "r"))
    local mainSource = mainFile:read("*a")
    mainFile:close()
    if not overviewSource:find("Export EWL", 1, true) or not overviewSource:find("EWL.ShowExportDialog", 1, true) then
        io.stderr:write("EWL UI FAIL: build overview export action is missing\n")
        os.exit(1)
    end
    if not mainSource:find('msg == "ewl"', 1, true) then
        io.stderr:write("EWL COMMAND FAIL: /ebb ewl command is missing\n")
        os.exit(1)
    end
end
print("Verified EWL generation controls and command integration.")

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
    ProjectEbonhold.PerkDatabase = {
        [100] = { quality = 2, classMask = 128, requiredSpell = 100100, families = {} },
        [101] = { quality = 2, classMask = 128, requiredSpell = 100101, families = {} },
        [102] = { quality = 2, classMask = 128, requiredSpell = 100102, families = {} },
    }
    EbonBuilds.BuildOverview.GetOwnedEchoSets = function()
        return { ["spell 101"] = true }, {}, { [101] = true }
    end
    local fixtureBuild = {
        class = "MAGE",
        echoWeights = {
            ["Spell 100"] = { [2] = 5 },
            ["Spell 101"] = { [2] = -3 },
            ["Spell 102"] = { [2] = 0 },
        },
        settings = EbonBuilds.Build.DefaultSettings(),
        lockedEchoes = {},
    }
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
    ProjectEbonhold.PerkDatabase = originalDatabase
    EbonBuilds.BuildOverview.GetOwnedEchoSets = originalOwned
end
print("Verified weighted-missing default and alternate Missing views.")

-- Theme consistency and bottom-of-list regression contracts.
do
    local themeFile = assert(io.open("modules/ui/Theme.lua", "r"))
    local themeSource = themeFile:read("*a")
    themeFile:close()
    if not themeSource:find('SetDisabledTexture%(""%)') then
        io.stderr:write("THEME FAIL: native disabled button texture is not cleared\n")
        os.exit(1)
    end

    local echoFile = assert(io.open("modules/ui/EchoTable.lua", "r"))
    local echoSource = echoFile:read("*a")
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
    local buildListSource = buildListFile:read("*a")
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
    local buildFormSource = buildFormFile:read("*a")
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
            local source = handle:read("*a")
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
    local source = file:read("*a")
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
    local source = file:read("*a")
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
    local source = file:read("*a")
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

-- Overview-shell regression: the dashboard must use themed flat tabs and a
-- shared page header rather than native parchment tab geometry.
do
    local file = assert(io.open("modules/ui/BuildOverview.lua", "r"))
    local source = file:read("*a")
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
    EbonBuilds.Build.SetActive(build.id)
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
    if EbonBuilds.Weights.GetFromWeights(build.echoWeights, "Spell 1", 3) ~= 22 then
        error("Recommendation apply did not update the intended rank")
    end
    local stillMatches = EbonBuilds.StatsView._CurrentRecommendationMatches(manualRecommendation, build)
    if stillMatches then error("Applied recommendation was not detected as stale") end
    local undone, undoError = EbonBuilds.StatsView._UndoRecentRecommendation()
    if not undone then error("Recommendation undo failed: " .. tostring(undoError)) end
    if EbonBuilds.Weights.GetFromWeights(build.echoWeights, "Spell 1", 3) ~= 12 then
        error("Recommendation undo did not restore the prior rank value")
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
    EbonBuilds.SessionHistory.RefreshSessionList()
    EbonBuilds.SessionHistory.RefreshLogView()
    EbonBuilds.SessionHistory.ShowDecisionDetail(EbonBuildsDB.sessions[1].logs[2])
    EbonBuilds.SessionHistory.OpenWithFilters({ echoName = "Spell 1", action = "Select", importantOnly = false })
end, debug.traceback)
if not analyticsOK then
    io.stderr:write("ANALYTICS UI FAIL: " .. tostring(analyticsErr) .. "\n")
    os.exit(1)
end
print("Rendered redesigned Stats and Logbook with representative data successfully.")
