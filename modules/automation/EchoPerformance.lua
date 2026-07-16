-- EbonBuilds: modules/automation/EchoPerformance.lua
-- Responsibility: correlate currently-active echoes with real combat
-- performance (DPS), using Details! damage meter's public API, if
-- installed. Off by default -- this is explicitly a rough, approximate
-- signal (echoes stack, execution/gear/fight-type vary run to run), not
-- a controlled measurement. Meant as a SUPPLEMENT to the theoretical
-- scoring model and Tuning Advisor's offer-distribution data, surfaced
-- through Export (AI) so an external AI has real performance context
-- too, not a replacement for either.
--
-- Everything that touches Details! is pcall-wrapped and feature-detected
-- -- it's a separate, large, independently-updated addon EbonBuilds does
-- not control, and its exact internals can change between versions. Only
-- the documented public API (Details:GetCurrentCombat, combat:GetActor,
-- actor.total, combat:GetCombatTime -- see Details' own API.lua) is used.

EbonBuilds.EchoPerformance = {}

local SAMPLE_INTERVAL = 10  -- seconds between DPS samples while in combat
local MAX_SAMPLES_PER_ECHO = 200

local function GetStore()
    EbonBuildsCharDB.echoPerformance = EbonBuildsCharDB.echoPerformance or {}
    return EbonBuildsCharDB.echoPerformance
end

function EbonBuilds.EchoPerformance.IsEnabled()
    return EbonBuildsCharDB.echoPerformanceEnabled == true
end

function EbonBuilds.EchoPerformance.SetEnabled(on)
    EbonBuildsCharDB.echoPerformanceEnabled = on and true or false
end

function EbonBuilds.EchoPerformance.IsDetailsAvailable()
    return Details ~= nil and Details.GetCurrentCombat ~= nil
end

function EbonBuilds.EchoPerformance.Clear()
    EbonBuildsCharDB.echoPerformance = {}
end

-- Current player DPS this combat, or nil if unavailable (not in combat,
-- Details not installed, or its API returned something unexpected --
-- any of which are just "no sample this tick", never an error).
local function GetCurrentDPS()
    if not EbonBuilds.EchoPerformance.IsDetailsAvailable() then return nil end
    local ok, dps = pcall(function()
        local combat = Details:GetCurrentCombat()
        if not combat then return nil end
        local playerName = UnitName("player")
        local actor = combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE, playerName)
        if not actor or not actor.total then return nil end
        local combatTime = combat:GetCombatTime()
        if not combatTime or combatTime <= 0 then return nil end
        return actor.total / combatTime
    end)
    if ok and type(dps) == "number" and dps >= 0 then return dps end
    return nil
end

-- Records one DPS sample against every currently-granted (active this
-- run) echo. Called by the sample ticker; safe to call even if disabled
-- or Details isn't installed (both are no-ops).
function EbonBuilds.EchoPerformance.Sample()
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    if not (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks) then return end
    local dps = GetCurrentDPS()
    if not dps then return end

    local granted = ProjectEbonhold.PerkService.GetGrantedPerks() or {}
    local store = GetStore()
    for name in pairs(granted) do
        local entry = store[name]
        if not entry then
            entry = { sum = 0, count = 0 }
            store[name] = entry
        end
        entry.sum = entry.sum + dps
        entry.count = entry.count + 1
        -- Cap by halving instead of dropping oldest one-by-one -- cheap,
        -- and keeps the running average meaningful rather than
        -- discarding history outright.
        if entry.count > MAX_SAMPLES_PER_ECHO then
            entry.sum = entry.sum / 2
            entry.count = math.floor(entry.count / 2)
        end
    end
end

-- Returns { avgDPS, sampleCount } for a given echo name, or nil if no
-- data has been collected for it.
function EbonBuilds.EchoPerformance.GetStats(name)
    local store = GetStore()
    local entry = store[name]
    if not entry or entry.count == 0 then return nil end
    return { avgDPS = entry.sum / entry.count, sampleCount = entry.count }
end

------------------------------------------------------------------------
-- Sample ticker: only does anything while actually in combat, and only
-- if the player opted in.
------------------------------------------------------------------------

local tickerFrame
local elapsed = 0

local function OnTick(self, dt)
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    if not UnitAffectingCombat("player") then return end
    elapsed = elapsed + dt
    if elapsed < SAMPLE_INTERVAL then return end
    elapsed = 0
    EbonBuilds.EchoPerformance.Sample()
end

function EbonBuilds.EchoPerformance.Init()
    if tickerFrame then return end
    tickerFrame = CreateFrame("Frame")
    tickerFrame:SetScript("OnUpdate", OnTick)
end
