local addonName, EbonBuilds = ...

-- EbonBuilds: core/Database.lua
-- Sole SavedVariables owner. Adoption is synchronous and shallow; migration,
-- indexing, and pruning run through the shared scheduler in resumable batches.

EbonBuilds.Database = {}
EbonBuilds.Runtime = EbonBuilds.Runtime or {}

local Database = EbonBuilds.Database
local ACCOUNT_SCHEMA = 3
local CHARACTER_SCHEMA = 2
local MAX_RAW_PER_CHARACTER = 30
local MAX_RAW_ACCOUNT = 120
local MAX_REMOTE_BUILDS = 500
local MAX_REMOTE_ESTIMATED_BYTES = 2 * 1024 * 1024
local MIGRATION_BATCH = 8
local SESSION_COMPACTION_SCHEMA = 1

local CHARACTER_PREFERENCE_DEFAULTS = {
    autoSellJunkEnabled = false,
    bagAffixDotsEnabled = true,
    debugLogEnabled = false,
    clickTraceEnabled = false,
    gearTooltipEnabled = true,
    mapZonePanelEnabled = true,
    syncVerboseLogEnabled = false,
}

local adopted = false
local migrationRunning = false
local ready = false

local function CharacterKey()
    local name = UnitName and UnitName("player") or "Unknown"
    if tostring(name):find("-", 1, true) then return tostring(name) end
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then return tostring(name) .. "-" .. tostring(realm) end
    return tostring(name)
end

Database.CharacterKey = CharacterKey

local function EnsureRootDefaults()
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.evalDelay = EbonBuildsDB.globalSettings.evalDelay or 2
    EbonBuildsDB.globalSettings.toastDuration = EbonBuildsDB.globalSettings.toastDuration or 3
    EbonBuildsDB.globalSettings.uiScale = EbonBuildsDB.globalSettings.uiScale or 1
    if EbonBuildsDB.globalSettings.syncChatMessages == nil then
        EbonBuildsDB.globalSettings.syncChatMessages = true
    end
    if EbonBuildsDB.globalSettings.tomeAtlasMapEnabled == nil then
        EbonBuildsDB.globalSettings.tomeAtlasMapEnabled = true
    end
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220
    EbonBuildsDB.builds = EbonBuildsDB.builds or {}
    EbonBuildsDB.remoteBuilds = EbonBuildsDB.remoteBuilds or {}
    EbonBuildsDB.sessions = EbonBuildsDB.sessions or {}
    EbonBuildsDB.buildAggregates = EbonBuildsDB.buildAggregates or {}
    EbonBuildsDB.echoEligibility = EbonBuildsDB.echoEligibility or { schema = 1, scopes = {} }
    EbonBuildsDB.echoEligibility.schema = tonumber(EbonBuildsDB.echoEligibility.schema) or 1
    EbonBuildsDB.echoEligibility.scopes = EbonBuildsDB.echoEligibility.scopes or {}
    EbonBuildsDB.ui = EbonBuildsDB.ui or { layoutPreset = "standard", scalePreset = 1 }

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

    -- Obsolete diagnostic/cache fields have no readers in the current addon.
    -- They are not user-authored data and should not be loaded and serialized
    -- forever after the feature that created them has gone away.
    EbonBuildsDB.syncPeers = nil
    EbonBuildsCharDB.performanceLab = nil
    EbonBuildsCharDB.performanceLegacy = nil
    EbonBuildsCharDB.performanceV2 = nil
    EbonBuildsCharDB.valuationTelemetry = nil

    -- Draft/editor state is runtime-only. Never retain a half-committed edit.
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB._wizardPrefill = nil
    EbonBuilds.Runtime.pendingWeights = nil
    EbonBuilds.Runtime.isEditingBuild = nil
    EbonBuilds.Runtime.wizardPrefill = nil
end

