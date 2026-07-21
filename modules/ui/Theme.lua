local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/Theme.lua
-- Shared visual language and reusable UI helpers for the addon.
-- All textures and APIs used here are safe for WoW 3.3.5a.

EbonBuilds.Theme = {}

local T = EbonBuilds.Theme
local R = EbonBuilds.ThemeRegistry.Get()
local FLAT = R.textures.flat

-- Compatibility aliases for existing components. New code consumes semantic
-- tokens from ThemeRegistry directly; these aliases keep the refactor atomic.
T.WINDOW_BG = R.colors.surfaceWindow
T.PANEL_BG = R.colors.surfacePanel
T.CARD_BG = R.colors.surfaceCard
T.CARD_HOVER = R.colors.surfaceCardHover
T.INPUT_BG = R.colors.surfaceInput
T.BORDER = R.colors.border
T.BORDER_DIM = R.colors.borderDim
T.ACCENT_GOLD = R.colors.accent
T.ACCENT_HEX = R.colorHex.accent
T.FOCUS = R.colors.accent
T.SELECTED_BG = R.colors.selected
T.SUCCESS = R.colors.success
T.WARNING = R.colors.warning
T.PRESENCE_TEAL = R.colors.presence
T.PRESENCE_TEAL_HEX = R.colorHex.presence
T.DANGER = R.colors.danger
T.TEXT_PRIMARY = R.colors.textPrimary
T.TEXT_MUTED = R.colors.textMuted
T.Registry = R

