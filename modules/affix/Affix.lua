local addonName, EbonBuilds = ...

-- EbonBuilds: modules/affix/Affix.lua
-- Client-side half of the learned-affix system: requests the server feed
-- (core/AffixServer.lua speaks the wire format), reassembles chunked
-- replies, caches the result per character, and exposes a small query API
-- for the Affix view and (later) build integration.

EbonBuilds.Affix = {}

local S = EbonBuilds.AffixServer

local inflight = {}          -- [msgId] = { total, got, parts, t0 }
local lastRequestAt = 0
local registered = false

------------------------------------------------------------------------
-- Cache (per character: affixes are a character-bound unlock, same as
-- Echoes' progression, not account-wide like the Tome Atlas).
------------------------------------------------------------------------

local function DB()
    EbonBuildsCharDB.affixes = EbonBuildsCharDB.affixes or { list = {}, lastReceivedAt = 0 }
    return EbonBuildsCharDB.affixes
end

-- Returns the cached affix list: array of
-- { id, name, icon, applyCost, appliedCount, difficulty, weaponOnly, learned }
function EbonBuilds.Affix.GetLearned()
    return DB().list
end

function EbonBuilds.Affix.HasData()
    return #DB().list > 0
end

-- Case-insensitive lookup, tolerant of a trailing " IV"-style rank suffix
-- matching a differently-ranked query (rank is ignored -- callers that
-- care about rank should compare .name exactly instead).
function EbonBuilds.Affix.IsLearned(name)
    if not name then return nil end
    local n = strlower(name)
    local list = DB().list
    if #list == 0 then return nil end -- no data yet: "can't determine"
    for _, a in ipairs(list) do
        if strlower(a.name) == n then
            return a.learned
        end
    end
    return false
end

------------------------------------------------------------------------
-- Request / receive
------------------------------------------------------------------------

function EbonBuilds.Affix.GetCooldownRemaining()
    if lastRequestAt <= 0 then return 0 end
    local now = GetTime()
    local remaining = S.REQUEST_THROTTLE_SECONDS - (now - lastRequestAt)
    return remaining > 0 and math.ceil(remaining) or 0
end

-- Requests a fresh copy from the server. force=true bypasses the "already
-- have data" short-circuit (used by the manual Refresh button); the
-- throttle still applies either way to avoid hammering the server.
function EbonBuilds.Affix.RequestLearned(force)
    if not force and EbonBuilds.Affix.HasData() then
        return false, "has-data"
    end
    if EbonBuilds.Affix.GetCooldownRemaining() > 0 then
        return false, "throttled"
    end
    if not registered and RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, S.PREFIX)
        registered = true
    end
    lastRequestAt = GetTime()
    local ok = pcall(SendAddonMessage, S.PREFIX, S.BuildRequestPayload(), "WHISPER", UnitName("player"))
    return ok, ok and "requested" or "error"
end

-- Applies a fully-reassembled payload body to the cache and notifies the
-- view. Exposed separately from the event handler so tests can drive it
-- directly without simulating chunked addon messages.
function EbonBuilds.Affix.ApplyPayload(body)
    local list = S.ParseLearnedAffixesPayload(body, GetSpellInfo)
    local db = DB()
    db.list = list
    db.lastReceivedAt = GetTime()
    if EbonBuilds.AffixView and EbonBuilds.AffixView.RefreshIfMounted then
        EbonBuilds.AffixView.RefreshIfMounted()
    end
    return list
end

-- CHAT_MSG_ADDON handler entry point.
function EbonBuilds.Affix.HandleAddonMessage(prefix, payload, dist, sender)
    if prefix ~= S.PREFIX then return false end -- cheapest possible check first -- this fires for every addon message on the channel, not just ours
    local playerName = UnitName("player")
    local ok = S.ShouldAcceptMessage(prefix, payload, dist, sender, playerName)
    if not ok then return false end

    local evt, rest = S.ParseEventPayload(payload)
    if evt ~= S.SEND_LEARNED then return true end

    local chunk = S.ParseChunk(rest)
    if not chunk then
        -- Unchunked reply: apply directly.
        EbonBuilds.Affix.ApplyPayload(rest or "")
        return true
    end

    local rec = inflight[chunk.mid]
    if not rec then
        rec = { total = chunk.total, got = 0, parts = {}, t0 = GetTime() }
        inflight[chunk.mid] = rec
    end
    if chunk.index and chunk.index >= 1 and chunk.index <= rec.total and not rec.parts[chunk.index] then
        rec.parts[chunk.index] = chunk.slice
        rec.got = rec.got + 1
    end
    if rec.got == rec.total then
        inflight[chunk.mid] = nil
        EbonBuilds.Affix.ApplyPayload(table.concat(rec.parts, "", 1, rec.total))
    end
    return true
end

function EbonBuilds.Affix.Init()
    -- spam-exempt: CHAT_MSG_ADDON fires for every addon message on the
    -- client (not just ours), and HandleAddonMessage's prefix check is
    -- already the cheapest possible first operation -- high call volume
    -- during a busy sync period isn't wasted work.
    EbonBuilds.WoWEvents.On("CHAT_MSG_ADDON", function(_, prefix, payload, dist, sender)
        EbonBuilds.Affix.HandleAddonMessage(prefix, payload, dist, sender)
    end, "Affix", false, true)
    -- Ask once shortly after login; cheap no-op if the character already
    -- has a cached list from a previous session.
    EbonBuilds.Affix.RequestLearned(false)
end
