local addonName, EbonBuilds = ...

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
local SUMMARY_H = 76
local DETAIL_H = 184
local DETAIL_WIDTH_GAP = 8
local FILTER_TOOLBAR_H = 30
local FILTER_CONTROL_H = 26
local FILTER_GAP = 6
local FILTER_SEARCH_W = 210
local FILTER_ACTION_W = 100
local FILTER_SOURCE_W = 104
local FILTER_IMPORTANT_W = 112
local FILTER_GROUP_W = 116

local topPanel, summaryStrip, bottomPanel
local runDropdown, previousRunButton, nextRunButton, runPositionLabel, historyDropdown
local runBrowser, runBrowserSearch, runBrowserPlaceholder, runBrowserCountLabel
local runBrowserScroll, runBrowserChild, runBrowserBar, runBrowserEmpty, runBrowserClear
local runBrowserFilterButtons = {}
local runBrowserRows = {}
local runBrowserResults = {}
local runBrowserSearchText = ""
local runBrowserFilter = "all"

local RUN_BROWSER_VISIBLE_ROWS = 8
local RUN_BROWSER_ROW_H = 50
local RUN_BROWSER_WIDTH = 560
local summaryMetrics = {}
local summaryRarityFrame, summaryRarityText
local runQualityCache = {}
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

local PolicyEvidence = {}

function PolicyEvidence.IsKnown(choice, entry)
    if type(choice) ~= "table" then return false end
    if entry and tonumber(entry.eligibilitySchema) == 1 then return true end
    if choice.eligibilityRecorded == true then return true end
    -- Older runs did record an active conditional policy effect, even though
    -- they did not record the complete eligibility snapshot.
    return choice.isBanned ~= nil or choice.isAvoided ~= nil or choice.policyBlocked ~= nil
        or choice.policyEffect == "banish" or choice.policyEffect == "exclude"
end

function PolicyEvidence.IsEligible(choice, entry)
    if not PolicyEvidence.IsKnown(choice, entry) then return true end
    return not (choice.isBanned or choice.isAvoided or choice.policyBlocked
        or choice.policyEffect == "banish" or choice.policyEffect == "exclude")
end

function PolicyEvidence.RuleLabel(choice)
    if not choice then return "policy" end
    if choice.isBanned then return "priority ban list" end
    local api = EbonBuilds.EchoPolicy
    local definition = api and api.Definition and choice.policy and api.Definition(choice.policy)
    if definition and definition.label then return tostring(definition.label) .. " policy" end
    if choice.policyEffect == "banish" then return "conditional banish policy" end
    if choice.policyEffect == "exclude" or choice.policyBlocked then return "selection policy" end
    if choice.isAvoided then return "avoid rule" end
    return "policy"
end

local function BestAlternative(entry, eligibleOnly)
    local target, targetArrayIndex = TargetChoice(entry)
    local best
    for arrayIndex, choice in ipairs((entry and entry.choices) or {}) do
        if choice ~= target and arrayIndex ~= targetArrayIndex
            and (not eligibleOnly or PolicyEvidence.IsEligible(choice, entry)) then
            if not best or (tonumber(choice.score) or 0) > (tonumber(best.score) or 0) then best = choice end
        end
    end
    return best
end