local NORMAL_BACKDROP = {
    bgFile   = FLAT,
    edgeFile = FLAT,
    edgeSize = R.sizes.border,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- A one-unit edge becomes only 0.9 physical pixels at the lowest supported
-- addon scale. The 3.3.5 renderer rounds those fractional edges inconsistently,
-- which makes the right/bottom portions appear cut off. Use a two-unit edge at
-- low scale so every side survives rasterization as at least one full pixel.
local LOW_SCALE_BACKDROP = {
    bgFile   = FLAT,
    edgeFile = FLAT,
    edgeSize = R.sizes.borderLowScale,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

local appliedScale
local backdropFrames = setmetatable({}, { __mode = "k" })

local function CurrentAddonScale()
    return tonumber(appliedScale)
        or tonumber(EbonBuildsDB and EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.uiScale)
        or 1
end

-- Border rasterization depends on the final physical scale. WoW's global UI
-- scale can reduce a one-unit edge below one physical pixel even when the
-- addon setting is 1.0, causing individual edges to disappear according to
-- screen position. Keep the decision centralized for every themed control.
local function CurrentRasterScale(frame)
    if frame and frame.GetEffectiveScale then
        local effective = tonumber(frame:GetEffectiveScale())
        if effective and effective > 0 then return effective end
    end

    local parentScale = 1
    if UIParent and UIParent.GetEffectiveScale then
        parentScale = tonumber(UIParent:GetEffectiveScale()) or 1
    end
    return CurrentAddonScale() * parentScale
end

local function CurrentBackdrop(frame)
    return CurrentRasterScale(frame) < 0.95 and LOW_SCALE_BACKDROP or NORMAL_BACKDROP
end

local function InstallBackdrop(frame)
    frame:SetBackdrop(CurrentBackdrop(frame))
    backdropFrames[frame] = true
end

function T.ApplyBackdropDefinition(frame)
    if frame then InstallBackdrop(frame) end
end

function T.SetAppliedScale(scale)
    appliedScale = tonumber(scale) or 1
    for frame in pairs(backdropFrames) do
        local background = frame.GetBackdropColor and { frame:GetBackdropColor() } or nil
        local border = frame.GetBackdropBorderColor and { frame:GetBackdropBorderColor() } or nil
        frame:SetBackdrop(CurrentBackdrop(frame))
        if background and background[1] then frame:SetBackdropColor(unpack(background)) end
        if border and border[1] then frame:SetBackdropBorderColor(unpack(border)) end
    end
end

local function ApplySurface(frame, background, border)
    InstallBackdrop(frame)
    frame:SetBackdropColor(unpack(background))
    frame:SetBackdropBorderColor(unpack(border))
end

function T.ApplyWindow(frame)
    ApplySurface(frame, T.WINDOW_BG, T.BORDER)
end

function T.ApplyPanel(frame)
    ApplySurface(frame, T.PANEL_BG, T.BORDER_DIM)
end

function T.ApplyCard(frame)
    ApplySurface(frame, T.CARD_BG, T.BORDER_DIM)
end

function T.SetCardHovered(frame, hovered)
    if hovered then
        frame:SetBackdropColor(unpack(T.CARD_HOVER))
        frame:SetBackdropBorderColor(unpack(T.BORDER))
    else
        frame:SetBackdropColor(unpack(T.CARD_BG))
        frame:SetBackdropBorderColor(unpack(T.BORDER_DIM))
    end
end

-- Runs a widget-specific hover cleanup when WoW hides or recycles the frame
-- without delivering OnLeave. This happens frequently when a click changes
-- views, opens a popup over the control, or rebinds a virtualized row.
function T.BindHoverReset(frame, reset)
    if not frame or type(reset) ~= "function" then return frame end
    frame._ebonHoverReset = reset
    if not frame._ebonHoverResetHooked then
        frame._ebonHoverResetHooked = true
        frame:HookScript("OnHide", function(self)
            local handler = self._ebonHoverReset
            if handler then handler(self) end
        end)
    end
    return frame
end

function T.ApplyInput(frame)
    ApplySurface(frame, T.INPUT_BG, T.BORDER_DIM)
    frame._uiState = "normal"
end

-- State is one of: normal, focus, error, disabled, success.
function T.SetInputState(frame, state)
    if not frame then return end
    frame._uiState = state or "normal"
    if state == "focus" then
        frame:SetBackdropColor(unpack(T.INPUT_BG))
        frame:SetBackdropBorderColor(unpack(T.FOCUS))
    elseif state == "error" then
        frame:SetBackdropColor(unpack(R.colors.surfaceInputError))
        frame:SetBackdropBorderColor(unpack(T.DANGER))
    elseif state == "success" then
        frame:SetBackdropColor(unpack(T.INPUT_BG))
        frame:SetBackdropBorderColor(unpack(T.SUCCESS))
    elseif state == "disabled" then
        frame:SetBackdropColor(unpack(R.colors.surfaceInputDisabled))
        frame:SetBackdropBorderColor(unpack(R.colors.borderDisabled))
    else
        frame:SetBackdropColor(unpack(T.INPUT_BG))
        frame:SetBackdropBorderColor(unpack(T.BORDER_DIM))
    end
end

-- Adds a consistent focus ring without replacing any module-specific scripts.
function T.WireEditBox(box, container)
    if not box or not container or box._ebonThemeWired then return end
    box._ebonThemeWired = true
    box:HookScript("OnEditFocusGained", function()
        if not box._error then T.SetInputState(container, "focus") end
    end)
    box:HookScript("OnEditFocusLost", function()
        if box._error then
            T.SetInputState(container, "error")
        else
            T.SetInputState(container, "normal")
        end
    end)
end

-- Small magnifying-glass icon (the same one Blizzard's own search boxes
-- use, e.g. Friends/Guild roster) anchored to a search box container's left
-- edge, so every search field in the addon reads as "search" at a glance
-- instead of some looking like plain text inputs. Returns the icon texture;
-- callers that indent their edit box to make room should offset text start
-- by ~16px from the container's left edge.
function T.AddSearchIcon(container)
    if not container then return nil end
    local icon = container:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(R.textures.search)
    icon:SetSize(R.sizes.iconSmall, R.sizes.iconSmall)
    icon:SetPoint("LEFT", container, "LEFT", 4, 0)
    icon:SetVertexColor(T.TEXT_MUTED[1], T.TEXT_MUTED[2], T.TEXT_MUTED[3], 0.85)
    return icon
end

-- Thin gold divider line under headers.
function T.AddHeaderRule(parent, anchorFontString, width)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(T.ACCENT_GOLD[1], T.ACCENT_GOLD[2], T.ACCENT_GOLD[3], 0.45)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", anchorFontString, "BOTTOMLEFT", 0, -4)
    rule:SetWidth(width or 200)
    return rule
end

-- Reusable section card. The caller anchors/sizes the returned panel and may
-- place controls relative to panel._contentAnchor.
function T.CreateSection(parent, titleText, subtitleText)
    local panel = CreateFrame("Frame", nil, parent)
    T.ApplyCard(panel)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    title:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetText(titleText or "")
    title:SetTextColor(unpack(T.TEXT_PRIMARY))

    local subtitle
    if subtitleText and subtitleText ~= "" then
        subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText(subtitleText)
        subtitle:SetTextColor(unpack(T.TEXT_MUTED))
    end

    panel._title = title
    panel._subtitle = subtitle
    panel._contentAnchor = subtitle or title
    return panel
end

function T.AttachTooltip(frame, titleText, bodyText, anchor)
    if not frame then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetToplevel(true)
        GameTooltip:SetClampedToScreen(true)
        GameTooltip:ClearLines()
        if titleText and titleText ~= "" then GameTooltip:AddLine(titleText, 1, 0.82, 0) end
        if bodyText and bodyText ~= "" then GameTooltip:AddLine(bodyText, 0.82, 0.82, 0.86, true) end
        GameTooltip:Show()
        GameTooltip:Raise()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Canonical class colors (WotLK RAID_CLASS_COLORS values).
T.CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.0,  0.96, 0.41 },
    PRIEST      = { 1.0,  1.0,  1.0  },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.0,  0.44, 0.87 },
    MAGE        = { 0.41, 0.8,  0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.0,  0.49, 0.04 },
}

function T.ClassRGB(token)
    local c = T.CLASS_COLORS[token]
    if c then return c[1], c[2], c[3] end
    return 0.5, 0.5, 0.5
end

------------------------------------------------------------------------
-- Buttons and tabs
------------------------------------------------------------------------

local BTN_BG          = { 0.145, 0.145, 0.185, 1.0 }
local BTN_BG_HOVER    = { 0.225, 0.225, 0.285, 1.0 }
local BTN_BG_DOWN     = { 0.075, 0.075, 0.105, 1.0 }
local BTN_BG_DISABLED = { 0.075, 0.075, 0.090, 0.75 }

local ACCENT_BORDERS = {
    gold   = { 0.95, 0.72, 0.05, 1.0 },
    danger = { 0.70, 0.18, 0.18, 1.0 },
    good   = { 0.18, 0.66, 0.27, 1.0 },
}

local function ApplyButtonVisual(btn, background, border)
    btn:SetBackdropColor(unpack(background))
    btn:SetBackdropBorderColor(unpack(border))
end

