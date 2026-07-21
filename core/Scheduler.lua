local addonName, EbonBuilds = ...

-- EbonBuilds: core/Scheduler.lua
-- Shared time-sliced execution kernel for callbacks, repeating work,
-- coroutine migrations, and combat-deferred jobs.

EbonBuilds.Scheduler = {}
local Scheduler = EbonBuilds.Scheduler

local CRITICAL, INTERACTIVE, BACKGROUND, MAINTENANCE = 1, 2, 3, 4
Scheduler.CRITICAL = CRITICAL
Scheduler.INTERACTIVE = INTERACTIVE
Scheduler.BACKGROUND = BACKGROUND
Scheduler.MAINTENANCE = MAINTENANCE

local frame = CreateFrame("Frame")
if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
    EbonBuilds.Debug.ProtectScript(frame, "Scheduler.Frame")
end
frame:Hide()

local jobsById = {}
local heap = {}
local heapCount = 0
local ready = {
    { head = 1, tail = 0 },
    { head = 1, tail = 0 },
    { head = 1, tail = 0 },
    { head = 1, tail = 0 },
}
local parkedHead, parkedTail
local pool = {}
local poolCount = 0
local jobCount = 0
local serial = 0
local runningJob

local DEFAULT_BUDGET = {
    [CRITICAL] = 0.80,
    [INTERACTIVE] = 1.00,
    [BACKGROUND] = 1.25,
    [MAINTENANCE] = 0.75,
}

local function Now()
    return GetTime and GetTime() or 0
end

local function ProfileNow()
    return debugprofilestop and debugprofilestop() or (Now() * 1000)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Report(id, err)
    local log = EbonBuilds.ErrorLog
    if log and type(log.Record) == "function" then
        log.Record("Scheduler." .. tostring(id), err)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444EbonBuilds scheduler error:|r " .. tostring(id) .. ": " .. tostring(err))
    end
end

local function Acquire()
    local job
    if poolCount > 0 then
        job = pool[poolCount]
        pool[poolCount] = nil
        poolCount = poolCount - 1
    else
        job = {}
    end
    return job
end

local function Release(job)
    job.id = nil
    job.callback = nil
    job.thread = nil
    job.interval = nil
    job.allowCombat = nil
    job.priority = nil
    job.due = nil
    job.lastRun = nil
    job.heapIndex = nil
    job.next = nil
    job.state = nil
    job.owner = nil
    job.serial = nil
    poolCount = poolCount + 1
    pool[poolCount] = job
end

local function Less(a, b)
    if a.due == b.due then return a.serial < b.serial end
    return a.due < b.due
end

local function HeapSwap(a, b)
    local left, right = heap[a], heap[b]
    heap[a], heap[b] = right, left
    right.heapIndex, left.heapIndex = a, b
end

local function HeapUp(index)
    while index > 1 do
        local parent = math.floor(index / 2)
        if not Less(heap[index], heap[parent]) then break end
        HeapSwap(index, parent)
        index = parent
    end
end

local function HeapDown(index)
    while true do
        local left = index * 2
        if left > heapCount then break end
        local right = left + 1
        local smallest = left
        if right <= heapCount and Less(heap[right], heap[left]) then smallest = right end
        if not Less(heap[smallest], heap[index]) then break end
        HeapSwap(index, smallest)
        index = smallest
    end
end

local function HeapPush(job)
    heapCount = heapCount + 1
    heap[heapCount] = job
    job.heapIndex = heapCount
    job.state = "delayed"
    HeapUp(heapCount)
end

local function HeapRemoveAt(index)
    local removed = heap[index]
    local last = heap[heapCount]
    heap[heapCount] = nil
    heapCount = heapCount - 1
    if index <= heapCount then
        heap[index] = last
        last.heapIndex = index
        HeapDown(index)
        HeapUp(index)
    end
    removed.heapIndex = nil
    return removed
