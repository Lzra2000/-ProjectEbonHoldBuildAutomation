-- EbonBuilds: modules/ui/EchoTable.lua
-- Responsibility: scroll frame, headers, and pooled row management for the
-- rank-specific Echo Weights list.

EbonBuilds.EchoTable = {}

local PADDING       = 10
local TITLE_HEIGHT  = 30
local HEADER_HEIGHT = 28
local ROW_HEIGHT    = EbonBuilds.EchoTableRows.ROW_HEIGHT
local COL_ICON      = EbonBuilds.EchoTableRows.COL_ICON
local COL_QUALITY   = EbonBuilds.EchoTableRows.COL_QUALITY
local COL_PROTECT   = EbonBuilds.EchoTableRows.COL_PROTECT
local RANK_COL_W    = EbonBuilds.EchoTableRows.RANK_COL_WIDTH
local RANK_TOTAL    = EbonBuilds.EchoTableRows.RANK_TOTAL
local QUALITY_ORDER = EbonBuilds.Quality.ORDER or {}
local RIGHT_MARGIN  = 4

local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local function ApplyClassFilter(list)
    if EbonBuilds.Filters and EbonBuilds.Filters.ShowAllClasses and EbonBuilds.Filters.ShowAllClasses() then
        return list
    end
    local token
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass then
        token = EbonBuilds.BuildForm.GetEditingClass()
    end
    if not token then
        local build = EbonBuilds.Build.GetActive()
        token = build and build.class
    end
    local bitVal = token and CLASS_BITS[token]
    if not bitVal then return list end

    local out = {}
    for i = 1, #list do
        local entry = list[i]
        if not entry.classMask or entry.classMask == 0 or bit.band(entry.classMask, bitVal) ~= 0 then
            out[#out + 1] = entry
        end
    end
    return out
end

local echoList, filteredList = {}, {}
local rowPool = {}
local scrollFrame, scrollChild, scrollBar
local headerButtons = {}
local sortState = { key = "name", desc = false }
local UpdateScrollRange, RefreshRows
local resortFrame, resortPending = nil, false


local function ScoreForRank(weights, settings, entry, quality)
    local weight = EbonBuilds.Weights.GetFromWeights(weights, entry.name, quality) or 0
    return EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
end

local function MaxScoreFrom(weights, settings, entry)
    local maxVal
    for _, quality in ipairs(QUALITY_ORDER) do
        if entry.qualities and entry.qualities[quality] then
            local score = ScoreForRank(weights, settings, entry, quality)
            if maxVal == nil or score > maxVal then maxVal = score end
        end
    end
    return maxVal or 0
end

local function RankFromSortKey(key)
    return tonumber((tostring(key):match("^rank:(%-?%d+)$")))
end

local function SortDescriptor(entry, key, weights, settings)
    if key == "name" then
        return { missing = false, value = string.lower(entry.name or "") }
    elseif key == "quality" then
        return { missing = false, value = entry.quality or 0 }
    elseif key == "weight" then
        return { missing = false, value = MaxScoreFrom(weights, settings, entry) }
    end

    local rank = RankFromSortKey(key)
    if rank ~= nil then
        -- Use the selected rank when the Echo has it. Otherwise compare using
        -- the Echo's highest available rank instead of treating the entry as
        -- missing or forcing it below every Echo of the selected rank. This
        -- keeps sorting score-first. The resolved rank is then evaluated
        -- with the same quality and family modifiers used by the visible
        -- Score label and automation.
        local resolvedRank = nil
        if entry.qualities and entry.qualities[rank] then
            resolvedRank = rank
        else
            for _, availableRank in ipairs(QUALITY_ORDER) do
                if entry.qualities and entry.qualities[availableRank] then
                    resolvedRank = availableRank
                    break
                end
            end
        end
        return {
            missing = resolvedRank == nil,
            value = resolvedRank and ScoreForRank(weights, settings, entry, resolvedRank) or 0,
            rank = resolvedRank,
        }
    end

    return { missing = false, value = string.lower(entry.name or "") }
end

local function CompareValues(a, b, desc)
    if a == b then return nil end
    if desc then return a > b end
    return a < b
end


local function SortList(list, weightsOverride, settingsOverride)
    local weights = weightsOverride or EbonBuilds.Build.GetActiveWeights() or {}
    local settings = settingsOverride or EbonBuilds.Scoring.GetEffectiveSettings() or EbonBuilds.Build.DefaultSettings()
    local decorated = {}
    for i = 1, #list do
        local entry = list[i]
        decorated[i] = {
            entry = entry,
            sort = SortDescriptor(entry, sortState.key, weights, settings),
            name = string.lower(entry.name or ""),
        }
    end

    table.sort(decorated, function(a, b)
        -- Entries with no known quality at all sort last. Echoes that merely
        -- lack the selected rank already received their highest available
        -- rank value in SortDescriptor and participate normally by value.
        if a.sort.missing ~= b.sort.missing then
            return not a.sort.missing
        end

        local result = CompareValues(a.sort.value, b.sort.value, sortState.desc)
        if result ~= nil then return result end

        -- Protection state is deliberately excluded from every tie-breaker.
        -- Equal total scores fall back only to Echo name for deterministic order.
        return a.name < b.name
    end)

    for i = 1, #decorated do list[i] = decorated[i].entry end
end

local function SortDependsOnScore()
    return sortState.key == "weight" or RankFromSortKey(sortState.key) ~= nil
end

local function CancelPendingResort()
    resortPending = false
    if resortFrame then resortFrame:Hide() end
end

local function ResortVisibleList()
    if not scrollFrame or not scrollChild then return end
    SortList(filteredList)
    UpdateScrollRange()
    RefreshRows()
end

local function EnsureResortFrame()
    if resortFrame then return resortFrame end
    resortFrame = CreateFrame("Frame")
    resortFrame:Hide()
    resortFrame:SetScript("OnUpdate", function(self)
        self:Hide()
        if not resortPending then return end
        resortPending = false
        ResortVisibleList()
    end)
    return resortFrame
end

-- Small test hook for regression coverage. It sorts the supplied list with
-- the exact production comparator but never touches protection state.
function EbonBuilds.EchoTable._SortEntriesForTest(list, key, desc, weights, settings)
    local previousKey, previousDesc = sortState.key, sortState.desc
    sortState.key, sortState.desc = key, desc and true or false
    SortList(list, weights or {}, settings or EbonBuilds.Build.DefaultSettings())
    sortState.key, sortState.desc = previousKey, previousDesc
    return list
end

local function ApplyFiltersAndSort()
    local base = ApplyClassFilter(echoList)
    if EbonBuilds.Filters and EbonBuilds.Filters.Apply then
        base = EbonBuilds.Filters.Apply(base)
    end
    SortList(base)
    filteredList = base
    if EbonBuilds.Filters and EbonBuilds.Filters.SetResultCount then
        EbonBuilds.Filters.SetResultCount(#filteredList, #echoList)
    end
end

local function HeaderLabel(label, key)
    local text = label
    if sortState.key == key then
        text = text .. (sortState.desc and " v" or " ^")
    end
    return text
end

local function UpdateHeaderVisuals()
    if EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.SetActiveSortKey then
        EbonBuilds.EchoTableRows.SetActiveSortKey(sortState.key)
    end
    if not headerButtons then return end
    for key, btn in pairs(headerButtons) do
        if btn and btn.SetText then
            btn:SetText(HeaderLabel(btn._baseLabel or "", key))
            if EbonBuilds.Theme and EbonBuilds.Theme.SetTabSelected then
                EbonBuilds.Theme.SetTabSelected(btn, sortState.key == key)
            end
        end
    end
end

local function SetSort(key, defaultDesc)
    CancelPendingResort()
    if sortState.key == key then
        sortState.desc = not sortState.desc
    else
        sortState.key = key
        sortState.desc = defaultDesc and true or false
    end
    UpdateHeaderVisuals()
    ApplyFiltersAndSort()
    if scrollBar then scrollBar:SetValue(0) end
    if scrollFrame and scrollChild then
        UpdateScrollRange()
        RefreshRows()
    end
end
------------------------------------------------------------------------
-- Headers
------------------------------------------------------------------------

local function CreateHeaderButton(parent, key, text, defaultDesc)
    local btn = EbonBuilds.Theme.CreateTab(parent, text)
    btn._baseLabel = text
    btn:SetHeight(22)
    btn:SetScript("OnClick", function() SetSort(key, defaultDesc) end)
    if EbonBuilds.Theme and EbonBuilds.Theme.AttachTooltip then
        local body = "Click to sort by this column. Click again to reverse the direction."
        if RankFromSortKey(key) ~= nil then
            body = body .. " Sort uses the final displayed score, including rank and family modifiers. Echoes without this rank use their highest available rank."
        end
        EbonBuilds.Theme.AttachTooltip(btn, text .. " sort", body)
    end
    headerButtons[key] = btn
    return btn
end

local function CreateStaticHeader(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(22)
    EbonBuilds.Theme.ApplyCard(frame)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(0.82, 0.82, 0.86, 1)
    frame.label = label
    return frame
end

local function CreateHeaders(parent)
    headerButtons = {}

    -- Build the fixed right-side columns from the same widths and offsets used
    -- by EchoTableRows. This keeps the header bar pixel-aligned with every row.
    local protectHdr = CreateStaticHeader(parent, "Protect")
    protectHdr:SetWidth(COL_PROTECT)
    protectHdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RIGHT_MARGIN + RANK_TOTAL), -3)

    local qualityHdr = CreateHeaderButton(parent, "quality", "Quality", true)
    qualityHdr:SetWidth(COL_QUALITY)
    qualityHdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RIGHT_MARGIN + RANK_TOTAL + COL_PROTECT), -3)

    for orderIndex, quality in ipairs(QUALITY_ORDER) do
        local key = "rank:" .. quality
        local label = string.upper(EbonBuilds.Quality.LABELS[quality] or tostring(quality))
        local rightOffset = RIGHT_MARGIN + (#QUALITY_ORDER - orderIndex) * RANK_COL_W
        local btn = CreateHeaderButton(parent, key, label, true)
        btn:SetWidth(RANK_COL_W)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightOffset, -3)
    end

    local nameHdr = CreateHeaderButton(parent, "name", "Echo", false)
    nameHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_ICON + 2, -3)
    nameHdr:SetPoint("TOPRIGHT", qualityHdr, "TOPLEFT", -2, 0)

    UpdateHeaderVisuals()
