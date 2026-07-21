local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/SettingsView.lua
-- Intent-first automation editor. The common workflow is kept above the fold:
-- choose an automation intent, understand the resulting score cutoffs, and
-- adjust the three decisions. Detailed protection, fallback, and scoring-model
-- controls are progressively disclosed under Advanced.

EbonBuilds.SettingsView = {}

local View = EbonBuilds.SettingsView
local Theme = EbonBuilds.Theme

-- Canonical family list and order come from modules/data/Families.lua.
local FAMILY_ORDER = EbonBuilds.Families.OrderedIds()

local PROFILES = {
    {
        key = "careful",
        label = "Save charges",
        description = "Acts only on clearly weak or clearly strong offers. Best when resources matter more than speed.",
        values = { banishEVPct = 45, rerollEVPct = 85, freezeEVPct = 125, freezePenaltyPct = 5 },
    },
    {
        key = "balanced",
        label = "Balanced",
        description = "Recommended. Rejects weak boards, protects good offers, and keeps enough charges for later levels.",
        values = { banishEVPct = 60, rerollEVPct = 95, freezeEVPct = 110, freezePenaltyPct = 8 },
    },
    {
        key = "selective",
        label = "Chase upgrades",
        description = "Spends resources more freely to search for premium Echoes and preserve strong pairs.",
        values = { banishEVPct = 75, rerollEVPct = 105, freezeEVPct = 100, freezePenaltyPct = 5 },
    },
}

local ACTIONS = {
    {
        key = "banish",
        label = "BANISH",
        smartKey = "banishEVPct",
        classicKey = "autoBanishPct",
        smartMin = 0, smartMax = 150,
        classicMin = 0, classicMax = 100,
        description = "Remove a single low-value offer",
        color = { 0.92, 0.32, 0.28, 1 },
    },
    {
        key = "reroll",
        label = "REROLL",
        smartKey = "rerollEVPct",
        classicKey = "autoRerollPct",
        smartMin = 0, smartMax = 150,
        classicMin = 0, classicMax = 300,
        description = "Replace a weak three-Echo screen",
        color = { 0.28, 0.62, 0.96, 1 },
    },
    {
        key = "freeze",
        label = "FREEZE",
        smartKey = "freezeEVPct",
        classicKey = "autoFreezePct",
        smartMin = 0, smartMax = 200,
        classicMin = 0, classicMax = 200,
        description = "Carry the lower of two strong offers",
        color = { 0.66, 0.36, 0.94, 1 },
    },
}

local viewFrame
local scrollFrame, scrollChild, scrollBar
local statusDot, statusTitle, statusSubtitle, automationToggle
local profileButtons = {}
local profileStateLabel, guidanceLabel
local statLabels = {}
local actionControls = {}
local modelButtons = {}
local advancedButton, advancedPanel
local syncChatMessagesCheckbox, tomeAtlasMapCheckbox
local guardControl, penaltyControl
local familyButtons = {}
local familyWarning
local banListFrame, banScroll, banScrollChild, banScrollBar, banEmpty, fallbackButton
local banItems = {}
local advancedExpanded = false
local suppressWrite = false
local cachedStats = { peak = 0, peakName = nil, mean = 0, evBest3 = 0 }

local ADVANCED_TOGGLE_H = 26
local COLLAPSED_HEIGHT = 732 -- includes the addon-wide feature controls above Advanced
local EXPANDED_HEIGHT = 1187

------------------------------------------------------------------------
-- State helpers
------------------------------------------------------------------------

local function Settings()
    return EbonBuilds.BuildForm.GetEditingSettings()
end

local function GlobalSettings()
    EbonBuildsDB = EbonBuildsDB or {}
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    local settings = EbonBuildsDB.globalSettings
    if settings.syncChatMessages == nil then settings.syncChatMessages = true end
    if settings.tomeAtlasMapEnabled == nil then settings.tomeAtlasMapEnabled = true end
    return settings
end

local function SyncChatMessagesEnabled()
    if EbonBuilds.Sync and EbonBuilds.Sync.IsChatMessagesEnabled then
        return EbonBuilds.Sync.IsChatMessagesEnabled() ~= false
    end
    return GlobalSettings().syncChatMessages ~= false
end

local function TomeAtlasMapEnabled()
    if EbonBuilds.WorldIntegration and EbonBuilds.WorldIntegration.IsMapEnabled then
        return EbonBuilds.WorldIntegration.IsMapEnabled() ~= false
    end
    return GlobalSettings().tomeAtlasMapEnabled ~= false
end

