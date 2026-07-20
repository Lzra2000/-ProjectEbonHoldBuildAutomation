-- EbonBuilds: modules/automation/Calibration.lua
-- Self-calibrating threshold advisor.
--
-- Automation's banish/reroll/freeze thresholds are set as a % of a
-- THEORETICAL peak/mean/EV computed from the build's own scoring weights
-- (Scoring.lua). That's a reasonable starting point, but it says nothing
-- about what you're ACTUALLY being offered on this server, with this
-- build's real weight tuning, over hundreds of picks. This module records
-- the score of every echo actually offered (as a % of that evaluation's
-- peak) into a persistent, capped sample buffer, then answers "if I want
-- this threshold to reject/trigger on roughly N% of what I'm really
-- offered, what value should that be?" from the real observed
-- distribution instead of the theoretical one.
--
-- Supports both Classic mode (autoBanishPct/autoRerollPct/autoFreezePct,
-- all already a % of peak -- the same space samples are recorded in) and
-- Smart/EV mode (banishEVPct/freezeEVPct, a % of mean/evBest3 instead --
-- converted via the current mean/peak or evBest3/peak ratio so both modes
-- can be analyzed against the same sample data).
--
-- Smart Reroll is supported through a separate best-offer sample stream.
-- Each sample divides out the live pacing multiplier first, so suggestions
-- remain comparable across different remaining-charge states.

EbonBuilds.Calibration = {}

local MAX_SAMPLES = 2000
local MAX_STRATEGY_STREAMS = 12
local MIN_SAMPLES_FOR_SUGGESTION = 30
local calibrationRevision = 0
local appearanceRevision = 0
local canonicalAppearanceIndex = {}
local canonicalAppearanceIndexBuilt = false
local normalizedAppearanceStoreRef
local appearanceSnapshotCache = {}

local function BumpCalibrationRevision()
    calibrationRevision = calibrationRevision + 1
end

local function BumpAppearanceRevision()
    appearanceRevision = appearanceRevision + 1
    appearanceSnapshotCache = {}
end

local function StrategyScope()
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build then return "unscoped", nil end
    return table.concat({ tostring(build.id), tostring(build.strategyRevision or 1),
        tostring(build.strategyHash or EbonBuilds.Build.StrategyChecksum(build)) }, ":"), build
end

local function GetStrategyStream()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    local calibration = EbonBuildsCharDB.calibration
    calibration.streams = calibration.streams or {}
    local key, build = StrategyScope()
    local stream = calibration.streams[key]
    if not stream then
        stream = { buildId = build and build.id, strategyRevision = build and build.strategyRevision or nil,
            strategyHash = build and build.strategyHash or nil }
        -- Legacy arrays had no scope. Preserve them once under the strategy
        -- active during migration rather than mixing them into every build.
        if calibration.samples then stream.samples = calibration.samples; calibration.samples = nil end
        if calibration.bestSamples then stream.bestSamples = calibration.bestSamples; calibration.bestSamples = nil end
        if calibration.samplesSinceLastTune then
            stream.samplesSinceLastTune = calibration.samplesSinceLastTune
            calibration.samplesSinceLastTune = nil
        end
        calibration.streams[key] = stream
    end
    stream.samples = EbonBuilds.RingBuffer.Ensure(stream.samples, MAX_SAMPLES)
    stream.bestSamples = EbonBuilds.RingBuffer.Ensure(stream.bestSamples, MAX_SAMPLES)
    stream.lastSeenAt = time()

    local streams = {}
    for streamKey, value in pairs(calibration.streams) do
        streams[#streams + 1] = { key = streamKey, seen = tonumber(value.lastSeenAt) or 0 }
    end
    if #streams > MAX_STRATEGY_STREAMS then
        table.sort(streams, function(a, b) return a.seen > b.seen end)
        for index = MAX_STRATEGY_STREAMS + 1, #streams do calibration.streams[streams[index].key] = nil end
    end
    return stream, key
end

local function GetStore()
    return GetStrategyStream().samples
end

-- Separate store: one sample per EVALUATION (not per offered echo) of the
-- best offered score, with that evaluation's charge-pacing multiplier
-- divided back out. Reroll (Smart mode) decides based on "best offered
-- vs threshold", not individual echo scores, so it needs its own sample
-- space -- and since the effective threshold moves with remaining
-- charges, normalizing pacing out is what makes samples from different
-- points in a run comparable to each other at all.
local function GetBestStore()
    return GetStrategyStream().bestSamples
end

function EbonBuilds.Calibration.GetScope()
    local _, key = GetStrategyStream()
    return key
end

-- Called once per evaluation, with the best offered echo's score (as a
-- % of peak) divided by that evaluation's reroll pacing multiplier.
function EbonBuilds.Calibration.RecordBestSample(normalizedPct)
    if not normalizedPct or normalizedPct < 0 then return end
    local store = GetBestStore()
    EbonBuilds.RingBuffer.Append(store, normalizedPct)
    BumpCalibrationRevision()
end

-- Called once per offered echo during automation evaluation, with its
-- score as a percentage of that evaluation's peak (0-100+, can exceed
-- 100 for an echo scored above the cached peak). Cheap: no sorting or
-- analysis happens here, just an append + cap.
function EbonBuilds.Calibration.RecordSample(pct)
    if not pct or pct < 0 then return end
    local store = GetStore()
    EbonBuilds.RingBuffer.Append(store, pct)
    BumpCalibrationRevision()
end

function EbonBuilds.Calibration.SampleCount()
    return EbonBuilds.RingBuffer.Count(GetStore())
end

function EbonBuilds.Calibration.BestSampleCount()
    return EbonBuilds.RingBuffer.Count(GetBestStore())
end

function EbonBuilds.Calibration.Clear()
    local stream, scope = GetStrategyStream()
    stream.samples = EbonBuilds.RingBuffer.New(MAX_SAMPLES)
    stream.bestSamples = EbonBuilds.RingBuffer.New(MAX_SAMPLES)
    stream.samplesSinceLastTune = 0
    local proposal = EbonBuildsCharDB.calibration.pendingReview
    if proposal and (not proposal.scope or proposal.scope == scope) then
        EbonBuildsCharDB.calibration.pendingReview = nil
    end
    BumpCalibrationRevision()