end

------------------------------------------------------------------------
-- Scroll rendering
------------------------------------------------------------------------

local function GetVisibleCount()
    return math.ceil(scrollFrame:GetHeight() / ROW_HEIGHT) + 1
end

UpdateScrollRange = function()
    -- Base the range on fully visible rows, not the oversized pooled-row count.
    -- The pool intentionally renders an extra row, but using that count for the
    -- maximum offset stopped one row too early and left the final Echo hidden
    -- underneath the footer/header chrome.
    local viewportHeight = math.max(0, scrollFrame:GetHeight() or 0)
    local fullVisibleRows = math.max(1, math.floor(math.max(0, viewportHeight - 8) / ROW_HEIGHT))
    local maxOffset = math.max(0, (#filteredList - fullVisibleRows) * ROW_HEIGHT)
    scrollBar:SetMinMaxValues(0, maxOffset)
    if scrollBar:GetValue() > maxOffset then scrollBar:SetValue(maxOffset) end
end

RefreshRows = function()
    local scrollOffset = math.floor(scrollBar:GetValue() / ROW_HEIGHT + 0.5)
    local visibleCount = GetVisibleCount()
    for poolIdx = 1, visibleCount do
        if not rowPool[poolIdx] then
            rowPool[poolIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, poolIdx)
            EbonBuilds.Theme.BindSliderWheel(scrollFrame, scrollBar, ROW_HEIGHT, rowPool[poolIdx])
        end
        local entry = filteredList[scrollOffset + poolIdx]
        if entry then
            EbonBuilds.EchoTableRows.Populate(rowPool[poolIdx], -(poolIdx - 1) * ROW_HEIGHT, entry)
        else
            rowPool[poolIdx]:Hide()
        end
    end
end

local function SyncChildWidth(sf, child)
    local width = sf:GetWidth()
    if width and width > 0 then child:SetWidth(width) end
end

local function WireScrollBar(sf, bar)
    bar:SetScript("OnValueChanged", RefreshRows)
    EbonBuilds.Theme.BindSliderWheel(sf, bar, ROW_HEIGHT, scrollChild)
    sf:SetScript("OnSizeChanged", function()
        SyncChildWidth(sf, scrollChild)
        UpdateScrollRange()
        RefreshRows()
    end)
end

local function CreateScrollBar(sf)
    local bar = EbonBuilds.Theme.CreateScrollBar(sf)
    bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 18, -2)
    bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 18, 2)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(ROW_HEIGHT)
    bar:SetValue(0)
    return bar
