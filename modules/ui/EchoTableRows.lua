-- EbonBuilds: modules/ui/EchoTableRows.lua
-- Echo catalog preparation and pooled row rendering for rank-specific values.
-- Rows communicate protection and validation with text as well as color.

EbonBuilds.EchoTableRows = {}

local Rows = EbonBuilds.EchoTableRows
local QUALITY_ORDER = EbonBuilds.Quality.ORDER or {}
local QUALITY_COLORS = EbonBuilds.Quality.HEX
local QUALITY_RGB = EbonBuilds.Quality.RGB
local StripQualitySuffix = EbonBuilds.Weights.StripQualitySuffix
local activeSortKey = "name"
local RIGHT_MARGIN = 4

Rows.COL_ICON       = 40
-- Keep the fixed action/value columns compact so the Echo column has enough
-- room for readable names. Long names wrap to two lines instead of being
-- shortened with an ellipsis.
Rows.COL_QUALITY    = 70
Rows.COL_PROTECT    = 84
Rows.COL_POLICY     = 104
Rows.RANK_COL_WIDTH = 56
Rows.ROW_HEIGHT     = 60
Rows.RANK_TOTAL     = #QUALITY_ORDER * Rows.RANK_COL_WIDTH

function Rows.SetActiveSortKey(key)
    activeSortKey = key or "name"
end

------------------------------------------------------------------------
-- Data preparation
------------------------------------------------------------------------

local function BuildBestByName()
    local best = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local raw = data.comment
        if raw and raw ~= "" then
            local name = StripQualitySuffix(raw)
            local existing = best[name]
            local mask = data.classMask or 0
            if not existing then
                existing = {
                    spellId = spellId,
                    quality = data.quality,
                    qualities = {},
                    families = data.families or {},
                    classMask = mask,
                    spellIds = {},
                    groupIds = {},
                }
                best[name] = existing
            else
                existing.classMask = bit.bor(existing.classMask or 0, mask)
                if data.quality > existing.quality then
                    existing.spellId = spellId
                    existing.quality = data.quality
                    existing.families = data.families or {}
                end
            end
            existing.qualities[data.quality] = true
            existing.spellIds[data.quality] = spellId
            if data.groupId then existing.groupIds[data.groupId] = true end
        end
    end
    return best
end

Rows.BuildBestByName = BuildBestByName

local cachedSortedList, cachedDbCount

local function CountDb()
    local n = 0
    for _ in pairs(ProjectEbonhold.PerkDatabase) do n = n + 1 end
    return n
end

