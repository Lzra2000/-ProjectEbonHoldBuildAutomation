local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/VirtualList.lua
-- Shared fixed-row virtualization helpers for WoW 3.3.5a. Feature modules
-- own their row visuals; this utility centralizes viewport math and recycled
-- row binding without allocating during wheel movement.

EbonBuilds.VirtualList = {}

local VirtualList = EbonBuilds.VirtualList

function VirtualList.VisibleCount(viewportHeight, rowHeight, poolSize)
    rowHeight = math.max(1, tonumber(rowHeight) or 1)
    poolSize = math.max(1, math.floor(tonumber(poolSize) or 1))
    local height = math.max(rowHeight, tonumber(viewportHeight) or rowHeight)
    return math.max(1, math.min(poolSize, math.floor(height / rowHeight)))
end

function VirtualList.ClampOffset(itemCount, visibleCount, offset)
    itemCount = math.max(0, math.floor(tonumber(itemCount) or 0))
    visibleCount = math.max(1, math.floor(tonumber(visibleCount) or 1))
    local maxOffset = math.max(0, itemCount - visibleCount)
    offset = math.max(0, math.min(maxOffset, math.floor(tonumber(offset) or 0)))
    return offset, maxOffset
end

function VirtualList.BindRows(rows, data, offset, visibleCount, bindRow, resetRow)
    if type(rows) ~= "table" or type(data) ~= "table" then return end
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    visibleCount = math.max(1, math.floor(tonumber(visibleCount) or #rows))
    for poolIndex, row in ipairs(rows) do
        local item = poolIndex <= visibleCount and data[offset + poolIndex] or nil
        if item ~= nil then
            bindRow(row, item, poolIndex, offset + poolIndex)
        elseif resetRow then
            resetRow(row, poolIndex)
        elseif row and row.Hide then
            row:Hide()
        end
    end
end
