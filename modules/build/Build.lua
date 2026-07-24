local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/Build.lua
-- Responsibility: build CRUD, UUID generation, active-build tracking,
-- one-time migration from the legacy single-weight-table shape.

EbonBuilds.Build = {}

EbonBuilds.Build.LOCKED_SLOTS = 6

local function DefaultSettings()
    local qualityBonus, qualityBonusMode = {}, {}
    local order = EbonBuilds.Quality and EbonBuilds.Quality.ORDER or {}
    for _, quality in ipairs(order) do
        qualityBonus[quality] = 0
        qualityBonusMode[quality] = false
    end
    return {
        qualityBonus        = qualityBonus,
        qualityBonusMode    = qualityBonusMode,
        familyBonus         = { Tank = 0, Survivability = 0, Healer = 0, Caster = 0, Melee = 0, Ranged = 0, ["No family"] = 0 },
        familyBonusMode     = { Tank = false, Survivability = false, Healer = false, Caster = false, Melee = false, Ranged = false, ["No family"] = false },
        banishFamilyWhitelist = {},
        autoBanishPct    = 20,
        autoRerollPct    = 120,
        rerollGuardPct   = 90,
        rerollMode       = "sum",   -- "sum" (legacy) or "ev" (smart: vs expected reroll value)
        rerollEVPct      = 95,      -- ev mode: reroll if best offer < this % of E[best of 3]
        banishEVPct      = 60,      -- ev mode: banish if score < this % of E[one random card]
        freezeEVPct      = 110,     -- ev mode: freeze if score > this % of E[best of 3]
        autoFreezePct    = 80,
        freezePenaltyPct = 10,
        noveltyValue     = 0,
        noveltyMode      = false,
        echoBanList      = {},
        echoWhitelist    = {},
        echoPolicies     = {},
        echoBanAllMode   = "highestScore",
    }
end

EbonBuilds.Build.DefaultSettings = DefaultSettings

-- New builds start from the recommended intent-first automation profile.
-- Existing builds continue to use their persisted mode and thresholds; this
-- helper is used only by create flows and the guided wizard.
local function NewBuildSettings()
    local settings = DefaultSettings()
    settings.rerollMode = "ev"
    settings.banishEVPct = 60
    settings.rerollEVPct = 95
    settings.freezeEVPct = 110
    settings.freezePenaltyPct = 8
    return settings
end

EbonBuilds.Build.NewBuildSettings = NewBuildSettings

local function EnsureSettings(build)
    build.settings = build.settings or DefaultSettings()
    local d = DefaultSettings()
    for k, v in pairs(d) do
        if build.settings[k] == nil then
            build.settings[k] = v
        elseif type(v) == "table" then
            if type(build.settings[k]) ~= "table" then build.settings[k] = {} end
            for sk, sv in pairs(v) do
                if build.settings[k][sk] == nil then
                    build.settings[k][sk] = sv
                end
            end
        end
    end
    local limits = {
        autoBanishPct = { 0, 500 }, autoRerollPct = { 0, 500 }, rerollGuardPct = { 0, 500 },
        rerollEVPct = { 0, 500 }, banishEVPct = { 0, 500 }, freezeEVPct = { 0, 500 },
        autoFreezePct = { 0, 500 }, freezePenaltyPct = { 0, 100 }, noveltyValue = { -999999, 999999 },
    }
    for field, range in pairs(limits) do
        local value = tonumber(build.settings[field]) or d[field]
        build.settings[field] = math.max(range[1], math.min(range[2], value))
    end
    if build.settings.rerollMode ~= "ev" then build.settings.rerollMode = "sum" end
    local function ClampBonusTable(values)
        for key, value in pairs(values or {}) do
            value = tonumber(value) or 0
            values[key] = math.max(-999999, math.min(999999, value))
        end
    end
    ClampBonusTable(build.settings.qualityBonus)
    ClampBonusTable(build.settings.familyBonus)
end

EbonBuilds.Build.EnsureSettings = EnsureSettings

local function CloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[CloneTable(k)] = CloneTable(v)
    end
    return copy
end

function EbonBuilds.Build.CloneSettings(settings)
    return CloneTable(settings)
end

EbonBuilds.Build.CloneTable = CloneTable

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

function EbonBuilds.Build.StrategyChecksum(build)
    return Digest({
        class = build and build.class,
        spec = build and build.spec,
        lockedEchoes = build and build.lockedEchoes or {},
        echoWeights = build and build.echoWeights or {},
        echoWeightsByRef = build and build.echoWeightsByRef or {},
        echoCatalogFingerprint = build and build.echoCatalogFingerprint,
        settings = build and build.settings or {},
    })
end

