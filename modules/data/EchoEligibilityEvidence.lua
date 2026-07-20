-- EbonBuilds: modules/data/EchoEligibilityEvidence.lua
-- Local, exact-spell positive gameplay evidence. It never narrows eligibility
-- and never becomes community/server truth. Persisted records are only class
-- mask contradictions, scoped to realm and catalog fingerprint.

EbonBuilds.EchoEligibilityEvidence = {}

local Evidence = EbonBuilds.EchoEligibilityEvidence
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

Evidence.FLAG_OFFERED = 1
Evidence.FLAG_REPLACEMENT = 2
Evidence.FLAG_DISCOVERED = 4
Evidence.FLAG_GRANTED = 8

local revision = 0
local initialized = false
local pendingByClass = {}
local sessionByClass = {}
local pendingSelection = { spellId = nil, classToken = nil, capturedAt = 0, fingerprint = nil }
local diagnostics = {
    rejectedBoards = 0,
    invalidSpells = 0,
    persistedExceptions = 0,
    discoveryLive = false,
}
local lifecycleFrame = CreateFrame("Frame")
local cachedScopeRealm, cachedScopeFingerprint, cachedScopeKey, cachedScope

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function EnsureClassTables()
    for _, classToken in ipairs(CLASS_ORDER) do
        pendingByClass[classToken] = pendingByClass[classToken] or {}
        sessionByClass[classToken] = sessionByClass[classToken] or {}
    end
end

local function PlayerClassToken()
    if EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetPlayerClassToken then
        return EbonBuilds.ProjectAPI.GetPlayerClassToken()
    end
    local _, token = UnitClass("player")
    return token and string.upper(token) or nil
end

local function CurrentScopeParts()
    local realm = tostring((GetRealmName and GetRealmName()) or "Unknown")
    local fingerprint = tostring((EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint()) or "unverified")
    return realm, fingerprint
end

local function ScopeKey()
    local realm, fingerprint = CurrentScopeParts()
    if cachedScopeKey and cachedScopeRealm == realm and cachedScopeFingerprint == fingerprint then
        return cachedScopeKey
    end
    cachedScopeRealm, cachedScopeFingerprint = realm, fingerprint
    cachedScopeKey = realm .. "\31" .. fingerprint
    cachedScope = nil
    return cachedScopeKey
end

local function InvalidateScopeCache()
    cachedScopeRealm, cachedScopeFingerprint, cachedScopeKey, cachedScope = nil, nil, nil, nil
end

local function Root()
    EbonBuildsDB.echoEligibility = EbonBuildsDB.echoEligibility or { schema = 1, scopes = {} }
    EbonBuildsDB.echoEligibility.schema = 1
    EbonBuildsDB.echoEligibility.scopes = EbonBuildsDB.echoEligibility.scopes or {}
    return EbonBuildsDB.echoEligibility
end

local function ActiveScope(create)
    local root = Root()
    local key = ScopeKey()
    local scope = cachedScope
    if scope == nil then
        scope = root.scopes[key]
        if scope then scope.lastSeenAt = (time and time()) or scope.lastSeenAt or 0 end
        cachedScope = scope or false
    elseif scope == false then
        scope = nil
    end
    if not scope and create then
        scope = { lastSeenAt = (time and time()) or 0, classes = {} }
        root.scopes[key] = scope
        cachedScope = scope
    end
    if scope then
        scope.classes = scope.classes or {}
    end
    return scope, key
end

local function ClassBit(classToken)
    return EbonBuilds.EchoEligibilityResolver and EbonBuilds.EchoEligibilityResolver.ClassBit(classToken)
        or (EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.ClassMask(classToken))
end

local function IsContradiction(spellId, classToken)
    local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
    local classBit = ClassBit(classToken)
    if not variant or not classBit then return false end
    local declared = tonumber(variant.classMask) or 0
    return declared == 0 or bit.band(declared, classBit) == 0
end

local function Bump(classToken, spellId, flags)
    revision = revision + 1
    if EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.Invalidate then
        EbonBuilds.EchoProjection.Invalidate(classToken)
    end
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("ECHO_ELIGIBILITY_CHANGED", revision, classToken, spellId, flags)
    end
end

local function Persist(classToken, spellId, flags)
    if not IsContradiction(spellId, classToken) then return false end
    local scope = ActiveScope(true)
    local classes = scope.classes
    local bucket = classes[classToken]
    if not bucket then bucket = {}; classes[classToken] = bucket end
    local previous = tonumber(bucket[spellId]) or 0
    local combined = bit.bor(previous, flags)
    if combined == previous then return false end
    bucket[spellId] = combined
    scope.lastSeenAt = (time and time()) or scope.lastSeenAt or 0
    diagnostics.persistedExceptions = diagnostics.persistedExceptions + (previous == 0 and 1 or 0)
    return true
