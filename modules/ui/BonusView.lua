local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/BonusView.lua
-- Clear, explicit editors for quality, family, and novelty score modifiers.

EbonBuilds.BonusView = {}

local QUALITY_ORDER = EbonBuilds.Quality.ORDER or {}
local FAMILY_ORDER = { "Tank", "Survivability", "Healer", "Caster", "Melee", "Ranged", "No family" }
local FAMILY_ROW1 = { "Tank", "Survivability", "Healer", "Caster" }
local FAMILY_ROW2 = { "Melee", "Ranged", "No family" }
local MIN_VALUE, MAX_VALUE = -9999, 9999

local viewFrame, scrollFrame, scrollChild, scrollBar
local qualityFields, qualityModes = {}, {}
local familyFields, familyModes = {}, {}
local noveltyField, noveltyMode
local allFields = {}
local CONTENT_HEIGHT = 470

local function SetFieldError(box, message)
    box._error = message
    EbonBuilds.Theme.SetInputState(box._container, "error")
    if box._errorLabel then box._errorLabel:SetText(message or "Invalid value") end
end

local function ClearFieldError(box)
    box._error = nil
    if box._errorLabel then box._errorLabel:SetText("") end
    EbonBuilds.Theme.SetInputState(box._container, box:HasFocus() and "focus" or "normal")
end

local function ParseValue(text)
    if text == nil or tostring(text):match("^%s*$") then return nil, "Value required" end
    local value = tonumber(text)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil, "Enter a valid number" end
    if value < MIN_VALUE or value > MAX_VALUE then return nil, "Out of range" end
    return value
end

local function CommitField(box)
    local value, err = ParseValue(box:GetText())
    if value == nil then
        SetFieldError(box, err)
        return false, err
    end
    box._setValue(value)
    box:SetText(tostring(box._getValue() or 0))
    ClearFieldError(box)
    return true
end

local function CreateNumberField(parent, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 58, 24)
    EbonBuilds.Theme.ApplyInput(container)

    local box = CreateFrame("EditBox", nil, container)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(box, "BonusView.EditBox")
    end
    box:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -3)
    box:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 3)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetMaxLetters(8)
    box._container = container

    box:SetScript("OnEnterPressed", function(self)
        if CommitField(self) then self:ClearFocus() end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(self._getValue() or 0))
        ClearFieldError(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        ClearFieldError(self)
        EbonBuilds.Theme.SetInputState(container, "focus")
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self) CommitField(self) end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._fieldTitle or "Bonus value", 1, 0.82, 0)
        if self._error then
            GameTooltip:AddLine(self._error, 1, 0.3, 0.3, true)
        else
            GameTooltip:AddLine("Numbers from -9999 to 9999 are accepted. Decimals are supported.", 0.82, 0.82, 0.86, true)
        end
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    allFields[#allFields + 1] = box
    return box, container
end

local function RefreshModeButton(btn)
    if btn.multiplicative then
        btn:SetText("Multiply")
        EbonBuilds.Theme.SetButtonAccent(btn, "good")
    else
        btn:SetText("Add")
        EbonBuilds.Theme.ClearButtonAccent(btn)
    end
end

local function CreateModeButton(parent)
    local btn = EbonBuilds.Theme.CreateButton(parent)
    btn:SetSize(70, 24)
    btn.multiplicative = false
    btn:SetScript("OnClick", function(self)
        self.multiplicative = not self.multiplicative
        RefreshModeButton(self)
        if self._setMode then self._setMode(self.multiplicative) end
    end)
    EbonBuilds.Theme.AttachTooltip(btn, "Modifier mode",
        "Add applies the value after the base score. Multiply scales the base score; values below 1 reduce it. Negative base values can become more negative when multiplied.")
    RefreshModeButton(btn)
    return btn
end

local function CreateModifierItem(panel, x, y, labelText, labelColor)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    label:SetWidth(122)
    label:SetJustifyH("CENTER")
    label:SetText(labelText)
    if labelColor then label:SetTextColor(labelColor[1], labelColor[2], labelColor[3], 1) end

    local box, container = CreateNumberField(panel, 48)
    container:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 1, y - 20)

    local mode = CreateModeButton(panel)
    mode:SetPoint("LEFT", container, "RIGHT", 4, 0)
    return box, mode
end

