-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level window shell with navigation and a high-contrast content panel.
-- Hosts the build list and the view router.

EbonBuilds.MainWindow = {}

local WINDOW_WIDTH       = 980
local WINDOW_HEIGHT      = 660
local MIN_WINDOW_WIDTH   = 900
local MIN_WINDOW_HEIGHT  = 620
local MIN_LEFT_WIDTH     = 220
local LEFT_WIDTH         = 230
local FRAME_NAME    = "EbonBuildsMainWindow"
local contextLabel
local pageLabel, dirtyLabel, automationPill, classAccent
local currentPageTitle = "Overview"
local currentDirty = false

local function SafeScale(requested, logicalWidth, logicalHeight, screenWidth, screenHeight)
    requested = math.max(0.9, math.min(1.2, tonumber(requested) or 1))
    screenWidth = tonumber(screenWidth)
        or UIParent and UIParent.GetWidth and UIParent:GetWidth()
        or GetScreenWidth and GetScreenWidth()
    screenHeight = tonumber(screenHeight)
        or UIParent and UIParent.GetHeight and UIParent:GetHeight()
        or GetScreenHeight and GetScreenHeight()
    if not screenWidth or not screenHeight or screenWidth <= 0 or screenHeight <= 0 then return requested end
    local fit = math.min((screenWidth - 24) / logicalWidth, (screenHeight - 24) / logicalHeight)
    return math.max(0.5, math.min(requested, fit))
end

-- Preserve the selected scale whenever the screen can hold a supported
-- logical viewport. Instead of shrinking the entire 980 x 660 tree when a
-- high scale barely misses the screen, trim only the excess logical width and
-- height. Anchored children then receive real OnSizeChanged events and reflow
-- without being recreated.
local function ResolveShellLayout(requested, screenWidth, screenHeight)
    requested = math.max(0.9, math.min(1.2, tonumber(requested) or 1))
    screenWidth = tonumber(screenWidth)
        or UIParent and UIParent.GetWidth and UIParent:GetWidth()
        or GetScreenWidth and GetScreenWidth()
    screenHeight = tonumber(screenHeight)
        or UIParent and UIParent.GetHeight and UIParent:GetHeight()
        or GetScreenHeight and GetScreenHeight()
    if not screenWidth or not screenHeight or screenWidth <= 0 or screenHeight <= 0 then
        return {
            width = WINDOW_WIDTH,
            height = WINDOW_HEIGHT,
            sidebar = LEFT_WIDTH,
            scale = requested,
            compact = false,
        }
    end

    local availableWidth = math.max(1, screenWidth - 24)
    local availableHeight = math.max(1, screenHeight - 24)
    local logicalWidth = math.floor(math.min(WINDOW_WIDTH, availableWidth / requested))
    local logicalHeight = math.floor(math.min(WINDOW_HEIGHT, availableHeight / requested))
    local applied = requested

    if logicalWidth < MIN_WINDOW_WIDTH or logicalHeight < MIN_WINDOW_HEIGHT then
        logicalWidth = MIN_WINDOW_WIDTH
        logicalHeight = MIN_WINDOW_HEIGHT
        applied = SafeScale(requested, logicalWidth, logicalHeight, screenWidth, screenHeight)
    end

    local widthProgress = math.max(0, math.min(1,
        (logicalWidth - MIN_WINDOW_WIDTH) / (WINDOW_WIDTH - MIN_WINDOW_WIDTH)))
    local sidebar = math.floor(MIN_LEFT_WIDTH + (LEFT_WIDTH - MIN_LEFT_WIDTH) * widthProgress + 0.5)
    return {
        width = logicalWidth,
        height = logicalHeight,
        sidebar = sidebar,
        scale = applied,
        compact = logicalWidth < WINDOW_WIDTH or logicalHeight < WINDOW_HEIGHT,
    }
end

local function ApplyShellLayout(frame, requested)
    if not frame then return end
    local layout = ResolveShellLayout(requested)
    frame._requestedScale = math.max(0.9, math.min(1.2, tonumber(requested) or 1))
    frame._responsiveLayout = layout
    frame:SetSize(layout.width, layout.height)
    if frame._left then frame._left:SetWidth(layout.sidebar) end
    -- Set the frame scale first so Theme.SetAppliedScale can inspect each
    -- control's final effective scale before choosing the safe edge width.
    frame:SetScale(layout.scale)
    if EbonBuilds.Theme and EbonBuilds.Theme.SetAppliedScale then
        EbonBuilds.Theme.SetAppliedScale(layout.scale)
    end
    if EbonBuilds.BuildList and EbonBuilds.BuildList.RefreshLayout then
        EbonBuilds.BuildList.RefreshLayout()
    end
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.RefreshLayout then
        EbonBuilds.BuildTabs.RefreshLayout()
    end
    if EbonBuilds.Filters and EbonBuilds.Filters.RefreshLayout then
        EbonBuilds.Filters.RefreshLayout()
    end
    if EbonBuilds.EchoTable and EbonBuilds.EchoTable.RefreshLayout then
        EbonBuilds.EchoTable.RefreshLayout()
    end
end

local function ApplyBackdrop(frame)
    EbonBuilds.Theme.ApplyWindow(frame)
end

