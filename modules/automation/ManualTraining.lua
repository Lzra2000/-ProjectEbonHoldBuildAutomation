local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/ManualTraining.lua
-- Responsibility: learn from the player's manual Echo choices without acting.
-- Manual Training is opt-in per build. While active, Automation.Evaluate()
-- yields to the native picker and this module compares the player's choice
-- with the scores EbonBuilds would have used.
--
-- Rank-aware storage is required because Echo weights are configured
-- independently for Common, Uncommon, Rare, and Epic. Legacy 2.57 stores that
-- only recorded an Echo name remain readable and produce an all-ranks nudge.

EbonBuilds.ManualTraining = {}

local M = EbonBuilds.ManualTraining
local MIN_NET_DISAGREEMENTS = 3
local WEIGHT_NUDGE = 10
local suggestionCache = {}

local function GetStore(buildId)
    EbonBuildsCharDB.manualTraining = EbonBuildsCharDB.manualTraining or {}
    local store = EbonBuildsCharDB.manualTraining[buildId]
    if type(store) ~= "table" then
        store = {}
        EbonBuildsCharDB.manualTraining[buildId] = store
    end
    store.version = 3
    store.preferredOverHigher = type(store.preferredOverHigher) == "table" and store.preferredOverHigher or {}
    store.passedOverForLower  = type(store.passedOverForLower) == "table" and store.passedOverForLower or {}
    store.totalSelects = tonumber(store.totalSelects) or 0
    return store
end

function M.IsEnabled(build)
    return build and EbonBuilds.Build.IsTrainingEnabled(build)
end

function M.SetEnabled(build, on)
    if not build then return end
    EbonBuilds.Build.SetTrainingEnabled(build, on and true or false)
end

function M.Clear(buildId)
    if not buildId then return end
    EbonBuildsCharDB.manualTraining = EbonBuildsCharDB.manualTraining or {}
    EbonBuildsCharDB.manualTraining[buildId] = nil
    suggestionCache[buildId] = nil
end

function M.GetSampleCount(buildId)
    if not buildId then return 0 end
    local store = EbonBuildsCharDB.manualTraining and EbonBuildsCharDB.manualTraining[buildId]
    return store and tonumber(store.totalSelects) or 0
end

local function IncrementSignal(bucket, name, quality)
    if not name then return end
    local entry = bucket[name]
    -- Legacy stores used a number directly under the Echo name. Preserve that
    -- signal under `legacy` when the first rank-aware observation arrives.
    if type(entry) == "number" then
        entry = { legacy = entry }
    elseif type(entry) ~= "table" then
        entry = {}
    end
    local key = quality ~= nil and quality or "legacy"
    entry[key] = (tonumber(entry[key]) or 0) + 1
    bucket[name] = entry
end

