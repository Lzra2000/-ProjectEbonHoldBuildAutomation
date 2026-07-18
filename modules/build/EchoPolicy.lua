-- EbonBuilds: modules/build/EchoPolicy.lua
-- Responsibility: build-level conditional Echo policies and current-run state.

EbonBuilds.EchoPolicy = {}

local P = EbonBuilds.EchoPolicy

P.NORMAL            = "normal"
P.BANISH_ON_SIGHT   = "banish_on_sight"
P.BANISH_AFTER_PICK = "banish_after_pick"
P.IGNORE_AFTER_PICK = "ignore_after_pick"
P.NEVER_PICK        = "never_pick"

P.ORDER = {
    P.NORMAL,
    P.BANISH_ON_SIGHT,
    P.BANISH_AFTER_PICK,
    P.IGNORE_AFTER_PICK,
    P.NEVER_PICK,
}

P.DEFINITIONS = {
    [P.NORMAL] = {
        label = "Normal", shortLabel = "Normal", group = "Standard",
        color = { 0.82, 0.82, 0.86 },
        description = "Use this Echo's score, weight, rarity, and normal Autopilot rules.",
    },
    [P.BANISH_ON_SIGHT] = {
        label = "Banish on Sight", shortLabel = "On Sight", group = "Resource actions",
        color = { 1.00, 0.28, 0.24 },
        description = "Banish this Echo whenever it appears before it has been selected once in the current run.",
    },
    [P.BANISH_AFTER_PICK] = {
        label = "Banish After Pick", shortLabel = "After Pick", group = "Resource actions",
        color = { 1.00, 0.58, 0.18 },
        description = "Treat this Echo normally until it has been selected once, then banish future offers.",
    },
    [P.IGNORE_AFTER_PICK] = {
        label = "Ignore After Pick", shortLabel = "Ignore After", group = "Selection rules",
        color = { 0.35, 0.68, 1.00 },
        description = "Treat this Echo normally until it has been selected once, then exclude future copies without spending a banish.",
    },
    [P.NEVER_PICK] = {
        label = "Never Pick", shortLabel = "Never Pick", group = "Selection rules",
        color = { 0.92, 0.34, 0.46 },
        description = "Never select this Echo automatically. This rule does not spend a banish.",
    },
}

local VALID = {}
for _, policy in ipairs(P.ORDER) do VALID[policy] = true end

local canonicalBySpellName = {}
local canonicalIndexBuilt = false

local function CanonicalName(value)
    if value == nil then return nil end
    if type(value) == "number" or (type(value) == "string" and value:match("^%d+$")) then
        return EbonBuilds.Weights and EbonBuilds.Weights.CanonicalName(tonumber(value)) or tostring(value)
    end
    local name = tostring(value)
    if EbonBuilds.Weights and EbonBuilds.Weights.StripQualitySuffix then
        name = EbonBuilds.Weights.StripQualitySuffix(name)
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or nil
end

P.CanonicalName = CanonicalName

function P.IsValid(policy)
    return VALID[policy] and true or false
end

function P.Definition(policy)
    return P.DEFINITIONS[P.IsValid(policy) and policy or P.NORMAL]
end

function P.Normalize(settings)
    if type(settings) ~= "table" then return {} end
    local source = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    local clean = {}
    for rawName, rawPolicy in pairs(source) do
        local name = CanonicalName(rawName)
        local policy = tostring(rawPolicy or "")
        if name and VALID[policy] and policy ~= P.NORMAL then
            clean[name] = policy
            if P.IsBanishPolicy(policy) and type(settings.echoWhitelist) == "table" then
                settings.echoWhitelist[name] = nil
            end
        end
    end
    settings.echoPolicies = clean
    return clean
end

function P.Get(settings, value)
    if type(settings) ~= "table" then return P.NORMAL end
    local policies = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    local name = CanonicalName(value)
    local policy = name and policies[name]
    return VALID[policy] and policy or P.NORMAL
end

function P.Set(settings, value, policy)
    if type(settings) ~= "table" then return false end
    local name = CanonicalName(value)
    if not name then return false end
    policy = VALID[policy] and policy or P.NORMAL
    settings.echoPolicies = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    if policy == P.NORMAL then settings.echoPolicies[name] = nil else settings.echoPolicies[name] = policy end
    return true
