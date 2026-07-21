-- EbonBuilds: modules/ui/BuildTabs.lua
-- Accessible, high-contrast tab container for editing a build.

EbonBuilds.BuildTabs = {}

local viewFrame
local contentArea
local tabs = {}
local saveBtn, cancelBtn, saveStatus
local tabsParent
local activeTab = 1
local dirty = false
local state = { context = nil }

local TAB_DEFS = {}
local function PopulateTabDefs()
    local L = EbonBuilds.L
    TAB_DEFS[1] = { label = L["Build"],       hint = L["Identity, class, locked Echoes, and sharing."] }
    TAB_DEFS[2] = { label = L["Priorities"],  hint = L["Set rank-specific Echo values and protect must-keep Echoes."] }
    TAB_DEFS[3] = { label = L["Modifiers"],   hint = L["Adjust rank, family, and unique-Echo strategy."] }
    TAB_DEFS[4] = { label = L["Autopilot"],   hint = L["Choose an automation intent and tune its decisions."] }
    TAB_DEFS[5] = { label = L["Character"],   hint = L["Live gear, full talent trees, and glyphs; adopt them into the build."] }
end

local function RefreshSaveState()
    if saveStatus then
        local active = EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
        if dirty then
            local warning = active and EbonBuilds.Build.IsAutomationEnabled(active) and EbonBuilds.L[" · Autopilot uses last saved settings"] or ""
            saveStatus:SetText(EbonBuilds.L["Unsaved changes"] .. warning)
            saveStatus:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
        else
            saveStatus:SetText(EbonBuilds.L["All changes saved"])
            saveStatus:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
        end
    end
    if saveBtn then
        if dirty or (state.context and state.context.mode == "create") then
            saveBtn:Enable()
            EbonBuilds.Theme.SetButtonAccent(saveBtn, "gold")
        else
            saveBtn:Disable()
        end
    end
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetDirtyState then
        EbonBuilds.MainWindow.SetDirtyState(dirty)
    end
end

function EbonBuilds.BuildTabs.MarkDirty()
    dirty = true
    RefreshSaveState()
end

function EbonBuilds.BuildTabs.ClearDirty()
    dirty = false
    RefreshSaveState()
end

local function UnmountAll()
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.CharacterView.Unmount()
end

local function RefreshTabs()
    for i, btn in ipairs(tabs) do
        EbonBuilds.Theme.SetTabSelected(btn, i == activeTab)
    end
end

