-- EbonBuilds: modules/ui/EchoTable.lua
-- Responsibility: scroll frame, headers, and pooled row management for the
-- rank-specific Echo Weights list.

EbonBuilds.EchoTable = {}

local PADDING       = 10
local TITLE_HEIGHT  = 30
local HEADER_HEIGHT = 28
local Rows          = EbonBuilds.EchoTableRows
local ROW_HEIGHT    = Rows.ROW_HEIGHT
local QUALITY_ORDER = EbonBuilds.Quality.ORDER or {}
local RIGHT_MARGIN  = 4

local function GetEditingClass()
    local token
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass then
        token = EbonBuilds.BuildForm.GetEditingClass()
    end
    if not token then
        local build = EbonBuilds.Build.GetActive()
        token = build and build.class
    end
    return token and tostring(token):upper() or nil
end

local function BuildEditorEchoList()
    local showAll = EbonBuilds.Filters and EbonBuilds.Filters.ShowAllClasses
        and EbonBuilds.Filters.ShowAllClasses()
    if Rows and Rows.BuildPriorityList then
        return Rows.BuildPriorityList(GetEditingClass(), showAll)
    end
    return Rows and Rows.BuildSortedList and Rows.BuildSortedList() or {}
end

local echoList, filteredList = {}, {}
local rowPool = {}
local scrollFrame, scrollChild, scrollBar
local headerButtons = {}
local headerFrames = { ranks = {} }
local headerBg
local sortState = { key = "name", desc = false }
local UpdateScrollRange, RefreshRows
local resortPending = false
local policyRefreshPending = false


local function ScoreForRank(weights, settings, entry, quality)
    local weight
    -- Test and compatibility callers can still provide a direct weight table,
    -- but normal editor sorting resolves the exact same ref-key weights shown
    -- in the row cells and used by automation.
    if type(weights) == "table" and entry.refKey and weights[entry.refKey] ~= nil then
        weight = EbonBuilds.Weights.GetFromWeights(weights, entry.refKey, quality)
    elseif type(weights) == "table" and entry.name and weights[entry.name] ~= nil then
        weight = EbonBuilds.Weights.GetFromWeights(weights, entry.name, quality)
    elseif entry.refKey and EbonBuilds.Weights.GetForRef then
        weight = EbonBuilds.Weights.GetForRef(EbonBuilds.Build.GetActive(), entry.refKey, quality)
    else
        weight = EbonBuilds.Weights.GetFromWeights(weights or {}, entry.name, quality)
    end
    return EbonBuilds.Scoring.ScorePerQuality(entry, weight or 0, settings, quality)
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
    EbonBuilds.Scheduler.Cancel("echoTable.resort")
end

local function ResortVisibleList()
    if not scrollFrame or not scrollChild then return end
    SortList(filteredList)
    UpdateScrollRange()
    RefreshRows()
end

local function ScheduleResort()
    EbonBuilds.Scheduler.After("echoTable.resort", 0, function()
        if not resortPending then return end
        resortPending = false
        ResortVisibleList()
    end, EbonBuilds.Scheduler.INTERACTIVE, true)
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
    -- Rebuild from the shared projection so class changes and the optional
    -- All-classes toggle cannot leave this screen on a stale, independently
    -- filtered catalog.
    echoList = BuildEditorEchoList()
    local base = echoList
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
            local label = btn._baseLabel or ""
            local configuredScale = tonumber(EbonBuildsDB and EbonBuildsDB.globalSettings
                and EbonBuildsDB.globalSettings.uiScale) or 1
            if (configuredScale < 0.95 or Rows.IsCompactLayout()) and btn._compactLabel then
                label = btn._compactLabel
            end
            btn:SetText(HeaderLabel(label, key))
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

local function LayoutHeaders(parent)
    if not parent or not headerFrames.protect then return end
    local rankTotal = Rows.RANK_TOTAL

    headerFrames.protect:SetWidth(Rows.COL_PROTECT)
    headerFrames.protect:ClearAllPoints()
    headerFrames.protect:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RIGHT_MARGIN + rankTotal), -3)

    headerFrames.policy:SetWidth(Rows.COL_POLICY)
    headerFrames.policy:ClearAllPoints()
    headerFrames.policy:SetPoint("TOPRIGHT", parent, "TOPRIGHT",
        -(RIGHT_MARGIN + rankTotal + Rows.COL_PROTECT), -3)

    headerFrames.quality:SetWidth(Rows.COL_QUALITY)
    headerFrames.quality:ClearAllPoints()
    headerFrames.quality:SetPoint("TOPRIGHT", parent, "TOPRIGHT",
        -(RIGHT_MARGIN + rankTotal + Rows.COL_PROTECT + Rows.COL_POLICY), -3)

    for orderIndex, quality in ipairs(QUALITY_ORDER) do
        local btn = headerFrames.ranks[quality]
        if btn then
            local rightOffset = RIGHT_MARGIN + (#QUALITY_ORDER - orderIndex) * Rows.RANK_COL_WIDTH
            btn:SetWidth(Rows.RANK_COL_WIDTH)
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightOffset, -3)
        end
    end

    headerFrames.name:ClearAllPoints()
    headerFrames.name:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -3)
    headerFrames.name:SetPoint("TOPRIGHT", headerFrames.quality, "TOPLEFT", -2, 0)
end