local function NormalizeProtection(build)
    EnsureSettings(build)
    local settings = build.settings
    if type(settings.echoWhitelist) ~= "table" then settings.echoWhitelist = {} end
    if type(settings.echoBanList) ~= "table" then settings.echoBanList = {} end

    local cleanWhitelist, unresolvedWhitelist = {}, {}
    for key, enabled in pairs(settings.echoWhitelist) do
        local isEnabled = enabled == true or enabled == 1 or enabled == "1" or enabled == "true"
        if isEnabled then
            local refKey
            local text = tostring(key or "")
            if text:match("^[gs]:%d+$") then
                refKey = text
            elseif type(key) == "number" or text:match("^%d+$") then
                refKey = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(tonumber(key))
            elseif EbonBuilds.EchoCatalog then
                local refs = EbonBuilds.EchoCatalog.FindLegacyRefs
                    and EbonBuilds.EchoCatalog.FindLegacyRefs(text)
                    or EbonBuilds.EchoCatalog.FindRefs(text)
                if #refs == 1 then refKey = refs[1]
                elseif #refs > 1 then unresolvedWhitelist[text] = true end
            end
            if refKey and EbonBuilds.EchoCatalog.GetByRef(refKey) then cleanWhitelist[refKey] = true end
        end
    end
    settings.echoWhitelist = cleanWhitelist
    settings.unresolvedEchoWhitelist = next(unresolvedWhitelist) and unresolvedWhitelist or nil

    local cleanBanList = {}
    for spellId, label in pairs(settings.echoBanList) do
        local numericId = tonumber(spellId) or spellId
        local refKey = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetRefForSpell(numericId)
        if not (refKey and cleanWhitelist[refKey]) then cleanBanList[numericId] = label end
    end
    settings.echoBanList = cleanBanList
    if EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.Normalize then
        EbonBuilds.EchoPolicy.Normalize(settings)
    end
end

local function RestoreWizardAvoidPolicies(build)
    if type(build) ~= "table" then return 0 end
    local refs = build.wizardMeta and build.wizardMeta.avoidPolicyRefs
    if type(refs) ~= "table" then return 0 end
    EnsureSettings(build)
    build.settings.echoPolicies = type(build.settings.echoPolicies) == "table" and build.settings.echoPolicies or {}
    local applied = 0
    for _, refKey in ipairs(refs) do
        if type(refKey) == "string" and refKey:match("^[gs]:%d+$") then
            build.settings.echoPolicies[refKey] = "never_pick"
            applied = applied + 1
        end
    end
    return applied
end

function EbonBuilds.Build.NormalizeData(build)
    if not build then return end
    EnsureSettings(build)
    -- Repair builds made by older Wizard revisions before policy
    -- normalization. The Wizard's Avoid list is authoritative.
    RestoreWizardAvoidPolicies(build)
    NormalizeProtection(build)
    -- NormalizeProtection may rewrite the policy table; enforce the required
    -- Avoid policies once more under their canonical ref keys.
    RestoreWizardAvoidPolicies(build)
    if EbonBuilds.Weights and EbonBuilds.Weights.NormalizeWeights then
        build.echoWeights = EbonBuilds.Weights.NormalizeWeights(build.echoWeights or {})
        if type(build.echoWeightsByRef) == "table" and EbonBuilds.Weights.NormalizeRefWeights then
            build.echoWeightsByRef = EbonBuilds.Weights.NormalizeRefWeights(build.echoWeightsByRef)
        end
    else
        build.echoWeights = build.echoWeights or {}
    end
end

EbonBuilds.Build.NormalizeProtection = NormalizeProtection
EbonBuilds.Build.RestoreWizardAvoidPolicies = RestoreWizardAvoidPolicies

function EbonBuilds.Build.Checksum(build)
    if not build then return Digest("") end
    return Digest({
        title = build.title,
        comments = build.comments,
        strategyHash = EbonBuilds.Build.StrategyChecksum(build),
        isPublic = build.isPublic == true,
        characterSnapshot = build.characterSnapshot,
    })
end

local function NewQualityStats()
    local values = {}
    local order = EbonBuilds.Quality and EbonBuilds.Quality.ORDER or {}
    for _, quality in ipairs(order) do values[quality] = 0 end
    return values
end

local function EnsureStats(build)
    build.stats = build.stats or {
        echoesSeen    = 0,
        runsCompleted = 0,
        runsReset     = 0,
        picks         = 0,
        rerollsUsed   = 0,
        banishesUsed  = 0,
        freezesUsed   = 0,
        qualityPicks  = NewQualityStats(),
        mostPicked    = {},
        mostBanned    = {},
    }
    build.stats.qualityPicks = build.stats.qualityPicks or NewQualityStats()
    build.stats.mostPicked   = build.stats.mostPicked   or {}
    build.stats.mostBanned   = build.stats.mostBanned   or {}
    if not build.author then build.author = "Unknown" end
    if not build.lastModified then build.lastModified = date("%Y-%m-%d %H:%M:%S") end
    if build.isPublic == nil then build.isPublic = false end
    if build.validated == nil then build.validated = false end
    if build.copiedFrom == nil then build.copiedFrom = nil end
end