end

local function HeapPop()
    if heapCount == 0 then return nil end
    return HeapRemoveAt(1)
end

local function ReadyPush(job)
    local queue = ready[job.priority]
    queue.tail = queue.tail + 1
    queue[queue.tail] = job
    job.state = "ready"
end

local function ReadyPop(priority)
    local queue = ready[priority]
    if queue.head > queue.tail then return nil end
    local job = queue[queue.head]
    queue[queue.head] = nil
    queue.head = queue.head + 1
    if queue.head > queue.tail then
        queue.head, queue.tail = 1, 0
    end
    return job
end

local function Park(job)
    job.state = "parked"
    job.next = nil
    if parkedTail then parkedTail.next = job else parkedHead = job end
    parkedTail = job
end

local function HasRunnableWork()
    if heapCount > 0 then return true end
    for priority = CRITICAL, MAINTENANCE do
        local queue = ready[priority]
        if queue.head <= queue.tail then return true end
    end
    return false
end

local function ActivateFrame()
    -- Parked combat jobs are event-driven. They must not keep an OnUpdate
    -- script running while combat is active and no runnable work exists.
    if HasRunnableWork() then frame:Show() else frame:Hide() end
end

local function Detach(job)
    if job.state == "delayed" and job.heapIndex then
        HeapRemoveAt(job.heapIndex)
    elseif job.state == "ready" then
        -- Ready queues use tombstones: cancellation invalidates jobsById and
        -- the queued object is released when popped.
    elseif job.state == "parked" then
        -- Parked list also uses tombstones and is compacted on wake.
    end
    job.state = "cancelled"
end

function Scheduler.Cancel(id)
    local job = jobsById[id]
    if not job then return false end
    jobsById[id] = nil
    jobCount = math.max(0, jobCount - 1)
    local previousState = job.state
    Detach(job)
    -- Delayed jobs are physically removed from the heap and can be returned
    -- immediately. Ready and parked queues use tombstones, so their records
    -- remain alive until the queue reaches them.
    if job ~= runningJob and previousState == "delayed" then Release(job) end
    ActivateFrame()
    return true
end

local function NormalizePriority(priority)
    priority = tonumber(priority) or BACKGROUND
    if priority < CRITICAL then return CRITICAL end
    if priority > MAINTENANCE then return MAINTENANCE end
    return math.floor(priority)
end

local function ScheduleRecord(id, delay, priority, interval, allowCombat, callback, thread, owner)
    if type(id) ~= "string" or id == "" then return false end
    if callback == nil and thread == nil then return false end
    Scheduler.Cancel(id)

    serial = serial + 1
    local now = Now()
    local job = Acquire()
    job.id = id
    job.callback = callback
    job.thread = thread
    job.interval = interval
    job.allowCombat = allowCombat == true
    job.priority = NormalizePriority(priority)
    job.due = now + math.max(0, tonumber(delay) or 0)
    job.lastRun = now
    job.owner = owner
    job.serial = serial
    jobsById[id] = job
    jobCount = jobCount + 1
    HeapPush(job)
    ActivateFrame()
    return true
end

function Scheduler.Schedule(id, delay, callback, priority, interval, allowCombat, owner)
    if type(callback) ~= "function" then return false end
    interval = interval and math.max(0.05, tonumber(interval) or 1) or nil
    return ScheduleRecord(id, delay, priority, interval, allowCombat, callback, nil, owner)
end

function Scheduler.After(id, delay, callback, priority, allowCombat, owner)
    return Scheduler.Schedule(id, delay, callback, priority, nil, allowCombat, owner)
end

function Scheduler.Every(id, interval, callback, priority, allowCombat, owner)
    interval = math.max(0.05, tonumber(interval) or 1)
    return Scheduler.Schedule(id, interval, callback, priority, interval, allowCombat, owner)
end

