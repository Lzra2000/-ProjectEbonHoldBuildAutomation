-- EbonBuilds: modules/ui/BuildForm.lua
-- Responsibility: create/edit build form with class, spec, title, comments,
-- and configurable locked-Echo slots. Declarative/widget-layout heavy:
-- template-file exception applies, so the 200-line hard limit is waived here.

EbonBuilds.BuildForm = {}

local classChangeCallbacks = {}

local function NotifyClassChange()
    for i = 1, #classChangeCallbacks do classChangeCallbacks[i]() end
end

function EbonBuilds.BuildForm.OnClassChanged(fn)
    classChangeCallbacks[#classChangeCallbacks + 1] = fn
end

local CLASS_ORDER = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST",
    "DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUALITY_COLOR = EbonBuilds.Quality.HEX
local QUALITY_BORDER_COLORS = EbonBuilds.Quality.RGB

local viewFrame
local state = {
    mode     = "create",
    id       = nil,
    title    = "",
    class    = nil,
    spec     = 1,
    comments = "",
    locked = { nil, nil, nil, nil, nil, nil },
    settings  = nil,
    isPublic  = false,
}
local function MarkDirty()
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.MarkDirty then
        EbonBuilds.BuildTabs.MarkDirty()
    end
end

function EbonBuilds.BuildForm.GetEditingClass()
    return state.class
end
function EbonBuilds.BuildForm.GetEditingSettings()
    if not state.settings then
        state.settings = (EbonBuilds.Build.NewBuildSettings and EbonBuilds.Build.NewBuildSettings()) or EbonBuilds.Build.DefaultSettings()
    end
    return state.settings
end

-- Returns the id of the build currently being edited, or nil in create mode
-- (or when no form is active). Lets the Settings tab persist changes live.
-- Called when a save re-keyed the build (imported-build fork): the editor
-- must adopt the new id or subsequent saves hit the deleted old id.
function EbonBuilds.BuildForm.NoteRekey(newId)
    if state.mode == "edit" then state.id = newId end
end

function EbonBuilds.BuildForm.GetEditingBuildId()
    if state.mode == "edit" then return state.id end
    return nil
end

-- Marks the editor settings as staged. Build configuration is committed only
-- by the shared Save action; operational controls such as Autopilot enablement
-- continue to use their own immediate persistence path.
function EbonBuilds.BuildForm.PersistEditingSettings()
    -- Build configuration is staged in the editor and committed by Save.
    -- Operational state such as automationEnabled is still persisted by its
    -- own control, but thresholds/protection/modifiers never leak from a
    -- half-edited build into the live run.
    MarkDirty()
    local id = EbonBuilds.BuildForm.GetEditingBuildId()
    return id and EbonBuilds.Build.Get(id) or nil
end

function EbonBuilds.BuildForm.GetEditingLockedEchoes()
    if not state.mode then return nil end
    return state.locked
end

local classButtons = {}
local specButtons  = {}
local slotButtons  = {}
local titleBox, titleContainer, titleErrorLabel, commentsBox, publicToggle

-- Global single-install hook: shift-click links go into the comments editbox
-- when it is focused. Guarded so we never install twice.
local _linkHookInstalled = false

local function InstallLinkHook()
    if _linkHookInstalled then return end
    _linkHookInstalled = true
    if not ChatEdit_InsertLink then return end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if not link then return end
        local focus = GetCurrentKeyBoardFocus()
        if focus and focus == commentsBox then
            commentsBox:Insert(link)
        end
    end)
end

------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    tex:SetTexture(CLASS_TEXTURE)
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

local function HighlightBorder(btn, on)
    if not btn._border then
        local b = btn:CreateTexture(nil, "OVERLAY")
        b:SetAllPoints(btn)
        b:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b:SetBlendMode("ADD")
        b:Hide()
        btn._border = b
    end
    if on then btn._border:Show() else btn._border:Hide() end
end

local function RefreshClassSelection()
    for token, btn in pairs(classButtons) do
        HighlightBorder(btn, token == state.class)
    end
end