local function RuntimeFor(build, defaultAutomation)
    if not build or not build.id then return nil end
    EbonBuildsCharDB.buildRuntime = EbonBuildsCharDB.buildRuntime or {}
    local runtime = EbonBuildsCharDB.buildRuntime[build.id]
    if not runtime then
        runtime = {
            automationEnabled = defaultAutomation == true,
            manualTrainingEnabled = false,
        }
        EbonBuildsCharDB.buildRuntime[build.id] = runtime
    end
    if build.automationEnabled ~= nil then
        runtime.automationEnabled = build.automationEnabled == true
        build.automationEnabled = nil
    end
    if build.manualTrainingEnabled ~= nil then
        runtime.manualTrainingEnabled = build.manualTrainingEnabled == true
        build.manualTrainingEnabled = nil
    end
    return runtime
end

function EbonBuilds.Build.EnsureRuntime(build, defaultAutomation)
    return RuntimeFor(build, defaultAutomation)
end

function EbonBuilds.Build.IsAutomationEnabled(build)
    local runtime = RuntimeFor(build, false)
    return runtime and runtime.automationEnabled == true or false
end

function EbonBuilds.Build.SetAutomationEnabled(build, enabled)
    local runtime = RuntimeFor(build, false)
    if not runtime then return false end
    runtime.automationEnabled = enabled == true
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_RUNTIME_CHANGED", build.id) end
    return runtime.automationEnabled
end

function EbonBuilds.Build.IsTrainingEnabled(build)
    local runtime = RuntimeFor(build, false)
    return runtime and runtime.manualTrainingEnabled == true or false
end

function EbonBuilds.Build.SetTrainingEnabled(build, enabled)
    local runtime = RuntimeFor(build, false)
    if not runtime then return false end
    runtime.manualTrainingEnabled = enabled == true
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_RUNTIME_CHANGED", build.id) end
    return runtime.manualTrainingEnabled
end

local activeChangeCallbacks = {}

local function Notify()
    for i = 1, #activeChangeCallbacks do
        activeChangeCallbacks[i]()
    end
end

function EbonBuilds.Build.OnActiveChanged(fn)
    activeChangeCallbacks[#activeChangeCallbacks + 1] = fn
end

------------------------------------------------------------------------
-- UUID
------------------------------------------------------------------------

function EbonBuilds.Build.NewObjectId()
    return string.format("%08x%04x%04x%04x%04x",
        time(),
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535))
end

------------------------------------------------------------------------
-- Talent helpers
------------------------------------------------------------------------

local function PlayerClassToken()
    return select(2, UnitClass("player"))
end

local function PlayerTopTalentTab()
    local best, bestPoints = 1, -1
    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i)
        pointsSpent = pointsSpent or 0
        if pointsSpent > bestPoints then
            best, bestPoints = i, pointsSpent
        end
    end
    return best
end

EbonBuilds.Build.PlayerClassToken   = PlayerClassToken
EbonBuilds.Build.PlayerTopTalentTab = PlayerTopTalentTab

local function NormalizePlayerName(name)
    name = tostring(name or ""):lower()
    return name:match("^([^-]+)") or name
end
EbonBuilds.Build._NormalizePlayerName = NormalizePlayerName

------------------------------------------------------------------------
-- Migration
------------------------------------------------------------------------

function EbonBuilds.Build.Migrate()
    EbonBuildsDB.builds        = EbonBuildsDB.builds        or {}
    EbonBuildsCharDB.activeBuildId = EbonBuildsCharDB.activeBuildId or nil

    -- Migrate old per-account activeBuildId to per-character
    if EbonBuildsDB.activeBuildId and not EbonBuildsCharDB.activeBuildId then
        EbonBuildsCharDB.activeBuildId = EbonBuildsDB.activeBuildId
    end
    EbonBuildsDB.activeBuildId = nil

    local legacy = EbonBuildsDB.echoWeights
    if legacy and not next(EbonBuildsDB.builds) then
        local id = EbonBuilds.Build.NewObjectId()
        EbonBuildsDB.builds[id] = {
            id              = id,
            title           = "Migrated",
            class           = PlayerClassToken(),
            spec            = PlayerTopTalentTab(),
            comments        = "",
            lockedEchoes = { nil, nil, nil, nil, nil, nil },
            echoWeights     = legacy,
            settings        = DefaultSettings(),
            version         = 1,
        }
        EbonBuildsCharDB.activeBuildId = id
    end
    EbonBuildsDB.echoWeights = nil

    for _, b in pairs(EbonBuildsDB.builds) do
        EbonBuilds.Build.NormalizeData(b)
        EnsureStats(b)
        b.revision = tonumber(b.revision) or tonumber(b.version) or 1
        b.version = b.revision
        b.strategyRevision = tonumber(b.strategyRevision) or 1
        b.strategyHash = EbonBuilds.Build.StrategyChecksum(b)
        b._checksum = EbonBuilds.Build.Checksum(b)
        local ownedHere = not b.importedFrom
            and NormalizePlayerName(b.author) == NormalizePlayerName(UnitName("player"))
        RuntimeFor(b, ownedHere)
    end

    EbonBuilds.Build.MigrateIds()