end

local function RuntimeVerified()
    return EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.IsRuntimeVerified
        and EbonBuilds.EchoCatalog.IsRuntimeVerified()
end

local function Record(classToken, spellId, flags)
    classToken = tostring(classToken or ""):upper()
    spellId = tonumber(spellId)
    flags = tonumber(flags) or 0
    local session = sessionByClass[classToken]
    local variant = spellId and EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
    if not session or not variant or flags == 0 then
        diagnostics.invalidSpells = diagnostics.invalidSpells + 1
        return false
    end

    local previous = tonumber(session[spellId]) or 0
    local combined = bit.bor(previous, flags)
    if combined == previous then return false end
    session[spellId] = combined

    if not RuntimeVerified() then
        local pending = pendingByClass[classToken]
        pending[spellId] = bit.bor(tonumber(pending[spellId]) or 0, flags)
        return true
    end

    if IsContradiction(spellId, classToken) then
        Persist(classToken, spellId, flags)
        Bump(classToken, spellId, combined)
    end
    return true
end

local function ChoiceMatches(current, candidate, wantedIndex)
    if type(current) ~= "table" or type(candidate) ~= "table" then return false end
    local spellId = tonumber(candidate.spellId or candidate.id)
    local quality = tonumber(candidate.quality)
    if not spellId or quality == nil or quality < 0 or quality > 4 then return false end
    if wantedIndex then
        local item = current[wantedIndex]
        return type(item) == "table" and tonumber(item.spellId or item.id) == spellId
            and tonumber(item.quality) == quality
    end
    for _, item in ipairs(current) do
        if type(item) == "table" and tonumber(item.spellId or item.id) == spellId
            and tonumber(item.quality) == quality then
            return true
        end
    end
    return false
end

function Evidence.ObserveChoiceBoard(choices, sourceFlag)
    if type(choices) ~= "table" then diagnostics.rejectedBoards = diagnostics.rejectedBoards + 1; return false end
    local current = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCurrentChoice
        and EbonBuilds.ProjectAPI.GetCurrentChoice() or nil
    local classToken = PlayerClassToken()
    if type(current) ~= "table" or not sessionByClass[classToken] then
        diagnostics.rejectedBoards = diagnostics.rejectedBoards + 1
        return false
    end
    local accepted = false
    for index = 1, #choices do
        local choice = choices[index]
        if ChoiceMatches(current, choice) then
            accepted = Record(classToken, choice.spellId or choice.id, sourceFlag or Evidence.FLAG_OFFERED) or accepted
        else
            diagnostics.rejectedBoards = diagnostics.rejectedBoards + 1
        end
    end
    return accepted
end

function Evidence.ObserveReplacement(perkIndex, perkData)
    local current = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCurrentChoice
        and EbonBuilds.ProjectAPI.GetCurrentChoice() or nil
    local index = tonumber(perkIndex)
    if index == nil or type(perkData) ~= "table" or not ChoiceMatches(current, perkData, index + 1) then
        diagnostics.rejectedBoards = diagnostics.rejectedBoards + 1
        return false
    end
    return Record(PlayerClassToken(), perkData.spellId or perkData.id, Evidence.FLAG_REPLACEMENT)
end

function Evidence.CaptureSelectionAttempt(spellId)
    spellId = tonumber(spellId)
    local current = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCurrentChoice
        and EbonBuilds.ProjectAPI.GetCurrentChoice() or nil
    if type(current) == "table" then Evidence.ObserveChoiceBoard(current, Evidence.FLAG_OFFERED) end
    local classToken = PlayerClassToken()
    local found = false
    for _, choice in ipairs(current or {}) do
        if tonumber(choice and (choice.spellId or choice.id)) == spellId then found = true; break end
    end
    if not spellId or not classToken or not found then
        diagnostics.rejectedBoards = diagnostics.rejectedBoards + 1
        return false
    end
    pendingSelection.spellId = spellId
    pendingSelection.classToken = classToken
    pendingSelection.capturedAt = GetTime and GetTime() or 0
    pendingSelection.fingerprint = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint() or nil
    return true
end

function Evidence.ConfirmPendingSelection()
    local now = GetTime and GetTime() or 0
    if not pendingSelection.spellId or now - (pendingSelection.capturedAt or 0) > 10 then
        pendingSelection.spellId = nil
        return false
    end
    local fingerprint = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint() or nil
    if fingerprint ~= pendingSelection.fingerprint then pendingSelection.spellId = nil; return false end
    local ok = Record(pendingSelection.classToken, pendingSelection.spellId, Evidence.FLAG_GRANTED)
    pendingSelection.spellId = nil
    return ok
