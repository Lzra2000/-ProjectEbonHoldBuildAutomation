-- EbonBuilds: core/Database.lua
-- Versioned SavedVariables ownership, bounded retention, and runtime scratch.

EbonBuilds.Database = {}
EbonBuilds.Runtime = EbonBuilds.Runtime or {}

local Database = EbonBuilds.Database
local ACCOUNT_SCHEMA = 2
local CHARACTER_SCHEMA = 1
local MAX_RAW_PER_CHARACTER = 30
local MAX_RAW_ACCOUNT = 120
local MAX_REMOTE_BUILDS = 500

-- Every checkbox exposed by Global Settings has one SavedVariables owner and
-- an explicit default. Defaults use == nil so a player's saved false is never
-- mistaken for an unset value during reload or migration.
local CHARACTER_PREFERENCE_DEFAULTS = {
    autoSellJunkEnabled = false,
    bagAffixDotsEnabled = true,
    debugLogEnabled = false,
    clickTraceEnabled = false,
    gearTooltipEnabled = true,
}

local function CharacterKey()
    local name = UnitName and UnitName("player") or "Unknown"
    if tostring(name):find("-", 1, true) then return name end
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then return tostring(name) .. "-" .. tostring(realm) end
    return tostring(name)
end

Database.CharacterKey = CharacterKey

function Database.Init()
    EbonBuildsDB = EbonBuildsDB or {}
    EbonBuildsCharDB = EbonBuildsCharDB or {}

    EbonBuildsDB.schemaVersion = ACCOUNT_SCHEMA
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.builds = EbonBuildsDB.builds or {}
    EbonBuildsDB.remoteBuilds = EbonBuildsDB.remoteBuilds or {}
    EbonBuildsDB.sessions = EbonBuildsDB.sessions or {}
    EbonBuildsDB.buildAggregates = EbonBuildsDB.buildAggregates or {}
    EbonBuildsDB.echoEligibility = EbonBuildsDB.echoEligibility or { schema = 1, scopes = {} }
    EbonBuildsDB.echoEligibility.schema = 1
    EbonBuildsDB.echoEligibility.scopes = EbonBuildsDB.echoEligibility.scopes or {}
    EbonBuildsDB.ui = EbonBuildsDB.ui or {
        layoutPreset = "standard",
        scalePreset = 1,
    }
    EbonBuildsDB.migration = EbonBuildsDB.migration or {
        source = "legacy",
        stage = "complete",
        cursor = 0,
    }

    EbonBuildsCharDB.schemaVersion = CHARACTER_SCHEMA
    EbonBuildsCharDB.buildRuntime = EbonBuildsCharDB.buildRuntime or {}
    EbonBuildsCharDB.consent = EbonBuildsCharDB.consent or {
        performanceVersion = 0,
        performanceEnabled = false,
        communityDpsSharing = false,
        communityAppearanceSharing = false,
    }
    for key, defaultValue in pairs(CHARACTER_PREFERENCE_DEFAULTS) do
        if EbonBuildsCharDB[key] == nil then EbonBuildsCharDB[key] = defaultValue end
    end

    -- Editor state never survives reload. A half-completed draft is
    -- less trustworthy than the last committed build.
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB._wizardPrefill = nil
    EbonBuilds.Runtime.pendingWeights = nil
    EbonBuilds.Runtime.isEditingBuild = nil
    EbonBuilds.Runtime.wizardPrefill = nil
end

function Database.GetCharacterPreference(key)
    if EbonBuildsCharDB and EbonBuildsCharDB[key] ~= nil then
        return EbonBuildsCharDB[key] == true
    end
    return CHARACTER_PREFERENCE_DEFAULTS[key] == true
end

function Database.SetCharacterPreference(key, value)
    if CHARACTER_PREFERENCE_DEFAULTS[key] == nil or not EbonBuildsCharDB then return false end
    EbonBuildsCharDB[key] = value == true
    return EbonBuildsCharDB[key]
end

function Database.GetCharacterPreferenceDefaults()
    local copy = {}
    for key, value in pairs(CHARACTER_PREFERENCE_DEFAULTS) do copy[key] = value end
    return copy
end

local function SessionCharacter(session)
    return tostring(session and (session.characterKey or session.characterName) or "Unknown")
end

function Database.PruneSessions()
    local sessions = EbonBuildsDB and EbonBuildsDB.sessions
    if type(sessions) ~= "table" or #sessions <= MAX_RAW_ACCOUNT then
        -- Per-character caps can still apply below the account cap.
        if type(sessions) ~= "table" then return 0 end
    end

    local active = nil
    if EbonBuildsDB.currentSessionIndex then active = sessions[EbonBuildsDB.currentSessionIndex] end
    local perCharacter = {}
    local kept = {}
    local removed = 0

    for _, session in ipairs(sessions) do
        local key = SessionCharacter(session)
        local count = perCharacter[key] or 0
        local keep = session == active
            or (#kept < MAX_RAW_ACCOUNT and count < MAX_RAW_PER_CHARACTER)
        if keep then
            kept[#kept + 1] = session
            perCharacter[key] = count + 1
        else
            removed = removed + 1
        end
    end

    if removed > 0 then
        EbonBuildsDB.sessions = kept
        EbonBuildsDB.currentSessionIndex = nil
        if active then
            for index, session in ipairs(kept) do
                if session == active then EbonBuildsDB.currentSessionIndex = index; break end
            end
        end
        if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_HISTORY_PRUNED", removed) end
    end
    return removed
end

function Database.SchedulePrune()
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.After("database.pruneSessions", 0.5, Database.PruneSessions,
            EbonBuilds.Scheduler.MAINTENANCE, false)
    elseif not (InCombatLockdown and InCombatLockdown()) then
        Database.PruneSessions()
    end
end

function Database.PruneRemoteBuilds()
    local remote = EbonBuildsDB and EbonBuildsDB.remoteBuilds
    if type(remote) ~= "table" then return 0 end
    local list = {}
    for id, build in pairs(remote) do list[#list + 1] = { id = id, build = build } end
    if #list <= MAX_REMOTE_BUILDS then return 0 end
    table.sort(list, function(a, b)
        local at = a.build._lastSeenAt or a.build.lastModified or ""
        local bt = b.build._lastSeenAt or b.build.lastModified or ""
        return tostring(at) > tostring(bt)
    end)
    for index = MAX_REMOTE_BUILDS + 1, #list do remote[list[index].id] = nil end
    return #list - MAX_REMOTE_BUILDS
end

function Database.GetLimits()
    return {
        rawPerCharacter = MAX_RAW_PER_CHARACTER,
        rawAccount = MAX_RAW_ACCOUNT,
        remoteBuilds = MAX_REMOTE_BUILDS,
    }
end
