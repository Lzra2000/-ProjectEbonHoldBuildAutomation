-- EbonBuilds: modules/ui/SessionHistory.lua
-- Decision-first Logbook for WoW 3.3.5a.
-- The page keeps run context, filters, a sortable recycled timeline, and one
-- collapsible evidence inspector in a single deterministic refresh pipeline.

EbonBuilds.SessionHistory = {}

local H = EbonBuilds.SessionHistory
local Theme = EbonBuilds.Theme

local ACTION_COLORS = {
    Select = { 0.27, 1.00, 0.27 },
    Banish = { 1.00, 0.27, 0.27 },
    Reroll = { 0.27, 0.67, 1.00 },
    Freeze = { 0.27, 0.80, 1.00 },
    Manual = { 1.00, 0.66, 0.16 },
    Other  = { 0.75, 0.75, 0.78 },
}

local EVENT_ROW_H = 34
local LEVEL_ROW_H = 22
local TOP_H = 84
local SUMMARY_H = 54
local DETAIL_H = 154
local DETAIL_WIDTH_GAP = 8

local topPanel, summaryStrip, bottomPanel
local runDropdown, previousRunButton, nextRunButton, runPositionLabel, historyDropdown
local summaryMetrics = {}
local toolbar, searchInput, searchPlaceholder, actionDropdown, sourceDropdown
local importantButton, groupButton, clearFiltersButton, resultLabel
local chipFrame, chipPool, chipEmpty = nil, {}, nil
local headerBar, headerButtons, headerLabels = nil, {}, {}
local logScroll, logChild, logBar, emptyState, emptyClearButton
local detailPanel, detailTitle, detailReason, detailMeta, detailFlags, detailResources
local detailChoiceRows = {}
local detailCopyButton

local relevantSessionCache = {}
local selectedSessionId
local selectedEntry
local durationTimer
local visible = false
local lastBuildKey

local rowPool = {}
local timelineItems, timelineOffsets, timelineTotalHeight = {}, {}, 1

local searchText = ""
local actionFilter = "All"
local sourceFilter = "All"
local importantOnly = false
local groupByLevel = false
local sortColumn = "time"
local sortAscending = true
local pendingFilters

local pendingDeleteSessionId
local pendingClearSessionIds

local function VisibleEchoName(name)
    if EbonBuilds.Weights and EbonBuilds.Weights.VisibleName then
        return EbonBuilds.Weights.VisibleName(name)
    end
    local value = tostring(name or "")
    for index = 1, #value do
        local byte = value:byte(index)
        if byte and (byte < 32 or byte == 127) then
            value = value:sub(1, index - 1)
            break
        end
    end
    return value
end

