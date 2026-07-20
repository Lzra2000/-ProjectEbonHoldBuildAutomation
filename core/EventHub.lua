-- EbonBuilds: core/EventHub.lua
-- Small dependency-free notification hub. Events pass primitive arguments;
-- callers never allocate an event object just to invalidate a cache.

EbonBuilds.EventHub = {}

local Hub = EbonBuilds.EventHub
local listeners = {}
local revisions = {}
local allowed = {
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
}

local function IsAllowed(eventName)
    return type(eventName) == "string" and allowed[eventName] == true
end

function Hub.On(eventName, callback)
    if not IsAllowed(eventName) or type(callback) ~= "function" then return nil end
    local bucket = listeners[eventName]
    if not bucket then
        bucket = {}
        listeners[eventName] = bucket
    end
    bucket[#bucket + 1] = callback
    return callback
end

function Hub.Off(eventName, callback)
    if not IsAllowed(eventName) then return false end
    local bucket = listeners[eventName]
    if not bucket then return false end
    for index = #bucket, 1, -1 do
        if bucket[index] == callback then
            table.remove(bucket, index)
            return true
        end
    end
    return false
end

local function RecordError(eventName, err)
    if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
        EbonBuilds.ErrorLog.Record("EventHub." .. tostring(eventName), err)
    end
end

function Hub.Emit(eventName, ...)
    if not IsAllowed(eventName) then return false end
    local bucket = listeners[eventName]
    if not bucket then return true end
    -- Capture the length. A callback registered during dispatch starts on the
    -- next emission; this keeps one emission deterministic without cloning.
    local count = #bucket
    for index = 1, count do
        local callback = bucket[index]
        if callback then
            local ok, err = pcall(callback, ...)
            if not ok then RecordError(eventName, err) end
        end
    end
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
