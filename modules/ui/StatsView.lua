local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/StatsView.lua
-- Connected analytics workspace for the Build Overview Stats tab.
-- Stats identifies patterns; SessionHistory provides the supporting evidence.

EbonBuilds.StatsView = {}

local View = EbonBuilds.StatsView
local Theme = EbonBuilds.Theme

-- Pure data layer, split out to modules/analytics/StatsData.lua (issue #19).
-- Local aliases keep every existing call site and test hook unchanged.
local Data = EbonBuilds.StatsData
local recentRecommendationByBuild = Data.recentRecommendationByBuild
local Round, NormalizeAction, SessionMatchesBuild, SessionMetrics, NewSessionMetrics, AggregateSessionMetrics, TargetChoice, NewActionBucket, NewActionAnalytics, BuildActionAnalytics, EarlyEpicObservation, BuildEarlyEpicStats, EarlySampleLabel, VisibleEchoName, LowerVisibleEchoName, WeightedCoverage, ConfidenceLabel, BuildEchoRows, ClampWeight, ResolveRecommendationRef, RecommendationDismissalStore, BuildRecommendations, CacheSignature, GenerateCache =
      Data.Round, Data.NormalizeAction, Data.SessionMatchesBuild, Data.SessionMetrics, Data.NewSessionMetrics, Data.AggregateSessionMetrics, Data.TargetChoice, Data.NewActionBucket, Data.NewActionAnalytics, Data.BuildActionAnalytics, Data.EarlyEpicObservation, Data.BuildEarlyEpicStats, Data.EarlySampleLabel, Data.VisibleEchoName, Data.LowerVisibleEchoName, Data.WeightedCoverage, Data.ConfidenceLabel, Data.BuildEchoRows, Data.ClampWeight, Data.ResolveRecommendationRef, Data.RecommendationDismissalStore, Data.BuildRecommendations, Data.CacheSignature, Data.GenerateCache
local QUALITY_ORDER = EbonBuilds.Quality.ORDER or { 3, 2, 1, 0 }

local root, activeBuild
local viewTabs, viewPanels = {}, {}
local activeView = "summary"
local summaryCards, summaryText = {}, {}
local earlyEpicCards = {}
local echoRows, echoHeaderButtons = {}, {}
local echoScroll, echoChild, echoBar, echoEmpty, echoCountText
local lastEchoRenderCount = 0
local actionCards, actionDistributionRows = {}, {}
local actionScopeText, actionCoverageText, actionSignalText, actionInsightText
local recommendationRows, recScroll, recChild, recBar, recEmpty = {}, nil, nil, nil, nil
local recHeader, recScopeText
local recommendationSection = "echo"
local recommendationSectionInitialized = false
local recommendationSectionButtons = {}
local recommendationFilters = { echo = "all", logic = "all" }
local recommendationFilterButtons = { echo = {}, logic = {} }
local statsCache
local cacheByBuildId = {}
local renderedTokens = {}
local echoSortRevision = 0
local echoSort = { key = "score", desc = true }
local echoSortLoaded = false

-- Thin wrapper: the data layer takes cache/build explicitly; the view owns
-- which ones are current.
local function EnsureRecommendations()
    return Data.EnsureRecommendations(statsCache, activeBuild)
end

-- Column metadata is shared by the header, comparator, default direction,
-- and test hooks. Keeping this in one place prevents a displayed column from
-- silently using a different sort key or default direction.
local ECHO_COLUMNS = {
    { key = "name",       label = "Echo",          x = 6,   w = 180, valueType = "string", defaultDesc = false },
    { key = "weight",     label = "Priority",      x = 194, w = 58,  valueType = "number", defaultDesc = true  },
    { key = "score",      label = "Final score",   x = 256, w = 60,  valueType = "number", defaultDesc = true  },
    { key = "appearance", label = "Appearance",    x = 318, w = 82,  valueType = "number", defaultDesc = true  },
    { key = "picks",      label = "Pick share",    x = 402, w = 76,  valueType = "number", defaultDesc = true  },
    { key = "dps",        label = "Avg DPS",       x = 480, w = 92,  valueType = "number", defaultDesc = true  },
    { key = "samples",    label = "Signal / data", x = 574, w = 96,  valueType = "number", defaultDesc = true  },
}
for _, column in ipairs(ECHO_COLUMNS) do
    column._baseX = column.x
    column._baseW = column.w
end
local ECHO_COLUMN_BY_KEY = {}
for _, column in ipairs(ECHO_COLUMNS) do ECHO_COLUMN_BY_KEY[column.key] = column end

local VIEW_ORDER = {
    { key = "summary", label = "Summary" },
    { key = "echoes", label = "Echoes" },
    { key = "actions", label = "Actions" },
    { key = "recommendations", label = "Recommendations" },
}

local ACTION_KEYS = Data.ACTION_KEYS
local ACTION_COLORS = {
    Select = { 0.30, 0.86, 0.38 },
    Banish = { 1.00, 0.32, 0.32 },
    Reroll = { 0.30, 0.62, 1.00 },
    Freeze = { 0.30, 0.82, 1.00 },
}

local function LoadEchoSort()
    if echoSortLoaded then return end
    -- SavedVariables are available before ADDON_LOADED in-game, but keeping
    -- this guard makes early test or integration mounts recover correctly.
    if not EbonBuildsDB then return end
    echoSortLoaded = true
    local globalSettings = EbonBuildsDB.globalSettings
    local saved = globalSettings and globalSettings.statsEchoSort
    if type(saved) == "table" and ECHO_COLUMN_BY_KEY[saved.key] then
        echoSort.key = saved.key
        echoSort.desc = saved.desc and true or false
    end
end

local function SaveEchoSort()
    if not EbonBuildsDB then return end
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.statsEchoSort = {
        key = echoSort.key,
        desc = echoSort.desc and true or false,
    }
end

local function DeltaText(value, previous, suffix)
    if not previous or previous == 0 then return "No comparable previous run" end
    local delta = value - previous
    if math.abs(delta) < 0.05 then return "No change vs previous run" end
    return string.format("%s%.1f%s vs previous", delta > 0 and "+" or "", delta, suffix or "")
end

local function MetricColor(kind)
    return kind == "success" and Theme.SUCCESS
        or kind == "warning" and Theme.WARNING
        or kind == "danger" and Theme.DANGER
        or Theme.TEXT_PRIMARY
end

local function SetSummaryMetric(card, value, description, evidence, kind)
    card.value:SetText(value or "—")
    card.description:SetText(description or "")
    card.evidence:SetText(evidence or "")
    card.value:SetTextColor(unpack(MetricColor(kind)))
end

local function TopEntry(counts)
    local bestName, bestCount
    for name, count in pairs(counts or {}) do
        if not bestCount or (tonumber(count) or 0) > bestCount then bestName, bestCount = name, tonumber(count) or 0 end
    end
    local visible = bestName and VisibleEchoName(bestName) or nil
    return visible and visible ~= "" and string.format("%s (%d)", visible, bestCount) or "—"
end

local function RefreshEarlyEpicCards()
    for level = 1, 3 do
        local card = earlyEpicCards[level]
        local data = statsCache.earlyEpic and statsCache.earlyEpic[level] or { seen = 0, tracked = 0, pct = 0, inferred = 0 }
        if card then
            local sampleLabel, sampleKind = EarlySampleLabel(data.tracked)
            card.sample:SetText(sampleLabel)
            card.sample:SetTextColor(unpack(MetricColor(sampleKind)))
            if (data.tracked or 0) > 0 then
                card.value:SetText(tostring(data.seen or 0))
                card.detail:SetText(string.format("of %d tracked run%s", data.tracked, data.tracked == 1 and "" or "s"))
                card.rate:SetText(string.format("%.1f%% saw an Epic", data.pct or 0))
            else
                card.value:SetText("—")
                card.detail:SetText("No tracked runs")
                card.rate:SetText("New runs will be counted")
            end
            local inferred = tonumber(data.inferred) or 0
            card._tooltipBody = string.format(
                "Counts a run once when at least one Epic Echo appears in Level %d's original offer. Rerolls, banish replacements, and repeated evaluations are excluded. %d of %d tracked observations were reconstructed from compatible legacy decision logs.",
                level, inferred, data.tracked or 0)
        end
    end
end

local function RefreshSummary()
    if not statsCache then return end
    local latest = statsCache.latest or NewSessionMetrics(nil)
    local aggregate = statsCache.aggregate or latest
    local runCount = statsCache.matchingRunCount or #(statsCache.sessions or {})

    SetSummaryMetric(
        summaryCards.score,
        string.format("%.1f", aggregate.averageSelected or 0),
        "Mean selected Echo score",
        string.format("%d selection%s across %d run%s", aggregate.selectedCount or 0, (aggregate.selectedCount or 0) == 1 and "" or "s", runCount, runCount == 1 and "" or "s"))
    SetSummaryMetric(
        summaryCards.resources,
        string.format("%.2f", aggregate.resourcePerLevel or 0),
        "Banish, reroll and freeze use",
        string.format("%d charges across %d tracked levels", aggregate.resourceTotal or 0, aggregate.levels or 0))
    SetSummaryMetric(
        summaryCards.coverage,
        string.format("%d / %d", statsCache.weightedLearned or 0, statsCache.weightedTotal or 0),
        "Weighted Echoes already learned",
        string.format("%.0f%% of configured priorities", statsCache.coveragePct or 0),
        (statsCache.coveragePct or 0) >= 80 and "success" or (statsCache.coveragePct or 0) >= 50 and "warning" or nil)
    SetSummaryMetric(
        summaryCards.confidence,
        statsCache.confidence or "Low",
        "Evidence for recommendations",
        string.format("%d useful personal sample%s", statsCache.usefulSamples or 0, (statsCache.usefulSamples or 0) == 1 and "" or "s"),
        statsCache.confidenceKind)

    if summaryText.scope then
        summaryText.scope:SetText(string.format("Based on %d matching run%s  ·  %d recorded decision%s",
            runCount, runCount == 1 and "" or "s",
            statsCache.decisionCount or 0, (statsCache.decisionCount or 0) == 1 and "" or "s"))
    end

    RefreshEarlyEpicCards()

    if statsCache.sessions and statsCache.sessions[1] then
        summaryText.run:SetText(string.format("Latest matching run: Level %d  ·  %d decisions", latest.maxLevel or 1, latest.events or 0))
        if (latest.selectedCount or 0) > 0 and (aggregate.selectedCount or 0) > 0 then
            local difference = (latest.averageSelected or 0) - (aggregate.averageSelected or 0)
            summaryText.comparison:SetText(string.format("Decision value %.1f   Build average %.1f   Difference %s%.1f",
                latest.averageSelected or 0, aggregate.averageSelected or 0, difference > 0 and "+" or "", difference))
        else
            summaryText.comparison:SetText("No selected-Echo score is available for this run yet.")
        end
    else
        summaryText.run:SetText("No matching run data yet")
        summaryText.comparison:SetText("Complete decisions with this build to populate comparisons.")
    end
    summaryText.selected:SetText(string.format("Select %d   Banish %d   Reroll %d   Freeze %d",
        latest.actions.Select or 0, latest.actions.Banish or 0, latest.actions.Reroll or 0, latest.actions.Freeze or 0))
    summaryText.top:SetText(string.format("Most picked: %s    Most banished: %s",
        TopEntry(activeBuild.stats and activeBuild.stats.mostPicked), TopEntry(activeBuild.stats and activeBuild.stats.mostBanned)))
end

local function EchoSortValue(row, key)
    if key == "name" then return row.sortName or LowerVisibleEchoName(row.name) end
    if key == "weight" then return tonumber(row.weight) end
    if key == "score" then return tonumber(row.score) end
    if key == "appearance" then return tonumber(row.appearancePct) end
    if key == "picks" then return tonumber(row.pickShare) end
    if key == "dps" then return tonumber(row.avgDPS) end
    if key == "samples" then return tonumber(row.sampleCount) end
    return nil
end

local function CompareEchoRows(a, b, key, desc)
    local av, bv = EchoSortValue(a, key), EchoSortValue(b, key)
    local aMissing, bMissing = av == nil, bv == nil

    -- Missing analytics always stay at the bottom. Treating missing values as
    -- -1 made them jump to the top in ascending mode and looked like bad data.
    if aMissing ~= bMissing then return not aMissing end

    if not aMissing and av ~= bv then
        -- Do not use the common "desc and a > b or a < b" shortcut here.
        -- When the first comparison is false, Lua evaluates the expression
        -- after `or`, allowing both a<b and b<a to return true in descending
        -- mode. table.sort then receives an invalid comparator.
        if desc then return av > bv end
        return av < bv
    end

    -- table.sort is not stable in Lua 5.1. Deterministic tie breakers stop
    -- equal-value rows from visibly jumping between refreshes.
    local an = a.sortName or LowerVisibleEchoName(a.name)
    local bn = b.sortName or LowerVisibleEchoName(b.name)
    if an ~= bn then return an < bn end

    local aq, bq = tonumber(a.quality) or 0, tonumber(b.quality) or 0
    if aq ~= bq then return aq > bq end
    return false
end

local function SortEchoes(rows, key, desc)
    key = ECHO_COLUMN_BY_KEY[key] and key or "score"
    desc = desc and true or false
    table.sort(rows, function(a, b) return CompareEchoRows(a, b, key, desc) end)
end

local function UpdateEchoHeaders()
    LoadEchoSort()
    for key, button in pairs(echoHeaderButtons) do
        local suffix = echoSort.key == key and (echoSort.desc and "  v" or "  ^") or ""
        button:SetText((button._baseLabel or "") .. suffix)
        Theme.SetTabSelected(button, echoSort.key == key)
    end
end

local function LayoutEchoColumns(width)
    width = math.max(560, tonumber(width) or 0)
    local scale = math.min(1, width / 674)
    for _, def in ipairs(ECHO_COLUMNS) do
        def.x = math.floor(def._baseX * scale + 0.5)
        def.w = math.max(46, math.floor(def._baseW * scale + 0.5))
        local header = echoHeaderButtons[def.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("LEFT", header:GetParent(), "LEFT", def.x, 0)
            header:SetWidth(def.w)
        end
    end
    for _, row in ipairs(echoRows) do
        for _, def in ipairs(ECHO_COLUMNS) do
            local key = def.key == "samples" and "confidence" or def.key
            local label = row._labels and row._labels[key]
            if label then
                label:ClearAllPoints()
                label:SetPoint("LEFT", row, "LEFT", def.x + 4, 0)
                label:SetWidth(math.max(40, def.w - 6))
            end
        end
    end
end

local function ApplyEchoRowBaseStyle(row)
    if row._alternate then
        row:SetBackdropColor(0.105, 0.105, 0.132, 0.985)
    else
        row:SetBackdropColor(unpack(Theme.CARD_BG))
    end
    row:SetBackdropBorderColor(unpack(Theme.BORDER_DIM))
end

local function EnsureEchoRow(index)
    if echoRows[index] then return echoRows[index] end
    local row = CreateFrame("Button", nil, echoChild)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "StatsView.EchoRow")
    end
    row:SetHeight(34)
    Theme.ApplyCard(row)
    row:RegisterForClicks("LeftButtonUp")

    local stripe = row:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    stripe:SetWidth(3)
    row._stripe = stripe

    row._labels = {}
    for _, def in ipairs(ECHO_COLUMNS) do
        local key = def.key == "samples" and "confidence" or def.key
        local align = (key == "name" or key == "confidence") and "LEFT" or "RIGHT"
        local fs = row:CreateFontString(nil, "OVERLAY", key == "name" and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", def.x + 4, 0)
        fs:SetWidth(math.max(40, def.w - 6))
        fs:SetJustifyH(align)
        row._labels[key] = fs
    end
    row:SetScript("OnClick", function(self)
        if self._data and EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OpenWithFilters then
            EbonBuilds.SessionHistory.OpenWithFilters({ echoName = self._data.name })
        end
    end)
    row:SetScript("OnEnter", function(self)
        Theme.SetCardHovered(self, true)
        if self._data then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._data.name, 1, 0.82, 0)
            GameTooltip:AddLine("Click to inspect matching Logbook decisions.", 0.82, 0.82, 0.86, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        ApplyEchoRowBaseStyle(self)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(row, function(self)
            ApplyEchoRowBaseStyle(self)
            GameTooltip:Hide()
        end)
    end
    if echoScroll and echoBar then Theme.BindScrollWheel(echoScroll, echoBar, 36, row) end
    echoRows[index] = row
    return row
end

local function RefreshEchoes()
    if not statsCache or not echoChild or not echoScroll or not echoBar then return end
    LoadEchoSort()

    local rows = {}
    for i, row in ipairs(statsCache.echoes or {}) do rows[i] = row end
    SortEchoes(rows, echoSort.key, echoSort.desc)
    UpdateEchoHeaders()

    local y = 0
    for i, data in ipairs(rows) do
        local row = EnsureEchoRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", echoChild, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", echoChild, "RIGHT", -4, 0)
        row._data = data
        row._alternate = i % 2 == 0
        ApplyEchoRowBaseStyle(row)

        local qr, qg, qb = EbonBuilds.Quality.GetRGB(data.quality)
        row._stripe:SetVertexColor(qr, qg, qb, 0.9)
        row._labels.name:SetText(EbonBuilds.Quality.Colorize(data.name or "Unknown Echo", data.quality))
        row._labels.weight:SetText(tostring(Round(data.weight)))
        row._labels.score:SetText(tostring(Round(data.score)))
        row._labels.appearance:SetText(data.appearancePct and string.format("%.1f%%", data.appearancePct) or "—")
        row._labels.picks:SetText(string.format("%.1f%%", data.pickShare or 0))
        row._labels.dps:SetText(data.avgDPS and string.format("%.0f", data.avgDPS) or "—")
        local confidence = ConfidenceLabel(math.max(data.personalCount or 0, data.recommendation and data.recommendation.count or 0))
        local signal = data.recommendation and (data.recommendation.direction == "raise" and "UP " or "DOWN ") or ""
        row._labels.confidence:SetText(string.format("%s%s P%d C%d", signal, confidence, data.personalCount or 0, data.communityCount or 0))
        row:Show()
        y = y + 36
    end

    for i = #rows + 1, #echoRows do echoRows[i]:Hide() end
    echoChild:SetHeight(math.max(1, y))

    local maxScroll = math.max(0, y - (echoScroll:GetHeight() or 0))
    echoBar:SetMinMaxValues(0, maxScroll)
    if echoBar:GetValue() > maxScroll then echoBar:SetValue(maxScroll) end

    lastEchoRenderCount = #rows
    if echoCountText then
        echoCountText:SetText(string.format("%d weighted Echo%s", #rows, #rows == 1 and "" or "es"))
    end
    if #rows == 0 then echoEmpty:Show() else echoEmpty:Hide() end
end

local ACTION_SCORE_LABELS = {
    Select = "Average selected value",
    Banish = "Average target value",
    Reroll = "Average best offer value",
    Freeze = "Average frozen value",
}

local ACTION_SUBJECT_DESCRIPTIONS = {
    Select = "the selected Echo",
    Banish = "the banished Echo",
    Reroll = "the highest-quality Echo in the rejected offer",
    Freeze = "the frozen Echo",
}

local function ActionInsightText(analytics)
    local lines = {}
    local selectBucket = analytics.actions.Select or NewActionBucket()
    local banishBucket = analytics.actions.Banish or NewActionBucket()

    if (selectBucket.rankTracked or 0) >= 5 then
        lines[#lines + 1] = string.format("- %.0f%% of tracked selections chose a highest-value option (%d decisions).",
            selectBucket.rankHitPct or 0, selectBucket.rankTracked or 0)
    end
    if (banishBucket.rankTracked or 0) >= 5 then
        lines[#lines + 1] = string.format("- %.0f%% of tracked banishes targeted a lowest-value option (%d decisions).",
            banishBucket.rankHitPct or 0, banishBucket.rankTracked or 0)
    end
    if (analytics.rerollPairs or 0) >= 5 and analytics.rerollAverageImprovement ~= nil then
        lines[#lines + 1] = string.format("- Rerolls changed the best available value by %s%.1f on average (%d paired boards).",
            analytics.rerollAverageImprovement > 0 and "+" or "",
            analytics.rerollAverageImprovement, analytics.rerollPairs)
    end
    if #lines == 0 then
        return "More complete decisions are needed to identify reliable action patterns. Rankings appear after at least 5 comparable decisions."
    end
    return table.concat(lines, "\n")
end

local function RefreshActionDistributionRow(action, bucket)
    local row = actionDistributionRows[action]
    if not row then return end
    local tracked = tonumber(bucket.qualityTracked) or 0
    local total = tonumber(bucket.count) or 0
    row.count:SetText(tostring(total))
    row.coverage:SetText(string.format("%d / %d", tracked, total))

    local barWidth = row._barWidth or 350
    local cursor, visibleSegments = 0, 0
    for index, quality in ipairs(QUALITY_ORDER) do
        local segment = row.segments[quality]
        local count = (bucket.qualities and tonumber(bucket.qualities[quality])) or 0
        if tracked > 0 and count > 0 then
            visibleSegments = visibleSegments + 1
            local width
            if index == #QUALITY_ORDER then
                width = math.max(1, barWidth - cursor)
            else
                width = math.max(1, math.floor(barWidth * count / tracked + 0.5))
                width = math.min(width, math.max(1, barWidth - cursor))
            end
            segment:ClearAllPoints()
            segment:SetPoint("LEFT", row.bar, "LEFT", cursor, 0)
            segment:SetWidth(width)
            segment:Show()
            cursor = cursor + width
            local qualityLabel = EbonBuilds.Quality.LABELS[quality] or tostring(quality)
            segment._tooltipTitle = qualityLabel .. " · " .. action
            segment._tooltipBody = string.format(
                "%d action%s · %.1f%% of quality-tracked %s actions. Quality describes %s.",
                count, count == 1 and "" or "s", count / tracked * 100,
                string.lower(action), ACTION_SUBJECT_DESCRIPTIONS[action] or "the action subject")
        else
            segment:Hide()
        end
    end
    if tracked == 0 then row.noData:Show() else row.noData:Hide() end
    row._tooltipBody = string.format(
        "%d of %d %s action%s include usable official quality data. Missing quality is excluded from the distribution rather than counted as Common.",
        tracked, total, string.lower(action), total == 1 and "" or "s")
end

local function RefreshActions()
    if not statsCache then return end
    local analytics = statsCache.actionAnalytics or NewActionAnalytics()
    local aggregate = statsCache.aggregate or NewSessionMetrics(nil)
    local runCount = analytics.matchingRuns or statsCache.matchingRunCount or 0

    if actionScopeText then
        if (analytics.total or 0) == 0 and (analytics.manualSelections or 0) == 0 then
            actionScopeText:SetText("No action statistics have been recorded for this build yet.")
        else
            actionScopeText:SetText(string.format(
                "How Select, Banish, Reroll and Freeze were used across %d matching run%s.",
                runCount, runCount == 1 and "" or "s"))
        end
    end
    if actionCoverageText then
        if (analytics.total or 0) == 0 and (analytics.manualSelections or 0) == 0 then
            actionCoverageText:SetText("Complete decisions with this build to populate action and quality analytics.")
        else
            local manualText = (analytics.manualSelections or 0) > 0
                and string.format("  ·  %d Manual Training selection%s recorded separately",
                    analytics.manualSelections, analytics.manualSelections == 1 and "" or "s") or ""
            actionCoverageText:SetText(string.format(
                "%d automated action%s  ·  %d include quality data (%.0f%%)%s",
                analytics.total or 0, (analytics.total or 0) == 1 and "" or "s",
                analytics.qualityTracked or 0, analytics.qualityCoveragePct or 0, manualText))
        end
    end

    for _, action in ipairs(ACTION_KEYS) do
        local card = actionCards[action]
        local bucket = analytics.actions[action] or NewActionBucket()
        if card then
            card.value:SetText(tostring(bucket.count or 0))
            card.share:SetText(string.format("%.0f%% of automated actions", bucket.sharePct or 0))
            if bucket.averageScore ~= nil then
                card.metric:SetText(string.format("%s: %.1f", ACTION_SCORE_LABELS[action], bucket.averageScore))
            else
                card.metric:SetText((ACTION_SCORE_LABELS[action] or "Average value") .. ": —")
            end
            card.coverage:SetText(string.format("Quality tracked: %d / %d", bucket.qualityTracked or 0, bucket.count or 0))
            card._tooltipTitle = action .. " action statistics"
            card._tooltipBody = string.format(
                "%d recorded %s action%s (%.1f%% of automated actions). The quality distribution uses %s. %d records include usable quality and %d include a comparable score. Click to inspect matching Logbook events.",
                bucket.count or 0, string.lower(action), (bucket.count or 0) == 1 and "" or "s",
                bucket.sharePct or 0, ACTION_SUBJECT_DESCRIPTIONS[action] or "the action subject",
                bucket.qualityTracked or 0, bucket.scoreTracked or 0)
            RefreshActionDistributionRow(action, bucket)
        end
    end

    if actionInsightText then actionInsightText:SetText(ActionInsightText(analytics)) end
    if actionSignalText then
        local sig = aggregate.signals or {}
        actionSignalText:SetText(string.format(
            "Decision flags: close %d   ·   final-charge %d   ·   modifier override %d   ·   fallback %d",
            sig.closeDecision or 0, sig.lastCharge or 0, sig.modifierOverride or 0, sig.fallback or 0))
    end
end

local function RecommendationValueText(recommendation, value)
    if recommendation.valueFormat == "percent" then return string.format("%.0f%%", tonumber(value) or 0) end
    return tostring(Round(tonumber(value) or 0, 0))
end

local function RecommendationChangeText(recommendation)
    local delta = tonumber(recommendation.delta) or 0
    local prefix = delta > 0 and "+" or ""
    local suffix = recommendation.valueFormat == "percent" and " pp" or ""
    return "Change " .. prefix .. tostring(Round(delta, 0)) .. suffix
end

local function RecommendationKindVisual(recommendation)
    if recommendation.state == "applied" then return "APPLIED TO BUILD", "success" end
    if recommendation.section == "logic" then
        if recommendation.category == "thresholds" then return recommendation.kind or "ADJUST THRESHOLD", "warning" end
        return recommendation.kind or "ADJUST LOGIC", "warning"
    end
    if recommendation.direction == "raise" then return recommendation.kind or "RAISE PRIORITY", "success" end
    if recommendation.direction == "lower" then return recommendation.kind or "LOWER PRIORITY", "danger" end
    return recommendation.kind or "REVIEW", "warning"
end

local function RecommendationEvidenceText(recommendation)
    local confidence = ConfidenceLabel(recommendation.samples or 0)
    local unit = recommendation.section == "logic" and "compatible offers" or "comparable decisions"
    return string.format("%s · %s confidence · %d %s", recommendation.source or "Analytics", confidence, recommendation.samples or 0, unit)
end

local function RecommendationApplyText(recommendation)
    local value = RecommendationValueText(recommendation, recommendation.suggestedValue)
    if recommendation.section == "logic" then
        local setting = tostring(recommendation.target or "setting")
        setting = setting:gsub("[Tt]hreshold$", "")
        setting = setting:gsub("%s+$", "")
        if setting ~= "" then return "Apply " .. value .. " " .. string.lower(setting) end
    end
    return "Apply " .. value
end

local function RecommendationSectionCounts(recommendations)
    local counts = { echo = 0, logic = 0 }
    for _, recommendation in ipairs(recommendations or {}) do
        local section = recommendation.section == "logic" and "logic" or "echo"
        counts[section] = counts[section] + 1
    end
    return counts
end

local function CurrentRecommendationMatches(recommendation, build)
    if not recommendation or not recommendation.apply or not build then return false, "This recommendation cannot be applied automatically." end
    local apply = recommendation.apply
    if apply.type == "weight" then
        local refKey = ResolveRecommendationRef(build, apply.refKey, apply.echoName)
        if not refKey then return false, "The Echo identity is ambiguous or no longer exists." end
        for quality, expected in pairs(apply.expectedValues or {}) do
            local current = EbonBuilds.Weights.GetForRef(build, refKey, quality)
            if current ~= expected then return false, "The Echo priority changed since this recommendation was calculated." end
        end
        apply.refKey = refKey
        return true
    elseif apply.type == "setting" then
        local current = tonumber((build.settings or {})[apply.field]) or 0
        if current ~= (tonumber(apply.expected) or 0) then return false, "The automation setting changed since this recommendation was calculated." end
        return true
    elseif apply.type == "qualityBonus" then
        local current = tonumber(((build.settings or {}).qualityBonus or {})[apply.quality]) or 0
        if current ~= (tonumber(apply.expected) or 0) then return false, "The quality modifier changed since this recommendation was calculated." end
        return true
    end
    return false, "Unknown recommendation type."
end

local function ShowRecommendationNotice(message)
    if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(message) end
end

local function ApplyRecommendation(recommendation)
    local build = activeBuild and EbonBuilds.Build.Get(activeBuild.id) or EbonBuilds.Build.GetActive()
    if not build or not recommendation or recommendation.state == "applied" then return false, "No active recommendation." end
    local matches, reason = CurrentRecommendationMatches(recommendation, build)
    if not matches then
        View.Invalidate(build.id)
        View.Refresh(build, true)
        return false, reason
    end

    local apply = recommendation.apply
    local saveData, undo = {}, { type = apply.type }
    if apply.type == "weight" then
        local refKey = apply.refKey
        local weights = EbonBuilds.Weights.CloneRefWeights(build.echoWeightsByRef or {})
        local entry = EbonBuilds.Weights.NormalizeEntry(weights[refKey])
        undo.refKey = refKey
        undo.echoName = apply.echoName
        undo.beforeValues, undo.afterValues = {}, {}
        if apply.applyAllRanks then
            for quality, expected in pairs(apply.expectedValues or {}) do
                local nextValue = ClampWeight(expected + (tonumber(apply.delta) or 0))
                undo.beforeValues[quality] = expected
                undo.afterValues[quality] = nextValue
                entry[quality] = nextValue
            end
        else
            local quality = apply.quality
            local before = EbonBuilds.Weights.GetFromWeights(weights, refKey, quality)
            local nextValue = ClampWeight(apply.value)
            undo.beforeValues[quality] = before
            undo.afterValues[quality] = nextValue
            entry[quality] = nextValue
        end
        weights[refKey] = entry
        saveData.echoWeightsByRef = weights
        saveData.echoSchema = 3
    elseif apply.type == "setting" then
        local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
        undo.field = apply.field
        undo.before = tonumber(settings[apply.field]) or 0
        undo.after = math.floor((tonumber(apply.value) or 0) + 0.5)
        settings[apply.field] = undo.after
        saveData.settings = settings
    elseif apply.type == "qualityBonus" then
        local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
        settings.qualityBonus = settings.qualityBonus or {}
        undo.quality = apply.quality
        undo.before = tonumber(settings.qualityBonus[apply.quality]) or 0
        undo.after = math.floor((tonumber(apply.value) or 0) + 0.5)
        settings.qualityBonus[apply.quality] = undo.after
        saveData.settings = settings
    else
        return false, "Unknown recommendation type."
    end

    local oldId = build.id
    local saved = EbonBuilds.Build.Save(build.id, saveData)
    if not saved then return false, "The build could not be updated." end
    activeBuild = saved
    recentRecommendationByBuild[saved.id] = {
        state = "applied",
        recommendation = recommendation,
        undo = undo,
        buildVersion = saved.version,
    }
    if saved.id ~= oldId then recentRecommendationByBuild[oldId] = nil end
    View.Invalidate(oldId)
    View.Invalidate(saved.id)
    View.Refresh(saved, true)
    return true
end

local function UndoRecentRecommendation()
    local build = activeBuild and EbonBuilds.Build.Get(activeBuild.id) or EbonBuilds.Build.GetActive()
    local recent = build and recentRecommendationByBuild[build.id]
    if not build or not recent or recent.state ~= "applied" then return false, "Nothing is available to undo." end
    local undo = recent.undo or {}
    local saveData = {}

    if undo.type == "weight" then
        local refKey = undo.refKey
        local weights = EbonBuilds.Weights.CloneRefWeights(build.echoWeightsByRef or {})
        local entry = EbonBuilds.Weights.NormalizeEntry(weights[refKey])
        for quality, expectedAfter in pairs(undo.afterValues or {}) do
            local current = EbonBuilds.Weights.GetFromWeights(weights, refKey, quality)
            if current ~= expectedAfter then return false, "The Echo priority changed after applying; Undo was cancelled." end
        end
        for quality, value in pairs(undo.beforeValues or {}) do entry[quality] = value end
        weights[refKey] = entry
        saveData.echoWeightsByRef = weights
        saveData.echoSchema = 3
    elseif undo.type == "setting" then
        local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
        if (tonumber(settings[undo.field]) or 0) ~= (tonumber(undo.after) or 0) then return false, "The automation setting changed after applying; Undo was cancelled." end
        settings[undo.field] = undo.before
        saveData.settings = settings
    elseif undo.type == "qualityBonus" then
        local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
        settings.qualityBonus = settings.qualityBonus or {}
        if (tonumber(settings.qualityBonus[undo.quality]) or 0) ~= (tonumber(undo.after) or 0) then return false, "The quality modifier changed after applying; Undo was cancelled." end
        settings.qualityBonus[undo.quality] = undo.before
        saveData.settings = settings
    else
        return false, "Unknown Undo type."
    end

    local oldId = build.id
    local saved = EbonBuilds.Build.Save(build.id, saveData)
    if not saved then return false, "The build could not be restored." end
    recentRecommendationByBuild[oldId] = nil
    activeBuild = saved
    if saved.id ~= oldId then recentRecommendationByBuild[oldId] = nil end
    View.Invalidate(oldId)
    View.Invalidate(saved.id)
    View.Refresh(saved, true)
    return true
end

local function DismissRecommendation(recommendation)
    if not activeBuild or not recommendation or recommendation.state == "applied" then return false, "This recommendation cannot be dismissed." end
    local store = RecommendationDismissalStore(activeBuild.id, true)
    if not store then return false, "Recommendation preferences are unavailable." end
    store[recommendation.key] = {
        source = recommendation.source,
        samples = recommendation.samples or 0,
        currentValue = recommendation.currentValue,
        suggestedValue = recommendation.suggestedValue,
    }
    View.Invalidate(activeBuild.id)
    View.Refresh(activeBuild, true)
    return true
end

local function InspectRecommendation(recommendation)
    if not recommendation then return end
    if recommendation.section == "echo" and recommendation.echoName and EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OpenWithFilters then
        EbonBuilds.SessionHistory.OpenWithFilters({
            echoName = VisibleEchoName(recommendation.echoName),
            source = recommendation.source == "Manual Training" and "manual" or nil,
            importantOnly = true,
        })
    elseif recommendation.section == "logic" and EbonBuilds.Calibration and EbonBuilds.Calibration.ShowWindow then
        EbonBuilds.Calibration.ShowWindow()
    end
end

local function ActiveRecommendationFilter()
    return recommendationFilters[recommendationSection] or "all"
end

local function RecommendationPassesFilter(recommendation)
    local section = recommendation.section == "logic" and "logic" or "echo"
    if section ~= recommendationSection then return false end
    local filter = ActiveRecommendationFilter()
    if filter == "all" then return true end
    if filter == "unapplied" then return recommendation.state ~= "applied" end
    if filter == "thresholds" then return recommendation.category == "thresholds" end
    if filter == "resource_rules" then return recommendation.category == "resource_rules" end
    return recommendation.direction == filter
end

local function VisibleRecommendations()
    local visible = {}
    local recent = activeBuild and recentRecommendationByBuild[activeBuild.id]
    if recent and recent.state == "applied" then
        local applied = {}
        for key, value in pairs(recent.recommendation or {}) do applied[key] = value end
        applied.state = "applied"
        applied.reason = "This build change was applied during the current session."
        applied.body = applied.reason
        if RecommendationPassesFilter(applied) then visible[#visible + 1] = applied end
    end
    for _, recommendation in ipairs(EnsureRecommendations()) do
        if RecommendationPassesFilter(recommendation) then visible[#visible + 1] = recommendation end
    end
    return visible
end

local function UpdateRecommendationNavigation(counts)
    counts = counts or RecommendationSectionCounts(EnsureRecommendations())
    local echoButton = recommendationSectionButtons.echo
    local logicButton = recommendationSectionButtons.logic
    if echoButton then
        echoButton:SetText(string.format("Echo priorities (%d)", counts.echo or 0))
        Theme.SetTabSelected(echoButton, recommendationSection == "echo")
    end
    if logicButton then
        logicButton:SetText(string.format("Automation logic (%d)", counts.logic or 0))
        Theme.SetTabSelected(logicButton, recommendationSection == "logic")
    end

    for section, buttons in pairs(recommendationFilterButtons) do
        for key, button in pairs(buttons) do
            if section == recommendationSection then
                button:Show()
                Theme.SetTabSelected(button, key == ActiveRecommendationFilter())
            else
                button:Hide()
            end
        end
    end

    if recHeader and recHeader._subtitle then
        if recommendationSection == "logic" then
            recHeader._subtitle:SetText("Threshold and rule changes that affect how complete offers are handled.")
        else
            recHeader._subtitle:SetText("Evidence-backed changes to individual Echo and quality weights.")
        end
    end
end

local function EnsureRecommendationRow(index)
    if recommendationRows[index] then return recommendationRows[index] end
    local card = Theme.CreateSection(recChild, "Recommendation", "Evidence-backed suggestion.")
    card:SetHeight(100)

    local kind = Theme.CreateStatusPill(card, "REVIEW", "warning")
    kind:SetSize(118, 16)
    kind:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -9)
    card._kind = kind
    card._title:ClearAllPoints()
    card._title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card._title:SetPoint("RIGHT", kind, "LEFT", -8, 0)
    card._title:SetJustifyH("LEFT")

    local transition = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    transition:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -31)
    transition:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    card._transition = transition

    local change = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    change:SetPoint("LEFT", transition, "RIGHT", 12, 0)
    change:SetTextColor(unpack(Theme.TEXT_MUTED))
    card._change = change

    local reason = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reason:SetPoint("TOPLEFT", transition, "BOTTOMLEFT", 0, -5)
    reason:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    reason:SetJustifyH("LEFT")
    reason:SetTextColor(unpack(Theme.TEXT_MUTED))
    card._reason = reason

    local evidence = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    evidence:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 11)
    evidence:SetPoint("RIGHT", card, "RIGHT", -294, 0)
    evidence:SetJustifyH("LEFT")
    evidence:SetTextColor(unpack(Theme.TEXT_MUTED))
    card._evidence = evidence

    local applyButton = Theme.CreateButton(card, "good")
    applyButton:SetSize(92, 22)
    applyButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -188, 8)
    applyButton:SetScript("OnClick", function()
        local data = card._data
        local ok, message
        if data and data.state == "applied" then
            ok, message = UndoRecentRecommendation()
            if ok then ShowRecommendationNotice("Recommendation undone.") end
        else
            ok, message = ApplyRecommendation(data)
            if ok then ShowRecommendationNotice("Build recommendation applied.") end
        end
        if not ok and message then ShowRecommendationNotice(message) end
    end)
    card._apply = applyButton

    local inspect = Theme.CreateButton(card)
    inspect:SetSize(104, 22)
    inspect:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -78, 8)
    inspect:SetText("Inspect evidence")
    inspect:SetScript("OnClick", function() InspectRecommendation(card._data) end)
    card._inspect = inspect

    local dismiss = Theme.CreateButton(card)
    dismiss:SetSize(62, 22)
    dismiss:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
    dismiss:SetText("Dismiss")
    dismiss:SetScript("OnClick", function()
        local ok, message = DismissRecommendation(card._data)
        if ok then ShowRecommendationNotice("Recommendation dismissed until its evidence changes.")
        elseif message then ShowRecommendationNotice(message) end
    end)
    card._dismiss = dismiss

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        Theme.SetCardHovered(self, true)
        local data = self._data
        if not data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(data.target or "Build recommendation", 1, 0.82, 0)
        GameTooltip:AddLine(data.reason or "Evidence-backed build adjustment.", 0.82, 0.82, 0.86, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Current: %s", RecommendationValueText(data, data.currentValue)), 0.72, 0.72, 0.76)
        GameTooltip:AddLine(string.format("Recommended: %s", RecommendationValueText(data, data.suggestedValue)), 0.72, 0.72, 0.76)
        GameTooltip:AddLine(RecommendationEvidenceText(data), 0.72, 0.72, 0.76, true)
        GameTooltip:AddLine(data.section == "logic" and "Scope: automation behavior across complete offers" or "Scope: individual Echo scoring", 0.62, 0.62, 0.68, true)
        if data.apply and data.apply.type == "weight" and data.apply.applyAllRanks then
            GameTooltip:AddLine("The same change is applied to every available quality rank, preserving rank differences.", 0.62, 0.62, 0.68, true)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        Theme.SetCardHovered(self, false)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(card, function(self)
            Theme.SetCardHovered(self, false)
            GameTooltip:Hide()
        end)
    end

    Theme.BindScrollWheel(recScroll, recBar, 48, card)
    recommendationRows[index] = card
    return card
end

local function RefreshRecommendations()
    if not statsCache then return end
    local activeRecommendations = EnsureRecommendations()
    local counts = RecommendationSectionCounts(activeRecommendations)
    if not recommendationSectionInitialized then
        recommendationSection = ((counts.echo or 0) == 0 and (counts.logic or 0) > 0) and "logic" or "echo"
        recommendationSectionInitialized = true
    end
    UpdateRecommendationNavigation(counts)
    local recommendations = VisibleRecommendations()
    local y = 0
    for i, recommendation in ipairs(recommendations) do
        local card = EnsureRecommendationRow(i)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", recChild, "TOPLEFT", 0, -y)
        card:SetPoint("RIGHT", recChild, "RIGHT", -4, 0)
        card._data = recommendation
        card._title:SetText(recommendation.target or "Review")
        if card._subtitle then card._subtitle:SetText("") end
        card._transition:SetText(string.format("%s  ->  %s", RecommendationValueText(recommendation, recommendation.currentValue), RecommendationValueText(recommendation, recommendation.suggestedValue)))
        card._change:SetText(RecommendationChangeText(recommendation))
        card._reason:SetText(recommendation.reason or "Review this build setting.")

        local kindLabel, kind = RecommendationKindVisual(recommendation)
        card._kind.label:SetText(kindLabel)
        local c = kind == "success" and Theme.SUCCESS or kind == "warning" and Theme.WARNING or Theme.DANGER
        card._kind:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.98)
        card._kind:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
        card._kind.label:SetTextColor(c[1], c[2], c[3], 1)

        card._evidence:SetText(RecommendationEvidenceText(recommendation))
        if recommendation.state == "applied" then
            card._apply:SetText("Undo")
            card._apply:Enable()
        elseif recommendation.apply then
            card._apply:SetText(RecommendationApplyText(recommendation))
            card._apply:Enable()
        else
            card._apply:SetText("Review")
            card._apply:Disable()
        end

        card._apply:ClearAllPoints()
        card._inspect:ClearAllPoints()
        if recommendation.section == "logic" then
            card._apply:SetWidth(132)
            card._inspect:SetWidth(112)
            card._inspect:SetText("Review calibration")
        else
            card._apply:SetWidth(92)
            card._inspect:SetWidth(104)
            card._inspect:SetText("Inspect decisions")
        end
        if recommendation.state == "applied" then
            card._dismiss:Hide()
            if recommendation.echoName or recommendation.category == "thresholds" then
                card._inspect:Show()
                card._inspect:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
                card._apply:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", recommendation.section == "logic" and -128 or -120, 8)
            else
                card._inspect:Hide()
                card._apply:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
            end
        else
            card._dismiss:Show()
            card._dismiss:ClearAllPoints()
            card._dismiss:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
            if recommendation.echoName or recommendation.category == "thresholds" then
                card._inspect:Show()
                card._inspect:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -78, 8)
                card._apply:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", recommendation.section == "logic" and -196 or -188, 8)
            else
                card._inspect:Hide()
                card._apply:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -78, 8)
            end
        end
        card:Show()
        y = y + 106
    end
    for i = #recommendations + 1, #recommendationRows do recommendationRows[i]:Hide() end
    recChild:SetHeight(math.max(1, y))
    local maxScroll = math.max(0, y - (recScroll:GetHeight() or 0))
    recBar:SetMinMaxValues(0, maxScroll)
    if recBar:GetValue() > maxScroll then recBar:SetValue(maxScroll) end
    if recScopeText then
        local recent = activeBuild and recentRecommendationByBuild[activeBuild.id]
        recScopeText:SetText(string.format("%d Echo · %d logic%s", counts.echo or 0, counts.logic or 0, recent and recent.state == "applied" and " · 1 applied this session" or ""))
    end
    if recEmpty then
        if recommendationSection == "logic" then
            recEmpty._title:SetText("No automation-logic changes recommended")
            recEmpty._body:SetText("Current thresholds and rules are supported by the available offer evidence, or the active filter hides them.")
        else
            recEmpty._title:SetText("No Echo-priority changes recommended")
            recEmpty._body:SetText("Current Echo weights are consistent with the available evidence, or the active filter hides them.")
        end
    end
    if #recommendations == 0 then recEmpty:Show() else recEmpty:Hide() end