function PolicyEvidence.BestIneligibleAlternative(entry)
    local target, targetArrayIndex = TargetChoice(entry)
    local best
    for arrayIndex, choice in ipairs((entry and entry.choices) or {}) do
        if choice ~= target and arrayIndex ~= targetArrayIndex
            and PolicyEvidence.IsKnown(choice, entry) and not PolicyEvidence.IsEligible(choice, entry) then
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
    ECHO_POLICY_BANISH = "A conditional Echo policy required this banish",
    ECHO_BAN_LIST = "The priority ban list required this banish",
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
    local target = TargetChoice(entry)
    local alternative = BestAlternative(entry, true)
    local ineligible = PolicyEvidence.BestIneligibleAlternative(entry)
    local threshold = tonumber(decision.threshold)
    local reason = REASON_TEXT[decision.reasonCode]

    if action == "Banish" and target then
        if decision.reasonCode == "ECHO_BAN_LIST" or (PolicyEvidence.IsKnown(target, entry) and target.isBanned) then
            return REASON_TEXT.ECHO_BAN_LIST
        end
        if decision.reasonCode == "ECHO_POLICY_BANISH" or target.policyEffect == "banish" then
            return string.format("The %s required this banish", PolicyEvidence.RuleLabel(target))
        end
        if threshold then return string.format("%.0f below threshold %.0f", tonumber(target.score) or 0, threshold) end
        return reason or "Removed the chosen low-value Echo"
    elseif action == "Reroll" then
        if alternative then return string.format("Best eligible current option: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0) end
        if ineligible then
            return string.format("No eligible current option; %s at %.0f was ineligible under the %s",
                ineligible.name or "Echo", tonumber(ineligible.score) or 0, PolicyEvidence.RuleLabel(ineligible))
        end
        return reason or "Replaced the current offer"
    elseif action == "Freeze" and target then
        if threshold then return string.format("%.0f exceeded threshold %.0f", tonumber(target.score) or 0, threshold) end
        return reason or "Preserved a strong Echo for later"
    elseif (action == "Select" or action == "Manual") and target then
        local targetScore = tonumber(target.score) or 0
        if alternative and (tonumber(alternative.score) or 0) > targetScore then
            return string.format("Higher eligible option: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0)
        end
        if ineligible and (tonumber(ineligible.score) or 0) > targetScore then
            return string.format("Highest eligible; %s at %.0f was ineligible under the %s",
                ineligible.name or "Echo", tonumber(ineligible.score) or 0, PolicyEvidence.RuleLabel(ineligible))
        end
        if alternative then return string.format("Next eligible: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0) end
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
        local best = BestAlternative(entry, true)
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

local function GetRunCompletionState(session)
    if not session then return "unknown" end
    -- A live session remains Active even if an older logger accidentally set a
    -- completion flag from the character's permanent level. Completion is only
    -- authoritative after the session has an end time.
    if not session.endTime then return "active" end
    if session.completed == true or session.completionReason == "all_picks_complete" or session.picksCompleted == true then
        return "complete"
    end
    if (tonumber(session.maxLevel or session.startLevel) or 1) >= 80 then
        return "complete"
    end
    return "short"
end

local function RunDisplayEndTime(session)
    if not session then return nil end
    if GetRunCompletionState(session) == "complete" and session.completionTime then
        return session.completionTime
    end
    return session.endTime
end

local function RunStatusLabel(session)
    local state = GetRunCompletionState(session)
    if state == "active" then return "Active" end
    if state == "complete" then return "Complete" end
    if state == "short" then return "Short" end
    return "Unknown"
end

local function ResolveChoiceQuality(choice)
    if type(choice) ~= "table" then return nil end
    local quality = tonumber(choice.quality)
    if quality ~= nil and EbonBuilds.Quality and EbonBuilds.Quality.IsValid and EbonBuilds.Quality.IsValid(quality) then
        return quality
    end

    local spellId = tonumber(choice.spellId)
    local database = ProjectEbonhold and ProjectEbonhold.PerkDatabase
    local data = spellId and database and (database[spellId] or database[tostring(spellId)])
    quality = data and tonumber(data.quality) or nil
    if quality ~= nil and EbonBuilds.Quality and EbonBuilds.Quality.IsValid and EbonBuilds.Quality.IsValid(quality) then
        return quality
    end
    return nil
end

local function RunQualityCacheToken(session)
    local databaseReady = ProjectEbonhold and ProjectEbonhold.PerkDatabase and 1 or 0
    return table.concat({
        tostring(session and session.analyticsRevision or 0),
        tostring(session and #(session.logs or {}) or 0),
        tostring(session and session.endTime or 0),
        tostring(session and session.maxLevel or 0),
        tostring(session and session.selectionCount or ""),
        tostring(session and session.completed or false),
        tostring(session and session.completionReason or ""),
        tostring(databaseReady),
    }, ":")
end

local function SelectionFingerprint(entry, target)
    if type(entry) ~= "table" or type(target) ~= "table" then return nil end

    local explicitId = tostring(entry.selectionId or "")
    if explicitId ~= "" then return "id:" .. explicitId end

    local targetKey = tostring(target.spellId or VisibleEchoName(target.name) or "")
    local targetQuality = tostring(target.quality == nil and "" or target.quality)
    local offer = {}
    for arrayIndex, choice in ipairs(entry.choices or {}) do
        offer[#offer + 1] = table.concat({
            tostring(arrayIndex),
            tostring(choice.spellId or VisibleEchoName(choice.name) or ""),
            tostring(choice.quality == nil and "" or choice.quality),
        }, ":")
    end

    return table.concat({ targetKey, targetQuality, tostring(entry.targetIndex or ""), table.concat(offer, ",") }, "|")
end

local function ExpectedRunSelectionCount(session)
    if not session then return nil end

    -- selectionCount may be stale on sessions created before pickIndex existed.
    -- Derive the best available count from every finalized selection record and
    -- never let a smaller saved value truncate a longer real history.
    local explicit = math.max(0, tonumber(session.selectionCount) or 0)
    local highestPick = 0
    local rawSelections = 0
    for _, entry in ipairs(session.logs or {}) do
        local action = NormalizeAction(entry.action)
        if (action == "Select" or action == "Manual") and TargetChoice(entry) then
            rawSelections = rawSelections + 1
            local pickIndex = tonumber(entry.pickIndex)
            if pickIndex and pickIndex > highestPick then highestPick = pickIndex end
        end
    end

    local cap = 79
    local state = GetRunCompletionState(session)
    local recordedLevel = tonumber(session.maxLevel)
    if state == "short" and recordedLevel and recordedLevel > 1 and recordedLevel < 80 then
        cap = math.min(cap, recordedLevel - 1)
    end

    local derived = math.max(explicit, highestPick, math.min(cap, rawSelections))
    if state == "complete" then derived = math.max(derived, math.min(79, rawSelections)) end
    return math.min(79, derived)
end

local function RunQualitySummary(session)
    local empty = {
        counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
        totalSelectionCount = 0,
        classifiedSelectionCount = 0,
        expectedSelectionCount = 0,
        discardedDuplicateCount = 0,
    }
    if not session then return empty end

    local cacheKey = tostring(session.id or session)
    local token = RunQualityCacheToken(session)
    local cached = runQualityCache[cacheKey]
    if cached and cached.token == token then return cached.summary end

    local result = {
        counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
        totalSelectionCount = 0,
        classifiedSelectionCount = 0,
        expectedSelectionCount = ExpectedRunSelectionCount(session) or 0,
        discardedDuplicateCount = 0,
    }

    -- New logs carry an explicit pickIndex. Older logs used UnitLevel("player")
    -- as entry.level, which can be 80 for every event even while the Echo run is
    -- only at Level 61. Treat such constant-level histories as sequential picks;
    -- otherwise they collapse to one record and produce totals such as U 2.
    local candidates = {}
    local rawSelectionCount = 0
    local levelFrequency = {}
    local levelAwareCount = 0

    local function PreferRecord(existing, candidate)
        if not existing then return candidate end
        if candidate.action == "Manual" and existing.action ~= "Manual" then return candidate end
        if candidate.action ~= "Manual" and existing.action == "Manual" then return existing end
        return candidate.logIndex >= existing.logIndex and candidate or existing
    end

    for logIndex, entry in ipairs(session.logs or {}) do
        local action = NormalizeAction(entry.action)
        if action == "Select" or action == "Manual" then
            local target = TargetChoice(entry)
            if target then
                rawSelectionCount = rawSelectionCount + 1
                local pickIndex = tonumber(entry.pickIndex)
                local level = tonumber(entry.level)
                if level then
                    levelFrequency[level] = (levelFrequency[level] or 0) + 1
                    levelAwareCount = levelAwareCount + 1
                end
                candidates[#candidates + 1] = {
                    target = target,
                    action = action,
                    logIndex = logIndex,
                    pickIndex = pickIndex,
                    level = level,
                    fingerprint = SelectionFingerprint(entry, target),
                }
            end
        end
    end

    local distinctLevels = 0
    for _ in pairs(levelFrequency) do distinctLevels = distinctLevels + 1 end

    -- Legacy builds sometimes stored only one or two character-level values for
    -- dozens of Echo picks. Treat levels as pick identifiers only when they cover
    -- most of the selection sequence. A tiny number of repeated levels must not
    -- collapse 60 real picks into two records.
    local minimumDistinctLevels = math.max(3, math.floor((rawSelectionCount + 1) / 2))
    local levelsAreTrustworthy = rawSelectionCount > 0
        and distinctLevels >= minimumDistinctLevels

    local records = {}
    local recordsByPick = {}
    local recordsByLevel = {}
    local recordsByExplicitId = {}

    for _, record in ipairs(candidates) do
        if record.pickIndex and record.pickIndex >= 1 and record.pickIndex <= 79 then
            recordsByPick[record.pickIndex] = PreferRecord(recordsByPick[record.pickIndex], record)
        elseif levelsAreTrustworthy and record.level and record.level >= 1 and record.level <= 80 then
            recordsByLevel[record.level] = PreferRecord(recordsByLevel[record.level], record)
        else
            -- No trustworthy progress key exists. Keep the event as a sequential
            -- finalized pick. Only an explicit selectionId is safe to deduplicate;
            -- repeated Echo names/offers can legitimately occur in different picks.
            local explicitId = record.fingerprint and record.fingerprint:match("^id:(.+)$")
            if explicitId then
                recordsByExplicitId[explicitId] = PreferRecord(recordsByExplicitId[explicitId], record)
            else
                records[#records + 1] = record
            end
        end
    end

    for _, record in pairs(recordsByPick) do records[#records + 1] = record end
    for _, record in pairs(recordsByLevel) do records[#records + 1] = record end
    for _, record in pairs(recordsByExplicitId) do records[#records + 1] = record end
    table.sort(records, function(left, right) return left.logIndex < right.logIndex end)

    -- Completed runs contain at most 79 picks. This also repairs legacy
    -- histories where an entire 79-pick sequence was appended twice. Active
    -- runs are not capped from the stale maxLevel field; all currently recorded
    -- finalized picks remain visible.
    local expected = result.expectedSelectionCount
    -- expectedSelectionCount is derived from the complete log above, so stale
    -- session.selectionCount values can no longer reduce the list to 2 records.
    local hardCap = expected and expected > 0 and expected or 79
    if #records > hardCap then
        local bounded = {}
        for index = 1, hardCap do bounded[index] = records[index] end
        records = bounded
    end

    local function CountSelection(record)
        if not record or not record.target then return end
        result.totalSelectionCount = result.totalSelectionCount + 1
        local quality = ResolveChoiceQuality(record.target)
        if quality ~= nil then
            result.counts[quality] = (result.counts[quality] or 0) + 1
            result.classifiedSelectionCount = result.classifiedSelectionCount + 1
        end
    end

    for _, record in ipairs(records) do CountSelection(record) end
    result.discardedDuplicateCount = math.max(0, rawSelectionCount - result.totalSelectionCount)

    runQualityCache[cacheKey] = { token = token, summary = result }
    return result
end

local function RunDisplayLevel(session)
    if not session then return 1 end
    local state = GetRunCompletionState(session)
    if state == "complete" then return 80 end

    local summary = RunQualitySummary(session)
    local picks = math.max(
        tonumber(session.selectionCount) or 0,
        tonumber(summary.totalSelectionCount) or 0
    )
    if picks > 0 then return math.min(80, picks + 1) end

    local recorded = tonumber(session.maxLevel or session.startLevel)
    if recorded and recorded >= 1 and recorded < 80 then return recorded end
    return 1
end

local function QualityCountText(summary, compact)
    summary = summary or RunQualitySummary(nil)
    local total = tonumber(summary.totalSelectionCount) or 0
    local classified = tonumber(summary.classifiedSelectionCount) or 0
    if total == 0 then
        return compact and "Selected: no Echo data" or "Selected Echo quality: no selections recorded"
    end
    if classified == 0 then
        return compact and "Selected quality unavailable" or "Selected Echo quality unavailable for this legacy run"
    end

    local counts = summary.counts or {}
    if compact then
        return table.concat({
            EbonBuilds.Quality.Colorize("E " .. tostring(counts[3] or 0), 3),
            EbonBuilds.Quality.Colorize("R " .. tostring(counts[2] or 0), 2),
            EbonBuilds.Quality.Colorize("U " .. tostring(counts[1] or 0), 1),
            EbonBuilds.Quality.Colorize("C " .. tostring(counts[0] or 0), 0),
        }, "  ·  ")
    end

    return "Selected Echo quality  " .. table.concat({
        EbonBuilds.Quality.Colorize("Epic " .. tostring(counts[3] or 0), 3),
        EbonBuilds.Quality.Colorize("Rare " .. tostring(counts[2] or 0), 2),
        EbonBuilds.Quality.Colorize("Uncommon " .. tostring(counts[1] or 0), 1),
        EbonBuilds.Quality.Colorize("Common " .. tostring(counts[0] or 0), 0),
    }, "  ·  ")
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
    result.quality = RunQualitySummary(session)
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
    local status = RunStatusLabel(session)
    return string.format("%s · Level %s · %s · %d events", status, tostring(RunDisplayLevel(session)), FormatDuration(session.startTime, RunDisplayEndTime(session)), #(session.logs or {}))
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
    if runBrowser and runBrowser:IsShown() and H.RefreshRunBrowser then H.RefreshRunBrowser(true) end
end

local function RunDurationSeconds(session)
    if not session then return 0 end
    return math.max(0, (RunDisplayEndTime(session) or time()) - (session.startTime or time()))
end

local function RunRelativeDate(session)
    local started = tonumber(session and session.startTime)
    if not started then return "Unknown date" end
    local today = date("%Y-%m-%d", time())
    local yesterday = date("%Y-%m-%d", time() - 86400)
    local runDay = date("%Y-%m-%d", started)
    if runDay == today then return "Today " .. date("%H:%M", started) end
    if runDay == yesterday then return "Yesterday " .. date("%H:%M", started) end
    return date("%d %b %Y %H:%M", started)
end

local function RunIsShort(session)
    return GetRunCompletionState(session) == "short"
end

local function RunIsRecent(session)
    local started = tonumber(session and session.startTime) or 0
    return started > 0 and (time() - started) <= 86400
end

local function RunBrowserSearchBlob(session)
    if not session then return "" end
    local completionState = GetRunCompletionState(session)
    local status = completionState == "complete" and "complete completed"
        or completionState == "short" and "short incomplete interrupted"
        or completionState == "active" and "active recording"
        or "unknown"
    local level = RunDisplayLevel(session)
    local eventCount = #(session.logs or {})
    local quality = RunQualitySummary(session)
    local fields = {
        status,
        "level " .. tostring(level),
        tostring(level),
        FormatDuration(session.startTime, RunDisplayEndTime(session)),
        FormatRunDate(session.startTime),
        RunRelativeDate(session),
        tostring(eventCount),
        tostring(eventCount) .. " events",
        "epic " .. tostring(quality.counts[3] or 0),
        "rare " .. tostring(quality.counts[2] or 0),
        "uncommon " .. tostring(quality.counts[1] or 0),
        "common " .. tostring(quality.counts[0] or 0),
    }
    if RunIsShort(session) then fields[#fields + 1] = "short" end
    if RunIsRecent(session) then fields[#fields + 1] = "recent" end
    return SearchSafeLower(table.concat(fields, " "))
end

local function RunMatchesBrowserFilter(session)
    if runBrowserFilter == "complete" then
        return GetRunCompletionState(session) == "complete"
    elseif runBrowserFilter == "short" then
        return RunIsShort(session)
    elseif runBrowserFilter == "recent" then
        return RunIsRecent(session)
    end
    return true
end

local function UpdateRunBrowserFilterButtons()
    for key, button in pairs(runBrowserFilterButtons) do
        Theme.SetTabSelected(button, key == runBrowserFilter)
    end
end

local function UpdateRunBrowserSearchPlaceholder()
    if not runBrowserSearch or not runBrowserPlaceholder then return end
    if runBrowserSearch:HasFocus() or (runBrowserSearch:GetText() or "") ~= "" then
        runBrowserPlaceholder:Hide()
    else
        runBrowserPlaceholder:Show()
    end
end

local function ApplyRunBrowserRowVisual(row, hovered)
    local session = row and row._session
    if not row or not session then return end
    local selected = session.id == selectedSessionId
    local active = not session.endTime
    if hovered then
        row:SetBackdropColor(unpack(Theme.CARD_HOVER))
        row:SetBackdropBorderColor(unpack(selected and Theme.ACCENT_GOLD or Theme.BORDER))
    else
        row:SetBackdropColor(unpack(Theme.CARD_BG))
        row:SetBackdropBorderColor(unpack(selected and Theme.ACCENT_GOLD or Theme.BORDER_DIM))
    end
    local marker = active and Theme.SUCCESS or selected and Theme.ACCENT_GOLD or Theme.BORDER_DIM
    row._marker:SetVertexColor(marker[1], marker[2], marker[3], (active or selected) and 1 or 0.75)
end

local function RefreshRunBrowserRows()
    if not runBrowser or not runBrowser:IsShown() or not runBrowserScroll then return end
    local firstIndex = math.floor((runBrowserScroll:GetVerticalScroll() or 0) / RUN_BROWSER_ROW_H) + 1
    for rowIndex, row in ipairs(runBrowserRows) do
        local dataIndex = firstIndex + rowIndex - 1
        local session = runBrowserResults[dataIndex]
        if session then
            local level = RunDisplayLevel(session)
            local events = #(session.logs or {})
            local quality = RunQualitySummary(session)
            row._session = session
            row._qualitySummary = quality
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", runBrowserChild, "TOPLEFT", 0, -((dataIndex - 1) * RUN_BROWSER_ROW_H))
            row:SetPoint("RIGHT", runBrowserChild, "RIGHT", 0, 0)
            row._primary:SetText(string.format("Level %d · %s", level, FormatDuration(session.startTime, RunDisplayEndTime(session))))
            row._secondary:SetText(string.format("%s · %s", RunStatusLabel(session), RunRelativeDate(session)))
            row._rarity:SetText(QualityCountText(quality, true))
            row._events:SetText(string.format("%d events", events))
            row._events:SetTextColor(events == 0 and 0.52 or Theme.TEXT_MUTED[1], events == 0 and 0.52 or Theme.TEXT_MUTED[2], events == 0 and 0.56 or Theme.TEXT_MUTED[3], 1)
            ApplyRunBrowserRowVisual(row, false)
            row:Show()
        else
            row._session = nil
            row._qualitySummary = nil
            row:Hide()
        end
    end
end

local function ScrollRunBrowserToSelected()
    if not runBrowserBar then return end
    local selectedIndex
    for index, session in ipairs(runBrowserResults) do
        if session.id == selectedSessionId then selectedIndex = index; break end
    end
    local _, maximum = runBrowserBar:GetMinMaxValues()
    local target = 0
    if selectedIndex then
        target = math.max(0, (selectedIndex - math.ceil(RUN_BROWSER_VISIBLE_ROWS / 2)) * RUN_BROWSER_ROW_H)
    end
    runBrowserBar:SetValue(math.min(maximum or 0, target))
end

function H.RefreshRunBrowser(scrollToSelected)
    if not runBrowser then return end
    runBrowserResults = {}
    local needle = SearchSafeLower(runBrowserSearchText)
    for _, session in ipairs(relevantSessionCache) do
        if RunMatchesBrowserFilter(session) and (needle == "" or RunBrowserSearchBlob(session):find(needle, 1, true)) then
            runBrowserResults[#runBrowserResults + 1] = session
        end
    end

    local totalHeight = math.max(1, #runBrowserResults * RUN_BROWSER_ROW_H)
    local viewportHeight = RUN_BROWSER_VISIBLE_ROWS * RUN_BROWSER_ROW_H
    runBrowserChild:SetHeight(totalHeight)
    local maximum = math.max(0, totalHeight - viewportHeight)
    runBrowserBar:SetMinMaxValues(0, maximum)
    if scrollToSelected then
        ScrollRunBrowserToSelected()
    elseif runBrowserBar:GetValue() > maximum then
        runBrowserBar:SetValue(maximum)
    else
        runBrowserScroll:SetVerticalScroll(runBrowserBar:GetValue())
        RefreshRunBrowserRows()
    end

    if runBrowserCountLabel then
        if #runBrowserResults == #relevantSessionCache then
            local completeCount, shortCount, activeCount = 0, 0, 0
            for _, session in ipairs(relevantSessionCache) do
                local state = GetRunCompletionState(session)
                if state == "complete" then completeCount = completeCount + 1
                elseif state == "short" then shortCount = shortCount + 1
                elseif state == "active" then activeCount = activeCount + 1 end
            end
            local suffix = activeCount > 0 and string.format(" · %d active", activeCount) or ""
            runBrowserCountLabel:SetText(string.format("%d runs · %d complete · %d short%s", #relevantSessionCache, completeCount, shortCount, suffix))
        else
            runBrowserCountLabel:SetText(string.format("%d of %d runs", #runBrowserResults, #relevantSessionCache))
        end
    end
    if runBrowserEmpty then
        if #runBrowserResults == 0 then runBrowserEmpty:Show() else runBrowserEmpty:Hide() end
    end
    if runBrowserClear then
        if runBrowserFilter ~= "all" or runBrowserSearchText ~= "" then runBrowserClear:Show() else runBrowserClear:Hide() end
    end
    UpdateRunBrowserFilterButtons()
    RefreshRunBrowserRows()
end

local function CloseRunBrowser()
    if runBrowser then runBrowser:Hide() end
    if runBrowserSearch then runBrowserSearch:ClearFocus() end
end

local function CreateRunBrowserRow(parent)
    local row = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "SessionHistory.RunBrowserRow")
    end
    row:SetHeight(RUN_BROWSER_ROW_H - 2)
    Theme.ApplyCard(row)

    local marker = row:CreateTexture(nil, "ARTWORK")
    marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    marker:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    marker:SetWidth(3)
    row._marker = marker

    local primary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    primary:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
    primary:SetPoint("RIGHT", row, "RIGHT", -92, 0)
    primary:SetJustifyH("LEFT")
    primary:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    row._primary = primary

    local secondary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    secondary:SetPoint("TOPLEFT", primary, "BOTTOMLEFT", 0, -3)
    secondary:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    secondary:SetJustifyH("LEFT")
    secondary:SetTextColor(unpack(Theme.TEXT_MUTED))
    row._secondary = secondary

    local rarity = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rarity:SetPoint("TOPLEFT", secondary, "BOTTOMLEFT", 0, -2)
    rarity:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    rarity:SetJustifyH("LEFT")
    rarity:SetTextColor(unpack(Theme.TEXT_MUTED))
    row._rarity = rarity

    local events = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    events:SetPoint("TOPRIGHT", row, "TOPRIGHT", -9, -5)
    events:SetWidth(78)
    events:SetJustifyH("RIGHT")
    row._events = events

    row:SetScript("OnEnter", function(self)
        ApplyRunBrowserRowVisual(self, true)
        local session = self._session
        local quality = self._qualitySummary
        if not session or not quality then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(RunMenuLabel(session), 1, 0.82, 0)
        GameTooltip:AddLine("Rarity counts include selected Echoes only; offered, banished, frozen-only, and rerolled Echoes are excluded.", 0.78, 0.78, 0.82, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Epic %d · Rare %d · Uncommon %d · Common %d", quality.counts[3] or 0, quality.counts[2] or 0, quality.counts[1] or 0, quality.counts[0] or 0), 0.86, 0.86, 0.90)
        if quality.classifiedSelectionCount < quality.totalSelectionCount then
            GameTooltip:AddLine(string.format("%d of %d selections could be classified by quality.", quality.classifiedSelectionCount, quality.totalSelectionCount), 1, 0.66, 0.16, true)
        else
            GameTooltip:AddLine(string.format("%d selected Echo%s classified.", quality.classifiedSelectionCount, quality.classifiedSelectionCount == 1 and "" or "es"), 0.68, 0.68, 0.74)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        ApplyRunBrowserRowVisual(self, false)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(row, function(self)
            if self._session then ApplyRunBrowserRowVisual(self, false) end
            GameTooltip:Hide()
        end)
    end
    row:SetScript("OnClick", function(self)
        if self._session then
            SelectSession(self._session.id)
            CloseRunBrowser()
        end
    end)
    return row
end

local function EnsureRunBrowser()
    if runBrowser then return runBrowser end

    local popup = CreateFrame("Frame", nil, UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(popup, "SessionHistory.RunBrowserPopup")
    end
    popup:SetSize(RUN_BROWSER_WIDTH, 526)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    Theme.ApplyWindow(popup)
    popup:Hide()
    runBrowser = popup

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -11)
    title:SetText("Select run")
    title:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local close = Theme.CreateButton(popup)
    close:SetSize(24, 22)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -7)
    close:SetText("x")
    close:SetScript("OnClick", CloseRunBrowser)

    runBrowserCountLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    runBrowserCountLabel:SetPoint("RIGHT", close, "LEFT", -10, 0)
    runBrowserCountLabel:SetJustifyH("RIGHT")
    runBrowserCountLabel:SetTextColor(unpack(Theme.TEXT_MUTED))

    local searchWrap = CreateFrame("Frame", nil, popup)
    searchWrap:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -38)
    searchWrap:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, -38)
    searchWrap:SetHeight(24)
    Theme.ApplyInput(searchWrap)

    local search = CreateFrame("EditBox", nil, searchWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(search, "SessionHistory.RunBrowserSearch")
    end
    search:SetPoint("TOPLEFT", searchWrap, "TOPLEFT", 7, -3)
    search:SetPoint("BOTTOMRIGHT", searchWrap, "BOTTOMRIGHT", -22, 3)
    search:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    search:SetAutoFocus(false)
    search:SetTextColor(1, 1, 1, 1)
    Theme.WireEditBox(search, searchWrap)
    runBrowserSearch = search

    local placeholder = searchWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 0, 0)
    placeholder:SetText("Search level, date, duration, or events...")
    placeholder:SetTextColor(unpack(Theme.TEXT_MUTED))
    runBrowserPlaceholder = placeholder

    local clearSearch = CreateFrame("Button", nil, searchWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(clearSearch, "SessionHistory.RunBrowserClearSearch")
    end
    clearSearch:SetSize(18, 18)
    clearSearch:SetPoint("RIGHT", searchWrap, "RIGHT", -2, 0)
    local clearText = clearSearch:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetPoint("CENTER")
    clearText:SetText("x")
    clearText:SetTextColor(unpack(Theme.TEXT_MUTED))
    clearSearch:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

    search:SetScript("OnTextChanged", function(self)
        runBrowserSearchText = self:GetText() or ""
        UpdateRunBrowserSearchPlaceholder()
        H.RefreshRunBrowser(false)
        if runBrowserBar then runBrowserBar:SetValue(0) end
    end)
    search:SetScript("OnEditFocusGained", UpdateRunBrowserSearchPlaceholder)
    search:SetScript("OnEditFocusLost", UpdateRunBrowserSearchPlaceholder)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else CloseRunBrowser() end
    end)
    Theme.AttachTooltip(searchWrap, "Search runs", "Matches status, level, duration, date, event count, and selected-Echo rarity totals.")

    local filterDefs = {
        { key = "all", label = "All", tip = "Show every run recorded for this build." },
        { key = "complete", label = "Complete", tip = "Show finished runs where all Echo picks were completed. Legacy Level 80 runs are treated as complete." },
        { key = "short", label = "Short", tip = "Show finished runs that ended before all Echo picks were completed. Active runs and completed Level 80 runs are excluded." },
        { key = "recent", label = "Recent", tip = "Show runs started during the last 24 hours." },
    }
    local previous
    for _, def in ipairs(filterDefs) do
        local item = def
        local button = Theme.CreateTab(popup, item.label)
        button:SetSize(item.key == "complete" and 82 or 68, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 5, 0) else button:SetPoint("TOPLEFT", searchWrap, "BOTTOMLEFT", 0, -7) end
        button:SetScript("OnClick", function()
            runBrowserFilter = item.key
            if runBrowserBar then runBrowserBar:SetValue(0) end
            H.RefreshRunBrowser(false)
        end)
        Theme.AttachTooltip(button, item.label .. " runs", item.tip)
        runBrowserFilterButtons[item.key] = button
        previous = button
    end

    local listTop = -94
    runBrowserScroll = CreateFrame("ScrollFrame", nil, popup)
    runBrowserScroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, listTop)
    runBrowserScroll:SetSize(RUN_BROWSER_WIDTH - 34, RUN_BROWSER_VISIBLE_ROWS * RUN_BROWSER_ROW_H)
    runBrowserScroll:EnableMouseWheel(true)

    runBrowserChild = CreateFrame("Frame", nil, runBrowserScroll)
    runBrowserChild:SetWidth(RUN_BROWSER_WIDTH - 40)
    runBrowserChild:SetHeight(1)
    runBrowserScroll:SetScrollChild(runBrowserChild)

    runBrowserBar = Theme.CreateScrollBar(popup)
    runBrowserBar:SetPoint("TOPRIGHT", runBrowserScroll, "TOPRIGHT", 17, -1)
    runBrowserBar:SetPoint("BOTTOMRIGHT", runBrowserScroll, "BOTTOMRIGHT", 17, 1)
    runBrowserBar:SetValueStep(RUN_BROWSER_ROW_H)
    runBrowserBar:SetScript("OnValueChanged", function(_, value)
        runBrowserScroll:SetVerticalScroll(value)
        RefreshRunBrowserRows()
    end)

    for index = 1, RUN_BROWSER_VISIBLE_ROWS do
        runBrowserRows[index] = CreateRunBrowserRow(runBrowserChild)
    end
    Theme.BindScrollWheel(runBrowserScroll, runBrowserBar, RUN_BROWSER_ROW_H, runBrowserChild)
    for _, row in ipairs(runBrowserRows) do Theme.BindScrollWheel(runBrowserScroll, runBrowserBar, RUN_BROWSER_ROW_H, row) end

    runBrowserEmpty = CreateFrame("Frame", nil, runBrowserScroll)
    runBrowserEmpty:SetAllPoints(runBrowserScroll)
    runBrowserEmpty:EnableMouse(false)
    local emptyTitle = runBrowserEmpty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyTitle:SetPoint("CENTER", runBrowserEmpty, "CENTER", 0, 10)
    emptyTitle:SetText("No matching runs")
    local emptyBody = runBrowserEmpty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyBody:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -6)
    emptyBody:SetText("Clear the search or select All.")
    emptyBody:SetTextColor(unpack(Theme.TEXT_MUTED))

    runBrowserClear = Theme.CreateButton(popup)
    runBrowserClear:SetSize(104, 22)
    runBrowserClear:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -10, 9)
    runBrowserClear:SetText("Clear filters")
    runBrowserClear:SetScript("OnClick", function()
        runBrowserFilter = "all"
        runBrowserSearchText = ""
        if runBrowserSearch then runBrowserSearch:SetText("") end
        if runBrowserBar then runBrowserBar:SetValue(0) end
        H.RefreshRunBrowser(false)
    end)

    local footer = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 11, 14)
    footer:SetText("Click a run to load it. The popup closes after selection.")
    footer:SetTextColor(unpack(Theme.TEXT_MUTED))

    popup:SetScript("OnHide", function()
        if runBrowserSearch then runBrowserSearch:ClearFocus() end
    end)
    return popup
end

local function ToggleRunBrowser()
    local popup = EnsureRunBrowser()
    if popup:IsShown() then
        CloseRunBrowser()
        return
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", runDropdown, "BOTTOMLEFT", 0, -4)
    popup:Show()
    H.RefreshRunBrowser(true)
end

local function UpdateSummary(session)
    local data = SessionSummary(session)
    local values = {
        level = tostring(session and (RunDisplayLevel(session)) or "—"),
        duration = session and FormatDuration(session.startTime, RunDisplayEndTime(session)) or "—",
        events = tostring(data.events or 0),
        score = data.selectedCount > 0 and string.format("%.1f", data.averageSelected or 0) or "—",
        actions = string.format("B %d  R %d  F %d", data.actions.Banish or 0, data.actions.Reroll or 0, data.actions.Freeze or 0),
    }
    for key, value in pairs(values) do if summaryMetrics[key] then summaryMetrics[key].value:SetText(value) end end
    if summaryRarityText then
        summaryRarityText:SetText(QualityCountText(data.quality, false))
    end
    if summaryRarityFrame then
        summaryRarityFrame._qualitySummary = data.quality
        summaryRarityFrame._session = session
    end
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
        dialog.text = string.format("Delete this completed run?\n\nLevel %s · %s · %d events\n\nThis cannot be undone.", tostring(RunDisplayLevel(session)), FormatDuration(session.startTime, RunDisplayEndTime(session)), SessionEventCount(session))
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
        row:SetBackdropColor(EbonBuilds.Theme.SELECTED_BG[1], EbonBuilds.Theme.SELECTED_BG[2], EbonBuilds.Theme.SELECTED_BG[3], 0.99)
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "SessionHistory.TimelineRow")
    end
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
    if Theme.BindHoverReset then
        Theme.BindHoverReset(row, function(self)
            self._hovered = false
            SetRowVisual(self)
        end)
    end
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

local RESOURCE_DEFINITIONS = {
    { key = "ban", label = "Banish", color = "ffff6b6b" },
    { key = "reroll", label = "Reroll", color = "ff55aaff" },
    { key = "freeze", label = "Freeze", color = "ff55ddee" },
}

local function ResourceChangeSummary(before, after, colored)
    after = after or {}
    local used, restored, remaining = {}, {}, {}
    for _, resource in ipairs(RESOURCE_DEFINITIONS) do
        local current = tonumber(after[resource.key]) or 0
        local previous = before and (tonumber(before[resource.key]) or 0) or nil
        local label = resource.label
        if colored then label = "|c" .. resource.color .. label .. "|r" end
        remaining[#remaining + 1] = string.format("%s %d", label, current)
        if previous then
            local delta = previous - current
            if delta > 0 then
                used[#used + 1] = string.format("%d %s", delta, resource.label)
            elseif delta < 0 then
                restored[#restored + 1] = string.format("%d %s", -delta, resource.label)
            end
        end
    end

    local change = nil
    if #used > 0 then change = "Used: " .. table.concat(used, ", ") end
    if #restored > 0 then
        local restoredText = "Restored: " .. table.concat(restored, ", ")
        change = change and (change .. "  |  " .. restoredText) or restoredText
    end
    local remainingText = "Remaining: " .. table.concat(remaining, "  |  ")
    return change, remainingText
end

local function ResourceDisplayText(before, after)
    local change, remaining = ResourceChangeSummary(before, after, true)
    return change and (change .. "\n" .. remaining) or remaining
end

local function ResizeDetailChoiceCards()
    if not detailPanel then return end
    local available = math.max(480, (detailPanel:GetWidth() or 700) - 24)
    local width = math.floor((available - DETAIL_WIDTH_GAP * 2) / 3)
    for index, card in ipairs(detailChoiceRows) do
        card:SetWidth(width)
        card:ClearAllPoints()
        if index == 1 then
            card:SetPoint("TOPLEFT", detailFlags, "BOTTOMLEFT", 0, -8)
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
        local modifierDelta = choice.modifierDelta
        if modifierDelta == nil and choice.baseWeight ~= nil and choice.score ~= nil then
            modifierDelta = (tonumber(choice.score) or 0) - (tonumber(choice.baseWeight) or 0)
        end
        lines[#lines + 1] = string.format("%d. %s%s · quality %s · weight %s · modifiers %s · final %s", index, choice.name or "Unknown Echo", choice == target and " [TARGET]" or "", tostring(choice.quality or "?"), tostring(choice.baseWeight or "?"), modifierDelta ~= nil and string.format("%+.0f", modifierDelta) or "?", tostring(choice.score or "?"))
    end
    local charges = entry.charges or {}
    local change, remaining = ResourceChangeSummary(PreviousEntryCharges(entry), charges, false)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Resources"
    if change then lines[#lines + 1] = change end
    lines[#lines + 1] = remaining
    return table.concat(lines, "\n")
end

function H.ShowDecisionDetail(entry)
    if not detailPanel or not entry then return end
    selectedEntry = entry
    local decision = entry.decision or {}
    local action = NormalizeAction(entry.action)
    local name = DecisionLabel(entry)
    detailTitle:SetText(string.format("%s · %s", string.upper(action), tostring(name or "Decision")))
    detailReason:SetText(ReasonSentence(entry))

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
    detailResources:SetText(ResourceDisplayText(before, after))

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
                local modifierDelta = choice.modifierDelta
                if modifierDelta == nil then modifierDelta = (tonumber(choice.score) or 0) - (tonumber(choice.baseWeight) or 0) end
                card._breakdown:SetText(string.format("Weight %.0f · Mod %+.0f · Final %.0f", choice.baseWeight or 0, modifierDelta, choice.score or 0))
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(frame, "SessionHistory.ExportDialog")
    end
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(edit, "SessionHistory.ExportDialogText")
    end
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)
    scroll:SetScrollChild(edit)
    local bar = Theme.CreateScrollBar(frame)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 18, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 18, 2)
    bar:SetValueStep(18)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    Theme.BindScrollWheel(scroll, bar, 18, edit)
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
    lines[#lines + 1] = string.format("Run: Level %d | Duration: %s | Soul Ashes: %s | Events: %d", RunDisplayLevel(session), FormatDuration(session.startTime, RunDisplayEndTime(session)), session.soulAshes or 0, #(session.logs or {}))
    lines[#lines + 1] = string.format("Started: %s | Status: %s", FormatRunDate(session.startTime), RunStatusLabel(session))
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
    wrap:SetSize(FILTER_SEARCH_W, FILTER_CONTROL_H)
    Theme.ApplyInput(wrap)
    local edit = CreateFrame("EditBox", nil, wrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(edit, "SessionHistory.ImportField")
    end
    edit:SetPoint("TOPLEFT", wrap, "TOPLEFT", 8, -2)
    edit:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -25, 2)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetAutoFocus(false)
    edit:SetTextColor(1, 1, 1, 1)
    Theme.WireEditBox(edit, wrap)
    local placeholder = wrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
    placeholder:SetPoint("RIGHT", edit, "RIGHT", -2, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText("Search Echoes, actions, reasons")
    placeholder:SetTextColor(unpack(Theme.TEXT_MUTED))
    local clear = CreateFrame("Button", nil, wrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(clear, "SessionHistory.ImportFieldClear")
    end
    clear:SetSize(20, 20)
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(button, "SessionHistory.HeaderButton")
    end
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
        if Theme.BindHoverReset then Theme.BindHoverReset(button, UpdateHeaderVisuals) end
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

    runDropdown = Theme.CreateButton(topPanel)
    runDropdown:SetPoint("TOPLEFT", previousRunButton, "TOPRIGHT", 6, 0)
    runDropdown:SetPoint("TOPRIGHT", nextRunButton, "TOPLEFT", -6, 0)
    runDropdown:SetHeight(38)
    runDropdown:SetText("Choose a run")
    local runLabel = runDropdown:GetFontString()
    if runLabel then
        runLabel:ClearAllPoints()
        runLabel:SetPoint("LEFT", runDropdown, "LEFT", 10, 0)
        runLabel:SetPoint("RIGHT", runDropdown, "RIGHT", -26, 0)
        runLabel:SetJustifyH("LEFT")
    end
    local runCaret = runDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    runCaret:SetPoint("RIGHT", runDropdown, "RIGHT", -9, 0)
    runCaret:SetText("v")
    runCaret:SetTextColor(unpack(Theme.TEXT_MUTED))
    runDropdown:SetScript("OnClick", ToggleRunBrowser)
    Theme.AttachTooltip(runDropdown, "Select a recorded run", "Opens a compact searchable browser. Only eight reusable rows are created regardless of history size.")

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
        card:SetPoint("TOPLEFT", summaryStrip, "TOPLEFT", 7 + (i - 1) * 126, -5)
        summaryMetrics[def[1]] = card
    end

    summaryRarityFrame = CreateFrame("Frame", nil, summaryStrip)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(summaryRarityFrame, "SessionHistory.SummaryRarityFrame")
    end
    summaryRarityFrame:SetPoint("BOTTOMLEFT", summaryStrip, "BOTTOMLEFT", 8, 4)
    summaryRarityFrame:SetPoint("BOTTOMRIGHT", summaryStrip, "BOTTOMRIGHT", -8, 4)
    summaryRarityFrame:SetHeight(18)
    summaryRarityFrame:EnableMouse(true)

    summaryRarityText = summaryRarityFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryRarityText:SetPoint("LEFT", summaryRarityFrame, "LEFT", 0, 0)
    summaryRarityText:SetPoint("RIGHT", summaryRarityFrame, "RIGHT", 0, 0)
    summaryRarityText:SetJustifyH("LEFT")
    summaryRarityText:SetTextColor(unpack(Theme.TEXT_MUTED))
    summaryRarityText:SetText("Selected Echo quality: no selections recorded")

    summaryRarityFrame:SetScript("OnEnter", function(self)
        local quality = self._qualitySummary
        if not quality then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Selected Echo quality", 1, 0.82, 0)
        GameTooltip:AddLine("Counts include successfully selected Echoes only. Offered, banished, frozen-only, and rerolled Echoes are excluded.", 0.78, 0.78, 0.82, true)
        if quality.totalSelectionCount > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Epic %d · Rare %d · Uncommon %d · Common %d", quality.counts[3] or 0, quality.counts[2] or 0, quality.counts[1] or 0, quality.counts[0] or 0), 0.86, 0.86, 0.90)
            if quality.classifiedSelectionCount < quality.totalSelectionCount then
                GameTooltip:AddLine(string.format("%d of %d selections could be classified by quality.", quality.classifiedSelectionCount, quality.totalSelectionCount), 1, 0.66, 0.16, true)
            end
        end
        GameTooltip:Show()
    end)
    summaryRarityFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildFilterToolbar(container)
    bottomPanel = CreateFrame("Frame", nil, container)
    bottomPanel:SetPoint("TOPLEFT", summaryStrip, "BOTTOMLEFT", 0, -5)
    bottomPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 2)

    toolbar = CreateFrame("Frame", nil, bottomPanel)
    toolbar:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(FILTER_TOOLBAR_H)

    local search = CreateSearch(toolbar)
    search:SetPoint("LEFT", toolbar, "LEFT", 0, 0)

    actionDropdown = Theme.CreateDropdown(toolbar, FILTER_ACTION_W, "All actions")
    actionDropdown:SetHeight(FILTER_CONTROL_H)
    actionDropdown:SetPoint("LEFT", search, "RIGHT", FILTER_GAP, 0)
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

    sourceDropdown = Theme.CreateDropdown(toolbar, FILTER_SOURCE_W, "All sources")
    sourceDropdown:SetHeight(FILTER_CONTROL_H)
    sourceDropdown:SetPoint("LEFT", actionDropdown, "RIGHT", FILTER_GAP, 0)
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
    importantButton:SetSize(FILTER_IMPORTANT_W, FILTER_CONTROL_H)
    importantButton:SetPoint("LEFT", sourceDropdown, "RIGHT", FILTER_GAP, 0)
    importantButton:SetScript("OnClick", function()
        importantOnly = not importantOnly
        H.UpdateFilterVisuals()
        H.RefreshLogView()
    end)
    Theme.AttachTooltip(importantButton, "Important decisions", "Shows close comparisons, final-charge actions, modifier overrides, failures, and meaningful manual disagreements.")

    groupButton = Theme.CreateTab(toolbar, "Group by level")
    groupButton:SetSize(FILTER_GROUP_W, FILTER_CONTROL_H)
    groupButton:SetPoint("LEFT", importantButton, "RIGHT", FILTER_GAP, 0)
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(logScroll, "SessionHistory.LogScroll")
    end
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
    detailFlags:SetHeight(28)
    detailFlags:SetJustifyH("LEFT")
    detailFlags:SetJustifyV("TOP")
    detailFlags:SetTextColor(unpack(Theme.WARNING))

    detailResources = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailResources:SetPoint("TOPLEFT", detailFlags, "TOPRIGHT", 15, 0)
    detailResources:SetPoint("RIGHT", detailPanel, "RIGHT", -12, 0)
    detailResources:SetHeight(28)
    detailResources:SetJustifyH("RIGHT")
    detailResources:SetJustifyV("TOP")
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

local function DurationTick()
    local session = SelectedSession()
    if not visible or not session or GetRunCompletionState(session) ~= "active" then return false end
    RefreshRunNavigatorText()
    UpdateSummary(session)
    return 1
end

function H.Show(container)
    local buildKey = ActiveBuildKey()
    if lastBuildKey and lastBuildKey ~= buildKey and not pendingFilters then
        selectedSessionId = nil
        selectedEntry = nil
        searchText = ""
        importantOnly = false
        if searchInput then searchInput:SetText("") end
        runBrowserSearchText = ""
        runBrowserFilter = "all"
        if runBrowserSearch then runBrowserSearch:SetText("") end
        CloseRunBrowser()
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
    if session and GetRunCompletionState(session) == "active" then
        EbonBuilds.Scheduler.Every("sessionHistory.duration", 1, DurationTick,
            EbonBuilds.Scheduler.INTERACTIVE, true, "SessionHistory")
    else
        EbonBuilds.Scheduler.Cancel("sessionHistory.duration")
    end
end

function H.Hide()
    visible = false
    if topPanel then topPanel:Hide() end
    if summaryStrip then summaryStrip:Hide() end
    if bottomPanel then bottomPanel:Hide() end
    if detailPanel then detailPanel:Hide() end
    if exportDialog then exportDialog:Hide() end
    CloseRunBrowser()
    EbonBuilds.Scheduler.Cancel("sessionHistory.duration")
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
H._RunIsShort = RunIsShort
H._RunIsRecent = RunIsRecent
H._GetRunCompletionState = GetRunCompletionState
H._RunDisplayLevel = RunDisplayLevel
H._RunQualitySummary = RunQualitySummary
H._ResourceDisplayText = ResourceDisplayText
H._QualityCountText = QualityCountText
H._RunBrowserSearchBlob = RunBrowserSearchBlob
H._EnsureRunBrowserForTest = EnsureRunBrowser
H._GetRunBrowserRowCountForTest = function() return #runBrowserRows end
H._GetRunBrowserResultCountForTest = function() return #runBrowserResults end
H._SetRunBrowserFilterForTest = function(filter, search)
    runBrowserFilter = filter or "all"
    runBrowserSearchText = search or ""
    H.RefreshRunBrowser(false)
end
H._UIBuildFunctions = {
    BuildRunNavigator = BuildRunNavigator,
    BuildSummaryStrip = BuildSummaryStrip,
    BuildFilterToolbar = BuildFilterToolbar,
    BuildEventTimeline = BuildEventTimeline,
    BuildDecisionInspector = BuildDecisionInspector,
    BuildUI = BuildUI,
}
