local addonName, EbonBuilds = ...

-- EbonBuilds: modules/analytics/SessionHistoryData.lua
-- Responsibility: pure data derivation for the Session History logbook --
-- policy evidence, run quality/rarity, filter matching, searchable text,
-- resource deltas, and run-browser indexing. No frames, no rendering.
-- Split out of modules/ui/SessionHistory.lua (issue #19).

EbonBuilds.SessionHistoryData = {}
local Data = EbonBuilds.SessionHistoryData

local runQualityCache = {}
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

-- Freeze-first withholds an Echo frozen on the current board from Select.
-- Carried/frozen Echoes from earlier boards remain legal picks.
function PolicyEvidence.IsSelectable(choice, entry)
    if not PolicyEvidence.IsEligible(choice, entry) then return false end
    if choice and choice.frozenThisBoard then return false end
    return true
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

local function BestAlternative(entry, eligibleOnly, selectableOnly)
    local target, targetArrayIndex = TargetChoice(entry)
    local best
    for arrayIndex, choice in ipairs((entry and entry.choices) or {}) do
        if choice ~= target and arrayIndex ~= targetArrayIndex then
            local allowed = true
            if selectableOnly then
                allowed = PolicyEvidence.IsSelectable(choice, entry)
            elseif eligibleOnly then
                allowed = PolicyEvidence.IsEligible(choice, entry)
            end
            if allowed then
                if not best or (tonumber(choice.score) or 0) > (tonumber(best.score) or 0) then best = choice end
            end
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
        local targetScore = tonumber(target.score) or 0
        -- Only claim "below threshold" when the recorded score is actually below
        -- the applied threshold. Legacy rows can store an unpaced peak%% value
        -- that disagrees with ChargePacing / cached peak used at decision time.
        if threshold and targetScore < threshold then
            return string.format("%.0f below threshold %.0f", targetScore, threshold)
        end
        if threshold then
            return string.format("Removed low-value Echo (%.0f; recorded threshold %.0f)", targetScore, threshold)
        end
        return reason or "Removed the chosen low-value Echo"
    elseif action == "Reroll" then
        if alternative then return string.format("Best eligible current option: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0) end
        if ineligible then
            return string.format("No eligible current option; %s at %.0f was ineligible under the %s",
                ineligible.name or "Echo", tonumber(ineligible.score) or 0, PolicyEvidence.RuleLabel(ineligible))
        end
        return reason or "Replaced the current offer"
    elseif action == "Freeze" and target then
        local freezeScore = tonumber(target.score) or 0
        if threshold and freezeScore >= threshold then
            return string.format("%.0f exceeded threshold %.0f", freezeScore, threshold)
        end
        if threshold then
            return string.format("%.0f preserved (locked/priority; threshold %.0f)", freezeScore, threshold)
        end
        return reason or "Preserved a strong Echo for later"
    elseif (action == "Select" or action == "Manual") and target then
        local targetScore = tonumber(target.score) or 0
        -- Prefer selectable alternatives so freeze-first picks do not look like
        -- Autopilot selected a worse Echo while the higher one was withheld.
        local selectable = BestAlternative(entry, true, true)
        if selectable and (tonumber(selectable.score) or 0) > targetScore then
            return string.format("Higher eligible option: %s at %.0f", selectable.name or "Echo", tonumber(selectable.score) or 0)
        end
        if ineligible and (tonumber(ineligible.score) or 0) > targetScore then
            return string.format("Highest eligible; %s at %.0f was ineligible under the %s",
                ineligible.name or "Echo", tonumber(ineligible.score) or 0, PolicyEvidence.RuleLabel(ineligible))
        end
        if alternative and alternative.frozenThisBoard and (tonumber(alternative.score) or 0) > targetScore then
            return string.format("Next eligible; %s at %.0f was frozen this board",
                alternative.name or "Echo", tonumber(alternative.score) or 0)
        end
        if selectable then
            return string.format("Next eligible: %s at %.0f", selectable.name or "Echo", tonumber(selectable.score) or 0)
        end
        if alternative and not alternative.frozenThisBoard then
            return string.format("Next eligible: %s at %.0f", alternative.name or "Echo", tonumber(alternative.score) or 0)
        end
        if alternative and alternative.frozenThisBoard then
            return string.format("Next eligible; %s at %.0f was frozen this board",
                alternative.name or "Echo", tonumber(alternative.score) or 0)
        end
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

function Data.EntryMatches(entry, filters)
    filters = filters or {}
    filters.actionFilter = filters.actionFilter or "All"
    filters.sourceFilter = filters.sourceFilter or "All"
    filters.searchText = filters.searchText or ""
    filters.sortColumn = filters.sortColumn or "time"
    if filters.sortAscending == nil then filters.sortAscending = true end
    if not entry then return false end
    if filters.actionFilter ~= "All" and NormalizeAction(entry.action) ~= filters.actionFilter then return false end
    if filters.sourceFilter ~= "All" and DecisionSource(entry) ~= filters.sourceFilter then return false end
    if filters.importantOnly and not IsImportant(entry) then return false end
    if filters.searchText == "" then return true end
    return SearchableText(entry):find(SearchSafeLower(filters.searchText), 1, true) ~= nil
end

local function SortValue(wrapper, column, filters)
    local entry = wrapper.entry
    if column == "time" then return tonumber(entry.timestamp) or 0 end
    if column == "action" then return string.lower(NormalizeAction(entry.action)) end
    if column == "subject" then
        local name = DecisionLabel(entry)
        return SearchSafeLower(VisibleEchoName(name))
    end
    return wrapper.index or 0
end

local function CompareWrappers(left, right, filters)
    local leftValue = SortValue(left, filters.sortColumn, filters)
    local rightValue = SortValue(right, filters.sortColumn, filters)
    if leftValue ~= rightValue then
        if filters.sortAscending then return leftValue < rightValue end
        return leftValue > rightValue
    end
    local leftTime, rightTime = tonumber(left.entry.timestamp) or 0, tonumber(right.entry.timestamp) or 0
    if leftTime ~= rightTime then return leftTime < rightTime end
    return (left.index or 0) < (right.index or 0)
end

function Data.VisibleItems(logs, filters)
    filters = filters or {}
    filters.actionFilter = filters.actionFilter or "All"
    filters.sourceFilter = filters.sourceFilter or "All"
    filters.searchText = filters.searchText or ""
    filters.sortColumn = filters.sortColumn or "time"
    if filters.sortAscending == nil then filters.sortAscending = true end
    if filters.groupByLevel == nil then filters.groupByLevel = false end
    if filters.importantOnly == nil then filters.importantOnly = false end
    local filtered = {}
    for index, entry in ipairs(logs or {}) do
        if Data.EntryMatches(entry, filters) then filtered[#filtered + 1] = { entry = entry, index = index } end
    end

    if not filters.groupByLevel then
        table.sort(filtered, function(a, b) return CompareWrappers(a, b, filters) end)
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
        table.sort(bucket.entries, function(a, b) return CompareWrappers(a, b, filters) end)
        items[#items + 1] = { type = "level", level = bucket.level }
        for _, wrapper in ipairs(bucket.entries) do
            items[#items + 1] = { type = "event", entry = wrapper.entry, sourceIndex = wrapper.index }
        end
    end
    return items, #filtered
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
    local dpsText = EbonBuilds.DpsLog and EbonBuilds.DpsLog.FormatBestSample
        and EbonBuilds.DpsLog.FormatBestSample(session, true) or ""
    if dpsText ~= "" then fields[#fields + 1] = dpsText end
    return SearchSafeLower(table.concat(fields, " "))
end
local DEFAULT_WHEEL_STEP = 34

local function NextWheelScrollValue(currentValue, delta, minimum, maximum, step)
    currentValue = tonumber(currentValue) or 0
    delta = tonumber(delta) or 0
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or minimum
    step = math.max(1, tonumber(step) or DEFAULT_WHEEL_STEP)

    if maximum < minimum then maximum = minimum end
    return math.max(minimum, math.min(maximum, currentValue - delta * step))
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

function Data.SessionMatchesBuild(session, build)
    if not session then return false end
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

Data.PolicyEvidence = PolicyEvidence
Data.FormatDuration = FormatDuration
Data.FormatTimestamp = FormatTimestamp
Data.FormatRunDate = FormatRunDate
Data.NormalizeAction = NormalizeAction
Data.DecisionSource = DecisionSource
Data.TargetChoice = TargetChoice
Data.IsImportant = IsImportant
Data.ReasonSentence = ReasonSentence
Data.DecisionLabel = DecisionLabel
Data.GetRunCompletionState = GetRunCompletionState
Data.RunDisplayEndTime = RunDisplayEndTime
Data.RunStatusLabel = RunStatusLabel
Data.RunQualitySummary = RunQualitySummary
Data.RunDisplayLevel = RunDisplayLevel
Data.QualityCountText = QualityCountText
Data.SessionSummary = SessionSummary
Data.RunIsShort = RunIsShort
Data.RunIsRecent = RunIsRecent
Data.RunBrowserSearchBlob = RunBrowserSearchBlob
Data.RunRelativeDate = RunRelativeDate
Data.ResourceChangeSummary = ResourceChangeSummary
Data.ResourceDisplayText = ResourceDisplayText
Data.NextWheelScrollValue = NextWheelScrollValue
Data.VisibleEchoName = VisibleEchoName
Data.SearchSafeLower = SearchSafeLower
Data.InvalidateRunQualityCache = function()
    wipe(runQualityCache)
end