end

local function RenderToken(key)
    if not statsCache then return nil end
    local token = tostring(statsCache.generation or 0)
    if key == "echoes" then token = token .. "|" .. tostring(echoSortRevision) end
    return token
end

local function RefreshActivePanel(key, force)
    local token = RenderToken(key)
    if not force and renderedTokens[key] == token then return end
    if key == "summary" then RefreshSummary()
    elseif key == "echoes" then RefreshEchoes()
    elseif key == "actions" then RefreshActions()
    elseif key == "recommendations" then RefreshRecommendations() end
    renderedTokens[key] = RenderToken(key)
end

local function SetView(key, force)
    activeView = key
    for _, def in ipairs(VIEW_ORDER) do
        if viewPanels[def.key] then if def.key == key then viewPanels[def.key]:Show() else viewPanels[def.key]:Hide() end end
        if viewTabs[def.key] then Theme.SetTabSelected(viewTabs[def.key], def.key == key) end
    end
    RefreshActivePanel(key, force and true or false)
end

local function SetEchoSort(key)
    LoadEchoSort()
    local column = ECHO_COLUMN_BY_KEY[key]
    if not column then return end

    if echoSort.key == key then
        echoSort.desc = not echoSort.desc
    else
        echoSort.key = key
        echoSort.desc = column.defaultDesc and true or false
    end

    SaveEchoSort()
    echoSortRevision = echoSortRevision + 1
    renderedTokens.echoes = nil
    if echoBar then echoBar:SetValue(0) end
    RefreshActivePanel("echoes", true)
