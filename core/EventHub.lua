local addonName, EbonBuilds = ...

-- EbonBuilds: core/EventHub.lua
-- Internal domain signals. Listener arrays are stable during dispatch;
-- unsubscription marks tombstones and compacts only after the outer emission.

EbonBuilds.EventHub = {}
local Hub = EbonBuilds.EventHub
local listeners = {}
local revisions = {}
local dispatchDepth = 0
local compactPending = false

local allowed = {
    CORE_READY = true,
    AUTOMATION_READY = true,
    APP_READY = true,
    ANALYTICS_READY = true,
    DATABASE_MIGRATION_CHANGED = true,
    DATABASE_READY = true,
    ANALYTICS_BACKFILL_COMPLETE = true,
    THEME_CHANGED = true,
    BUILD_LIBRARY_CHANGED = true,
    ACTIVE_BUILD_CHANGED = true,
    BUILD_REVISION_CHANGED = true,
    BUILD_RUNTIME_CHANGED = true,
    RUN_STARTED = true,
    RUN_EVENT_RECORDED = true,
    RUN_ENDED = true,
    RUN_HISTORY_PRUNED = true,
    RUN_STRATEGY_CHANGED = true,
    EVIDENCE_REVISION_CHANGED = true,
    COLLECTION_REVISION_CHANGED = true,
    SYNC_REVISION_CHANGED = true,
    LOCALE_CHANGED = true,
    TUNING_PROPOSAL_APPLIED = true,
    ECHO_CATALOG_READY = true,
    ECHO_CATALOG_CHANGED = true,
    ECHO_RECONCILIATION_FAILED = true,
    ECHO_DIAGNOSTICS_CHANGED = true,
    ECHO_IDENTITY_CHANGED = true,
    ECHO_ELIGIBILITY_CHANGED = true,
    ECHO_PROJECTION_CHANGED = true,
    PROJECT_CHOICE_CHANGED = true,
    PROJECT_ACTION_RESULT = true,
}

local function IsAllowed(eventName)
    return type(eventName) == "string" and allowed[eventName] == true
end

local function RecordError(eventName, owner, err)
    if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
        EbonBuilds.ErrorLog.Record("EventHub." .. tostring(eventName) .. "." .. tostring(owner or "anonymous"), err)
    end
end

local function Compact()
    if dispatchDepth > 0 then compactPending = true; return end
    compactPending = false
    for eventName, bucket in pairs(listeners) do
        local write = 1
        for read = 1, #bucket do
            local record = bucket[read]
            if record and record.active then
                if write ~= read then bucket[write] = record end
                write = write + 1
            end
        end
        for index = #bucket, write, -1 do bucket[index] = nil end
        if #bucket == 0 then listeners[eventName] = nil end
    end
end

function Hub.On(eventName, callback, owner)
    if not IsAllowed(eventName) or type(callback) ~= "function" then return nil end
    local bucket = listeners[eventName]
    if not bucket then bucket = {}; listeners[eventName] = bucket end
    local token = { event = eventName, callback = callback, owner = owner, active = true }
    bucket[#bucket + 1] = token
    return token
end

function Hub.Off(eventNameOrToken, callback)
    if type(eventNameOrToken) == "table" then
        local token = eventNameOrToken
        if not token.active then return false end
        token.active = false
        if dispatchDepth > 0 then compactPending = true else Compact() end
        return true
    end

    local eventName = eventNameOrToken
    if not IsAllowed(eventName) then return false end
    local bucket = listeners[eventName]
    if not bucket then return false end
    for index = #bucket, 1, -1 do
        local token = bucket[index]
        if token and token.active and token.callback == callback then
            token.active = false
            if dispatchDepth > 0 then compactPending = true else Compact() end
            return true
        end
    end
    return false
end

function Hub.OffOwner(owner)
    if owner == nil then return 0 end
    local removed = 0
    for _, bucket in pairs(listeners) do
        for index = 1, #bucket do
            local token = bucket[index]
            if token and token.active and token.owner == owner then
                token.active = false
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        if dispatchDepth > 0 then compactPending = true else Compact() end
    end
    return removed
end

function Hub.Emit(eventName, ...)
    if not IsAllowed(eventName) then return false end
    local bucket = listeners[eventName]
    if not bucket then return true end

    dispatchDepth = dispatchDepth + 1
    local count = #bucket
    for index = 1, count do
        local token = bucket[index]
        if token and token.active then
            local ok, err = pcall(token.callback, ...)
            if not ok then RecordError(eventName, token.owner, err) end
        end
    end
    dispatchDepth = dispatchDepth - 1
    if dispatchDepth == 0 and compactPending then Compact() end
    return true
end

function Hub.Bump(eventName, ...)
    if not IsAllowed(eventName) then return nil end
    revisions[eventName] = (revisions[eventName] or 0) + 1
    Hub.Emit(eventName, revisions[eventName], ...)
    return revisions[eventName]
end

function Hub.Revision(eventName)
    if not IsAllowed(eventName) then return 0 end
    return revisions[eventName] or 0
end

function Hub.IsAllowed(eventName)
    return IsAllowed(eventName)
end