local function CreateTitleBar(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -10)
    title:SetText("EbonBuilds")
    title:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. tostring((GetAddOnMetadata and GetAddOnMetadata("EbonBuilds", "Version")) or EbonBuilds.VERSION or "2.6"))
    version:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageLabel:SetPoint("LEFT", version, "RIGHT", 18, 0)
    pageLabel:SetWidth(280)
    pageLabel:SetJustifyH("LEFT")
    if pageLabel.SetNonSpaceWrap then pageLabel:SetNonSpaceWrap(false) end
    if pageLabel.SetWordWrap then pageLabel:SetWordWrap(false) end
    pageLabel:SetText("/  Overview")
    pageLabel:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))

    automationPill = EbonBuilds.Theme.CreateStatusPill(frame, "AUTOPILOT --", "warning")
    automationPill:SetWidth(104)
    automationPill:SetPoint("RIGHT", frame, "RIGHT", -120, 0)
    automationPill:SetPoint("TOP", frame, "TOP", 0, -14)

    contextLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contextLabel:SetPoint("RIGHT", automationPill, "LEFT", -16, 0)
    contextLabel:SetPoint("TOP", frame, "TOP", 0, -14)
    contextLabel:SetWidth(188)
    contextLabel:SetJustifyH("RIGHT")
    if contextLabel.SetNonSpaceWrap then contextLabel:SetNonSpaceWrap(false) end
    if contextLabel.SetWordWrap then contextLabel:SetWordWrap(false) end
    contextLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))
    contextLabel:SetText("No active build")

    classAccent = frame:CreateTexture(nil, "ARTWORK")
    classAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    classAccent:SetSize(3, 18)
    classAccent:SetPoint("RIGHT", contextLabel, "LEFT", -10, 0)
    classAccent:SetPoint("TOP", frame, "TOP", 0, -8)
    classAccent:SetVertexColor(0.5, 0.5, 0.5, 0.8)

    dirtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dirtyLabel:SetPoint("TOPRIGHT", automationPill, "BOTTOMRIGHT", 0, -4)
    dirtyLabel:SetWidth(312)
    dirtyLabel:SetJustifyH("RIGHT")
    dirtyLabel:SetText("")
    dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.30, 0.30, 0.36, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -36)

    local dragRegion = CreateFrame("Frame", nil, frame)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(dragRegion, "MainWindow.DragRegion")
    end
    dragRegion:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,   0)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -330, 0)
    dragRegion:SetHeight(34)
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local cx, cy = frame:GetCenter()
        if cx and cy then EbonBuildsDB.windowPos = { x = cx, y = cy } end
    end)
end

function EbonBuilds.MainWindow._ResolveShellLayoutForTest(requested, screenWidth, screenHeight)
    return ResolveShellLayout(requested, screenWidth, screenHeight)
end

local function CreateCloseButton(frame)
    local closeBtn = EbonBuilds.Theme.CreateCloseButton(frame)
    closeBtn:SetFrameLevel(100)
    return closeBtn
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