-- Restore a button to its canonical non-hover visual state. This is required
-- for recycled widgets because WoW may not fire OnLeave when a popup or
-- full-screen click catcher appears over the button that was clicked.
function T.ResetButtonVisual(btn)
    if not btn then return end

    local label = btn.GetFontString and btn:GetFontString() or nil
    if btn.IsEnabled and btn:IsEnabled() ~= 1 then
        local c = btn._accentBorder or T.BORDER_DIM
        btn:SetBackdropColor(unpack(BTN_BG_DISABLED))
        btn:SetBackdropBorderColor(c[1], c[2], c[3], btn._accentBorder and 0.42 or 0.70)
        if label then label:SetTextColor(0.52, 0.52, 0.56) end
        return
    end

    if btn._tabSelected then
        btn._accentBorder = ACCENT_BORDERS.gold
        btn:SetBackdropColor(unpack(T.SELECTED_BG))
        btn:SetBackdropBorderColor(unpack(ACCENT_BORDERS.gold))
        if label then label:SetTextColor(1, 0.90, 0.35) end
        return
    end

    -- Tabs use a muted neutral label while idle. Previously every tab's
    -- OnLeave passed through the generic button reset below, which changed
    -- the hovered navigation label to gold until another selection refresh.
    if btn._tabSelected ~= nil then
        btn._accentBorder = nil
        ApplyButtonVisual(btn, BTN_BG, T.BORDER_DIM)
        if label then label:SetTextColor(0.82, 0.82, 0.86) end
        return
    end

    ApplyButtonVisual(btn, BTN_BG, btn._accentBorder or T.BORDER_DIM)
    -- Generic buttons are allowed to use context-specific text colors. The
    -- old reset forced every label back to gold on OnLeave, so hovering a
    -- muted navigation/action button permanently changed its text color.
    -- Tabs and disabled buttons have explicit states above; ordinary buttons
    -- keep whichever text color their owning view assigned.
end

function T.SkinButton(btn)
    btn:SetNormalTexture("")
    btn:SetPushedTexture("")
    btn:SetHighlightTexture("")
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    InstallBackdrop(btn)
    ApplyButtonVisual(btn, BTN_BG, btn._accentBorder or T.BORDER_DIM)

    btn:HookScript("OnEnter", function(self)
        if self:IsEnabled() == 1 then
            ApplyButtonVisual(self, BTN_BG_HOVER, self._accentBorder or T.BORDER)
        end
    end)
    btn:HookScript("OnLeave", function(self)
        T.ResetButtonVisual(self)
    end)
    btn:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() == 1 then ApplyButtonVisual(self, BTN_BG_DOWN, self._accentBorder or T.BORDER) end
    end)
    btn:HookScript("OnMouseUp", function(self)
        if self:IsEnabled() == 1 then
            if self.IsMouseOver and self:IsMouseOver() then
                ApplyButtonVisual(self, BTN_BG_HOVER, self._accentBorder or T.BORDER)
            else
                ApplyButtonVisual(self, BTN_BG, self._accentBorder or T.BORDER_DIM)
            end
        end
    end)
    btn:HookScript("OnDisable", function(self)
        local c = self._accentBorder or T.BORDER_DIM
        local label = self:GetFontString()
        if label and label.GetTextColor then
            self._enabledTextColor = { label:GetTextColor() }
        end
        self:SetBackdropColor(unpack(BTN_BG_DISABLED))
        self:SetBackdropBorderColor(c[1], c[2], c[3], self._accentBorder and 0.42 or 0.70)
        if label then label:SetTextColor(0.52, 0.52, 0.56) end
    end)
    btn:HookScript("OnEnable", function(self)
        T.ResetButtonVisual(self)
        local label = self:GetFontString()
        local color = self._enabledTextColor
        if label and color and self._tabSelected == nil then
            label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        self._enabledTextColor = nil
    end)
    T.BindHoverReset(btn, T.ResetButtonVisual)
    return btn
end

function T.CreateButton(parent, accent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    T.SkinButton(btn)
    if accent then T.SetButtonAccent(btn, accent) end
    -- Every OnClick a caller attaches to this button from here on is
    -- auto-wrapped in ErrorLog.Protect, without the caller having to do
    -- anything -- see core/Debug.lua for why this exists.
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "Theme.Button")
    end
    btn:HookScript("OnClick", function(self)
        if EbonBuilds.ClickTrace then
            EbonBuilds.ClickTrace.Log("click", self:GetText() or self:GetName() or "?")
        end
    end)
    return btn
end

function T.SetButtonAccent(btn, accent)
    local c = ACCENT_BORDERS[accent]
    if not c then return end
    btn._accentBorder = c
    T.ResetButtonVisual(btn)
end

function T.ClearButtonAccent(btn)
    btn._accentBorder = nil
    T.ResetButtonVisual(btn)
end

-- Custom flat tabs provide a stronger selected state than the small WotLK
-- parchment tabs and remain legible over every game-world background.
function T.CreateTab(parent, text)
    local btn = T.CreateButton(parent)
    btn:SetHeight(26)
    btn:SetText(text or "")
    btn._tabSelected = false
    return btn
end

function T.SetTabSelected(btn, selected)
    if not btn then return end
    btn._tabSelected = selected and true or false
    if selected then
        btn._accentBorder = ACCENT_BORDERS.gold
        btn:SetBackdropColor(unpack(T.SELECTED_BG))
        btn:SetBackdropBorderColor(unpack(ACCENT_BORDERS.gold))
        if btn:GetFontString() then btn:GetFontString():SetTextColor(1, 0.90, 0.35) end
    else
        btn._accentBorder = nil
        btn:SetBackdropColor(unpack(BTN_BG))
        btn:SetBackdropBorderColor(unpack(T.BORDER_DIM))
        if btn:GetFontString() then btn:GetFontString():SetTextColor(0.82, 0.82, 0.86) end
    end
end

