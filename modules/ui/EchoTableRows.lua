-- EbonBuilds: modules/ui/EchoTableRows.lua
-- Responsibility: data preparation and row-frame factory for EchoTable.

EbonBuilds.EchoTableRows = {}

local COL_ICON   = 40
local COL_WEIGHT = 80
local COL_SCORE  = 140
local ROW_HEIGHT = 36

local QUALITY_COLORS = EbonBuilds.Quality.HEX

-- Data preparation -----------------------------------------------------

-- Single source of truth for the weight key lives in Weights.lua; the
-- table and the automation MUST derive names identically or weights
-- silently stop applying (see Weights.CanonicalName).
local StripQualitySuffix = EbonBuilds.Weights.StripQualitySuffix

local function BuildBestByName()
    local best = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local raw = data.comment
        if raw and raw ~= "" then
            local name = StripQualitySuffix(raw)
            local existing = best[name]
            local mask = data.classMask or 0
            if not existing then
                existing = { spellId = spellId, quality = data.quality, qualities = {}, families = data.families or {}, classMask = mask, spellIds = {} }
                best[name] = existing
            else
                existing.classMask = bit.bor(existing.classMask or 0, mask)
                if data.quality > existing.quality then
                    existing.spellId  = spellId
                    existing.quality  = data.quality
                    existing.families = data.families or {}
                end
            end
            existing.qualities[data.quality] = true
            existing.spellIds[data.quality] = spellId
        end
    end
    return best
end

EbonBuilds.EchoTableRows.BuildBestByName = BuildBestByName

local cachedSortedList, cachedDbCount

local function CountDb()
    local n = 0
    for _ in pairs(ProjectEbonhold.PerkDatabase) do n = n + 1 end
    return n
end

function EbonBuilds.EchoTableRows.BuildSortedList()
    -- ComputePeak runs on every wizard/settings slider tick; rebuilding and
    -- resorting 500+ entries each time is wasteful. The DB only changes when
    -- the server (re)sends it, so a cheap entry-count check is enough to
    -- detect that and rebuild.
    local count = CountDb()
    if cachedSortedList and cachedDbCount == count then
        return cachedSortedList
    end

    local best = BuildBestByName()
    local list = {}
    for name, entry in pairs(best) do
        list[#list + 1] = {
            spellId = entry.spellId, name = name, quality = entry.quality,
            qualities = entry.qualities, families = entry.families,
            classMask = entry.classMask or 0,
            spellIds = entry.spellIds,
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)

    cachedSortedList = list
    cachedDbCount = count
    return list
end

function EbonBuilds.EchoTableRows.InvalidateCache()
    cachedSortedList, cachedDbCount = nil, nil
end

function EbonBuilds.EchoTableRows.BuildAllQualitiesList()
    local list = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local raw = data.comment
        if raw and raw ~= "" then
            local name = StripQualitySuffix(raw)
            list[#list + 1] = {
                spellId = spellId,
                name = name,
                quality = data.quality,
                classMask = data.classMask or 0,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.quality < b.quality
    end)
    return list
end

