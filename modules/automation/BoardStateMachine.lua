local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/BoardStateMachine.lua
-- Responsibility: derive the WP1 board lifecycle (OPEN / FROZEN_PENDING /
-- CONFIRMED / SPENT) from observable ProjectEbonhold + Autopilot signals until
-- the server publishes authoritative boardState (issue #50).

EbonBuilds.AutomationBoardStateMachine = {}

local M = EbonBuilds.AutomationBoardStateMachine

M.STATE = {
    OPEN = "OPEN",
    FROZEN_PENDING = "FROZEN_PENDING",
    CONFIRMED = "CONFIRMED",
    SPENT = "SPENT",
}

M.REASON = {
    SERVER = "server_authoritative",
    NO_BOARD = "no_visible_board",
    AFTER_SELECT = "board_spent_after_select",
    FREEZE_IN_FLIGHT = "freeze_lock_pending",
    FREEZE_UNCERTAIN = "freeze_lock_uncertain",
    FREEZE_CONFIRMED = "freeze_lock_confirmed",
    FRESH_BOARD = "board_open",
}

local VALID_STATES = {
    [M.STATE.OPEN] = true,
    [M.STATE.FROZEN_PENDING] = true,
    [M.STATE.CONFIRMED] = true,
    [M.STATE.SPENT] = true,
}

local function EchoKey(slot)
    if not slot then return nil end
    return tonumber(slot.spellId) or slot.echoId or slot.refKey
end

local function ChoiceEchoKey(choice)
    if not choice then return nil end
    return tonumber(choice.spellId)
end

local function HasConfirmedFreezeOnBoard(snapshot)
    if (tonumber(snapshot.frozenCount) or 0) > 0 then return true end

    for _, choice in ipairs(snapshot.choices or {}) do
        if choice and (choice.isFrozen or choice.justFrozen) then return true end
    end
    for _, slot in ipairs(snapshot.slots or {}) do
        if slot and slot.isFrozen then return true end
    end

    local runFrozen = snapshot.runFrozenEchoIDs
    if type(runFrozen) ~= "table" then return false end
    for _, choice in ipairs(snapshot.choices or {}) do
        local key = ChoiceEchoKey(choice)
        if key ~= nil and runFrozen[key] then return true end
    end
    for _, slot in ipairs(snapshot.slots or {}) do
        local key = EchoKey(slot)
        if key ~= nil and runFrozen[key] then return true end
    end

    if type(snapshot.frozenThisBoardBySlot) == "table" then
        for _, marked in pairs(snapshot.frozenThisBoardBySlot) do
            if marked then return true end
        end
    end
    if type(snapshot.frozenThisBoardEchoIDs) == "table" then
        for _, marked in pairs(snapshot.frozenThisBoardEchoIDs) do
            if marked then return true end
        end
    end
    return false
end

local function IsFreezePending(snapshot)
    if snapshot.pendingFreezeSlot ~= nil then return true, M.REASON.FREEZE_IN_FLIGHT end
    if snapshot.frozenStateUncertain then return true, M.REASON.FREEZE_UNCERTAIN end
    if snapshot.pendingAction == "freeze" then return true, M.REASON.FREEZE_IN_FLIGHT end
    if snapshot.serverPendingAction == "freeze" then return true, M.REASON.FREEZE_IN_FLIGHT end
    return false
end

local function BoardVisible(snapshot)
    if snapshot.boardVisible == false then return false end
    if type(snapshot.choices) == "table" and #snapshot.choices > 0 then return true end
    if type(snapshot.slots) == "table" and #snapshot.slots > 0 then return true end
    return false
end

function M.IsValidState(state)
    return VALID_STATES[state] == true
end

function M.IsRerollBlocked(state)
    return state == M.STATE.FROZEN_PENDING
        or state == M.STATE.CONFIRMED
        or state == M.STATE.SPENT
end

function M.RerollBlockReason(state, reasonCode)
    if state == M.STATE.FROZEN_PENDING then
        return reasonCode or M.REASON.FREEZE_IN_FLIGHT
    end
    if state == M.STATE.CONFIRMED then
        return M.REASON.FREEZE_CONFIRMED
    end
    if state == M.STATE.SPENT then
        return M.REASON.AFTER_SELECT
    end
    return nil
end

function M.RerollBlockMessage(state, reasonCode)
    local code = M.RerollBlockReason(state, reasonCode)
    if not code then return nil end
    if code == M.REASON.FREEZE_IN_FLIGHT or code == M.REASON.FREEZE_UNCERTAIN then
        return "reroll blocked: freeze confirmation is pending"
    end
    if code == M.REASON.FREEZE_CONFIRMED then
        return "reroll blocked: board has a confirmed freeze"
    end
    if code == M.REASON.AFTER_SELECT then
        return "reroll blocked: board is spent"
    end
    return "reroll blocked: " .. tostring(code)
end

function M.Derive(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}

    local serverState = snapshot.serverBoardState or snapshot.boardState
    if M.IsValidState(serverState) then
        return serverState, M.REASON.SERVER, "server"
    end

    if not BoardVisible(snapshot) then
        if snapshot.pendingAction == "select" or snapshot.serverPendingAction == "select" then
            return M.STATE.SPENT, M.REASON.AFTER_SELECT, "derived"
        end
        return M.STATE.OPEN, M.REASON.NO_BOARD, "derived"
    end

    local pending, pendingReason = IsFreezePending(snapshot)
    if pending then
        return M.STATE.FROZEN_PENDING, pendingReason, "derived"
    end

    if HasConfirmedFreezeOnBoard(snapshot) then
        return M.STATE.CONFIRMED, M.REASON.FREEZE_CONFIRMED, "derived"
    end

    return M.STATE.OPEN, M.REASON.FRESH_BOARD, "derived"
end

function M.Attach(board, snapshot)
    if type(board) ~= "table" then return nil end
    local state, reasonCode, source = M.Derive(snapshot)
    board.lifecycleState = state
    board.lifecycleReasonCode = reasonCode
    board.lifecycleSource = source
    board.boardState = state
    board.boardStateReasonCode = reasonCode
    return state, reasonCode, source
end