function Rows.BuildSortedList()
    local count = CountDb()
    if cachedSortedList and cachedDbCount == count then return cachedSortedList end

    local list = {}
    for name, entry in pairs(BuildBestByName()) do
        list[#list + 1] = {
            spellId = entry.spellId,
            name = name,
            quality = entry.quality,
            qualities = entry.qualities,
            families = entry.families,
            classMask = entry.classMask or 0,
            spellIds = entry.spellIds,
            groupIds = entry.groupIds,
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    cachedSortedList, cachedDbCount = list, count
    return list
end

function Rows.InvalidateCache()
    cachedSortedList, cachedDbCount = nil, nil
end

function Rows.BuildAllQualitiesList()
    local list = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local raw = data.comment
        if raw and raw ~= "" then
            list[#list + 1] = {
                spellId = spellId,
                name = StripQualitySuffix(raw),
                quality = data.quality,
                classMask = data.classMask or 0,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.quality > b.quality
    end)
    return list
end

------------------------------------------------------------------------
-- Shared row helpers
------------------------------------------------------------------------

local function GetSettings()
    return EbonBuilds.Scoring.GetEffectiveSettings()
end

local function PersistSettings()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.PersistEditingSettings then
        EbonBuilds.BuildForm.PersistEditingSettings()
        return
    end
    local build = EbonBuilds.Build.GetActive()
    if build then EbonBuilds.Build.Save(build.id, { settings = EbonBuilds.Build.CloneSettings(GetSettings()) }) end
end

local function IsWhitelisted(name)
    local settings = GetSettings()
    return settings.echoWhitelist and settings.echoWhitelist[name] and true or false
end

local function RemoveBanConflicts(settings, entry)
    settings.echoBanList = settings.echoBanList or {}
    for spellId in pairs(settings.echoBanList) do
        if EbonBuilds.Weights.CanonicalName(tonumber(spellId) or spellId) == entry.name then
            settings.echoBanList[spellId] = nil
        end
    end
end


local function HighestQuality(entry)
    return entry and entry.quality or 0
end

local function MaxTotalScore(entry)
    local settings = GetSettings()
    local maxScore
    local any = false
    for _, quality in ipairs(QUALITY_ORDER) do
        if entry.qualities and entry.qualities[quality] then
            local weight = EbonBuilds.Weights.Get(entry.name, quality) or 0
            local score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
            if maxScore == nil or score > maxScore then maxScore = score end
            any = true
        end
    end
    if not any then
        local quality = entry.quality or 0
        local weight = EbonBuilds.Weights.Get(entry.name, quality) or 0
        maxScore = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
    end
    return maxScore or 0
end

local function QualityLabel(quality)
    return string.upper(EbonBuilds.Quality.LABELS[quality] or tostring(quality or ""))
end
local function UpdateProtectionVisual(row, entry, protected)
    row.protectToggle:SetChecked(protected)
    local maxScore = MaxTotalScore(entry)
    if protected then
        row.statusLabel:SetText(string.format("Protected · Max %d", maxScore))
        row.statusLabel:SetTextColor(unpack(EbonBuilds.Theme.SUCCESS))
        row.protectAccent:Show()
        row._baseBg:SetVertexColor(0.07, 0.11, 0.08, row._stripeEven and 0.28 or 0.20)
    else
        row.statusLabel:SetText(string.format("Max %d", maxScore))
        row.statusLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
        row.protectAccent:Hide()
        local alpha = row._stripeEven and 0.22 or 0.12
        row._baseBg:SetVertexColor(0.08, 0.08, 0.11, alpha)
    end
end

local function UpdateScores(row, entry)
    local settings = GetSettings()
    for _, quality in ipairs(QUALITY_ORDER) do
        local cell = row.rankCells[quality]
        if cell and entry.qualities[quality] and not cell.editBox._error then
            local spellId = entry.spellIds and entry.spellIds[quality]
            if spellId and EbonBuilds.Scoring.IsLocked(spellId) then
                cell.scoreLabel:SetText("|cff" .. QUALITY_COLORS[quality] .. "Locked|r")
            elseif spellId and EbonBuilds.Scoring.IsBanned(spellId, settings) then
                cell.scoreLabel:SetText("|cff" .. QUALITY_COLORS[quality] .. "Banned|r")
            else
                local weight = EbonBuilds.Weights.Get(entry.name, quality)
                local score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
                cell.scoreLabel:SetText(string.format("|cff%sScore %d|r", QUALITY_COLORS[quality], score))
            end
        end
    end
end

------------------------------------------------------------------------
-- Icon and protection controls
------------------------------------------------------------------------

local function CreateIconFrame(row)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetWidth(Rows.COL_ICON)
    frame:SetHeight(Rows.ROW_HEIGHT)
    frame:SetPoint("LEFT", row, "LEFT", 3, 0)
    frame:EnableMouse(true)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(30, 30)
    tex:SetPoint("CENTER")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex
    return frame
end

local function WireIconTooltip(iconFrame)
    iconFrame:SetScript("OnEnter", function(self)
        if not self.spellId then return end
        local spellName = GetSpellInfo(self.spellId)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if spellName then GameTooltip:AddLine(spellName, 1, 0.82, 0) end
        if utils and utils.GetSpellDescription then
            local description = utils.GetSpellDescription(self.spellId, 500, 1)
            if description and description ~= "" then GameTooltip:AddLine(description, 1, 1, 1, true) end
        end
        if spellName and EbonBuilds.Calibration and EbonBuilds.Calibration.GetAppearanceStats then
            local appearanceName = EbonBuilds.Weights.CanonicalName(self.spellId) or spellName
            local ap = EbonBuilds.Calibration.GetAppearanceStats(appearanceName)
            if ap then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("Appears in ~%.1f%% of offers (%d evaluations)", ap.pct, ap.totalEvals), 0.6, 0.8, 1)
            end
        end
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
Rows.WireIconTooltip = WireIconTooltip

local function CreateQualityBadge(row)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetSize(Rows.COL_QUALITY - 10, 22)
    frame:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_MARGIN + Rows.RANK_TOTAL + Rows.COL_PROTECT + Rows.COL_POLICY + 5), 2)
    EbonBuilds.Theme.ApplyInput(frame)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", frame, "LEFT", 3, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    frame.label = label
    return frame
end

