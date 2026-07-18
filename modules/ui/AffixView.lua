-- EbonBuilds: modules/ui/AffixView.lua
-- Shows the character's learned-affix status, fed by the server (see
-- core/AffixServer.lua + modules/affix/Affix.lua) rather than guessed from
-- item tooltips.

EbonBuilds.AffixView = {}

local ROW_HEIGHT   = 30
local VISIBLE_ROWS = 12

local viewFrame, scrollFrame, scrollChild, scrollBar
local searchBox, filterBtn, refreshBtn, countLabel, emptyText
local rows = {}
local state = { text = "", missingOnly = false }
local offset = 0
local filtered = {}

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function BuildFilteredList()
    local all = EbonBuilds.Affix.GetLearned()
    local out = {}
    for _, a in ipairs(all) do
        local matchesText = state.text == "" or strlower(a.name or ""):find(state.text, 1, true)
        if matchesText and (not state.missingOnly or not a.learned) then
            out[#out + 1] = a
        end
    end
    table.sort(out, function(x, y)
        if x.learned ~= y.learned then
            return not x.learned  -- missing (not learned) sorts before learned
        end
        return (x.name or "") < (y.name or "")
    end)
    return out
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, 0.03)
    row._stripe = stripe

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local statusDot = row:CreateTexture(nil, "OVERLAY")
    statusDot:SetSize(8, 8)
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusDot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    row._statusDot = statusDot

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 6)
    name:SetJustifyH("LEFT")
    name:SetWidth(260)
    row._name = name

    local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", icon, "RIGHT", 8, -8)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.75, 0.75, 0.75, 1)
    row._sub = sub

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local a = self._affix
        if not a then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = a.id and pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. a.id)
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(a.name or "?", 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(a.learned and "|cff1eff00Learned|r" or "|cffff4444Not learned|r")
        GameTooltip:AddLine(a.weaponOnly and "Weapon-only affix" or "Armor / any slot", 0.7, 0.7, 0.7)
        if a.applyCost and a.applyCost > 0 then
            GameTooltip:AddLine(("Apply cost: %d"):format(a.applyCost), 0.7, 0.7, 0.7)
        end
        if a.appliedCount and a.appliedCount > 0 then
            GameTooltip:AddLine(("Applied %d time(s)"):format(a.appliedCount), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function Render()
    filtered = BuildFilteredList()

    local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    scrollBar:SetMinMaxValues(0, maxOffset)

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local a = filtered[offset + i]
        if a then
            row._affix = a
            row._icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row._name:SetText(a.name or "?")
            if a.learned then
                row._name:SetTextColor(1, 1, 1, 1)
                row._statusDot:SetVertexColor(0.12, 0.85, 0.12, 1)
            else
                row._name:SetTextColor(0.6, 0.6, 0.6, 1)
                row._statusDot:SetVertexColor(0.85, 0.2, 0.2, 1)
            end
            row._sub:SetText(a.weaponOnly and "Weapon-only" or "Armor / any slot")
            row._stripe:SetVertexColor(1, 1, 1, (offset + i) % 2 == 0 and 0.05 or 0.02)
            row:Show()
        else
            row._affix = nil
            row:Hide()
        end
    end

    local all = EbonBuilds.Affix.GetLearned()
    local learnedCount = 0
    for _, a in ipairs(all) do if a.learned then learnedCount = learnedCount + 1 end end
    countLabel:SetText(string.format("%d / %d learned", learnedCount, #all))

    if #filtered == 0 then
        if #all == 0 then
            emptyText:SetText("No affix data yet.\n\nPress Refresh to request your learned affixes from the server.")
        else
            emptyText:SetText("No affix matches your filter.")
        end
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

    EbonBuilds.Theme.CreatePageHeader(
        f,
        "Affixes",
        "Track learned gear affixes, find collection gaps, and request a fresh server snapshot."
    )

    -- Row 1: search box, full width. Fixed offset from f (not chained off
    -- sub's rendered height) -- see the Tome Atlas header for why that
    -- matters once text can wrap.
    searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58)
    searchBox:SetPoint("RIGHT", f, "RIGHT", -38, 0)
    searchBox:SetAutoFocus(false)
    local PLACEHOLDER = "Search affix..."
    local function ShowPlaceholder(self)
        if self:GetText() == "" then
            self:SetTextColor(0.5, 0.5, 0.5, 1)
            self:SetText(PLACEHOLDER)
            self._isPlaceholder = true
        end
    end
    local function HidePlaceholder(self)
        if self._isPlaceholder then
            self:SetText("")
            self:SetTextColor(1, 1, 1, 1)
            self._isPlaceholder = false
        end
    end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        state.text = self._isPlaceholder and "" or strlower(self:GetText() or "")
        offset = 0
        Render()
    end)
    searchBox:SetScript("OnEditFocusGained", HidePlaceholder)
    searchBox:SetScript("OnEditFocusLost", function(self)
        self:SetTextColor(1, 1, 1, 1)
        ShowPlaceholder(self)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ShowPlaceholder(searchBox)

    -- Row 2: count (left), filter + refresh (right). Same single-anchor
    -- pattern as the Tome Atlas -- see its 2.6 fix for why.
    local controlsRow = CreateFrame("Frame", nil, f)
    controlsRow:SetHeight(20)
    controlsRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
    controlsRow:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    refreshBtn = EbonBuilds.Theme.CreateButton(f)
    refreshBtn:SetSize(80, 20)
    refreshBtn:SetPoint("TOPRIGHT", controlsRow, "TOPRIGHT", 0, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        EbonBuilds.Affix.RequestLearned(true)
    end)
    refreshBtn:SetScript("OnUpdate", function(self, dt)
        self._throttle = (self._throttle or 0) + dt
        if self._throttle < 0.25 then return end
        self._throttle = 0
        local remaining = EbonBuilds.Affix.GetCooldownRemaining()
        if remaining ~= self._lastRemaining then
            self._lastRemaining = remaining
            if remaining > 0 then
                self:Disable()
                self:SetText(remaining .. "s")
            else
                self:Enable()
                self:SetText("Refresh")
            end
        end
    end)

    filterBtn = EbonBuilds.Theme.CreateButton(f)
    filterBtn:SetSize(130, 20)
    filterBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -8, 0)
    filterBtn:SetText("Show: All")
    filterBtn:SetScript("OnClick", function(self)
        state.missingOnly = not state.missingOnly
        self:SetText(state.missingOnly and "Show: Missing only" or "Show: All")
        offset = 0
        Render()
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("LEFT", controlsRow, "LEFT", 0, 0)
    countLabel:SetPoint("TOP", controlsRow, "TOP", 0, -3)

    scrollChild = CreateFrame("Frame", nil, f)
    scrollChild:SetPoint("TOPLEFT", controlsRow, "BOTTOMLEFT", 4, -14)
    scrollChild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)

    for i = 1, VISIBLE_ROWS do
        local row = CreateRow(scrollChild)
        row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * ROW_HEIGHT)
        rows[i] = row
    end

    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER", 0, 20)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    scrollBar = EbonBuilds.Theme.CreateScrollBar(f)
    scrollBar:SetPoint("TOPLEFT", scrollChild, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMRIGHT", 6, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        offset = math.floor(value + 0.5)
        Render()
    end)

    EbonBuilds.Theme.BindSliderWheel(f, scrollBar, 1, scrollChild)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

function EbonBuilds.AffixView.Show(parent)
    if not viewFrame then
        viewFrame = BuildViewFrame(parent)
    end
    offset = 0
    Render()
    viewFrame:Show()
    return viewFrame
end

function EbonBuilds.AffixView.Hide()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.AffixView.RefreshIfMounted()
    if viewFrame and viewFrame:IsShown() then
        Render()
    end
end