end

function Evidence.GetFlags(classToken, spellId)
    classToken = tostring(classToken or ""):upper()
    spellId = tonumber(spellId)
    if not spellId then return 0 end
    local flags = tonumber(sessionByClass[classToken] and sessionByClass[classToken][spellId]) or 0
    local scope = ActiveScope(false)
    local persisted = scope and scope.classes and scope.classes[classToken]
    if persisted then flags = bit.bor(flags, tonumber(persisted[spellId]) or 0) end
    return flags
end

function Evidence.ReconcilePending()
    if not RuntimeVerified() then return false end
    local changed = false
    for _, classToken in ipairs(CLASS_ORDER) do
        local pending = pendingByClass[classToken]
        for spellId, flags in pairs(pending) do
            if IsContradiction(spellId, classToken) then
                Persist(classToken, spellId, flags)
                Bump(classToken, spellId, flags)
                changed = true
            end
            pending[spellId] = nil
        end
    end
    return changed
end

local function ScanDiscoveredTable(discovered, classToken)
    local changed = false
    for key, value in pairs(discovered or {}) do
        local spellId = tonumber(key)
        if not spellId and type(value) == "number" then spellId = tonumber(value) end
        if not spellId and type(value) == "table" then spellId = tonumber(value.spellId or value.id) end
        if spellId then changed = Record(classToken, spellId, Evidence.FLAG_DISCOVERED) or changed end
    end
    return changed
end

function Evidence.ScanDiscovery()
    local discovered, live
    if EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetDiscoveryState then
        discovered, live = EbonBuilds.ProjectAPI.GetDiscoveryState()
    end
    diagnostics.discoveryLive = live == true
    if live ~= true or type(discovered) ~= "table" then return false end
    return ScanDiscoveredTable(discovered, PlayerClassToken())
end

function Evidence.ScheduleDiscoveryScan()
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.After("echoEligibility.discovery", 0, Evidence.ScanDiscovery,
            EbonBuilds.Scheduler.BACKGROUND, true)
    end
end

function Evidence.Prune()
    local root = Root()
    local list = {}
    for key, scope in pairs(root.scopes or {}) do
        list[#list + 1] = { key = key, at = tonumber(scope.lastSeenAt) or 0 }
    end
    if #list <= 8 then return 0 end
    table.sort(list, function(a, b) return a.at > b.at end)
    for index = 9, #list do root.scopes[list[index].key] = nil end
    return #list - 8
end

local function InstallHooks()
    local service = ProjectEbonhold and ProjectEbonhold.PerkService
    if service and type(service.SelectPerk) == "function" and not service._ebonBuildsEligibilityHooked then
        hooksecurefunc(service, "SelectPerk", function(spellId) Evidence.CaptureSelectionAttempt(spellId) end)
        service._ebonBuildsEligibilityHooked = true
    end
    local journal = ProjectEbonhold and ProjectEbonhold.EchoJournal
    if journal and type(journal.NotifyNewEcho) == "function" and not journal._ebonBuildsGrantHooked then
        hooksecurefunc(journal, "NotifyNewEcho", Evidence.ConfirmPendingSelection)
        journal._ebonBuildsGrantHooked = true
    end
    if journal and type(journal.OnDataChanged) == "function" and not journal._ebonBuildsDiscoveryHooked then
        hooksecurefunc(journal, "OnDataChanged", Evidence.ScheduleDiscoveryScan)
        journal._ebonBuildsDiscoveryHooked = true
    end
end

function Evidence.Init()
    if initialized then return end
    initialized = true
    EnsureClassTables()
    Root()
    InstallHooks()
    lifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    lifecycleFrame:SetScript("OnEvent", function()
        InstallHooks()
        Evidence.ScheduleDiscoveryScan()
        if EbonBuilds.Scheduler then
            EbonBuilds.Scheduler.After("echoEligibility.prune", 1, Evidence.Prune,
                EbonBuilds.Scheduler.MAINTENANCE, false)
        end
    end)
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.On("ECHO_CATALOG_CHANGED", function()
            InvalidateScopeCache()
            Evidence.ReconcilePending()
            Evidence.ScheduleDiscoveryScan()
        end)
    end
end

function Evidence.GetRevision() return revision end
function Evidence.GetDiagnostics() return diagnostics end
function Evidence.GetScopeKey() return ScopeKey() end
