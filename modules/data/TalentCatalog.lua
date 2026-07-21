local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/TalentCatalog.lua
-- Restores presentation metadata for schema-1 character snapshots. The
-- compact catalog contains only stable 3.3.5a spell IDs and layout facts;
-- localized names and native icon paths come from the client's GetSpellInfo.

EbonBuilds.TalentCatalog = {}

local C = EbonBuilds.TalentCatalog
local DATA = EbonBuilds.TalentCatalogData or {}

local function PositionKey(tier, column)
    return tostring(tonumber(tier) or 0) .. ":" .. tostring(tonumber(column) or 0)
end

local function HasCompleteCatalog(snapshot)
    local found = false
    for _, tree in pairs(snapshot and snapshot.talents or {}) do
        found = true
        if tree.catalogComplete ~= true then return false end
    end
    return found
end

C.HasCompleteCatalog = HasCompleteCatalog

-- Returns the stable first-rank spell ID for a 3.3.5a talent. Complete
-- schema-2 snapshots created before spell IDs were stored can therefore use
-- native spell tooltips even when the viewed build belongs to another class.
-- Prefer an exact grid-position match because legacy API indices are not as
-- durable as the DBC tier/column coordinates.
function C.GetSpellId(classToken, tab, talent)
    local classData = DATA[classToken]
    local tree = classData and classData[tonumber(tab)]
    local rows = tree and tree[3]
    if not rows or not talent then return nil end

    local tier = tonumber(talent.tier)
    local column = tonumber(talent.column)
    if tier and column then
        for _, row in ipairs(rows) do
            if tonumber(row[2]) == tier and tonumber(row[3]) == column then return row[1] end
        end
    end
    local row = rows[tonumber(talent.index)]
    return row and row[1] or nil
end

local function SavedTree(snapshot, tab)
    return snapshot and snapshot.talents
        and (snapshot.talents[tab] or snapshot.talents[tostring(tab)]) or nil
end

local function ValidateLegacyPositions(snapshot, classData)
    for tab = 1, 3 do
        local savedTree = SavedTree(snapshot, tab)
        local catalogTree = classData[tab]
        local rows = catalogTree and catalogTree[3]
        if savedTree and rows then
            local catalogPositions = {}
            for _, row in ipairs(rows) do
                catalogPositions[PositionKey(row[2], row[3])] = true
            end
            for _, talent in ipairs(savedTree.talents or {}) do
                if not catalogPositions[PositionKey(talent.tier, talent.column)] then return false end
            end
        end
    end
    return true
end

-- Returns an ephemeral display snapshot. The stored build record is never
-- mutated, so opening the Character tab cannot dirty or silently migrate it.
function C.ResolveSnapshot(snapshot, getSpellInfo)
    if not snapshot or HasCompleteCatalog(snapshot) then return snapshot, false end
    local classData = DATA[snapshot.classToken]
    if not classData or not ValidateLegacyPositions(snapshot, classData) then
        return snapshot, false
    end
    getSpellInfo = getSpellInfo or GetSpellInfo

    local resolved = {}
    for key, value in pairs(snapshot) do resolved[key] = value end
    resolved.talents = {}
    resolved._catalogRecovered = true

    for tab = 1, 3 do
        local catalogTree = classData[tab]
        local savedTree = SavedTree(snapshot, tab) or {}
        if catalogTree then
            local rows = catalogTree[3]
            local savedByIndex, savedByPosition = {}, {}
            for _, talent in ipairs(savedTree.talents or {}) do
                local index = tonumber(talent.index)
                if index then savedByIndex[index] = talent end
                savedByPosition[PositionKey(talent.tier, talent.column)] = talent
            end

            local tree = {
                tabIndex = tab,
                name = savedTree.name or catalogTree[1],
                icon = savedTree.icon,
                background = savedTree.background or catalogTree[2],
                points = tonumber(savedTree.points) or 0,
                catalogComplete = true,
                talents = {},
            }
            for index, row in ipairs(rows) do
                local saved = savedByPosition[PositionKey(row[2], row[3])] or savedByIndex[index]
                local name, icon
                if getSpellInfo then
                    local spellName, _, spellIcon = getSpellInfo(row[1])
                    name, icon = spellName, spellIcon
                end
                local talent = {
                    index = index,
                    spellId = row[1],
                    link = saved and saved.link,
                    name = name or (saved and saved.name) or ("Talent " .. index),
                    icon = icon or (saved and saved.icon),
                    tier = row[2],
                    column = row[3],
                    rank = tonumber(saved and saved.rank) or 0,
                    maxRank = row[4],
                    available = true,
                    prerequisites = {},
                }
                for offset = 5, #row, 2 do
                    local sourceIndex = row[offset]
                    local requiredRank = row[offset + 1] or 1
                    local sourceRow = rows[sourceIndex]
                    if sourceRow then
                        local sourceSaved = savedByPosition[PositionKey(sourceRow[2], sourceRow[3])]
                            or savedByIndex[sourceIndex]
                        talent.prerequisites[#talent.prerequisites + 1] = {
                            tier = sourceRow[2],
                            column = sourceRow[3],
                            met = (tonumber(sourceSaved and sourceSaved.rank) or 0) >= requiredRank,
                        }
                    end
                end
                tree.talents[index] = talent
            end
            resolved.talents[tab] = tree
        elseif next(savedTree) then
            resolved.talents[tab] = savedTree
        end
    end
    return resolved, true
end