end

------------------------------------------------------------------------
-- Echo appearance frequency -- how often does each echo actually show
-- up on a choice screen, as a % of evaluations? A different question
-- from the score-based samples above (which are about VALUE): this is
-- about how often the server offers it at all. Always-on locally (cheap,
-- needs nothing but the same evaluation loop already running); sharing
-- with other same-class players is a separate opt-in toggle, since
-- unlike EchoPerformance's DPS tracking this doesn't need Details! at
-- all and shouldn't be gated behind that requirement. Offers are recorded
-- whenever EbonBuilds evaluates a native choice screen, including while
-- Autopilot is off or Manual Training is active.
------------------------------------------------------------------------

local MAX_TRUSTED_APPEARANCE_EVALS = 5000  -- reject a single peer claiming more evaluations than this
local MAX_APPEARANCE_PEERS          = 50
local APPEARANCE_BROADCAST_BATCH   = 8
local APPEARANCE_BROADCAST_INTERVAL = 180  -- seconds

local function EnsureCanonicalAppearanceIndex()
    if canonicalAppearanceIndexBuilt then return end
    canonicalAppearanceIndexBuilt = true
    if not (ProjectEbonhold and ProjectEbonhold.PerkDatabase) then return end
    for spellId in pairs(ProjectEbonhold.PerkDatabase) do
        local spellName = GetSpellInfo(spellId)
        if spellName then canonicalAppearanceIndex[spellName] = EbonBuilds.Weights.CanonicalName(spellId) or spellName end
    end
end

local function CanonicalAppearanceName(value)
    if value == nil then return nil end
    local numeric = type(value) == "number" and value
        or (type(value) == "string" and value:match("^%d+$") and tonumber(value))
    if numeric then
        local cached = canonicalAppearanceIndex[numeric]
        if cached then return cached end
        cached = EbonBuilds.Weights.CanonicalName(numeric) or GetSpellInfo(numeric)
        canonicalAppearanceIndex[numeric] = cached
        return cached
    end
    local name = tostring(value)
    local cached = canonicalAppearanceIndex[name]
    if cached then return cached end
    EnsureCanonicalAppearanceIndex()
    cached = canonicalAppearanceIndex[name] or EbonBuilds.Weights.StripQualitySuffix(name)
    canonicalAppearanceIndex[name] = cached
    return cached
end

local function NormalizeAppearanceCounts(counts)
    local out = {}
    for rawName, rawCount in pairs(type(counts) == "table" and counts or {}) do
        local name = CanonicalAppearanceName(rawName)
        local count = tonumber(rawCount)
        if name and count and count >= 0 then out[name] = (out[name] or 0) + count end
    end
    return out
end

local function GetAppearanceStore()
    EbonBuildsCharDB.appearance = EbonBuildsCharDB.appearance or { counts = {}, totalEvals = 0 }
    local store = EbonBuildsCharDB.appearance
    if normalizedAppearanceStoreRef ~= store then
        store.counts = NormalizeAppearanceCounts(store.counts)
        store.totalEvals = tonumber(store.totalEvals) or 0
        normalizedAppearanceStoreRef = store
    end
    return store
end

local function GetAppearanceCommunityStore()
    EbonBuildsCharDB.appearanceCommunity = EbonBuildsCharDB.appearanceCommunity or {}
    return EbonBuildsCharDB.appearanceCommunity
end

function EbonBuilds.Calibration.IsAppearanceSharingEnabled()
    local consent = EbonBuildsCharDB.consent
    return consent and (tonumber(consent.performanceVersion) or 0) >= 1 and consent.communityAppearanceSharing == true
end

function EbonBuilds.Calibration.SetAppearanceSharingEnabled(on)
    EbonBuildsCharDB.consent = EbonBuildsCharDB.consent or {}
    EbonBuildsCharDB.consent.performanceVersion = 1
    EbonBuildsCharDB.consent.communityAppearanceSharing = on and true or false
    EbonBuildsCharDB.appearanceSharingEnabled = nil
end

-- Called once per evaluation, regardless of what happens after.
function EbonBuilds.Calibration.RecordEvaluation()
    local store = GetAppearanceStore()
    store.totalEvals = store.totalEvals + 1
    BumpAppearanceRevision()
end

-- Called once per offered echo per evaluation.
function EbonBuilds.Calibration.RecordAppearance(name)
    name = CanonicalAppearanceName(name)
    if not name then return end
    local store = GetAppearanceStore()
    store.counts[name] = (store.counts[name] or 0) + 1
    BumpAppearanceRevision()
end

function EbonBuilds.Calibration.ClearAppearance()
    EbonBuildsCharDB.appearance = { counts = {}, totalEvals = 0 }
    EbonBuildsCharDB.appearanceCommunity = {}
    normalizedAppearanceStoreRef = nil
    BumpAppearanceRevision()
end