-- Compact text badge used for non-color-only status communication.
function T.CreateStatusPill(parent, text, kind)
    local frame = CreateFrame("Frame", nil, parent)
    InstallBackdrop(frame)
    frame:SetHeight(16)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", frame, "LEFT", 5, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    label:SetJustifyH("CENTER")
    label:SetText(text or "")
    frame.label = label

    local c = kind == "success" and T.SUCCESS or kind == "warning" and T.WARNING or kind == "danger" and T.DANGER or T.BORDER
    frame:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.98)
    frame:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
    label:SetTextColor(c[1], c[2], c[3], 1)
    return frame
end


------------------------------------------------------------------------
-- Dropdowns and sliders
------------------------------------------------------------------------

local dropdownMenus = setmetatable({}, { __mode = "k" })

local function CloseDropdownMenu(dropdown)
    if not dropdown then return end
    if dropdown._menu then dropdown._menu:Hide() end
    if dropdown._container and dropdown._container._uiState ~= "error" then
        T.SetInputState(dropdown._container, "normal")
    end
end

local function CloseOtherDropdownMenus(except)
    for dropdown in pairs(dropdownMenus) do
        if dropdown ~= except then CloseDropdownMenu(dropdown) end
    end
end

function T.CreateDropdown(parent, width, defaultText, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or 140, 24)

    local container = CreateFrame("Frame", nil, frame)
    container:SetAllPoints(frame)
    T.ApplyInput(container)
    frame._container = container

    local button = CreateFrame("Button", nil, container)
    button:SetAllPoints(container)
    frame._button = button
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(button, "Theme.Dropdown.Button")
    end

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", container, "LEFT", 8, 0)
    label:SetPoint("RIGHT", container, "RIGHT", -22, 0)
    label:SetJustifyH("LEFT")
    label:SetText(defaultText or "Select")
    label:SetTextColor(unpack(T.TEXT_PRIMARY))
    frame._label = label
    frame._defaultText = defaultText or "Select"

    local caret = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caret:SetPoint("RIGHT", container, "RIGHT", -7, 0)
    caret:SetText("v")
    caret:SetTextColor(unpack(T.TEXT_MUTED))
    frame._caret = caret

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    T.ApplyPanel(menu)
    menu:Hide()
    menu:SetClampedToScreen(true)
    frame._menu = menu
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(menu, "Theme.Dropdown.Menu")
    end

    local optionButtons = {}
    local footerButton

    local function EnsureOptionButton(index)
        local btn = optionButtons[index]
        if btn then return btn end
        btn = CreateFrame("Button", nil, menu)
        if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
            EbonBuilds.Debug.ProtectScript(btn, "Theme.Dropdown.Option")
        end
        btn:SetHeight(22)
        InstallBackdrop(btn)
        btn:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
        btn:SetBackdropBorderColor(0.16, 0.16, 0.20, 1)

        local mark = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mark:SetPoint("LEFT", btn, "LEFT", 7, 0)
        mark:SetWidth(10)
        mark:SetJustifyH("CENTER")
        btn._mark = mark

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", mark, "RIGHT", 5, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        btn._text = text

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(T.CARD_HOVER))
            self:SetBackdropBorderColor(unpack(T.BORDER))
            if self._tooltipTitle or self._tooltipBody then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self._tooltipTitle then GameTooltip:AddLine(self._tooltipTitle, 1, 0.82, 0) end
                if self._tooltipBody then GameTooltip:AddLine(self._tooltipBody, 0.82, 0.82, 0.86, true) end
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
            self:SetBackdropBorderColor(0.16, 0.16, 0.20, 1)
        end)
        T.BindHoverReset(btn, function(self)
            GameTooltip:Hide()
            self:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
            self:SetBackdropBorderColor(0.16, 0.16, 0.20, 1)
        end)

        optionButtons[index] = btn
        return btn
    end

    local function RebuildMenu()
        local builder = frame._builder or opts.buildMenu
        local items = builder and builder() or {}
        local itemCount = #items
        local menuWidth = math.max(frame:GetWidth(), opts.menuWidth or frame:GetWidth())
        local rowHeight = opts.rowHeight or 22
        local footerHeight = opts.multiSelect and 26 or 0
        local height = itemCount * rowHeight + 8 + footerHeight
        menu:SetWidth(menuWidth)
        menu:SetHeight(math.max(30, height))

        for i = 1, itemCount do
            local item = items[i]
            local btn = EnsureOptionButton(i)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * rowHeight)
            btn:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
            btn:SetHeight(rowHeight - 2)
            btn._mark:SetText(item.checked and "x" or "")
            btn._text:SetText(item.text or "")
            if item.color then btn._text:SetTextColor(unpack(item.color)) else btn._text:SetTextColor(unpack(T.TEXT_PRIMARY)) end
            btn._tooltipTitle = item.tooltipTitle
            btn._tooltipBody = item.tooltipBody
            if item.disabled then
                btn:Disable()
                btn._text:SetTextColor(0.45, 0.45, 0.50)
                btn._mark:SetTextColor(0.35, 0.35, 0.40)
            else
                btn:Enable()
                btn._mark:SetTextColor(1, 0.82, 0, 1)
            end
            btn:SetScript("OnClick", function()
                if item.func then item.func() end
                if not (opts.multiSelect or item.keepShownOnClick) then
                    CloseDropdownMenu(frame)
                else
                    RebuildMenu()
                end
            end)
            btn:Show()
        end
        for i = itemCount + 1, #optionButtons do optionButtons[i]:Hide() end

        if opts.multiSelect then
            if not footerButton then
                footerButton = T.CreateButton(menu)
                footerButton:SetSize(48, 20)
                footerButton:SetText("Done")
                footerButton:SetScript("OnClick", function() CloseDropdownMenu(frame) end)
            end
            footerButton:ClearAllPoints()
            footerButton:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, 4)
            footerButton:Show()
        elseif footerButton then
            footerButton:Hide()
        end
    end

    function frame:SetText(text)
        label:SetText(text and text ~= "" and text or frame._defaultText)
    end

    function frame:GetText()
        return label:GetText()
    end

    function frame:SetMenuBuilder(builder)
        frame._builder = builder
    end

    function frame:RefreshMenu()
        if menu:IsShown() then RebuildMenu() end
    end

    function frame:IsOpen()
        return menu:IsShown()
    end

    function frame:OpenMenu()
        CloseOtherDropdownMenus(frame)
        RebuildMenu()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
        menu:Show()
        T.SetInputState(container, "focus")
    end

    function frame:CloseMenu()
        CloseDropdownMenu(frame)
    end

    button:SetScript("OnClick", function()
        if menu:IsShown() then frame:CloseMenu() else frame:OpenMenu() end
    end)
    button:SetScript("OnEnter", function()
        if not menu:IsShown() then container:SetBackdropBorderColor(unpack(T.BORDER)) end
    end)
    button:SetScript("OnLeave", function()
        if not menu:IsShown() and container._uiState ~= "focus" then container:SetBackdropBorderColor(unpack(T.BORDER_DIM)) end
    end)
    T.BindHoverReset(button, function()
        if not menu:IsShown() and container._uiState ~= "focus" then
            container:SetBackdropBorderColor(unpack(T.BORDER_DIM))
        end
    end)

    frame:HookScript("OnHide", function() frame:CloseMenu() end)
    menu:SetScript("OnHide", function()
        if container._uiState ~= "error" then T.SetInputState(container, "normal") end
    end)

    dropdownMenus[frame] = true
    return frame