end

local function AttachDynamicTooltip(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if self._tooltipTitle and self._tooltipTitle ~= "" then
            GameTooltip:AddLine(self._tooltipTitle, 1, 0.82, 0)
        end
        if self._tooltipBody and self._tooltipBody ~= "" then
            GameTooltip:AddLine(self._tooltipBody, 0.82, 0.82, 0.86, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        Theme.SetCardHovered(self, false)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(frame, function(self)
            Theme.SetCardHovered(self, false)
            GameTooltip:Hide()
        end)
    end
end

local function CreateSummaryMetricCard(parent, titleText, tooltipText)
    local card = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(card, "StatsView.SummaryMetricCard")
    end
    Theme.ApplyCard(card)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -7)
    title:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    title:SetJustifyH("LEFT")
    title:SetText(titleText or "Metric")
    title:SetTextColor(unpack(Theme.TEXT_MUTED))

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
    value:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    value:SetJustifyH("LEFT")
    value:SetText("0")
    value:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local description = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -1)
    description:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    description:SetJustifyH("LEFT")
    description:SetTextColor(unpack(Theme.TEXT_SECONDARY or Theme.TEXT_PRIMARY))

    local evidence = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    evidence:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 7)
    evidence:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    evidence:SetJustifyH("LEFT")
    evidence:SetTextColor(unpack(Theme.TEXT_MUTED))

    card.title = title
    card.value = value
    card.description = description
    card.evidence = evidence
    card._tooltipTitle = titleText
    card._tooltipBody = tooltipText
    AttachDynamicTooltip(card)
    return card
