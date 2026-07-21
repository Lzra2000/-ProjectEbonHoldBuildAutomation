local addonName, EbonBuilds = ...

-- EbonBuilds: modules/sync/Sync.lua
-- Responsibility: peer-to-peer build synchronisation.
-- Discovery via hidden chat channel + known-peers fallback.
-- Data transfer via SendAddonMessage WHISPER chunks.
-- Batch protocol: LST (list batch) → WNT/SKP (want/skip) → BLD (build data).

EbonBuilds.Sync = {}

local PREFIX        = "EbonBuilds"

-- UnitName("player") and whisper sender names can each come back with or
-- without a "-Realm" suffix depending on connection state. Comparing them
-- exactly risks false negatives (own build treated as foreign) and false
-- positives (loopback not detected). Normalize before comparing.
local function NormalizeName(name)
    name = tostring(name or ""):lower()
    return name:match("^([^-]+)") or name
end
local SYNC_CHANNEL  = "ebonbuildssync"

-- Must be called at file scope (during addon load), not inside ADDON_LOADED event
if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
    -- Announce our version once shortly after login (guild channel is
    -- enough reach; the sync channel rebroadcast happens on activity).
    EbonBuilds.Scheduler.After("sync.versionPing", 15, function()
        local v = GetAddOnMetadata and GetAddOnMetadata("EbonBuilds", "Version")
        if v then
            if GetGuildInfo("player") then
                SendAddonMessage(PREFIX, "VER|" .. v, "GUILD")
            end
            RefreshChannel()
            if syncChannelIndex and syncChannelIndex > 0 then
                pcall(SendChatMessage, ("VER|" .. v):gsub("|", "||"), "CHANNEL", nil, syncChannelIndex)
            end
        end
    end)
end
local MAX_CHUNK     = 180
local MAX_BUILD_TRANSFER = 27000
local MAX_TRANSFER_CHUNKS = math.ceil(MAX_BUILD_TRANSFER / MAX_CHUNK)
local MAX_INFLIGHT_TRANSFERS = 20
local SYNC_TIMEOUT  = 15
local BATCH_SIZE    = 1
local WANT_TIMEOUT  = 15
local REQ_COOLDOWN  = 30
local OFFLINE_COOLDOWN        = 60  -- seconds to block re-sends to a target detected as offline
local MAX_QUEUE_SIZE          = 500 -- safety cap to prevent unbounded queue growth
local MAX_CONSECUTIVE_SENDS   = 200 -- max sends to a target without receiving a response.
                                    -- Covers worst-case batch: 1 LST + (3 builds × ~60 BLD
                                    -- chunks for a 10 KB export) + 1 END = ~182 messages.

-- Bump this to invalidate remote builds from older addon versions.
-- Only affects builds that have NOT been imported — imported builds stay.
local SYNC_VERSION  = 1

-- Set to true to only share builds that reached level 80 while active
local VALIDATION_REQUIRED = true
local VERBOSE_LOG = false

