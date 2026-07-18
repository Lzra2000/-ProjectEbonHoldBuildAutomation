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

local function NormalizeProtection(build)
    EnsureSettings(build)
    local settings = build.settings
    if type(settings.echoWhitelist) ~= "table" then settings.echoWhitelist = {} end
    if type(settings.echoBanList) ~= "table" then settings.echoBanList = {} end

    -- Keep only explicit true values under canonical echo-name keys. Imported
    -- suffix-bearing names and numeric spell-id keys are repaired defensively.
    local cleanWhitelist = {}
    for key, enabled in pairs(settings.echoWhitelist) do
        local isEnabled = enabled == true or enabled == 1 or enabled == "1" or enabled == "true"
        if isEnabled then
            local name
            if type(key) == "number" or (type(key) == "string" and key:match("^%d+$")) then
                name = EbonBuilds.Weights and EbonBuilds.Weights.CanonicalName(tonumber(key))
            elseif type(key) == "string" then
                name = EbonBuilds.Weights and EbonBuilds.Weights.StripQualitySuffix(key) or key
            end
            if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
            if name and name ~= "" then cleanWhitelist[name] = true end
        end
    end
    settings.echoWhitelist = cleanWhitelist

    -- Whitelist wins over imported or legacy ban-list conflicts. This also
    -- protects every quality tier of a whitelisted echo family. Numeric-string
    -- spell IDs are canonicalized at the same time so every consumer can use
    -- the normal numeric database lookup path.
    local cleanBanList = {}
    for spellId, label in pairs(settings.echoBanList) do
        local numericId = tonumber(spellId) or spellId
        local canonical = EbonBuilds.Weights and EbonBuilds.Weights.CanonicalName(numericId)
        if not (canonical and cleanWhitelist[canonical]) then
            cleanBanList[numericId] = label
        end
    end
    settings.echoBanList = cleanBanList
    if EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.Normalize then
        EbonBuilds.EchoPolicy.Normalize(settings)
    end
end

function EbonBuilds.Build.NormalizeData(build)
    if not build then return end
    EnsureSettings(build)
    NormalizeProtection(build)
    if EbonBuilds.Weights and EbonBuilds.Weights.NormalizeWeights then
        build.echoWeights = EbonBuilds.Weights.NormalizeWeights(build.echoWeights or {})
    else
        build.echoWeights = build.echoWeights or {}
    end
end

EbonBuilds.Build.NormalizeProtection = NormalizeProtection

