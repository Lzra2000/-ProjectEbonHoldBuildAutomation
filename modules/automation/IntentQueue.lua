local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/IntentQueue.lua
-- Responsibility: client-side WP3 intent queue (one in-flight select/freeze/banish/reroll).
-- Client-side stepping stone for WP3 (#52): one in-flight Autopilot intent
-- (select / freeze / banish / reroll). Blocks duplicates, clears on board
-- identity change, ProjectEbonhold pending-flag drop, or timeout. Full
-- server intent ack (CS/SS) remains future ProjectEbonhold work.

EbonBuilds.AutomationIntentQueue = {}

local M = EbonBuilds.AutomationIntentQueue

local VALID_ACTIONS = {
    select = true,
    freeze = true,
    banish = true,
    reroll = true,
}

local INTENT_TTL = 8

local sequence = 0
local inFlight = nil
local sawServerPending = false

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    return tonumber(GetTime()) or 0
end

local function NormalizeAction(action)
    if action == nil then return nil end
    return string.lower(tostring(action))
end

local function GetServerPending(snapshot)
    if snapshot and snapshot.serverPendingAction ~= nil then
        return snapshot.serverPendingAction
    end
    local api = EbonBuilds.ProjectAPI
    if api and type(api.GetPendingAction) == "function" then
        return api.GetPendingAction()
    end
    return nil
end

function M.GetInFlight()
    return inFlight
end

function M.Clear(reason)
    inFlight = nil
    sawServerPending = false
end

function M.Reset()
    M.Clear("reset")
end

-- Returns none | waiting | board_ack | pending_ack | timeout
function M.PollAck(snapshot)
    if not inFlight then return "none" end

    local now = Now()
    if now - (inFlight.startedAt or 0) > INTENT_TTL then
        M.Clear("timeout")
        return "timeout"
    end

    local identity = snapshot and snapshot.identityFingerprint
    if identity and inFlight.identityFingerprint and identity ~= inFlight.identityFingerprint then
        M.Clear("board_ack")
        return "board_ack"
    end

    local serverPending = GetServerPending(snapshot)
    if serverPending then
        sawServerPending = true
        return "waiting"
    end

    if sawServerPending then
        M.Clear("pending_ack")
        return "pending_ack"
    end

    return "waiting"
end

function M.IsBlocking(snapshot)
    M.PollAck(snapshot)
    return inFlight ~= nil
end

function M.BlockReason()
    if not inFlight then return nil end
    return "intent_in_flight:" .. tostring(inFlight.action)
end

function M.DescribeBlock(code)
    local messages = {
        invalid_action = "Invalid autopilot intent",
        duplicate_intent = "Duplicate intent blocked (same action already in flight)",
        intent_in_flight = "Another intent is already in flight",
        server_pending_select = "ProjectEbonhold select request in flight",
        server_pending_banish = "ProjectEbonhold banish request in flight",
        server_pending_freeze = "ProjectEbonhold freeze request in flight",
        server_pending_reroll = "ProjectEbonhold reroll request in flight",
        server_pending_slot = "ProjectEbonhold build-slot request in flight",
        constraints_stale = "Autopilot prefs changed mid-board; intent cleared",
    }
    return messages[code] or ("Intent blocked: " .. tostring(code))
end

-- Returns accepted, intentIdOrReasonCode
function M.TryBegin(action, snapshot)
    action = NormalizeAction(action)
    if not VALID_ACTIONS[action] then
        return false, "invalid_action"
    end

    M.PollAck(snapshot)

    if inFlight then
        local constraintsHash = snapshot and snapshot.constraintsHash
        if constraintsHash and inFlight.constraintsHash
            and constraintsHash ~= inFlight.constraintsHash then
            M.Clear("constraints_stale")
        elseif inFlight.action == action then
            return false, "duplicate_intent"
        else
            return false, "intent_in_flight"
        end
    end

    local serverPending = GetServerPending(snapshot)
    if serverPending then
        if serverPending == "slot" then
            return false, "server_pending_slot"
        end
        return false, "server_pending_" .. tostring(serverPending)
    end

    sequence = sequence + 1
    inFlight = {
        id = sequence,
        action = action,
        offerId = snapshot and snapshot.offerId,
        identityFingerprint = snapshot and snapshot.identityFingerprint,
        targetSlot = snapshot and snapshot.targetSlot,
        constraintsHash = snapshot and snapshot.constraintsHash,
        startedAt = Now(),
    }
    sawServerPending = false
    return true, inFlight.id
end

function M.BuildSnapshot(board, target)
    return {
        offerId = board and board.offerId,
        identityFingerprint = board and board.identityFingerprint,
        targetSlot = target and target.index,
        serverPendingAction = board and board.serverPendingAction,
        pendingAction = board and board.pendingAction,
        constraintsHash = board and board.constraintsHash,
    }
end