local function PolicyDefinition(policy)
    local api = EbonBuilds.EchoPolicy
    return api and api.Definition(policy) or { label = "Normal", shortLabel = "Normal", color = { 0.82, 0.82, 0.86 }, description = "Standard automation rules." }
end

local function UpdatePolicyVisual(row, entry, selectedNames)
    if not row.policyDropdown or not entry then return end
    local api = EbonBuilds.EchoPolicy
    local settings = GetSettings()
    local policy = api and api.Get(settings, entry.name) or "normal"
    local selected = api and api.IsSelected(entry.name, selectedNames) or false
    local definition = PolicyDefinition(policy)
    row.policyDropdown:SetText(definition.shortLabel or definition.label)
    if row.policyDropdown._label then row.policyDropdown._label:SetTextColor(unpack(definition.color or EbonBuilds.Theme.TEXT_PRIMARY)) end
    if row.policyDropdown._container then
        local c = definition.color or EbonBuilds.Theme.BORDER_DIM
        row.policyDropdown._container:SetBackdropBorderColor(c[1], c[2], c[3], policy == "normal" and 0.45 or 0.90)
    end
    row.policyDropdown._policy = policy
    row.policyDropdown._selectedOnce = selected
end

local function CreatePolicyDropdown(row)
    local dropdown = EbonBuilds.Theme.CreateDropdown(row, Rows.COL_POLICY - 8, "Normal", { menuWidth = 270, rowHeight = 30 })
    dropdown:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_MARGIN + Rows.RANK_TOTAL + Rows.COL_PROTECT + 4), 2)

    dropdown:SetMenuBuilder(function()
        local api = EbonBuilds.EchoPolicy
        local entry = row._entry
        if not api or not entry then return {} end
        local settings = GetSettings()
        local current = api.Get(settings, entry.name)
        local selected = api.IsSelected(entry.name)
        local items = {}
        for _, policy in ipairs(api.ORDER or {}) do
            local policyKey = policy
            local definition = api.Definition(policyKey)
            items[#items + 1] = {
                text = definition.label,
                checked = current == policyKey,
                color = definition.color,
                tooltipTitle = definition.group .. " - " .. definition.label,
                tooltipBody = definition.description .. "\n\nCurrent effect: " .. api.EffectText(policyKey, selected),
                func = function()
                    local liveEntry = row._entry
                    if not liveEntry then return end
                    local liveSettings = GetSettings()
                    api.Set(liveSettings, liveEntry.name, policyKey)
                    if api.IsBanishPolicy(policyKey) then
                        liveSettings.echoWhitelist = liveSettings.echoWhitelist or {}
                        liveSettings.echoWhitelist[liveEntry.name] = nil
                    end
                    PersistSettings()
                    UpdateProtectionVisual(row, liveEntry, IsWhitelisted(liveEntry.name))
                    UpdatePolicyVisual(row, liveEntry)
                    if EbonBuilds.EchoTable and EbonBuilds.EchoTable.NotifyPolicyChanged then
                        EbonBuilds.EchoTable.NotifyPolicyChanged()
                    end
                end,
            }
        end
        return items
    end)

    if dropdown._button and dropdown._button.HookScript then
        dropdown._button:HookScript("OnEnter", function(self)
            local entry = row._entry
            local api = EbonBuilds.EchoPolicy
            if not entry or not api then return end
            local policy = api.Get(GetSettings(), entry.name)
            local selected = api.IsSelected(entry.name)
            local definition = api.Definition(policy)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(definition.label, 1, 0.82, 0)
            GameTooltip:AddLine(definition.description, 0.82, 0.82, 0.86, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(api.EffectText(policy, selected), unpack(definition.color))
            GameTooltip:AddLine("Changes remain staged until Save.", 0.55, 0.58, 0.64, true)
            GameTooltip:Show()
        end)
        dropdown._button:HookScript("OnLeave", function()
            GameTooltip:Hide()
            if row._entry then UpdatePolicyVisual(row, row._entry) end
        end)
    end
    if dropdown._menu and dropdown._menu.HookScript then
        dropdown._menu:HookScript("OnHide", function()
            if row._entry then UpdatePolicyVisual(row, row._entry) end
        end)
    end
    return dropdown
end

local function CreateProtectToggle(row)
    -- A single intent-labelled toggle replaces the old checkbox-like control.
    -- The button says what it does rather than exposing implementation terms.
    local btn = EbonBuilds.Theme.CreateButton(row)
    btn:SetSize(80, 24)
    btn:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_MARGIN + Rows.RANK_TOTAL + (Rows.COL_PROTECT - 80) / 2), 2)

    function btn:SetChecked(checked)
        self._checked = checked and true or false
        if self._checked then
            self:SetText("Protected")
            EbonBuilds.Theme.SetButtonAccent(self, "good")
        else
            self:SetText("Protect")
            EbonBuilds.Theme.ClearButtonAccent(self)
        end
    end

    function btn:GetChecked() return self._checked end

    btn:SetScript("OnClick", function(self)
        local entry = row._entry
        if not entry then return end
        local settings = GetSettings()
        settings.echoWhitelist = settings.echoWhitelist or {}
        local newValue = not self:GetChecked()
        if newValue then
            settings.echoWhitelist[entry.name] = true
            RemoveBanConflicts(settings, entry)
            if EbonBuilds.EchoPolicy then
                local policy = EbonBuilds.EchoPolicy.Get(settings, entry.name)
                if EbonBuilds.EchoPolicy.IsBanishPolicy(policy) then
                    EbonBuilds.EchoPolicy.Set(settings, entry.name, EbonBuilds.EchoPolicy.NORMAL)
                end
            end
        else
            settings.echoWhitelist[entry.name] = nil
        end
        UpdateProtectionVisual(row, entry, newValue)
        UpdatePolicyVisual(row, entry)
        PersistSettings()
        UpdateScores(row, entry)
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show(entry.name .. (newValue and " is protected" or " can be banished again"))
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self:GetChecked() and "Protected Echo" or "Protect this Echo", 1, 0.82, 0)
        if self:GetChecked() then
            GameTooltip:AddLine("All ranks of this Echo are excluded from explicit and automatic banishing. Click to remove protection.", 0.8, 1, 0.8, true)
        else
            GameTooltip:AddLine("Click once to keep every rank of this Echo safe from all banish logic.", 0.82, 0.82, 0.86, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetChecked(false)
    return btn
end

------------------------------------------------------------------------
-- Rank-specific editors
------------------------------------------------------------------------

local activeEditBox

local function RestoreBorder(box)
    if box:HasFocus() then
        EbonBuilds.Theme.SetInputState(box._container, "focus")
        return
    end
    local rgb = QUALITY_RGB[box.quality] or QUALITY_RGB[0]
    box._container:SetBackdropColor(unpack(EbonBuilds.Theme.INPUT_BG))
    box._container:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 0.82)