end

function P.IsBanishPolicy(policy)
    return policy == P.BANISH_ON_SIGHT or policy == P.BANISH_AFTER_PICK
end

local function EnsureCanonicalIndex()
    if canonicalIndexBuilt then return end
    canonicalIndexBuilt = true
    local database = ProjectEbonhold and ProjectEbonhold.PerkDatabase
    if not database then return end
    for spellId in pairs(database) do
        local spellName = GetSpellInfo(spellId)
        if spellName then canonicalBySpellName[spellName] = CanonicalName(spellId) or spellName end
    end
end

local function MarkSelected(set, value)
    if value == nil then return end
    local name
    if type(value) == "table" then
        name = CanonicalName(value.spellId or value.id or value.name or value.comment)
    elseif type(value) == "string" and not value:match("^%d+$") then
        EnsureCanonicalIndex()
        name = canonicalBySpellName[value] or CanonicalName(value)
    else
        name = CanonicalName(value)
    end
    if name then set[name] = true end
end

function P.SelectedNames()
    local selected = {}

    local active = EbonBuilds.Session and EbonBuilds.Session.GetActiveSession and EbonBuilds.Session.GetActiveSession()
    for _, entry in ipairs(active and active.logs or {}) do
        local action = tostring(entry.action or "")
        if action:find("^Select") or action:find("^Manual") then
            local targetIndex = tonumber(entry.targetIndex)
            local target
            for arrayIndex, choice in ipairs(entry.choices or {}) do
                if arrayIndex == targetIndex or tonumber(choice.index) == targetIndex then target = choice; break end
            end
            if target then MarkSelected(selected, target.spellId or target.name) end
        end
    end

    local service = ProjectEbonhold and ProjectEbonhold.PerkService
    local granted = service and service.GetGrantedPerks and service.GetGrantedPerks()
    if type(granted) == "table" then
        for key, value in pairs(granted) do
            MarkSelected(selected, key)
            if type(value) == "table" then MarkSelected(selected, value) end
        end
    end

    return selected
end

function P.IsSelected(value, selectedNames)
    local name = CanonicalName(value)
    selectedNames = selectedNames or P.SelectedNames()
    return name and selectedNames[name] and true or false
end

function P.Resolve(policy, selected)
    policy = VALID[policy] and policy or P.NORMAL
    if policy == P.BANISH_ON_SIGHT and not selected then return "banish" end
    if policy == P.BANISH_AFTER_PICK and selected then return "banish" end
    if policy == P.IGNORE_AFTER_PICK and selected then return "exclude" end
    if policy == P.NEVER_PICK then return "exclude" end
    return "normal"
end

function P.EffectText(policy, selected)
    local effect = P.Resolve(policy, selected)
    if effect == "banish" then return "Active: future offers are mandatory banish targets." end
    if effect == "exclude" then return "Active: this Echo is excluded from automatic selection." end
    if policy == P.BANISH_ON_SIGHT then return "Inactive after selection: this Echo is treated normally." end
    if policy == P.BANISH_AFTER_PICK or policy == P.IGNORE_AFTER_PICK then
        return "Waiting for the first selection; normal scoring is currently active."
    end
    return "Standard scoring and Autopilot rules are active."
end

function P.Summary(settings)
    local summary = { total = 0 }
    for _, policy in ipairs(P.ORDER) do summary[policy] = 0 end
    local policies = type(settings) == "table" and settings.echoPolicies or nil
    if type(policies) ~= "table" then return summary end
    for _, policy in pairs(policies) do
        if VALID[policy] and policy ~= P.NORMAL then
            summary[policy] = summary[policy] + 1
            summary.total = summary.total + 1
        end
    end
    return summary
end

function P.SummaryText(settings)
    local s = P.Summary(settings)
    if s.total == 0 then return "No custom policies" end
    return string.format("%d custom: %d sight, %d after, %d ignore, %d never",
        s.total, s[P.BANISH_ON_SIGHT], s[P.BANISH_AFTER_PICK], s[P.IGNORE_AFTER_PICK], s[P.NEVER_PICK])
end