end

function T.SkinSlider(slider, accentColor)
    if not slider or slider._ebonSkinned then return slider end
    slider._ebonSkinned = true
    local r, g, b = unpack(accentColor or T.ACCENT_GOLD)

    local railBg = slider:CreateTexture(nil, "BACKGROUND")
    railBg:SetTexture(FLAT)
    railBg:SetVertexColor(0.14, 0.14, 0.18, 1)
    railBg:SetPoint("LEFT", slider, "LEFT", 0, 0)
    railBg:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    railBg:SetHeight(6)
    slider._railBg = railBg

    local fill = slider:CreateTexture(nil, "BORDER")
    fill:SetTexture(FLAT)
    fill:SetVertexColor(r, g, b, 0.88)
    fill:SetPoint("LEFT", railBg, "LEFT", 0, 0)
    fill:SetHeight(6)
    slider._fill = fill

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(FLAT)
    thumb:SetVertexColor(0.98, 0.92, 0.70, 1)
    thumb:SetSize(10, 16)
    slider:SetThumbTexture(thumb)
    slider._thumb = thumb

    local function SyncSliderVisual()
        local minValue, maxValue = slider:GetMinMaxValues()
        local value = slider:GetValue() or 0
        local width = slider:GetWidth() or 0
        local ratio = 0
        if maxValue and minValue and maxValue > minValue then
            ratio = (value - minValue) / (maxValue - minValue)
        end
        if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
        local fillWidth = math.floor(width * ratio + 0.5)
        if fillWidth < 0 then fillWidth = 0 end
        fill:SetWidth(fillWidth)
    end

    slider:HookScript("OnValueChanged", SyncSliderVisual)
    slider:HookScript("OnShow", SyncSliderVisual)
    slider:HookScript("OnSizeChanged", SyncSliderVisual)
    slider:HookScript("OnEnable", function(self)
        railBg:SetAlpha(1)
        fill:SetAlpha(0.88)
        if self._thumb then self._thumb:SetAlpha(1) end
    end)
    slider:HookScript("OnDisable", function(self)
        railBg:SetAlpha(0.55)
        fill:SetAlpha(0.40)
        if self._thumb then self._thumb:SetAlpha(0.55) end
    end)
    SyncSliderVisual()
    return slider
end

------------------------------------------------------------------------
-- Themed vertical scrollbar
------------------------------------------------------------------------