local function RefreshSpecButtons()
    local specs = state.class and EbonBuilds.SpecData and EbonBuilds.SpecData[state.class]
    for i = 1, 3 do
        local btn = specButtons[i]
        local entry = specs and specs[i]
        local icon  = entry and entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local name  = entry and entry.name or ("Spec " .. i)
        if btn._icon then btn._icon:SetTexture(icon) end
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(name)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        HighlightBorder(btn, i == state.spec)
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

------------------------------------------------------------------------
-- Class grid
------------------------------------------------------------------------

local function BuildClassGrid(parent, xAnchor, yAnchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yAnchor)
    label:SetText("Class:")
    for i, token in ipairs(CLASS_ORDER) do
        local btn = CreateIconButton(parent, 28)
        SetClassIcon(btn._icon, token)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor + 56 + (i - 1) * 30, yAnchor + 6)
        btn:SetScript("OnClick", function()
            if state.class == token then return end
            state.class = token
            MarkDirty()
            if state.spec > 3 then state.spec = 1 end
            RefreshClassSelection()
            RefreshSpecButtons()
            NotifyClassChange()
        end)
        classButtons[token] = btn
    end
end

local function BuildSpecGrid(parent, xAnchor, yAnchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yAnchor)
    label:SetText("Spec:")
    for i = 1, 3 do
        local btn = CreateIconButton(parent, 36)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor + 56 + (i - 1) * 40, yAnchor + 6)
        btn:SetScript("OnClick", function()
            state.spec = i
            MarkDirty()
            RefreshSpecButtons()
        end)
        specButtons[i] = btn
    end
end

------------------------------------------------------------------------
-- Title + Comments + Locked Echoes
------------------------------------------------------------------------

local function CreateBackdropEditBox(parent, width, height, multi)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)
    EbonBuilds.Theme.ApplyInput(c)

    local box = CreateFrame("EditBox", nil, c)
    box:SetPoint("TOPLEFT",     c, "TOPLEFT",     4,  -4)
    box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -4,  4)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetAutoFocus(false)
    if multi then
        box:SetMultiLine(true)
        box:SetMaxLetters(0)
        box:EnableMouse(true)
    else
        box:SetMaxLetters(40)
    end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    EbonBuilds.Theme.WireEditBox(box, c)
    return box, c
end

local function BuildTitleField(parent, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("Build name:")
    local box, container = CreateBackdropEditBox(parent, 360, 24, false)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 88, y + 7)
    titleBox, titleContainer = box, container

    titleErrorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleErrorLabel:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 2, -2)
    titleErrorLabel:SetTextColor(unpack(EbonBuilds.Theme.DANGER))
    titleErrorLabel:SetText("")

    box:SetScript("OnTextChanged", function(self)
        if not state._loading then MarkDirty() end
        if (self:GetText() or ""):match("%S") then
            titleErrorLabel:SetText("")
            self._error = nil
            EbonBuilds.Theme.SetInputState(container, self:HasFocus() and "focus" or "normal")
        end
    end)
end

local function BuildLockedSlots(parent, x, y)
    local slotSize = 38
    local slotGap = 8
    local slotStartX = x + 96

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetText("Locked Echoes:")
    lbl:SetWidth(84)
    lbl:SetJustifyH("RIGHT")

    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(parent, slotSize)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", slotStartX + (i - 1) * (slotSize + slotGap), y + 7)
        btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        btn.spellId = nil
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        EbonBuilds.EchoTableRows.WireIconTooltip(btn)

        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._qualityBorder = border

        btn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                state.locked[i] = nil
                MarkDirty()
                btn.spellId = nil
                btn._quality = nil
                btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                btn._qualityBorder:Hide()
                return
            end
            local settings = EbonBuilds.BuildForm.GetEditingSettings()
            local allList = EbonBuilds.EchoTableRows.BuildAllQualitiesList()
            local filtered = {}
            for _, entry in ipairs(allList) do
                if not EbonBuilds.Scoring.IsBanned(entry.spellId, settings) then
                    filtered[#filtered + 1] = entry
                end
            end
            EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
                state.locked[i] = spellId
                MarkDirty()
                btn.spellId = spellId
                btn._quality = quality
                btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
                local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
                btn._qualityBorder:SetTexture(bc[1], bc[2], bc[3])
                btn._qualityBorder:Show()
            end, filtered)
        end)
        slotButtons[i] = btn
    end

    -- Align the label and helper copy to the icon row instead of squeezing the
    -- instructions between the label and the first slot. This keeps all six
    -- slots evenly spaced and readable at common 3.3.5a UI scales.
    if slotButtons[1] then
        lbl:SetPoint("RIGHT", slotButtons[1], "LEFT", -12, 0)
    else
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetText("Left-click: choose    Right-click: clear")
    hint:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    hint:SetJustifyH("LEFT")
    hint:SetWidth(210)
    if slotButtons[EbonBuilds.Build.LOCKED_SLOTS] then
        hint:SetPoint("LEFT", slotButtons[EbonBuilds.Build.LOCKED_SLOTS], "RIGHT", 16, 0)
    else
        hint:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
    end
