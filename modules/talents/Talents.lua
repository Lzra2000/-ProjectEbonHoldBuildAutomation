local addonName, EbonBuilds = ...

-- EbonBuilds: modules/talents/Talents.lua
-- Reads a WoW 3.3.5a talent allocation (the standard 51-point class talent
-- trees, NOT Echoes) either from the player's own character or from an
-- inspected target, and stores it as a compact, class-scoped preset that
-- travels along with a build through the existing export/sync/chat-link
-- pipeline (it's just another field on the build object -- no changes
-- needed to Sync.lua or ChatLink.lua).
--
-- Storage format on a build:
--   build.talents = {
--     class = "MAGE",                 -- talent layouts are class-specific;
--                                      -- guards against pasting a DK spec
--                                      -- onto a Mage build
--     tabs = {
--       [1] = { name = "Arcane", points = 31, ranks = { [3]=5, [7]=1, ... } },
--       [2] = { name = "Fire",   points = 5,  ranks = { [1]=5 } },
--       [3] = { name = "Frost",  points = 5,  ranks = { [2]=5 } },
--     },
--   }
-- `ranks` is keyed by talent index within that tab (stable for a given
-- class -- the same index always means the same talent for everyone of
-- that class, so no name/id translation is needed between players).

EbonBuilds.Talents = {}

local function ScanTabs(isInspect)
    local numTabs = GetNumTalentTabs and GetNumTalentTabs(isInspect) or 0
    local tabs = {}
    for tabIndex = 1, numTabs do
        local name, _, pointsSpent = GetTalentTabInfo(tabIndex, isInspect)
        local ranks = {}
        local numTalents = GetNumTalents and GetNumTalents(tabIndex, isInspect) or 0
        for talentIndex = 1, numTalents do
            local _, _, _, _, rank = GetTalentInfo(tabIndex, talentIndex, isInspect)
            if rank and rank > 0 then
                ranks[talentIndex] = rank
            end
        end
        tabs[tabIndex] = { name = name or ("Tab " .. tabIndex), points = pointsSpent or 0, ranks = ranks }
    end
    return tabs
end

-- Reads the player's own current talent allocation.
function EbonBuilds.Talents.ScanSelf()
    return {
        class = EbonBuilds.Build.PlayerClassToken(),
        tabs  = ScanTabs(false),
    }
end

------------------------------------------------------------------------
-- Inspecting a target (async: the server has to send the data first)
------------------------------------------------------------------------

local INSPECT_TIMEOUT = 5
local pending = nil -- { unit, class, callback, elapsed } or nil
local watcherToken

local function FinishPending(talents, err)
    local cb = pending and pending.callback
    pending = nil
    EbonBuilds.Scheduler.Cancel("talents.inspectTimeout")
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    if cb then cb(talents, err) end
end

local function EnsureWatcher()
    if watcherToken then return end
    watcherToken = EbonBuilds.WoWEvents.On("INSPECT_TALENT_READY", function()
        if not pending then return end
        local talents = { class = pending.class, tabs = ScanTabs(true) }
        FinishPending(talents, nil)
    end, "Talents")
end

-- Requests the given unit's talents and calls callback(talents, err) once
-- the data arrives (or after a timeout). Only one inspect request can be
-- in flight at a time; a new call cancels any previous one.
function EbonBuilds.Talents.ScanUnit(unit, callback)
    if not unit or not UnitExists(unit) then
        callback(nil, "no target")
        return
    end
    if not UnitIsPlayer(unit) then
        callback(nil, "not a player")
        return
    end
    if UnitIsUnit(unit, "player") then
        callback(EbonBuilds.Talents.ScanSelf(), nil)
        return
    end
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then
        callback(nil, "too far away")
        return
    end

    EnsureWatcher()
    local _, classToken = UnitClass(unit)
    pending = { unit = unit, class = classToken, callback = callback, elapsed = 0 }
    EbonBuilds.Scheduler.After("talents.inspectTimeout", INSPECT_TIMEOUT, function()
        if pending then FinishPending(nil, "timeout") end
    end, EbonBuilds.Scheduler.BACKGROUND, true)
    NotifyInspect(unit)
end

------------------------------------------------------------------------
-- Display helpers
------------------------------------------------------------------------