function T.CreateScrollBar(parent, width)
    local bar = CreateFrame("Slider", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(bar, "Theme.ScrollBar")
    end
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(width or 12)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)

    local rail = bar:CreateTexture(nil, "BACKGROUND")
    rail:SetTexture(FLAT)
    rail:SetVertexColor(0.10, 0.10, 0.13, 0.96)
    rail:SetPoint("TOP", bar, "TOP", 0, -1)
    rail:SetPoint("BOTTOM", bar, "BOTTOM", 0, 1)
    rail:SetWidth(5)
    bar._rail = rail

    local railEdge = bar:CreateTexture(nil, "BORDER")
    railEdge:SetTexture(FLAT)
    railEdge:SetVertexColor(0.24, 0.24, 0.29, 0.75)
    railEdge:SetPoint("TOP", bar, "TOP", 0, -1)
    railEdge:SetPoint("BOTTOM", bar, "BOTTOM", 0, 1)
    railEdge:SetWidth(1)
    bar._railEdge = railEdge

    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(FLAT)
    thumb:SetVertexColor(0.90, 0.72, 0.12, 1)
    thumb:SetSize((width or 12) - 2, 30)
    bar:SetThumbTexture(thumb)
    bar._thumb = thumb

    local glow = bar:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(FLAT)
    glow:SetVertexColor(1.0, 0.84, 0.20, 0.18)
    glow:SetAllPoints(thumb)
    glow:Hide()
    bar._thumbGlow = glow

    local nativeSetMinMaxValues = bar.SetMinMaxValues
    function bar:SetMinMaxValues(minValue, maxValue)
        nativeSetMinMaxValues(self, minValue, maxValue)
        local scrollable = (maxValue or 0) > (minValue or 0)
        if scrollable then
            thumb:Show()
            rail:SetAlpha(1)
            railEdge:SetAlpha(1)
            self:Enable()
        else
            thumb:Hide()
            rail:SetAlpha(0.45)
            railEdge:SetAlpha(0.45)
            self:Disable()
        end
    end

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if self._thumb then self._thumb:SetVertexColor(1.0, 0.82, 0.16, 1) end
        if self._thumbGlow then self._thumbGlow:Show() end
    end)
    bar:SetScript("OnLeave", function(self)
        if self._thumb then self._thumb:SetVertexColor(0.90, 0.72, 0.12, 1) end
        if self._thumbGlow then self._thumbGlow:Hide() end
    end)
    T.BindHoverReset(bar, function(self)
        if self._thumb then self._thumb:SetVertexColor(0.90, 0.72, 0.12, 1) end
        if self._thumbGlow then self._thumbGlow:Hide() end
    end)
    bar:HookScript("OnDisable", function(self)
        if self._thumb then self._thumb:SetAlpha(0.30) end
        if self._rail then self._rail:SetAlpha(0.45) end
    end)
    bar:HookScript("OnEnable", function(self)
        if self._thumb then self._thumb:SetAlpha(1) end
        if self._rail then self._rail:SetAlpha(1) end
    end)
    bar:SetMinMaxValues(0, 0)
    return bar
end


function T.CreateHorizontalScrollBar(parent, height)
    local bar = CreateFrame("Slider", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(bar, "Theme.HorizontalScrollBar")
    end
    bar:SetOrientation("HORIZONTAL")
    bar:SetHeight(height or 12)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)

    local rail = bar:CreateTexture(nil, "BACKGROUND")
    rail:SetTexture(FLAT)
    rail:SetVertexColor(0.10, 0.10, 0.13, 0.96)
    rail:SetPoint("LEFT", bar, "LEFT", 1, 0)
    rail:SetPoint("RIGHT", bar, "RIGHT", -1, 0)
    rail:SetHeight(5)
    bar._rail = rail

    local railEdge = bar:CreateTexture(nil, "BORDER")
    railEdge:SetTexture(FLAT)
    railEdge:SetVertexColor(0.24, 0.24, 0.29, 0.75)
    railEdge:SetPoint("LEFT", bar, "LEFT", 1, 0)
    railEdge:SetPoint("RIGHT", bar, "RIGHT", -1, 0)
    railEdge:SetHeight(1)
    bar._railEdge = railEdge

    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(FLAT)
    thumb:SetVertexColor(0.90, 0.72, 0.12, 1)
    thumb:SetSize(44, (height or 12) - 2)
    bar:SetThumbTexture(thumb)
    bar._thumb = thumb

    local glow = bar:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(FLAT)
    glow:SetVertexColor(1.0, 0.84, 0.20, 0.18)
    glow:SetAllPoints(thumb)
    glow:Hide()
    bar._thumbGlow = glow

    local nativeSetMinMaxValues = bar.SetMinMaxValues
    function bar:SetMinMaxValues(minValue, maxValue)
        nativeSetMinMaxValues(self, minValue, maxValue)
        local scrollable = (maxValue or 0) > (minValue or 0)
        if scrollable then
            thumb:Show()
            rail:SetAlpha(1)
            railEdge:SetAlpha(1)
            self:Enable()
        else
            thumb:Hide()
            rail:SetAlpha(0.45)
            railEdge:SetAlpha(0.45)
            self:Disable()
        end
    end

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if self._thumb then self._thumb:SetVertexColor(1.0, 0.82, 0.16, 1) end
        if self._thumbGlow then self._thumbGlow:Show() end
    end)
    bar:SetScript("OnLeave", function(self)
        if self._thumb then self._thumb:SetVertexColor(0.90, 0.72, 0.12, 1) end
        if self._thumbGlow then self._thumbGlow:Hide() end
    end)
    T.BindHoverReset(bar, function(self)
        if self._thumb then self._thumb:SetVertexColor(0.90, 0.72, 0.12, 1) end
        if self._thumbGlow then self._thumbGlow:Hide() end
    end)
    bar:HookScript("OnDisable", function(self)
        if self._thumb then self._thumb:SetAlpha(0.30) end
        if self._rail then self._rail:SetAlpha(0.45) end
    end)
    bar:HookScript("OnEnable", function(self)
        if self._thumb then self._thumb:SetAlpha(1) end
        if self._rail then self._rail:SetAlpha(1) end
    end)
    bar:SetMinMaxValues(0, 0)
    return bar
end

------------------------------------------------------------------------
-- Reliable mouse-wheel scrolling
------------------------------------------------------------------------

-- WoW 3.3.5a may deliver the wheel event to the deepest mouse-enabled child
-- under the cursor instead of the owning ScrollFrame. In addition, a Slider
-- parked at its maximum can occasionally fail to repaint the ScrollFrame when
-- only SetValue is used. Keep one shared path that routes wheel input through
-- the complete content tree and updates both controls explicitly.
local function NextWheelScrollValue(currentValue, delta, minimum, maximum, step)
    currentValue = tonumber(currentValue) or 0
    delta = tonumber(delta) or 0
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or minimum
    step = math.max(1, tonumber(step) or 30)

    if maximum < minimum then maximum = minimum end
    currentValue = math.max(minimum, math.min(maximum, currentValue))
    return math.max(minimum, math.min(maximum, currentValue - delta * step))