local function CreateHeaders(parent)
    headerButtons = {}
    headerFrames = { ranks = {} }

    -- Build the fixed right-side columns from the same widths and offsets used
    -- by EchoTableRows. This keeps the header bar pixel-aligned with every row.
    local protectHdr = CreateStaticHeader(parent, "Protect")
    headerFrames.protect = protectHdr

    local policyHdr = CreateStaticHeader(parent, "Policy")
    headerFrames.policy = policyHdr

    local qualityHdr = CreateHeaderButton(parent, "quality", "Quality", true)
    headerFrames.quality = qualityHdr

    for orderIndex, quality in ipairs(QUALITY_ORDER) do
        local key = "rank:" .. quality
        local label = string.upper(EbonBuilds.Quality.LABELS[quality] or tostring(quality))
        local btn = CreateHeaderButton(parent, key, label, true)
        btn._compactLabel = ({ [3] = "EPIC", [2] = "RARE", [1] = "UNC.", [0] = "COM." })[quality]
        headerFrames.ranks[quality] = btn
    end

    local nameHdr = CreateHeaderButton(parent, "name", "Echo", false)
    headerFrames.name = nameHdr

    LayoutHeaders(parent)
    UpdateHeaderVisuals()
end

function EbonBuilds.EchoTable.RefreshScaleLabels()
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
    local selectedNames = EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.SelectedNames() or {}
    for poolIdx = 1, visibleCount do
        if not rowPool[poolIdx] then
            rowPool[poolIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, poolIdx)
            EbonBuilds.Theme.BindSliderWheel(scrollFrame, scrollBar, ROW_HEIGHT, rowPool[poolIdx])
        end
        local entry = filteredList[scrollOffset + poolIdx]
        if entry then
            EbonBuilds.EchoTableRows.Populate(rowPool[poolIdx], -(poolIdx - 1) * ROW_HEIGHT, entry, selectedNames)
        else
            rowPool[poolIdx]:Hide()
        end
    end
end

local function SyncChildWidth(sf, child)
    local width = sf:GetWidth()
    if width and width > 0 then child:SetWidth(width) end
end

local function ApplyColumnLayout()
    if not scrollFrame then return end
    local compact = Rows.UseCompactLayoutForWidth(scrollFrame:GetWidth())
    local changed = Rows.SetCompactLayout(compact)
    if headerBg then LayoutHeaders(headerBg) end
    for _, row in ipairs(rowPool) do Rows.ApplyRowLayout(row) end
    if changed then UpdateHeaderVisuals() end
end

local function WireScrollBar(sf, bar)
    bar:SetScript("OnValueChanged", RefreshRows)
    EbonBuilds.Theme.BindSliderWheel(sf, bar, ROW_HEIGHT, scrollChild)
    sf:SetScript("OnSizeChanged", function()
        ApplyColumnLayout()
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(sf, "EchoTable.ScrollFrame")
    end
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
    ScheduleResort()
end

local function SchedulePolicyRefresh()
    EbonBuilds.Scheduler.After("echoTable.policyRefresh", 0, function()
        if not policyRefreshPending then return end
        policyRefreshPending = false
        EbonBuilds.EchoTable.RefreshCurrentView(false)
    end, EbonBuilds.Scheduler.INTERACTIVE, true)
end

function EbonBuilds.EchoTable.NotifyPolicyChanged()
    if not scrollFrame then return end
    policyRefreshPending = true
    SchedulePolicyRefresh()
end

function EbonBuilds.EchoTable.ApplyPolicyToFiltered(policy)
    local api = EbonBuilds.EchoPolicy
    if not api or not api.IsValid(policy) then return 0 end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local count = 0
    local changed = false
    for _, entry in ipairs(filteredList or {}) do
        if api.Get(settings, entry.refKey) ~= policy then
            api.SetRef(settings, entry.refKey, policy)
            count = count + 1
            changed = true
        end
        if api.IsBanishPolicy(policy) then
            settings.echoWhitelist = settings.echoWhitelist or {}
            if settings.echoWhitelist[entry.refKey] then
                settings.echoWhitelist[entry.refKey] = nil
                changed = true
            end
        end
    end
    if changed and EbonBuilds.BuildForm and EbonBuilds.BuildForm.PersistEditingSettings then
        EbonBuilds.BuildForm.PersistEditingSettings()
    end
    if changed then EbonBuilds.EchoTable.NotifyPolicyChanged() end
    return count
end

function EbonBuilds.EchoTable.RefreshCurrentView(resetScroll)
    if not scrollFrame then return end
    CancelPendingResort()
    echoList = BuildEditorEchoList()
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
    echoList = BuildEditorEchoList()
    ApplyFiltersAndSort()

    local left = PADDING
    local top = -(TITLE_HEIGHT + PADDING) - FILTER_BAR_OFFSET
    headerBg = CreateFrame("Frame", nil, parent)
    headerBg:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 6)
    headerBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING - 20, top + 6)
    headerBg:SetHeight(HEADER_HEIGHT)
    EbonBuilds.Theme.ApplyCard(headerBg)
    CreateHeaders(headerBg)

    scrollFrame, scrollChild = CreateScrollFrame(parent, left, top - HEADER_HEIGHT)
    scrollBar = CreateScrollBar(scrollFrame)
    WireScrollBar(scrollFrame, scrollBar)
    ApplyColumnLayout()

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
        echoList = BuildEditorEchoList()
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
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.On("ECHO_PROJECTION_CHANGED", function(_, classToken)
            local current = GetEditingClass()
            if not classToken or not current or tostring(classToken):upper() == current then Rebuild() end
        end)
    end

    SyncChildWidth(scrollFrame, scrollChild)
    UpdateScrollRange()
    RefreshRows()
end


function EbonBuilds.EchoTable.RefreshLayout()
    if not scrollFrame then return end
    ApplyColumnLayout()
    SyncChildWidth(scrollFrame, scrollChild)
    UpdateScrollRange()
    RefreshRows()
end
