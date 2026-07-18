-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level window shell with navigation and a high-contrast content panel.
-- Hosts the build list and the view router.

EbonBuilds.MainWindow = {}

local WINDOW_WIDTH  = 980
local WINDOW_HEIGHT = 660
local LEFT_WIDTH    = 230
local FRAME_NAME    = "EbonBuildsMainWindow"
local contextLabel
local pageLabel, dirtyLabel, automationPill, classAccent
local currentPageTitle = "Overview"
local currentDirty = false

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

local function CreateCloseButton(frame)
    local closeBtn = EbonBuilds.Theme.CreateCloseButton(frame)
    closeBtn:SetFrameLevel(100)
    return closeBtn
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

local function BuildSettingsPopup()
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    popup:SetSize(420, 500)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(popup)
    popup:Hide()

    -- Title bar / drag region
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", popup, "TOP", 0, -16)
    title:SetText("EbonBuilds Settings")

    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0,   0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -37, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    drag:SetScript("OnDragStop",  function() popup:StopMovingOrSizing() end)

    -- Close button for popup
    local closeBtn = EbonBuilds.Theme.CreateCloseButton(popup)

    -- Scrollable body: as this dialog gains more settings over time, a
    -- fixed-size popup with unclipped content would eventually overflow
    -- exactly like the old FAQ window did (see 2.14) -- a scrollframe
    -- means that can never happen here regardless of how much gets added.
    local scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsGlobalSettingsSF", popup)
    scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -24, 50)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(370)
    -- Start near the current content size. OnShow recalculates this from the
    -- final control positions so the dialog does not present a large empty
    -- scroll range when all settings already fit in the viewport.
    scrollChild:SetHeight(320)
    scrollFrame:SetScrollChild(scrollChild)

    local settingsScrollBar = EbonBuilds.Theme.CreateScrollBar(popup)
    settingsScrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 17, -2)
    settingsScrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 17, 2)
    settingsScrollBar:SetValueStep(28)
    settingsScrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    local function RefreshSettingsScrollRange()
        local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
        settingsScrollBar:SetMinMaxValues(0, maxScroll)
        if settingsScrollBar:GetValue() > maxScroll then settingsScrollBar:SetValue(maxScroll) end
    end
    scrollFrame:SetScript("OnSizeChanged", RefreshSettingsScrollRange)

    RefreshSettingsScrollRange()

    -- Helper: label -> optional flavor text -> slider with track and value
    -- display. Anchored relative to the PREVIOUS element's actual rendered
    -- bottom edge (not a fixed pixel offset), so wrapped flavor text can
    -- never make two blocks overlap.
    local function AddSlider(labelText, flavorText, yAnchor, yOffset, minV, maxV, value)
        local label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if yAnchor == scrollChild then
            -- The first control belongs at the visible top of the scroll child.
            -- Anchoring it to scrollChild's BOTTOMLEFT placed the entire settings
            -- form below the viewport, leaving a blank black dialog.
            label:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        else
            label:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", 0, yOffset)
        end

        local anchorForSlider = label
        local flavor
        if flavorText then
            flavor = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            flavor:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
            flavor:SetWidth(360)
            flavor:SetJustifyH("LEFT")
            flavor:SetText(flavorText)
            anchorForSlider = flavor
        end

        local slider = CreateFrame("Slider", nil, scrollChild)
        slider:SetOrientation("HORIZONTAL")
        slider:SetWidth(190)
        slider:SetHeight(20)
        slider:SetPoint("TOPLEFT", anchorForSlider, "BOTTOMLEFT", 0, -4)
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(0.1)
        slider:SetValue(value)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.25, 0.25, 0.25, 1)
        track:SetHeight(6)
        track:SetPoint("CENTER", slider)
        track:SetPoint("LEFT", slider)
        track:SetPoint("RIGHT", slider)

        local valText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valText:SetPoint("LEFT", slider, "RIGHT", 6, 0)

        local function RefreshLabel()
            local v = slider:GetValue()
            label:SetText(string.format("%s %.1fs", labelText, v))
            valText:SetText(string.format("%.1fs", v))
        end

        slider:SetScript("OnValueChanged", RefreshLabel)
        RefreshLabel()

        return slider, slider
    end

    -- Helper: themed checkbox with a label and explanation, same
    -- previous-element-relative anchoring as AddSlider.
    local function AddCheckbox(labelText, flavorText, yAnchor, yOffset)
        local cb = EbonBuilds.Theme.CreateCheckbox(scrollChild, labelText)
        cb:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", -2, yOffset)

        local flavor = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        flavor:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, -2)
        flavor:SetWidth(340)
        flavor:SetJustifyH("LEFT")
        flavor:SetText(flavorText)

        return cb, flavor
    end

    local delaySlider, delayBottom = AddSlider(
        "Action delay:",
        "Very low values may cause the addon to malfunction.",
        scrollChild, 0, 0.1, 3.0, 2)

    local toastSlider, toastBottom = AddSlider(
        "Toast duration:",
        "How long pick/reroll/freeze/banish notifications stay on screen.",
        delayBottom, -14, 0.5, 8.0, 3)

    -- Section header for the on/off feature toggles below
    local togglesHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    togglesHeader:SetPoint("TOPLEFT", toastBottom, "BOTTOMLEFT", 0, -18)
    togglesHeader:SetText("Feature toggles")
    togglesHeader:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))

    local autoSellCB, autoSellBottom = AddCheckbox(
        "Auto-sell junk at vendors",
        "Sells 0-copper bag items automatically while a vendor is open. Items with an unlearned affix stay protected even if worthless. Same as /ebb autosell.",
        togglesHeader, -8)

    local bagDotsCB, bagDotsBottom = AddCheckbox(
        "Bag affix dots",
        "Colored dot on bag items missing an affix: red for a new line, purple for a rank you're missing on one you already have. Same as /ebb bagdots.",
        autoSellBottom, -10)

    local function RefreshSettingsContentHeight()
        local childTop = scrollChild:GetTop()
        local contentBottom = bagDotsBottom:GetBottom()
        local viewportHeight = scrollFrame:GetHeight() or 0
        if childTop and contentBottom then
            scrollChild:SetHeight(math.max(viewportHeight, childTop - contentBottom + 14))
        else
            scrollChild:SetHeight(math.max(viewportHeight, 320))
        end
        RefreshSettingsScrollRange()
    end

    -- Buttons (outside the scrollframe, always visible)
    local saveBtn = EbonBuilds.Theme.CreateButton(popup)
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("BOTTOM", popup, "BOTTOM", 43, 18)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local gs = EbonBuildsDB.globalSettings
        gs.evalDelay = delaySlider:GetValue()
        gs.toastDuration = toastSlider:GetValue()
        local autoSellOn, bagDotsOn
        if EbonBuilds.AutoSell then
            autoSellOn = autoSellCB:GetChecked() and true or false
            EbonBuilds.AutoSell.SetEnabled(autoSellOn)
        end
        if EbonBuilds.BagAffixDots then
            bagDotsOn = bagDotsCB:GetChecked() and true or false
            EbonBuilds.BagAffixDots.SetEnabled(bagDotsOn)
        end
        popup:Hide()
        -- Confirms the settings actually took effect -- previously Save
        -- just closed the popup silently with no feedback at all, so
        -- there was no way to tell a toggle click had actually been
        -- saved versus just visually checked in the box.
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            local parts = {}
            if autoSellOn ~= nil then parts[#parts + 1] = "Auto-sell " .. (autoSellOn and "ON" or "OFF") end
            if bagDotsOn ~= nil then parts[#parts + 1] = "Bag dots " .. (bagDotsOn and "ON" or "OFF") end
            local msg = "Settings saved"
            if #parts > 0 then msg = msg .. " (" .. table.concat(parts, ", ") .. ")" end
            EbonBuilds.Toast.Show(msg)
        end
    end)

    local cancelBtn = EbonBuilds.Theme.CreateButton(popup)
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", -43, 18)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    EbonBuilds.Theme.BindScrollWheel(scrollFrame, settingsScrollBar, 32, scrollChild)

    popup:SetScript("OnShow", function()
        local gs = EbonBuildsDB.globalSettings
        delaySlider:SetValue(gs.evalDelay or 2)
        toastSlider:SetValue(gs.toastDuration or 3)
        autoSellCB:SetChecked(EbonBuilds.AutoSell and EbonBuilds.AutoSell.IsEnabled())
        bagDotsCB:SetChecked(EbonBuilds.BagAffixDots and EbonBuilds.BagAffixDots.IsEnabled())
        RefreshSettingsContentHeight()
        settingsScrollBar:SetValue(0)
    end)

    return popup
end

local function CreateHeaderIconButton(frame, anchor, texture, tooltipTitle, tooltipBody)
    local btn = CreateFrame("Button", nil, frame)
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
    col:SetWidth(LEFT_WIDTH)
    EbonBuilds.Theme.ApplySidebar(col)
    return col
end

local function CreateRightPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12 + LEFT_WIDTH + 8, -44)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    EbonBuilds.Theme.ApplyPanel(panel)
    return panel
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetHeight(WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

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

    local settingsPopup = BuildSettingsPopup()
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

    local enabled = build.automationEnabled ~= false
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
    local right = CreateRightPanel(frame)

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = left
    EbonBuilds.MainWindow._right = right

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
SlashCmdList["EbonBuilds"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "debug" then
        EbonBuilds.DebugLog.Toggle()
    elseif msg == "debuglog" or msg == "log" then
        EbonBuilds.DebugLog.ShowWindow()
    elseif msg == "faq" or msg == "help" or msg == "whatsnew" then
        EbonBuilds.FAQ.Show()
    elseif msg == "showcase" or msg == "commands" or msg == "welcome" then
        EbonBuilds.ShowcaseView.Show()
    elseif msg == "atlas" or msg == "tomes" then
        EbonBuilds.MainWindow.Toggle()
        EbonBuilds.ViewRouter.Show("tomeAtlas")
    elseif msg == "affix" or msg == "affixes" then
        EbonBuilds.MainWindow.Toggle()
        EbonBuilds.ViewRouter.Show("affixes")
    elseif msg == "clicktrace" then
        EbonBuilds.ClickTrace.SetEnabled(not EbonBuilds.ClickTrace.IsEnabled())
        EbonBuilds.ClickTrace.ShowWindow()
    elseif msg == "errors" or msg == "errorlog" then
        EbonBuilds.ErrorLog.ShowWindow()
    elseif msg == "tuning" or msg == "advisor" then
        EbonBuilds.Calibration.ShowWindow()
    elseif msg == "ewl" or msg == "wishlist" then
        local build = EbonBuilds.Build.GetActive()
        if not build then
            DEFAULT_CHAT_FRAME:AddMessage("|cff44ff44EbonBuilds:|r No active build.")
        elseif EbonBuilds.EWL then
            EbonBuilds.EWL.ShowExportDialog(build)
        end
    elseif msg == "cleartraining" then
        local build = EbonBuilds.Build.GetActive()
        if not build then
            DEFAULT_CHAT_FRAME:AddMessage("|cff44ff44EbonBuilds:|r No active build.")
        else
            EbonBuilds.ManualTraining.Clear(build.id)
            DEFAULT_CHAT_FRAME:AddMessage("|cff44ff44EbonBuilds:|r Cleared manual training data for \"" .. (build.title or "?") .. "\".")
        end
    elseif msg == "autosell" then
        local on = not EbonBuilds.AutoSell.IsEnabled()
        EbonBuilds.AutoSell.SetEnabled(on)
        DEFAULT_CHAT_FRAME:AddMessage("|cff44ff44EbonBuilds:|r Auto-sell junk at vendors is now " ..
            (on and "|cff44ff44ON|r" or "|cffff4444OFF|r") .. ".")
    elseif msg == "bagdots" then
        local on = not EbonBuilds.BagAffixDots.IsEnabled()
        EbonBuilds.BagAffixDots.SetEnabled(on)
        DEFAULT_CHAT_FRAME:AddMessage("|cff44ff44EbonBuilds:|r Bag affix dots are now " ..
            (on and "|cff44ff44ON|r" or "|cffff4444OFF|r") .. ".")
    else
        EbonBuilds.MainWindow.Toggle()
    end
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

function EbonBuilds.MainWindow.GetRightPanel()
    return EbonBuilds.MainWindow._right
end
