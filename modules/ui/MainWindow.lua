-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level window shell (800x550) with left column and right panel.
-- Hosts the build list and the view router.

EbonBuilds.MainWindow = {}

local WINDOW_WIDTH  = 800
local WINDOW_HEIGHT = 550
local LEFT_WIDTH    = 200
local FRAME_NAME    = "EbonBuildsMainWindow"

local function ApplyBackdrop(frame)
    EbonBuilds.Theme.ApplyWindow(frame)
end

local function CreateTitleBar(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("EbonBuilds")

    local dragRegion = CreateFrame("Frame", nil, frame)
    dragRegion:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,   0)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -37, 0)
    dragRegion:SetHeight(30)
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Persist center position in UIParent coordinates.
        local cx, cy = frame:GetCenter()
        if cx and cy then
            EbonBuildsDB.windowPos = { x = cx, y = cy }
        end
    end)
end

local function CreateCloseButton(frame)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(100)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    return closeBtn
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

local function BuildSettingsPopup()
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    popup:SetSize(380, 430)
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
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Scrollable body: as this dialog gains more settings over time, a
    -- fixed-size popup with unclipped content would eventually overflow
    -- exactly like the old FAQ window did (see 2.14) -- a scrollframe
    -- means that can never happen here regardless of how much gets added.
    local scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsGlobalSettingsSF", popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -34, 50)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(330)
    -- Generous fixed height: this is a bounded set of controls (unlike the
    -- FAQ's ever-growing changelog), so a comfortably oversized scroll
    -- child costs nothing -- the scrollbar simply won't move if content is
    -- shorter than it.
    scrollChild:SetHeight(700)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local newScroll = self:GetVerticalScroll() - delta * 32
        self:SetVerticalScroll(math.max(0, math.min(newScroll, range)))
    end)

    -- Helper: label -> optional flavor text -> slider with track and value
    -- display. Anchored relative to the PREVIOUS element's actual rendered
    -- bottom edge (not a fixed pixel offset), so wrapped flavor text can
    -- never make two blocks overlap.
    local function AddSlider(labelText, flavorText, yAnchor, yOffset, minV, maxV, value)
        local label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", 0, yOffset)

        local anchorForSlider = label
        local flavor
        if flavorText then
            flavor = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            flavor:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
            flavor:SetWidth(320)
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

    -- Helper: native checkbox with a label and explanation, same
    -- previous-element-relative anchoring as AddSlider.
    local function AddCheckbox(labelText, flavorText, yAnchor, yOffset)
        local cb = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
        cb:SetWidth(24)
        cb:SetHeight(24)
        cb:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", -2, yOffset)

        local label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(labelText)

        local flavor = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        flavor:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, -2)
        flavor:SetWidth(300)
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

    popup:SetScript("OnShow", function()
        local gs = EbonBuildsDB.globalSettings
        delaySlider:SetValue(gs.evalDelay or 2)
        toastSlider:SetValue(gs.toastDuration or 3)
        autoSellCB:SetChecked(EbonBuilds.AutoSell and EbonBuilds.AutoSell.IsEnabled())
        bagDotsCB:SetChecked(EbonBuilds.BagAffixDots and EbonBuilds.BagAffixDots.IsEnabled())
        scrollFrame:SetVerticalScroll(0)
    end)

    return popup
end

local function CreateSettingsButton(frame, popup, closeBtn)
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(20, 20)
    btn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    btn:SetFrameLevel(100)

    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAllPoints(btn)

    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
end

local function CreateLeftColumn(frame)
    local col = CreateFrame("Frame", nil, frame)
    col:SetPoint("TOPLEFT",    frame, "TOPLEFT",    14, -34)
    col:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14,  14)
    col:SetWidth(LEFT_WIDTH)
    return col
end

local function CreateRightPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14 + LEFT_WIDTH + 6, -34)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    return panel
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetHeight(WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

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
    CreateSettingsButton(frame, settingsPopup, closeBtn)
    frame._settingsPopup = settingsPopup

    -- Standard WoW behavior: ESC closes the window.
    tinsert(UISpecialFrames, FRAME_NAME)

    frame:Hide()
    return frame
end

function EbonBuilds.MainWindow.Init()
    local frame = BuildFrame()
    local left  = CreateLeftColumn(frame)
    local right = CreateRightPanel(frame)

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = left
    EbonBuilds.MainWindow._right = right

    EbonBuilds.ViewRouter.SetContainer(right)
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
