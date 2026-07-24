local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/Constraints.lua
-- Responsibility: pack Autopilot build prefs into a versioned constraints table,
-- wire blob, and hash for future ProjectEbonhold policy/intent upload (WP5 #54).
-- Client-side stepping stone: local object for IntentQueue + Automation until PE
-- exposes serverConstraints / serverPolicy.

EbonBuilds.AutomationConstraints = {}

local M = EbonBuilds.AutomationConstraints

M.SCHEMA_VERSION = 1
M.WIRE_SOFT_LIMIT = 240

local POLICY_WIRE = {
    banish_on_sight = "bos",
    banish_after_pick = "bap",
    ignore_after_pick = "iap",
    never_pick = "np",
}

local WIRE_POLICY = {
    bos = "banish_on_sight",
    bap = "banish_after_pick",
    iap = "ignore_after_pick",
    np = "never_pick",
}

local THRESHOLD_FIELDS = {
    "autoBanishPct", "autoRerollPct", "rerollGuardPct",
    "rerollEVPct", "banishEVPct", "freezeEVPct",
    "autoFreezePct", "freezePenaltyPct", "noveltyValue",
}

local function StableSerialize(value)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "t" or "f" end
    if kind == "number" then return "#" .. tostring(value) end
    if kind == "string" then return "$" .. value end
    if kind ~= "table" then return "?" .. kind end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return tostring(a) < tostring(b)
    end)
    local out = { "{" }
    for _, key in ipairs(keys) do
        out[#out + 1] = StableSerialize(key)
        out[#out + 1] = StableSerialize(value[key])
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

local function Digest(value)
    local text = type(value) == "string" and value or StableSerialize(value)
    local hash = 5381
    for index = 1, #text do hash = (hash * 33 + text:byte(index)) % 4294967296 end
    local digits, out = "0123456789abcdef", {}
    for index = 8, 1, -1 do
        local nibble = hash % 16
        out[index] = digits:sub(nibble + 1, nibble + 1)
        hash = math.floor(hash / 16)
    end
    return table.concat(out)
end

M.Digest = Digest

local function FamilySlug(family)
    return tostring(family or ""):lower():gsub("%s+", "_")
end

local function CollectProtectFamilies(settings)
    local protected = settings and settings.banishFamilyWhitelist or {}
    local families = {}
    for family, enabled in pairs(protected) do
        if enabled then families[#families + 1] = FamilySlug(family) end
    end
    table.sort(families)
    return families
end

local function CollectPolicies(settings)
    local policies = settings and settings.echoPolicies or {}
    local out = {}
    for refKey, policy in pairs(policies) do
        local wire = POLICY_WIRE[policy]
        if wire then out[tostring(refKey)] = wire end
    end
    return out
end

local function CollectSpellIds(map)
    local ids = {}
    for key, enabled in pairs(map or {}) do
        if enabled then
            local spellId = tonumber(key)
            if spellId then ids[#ids + 1] = spellId end
        end
    end
    table.sort(ids)
    return ids
end

local function CollectWhitelist(settings)
    local whitelist = settings and settings.echoWhitelist or {}
    local refs = {}
    for refKey, enabled in pairs(whitelist) do
        if enabled then refs[#refs + 1] = tostring(refKey) end
    end
    table.sort(refs)
    return refs
end

local function Remaining(total, used)
    return math.max(0, (tonumber(total) or 0) - (tonumber(used) or 0))
end

function M.Pack(settings, context)
    settings = type(settings) == "table" and settings or {}
    context = type(context) == "table" and context or {}

    if EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.Normalize then
        EbonBuilds.EchoPolicy.Normalize(settings)
    end

    local packed = {
        v = M.SCHEMA_VERSION,
        rerollMode = (settings.rerollMode or "sum") == "ev" and "ev" or "sum",
        protectFamilies = CollectProtectFamilies(settings),
        echoPolicies = CollectPolicies(settings),
        echoBanList = CollectSpellIds(settings.echoBanList),
        echoWhitelist = CollectWhitelist(settings),
        noveltyMode = settings.noveltyMode and true or false,
    }

    for _, field in ipairs(THRESHOLD_FIELDS) do
        local value = tonumber(settings[field])
        if value ~= nil then packed[field] = value end
    end

    local runData = context.runData
    if runData then
        packed.maxRerolls = Remaining(runData.totalRerolls, runData.usedRerolls)
        packed.remainingBanishes = tonumber(runData.remainingBanishes)
        packed.remainingFreezes = Remaining(runData.totalFreezes, runData.usedFreezes)
    end
    if context.maxRerolls ~= nil then
        packed.maxRerolls = tonumber(context.maxRerolls)
    end

    return packed
end

function M.Hash(packed)
    return Digest(packed)
end

local function JoinList(values, separator)
    if #values == 0 then return nil end
    return table.concat(values, separator or ",")
end

local function EncodePolicies(policies)
    local entries = {}
    for refKey, wire in pairs(policies or {}) do
        entries[#entries + 1] = tostring(refKey) .. ":" .. tostring(wire)
    end
    table.sort(entries)
    return JoinList(entries, ",")
end

function M.Serialize(packed)
    packed = type(packed) == "table" and packed or {}
    if tonumber(packed.v) ~= M.SCHEMA_VERSION then return nil, "unsupported_version" end

    local parts = { "v=" .. tostring(M.SCHEMA_VERSION) }
    if packed.rerollMode then parts[#parts + 1] = "rerollMode=" .. packed.rerollMode end

    for _, field in ipairs(THRESHOLD_FIELDS) do
        local value = packed[field]
        if value ~= nil then parts[#parts + 1] = field .. "=" .. tostring(value) end
    end
    if packed.noveltyMode then parts[#parts + 1] = "noveltyMode=1" end

    local families = JoinList(packed.protectFamilies or {})
    if families then parts[#parts + 1] = "protectFamilies=" .. families end

    local policies = EncodePolicies(packed.echoPolicies)
    if policies then parts[#parts + 1] = "policy=" .. policies end

    local bans = JoinList(packed.echoBanList or {})
    if bans then parts[#parts + 1] = "ban=" .. bans end

    local whitelist = JoinList(packed.echoWhitelist or {})
    if whitelist then parts[#parts + 1] = "whitelist=" .. whitelist end

    if packed.maxRerolls ~= nil then
        parts[#parts + 1] = "maxRerolls=" .. tostring(packed.maxRerolls)
    end
    if packed.remainingBanishes ~= nil then
        parts[#parts + 1] = "remainingBanishes=" .. tostring(packed.remainingBanishes)
    end
    if packed.remainingFreezes ~= nil then
        parts[#parts + 1] = "remainingFreezes=" .. tostring(packed.remainingFreezes)
    end

    return table.concat(parts, ";")
end

local function SplitList(text)
    local out = {}
    for token in tostring(text or ""):gmatch("[^,]+") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then out[#out + 1] = token end
    end
    return out
end

local function ParsePolicies(text)
    local policies = {}
    for entry in tostring(text or ""):gmatch("[^,]+") do
        local refKey, wire = entry:match("^([^:]+):([^:]+)$")
        if refKey and wire and WIRE_POLICY[wire] then
            policies[refKey] = WIRE_POLICY[wire]
        end
    end
    return policies
end

function M.Parse(wire)
    if type(wire) ~= "string" or wire == "" then return nil, "empty" end
    local packed = { v = nil }
    for token in wire:gmatch("[^;]+") do
        local key, value = token:match("^([^=]+)=(.+)$")
        if key and value then
            if key == "v" then
                packed.v = tonumber(value)
            elseif key == "rerollMode" then
                packed.rerollMode = value == "ev" and "ev" or "sum"
            elseif key == "noveltyMode" then
                packed.noveltyMode = value == "1" or value == "true"
            elseif key == "protectFamilies" then
                packed.protectFamilies = SplitList(value)
            elseif key == "policy" then
                packed.echoPolicies = ParsePolicies(value)
            elseif key == "ban" then
                local bans = {}
                for _, spellId in ipairs(SplitList(value)) do
                    bans[tonumber(spellId) or spellId] = true
                end
                packed.echoBanList = bans
            elseif key == "whitelist" then
                local whitelist = {}
                for _, refKey in ipairs(SplitList(value)) do
                    whitelist[refKey] = true
                end
                packed.echoWhitelist = whitelist
            else
                local number = tonumber(value)
                if number ~= nil then packed[key] = number end
            end
        end
    end
    if tonumber(packed.v) ~= M.SCHEMA_VERSION then return nil, "unsupported_version" end
    return packed
end

function M.FromSettings(settings, context)
    local tableValue = M.Pack(settings, context)
    local hash = M.Hash(tableValue)
    local wire, err = M.Serialize(tableValue)
    return {
        table = tableValue,
        hash = hash,
        wire = wire,
        error = err,
    }
end

function M.FromBuild(build, context)
    if not build then return M.FromSettings({}, context) end
    if EbonBuilds.Build and EbonBuilds.Build.EnsureSettings then
        EbonBuilds.Build.EnsureSettings(build)
    end
    return M.FromSettings(build.settings, context)
end

function M.GetActive(context)
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    return M.FromBuild(build, context)
end

function M.IsStale(currentHash, attachedHash)
    if not attachedHash or attachedHash == "" then return false end
    if not currentHash or currentHash == "" then return false end
    return currentHash ~= attachedHash
end

function M.FitsAddonMsg(wire)
    wire = tostring(wire or "")
    return #wire <= M.WIRE_SOFT_LIMIT
end

function M.AttachToBoard(board, build, runData)
    if not board then return nil end
    local snapshot = M.FromBuild(build, { runData = runData })
    board.constraints = snapshot.table
    board.constraintsHash = snapshot.hash
    board.constraintsWire = snapshot.wire
    return snapshot
end
