local addonName, EbonBuilds = ...

-- EbonBuilds: core/Pool.lua
-- Typed object pool. Repeated acquire/release operations allocate nothing once
-- the pool has warmed. Domain-specific scrub callbacks own reference cleanup.

EbonBuilds.Pool = {}
local Pool = EbonBuilds.Pool

local function ClearTable(value)
    for key in pairs(value) do value[key] = nil end
    return value
end

Pool.ClearTable = ClearTable

function Pool.New(factory, scrub, maximumRetained)
    if type(factory) ~= "function" then return nil end
    local free = {}
    local count = 0
    local maxRetained = math.max(0, tonumber(maximumRetained) or 128)
    local objectPool = {}

    function objectPool:Acquire(...)
        local object
        if count > 0 then
            object = free[count]
            free[count] = nil
            count = count - 1
        else
            object = factory(...)
        end
        if object then object.__ebonPool = objectPool end
        return object
    end

    function objectPool:Release(object)
        if type(object) ~= "table" or object.__ebonPool ~= objectPool then return false end
        if scrub then scrub(object) end
        object.__ebonPool = objectPool
        if count < maxRetained then
            count = count + 1
            free[count] = object
        else
            object.__ebonPool = nil
        end
        return true
    end

    function objectPool:FreeCount()
        return count
    end

    function objectPool:Trim(keep)
        keep = math.max(0, math.min(count, tonumber(keep) or 0))
        for index = count, keep + 1, -1 do
            local object = free[index]
            free[index] = nil
            if object then object.__ebonPool = nil end
        end
        count = keep
    end

    return objectPool
end