local function UpdateScores(row, entry)
    if not row.scoreLabel then return end
    local weight = EbonBuilds.Weights.Get(entry.name) or 0
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local parts = {}
    for q = 0, 4 do
        if entry.qualities[q] then
            local spellId = entry.spellIds and entry.spellIds[q]
            if spellId and EbonBuilds.Scoring.IsLocked(spellId) then
                parts[#parts + 1] = string.format("|cff%sLocked|r", QUALITY_COLORS[q])
            elseif spellId and EbonBuilds.Scoring.IsBanned(spellId) then
                parts[#parts + 1] = string.format("|cff%sBanned|r", QUALITY_COLORS[q])
            else
                local score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, q)
                parts[#parts + 1] = string.format("|cff%s%d|r", QUALITY_COLORS[q], score)
            end
        end
    end
    row.scoreLabel:SetText(table.concat(parts, " - "))
end

-- Icon cell ------------------------------------------------------------

local function CreateIconFrame(row)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetWidth(COL_ICON)
    frame:SetHeight(ROW_HEIGHT)
    frame:SetPoint("LEFT", row, "LEFT", 4, 0)
    frame:EnableMouse(true)
    frame.spellId = 0

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(28)
    tex:SetHeight(28)
    tex:SetPoint("CENTER", frame, "CENTER")
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
        if spellName then
            GameTooltip:AddLine(spellName, 1, 0.82, 0)
        end
        if utils and utils.GetSpellDescription then
            local description = utils.GetSpellDescription(self.spellId, 500, 1)
            if description and description ~= "" then
                GameTooltip:AddLine(description, 1, 1, 1, true)
            end
        end
        if spellName and EbonBuilds.Calibration and EbonBuilds.Calibration.GetAppearanceStats then
            local ap = EbonBuilds.Calibration.GetAppearanceStats(spellName)
            if ap then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("Appears in ~%.1f%% of offers (%d evaluations)", ap.pct, ap.totalEvals), 0.6, 0.8, 1)
            end
        end
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
EbonBuilds.EchoTableRows.WireIconTooltip = WireIconTooltip

-- Weight cell ----------------------------------------------------------

local function ApplyWeight(editBox, raw)
    local num = tonumber(raw)
    if num and math.floor(num) == num and num >= 0 then
        EbonBuilds.Weights.Set(editBox.echoName, num)
    end
    editBox:SetText(tostring(EbonBuilds.Weights.Get(editBox.echoName)))
    if editBox._row and editBox._row.scoreLabel then
        local row = editBox._row
        local entry = { name = editBox.echoName, qualities = row._qualities, families = row._families, spellIds = row._spellIds }
        UpdateScores(row, entry)
    end
end

local function WireWeightBox(editBox)
    editBox:SetScript("OnChar", function(self, char)
        if not char:match("%d") then
            local pos  = self:GetCursorPosition()
            local text = self:GetText()
            self:SetText(text:sub(1, pos - 1) .. text:sub(pos + 1))
            self:SetCursorPosition(pos - 1)
        end
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        ApplyWeight(self, self:GetText())
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        ApplyWeight(self, self:GetText())
    end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
end

local function CreateWeightBox(parentRow)
    local editContainer = CreateFrame("Frame", nil, parentRow)
    editContainer:SetSize(58, 22)
    editContainer:SetPoint("RIGHT", parentRow, "RIGHT", -8, 0)
    editContainer:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    editContainer:SetBackdropColor(0, 0, 0, 0.6)
    editContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local box = CreateFrame("EditBox", nil, editContainer)
    box:SetSize(52, 18)
    box:SetPoint("CENTER", editContainer, "CENTER", 0, 0)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetMaxLetters(6)
    box._row = parentRow
    WireWeightBox(box)
    return box
end

-- Row factory ----------------------------------------------------------

local function AddBackground(row, index)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture(0, 0, 0, (index % 2 == 0) and 0.15 or 0.05)
end

-- Creates a single pooled row frame attached to parent.
function EbonBuilds.EchoTableRows.CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    AddBackground(row, index)

    local iconFrame = CreateIconFrame(row)
    WireIconTooltip(iconFrame)

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", row,       "RIGHT", -(COL_WEIGHT + COL_SCORE + 24), 0)
    nameLabel:SetJustifyH("LEFT")

    local scoreLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scoreLabel:SetPoint("RIGHT", row, "RIGHT", -(COL_WEIGHT + 16), 0)
    scoreLabel:SetWidth(COL_SCORE)
    scoreLabel:SetJustifyH("RIGHT")

    local weightBox = CreateWeightBox(row)

    row.iconFrame  = iconFrame
    row.nameLabel  = nameLabel
    row.scoreLabel = scoreLabel
    row.weightBox  = weightBox
    row:Hide()
    return row
end

function EbonBuilds.EchoTableRows.Populate(row, yOffset, entry)
    row:SetPoint("TOP", row:GetParent(), "TOP", 0, yOffset)
    row.iconFrame.spellId = entry.spellId
    row.iconFrame.icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
    -- Name tinted by the echo's highest available rarity, item-style.
    row.nameLabel:SetText(EbonBuilds.Quality.Colorize(entry.name, entry.quality))
    row.weightBox.echoName = entry.name
    row.weightBox:SetText(tostring(EbonBuilds.Weights.Get(entry.name)))
    row._qualities = entry.qualities
    row._families  = entry.families
    row._spellIds  = entry.spellIds
    UpdateScores(row, entry)
    row:Show()
end