local function SetSyncChatMessagesEnabled(enabled)
    GlobalSettings().syncChatMessages = enabled and true or false
    if EbonBuilds.Sync and EbonBuilds.Sync.SetChatMessagesEnabled then
        EbonBuilds.Sync.SetChatMessagesEnabled(enabled)
    end
end

local function SetTomeAtlasMapEnabled(enabled)
    GlobalSettings().tomeAtlasMapEnabled = enabled and true or false
    if EbonBuilds.WorldIntegration and EbonBuilds.WorldIntegration.SetMapEnabled then
        EbonBuilds.WorldIntegration.SetMapEnabled(enabled)
    end
end

local function EditingBuild()
    local id = EbonBuilds.BuildForm.GetEditingBuildId and EbonBuilds.BuildForm.GetEditingBuildId()
    return id and EbonBuilds.Build.Get(id) or nil
end

local function PersistSettings()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.PersistEditingSettings then
        EbonBuilds.BuildForm.PersistEditingSettings()
    end
end

local function IsSmart()
    return (Settings().rerollMode or "sum") == "ev"
end

local function CountEnabled(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _, enabled in pairs(tbl) do if enabled then count = count + 1 end end
    end
    return count
end

local function Rounded(value)
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

local function RecomputeStats()
    local settings = Settings()
    local class = EbonBuilds.BuildForm.GetEditingClass()
    local peakName, peak = EbonBuilds.Scoring.ComputePeak(class, settings)
    local stats = EbonBuilds.Scoring.ComputeOutcomeStats(class, settings)
    cachedStats.peakName = peakName
    cachedStats.peak = peak or 0
    cachedStats.mean = stats and stats.mean or 0
    cachedStats.evBest3 = stats and stats.evBest3 or 0
end

local function ActiveKey(action)
    return IsSmart() and action.smartKey or action.classicKey
end

local function ActiveRange(action)
    if IsSmart() then return action.smartMin, action.smartMax end
    return action.classicMin, action.classicMax
end

local function ThresholdScore(action, pct)
    if IsSmart() then
        if action.key == "banish" then return cachedStats.mean * pct / 100 end
        return cachedStats.evBest3 * pct / 100
    end
    return cachedStats.peak * pct / 100
end

local function ThresholdSentence(action, pct)
    local score = Rounded(ThresholdScore(action, pct))
    if action.key == "banish" then
        return "Banish offers below score " .. score
    elseif action.key == "reroll" then
        if IsSmart() then return "Reroll when the best offer is below " .. score end
        return "Reroll when the three scores total below " .. score
    end
    return "Freeze when two offers score above " .. score
end

local function ProfileMatch(settings)
    if (settings.rerollMode or "sum") ~= "ev" then return nil end
    for _, profile in ipairs(PROFILES) do
        local match = true
        for key, value in pairs(profile.values) do
            if (settings[key] or 0) ~= value then match = false; break end
        end
        if match then return profile end
    end
    return nil
end

------------------------------------------------------------------------
-- Shared UI helpers
------------------------------------------------------------------------

local function SetSelectedButton(btn, selected, kind)
    if selected then
        Theme.SetButtonAccent(btn, kind or "gold")
        btn:SetBackdropColor(unpack(EbonBuilds.Theme.SELECTED_BG))
    else
        Theme.ClearButtonAccent(btn)
        btn:SetBackdropColor(0.145, 0.145, 0.185, 1)
    end
end

local function CreateStat(parent, x, label)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(118, 45)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -42)
    Theme.ApplyCard(card)

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOP", card, "TOP", 0, -7)
    value:SetText("0")
    value:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local caption = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("TOP", value, "BOTTOM", 0, -2)
    caption:SetText(label)
    caption:SetTextColor(unpack(Theme.TEXT_MUTED))
    return value
end