end

local function ClearError(box)
    box._error = nil
    RestoreBorder(box)
end

local function SetError(box, message)
    box._error = message
    EbonBuilds.Theme.SetInputState(box._container, "error")
    box._scoreLabel:SetText("|cffff5555Invalid value|r")
end

local function ApplyWeight(box)
    local parsed, validationError = EbonBuilds.Weights.Validate(box:GetText())
    if parsed == nil then
        SetError(box, validationError or "Invalid value.")
        return false, validationError
    end

    local previous = EbonBuilds.Weights.Get(box.echoName, box.quality)
    if previous ~= parsed then
        local ok, err = EbonBuilds.Weights.Set(box.echoName, parsed, box.quality)
        if not ok then
            SetError(box, err or "Invalid value.")
            return false, err
        end
    end

    ClearError(box)
    box:SetText(tostring(parsed))
    if box._row and box._row._entry and box._row._entry.name == box.echoName then
        UpdateProtectionVisual(box._row, box._row._entry, IsWhitelisted(box.echoName))
        UpdateScores(box._row, box._row._entry)
    end

    -- A score-sorted table is re-ordered once on the next frame. Do not run a
    -- full table rebuild here: doing so while the EditBox is still committing
    -- can recycle its row, fire FocusLost again and freeze the client.
    if previous ~= parsed then
        if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.MarkDirty then EbonBuilds.BuildTabs.MarkDirty() end
        if EbonBuilds.EchoTable and EbonBuilds.EchoTable.NotifyWeightChanged then
            EbonBuilds.EchoTable.NotifyWeightChanged(box.echoName, box.quality)
        end
    end
    return true
end

function Rows.CommitActiveEdit()
    if not activeEditBox then return true end
    local box = activeEditBox
    local ok, err = ApplyWeight(box)
    if ok then
        activeEditBox = nil
        box:ClearFocus()
        return true
    end
    if box.SetFocus then box:SetFocus() end
    return false, err or box._error
end