end

local function CreateEarlyEpicCard(parent, level)
    local card = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(card, "StatsView.EarlyEpicCard")
    end
    Theme.ApplyCard(card)

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    local er, eg, eb = EbonBuilds.Quality.GetRGB(3)
    accent:SetVertexColor(er, eg, eb, 0.85)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -7)
    title:SetText("LEVEL " .. tostring(level))
    title:SetTextColor(unpack(Theme.TEXT_MUTED))

    local sample = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sample:SetPoint("TOPRIGHT", card, "TOPRIGHT", -9, -7)
    sample:SetJustifyH("RIGHT")
    card.sample = sample

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -25)
    value:SetWidth(30)
    value:SetJustifyH("LEFT")
    value:SetText("—")
    value:SetTextColor(er, eg, eb)
    card.value = value

    local detail = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("TOPLEFT", card, "TOPLEFT", 43, -24)
    detail:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    card.detail = detail

    local rate = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rate:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -2)
    rate:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    rate:SetJustifyH("LEFT")
    rate:SetTextColor(unpack(Theme.TEXT_MUTED))
    card.rate = rate

    card._tooltipTitle = "Level " .. tostring(level) .. " Epic availability"
    card._tooltipBody = "Counts a run once when at least one Epic Echo appears in the original offer at this level. Rerolls are excluded."
    AttachDynamicTooltip(card)
    return card