local function LayoutTabs()
    local parent = tabsParent or viewFrame
    if not parent or #tabs == 0 then return end
    local available = math.max(1, (parent:GetWidth() or 0) - 16 - (#tabs - 1) * 5)
    local baseWidth = math.floor(available / #tabs)
    local remainder = available - baseWidth * #tabs
    for i, btn in ipairs(tabs) do
        btn:SetWidth(math.max(82, baseWidth + (i <= remainder and 1 or 0)))
    end
    if saveStatus then
        if (parent:GetWidth() or 0) < 590 then saveStatus:Hide() else saveStatus:Show() end
    end
end

local function CanLeaveActiveTab(nextIndex)
    if nextIndex == activeTab then return true end
    if activeTab == 2 and EbonBuilds.EchoTable and EbonBuilds.EchoTable.ValidateAndCommitAll then
        local ok, err = EbonBuilds.EchoTable.ValidateAndCommitAll()
        if not ok then
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(err or "Fix the invalid Echo value first") end
            return false
        end
    elseif activeTab == 3 and EbonBuilds.BonusView and EbonBuilds.BonusView.ValidateAndCommitAll then
        local ok, err = EbonBuilds.BonusView.ValidateAndCommitAll()
        if not ok then
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(err or "Fix the invalid bonus value first") end
            return false
        end
    elseif activeTab == 4 and EbonBuilds.SettingsView and EbonBuilds.SettingsView.ValidateAndCommitAll then
        local ok, err = EbonBuilds.SettingsView.ValidateAndCommitAll()
        if not ok then
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(err or "Fix the invalid Autopilot value first") end
            return false
        end
    end
    return true
end

local function ShowTab(index)
    if not CanLeaveActiveTab(index) then return false end
    activeTab = index
    UnmountAll()
    if index == 1 then
        EbonBuilds.BuildForm.Mount(contentArea, state.context)
    elseif index == 2 then
        EbonBuilds.WeightsView.Mount(contentArea)
    elseif index == 3 then
        EbonBuilds.BonusView.Mount(contentArea)
    elseif index == 4 then
        EbonBuilds.SettingsView.Mount(contentArea)
    elseif index == 5 then
        EbonBuilds.CharacterView.Mount(contentArea, state.context)
    end
    RefreshTabs()
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetPageContext then
        local prefix = state.context and state.context.mode == "create" and "New Build" or "Edit Build"
        EbonBuilds.MainWindow.SetPageContext(prefix .. " · " .. TAB_DEFS[index].label)
    end
    return true
end

function EbonBuilds.BuildTabs.ShowTab(index)
    if index and TAB_DEFS[index] then ShowTab(index) end
end

function EbonBuilds.BuildTabs.OnBuildSaved(savedBuild)
    savedBuild = savedBuild or EbonBuilds.Build.GetActive()
    if not savedBuild then return end

    -- Mutate the existing context so a mounted view holding this table keeps
    -- the same object, while future tab switches see the committed build (and
    -- any new id created when saving an imported build).
    state.context = state.context or {}
    state.context.mode = "edit"
    state.context.build = savedBuild
    state.context.tab = activeTab

    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.AcceptSavedBuild then
        EbonBuilds.BuildForm.AcceptSavedBuild(savedBuild)
    end
    EbonBuilds.BuildTabs.ClearDirty()
    RefreshTabs()
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetPageContext then
        EbonBuilds.MainWindow.SetPageContext("Edit Build · " .. TAB_DEFS[activeTab].label)
    end
end

local function CreateTabs(parent)
    tabsParent = parent
    local anchor
    for i, def in ipairs(TAB_DEFS) do
        local btn = EbonBuilds.Theme.CreateTab(parent, def.label)
        btn:SetWidth(100)
        if not anchor then
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -2)
        else
            btn:SetPoint("LEFT", anchor, "RIGHT", 5, 0)
        end
        btn:SetScript("OnClick", function() ShowTab(i) end)
        EbonBuilds.Theme.AttachTooltip(btn, def.label, def.hint)
        tabs[i] = btn
        anchor = btn
    end
    LayoutTabs()
    RefreshTabs()
end

local function CreateContentArea(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 42)
    EbonBuilds.Theme.ApplyPanel(frame)

    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    return inner
end

local function AddButtonTooltip(btn, title, body)
    EbonBuilds.Theme.AttachTooltip(btn, title, body)
end

-- Named (not inline) so it's independently testable via
-- EbonBuilds.BuildTabs._TriggerExportAI, instead of only reachable through
-- a real button click, which the test harness's frame stubs can't simulate.
--
-- Wrapped in ErrorLog.Protect below (in BuildViewFrame, not here -- this
-- file loads before core/ErrorLog.lua in EbonBuilds.toc, so EbonBuilds.ErrorLog
-- doesn't exist yet at this point): unlike most of the addon's OnClick
-- handlers, this one calls into a large, recently-changed function
-- (GenerateAIText) that a bug report claimed "does nothing" with nothing in
-- /ebb errors -- unprotected, a real error here would reach WoW's own
-- (usually disabled) Lua error display and never reach EbonBuilds' own log.
local function OnClickExportAI()
    local build = (state.context and state.context.build) or EbonBuilds.Build.GetActive()
    if build then EbonBuilds.ExportImport.ShowAIExportDialog(build) end
end

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildTabs", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "BuildTabs.ViewFrame")
    end
    CreateTabs(f)
    contentArea = CreateContentArea(f)

    saveBtn = EbonBuilds.Theme.CreateButton(f, "gold")
    saveBtn:SetSize(96, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    saveBtn:SetText(EbonBuilds.L["Save build"])
    saveBtn:SetScript("OnClick", function() EbonBuilds.BuildForm.Save() end)
    AddButtonTooltip(saveBtn, EbonBuilds.L["Save build"], EbonBuilds.L["Validate active fields and save build details, Echo values, bonuses, and visibility."])

    cancelBtn = EbonBuilds.Theme.CreateButton(f)
    cancelBtn:SetSize(86, 24)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    cancelBtn:SetText(EbonBuilds.L["Cancel"])
    cancelBtn:SetScript("OnClick", function() EbonBuilds.BuildForm.Cancel() end)
    AddButtonTooltip(cancelBtn, EbonBuilds.L["Cancel editing"], EbonBuilds.L["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."])

    local exportBtn = EbonBuilds.Theme.CreateButton(f)
    exportBtn:SetSize(82, 24)
    exportBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    exportBtn:SetText(EbonBuilds.L["Export"])
    AddButtonTooltip(exportBtn, EbonBuilds.L["Export build"], EbonBuilds.L["Create a compact string that another EbonBuilds user can import."])
    exportBtn:SetScript("OnClick", function()
        local build = (state.context and state.context.build) or EbonBuilds.Build.GetActive()
        if build then EbonBuilds.ExportImport.ShowExportDialog(build) end
    end)

    local exportAIBtn = EbonBuilds.Theme.CreateButton(f)
    exportAIBtn:SetSize(90, 24)
    exportAIBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    exportAIBtn:SetText(EbonBuilds.L["AI report"])
    AddButtonTooltip(exportAIBtn, EbonBuilds.L["AI tuning report"], EbonBuilds.L["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."])
    local protectedOnClickExportAI = EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Protect
        and EbonBuilds.ErrorLog.Protect("BuildTabs.ExportAI", OnClickExportAI)
        or OnClickExportAI
    exportAIBtn:SetScript("OnClick", protectedOnClickExportAI)

    saveStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    saveStatus:SetPoint("LEFT", exportAIBtn, "RIGHT", 10, 0)
    saveStatus:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    saveStatus:SetJustifyH("CENTER")
    saveStatus:SetText(EbonBuilds.L["All changes saved"])
    saveStatus:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    f:SetScript("OnSizeChanged", LayoutTabs)
    LayoutTabs()

    return f
end

function EbonBuilds.BuildTabs.EnableEchoesTab()
    if tabs[2] then tabs[2]:Enable() end
end

local view = {}

function view.Show(container, context)
    -- When BuildTabs is shown again without a router-level hide (for example,
    -- selecting another build while already editing), commit and hide the old
    -- mounted tab before replacing its draft context.
    UnmountAll()
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    state.context = context or { mode = "create" }
    dirty = state.context.mode == "create"

    -- Draft initialization must not depend on visiting tab 1 first. Direct
    -- Character routing and normal Edit Build routing now consume the exact
    -- same cloned class/spec/snapshot state.
    EbonBuilds.BuildForm.Prepare(state.context)

    for _, tab in ipairs(tabs) do tab:Enable() end
    activeTab = 1
    local requestedTab = tonumber(state.context.tab) or 1
    if not TAB_DEFS[requestedTab] then requestedTab = 1 end
    ShowTab(requestedTab)
    RefreshSaveState()
    viewFrame:Show()
end

function view.Hide()
    EbonBuilds.Runtime.isEditingBuild = nil
    EbonBuilds.Runtime.pendingWeights = nil
    EbonBuilds.Runtime.wizardPrefill = nil
    UnmountAll()
    dirty = false
    RefreshSaveState()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.BuildTabs.Init()
    PopulateTabDefs()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildTabs", view)
end

function EbonBuilds.BuildTabs.RefreshLayout()
    LayoutTabs()
end

------------------------------------------------------------------------
-- Test/integration helpers. These are pure and do not mutate saved data,
-- except _SetContextForTest which exists only so tests can drive the same
-- state real button clicks would (viewFrame:Show sets it normally).
------------------------------------------------------------------------
EbonBuilds.BuildTabs._TriggerExportAI = OnClickExportAI
function EbonBuilds.BuildTabs._SetContextForTest(context)
    state.context = context
end