local function RevertInvalidBeforeRecycle(row, nextEntry)
    if not activeEditBox or activeEditBox._row ~= row then return end
    if not row._entry or row._entry.name == nextEntry.name then return end

    local box = activeEditBox
    local oldName, oldQuality = box.echoName, box.quality
    local ok = ApplyWeight(box)
    if not ok then
        box:SetText(tostring(EbonBuilds.Weights.Get(oldName, oldQuality)))
        ClearError(box)
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show("Invalid Echo value was not applied")
        end
    end
    activeEditBox = nil
    box:ClearFocus()
end

local function WireWeightBox(box)
    box:SetScript("OnEnterPressed", function(self)
        if ApplyWeight(self) then activeEditBox = nil; self:ClearFocus() end
    end)
    box:SetScript("OnEditFocusLost", function(self)
        -- Enter and CommitActiveEdit clear activeEditBox before ClearFocus. In
        -- that case the value was already committed and must not be applied a
        -- second time. A normal click-away still commits once here.
        if activeEditBox ~= self then
            RestoreBorder(self)
            return
        end
        activeEditBox = nil
        ApplyWeight(self)
    end)
    box:SetScript("OnEditFocusGained", function(self)
        activeEditBox = self
        self._error = nil
        EbonBuilds.Theme.SetInputState(self._container, "focus")
        self:HighlightText()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(EbonBuilds.Weights.Get(self.echoName, self.quality)))
        self._error = nil
        activeEditBox = nil
        self:ClearFocus()
        RestoreBorder(self)
        if self._row and self._row._entry then UpdateScores(self._row, self._row._entry) end
    end)
    box:SetScript("OnTabPressed", function(self)
        if not ApplyWeight(self) then return end
        activeEditBox = nil
        local row = self._row
        if not row then self:ClearFocus(); return end
        local currentIndex = 1
        for i, quality in ipairs(QUALITY_ORDER) do
            if quality == self.quality then currentIndex = i; break end
        end
        for step = 1, #QUALITY_ORDER do
            local nextIndex = ((currentIndex - 1 + step) % #QUALITY_ORDER) + 1
            local quality = QUALITY_ORDER[nextIndex]
            local cell = row.rankCells and row.rankCells[quality]
            if cell and cell.editContainer and cell.editContainer:IsShown() then
                self:ClearFocus()
                cell.editBox:SetFocus()
                cell.editBox:HighlightText()
                return
            end
        end
        self:ClearFocus()
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local rank = EbonBuilds.Quality.LABELS[self.quality] or tostring(self.quality)
        if self._error then
            GameTooltip:AddLine("Invalid " .. rank .. " value", 1, 0.25, 0.25)
            GameTooltip:AddLine(self._error, 1, 1, 1, true)
        else
            GameTooltip:AddLine(rank .. " Echo value", 1, 0.82, 0)
            GameTooltip:AddLine(string.format("Signed whole number from %d to %d. Press Enter to apply; Escape restores the saved value.", EbonBuilds.Weights.MIN_VALUE, EbonBuilds.Weights.MAX_VALUE), 0.82, 0.82, 0.86, true)
        end
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateRankCell(row, quality, orderIndex)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(Rows.RANK_COL_WIDTH, Rows.ROW_HEIGHT)
    local rightOffset = 4 + (#QUALITY_ORDER - orderIndex) * Rows.RANK_COL_WIDTH
    cell:SetPoint("RIGHT", row, "RIGHT", -rightOffset, 0)

    local unavailableBg = cell:CreateTexture(nil, "BACKGROUND")
    unavailableBg:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -7)
    unavailableBg:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -6, 8)
    unavailableBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    unavailableBg:SetVertexColor(0.10, 0.10, 0.13, 0.42)
    unavailableBg:Hide()

    local sortTint = cell:CreateTexture(nil, "BACKGROUND")
    sortTint:SetAllPoints(cell)
    sortTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    sortTint:SetVertexColor(1.0, 0.82, 0.0, 0.055)
    sortTint:Hide()

    local container = CreateFrame("Frame", nil, cell)
    container:SetSize(50, 22)
    container:SetPoint("TOP", cell, "TOP", 0, -6)
    EbonBuilds.Theme.ApplyInput(container)

    local box = CreateFrame("EditBox", nil, container)
    box:SetSize(46, 18)
    box:SetPoint("CENTER")
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetMaxLetters(7)
    box.quality = quality
    box._container = container
    box._row = row

    local score = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    score:SetPoint("TOP", container, "BOTTOM", 0, -3)
    score:SetWidth(Rows.RANK_COL_WIDTH)
    score:SetJustifyH("CENTER")
    box._scoreLabel = score

    local unavailable = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    unavailable:SetPoint("CENTER")
    unavailable:SetText("")
    unavailable:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    unavailable:Hide()

    WireWeightBox(box)
    RestoreBorder(box)

    cell.editContainer = container
    cell.editBox = box
    cell.scoreLabel = score
    cell.unavailable = unavailable
    cell.sortTint = sortTint
    cell.unavailableBg = unavailableBg
    return cell
end

------------------------------------------------------------------------
-- Row factory / population
------------------------------------------------------------------------

function Rows.CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Rows.ROW_HEIGHT)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:EnableMouse(true)
    row._stripeEven = index % 2 == 0

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row._baseBg = bg

    local hover = row:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(row)
    hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    hover:SetVertexColor(0.28, 0.28, 0.36, 0.28)
    hover:Hide()
    row._hoverBg = hover

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    accent:SetWidth(3)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetVertexColor(unpack(EbonBuilds.Theme.SUCCESS))
    accent:Hide()
    row.protectAccent = accent

    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    row.iconFrame = CreateIconFrame(row)
    WireIconTooltip(row.iconFrame)

    row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameLabel:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 8, -5)
    row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_MARGIN + Rows.RANK_TOTAL + Rows.COL_PROTECT + Rows.COL_POLICY + Rows.COL_QUALITY + 8), 0)
    row.nameLabel:SetHeight(30)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetJustifyV("TOP")
    if row.nameLabel.SetWordWrap then row.nameLabel:SetWordWrap(true) end
    if row.nameLabel.SetNonSpaceWrap then row.nameLabel:SetNonSpaceWrap(false) end

    row.statusLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.statusLabel:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 8, 6)
    row.statusLabel:SetPoint("RIGHT", row.nameLabel, "RIGHT", 0, 0)
    row.statusLabel:SetJustifyH("LEFT")

    row.qualityBadge = CreateQualityBadge(row)
    row.policyDropdown = CreatePolicyDropdown(row)
    row.protectToggle = CreateProtectToggle(row)
    row.rankCells = {}
    for indexInOrder, quality in ipairs(QUALITY_ORDER) do
        row.rankCells[quality] = CreateRankCell(row, quality, indexInOrder)
    end

    row:Hide()
    return row