-- Merges one peer's reported appearance batch. Idempotent per sender
-- (replaced, not added, each time) and class-matched, same
-- anti-poisoning philosophy as EchoPerformance's DPS sharing.
function EbonBuilds.Calibration.MergeAppearanceContribution(sender, class, totalEvals, counts)
    if not (sender and class and totalEvals and counts) then return end
    local normalizePlayer = EbonBuilds.Build and EbonBuilds.Build._NormalizePlayerName
        or function(v) return tostring(v or ""):lower():match("^([^-]+)") end
    if normalizePlayer(sender) == normalizePlayer(UnitName("player")) then return end
    sender = normalizePlayer(sender)
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or build.class ~= class then return end
    totalEvals = tonumber(totalEvals)
    if not totalEvals or totalEvals <= 0 or totalEvals > MAX_TRUSTED_APPEARANCE_EVALS then return end

    local cleanCounts = NormalizeAppearanceCounts(counts)
    local countEntries = 0
    for name, count in pairs(cleanCounts) do
        countEntries = countEntries + 1
        if count > totalEvals then cleanCounts[name] = totalEvals end
        if countEntries > 500 then cleanCounts[name] = nil end
    end
    if not next(cleanCounts) then return end

    local store = GetAppearanceCommunityStore()
    store[sender] = store[sender] or {}
    store[sender][class] = { totalEvals = totalEvals, counts = cleanCounts }
    store[sender]._lastSeenAt = time()
    local peers = {}
    for peer, contribution in pairs(store) do
        peers[#peers + 1] = { peer = peer, seen = tonumber(contribution._lastSeenAt) or 0 }
    end
    if #peers > MAX_APPEARANCE_PEERS then
        table.sort(peers, function(a, b) return a.seen > b.seen end)
        for index = MAX_APPEARANCE_PEERS + 1, #peers do store[peers[index].peer] = nil end
    end
    BumpAppearanceRevision()
end

-- Build one appearance snapshot for the active class. The previous API
-- normalized and re-scanned every personal/community counter once per Echo,
-- which made analytics views scale quadratically with collection size.
function EbonBuilds.Calibration.GetAllAppearanceStats(class)
    if not class then
        local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
        class = build and build.class or ""
    end
    local key = tostring(class or "") .. "|" .. tostring(appearanceRevision)
    if appearanceSnapshotCache[key] then return appearanceSnapshotCache[key] end

    local personal = GetAppearanceStore()
    local totalEvals = personal.totalEvals or 0
    local counts = {}
    for name, count in pairs(personal.counts or {}) do counts[name] = tonumber(count) or 0 end

    if class and class ~= "" then
        for _, byClass in pairs(GetAppearanceCommunityStore()) do
            local contribution = byClass[class]
            if contribution then
                totalEvals = totalEvals + (tonumber(contribution.totalEvals) or 0)
                for rawName, rawCount in pairs(contribution.counts or {}) do
                    local name = CanonicalAppearanceName(rawName)
                    if name then counts[name] = (counts[name] or 0) + (tonumber(rawCount) or 0) end
                end
            end
        end
    end

    local snapshot = {}
    if totalEvals > 0 then
        for name, count in pairs(counts) do
            snapshot[name] = {
                pct = count / totalEvals * 100,
                count = count,
                totalEvals = totalEvals,
                personalEvals = personal.totalEvals or 0,
            }
        end
    end
    appearanceSnapshotCache[key] = snapshot
    return snapshot
end

function EbonBuilds.Calibration.GetAppearanceStats(name)
    name = CanonicalAppearanceName(name)
    if not name then return nil end
    return EbonBuilds.Calibration.GetAllAppearanceStats()[name]
end

function EbonBuilds.Calibration.GetRevision()
    return calibrationRevision
end

function EbonBuilds.Calibration.GetAppearanceRevision()
    return appearanceRevision
end

------------------------------------------------------------------------
-- Wire format: APR|<class>|<totalEvals>|name1:count1;name2:count2;...
-- A rotating batch, same rationale as EchoPerformance's PRF -- short
-- messages over the sync channel rather than one giant payload.
------------------------------------------------------------------------

function EbonBuilds.Calibration.SerializeAppearanceBatch(class, names)
    if not class or not names or #names == 0 then return nil end
    local store = GetAppearanceStore()
    local parts = {}
    for _, name in ipairs(names) do
        local count = store.counts[name]
        if count and count > 0 then
            parts[#parts + 1] = string.format("%s:%d", name, count)
        end
    end
    if #parts == 0 then return nil end
    return string.format("APR|%s|%d|%s", class, store.totalEvals or 0, table.concat(parts, ";"))
end

function EbonBuilds.Calibration.ParseAppearanceBatch(payload)
    local class, totalEvals, body = payload:match("^APR|([^|]+)|(%d+)|(.+)$")
    if not class then return nil end
    local counts = {}
    for entry in body:gmatch("[^;]+") do
        local name, count = entry:match("^(.+):(%d+)$")
        if name then counts[name] = tonumber(count) end
    end
    return class, tonumber(totalEvals), counts
end

function EbonBuilds.Calibration.HandleAppearanceBroadcast(payload, sender)
    if not EbonBuilds.Calibration.IsAppearanceSharingEnabled() then return end
    local class, totalEvals, counts = EbonBuilds.Calibration.ParseAppearanceBatch(payload)
    if not class then return end
    EbonBuilds.Calibration.MergeAppearanceContribution(sender, class, totalEvals, counts)
end

local appearanceBroadcastElapsed = 0
local appearanceBroadcastCursor = 1

local function SendOneAppearanceBatch()
    if not (EbonBuilds.Sync and EbonBuilds.Sync.BroadcastPerfBatch) then return false end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or not build.class then return false end

    local store = GetAppearanceStore()
    local names = {}
    for name in pairs(store.counts) do names[#names + 1] = name end
    if #names == 0 then return false end
    table.sort(names)

    local batch = {}
    for i = 1, APPEARANCE_BROADCAST_BATCH do
        local idx = ((appearanceBroadcastCursor - 1 + i - 1) % #names) + 1
        batch[#batch + 1] = names[idx]
    end
    appearanceBroadcastCursor = ((appearanceBroadcastCursor - 1 + APPEARANCE_BROADCAST_BATCH) % #names) + 1

    local payload = EbonBuilds.Calibration.SerializeAppearanceBatch(build.class, batch)
    if not payload then return false end
    EbonBuilds.Sync.BroadcastPerfBatch(payload)
    return true
end

function EbonBuilds.Calibration.MaybeBroadcastAppearance(dt)
    if not EbonBuilds.Calibration.IsAppearanceSharingEnabled() then return end
    appearanceBroadcastElapsed = appearanceBroadcastElapsed + (dt or 0)
    if appearanceBroadcastElapsed < APPEARANCE_BROADCAST_INTERVAL then return end
    appearanceBroadcastElapsed = 0
    SendOneAppearanceBatch()
end

local SYNC_NOW_MAX_APPEARANCE_BATCHES = 3

function EbonBuilds.Calibration.SyncAppearanceNow()
    if not EbonBuilds.Calibration.IsAppearanceSharingEnabled() then
        return false, "appearance sharing is off"
    end
    appearanceBroadcastElapsed = 0
    local sent = 0
    for i = 1, SYNC_NOW_MAX_APPEARANCE_BATCHES do
        if not SendOneAppearanceBatch() then break end
        sent = sent + 1
    end
    if sent == 0 then return false, "nothing to sync yet" end
    return true, sent
end

------------------------------------------------------------------------
-- Tuning proposal preparation (opt-in)
--
-- Off by default. Every TUNE_INTERVAL_SAMPLES newly-collected samples,
-- prepares a small proposal (TUNE_STEP fraction of the gap) for explicit
-- review. It never mutates the live build in the background. Samples and
-- rate limiting are scoped to the active build's strategy revision so a
-- different build or reweight cannot contaminate the evidence stream.
------------------------------------------------------------------------

local TUNE_STEP = 0.25             -- close 25% of the gap per adjustment
local TUNE_INTERVAL_SAMPLES = 20   -- newly-collected samples between passes
local TUNE_MIN_GAP = 1.5           -- ignore gaps smaller than this (percentage points)

function EbonBuilds.Calibration.IsAutoTuneEnabled()
    return EbonBuildsCharDB.calibration and EbonBuildsCharDB.calibration.autoTuneEnabled == true
end

function EbonBuilds.Calibration.SetAutoTuneEnabled(on)
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.autoTuneEnabled = on and true or false
    local stream = GetStrategyStream()
    stream.samplesSinceLastTune = 0
end

-- Value at the given percentile (0-100) of an already-sorted list.
local function Percentile(sorted, p)
    if #sorted == 0 then return 0 end
    local idx = math.max(1, math.min(#sorted, math.ceil(p / 100 * #sorted)))
    return sorted[idx]
end

-- What % of samples fall strictly below a given threshold value.
local function FractionBelow(sorted, threshold)
    if #sorted == 0 then return 0 end
    local count = 0
    for _, v in ipairs(sorted) do
        if v < threshold then count = count + 1 end
    end
    return count / #sorted * 100
end

-- Core analysis, worked entirely in "% of peak" space (the space samples
-- are recorded in). direction "below" = Banish/Reroll (triggers under the
-- threshold, target = % you want rejected). direction "above" = Freeze
-- (triggers over the threshold, target = % you want it to catch).
local function BuildSuggestion(currentPctOfPeak, targetFraction, direction, store)
    store = store or GetStore()
    if EbonBuilds.RingBuffer.Is(store) then store = EbonBuilds.RingBuffer.ToArray(store) end
    local result = {
        sampleCount = #store,
        currentPctOfPeak = currentPctOfPeak,
        targetFraction = targetFraction,
        direction = direction,
    }
    if #store < MIN_SAMPLES_FOR_SUGGESTION then
        result.insufficientData = true
        return result
    end
    local sorted = {}
    for i, v in ipairs(store) do sorted[i] = v end
    table.sort(sorted)

    local fractionBelow = FractionBelow(sorted, currentPctOfPeak)
    if direction == "above" then
        result.currentFraction   = 100 - fractionBelow
        result.suggestedPctOfPeak = Percentile(sorted, 100 - targetFraction)
    else
        result.currentFraction   = fractionBelow
        result.suggestedPctOfPeak = Percentile(sorted, targetFraction)
    end
    return result
end

------------------------------------------------------------------------
-- Classic mode: settings fields are already a % of peak, no conversion.
------------------------------------------------------------------------

-- Target: reject roughly the bottom 15% of what's actually offered.
function EbonBuilds.Calibration.SuggestBanish(settings)
    local r = BuildSuggestion(settings.autoBanishPct or 0, 15, "below")
    r.currentFieldPct = settings.autoBanishPct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

-- Target: reroll offers landing in the bottom ~45% (proxy for the real
-- sum-of-three check Automation.lua uses -- not an exact match, but
-- directionally useful).
function EbonBuilds.Calibration.SuggestReroll(settings)
    local r = BuildSuggestion(settings.autoRerollPct or 0, 45, "below")
    r.currentFieldPct = settings.autoRerollPct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

-- Target: catch roughly the top 10% of what's offered.
function EbonBuilds.Calibration.SuggestFreeze(settings)
    local r = BuildSuggestion(settings.autoFreezePct or 0, 10, "above")
    r.currentFieldPct = settings.autoFreezePct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

------------------------------------------------------------------------
-- Smart (EV) mode: fields are a % of a DIFFERENT baseline (mean or
-- evBest3), not peak directly. Convert via that baseline's current
-- ratio to peak (from the live scoring model), analyze in peak-relative
-- space to match the sample data, then convert the suggestion back.
------------------------------------------------------------------------

local function SuggestSmart(currentFieldPct, baselineRatio, targetFraction, direction)
    if not baselineRatio or baselineRatio <= 0 then
        return { insufficientData = true, sampleCount = EbonBuilds.Calibration.SampleCount() }
    end
    local r = BuildSuggestion(currentFieldPct * baselineRatio, targetFraction, direction)
    r.currentFieldPct = currentFieldPct
    if not r.insufficientData then
        r.suggestedFieldPct = r.suggestedPctOfPeak / baselineRatio
    end
    return r
end

function EbonBuilds.Calibration.SuggestSmartBanish(settings)
    local stats = EbonBuilds.Automation.GetOutcomeStats()
    local peak  = EbonBuilds.Automation.GetPeak()
    local ratio = (peak and peak > 0 and stats.mean) and (stats.mean / peak) or nil
    return SuggestSmart(settings.banishEVPct or 60, ratio, 15, "below")
end

function EbonBuilds.Calibration.SuggestSmartFreeze(settings)
    local stats = EbonBuilds.Automation.GetOutcomeStats()
    local peak  = EbonBuilds.Automation.GetPeak()
    local ratio = (peak and peak > 0 and stats.evBest3) and (stats.evBest3 / peak) or nil
    return SuggestSmart(settings.freezeEVPct or 110, ratio, 10, "above")
end

-- Smart Reroll, finally supported: samples in bestSamples already have
-- each evaluation's pacing multiplier divided out (see Automation.lua's
-- reroll-check hook and RecordBestSample above), so comparing against
-- them is equivalent to asking "what would this threshold do at full
-- pacing (8+ charges)?" -- the live threshold at any given charge count
-- still scales the same way as before via ChargePacing; this only
-- fixes what the SUGGESTION itself is calculated from.
function EbonBuilds.Calibration.SuggestSmartReroll(settings)
    local ev   = EbonBuilds.Automation.GetRerollEV()
    local peak = EbonBuilds.Automation.GetPeak()
    if not (peak and peak > 0 and ev and ev > 0) then
        return { insufficientData = true, sampleCount = EbonBuilds.Calibration.BestSampleCount() }
    end
    local ratio = ev / peak
    local currentFieldPct = settings.rerollEVPct or 95
    local r = BuildSuggestion(currentFieldPct * ratio, 45, "below", GetBestStore())
    r.currentFieldPct = currentFieldPct
    if not r.insufficientData then
        r.suggestedFieldPct = r.suggestedPctOfPeak / ratio
    end
    return r
end

------------------------------------------------------------------------
-- Auto-tune pass (see the opt-in block above for the rationale)
------------------------------------------------------------------------

-- One gradual step for a single metric: nudges `field` by TUNE_STEP of
-- the gap to its suggestion. Returns true if it actually changed anything.
local function StepField(settings, result, field)
    if result.insufficientData then return false end
    local gap = result.suggestedFieldPct - result.currentFieldPct
    if math.abs(gap) < TUNE_MIN_GAP then return false end
    local newValue = result.currentFieldPct + gap * TUNE_STEP
    settings[field] = math.floor(newValue + 0.5)
    return true, settings[field]
end

-- Called after every recorded sample. Cheap check (a counter compare) on
-- every call; the actual analysis (sorting samples, computing suggestions)
-- only runs once every TUNE_INTERVAL_SAMPLES, and only if the player has
-- opted in.
function EbonBuilds.Calibration.IsAutoApplyWeightsEnabled()
    return EbonBuildsCharDB.calibration and EbonBuildsCharDB.calibration.autoApplyWeights == true
end

function EbonBuilds.Calibration.SetAutoApplyWeightsEnabled(on)
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.autoApplyWeights = on and true or false
end

function EbonBuilds.Calibration.MaybeAutoTune()
    if not EbonBuilds.Calibration.IsAutoTuneEnabled() then return end
    local stream, scope = GetStrategyStream()
    stream.samplesSinceLastTune = (stream.samplesSinceLastTune or 0) + 1
    if stream.samplesSinceLastTune < TUNE_INTERVAL_SAMPLES then return end
    stream.samplesSinceLastTune = 0

    local build = EbonBuilds.Build.GetActive()
    if not build then return end
    local liveSettings = build.settings or EbonBuilds.Build.DefaultSettings()
    local settings = EbonBuilds.Build.CloneSettings(liveSettings)
    local isSmart = (liveSettings.rerollMode or "sum") == "ev"

    local changed = {}
    local okB, valB = StepField(settings,
        isSmart and EbonBuilds.Calibration.SuggestSmartBanish(liveSettings) or EbonBuilds.Calibration.SuggestBanish(liveSettings),
        isSmart and "banishEVPct" or "autoBanishPct")
    if okB then changed[#changed + 1] = ("Banish " .. valB .. "%") end

    local okF, valF = StepField(settings,
        isSmart and EbonBuilds.Calibration.SuggestSmartFreeze(liveSettings) or EbonBuilds.Calibration.SuggestFreeze(liveSettings),
        isSmart and "freezeEVPct" or "autoFreezePct")
    if okF then changed[#changed + 1] = ("Freeze " .. valF .. "%") end

    if not isSmart then
        local okR, valR = StepField(settings, EbonBuilds.Calibration.SuggestReroll(liveSettings), "autoRerollPct")
        if okR then changed[#changed + 1] = ("Reroll " .. valR .. "%") end
    else
        local okR, valR = StepField(settings, EbonBuilds.Calibration.SuggestSmartReroll(liveSettings), "rerollEVPct")
        if okR then changed[#changed + 1] = ("Reroll " .. valR .. "%") end
    end

    -- Weight suggestions are a separate opt-in because their evidence is
    -- noisier than threshold evidence. This reuses the exact same suggestion
    -- functions the manual "read the report" path uses, so there's only
    -- one place either kind of suggestion is computed.
    local weightsChanged = {}
    local newWeights
    if EbonBuilds.Calibration.IsAutoApplyWeightsEnabled() then
        newWeights = EbonBuilds.Weights.CloneWeights(build.echoWeights or {})

        -- Suggestions from DPS are family-level (the server does not always
        -- expose the active rank), while Manual Training can be rank-specific.
        -- Accumulate deltas first so opposite signals cancel instead of one
        -- source silently overwriting the other, then update nested rank
        -- tables without ever replacing them with a scalar.
        local pendingDeltas = {}
        local catalog = EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildBestByName
            and EbonBuilds.EchoTableRows.BuildBestByName() or {}

        local function AddDelta(name, quality, delta)
            if not name or not delta or delta == 0 then return end
            pendingDeltas[name] = pendingDeltas[name] or {}
            pendingDeltas[name][quality] = (pendingDeltas[name][quality] or 0) + delta
        end

        local function AddSuggestionList(list)
            for _, suggestion in ipairs(list or {}) do
                local delta = tonumber(suggestion.delta)
                if not delta and suggestion.currentWeight ~= nil and suggestion.suggestedWeight ~= nil then
                    delta = suggestion.suggestedWeight - suggestion.currentWeight
                end
                if delta and delta ~= 0 then
                    if suggestion.quality ~= nil and EbonBuilds.Quality.IsValid(suggestion.quality) then
                        AddDelta(suggestion.name, suggestion.quality, delta)
                    else
                        local qualities = suggestion.qualities
                            or (catalog[suggestion.name] and catalog[suggestion.name].qualities)
                        local added = false
                        for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                            if not qualities or qualities[quality] then
                                AddDelta(suggestion.name, quality, delta)
                                added = true
                            end
                        end
                        if not added then
                            for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                                AddDelta(suggestion.name, quality, delta)
                            end
                        end
                    end
                end
            end
        end

        if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled() then
            AddSuggestionList(EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build))
        end
        if EbonBuilds.ManualTraining then
            AddSuggestionList(EbonBuilds.ManualTraining.SuggestWeightAdjustments(build))
        end

        for name, byQuality in pairs(pendingDeltas) do
            local entry = EbonBuilds.Weights.NormalizeEntry(newWeights[name])
            for quality, delta in pairs(byQuality) do
                if delta ~= 0 and EbonBuilds.Quality.IsValid(quality) then
                    local oldValue = EbonBuilds.Weights.GetFromWeights(newWeights, name, quality)
                    local newValue = math.max(EbonBuilds.Weights.MIN_VALUE,
                        math.min(EbonBuilds.Weights.MAX_VALUE, oldValue + delta))
                    if newValue ~= oldValue then
                        entry[quality] = newValue
                        weightsChanged[#weightsChanged + 1] = string.format("%s (%s)", name,
                            (EbonBuilds.Quality.LABELS or {})[quality] or tostring(quality))
                    end
                end
            end
            newWeights[name] = entry
        end

        if #weightsChanged > 0 then
            changed[#changed + 1] = string.format("%d rank weight(s)", #weightsChanged)
        end
    end

    if #changed == 0 then return end

    local summary = table.concat(changed, ", ")
    EbonBuildsCharDB.calibration.pendingReview = {
        buildId = build.id,
        baseRevision = tonumber(build.revision) or 1,
        scope = scope,
        createdAt = time(),
        settings = settings,
        echoWeights = newWeights and #weightsChanged > 0 and newWeights or nil,
        summary = summary,
    }
    if EbonBuilds.Toast then
        EbonBuilds.Toast.Show("Tuning proposal ready: " .. summary .. ". Review before applying.")
    end
    if EbonBuilds.DebugLog and EbonBuilds.DebugLog.IsEnabled() then
        EbonBuilds.DebugLog.AddF("-> TUNING PROPOSAL: %s", summary)
        if #weightsChanged > 0 then
            EbonBuilds.DebugLog.AddF("-> AUTO-TUNE weights: %s", table.concat(weightsChanged, ", "))
        end
    end
end

function EbonBuilds.Calibration.GetPendingReview()
    local calibration = EbonBuildsCharDB.calibration
    local proposal = calibration and calibration.pendingReview
    if not proposal then return nil, "NONE" end
    local build = EbonBuilds.Build.GetActive()
    if not build or proposal.buildId ~= build.id then return proposal, "OTHER_BUILD" end
    if tonumber(proposal.baseRevision) ~= (tonumber(build.revision) or 1) then
        return proposal, "STALE"
    end
    if proposal.scope and proposal.scope ~= EbonBuilds.Calibration.GetScope() then
        return proposal, "STALE"
    end
    return proposal, "READY"
end

function EbonBuilds.Calibration.DismissPendingReview()
    if EbonBuildsCharDB.calibration then
        EbonBuildsCharDB.calibration.pendingReview = nil
    end
    return true
end

function EbonBuilds.Calibration.ApplyPendingReview()
    local proposal, status = EbonBuilds.Calibration.GetPendingReview()
    if status ~= "READY" then
        return false, status == "OTHER_BUILD" and "Proposal belongs to another active build"
            or status == "STALE" and "Proposal is stale because the build changed"
            or "No tuning proposal is ready"
    end
    local saved, reason = EbonBuilds.Build.Save(proposal.buildId, {
        settings = proposal.settings,
        echoWeights = proposal.echoWeights,
        baseRevision = proposal.baseRevision,
    })
    if not saved then
        return false, reason == "CONFLICT" and "Proposal is stale because the build changed"
            or "Unable to apply tuning proposal"
    end
    EbonBuildsCharDB.calibration.pendingReview = nil
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("TUNING_PROPOSAL_APPLIED", saved.id, saved.revision)
    end
    return true, saved
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function ApplySuggestion(field, value)
    local build = EbonBuilds.Build.GetActive()
    if not build then return false end
    local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
    settings[field] = math.floor(value + 0.5)
    local saved = EbonBuilds.Build.Save(build.id, { settings = settings, baseRevision = build.revision })
    return saved ~= nil
end

local frame, countLabel, modeWarning, proposalLabel, proposalApplyBtn, proposalDismissBtn
local banishRow, rerollRow, freezeRow

local function BuildRow(parent, yOffset, label)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    title:SetText(label)

    local current = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    current:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    current:SetWidth(480)
    current:SetJustifyH("LEFT")

    local suggestion = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suggestion:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -4)
    suggestion:SetWidth(400)
    suggestion:SetJustifyH("LEFT")

    local applyBtn = EbonBuilds.Theme.CreateButton(parent)
    applyBtn:SetSize(90, 20)
    applyBtn:SetPoint("LEFT", suggestion, "RIGHT", 8, 0)

    return { title = title, current = current, suggestion = suggestion, applyBtn = applyBtn }
end

local function ClearRow(row, text)
    row.current:SetText(text or "")
    row.suggestion:SetText("")
    row.applyBtn:Hide()
end

local function RefreshRow(row, result, field, unitLabel)
    local verb = result.direction == "above" and "triggers on" or "rejects"
    if result.insufficientData then
        row.current:SetText(string.format("|cff888888Collecting data... (%d / %d samples needed)|r",
            result.sampleCount, MIN_SAMPLES_FOR_SUGGESTION))
        row.suggestion:SetText("")
        row.applyBtn:Hide()
        return
    end
    row.current:SetText(string.format("Current: %.0f%% -- %s ~%.0f%% of what you're actually offered (%d samples)",
        result.currentFieldPct, verb, result.currentFraction, result.sampleCount))
    if math.abs(result.suggestedFieldPct - result.currentFieldPct) < 1 then
        row.suggestion:SetText(string.format("|cff1eff00Already close to the %s target (~%.0f%%).|r", unitLabel, result.targetFraction))
        row.applyBtn:Hide()
    else
        row.suggestion:SetText(string.format("Suggested: |cffffd100%.0f%%|r to target ~%.0f%% %s",
            result.suggestedFieldPct, result.targetFraction, result.direction == "above" and "caught" or "rejected"))
        row.applyBtn:SetText(string.format("Apply %.0f%%", result.suggestedFieldPct))
        row.applyBtn:Show()
        row.applyBtn:SetScript("OnClick", function()
            if ApplySuggestion(field, result.suggestedFieldPct) then
                EbonBuilds.Toast.Show(string.format("%s threshold set to %.0f%%", unitLabel, result.suggestedFieldPct))
                EbonBuilds.Calibration.RefreshWindow()
            end
        end)
    end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsTuningAdvisorWindow", UIParent)
    f:SetSize(560, 610)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Tuning Advisor")

    local drag = CreateFrame("Frame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "Calibration.DragHeader")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    subtitle:SetWidth(528)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Compares your current thresholds against what your build actually gets offered, and suggests values based on the real distribution instead of the theoretical scoring model. Works with both Classic and Smart (EV) mode.")
    -- No fixed SetHeight: this text needs 3 lines at this width, and a
    -- height sized for 2 (28px) clipped the third line instead of
    -- showing it. Auto-sizing to the wrapped content is safe here --
    -- banishRow/rerollRow/freezeRow below all anchor to fixed offsets
    -- from the window itself, not chained to subtitle, so subtitle
    -- growing a bit taller doesn't push anything else out of place.

    modeWarning = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeWarning:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    modeWarning:SetWidth(500)
    modeWarning:SetJustifyH("LEFT")
    modeWarning:SetTextColor(1, 0.6, 0.2, 1)

    banishRow = BuildRow(f, -160, "Banish")
    rerollRow = BuildRow(f, -220, "Reroll")
    freezeRow = BuildRow(f, -280, "Freeze")

    local autoTuneCB = EbonBuilds.Theme.CreateCheckbox(f, "Prepare tuning proposals")
    autoTuneCB:SetPoint("TOPLEFT", freezeRow.suggestion, "BOTTOMLEFT", -4, -10)
    autoTuneCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Prepare tuning proposals", 1, 1, 1)
        GameTooltip:AddLine("Off by default. Every ~20 new offers, prepares a small evidence-based proposal and tells you it is ready. It never changes the live build automatically; use the Apply controls after reviewing the evidence.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoTuneCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoTuneCB:SetScript("OnClick", function(self)
        EbonBuilds.Calibration.SetAutoTuneEnabled(self:GetChecked() and true or false)
    end)

    local perfCB = EbonBuilds.Theme.CreateCheckbox(f, "Track + share DPS by echo (needs Details!)")
    perfCB:SetPoint("TOPLEFT", autoTuneCB, "BOTTOMLEFT", 0, -6)
    perfCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Track + share DPS by echo", 1, 1, 1)
        GameTooltip:AddLine("Off by default. Requires the Details! damage meter addon. Every 10s in combat, samples your current DPS and credits it to every echo you currently have active, building a rough real-performance average per echo over time.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Also shares this with other EbonBuilds users of the SAME class over the sync channel, and merges what they share back into your own data -- aggregate numbers only (per-echo average + sample count), never raw combat logs. Both directions use the same toggle. Received data is sanity-checked and can't be inflated by someone re-sending the same numbers.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Approximate on purpose either way: echoes stack together and fights vary a lot, so this can't isolate any single echo's true effect. A rough signal to combine with the scoring model, not a precise measurement. Shown in Export (AI) once you've collected some data.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    perfCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    perfCB:SetScript("OnClick", function(self)
        if self:GetChecked() and not EbonBuilds.EchoPerformance.IsDetailsAvailable() then
            EbonBuilds.Toast.Show("Details! not found -- install it to use DPS tracking")
            self:SetChecked(false)
            return
        end
        EbonBuilds.EchoPerformance.SetEnabled(self:GetChecked() and true or false)
    end)

    local appearCB = EbonBuilds.Theme.CreateCheckbox(f, "Share echo appearance rates")
    appearCB:SetPoint("TOPLEFT", perfCB, "BOTTOMLEFT", 0, -6)
    appearCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Share echo appearance rates", 1, 1, 1)
        GameTooltip:AddLine("Off by default. Doesn't need Details! -- separate from DPS tracking above. Tracks how often each echo actually shows up on a choice screen (not how good it scores, just how often the server offers it), as a % of all evaluations. Always recorded locally; this toggle only controls sharing it with other same-class EbonBuilds users and merging theirs back into yours.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Same safeguards as DPS sharing: only merges from a class-matched peer, a single peer's claimed evaluation count is capped, and re-broadcasts can't inflate the total. Shown in Export (AI).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    appearCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    appearCB:SetScript("OnClick", function(self)
        EbonBuilds.Calibration.SetAppearanceSharingEnabled(self:GetChecked() and true or false)
    end)

    local weightCB = EbonBuilds.Theme.CreateCheckbox(f, "Include weights in proposals")
    weightCB:SetPoint("TOPLEFT", appearCB, "BOTTOMLEFT", 0, -6)
    weightCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Include weights in proposals", 1, 1, 1)
        GameTooltip:AddLine("Off by default. Includes DPS-based and Manual Training weight changes in the staged tuning proposal. Nothing is applied automatically.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Weight evidence is noisier than offer-distribution evidence, so it stays a separate opt-in. DPS and Manual Training deltas are combined first; opposite signals cancel. Rank-specific training affects only that rank.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    weightCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    weightCB:SetScript("OnClick", function(self)
        EbonBuilds.Calibration.SetAutoApplyWeightsEnabled(self:GetChecked() and true or false)
    end)

    local clearBtn = EbonBuilds.Theme.CreateButton(f, "danger")
    clearBtn:SetSize(140, 20)
    clearBtn:SetPoint("TOPLEFT", weightCB, "BOTTOMLEFT", 0, -12)
    clearBtn:SetText("Clear Collected Data")
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Wipes score samples for the active strategy revision and all local appearance-rate data. Older strategy streams remain isolated and bounded. Worth doing when you want a clean current baseline.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.Calibration.Clear()
        EbonBuilds.Calibration.ClearAppearance()
        EbonBuilds.Calibration.RefreshWindow()
    end)

    local syncNowBtn = EbonBuilds.Theme.CreateButton(f)
    syncNowBtn:SetSize(100, 20)
    syncNowBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    syncNowBtn:SetText("Sync Now")
    syncNowBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Sync Now", 1, 1, 1)
        GameTooltip:AddLine("Pushes a few batches of your DPS and/or appearance-rate data right away instead of waiting for the periodic broadcast (every 3 min). Only sends whichever of those two you've actually enabled above -- does nothing if both are off.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    syncNowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncNowBtn:SetScript("OnClick", function()
        local parts = {}
        if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.SyncNow then
            local ok, sentOrReason = EbonBuilds.EchoPerformance.SyncNow()
            if ok then parts[#parts + 1] = string.format("%d DPS batch(es)", sentOrReason) end
        end
        if EbonBuilds.Calibration.SyncAppearanceNow then
            local ok, sentOrReason = EbonBuilds.Calibration.SyncAppearanceNow()
            if ok then parts[#parts + 1] = string.format("%d appearance batch(es)", sentOrReason) end
        end
        if #parts == 0 then
            EbonBuilds.Toast.Show("Nothing to sync -- enable DPS or appearance sharing above first")
        else
            EbonBuilds.Toast.Show("Synced: " .. table.concat(parts, ", "))
        end
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("TOPLEFT", clearBtn, "BOTTOMLEFT", 0, -14)
    countLabel:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    countLabel:SetJustifyH("LEFT")

    proposalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    proposalLabel:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -12)
    proposalLabel:SetWidth(330)
    proposalLabel:SetJustifyH("LEFT")

    proposalApplyBtn = EbonBuilds.Theme.CreateButton(f)
    proposalApplyBtn:SetSize(88, 22)
    proposalApplyBtn:SetPoint("TOPLEFT", proposalLabel, "TOPRIGHT", 8, 2)
    proposalApplyBtn:SetText("Apply")
    proposalApplyBtn:SetScript("OnClick", function()
        local ok, result = EbonBuilds.Calibration.ApplyPendingReview()
        if ok then
            EbonBuilds.Toast.Show("Tuning proposal applied as a new strategy revision")
        else
            EbonBuilds.Toast.Show(result)
        end
        EbonBuilds.Calibration.RefreshWindow()
    end)

    proposalDismissBtn = EbonBuilds.Theme.CreateButton(f, "danger")
    proposalDismissBtn:SetSize(88, 22)
    proposalDismissBtn:SetPoint("LEFT", proposalApplyBtn, "RIGHT", 6, 0)
    proposalDismissBtn:SetText("Discard")
    proposalDismissBtn:SetScript("OnClick", function()
        EbonBuilds.Calibration.DismissPendingReview()
        EbonBuilds.Toast.Show("Tuning proposal discarded")
        EbonBuilds.Calibration.RefreshWindow()
    end)

    f._autoTuneCB = autoTuneCB
    f._perfCB = perfCB
    f._appearCB = appearCB
    f._weightCB = weightCB
    tinsert(UISpecialFrames, "EbonBuildsTuningAdvisorWindow")
    f:Hide()
    return f
end

function EbonBuilds.Calibration.RefreshWindow()
    if not frame then return end
    if frame._autoTuneCB then
        frame._autoTuneCB:SetChecked(EbonBuilds.Calibration.IsAutoTuneEnabled())
    end
    if frame._perfCB then
        frame._perfCB:SetChecked(EbonBuilds.EchoPerformance.IsEnabled())
    end
    if frame._appearCB then
        frame._appearCB:SetChecked(EbonBuilds.Calibration.IsAppearanceSharingEnabled())
    end
    if frame._weightCB then
        frame._weightCB:SetChecked(EbonBuilds.Calibration.IsAutoApplyWeightsEnabled())
    end
    local build = EbonBuilds.Build.GetActive()
    if not build then
        modeWarning:SetText("No active build selected.")
        ClearRow(banishRow)
        ClearRow(rerollRow)
        ClearRow(freezeRow)
        countLabel:SetText("")
        proposalLabel:SetText("")
        proposalApplyBtn:Hide()
        proposalDismissBtn:Hide()
        return
    end
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    if (settings.rerollMode or "sum") == "ev" then
        modeWarning:SetText("Smart (EV) mode.")
        RefreshRow(banishRow, EbonBuilds.Calibration.SuggestSmartBanish(settings), "banishEVPct", "Smart Banish")
        RefreshRow(rerollRow, EbonBuilds.Calibration.SuggestSmartReroll(settings), "rerollEVPct", "Smart Reroll")
        RefreshRow(freezeRow, EbonBuilds.Calibration.SuggestSmartFreeze(settings), "freezeEVPct", "Smart Freeze")
    else
        modeWarning:SetText("Classic mode.")
        RefreshRow(banishRow, EbonBuilds.Calibration.SuggestBanish(settings), "autoBanishPct", "Banish")
        RefreshRow(rerollRow, EbonBuilds.Calibration.SuggestReroll(settings), "autoRerollPct", "Reroll")
        RefreshRow(freezeRow, EbonBuilds.Calibration.SuggestFreeze(settings), "autoFreezePct", "Freeze")
    end
    local countText = string.format("%d samples (%d best-offer) collected for %s",
        EbonBuilds.Calibration.SampleCount(), EbonBuilds.Calibration.BestSampleCount(), build.title or "this build")
    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled() then
        local weightSuggestions = EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
        if #weightSuggestions > 0 then
            countText = countText .. string.format(" -- %d weight suggestion(s) available, see Export (AI)", #weightSuggestions)
        end
    end
    countLabel:SetText(countText)

    local proposal, proposalStatus = EbonBuilds.Calibration.GetPendingReview()
    if proposalStatus == "READY" then
        proposalLabel:SetText("|cffffd100Proposal ready:|r " .. (proposal.summary or "review suggested changes"))
        proposalApplyBtn:Show()
        proposalDismissBtn:Show()
    elseif proposal then
        proposalLabel:SetText("|cffff7f50Stale proposal:|r the active build or strategy changed. Discard it and collect fresh evidence.")
        proposalApplyBtn:Hide()
        proposalDismissBtn:Show()
    else
        proposalLabel:SetText("No staged proposal. Manual threshold recommendations above remain available.")
        proposalApplyBtn:Hide()
        proposalDismissBtn:Hide()
    end
end

function EbonBuilds.Calibration.ShowWindow()
    if not frame then frame = BuildWindow() end
    EbonBuilds.Calibration.RefreshWindow()
    frame:Show()
end

------------------------------------------------------------------------
-- Ticker: drives the appearance-sharing broadcast independent of
-- combat state (unlike EchoPerformance's DPS sampling, this doesn't
-- need to be in combat to fire -- it's just periodically re-sending
-- already-collected counts).
------------------------------------------------------------------------

function EbonBuilds.Calibration.Init()
    EbonBuilds.Scheduler.Every("calibration.appearanceBroadcast", 1,
        EbonBuilds.Calibration.MaybeBroadcastAppearance, EbonBuilds.Scheduler.BACKGROUND, true)
end
