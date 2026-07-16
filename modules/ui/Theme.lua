-- EbonBuilds: modules/ui/Theme.lua
-- Retail-inspired dark theme, built entirely from 3.3.5a-safe textures.
-- Instead of the WotLK parchment dialog look, panels get flat, dark,
-- slightly translucent backgrounds with thin neutral borders and gold
-- accents -- the visual language of the modern client.

EbonBuilds.Theme = {}

local T = EbonBuilds.Theme

-- Palette ---------------------------------------------------------------
T.WINDOW_BG   = { 0.07, 0.07, 0.09, 0.95 }  -- main window body
T.PANEL_BG    = { 0.10, 0.10, 0.13, 0.95 }  -- inner panels / cards
T.CARD_BG     = { 0.13, 0.13, 0.16, 0.95 }  -- list cards
T.CARD_HOVER  = { 0.18, 0.18, 0.22, 0.95 }
T.BORDER      = { 0.35, 0.35, 0.40, 1.00 }  -- thin neutral border
T.BORDER_DIM  = { 0.22, 0.22, 0.26, 1.00 }
T.ACCENT_GOLD = { 1.00, 0.82, 0.00, 1.00 }  -- retail gold
T.ACCENT_HEX  = "ffd100"

local FLAT = "Interface\\Buttons\\WHITE8X8"

local WINDOW_BACKDROP = {
    bgFile   = FLAT,
    edgeFile = FLAT,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- A window-level frame: dark body, 1px border.
function T.ApplyWindow(frame)
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(unpack(T.WINDOW_BG))
    frame:SetBackdropBorderColor(unpack(T.BORDER))
end

-- An inner panel / inset area.
function T.ApplyPanel(frame)
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(unpack(T.PANEL_BG))
    frame:SetBackdropBorderColor(unpack(T.BORDER_DIM))
end

-- A list card (build list, public builds, sessions).
function T.ApplyCard(frame)
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(unpack(T.CARD_BG))
    frame:SetBackdropBorderColor(unpack(T.BORDER_DIM))
end

function T.SetCardHovered(frame, hovered)
    if hovered then
        frame:SetBackdropColor(unpack(T.CARD_HOVER))
    else
        frame:SetBackdropColor(unpack(T.CARD_BG))
    end
end

-- Thin gold divider line under headers, retail-style.
function T.AddHeaderRule(parent, anchorFontString, width)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(T.ACCENT_GOLD[1], T.ACCENT_GOLD[2], T.ACCENT_GOLD[3], 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", anchorFontString, "BOTTOMLEFT", 0, -4)
    rule:SetWidth(width or 200)
    return rule
end

-- Canonical class colors (WotLK RAID_CLASS_COLORS values), shared so list
-- views never drift apart.
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
-- Retail-style buttons
------------------------------------------------------------------------

local BTN_BG       = { 0.16, 0.16, 0.20, 1.0 }
local BTN_BG_HOVER = { 0.24, 0.24, 0.30, 1.0 }
local BTN_BG_DOWN  = { 0.10, 0.10, 0.13, 1.0 }

-- Reskins a UIPanelButtonTemplate button into the flat retail look.
-- Keeps the full Button API (SetText, Enable/Disable, scripts).
function T.SkinButton(btn)
    btn:SetNormalTexture("")
    btn:SetPushedTexture("")
    btn:SetHighlightTexture("")
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(unpack(BTN_BG))
    btn:SetBackdropBorderColor(unpack(T.BORDER_DIM))

    btn:HookScript("OnEnter", function(self)
        if self:IsEnabled() == 1 then
            self:SetBackdropColor(unpack(BTN_BG_HOVER))
            self:SetBackdropBorderColor(unpack(self._accentBorder or T.BORDER))
        end
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(BTN_BG))
        self:SetBackdropBorderColor(unpack(self._accentBorder or T.BORDER_DIM))
    end)
    btn:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() == 1 then
            self:SetBackdropColor(unpack(BTN_BG_DOWN))
        end
    end)
    btn:HookScript("OnMouseUp", function(self)
        if self:GetScript("OnEnter") and self:IsMouseOver() then
            self:SetBackdropColor(unpack(BTN_BG_HOVER))
        else
            self:SetBackdropColor(unpack(BTN_BG))
        end
    end)
    return btn
end

-- Drop-in replacement for CreateFrame("Button", ..., "UIPanelButtonTemplate").
-- accent = "gold" for the one primary call-to-action in a group (e.g. "+ New
-- Build"), "danger" for destructive actions (e.g. Delete). Plain by default.
function T.CreateButton(parent, accent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    T.SkinButton(btn)
    if accent then T.SetButtonAccent(btn, accent) end
    -- Single choke point for every themed button in the addon, so
    -- ClickTrace (core/ClickTrace.lua) can log "click IS arriving here"
    -- without every module needing its own hook.
    btn:HookScript("OnClick", function(self)
        if EbonBuilds.ClickTrace then
            EbonBuilds.ClickTrace.Log("click", self:GetText() or self:GetName() or "?")
        end
    end)
    return btn
end

local ACCENT_BORDERS = {
    gold   = { 0.85, 0.65, 0.05, 1.0 },
    danger = { 0.55, 0.18, 0.18, 1.0 },
    good   = { 0.15, 0.55, 0.20, 1.0 },
}

-- Recolors a themed button's border (and restores it on mouse-leave), so a
-- button can signal its role (primary action, destructive, active-state)
-- without abandoning the shared flat skin.
function T.SetButtonAccent(btn, accent)
    local c = ACCENT_BORDERS[accent]
    if not c then return end
    btn._accentBorder = c
    btn:SetBackdropBorderColor(unpack(c))
end

function T.ClearButtonAccent(btn)
    btn._accentBorder = nil
    btn:SetBackdropBorderColor(unpack(T.BORDER_DIM))
end