StaticPopupDialogs["EBONBUILDS_CLEAR_TRAINING"] = {
    text = "",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        local build = EbonBuilds.Build.GetActive()
        if not build then return end
        EbonBuilds.ManualTraining.Clear(build.id)
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show("Cleared Manual Training data for \"" .. (build.title or "?") .. "\"")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local SETTINGS_NAV_WIDTH = 150
local SETTINGS_CONTENT_WIDTH = 410
local SETTINGS_CATEGORIES = {
    {
        key = "general",
        label = "General",
        title = "General",
        description = "Timing and notification behavior used throughout EbonBuilds.",
    },
    {
        key = "automation",
        label = "Automation",
        title = "Automation",
        description = "Convenience features and diagnostics that run alongside Autopilot.",
    },
    {
        key = "interface",
        label = "Interface",
        title = "Interface",
        description = "Language and display preferences for the addon interface.",
    },
    {
        key = "tools",
        label = "Windows & Tools",
        title = "Windows & Tools",
        description = "Open reference windows, diagnostics, and addon utilities.",
    },
    {
        key = "build",
        label = "Build",
        title = "Build",
        description = "Utilities that operate on the currently active build.",
    },
}

local function BuildSettingsPopup(ownerFrame)
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(popup, "MainWindow.GlobalSettingsPopup")
    end
    popup:SetSize(640, 520)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:SetClampedToScreen(true)
    popup:SetScale(SafeScale(EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.uiScale, 640, 520))
    popup:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(popup)
    popup:Hide()

    local draft
    local baseline
    local loadingDraft = false
    local categoryFrames = {}
    local categoryButtons = {}
    local categoryErrors = {}
    local controls = {}
    local activeCategoryKey = "general"

    local function EnsureSettingsDefaults()
        EbonBuildsDB = EbonBuildsDB or {}
        EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
        local gs = EbonBuildsDB.globalSettings
        if tonumber(gs.evalDelay) == nil then gs.evalDelay = 2 end
        if tonumber(gs.toastDuration) == nil then gs.toastDuration = 3 end
        if tonumber(gs.uiScale) == nil then gs.uiScale = 1 end
        if not gs.settingsCategory then gs.settingsCategory = "general" end
        return gs
    end

    local function Bool(value)
        return value and true or false
    end

    local function ReadModuleToggle(module)
        if module and module.IsEnabled then
            local ok, value = pcall(module.IsEnabled)
            if ok then return Bool(value) end
        end
        return false
    end

    local function CopyDraft(source)
        return {
            evalDelay = tonumber(source.evalDelay) or 2,
            toastDuration = tonumber(source.toastDuration) or 3,
            autoSell = Bool(source.autoSell),
            autoSellPoorOnly = Bool(source.autoSellPoorOnly),
            autoSellExcludeTradeGoods = Bool(source.autoSellExcludeTradeGoods),
            autoSellExcludeRecipes = Bool(source.autoSellExcludeRecipes),
            bagDots = Bool(source.bagDots),
            debugLog = Bool(source.debugLog),
            clickTrace = Bool(source.clickTrace),
            gearTooltip = Bool(source.gearTooltip),
            mapZonePanel = Bool(source.mapZonePanel),
            locale = source.locale or "enUS",
            uiScale = tonumber(source.uiScale) or 1,
        }
    end

    local function ReadSavedDraft()
        local gs = EnsureSettingsDefaults()
        return {
            evalDelay = tonumber(gs.evalDelay) or 2,
            toastDuration = tonumber(gs.toastDuration) or 3,
            autoSell = ReadModuleToggle(EbonBuilds.AutoSell),
            autoSellPoorOnly = Bool(EbonBuilds.AutoSell and EbonBuilds.AutoSell.GetCategory and EbonBuilds.AutoSell.GetCategory("poorOnly")),
            autoSellExcludeTradeGoods = EbonBuilds.AutoSell and EbonBuilds.AutoSell.GetCategory
                and EbonBuilds.AutoSell.GetCategory("excludeTradeGoods") ~= false or true,
            autoSellExcludeRecipes = EbonBuilds.AutoSell and EbonBuilds.AutoSell.GetCategory
                and EbonBuilds.AutoSell.GetCategory("excludeRecipes") ~= false or true,
            bagDots = ReadModuleToggle(EbonBuilds.BagAffixDots),
            debugLog = ReadModuleToggle(EbonBuilds.DebugLog),
            clickTrace = ReadModuleToggle(EbonBuilds.ClickTrace),
            gearTooltip = ReadModuleToggle(EbonBuilds.GearTooltip),
            mapZonePanel = Bool(EbonBuilds.WorldIntegration and EbonBuilds.WorldIntegration.IsMapPanelEnabled
                and EbonBuilds.WorldIntegration.IsMapPanelEnabled()),
            locale = (EbonBuilds.Locale and EbonBuilds.Locale.GetActiveLocale and EbonBuilds.Locale.GetActiveLocale()) or gs.localeOverride or "enUS",
            uiScale = math.max(0.9, math.min(1.2, tonumber(gs.uiScale) or 1)),
        }
    end

    local function SameNumber(a, b)
        return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.001
    end

    local function CountDirtyFields()
        if not draft or not baseline then return 0 end
        local count = 0
        if not SameNumber(draft.evalDelay, baseline.evalDelay) then count = count + 1 end
        if not SameNumber(draft.toastDuration, baseline.toastDuration) then count = count + 1 end
        if Bool(draft.autoSell) ~= Bool(baseline.autoSell) then count = count + 1 end
        if Bool(draft.autoSellPoorOnly) ~= Bool(baseline.autoSellPoorOnly) then count = count + 1 end
        if Bool(draft.autoSellExcludeTradeGoods) ~= Bool(baseline.autoSellExcludeTradeGoods) then count = count + 1 end
        if Bool(draft.autoSellExcludeRecipes) ~= Bool(baseline.autoSellExcludeRecipes) then count = count + 1 end
        if Bool(draft.bagDots) ~= Bool(baseline.bagDots) then count = count + 1 end
        if Bool(draft.debugLog) ~= Bool(baseline.debugLog) then count = count + 1 end
        if Bool(draft.clickTrace) ~= Bool(baseline.clickTrace) then count = count + 1 end
        if Bool(draft.gearTooltip) ~= Bool(baseline.gearTooltip) then count = count + 1 end
        if Bool(draft.mapZonePanel) ~= Bool(baseline.mapZonePanel) then count = count + 1 end
        if tostring(draft.locale or "") ~= tostring(baseline.locale or "") then count = count + 1 end
        if not SameNumber(draft.uiScale, baseline.uiScale) then count = count + 1 end
        return count
    end

    -- Title bar / drag region.
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -14)
    title:SetText("EbonBuilds Settings")
    title:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local subtitle = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("Addon-wide preferences and tools")
    subtitle:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local drag = CreateFrame("Frame", nil, popup)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "MainWindow.PopupDragHeader")
    end
    drag:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -37, 0)
    drag:SetHeight(38)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        popup:StopMovingOrSizing()
        local x, y = popup:GetCenter()
        if x and y then
            local gs = EnsureSettingsDefaults()
            gs.settingsWindowPos = { x = x, y = y }
        end
    end)

    local closeBtn = EbonBuilds.Theme.CreateCloseButton(popup)

    local bodyTop = -52
    local footerHeight = 52

    local nav = CreateFrame("Frame", nil, popup)
    nav:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, bodyTop)
    nav:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, footerHeight)
    nav:SetWidth(SETTINGS_NAV_WIDTH)
    EbonBuilds.Theme.ApplySidebar(nav)

    local navHeading = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    navHeading:SetPoint("TOPLEFT", nav, "TOPLEFT", 12, -12)
    navHeading:SetText("CATEGORIES")
    navHeading:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local content = CreateFrame("Frame", nil, popup)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, footerHeight)
    EbonBuilds.Theme.ApplyPanel(content)

    local pageTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -14)
    pageTitle:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local pageDescription = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pageDescription:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -4)
    pageDescription:SetPoint("RIGHT", content, "RIGHT", -18, 0)
    pageDescription:SetJustifyH("LEFT")
    pageDescription:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local headerDivider = content:CreateTexture(nil, "ARTWORK")
    headerDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
    headerDivider:SetVertexColor(0.28, 0.28, 0.33, 0.9)
    headerDivider:SetHeight(1)
    headerDivider:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -58)
    headerDivider:SetPoint("TOPRIGHT", content, "TOPRIGHT", -14, -58)

    local settingsScroll = CreateFrame("ScrollFrame", nil, content)
    settingsScroll:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -68)
    settingsScroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -28, 12)
    settingsScroll:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, settingsScroll)
    scrollChild:SetWidth(SETTINGS_CONTENT_WIDTH)
    scrollChild:SetHeight(1)
    settingsScroll:SetScrollChild(scrollChild)

    local settingsScrollBar = EbonBuilds.Theme.CreateScrollBar(content, 12)
    settingsScrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -70)
    settingsScrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 14)
    settingsScrollBar:SetScript("OnValueChanged", function(_, value)
        settingsScroll:SetVerticalScroll(value or 0)
    end)
    EbonBuilds.Theme.BindScrollWheel(settingsScroll, settingsScrollBar, 32, scrollChild)

    local dirtyLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dirtyLabel:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 20)
    dirtyLabel:SetWidth(300)
    dirtyLabel:SetJustifyH("LEFT")
    dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local saveBtn = EbonBuilds.Theme.CreateButton(popup, "gold")
    saveBtn:SetSize(112, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14, 14)
    saveBtn:SetText("Save changes")

    local cancelBtn = EbonBuilds.Theme.CreateButton(popup)
    cancelBtn:SetSize(82, 24)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetText("Cancel")

    local function RefreshDirtyState()
        if loadingDraft then return end
        local count = CountDirtyFields()
        if count > 0 then
            dirtyLabel:SetText(count == 1 and "1 unsaved change" or (tostring(count) .. " unsaved changes"))
            dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
            saveBtn:Enable()
        else
            dirtyLabel:SetText("No unsaved changes")
            dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
            saveBtn:Disable()
        end
    end

    local function RefreshLocaleButtons()
        for _, button in ipairs(controls.languageButtons or {}) do
            local selected = draft and button._localeCode == draft.locale
            if selected then
                EbonBuilds.Theme.SetButtonAccent(button, "gold")
                local font = button.GetFontString and button:GetFontString()
                if font then font:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD)) end
            else
                EbonBuilds.Theme.ClearButtonAccent(button)
                local font = button.GetFontString and button:GetFontString()
                if font then font:SetTextColor(0.82, 0.82, 0.86, 1) end
            end
        end
    end

    local function RefreshScaleButtons()
        for _, button in ipairs(controls.scaleButtons or {}) do
            if draft and SameNumber(button._scaleValue, draft.uiScale) then
                EbonBuilds.Theme.SetButtonAccent(button, "gold")
            else
                EbonBuilds.Theme.ClearButtonAccent(button)
            end
        end
    end

    local function RefreshControlsFromDraft()
        if not draft then return end
        loadingDraft = true
        if controls.delaySlider then controls.delaySlider:SetValue(draft.evalDelay) end
        if controls.toastSlider then controls.toastSlider:SetValue(draft.toastDuration) end
        if controls.autoSellCB then controls.autoSellCB:SetChecked(draft.autoSell) end
        if controls.autoSellPoorOnlyCB then controls.autoSellPoorOnlyCB:SetChecked(draft.autoSellPoorOnly) end
        if controls.autoSellExcludeTradeGoodsCB then controls.autoSellExcludeTradeGoodsCB:SetChecked(draft.autoSellExcludeTradeGoods) end
        if controls.autoSellExcludeRecipesCB then controls.autoSellExcludeRecipesCB:SetChecked(draft.autoSellExcludeRecipes) end
        if controls.bagDotsCB then controls.bagDotsCB:SetChecked(draft.bagDots) end
        if controls.debugCB then controls.debugCB:SetChecked(draft.debugLog) end
        if controls.clickTraceCB then controls.clickTraceCB:SetChecked(draft.clickTrace) end
        if controls.gearTooltipCB then controls.gearTooltipCB:SetChecked(draft.gearTooltip) end
        if controls.mapZonePanelCB then controls.mapZonePanelCB:SetChecked(draft.mapZonePanel) end
        RefreshLocaleButtons()
        RefreshScaleButtons()
        loadingDraft = false
        RefreshDirtyState()
    end

    local function UpdateScrollRange()
        local panel = categoryFrames[activeCategoryKey]
        local childHeight = panel and panel._contentHeight or 1
        local viewportHeight = settingsScroll:GetHeight() or 1
        scrollChild:SetHeight(math.max(1, childHeight))
        local maximum = math.max(0, childHeight - viewportHeight)
        settingsScrollBar:SetMinMaxValues(0, maximum)
        if maximum > 0 then
            settingsScrollBar:Show()
        else
            settingsScrollBar:Hide()
        end
        settingsScrollBar:SetValue(0)
        settingsScroll:SetVerticalScroll(0)
    end

    local function ShowCategory(key)
        local selectedDefinition
        for _, definition in ipairs(SETTINGS_CATEGORIES) do
            local panel = categoryFrames[definition.key]
            if panel then
                if definition.key == key then panel:Show() else panel:Hide() end
            end
            local button = categoryButtons[definition.key]
            if button then EbonBuilds.Theme.SetTabSelected(button, definition.key == key) end
            if definition.key == key then selectedDefinition = definition end
        end
        if not selectedDefinition then
            key = "general"
            selectedDefinition = SETTINGS_CATEGORIES[1]
            local panel = categoryFrames.general
            if panel then panel:Show() end
            if categoryButtons.general then EbonBuilds.Theme.SetTabSelected(categoryButtons.general, true) end
        end
        activeCategoryKey = key
        pageTitle:SetText(selectedDefinition.title)
        pageDescription:SetText(selectedDefinition.description)
        EnsureSettingsDefaults().settingsCategory = key
        UpdateScrollRange()
    end

    local previousNavButton
    for _, definition in ipairs(SETTINGS_CATEGORIES) do
        local button = EbonBuilds.Theme.CreateTab(nav, definition.label)
        button:SetSize(126, 30)
        if previousNavButton then
            button:SetPoint("TOPLEFT", previousNavButton, "BOTTOMLEFT", 0, -5)
        else
            button:SetPoint("TOPLEFT", navHeading, "BOTTOMLEFT", 0, -10)
        end
        button:SetScript("OnClick", function() ShowCategory(definition.key) end)
        categoryButtons[definition.key] = button
        previousNavButton = button
    end

    local function NewCategoryPanel(key, height)
        local panel = CreateFrame("Frame", nil, scrollChild)
        panel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        panel:SetWidth(SETTINGS_CONTENT_WIDTH)
        panel:SetHeight(height or 1)
        panel._contentHeight = height or 1
        panel:Hide()
        categoryFrames[key] = panel
        return panel
    end

    local function AddSectionTitle(parent, text, y)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y)
        label:SetText(text)
        label:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))
        return label
    end

    local function AddSlider(parent, labelText, flavorText, y, minValue, maxValue, field)
        local card = CreateFrame("Frame", nil, parent)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        card:SetSize(SETTINGS_CONTENT_WIDTH - 4, 78)
        EbonBuilds.Theme.ApplyCard(card)

        local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
        label:SetText(labelText)

        local valueText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
        valueText:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))

        local flavor = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        flavor:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        flavor:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        flavor:SetJustifyH("LEFT")
        flavor:SetText(flavorText)

        local slider = CreateFrame("Slider", nil, card)
        if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
            EbonBuilds.Debug.ProtectScript(slider, "MainWindow.CardSlider")
        end
        slider:SetOrientation("HORIZONTAL")
        slider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 9)
        slider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 9)
        slider:SetHeight(18)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(0.1)
        EbonBuilds.Theme.SkinSlider(slider)
        slider:SetScript("OnValueChanged", function(_, value)
            valueText:SetText(string.format("%.1fs", value or 0))
            if draft then draft[field] = value end
            RefreshDirtyState()
        end)
        return slider
    end

    local function AddCheckbox(parent, labelText, flavorText, y, field)
        local card = CreateFrame("Frame", nil, parent)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        card:SetSize(SETTINGS_CONTENT_WIDTH - 4, 62)
        EbonBuilds.Theme.ApplyCard(card)

        local checkbox = EbonBuilds.Theme.CreateCheckbox(card, labelText)
        checkbox:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
        checkbox:SetScript("OnClick", function(self)
            if draft then draft[field] = self:GetChecked() and true or false end
            RefreshDirtyState()
        end)

        local flavor = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        flavor:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 26, -3)
        flavor:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        flavor:SetJustifyH("LEFT")
        flavor:SetText(flavorText)
        return checkbox
    end

    local function AddToolButton(parent, labelText, y, onClick, width)
        local button = EbonBuilds.Theme.CreateButton(parent)
        button:SetSize(width or 196, 24)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        button:SetText(labelText)
        button:SetScript("OnClick", onClick)
        return button
    end

    local function AddCategoryFailure(panel, source, err)
        categoryErrors[source] = tostring(err)
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("Settings." .. source, err)
        end
        panel._contentHeight = 150
        panel:SetHeight(150)
        local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
        heading:SetText("This settings section could not be displayed.")
        heading:SetTextColor(unpack(EbonBuilds.Theme.DANGER))
        local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
        note:SetWidth(390)
        note:SetJustifyH("LEFT")
        note:SetText("The error was recorded. Open the Error Log for details, then try the section again after /reload.")
        local openLog = EbonBuilds.Theme.CreateButton(panel)
        openLog:SetSize(118, 24)
        openLog:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
        openLog:SetText("Open Error Log")
        openLog:SetScript("OnClick", function()
            if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.ShowWindow then EbonBuilds.ErrorLog.ShowWindow() end
        end)
    end

    local function BuildCategory(key, height, builder)
        local panel = NewCategoryPanel(key, height)
        local ok, err = pcall(builder, panel)
        if not ok then AddCategoryFailure(panel, key, err) end
        return panel
    end

    BuildCategory("general", 196, function(panel)
        AddSectionTitle(panel, "TIMING", -2)
        controls.delaySlider = AddSlider(panel,
            "Action delay",
            "Very low values may cause offers to change before the client is ready.",
            -24, 0.1, 3.0, "evalDelay")
        controls.toastSlider = AddSlider(panel,
            "Toast duration",
            "How long Select, Reroll, Freeze, and Banish notifications stay visible.",
            -110, 0.5, 8.0, "toastDuration")
    end)

    BuildCategory("automation", 570, function(panel)
        AddSectionTitle(panel, "CONVENIENCE & DIAGNOSTICS", -2)
        controls.autoSellCB = AddCheckbox(panel,
            "Auto-sell junk at vendors",
            "Sells eligible zero-copper items while a vendor is open; unlearned affixes remain protected.",
            -24, "autoSell")
        controls.autoSellPoorOnlyCB = AddCheckbox(panel,
            "Only sell Poor (gray) quality",
            "Restricts the zero-copper sweep to Poor-quality items only, instead of any quality.",
            -92, "autoSellPoorOnly")
        controls.autoSellExcludeTradeGoodsCB = AddCheckbox(panel,
            "Never auto-sell Trade Goods",
            "Materials sometimes show as zero-copper but are still worth keeping (e.g. for professions).",
            -160, "autoSellExcludeTradeGoods")
        controls.autoSellExcludeRecipesCB = AddCheckbox(panel,
            "Never auto-sell Recipes",
            "Recipes/patterns can be zero-copper at a vendor but still worth learning or trading.",
            -228, "autoSellExcludeRecipes")
        controls.autoSellKeepListButton = AddToolButton(panel,
            "Manage Auto-Sell Keep List...",
            -296,
            function() EbonBuilds.AutoSell.ShowKeepListWindow() end)
        controls.bagDotsCB = AddCheckbox(panel,
            "Bag affix dots",
            "Marks bag items with an unlearned affix/rank (red/purple), an unbound BoE item (blue), or a likely disenchant candidate (teal).",
            -332, "bagDots")
        controls.debugCB = AddCheckbox(panel,
            "Detailed automation logging",
            "Records every automation decision and its reasoning in the Debug Log.",
            -400, "debugLog")
        controls.clickTraceCB = AddCheckbox(panel,
            "Log every button click",
            "Records interface clicks for troubleshooting actions that appear to do nothing.",
            -468, "clickTrace")
        controls.gearTooltipCB = AddCheckbox(panel,
            "Gear upgrade hints on tooltips",
            "Adds a line to item tooltips saying whether the item scores as an upgrade for the active build's spec.",
            -536, "gearTooltip")
    end)

    BuildCategory("interface", 290, function(panel)
        AddSectionTitle(panel, "LANGUAGE", -2)
        local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -26)
        note:SetWidth(400)
        note:SetJustifyH("LEFT")
        note:SetText("Choose the interface language. The selection is staged until Save changes and takes effect fully after /reload.")

        controls.languageButtons = {}
        local locales = EbonBuilds.Locale.GetSupportedLocales()
        local buttonWidth, gap, perRow = 76, 6, 5
        for index, entry in ipairs(locales) do
            local button = EbonBuilds.Theme.CreateButton(panel)
            button:SetSize(buttonWidth, 24)
            local column = (index - 1) % perRow
            local row = math.floor((index - 1) / perRow)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", 2 + column * (buttonWidth + gap), -62 - row * 30)
            button:SetText(entry.code)
            button._localeCode = entry.code
            button:SetScript("OnClick", function()
                if draft then draft.locale = entry.code end
                RefreshLocaleButtons()
                RefreshDirtyState()
            end)
            controls.languageButtons[#controls.languageButtons + 1] = button
        end


        local scaleTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scaleTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -134)
        scaleTitle:SetText("INTERFACE SCALE")
        scaleTitle:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))
        controls.scaleButtons = {}
        local presets = { { 0.9, "90%" }, { 1.0, "100%" }, { 1.1, "110%" }, { 1.2, "120%" } }
        for index, preset in ipairs(presets) do
            local button = EbonBuilds.Theme.CreateButton(panel)
            button:SetSize(92, 24)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", 2 + (index - 1) * 100, -158)
            button:SetText(preset[2])
            button._scaleValue = preset[1]
            button:SetScript("OnClick", function()
                if draft then draft.uiScale = preset[1] end
                RefreshScaleButtons()
                RefreshDirtyState()
            end)
            controls.scaleButtons[#controls.scaleButtons + 1] = button
        end

        local mapTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mapTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -198)
        mapTitle:SetText("WORLD MAP")
        mapTitle:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))
        controls.mapZonePanelCB = AddCheckbox(panel,
            "Show tome list on the world map",
            "The 'Tomes in this zone' panel; can also be closed directly from its own X button on the map.",
            -218, "mapZonePanel")
    end)

    BuildCategory("tools", 254, function(panel)
        AddSectionTitle(panel, "OPEN A WINDOW", -2)
        local leftX, rightX = 0, 210
        local rows = { -24, -56, -88, -120 }
        local function AddAt(label, column, row, handler)
            local button = EbonBuilds.Theme.CreateButton(panel)
            button:SetSize(196, 24)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", column == 1 and leftX or rightX, rows[row])
            button:SetText(label)
            button:SetScript("OnClick", handler)
            return button
        end
        AddAt("Commands guide", 1, 1, function()
            if EbonBuilds.ShowcaseView then EbonBuilds.ShowcaseView.Show() end
        end)
        AddAt("Tome Atlas", 2, 1, function()
            popup:Hide()
            if ownerFrame and not ownerFrame:IsShown() then ownerFrame:Show() end
            if EbonBuilds.ViewRouter then EbonBuilds.ViewRouter.Show("tomeAtlas") end
        end)
        AddAt("Affixes reference", 1, 2, function()
            popup:Hide()
            if ownerFrame and not ownerFrame:IsShown() then ownerFrame:Show() end
            if EbonBuilds.ViewRouter then EbonBuilds.ViewRouter.Show("affixes") end
        end)
        AddAt("Tuning Advisor", 2, 2, function()
            if EbonBuilds.Calibration then EbonBuilds.Calibration.ShowWindow() end
        end)
        AddAt("Debug log", 1, 3, function()
            if EbonBuilds.DebugLog then EbonBuilds.DebugLog.ShowWindow() end
        end)
        AddAt("Click Trace log", 2, 3, function()
            if EbonBuilds.ClickTrace then EbonBuilds.ClickTrace.ShowWindow() end
        end)
        AddAt("Error log", 1, 4, function()
            if EbonBuilds.ErrorLog then EbonBuilds.ErrorLog.ShowWindow() end
        end)

        local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -170)
        note:SetWidth(400)
        note:SetJustifyH("LEFT")
        note:SetText("Diagnostic windows are safe to open while settings contain unsaved changes. Closing Settings still discards the draft.")
    end)

    BuildCategory("build", 170, function(panel)
        AddSectionTitle(panel, "ACTIVE BUILD", -2)
        controls.buildNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        controls.buildNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -28)
        controls.buildNote:SetWidth(400)
        controls.buildNote:SetJustifyH("LEFT")
        controls.buildNote:SetText("No active build. Select one in the main window to use these tools.")

        controls.ewlBtn = AddToolButton(panel, "Export Wishlist (EWL)", -66, function()
            local build = EbonBuilds.Build.GetActive()
            if build and EbonBuilds.EWL then EbonBuilds.EWL.ShowExportDialog(build) end
        end)
        controls.clearTrainingBtn = AddToolButton(panel, "Clear Manual Training data", -98, function()
            local build = EbonBuilds.Build.GetActive()
            if not build then return end
            StaticPopupDialogs["EBONBUILDS_CLEAR_TRAINING"].text =
                "Clear Manual Training data for \"" .. (build.title or "?") .. "\"?\n\nThis cannot be undone."
            StaticPopup_Show("EBONBUILDS_CLEAR_TRAINING")
        end)
    end)

    local function RefreshBuildPanelState()
        if not controls.buildNote or not controls.ewlBtn or not controls.clearTrainingBtn then return end
        local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
        if build then
            controls.buildNote:SetText("Applies to \"" .. (build.title or "Untitled") .. "\".")
            controls.ewlBtn:Enable()
            controls.clearTrainingBtn:Enable()
        else
            controls.buildNote:SetText("No active build. Select one in the main window to use these tools.")
            controls.ewlBtn:Disable()
            controls.clearTrainingBtn:Disable()
        end
    end

    local fatalState = CreateFrame("Frame", nil, content)
    fatalState:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -68)
    fatalState:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -14, 12)
    EbonBuilds.Theme.ApplyCard(fatalState)
    fatalState:Hide()

    local fatalTitle = fatalState:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fatalTitle:SetPoint("TOPLEFT", fatalState, "TOPLEFT", 16, -18)
    fatalTitle:SetText("Settings could not be displayed.")
    fatalTitle:SetTextColor(unpack(EbonBuilds.Theme.DANGER))

    local fatalNote = fatalState:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fatalNote:SetPoint("TOPLEFT", fatalTitle, "BOTTOMLEFT", 0, -8)
    fatalNote:SetWidth(380)
    fatalNote:SetJustifyH("LEFT")
    fatalNote:SetText("The error was recorded. Open the Error Log for technical details or try loading the settings again.")

    local fatalLogBtn = EbonBuilds.Theme.CreateButton(fatalState)
    fatalLogBtn:SetSize(120, 24)
    fatalLogBtn:SetPoint("TOPLEFT", fatalNote, "BOTTOMLEFT", 0, -14)
    fatalLogBtn:SetText("Open Error Log")
    fatalLogBtn:SetScript("OnClick", function()
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.ShowWindow then EbonBuilds.ErrorLog.ShowWindow() end
    end)

    local fatalRetryBtn = EbonBuilds.Theme.CreateButton(fatalState)
    fatalRetryBtn:SetSize(90, 24)
    fatalRetryBtn:SetPoint("LEFT", fatalLogBtn, "RIGHT", 8, 0)
    fatalRetryBtn:SetText("Try Again")
    fatalRetryBtn:SetScript("OnClick", function()
        popup:Hide()
        popup:Show()
    end)

    local function ShowSettingsErrorState(err)
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("Settings.Open", err)
        end
        settingsScroll:Hide()
        settingsScrollBar:Hide()
        fatalState:Show()
        dirtyLabel:SetText("Settings failed to load")
        dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.DANGER))
        saveBtn:Disable()
    end

    local function HideSettingsErrorState()
        fatalState:Hide()
        settingsScroll:Show()
    end

    local function LoadDraft()
        baseline = ReadSavedDraft()
        draft = CopyDraft(baseline)
        RefreshControlsFromDraft()
        RefreshBuildPanelState()
    end

    local function CancelAndHide()
        draft = baseline and CopyDraft(baseline) or nil
        popup:Hide()
    end

    local function ApplyDraft()
        if not draft then return end
        local gs = EnsureSettingsDefaults()
        gs.evalDelay = draft.evalDelay
        gs.toastDuration = draft.toastDuration
        gs.uiScale = math.max(0.9, math.min(1.2, tonumber(draft.uiScale) or 1))
        EbonBuildsDB.ui = EbonBuildsDB.ui or {}
        EbonBuildsDB.ui.scalePreset = gs.uiScale
        ApplyShellLayout(ownerFrame, gs.uiScale)
        popup:SetScale(SafeScale(gs.uiScale, 640, 520))
        if EbonBuilds.EchoTable and EbonBuilds.EchoTable.RefreshScaleLabels then
            EbonBuilds.EchoTable.RefreshScaleLabels()
        end
        if EbonBuilds.AutoSell and EbonBuilds.AutoSell.SetEnabled then EbonBuilds.AutoSell.SetEnabled(draft.autoSell) end
        if EbonBuilds.AutoSell and EbonBuilds.AutoSell.SetCategory then
            EbonBuilds.AutoSell.SetCategory("poorOnly", draft.autoSellPoorOnly)
            EbonBuilds.AutoSell.SetCategory("excludeTradeGoods", draft.autoSellExcludeTradeGoods)
            EbonBuilds.AutoSell.SetCategory("excludeRecipes", draft.autoSellExcludeRecipes)
        end
        if EbonBuilds.BagAffixDots and EbonBuilds.BagAffixDots.SetEnabled then EbonBuilds.BagAffixDots.SetEnabled(draft.bagDots) end
        if EbonBuilds.DebugLog and EbonBuilds.DebugLog.SetEnabled then EbonBuilds.DebugLog.SetEnabled(draft.debugLog) end
        if EbonBuilds.ClickTrace and EbonBuilds.ClickTrace.SetEnabled then EbonBuilds.ClickTrace.SetEnabled(draft.clickTrace) end
        if EbonBuilds.GearTooltip and EbonBuilds.GearTooltip.SetEnabled then EbonBuilds.GearTooltip.SetEnabled(draft.gearTooltip) end
        if EbonBuilds.WorldIntegration and EbonBuilds.WorldIntegration.SetMapPanelEnabled then
            EbonBuilds.WorldIntegration.SetMapPanelEnabled(draft.mapZonePanel)
        end
        local localeChanged = baseline and draft.locale ~= baseline.locale
        if localeChanged and EbonBuilds.Locale and EbonBuilds.Locale.SetLocale then
            EbonBuilds.Locale.SetLocale(draft.locale)
        end
        baseline = CopyDraft(draft)
        popup:Hide()
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show(localeChanged and "Settings saved -- /reload to apply the language" or "Settings saved")
        end
    end

    saveBtn:SetScript("OnClick", ApplyDraft)
    cancelBtn:SetScript("OnClick", CancelAndHide)
    closeBtn:SetScript("OnClick", CancelAndHide)

    popup:SetScript("OnShow", function()
        HideSettingsErrorState()
        local gs = EnsureSettingsDefaults()
        local savedPos = gs.settingsWindowPos
        if savedPos and savedPos.x and savedPos.y then
            popup:ClearAllPoints()
            popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", savedPos.x, savedPos.y)
        end
        local ok, err = pcall(function()
            LoadDraft()
            ShowCategory(gs.settingsCategory or "general")
        end)
        if not ok then ShowSettingsErrorState(err) end
    end)

    popup:SetScript("OnHide", function()
        draft = nil
        baseline = nil
    end)

    popup:SetScript("OnSizeChanged", function()
        if popup:IsShown() then UpdateScrollRange() end
    end)

    if not popup._registeredForEscape then
        tinsert(UISpecialFrames, "EbonBuildsGlobalSettingsPopup")
        popup._registeredForEscape = true
    end

    popup._ShowCategory = ShowCategory
    popup._CountDirtyFields = CountDirtyFields
    popup._ShowSettingsErrorState = ShowSettingsErrorState
    popup._categoryErrors = categoryErrors
    return popup