function Scheduler.Coroutine(id, threadOrFactory, priority, allowCombat, owner)
    local thread = threadOrFactory
    if type(threadOrFactory) == "function" then thread = coroutine.create(threadOrFactory) end
    if type(thread) ~= "thread" then return false end
    return ScheduleRecord(id, 0, priority, nil, allowCombat, nil, thread, owner)
end

function Scheduler.Has(id)
    return jobsById[id] ~= nil
end

function Scheduler.Count()
    return jobCount
end

function Scheduler.CancelOwner(owner)
    local removed = 0
    for id, job in pairs(jobsById) do
        if job.owner == owner and Scheduler.Cancel(id) then removed = removed + 1 end
    end
    return removed
end

function Scheduler.SetBudget(priority, milliseconds)
    priority = NormalizePriority(priority)
    DEFAULT_BUDGET[priority] = math.max(0.1, tonumber(milliseconds) or DEFAULT_BUDGET[priority])
end

local function Requeue(job, delay)
    serial = serial + 1
    job.serial = serial
    job.due = Now() + math.max(0, tonumber(delay) or 0)
    jobsById[job.id] = job
    jobCount = jobCount + 1
    HeapPush(job)
end

local function Complete(job, ok, result)
    local id = job.id
    if not ok then Report(id, result) end

    local replacement = jobsById[id]
    if replacement and replacement ~= job then
        Release(job)
        return
    end

    if job.thread then
        if ok and coroutine.status(job.thread) ~= "dead" and result ~= false then
            Requeue(job, tonumber(result) or 0)
        else
            Release(job)
        end
        return
    end

    if ok and job.interval and result ~= false then
        job.lastRun = Now()
        Requeue(job, tonumber(result) or job.interval)
    else
        Release(job)
    end
end

local function Run(job, now)
    if jobsById[job.id] ~= job then
        Release(job)
        return
    end

    jobsById[job.id] = nil
    jobCount = math.max(0, jobCount - 1)
    job.state = "running"
    runningJob = job

    local elapsed = math.max(0, now - (job.lastRun or now))
    local ok, result
    if job.thread then
        ok, result = coroutine.resume(job.thread, elapsed)
    else
        ok, result = pcall(job.callback, elapsed)
    end

    runningJob = nil
    Complete(job, ok, result)
end

local function MoveDue(now)
    while heapCount > 0 do
        local job = heap[1]
        if job.due > now then break end
        HeapPop()
        if jobsById[job.id] == job then ReadyPush(job) else Release(job) end
    end
end

local function RunPriority(priority, combat)
    local started = ProfileNow()
    local budget = DEFAULT_BUDGET[priority]
    while true do
        local job = ReadyPop(priority)
        if not job then break end
        if jobsById[job.id] ~= job then
            Release(job)
        elseif combat and not job.allowCombat then
            Park(job)
        else
            Run(job, Now())
        end
        if ProfileNow() - started >= budget then break end
    end
end

function Scheduler.WakeCombatQueue()
    local job = parkedHead
    parkedHead, parkedTail = nil, nil
    local now = Now()
    while job do
        local nextJob = job.next
        job.next = nil
        if jobsById[job.id] == job then
            job.due = now
            HeapPush(job)
        else
            Release(job)
        end
        job = nextJob
    end
    ActivateFrame()
end

frame:SetScript("OnUpdate", function()
    if not HasRunnableWork() then frame:Hide(); return end
    local now = Now()
    MoveDue(now)
    local combat = InCombat()
    RunPriority(CRITICAL, combat)
    RunPriority(INTERACTIVE, combat)
    RunPriority(BACKGROUND, combat)
    RunPriority(MAINTENANCE, combat)
    ActivateFrame()
end)

if EbonBuilds.WoWEvents then
    EbonBuilds.WoWEvents.On("PLAYER_REGEN_ENABLED", function()
        Scheduler.WakeCombatQueue()
    end, "Scheduler")
end