function Database.Adopt()
    if adopted then return true end
    EbonBuildsDB = type(EbonBuildsDB) == "table" and EbonBuildsDB or {}
    EbonBuildsCharDB = type(EbonBuildsCharDB) == "table" and EbonBuildsCharDB or {}

    local accountSource = tonumber(EbonBuildsDB.schemaVersion) or 0
    local characterSource = tonumber(EbonBuildsCharDB.schemaVersion) or 0
    local migration = type(EbonBuildsDB.migration) == "table" and EbonBuildsDB.migration or {}
    EbonBuildsDB.migration = migration
    migration.sourceAccountSchema = tonumber(migration.sourceAccountSchema) or accountSource
    migration.sourceCharacterSchema = tonumber(migration.sourceCharacterSchema) or characterSource
    migration.targetAccountSchema = ACCOUNT_SCHEMA
    migration.targetCharacterSchema = CHARACTER_SCHEMA
    migration.stage = migration.stage or "adopted"
    migration.cursor = tonumber(migration.cursor) or 0
    migration.failures = tonumber(migration.failures) or 0
    migration.generation = tonumber(migration.generation) or 1

    EnsureRootDefaults()
    adopted = true
    return true
end

local function SessionCharacter(session)
    return tostring(session and (session.characterKey or session.characterName) or "Unknown")
end

local function LegacyRunId(session, index)
    local stamp = session and (session.startedAt or session.startTime or session.endedAt or session.endTime) or 0
    local buildId = session and (session.buildId or session.buildUUID) or "none"
    return "legacy:" .. SessionCharacter(session) .. ":" .. tostring(stamp) .. ":" .. tostring(buildId) .. ":" .. tostring(index)
end

local function CompactSession(session)
    local changed = 0
    for _, entry in ipairs(type(session.logs) == "table" and session.logs or {}) do
        local choiceCount, recordedEligibilityCount = 0, 0
        local choices = type(entry.choices) == "table" and entry.choices or {}
        for _, choice in ipairs(choices) do
            choiceCount = choiceCount + 1
            if choice.eligibilityRecorded == true then recordedEligibilityCount = recordedEligibilityCount + 1 end
        end
        local promoteEligibility = choiceCount > 0 and recordedEligibilityCount == choiceCount
        for _, choice in ipairs(choices) do
            if promoteEligibility and choice.eligibilityRecorded ~= nil then
                choice.eligibilityRecorded = nil
                changed = changed + 1
            end
            if choice.refKey ~= nil then choice.refKey = nil; changed = changed + 1 end
            if choice.families ~= nil then choice.families = nil; changed = changed + 1 end
            if choice.modifierDelta ~= nil then choice.modifierDelta = nil; changed = changed + 1 end
            if choice.policySelected ~= nil then choice.policySelected = nil; changed = changed + 1 end
            if choice.isProtected ~= nil then choice.isProtected = nil; changed = changed + 1 end
            if choice.policy == "normal" then choice.policy = nil; changed = changed + 1 end
            if choice.policyEffect == "normal" then choice.policyEffect = nil; changed = changed + 1 end
            if choice.isBanned == false then choice.isBanned = nil; changed = changed + 1 end
            if choice.isAvoided == false
                or (choice.isAvoided and (choice.isBanned or choice.policyBlocked
                    or choice.policyEffect == "banish" or choice.policyEffect == "exclude")) then
                choice.isAvoided = nil
                changed = changed + 1
            end
            if choice.policyBlocked == false
                or (choice.policyBlocked and (choice.policyEffect == "banish" or choice.policyEffect == "exclude")) then
                choice.policyBlocked = nil
                changed = changed + 1
            end
        end
        if promoteEligibility and entry.eligibilitySchema ~= 1 then
            entry.eligibilitySchema = 1
            changed = changed + 1
        end
        local flags = entry.decision and entry.decision.flags
        if entry.decision and tostring(entry.decision.source or ""):lower() == "automatic" then
            entry.decision.source = nil
            changed = changed + 1
        end
        if type(flags) == "table" then
            for key, value in pairs(flags) do
                if value == false then flags[key] = nil; changed = changed + 1 end
            end
            if next(flags) == nil then entry.decision.flags = nil; changed = changed + 1 end
        end
    end
    return changed