end


local function CreateHeaderIconButton(frame, anchor, texture, tooltipTitle, tooltipBody)
    local btn = CreateFrame("Button", nil, frame)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "MainWindow.ToolbarButton")
    end
    btn:SetSize(24, 24)
    btn:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    btn:SetFrameLevel(100)
    EbonBuilds.Theme.ApplyCard(btn)

    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(texture)
    icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    btn._icon = icon

    btn:SetScript("OnEnter", function(self)
        EbonBuilds.Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0)
        GameTooltip:AddLine(tooltipBody, 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        EbonBuilds.Theme.SetCardHovered(self, false)
        GameTooltip:Hide()
    end)
    return btn
end

local function CreateSettingsButton(frame, popup, closeBtn)
    local btn = CreateHeaderIconButton(frame, closeBtn, "Interface\\Icons\\Trade_Engineering",
        "Settings", "Configure addon-wide timing and convenience features.")
    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    return btn
end

local function CreateHelpButton(frame, settingsBtn)
    local btn = CreateHeaderIconButton(frame, settingsBtn, "Interface\\Icons\\INV_Misc_Book_09",
        "Help and what's new", "Open the getting-started guide, feature explanations, and changelog.")
    btn:SetScript("OnClick", function()
        if EbonBuilds.FAQ and EbonBuilds.FAQ.Show then EbonBuilds.FAQ.Show() end
    end)
    return btn