end

local descriptionPlaceholder
local descriptionScrollBar

local function RefreshDescriptionPlaceholder()
    if not descriptionPlaceholder or not commentsBox then return end
    if commentsBox:HasFocus() then
        descriptionPlaceholder:Hide()
        return
    end
    if (commentsBox:GetText() or "") == "" then
        descriptionPlaceholder:Show()
    else
        descriptionPlaceholder:Hide()
    end
end

local function BuildDescriptionField(parent, x, y, height)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("Description:")

    local insertBtn = EbonBuilds.Theme.CreateButton(parent)
    insertBtn:SetWidth(110)
    insertBtn:SetHeight(20)
    insertBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 90, y + 2)
    insertBtn:SetText("+ Insert Echo Link")
    insertBtn:SetScript("OnClick", function()
        EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
            local color = QUALITY_COLOR[quality] or "ffffff"
            local link  = "|cff" .. color .. "|Hecho:" .. spellId .. "|h[" .. name .. "]|h|r"
            if commentsBox:HasFocus() then
                commentsBox:Insert(link)
            else
                commentsBox:SetText((commentsBox:GetText() or "") .. link)
            end
        end)
    end)
    insertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Insert Echo Link", 1, 0.82, 0, 1)
        GameTooltip:AddLine("Inserts a clickable echo reference into the description.", 0.8, 0.8, 0.8, 1)
        GameTooltip:AddLine(" ", 1, 1, 1, 1)
        GameTooltip:AddLine("To set Echo priorities and broad modifiers for this build,", 0.6, 0.6, 0.6, 1)
        GameTooltip:AddLine("use the Priorities and Modifiers tabs after saving.", 0.6, 0.6, 0.6, 1)
        GameTooltip:Show()
    end)
    insertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT",     parent, "TOPLEFT",     x,   y - 24)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 50)
    EbonBuilds.Theme.ApplyInput(container)

    local scroll = CreateFrame("ScrollFrame", "EbonBuildsBuildFormDescriptionSF", container)
    scroll:SetPoint("TOPLEFT",     container, "TOPLEFT",      4, -4)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -20,  4)

    descriptionScrollBar = EbonBuilds.Theme.CreateScrollBar(container)
    descriptionScrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -3, -5)
    descriptionScrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -3, 5)
    descriptionScrollBar:SetValueStep(24)
    descriptionScrollBar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -2)
    box:SetWidth(420)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    commentsBox = box
    box:HookScript("OnTextChanged", function() if not state._loading then MarkDirty() end end)

    -- Hidden FontString used to measure wrapped text height for scroll range
    local descMeasure = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descMeasure:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    descMeasure:SetWidth(410)
    descMeasure:Hide()

    local function SyncDescriptionWidth()
        local width = math.max(120, (scroll:GetWidth() or 0) - 4)
        box:SetWidth(width)
        descMeasure:SetWidth(math.max(100, width - 10))
    end
    scroll:SetScript("OnSizeChanged", SyncDescriptionWidth)
    SyncDescriptionWidth()

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOPLEFT",  box, "TOPLEFT",   2, -2)
    hint:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetTextColor(0.5, 0.5, 0.5, 1)
    hint:SetText("Explain the outcome this build is meant to achieve. Use Priorities and Modifiers for scoring details.")
    descriptionPlaceholder = hint

    box:SetScript("OnEditFocusGained", function()
        descriptionPlaceholder:Hide()
        EbonBuilds.Theme.SetInputState(container, "focus")
    end)
    box:SetScript("OnEditFocusLost", function(self)
        EbonBuilds.Theme.SetInputState(container, "normal")
        if (self:GetText() or "") == "" then descriptionPlaceholder:Show() end
    end)
    box:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then
            descriptionPlaceholder:Hide()
        else
            if (self:GetText() or "") == "" then
                descriptionPlaceholder:Show()
            else
                descriptionPlaceholder:Hide()
            end
        end

        -- Auto-resize to fit content and track cursor visibility
        descMeasure:SetText(self:GetText() or "")
        local textHeight = descMeasure:GetStringHeight() or 0
        local contentH = math.max(textHeight + 10, scroll:GetHeight())
        self:SetHeight(contentH)

        local sbar = descriptionScrollBar
        if sbar then
            local maxScroll = math.max(0, contentH - scroll:GetHeight())
            sbar:SetMinMaxValues(0, maxScroll)

            -- Measure cursor Y position within the text
            local cursorByte = self:GetCursorPosition() or 0
            local textBefore = (self:GetText() or ""):sub(1, cursorByte)
            descMeasure:SetText(textBefore)
            local cursorY = descMeasure:GetStringHeight() or 0

            local scrollTop = sbar:GetValue() or 0
            local visibleH = scroll:GetHeight()
            local cursorScreenY = cursorY - scrollTop

            if cursorScreenY > visibleH - 20 then
                sbar:SetValue(math.min(maxScroll, cursorY - visibleH + 20))
            elseif cursorScreenY < 4 then
                sbar:SetValue(math.max(0, cursorY - 20))
            end
        end
    end)

    EbonBuilds.Theme.BindScrollWheel(scroll, descriptionScrollBar, 28, box)