end

local function BuildSummary(parent)
    local scope = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scope:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
    scope:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    scope:SetJustifyH("LEFT")
    scope:SetTextColor(unpack(Theme.TEXT_MUTED))
    summaryText.scope = scope

    local definitions = {
        {
            key = "score",
            title = "Decision value",
            tooltip = "The mean final score of selected Echoes across matching runs. This combines configured priority and active score modifiers; it is not a DPS measurement.",
        },
        {
            key = "resources",
            title = "Resource usage",
            tooltip = "Average banish, reroll, and freeze charges spent per tracked run level across matching runs.",
        },
        {
            key = "coverage",
            title = "Priority coverage",
            tooltip = "Weighted Echo families already learned in the Tome compared with every Echo family that has a non-zero configured priority.",
        },
        {
            key = "confidence",
            title = "Sample quality",
            tooltip = "Personal Manual Training and DPS observations available to support evidence-backed recommendations. This is a practical sample label, not a formal confidence interval.",
        },
    }
    for i, definition in ipairs(definitions) do
        local card = CreateSummaryMetricCard(parent, definition.title, definition.tooltip)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (i - 1) * 170, -24)
        card:SetSize(162, 78)
        card._summaryOrder = i
        summaryCards[definition.key] = card
    end

    local early = Theme.CreateSection(parent, "Early Epic availability", "Epic Echoes seen in each level's original offer. Rerolls and replacement cards are excluded.")
    early:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -114)
    early:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -114)
    early:SetHeight(118)
    for level = 1, 3 do
        local card = CreateEarlyEpicCard(early, level)
        card:SetPoint("TOPLEFT", early, "TOPLEFT", 12 + (level - 1) * 218, -47)
        card:SetSize(210, 60)
        card._summaryOrder = level
        earlyEpicCards[level] = card
    end


    local function LayoutSummaryCards()
        local parentWidth = math.max(560, parent:GetWidth() or 0)
        local metricGap = 8
        local metricWidth = math.floor((parentWidth - 12 - metricGap * 3) / 4)
        for _, card in pairs(summaryCards) do
            local order = card._summaryOrder or 1
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (order - 1) * (metricWidth + metricGap), -24)
            card:SetWidth(metricWidth)
        end

        local earlyWidth = math.max(540, early:GetWidth() or (parentWidth - 12))
        local earlyGap = 8
        local cardWidth = math.floor((earlyWidth - 24 - earlyGap * 2) / 3)
        for level, card in ipairs(earlyEpicCards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", early, "TOPLEFT", 12 + (level - 1) * (cardWidth + earlyGap), -47)
            card:SetWidth(cardWidth)
        end
    end
    parent:SetScript("OnSizeChanged", LayoutSummaryCards)
    early:HookScript("OnSizeChanged", LayoutSummaryCards)
    LayoutSummaryCards()

    local run = Theme.CreateSection(parent, "Latest run", "The newest run associated with this build, compared with the build's full recorded average.")
    run:SetPoint("TOPLEFT", early, "BOTTOMLEFT", 0, -12)
    run:SetPoint("TOPRIGHT", early, "BOTTOMRIGHT", 0, -12)
    run:SetHeight(104)
    local runText = run:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    runText:SetPoint("TOPLEFT", run._contentAnchor, "BOTTOMLEFT", 0, -10)
    runText:SetPoint("RIGHT", run, "RIGHT", -12, 0)
    runText:SetJustifyH("LEFT")
    summaryText.run = runText

    local comparison = run:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    comparison:SetPoint("TOPLEFT", runText, "BOTTOMLEFT", 0, -6)
    comparison:SetPoint("RIGHT", run, "RIGHT", -12, 0)
    comparison:SetJustifyH("LEFT")
    comparison:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    summaryText.comparison = comparison

    local actions = run:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    actions:SetPoint("TOPLEFT", comparison, "BOTTOMLEFT", 0, -6)
    actions:SetPoint("RIGHT", run, "RIGHT", -12, 0)
    actions:SetJustifyH("LEFT")
    actions:SetTextColor(unpack(Theme.TEXT_MUTED))
    summaryText.selected = actions

    local highlights = Theme.CreateSection(parent, "Build signals", "The most frequent recorded outcomes; use the focused views for individual Echo and decision evidence.")
    highlights:SetPoint("TOPLEFT", run, "BOTTOMLEFT", 0, -12)
    highlights:SetPoint("TOPRIGHT", run, "BOTTOMRIGHT", 0, -12)
    highlights:SetHeight(88)
    local top = highlights:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    top:SetPoint("TOPLEFT", highlights._contentAnchor, "BOTTOMLEFT", 0, -11)
    top:SetPoint("RIGHT", highlights, "RIGHT", -12, 0)
    top:SetJustifyH("LEFT")
    summaryText.top = top

    local hint = highlights:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", highlights, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Echo rows and recommendation cards link directly to matching Logbook evidence.")
    hint:SetTextColor(unpack(Theme.TEXT_MUTED))
