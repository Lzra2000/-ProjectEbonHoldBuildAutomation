-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write and migrate rank-specific echo weights stored on
-- the active build. Legacy single-number entries remain readable and are
-- migrated to one value per quality without changing their effective score.

EbonBuilds.Weights = {}

local W = EbonBuilds.Weights

-- Preserve the old six-digit positive range and extend it symmetrically for
-- negative values. Echo weights remain whole numbers; decimal input was not
-- supported by the project before this migration.
W.MIN_VALUE = -999999
W.MAX_VALUE =  999999

------------------------------------------------------------------------
-- Canonical echo name
------------------------------------------------------------------------

local QUALITY_SUFFIXES = {}
local function EscapePattern(value)
    return tostring(value):gsub("([^%w])", "%%%1")
end
for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
    local label = EbonBuilds.Quality.LABELS[quality]
    if label then QUALITY_SUFFIXES[#QUALITY_SUFFIXES + 1] = " %- " .. EscapePattern(label) .. "$" end
end

function W.StripQualitySuffix(name)
    name = tostring(name or "")
    for _, pattern in ipairs(QUALITY_SUFFIXES) do
        local stripped = name:match("^(.+)" .. pattern)
        if stripped then return stripped end
    end
    return name
end

-- Some Project Ebonhold database comments append an invisible control-byte
-- discriminator to otherwise identical player-facing Echo names. Keep that
-- suffix in storage keys so distinct variants do not collapse, but never pass
-- it to FontStrings, search, or WoW's locale string helpers.
function W.VisibleName(name)
    name = tostring(name or "")
    for index = 1, #name do
        local byte = name:byte(index)
        if byte and (byte < 32 or byte == 127) then
            name = name:sub(1, index - 1)
            break
        end
    end
    return name:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Returns the canonical weight key for a spellId: the DB comment (suffix
-- stripped) when present, otherwise the stripped spell name as fallback.
function W.CanonicalName(spellId)
    if not spellId then return nil end
    local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase
        and ProjectEbonhold.PerkDatabase[spellId]
    local raw = data and data.comment
    if not raw or raw == "" then raw = GetSpellInfo(spellId) end
    if not raw then return nil end
    return W.StripQualitySuffix(raw)
end

------------------------------------------------------------------------
-- Validation / normalization
------------------------------------------------------------------------

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function W.Validate(value)
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "Enter a finite whole number."
        end
        if math.floor(value) ~= value then
            return nil, "Whole numbers only; decimals are not supported."
        end
    elseif type(value) == "string" then
        local raw = Trim(value)
        if raw == "" then return nil, "A value is required." end
        if not raw:match("^[+-]?%d+$") then
            return nil, "Enter a whole number, for example -10, 0, or 25."
        end
        value = tonumber(raw)
    else
        return nil, "Enter a numeric value."
    end

    if not value then return nil, "Enter a valid whole number." end
    if value < W.MIN_VALUE or value > W.MAX_VALUE then
        return nil, string.format("Value must be between %d and %d.", W.MIN_VALUE, W.MAX_VALUE)
    end
    return math.floor(value), nil
end

function W.MakeUniform(value)
    local valid = W.Validate(value)
    if valid == nil then valid = 0 end
    local out = {}
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        out[quality] = valid
    end
    return out
end

-- Normalizes malformed, partial, legacy, and imported values defensively.
-- Missing rank-specific values fall back to `default` when present, otherwise
-- to zero. A legacy number is copied to every quality rank.
function W.NormalizeEntry(value)
    if type(value) == "number" or type(value) == "string" then
        local valid = W.Validate(value)
        return W.MakeUniform(valid or 0)
    end

    local out = {}
    local fallback = 0
    if type(value) == "table" then
        local maybeDefault = value.default
        local validDefault = W.Validate(maybeDefault)
        if validDefault ~= nil then fallback = validDefault end
    end

    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        local raw = type(value) == "table" and (value[quality] ~= nil and value[quality] or value[tostring(quality)]) or nil
        local valid = W.Validate(raw)
        out[quality] = valid ~= nil and valid or fallback
    end

    -- Keep unknown numeric rank data intact for forward/backward compatibility,
    -- but do not expose it in the current four-rank interface. This prevents a
    -- UI-only rank change from destroying values during edit, import, or sync.
    if type(value) == "table" then
        for rawKey, rawValue in pairs(value) do
            local numericKey = type(rawKey) == "number" and rawKey
                or (type(rawKey) == "string" and rawKey:match("^%d+$") and tonumber(rawKey))
            if numericKey and not EbonBuilds.Quality.IsValid(numericKey) then
                local valid = W.Validate(rawValue)
                if valid ~= nil then out[numericKey] = valid end
            end
        end
    end
    return out
end

function W.NormalizeWeights(weights)
    local out = {}
    if type(weights) ~= "table" then return out end
    for name, value in pairs(weights) do
        if type(name) == "string" and name ~= "" then
            out[name] = W.NormalizeEntry(value)
        end
    end
    return out
end

function W.CloneWeights(weights)
    return W.NormalizeWeights(weights)
end

function W.Init()
    -- Storage lives on each build. Migration runs from Build.Migrate after all
    -- modules have loaded.
end

------------------------------------------------------------------------
-- Reads / writes
------------------------------------------------------------------------

function W.GetFromWeights(weights, echoName, quality)
    if type(weights) ~= "table" then return 0 end
    local entry = weights[echoName]
    if type(entry) == "number" or type(entry) == "string" then
        local valid = W.Validate(entry)
        return valid or 0
    end
    if type(entry) ~= "table" then return 0 end

    if quality ~= nil then
        local raw = entry[quality]
        if raw == nil then raw = entry[tostring(quality)] end
        local valid = W.Validate(raw)
        if valid ~= nil then return valid end
        local fallback = W.Validate(entry.default)
        return fallback or 0
    end

    local fallback = W.Validate(entry.default)
    if fallback ~= nil then return fallback end
    for _, rank in ipairs(EbonBuilds.Quality.ORDER or {}) do
        local valid = W.Validate(entry[rank])
        if valid ~= nil then return valid end
    end
    return 0
end

function W.Get(echoName, quality)
    return W.GetFromWeights(EbonBuilds.Build.GetActiveWeights(), echoName, quality)
end

-- Writes one rank when quality is provided. Calls without quality preserve the
-- old API by assigning the same value to every quality rank.
function W.Set(echoName, value, quality)
    local valid, err = W.Validate(value)
    if valid == nil then return false, err end
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return false, "No active build." end

    if quality == nil then
        weights[echoName] = W.MakeUniform(valid)
    else
        if not EbonBuilds.Quality.IsValid(quality) then
            return false, "Unknown quality rank."
        end
        local entry = W.NormalizeEntry(weights[echoName])
        entry[quality] = valid
        weights[echoName] = entry
    end

    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    return true
end

function W.HasNonZero(entry)
    if type(entry) == "number" or type(entry) == "string" then
        local valid = W.Validate(entry)
        return valid ~= nil and valid ~= 0
    end
    if type(entry) ~= "table" then return false end
    local normalized = W.NormalizeEntry(entry)
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if normalized[quality] ~= 0 then return true end
    end
    return false
end

function W.MaxFromWeights(weights, echoName, qualities)
    local best = nil
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if not qualities or qualities[quality] then
            local value = W.GetFromWeights(weights, echoName, quality)
            if best == nil or value > best then best = value end
        end
    end
    return best or 0
end

function W.DescribeFromWeights(weights, echoName, qualities)
    local parts = {}
    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
        if not qualities or qualities[quality] then
            local label = EbonBuilds.Quality.LABELS[quality] or tostring(quality)
            parts[#parts + 1] = label .. "=" .. tostring(W.GetFromWeights(weights, echoName, quality))
        end
    end
    return table.concat(parts, ", ")
end