end

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------

local function CollectFromInputs()
    state.title    = titleBox:GetText() or ""
    state.comments = commentsBox:GetText() or ""
end

local function OnSave()
    local echoOK, echoErr = true, nil
    if EbonBuilds.EchoTable and EbonBuilds.EchoTable.ValidateAndCommitAll then
        echoOK, echoErr = EbonBuilds.EchoTable.ValidateAndCommitAll()
    end
    if not echoOK then
        if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ShowTab then EbonBuilds.BuildTabs.ShowTab(2) end
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show(echoErr or "Fix the invalid Echo value before saving")
        end
        return
    end

    if EbonBuilds.BonusView and EbonBuilds.BonusView.ValidateAndCommitAll then
        local bonusOK, bonusErr = EbonBuilds.BonusView.ValidateAndCommitAll()
        if not bonusOK then
            if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ShowTab then EbonBuilds.BuildTabs.ShowTab(3) end
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                EbonBuilds.Toast.Show(bonusErr or "Fix the invalid bonus value before saving")
            end
            return
        end
    end

    if EbonBuilds.SettingsView and EbonBuilds.SettingsView.ValidateAndCommitAll then
        local settingsOK, settingsErr = EbonBuilds.SettingsView.ValidateAndCommitAll()
        if not settingsOK then
            if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ShowTab then EbonBuilds.BuildTabs.ShowTab(4) end
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                EbonBuilds.Toast.Show(settingsErr or "Fix the invalid Autopilot value before saving")
            end
            return
        end
    end

    CollectFromInputs()
    state.title = (state.title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    titleBox:SetText(state.title)
    if state.title == "" then
        if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ShowTab then EbonBuilds.BuildTabs.ShowTab(1) end
        titleBox._error = true
        titleErrorLabel:SetText("A build name is required.")
        EbonBuilds.Theme.SetInputState(titleContainer, "error")
        titleBox:SetFocus()
        return
    end
    local weights = EbonBuildsDB.pendingWeights
    if state.mode == "create" then
        local b = EbonBuilds.Build.Create({
            title = state.title, class = state.class, spec = state.spec,
            comments = state.comments, lockedEchoes = { unpack(state.locked, 1, EbonBuilds.Build.LOCKED_SLOTS) },
            settings = state.settings,
            isPublic = state.isPublic,
            echoWeights = weights,
        })
        state.mode = "edit"
        state.id   = b.id
        EbonBuilds.Build.SetActive(b.id)
    else
        local saved = EbonBuilds.Build.Save(state.id, {
            title = state.title, class = state.class, spec = state.spec,
            comments = state.comments, lockedEchoes = { unpack(state.locked, 1, EbonBuilds.Build.LOCKED_SLOTS) },
            settings = state.settings,
            isPublic = state.isPublic,
            echoWeights = weights,
        })
        -- Saving an imported build forks it under a new id (old id deleted);
        -- adopt it so further saves keep working.
        if saved then state.id = saved.id end
    end
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB._wizardPrefill = nil
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ClearDirty then EbonBuilds.BuildTabs.ClearDirty() end
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.OnBuildSaved then
        EbonBuilds.BuildTabs.OnBuildSaved()
    end
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.EnableEchoesTab then
        EbonBuilds.BuildTabs.EnableEchoesTab()
    end
    local active = EbonBuilds.Build.GetActive()
    if active then
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("Build saved: " .. (active.title or "Untitled")) end
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    end
end

local LoadFromBuild, ApplyStateToInputs

local function OnCancel()
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB._wizardPrefill = nil
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.ClearDirty then EbonBuilds.BuildTabs.ClearDirty() end

    -- Revert state and inputs to original build so dirty edits don't survive Cancel
    if state.mode == "edit" and state.id then
        local build = EbonBuilds.Build.Get(state.id)
        if build then
            LoadFromBuild(build)
            ApplyStateToInputs()
        end
    end

    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
end

local function OnDelete()
    if not state.id then return end
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB._wizardPrefill = nil
    EbonBuilds.Build.Delete(state.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = active })
    else
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create" })
    end