local function CreatePercentControl(parent, action, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
    row:SetHeight(82)
    Theme.ApplyCard(row)

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(4)
    accent:SetVertexColor(unpack(action.color))

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -10)
    title:SetText(action.label)
    title:SetTextColor(action.color[1], action.color[2], action.color[3], 1)

    local description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    description:SetPoint("LEFT", title, "RIGHT", 10, 0)
    description:SetText(action.description)
    description:SetTextColor(unpack(Theme.TEXT_MUTED))

    local effect = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    effect:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -11)
    effect:SetWidth(230)
    effect:SetJustifyH("RIGHT")
    effect:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local slider = CreateFrame("Slider", nil, row)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(slider, "SettingsView.RowSlider")
    end
    slider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 14, 13)
    slider:SetWidth(445)
    slider:SetHeight(22)
    slider:SetOrientation("HORIZONTAL")
    slider:SetValueStep(1)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.24, 0.24, 0.29, 1)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(5)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(16, 22)
    slider:SetThumbTexture(thumb)

    local container = CreateFrame("Frame", nil, row)
    container:SetSize(56, 24)
    container:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    Theme.ApplyInput(container)

    local box = CreateFrame("EditBox", nil, container)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(box, "SettingsView.EditBox")
    end
    box:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -3)
    box:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -15, 3)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetJustifyH("RIGHT")
    box:SetTextColor(1, 1, 1, 1)
    box:SetAutoFocus(false)
    box:SetMaxLetters(4)

    local percent = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    percent:SetPoint("RIGHT", container, "RIGHT", -4, 0)
    percent:SetText("%")
    percent:SetTextColor(unpack(Theme.TEXT_MUTED))

    local control = {
        action = action,
        row = row,
        slider = slider,
        box = box,
        container = container,
        effect = effect,
    }

    local function RefreshEffect(value)
        effect:SetText(ThresholdSentence(action, value))
    end

    local function CommitBox()
        if box._committing then return not box._error end
        box._committing = true
        local raw = (box:GetText() or ""):match("^%s*(.-)%s*$")
        local value = raw:match("^%d+$") and tonumber(raw) or nil
        local minValue, maxValue = ActiveRange(action)
        if not value then
            box._error = "Enter a whole-number percentage."
            Theme.SetInputState(container, "error")
            box._committing = nil
            return false
        end
        if value < minValue or value > maxValue then
            box._error = string.format("Use %d to %d.", minValue, maxValue)
            Theme.SetInputState(container, "error")
            box._committing = nil
            return false
        end
        box._error = nil
        suppressWrite = true
        slider:SetValue(value)
        suppressWrite = false
        box:SetText(tostring(value))
        Settings()[ActiveKey(action)] = value
        Theme.SetInputState(container, box:HasFocus() and "focus" or "normal")
        RefreshEffect(value)
        box._committing = nil
        PersistSettings()
        return true
    end

    box:SetScript("OnEnterPressed", function(self) if CommitBox() then self:ClearFocus() end end)
    box:SetScript("OnEscapePressed", function(self)
        self._error = nil
        self:SetText(tostring(Settings()[ActiveKey(action)] or 0))
        Theme.SetInputState(container, "normal")
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self._error = nil
        Theme.SetInputState(container, "focus")
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function() CommitBox() end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(action.label .. " threshold", 1, 0.82, 0)
        GameTooltip:AddLine(self._error or "Type an exact percentage. The plain-language score cutoff updates immediately.", self._error and 1 or 0.82, self._error and 0.3 or 0.82, self._error and 0.3 or 0.86, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slider:SetScript("OnValueChanged", function(_, value)
        if suppressWrite then return end
        local rounded = math.floor(value + 0.5)
        box._error = nil
        box:SetText(tostring(rounded))
        Theme.SetInputState(container, box:HasFocus() and "focus" or "normal")
        Settings()[ActiveKey(action)] = rounded
        RefreshEffect(rounded)
    end)
    slider:SetScript("OnMouseUp", function() PersistSettings() end)
    slider:SetScript("OnEnter", function()
        GameTooltip:SetOwner(slider, "ANCHOR_RIGHT")
        GameTooltip:AddLine(action.label, 1, 0.82, 0)
        GameTooltip:AddLine(action.description .. ". Drag to explore; the exact score outcome is shown in the row.", 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    control.Commit = CommitBox
    control.Refresh = function()
        local minValue, maxValue = ActiveRange(action)
        local value = Settings()[ActiveKey(action)] or 0
        value = math.max(minValue, math.min(maxValue, value))
        suppressWrite = true
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValue(value)
        suppressWrite = false
        box._error = nil
        box:SetText(tostring(value))
        Theme.SetInputState(container, "normal")
        RefreshEffect(value)
    end
    return control
end

local function CreateCompactSlider(parent, labelText, descriptionText, key, minValue, maxValue, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    label:SetText(labelText)

    local description = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    description:SetText(descriptionText)
    description:SetTextColor(unpack(Theme.TEXT_MUTED))

    local slider = CreateFrame("Slider", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(slider, "SettingsView.ThresholdSlider")
    end
    slider:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -6)
    slider:SetWidth(430)
    slider:SetHeight(20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.24, 0.24, 0.29, 1)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(5)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(16, 20)
    slider:SetThumbTexture(thumb)

    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    value:SetWidth(54)
    value:SetJustifyH("LEFT")

    slider:SetScript("OnValueChanged", function(_, v)
        if suppressWrite then return end
        local n = math.floor(v + 0.5)
        Settings()[key] = n
        value:SetText(n .. "%")
    end)
    slider:SetScript("OnMouseUp", function() PersistSettings() end)

    return {
        slider = slider,
        value = value,
        Refresh = function()
            local n = Settings()[key] or 0
            suppressWrite = true
            slider:SetValue(n)
            suppressWrite = false
            value:SetText(n .. "%")
        end,
    }
end

------------------------------------------------------------------------
-- One-glance status and intent presets
------------------------------------------------------------------------

local function RefreshAutomationStatus()
    local build = EditingBuild()
    if build then
        local enabled = EbonBuilds.Build.IsAutomationEnabled(build)
        statusTitle:SetText(enabled and "AUTOPILOT READY" or "AUTOPILOT PAUSED")
        statusSubtitle:SetText(enabled and "The active build will act automatically on the next Echo screen." or "Rules are configured, but automatic actions are currently disabled.")
        automationToggle:SetText(enabled and "Pause Autopilot" or "Enable Autopilot")
        if enabled then
            Theme.SetButtonAccent(automationToggle, "good")
            statusDot:SetVertexColor(unpack(Theme.SUCCESS))
            statusDot._active = true
        else
            Theme.ClearButtonAccent(automationToggle)
            statusDot:SetVertexColor(unpack(Theme.TEXT_MUTED))
            statusDot._active = false
            statusDot:SetAlpha(0.55)
        end
        automationToggle:Enable()
    else
        statusTitle:SetText("AUTOPILOT READY AFTER SAVE")
        statusSubtitle:SetText("New builds start with Autopilot enabled. Save the build to activate these rules.")
        automationToggle:SetText("Enabled after save")
        automationToggle:Disable()
        statusDot:SetVertexColor(unpack(Theme.WARNING))
        statusDot._active = false
        statusDot:SetAlpha(0.8)
    end
end

local function RefreshStatsDisplay()
    statLabels.peak:SetText(tostring(Rounded(cachedStats.peak)))
    statLabels.mean:SetText(tostring(Rounded(cachedStats.mean)))
    statLabels.best:SetText(tostring(Rounded(cachedStats.evBest3)))
end

local function RefreshProfileDisplay()
    local settings = Settings()
    local matched = ProfileMatch(settings)
    for _, profile in ipairs(PROFILES) do
        SetSelectedButton(profileButtons[profile.key], matched and matched.key == profile.key, matched and matched.key == "balanced" and "good" or "gold")
    end
    if matched then
        profileStateLabel:SetText("Current intent: " .. matched.label)
        profileStateLabel:SetTextColor(unpack(matched.key == "balanced" and Theme.SUCCESS or Theme.ACCENT_GOLD))
        guidanceLabel:SetText(matched.description)
    else
        profileStateLabel:SetText(IsSmart() and "Current intent: Custom" or "Current intent: Classic rules")
        profileStateLabel:SetTextColor(unpack(Theme.WARNING))
        guidanceLabel:SetText(IsSmart() and "Custom tuning is active. Use a preset whenever you want a clean, dependable baseline." or "Classic mode is active. Open Advanced to review peak-based guard and threshold behavior.")
    end
end

local function ApplyProfile(profile)
    local settings = Settings()
    settings.rerollMode = "ev"
    for key, value in pairs(profile.values) do settings[key] = value end
    RecomputeStats()
    PersistSettings()
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then EbonBuilds.Automation.ResetPeakCache() end
    View.Refresh()
    if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(profile.label .. " Autopilot applied") end
end

local function BuildStatusPanel(parent, y)
    local panel = Theme.CreateSection(parent, "Autopilot status", "Live context from the build you are editing.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    panel:SetHeight(124)

    statusDot = panel:CreateTexture(nil, "ARTWORK")
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusDot:SetSize(9, 9)
    statusDot:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -47)

    statusTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusTitle:SetPoint("LEFT", statusDot, "RIGHT", 8, 0)
    statusTitle:SetText("AUTOPILOT READY")

    statusSubtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusSubtitle:SetPoint("TOPLEFT", statusTitle, "BOTTOMLEFT", 0, -4)
    statusSubtitle:SetWidth(208)
    statusSubtitle:SetJustifyH("LEFT")
    statusSubtitle:SetTextColor(unpack(Theme.TEXT_MUTED))

    automationToggle = Theme.CreateButton(panel)
    automationToggle:SetSize(126, 24)
    automationToggle:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 10)
    automationToggle:SetScript("OnClick", function()
        local build = EditingBuild()
        if not build then return end
        EbonBuilds.Build.SetAutomationEnabled(build, not EbonBuilds.Build.IsAutomationEnabled(build))
        RefreshAutomationStatus()
        if EbonBuilds.MainWindow and EbonBuilds.MainWindow.RefreshContext then EbonBuilds.MainWindow.RefreshContext() end
    end)

    statLabels.peak = CreateStat(panel, 246, "Peak score")
    statLabels.mean = CreateStat(panel, 368, "Average offer")
    statLabels.best = CreateStat(panel, 490, "Expected best")

    panel:SetScript("OnUpdate", function(_, elapsed)
        if not statusDot or not statusDot._active then return end
        statusDot._pulse = (statusDot._pulse or 0) + elapsed
        statusDot:SetAlpha(0.62 + 0.32 * math.abs(math.sin(statusDot._pulse * 2.2)))
    end)
end

local function BuildIntentPanel(parent, y)
    local panel = Theme.CreateSection(parent, "Choose your intent", "Start with a dependable strategy, then fine-tune only what matters.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    panel:SetHeight(128)

    for i, profile in ipairs(PROFILES) do
        local btn = Theme.CreateButton(panel)
        btn:SetSize(180, 30)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * 194, -48)
        btn:SetText(profile.label)
        btn:SetScript("OnClick", function() ApplyProfile(profile) end)
        Theme.AttachTooltip(btn, profile.label, profile.description)
        profileButtons[profile.key] = btn
    end

    profileStateLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileStateLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -87)
    profileStateLabel:SetWidth(190)
    profileStateLabel:SetJustifyH("LEFT")

    guidanceLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    guidanceLabel:SetPoint("LEFT", profileStateLabel, "RIGHT", 10, 0)
    guidanceLabel:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    guidanceLabel:SetJustifyH("LEFT")
    guidanceLabel:SetTextColor(unpack(Theme.TEXT_MUTED))
end

------------------------------------------------------------------------
-- Advanced controls
------------------------------------------------------------------------

local function RefreshModelButtons()
    SetSelectedButton(modelButtons.smart, IsSmart(), "good")
    SetSelectedButton(modelButtons.classic, not IsSmart(), "gold")
end

local function SetModel(mode)
    Settings().rerollMode = mode
    if mode == "sum" then advancedExpanded = true end
    PersistSettings()
    View.Refresh()
end

local function RefreshFamilyButtons()
    local protected = Settings().banishFamilyWhitelist or {}
    local allSelected = true
    for _, family in ipairs(FAMILY_ORDER) do
        local selected = protected[family] and true or false
        local btn = familyButtons[family]
        btn._selected = selected
        if selected then
            Theme.SetButtonAccent(btn, "good")
            btn:SetText(family .. ": ON")
        else
            Theme.ClearButtonAccent(btn)
            btn:SetText(family)
            allSelected = false
        end
    end
    if allSelected then familyWarning:Show() else familyWarning:Hide() end
end

local QUALITY_RGB = EbonBuilds.Quality.RGB
local BAN_ICON = 28
local BAN_GAP = 4
local BAN_STEP = BAN_ICON + BAN_GAP
local BAN_WIDTH = 500

local function RefreshBanList()
    if not banListFrame then return end
    for _, item in ipairs(banItems) do item:Hide() end
    local settings = Settings()
    EbonBuilds.Build.NormalizeProtection({ settings = settings })
    local banList = settings.echoBanList or {}
    local cols = math.max(1, math.floor((BAN_WIDTH - 4) / BAN_STEP))
    local index = 0

    for spellId in pairs(banList) do
        index = index + 1
        local btn = banItems[index]
        if not btn then
            btn = CreateFrame("Button", nil, banScrollChild)
            if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
                EbonBuilds.Debug.ProtectScript(btn, "SettingsView.BanListIcon")
            end
            btn:SetSize(BAN_ICON, BAN_ICON)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon = icon
            local border = btn:CreateTexture(nil, "BORDER")
            border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            btn._border = border
            btn:SetScript("OnClick", function(self)
                local id = self._spellId
                if id then Settings().echoBanList[id] = nil end
                RefreshBanList()
                PersistSettings()
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(EbonBuilds.Weights.CanonicalName(self._spellId) or "Banned Echo", 1, 0.82, 0)
                GameTooltip:AddLine("Priority ban. Click to remove.", 0.82, 0.82, 0.86, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            banItems[index] = btn
        end
        local data = ProjectEbonhold.PerkDatabase[spellId]
        local quality = data and data.quality or 0
        local rgb = QUALITY_RGB[quality] or QUALITY_RGB[0]
        btn._spellId = spellId
        btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
        btn._border:SetTexture(rgb[1], rgb[2], rgb[3])
        local col = (index - 1) % cols
        local row = math.floor((index - 1) / cols)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", banScrollChild, "TOPLEFT", 4 + col * BAN_STEP, -4 - row * BAN_STEP)
        btn:Show()
    end

    local rows = math.ceil(index / cols)
    local contentHeight = math.max(68, rows * BAN_STEP + 8)
    banScrollChild:SetHeight(contentHeight)
    local range = math.max(0, contentHeight - 68)
    banScrollBar:SetMinMaxValues(0, range)
    if index == 0 then banEmpty:Show() else banEmpty:Hide() end
end

local function AddBannedEcho(name, spellId)
    local settings = Settings()
    if EbonBuilds.Scoring.IsWhitelisted(spellId, settings) then
        EbonBuilds.Toast.Show("This Echo is protected. Remove protection before banning it.")
        return
    end
    settings.echoBanList = settings.echoBanList or {}
    settings.echoBanList[spellId] = name
    RefreshBanList()
    PersistSettings()
end

local function BuildGlobalFeaturesPanel(parent, y)
    local panel = Theme.CreateSection(parent, "Addon-wide features",
        "These controls affect the whole addon, not only the build currently being edited.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    panel:SetHeight(132)

    syncChatMessagesCheckbox = Theme.CreateCheckbox(panel, "Sync chat messages")
    syncChatMessagesCheckbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -54)
    syncChatMessagesCheckbox:SetScript("OnClick", function(self)
        SetSyncChatMessagesEnabled(self:GetChecked() and true or false)
    end)
    Theme.AttachTooltip(syncChatMessagesCheckbox, "Sync chat messages",
        "Shows passive EbonBuilds Sync status, transfer, and update notices in chat. Explicit slash-command replies remain visible.")

    tomeAtlasMapCheckbox = Theme.CreateCheckbox(panel, "Tome Atlas map integration")
    tomeAtlasMapCheckbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -88)
    tomeAtlasMapCheckbox:SetScript("OnClick", function(self)
        SetTomeAtlasMapEnabled(self:GetChecked() and true or false)
    end)
    Theme.AttachTooltip(tomeAtlasMapCheckbox, "Tome Atlas map integration",
        "Shows Tome Atlas highlights, source lists, pins, and legends on the world map. The Tome Atlas window and collected data remain available.")
end

local function RefreshGlobalFeatureControls()
    if syncChatMessagesCheckbox then syncChatMessagesCheckbox:SetChecked(SyncChatMessagesEnabled()) end
    if tomeAtlasMapCheckbox then tomeAtlasMapCheckbox:SetChecked(TomeAtlasMapEnabled()) end
end

local function BuildAdvancedPanel(parent, y)
    local panel = Theme.CreateSection(parent, "Advanced controls", "Smart is right for virtually everyone -- these exist for builds tuned before Smart existed, or genuine exceptions.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    panel:SetHeight(390)
    advancedPanel = panel

    local modelLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modelLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -48)
    modelLabel:SetText("Decision model")

    local smart = Theme.CreateButton(panel)
    smart:SetSize(160, 24)
    smart:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -68)
    smart:SetText("Smart expected value")
    smart:SetScript("OnClick", function() SetModel("ev") end)
    Theme.AttachTooltip(smart, "Smart expected value",
        "Recommended. Asks \"is this offer better than what I'd realistically get by waiting or rerolling?\" instead of comparing it to a fixed ceiling -- so a threshold means the same thing whether the run has been lucky or unlucky so far.")
    modelButtons.smart = smart

    local classic = Theme.CreateButton(panel)
    classic:SetSize(150, 24)
    classic:SetPoint("LEFT", smart, "RIGHT", 6, 0)
    classic:SetText("Classic peak %")
    classic:SetScript("OnClick", function() SetModel("sum") end)
    Theme.AttachTooltip(classic, "Classic peak percentage",
        "Legacy model. Asks \"what percent of the single highest score my build could ever roll is this?\" -- a fixed yardstick, kept for builds already tuned around it. Reroll uses the sum of all three offers.")
    modelButtons.classic = classic

    guardControl = CreateCompactSlider(panel, "Reroll guard", "Classic only: keep the screen whenever one Echo reaches this percentage of peak.", "rerollGuardPct", 0, 200, -106)
    penaltyControl = CreateCompactSlider(panel, "Frozen Echo penalty", "Temporarily lowers a carried Echo so fresh choices can win later selections.", "freezePenaltyPct", 0, 50, -172)

    local familyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    familyLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -242)
    familyLabel:SetText("Protect families from automatic banish")

    for i, family in ipairs(FAMILY_ORDER) do
        local btn = Theme.CreateButton(panel)
        btn:SetSize(112, 22)
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + col * 145, -262 - row * 27)
        btn:SetText(family)
        btn:SetScript("OnClick", function()
            local protected = Settings().banishFamilyWhitelist or {}
            Settings().banishFamilyWhitelist = protected
            protected[family] = protected[family] and nil or true
            RefreshFamilyButtons()
            PersistSettings()
        end)
        Theme.AttachTooltip(btn, "Protect " .. family, "When active, automatic banish skips Echoes in this family. Individual Echo protection always takes priority as well.")
        familyButtons[family] = btn
    end

    familyWarning = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    familyWarning:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -318)
    familyWarning:SetText("All families are protected, so automatic banish cannot act.")
    familyWarning:SetTextColor(unpack(Theme.WARNING))
    familyWarning:Hide()

    local banLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -342)
    banLabel:SetText("Priority bans")

    local add = Theme.CreateButton(panel)
    add:SetSize(86, 22)
    add:SetPoint("LEFT", banLabel, "RIGHT", 12, 0)
    add:SetText("Add Echo")
    add:SetScript("OnClick", function()
        local settings = Settings()
        local classToken = EbonBuilds.BuildForm.GetEditingClass()
        local list = EbonBuilds.EchoTableRows.BuildAllQualitiesList(classToken)
        local filtered = {}
        for _, entry in ipairs(list) do
            if not (settings.echoBanList or {})[entry.spellId]
                and not EbonBuilds.Scoring.IsWhitelisted(entry.spellId, settings)
                and not EbonBuilds.Scoring.IsLocked(entry.spellId) then
                filtered[#filtered + 1] = entry
            end
        end
        EbonBuilds.EchoPicker.Show(function(spellId, _, name) AddBannedEcho(name, spellId) end, filtered, classToken)
    end)

    banListFrame = CreateFrame("Frame", nil, panel)
    banListFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -366)
    banListFrame:SetSize(BAN_WIDTH, 68)
    Theme.ApplyInput(banListFrame)

    banScroll = CreateFrame("ScrollFrame", nil, banListFrame)
    banScroll:SetPoint("TOPLEFT", banListFrame, "TOPLEFT", 0, 0)
    banScroll:SetPoint("BOTTOMRIGHT", banListFrame, "BOTTOMRIGHT", 0, 0)
    banScrollChild = CreateFrame("Frame", nil, banScroll)
    banScrollChild:SetSize(BAN_WIDTH, 68)
    banScroll:SetScrollChild(banScrollChild)

    banScrollBar = EbonBuilds.Theme.CreateScrollBar(banListFrame)
    banScrollBar:SetPoint("TOPLEFT", banListFrame, "TOPRIGHT", 0, -2)
    banScrollBar:SetPoint("BOTTOMLEFT", banListFrame, "BOTTOMRIGHT", 0, 2)
    banScrollBar:SetValueStep(BAN_STEP)
    banScrollBar:SetValue(0)
    banScrollBar:SetScript("OnValueChanged", function(_, value) banScroll:SetVerticalScroll(value) end)
    Theme.BindScrollWheel(banScroll, banScrollBar, BAN_STEP, banScrollChild)

    banEmpty = banListFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    banEmpty:SetPoint("CENTER", banListFrame, "CENTER", 0, 0)
    banEmpty:SetText("No priority bans. Thresholds decide automatically.")
    banEmpty:SetTextColor(unpack(Theme.TEXT_MUTED))

    fallbackButton = Theme.CreateButton(panel)
    fallbackButton:SetSize(172, 22)
    fallbackButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -342)
    fallbackButton:SetScript("OnClick", function(self)
        local settings = Settings()
        settings.echoBanAllMode = (settings.echoBanAllMode or "highestScore") == "highestScore" and "random" or "highestScore"
        self:SetText(settings.echoBanAllMode == "random" and "Fallback: Random" or "Fallback: Highest score")
        PersistSettings()
    end)
    Theme.AttachTooltip(fallbackButton, "When every offer is banned", "Choose the highest-scoring candidate for consistency, or pick randomly when no banish charges remain.")

    -- The ban list extends below the original panel height. Increase after all
    -- controls are anchored so the card remains a single coherent section.
    panel:SetHeight(455)