end

function Rows.Populate(row, yOffset, entry, selectedNames)
    RevertInvalidBeforeRecycle(row, entry)
    if row._entry ~= entry and row.policyDropdown and row.policyDropdown.CloseMenu then row.policyDropdown:CloseMenu() end

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", row:GetParent(), "RIGHT", 0, 0)
    row._entry = entry

    row.iconFrame.spellId = entry.spellId
    row.iconFrame.icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
    row.nameLabel:SetText(EbonBuilds.Quality.Colorize(entry.name, entry.quality))
    if row.qualityBadge and row.qualityBadge.label then
        local q = HighestQuality(entry)
        local rgb = QUALITY_RGB[q] or QUALITY_RGB[0] or { 1, 1, 1 }
        row.qualityBadge.label:SetText(QualityLabel(q))
        row.qualityBadge.label:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
        row.qualityBadge:SetBackdropColor(rgb[1] * 0.10, rgb[2] * 0.10, rgb[3] * 0.10, 0.98)
        row.qualityBadge:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], activeSortKey == "quality" and 1 or 0.60)
    end
    UpdateProtectionVisual(row, entry, IsWhitelisted(entry.name))
    UpdatePolicyVisual(row, entry, selectedNames)

    for _, quality in ipairs(QUALITY_ORDER) do
        local cell = row.rankCells[quality]
        local available = entry.qualities and entry.qualities[quality]
        if cell.sortTint then
            if activeSortKey == ("rank:" .. quality) then cell.sortTint:Show() else cell.sortTint:Hide() end
        end
        cell.editBox.echoName = entry.name
        cell.editBox._error = nil
        if available then
            cell.editContainer:Show()
            cell.scoreLabel:Show()
            cell.unavailable:Hide()
            if cell.unavailableBg then cell.unavailableBg:Hide() end
            cell.editBox:SetText(tostring(EbonBuilds.Weights.Get(entry.name, quality)))
            RestoreBorder(cell.editBox)
        else
            cell.editContainer:Hide()
            cell.scoreLabel:Hide()
            cell.unavailable:Hide()
            if cell.unavailableBg then cell.unavailableBg:Show() end
        end
    end

    UpdateScores(row, entry)
    row:Show()
end

Rows.UpdatePolicyVisual = UpdatePolicyVisual