end

EbonBuilds.BuildForm.Save   = OnSave
EbonBuilds.BuildForm.Cancel = OnCancel
EbonBuilds.BuildForm.Delete = OnDelete

------------------------------------------------------------------------
-- Load/Reset state
------------------------------------------------------------------------

ApplyStateToInputs = function()
    state._loading = true
    titleBox:SetText(state.title or "")
    titleBox._error = nil
    if titleErrorLabel then titleErrorLabel:SetText("") end
    if titleContainer then EbonBuilds.Theme.SetInputState(titleContainer, "normal") end
    commentsBox:SetText(state.comments or "")
    RefreshDescriptionPlaceholder()
    RefreshClassSelection()
    RefreshSpecButtons()
    publicToggle:SetText(state.isPublic and "Sharing: On" or "Sharing: Off")
    if state.isPublic then EbonBuilds.Theme.SetButtonAccent(publicToggle, "good") else EbonBuilds.Theme.ClearButtonAccent(publicToggle) end
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local id = state.locked[i]
        local btn = slotButtons[i]
        btn.spellId = id
        if id then
            btn._icon:SetTexture(select(3, GetSpellInfo(id)))
            local data = ProjectEbonhold.PerkDatabase[id]
            local quality = data and data.quality or 0
            btn._quality = quality
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._qualityBorder:SetTexture(bc[1], bc[2], bc[3])
            btn._qualityBorder:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._quality = nil
            btn._qualityBorder:Hide()
        end
    end
    state._loading = nil
end

local function CloneSettings(src)
    local dst = EbonBuilds.Build.DefaultSettings()
    if not src then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            for k2, v2 in pairs(v) do dst[k][k2] = v2 end
        else
            dst[k] = v
        end
    end
    return dst
end