-- Was only a bare /ebbsync verbose toggle -- not discoverable, and not
-- persisted, so a player who turned it on (or on some sessions forgot
-- they had) had no obvious way to find it again short of retyping the
-- same command. Now a real Settings checkbox (Automation -> "Verbose
-- sync logging"); the slash command still works and stays in sync with it.
function EbonBuilds.Sync.IsVerboseLogEnabled()
    return VERBOSE_LOG
end

function EbonBuilds.Sync.SetVerboseLogEnabled(enabled)
    VERBOSE_LOG = enabled and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("syncVerboseLogEnabled", VERBOSE_LOG)
    end
end

local syncChannelIndex
local RefreshChannel
local inflight = {}
local sendQueue = EbonBuilds.RingBuffer.New(MAX_QUEUE_SIZE)
local nextSendTime = 0
local SEND_DELAY = 0.15  -- ~6.7 msg/s; WoW 3.3.5a anti-spam ceiling is ~10 msg/s
local pendingBatches = {}
local lastRequestTime = 0
local MAX_CHANNEL_RETRIES = 2
local channelRetries = { remaining = 0, payload = nil, nextTime = 0 }
local failedTargets = {}  -- [playerName] = blockUntil (Now() + OFFLINE_COOLDOWN)
local sendTally = {}      -- [playerName] = consecutive sends without response

-- "Sync all classes": instead of one unfiltered REQ (every responder's
-- entire public/relayed collection, the exact flood that motivated the
-- per-class filter), each class is requested one at a time with a short
-- gap between them -- same total classes covered, but every individual
-- request is as cheap for responders as a normal single-class sync.
local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_SYNC_STAGGER = 1.5  -- seconds between each class's REQ broadcast
local classSyncQueue = EbonBuilds.RingBuffer.New(#CLASS_TOKENS)
local classSyncNextTime = 0

-- Reliability & anti-flood state (sync v2 improvements):
local wantedFrom = {}       -- [sender] = { uuids = {uuid=true}, retries = {uuid=n}, lastActivity = t }
local requestedThisSync = {}-- [uuid] = true  (dedup across responders, reset per RequestSync)
local reqCooldown = {}      -- [sender] = ignore-REQs-until timestamp (responder-side flood guard)
local syncSession = { active = false, received = 0, lastActivity = 0 }
local RTX_IDLE      = 8    -- seconds of silence from a sender before retransmit request
local RTX_MAX       = 2    -- retransmit attempts per build per sender
local REQ_MIN_GAP   = 30   -- seconds a responder ignores repeat REQs from the same player
local SESSION_SETTLE = 6   -- seconds of silence before the sync summary toast

local function Now()
    return GetTime()
end

local function SyncTrace(msg)
    if EbonBuilds.DebugLog and EbonBuilds.DebugLog.IsEnabled and EbonBuilds.DebugLog.IsEnabled() then
        EbonBuilds.DebugLog.Add("SYNC " .. msg)
    end
end

local function ChatMessagesEnabled()
    local settings = EbonBuildsDB and EbonBuildsDB.globalSettings
    return not settings or settings.syncChatMessages ~= false
end

function EbonBuilds.Sync.IsChatMessagesEnabled()
    return ChatMessagesEnabled()
end

function EbonBuilds.Sync.SetChatMessagesEnabled(enabled)
    EbonBuildsDB = EbonBuildsDB or {}
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.syncChatMessages = enabled and true or false
end

local function Log(msg, force)
    if not force and not ChatMessagesEnabled() then return end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[EbonBuilds Sync]|r " .. msg)
    end
end

local function CommandLog(msg)
    Log(msg, true)
end

local function VerboseLog(msg)
    if VERBOSE_LOG then Log(msg) end
end

-- Every player we've received ANY addon traffic from, with the version
-- they announced (VER opcode) when known. Feeds the unit-tooltip line
-- ("this player runs EbonBuilds") -- session-local by design: presence
-- is live information, not something to persist.
local peers = {}

local function MarkAlive(target)
    -- Reset consecutive send counter when we receive any message from this target
    if target and target ~= "" then
        sendTally[target] = nil
        local p = peers[target] or {}
        p.lastSeen = GetTime()
        peers[target] = p
    end
end

-- name -> { version?, lastSeen } or nil. Strips -Realm suffixes so the
-- tooltip lookup by plain unit name matches cross-realm senders too.
function EbonBuilds.Sync.GetPeerInfo(name)
    if not name then return nil end
    return peers[name] or peers[name:match("^([^-]+)")]
end

local function SortableNow()
    return date("%Y-%m-%d %H:%M:%S")
end

local function IsSyncChannelName(name)
    if type(name) ~= "string" then return false end
    return name:lower():find(SYNC_CHANNEL, 1, true) ~= nil
end


local function IsoToEpoch(iso)
    if not iso or iso == "" then return 0 end
    local y, m, d, h, min, s = iso:match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$")
    if not y then return 0 end
    local ok, result = pcall(time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
    })
    return ok and result or 0
end

-- Handles both ISO (YYYY-MM-DD HH:MM:SS) and US (MM/DD/YY HH:MM:SS) formats
local function DateToEpoch(d)
    if not d or d == "" then return 0 end
    -- Try ISO first: 2026-05-20 16:35:08
    local epoch = IsoToEpoch(d)
    if epoch > 0 then return epoch end
    -- Try US format: 05/19/26 17:51:39  (two-digit year)
    local m, day, y, h, min, s = d:match("^(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+)$")
    if not m then return 0 end
    -- Normalize two-digit year: 26 → 2026
    local year = tonumber(y)
    if year < 100 then year = year + 2000 end
    local ok, result = pcall(time, {
        year = year, month = tonumber(m), day = tonumber(day),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
    })
    return ok and result or 0
end

------------------------------------------------------------------------
-- Offline detection — prevents flooding SendAddonMessage to offline targets
------------------------------------------------------------------------

local function HandleSystemMessage(msg)
    -- WoW 3.3.5a shows this system message when SendAddonMessage WHISPER
    -- targets an offline player: "No player named 'JohnDoe' is currently playing."
    -- Constant: ERR_CHAT_PLAYER_NOT_FOUND_S
    local lower = msg:lower()
    local isOffline = false
    if lower:find("no player named", 1, true) then
        isOffline = true
    end
    if not isOffline then return end

    local now = Now()

    -- Check pendingBatches — these are responders we're actively serving
    for target in pairs(pendingBatches) do
        if lower:find(target:lower(), 1, true) then
            failedTargets[target] = now + OFFLINE_COOLDOWN
            sendTally[target] = nil
            EbonBuilds.RingBuffer.RemoveIf(sendQueue, function(entry) return entry and entry.target == target end)
            pendingBatches[target] = nil
            VerboseLog("Player " .. target .. " is offline — cancelled pending sync batch.")
            return
        end
    end

    -- Also scan sendQueue in case pendingBatches was already cleaned
    local offlineTarget
    EbonBuilds.RingBuffer.ForEach(sendQueue, function(entry)
        if entry and entry.target and lower:find(entry.target:lower(), 1, true) then
            offlineTarget = entry.target
            return false
        end
    end)
    if offlineTarget then
            local target = offlineTarget
            failedTargets[target] = now + OFFLINE_COOLDOWN
            sendTally[target] = nil
            EbonBuilds.RingBuffer.RemoveIf(sendQueue, function(entry) return entry and entry.target == target end)
            pendingBatches[target] = nil
            VerboseLog("Player " .. target .. " is offline — flushed send queue.")
            return
    end
end

------------------------------------------------------------------------
-- Channel management
------------------------------------------------------------------------

local function FindSyncChannel()
    -- GetChannelList() returns all joined channels as id, name pairs
    -- (e.g. 2, "LocalDefense", 4, "ebonbuildssync", 7, "world").
    -- This is the most reliable discovery method across servers.
    if not GetChannelList then return nil end
    local all = {GetChannelList()}
    for i = 1, #all, 2 do
        local idx = tonumber(all[i])
        local name = all[i + 1]
        if idx and idx > 0 and type(name) == "string" and IsSyncChannelName(name) then
            return idx
        end
    end
    return nil
end

local function HideChannelFromChat()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            ChatFrame_RemoveChannel(frame, SYNC_CHANNEL)
        end
    end
end

RefreshChannel = function()
    local idx = FindSyncChannel()
    if idx and idx > 0 then
        if syncChannelIndex ~= idx then
            VerboseLog("Sync channel index updated: " .. (syncChannelIndex or "nil") .. " -> " .. idx)
            syncChannelIndex = idx
        end
    elseif syncChannelIndex and syncChannelIndex > 0 then
        -- We have a cached index from a previous REQ reception; keep it.
    else
        Log("Sync channel not found — join with /join " .. SYNC_CHANNEL)
        syncChannelIndex = nil
    end
end

------------------------------------------------------------------------
-- Send queue (rate-limited via OnUpdate, 50 ms between messages)
------------------------------------------------------------------------

local function Enqueue(target, payload)
    if not target or target == "" or not payload then return end
    -- Reject if target was recently detected as offline
    if failedTargets[target] then
        local t = Now()
        if t < failedTargets[target] then return end
        failedTargets[target] = nil  -- cooldown expired, allow retry
    end
    -- Ring append is O(1); at the safety cap it overwrites the oldest entry.
    EbonBuilds.RingBuffer.Append(sendQueue, { target = target, payload = payload })
end

local function SendChunked(target, code, streamKey, data)
    if type(data) ~= "string" or #data > MAX_BUILD_TRANSFER then
        if EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("Sync.SendChunked", "Build payload exceeds the 27 KB transfer limit")
        end
        return false
    end
    local sender = UnitName("player")
    if #data <= MAX_CHUNK then
        local payload = string.format("%s|%s|%s|1/1|%s", code, sender, streamKey, data)
        Enqueue(target, payload)
        return true
    end
    local total = math.ceil(#data / MAX_CHUNK)
    for idx = 1, total do
        local start = (idx - 1) * MAX_CHUNK + 1
        local chunk = string.sub(data, start, start + MAX_CHUNK - 1)
        local payload = string.format("%s|%s|%s|%d/%d|%s", code, sender, streamKey, idx, total, chunk)
        Enqueue(target, payload)
    end
    return true
end

------------------------------------------------------------------------
-- Inflight cleanup (received chunks)
------------------------------------------------------------------------

local function CleanupExpired()
    local t = Now()
    for k, v in pairs(inflight) do
        if t - (v.t0 or t) > SYNC_TIMEOUT then
            inflight[k] = nil
        end
    end
    for k, v in pairs(pendingBatches) do
        if t - (v.t0 or t) > WANT_TIMEOUT then
            pendingBatches[k] = nil
        end
    end
    for k, expires in pairs(failedTargets) do
        if t >= expires then
            failedTargets[k] = nil
        end
    end
    -- Garbage-collect sendTally entries that haven't been touched in > SYNC_TIMEOUT
    for k in pairs(sendTally) do
        if not pendingBatches[k] and not failedTargets[k] then
            sendTally[k] = nil
        end
    end
end

------------------------------------------------------------------------
-- Assembly
------------------------------------------------------------------------

local function AssembleBuild(sender, buildId, base64)
    local imported = EbonBuilds.ExportImport.DecodeBuild(base64)
    if not imported then return end

    EbonBuildsDB.remoteBuilds = EbonBuildsDB.remoteBuilds or {}

    -- Network data never mutates the local build collection. A UUID collision
    -- is stored under a sender-qualified remote key and requires an explicit
    -- user import/merge from the Public Builds view.
    local localCollision = EbonBuildsDB.builds[buildId] ~= nil
    local remoteKey = localCollision and (NormalizeName(sender) .. ":" .. buildId) or buildId
    imported._sourceBuildId = buildId
    imported._transportSender = sender
    imported._claimedAuthor = imported.author

    -- Store in remote builds (market), not in local collection.
    local rb = EbonBuildsDB.remoteBuilds[remoteKey]
    if rb then
        rb._lastSeenAt = time()
        local incomingDate = imported.lastModified or ""
        local storedDate   = rb.lastModified or ""
        if incomingDate > storedDate then
            imported.id = buildId
            imported._lastSeenAt = time()
            EbonBuildsDB.remoteBuilds[remoteKey] = imported
            VerboseLog("Build " .. buildId .. " updated in remote (incoming=" .. incomingDate .. ")")
        end
    else
        imported.id = buildId
        imported._lastSeenAt = time()
        EbonBuildsDB.remoteBuilds[remoteKey] = imported
        VerboseLog("Build " .. buildId .. " stored in remote (author: " .. (imported.author or "?") .. ")")
    end
    EbonBuilds.Scheduler.After("database.pruneRemoteBuilds", 0.5,
        EbonBuilds.Database.PruneRemoteBuilds, EbonBuilds.Scheduler.MAINTENANCE, false)

    if EbonBuilds.PublicBuildsView and EbonBuilds.PublicBuildsView.RefreshIfMounted then
        EbonBuilds.PublicBuildsView.RefreshIfMounted()
    end
end

------------------------------------------------------------------------
-- Batch protocol (responder side)
------------------------------------------------------------------------

local function SendNextBatch(requester)
    local pb = pendingBatches[requester]
    if not pb then return end

    pb.current = pb.current + 1
    local start = (pb.current - 1) * BATCH_SIZE + 1
    if start > #pb.builds then
        -- All batches done, send END
        local endPayload = string.format("END|%s|%d", UnitName("player"), pb.sent)
        Enqueue(requester, endPayload)
        VerboseLog(string.format("All batches sent to %s (%d builds total)", requester, pb.sent))
        pendingBatches[requester] = nil
        return
    end

    local finish = math.min(start + BATCH_SIZE - 1, #pb.builds)
    local parts = { "LST", UnitName("player"), pb.current .. "/" .. pb.totalBatches }
    for i = start, finish do
        local b = pb.builds[i]
        parts[#parts + 1] = b.id
        parts[#parts + 1] = tostring(DateToEpoch(b.lastModified))
    end
    Enqueue(requester, table.concat(parts, "|"))
    VerboseLog(string.format("LST batch %s enqueued for %s (%d builds)",
        pb.current .. "/" .. pb.totalBatches, requester, finish - start + 1))
end

local function SendBatchBuilds(requester, wantedUuids)
    local pb = pendingBatches[requester]
    if not pb then return end

    local wanted = {}
    for uuid in pairs(wantedUuids) do wanted[uuid] = true end

    local start = (pb.current - 1) * BATCH_SIZE + 1
    local finish = math.min(start + BATCH_SIZE - 1, #pb.builds)
    for i = start, finish do
        local b = pb.builds[i]
        if wanted[b.id] then
            local b64 = EbonBuilds.ExportImport.ExportBuild(b)
            if b64 then
                VerboseLog(string.format("BLD enqueued for %s: %s (%d bytes)",
                    requester, b.id, #b64))
                if SendChunked(requester, "BLD", b.id, b64) then pb.sent = pb.sent + 1 end
            end
        end
    end

    SendNextBatch(requester)
end

------------------------------------------------------------------------
-- Core request handler (responder side)
------------------------------------------------------------------------

local function HandleRequest(requester, classFilter)
    -- Flood guard: answering a REQ costs real work (list building, batching,
    -- tome sharing). One answer per requester per REQ_MIN_GAP is plenty.
    if requester and reqCooldown[requester] and Now() < reqCooldown[requester] then
        VerboseLog("REQ from " .. requester .. " ignored (cooldown)")
        return
    end
    if requester then reqCooldown[requester] = Now() + REQ_MIN_GAP end
    if classFilter == "" then classFilter = nil end
    SyncTrace("REQ from " .. tostring(requester) .. (classFilter and (" (class filter: " .. classFilter .. ")") or ""))
    if not requester or requester == "" or NormalizeName(requester) == NormalizeName(UnitName("player")) then return end

    EbonBuildsDB.syncPeers = EbonBuildsDB.syncPeers or {}
    EbonBuildsDB.syncPeers[requester] = true

    -- Target just contacted us — reset send cap so BLD chunks aren't blocked
    sendTally[requester] = nil

    -- Share our tome-drop knowledge with the requester (capped batch,
    -- whisper queue handles rate limiting). Merging is idempotent on the
    -- receiving side, so overlapping answers from several responders are
    -- harmless. This must happen BEFORE any early return below: a player
    -- with zero public builds still has tome observations worth sharing,
    -- and used to be skipped entirely because the old code shared tomes
    -- only after the "any public builds?" check.
    for _, tomMsg in ipairs(EbonBuilds.TomeAtlas.SerializeAll(100)) do
        Enqueue(requester, tomMsg)
    end

    local allPublic = EbonBuilds.Build.ListPublic()
    VerboseLog("HandleRequest: " .. #allPublic .. " public builds total")
    if #allPublic == 0 then
        VerboseLog("No public builds to send, replying END to " .. requester)
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    local eligible = {}
    for _, build in ipairs(allPublic) do
        if classFilter and build.class ~= classFilter then
            -- Skipped silently: not a VerboseLog case per-build, would be
            -- noisy on a full server sync; the total counts below cover it.
        elseif NormalizeName(build.author) ~= NormalizeName(requester) then
            if VALIDATION_REQUIRED and not build.validated then
                VerboseLog("  build " .. (build.title or "?") .. " skipped: no completed local run reported")
            else
                eligible[#eligible + 1] = build
            end
        else
            VerboseLog("  build " .. (build.title or "?") .. " skipped: authored by requester")
        end
    end

    VerboseLog("HandleRequest: " .. #eligible .. " eligible after filtering")
    if #eligible == 0 then
        VerboseLog("No eligible builds for " .. requester .. ", replying END")
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    VerboseLog(string.format("Prepared %d builds for %s in %d batch(es)",
        #eligible, requester, math.ceil(#eligible / BATCH_SIZE)))

    pendingBatches[requester] = {
        builds = eligible,
        totalBatches = math.ceil(#eligible / BATCH_SIZE),
        current = 0,
        sent = 0,
        t0 = Now(),
    }
    SendNextBatch(requester)
end

-- Messages (both visible chat and SendAddonMessage) can carry server-injected
-- prefixes (e.g. Ebonhold hardcore tier markers like "|cffff0000[HCIV]|r").
-- Strip WoW colour escapes, then remove any bracket-enclosed prefix at the
-- start (handles [HCI] through [HCX] and any future server-injected tag).
-- Strips server-injected hardcore prefixes ("|cffff0000[HCIV]|r ") and a
-- whole-message colour wrap from the START of a message only.
--
-- CRITICAL: this must never gsub colour patterns globally. Payload fields
-- are "|"-separated, so a global "|c%x+" wipe eats any field beginning
-- with c+hex -- which includes ~1/16 of all build ids and base64 chunks --
-- silently corrupting transfers. Everything here is anchored.
local function _StripChatPrefix(msg)
    local s = msg
    local strippedLeadingColour = false
    local changed = true
    while changed do
        changed = false
        local n
        s, n = s:gsub("^%s+", "")
        if n > 0 then changed = true end
        s, n = s:gsub("^|c%x%x%x%x%x%x%x%x", "")
        if n > 0 then changed = true; strippedLeadingColour = true end
        s, n = s:gsub("^|r", "")
        if n > 0 then changed = true end
        s, n = s:gsub("^%[[^%]]+%]%s*", "")
        if n > 0 then changed = true end
    end
    -- A trailing |r is only removed when it closes a leading colour wrap;
    -- otherwise a legitimate payload ending in "|r" would be damaged.
    if strippedLeadingColour then
        s = s:gsub("|r%s*$", "")
    end
    return s
end

------------------------------------------------------------------------
-- Channel message handler (REQ via custom chat channel)
------------------------------------------------------------------------

-- Forward declaration: HandleTome is defined further down but referenced by
-- the channel dispatcher; without this the closure would call a nil global.
local HandleTome
local HandleGet

local function HandleChannelMessage(msg, sender, _, channelName, _, _, _, channelNumber)
    -- CHAT_MSG_CHANNEL args: text, playerName, language, channelName,
    --   playerName2, specialFlag, zoneChannelID, channelIndex, channelBaseName.
    -- channelNumber = arg8 (channelIndex), arg5-7 skipped via _ placeholders.
    -- channelName may be a name string, slot ID string, or slot ID number
    -- depending on server — accept anything non-nil and non-empty.
    if not channelName or channelName == "" then
        return
    end

    MarkAlive(sender)

    local decoded = msg:gsub("||", "|")
    decoded = _StripChatPrefix(decoded)
    local parts = {strsplit("|", decoded)}
    local code = parts[1]
    if code == "VER" then
        HandleVersionPing(decoded, sender)
    elseif code == "TOM" then
        HandleTome(decoded, sender)
        return
    end
    if code == "GET" then
        HandleGet(decoded, sender)
        return
    end
    if code == "PRF" then
        if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.HandleBroadcast then
            local ok, err = pcall(EbonBuilds.EchoPerformance.HandleBroadcast, decoded, sender)
            if not ok then Log("EchoPerformance.HandleBroadcast error: " .. tostring(err)) end
        end
        return
    end
    if code == "APR" then
        if EbonBuilds.Calibration and EbonBuilds.Calibration.HandleAppearanceBroadcast then
            local ok, err = pcall(EbonBuilds.Calibration.HandleAppearanceBroadcast, decoded, sender)
            if not ok then Log("Calibration.HandleAppearanceBroadcast error: " .. tostring(err)) end
        end
        return
    end
    if code ~= "REQ" then return end

    -- We received a valid REQ on this channel — learn its index
    if channelNumber and type(channelNumber) == "number" and channelNumber > 0 then
        if not syncChannelIndex or syncChannelIndex ~= channelNumber then
            syncChannelIndex = channelNumber
            VerboseLog("Sync channel index learned: " .. channelNumber)
        end
    end

    local ok, err = pcall(HandleRequest, sender, parts[3])
    if not ok then Log("HandleRequest error: " .. tostring(err)) end
end

------------------------------------------------------------------------
-- Addon message handlers (requester side)
------------------------------------------------------------------------

local function HandleAddonREQ(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "REQ" then return end
    local ok, err = pcall(HandleRequest, sender, parts[3])
    if not ok then Log("HandleAddonREQ error: " .. tostring(err)) end
end

local function HandleChunk(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "BLD" or #parts < 5 then return end
    local snd, buildId, idxTotal, data = parts[2], parts[3], parts[4], parts[5]

    local idx, total = idxTotal:match("^(%d+)/(%d+)$")
    if not idx then return end
    idx = tonumber(idx)
    total = tonumber(total)
    if not idx or not total or total < 1 or total > MAX_TRANSFER_CHUNKS then return end
    if type(data) ~= "string" or #data > MAX_CHUNK then return end
    if type(buildId) ~= "string" or #buildId > 80 then return end
    if NormalizeName(snd) ~= NormalizeName(sender) then return end

    local key = NormalizeName(sender) .. ":" .. buildId
    local rec = inflight[key]
    if not rec then
        local activeTransfers = 0
        for _ in pairs(inflight) do activeTransfers = activeTransfers + 1 end
        if activeTransfers >= MAX_INFLIGHT_TRANSFERS then CleanupExpired(); return end
        rec = { total = total, got = 0, parts = {}, t0 = Now() }
        inflight[key] = rec
    end
    if rec.total ~= total then inflight[key] = nil; return end

    if idx >= 1 and idx <= total and not rec.parts[idx] then
        rec.parts[idx] = data
        rec.got = rec.got + 1
    end

    -- Any chunk from this sender counts as liveness for retransmit timing.
    local wf = wantedFrom[snd]
    if wf then wf.lastActivity = Now() end
    if syncSession.active then syncSession.lastActivity = Now() end

    if rec.got == rec.total then
        local assembled = table.concat(rec.parts, "", 1, rec.total)
        inflight[key] = nil
        VerboseLog(string.format("Build %s from %s fully received (%d chunks, %d bytes)",
            buildId, snd, total, #assembled))
        SyncTrace(("BLD %s complete from %s (%d chunks)"):format(buildId, snd, total))
        if wf then wf.uuids[buildId] = nil end
        local ok, err = pcall(AssembleBuild, snd, buildId, assembled)
        if ok then
            if syncSession.active then
                syncSession.received = syncSession.received + 1
            end
        else
            if EbonBuilds.ErrorLog then
                EbonBuilds.ErrorLog.Record("Sync.AssembleBuild", "Error assembling build " .. buildId .. ": " .. tostring(err))
            end
            VerboseLog("Error assembling build " .. buildId .. ": " .. tostring(err))
        end
    end

    CleanupExpired()
end

local function HandleListBatch(payload, sender)
    -- payload: "LST|sender|batch/total|uuid1|epoch1|uuid2|epoch2|..."
    VerboseLog(string.format("LST received from %s", sender))
    local parts = {strsplit("|", payload)}
    if #parts < 4 then return end

    local wanted = {}
    for i = 4, #parts, 2 do
        local uuid = parts[i]
        local offerEpoch = tonumber(parts[i + 1]) or 0
        if uuid and uuid ~= "" then
            local needUpdate = false
            local ownBuild = EbonBuildsDB.builds[uuid]
            if ownBuild then
                local localEpoch = DateToEpoch(ownBuild.lastModified)
                needUpdate = offerEpoch > localEpoch
            else
                -- Already imported as local copy?
                local localCopy = nil
                for _, b in pairs(EbonBuildsDB.builds) do
                    if b.importedFrom == uuid then localCopy = b; break end
                end
                local localEpoch = localCopy and DateToEpoch(localCopy._importedAt) or 0
                if offerEpoch > localEpoch then
                    needUpdate = true
                end
                -- Already received via another responder?
                if not needUpdate then
                    local rb = (EbonBuildsDB.remoteBuilds or {})[uuid]
                    local rbEpoch = rb and DateToEpoch(rb.lastModified) or 0
                    needUpdate = offerEpoch > rbEpoch
                end
            end
            if needUpdate and requestedThisSync[uuid] then
                -- Another responder already offered this uuid and we asked
                -- them for it -- don't transfer the same build twice.
                VerboseLog("uuid " .. uuid .. " already requested elsewhere, skipping")
                needUpdate = false
            end
            if needUpdate then
                wanted[#wanted + 1] = uuid
            end
        end
    end

    if #wanted == 0 then
        VerboseLog(string.format("SKP enqueued for %s (nothing wanted)", sender))
        local skipPayload = string.format("SKP|%s", UnitName("player"))
        Enqueue(sender, skipPayload)
    else
        VerboseLog(string.format("WNT enqueued for %s: %d builds", sender, #wanted))
        SyncTrace(("WNT -> %s: %d build(s)"):format(sender, #wanted))
        -- Track what we asked this sender for, so lost transfers can be
        -- detected and retransmit-requested (RTX) instead of vanishing.
        local wf = wantedFrom[sender]
        if not wf then
            wf = { uuids = {}, retries = {}, lastActivity = Now() }
            wantedFrom[sender] = wf
        end
        local wantParts = { "WNT", UnitName("player") }
        for _, uuid in ipairs(wanted) do
            wantParts[#wantParts + 1] = uuid
            wf.uuids[uuid] = true
            requestedThisSync[uuid] = true
        end
        wf.lastActivity = Now()
        Enqueue(sender, table.concat(wantParts, "|"))
    end
end

local function HandleWant(payload, sender)
    -- payload: "WNT|requester|uuid1|uuid2|..."
    VerboseLog(string.format("WNT received from %s", sender))
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "WNT" then return end
    local wantedUuids = {}
    for i = 3, #parts do
        wantedUuids[parts[i]] = true
    end
    SendBatchBuilds(sender, wantedUuids)
end

local function HandleSkip(payload, sender)
    VerboseLog(string.format("SKP received from %s", sender))
    SendBatchBuilds(sender, {})  -- empty = skip all in current batch
end

local function HandleEnd(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "END" then return end
    local snd, count = parts[2], parts[3]

    EbonBuildsDB.lastSyncDate = SortableNow()

    local c = tonumber(count) or 0
    if c > 0 and ChatMessagesEnabled() then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff19ff19EbonBuilds|r: Received %d build(s) from %s.", c, snd))
    end

    if EbonBuilds.PublicBuildsView and EbonBuilds.PublicBuildsView.RefreshIfMounted then
        EbonBuilds.PublicBuildsView.RefreshIfMounted()
    end
end

------------------------------------------------------------------------
-- Tome Atlas sharing
------------------------------------------------------------------------

-- RTX|requester|uuid1|uuid2... -- the requester lost (part of) these
-- transfers; re-send them. Only public builds we actually own are eligible,
-- so a malicious RTX can't exfiltrate private data.
local function HandleRtx(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "RTX" then return end
    local resent = 0
    for i = 3, #parts do
        local uuid = parts[i]
        local b = uuid and EbonBuildsDB.builds[uuid]
        if b and b.isPublic then
            local b64 = EbonBuilds.ExportImport.ExportBuild(b)
            if b64 then
                if SendChunked(sender, "BLD", uuid, b64) then resent = resent + 1 end
            end
        end
    end
    SyncTrace(("RTX from %s: re-sent %d build(s)"):format(sender, resent))
end

-- GET|requester|id8 -- chat-link fetch: send the matching PUBLIC build.
-- Same safety rule as RTX: private builds are never served.
function HandleGet(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "GET" or not parts[3] then return end
    if sender == UnitName("player") then return end
    local id8 = parts[3]
    for id, b in pairs(EbonBuildsDB.builds or {}) do
        if b.isPublic and id:gsub("%-", ""):sub(1, 8) == id8 then
            local b64 = EbonBuilds.ExportImport.ExportBuild(b)
            if b64 then
                if SendChunked(sender, "BLD", id, b64) then
                    SyncTrace(("GET from %s: served %s"):format(sender, id))
                end
            end
            return
        end
    end
end

-- Broadcast a chat-link fetch request (channel + guild).
function EbonBuilds.Sync.BroadcastGet(id8)
    local payload = string.format("GET|%s|%s", UnitName("player"), id8)
    RefreshChannel()
    if syncChannelIndex and syncChannelIndex > 0 then
        pcall(SendChatMessage, payload:gsub("|", "||"), "CHANNEL", nil, syncChannelIndex)
    end
    if GetGuildInfo("player") then
        SendAddonMessage(PREFIX, payload, "GUILD")
    end
end

function HandleTome(payload, sender)
    if sender == UnitName("player") then return end
    local id, name, mob, zone, count = EbonBuilds.TomeAtlas.ParsePayload(payload)
    if not id then return end
    EbonBuilds.TomeAtlas.Merge(id, name, mob, zone, count)
    if EbonBuilds.TomeAtlasView and EbonBuilds.TomeAtlasView.RefreshIfMounted then
        EbonBuilds.TomeAtlasView.RefreshIfMounted()
    end
end

-- Broadcasts a single fresh drop observation to everyone (channel + guild).
function EbonBuilds.Sync.BroadcastTomeEntry(itemId, key, count)
    local payload = EbonBuilds.TomeAtlas.SerializeEntry(itemId, key, count)
    if not payload then return end
    RefreshChannel()
    if syncChannelIndex and syncChannelIndex > 0 then
        local escaped = payload:gsub("|", "||")
        pcall(SendChatMessage, escaped, "CHANNEL", nil, syncChannelIndex)
    end
    if GetGuildInfo("player") then
        SendAddonMessage(PREFIX, payload, "GUILD")
    end
end

-- Broadcasts a batch of Echo Performance aggregate data (see
-- EchoPerformance.lua's SerializeBatch) to everyone. Same
-- channel+guild pattern as BroadcastTomeEntry; the payload already
-- starts with "PRF|", not re-tagged here.
function EbonBuilds.Sync.BroadcastPerfBatch(payload)
    if not payload then return end
    RefreshChannel()
    if syncChannelIndex and syncChannelIndex > 0 then
        local escaped = payload:gsub("|", "||")
        pcall(SendChatMessage, escaped, "CHANNEL", nil, syncChannelIndex)
    end
    if GetGuildInfo("player") then
        SendAddonMessage(PREFIX, payload, "GUILD")
    end
end

------------------------------------------------------------------------
-- Dispatch (CHAT_MSG_ADDON events)
------------------------------------------------------------------------

-- Update notice: peers include their addon version in a lightweight
-- VER message. Seeing a HIGHER version than ours triggers one chat
-- notice per session pointing at the GitHub releases page -- the only
-- update check a sandboxed addon can do (no network access, so GitHub
-- itself is unreachable from in-game; peers ARE the signal). Older
-- clients without this handler simply ignore the unknown opcode, which
-- the sync fuzzer already guarantees is safe.
local updateNoticeShown = false

local function ParseVersion(v)
    local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major) * 10000 + tonumber(minor)
end

local function OwnVersion()
    if GetAddOnMetadata then
        return GetAddOnMetadata("EbonBuilds", "Version")
    end
    return nil
end

local function HandleVersionPing(payload, sender)
    if sender == UnitName("player") then return end
    -- Record the announced version regardless of the notice logic --
    -- the tooltip wants to know versions lower than ours too.
    if sender and sender ~= "" then
        local p = peers[sender] or {}
        p.version = payload:sub(5)
        p.lastSeen = GetTime()
        peers[sender] = p
    end
    if updateNoticeShown then return end
    local theirs = ParseVersion(payload:sub(5))
    local mine = ParseVersion(OwnVersion())
    if not theirs or not mine or theirs <= mine then return end
    updateNoticeShown = true
    if ChatMessagesEnabled() then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffffd100EbonBuilds:|r a newer version (%s) is in use around you. Download: |cff6ea3d9github.com/Lzra2000/-ProjectEbonHoldBuildAutomation/releases|r",
            payload:sub(5)))
    end
end
EbonBuilds.Sync._HandleVersionPingForTests = function(...) return HandleVersionPing(...) end

local function DispatchAddon(prefix, payload, dist, sender)
    if prefix ~= PREFIX then return end
    if not payload or payload == "" then return end
    MarkAlive(sender)

    -- Server may inject hardcore prefix even into addon messages
    payload = _StripChatPrefix(payload)
    local code = payload:sub(1, 3)
    if code == "VER" then
        HandleVersionPing(payload, sender)
    elseif code == "REQ" then
        HandleAddonREQ(payload, sender)
    elseif code == "BLD" then
        HandleChunk(payload, sender)
    elseif code == "LST" then
        HandleListBatch(payload, sender)
    elseif code == "WNT" then
        HandleWant(payload, sender)
    elseif code == "SKP" then
        HandleSkip(payload, sender)
    elseif code == "END" then
        HandleEnd(payload, sender)
    elseif code == "TOM" then
        HandleTome(payload, sender)
    elseif code == "RTX" then
        HandleRtx(payload, sender)
    elseif code == "GET" then
        HandleGet(payload, sender)
    elseif code == "PRF" then
        if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.HandleBroadcast then
            local ok, err = pcall(EbonBuilds.EchoPerformance.HandleBroadcast, payload, sender)
            if not ok then Log("EchoPerformance.HandleBroadcast error: " .. tostring(err)) end
        end
    elseif code == "APR" then
        if EbonBuilds.Calibration and EbonBuilds.Calibration.HandleAppearanceBroadcast then
            local ok, err = pcall(EbonBuilds.Calibration.HandleAppearanceBroadcast, payload, sender)
            if not ok then Log("Calibration.HandleAppearanceBroadcast error: " .. tostring(err)) end
        end
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Internal export for unit tests
EbonBuilds.Sync._StripChatPrefix = _StripChatPrefix
EbonBuilds.Sync._DispatchAddonForTests = function(...) return DispatchAddon(...) end
EbonBuilds.Sync._HandleChannelMessageForTests = function(...) return HandleChannelMessage(...) end
EbonBuilds.Sync._HandleSystemMessageForTests = function(...) return HandleSystemMessage(...) end
EbonBuilds.Sync._DebugState = function()
    local q, opcodes = 0, {}
    EbonBuilds.RingBuffer.ForEach(sendQueue, function(entry)
        q = q + 1
        local payload = type(entry) == "table" and entry.payload or entry
        if type(payload) == "string" then
            opcodes[#opcodes + 1] = payload:sub(1, 3)
        end
    end)
    local wf = 0
    for _, rec in pairs(wantedFrom) do
        for _ in pairs(rec.uuids) do wf = wf + 1 end
    end
    return { queue = q, opcodes = opcodes, wantedFrom = wf, session = syncSession, requested = requestedThisSync }
end
EbonBuilds.Sync._ResetForTests = function()
    wantedFrom = {}
    requestedThisSync = {}
    reqCooldown = {}
    EbonBuilds.RingBuffer.Clear(sendQueue)
    EbonBuilds.RingBuffer.Clear(classSyncQueue)
    syncSession.active = false
    syncSession.received = 0
end

function EbonBuilds.Sync.GetCooldownRemaining()
    local elapsed = Now() - lastRequestTime
    if elapsed >= REQ_COOLDOWN then return 0 end
    return math.ceil(REQ_COOLDOWN - elapsed)
end

-- Fires one REQ broadcast (channel + guild). Does NOT touch the cooldown --
-- callers (RequestSync / the all-classes queue drain) own that.
local function DoBroadcastREQ(classFilter)
    local me      = UnitName("player")
    -- Third field is an optional class-token filter (e.g. "DEATHKNIGHT").
    -- Older clients (pre-2.13) ignore a trailing field they don't parse,
    -- so this is backward compatible with responders who haven't updated.
    local payload = string.format("REQ|%s|%s", me, classFilter or "")

    -- 1. Broadcast via hidden chat channel (all addon users on the realm)
    RefreshChannel()
    local escapedPayload = payload:gsub("|", "||")
    channelRetries.remaining = MAX_CHANNEL_RETRIES
    channelRetries.payload = escapedPayload
    channelRetries.nextTime = 0  -- fire immediately on next OnUpdate

    -- 2. Guild broadcast via SendAddonMessage (reliable, but guild-only)
    local guildName = GetGuildInfo("player")
    if guildName then
        SendAddonMessage(PREFIX, payload, "GUILD")
        VerboseLog("REQ also broadcast via GUILD" ..
            (classFilter and (" (class filter: " .. classFilter .. ")") or ""))
    end
end

function EbonBuilds.Sync.RequestSync(classFilter)
    local remaining = EbonBuilds.Sync.GetCooldownRemaining()
    if remaining > 0 then
        Log("Sync on cooldown, wait " .. remaining .. "s before requesting again")
        return
    end
    lastRequestTime = Now()

    -- Fresh sync session: reset cross-responder dedup and transfer tracking,
    -- arm the summary toast.
    requestedThisSync = {}
    wantedFrom = {}
    syncSession.active = true
    syncSession.received = 0
    syncSession.lastActivity = Now()

    EbonBuilds.RingBuffer.Clear(classSyncQueue) -- a single-class request cancels any pending "sync all" run

    if classFilter then
        Log("Requesting sync (class filter: " .. classFilter .. ")...")
    else
        Log("Requesting sync...")
    end
    DoBroadcastREQ(classFilter)
end

-- Requests every class one at a time (staggered) instead of one unfiltered
-- REQ. Same total coverage as the old "All Classes" behavior, but each
-- responder only ever has to answer a normal, cheap single-class request --
-- avoiding the exact flood of near-duplicate builds this filter exists to
-- prevent.
function EbonBuilds.Sync.RequestSyncAllClasses()
    local remaining = EbonBuilds.Sync.GetCooldownRemaining()
    if remaining > 0 then
        Log("Sync on cooldown, wait " .. remaining .. "s before requesting again")
        return
    end
    lastRequestTime = Now()

    requestedThisSync = {}
    wantedFrom = {}
    syncSession.active = true
    syncSession.received = 0
    syncSession.lastActivity = Now()

    EbonBuilds.RingBuffer.Clear(classSyncQueue)
    for _, token in ipairs(CLASS_TOKENS) do
        EbonBuilds.RingBuffer.Append(classSyncQueue, token)
    end
    classSyncNextTime = 0 -- fire the first class immediately on next OnUpdate
    Log(("Requesting sync for all %d classes (staggered)..."):format(EbonBuilds.RingBuffer.Count(classSyncQueue)))
end

function EbonBuilds.Sync.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        VERBOSE_LOG = EbonBuilds.Database.GetCharacterPreference("syncVerboseLogEnabled")
    end
    -- spam-exempt (5th arg): both events legitimately fire very often during
    -- active sync with many nearby players (every CHAT_MSG_ADDON on the
    -- client reaches this listener, not just ours, plus real BLD/WNT/RTX
    -- traffic) -- that's the feature working, not over-broad registration.
    EbonBuilds.WoWEvents.On("CHAT_MSG_ADDON", function(_, ...) DispatchAddon(...) end, "Sync", false, true)
    EbonBuilds.WoWEvents.On("CHAT_MSG_CHANNEL", function(_, ...) HandleChannelMessage(...) end, "Sync", false, true)
    EbonBuilds.WoWEvents.On("CHAT_MSG_SYSTEM", function(_, ...) HandleSystemMessage(...) end, "Sync")
    EbonBuilds.WoWEvents.On("PLAYER_LEVEL_UP", function(_, newLevel)
        if newLevel == 80 then
            local build = EbonBuilds.Build.GetActive()
            local session = EbonBuilds.Session and EbonBuilds.Session.GetActiveSession()
            local sameStrategy = build and session and session.buildId == build.id
                and not session.mixedStrategy
                and (tonumber(session.strategyRevision) or 1) == (tonumber(build.strategyRevision) or 1)
            if build and sameStrategy and not build.validated then
                build.validated = true
                VerboseLog("Build \"" .. (build.title or "?") .. "\" marked locally run-tested (reached level 80)")
            end
        end
    end, "Sync")
    local function TickSync()
        local now = Now()

        -- Retransmit lost transfers: if a sender we WNT'd builds from has
        -- gone quiet while builds are still missing, ask again (bounded).
        for sender, wf in pairs(wantedFrom) do
            if next(wf.uuids) and now - wf.lastActivity > RTX_IDLE then
                local rtx = { "RTX", UnitName("player") }
                for uuid in pairs(wf.uuids) do
                    wf.retries[uuid] = (wf.retries[uuid] or 0) + 1
                    if wf.retries[uuid] <= RTX_MAX then
                        rtx[#rtx + 1] = uuid
                    else
                        -- Give up on this sender; allow another responder
                        -- to offer the same uuid in a future LST.
                        wf.uuids[uuid] = nil
                        requestedThisSync[uuid] = nil
                        SyncTrace(("giving up on %s from %s"):format(uuid, sender))
                    end
                end
                wf.lastActivity = now
                if #rtx > 2 then
                    Enqueue(sender, table.concat(rtx, "|"))
                    SyncTrace(("RTX -> %s: %d build(s)"):format(sender, #rtx - 2))
                end
            elseif not next(wf.uuids) then
                wantedFrom[sender] = nil
            end
        end

        -- Sync summary: once traffic settles, tell the user what happened.
        if syncSession.active and now - syncSession.lastActivity > SESSION_SETTLE then
            syncSession.active = false
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                if syncSession.received > 0 then
                    EbonBuilds.Toast.Show(("Sync complete: %d build(s) received"):format(syncSession.received))
                else
                    EbonBuilds.Toast.Show("Sync complete: everything up to date")
                end
            end
            SyncTrace(("session settled: %d received"):format(syncSession.received))
        end

        -- "Sync all classes" queue: fire the next class's REQ once the
        -- current one's channel-retry cycle is idle and the stagger gap
        -- has elapsed. Keeps every individual REQ as cheap as a normal
        -- single-class sync instead of one unfiltered blast.
        if EbonBuilds.RingBuffer.Count(classSyncQueue) > 0 and channelRetries.remaining == 0 and now >= classSyncNextTime then
            local nextClass = EbonBuilds.RingBuffer.PopOldest(classSyncQueue)
            DoBroadcastREQ(nextClass)
            classSyncNextTime = now + CLASS_SYNC_STAGGER
        end

        -- Channel retry loop
        if channelRetries.remaining > 0 and now >= channelRetries.nextTime then
            channelRetries.remaining = channelRetries.remaining - 1
            local sent = false
            -- Try by index first (fast path when JoinChannelByName worked)
            if syncChannelIndex and syncChannelIndex > 0 then
                local ok, err = pcall(SendChatMessage, channelRetries.payload, "CHANNEL", nil, syncChannelIndex)
                if ok then
                    VerboseLog("REQ sent on channel index " .. syncChannelIndex)
                    sent = true
                else
                    VerboseLog("REQ by index failed: " .. tostring(err) .. " — trying by name")
                end
            end
            -- Fallback: send by channel name string
            if not sent then
                local ok, err = pcall(SendChatMessage, channelRetries.payload, "CHANNEL", nil, SYNC_CHANNEL)
                if ok then
                    VerboseLog("REQ sent on channel name " .. SYNC_CHANNEL)
                    sent = true
                else
                    VerboseLog("REQ by name also failed: " .. tostring(err))
                end
            end
            if sent or channelRetries.remaining == 0 then
                channelRetries.remaining = 0
            else
                channelRetries.nextTime = now + 0.1
            end
        end
        -- Send queue (rate-limited, with offline guard)
        if EbonBuilds.RingBuffer.Count(sendQueue) > 0 and now >= nextSendTime then
            local entry = EbonBuilds.RingBuffer.PopOldest(sendQueue)
            if entry.target and entry.target ~= "" and entry.payload then
                local blocked = failedTargets[entry.target]
                local tally = sendTally[entry.target] or 0
                if (blocked and now < blocked) then
                    VerboseLog(string.format("Dropped msg for %s: target offline (blocked for %ds)",
                        entry.target, math.ceil(blocked - now)))
                elseif tally >= MAX_CONSECUTIVE_SENDS then
                    VerboseLog(string.format("Dropped msg for %s: exceeded send cap (%d)",
                        entry.target, tally))
                else
                    if blocked then failedTargets[entry.target] = nil end
                    local code = entry.payload:match("^(%a%a%a)|") or "?"
                    VerboseLog(string.format("Sent %s to %s (%d bytes)",
                        code, entry.target, #entry.payload))
                    SendAddonMessage(PREFIX, entry.payload, "WHISPER", entry.target)
                    sendTally[entry.target] = tally + 1
                end
            end
            nextSendTime = now + SEND_DELAY
        end
    end
    EbonBuilds.Scheduler.Every("sync.tick", 0.05, TickSync,
        EbonBuilds.Scheduler.INTERACTIVE, true)

    -- Join and hide the sync channel
    syncChannelIndex = FindSyncChannel() or JoinChannelByName(SYNC_CHANNEL)
    if syncChannelIndex and syncChannelIndex > 0 then
        Log("Sync channel at index " .. syncChannelIndex)
        HideChannelFromChat()
    else
        Log("Sync channel not found — join with /join " .. SYNC_CHANNEL)
    end

    EbonBuildsDB.lastSyncDate = EbonBuildsDB.lastSyncDate or nil
    EbonBuildsDB.syncPeers    = EbonBuildsDB.syncPeers    or {}

    -- Purge remote builds from older addon versions (only unimported builds)
    local storedVersion = EbonBuildsDB.syncVersion or 0
    if storedVersion < SYNC_VERSION then
        if EbonBuildsDB.remoteBuilds and next(EbonBuildsDB.remoteBuilds) then
            EbonBuildsDB.remoteBuilds = {}
            Log("Sync version bumped to " .. SYNC_VERSION .. " — remote builds purged.")
        end
        EbonBuildsDB.syncVersion = SYNC_VERSION
    end
end

SLASH_EBBSYNC1 = "/ebbsync"
SlashCmdList["EBBSYNC"] = function(cmd)
    cmd = strtrim(cmd or "")
    if cmd == "join" then
        CommandLog("To enable sync discovery, type: /join " .. SYNC_CHANNEL)
        CommandLog("After joining, reload with /reload or click Reload on Public Builds.")
    elseif cmd == "status" then
        RefreshChannel()
        if syncChannelIndex and syncChannelIndex > 0 then
            local name = GetChannelName(syncChannelIndex)
            CommandLog("Sync channel: index=" .. syncChannelIndex .. " name=" .. tostring(name))
        else
            CommandLog("Sync channel not joined. Type /ebbsync join for help.")
        end
    elseif cmd == "reset" then
        lastRequestTime = 0
        EbonBuildsDB.lastSyncDate = nil
        EbonBuildsDB.remoteBuilds = {}
        CommandLog("Sync cooldown and lastSyncDate reset. Remote builds cleared.")
    elseif cmd == "verbose" then
        EbonBuilds.Sync.SetVerboseLogEnabled(not VERBOSE_LOG)
        CommandLog("Verbose logging " .. (VERBOSE_LOG and "enabled" or "disabled") .. ".")
    else
        CommandLog("EbonBuilds Sync commands:")
        CommandLog("  /ebbsync join    - Show how to join the sync channel")
        CommandLog("  /ebbsync status  - Show current sync channel status")
        CommandLog("  /ebbsync reset   - Reset sync cooldown timer")
        CommandLog("  /ebbsync verbose - Toggle verbose logging")
    end
end
