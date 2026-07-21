local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/EchoPerformance.lua
-- Responsibility: correlate currently-active echoes with real combat
-- performance (DPS), using Details! damage meter's public API, if
-- installed. Off by default -- this is explicitly a rough, approximate
-- signal (echoes stack, execution/gear/fight-type vary run to run), not
-- a controlled measurement. Meant as a SUPPLEMENT to the theoretical
-- scoring model and Tuning Advisor's offer-distribution data, surfaced
-- through Export (AI) so an external AI has real performance context
-- too, not a replacement for either.
--
-- Everything that touches Details! is pcall-wrapped and feature-detected
-- -- it's a separate, large, independently-updated addon EbonBuilds does
-- not control, and its exact internals can change between versions. Only
-- the documented public API (Details:GetCurrentCombat, combat:GetActor,
-- actor.total, combat:GetCombatTime -- see Details' own API.lua) is used.

EbonBuilds.EchoPerformance = {}

local SAMPLE_INTERVAL = 10  -- seconds between DPS samples while in combat
local MAX_SAMPLES_PER_ECHO = 200
local normalizedStoreRef
local dataRevision = 0
local allStatsCacheRevision = -1
local allStatsCache

local function BumpRevision()
    dataRevision = dataRevision + 1
    allStatsCacheRevision = -1
    allStatsCache = nil
end

local function CanonicalEchoName(value)
    if value == nil then return nil end
    local numeric = type(value) == "number" and value
        or (type(value) == "string" and value:match("^%d+$") and tonumber(value))
    if numeric then
        local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(numeric)
        return variant and (variant.displayName or variant.sourceName)
            or EbonBuilds.Weights.CanonicalName(numeric)
            or (GetSpellInfo and GetSpellInfo(numeric))
    end

    local name = EbonBuilds.Weights.StripQualitySuffix(tostring(value))
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindLegacyRefs
        and EbonBuilds.EchoCatalog.FindLegacyRefs(name) or {}
    if #refs == 1 then
        local definition = EbonBuilds.EchoCatalog.GetByRef(refs[1])
        return definition and (definition.displayName or definition.sourceName) or name
    end
    -- Ambiguous runtime aliases are not canonicalized. Keeping the literal
    -- legacy key prevents Crimson Reprisal and Blood Mirror data from merging.
    return name
end

local function NormalizeStoreKeys(store)
    local moves = {}
    for rawName, entry in pairs(store) do
        local canonical = CanonicalEchoName(rawName)
        if canonical and canonical ~= rawName and type(entry) == "table" then
            moves[#moves + 1] = { raw = rawName, canonical = canonical, entry = entry }
        end
    end
    for _, move in ipairs(moves) do
        local target = store[move.canonical]
        if type(target) ~= "table" then target = { sum = 0, count = 0 } end
        target.sum = (tonumber(target.sum) or 0) + (tonumber(move.entry.sum) or 0)
        target.count = (tonumber(target.count) or 0) + (tonumber(move.entry.count) or 0)
        store[move.canonical] = target
        store[move.raw] = nil
    end
    return store
end

local function GetStore()
    EbonBuildsCharDB.echoPerformance = EbonBuildsCharDB.echoPerformance or {}
    local store = EbonBuildsCharDB.echoPerformance
    if normalizedStoreRef ~= store then
        NormalizeStoreKeys(store)
        normalizedStoreRef = store
    end
    return store
end

local function GrantedEchoName(key, value)
    local spellId = tonumber(key)
    if not spellId and type(value) == "table" then spellId = value.spellId or value.id end
    if spellId then return CanonicalEchoName(spellId) end
    local name = type(key) == "string" and key
        or (type(value) == "string" and value)
        or (type(value) == "table" and value.name)
    return CanonicalEchoName(name)
end

function EbonBuilds.EchoPerformance.IsEnabled()
    local consent = EbonBuildsCharDB.consent
    return consent and (tonumber(consent.performanceVersion) or 0) >= 1 and consent.performanceEnabled == true
end

function EbonBuilds.EchoPerformance.SetEnabled(on)
    EbonBuildsCharDB.consent = EbonBuildsCharDB.consent or {}
    EbonBuildsCharDB.consent.performanceVersion = 1
    EbonBuildsCharDB.consent.performanceEnabled = on and true or false
    EbonBuildsCharDB.consent.communityDpsSharing = on and true or false
    EbonBuildsCharDB.echoPerformanceEnabled = nil
end

function EbonBuilds.EchoPerformance.IsDetailsAvailable()
    return Details ~= nil and Details.GetCurrentCombat ~= nil
end

function EbonBuilds.EchoPerformance.Clear()
    EbonBuildsCharDB.echoPerformance = {}
    EbonBuildsCharDB.echoPerformanceCommunity = {}
    normalizedStoreRef = nil
    BumpRevision()
end

-- Current player DPS this combat, or nil if unavailable (not in combat,
-- Details not installed, or its API returned something unexpected --
-- any of which are just "no sample this tick", never an error).
local function GetCurrentDPS()
    if not EbonBuilds.EchoPerformance.IsDetailsAvailable() then return nil end
    local ok, dps = pcall(function()
        local combat = Details:GetCurrentCombat()
        if not combat then return nil end
        local playerName = UnitName("player")
        local actor = combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE, playerName)
        if not actor or not actor.total then return nil end
        -- Prefer "activity time" (actor:Tempo(), excludes idle/movement
        -- gaps within the combat window) over "effective time"
        -- (combat:GetCombatTime(), the whole window including those
        -- gaps) -- Details' own docs distinguish the two, and activity
        -- time is the less noisy signal: two players with identical
        -- actual damage output but different amounts of downtime would
        -- otherwise show different DPS for reasons that have nothing to
        -- do with what echoes were active.
        local activeTime = actor.Tempo and actor:Tempo()
        if activeTime and activeTime > 0 then
            return actor.total / activeTime
        end
        local combatTime = combat:GetCombatTime()
        if not combatTime or combatTime <= 0 then return nil end
        return actor.total / combatTime
    end)
    if ok and type(dps) == "number" and dps >= 0 then return dps end
    return nil
end

-- Records one DPS sample against every currently-granted (active this
-- run) echo. Called by the sample ticker; safe to call even if disabled
-- or Details isn't installed (both are no-ops).
function EbonBuilds.EchoPerformance.Sample()
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    if not (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks) then return end
    local dps = GetCurrentDPS()
    if not dps then return end

    local granted = ProjectEbonhold.PerkService.GetGrantedPerks() or {}
    local store = GetStore()
    local changed = false
    -- New model: one whole-set sample per tick (every active echo
    -- together with this DPS reading) into EchoSamples -- the honest
    -- basis for with/without analysis. The legacy per-echo sum/count
    -- below keeps accumulating during the migration window so existing
    -- consumers stay functional until they've all moved to
    -- EchoSamples.EvidenceValue; it is scheduled for removal.
    local setNames = {}
    for key, value in pairs(granted) do
        local n = GrantedEchoName(key, value)
        if n then setNames[#setNames + 1] = n end
    end
    if #setNames > 0 then
        EbonBuilds.EchoSamples.Record(setNames, dps)
    end
    for key, value in pairs(granted) do
        local name = GrantedEchoName(key, value)
        if name then
            local entry = store[name]
            if not entry then
                entry = { sum = 0, count = 0 }
                store[name] = entry
            end
            entry.sum = entry.sum + dps
            entry.count = entry.count + 1
            changed = true
            -- Cap by halving instead of dropping oldest one-by-one -- cheap,
            -- and keeps the running average meaningful rather than
            -- discarding history outright.
            if entry.count > MAX_SAMPLES_PER_ECHO then
                entry.sum = entry.sum / 2
                entry.count = math.floor(entry.count / 2)
            end
        end
    end
    if changed then BumpRevision() end
end

------------------------------------------------------------------------
-- Community sharing (opt-in via the same "Track DPS by echo" toggle)
--
-- Broadcasts aggregate {sum, count} per echo -- never raw samples -- to
-- other EbonBuilds users of the SAME class over the existing sync
-- channel, and merges what they broadcast back into a separate
-- "community" pool. GetStats() below returns personal + community
-- combined, which is what weight suggestions and Export (AI) read.
--
-- Idempotent by design: each sender's contribution is stored keyed by
-- sender name and REPLACED (not added to) on every receive, so a peer
-- re-broadcasting the same totals repeatedly can't inflate the merged
-- result -- the community total is always the sum of each currently-
-- known peer's most recent reported {sum, count}, not a running total
-- of every message ever received.
------------------------------------------------------------------------

local MAX_TRUSTED_COUNT_PER_ECHO = 500        -- reject a single peer claiming more samples than this for one echo
local MAX_TRUSTED_DPS            = 50000000   -- reject implausibly large avg DPS (sanity ceiling, not a real limit)
local MAX_COMMUNITY_PEERS        = 50
local MAX_ECHOES_PER_PEER        = 500
local BROADCAST_BATCH_SIZE       = 6          -- echoes per broadcast -- keeps each channel message short
local BROADCAST_INTERVAL         = 180        -- seconds between broadcasts

local function GetCommunityStore()
    EbonBuildsCharDB.echoPerformanceCommunity = EbonBuildsCharDB.echoPerformanceCommunity or {}
    return EbonBuildsCharDB.echoPerformanceCommunity
end

-- Called when a PRF broadcast is received from another player. class must
-- match the currently active build's class -- echo pools and typical DPS
-- differ by class, so cross-class data would just be noise, not signal.
function EbonBuilds.EchoPerformance.MergeCommunityContribution(sender, class, name, sum, count)
    if not (sender and class and name and sum and count) then return end
    name = CanonicalEchoName(name)
    if not name then return end
    local normalizePlayer = EbonBuilds.Build and EbonBuilds.Build._NormalizePlayerName
        or function(v) return tostring(v or ""):lower():match("^([^-]+)") end
    if normalizePlayer(sender) == normalizePlayer(UnitName("player")) then return end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or build.class ~= class then return end
    count = tonumber(count)
    sum = tonumber(sum)
    if not count or not sum or count <= 0 or count > MAX_TRUSTED_COUNT_PER_ECHO then return end
    local avg = sum / count
    if avg < 0 or avg > MAX_TRUSTED_DPS then return end

    local store = GetCommunityStore()
    local senderKey = normalizePlayer(sender)
    store[senderKey] = store[senderKey] or {}
    local contributions = store[senderKey]
    if not contributions[name] then
        local echoCount = 0
        for echoName, entry in pairs(contributions) do
            if echoName ~= "_lastSeenAt" and type(entry) == "table" then echoCount = echoCount + 1 end
        end
        if echoCount >= MAX_ECHOES_PER_PEER then return end
    end
    contributions[name] = { sum = sum, count = count }
    contributions._lastSeenAt = time()
    local peers = {}
    for peer, entries in pairs(store) do
        peers[#peers + 1] = { peer = peer, seen = tonumber(entries._lastSeenAt) or 0 }
    end
    if #peers > MAX_COMMUNITY_PEERS then
        table.sort(peers, function(a, b) return a.seen > b.seen end)
        for index = MAX_COMMUNITY_PEERS + 1, #peers do store[peers[index].peer] = nil end
    end
    BumpRevision()
end

-- One aggregate snapshot replaces the previous per-Echo community scan.
-- Stats views and recommendation passes can now read every Echo in O(1)
-- after one linear aggregation of the personal/community stores.
function EbonBuilds.EchoPerformance.GetAllStats()
    if allStatsCache and allStatsCacheRevision == dataRevision then return allStatsCache end

    local totals = {}
    local function Add(name, sum, count, personal)
        name = CanonicalEchoName(name)
        count = tonumber(count) or 0
        sum = tonumber(sum) or 0
        if not name or count <= 0 then return end
        local entry = totals[name]
        if not entry then
            entry = { personalSum = 0, personalCount = 0, communitySum = 0, communityCount = 0 }
            totals[name] = entry
        end
        if personal then
            entry.personalSum = entry.personalSum + sum
            entry.personalCount = entry.personalCount + count
        else
            entry.communitySum = entry.communitySum + sum
            entry.communityCount = entry.communityCount + count
        end
    end

    for name, entry in pairs(GetStore()) do
        if type(entry) == "table" then Add(name, entry.sum, entry.count, true) end
    end
    for _, contributions in pairs(GetCommunityStore()) do
        for name, entry in pairs(contributions or {}) do
            if type(entry) == "table" then Add(name, entry.sum, entry.count, false) end
        end
    end

    local snapshot = {}
    for name, entry in pairs(totals) do
        local totalSum = entry.personalSum + entry.communitySum
        local totalCount = entry.personalCount + entry.communityCount
        if totalCount > 0 then
            snapshot[name] = {
                avgDPS = totalSum / totalCount,
                sampleCount = totalCount,
                personalCount = entry.personalCount,
                communityCount = entry.communityCount,
            }
        end
    end
    allStatsCache = snapshot
    allStatsCacheRevision = dataRevision
    return snapshot
end

function EbonBuilds.EchoPerformance.GetStats(name)
    name = CanonicalEchoName(name)
    if not name then return nil end
    return EbonBuilds.EchoPerformance.GetAllStats()[name]
end

function EbonBuilds.EchoPerformance.GetRevision()
    return dataRevision
end

------------------------------------------------------------------------
-- Wire format: PRF|<class>|name1:sum1:count1;name2:sum2:count2;...
-- Kept deliberately short (a handful of echoes per message) since this
-- goes out over the same chat-channel-based transport builds sync over.
------------------------------------------------------------------------

function EbonBuilds.EchoPerformance.SerializeBatch(class, names)
    if not class or not names or #names == 0 then return nil end
    local store = GetStore()
    local parts = {}
    for _, name in ipairs(names) do
        local entry = store[name]
        if entry and entry.count > 0 then
            parts[#parts + 1] = string.format("%s:%.0f:%d", name, entry.sum, entry.count)
        end
    end
    if #parts == 0 then return nil end
    return "PRF|" .. class .. "|" .. table.concat(parts, ";")
end

function EbonBuilds.EchoPerformance.ParseBatch(payload)
    local class, body = payload:match("^PRF|([^|]+)|(.+)$")
    if not class then return nil end
    local entries = {}
    for entry in body:gmatch("[^;]+") do
        local name, sum, count = entry:match("^(.+):(%-?%d+%.?%d*):(%d+)$")
        if name then
            entries[#entries + 1] = { name = name, sum = tonumber(sum), count = tonumber(count) }
        end
    end
    return class, entries
end

-- Called by the receiving side (Sync.lua's channel dispatcher) for every
-- incoming PRF message.
function EbonBuilds.EchoPerformance.HandleBroadcast(payload, sender)
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    local class, entries = EbonBuilds.EchoPerformance.ParseBatch(payload)
    if not class then return end
    for _, e in ipairs(entries) do
        EbonBuilds.EchoPerformance.MergeCommunityContribution(sender, class, e.name, e.sum, e.count)
    end
end

------------------------------------------------------------------------
-- Broadcast rotation: cycles through known echoes a few at a time so no
-- single message needs to carry the whole table.
------------------------------------------------------------------------

local broadcastElapsed = 0
local broadcastCursor = 1

-- Sends one rotating batch. Shared by the automatic timer path and the
-- manual "Sync Now" button -- same batching logic either way, so a
-- manual sync can't accidentally send a differently-shaped payload than
-- what a peer's automatic receive handler expects.
local function SendOneBatch()
    if not (EbonBuilds.Sync and EbonBuilds.Sync.BroadcastPerfBatch) then return false end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or not build.class then return false end

    local store = GetStore()
    local names = {}
    for name in pairs(store) do names[#names + 1] = name end
    if #names == 0 then return false end
    table.sort(names) -- stable order so the rotation actually cycles through everything

    local batch = {}
    for i = 1, BROADCAST_BATCH_SIZE do
        local idx = ((broadcastCursor - 1 + i - 1) % #names) + 1
        batch[#batch + 1] = names[idx]
    end
    broadcastCursor = ((broadcastCursor - 1 + BROADCAST_BATCH_SIZE) % #names) + 1

    local payload = EbonBuilds.EchoPerformance.SerializeBatch(build.class, batch)
    if not payload then return false end
    EbonBuilds.Sync.BroadcastPerfBatch(payload)
    return true
end

local function MaybeBroadcast(dt)
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    broadcastElapsed = broadcastElapsed + dt
    if broadcastElapsed < BROADCAST_INTERVAL then return end
    broadcastElapsed = 0
    SendOneBatch()
end

-- Manual trigger: sends a few batches back-to-back right away instead of
-- waiting for the periodic timer, and resets the timer so the next
-- automatic broadcast doesn't fire immediately after. Capped at a few
-- batches rather than everything at once, so clicking it can't flood
-- the sync channel the way a single giant payload would.
local SYNC_NOW_MAX_BATCHES = 3

function EbonBuilds.EchoPerformance.SyncNow()
    if not EbonBuilds.EchoPerformance.IsEnabled() then
        return false, "DPS sharing is off"
    end
    broadcastElapsed = 0
    local sent = 0
    for i = 1, SYNC_NOW_MAX_BATCHES do
        if not SendOneBatch() then break end
        sent = sent + 1
    end
    if sent == 0 then return false, "nothing to sync yet" end
    return true, sent
end

------------------------------------------------------------------------
-- Weight suggestions (read-only report, not auto-applied)
--
-- Compares each echo's average DPS against the average of OTHER echoes
-- that currently share its exact weight value (its "tier") -- notably
-- over/under-performing echoes within a tier are flagged with a small,
-- capped nudge suggestion. Deliberately NOT auto-applied like the
-- threshold Tuning Advisor: weight changes are a bigger, more visible
-- intervention, and this data is noisier (fight difficulty/duration
-- varies, and see EchoPerformance's co-active cluster limitation) --
-- this is meant to be read and judged, not blindly trusted.
--
-- Only echoes with a fully unique DPS+sample-count signature are
-- considered (MAX_CLUSTER_SIZE_TO_TRUST = 1). Originally this allowed
-- small clusters (up to 3) on the assumption that a couple of echoes
-- briefly overlapping was a coincidence -- real data showed 2-3 member
-- clusters are actually the common case (any two echoes active across
-- the same handful of fights end up sharing a signature), so most
-- "suggestions" at that looser threshold were really one data point
-- duplicated across indistinguishable echoes, not independent evidence.
------------------------------------------------------------------------

local MIN_SAMPLES_FOR_WEIGHT_SUGGESTION = 8  -- per-echo, before it's considered at all
local MIN_TIER_BASELINE_SIZE = 2             -- how many clean data points a tier needs to have a baseline
local MAX_CLUSTER_SIZE_TO_TRUST = 1          -- an echo's DPS signature must be unique (shared with nobody else) to be trusted for a weight suggestion
local WEIGHT_SUGGESTION_DEVIATION = 0.25     -- min fractional deviation from tier average to flag
local WEIGHT_NUDGE = 10                      -- fixed, modest suggested adjustment

-- Returns a sorted list of { name, currentWeight, suggestedWeight,
-- deviationPct, tierAvgDPS, avgDPS, sampleCount }, largest deviation
-- first. Empty list if there isn't enough clean data to say anything.
-- Delta-based replacement for GetAllStats as the SUGGESTION data
-- source. Same shape ({ avgDPS, sampleCount } per echo) so the tier
-- baseline / nudge math downstream applies unchanged -- but avgDPS is
-- now the with/without delta from whole-set samples, not the confounded
-- per-echo average, sampleCount is the weaker side of the split, and
-- an echo appears at all only when the evidence is reliable AND the
-- echo is DPS-relevant (pure-utility echoes -- the mount-speed case --
-- are excluded from attribution by design).
function EbonBuilds.EchoPerformance.GetEvidenceStats()
    local out = {}
    if not (EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildBestByName) then return out end
    for name in pairs(EbonBuilds.EchoTableRows.BuildBestByName()) do
        local value, kind, d = EbonBuilds.EchoSamples.EvidenceValue(name)
        if value ~= nil and kind == "delta" then
            out[name] = {
                avgDPS = value,
                sampleCount = math.min(d.nWith, d.nWithout),
                evidence = "delta",
                nWith = d.nWith,
                nWithout = d.nWithout,
            }
        end
    end
    return out
end

function EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
    if not build or not build.class or not EbonBuilds.EchoProjection then return {} end
    local allStats = EbonBuilds.EchoPerformance.GetEvidenceStats()

    -- The canonical class projection is the only eligibility universe.
    local signatureCounts = {}
    local rawEntries = {}
    for _, info in ipairs(EbonBuilds.EchoProjection.GetAvailable(build.class)) do
        local name = info.displayName or info.name
        local perf = name and allStats[name]
        if perf and perf.sampleCount >= MIN_SAMPLES_FOR_WEIGHT_SUGGESTION then
            local sig = string.format("%.2f|%d", perf.avgDPS, perf.sampleCount)
            signatureCounts[sig] = (signatureCounts[sig] or 0) + 1
            local strongest = nil
            for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                if info.qualities and info.qualities[quality] then
                    local value = EbonBuilds.Weights.GetForRef(build, info.refKey, quality) or 0
                    if strongest == nil or value > strongest then strongest = value end
                end
            end
            rawEntries[#rawEntries + 1] = {
                refKey = info.refKey,
                name = name,
                weight = strongest or 0,
                qualities = info.qualities,
                avgDPS = perf.avgDPS,
                sampleCount = perf.sampleCount,
                sig = sig,
            }
        end
    end

    -- Tier baselines, computed only from entries NOT in a large cluster
    -- (so one inflated/deflated group doesn't skew the whole tier).
    local tierSum, tierAbsSum, tierCount = {}, {}, {}
    for _, e in ipairs(rawEntries) do
        if signatureCounts[e.sig] <= MAX_CLUSTER_SIZE_TO_TRUST then
            tierSum[e.weight] = (tierSum[e.weight] or 0) + e.avgDPS
            tierAbsSum[e.weight] = (tierAbsSum[e.weight] or 0) + math.abs(e.avgDPS)
            tierCount[e.weight] = (tierCount[e.weight] or 0) + 1
        end
    end

    local suggestions = {}
    for _, e in ipairs(rawEntries) do
        local n = tierCount[e.weight] or 0
        if signatureCounts[e.sig] <= MAX_CLUSTER_SIZE_TO_TRUST and n >= MIN_TIER_BASELINE_SIZE then
            local tierAvg = tierSum[e.weight] / n
            -- Values are with/without DELTAS now, which legitimately sit
            -- around (or below) zero -- deviation is therefore normalized
            -- by the tier's typical delta magnitude, not the mean itself.
            local scale = tierAbsSum[e.weight] / n
            if scale > 0 then
                local deviation = (e.avgDPS - tierAvg) / scale
                if math.abs(deviation) >= WEIGHT_SUGGESTION_DEVIATION then
                    local delta = deviation > 0 and WEIGHT_NUDGE or -WEIGHT_NUDGE
                    suggestions[#suggestions + 1] = {
                        refKey = e.refKey,
                        name = e.name,
                        quality = nil,
                        qualities = e.qualities,
                        applyAllRanks = true,
                        delta = delta,
                        currentWeight = e.weight,
                        suggestedWeight = math.max(EbonBuilds.Weights.MIN_VALUE, math.min(EbonBuilds.Weights.MAX_VALUE, e.weight + delta)),
                        deviationPct = deviation * 100,
                        tierAvgDPS = tierAvg,
                        avgDPS = e.avgDPS,
                        sampleCount = e.sampleCount,
                    }
                end
            end
        end
    end

    table.sort(suggestions, function(a, b) return math.abs(a.deviationPct) > math.abs(b.deviationPct) end)
    return suggestions
end

------------------------------------------------------------------------
-- Quality bonus suggestions (experimental, report only -- no auto-apply
-- path exists for this yet, unlike per-echo weights).
--
-- Different question from per-echo weight suggestions: instead of "is
-- this ONE echo over/under-weighted relative to its peers," this asks
-- "is a whole QUALITY TIER systematically over/under-delivering relative
-- to its weight, in a way a single global Quality Bonus number might be
-- able to fix." Compares each tier's average DPS-per-weight-point
-- against the overall average across all weighted, tracked echoes.
--
-- Rationale for direction: the denominator is the same final score used by
-- automation (base rank value plus quality/family modifiers, without novelty).
-- If a tier still delivers above-average DPS per score point, its value may be
-- under-represented; below-average suggests its additive quality modifier may
-- be too generous. Multiplicative quality modes are skipped because an
-- additive nudge would be ambiguous there.
--
-- Deliberately conservative: needs more distinct echoes per tier than a
-- single-echo weight suggestion does (aggregating many echoes into one
-- number is a bigger generalization), and the suggested nudge is small,
-- since a bonus change affects every echo of that quality simultaneously
-- rather than just one.
------------------------------------------------------------------------

local MIN_ECHOES_PER_TIER_FOR_BONUS = 5
local BONUS_DEVIATION_THRESHOLD = 0.25
local BONUS_NUDGE = 3


-- Returns a sorted list of { quality, qualityLabel, currentBonus,
-- suggestedBonus, deviationPct, tierEchoCount }, or {} if there isn't
-- enough data across enough distinct tiers to say anything.
function EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment(build)
    if not build or not build.class or not EbonBuilds.EchoProjection then return {} end
    local allStats = EbonBuilds.EchoPerformance.GetEvidenceStats()

    local signatureCounts = {}
    local raw = {}
    for _, info in ipairs(EbonBuilds.EchoProjection.GetAvailable(build.class)) do
        local name = info.displayName or info.name
        local perf = name and allStats[name]
        for _, variant in ipairs(info.availableVariants or {}) do
            local quality = tonumber(variant.quality) or 0
            local baseWeight = EbonBuilds.Weights.GetForRef(build, info.refKey, quality) or 0
            local score = EbonBuilds.Scoring.ScorePerQuality({
                refKey = info.refKey, spellId = variant.spellId, name = name,
                quality = quality, families = variant.families or info.families,
            }, baseWeight, build.settings or EbonBuilds.Build.DefaultSettings(), quality)
            if score > 0 and perf and perf.sampleCount >= MIN_SAMPLES_FOR_WEIGHT_SUGGESTION then
                local sig = string.format("%.2f|%d", perf.avgDPS, perf.sampleCount)
                signatureCounts[sig] = (signatureCounts[sig] or 0) + 1
                raw[#raw + 1] = { name = name, refKey = info.refKey, quality = quality, ratio = perf.avgDPS / score, sig = sig }
            end
        end
    end

    local tierSum, tierCount = {}, {}
    local globalSum, globalAbsSum, globalCount = 0, 0, 0
    for _, e in ipairs(raw) do
        if signatureCounts[e.sig] <= MAX_CLUSTER_SIZE_TO_TRUST then
            tierSum[e.quality] = (tierSum[e.quality] or 0) + e.ratio
            tierCount[e.quality] = (tierCount[e.quality] or 0) + 1
            globalSum = globalSum + e.ratio
            globalAbsSum = globalAbsSum + math.abs(e.ratio)
            globalCount = globalCount + 1
        end
    end
    if globalCount < MIN_ECHOES_PER_TIER_FOR_BONUS then return {} end
    -- Ratios are built on with/without DELTAS now: each value already
    -- means "runs with this echo minus runs without it", so ZERO is the
    -- natural reference line -- a tier with a clearly negative mean
    -- delta deserves a downward nudge regardless of how other tiers
    -- look (and after the utility filter, a single surviving tier must
    -- still be judgeable at all). Normalized by typical magnitude.
    local scale = globalAbsSum / globalCount
    if scale <= 0 then return {} end

    local settings = build.settings or {}
    local suggestions = {}
    for quality, count in pairs(tierCount) do
        if count >= MIN_ECHOES_PER_TIER_FOR_BONUS then
            local tierAvg = tierSum[quality] / count
            local deviation = tierAvg / scale
            if math.abs(deviation) >= BONUS_DEVIATION_THRESHOLD
                and not ((settings.qualityBonusMode or {})[quality]) then
                local currentBonus = (settings.qualityBonus and settings.qualityBonus[quality]) or 0
                local nudge = deviation > 0 and BONUS_NUDGE or -BONUS_NUDGE
                suggestions[#suggestions + 1] = {
                    quality = quality,
                    qualityLabel = (EbonBuilds.Quality.LABELS or {})[quality] or tostring(quality),
                    currentBonus = currentBonus,
                    suggestedBonus = math.max(-9999, math.min(9999, currentBonus + nudge)),
                    deviationPct = deviation * 100,
                    tierEchoCount = count,
                }
            end
        end
    end
    return suggestions
end

------------------------------------------------------------------------
-- Family Bonus suggestions (experimental, report only -- no auto-apply).
--
-- Same DPS-per-weight-point comparison as Quality Bonus, but family is a
-- harder attribution problem: an echo can belong to SEVERAL families at
-- once (e.g. "Caster DPS/Melee DPS/Ranged DPS/Tank"), and Scoring.lua's
-- ApplyFamilyBonuses stacks every matching family's bonus onto the same
-- score in sequence -- so a 4-family echo's score reflects FOUR bonuses
-- compounded together, not one. Cleanly separating out each family's own
-- marginal contribution from that would need real multi-variate
-- regression across every echo's family membership.
--
-- Deliberately sidesteps that instead of attempting it: only echoes with
-- EXACTLY ONE matching family (or explicitly none, i.e. "No family") are
-- used at all. This throws away real data from multi-family echoes, but
-- keeps every comparison unambiguous -- consistent with how co-active
-- clusters are excluded from weight suggestions rather than guessed at.
------------------------------------------------------------------------

local FAMILY_BONUS_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

-- Returns the single normalized family this echo belongs to, "No family"
-- if it belongs to none, or nil if it belongs to more than one (the
-- ambiguous case this function refuses to use).
-- Family Bonus suggestions, rebuilt on family-level with/without
-- evidence (EchoSamples.FamilyDelta). The old path went per-echo:
-- average each echo, keep only single-family ones (multi-family
-- echoes were EXCLUDED because a per-echo number can't attribute a
-- stacked modifier), then compare family means of those ratios. Set
-- membership dissolves that: a run either contains the family or it
-- doesn't, so every echo -- multi-family included -- contributes to
-- every family it belongs to, and the delta is read directly against
-- the zero line. Non-damage families get no DPS-based suggestions at
-- all; DPS evidence says nothing about tanking value.
function EbonBuilds.EchoPerformance.SuggestFamilyBonusAdjustment(build)
    if not build or not build.class then return {} end
    if not (EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildBestByName) then return {} end

    -- Scale: typical reliable family-delta magnitude, so the deviation
    -- threshold means the same thing regardless of the class's DPS level.
    local deltas = {}
    local absSum, absCount = 0, 0
    for _, familyId in ipairs(EbonBuilds.Families.OrderedIds()) do
        if EbonBuilds.Families.IsDps(familyId) then
            local d = EbonBuilds.EchoSamples.FamilyDelta(familyId)
            if d and d.reliable then
                deltas[#deltas + 1] = d
                absSum = absSum + math.abs(d.delta)
                absCount = absCount + 1
            end
        end
    end
    if absCount == 0 then return {} end
    local scale = absSum / absCount
    if scale <= 0 then return {} end

    local settings = build.settings or {}
    local suggestions = {}
    for _, d in ipairs(deltas) do
        local deviation = d.delta / scale
        if math.abs(deviation) >= BONUS_DEVIATION_THRESHOLD then
            local currentBonus = (settings.familyBonus and settings.familyBonus[d.family]) or 0
            local nudge = deviation > 0 and BONUS_NUDGE or -BONUS_NUDGE
            suggestions[#suggestions + 1] = {
                family = d.family,
                currentBonus = currentBonus,
                suggestedBonus = currentBonus + nudge,
                delta = d.delta,
                deviationPct = deviation * 100,
                nWith = d.nWith,
                nWithout = d.nWithout,
                sampleCount = math.min(d.nWith, d.nWithout),
            }
        end
    end
    table.sort(suggestions, function(a, b) return math.abs(a.deviationPct) > math.abs(b.deviationPct) end)
    return suggestions
end

-- Restored after the family-suggestion rewrite accidentally swept it
-- away with the old function body -- find-orphans caught Sample() going
-- caller-less, which in-game would have silently stopped all sampling.
local elapsed = 0
local function OnTick(dt)
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    MaybeBroadcast(dt)
    if not UnitAffectingCombat("player") then return end
    elapsed = elapsed + dt
    if elapsed < SAMPLE_INTERVAL then return end
    elapsed = 0
    EbonBuilds.EchoPerformance.Sample()
end

function EbonBuilds.EchoPerformance.Init()
    -- Explicit consent only. Opening the advisor shows the opt-in control;
    -- installing or upgrading never starts combat sampling by itself.
    EbonBuildsCharDB.echoPerformanceEnabled = nil
    EbonBuilds.Scheduler.Every("performance.sample", 1, OnTick,
        EbonBuilds.Scheduler.BACKGROUND, true)
end