end

local function CreateLeftColumn(frame)
    local col = CreateFrame("Frame", nil, frame)
    col:SetPoint("TOPLEFT",    frame, "TOPLEFT",    12, -44)
    col:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12,  12)
    local layout = frame._responsiveLayout
    col:SetWidth(layout and layout.sidebar or LEFT_WIDTH)
    EbonBuilds.Theme.ApplySidebar(col)
    return col
end

local function CreateRightPanel(frame, left)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT",     left,  "TOPRIGHT",     8, 0)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    EbonBuilds.Theme.ApplyPanel(panel)
    return panel
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(frame, "MainWindow.MainFrame")
    end
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    local savedScale = EbonBuildsDB.globalSettings and tonumber(EbonBuildsDB.globalSettings.uiScale)
        or EbonBuildsDB.ui and tonumber(EbonBuildsDB.ui.scalePreset) or 1
    ApplyShellLayout(frame, savedScale)

    -- Restore saved position, or default to center.
    local pos = EbonBuildsDB.windowPos
    if pos and pos.x and pos.y then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    ApplyBackdrop(frame)
    CreateTitleBar(frame)
    local closeBtn = CreateCloseButton(frame)

    local settingsPopup = BuildSettingsPopup(frame)
    local settingsBtn = CreateSettingsButton(frame, settingsPopup, closeBtn)
    CreateHelpButton(frame, settingsBtn)
    frame._settingsPopup = settingsPopup

    -- Standard WoW behavior: ESC closes the window.
    tinsert(UISpecialFrames, FRAME_NAME)

    frame:Hide()
    return frame