local function SearchSafeLower(value)
    local source = tostring(value or "")
    local out = {}
    for index = 1, #source do
        local byte = source:byte(index)
        if byte and byte >= 32 and byte ~= 127 then
            out[#out + 1] = string.char(byte)
        else
            out[#out + 1] = " "
        end
    end
    return string.lower(table.concat(out))
end

------------------------------------------------------------------------
-- Data helpers
------------------------------------------------------------------------

local function FormatDuration(startTime, endTime)
    local seconds = math.max(0, (endTime or time()) - (startTime or time()))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function FormatTimestamp(timestamp)
    return date("%H:%M:%S", timestamp or time())
end

local function FormatRunDate(timestamp)
    if not timestamp then return "Unknown start" end
    return date("%d %b %H:%M", timestamp)
end

local function NormalizeAction(action)
    action = tostring(action or "")
    if action:find("^Select") then return "Select" end
    if action:find("^Banish") then return "Banish" end
    if action:find("^Reroll") then return "Reroll" end
    if action:find("^Freeze") then return "Freeze" end
    if action:find("^Manual") then return "Manual" end
    return action ~= "" and action or "Other"
end

local function DecisionSource(entry)
    local source = entry and entry.decision and entry.decision.source or "automatic"
    source = string.lower(tostring(source or "automatic"))
    if source:find("manual") then return "Manual" end
    return "Automatic"
end

local function TargetChoice(entry)
    if not entry then return nil end
    local targetIndex = tonumber(entry.targetIndex)
    if targetIndex then
        for arrayIndex, choice in ipairs(entry.choices or {}) do
            if arrayIndex == targetIndex or tonumber(choice.index) == targetIndex then
                return choice, arrayIndex
            end
        end
    end
    return nil
end

local function BestAlternative(entry)
    local target, targetArrayIndex = TargetChoice(entry)
    local best
    for arrayIndex, choice in ipairs((entry and entry.choices) or {}) do
        if choice ~= target and arrayIndex ~= targetArrayIndex then
            if not best or (tonumber(choice.score) or 0) > (tonumber(best.score) or 0) then best = choice end
        end
    end
    return best
end

local REASON_TEXT = {
    BELOW_BANISH_THRESHOLD = "Below the active banish threshold",
    BOARD_BELOW_REROLL_THRESHOLD = "The board was below the reroll threshold",
    TWO_OFFERS_ABOVE_FREEZE_THRESHOLD = "Two offers exceeded the freeze threshold",
    HIGHEST_FINAL_SCORE = "Highest eligible final score",
    MANUAL_CHOICE = "Player made this choice manually",
}

local function IsImportant(entry)
    if not entry then return false end
    local decision = entry.decision or {}
    local flags = decision.flags or {}
    if flags.lastCharge or flags.closeDecision or flags.modifierOverride or flags.manualDisagreement or flags.fallback or flags.failed or flags.protectionAffected then
        return true
    end
    local charges = entry.charges or {}
    local action = NormalizeAction(entry.action)
    if action == "Banish" and (charges.ban or 0) <= 1 then return true end
    if action == "Reroll" and (charges.reroll or 0) <= 1 then return true end
    if action == "Freeze" and (charges.freeze or 0) <= 1 then return true end
    if DecisionSource(entry) == "Manual" then
        local target = TargetChoice(entry)
        local bestScore
        for _, choice in ipairs(entry.choices or {}) do
            local score = tonumber(choice.score) or 0
            if bestScore == nil or score > bestScore then bestScore = score end
        end
        return target and bestScore and (tonumber(target.score) or 0) < bestScore or false
    end
    return false
end

local function ReasonSentence(entry)
    entry = entry or {}
    local action = NormalizeAction(entry.action)
    local decision = entry.decision or {}
    local target, alternative = TargetChoice(entry), BestAlternative(entry)
    local threshold = tonumber(decision.threshold)
    local reason = REASON_TEXT[decision.reasonCode]

    if action == "Banish" and target then
        if threshold then return string.format("%.0f below threshold %.0f", tonumber(target.score) or 0, threshold) end
        return reason or "Removed the chosen low-value Echo"
    elseif action == "Reroll" then
        if alternative then return string.format("Best current option: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0) end
        return reason or "Replaced the current offer"
    elseif action == "Freeze" and target then
        if threshold then return string.format("%.0f exceeded threshold %.0f", tonumber(target.score) or 0, threshold) end
        return reason or "Preserved a strong Echo for later"
    elseif (action == "Select" or action == "Manual") and target then
        if alternative then return string.format("Next-best: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0) end
        return reason or "Selected the highest eligible Echo"
    end
    return reason or "Detailed reason was not recorded"
end

local function DecisionLabel(entry)
    entry = entry or {}
    local action = NormalizeAction(entry.action)
    local target = TargetChoice(entry)
    if target then return target.name or "Unknown Echo", tonumber(target.score) or 0, tonumber(target.quality) or 0, target end
    if action == "Reroll" then
        local best = BestAlternative(entry)
        return best and ("Offer · best " .. (best.name or "Echo")) or "Offer rerolled", best and (tonumber(best.score) or 0) or 0, best and (tonumber(best.quality) or 0) or 0, best
    end
    return action, 0, 0, nil
end

local function ActiveBuildKey()
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build then return "NO_BUILD" end
    return tostring(build.id or build.title or "NO_BUILD")
end

local function SessionMatchesActiveBuild(session)
    if not session then return false end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build then return true end
    if session.buildId and session.buildId == build.id then return true end
    if not session.buildId and session.buildTitle and session.buildTitle == build.title then return true end
    for _, entry in ipairs(session.logs or {}) do
        local decision = entry.decision or {}
        if decision.buildId and decision.buildId == build.id then return true end
        if decision.buildTitle and decision.buildTitle == build.title then return true end
    end
    return false
end

local function RelevantSessions()
    local out = {}
    for _, session in ipairs((EbonBuilds.Session and EbonBuilds.Session.GetSessions and EbonBuilds.Session.GetSessions()) or {}) do
        if SessionMatchesActiveBuild(session) then out[#out + 1] = session end
    end
    table.sort(out, function(a, b)
        if not a.endTime and b.endTime then return true end
        if not b.endTime and a.endTime then return false end
        if (a.startTime or 0) ~= (b.startTime or 0) then return (a.startTime or 0) > (b.startTime or 0) end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    return out
end

local function FindSession(id)
    for _, session in ipairs((EbonBuilds.Session and EbonBuilds.Session.GetSessions and EbonBuilds.Session.GetSessions()) or {}) do
        if session.id == id then return session end
    end
end

local function SelectedSession()
    return selectedSessionId and FindSession(selectedSessionId) or nil
end

local function SessionSummary(session)
    local result = {
        events = 0,
        selectedCount = 0,
        selectedSum = 0,
        actions = { Select = 0, Banish = 0, Reroll = 0, Freeze = 0, Manual = 0 },
    }
    if not session then return result end
    for _, entry in ipairs(session.logs or {}) do
        result.events = result.events + 1
        local action = NormalizeAction(entry.action)
        result.actions[action] = (result.actions[action] or 0) + 1
        if action == "Select" or action == "Manual" then
            local target = TargetChoice(entry)
            if target then
                result.selectedCount = result.selectedCount + 1
                result.selectedSum = result.selectedSum + (tonumber(target.score) or 0)
            end
        end
    end
    result.averageSelected = result.selectedCount > 0 and result.selectedSum / result.selectedCount or 0
    return result
end

local function SearchableText(entry)
    local fields = {
        tostring(entry.action or ""),
        NormalizeAction(entry.action),
        DecisionSource(entry),
        FormatTimestamp(entry.timestamp),
        ReasonSentence(entry),
        tostring(entry.level or ""),
    }
    local decision = entry.decision or {}
    fields[#fields + 1] = tostring(decision.reasonCode or "")
    fields[#fields + 1] = tostring(decision.model or "")
    for _, choice in ipairs(entry.choices or {}) do
        fields[#fields + 1] = tostring(choice.name or "")
        fields[#fields + 1] = tostring(choice.spellId or "")
        if choice.families then fields[#fields + 1] = tostring(choice.families) end
    end
    return SearchSafeLower(table.concat(fields, " "))
end

local function EntryMatches(entry)
    if not entry then return false end
    if actionFilter ~= "All" and NormalizeAction(entry.action) ~= actionFilter then return false end
    if sourceFilter ~= "All" and DecisionSource(entry) ~= sourceFilter then return false end
    if importantOnly and not IsImportant(entry) then return false end
    if searchText == "" then return true end
    return SearchableText(entry):find(SearchSafeLower(searchText), 1, true) ~= nil
end

local function SortValue(wrapper, column)
    local entry = wrapper.entry
    if column == "time" then return tonumber(entry.timestamp) or 0 end
    if column == "action" then return string.lower(NormalizeAction(entry.action)) end
    if column == "subject" then
        local name = DecisionLabel(entry)
        return SearchSafeLower(VisibleEchoName(name))
    end
    return wrapper.index or 0
end

local function CompareWrappers(left, right)
    local leftValue = SortValue(left, sortColumn)
    local rightValue = SortValue(right, sortColumn)
    if leftValue ~= rightValue then
        if sortAscending then return leftValue < rightValue end
        return leftValue > rightValue
    end
    local leftTime, rightTime = tonumber(left.entry.timestamp) or 0, tonumber(right.entry.timestamp) or 0
    if leftTime ~= rightTime then return leftTime < rightTime end
    return (left.index or 0) < (right.index or 0)
end

local function VisibleItems(logs)
    local filtered = {}
    for index, entry in ipairs(logs or {}) do
        if EntryMatches(entry) then filtered[#filtered + 1] = { entry = entry, index = index } end
    end

    if not groupByLevel then
        table.sort(filtered, CompareWrappers)
        local items = {}
        for _, wrapper in ipairs(filtered) do items[#items + 1] = { type = "event", entry = wrapper.entry, sourceIndex = wrapper.index } end
        return items, #filtered
    end

    local buckets, levelKeys = {}, {}
    for _, wrapper in ipairs(filtered) do
        local level = wrapper.entry.level or "Historical"
        local key = tostring(level)
        if not buckets[key] then
            buckets[key] = { level = level, entries = {} }
            levelKeys[#levelKeys + 1] = key
        end
        buckets[key].entries[#buckets[key].entries + 1] = wrapper
    end
    table.sort(levelKeys, function(a, b)
        local av, bv = tonumber(buckets[a].level), tonumber(buckets[b].level)
        if av and bv then return av < bv end
        if av then return true end
        if bv then return false end
        return a < b
    end)

    local items = {}
    for _, key in ipairs(levelKeys) do
        local bucket = buckets[key]
        table.sort(bucket.entries, CompareWrappers)
        items[#items + 1] = { type = "level", level = bucket.level }
        for _, wrapper in ipairs(bucket.entries) do
            items[#items + 1] = { type = "event", entry = wrapper.entry, sourceIndex = wrapper.index }
        end
    end
    return items, #filtered
end

------------------------------------------------------------------------
-- Preferences and filter state
------------------------------------------------------------------------

local function PreferenceTable()
    if not EbonBuildsDB then return nil end
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.logbook = EbonBuildsDB.globalSettings.logbook or {}
    return EbonBuildsDB.globalSettings.logbook
end

local function SavePreferences()
    local prefs = PreferenceTable()
    if not prefs then return end
    prefs.actionFilter = actionFilter
    prefs.sourceFilter = sourceFilter
    prefs.groupByLevel = groupByLevel and true or false
    prefs.sortColumn = sortColumn
    prefs.sortAscending = sortAscending and true or false
end

local function LoadPreferences()
    local prefs = PreferenceTable() or {}
    local validActions = { All = true, Select = true, Banish = true, Reroll = true, Freeze = true, Manual = true }
    local validSources = { All = true, Automatic = true, Manual = true }
    local validSort = { time = true, action = true, subject = true }
    actionFilter = validActions[prefs.actionFilter] and prefs.actionFilter or "All"
    sourceFilter = validSources[prefs.sourceFilter] and prefs.sourceFilter or "All"
    groupByLevel = prefs.groupByLevel and true or false
    sortColumn = validSort[prefs.sortColumn] and prefs.sortColumn or "time"
    sortAscending = prefs.sortAscending == nil and true or (prefs.sortAscending and true or false)
end

local function ActiveFilterDefinitions()
    local defs = {}
    if searchText ~= "" then
        local display = searchText
        if #display > 16 then display = display:sub(1, 16) .. "…" end
        defs[#defs + 1] = {
            label = "Search: " .. display,
            clear = function()
                searchText = ""
                if searchInput and (searchInput:GetText() or "") ~= "" then searchInput:SetText("") end
            end,
        }
    end
    if actionFilter ~= "All" then
        defs[#defs + 1] = { label = actionFilter, clear = function() actionFilter = "All"; SavePreferences() end }
    end
    if sourceFilter ~= "All" then
        defs[#defs + 1] = { label = sourceFilter, clear = function() sourceFilter = "All"; SavePreferences() end }
    end
    if importantOnly then defs[#defs + 1] = { label = "Important", clear = function() importantOnly = false end } end
    return defs
end

local function ClearFilters()
    searchText = ""
    actionFilter = "All"
    sourceFilter = "All"
    importantOnly = false
    if searchInput and (searchInput:GetText() or "") ~= "" then searchInput:SetText("") end
    SavePreferences()
    if H.UpdateFilterVisuals then H.UpdateFilterVisuals() end
    H.RefreshLogView()
end

local function UpdateSearchPlaceholder()
    if not searchInput or not searchPlaceholder then return end
    if searchInput:HasFocus() or (searchInput:GetText() or "") ~= "" then searchPlaceholder:Hide() else searchPlaceholder:Show() end
end

local function UpdateFilterChips()
    if not chipFrame then return end
    for _, chip in ipairs(chipPool) do chip:Hide() end
    local defs = ActiveFilterDefinitions()
    local x = 0
    for i, def in ipairs(defs) do
        local item = def
        local chip = chipPool[i] or Theme.CreateFilterChip(chipFrame, item.label)
        chipPool[i] = chip
        local text = item.label
        if #text > 18 then text = text:sub(1, 18) .. "…" end
        chip:SetText(text .. "  x")
        chip:SetWidth(math.max(54, math.min(124, 28 + #text * 6)))
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", chipFrame, "LEFT", x, 0)
        chip:SetScript("OnClick", function()
            item.clear()
            H.UpdateFilterVisuals()
            H.RefreshLogView()
        end)
        chip:Show()
        x = x + chip:GetWidth() + 5
    end
    if chipEmpty then
        if #defs == 0 then chipEmpty:Show() else chipEmpty:Hide() end
    end
    if clearFiltersButton then
        if #defs > 0 then clearFiltersButton:Show() else clearFiltersButton:Hide() end
    end
end

function H.UpdateFilterVisuals()
    if actionDropdown then actionDropdown:SetText(actionFilter == "All" and "All actions" or actionFilter) end
    if sourceDropdown then sourceDropdown:SetText(sourceFilter == "All" and "All sources" or sourceFilter) end
    if importantButton then
        importantButton:SetText(importantOnly and "✓ Important only" or "Important only")
        Theme.SetTabSelected(importantButton, importantOnly)
    end
    if groupButton then
        groupButton:SetText(groupByLevel and "✓ Group by level" or "Group by level")
        Theme.SetTabSelected(groupButton, groupByLevel)
    end
    UpdateFilterChips()
end

------------------------------------------------------------------------
-- Run navigator and history management
------------------------------------------------------------------------

local function SelectedSessionIndex()
    for index, session in ipairs(relevantSessionCache) do
        if session.id == selectedSessionId then return index end
    end
    return nil
end

local function RunMenuLabel(session)
    if not session then return "Choose a run" end
    local status = session.endTime and "Complete" or "Active"
    return string.format("%s · Level %s · %s · %d events", status, tostring(session.maxLevel or session.startLevel or 1), FormatDuration(session.startTime, session.endTime), #(session.logs or {}))
end

local function RefreshRunNavigatorText()
    if not runDropdown then return end
    local session = SelectedSession()
    local index = SelectedSessionIndex()
    if session then
        runDropdown:SetText(RunMenuLabel(session))
        runPositionLabel:SetText(string.format("Run %d of %d · Started %s%s", index or 1, #relevantSessionCache, FormatRunDate(session.startTime), session.endTime and "" or " · recording now"))
    else
        runDropdown:SetText("Choose a run")
        runPositionLabel:SetText(#relevantSessionCache > 0 and (#relevantSessionCache .. " runs available") or "No runs recorded for this build")
    end
    if previousRunButton then
        if index and index > 1 then previousRunButton:Enable() else previousRunButton:Disable() end
    end
    if nextRunButton then
        if index and index < #relevantSessionCache then nextRunButton:Enable() else nextRunButton:Disable() end
    end
    if historyDropdown then historyDropdown:RefreshMenu() end
end

local function CloseDetail()
    selectedEntry = nil
    if detailPanel then detailPanel:Hide() end
end

local function SelectSession(id)
    if id == selectedSessionId then return end
    selectedSessionId = id
    selectedEntry = nil
    if detailPanel then detailPanel:Hide() end
    if logBar then logBar:SetValue(0) end
    RefreshRunNavigatorText()
    H.RefreshLogView()
end

local function MoveSession(delta)
    local index = SelectedSessionIndex()
    if not index then return end
    local nextIndex = math.max(1, math.min(#relevantSessionCache, index + delta))
    if relevantSessionCache[nextIndex] then SelectSession(relevantSessionCache[nextIndex].id) end
end

function H.RefreshSessionList()
    relevantSessionCache = RelevantSessions()
    local active = EbonBuilds.Session and EbonBuilds.Session.GetActiveSession and EbonBuilds.Session.GetActiveSession()
    if active and not SessionMatchesActiveBuild(active) then active = nil end
    if selectedSessionId and not SessionMatchesActiveBuild(FindSession(selectedSessionId)) then selectedSessionId = nil end
    if selectedSessionId and not FindSession(selectedSessionId) then selectedSessionId = nil end
    if not selectedSessionId and active then selectedSessionId = active.id end
    if not selectedSessionId and relevantSessionCache[1] then selectedSessionId = relevantSessionCache[1].id end
    RefreshRunNavigatorText()
end

local function UpdateSummary(session)
    local data = SessionSummary(session)
    local values = {
        level = tostring(session and (session.maxLevel or session.startLevel or 1) or "—"),
        duration = session and FormatDuration(session.startTime, session.endTime) or "—",
        events = tostring(data.events or 0),
        score = data.selectedCount > 0 and string.format("%.1f", data.averageSelected or 0) or "—",
        actions = string.format("B %d  R %d  F %d", data.actions.Banish or 0, data.actions.Reroll or 0, data.actions.Freeze or 0),
    }
    for key, value in pairs(values) do if summaryMetrics[key] then summaryMetrics[key].value:SetText(value) end end
end

local function SessionEventCount(session)
    return session and #(session.logs or {}) or 0
end

local function ShowDeleteSelectedConfirmation()
    local session = SelectedSession()
    if not session or not session.endTime then return end
    pendingDeleteSessionId = session.id
    local dialog = StaticPopupDialogs["EBONBUILDS_DELETE_SELECTED_SESSION"]
    if dialog then
        dialog.text = string.format("Delete this completed run?\n\nLevel %s · %s · %d events\n\nThis cannot be undone.", tostring(session.maxLevel or session.startLevel or 1), FormatDuration(session.startTime, session.endTime), SessionEventCount(session))
    end
    StaticPopup_Show("EBONBUILDS_DELETE_SELECTED_SESSION")
end

local function CompletedRelevantSessions()
    local sessions = {}
    for _, session in ipairs(RelevantSessions()) do
        if session.endTime then sessions[#sessions + 1] = session end
    end
    return sessions
end

local function ShowClearBuildHistoryConfirmation()
    local sessions = CompletedRelevantSessions()
    if #sessions == 0 then return end
    local ids, events = {}, 0
    for _, session in ipairs(sessions) do
        ids[#ids + 1] = session.id
        events = events + SessionEventCount(session)
    end
    pendingClearSessionIds = ids
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    local dialog = StaticPopupDialogs["EBONBUILDS_CLEAR_BUILD_HISTORY"]
    if dialog then
        dialog.text = string.format("Delete %d completed run%s and %d event%s for %s?\n\nThe active recording session will be preserved. This cannot be undone.", #sessions, #sessions == 1 and "" or "s", events, events == 1 and "" or "s", build and build.title or "this build")
    end
    StaticPopup_Show("EBONBUILDS_CLEAR_BUILD_HISTORY")
end

------------------------------------------------------------------------
-- Sorting, rows, and inspector layout
------------------------------------------------------------------------

local function LayoutColumns(width)
    width = math.max(width or 0, 430)
    local gap, timeW, actionW, subjectW, chargesW = 6, 55, 72, 172, 76
    local reasonW = math.max(90, width - timeW - actionW - subjectW - chargesW - gap * 5 - 18)
    local x = 10
    local geometry = {}
    geometry.time = { x = x, w = timeW }; x = x + timeW + gap
    geometry.action = { x = x, w = actionW }; x = x + actionW + gap
    geometry.subject = { x = x, w = subjectW }; x = x + subjectW + gap
    geometry.reason = { x = x, w = reasonW }; x = x + reasonW + gap
    geometry.charges = { x = x, w = chargesW }
    return geometry
end

local function HeaderText(key)
    local labels = { time = "Time", action = "Action", subject = "Subject", reason = "Reason", charges = "Charges" }
    local text = labels[key] or key
    if key == sortColumn then text = text .. (sortAscending and "  ^" or "  v") end
    return text
end

local function UpdateHeaderVisuals()
    for key, button in pairs(headerButtons) do
        local active = key == sortColumn
        if button._label then
            button._label:SetText(HeaderText(key))
            if active then button._label:SetTextColor(unpack(Theme.ACCENT_GOLD)) else button._label:SetTextColor(0.86, 0.86, 0.90, 1) end
        end
        if button.SetBackdropBorderColor then
            if active then button:SetBackdropBorderColor(Theme.ACCENT_GOLD[1], Theme.ACCENT_GOLD[2], Theme.ACCENT_GOLD[3], 0.55) else button:SetBackdropBorderColor(0, 0, 0, 0) end
        end
    end
end

local function LayoutHeader(width)
    if not headerBar then return end
    local geometry = LayoutColumns(width)
    for key, pos in pairs(geometry) do
        local button = headerButtons[key]
        if button then
            button:ClearAllPoints()
            button:SetPoint("LEFT", headerBar, "LEFT", pos.x - 4, 0)
            button:SetSize(pos.w + 8, 20)
        end
    end
    UpdateHeaderVisuals()
end

local function SetSort(column)
    if column ~= "time" and column ~= "action" and column ~= "subject" then return end
    if sortColumn == column then
        sortAscending = not sortAscending
    else
        sortColumn = column
        sortAscending = true
    end
    SavePreferences()
    if logBar then logBar:SetValue(0) end
    H.RefreshLogView()
end

local function SetRowVisual(row)
    if not row then return end
    if row._selected then
        row:SetBackdropColor(0.17, 0.15, 0.07, 0.99)
        row:SetBackdropBorderColor(unpack(Theme.ACCENT_GOLD))
    elseif row._hovered then
        Theme.SetCardHovered(row, true)
    else
        Theme.SetCardHovered(row, false)
    end
end

local function NextWheelScrollValue(currentValue, delta, minimum, maximum, step)
    currentValue = tonumber(currentValue) or 0
    delta = tonumber(delta) or 0
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or minimum
    step = math.max(1, tonumber(step) or EVENT_ROW_H)

    if maximum < minimum then maximum = minimum end
    return math.max(minimum, math.min(maximum, currentValue - delta * step))
end

local function ScrollLogByWheel(delta)
    if not logBar or not logScroll then return end
    Theme.ScrollByMouseWheel(logScroll, logBar, delta, EVENT_ROW_H)
end

-- Mouse-wheel events do not reliably bubble through mouse-enabled Button
-- rows on the 3.3.5a client. Route the wheel from both the ScrollFrame and
-- every recycled row so reaching the last row cannot trap upward scrolling.
local function EnableLogMouseWheel(frame)
    if not frame then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        ScrollLogByWheel(delta)
    end)
end

local function BuildTimelineRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    Theme.ApplyCard(row)
    if logScroll and logBar then
        Theme.BindScrollWheel(logScroll, logBar, EVENT_ROW_H, row)
    else
        EnableLogMouseWheel(row)
    end

    local marker = row:CreateTexture(nil, "ARTWORK")
    marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    marker:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    marker:SetWidth(3)
    row._marker = marker

    local notable = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notable:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -3)
    notable:SetText("!")
    notable:SetTextColor(unpack(Theme.WARNING))
    notable:Hide()
    row._notable = notable

    row._labels = {}
    for _, key in ipairs({ "time", "action", "subject", "reason", "charges" }) do
        local fs = row:CreateFontString(nil, "OVERLAY", key == "subject" and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetJustifyH(key == "charges" and "RIGHT" or "LEFT")
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        row._labels[key] = fs
    end

    local levelLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("LEFT", row, "LEFT", 10, 0)
    levelLabel:SetTextColor(unpack(Theme.ACCENT_GOLD))
    row._levelLabel = levelLabel

    row:SetScript("OnClick", function(self) if self._entry then H.ShowDecisionDetail(self._entry) end end)
    row:SetScript("OnEnter", function(self) self._hovered = true; SetRowVisual(self) end)
    row:SetScript("OnLeave", function(self) self._hovered = false; SetRowVisual(self) end)
    return row
end

local function BindRow(row, item, width, y)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", logChild, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", logChild, "RIGHT", -4, 0)
    row._hovered = false
    if item.type == "level" then
        row:SetHeight(LEVEL_ROW_H)
        row._entry = nil
        row._selected = false
        row._levelLabel:SetText(item.level == "Historical" and "HISTORICAL EVENTS" or ("LEVEL " .. tostring(item.level)))
        row._levelLabel:Show()
        row._marker:SetVertexColor(unpack(Theme.ACCENT_GOLD))
        row._notable:Hide()
        for _, label in pairs(row._labels) do label:Hide() end
        SetRowVisual(row)
        row:Show()
        return LEVEL_ROW_H
    end

    local entry = item.entry
    row:SetHeight(EVENT_ROW_H)
    row._entry = entry
    row._selected = entry == selectedEntry
    row._levelLabel:Hide()
    for _, label in pairs(row._labels) do label:Show() end
    local geometry = LayoutColumns(width)
    for key, pos in pairs(geometry) do
        local label = row._labels[key]
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", pos.x, 0)
        label:SetWidth(pos.w)
    end

    local action = NormalizeAction(entry.action)
    local color = ACTION_COLORS[action] or ACTION_COLORS.Other
    row._marker:SetVertexColor(color[1], color[2], color[3], 0.95)
    row._labels.time:SetText("|cff9b9ba5" .. FormatTimestamp(entry.timestamp) .. "|r")
    row._labels.action:SetText(action)
    row._labels.action:SetTextColor(color[1], color[2], color[3], 1)
    local name, score, quality = DecisionLabel(entry)
    row._labels.subject:SetText(EbonBuilds.Quality.Colorize(name, quality) .. string.format("  |cffb6b6bd%.0f|r", score or 0))
    row._labels.reason:SetText(ReasonSentence(entry))
    row._labels.reason:SetTextColor(unpack(Theme.TEXT_MUTED))
    local charges = entry.charges or {}
    row._labels.charges:SetText(string.format("B:%d R:%d F:%d", charges.ban or 0, charges.reroll or 0, charges.freeze or 0))
    row._labels.charges:SetTextColor(unpack(Theme.TEXT_MUTED))
    if IsImportant(entry) then row._notable:Show() else row._notable:Hide() end
    SetRowVisual(row)
    row:Show()
    return EVENT_ROW_H
end

local function TimelineItemHeight(item)
    return item and item.type == "level" and LEVEL_ROW_H or EVENT_ROW_H
end

local function PositionLogAndInspector()
    if not headerBar or not logScroll or not bottomPanel then return end
    logScroll:ClearAllPoints()
    logScroll:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
    if selectedEntry and detailPanel then
        logScroll:SetPoint("BOTTOMRIGHT", detailPanel, "TOPRIGHT", -2, 5)
    else
        logScroll:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", -2, 2)
    end
    if logChild then logChild:SetWidth(math.max(430, logScroll:GetWidth() or 0)) end
    LayoutHeader(logScroll:GetWidth() or 0)
end

local function RenderVisibleRows()
    if not logScroll or not logChild then return end
    for _, row in ipairs(rowPool) do row:Hide() end
    if #timelineItems == 0 then return end

    local scrollValue = logBar and (logBar:GetValue() or 0) or 0
    local viewport = math.max(1, logScroll:GetHeight() or 1)
    local buffer = EVENT_ROW_H * 2
    local first, last = 1, #timelineItems
    for i = 1, #timelineItems do
        local top = timelineOffsets[i] or 0
        local bottom = top + TimelineItemHeight(timelineItems[i]) + 2
        if bottom >= scrollValue - buffer then first = i; break end
    end
    for i = first, #timelineItems do
        local top = timelineOffsets[i] or 0
        if top > scrollValue + viewport + buffer then last = i - 1; break end
    end

    local width = math.max(430, logScroll:GetWidth() or 0)
    local poolIndex = 0
    for i = first, last do
        poolIndex = poolIndex + 1
        local row = rowPool[poolIndex] or BuildTimelineRow(logChild)
        rowPool[poolIndex] = row
        BindRow(row, timelineItems[i], width, timelineOffsets[i] or 0)
    end
    for i = poolIndex + 1, #rowPool do rowPool[i]:Hide() end
end

local function PreviousEntryCharges(entry)
    local session = SelectedSession()
    if not session then return nil end
    for index, candidate in ipairs(session.logs or {}) do
        if candidate == entry then
            local previous = session.logs[index - 1]
            return previous and previous.charges or nil
        end
    end
    return nil
end

local function ResizeDetailChoiceCards()
    if not detailPanel then return end
    local available = math.max(480, (detailPanel:GetWidth() or 700) - 24)
    local width = math.floor((available - DETAIL_WIDTH_GAP * 2) / 3)
    for index, card in ipairs(detailChoiceRows) do
        card:SetWidth(width)
        card:ClearAllPoints()
        if index == 1 then
            card:SetPoint("BOTTOMLEFT", detailPanel, "BOTTOMLEFT", 12, 10)
        else
            card:SetPoint("LEFT", detailChoiceRows[index - 1], "RIGHT", DETAIL_WIDTH_GAP, 0)
        end
    end
end

local function ChoiceIcon(choice)
    if not choice or not choice.spellId then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, icon = GetSpellInfo(choice.spellId)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function BuildDecisionExport(entry)
    if not entry then return "No decision selected." end
    local lines = {}
    local name, score = DecisionLabel(entry)
    lines[#lines + 1] = string.format("%s · %s · %s", FormatTimestamp(entry.timestamp), NormalizeAction(entry.action), name)
    lines[#lines + 1] = string.format("Level: %s", tostring(entry.level or "Unknown"))
    lines[#lines + 1] = string.format("Final value: %.0f", score or 0)
    lines[#lines + 1] = "Reason: " .. ReasonSentence(entry)
    lines[#lines + 1] = "Source: " .. DecisionSource(entry)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Offer:"
    for index, choice in ipairs(entry.choices or {}) do
        local target = TargetChoice(entry)
        lines[#lines + 1] = string.format("%d. %s%s · quality %s · weight %s · modifiers %s · final %s", index, choice.name or "Unknown Echo", choice == target and " [TARGET]" or "", tostring(choice.quality or "?"), tostring(choice.baseWeight or "?"), choice.modifierDelta ~= nil and string.format("%+.0f", choice.modifierDelta) or "?", tostring(choice.score or "?"))
    end
    local charges = entry.charges or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Resources after: Banish %d · Reroll %d · Freeze %d", charges.ban or 0, charges.reroll or 0, charges.freeze or 0)
    return table.concat(lines, "\n")
end

function H.ShowDecisionDetail(entry)
    if not detailPanel or not entry then return end
    selectedEntry = entry
    local decision = entry.decision or {}
    local action = NormalizeAction(entry.action)
    local name = DecisionLabel(entry)
    detailTitle:SetText(string.format("%s · %s", string.upper(action), tostring(name or "Decision")))
    detailReason:SetText(REASON_TEXT[decision.reasonCode] or ReasonSentence(entry))

    local meta = { "Level " .. tostring(entry.level or "?"), FormatTimestamp(entry.timestamp), DecisionSource(entry) }
    if decision.threshold ~= nil then meta[#meta + 1] = string.format("Threshold %.0f", decision.threshold) end
    if decision.model then meta[#meta + 1] = tostring(decision.model) end
    detailMeta:SetText(table.concat(meta, " · "))

    local flags = decision.flags or {}
    local flagText = {}
    if flags.closeDecision then flagText[#flagText + 1] = "Close scores" end
    if flags.lastCharge then flagText[#flagText + 1] = "Last charge" end
    if flags.modifierOverride then flagText[#flagText + 1] = "Modifiers changed winner" end
    if flags.manualDisagreement then flagText[#flagText + 1] = "Manual disagreement" end
    if flags.fallback then flagText[#flagText + 1] = "Fallback used" end
    if IsImportant(entry) and #flagText == 0 then flagText[#flagText + 1] = "Marked important" end
    detailFlags:SetText(#flagText > 0 and table.concat(flagText, " · ") or "Routine decision")

    local after = entry.charges or {}
    local before = PreviousEntryCharges(entry)
    if before then
        detailResources:SetText(string.format("Resources  B %d→%d   R %d→%d   F %d→%d", before.ban or 0, after.ban or 0, before.reroll or 0, after.reroll or 0, before.freeze or 0, after.freeze or 0))
    else
        detailResources:SetText(string.format("Resources after  B %d   R %d   F %d", after.ban or 0, after.reroll or 0, after.freeze or 0))
    end

    local target = TargetChoice(entry)
    for i = 1, 3 do
        local card = detailChoiceRows[i]
        local choice = entry.choices and entry.choices[i]
        if choice then
            card._icon:SetTexture(ChoiceIcon(choice))
            local targetLabel = choice == target and "  |cffffd100TARGET|r" or ""
            card._name:SetText((choice.name or "Unknown Echo") .. targetLabel)
            card._name:SetTextColor(EbonBuilds.Quality.GetRGB(choice.quality))
            if choice.baseWeight ~= nil then
                card._breakdown:SetText(string.format("Weight %.0f · Mod %+.0f · Final %.0f", choice.baseWeight or 0, choice.modifierDelta or 0, choice.score or 0))
            else
                card._breakdown:SetText(string.format("Final %.0f · legacy details unavailable", choice.score or 0))
            end
            card:Show()
        else
            card:Hide()
        end
    end
    detailPanel:Show()
    ResizeDetailChoiceCards()
    PositionLogAndInspector()
    H.RefreshLogView()
end

------------------------------------------------------------------------
-- Main refresh pipeline
------------------------------------------------------------------------

function H.RefreshLogView()
    if not logScroll or not logChild then return end
    for _, row in ipairs(rowPool) do row:Hide() end
    local session = SelectedSession()
    UpdateSummary(session)
    PositionLogAndInspector()
    UpdateHeaderVisuals()

    if not session then
        timelineItems, timelineOffsets, timelineTotalHeight = {}, {}, 1
        logChild:SetHeight(1)
        logBar:SetMinMaxValues(0, 0)
        resultLabel:SetText("No run selected")
        emptyState._title:SetText("Choose a run")
        emptyState._body:SetText("Select a run above to inspect its recorded decisions.")
        emptyClearButton:Hide()
        emptyState:Show()
        return
    end

    if selectedEntry then
        local belongsToSession = false
        for _, entry in ipairs(session.logs or {}) do
            if entry == selectedEntry then belongsToSession = true; break end
        end
        if not belongsToSession or not EntryMatches(selectedEntry) then
            CloseDetail()
            PositionLogAndInspector()
        end
    end

    local items, eventCount = VisibleItems(session.logs or {})
    timelineItems, timelineOffsets = items, {}
    local total = #(session.logs or {})
    local filterCount = #ActiveFilterDefinitions()
    if eventCount == total and filterCount == 0 then
        resultLabel:SetText(eventCount .. " events")
    else
        resultLabel:SetText(string.format("%d of %d · %d filter%s", eventCount, total, filterCount, filterCount == 1 and "" or "s"))
    end

    local width = math.max(430, logScroll:GetWidth() or 0)
    logChild:SetWidth(width)
    LayoutHeader(width)

    local y = 0
    for index, item in ipairs(timelineItems) do
        timelineOffsets[index] = y
        y = y + TimelineItemHeight(item) + 2
    end
    timelineTotalHeight = math.max(1, y)
    logChild:SetHeight(timelineTotalHeight)
    local maxScroll = math.max(0, timelineTotalHeight - (logScroll:GetHeight() or 0))
    logBar:SetMinMaxValues(0, maxScroll)
    if logBar:GetValue() > maxScroll then logBar:SetValue(maxScroll) end
    RenderVisibleRows()

    if #items == 0 then
        emptyState._title:SetText(total == 0 and "No decisions recorded" or "No matching decisions")
        if total == 0 then
            emptyState._body:SetText("This run has no recorded decisions yet.")
            emptyClearButton:Hide()
        elseif filterCount > 0 then
            emptyState._body:SetText(string.format("0 of %d events match %d active filter%s.", total, filterCount, filterCount == 1 and "" or "s"))
            emptyClearButton:Show()
        else
            emptyState._body:SetText("No events are available in the current view.")
            emptyClearButton:Hide()
        end
        emptyState:Show()
    else
        emptyState:Hide()
    end
end

------------------------------------------------------------------------
-- Export helpers
------------------------------------------------------------------------

local exportDialog

local function EnsureExportDialog()
    if exportDialog then return exportDialog end
    local frame = CreateFrame("Frame", "EbonBuildsExportDialog", UIParent)
    frame:SetSize(800, 550)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Theme.ApplyWindow(frame)
    frame:Hide()
    frame:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then self:StartMoving() end end)
    frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("Logbook Export")
    local close = Theme.CreateButton(frame)
    close:SetSize(24, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    close:SetText("x")
    close:SetScript("OnClick", function() frame:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)
    scroll:SetScrollChild(edit)
    local bar = Theme.CreateScrollBar(frame)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 18, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 18, 2)
    bar:SetValueStep(18)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local minimum, maximum = bar:GetMinMaxValues()
        bar:SetValue(math.max(minimum, math.min(maximum, bar:GetValue() - delta * 18)))
    end)
    frame._title, frame._edit, frame._scroll, frame._bar = title, edit, scroll, bar
    exportDialog = frame
    return frame
end

local function ShowExportText(title, text)
    local dialog = EnsureExportDialog()
    local lineCount = 1
    for _ in tostring(text or ""):gmatch("\n") do lineCount = lineCount + 1 end
    dialog._title:SetText(title or "Logbook Export")
    dialog._edit:SetText(text or "")
    dialog._edit:SetWidth(math.max(600, dialog._scroll:GetWidth() - 8))
    local height = math.max(dialog._scroll:GetHeight(), lineCount * 14 + 20)
    dialog._edit:SetHeight(height)
    dialog._bar:SetMinMaxValues(0, math.max(0, height - dialog._scroll:GetHeight()))
    dialog._bar:SetValue(0)
    dialog:Show()
    dialog._edit:SetFocus()
    dialog._edit:HighlightText()
end

local function SessionExportLines(session)
    local lines = {}
    if not session then return { "No session selected." } end
    lines[#lines + 1] = string.format("Run: Level %d | Duration: %s | Soul Ashes: %s | Events: %d", session.maxLevel or session.startLevel or 1, FormatDuration(session.startTime, session.endTime), session.soulAshes or 0, #(session.logs or {}))
    lines[#lines + 1] = string.format("Started: %s | Status: %s", FormatRunDate(session.startTime), session.endTime and "Complete" or "Active")
    lines[#lines + 1] = ""
    for _, entry in ipairs(session.logs or {}) do
        local name, score = DecisionLabel(entry)
        lines[#lines + 1] = string.format("%s  %-8s  %-30s (%4.0f)  %s", FormatTimestamp(entry.timestamp), NormalizeAction(entry.action), name, score, ReasonSentence(entry))
    end
    return lines
end

function H.ExportSession()
    local session = SelectedSession()
    ShowExportText("Selected Run Export", table.concat(SessionExportLines(session), "\n"))
end

function H.ExportBuildHistory()
    local lines = {}
    local sessions = RelevantSessions()
    if #sessions == 0 then
        lines[1] = "No runs are recorded for this build."
    else
        for index, session in ipairs(sessions) do
            if index > 1 then lines[#lines + 1] = "\n" .. string.rep("-", 72) .. "\n" end
            local sessionLines = SessionExportLines(session)
            for _, line in ipairs(sessionLines) do lines[#lines + 1] = line end
        end
    end
    ShowExportText("Build History Export", table.concat(lines, "\n"))
end

function H.ExportDecision()
    ShowExportText("Decision Details", BuildDecisionExport(selectedEntry))
end

------------------------------------------------------------------------
-- UI construction
------------------------------------------------------------------------

local function CreateSearch(parent)
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(190, 24)
    Theme.ApplyInput(wrap)
    local edit = CreateFrame("EditBox", nil, wrap)
    edit:SetPoint("TOPLEFT", wrap, "TOPLEFT", 7, -3)
    edit:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -22, 3)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetAutoFocus(false)
    edit:SetTextColor(1, 1, 1, 1)
    Theme.WireEditBox(edit, wrap)
    local placeholder = wrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
    placeholder:SetText("Search Echoes, actions, reasons…")
    placeholder:SetTextColor(unpack(Theme.TEXT_MUTED))
    local clear = CreateFrame("Button", nil, wrap)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", wrap, "RIGHT", -2, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(unpack(Theme.TEXT_MUTED))
    clear:SetScript("OnClick", function() edit:SetText(""); edit:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        searchText = string.lower(self:GetText() or "")
        UpdateSearchPlaceholder()
        H.UpdateFilterVisuals()
        H.RefreshLogView()
    end)
    edit:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
    edit:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self) if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end end)
    Theme.AttachTooltip(wrap, "Search the Logbook", "Matches Echo names, spell IDs, actions, sources, levels, timestamps, and recorded decision reasons.")
    searchInput, searchPlaceholder = edit, placeholder
    UpdateSearchPlaceholder()
    return wrap
end

local function BuildHeaderButton(parent, key)
    local button = CreateFrame("Button", nil, parent)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", button, "LEFT", 4, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    label:SetJustifyH(key == "charges" and "RIGHT" or "LEFT")
    button._label = label
    if key == "time" or key == "action" or key == "subject" then
        button:SetScript("OnClick", function() SetSort(key) end)
        button:SetScript("OnEnter", function(self) if key ~= sortColumn then self._label:SetTextColor(unpack(Theme.TEXT_PRIMARY)) end end)
        button:SetScript("OnLeave", function(self) UpdateHeaderVisuals() end)
        Theme.AttachTooltip(button, "Sort by " .. key, "Click the active column again to reverse the sort direction.")
    else
        button:EnableMouse(false)
    end
    headerButtons[key] = button
    headerLabels[key] = label
    return button
end

local function BuildDetailChoiceCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(49)
    Theme.ApplyCard(card)
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", card, "LEFT", 7, 0)
    card._icon = icon
    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 7, 0)
    name:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    name:SetJustifyH("LEFT")
    card._name = name
    local breakdown = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    breakdown:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    breakdown:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    breakdown:SetJustifyH("LEFT")
    breakdown:SetTextColor(unpack(Theme.TEXT_MUTED))
    card._breakdown = breakdown
    return card
end

local function BuildRunNavigator(container)
    topPanel = CreateFrame("Frame", nil, container)
    topPanel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -2)
    topPanel:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    topPanel:SetHeight(TOP_H)

    local hint = topPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", topPanel, "TOPLEFT", 4, -2)
    hint:SetText("Select a run, narrow the evidence, then inspect any recorded decision.")
    hint:SetTextColor(unpack(Theme.TEXT_MUTED))

    historyDropdown = Theme.CreateDropdown(topPanel, 145, "Logbook options", { menuWidth = 214 })
    historyDropdown:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", 0, 0)
    historyDropdown:SetMenuBuilder(function()
        local selected = SelectedSession()
        local completed = CompletedRelevantSessions()
        return {
            { text = "Export selected run", disabled = not selected, func = H.ExportSession },
            { text = "Export current build history", disabled = #relevantSessionCache == 0, func = H.ExportBuildHistory },
            { text = "Delete selected completed run", disabled = not selected or not selected.endTime, color = Theme.DANGER, func = ShowDeleteSelectedConfirmation, tooltipBody = "The active recording session cannot be deleted." },
            { text = "Clear completed build history", disabled = #completed == 0, color = Theme.DANGER, func = ShowClearBuildHistoryConfirmation, tooltipBody = "Deletes completed runs for this build while preserving the active session." },
        }
    end)

    previousRunButton = Theme.CreateButton(topPanel)
    previousRunButton:SetSize(26, 38)
    previousRunButton:SetPoint("TOPLEFT", topPanel, "TOPLEFT", 0, -25)
    previousRunButton:SetText("<")
    previousRunButton:SetScript("OnClick", function() MoveSession(-1) end)
    Theme.AttachTooltip(previousRunButton, "Newer run", "Move to the previous run in the current build history.")

    nextRunButton = Theme.CreateButton(topPanel)
    nextRunButton:SetSize(26, 38)
    nextRunButton:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", 0, -25)
    nextRunButton:SetText(">")
    nextRunButton:SetScript("OnClick", function() MoveSession(1) end)
    Theme.AttachTooltip(nextRunButton, "Older run", "Move to the next run in the current build history.")

    runDropdown = Theme.CreateDropdown(topPanel, 500, "Choose a run", { menuWidth = 560 })
    runDropdown:SetPoint("TOPLEFT", previousRunButton, "TOPRIGHT", 6, 0)
    runDropdown:SetPoint("TOPRIGHT", nextRunButton, "TOPLEFT", -6, 0)
    runDropdown:SetHeight(38)
    runDropdown:SetMenuBuilder(function()
        local items = {}
        for index, session in ipairs(relevantSessionCache) do
            local current = session
            items[#items + 1] = {
                text = string.format("%d. %s", index, RunMenuLabel(current)),
                checked = current.id == selectedSessionId,
                func = function() SelectSession(current.id) end,
                tooltipTitle = current.endTime and "Completed run" or "Active run",
                tooltipBody = string.format("Started %s. %d recorded events.", FormatRunDate(current.startTime), #(current.logs or {})),
            }
        end
        return items
    end)

    runPositionLabel = topPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    runPositionLabel:SetPoint("TOPLEFT", runDropdown, "BOTTOMLEFT", 3, -5)
    runPositionLabel:SetPoint("RIGHT", runDropdown, "RIGHT", -3, 0)
    runPositionLabel:SetJustifyH("LEFT")
    runPositionLabel:SetTextColor(unpack(Theme.TEXT_MUTED))
end

local function BuildSummaryStrip(container)
    summaryStrip = CreateFrame("Frame", nil, container)
    summaryStrip:SetPoint("TOPLEFT", topPanel, "BOTTOMLEFT", 0, -5)
    summaryStrip:SetPoint("TOPRIGHT", topPanel, "BOTTOMRIGHT", 0, -5)
    summaryStrip:SetHeight(SUMMARY_H)
    Theme.ApplyPanel(summaryStrip)

    local metricDefs = {
        { "level", "Level" },
        { "duration", "Duration" },
        { "events", "Events" },
        { "score", "Avg selected" },
        { "actions", "Resources" },
    }
    for i, def in ipairs(metricDefs) do
        local card = Theme.CreateMetricCard(summaryStrip, def[2])
        card:SetSize(i == 5 and 152 or 112, 42)
        card:SetPoint("LEFT", summaryStrip, "LEFT", 7 + (i - 1) * 126, 0)
        summaryMetrics[def[1]] = card
    end
end

local function BuildFilterToolbar(container)
    bottomPanel = CreateFrame("Frame", nil, container)
    bottomPanel:SetPoint("TOPLEFT", summaryStrip, "BOTTOMLEFT", 0, -5)
    bottomPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 2)

    toolbar = CreateFrame("Frame", nil, bottomPanel)
    toolbar:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(28)

    local search = CreateSearch(toolbar)
    search:SetPoint("LEFT", toolbar, "LEFT", 0, 0)

    actionDropdown = Theme.CreateDropdown(toolbar, 96, "All actions")
    actionDropdown:SetPoint("LEFT", search, "RIGHT", 7, 0)
    actionDropdown:SetMenuBuilder(function()
        local items = {}
        for _, action in ipairs({ "All", "Select", "Banish", "Reroll", "Freeze", "Manual" }) do
            local value = action
            items[#items + 1] = {
                text = value == "All" and "All actions" or value,
                checked = actionFilter == value,
                func = function()
                    actionFilter = value
                    SavePreferences()
                    H.UpdateFilterVisuals()
                    H.RefreshLogView()
                end,
            }
        end
        return items
    end)

    sourceDropdown = Theme.CreateDropdown(toolbar, 96, "All sources")
    sourceDropdown:SetPoint("LEFT", actionDropdown, "RIGHT", 7, 0)
    sourceDropdown:SetMenuBuilder(function()
        local items = {}
        for _, source in ipairs({ "All", "Automatic", "Manual" }) do
            local value = source
            items[#items + 1] = {
                text = value == "All" and "All sources" or value,
                checked = sourceFilter == value,
                func = function()
                    sourceFilter = value
                    SavePreferences()
                    H.UpdateFilterVisuals()
                    H.RefreshLogView()
                end,
            }
        end
        return items
    end)

    importantButton = Theme.CreateTab(toolbar, "Important only")
    importantButton:SetSize(108, 22)
    importantButton:SetPoint("LEFT", sourceDropdown, "RIGHT", 7, 0)
    importantButton:SetScript("OnClick", function()
        importantOnly = not importantOnly
        H.UpdateFilterVisuals()
        H.RefreshLogView()
    end)
    Theme.AttachTooltip(importantButton, "Important decisions", "Shows close comparisons, final-charge actions, modifier overrides, failures, and meaningful manual disagreements.")

    groupButton = Theme.CreateTab(toolbar, "Group by level")
    groupButton:SetSize(112, 22)
    groupButton:SetPoint("LEFT", importantButton, "RIGHT", 7, 0)
    groupButton:SetScript("OnClick", function()
        groupByLevel = not groupByLevel
        SavePreferences()
        H.UpdateFilterVisuals()
        H.RefreshLogView()
    end)
    Theme.AttachTooltip(groupButton, "Group by level", "Adds level separators without changing which events match the filters.")

    chipFrame = CreateFrame("Frame", nil, bottomPanel)
    chipFrame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -3)
    chipFrame:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -3)
    chipFrame:SetHeight(22)

    chipEmpty = chipFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    chipEmpty:SetPoint("LEFT", chipFrame, "LEFT", 2, 0)
    chipEmpty:SetText("No active filters")
    chipEmpty:SetTextColor(0.48, 0.50, 0.55, 1)

    resultLabel = chipFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultLabel:SetPoint("RIGHT", chipFrame, "RIGHT", -4, 0)
    resultLabel:SetWidth(126)
    resultLabel:SetJustifyH("RIGHT")
    resultLabel:SetTextColor(unpack(Theme.TEXT_MUTED))
    resultLabel:SetText("0 events")

    clearFiltersButton = Theme.CreateButton(chipFrame)
    clearFiltersButton:SetSize(78, 20)
    clearFiltersButton:SetPoint("RIGHT", resultLabel, "LEFT", -7, 0)
    clearFiltersButton:SetText("Clear filters")
    clearFiltersButton:SetScript("OnClick", ClearFilters)
    clearFiltersButton:Hide()
end

local function BuildEventTimeline()
    headerBar = CreateFrame("Frame", nil, bottomPanel)
    headerBar:SetPoint("TOPLEFT", chipFrame, "BOTTOMLEFT", 0, -4)
    headerBar:SetPoint("TOPRIGHT", chipFrame, "BOTTOMRIGHT", 0, -4)
    headerBar:SetHeight(24)
    Theme.ApplyCard(headerBar)
    for _, key in ipairs({ "time", "action", "subject", "reason", "charges" }) do
        BuildHeaderButton(headerBar, key)
    end

    logScroll = CreateFrame("ScrollFrame", nil, bottomPanel)
    logChild = CreateFrame("Frame", nil, logScroll)
    logChild:SetSize(430, 1)
    logScroll:SetScrollChild(logChild)

    logBar = Theme.CreateScrollBar(bottomPanel)
    logBar:SetPoint("TOPRIGHT", logScroll, "TOPRIGHT", 15, -2)
    logBar:SetPoint("BOTTOMRIGHT", logScroll, "BOTTOMRIGHT", 15, 2)
    logBar:SetValueStep(EVENT_ROW_H)
    logBar:SetScript("OnValueChanged", function(_, value)
        logScroll:SetVerticalScroll(value)
        RenderVisibleRows()
    end)
    Theme.BindScrollWheel(logScroll, logBar, EVENT_ROW_H, logChild)
    logScroll:SetScript("OnSizeChanged", function(self)
        logChild:SetWidth(math.max(430, self:GetWidth()))
        LayoutHeader(self:GetWidth())
        H.RefreshLogView()
    end)

    emptyState = Theme.CreateEmptyState(logScroll, "Choose a run", "Select a run above to inspect its decisions.")
    emptyState:SetHeight(126)
    emptyClearButton = Theme.CreateButton(emptyState, "gold")
    emptyClearButton:SetSize(112, 22)
    emptyClearButton:SetPoint("TOP", emptyState._body, "BOTTOM", 0, -10)
    emptyClearButton:SetText("Clear all filters")
    emptyClearButton:SetScript("OnClick", ClearFilters)
    emptyClearButton:Hide()
end

local function BuildDecisionInspector()
    detailPanel = Theme.CreateSection(bottomPanel, "Decision inspector", "Complete offer, score breakdown, resources, and recorded context.")
    detailPanel:SetPoint("BOTTOMLEFT", bottomPanel, "BOTTOMLEFT", 0, 2)
    detailPanel:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", 0, 2)
    detailPanel:SetHeight(DETAIL_H)
    detailPanel:Hide()
    detailPanel:SetScript("OnSizeChanged", ResizeDetailChoiceCards)

    local close = Theme.CreateButton(detailPanel)
    close:SetSize(22, 20)
    close:SetPoint("TOPRIGHT", detailPanel, "TOPRIGHT", -7, -7)
    close:SetText("x")
    close:SetScript("OnClick", function()
        CloseDetail()
        PositionLogAndInspector()
        H.RefreshLogView()
    end)

    detailCopyButton = Theme.CreateButton(detailPanel)
    detailCopyButton:SetSize(86, 20)
    detailCopyButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)
    detailCopyButton:SetText("Copy details")
    detailCopyButton:SetScript("OnClick", H.ExportDecision)
    Theme.AttachTooltip(detailCopyButton, "Copy decision details", "Opens selectable text. WoW 3.3.5a addons cannot write directly to the system clipboard.")

    detailTitle = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -42)
    detailTitle:SetPoint("RIGHT", detailCopyButton, "LEFT", -8, 0)
    detailTitle:SetJustifyH("LEFT")

    detailMeta = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -3)
    detailMeta:SetPoint("RIGHT", detailPanel, "RIGHT", -12, 0)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetTextColor(unpack(Theme.TEXT_MUTED))

    detailReason = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailReason:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -5)
    detailReason:SetPoint("RIGHT", detailPanel, "RIGHT", -12, 0)
    detailReason:SetJustifyH("LEFT")
    detailReason:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    detailFlags = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailFlags:SetPoint("TOPLEFT", detailReason, "BOTTOMLEFT", 0, -4)
    detailFlags:SetWidth(330)
    detailFlags:SetJustifyH("LEFT")
    detailFlags:SetTextColor(unpack(Theme.WARNING))

    detailResources = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailResources:SetPoint("LEFT", detailFlags, "RIGHT", 15, 0)
    detailResources:SetPoint("RIGHT", detailPanel, "RIGHT", -12, 0)
    detailResources:SetJustifyH("RIGHT")
    detailResources:SetTextColor(unpack(Theme.TEXT_MUTED))

    for i = 1, 3 do
        detailChoiceRows[i] = BuildDetailChoiceCard(detailPanel)
    end
    ResizeDetailChoiceCards()
end

local function BuildUI(container)
    BuildRunNavigator(container)
    BuildSummaryStrip(container)
    BuildFilterToolbar(container)
    BuildEventTimeline()
    BuildDecisionInspector()
    PositionLogAndInspector()
    H.UpdateFilterVisuals()
end

------------------------------------------------------------------------
-- Public interface and change notifications
------------------------------------------------------------------------

function H.OpenWithFilters(filters)
    local requested = filters or {}
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.OpenLogbook then EbonBuilds.BuildOverview.OpenLogbook() end
    pendingFilters = requested
    searchText = SearchSafeLower(VisibleEchoName(requested.echoName))
    actionFilter = requested.action or "All"
    if requested.source then
        sourceFilter = requested.source:lower():find("manual") and "Manual" or "Automatic"
    else
        sourceFilter = "All"
    end
    importantOnly = requested.importantOnly and true or false
    if searchInput then searchInput:SetText(requested.echoName or "") end
    H.UpdateFilterVisuals()
    H.RefreshLogView()
    pendingFilters = nil
end

function H.OnHistoryChanged()
    if not visible then return end
    H.RefreshSessionList()
    H.RefreshLogView()
end

local function DurationTick(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed < 1 then return end
    self._elapsed = 0
    local session = SelectedSession()
    if not session or session.endTime then self:Hide(); return end
    RefreshRunNavigatorText()
    UpdateSummary(session)
end

function H.Show(container)
    local buildKey = ActiveBuildKey()
    if lastBuildKey and lastBuildKey ~= buildKey and not pendingFilters then
        selectedSessionId = nil
        selectedEntry = nil
        searchText = ""
        importantOnly = false
        if searchInput then searchInput:SetText("") end
    end
    lastBuildKey = buildKey

    if not topPanel then
        BuildUI(container)
    else
        topPanel:SetParent(container)
        summaryStrip:SetParent(container)
        bottomPanel:SetParent(container)
        topPanel:Show()
        summaryStrip:Show()
        bottomPanel:Show()
    end
    visible = true
    H.RefreshSessionList()
    H.UpdateFilterVisuals()
    H.RefreshLogView()

    local session = SelectedSession()
    if session and not session.endTime then
        if not durationTimer then
            durationTimer = CreateFrame("Frame")
            durationTimer:SetScript("OnUpdate", DurationTick)
        end
        durationTimer._elapsed = 0
        durationTimer:Show()
    elseif durationTimer then
        durationTimer:Hide()
    end
end

function H.Hide()
    visible = false
    if topPanel then topPanel:Hide() end
    if summaryStrip then summaryStrip:Hide() end
    if bottomPanel then bottomPanel:Hide() end
    if detailPanel then detailPanel:Hide() end
    if exportDialog then exportDialog:Hide() end
    if durationTimer then durationTimer:Hide() end
    selectedEntry = nil
end

function H.Init()
    LoadPreferences()

    StaticPopupDialogs["EBONBUILDS_DELETE_SELECTED_SESSION"] = {
        text = "Delete this completed run?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            if pendingDeleteSessionId and EbonBuilds.Session and EbonBuilds.Session.DeleteSession then
                EbonBuilds.Session.DeleteSession(pendingDeleteSessionId)
                if selectedSessionId == pendingDeleteSessionId then selectedSessionId = nil end
            end
            pendingDeleteSessionId = nil
            H.RefreshSessionList()
            H.RefreshLogView()
        end,
        OnCancel = function() pendingDeleteSessionId = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["EBONBUILDS_CLEAR_BUILD_HISTORY"] = {
        text = "Delete completed history for this build?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            for _, id in ipairs(pendingClearSessionIds or {}) do
                if EbonBuilds.Session and EbonBuilds.Session.DeleteSession then EbonBuilds.Session.DeleteSession(id) end
                if selectedSessionId == id then selectedSessionId = nil end
            end
            pendingClearSessionIds = nil
            H.RefreshSessionList()
            H.RefreshLogView()
        end,
        OnCancel = function() pendingClearSessionIds = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- Test and integration hooks.
H._NormalizeAction = NormalizeAction
H._IsImportant = IsImportant
H._ReasonSentence = ReasonSentence
H._EntryMatches = EntryMatches
H._SessionSummary = SessionSummary
H._VisibleItems = VisibleItems
H._ClearFilters = ClearFilters
H._SetSort = SetSort
H._NextWheelScrollValue = NextWheelScrollValue
H._UIBuildFunctions = {
    BuildRunNavigator = BuildRunNavigator,
    BuildSummaryStrip = BuildSummaryStrip,
    BuildFilterToolbar = BuildFilterToolbar,
    BuildEventTimeline = BuildEventTimeline,
    BuildDecisionInspector = BuildDecisionInspector,
    BuildUI = BuildUI,
}
