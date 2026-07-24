local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/BoardDecision.lua
-- Responsibility: choose one deterministic freeze-first action from an already
-- scored Echo board without performing I/O or recalculating Echo values.

EbonBuilds.AutomationBoardDecision = {}

local D = EbonBuilds.AutomationBoardDecision

D.MAX_FROZEN_PER_BOARD = 2
D.STATE = {
    IDLE = "IDLE",
    WAITING_FOR_BOARD = "WAITING_FOR_BOARD",
    EVALUATING = "EVALUATING",
    REQUESTING_FREEZE = "REQUESTING_FREEZE",
    WAITING_FOR_FREEZE_CONFIRMATION = "WAITING_FOR_FREEZE_CONFIRMATION",
    SELECTING = "SELECTING",
    REROLLING = "REROLLING",
    BANISHING = "BANISHING",
    WAITING_FOR_BOARD_UPDATE = "WAITING_FOR_BOARD_UPDATE",
    RECOVERY = "RECOVERY",
}

local function IsBetter(a, b)
    if not a then return false end
    if not b then return true end
    local aScore = tonumber(a.score) or 0
    local bScore = tonumber(b.score) or 0
    if aScore ~= bScore then return aScore > bScore end
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
end

local function IsWorse(a, b)
    if not a then return false end
    if not b then return true end
    local aScore = tonumber(a.score) or 0
    local bScore = tonumber(b.score) or 0
    if aScore ~= bScore then return aScore < bScore end
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
end

local function EchoKey(slot)
    if not slot then return nil end
    return tonumber(slot.spellId) or slot.echoId or slot.refKey
end

local function IsAvoided(slot)
    return slot and (slot.isAvoided or slot.isBanned or slot.policyBlocked
        or slot.policyEffect == "banish" or slot.policyEffect == "exclude") and true or false
end

local function WasFrozenThisBoard(board, slot)
    if not board or not slot then return false end
    local index = tonumber(slot.index)
    local key = EchoKey(slot)
    return (index ~= nil and board.frozenThisBoardBySlot
            and board.frozenThisBoardBySlot[index])
        or (key ~= nil and board.frozenThisBoardEchoIDs
            and board.frozenThisBoardEchoIDs[key])
        or false
end

local function IsValuable(slot, threshold)
    if not slot or slot.isValid == false or IsAvoided(slot) then return false end
    if slot.isLocked or slot.preserve or slot.isCrucial
        or slot.policyPreserve or slot.priorityPreserve then
        return true
    end
    return tonumber(slot.score) ~= nil and tonumber(slot.score) >= (tonumber(threshold) or math.huge)
end

local function IsLegalSelection(slot, board)
    -- A carried Echo is a real choice on the next board. Only an Echo frozen
    -- during the current board is withheld so Freeze -> Select can never target
    -- the same Echo in one turn.
    return slot and slot.isValid ~= false and not IsAvoided(slot)
        and not WasFrozenThisBoard(board, slot)
end

local function RequiresPreservation(slot, threshold)
    -- A guaranteed card (injected from the active ProjectEbonhold build slot)
    -- reappears in every draw and the server refuses to freeze it, so it never
    -- needs a freeze charge.
    if not slot or slot.isFrozen or slot.isCarried or slot.isGuaranteed then return false end
    return IsValuable(slot, threshold)
end