end

Database._CompactSessionForTests = CompactSession

local function MigrationCoroutine()
    migrationRunning = true
    local migration = EbonBuildsDB.migration
    migration.stage = "sessions"
    local sessions = EbonBuildsDB.sessions
    local cursor = math.max(0, tonumber(migration.cursor) or 0)

    while cursor < #sessions do
        local stop = math.min(#sessions, cursor + MIGRATION_BATCH)
        for index = cursor + 1, stop do
            local session = sessions[index]
            if type(session) == "table" then
                session.runId = session.runId or LegacyRunId(session, index)
                session.characterKey = session.characterKey or SessionCharacter(session)
                CompactSession(session)
            end
        end
        cursor = stop
        migration.cursor = cursor
        if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("DATABASE_MIGRATION_CHANGED", migration.stage, cursor, #sessions) end
        coroutine.yield(0)
    end

    migration.stage = "prune"
    migration.cursor = 0
    Database.PruneSessions()
    Database.PruneRemoteBuilds()
    coroutine.yield(0)

    EbonBuildsDB.schemaVersion = ACCOUNT_SCHEMA
    EbonBuildsCharDB.schemaVersion = CHARACTER_SCHEMA
    migration.sessionCompactionSchema = SESSION_COMPACTION_SCHEMA
    migration.stage = "complete"
    migration.cursor = 0
    migration.completedAt = time and time() or 0
    migrationRunning = false
    ready = true
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("DATABASE_MIGRATION_CHANGED", "complete", 1, 1)
        EbonBuilds.EventHub.Bump("DATABASE_READY", ACCOUNT_SCHEMA, CHARACTER_SCHEMA)
    end
end

function Database.Init()
    Database.Adopt()
    local migration = EbonBuildsDB.migration
    local needsMigration = tonumber(EbonBuildsDB.schemaVersion) ~= ACCOUNT_SCHEMA
        or tonumber(EbonBuildsCharDB.schemaVersion) ~= CHARACTER_SCHEMA
        or tonumber(migration.sessionCompactionSchema) ~= SESSION_COMPACTION_SCHEMA
        or migration.stage ~= "complete"

    if needsMigration and EbonBuilds.Scheduler and not migrationRunning then
        EbonBuilds.Scheduler.Coroutine(
            "database.migration",
            MigrationCoroutine,
            EbonBuilds.Scheduler.BACKGROUND,
            false,
            "Database"
        )
    elseif not needsMigration then
        migration.stage = "complete"
        ready = true
        if EbonBuilds.EventHub then
            EbonBuilds.EventHub.Bump("DATABASE_READY", ACCOUNT_SCHEMA, CHARACTER_SCHEMA)
        end
    end
    return true
end

function Database.IsMigrationRunning()
    return migrationRunning
end

function Database.IsReady()
    return ready == true
end

function Database.GetMigrationState()
    local migration = EbonBuildsDB and EbonBuildsDB.migration
    if not migration then return "unavailable", 0 end
    return migration.stage, migration.cursor or 0
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

function Database.PruneSessions()
    local sessions = EbonBuildsDB and EbonBuildsDB.sessions
    if type(sessions) ~= "table" then return 0 end

    local active
    if EbonBuildsDB.currentSessionIndex then active = sessions[EbonBuildsDB.currentSessionIndex] end
    local perCharacter = {}
    local kept = {}
    local removed = 0

    for index = 1, #sessions do
        local session = sessions[index]
        local key = SessionCharacter(session)
        local count = perCharacter[key] or 0
        local keep = session == active or (#kept < MAX_RAW_ACCOUNT and count < MAX_RAW_PER_CHARACTER)
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
            for index = 1, #kept do
                if kept[index] == active then EbonBuildsDB.currentSessionIndex = index; break end
            end
        end
        if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("RUN_HISTORY_PRUNED", removed) end
    end
    return removed
end

function Database.SchedulePrune()
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.After("database.pruneSessions", 0.5, Database.PruneSessions,
            EbonBuilds.Scheduler.MAINTENANCE, false, "Database")
    elseif not (InCombatLockdown and InCombatLockdown()) then
        Database.PruneSessions()
    end
end

local function EstimateValue(value, depth, seen)
    local valueType = type(value)
    if valueType == "nil" then return 1 end
    if valueType == "boolean" then return 1 end
    if valueType == "number" then return 8 end
    if valueType == "string" then return #value + 8 end
    if valueType ~= "table" or depth <= 0 or seen[value] then return 16 end
    seen[value] = true
    local bytes = 24
    for key, child in pairs(value) do
        bytes = bytes + EstimateValue(key, depth - 1, seen) + EstimateValue(child, depth - 1, seen)
    end
    seen[value] = nil
    return bytes
end

function Database.PruneRemoteBuilds()
    local remote = EbonBuildsDB and EbonBuildsDB.remoteBuilds
    if type(remote) ~= "table" then return 0 end

    -- The public browser and relay path already collapse builds by normalized
    -- title. Persisting every hidden copy only duplicates complete weight and
    -- settings maps, so keep the same earliest-known winner and discard remote
    -- copies that can never be displayed or relayed.
    local titleWinners = {}
    local function Consider(build)
        if type(build) ~= "table" then return end
        local key = tostring(build.title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if key == "" then return end
        local current = titleWinners[key]
        local candidateDate = tostring(build.lastModified or "")
        local currentDate = current and tostring(current.lastModified or "") or nil
        -- Match Build.ListPublic exactly: on equal dates, retain the first
        -- record encountered (local public builds are considered first).
        if not current or candidateDate < currentDate then
            titleWinners[key] = build
        end
    end
    for _, build in pairs(EbonBuildsDB.builds or {}) do
        if type(build) == "table" and build.isPublic then Consider(build) end
    end
    for _, build in pairs(remote) do Consider(build) end

    local removed = 0
    for id, build in pairs(remote) do
        local key = type(build) == "table"
            and tostring(build.title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        local winner = key ~= "" and titleWinners[key] or nil
        if winner and winner ~= build then
            remote[id] = nil
            removed = removed + 1
        end
    end

    local list = {}
    local estimatedBytes = 0
    local seen = {}
    for id, build in pairs(remote) do
        local bytes = EstimateValue(build, 6, seen)
        estimatedBytes = estimatedBytes + bytes
        list[#list + 1] = { id = id, build = build, bytes = bytes }
    end
    if #list <= MAX_REMOTE_BUILDS and estimatedBytes <= MAX_REMOTE_ESTIMATED_BYTES then return removed end

    table.sort(list, function(a, b)
        local at = a.build._lastSeenAt or a.build.lastModified or ""
        local bt = b.build._lastSeenAt or b.build.lastModified or ""
        return tostring(at) > tostring(bt)
    end)

    local keptBytes, keptCount = 0, 0
    for index = 1, #list do
        local entry = list[index]
        if keptCount < MAX_REMOTE_BUILDS and keptBytes + entry.bytes <= MAX_REMOTE_ESTIMATED_BYTES then
            keptCount = keptCount + 1
            keptBytes = keptBytes + entry.bytes
        else
            remote[entry.id] = nil
            removed = removed + 1
        end
    end
    return removed
end

function Database.GetLimits()
    return {
        rawPerCharacter = MAX_RAW_PER_CHARACTER,
        rawAccount = MAX_RAW_ACCOUNT,
        remoteBuilds = MAX_REMOTE_BUILDS,
        remoteEstimatedBytes = MAX_REMOTE_ESTIMATED_BYTES,
    }
end
