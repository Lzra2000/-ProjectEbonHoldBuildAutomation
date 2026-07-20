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
    -- Stable Echo references (g:<groupId>/s:<spellId>) are storage keys, not
    -- display names. Treating one as both made P.Set write the policy and then
    -- immediately delete the same key during legacy-name cleanup.
    if type(value) == "string" and value:match("^[gs]:%d+$") then return nil end
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

local function ReferenceKey(value)
    if value == nil then return nil end
    if type(value) == "table" then
        if value.refKey and tostring(value.refKey):match("^[gs]:%d+$") then return tostring(value.refKey) end
        value = value.spellId or value.id or value.name or value.comment
    end
    local text = tostring(value)
    if text:match("^[gs]:%d+$") then return text end
    if type(value) == "number" or text:match("^%d+$") then
        return EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(tonumber(value)) or nil
    end
    local refs = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.FindRefs(text) or {}
    return #refs == 1 and refs[1] or nil
end

P.ReferenceKey = ReferenceKey

local function LegacyReferenceKey(value)
    if value == nil then return nil end
    if type(value) == "table" then
        if value.refKey and tostring(value.refKey):match("^[gs]:%d+$") then
            return ReferenceKey(value.refKey)
        end
        local exact = value.spellId or value.id
        if exact then return ReferenceKey(exact) end
        value = value.name or value.comment
    end

    local text = tostring(value or "")
    if text:match("^[gs]:%d+$") or text:match("^%d+$") then
        return ReferenceKey(text)
    end
    if text == "" or not EbonBuilds.EchoCatalog then return nil end

    -- Persisted display-name keys predate canonical refKeys. Search both safe
    -- and quarantined aliases so a historical Blood Mirror key cannot be
    -- silently assigned to g:296 when it may have represented Crimson
    -- Reprisal under the server's incorrect runtime name.
    local refs = EbonBuilds.EchoCatalog.FindLegacyRefs
        and EbonBuilds.EchoCatalog.FindLegacyRefs(text)
        or EbonBuilds.EchoCatalog.FindRefs(text)
    if #refs == 1 then return refs[1] end
    return nil, #refs > 1 and "AMBIGUOUS_ALIAS" or "MISSING_ALIAS", refs
end

function P.IsValid(policy)
    return VALID[policy] and true or false
end

function P.Definition(policy)
    return P.DEFINITIONS[P.IsValid(policy) and policy or P.NORMAL]
end

function P.Normalize(settings)
    if type(settings) ~= "table" then return {} end
    local source = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    local clean, unresolved = {}, {}
    for rawKey, rawPolicy in pairs(source) do
        local refKey, reason, candidates = LegacyReferenceKey(rawKey)
        local policy = tostring(rawPolicy or "")
        if refKey and VALID[policy] and policy ~= P.NORMAL then
            clean[refKey] = policy
            if P.IsBanishPolicy(policy) and type(settings.echoWhitelist) == "table" then
                settings.echoWhitelist[refKey] = nil
            end
        elseif VALID[policy] and policy ~= P.NORMAL then
            unresolved[tostring(rawKey)] = { policy = policy, reason = reason, candidates = candidates }
        end
    end
    settings.echoPolicies = clean
    settings.unresolvedEchoPolicies = next(unresolved) and unresolved or nil
    return clean
end

function P.Get(settings, value)
    if type(settings) ~= "table" then return P.NORMAL end
    local policies = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    local refKey = ReferenceKey(value)
    local policy = refKey and policies[refKey] or nil
    return VALID[policy] and policy or P.NORMAL
end

-- Writes a policy under an already validated canonical Echo reference. This
-- bypasses catalogue/name resolution and is used by the Build Wizard, which
-- already owns stable g:/s: refKeys. It prevents an Avoid policy from being
-- lost when spell metadata is unavailable during build creation.
function P.SetRef(settings, refKey, policy)
    if type(settings) ~= "table" then return false end
    refKey = tostring(refKey or "")
    if not refKey:match("^[gs]:%d+$") then return false end
    policy = VALID[policy] and policy or P.NORMAL
    settings.echoPolicies = type(settings.echoPolicies) == "table" and settings.echoPolicies or {}
    if policy == P.NORMAL then settings.echoPolicies[refKey] = nil
    else settings.echoPolicies[refKey] = policy end
    return true
end

function P.EnsureNeverPick(settings, refKey)
    return P.SetRef(settings, refKey, P.NEVER_PICK)
end

function P.Set(settings, value, policy)
    if type(settings) ~= "table" then return false end
    local refKey = ReferenceKey(value)
    if not refKey then return false end
    return P.SetRef(settings, refKey, policy)
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
        if spellName then
            local canonical = CanonicalName(spellId) or spellName
            local previous = canonicalBySpellName[spellName]
            if previous == nil then canonicalBySpellName[spellName] = canonical
            elseif previous ~= canonical then canonicalBySpellName[spellName] = false end
        end
    end
end

local function MarkSelected(set, value)
    if value == nil then return end
    local name
    if type(value) == "table" then
        name = CanonicalName(value.spellId or value.id or value.name or value.comment)
    elseif type(value) == "string" and not value:match("^%d+$") then
        EnsureCanonicalIndex()
        local mapped = canonicalBySpellName[value]
        name = mapped ~= false and (mapped or CanonicalName(value)) or nil
    else
        name = CanonicalName(value)
    end
    local refKey = ReferenceKey(value)
    if refKey then set[refKey] = true end
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
    local refKey = ReferenceKey(value)
    local name = CanonicalName(value)
    selectedNames = selectedNames or P.SelectedNames()
    return (refKey and selectedNames[refKey]) or (name and selectedNames[name]) or false
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