end

local function BuildEchoes(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -6)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -6)
    header:SetHeight(25)
    Theme.ApplyCard(header)
    LoadEchoSort()
    for _, def in ipairs(ECHO_COLUMNS) do
        local btn = Theme.CreateTab(header, def.label)
        btn:SetPoint("LEFT", header, "LEFT", def.x, 0)
        btn:SetSize(def.w, 21)
        btn._baseLabel = def.label
        local sortKey = def.key
        btn:SetScript("OnClick", function() SetEchoSort(sortKey) end)
        if Theme.AttachTooltip then
            Theme.AttachTooltip(btn, def.label .. " sort", "Click to sort by this column. Click again to reverse the direction.")
        end
        echoHeaderButtons[sortKey] = btn
    end

    echoScroll = CreateFrame("ScrollFrame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(echoScroll, "StatsView.EchoScroll")
    end
    echoScroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    echoScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 24)
    echoChild = CreateFrame("Frame", nil, echoScroll)
    echoChild:SetSize(560, 1)
    echoScroll:SetScrollChild(echoChild)
    echoBar = Theme.CreateScrollBar(parent)
    echoBar:SetPoint("TOPRIGHT", echoScroll, "TOPRIGHT", 15, -2)
    echoBar:SetPoint("BOTTOMRIGHT", echoScroll, "BOTTOMRIGHT", 15, 2)
    echoBar:SetValueStep(36)
    echoBar:SetScript("OnValueChanged", function(_, value) echoScroll:SetVerticalScroll(value) end)
    Theme.BindScrollWheel(echoScroll, echoBar, 36, echoChild)
    echoScroll:SetScript("OnSizeChanged", function(self)
        local width = math.max(560, self:GetWidth() or 0)
        if echoChild._statsWidth == width then return end
        echoChild._statsWidth = width
        echoChild:SetWidth(width)
        LayoutEchoColumns(width)
        renderedTokens.echoes = nil
        if activeView == "echoes" and statsCache then RefreshActivePanel("echoes", true) end
    end)
    LayoutEchoColumns(math.max(560, echoScroll:GetWidth() or 0))
    echoCountText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    echoCountText:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 7)
    echoCountText:SetTextColor(unpack(Theme.TEXT_MUTED))
    echoCountText:SetText("0 weighted Echoes")

    echoEmpty = Theme.CreateEmptyState(echoScroll, "No weighted Echoes", "Add a non-zero priority to an Echo to include it in this analytics table.")

    -- A panel can become effectively visible because its parent was shown.
    -- Rendering here avoids relying on a header click to populate the rows.
    parent:SetScript("OnShow", function()
        if activeView == "echoes" and statsCache then
            renderedTokens.echoes = nil
            RefreshActivePanel("echoes", true)
        end
    end)
    UpdateEchoHeaders()