local function OnPlayerSelect(pickedSpellId)
    local build = EbonBuilds.Build.GetActive()
    if not build or not M.IsEnabled(build) then return end
    local svc = ProjectEbonhold and ProjectEbonhold.PerkService
    if not (svc and svc.GetCurrentChoice) then return end
    local choices = svc.GetCurrentChoice()
    if not choices or #choices == 0 then return end
    if not (EbonBuilds.Automation and EbonBuilds.Automation._ScoreChoice) then return end

    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local scored, picked = {}, nil
    for index, choice in ipairs(choices) do
        local s = EbonBuilds.Automation._ScoreChoice(choice, settings)
        if s then
            s.index = index
            scored[#scored + 1] = s
            if choice.spellId == pickedSpellId then picked = s end
        end
    end
    if not picked or #scored < 2 then return end

    if EbonBuilds.Session and EbonBuilds.Session.LogAction then
        EbonBuilds.Session.LogAction(scored, "Manual Select", picked.index, "manual")
    end

    local store = GetStore(build.id)
    store.totalSelects = store.totalSelects + 1
    suggestionCache[build.id] = nil
    for _, offered in ipairs(scored) do
        if offered ~= picked and offered.score and picked.score and offered.score > picked.score then
            local pickedKey = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(picked.spellId)
            local offeredKey = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(offered.spellId)
            if pickedKey then IncrementSignal(store.preferredOverHigher, pickedKey, picked.quality) end
            if offeredKey then IncrementSignal(store.passedOverForLower, offeredKey, offered.quality) end
        end
    end
end


local function ResolveTrainingIdentity(value)
    if value == nil then return nil end
    value = tostring(value)
    if value:match("^[gs]:%d+$") then
        local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(value)
        if definition then return value, definition.displayName or definition.sourceName end
        return nil
    end
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindRefs
        and EbonBuilds.EchoCatalog.FindLegacyRefs(EbonBuilds.Weights.StripQualitySuffix(value)) or {}
    if #refs ~= 1 then return nil end
    local definition = EbonBuilds.EchoCatalog.GetByRef(refs[1])
    return refs[1], definition and (definition.displayName or definition.sourceName) or value
end

local function AddSignal(signals, storedKey, quality, direction, count)
    local refKey, displayName = ResolveTrainingIdentity(storedKey)
    count = tonumber(count) or 0
    if not refKey or count <= 0 then return end
    local key = refKey .. "\031" .. tostring(quality == nil and "legacy" or quality)
    local signal = signals[key]
    if not signal then
        signal = { refKey = refKey, name = displayName, quality = quality, raiseCount = 0, lowerCount = 0 }
        signals[key] = signal
    end
    if direction == "raise" then
        signal.raiseCount = signal.raiseCount + count
    else
        signal.lowerCount = signal.lowerCount + count
    end
end

local function ReadBucket(signals, bucket, direction)
    for name, entry in pairs(bucket or {}) do
        if type(entry) == "number" then
            AddSignal(signals, name, nil, direction, entry)
        elseif type(entry) == "table" then
            for rawQuality, count in pairs(entry) do
                local quality = rawQuality == "legacy" and nil or tonumber(rawQuality)
                if rawQuality == "legacy" or (quality ~= nil and EbonBuilds.Quality.IsValid(quality)) then
                    AddSignal(signals, name, quality, direction, count)
                end
            end
        end
    end
end

-- Returns rank-aware suggestions. `quality == nil` means the signal came from
-- legacy family-level data and an automatic application should nudge every
-- available rank by `delta` rather than replacing the rank table.
function M.SuggestWeightAdjustments(build)
    if not build then return {} end
    local store = EbonBuildsCharDB.manualTraining and EbonBuildsCharDB.manualTraining[build.id]
    if type(store) ~= "table" then return {} end

    local signature = table.concat({
        tostring(store),
        tostring(store.totalSelects or 0),
        tostring(build.version or 0),
        tostring(build.modifiedAt or build.updatedAt or 0),
    }, "|")
    local cached = suggestionCache[build.id]
    if cached and cached.signature == signature then return cached.value end

    local signals = {}
    ReadBucket(signals, store.preferredOverHigher, "raise")
    ReadBucket(signals, store.passedOverForLower, "lower")

    local suggestions = {}
    for _, signal in pairs(signals) do
        local net = signal.raiseCount - signal.lowerCount
        if math.abs(net) >= MIN_NET_DISAGREEMENTS then
            local delta = net > 0 and WEIGHT_NUDGE or -WEIGHT_NUDGE
            local current
            if signal.quality ~= nil then
                current = EbonBuilds.Weights.GetForRef(build, signal.refKey, signal.quality)
            else
                local values = build.echoWeightsByRef and build.echoWeightsByRef[signal.refKey]
                current = nil
                for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                    local value = values and EbonBuilds.Weights.GetFromWeights(build.echoWeightsByRef, signal.refKey, quality)
                        or EbonBuilds.Weights.GetForRef(build, signal.refKey, quality)
                    if current == nil or value > current then current = value end
                end
                current = current or 0
            end
            local suggested = math.max(EbonBuilds.Weights.MIN_VALUE,
                math.min(EbonBuilds.Weights.MAX_VALUE, current + delta))
            suggestions[#suggestions + 1] = {
                refKey = signal.refKey,
                name = signal.name,
                quality = signal.quality,
                applyAllRanks = signal.quality == nil,
                direction = delta > 0 and "raise" or "lower",
                delta = delta,
                count = math.abs(net),
                raiseCount = signal.raiseCount,
                lowerCount = signal.lowerCount,
                currentWeight = current,
                suggestedWeight = suggested,
            }
        end
    end
    table.sort(suggestions, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.name ~= b.name then return a.name < b.name end
        return (a.quality or -1) > (b.quality or -1)
    end)
    suggestionCache[build.id] = { signature = signature, value = suggestions }
    return suggestions
end

function M.Init()
    local svc = ProjectEbonhold and ProjectEbonhold.PerkService
    if not (svc and svc.SelectPerk) then return end
    if svc._ebonBuildsTrainingHooked then return end
    hooksecurefunc(svc, "SelectPerk", function(spellId)
        local ok, err = pcall(OnPlayerSelect, spellId)
        if not ok and EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("ManualTraining.OnPlayerSelect", err)
        end
    end)
    svc._ebonBuildsTrainingHooked = true
end

M.GetRevision = function(buildId)
    local store = EbonBuildsCharDB.manualTraining and EbonBuildsCharDB.manualTraining[buildId]
    return store and tonumber(store.totalSelects) or 0
end

M._OnPlayerSelect = OnPlayerSelect