end

local function CreateScrollFrame(parent, x, y)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -x - 20, PADDING)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    return sf, child
end

------------------------------------------------------------------------
-- Validation contract
------------------------------------------------------------------------


function EbonBuilds.EchoTable.ValidateAndCommitAll()
    if EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.CommitActiveEdit then
        return EbonBuilds.EchoTableRows.CommitActiveEdit()
    end
    return true
end

-- Called after a rank value is committed. Weight edits only require a
-- re-sort when a score column is active; filters, database catalog data and
-- row frames do not need to be rebuilt. The work is deferred by one frame so
-- Enter/FocusLost cannot recursively recycle the row that is still committing.
function EbonBuilds.EchoTable.NotifyWeightChanged()
    if not scrollFrame or not SortDependsOnScore() then return end
    resortPending = true
    EnsureResortFrame():Show()
end

function EbonBuilds.EchoTable.RefreshCurrentView(resetScroll)
    if not scrollFrame then return end
    CancelPendingResort()
    echoList = EbonBuilds.EchoTableRows.BuildSortedList()
    ApplyFiltersAndSort()
    UpdateHeaderVisuals()
    UpdateScrollRange()
    if resetScroll and scrollBar then scrollBar:SetValue(0) end
    RefreshRows()
end

------------------------------------------------------------------------
-- Public Init
------------------------------------------------------------------------