end

local function RefreshAdvancedVisibility()
    if advancedExpanded then
        advancedButton:SetText("Hide advanced controls")
        Theme.SetButtonAccent(advancedButton, "gold")
        advancedPanel:Show()
        scrollChild:SetHeight(EXPANDED_HEIGHT)
    else
        advancedButton:SetText("Show advanced controls")
        Theme.ClearButtonAccent(advancedButton)
        advancedPanel:Hide()
        scrollChild:SetHeight(COLLAPSED_HEIGHT)
    end
    local range = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
    scrollBar:SetMinMaxValues(0, range)
    if scrollBar:GetValue() > range then scrollBar:SetValue(range) end
end

------------------------------------------------------------------------
-- Refresh and validation
------------------------------------------------------------------------

local function RefreshActionControls()
    for _, action in ipairs(ACTIONS) do actionControls[action.key].Refresh() end
end

local function RefreshAdvanced()
    RefreshModelButtons()
    guardControl.Refresh()
    penaltyControl.Refresh()
    if IsSmart() then
        guardControl.slider:Disable()
        guardControl.value:SetText("Classic only")
        guardControl.value:SetTextColor(unpack(Theme.TEXT_MUTED))
    else
        guardControl.slider:Enable()
        guardControl.value:SetText((Settings().rerollGuardPct or 0) .. "%")
        guardControl.value:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    end
    RefreshFamilyButtons()
    RefreshBanList()
    fallbackButton:SetText((Settings().echoBanAllMode or "highestScore") == "random" and "Fallback: Random" or "Fallback: Highest score")