end

local function CreateActionMetricCard(parent, action)
    local card = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(card, "StatsView.ActionMetricCard")
    end
    Theme.ApplyCard(card)

    local color = ACTION_COLORS[action] or Theme.ACCENT_GOLD
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetVertexColor(color[1], color[2], color[3], 0.88)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -7)
    title:SetText(string.upper(action))
    title:SetTextColor(color[1], color[2], color[3], 1)

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -23)
    value:SetWidth(34)
    value:SetJustifyH("LEFT")
    value:SetText("0")
    value:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local share = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    share:SetPoint("TOPLEFT", card, "TOPLEFT", 43, -25)
    share:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    share:SetJustifyH("LEFT")
    share:SetTextColor(unpack(Theme.TEXT_MUTED))

    local metric = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metric:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -48)
    metric:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    metric:SetJustifyH("LEFT")
    metric:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    local coverage = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    coverage:SetPoint("TOPLEFT", metric, "BOTTOMLEFT", 0, -4)
    coverage:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    coverage:SetJustifyH("LEFT")
    coverage:SetTextColor(unpack(Theme.TEXT_MUTED))

    local hit = CreateFrame("Button", nil, card)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(hit, "StatsView.CardHitArea")
    end
    hit:SetAllPoints(card)
    hit:SetScript("OnClick", function()
        if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OpenWithFilters then
            EbonBuilds.SessionHistory.OpenWithFilters({ action = action })
        end
    end)
    hit:SetScript("OnEnter", function()
        Theme.SetCardHovered(card, true)
        GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(card._tooltipTitle or (action .. " action statistics"), 1, 0.82, 0)
        if card._tooltipBody then GameTooltip:AddLine(card._tooltipBody, 0.82, 0.82, 0.86, true) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
        Theme.SetCardHovered(card, false)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(hit, function()
            Theme.SetCardHovered(card, false)
            GameTooltip:Hide()
        end)
    end

    card.value = value
    card.share = share
    card.metric = metric
    card.coverage = coverage
    card._hit = hit
    return card
end

local function CreateQualityDistributionRow(parent, action, rowIndex)
    local row = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "StatsView.Row")
    end
    Theme.ApplyCard(row)
    row:SetHeight(29)
    row._alternate = rowIndex % 2 == 0
    if row._alternate then row:SetBackdropColor(0.105, 0.105, 0.132, 0.985) end

    local color = ACTION_COLORS[action] or Theme.TEXT_PRIMARY
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetWidth(62)
    label:SetJustifyH("LEFT")
    label:SetText(action)
    label:SetTextColor(color[1], color[2], color[3], 1)

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("LEFT", row, "LEFT", 68, 0)
    count:SetWidth(30)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(unpack(Theme.TEXT_MUTED))

    local bar = CreateFrame("Frame", nil, row)
    bar:SetPoint("LEFT", row, "LEFT", 108, 0)
    bar:SetSize(410, 14)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    bar:SetBackdropColor(0.025, 0.025, 0.035, 0.95)

    local noData = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noData:SetPoint("CENTER", bar, "CENTER", 0, 0)
    noData:SetText("No quality data")
    noData:SetTextColor(unpack(Theme.TEXT_MUTED))

    local coverage = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    coverage:SetPoint("LEFT", row, "LEFT", 530, 0)
    coverage:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    coverage:SetJustifyH("RIGHT")
    coverage:SetTextColor(unpack(Theme.TEXT_MUTED))

    row.segments = {}
    for _, quality in ipairs(QUALITY_ORDER) do
        local segment = CreateFrame("Frame", nil, bar)
        if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
            EbonBuilds.Debug.ProtectScript(segment, "StatsView.BarSegment")
        end
        segment:SetHeight(14)
        local texture = segment:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(segment)
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        local r, g, b = EbonBuilds.Quality.GetRGB(quality)
        texture:SetVertexColor(r, g, b, quality == 0 and 0.72 or 0.88)
        segment._texture = texture
        segment:EnableMouse(true)
        segment:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if self._tooltipTitle then GameTooltip:AddLine(self._tooltipTitle, 1, 0.82, 0) end
            if self._tooltipBody then GameTooltip:AddLine(self._tooltipBody, 0.82, 0.82, 0.86, true) end
            GameTooltip:Show()
        end)
        segment:SetScript("OnLeave", function() GameTooltip:Hide() end)
        segment:Hide()
        row.segments[quality] = segment
    end

    row._tooltipTitle = action .. " quality coverage"
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self._tooltipTitle or "Quality coverage", 1, 0.82, 0)
        if self._tooltipBody then GameTooltip:AddLine(self._tooltipBody, 0.82, 0.82, 0.86, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if self._alternate then
            self:SetBackdropColor(0.105, 0.105, 0.132, 0.985)
            self:SetBackdropBorderColor(unpack(Theme.BORDER_DIM))
        else
            Theme.SetCardHovered(self, false)
        end
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(row, function(self)
            if self._alternate then
                self:SetBackdropColor(0.105, 0.105, 0.132, 0.985)
                self:SetBackdropBorderColor(unpack(Theme.BORDER_DIM))
            else
                Theme.SetCardHovered(self, false)
            end
            GameTooltip:Hide()
        end)
    end
    row.count = count
    row.bar = bar
    row.noData = noData
    row.coverage = coverage
    row._barWidth = 410
    return row
end

local function BuildActions(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
    title:SetText("Action statistics")
    title:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    actionScopeText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    actionScopeText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    actionScopeText:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    actionScopeText:SetJustifyH("LEFT")
    actionScopeText:SetTextColor(unpack(Theme.TEXT_MUTED))

    actionCoverageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    actionCoverageText:SetPoint("TOPLEFT", actionScopeText, "BOTTOMLEFT", 0, -3)
    actionCoverageText:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    actionCoverageText:SetJustifyH("LEFT")
    actionCoverageText:SetTextColor(unpack(Theme.TEXT_MUTED))

    for i, action in ipairs(ACTION_KEYS) do
        local card = CreateActionMetricCard(parent, action)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (i - 1) * 170, -55)
        card:SetSize(162, 88)
        actionCards[action] = card
    end

    local distribution = Theme.CreateSection(parent, "Recorded Echo quality",
        "Official quality of each action's subject. Reroll uses the highest-quality Echo in the rejected offer.")
    distribution:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -155)
    distribution:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -155)
    -- The four 29px rows end at y=-190. 194px keeps the final row inside
    -- the card while recovering enough vertical space for Action patterns.
    distribution:SetHeight(194)

    local legendAnchor
    for _, quality in ipairs(QUALITY_ORDER) do
        local legend = CreateFrame("Frame", nil, distribution)
        legend:SetSize(92, 13)
        if legendAnchor then
            legend:SetPoint("LEFT", legendAnchor, "RIGHT", 7, 0)
        else
            legend:SetPoint("TOPLEFT", distribution, "TOPLEFT", 108, -48)
        end
        local swatch = legend:CreateTexture(nil, "ARTWORK")
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetPoint("LEFT", legend, "LEFT", 0, 0)
        swatch:SetSize(9, 9)
        local r, g, b = EbonBuilds.Quality.GetRGB(quality)
        swatch:SetVertexColor(r, g, b, quality == 0 and 0.72 or 0.9)
        local text = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
        text:SetText(EbonBuilds.Quality.LABELS[quality] or tostring(quality))
        text:SetTextColor(unpack(Theme.TEXT_MUTED))
        legendAnchor = legend
    end

    local coverageHeader = distribution:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    coverageHeader:SetPoint("TOPRIGHT", distribution, "TOPRIGHT", -20, -48)
    coverageHeader:SetText("QUALITY DATA")
    coverageHeader:SetTextColor(unpack(Theme.TEXT_MUTED))

    for i, action in ipairs(ACTION_KEYS) do
        local row = CreateQualityDistributionRow(distribution, action, i)
        row:SetPoint("TOPLEFT", distribution, "TOPLEFT", 10, -65 - (i - 1) * 32)
        row:SetPoint("RIGHT", distribution, "RIGHT", -10, 0)
        actionDistributionRows[action] = row
    end

    local insights = Theme.CreateSection(parent, "Action patterns",
        "Deterministic comparisons appear only when at least five compatible decisions are available.")
    insights:SetPoint("TOPLEFT", distribution, "BOTTOMLEFT", 0, -8)
    -- Anchor the final section to the viewport bottom instead of assigning a
    -- fixed height. This keeps it inside the Stats panel at smaller window
    -- sizes and non-default UI scales.
    insights:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 4)

    actionInsightText = insights:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    actionInsightText:SetPoint("TOPLEFT", insights._contentAnchor, "BOTTOMLEFT", 0, -7)
    actionInsightText:SetPoint("BOTTOMRIGHT", insights, "BOTTOMRIGHT", -12, 9)
    actionInsightText:SetJustifyH("LEFT")
    actionInsightText:SetJustifyV("TOP")
    actionInsightText:SetTextColor(unpack(Theme.TEXT_PRIMARY))

    -- Decision flags are diagnostic context, not a primary user metric. Keep
    -- them available through the section tooltip rather than spending a full
    -- visible line and forcing the card outside the viewport.
    actionSignalText = insights:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    actionSignalText:Hide()

    insights:EnableMouse(true)
    insights:SetScript("OnEnter", function(self)
        Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Action patterns", 1, 0.82, 0)
        GameTooltip:AddLine("Patterns are shown only when at least five compatible decisions support the comparison.", 0.82, 0.82, 0.86, true)
        local signalText = actionSignalText and actionSignalText:GetText()
        if signalText and signalText ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(signalText, 0.62, 0.62, 0.68, true)
        end
        GameTooltip:Show()
    end)
    insights:SetScript("OnLeave", function(self)
        Theme.SetCardHovered(self, false)
        GameTooltip:Hide()
    end)
    if Theme.BindHoverReset then
        Theme.BindHoverReset(insights, function(self)
            Theme.SetCardHovered(self, false)
            GameTooltip:Hide()
        end)
    end
