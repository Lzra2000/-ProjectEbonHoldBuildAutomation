local addonName, EbonBuilds = ...

-- EbonBuilds: core/RingBuffer.lua
-- SavedVariables-safe O(1) bounded queue. Legacy arrays migrate in place.

EbonBuilds.RingBuffer = {}

local Ring = EbonBuilds.RingBuffer

function Ring.New(capacity)
    capacity = math.max(1, math.floor(tonumber(capacity) or 1))
    return { __ebRing = 1, capacity = capacity, head = 1, count = 0, values = {} }
end

function Ring.Is(value)
    return type(value) == "table" and value.__ebRing == 1 and type(value.values) == "table"
end

function Ring.Append(ring, value)
    if not Ring.Is(ring) then return false end
    local capacity = ring.capacity
    ring.values[ring.head] = value
    ring.head = ring.head + 1
    if ring.head > capacity then ring.head = 1 end
    if ring.count < capacity then ring.count = ring.count + 1 end
    return true
end

function Ring.Count(ring)
    return Ring.Is(ring) and (tonumber(ring.count) or 0) or 0
end

local function OldestIndex(ring)
    local index = ring.head - Ring.Count(ring)
    while index <= 0 do index = index + ring.capacity end
    return index
end

function Ring.PopOldest(ring)
    if not Ring.Is(ring) or Ring.Count(ring) == 0 then return nil end
    local index = OldestIndex(ring)
    local value = ring.values[index]
    ring.values[index] = nil
    ring.count = ring.count - 1
    return value
end

function Ring.Clear(ring)
    if not Ring.Is(ring) then return false end
    for key in pairs(ring.values) do ring.values[key] = nil end
    ring.head = 1
    ring.count = 0
    return true
end

function Ring.ForEach(ring, callback)
    if not Ring.Is(ring) or type(callback) ~= "function" then return false end
    local count = Ring.Count(ring)
    local index = OldestIndex(ring)
    for ordinal = 1, count do
        if callback(ring.values[index], ordinal) == false then return false end
        index = index + 1
        if index > ring.capacity then index = 1 end
    end
    return true
end

function Ring.RemoveIf(ring, predicate)
    if not Ring.Is(ring) or type(predicate) ~= "function" then return 0 end
    local kept, removed = {}, 0
    Ring.ForEach(ring, function(value)
        if predicate(value) then removed = removed + 1 else kept[#kept + 1] = value end
    end)
    Ring.Clear(ring)
    for _, value in ipairs(kept) do Ring.Append(ring, value) end
    return removed
end

function Ring.ToArray(ring)
    if not Ring.Is(ring) then return {} end
    local out = {}
    local count = Ring.Count(ring)
    local capacity = ring.capacity
    local index = OldestIndex(ring)
    for outIndex = 1, count do
        out[outIndex] = ring.values[index]
        index = index + 1
        if index > capacity then index = 1 end
    end
    return out
end

function Ring.Ensure(value, capacity)
    capacity = math.max(1, math.floor(tonumber(capacity) or 1))
    if Ring.Is(value) then
        value.capacity = capacity
        value.head = math.max(1, math.min(capacity, tonumber(value.head) or 1))
        value.count = math.max(0, math.min(capacity, tonumber(value.count) or 0))
        return value
    end
    local ring = Ring.New(capacity)
    if type(value) == "table" then
        local first = math.max(1, #value - capacity + 1)
        for index = first, #value do Ring.Append(ring, value[index]) end
    end
    return ring
end