end

function View.Refresh()
    if not viewFrame then return end
    RecomputeStats()
    RefreshAutomationStatus()
    RefreshStatsDisplay()
    RefreshProfileDisplay()
    RefreshActionControls()
    RefreshGlobalFeatureControls()
    RefreshAdvanced()
    RefreshAdvancedVisibility()
end

function View.ValidateAndCommitAll()
    for _, action in ipairs(ACTIONS) do
        local control = actionControls[action.key]
        if control and (control.box:HasFocus() or control.box._error) then
            if not control.Commit() then
                control.box:SetFocus()
                return false, control.box._error or ("Fix the " .. action.label .. " percentage.")
            end
            control.box:ClearFocus()
        end
    end
    return true
end

local function CommitFocusedBoxes()
    View.ValidateAndCommitAll()
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    header:SetText("Autopilot")
    header:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Choose the outcome you want. The addon translates it into precise banish, reroll, and freeze decisions.")
    subtitle:SetTextColor(unpack(Theme.TEXT_MUTED))

    scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(scrollFrame, "SettingsView.ScrollFrame")
    end
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(610, COLLAPSED_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = EbonBuilds.Theme.CreateScrollBar(scrollFrame)
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2, 4)
    scrollBar:SetValueStep(24)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(_, value) scrollFrame:SetVerticalScroll(value) end)

    scrollFrame:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(math.max(610, self:GetWidth() or 0))
        RefreshAdvancedVisibility()
    end)

    BuildStatusPanel(scrollChild, -4)
    BuildIntentPanel(scrollChild, -136)

    actionControls.banish = CreatePercentControl(scrollChild, ACTIONS[1], -272)
    actionControls.reroll = CreatePercentControl(scrollChild, ACTIONS[2], -362)
    actionControls.freeze = CreatePercentControl(scrollChild, ACTIONS[3], -452)

    BuildGlobalFeaturesPanel(scrollChild, -540)

    advancedButton = Theme.CreateButton(scrollChild)
    advancedButton:SetSize(190, ADVANCED_TOGGLE_H)
    advancedButton:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -692)
    advancedButton:SetText("Show advanced controls")
    advancedButton:SetScript("OnClick", function()
        advancedExpanded = not advancedExpanded
        RefreshAdvancedVisibility()
    end)
    Theme.AttachTooltip(advancedButton, "Advanced controls", "Reveal the decision model, classic guard, freeze penalty, protected families, explicit bans, and fallback behavior.")

    BuildAdvancedPanel(scrollChild, -724)
    Theme.BindScrollWheel(scrollFrame, scrollBar, 30, scrollChild)
    scrollChild:SetWidth(math.max(610, scrollFrame:GetWidth() or 0))
    return frame
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function View.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    local settings = Settings()
    local hasExceptions = CountEnabled(settings.banishFamilyWhitelist) > 0 or CountEnabled(settings.echoBanList) > 0
    advancedExpanded = (settings.rerollMode or "sum") ~= "ev" or hasExceptions

    View.Refresh()
    viewFrame:Show()
    scrollBar:SetValue(0)
end

function View.Unmount()
    if not viewFrame then return end
    CommitFocusedBoxes()
    viewFrame:Hide()
end

function View.Init()
end
