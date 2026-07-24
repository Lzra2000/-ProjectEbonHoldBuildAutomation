local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/SharedLoadoutBridge.lua
-- Lean bridge: ProjectEbonhold Echo Journal community loadouts
-- (PerkService.GetSharedEchoLoadouts) to ephemeral pseudo-builds for Public
-- Builds browsing and CommunityEligibility evidence.
--
-- Intentionally NOT written into EbonBuildsDB.builds / remoteBuilds and never
-- returned from Build.ListPublic(), so peer WNT/BLD sync cannot rebroadcast
-- PE server loadouts as if they were EbonBuilds public builds.
-- Target: WoW 3.3.5a / build 12340.

EbonBuilds.SharedLoadoutBridge = {}
local Bridge = EbonBuilds.SharedLoadoutBridge

local ID_PREFIX = "pe-shared:"
local cache = {} -- id -> pseudo-build
local cacheRevision = 0
local hookedJournal = nil
local initialized = false

local function ClearTable(t)
    for key in pairs(t) do t[key] = nil end
end

local function Caps()
    local api = EbonBuilds.ProjectAPI
    if not api or type(api.GetCapabilities) ~= "function" then return nil end
    local ok, caps = pcall(api.GetCapabilities)
    return ok and type(caps) == "table" and caps or nil
end

local function SharedAvailable()
    local caps = Caps()
    return caps and caps.sharedLoadouts == true
end

-- Stable id derived from author/class/name so Import / FindImportedCopy can
-- key off it without colliding with UUID builds.
function Bridge.MakeId(loadout)
    if type(loadout) ~= "table" then return nil end
    local author = tostring(loadout.author or "unknown"):gsub("[%c|]", "")
    local class = tostring(loadout.class or "UNKNOWN"):upper():gsub("[^A-Z]", "")
    local name = tostring(loadout.name or ""):gsub("[%c|]", "")
    if name == "" then return nil end
    if class == "" then class = "UNKNOWN" end
    return ID_PREFIX .. author .. ":" .. class .. ":" .. name
end

function Bridge.IsPseudoId(id)
    return type(id) == "string" and id:sub(1, #ID_PREFIX) == ID_PREFIX
end

--- Map one PE shared loadout ({name, author, class, echoes}) to a lean
-- public-shaped pseudo-build. lockedEchoes holds every echo spellId in
-- loadout order (Public Builds icons still only render LOCKED_SLOTS).
function Bridge.MapLoadoutToBuild(loadout)
    if type(loadout) ~= "table" then return nil end
    local id = Bridge.MakeId(loadout)
    if not id then return nil end

    local locked = {}
    for _, entry in ipairs(loadout.echoes or {}) do
        local spellId = type(entry) == "table" and tonumber(entry.spellId) or tonumber(entry)
        if spellId and spellId > 0 then
            locked[#locked + 1] = spellId
        end
    end
    if #locked == 0 then return nil end

    local class = tostring(loadout.class or ""):upper():gsub("[^A-Z]", "")
    if class == "" then class = "UNKNOWN" end

    return {
        id = id,
        title = tostring(loadout.name or "Loadout"),
        author = tostring(loadout.author or "unknown"),
        class = class,
        -- PE community loadouts carry no talent-spec; Public Builds shows
        -- them under All Specs / any Spec filter, and CommunityEligibility
        -- only picks them up on class-wide widen (or anySpec).
        spec = nil,
        comments = "Echo Journal community loadout",
        lockedEchoes = locked,
        echoWeights = {},
        echoWeightsByRef = {},
        settings = nil,
        isPublic = true,
        peSharedLoadout = true,
        validated = false,
        lastModified = "",
        _lastSeenAt = tostring(cacheRevision),
    }
end

local function RebuildCache()
    ClearTable(cache)
    cacheRevision = cacheRevision + 1
    local api = EbonBuilds.ProjectAPI
    if not api or type(api.GetSharedEchoLoadouts) ~= "function" then return 0 end
    local list = api.GetSharedEchoLoadouts()
    if type(list) ~= "table" then return 0 end

    local count = 0
    for i = 1, #list do
        local build = Bridge.MapLoadoutToBuild(list[i])
        if build then
            cache[build.id] = build
            count = count + 1
        end
    end
    return count
end

function Bridge.GetRevision()
    return cacheRevision
end

--- Ephemeral pseudo-builds only. Never persist; never feed Sync.ListPublic.
function Bridge.ListPseudoBuilds(classToken)
    local want = classToken and tostring(classToken):upper() or nil
    if want == "" then want = nil end
    local out = {}
    for _, build in pairs(cache) do
        if type(build) == "table" and (not want or build.class == want) then
            out[#out + 1] = build
        end
    end
    table.sort(out, function(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            if type(a) ~= "table" and type(b) ~= "table" then return false end
            return type(b) ~= "table"
        end
        local ca, cb = a.class or "", b.class or ""
        if ca ~= cb then return ca < cb end
        return (a.title or "") < (b.title or "")
    end)
    return out
end

function Bridge.Request(classToken)
    if not SharedAvailable() then return false end
    local api = EbonBuilds.ProjectAPI
    return api.RequestSharedEchoLoadouts(classToken or "") == true
end

function Bridge.RefreshFromService()
    if not SharedAvailable() then
        ClearTable(cache)
        cacheRevision = cacheRevision + 1
        return 0
    end
    return RebuildCache()
end

local function NotifyConsumers()
    if EbonBuilds.PublicBuildsView and EbonBuilds.PublicBuildsView.RefreshIfMounted then
        EbonBuilds.PublicBuildsView.RefreshIfMounted()
    end
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("PE_SHARED_LOADOUTS_CHANGED", cacheRevision)
    end
end

local function OnJournalDataChanged()
    Bridge.RefreshFromService()
    NotifyConsumers()
end

local function InstallHooks()
    local journal = ProjectEbonhold and ProjectEbonhold.EchoJournal
    if journal and type(journal.OnDataChanged) == "function" and hookedJournal ~= journal then
        hooksecurefunc(journal, "OnDataChanged", OnJournalDataChanged)
        hookedJournal = journal
    end
end

function Bridge.Init()
    if initialized then return true end
    initialized = true
    InstallHooks()
    Bridge.RefreshFromService()
    if EbonBuilds.WoWEvents then
        EbonBuilds.WoWEvents.On("PLAYER_ENTERING_WORLD", function()
            InstallHooks()
            Bridge.Request("")
            Bridge.RefreshFromService()
            NotifyConsumers()
        end, "SharedLoadoutBridge")
    end
    return true
end