end

function EbonBuilds.Build.MigrateIds()
    local oldIds = {}
    for id, b in pairs(EbonBuildsDB.builds) do
        if id:match("-") then oldIds[#oldIds + 1] = id end
    end

    if #oldIds == 0 then return end

    local map = {}
    for _, oldId in ipairs(oldIds) do
        map[oldId] = EbonBuilds.Build.NewObjectId()
    end

    for _, oldId in ipairs(oldIds) do
        local newId = map[oldId]
        local build = EbonBuildsDB.builds[oldId]
        build.id = newId
        EbonBuildsDB.builds[newId] = build
        EbonBuildsDB.builds[oldId] = nil
        if EbonBuildsCharDB.buildRuntime and EbonBuildsCharDB.buildRuntime[oldId] then
            EbonBuildsCharDB.buildRuntime[newId] = EbonBuildsCharDB.buildRuntime[oldId]
            EbonBuildsCharDB.buildRuntime[oldId] = nil
        end
    end

    if EbonBuildsCharDB.activeBuildId and map[EbonBuildsCharDB.activeBuildId] then
        EbonBuildsCharDB.activeBuildId = map[EbonBuildsCharDB.activeBuildId]
    end

    for _, build in pairs(EbonBuildsDB.builds) do
        if build.importedFrom and map[build.importedFrom] then
            build.importedFrom = map[build.importedFrom]
        end
    end
end

------------------------------------------------------------------------
-- CRUD
------------------------------------------------------------------------

function EbonBuilds.Build.List()
    local out = {}
    for _, b in pairs(EbonBuildsDB.builds) do
        out[#out + 1] = b
    end
    table.sort(out, function(a, b) return (a.title or "") < (b.title or "") end)
    return out
end

function EbonBuilds.Build.ListPublic()
    local out = {}
    -- Local public builds
    for _, b in pairs(EbonBuildsDB.builds) do
        if type(b) == "table" and b.isPublic then out[#out + 1] = b end
    end
    -- Remote builds (received via sync)
    if EbonBuildsDB.remoteBuilds then
        for _, b in pairs(EbonBuildsDB.remoteBuilds) do
            if type(b) == "table" then out[#out + 1] = b end
        end
    end

    -- Collapse same-titled builds from different authors down to one (the
    -- earliest-known copy). Build.Save() now stops NEW duplicates from
    -- being created, but this cleans up anything that already exists
    -- (from before that fix, or synced from a peer who hasn't updated
    -- yet) immediately, in both the browsing list and anything relayed
    -- onward via HandleRequest (which also calls ListPublic()).
    local byTitle = {}
    local deduped = {}
    for _, b in ipairs(out) do
        if type(b) == "table" then
            local key = (b.title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if key == "" then
                deduped[#deduped + 1] = b -- never collapse untitled builds against each other
            else
                local existing = byTitle[key]
                if not existing then
                    byTitle[key] = b
                elseif (b.lastModified or "") < (existing.lastModified or "") then
                    byTitle[key] = b
                end
            end
        end
    end
    for _, b in pairs(byTitle) do
        if type(b) == "table" then deduped[#deduped + 1] = b end
    end

    -- Author-reported locally run-tested builds first, then by recency.
    table.sort(deduped, function(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            if type(a) ~= "table" and type(b) ~= "table" then return false end
            return type(b) ~= "table"
        end
        local av = a.validated and 1 or 0
        local bv = b.validated and 1 or 0
        if av ~= bv then return av > bv end
        return (a.lastModified or "") > (b.lastModified or "")
    end)
    return deduped
end

function EbonBuilds.Build.Get(id)
    if not id then return nil end
    return EbonBuildsDB.builds[id]
end

function EbonBuilds.Build.GetActive()
    local build = EbonBuilds.Build.Get(EbonBuildsCharDB.activeBuildId)
    -- While the editor holds a pending draft, skip migration Ensure. Save
    -- replaces echoWeightsByRef with a new table and bumps revision, which
    -- invalidates the migration cache; Ensure would rewrite the just-saved
    -- maps before AcceptSavedBuild could adopt them as the clean baseline.
    if build and EbonBuilds.EchoReferenceMigration
        and not (EbonBuilds.Runtime and EbonBuilds.Runtime.isEditingBuild) then
        EbonBuilds.EchoReferenceMigration.Ensure(build)
    end
    return build
end

function EbonBuilds.Build.SetActive(id)
    if EbonBuildsCharDB.activeBuildId == id then return end
    EbonBuildsCharDB.activeBuildId = id
    local active = EbonBuilds.Build.Get(id)
    if active then
        if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(active) end
        RuntimeFor(active, false)
    end
    -- The automation peak is relative to the active build's weights and
    -- settings; switching builds invalidates it.
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    Notify()
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("ACTIVE_BUILD_CHANGED", id) end
end

function EbonBuilds.Build.GetActiveWeights()
    if EbonBuilds.Runtime.isEditingBuild then
        EbonBuilds.Runtime.pendingWeights = EbonBuilds.Runtime.pendingWeights or {}
        return EbonBuilds.Runtime.pendingWeights
    end
    local build = EbonBuilds.Build.GetActive()
    if build then
        build.echoWeights = build.echoWeights or {}
        return build.echoWeights
    end
    EbonBuilds.Runtime.pendingWeights = EbonBuilds.Runtime.pendingWeights or {}
    return EbonBuilds.Runtime.pendingWeights
end

function EbonBuilds.Build.GetActiveRefWeights()
    if EbonBuilds.Runtime.isEditingBuild then
        EbonBuilds.Runtime.pendingRefWeights = EbonBuilds.Runtime.pendingRefWeights or {}
        return EbonBuilds.Runtime.pendingRefWeights
    end
    local build = EbonBuilds.Build.GetActive()
    if build then
        if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end
        build.echoWeightsByRef = build.echoWeightsByRef or {}
        return build.echoWeightsByRef
    end
    EbonBuilds.Runtime.pendingRefWeights = EbonBuilds.Runtime.pendingRefWeights or {}
    return EbonBuilds.Runtime.pendingRefWeights
end

-- UnitName("player") is not guaranteed to return the same FORMAT across
-- sessions -- it can come back with or without a "-Realm" suffix depending
-- on connection state (this is a known WoW client quirk around cross-realm
-- zones and reconnects). Comparing it exactly against a stored author name
-- risks treating the player's OWN build as foreign, which forks it under a
-- new id and DELETES the original -- a real data-loss bug. Strip the realm
-- suffix and case before comparing, same normalization already used for
-- sync/affix sender checks.
local function NormalizeTitle(title)
    return tostring(title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Is `title` already publicly claimed by someone other than `author`?
-- Scans this player's own public builds plus everything received via
-- sync (EbonBuildsDB.remoteBuilds). Only the earliest-known build under
-- that exact name is considered its "owner" -- there's no central
-- registry to authorize this against (ProjectEbonhold is the server and
-- this addon doesn't touch it), so this is a best-effort, client-side
-- safeguard: it stops any individual honest client from re-publishing a
-- name it can see is already taken, which is what actually causes the
-- same title to multiply across many authors in Public Builds (each
-- import -> tiny edit -> save silently forks a same-titled public copy).
local function FindTitleOwner(title, excludeId, excludeAuthor)
    local norm = NormalizeTitle(title)
    if norm == "" then return nil end
    local excludeNorm = excludeAuthor and NormalizePlayerName(excludeAuthor)

    local function Check(b)
        if not b or b.id == excludeId then return nil end
        if NormalizeTitle(b.title) ~= norm then return nil end
        if excludeNorm and NormalizePlayerName(b.author or "") == excludeNorm then return nil end
        return b
    end

    local best = nil
    local function Consider(b)
        local hit = Check(b)
        if hit and (not best or (hit.lastModified or "") < (best.lastModified or "")) then
            best = hit
        end
    end

    for _, b in pairs(EbonBuildsDB.builds) do
        if b.isPublic then Consider(b) end
    end
    if EbonBuildsDB.remoteBuilds then
        for _, b in pairs(EbonBuildsDB.remoteBuilds) do Consider(b) end
    end
    return best
end
EbonBuilds.Build.FindTitleOwner = FindTitleOwner

StaticPopupDialogs["EBONBUILDS_TITLE_TAKEN"] = {
    text = "The build name \"%s\" is already public under %s.\n\nYour copy has been unpublished so Public Builds doesn't end up with duplicates of the same name. Rename it (Edit Build) if you'd like to share your own version.",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- If this build is public and its title collides with someone else's
-- already-public/known build, un-publish it and tell the player why.
-- Called both right after a fork (the usual trigger: import -> edit ->
-- save) and generally whenever isPublic is turned on (including a brand
-- new build created with "Make Public" already checked), so a
-- coincidental name collision is always caught, not just the fork case.
local function EnforceTitleUniqueness(build)
    if not build.isPublic then return end
    local owner = FindTitleOwner(build.title, build.id, build.author)
    if owner then
        build.isPublic = false
        StaticPopup_Show("EBONBUILDS_TITLE_TAKEN", build.title, owner.author or "another player")
    end
end

function EbonBuilds.Build.NewObject(data)
    local id = EbonBuilds.Build.NewObjectId()
    local build = {
        id              = id,
        title           = data.title or "Untitled",
        class           = data.class or PlayerClassToken(),
        spec            = data.spec or PlayerTopTalentTab(),
        comments        = data.comments or "",
        lockedEchoes = CloneTable(data.lockedEchoes or { nil, nil, nil, nil, nil, nil }),
        echoWeights     = CloneTable(data.echoWeights or {}),
        echoWeightsByRef = CloneTable(data.echoWeightsByRef or {}),
        echoRefs         = CloneTable(data.echoRefs or {}),
        unresolvedEchoWeights = CloneTable(data.unresolvedEchoWeights),
        echoSchema       = tonumber(data.echoSchema) or (data.echoWeightsByRef and 3 or nil),
        echoCatalogFingerprint = data.echoCatalogFingerprint,
        settings        = CloneTable(data.settings or DefaultSettings()),
        version         = 1,
        revision        = 1,
        strategyRevision = 1,
        author          = data.author or UnitName("player") or "Unknown",
        lastModified    = data.lastModified or date("%Y-%m-%d %H:%M:%S"),
        isPublic         = data.isPublic or false,
        validated         = data.validated or false,
        copiedFrom        = data.copiedFrom or nil,
        wizardMeta        = data.wizardMeta and CloneTable(data.wizardMeta) or nil,
        characterSnapshot = data.characterSnapshot and CloneTable(data.characterSnapshot) or nil,
        stats            = {
            echoesSeen    = 0,
            runsCompleted = 0,
            runsReset     = 0,
            picks         = 0,
            rerollsUsed   = 0,
            banishesUsed  = 0,
            freezesUsed   = 0,
            qualityPicks  = NewQualityStats(),
            mostPicked    = {},
            mostBanned    = {},
        },
    }
    EbonBuilds.Build.NormalizeData(build)
    build.strategyHash = EbonBuilds.Build.StrategyChecksum(build)
    build._checksum = EbonBuilds.Build.Checksum(build)
    return build
end

local function ApplyWizardAvoidPolicies(build, data)
    local meta = (data and data.wizardMeta) or (build and build.wizardMeta)
    local refs = meta and meta.avoidPolicyRefs
    local api = EbonBuilds.EchoPolicy
    if type(refs) ~= "table" or not api then return 0 end
    build.settings = build.settings or DefaultSettings()
    build.settings.echoPolicies = type(build.settings.echoPolicies) == "table" and build.settings.echoPolicies or {}
    local applied = 0
    for _, refKey in ipairs(refs) do
        if type(refKey) == "string" and refKey:match("^[gs]:%d+$") then
            local ok
            if api.EnsureNeverPick then ok = api.EnsureNeverPick(build.settings, refKey)
            elseif api.SetRef then ok = api.SetRef(build.settings, refKey, api.NEVER_PICK)
            elseif api.Set then ok = api.Set(build.settings, refKey, api.NEVER_PICK) end
            -- Last-resort canonical write. Avoid is a required Wizard policy,
            -- so it must survive even if catalogue resolution is unavailable.
            if not ok then
                build.settings.echoPolicies[refKey] = api.NEVER_PICK or "never_pick"
                ok = true
            end
            if ok then applied = applied + 1 end
        end
    end
    return applied
end

function EbonBuilds.Build.Create(data)
    local build = EbonBuilds.Build.NewObject(data)
    local sourceWeights = data and data.echoWeights ~= nil and build.echoWeights
        or EbonBuilds.Runtime.pendingWeights or build.echoWeights
    build.echoWeights = EbonBuilds.Weights.NormalizeWeights(sourceWeights)
    local sourceRefWeights = data and data.echoWeightsByRef ~= nil and data.echoWeightsByRef
        or EbonBuilds.Runtime.pendingRefWeights or build.echoWeightsByRef
    build.echoWeightsByRef = EbonBuilds.Weights.NormalizeRefWeights(sourceRefWeights or {})
    if next(build.echoWeightsByRef) then
        build.echoSchema = 3
        build.echoCatalogFingerprint = data.echoCatalogFingerprint
            or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint())
    end
    EbonBuilds.Runtime.pendingWeights = nil
    EbonBuilds.Runtime.pendingRefWeights = nil
    EbonBuilds.Build.NormalizeData(build)
    ApplyWizardAvoidPolicies(build, data)
    -- Re-normalize after applying required Wizard policies. EchoPolicy.Normalize
    -- keeps canonical ref keys and guarantees the policy reaches UI/automation.
    EbonBuilds.Build.NormalizeData(build)
    build.strategyHash = EbonBuilds.Build.StrategyChecksum(build)
    build._checksum = EbonBuilds.Build.Checksum(build)
    EbonBuildsDB.builds[build.id] = build
    RuntimeFor(build, data and data.startPaused ~= true)
    EnforceTitleUniqueness(build)
    build._checksum = EbonBuilds.Build.Checksum(build)
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", build.id, "created") end
    return build
end

-- Creates a full copy of an existing build under a new id, with fresh stats,
-- private visibility, and "(Copy)" appended to the title. Returns the copy.
function EbonBuilds.Build.Duplicate(sourceId)
    local source = EbonBuildsDB.builds[sourceId]
    if not source then return nil end
    local copy = EbonBuilds.Build.NewObject({
        title        = (source.title or "Untitled") .. " (Copy)",
        class        = source.class,
        spec         = source.spec,
        comments     = source.comments,
        lockedEchoes = CloneTable(source.lockedEchoes or {}),
        echoWeights  = CloneTable(source.echoWeights or {}),
        echoWeightsByRef = CloneTable(source.echoWeightsByRef or {}),
        echoRefs = CloneTable(source.echoRefs or {}),
        unresolvedEchoWeights = CloneTable(source.unresolvedEchoWeights),
        echoSchema = source.echoSchema,
        echoCatalogFingerprint = source.echoCatalogFingerprint,
        settings     = EbonBuilds.Build.CloneSettings(source.settings or DefaultSettings()),
        isPublic     = false,
        copiedFrom   = source.id,
        wizardMeta   = CloneTable(source.wizardMeta),
    })
    EbonBuildsDB.builds[copy.id] = copy
    local sourceRuntime = RuntimeFor(source, false)
    local copyRuntime = RuntimeFor(copy, false)
    copyRuntime.automationEnabled = sourceRuntime and sourceRuntime.automationEnabled == true or false
    copyRuntime.manualTrainingEnabled = sourceRuntime and sourceRuntime.manualTrainingEnabled == true or false
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", copy.id, "created") end
    return copy
end

function EbonBuilds.Build.UpdateFromPublic(localBuild, publicBuild)
    localBuild.title            = publicBuild.title            or localBuild.title
    localBuild.class            = publicBuild.class            or localBuild.class
    localBuild.spec             = publicBuild.spec             or localBuild.spec
    localBuild.comments         = publicBuild.comments         or localBuild.comments
    localBuild.lockedEchoes     = { nil, nil, nil, nil, nil, nil }
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        localBuild.lockedEchoes[i] = (publicBuild.lockedEchoes and publicBuild.lockedEchoes[i]) or nil
    end
    if publicBuild.settings then
        localBuild.settings = EbonBuilds.Build.CloneSettings(publicBuild.settings)
    end
    if publicBuild.echoWeights and next(publicBuild.echoWeights) then
        localBuild.echoWeights = EbonBuilds.Weights.CloneWeights(publicBuild.echoWeights)
    end
    if publicBuild.echoWeightsByRef and next(publicBuild.echoWeightsByRef) then
        localBuild.echoWeightsByRef = EbonBuilds.Weights.CloneRefWeights(publicBuild.echoWeightsByRef)
        localBuild.echoRefs = CloneTable(publicBuild.echoRefs or {})
        localBuild.unresolvedEchoWeights = CloneTable(publicBuild.unresolvedEchoWeights)
        localBuild.echoSchema = publicBuild.echoSchema or 3
        localBuild.echoCatalogFingerprint = publicBuild.echoCatalogFingerprint
    end
    if publicBuild.copiedFrom then
        localBuild.copiedFrom = publicBuild.copiedFrom
    end
    localBuild.wizardMeta = CloneTable(publicBuild.wizardMeta)
    localBuild._importedAt = publicBuild.lastModified
    localBuild.lastModified = date("%Y-%m-%d %H:%M:%S")
    localBuild.revision = (tonumber(localBuild.revision) or tonumber(localBuild.version) or 1) + 1
    localBuild.version = localBuild.revision
    localBuild.strategyRevision = (tonumber(localBuild.strategyRevision) or 1) + 1
    EbonBuilds.Build.NormalizeData(localBuild)
    localBuild.strategyHash = EbonBuilds.Build.StrategyChecksum(localBuild)
    localBuild._checksum = EbonBuilds.Build.Checksum(localBuild)
    EbonBuilds.Build.SetAutomationEnabled(localBuild, false)
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", localBuild.id, "updated")
        EbonBuilds.EventHub.Bump("BUILD_REVISION_CHANGED", localBuild.id, localBuild.revision, true)
    end
    return localBuild
end

function EbonBuilds.Build.Save(id, data)
    local build = EbonBuildsDB.builds[id]
    if not build then return nil end
    if data.baseRevision and tonumber(data.baseRevision) ~= (tonumber(build.revision) or 1) then
        return nil, "CONFLICT", build
    end
    local oldChecksum = EbonBuilds.Build.Checksum(build)
    local oldStrategyHash = EbonBuilds.Build.StrategyChecksum(build)
    local classChanged = data.class and data.class ~= build.class
    build.title           = data.title           or build.title
    build.class            = data.class           or build.class
    build.spec             = data.spec            or build.spec
    build.comments         = data.comments        or build.comments
    build.lockedEchoes = data.lockedEchoes or build.lockedEchoes
    if data.settings then build.settings = EbonBuilds.Build.CloneSettings(data.settings) end
    if data.echoWeights then build.echoWeights = EbonBuilds.Weights.CloneWeights(data.echoWeights) end
    if data.echoWeightsByRef then
        build.echoWeightsByRef = EbonBuilds.Weights.CloneRefWeights(data.echoWeightsByRef)
        build.echoSchema = data.echoSchema or 3
        build.echoCatalogFingerprint = data.echoCatalogFingerprint
            or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint())
    end
    if data.echoRefs ~= nil then build.echoRefs = CloneTable(data.echoRefs) end
    if data.unresolvedEchoWeights ~= nil then build.unresolvedEchoWeights = CloneTable(data.unresolvedEchoWeights) end
    if data.isPublic ~= nil then build.isPublic = data.isPublic end
    if data.characterSnapshot ~= nil then build.characterSnapshot = CloneTable(data.characterSnapshot) end
    if data.clearCharacterSnapshot then build.characterSnapshot = nil end
    if data.wizardMeta ~= nil then build.wizardMeta = CloneTable(data.wizardMeta) end
    if data.clearWizardMeta then build.wizardMeta = nil end
    EbonBuilds.Build.NormalizeData(build)
    ApplyWizardAvoidPolicies(build, data)
    EbonBuilds.Build.NormalizeData(build)
    EnforceTitleUniqueness(build)
    local newStrategyHash = EbonBuilds.Build.StrategyChecksum(build)
    local newChecksum = EbonBuilds.Build.Checksum(build)
    local strategyChanged = newStrategyHash ~= oldStrategyHash
    if newChecksum ~= oldChecksum then
        build.revision = (tonumber(build.revision) or tonumber(build.version) or 1) + 1
        build.version = build.revision
        if strategyChanged then
            build.strategyRevision = (tonumber(build.strategyRevision) or 1) + 1
            build.validated = false
            if EbonBuilds.Session and EbonBuilds.Session.MarkStrategyChanged then
                EbonBuilds.Session.MarkStrategyChanged(build, oldStrategyHash, newStrategyHash)
            end
            if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
                EbonBuilds.Automation.ResetPeakCache()
            end
        end
        build.strategyHash = newStrategyHash
        build._checksum = newChecksum
        build.lastModified = date("%Y-%m-%d %H:%M:%S")
        local playerName = UnitName("player") or "Unknown"
        if build.author and NormalizePlayerName(build.author) ~= NormalizePlayerName(playerName) then
            build.copiedFrom = build.author
            build.author = playerName
            build.validated = false
            build.importedFrom = nil
            local newId = EbonBuilds.Build.NewObjectId()
            local runtime = EbonBuildsCharDB.buildRuntime and EbonBuildsCharDB.buildRuntime[id]
            build.id = newId
            EbonBuildsDB.builds[newId] = build
            EbonBuildsDB.builds[id] = nil
            if runtime then
                EbonBuildsCharDB.buildRuntime[newId] = runtime
                EbonBuildsCharDB.buildRuntime[id] = nil
            else
                RuntimeFor(build, false)
            end
            if EbonBuildsCharDB.activeBuildId == id then
                EbonBuildsCharDB.activeBuildId = newId
                Notify()
            end
        end
        if EbonBuilds.EventHub then
            EbonBuilds.EventHub.Bump("BUILD_REVISION_CHANGED", build.id, build.revision, strategyChanged)
            EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", build.id, "updated")
        end
    else
        build.strategyHash = newStrategyHash
        build._checksum = newChecksum
    end
    build._checksum = EbonBuilds.Build.Checksum(build)
    if classChanged and EbonBuildsCharDB.activeBuildId == id then
        Notify()
    end
    return build
end

-- Last deleted build, kept in memory (not saved variables) so an accidental
-- delete can be undone until the next delete or a /reload.
local lastDeleted = nil
local lastDeletedRuntime = nil

function EbonBuilds.Build.Delete(id)
    if not id then return end
    lastDeleted = EbonBuildsDB.builds[id]
    lastDeletedRuntime = EbonBuildsCharDB.buildRuntime and EbonBuildsCharDB.buildRuntime[id] or nil
    EbonBuildsDB.builds[id] = nil
    if EbonBuildsCharDB.buildRuntime then EbonBuildsCharDB.buildRuntime[id] = nil end
    if EbonBuildsCharDB.activeBuildId == id then
        EbonBuildsCharDB.activeBuildId = nil
        Notify()
        if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("ACTIVE_BUILD_CHANGED", nil) end
    end
    if lastDeleted and EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", id, "deleted")
    end
end

-- Restores the most recently deleted build. Returns the build or nil.
function EbonBuilds.Build.RestoreLastDeleted()
    if not lastDeleted or not lastDeleted.id then return nil end
    -- Guard against id collision if a new build somehow reused the id.
    if EbonBuildsDB.builds[lastDeleted.id] then
        lastDeleted.id = EbonBuilds.Build.NewObjectId()
    end
    EbonBuildsDB.builds[lastDeleted.id] = lastDeleted
    if lastDeletedRuntime then
        EbonBuildsCharDB.buildRuntime[lastDeleted.id] = lastDeletedRuntime
    else
        RuntimeFor(lastDeleted, false)
    end
    local restored = lastDeleted
    lastDeleted = nil
    lastDeletedRuntime = nil
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", restored.id, "restored") end
    return restored
end
