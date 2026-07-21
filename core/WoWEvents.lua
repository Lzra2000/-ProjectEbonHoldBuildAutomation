local addonName, EbonBuilds = ...

-- EbonBuilds: core/WoWEvents.lua
-- One Blizzard-event frame with stable listener mutation. Event dispatch does
-- not allocate tables and never removes array entries while iterating.

EbonBuilds.WoWEvents = {}
local Router = EbonBuilds.WoWEvents
local frame = CreateFrame("Frame")
local buckets = {}
local activeCounts = {}
local dispatchDepth = 0
local compactPending = false

local function Report(eventName, owner, err)
    local log = EbonBuilds.ErrorLog
    if log and type(log.Record) == "function" then
        log.Record("WoWEvents." .. tostring(eventName) .. "." .. tostring(owner or "anonymous"), err)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444EbonBuilds event error:|r " .. tostring(eventName) .. ": " .. tostring(err))
    end
end

local function Compact()
    if dispatchDepth > 0 then compactPending = true; return end
    compactPending = false
    for eventName, bucket in pairs(buckets) do
        local write = 1
        for read = 1, #bucket do
            local record = bucket[read]
            if record and record.active then
                if write ~= read then bucket[write] = record end
                write = write + 1
            end
        end
        for index = #bucket, write, -1 do bucket[index] = nil end
        if (activeCounts[eventName] or 0) == 0 then
            buckets[eventName] = nil
            activeCounts[eventName] = nil
            if frame.UnregisterEvent then frame:UnregisterEvent(eventName) end
        end
    end
end

-- fast: skip pcall entirely for performance-critical handlers (no error
-- isolation -- use only where that trade-off is deliberate).
-- spamExempt: pass true for a listener that's legitimately expected to
-- fire very often by design (e.g. CHAT_MSG_ADDON during heavy sync with
-- many nearby players) -- same reasoning and the same underlying counter
-- as core/Debug.lua's ProtectScript(frame, source, spamExempt).
function Router.On(eventName, callback, owner, fast, spamExempt)
    if type(eventName) ~= "string" or type(callback) ~= "function" then return nil end
    local bucket = buckets[eventName]
    if not bucket then
        bucket = {}
        buckets[eventName] = bucket
        activeCounts[eventName] = 0
        frame:RegisterEvent(eventName)
    end
    local record = {
        event = eventName,
        callback = callback,
        owner = owner,
        fast = fast == true,
        spamExempt = spamExempt == true,
        active = true,
    }
    bucket[#bucket + 1] = record
    activeCounts[eventName] = activeCounts[eventName] + 1
    return record
end

function Router.Off(token)
    if type(token) ~= "table" or not token.active then return false end
    token.active = false
    local eventName = token.event
    activeCounts[eventName] = math.max(0, (activeCounts[eventName] or 1) - 1)
    if dispatchDepth > 0 then compactPending = true else Compact() end
    return true
end

function Router.OffOwner(owner)
    if owner == nil then return 0 end
    local removed = 0
    for _, bucket in pairs(buckets) do
        for index = 1, #bucket do
            local record = bucket[index]
            if record and record.active and record.owner == owner then
                record.active = false
                activeCounts[record.event] = math.max(0, (activeCounts[record.event] or 1) - 1)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        if dispatchDepth > 0 then compactPending = true else Compact() end
    end
    return removed
end

-- Same spam threshold/window as core/Debug.lua's ProtectScript -- one
-- shared definition of "too often" (EbonBuilds.Debug.CheckSpam), not two
-- independently-tuned copies that could quietly drift apart.
local function CheckListenerSpam(eventName, record)
    if record.spamExempt or not EbonBuilds.Debug or not EbonBuilds.Debug.CheckSpam then return end
    -- Keyed per-registration (tostring(record) is unique per listener),
    -- not just per event+owner -- two listeners on the same event from the
    -- same module must not share a counter, same reasoning as ProtectScript
    -- keying per-frame instead of per-source-string.
    local key = tostring(record) .. "." .. eventName
    if EbonBuilds.Debug.CheckSpam(key) then
        Report(eventName .. ".spam", record.owner,
            "fired 120+ times within 1 second -- check event registration scope")
    end
end

function Router.EmitForTests(eventName, ...)
    local bucket = buckets[eventName]
    if not bucket then return true end
    dispatchDepth = dispatchDepth + 1
    local count = #bucket
    for index = 1, count do
        local record = bucket[index]
        if record and record.active then
            CheckListenerSpam(eventName, record)
            if record.fast then
                record.callback(eventName, ...)
            else
                local ok, err = pcall(record.callback, eventName, ...)
                if not ok then Report(eventName, record.owner, err) end
            end
        end
    end
    dispatchDepth = dispatchDepth - 1
    if dispatchDepth == 0 and compactPending then Compact() end
    return true
end

frame:SetScript("OnEvent", function(_, eventName, ...)
    Router.EmitForTests(eventName, ...)
end)

Router.On("ADDON_LOADED", function(_, loadedName)
    if loadedName == addonName and type(EbonBuilds.Start) == "function" then
        EbonBuilds.Start()
    end
end, "Bootstrap")