end

local function BuildRecommendationsPanel(parent)
    recHeader = Theme.CreateSection(parent, "Build recommendations", "Evidence-backed changes to individual Echo and quality weights.")
    recHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -5)
    recHeader:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -5)
    recHeader:SetHeight(91)

    recScopeText = recHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    recScopeText:SetPoint("TOPRIGHT", recHeader, "TOPRIGHT", -10, -10)
    recScopeText:SetTextColor(unpack(Theme.TEXT_MUTED))

    local sectionDefs = {
        { key = "echo", label = "Echo priorities (0)", width = 152 },
        { key = "logic", label = "Automation logic (0)", width = 166 },
    }
    local sectionAnchor
    for _, def in ipairs(sectionDefs) do
        local button = Theme.CreateTab(recHeader, def.label)
        button:SetSize(def.width, 22)
        if sectionAnchor then button:SetPoint("LEFT", sectionAnchor, "RIGHT", 6, 0) else button:SetPoint("TOPLEFT", recHeader, "TOPLEFT", 10, -38) end
        local key = def.key
        button:SetScript("OnClick", function()
            recommendationSection = key
            if recBar then
                recBar:SetValue(0)
                recScroll:SetVerticalScroll(0)
            end
            RefreshRecommendations()
        end)
        recommendationSectionButtons[key] = button
        sectionAnchor = button
    end

    local filterDefs = {
        echo = {
            { key = "all", label = "All", width = 54 },
            { key = "raise", label = "Raise", width = 64 },
            { key = "lower", label = "Lower", width = 64 },
            { key = "unapplied", label = "Unapplied", width = 84 },
        },
        logic = {
            { key = "all", label = "All", width = 54 },
            { key = "thresholds", label = "Thresholds", width = 88 },
            { key = "resource_rules", label = "Resource rules", width = 104 },
            { key = "unapplied", label = "Unapplied", width = 84 },
        },
    }
    for section, defs in pairs(filterDefs) do
        local anchor
        for _, def in ipairs(defs) do
            local button = Theme.CreateTab(recHeader, def.label)
            button:SetSize(def.width, 19)
            if anchor then button:SetPoint("LEFT", anchor, "RIGHT", 5, 0) else button:SetPoint("BOTTOMLEFT", recHeader, "BOTTOMLEFT", 10, 7) end
            local key = def.key
            button:SetScript("OnClick", function()
                recommendationFilters[section] = key
                if recBar then
                    recBar:SetValue(0)
                    recScroll:SetVerticalScroll(0)
                end
                RefreshRecommendations()
            end)
            recommendationFilterButtons[section][key] = button
            anchor = button
        end
    end
    UpdateRecommendationNavigation({ echo = 0, logic = 0 })

    recScroll = CreateFrame("ScrollFrame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(recScroll, "StatsView.RecScroll")
    end
    recScroll:SetPoint("TOPLEFT", recHeader, "BOTTOMLEFT", 0, -7)
    recScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 4)
    recChild = CreateFrame("Frame", nil, recScroll)
    recChild:SetSize(560, 1)
    recScroll:SetScrollChild(recChild)
    recBar = Theme.CreateScrollBar(parent)
    recBar:SetPoint("TOPRIGHT", recScroll, "TOPRIGHT", 15, -2)
    recBar:SetPoint("BOTTOMRIGHT", recScroll, "BOTTOMRIGHT", 15, 2)
    recBar:SetValueStep(48)
    recBar:SetScript("OnValueChanged", function(_, value) recScroll:SetVerticalScroll(value) end)
    Theme.BindScrollWheel(recScroll, recBar, 48, recChild)
    recScroll:SetScript("OnSizeChanged", function(self) recChild:SetWidth(math.max(560, self:GetWidth() or 0)) end)
    recEmpty = Theme.CreateEmptyState(recScroll, "No Echo-priority changes recommended", "Current Echo weights are consistent with the available evidence.")
end

function View.Mount(parent)
    if root then
        root:SetParent(parent)
        root:SetAllPoints(parent)
        return root
    end
    root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)

    local tabBar = CreateFrame("Frame", nil, root)
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
    tabBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -4)
    tabBar:SetHeight(27)
    local anchor
    for _, def in ipairs(VIEW_ORDER) do
        local btn = Theme.CreateTab(tabBar, def.label)
        btn:SetSize(def.key == "recommendations" and 132 or 104, 24)
        if anchor then btn:SetPoint("LEFT", anchor, "RIGHT", 6, 0) else btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0) end
        local viewKey = def.key
        btn:SetScript("OnClick", function() SetView(viewKey, true) end)
        viewTabs[viewKey] = btn
        anchor = btn
    end

    for _, def in ipairs(VIEW_ORDER) do
        local panel = CreateFrame("Frame", nil, root)
        panel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -7)
        panel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
        panel:Hide()
        viewPanels[def.key] = panel
    end
    BuildSummary(viewPanels.summary)
    BuildEchoes(viewPanels.echoes)
    BuildActions(viewPanels.actions)
    BuildRecommendationsPanel(viewPanels.recommendations)
    SetView("summary")
    return root
end

function View.SetView(key)
    if viewPanels[key] then SetView(key, true) end
end

function View.Refresh(build, force)
    local previousBuildId = activeBuild and activeBuild.id
    activeBuild = build or activeBuild
    if not activeBuild then return end
    if previousBuildId and previousBuildId ~= activeBuild.id then recommendationSectionInitialized = false end
    local signature = CacheSignature(activeBuild)
    local cached = cacheByBuildId[activeBuild.id]
    if not force and cached and cached.signature == signature then
        statsCache = cached.cache
    else
        statsCache = GenerateCache(activeBuild)
        statsCache.signature = signature
        cacheByBuildId[activeBuild.id] = { signature = signature, cache = statsCache }
        renderedTokens = {}
    end
    -- Always repaint the active panel when the outer Stats workspace opens or
    -- refreshes. Cached analytics may be reused, but cached visibility is not a
    -- reliable substitute for rendering after parent frames were hidden.
    SetView(activeView, true)
end

function View.Invalidate(buildId)
    if buildId then cacheByBuildId[buildId] = nil else cacheByBuildId = {} end
    renderedTokens = {}
end

function View.Show(build)
    if root then root:Show() end
    View.Refresh(build)
end

function View.OnSessionAnalyticsChanged(buildId)
    View.Invalidate(buildId)
    if root and root:IsShown() and activeBuild and (not buildId or activeBuild.id == buildId) then
        View.Refresh(activeBuild, true)
    end
end

function View.Hide()
    if root then root:Hide() end
end

-- Test hooks and integration helpers.
View._NormalizeAction = NormalizeAction
View._SessionMetrics = SessionMetrics
View._SessionMatchesBuild = SessionMatchesBuild
View._ConfidenceLabel = ConfidenceLabel
View._GenerateCache = GenerateCache
View._CacheSignature = CacheSignature
View._EnsureRecommendations = EnsureRecommendations
View._BuildRecommendations = BuildRecommendations
View._ApplyRecommendation = ApplyRecommendation
View._UndoRecentRecommendation = UndoRecentRecommendation
View._DismissRecommendation = DismissRecommendation
View._CurrentRecommendationMatches = CurrentRecommendationMatches
View._VisibleRecommendations = VisibleRecommendations
View._RecommendationSectionCounts = RecommendationSectionCounts
View._SetRecommendationSectionForTest = function(section)
    if section == "echo" or section == "logic" then recommendationSection = section end
end
View._SetRecommendationFilterForTest = function(section, filter)
    if recommendationFilters[section] then recommendationFilters[section] = filter end
end
View._BuildEarlyEpicStats = BuildEarlyEpicStats
View._EarlyEpicObservation = EarlyEpicObservation
View._AggregateSessionMetrics = AggregateSessionMetrics
View._BuildActionAnalytics = BuildActionAnalytics
View._TargetChoice = TargetChoice
View._BuildEchoRowsForTest = BuildEchoRows
View._WeightedCoverageForTest = WeightedCoverage
View._SortEchoRowsForTest = function(rows, key, desc)
    SortEchoes(rows, key, desc)
    return rows
end
View._GetEchoSortForTest = function()
    return echoSort.key, echoSort.desc
end
View._GetEchoRenderCountForTest = function()
    return lastEchoRenderCount
end