local function BuildQualitySection(parent, x, y)
    local panel = EbonBuilds.Theme.CreateSection(parent, "Rank strategy",
        "Shape the value curve from EPIC on the left to COMMON on the right. Add is the clearest default; Multiply is an advanced option.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y)
    panel:SetHeight(126)

    for i, q in ipairs(QUALITY_ORDER) do
        local info = EbonBuilds.Quality
        local rgb = info.RGB[q] or info.RGB[0]
        local box, mode = CreateModifierItem(panel, 10 + (i - 1) * 120, -54, info.LABELS[q] or tostring(q), rgb)
        box._fieldTitle = (info.LABELS[q] or tostring(q)) .. " quality modifier"
        box._getValue = function()
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            return s.qualityBonus[q] or 0
        end
        box._setValue = function(value)
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.qualityBonus[q] = value
        end
        mode._setMode = function(value)
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.qualityBonusMode[q] = value
        end
        qualityFields[q], qualityModes[q] = box, mode
    end
end

local function BuildFamilySection(parent, x, y)
    local panel = EbonBuilds.Theme.CreateSection(parent, "Role emphasis",
        "Raise or lower whole groups when your build clearly favors a role or damage type.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y)
    panel:SetHeight(188)

    local function CreateFamily(fam, col, row)
        local box, mode = CreateModifierItem(panel, 10 + (col - 1) * 148, -54 - (row - 1) * 62, fam)
        box._fieldTitle = fam .. " family modifier"
        box._getValue = function()
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            return s.familyBonus[fam] or 0
        end
        box._setValue = function(value)
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.familyBonus[fam] = value
        end
        mode._setMode = function(value)
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.familyBonusMode[fam] = value
        end
        familyFields[fam], familyModes[fam] = box, mode
    end

    for i, fam in ipairs(FAMILY_ROW1) do CreateFamily(fam, i, 1) end
    for i, fam in ipairs(FAMILY_ROW2) do CreateFamily(fam, i, 2) end
end

local function BuildNoveltySection(parent, x, y)
    local panel = EbonBuilds.Theme.CreateSection(parent, "Unique Echo strategy",
        "Applied only the first time an Echo family appears in the run. This is the main control for encouraging unique picks.")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y)
    panel:SetHeight(104)

    local box, mode = CreateModifierItem(panel, 12, -54, "New unique Echo")
    box._fieldTitle = "Novelty modifier"
    box._getValue = function()
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        return s.noveltyValue or 0
    end
    box._setValue = function(value)
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        s.noveltyValue = value
    end
    mode._setMode = function(value)
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        s.noveltyMode = value
    end
    noveltyField, noveltyMode = box, mode
end

local function RefreshInputs()
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    for _, q in ipairs(QUALITY_ORDER) do
        local box, mode = qualityFields[q], qualityModes[q]
        box:SetText(tostring(settings.qualityBonus[q] or 0))
        ClearFieldError(box)
        mode.multiplicative = settings.qualityBonusMode[q] and true or false
        RefreshModeButton(mode)
    end
    for _, fam in ipairs(FAMILY_ORDER) do
        local box, mode = familyFields[fam], familyModes[fam]
        box:SetText(tostring(settings.familyBonus[fam] or 0))
        ClearFieldError(box)
        mode.multiplicative = settings.familyBonusMode[fam] and true or false
        RefreshModeButton(mode)
    end
    noveltyField:SetText(tostring(settings.noveltyValue or 0))
    ClearFieldError(noveltyField)
    noveltyMode.multiplicative = settings.noveltyMode and true or false
    RefreshModeButton(noveltyMode)
end

function EbonBuilds.BonusView.ValidateAndCommitAll()
    if not viewFrame then return true end
    for _, box in ipairs(allFields) do
        local ok, err = CommitField(box)
        if not ok then
            if box.SetFocus then box:SetFocus() end
            return false, err or "Fix the invalid bonus value before saving"
        end
    end
    return true
end

local function UpdateScrollRange()
    if not scrollFrame or not scrollBar then return end
    local range = math.max(0, CONTENT_HEIGHT - scrollFrame:GetHeight())
    scrollBar:SetMinMaxValues(0, range)
    if scrollBar:GetValue() > range then scrollBar:SetValue(range) end
end

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    header:SetText("Modifiers")
    header:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    sub:SetText("Use broad rules sparingly; individual Echo priorities remain the clearest source of intent.")
    sub:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(scrollFrame, "BonusView.ScrollFrame")
    end
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(625)
    scrollChild:SetHeight(CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = EbonBuilds.Theme.CreateScrollBar(scrollFrame)
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2, 4)
    scrollBar:SetValueStep(24)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    scrollFrame:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(math.max(610, self:GetWidth() or 0))
        UpdateScrollRange()
    end)

    BuildQualitySection(scrollChild, 4, -4)
    BuildFamilySection(scrollChild, 4, -140)
    BuildNoveltySection(scrollChild, 4, -338)
    EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, 24, scrollChild)
    scrollChild:SetWidth(math.max(610, scrollFrame:GetWidth() or 0))
    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.BonusView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshInputs()
    viewFrame:Show()
    UpdateScrollRange()
    scrollBar:SetValue(0)
end

function EbonBuilds.BonusView.Unmount()
    if not viewFrame then return end
    -- Keep invalid values visible while switching tabs; Save performs the full
    -- validation pass and focuses the first invalid field.
    for _, box in ipairs(allFields) do
        if box:HasFocus() then CommitField(box); box:ClearFocus() end
    end
    viewFrame:Hide()
end

function EbonBuilds.BonusView.Init()
end