LoadFromBuild = function(build)
    state.mode     = "edit"
    state.id       = build.id
    state.title    = build.title    or ""
    state.class    = build.class
    state.spec     = build.spec     or 1
    state.comments = build.comments or ""
    state.settings = CloneSettings(build.settings)
    state.isPublic = build.isPublic or false
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do state.locked[i] = build.lockedEchoes and build.lockedEchoes[i] or nil end
    EbonBuildsDB._isEditingBuild = true
    EbonBuildsDB.pendingWeights = EbonBuilds.Weights.CloneWeights(build.echoWeights or {})
end

local function LoadDefaults()
    state.mode     = "create"
    state.id       = nil
    state.title    = ""
    state.class    = EbonBuilds.Build.PlayerClassToken()
    state.spec     = EbonBuilds.Build.PlayerTopTalentTab()
    state.comments = ""
    state.settings = (EbonBuilds.Build.NewBuildSettings and EbonBuilds.Build.NewBuildSettings()) or EbonBuilds.Build.DefaultSettings()
    state.isPublic = false
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do state.locked[i] = nil end
    EbonBuildsDB._isEditingBuild = true
    EbonBuildsDB.pendingWeights = {}
    EbonBuildsDB._wizardPrefill = nil
end

local function LoadFromWizardPrefill()
    local pre = EbonBuildsDB._wizardPrefill
    state.mode     = "create"
    state.id       = nil
    state.title    = pre.title or ""
    state.class    = pre.class or EbonBuilds.Build.PlayerClassToken()
    state.spec     = pre.spec or EbonBuilds.Build.PlayerTopTalentTab()
    state.comments = pre.comments or ""
    state.settings = pre.settings or ((EbonBuilds.Build.NewBuildSettings and EbonBuilds.Build.NewBuildSettings()) or EbonBuilds.Build.DefaultSettings())
    state.isPublic = pre.isPublic or false
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do state.locked[i] = (pre.lockedEchoes and pre.lockedEchoes[i]) or nil end
    EbonBuildsDB._isEditingBuild = true
    EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
end

------------------------------------------------------------------------
-- Public Mount/Unmount
------------------------------------------------------------------------

local function TargetMatchesState(context)
    if context.mode == "edit" and context.build then
        return state.mode == "edit" and state.id == context.build.id
    end
    return false
end

function EbonBuilds.BuildForm.Mount(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    local keepState = TargetMatchesState(context)
    if not keepState then
        if context.mode == "create" and context.fromWizard and EbonBuildsDB._wizardPrefill then
            LoadFromWizardPrefill()
        elseif context.mode == "edit" and context.build then
            LoadFromBuild(context.build)
        else
            LoadDefaults()
        end
    end

    ApplyStateToInputs()
    NotifyClassChange()
    viewFrame:Show()
end

function EbonBuilds.BuildForm.Unmount()
    if viewFrame and titleBox and commentsBox then
        state.title    = titleBox:GetText() or state.title
        state.comments = commentsBox:GetText() or state.comments
    end
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Build view frame (deferred until Init so parent is known)
------------------------------------------------------------------------

local function BuildViewFrame()
    local f = CreateFrame("Frame", nil, UIParent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    header:SetText("Build intent")
    header:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    sub:SetText("Define who this build is for and which starting Echoes are non-negotiable.")
    sub:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    publicToggle = EbonBuilds.Theme.CreateButton(f)
    publicToggle:SetSize(118, 24)
    publicToggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
    publicToggle:SetText("Sharing: Off")
    publicToggle:SetScript("OnClick", function(self)
        state.isPublic = not state.isPublic
        MarkDirty()
        self:SetText(state.isPublic and "Sharing: On" or "Sharing: Off")
        if state.isPublic then EbonBuilds.Theme.SetButtonAccent(self, "good") else EbonBuilds.Theme.ClearButtonAccent(self) end
    end)
    EbonBuilds.Theme.AttachTooltip(publicToggle, "Public sharing", "When enabled, this build can be discovered by other EbonBuilds users through Public Builds.")

    BuildClassGrid(f, 10, -50)
    BuildSpecGrid(f, 10, -90)
    BuildTitleField(f, 10, -138)
    BuildLockedSlots(f, 10, -178)
    BuildDescriptionField(f, 10, -228, 180)
    return f
end

function EbonBuilds.BuildForm.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    InstallLinkHook()
end