function D.Fingerprint(board)
    if type(board) ~= "table" or type(board.slots) ~= "table" then return nil end
    local parts = {}
    for i, slot in ipairs(board.slots) do
        local id = EchoKey(slot)
        parts[#parts + 1] = tostring(tonumber(slot.index) or i)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = tostring(id or "?")
        parts[#parts + 1] = slot.isFrozen and "F" or "U"
        parts[#parts + 1] = slot.isCarried and "C" or "-"
        parts[#parts + 1] = ";"
    end
    if board.offerId ~= nil then
        parts[#parts + 1] = "#"
        parts[#parts + 1] = tostring(board.offerId)
    end
    return table.concat(parts)
end

function D.IdentityFingerprint(board)
    if type(board) ~= "table" or type(board.slots) ~= "table" then return nil end
    local parts = {}
    for i, slot in ipairs(board.slots) do
        parts[#parts + 1] = tostring(tonumber(slot.index) or i)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = tostring(EchoKey(slot) or "?")
        parts[#parts + 1] = ";"
    end
    if board.offerId ~= nil then
        parts[#parts + 1] = "#"
        parts[#parts + 1] = tostring(board.offerId)
    end
    return table.concat(parts)
end

function D.MatchesFingerprint(board, evaluatedFingerprint)
    return evaluatedFingerprint ~= nil and D.Fingerprint(board) == evaluatedFingerprint
end

function D.ClassifyPendingFreeze(board, pendingSlot, pendingEchoID, pendingIdentity)
    if not pendingSlot then return "none" end
    for _, slot in ipairs(board.slots or {}) do
        if slot.index == pendingSlot and EchoKey(slot) == pendingEchoID
            and (slot.isFrozen or slot.isCarried) then
            return "confirmed", slot
        end
    end
    if pendingIdentity and D.IdentityFingerprint(board) ~= pendingIdentity then return "board_changed" end
    return "waiting"
end

local function IsRunFrozenEcho(board, slot)
    if not board or not slot then return false end
    local key = EchoKey(slot)
    -- boardState.frozenEchoIDs is run-persistent and survives board-identity
    -- changes. Servers that omit isFrozen/isCarried still block rerolls when
    -- the client previously accepted or confirmed a freeze for this Echo.
    return key ~= nil and board.runFrozenEchoIDs and board.runFrozenEchoIDs[key] and true or false
end

function D.RefreshFrozenState(board)
    board.frozenCount = 0
    board.frozenBySlot = board.frozenBySlot or {}
    board.frozenEchoIDs = board.frozenEchoIDs or {}
    for key in pairs(board.frozenBySlot) do board.frozenBySlot[key] = nil end
    for key in pairs(board.frozenEchoIDs) do board.frozenEchoIDs[key] = nil end

    for i, slot in ipairs(board.slots or {}) do
        local index = tonumber(slot.index) or i
        local key = EchoKey(slot)
        if slot.isFrozen or slot.isCarried or WasFrozenThisBoard(board, slot)
            or IsRunFrozenEcho(board, slot) then
            board.frozenCount = board.frozenCount + 1
            board.frozenBySlot[index] = true
            if key ~= nil then board.frozenEchoIDs[key] = true end
        end
    end
    return board.frozenCount
end

function D.FindBestLegalPick(board)
    local best
    for _, slot in ipairs(board.slots or {}) do
        if IsLegalSelection(slot, board) and IsBetter(slot, best) then best = slot end
    end
    return best
end

function D.FindBestFreezeCandidate(board, selectionTarget)
    local maxFrozen = tonumber(board.maxFrozen) or D.MAX_FROZEN_PER_BOARD
    local frozenCount = tonumber(board.frozenCount) or 0
    if frozenCount >= maxFrozen or (tonumber(board.freezeResources) or 0) <= 0 then return nil end
    -- Freezing is useful only when the intended pick is valuable too. This
    -- prevents spending a freeze to preserve the board's sole valuable Echo
    -- while selecting an ordinary one. Protection is intentionally absent:
    -- it only shields an Echo/family from banish logic.
    if not IsValuable(selectionTarget, board.freezeThreshold) then return nil end

    local selectedKey = EchoKey(selectionTarget)
    local best
    for _, slot in ipairs(board.slots or {}) do
        local key = EchoKey(slot)
        local isSelection = selectionTarget and slot.index == selectionTarget.index
        local duplicate = key ~= nil and ((board.frozenEchoIDs and board.frozenEchoIDs[key])
            or (selectedKey ~= nil and key == selectedKey))
        local failed = board.failedFreezeBySlot and board.failedFreezeBySlot[slot.index]
        if not isSelection and not duplicate and not failed and not WasFrozenThisBoard(board, slot)
            and RequiresPreservation(slot, board.freezeThreshold) and IsBetter(slot, best) then
            best = slot
        end
    end
    return best
end

function D.FindBanishTarget(board)
    if (tonumber(board.frozenCount) or 0) > 0 or not board.canBanish then return nil end
    local worst
    for _, slot in ipairs(board.slots or {}) do
        -- isGuaranteed: the server refuses to banish the active build slot's
        -- injected card; skipping it avoids a wasted request and recovery pause.
        if slot and slot.isValid ~= false and not slot.isFrozen and not slot.isCarried
            and not slot.isGuaranteed
            and (slot.policyEffect == "banish" or slot.isBanned or slot.banishEligible)
            and not (slot.isProtected and slot.policyEffect ~= "banish")
            and IsWorse(slot, worst) then
            worst = slot
        end
    end
    return worst
end

function D.HasUnsecuredFreezeCandidate(board, selectionTarget)
    return D.FindBestFreezeCandidate(board, selectionTarget) ~= nil
end

function D.CanReroll(board)
    if (tonumber(board.frozenCount) or 0) > 0 then return false, "board contains a frozen Echo" end
    if board.pendingFreezeSlot then return false, "freeze confirmation is pending" end
    if board.pendingAction then return false, "another board action is pending" end
    if board.frozenStateUncertain then return false, "frozen state is uncertain" end
    if not board.isStable or not board.isValid then return false, "board is not stable and fully resolved" end
    if D.HasUnsecuredFreezeCandidate(board, D.FindBestLegalPick(board)) then
        return false, "a qualifying Echo still requires freezing"
    end
    if D.FindBestLegalPick(board) and board.pickIsAcceptable ~= false then
        return false, "an acceptable direct pick exists"
    end
    if not board.canReroll then return false, "no reroll resource is available" end
    return true
end

function D.Decide(board)
    if type(board) ~= "table" or not board.isValid then
        return { action = "RECOVERY", reason = "board validation failed" }
    end
    if not board.isStable then return { action = "WAIT", reason = "board is not stable" } end

    D.RefreshFrozenState(board)

    if board.pendingAction then
        return { action = "WAIT", reason = "another board action is pending" }
    end
    if board.pendingFreezeSlot then
        return { action = "WAIT_FOR_FREEZE", reason = "freeze confirmation is pending" }
    end
    if board.frozenStateUncertain then
        return { action = "RECOVERY", reason = "frozen state is uncertain" }
    end

    local selectionTarget = D.FindBestLegalPick(board)
    local freezeTarget = D.FindBestFreezeCandidate(board, selectionTarget)
    if freezeTarget then
        return {
            action = "FREEZE",
            target = freezeTarget,
            selectionTarget = selectionTarget,
            reason = "freeze actions take priority over selection",
        }
    end
    if selectionTarget and (board.pickIsAcceptable ~= false or board.frozenCount > 0
        or (not board.canReroll and not board.canBanish)) then
        return {
            action = "SELECT",
            target = selectionTarget,
            selectionTarget = selectionTarget,
            reason = "no unsecured freeze candidate remains",
        }
    end

    if board.frozenCount > 0 then
        return { action = "RECOVERY", reason = "no legal unfrozen selection exists on a frozen board" }
    end

    local banishTarget = D.FindBanishTarget(board)
    if banishTarget then
        return { action = "BANISH", target = banishTarget, reason = "no acceptable pick; avoided Echo can be banished" }
    end

    local canReroll, rerollReason = D.CanReroll(board)
    if canReroll then return { action = "REROLL", reason = "no acceptable direct pick or freeze candidate" } end
    if selectionTarget then
        return {
            action = "SELECT",
            target = selectionTarget,
            selectionTarget = selectionTarget,
            reason = "reroll is unavailable; selecting the best legal Echo",
        }
    end
    return { action = "RECOVERY", reason = rerollReason or "no safe automatic action exists" }
end

D._IsLegalSelection = IsLegalSelection
D._IsValuable = IsValuable
D._RequiresPreservation = RequiresPreservation
D._WasFrozenThisBoard = WasFrozenThisBoard
D._IsRunFrozenEcho = IsRunFrozenEcho