end


function EbonBuilds.MainWindow.SetPageContext(title)
    currentPageTitle = title or "Overview"
    if pageLabel then pageLabel:SetText("/  " .. currentPageTitle) end
end

function EbonBuilds.MainWindow.SetDirtyState(dirty)
    currentDirty = dirty and true or false
    if dirtyLabel then
        if currentDirty then
            dirtyLabel:SetText("Unsaved build changes")
            dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
        else
            dirtyLabel:SetText("")
        end
    end
end

function EbonBuilds.MainWindow.RefreshContext()
    if pageLabel then pageLabel:SetText("/  " .. (currentPageTitle or "Overview")) end
    if not contextLabel then return end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build then
        contextLabel:SetText("No active build")
        contextLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
        if automationPill and automationPill.label then automationPill.label:SetText("AUTOPILOT --") end
        if classAccent then classAccent:SetVertexColor(0.5, 0.5, 0.5, 0.6) end
        return
    end

    contextLabel:SetText(build.title or "Untitled")
    local r, g, b = EbonBuilds.Theme.ClassRGB(build.class)
    contextLabel:SetTextColor(r, g, b, 1)
    if classAccent then classAccent:SetVertexColor(r, g, b, 1) end

    local enabled = EbonBuilds.Build.IsAutomationEnabled(build)
    if automationPill and automationPill.label then
        automationPill.label:SetText(enabled and "AUTOPILOT ON" or "AUTOPILOT OFF")
        local c = enabled and EbonBuilds.Theme.SUCCESS or EbonBuilds.Theme.WARNING
        automationPill:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.98)
        automationPill:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
        automationPill.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    EbonBuilds.MainWindow.SetDirtyState(currentDirty)