local FILTER_BAR_OFFSET = 100

function EbonBuilds.EchoTable.Init(parent)
    echoList = EbonBuilds.EchoTableRows.BuildSortedList()
    ApplyFiltersAndSort()

    local left = PADDING
    local top = -(TITLE_HEIGHT + PADDING) - FILTER_BAR_OFFSET
    local headerBg = CreateFrame("Frame", nil, parent)
    headerBg:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 6)
    headerBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING - 20, top + 6)
    headerBg:SetHeight(HEADER_HEIGHT)
    EbonBuilds.Theme.ApplyCard(headerBg)
    CreateHeaders(headerBg)

    scrollFrame, scrollChild = CreateScrollFrame(parent, left, top - HEADER_HEIGHT)
    scrollBar = CreateScrollBar(scrollFrame)
    WireScrollBar(scrollFrame, scrollBar)

    scrollFrame:SetScript("OnShow", function()
        CancelPendingResort()
        SyncChildWidth(scrollFrame, scrollChild)
        ApplyFiltersAndSort()
        UpdateScrollRange()
        RefreshRows()
    end)

    if EbonBuilds.Filters and EbonBuilds.Filters.OnChange then
        EbonBuilds.Filters.OnChange(function()
            CancelPendingResort()
            ApplyFiltersAndSort()
            UpdateScrollRange()
            scrollBar:SetValue(0)
            RefreshRows()
        end)
    end

    local function Rebuild()
        CancelPendingResort()
        echoList = EbonBuilds.EchoTableRows.BuildSortedList()
        ApplyFiltersAndSort()
        UpdateScrollRange()
        RefreshRows()
    end

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Rebuild)
    end
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.OnClassChanged then
        EbonBuilds.BuildForm.OnClassChanged(Rebuild)
    end

    SyncChildWidth(scrollFrame, scrollChild)
    UpdateScrollRange()
    RefreshRows()
end
