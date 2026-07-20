-- EbonBuilds: modules/recommendations/CommunityEligibility.lua
-- Converts public builds into bounded recommendation records keyed by Echo refs.

EbonBuilds.CommunityEligibility = {}

local Eligibility = EbonBuilds.CommunityEligibility
local MAX_SIGNALS_PER_BUILD = 32

local function NormalizeText(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

function Eligibility.CohortKey(classToken, spec)
    classToken = tostring(classToken or "UNKNOWN"):upper()
    spec = math.max(1, math.min(3, tonumber(spec) or 1))
    return classToken .. ":" .. tostring(spec) .. ":4"
end

function Eligibility.IsEligible(build, classToken, spec)
    if type(build) ~= "table" or build.wizardMeta ~= nil or build.recommendationOrigin ~= nil then return false end
    if tostring(build.class or ""):upper() ~= tostring(classToken or ""):upper() then return false end
    if (tonumber(build.spec) or 1) ~= (tonumber(spec) or 1) then return false end
    return type(build.echoWeightsByRef) == "table" or type(build.echoWeights) == "table" or type(build.lockedEchoes) == "table"
end

function Eligibility.AuthorKey(build)
    local author = NormalizeText(build and build.author)
    return author ~= "" and author or "unknown"
end

function Eligibility.OriginKey(build)
    if not build then return nil end
    local lineage = tostring(build.copiedFrom or build.importedFrom or "")
    if #lineage >= 20 then return "id:" .. lineage end
    local id = tostring(build.id or "")
    if id ~= "" then return "id:" .. id end
    local checksum = build.strategyHash
    if not checksum and EbonBuilds.Build and EbonBuilds.Build.StrategyChecksum then checksum = EbonBuilds.Build.StrategyChecksum(build) end
    return "strategy:" .. Eligibility.AuthorKey(build) .. ":" .. tostring(checksum or build.title or "unknown")
end

local function StrongestWeight(entry)
    local strongest = 0
    if type(entry) == "number" or type(entry) == "string" then return tonumber(entry) or 0 end
    if type(entry) ~= "table" then return 0 end
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        local value = tonumber(entry[quality] or entry[tostring(quality)] or entry.default) or 0
        if math.abs(value) > math.abs(strongest) then strongest = value end
    end
    return strongest
end

local function EnsureSignal(map, refKey, classToken)
    refKey = tostring(refKey or "")
    if not refKey:match("^[gs]:%d+$") then return nil end
    local signal = map[refKey]
    if not signal then
        local definition = EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.GetEntry(classToken, refKey)
        if not definition then return nil end
        signal = { refKey = refKey, name = definition.displayName or definition.canonicalName or definition.sourceName, weight = 0 }
        map[refKey] = signal
    end
    return signal
end

local function ResolveLegacy(build, value)
    if type(value) == "number" or tostring(value):match("^%d+$") then
        local variant = EbonBuilds.EchoCatalog.GetBySpellId(tonumber(value))
        if variant and EbonBuilds.EchoProjection.GetEntry(build.class, variant.refKey) then return variant.refKey end
        return nil
    end
    return EbonBuilds.Weights.ResolveLegacyName(build, value)
end

local function CandidatePriority(signal)
    local priority = math.abs(signal.weight or 0)
    if signal.locked then priority = priority + 1000000 end
    if signal.protected then priority = priority + 500000 end
    if signal.negative then priority = priority + 250000 end
    return priority
end

function Eligibility.BuildRecord(build)
    local signals, unresolved = {}, 0
    if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end

    for refKey, entry in pairs(build.echoWeightsByRef or {}) do
        local signal = EnsureSignal(signals, refKey, build.class)
        if signal then
            signal.weight = StrongestWeight(entry)
            signal.present, signal.positive, signal.negative = signal.weight ~= 0, signal.weight > 0, signal.weight < 0
        end
    end
    -- Legacy entries not represented in schema-2 storage are resolved only when
    -- unambiguous for this build class.
    for rawName, entry in pairs(build.echoWeights or {}) do
        local refKey = ResolveLegacy(build, rawName)
        if refKey then
            local signal = EnsureSignal(signals, refKey, build.class)
            if signal and signal.weight == 0 then
                signal.weight = StrongestWeight(entry)
                signal.present, signal.positive, signal.negative = signal.weight ~= 0, signal.weight > 0, signal.weight < 0
            end
        else unresolved = unresolved + 1 end
    end

    for _, spellId in pairs(build.lockedEchoes or {}) do
        local entry, variant = EbonBuilds.EchoProjection.ResolveSpell(build.class, spellId)
        local signal = entry and EnsureSignal(signals, entry.refKey, build.class)
        if signal and variant then
            signal.present, signal.positive, signal.locked = true, true, true
            signal.lockedSpellId = tonumber(spellId)
        else unresolved = unresolved + 1 end
    end

    local settings = type(build.settings) == "table" and build.settings or {}
    for name, enabled in pairs(settings.echoWhitelist or {}) do
        if enabled == true or enabled == 1 then
            local refKey = ResolveLegacy(build, name)
            local signal = refKey and EnsureSignal(signals, refKey, build.class)
            if signal then signal.present, signal.positive, signal.protected = true, true, true end
        end
    end
    for name, policy in pairs(settings.echoPolicies or {}) do
        if policy ~= "normal" then
            local refKey = ResolveLegacy(build, name)
            local signal = refKey and EnsureSignal(signals, refKey, build.class)
            if signal then
                signal.present = true
                if policy == "never_pick" or policy == "banish_on_sight" or policy == "banish_after_pick" then signal.negative = true end
            end
        end
    end
    for spellId in pairs(settings.echoBanList or {}) do
        local refKey = ResolveLegacy(build, spellId)
        local signal = refKey and EnsureSignal(signals, refKey, build.class)
        if signal then signal.present, signal.negative = true, true end
    end

    local list = {}
    for _, signal in pairs(signals) do if signal.present or signal.positive or signal.negative then list[#list + 1] = signal end end
    table.sort(list, function(a, b)
        local ap, bp = CandidatePriority(a), CandidatePriority(b)
        if ap ~= bp then return ap > bp end
        return tostring(a.refKey) < tostring(b.refKey)
    end)
    local positiveRank = 0
    for index = 1, math.min(#list, MAX_SIGNALS_PER_BUILD) do
        local signal = list[index]
        if signal.positive and not signal.negative then positiveRank = positiveRank + 1; signal.topGroup = positiveRank <= 3 end
    end
    while #list > MAX_SIGNALS_PER_BUILD do table.remove(list) end

    local family = type(settings.familyBonus) == "table" and settings.familyBonus or {}
    local defensiveModifier = math.max(tonumber(family.Tank) or 0, tonumber(family.Survivability) or 0)
    local damageModifier = math.max(tonumber(family.Caster) or 0, tonumber(family.Melee) or 0, tonumber(family.Ranged) or 0)
    return {
        originKey = Eligibility.OriginKey(build), authorKey = Eligibility.AuthorKey(build),
        defensiveProfile = defensiveModifier > 0 and defensiveModifier > damageModifier,
        signals = list, unresolvedEntries = unresolved,
    }
end

function Eligibility.CollectSources(classToken, spec)
    local sources, seen = {}, {}
    local function Consider(id, build)
        if Eligibility.IsEligible(build, classToken, spec) then
            local key = tostring(id or build.id or build)
            if not seen[key] then seen[key] = true; sources[#sources + 1] = build end
        end
    end
    for id, build in pairs(EbonBuildsDB and EbonBuildsDB.builds or {}) do if build.isPublic then Consider(id, build) end end
    for id, build in pairs(EbonBuildsDB and EbonBuildsDB.remoteBuilds or {}) do Consider(id, build) end
    table.sort(sources, function(a, b) return tostring(a._lastSeenAt or a.lastModified or "") > tostring(b._lastSeenAt or b.lastModified or "") end)
    return sources
end