end

function EbonBuilds.MainWindow.Init()
    local frame = BuildFrame()
    local left  = CreateLeftColumn(frame)
    local right = CreateRightPanel(frame, left)

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = left
    EbonBuilds.MainWindow._right = right
    ApplyShellLayout(frame, frame._requestedScale)

    -- Resolution and game UI-scale changes can alter UIParent without changing
    -- the saved addon preset. Re-resolve the same preset on the next scheduler
    -- pass so every anchored view receives one coherent resize.
    if UIParent and UIParent.HookScript and not EbonBuilds.MainWindow._screenSizeHooked then
        UIParent:HookScript("OnSizeChanged", function()
            EbonBuilds.Scheduler.After("mainWindow.responsiveLayout", 0, function()
                local live = EbonBuilds.MainWindow._frame
                if live then ApplyShellLayout(live, live._requestedScale or 1) end
            end, EbonBuilds.Scheduler.INTERACTIVE, true)
        end)
        EbonBuilds.MainWindow._screenSizeHooked = true
    end

    EbonBuilds.ViewRouter.SetContainer(right)
    frame:SetScript("OnShow", EbonBuilds.MainWindow.RefreshContext)
    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(EbonBuilds.MainWindow.RefreshContext)
    end
    EbonBuilds.MainWindow.RefreshContext()
    EbonBuilds.BuildList.Init(left)
    EbonBuilds.WeightsView.Init()
    EbonBuilds.BuildForm.Init()
    EbonBuilds.SettingsView.Init()
    EbonBuilds.BuildTabs.Init()
    EbonBuilds.BuildOverview.Init()
    EbonBuilds.PublicBuildsView.Init()

    EbonBuilds.ViewRouter.Register("welcome", {
        Show = function(container, _)
            EbonBuilds.WelcomeView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.WelcomeView.Unmount()
        end,
    })

    EbonBuilds.ViewRouter.Register("publicBuilds", {
        Show = function(container, _)
            EbonBuilds.PublicBuildsView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.PublicBuildsView.Unmount()
        end,
    })

    EbonBuilds.ViewRouter.Register("tomeAtlas", {
        Show = function(container, _)
            EbonBuilds.TomeAtlasView.Show(container)
        end,
        Hide = function()
            EbonBuilds.TomeAtlasView.Hide()
        end,
    })

    EbonBuilds.ViewRouter.Register("affixes", {
        Show = function(container, _)
            EbonBuilds.AffixView.Show(container)
        end,
        Hide = function()
            EbonBuilds.AffixView.Hide()
        end,
    })

    EbonBuilds.MainWindow._ShowInitialView()
end

function EbonBuilds.MainWindow._ShowInitialView()
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
end

SLASH_EbonBuilds1 = "/ebb"
SLASH_EbonBuilds2 = "/ebonbuilds"
SlashCmdList["EbonBuilds"] = function()
    EbonBuilds.MainWindow.Toggle()
end

function EbonBuilds.MainWindow.Toggle()
    local frame = EbonBuilds.MainWindow._frame
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        EbonBuilds.MainWindow._ShowInitialView()
        frame:Show()
    end
end