function EbonBuilds.Build.Checksum(build)
    local parts = {
        build.title or "",
        build.class or "",
        tostring(build.spec or 1),
        build.comments or "",
    }
    local le = build.lockedEchoes or {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        parts[#parts + 1] = tostring(le[i] or "nil")
    end
    if build.echoWeights then
        local names = {}
        for name, entry in pairs(build.echoWeights) do
            if EbonBuilds.Weights and EbonBuilds.Weights.HasNonZero(entry) then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                local value = EbonBuilds.Weights.GetFromWeights(build.echoWeights, name, quality)
                if value ~= 0 then
                    parts[#parts + 1] = name .. ":" .. tostring(quality) .. "=" .. tostring(value)
                end
            end
        end
    end
    parts[#parts + 1] = tostring(build.automationEnabled and 1 or 0)
    local s = CloneTable(build.settings or DefaultSettings())
    parts[#parts + 1] = EbonBuilds.ExportImport and EbonBuilds.ExportImport.JSONEncode and EbonBuilds.ExportImport.JSONEncode(s) or ""
    return table.concat(parts, "|")
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
    if build.automationEnabled == nil then build.automationEnabled = true end
    if build.manualTrainingEnabled == nil then build.manualTrainingEnabled = false end
    if not build.author then build.author = "Unknown" end
    if not build.lastModified then build.lastModified = date("%Y-%m-%d %H:%M:%S") end
    if build.isPublic == nil then build.isPublic = false end
    if build.validated == nil then build.validated = false end
    if build.copiedFrom == nil then build.copiedFrom = nil end
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

function EbonBuilds.Build.NewId()
    local name = UnitName("player") or "unknown"
    return tostring(time()) .. "-" .. tostring(math.random(1, 1000000000)) .. "-" .. name
end

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
        if b.isPublic then out[#out + 1] = b end
    end
    -- Remote builds (received via sync)
    if EbonBuildsDB.remoteBuilds then
        for _, b in pairs(EbonBuildsDB.remoteBuilds) do
            out[#out + 1] = b
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
    for _, b in pairs(byTitle) do deduped[#deduped + 1] = b end

    -- Validated builds (proven to reach level 80) first, then by recency.
    table.sort(deduped, function(a, b)
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
    return EbonBuilds.Build.Get(EbonBuildsCharDB.activeBuildId)
end

function EbonBuilds.Build.SetActive(id)
    if EbonBuildsCharDB.activeBuildId == id then return end
    EbonBuildsCharDB.activeBuildId = id
    -- The automation peak is relative to the active build's weights and
    -- settings; switching builds invalidates it.
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    Notify()
end

function EbonBuilds.Build.GetActiveWeights()
    if EbonBuildsDB._isEditingBuild then
        EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
        return EbonBuildsDB.pendingWeights
    end
    local build = EbonBuilds.Build.GetActive()
    if build then
        build.echoWeights = build.echoWeights or {}
        return build.echoWeights
    end
    EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
    return EbonBuildsDB.pendingWeights
end

-- UnitName("player") is not guaranteed to return the same FORMAT across
-- sessions -- it can come back with or without a "-Realm" suffix depending
-- on connection state (this is a known WoW client quirk around cross-realm
-- zones and reconnects). Comparing it exactly against a stored author name
-- risks treating the player's OWN build as foreign, which forks it under a
-- new id and DELETES the original -- a real data-loss bug. Strip the realm
-- suffix and case before comparing, same normalization already used for
-- sync/affix sender checks.
local function NormalizePlayerName(name)
    name = tostring(name or ""):lower()
    return name:match("^([^-]+)") or name
end
EbonBuilds.Build._NormalizePlayerName = NormalizePlayerName

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
        settings        = CloneTable(data.settings or DefaultSettings()),
        version         = 1,
        author          = data.author or UnitName("player") or "Unknown",
        lastModified    = data.lastModified or date("%Y-%m-%d %H:%M:%S"),
        automationEnabled = (data.automationEnabled ~= nil) and data.automationEnabled or true,
        manualTrainingEnabled = data.manualTrainingEnabled == true,
        isPublic         = data.isPublic or false,
        validated         = data.validated or false,
        copiedFrom        = data.copiedFrom or nil,
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
    build._checksum = EbonBuilds.Build.Checksum(build)
    return build
end

function EbonBuilds.Build.Create(data)
    local build = EbonBuilds.Build.NewObject(data)
    build.echoWeights = EbonBuilds.Weights.NormalizeWeights(EbonBuildsDB.pendingWeights or build.echoWeights)
    EbonBuildsDB.pendingWeights = nil
    EbonBuilds.Build.NormalizeData(build)
    build._checksum = EbonBuilds.Build.Checksum(build)
    EbonBuildsDB.builds[build.id] = build
    EnforceTitleUniqueness(build)
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
        settings     = EbonBuilds.Build.CloneSettings(source.settings or DefaultSettings()),
        manualTrainingEnabled = source.manualTrainingEnabled == true,
        isPublic     = false,
        copiedFrom   = source.id,
    })
    EbonBuildsDB.builds[copy.id] = copy
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
    if publicBuild.automationEnabled ~= nil then
        localBuild.automationEnabled = publicBuild.automationEnabled
    end
    if publicBuild.echoWeights and next(publicBuild.echoWeights) then
        localBuild.echoWeights = EbonBuilds.Weights.CloneWeights(publicBuild.echoWeights)
    end
    if publicBuild.copiedFrom then
        localBuild.copiedFrom = publicBuild.copiedFrom
    end
    localBuild._importedAt = publicBuild.lastModified
    localBuild.lastModified = date("%Y-%m-%d %H:%M:%S")
    localBuild.version = (localBuild.version or 1) + 1
    EbonBuilds.Build.NormalizeData(localBuild)
    localBuild._checksum = EbonBuilds.Build.Checksum(localBuild)
    return localBuild
end

function EbonBuilds.Build.Save(id, data)
    local build = EbonBuildsDB.builds[id]
    if not build then return nil end
    local oldChecksum = build._checksum
    local classChanged = data.class and data.class ~= build.class
    build.title           = data.title           or build.title
    build.class            = data.class           or build.class
    build.spec             = data.spec            or build.spec
    build.comments         = data.comments        or build.comments
    build.lockedEchoes = data.lockedEchoes or build.lockedEchoes
    if data.settings then build.settings = EbonBuilds.Build.CloneSettings(data.settings) end
    if data.echoWeights then build.echoWeights = EbonBuilds.Weights.CloneWeights(data.echoWeights) end
    if data.automationEnabled ~= nil then build.automationEnabled = data.automationEnabled end
    if data.manualTrainingEnabled ~= nil then build.manualTrainingEnabled = data.manualTrainingEnabled end
    if data.isPublic ~= nil then build.isPublic = data.isPublic end
    EbonBuilds.Build.NormalizeData(build)
    build.version         = (build.version or 1) + 1
    build._checksum       = EbonBuilds.Build.Checksum(build)
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
    if build._checksum ~= oldChecksum then
        build.lastModified = date("%Y-%m-%d %H:%M:%S")
        build.validated = false
        local playerName = UnitName("player") or "Unknown"
        if build.author and NormalizePlayerName(build.author) ~= NormalizePlayerName(playerName) then
            build.copiedFrom = build.author
            build.author = playerName
            build.validated = false
            build.importedFrom = nil
            local newId = EbonBuilds.Build.NewObjectId()
            build.id = newId
            EbonBuildsDB.builds[newId] = build
            EbonBuildsDB.builds[id] = nil
            if EbonBuildsCharDB.activeBuildId == id then
                EbonBuildsCharDB.activeBuildId = newId
                Notify()
            end
        end
    end
    EnforceTitleUniqueness(build)
    if classChanged and EbonBuildsCharDB.activeBuildId == id then
        Notify()
    end
    return build
end

-- Last deleted build, kept in memory (not saved variables) so an accidental
-- delete can be undone until the next delete or a /reload.
local lastDeleted = nil

function EbonBuilds.Build.Delete(id)
    if not id then return end
    lastDeleted = EbonBuildsDB.builds[id]
    EbonBuildsDB.builds[id] = nil
    if EbonBuildsCharDB.activeBuildId == id then
        EbonBuildsCharDB.activeBuildId = nil
        Notify()
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
    local restored = lastDeleted
    lastDeleted = nil
    return restored
end

function EbonBuilds.Build.HasRestorableDelete()
    return lastDeleted ~= nil
end