end

function T.ScrollByMouseWheel(scrollFrame, scrollBar, delta, step)
    if not scrollFrame or not scrollBar then return nil end
    local minimum, maximum = scrollBar:GetMinMaxValues()
    local currentValue
    if scrollFrame.GetVerticalScroll then
        currentValue = tonumber(scrollFrame:GetVerticalScroll())
    end
    if currentValue == nil then currentValue = tonumber(scrollBar:GetValue()) or minimum or 0 end

    local nextValue = NextWheelScrollValue(currentValue, delta, minimum, maximum, step)
    -- Set both values deliberately. On the 3.3.5a client the Slider's
    -- OnValueChanged callback is not a sufficiently reliable repaint path at
    -- the exact bottom boundary.
    scrollBar:SetValue(nextValue)
    scrollFrame:SetVerticalScroll(nextValue)
    return nextValue
end

local function AttachWheelTarget(target, owner, handler)
    if not target then return end
    -- A nested ScrollFrame owns its own wheel context. Do not make an outer
    -- page scroller consume the inner list's input or run both handlers.
    if target ~= owner and target._ebonWheelContext and target._ebonWheelContext.handler then return end
    if target._ebonWheelOwner ~= owner then
        target:EnableMouseWheel(true)
        if target.HookScript then
            target:HookScript("OnMouseWheel", handler)
        else
            target:SetScript("OnMouseWheel", handler)
        end
        target._ebonWheelOwner = owner
    end

    if target.GetChildren then
        local children = { target:GetChildren() }
        for _, child in ipairs(children) do
            AttachWheelTarget(child, owner, handler)
        end
    end
end

function T.BindScrollWheel(scrollFrame, scrollBar, step, ...)
    if not scrollFrame or not scrollBar then return nil end
    scrollFrame._ebonWheelContext = scrollFrame._ebonWheelContext or {}
    local context = scrollFrame._ebonWheelContext
    context.bar = scrollBar
    context.step = math.max(1, tonumber(step) or 30)

    if not context.handler then
        context.handler = function(_, delta)
            local active = scrollFrame._ebonWheelContext
            if active then T.ScrollByMouseWheel(scrollFrame, active.bar, delta, active.step) end
        end
    end

    AttachWheelTarget(scrollFrame, scrollFrame, context.handler)
    AttachWheelTarget(scrollBar, scrollFrame, context.handler)
    for index = 1, select("#", ...) do
        AttachWheelTarget(select(index, ...), scrollFrame, context.handler)
    end
    return context.handler
end

-- Virtualized lists use their Slider value as a row offset instead of a native
-- ScrollFrame pixel offset. They still need the same child-tree wheel routing
-- and boundary behavior, but must not call SetVerticalScroll.
function T.BindSliderWheel(ownerFrame, scrollBar, step, ...)
    if not ownerFrame or not scrollBar then return nil end
    ownerFrame._ebonSliderWheelContext = ownerFrame._ebonSliderWheelContext or {}
    local context = ownerFrame._ebonSliderWheelContext
    context.bar = scrollBar
    context.step = math.max(1, tonumber(step) or 1)

    if not context.handler then
        context.handler = function(_, delta)
            local active = ownerFrame._ebonSliderWheelContext
            if not active or not active.bar then return end
            local minimum, maximum = active.bar:GetMinMaxValues()
            local nextValue = NextWheelScrollValue(active.bar:GetValue(), delta, minimum, maximum, active.step)
            active.bar:SetValue(nextValue)
        end
    end

    AttachWheelTarget(ownerFrame, ownerFrame, context.handler)
    AttachWheelTarget(scrollBar, ownerFrame, context.handler)
    for index = 1, select("#", ...) do
        AttachWheelTarget(select(index, ...), ownerFrame, context.handler)
    end
    return context.handler
end

T._NextWheelScrollValue = NextWheelScrollValue

------------------------------------------------------------------------
-- Workspace primitives (2.89 shell redesign)
------------------------------------------------------------------------

T.PAGE_HEADER_HEIGHT = 48

-- Consistent page title block. Callers may anchor contextual actions to the
-- returned frame's right edge without reimplementing title/subtitle geometry.
function T.CreatePageHeader(parent, titleText, subtitleText)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    header:SetHeight(T.PAGE_HEADER_HEIGHT)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 2, -3)
    title:SetPoint("RIGHT", header, "RIGHT", -170, 0)
    title:SetJustifyH("LEFT")
    title:SetText(titleText or "")
    title:SetTextColor(unpack(T.TEXT_PRIMARY))

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(subtitleText or "")
    subtitle:SetTextColor(unpack(T.TEXT_MUTED))

    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(T.ACCENT_GOLD[1], T.ACCENT_GOLD[2], T.ACCENT_GOLD[3], 0.34)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    header._title = title
    header._subtitle = subtitle
    header._rule = rule
    return header
end

function T.UpdatePageHeader(header, titleText, subtitleText)
    if not header then return end
    if header._title and titleText ~= nil then header._title:SetText(titleText) end
    if header._subtitle and subtitleText ~= nil then header._subtitle:SetText(subtitleText) end
end

function T.CreateSectionLabel(parent, text, anchor, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if anchor then
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, yOffset or -10)
    else
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, yOffset or -4)
    end
    label:SetText(string.upper(text or ""))
    label:SetTextColor(0.58, 0.60, 0.66, 1)
    return label
end

-- Small removable chip used for active filters and contextual state.
function T.CreateFilterChip(parent, text)
    local btn = T.CreateButton(parent)
    btn:SetHeight(20)
    btn:SetText((text or "") .. "  x")
    btn._chipLabel = text or ""
    local width = 28 + math.min(170, #(text or "") * 6)
    btn:SetWidth(math.max(54, width))
    return btn
end

function T.CreateEmptyState(parent, titleText, bodyText)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 10)
    frame:SetSize(420, 90)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOP", frame, "TOP", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetAlpha(0.45)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -7)
    title:SetText(titleText or "Nothing to show")
    title:SetTextColor(unpack(T.TEXT_PRIMARY))

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    body:SetPoint("TOP", title, "BOTTOM", 0, -4)
    body:SetWidth(390)
    body:SetJustifyH("CENTER")
    body:SetText(bodyText or "")
    body:SetTextColor(unpack(T.TEXT_MUTED))

    frame._icon = icon
    frame._title = title
    frame._body = body
    return frame
end

function T.CreateMetricCard(parent, labelText)
    local card = CreateFrame("Frame", nil, parent)
    T.ApplyCard(card)

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    value:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    value:SetJustifyH("LEFT")
    value:SetText("0")
    value:SetTextColor(unpack(T.TEXT_PRIMARY))

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -3)
    label:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or "")
    label:SetTextColor(unpack(T.TEXT_MUTED))

    card.value = value
    card.label = label
    return card
end

function T.ApplySidebar(frame)
    ApplySurface(frame, { 0.045, 0.045, 0.062, 0.995 }, T.BORDER_DIM)
end

-- Themed close button: an "X" in the window's own visual language instead
-- of the round WotLK UIPanelCloseButton, which reads as a foreign element
-- on the flat dark surfaces every window now uses. Same size and corner
-- position conventions as the native one so muscle memory keeps working.
function T.CreateCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    InstallBackdrop(btn)
    ApplyButtonVisual(btn, BTN_BG, T.BORDER_DIM)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText("x")
    label:SetTextColor(0.85, 0.85, 0.88)
    btn._label = label
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "Theme.CloseButton")
    end
    btn:SetScript("OnEnter", function(self)
        ApplyButtonVisual(self, BTN_BG_HOVER, T.DANGER)
        self._label:SetTextColor(1.00, 0.35, 0.35)
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyButtonVisual(self, BTN_BG, T.BORDER_DIM)
        self._label:SetTextColor(0.85, 0.85, 0.88)
    end)
    T.BindHoverReset(btn, function(self)
        ApplyButtonVisual(self, BTN_BG, T.BORDER_DIM)
        self._label:SetTextColor(0.85, 0.85, 0.88)
    end)
    btn:SetScript("OnClick", function(self)
        if EbonBuilds.ClickTrace then EbonBuilds.ClickTrace.Log("click", "close") end
        parent:Hide()
    end)
    return btn
end

-- Themed checkbox: a flat square that fills with the gold accent when
-- checked, replacing UICheckButtonTemplate's parchment check. Exposes the
-- same GetChecked/SetChecked contract call sites already rely on, so a
-- swap-in requires no logic changes. The label is part of the control and
-- extends the click target, matching how the redesign's filter chips treat
-- their text.
function T.CreateCheckbox(parent, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    InstallBackdrop(btn)
    ApplyButtonVisual(btn, T.INPUT_BG, T.BORDER_DIM)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(FLAT)
    fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    fill:SetVertexColor(unpack(T.ACCENT_GOLD))
    fill:Hide()
    btn._fill = fill
    btn._checked = false

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    label:SetText(labelText or "")
    btn._labelFS = label

    function btn:GetChecked()
        return self._checked and 1 or nil
    end
    function btn:SetChecked(state)
        self._checked = state and true or false
        if self._checked then self._fill:Show() else self._fill:Hide() end
    end

    -- Extend the click target over the label, like a real form control.
    btn:SetHitRectInsets(0, -(label:GetStringWidth() + 10), 0, 0)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(T.BORDER))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(T.BORDER_DIM))
    end)
    T.BindHoverReset(btn, function(self)
        self:SetBackdropBorderColor(unpack(T.BORDER_DIM))
    end)
    -- Contract: a call site's OnClick handler must read the NEW state,
    -- exactly like UICheckButtonTemplate. Implemented by overriding
    -- SetScript for "OnClick" so external handlers get chained AFTER the
    -- internal toggle -- deliberately NOT via a "PreClick" script, whose
    -- validity on plain (non-secure) Buttons under 3.3.5 is exactly the
    -- kind of API detail a wrong guess about would abort window
    -- construction midway and silently leave half a window unbuilt.
    local function InternalToggle(self)
        self:SetChecked(not self._checked)
        if EbonBuilds.ClickTrace then
            EbonBuilds.ClickTrace.Log("click", (labelText or "checkbox") .. (self._checked and " [on]" or " [off]"))
        end
    end
    btn:SetScript("OnClick", InternalToggle)
    local rawSetScript = btn.SetScript
    btn.SetScript = function(self, scriptType, handler)
        if scriptType == "OnClick" then
            if handler then
                rawSetScript(self, "OnClick", function(...)
                    InternalToggle(...)
                    handler(...)
                end)
            else
                rawSetScript(self, "OnClick", InternalToggle)
            end
        else
            rawSetScript(self, scriptType, handler)
        end
    end
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "Theme.Checkbox")
    end
    return btn
end
