local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/CharacterSnapshot.lua
-- Responsibility: capturing the character's current state -- equipped
-- gear per slot, all three talent trees in full (every talent, not just
-- skilled ones), and glyph sockets -- and writing that snapshot onto a
-- build. The Character tab renders the live capture; "Adopt snapshot"
-- stores it on the build being edited, where the normal Save/Cancel
-- draft flow decides whether it persists.

EbonBuilds.CharacterSnapshot = {}

local M = EbonBuilds.CharacterSnapshot

-- Snapshot adoption is meaningful only when the live character and edited
-- build represent the same class. Keep this rule in the data module so UI
-- state cannot be bypassed by a future caller or test hook.
function M.CanApplyToClass(buildClass, snapshotClass)
    if not buildClass or buildClass == "" then return false, "NO_BUILD_CLASS" end
    if not snapshotClass or snapshotClass == "" then return false, "NO_CHARACTER_CLASS" end
    if buildClass ~= snapshotClass then return false, "CLASS_MISMATCH" end
    return true
end

-- Character presentation includes the two cosmetic equipment slots that are
-- deliberately absent from GearScore.SLOTS. They remain visible in the paper
-- doll, but are never treated as meaningful score contributors.
local EQUIPMENT_SLOTS = {
    { id = 1,  name = "Head" },          { id = 2,  name = "Neck" },
    { id = 3,  name = "Shoulder" },      { id = 4,  name = "Shirt", cosmetic = true },
    { id = 5,  name = "Chest" },         { id = 6,  name = "Waist" },
    { id = 7,  name = "Legs" },          { id = 8,  name = "Feet" },
    { id = 9,  name = "Wrist" },         { id = 10, name = "Hands" },
    { id = 11, name = "Finger 1" },      { id = 12, name = "Finger 2" },
    { id = 13, name = "Trinket 1" },     { id = 14, name = "Trinket 2" },
    { id = 15, name = "Back" },          { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand" },      { id = 18, name = "Ranged / Relic" },
    { id = 19, name = "Tabard", cosmetic = true },
}
M.EQUIPMENT_SLOTS = EQUIPMENT_SLOTS

-- WotLK 3.3.5a glyph socket layout: 1/4/6 are major, 2/3/5 are minor.
local GLYPH_SOCKET_TYPE = { [1] = "major", [2] = "minor", [3] = "minor", [4] = "major", [5] = "minor", [6] = "major" }
M.GLYPH_SOCKET_TYPE = GLYPH_SOCKET_TYPE

-- All getters injectable for tests, mirroring GearScore's pattern.
local function ItemIdFromLink(link)
    return tonumber(tostring(link or ""):match("item:(%d+)"))
end

local function ResolveItemIcon(link, getIcon)
    if not link or not getIcon then return nil end
    local ok, icon = pcall(getIcon, ItemIdFromLink(link) or link)
    return ok and icon or nil
end

function M.CaptureGear(getInvLink, getInfo, getIcon)
    getInvLink = getInvLink or function(slotId) return GetInventoryItemLink("player", slotId) end
    getInfo = getInfo or GetItemInfo
    getIcon = getIcon or GetItemIcon
    local gear = {}
    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local link = getInvLink(slot.id)
        if link then
            local name, resolvedLink, quality, itemLevel, requiredLevel, itemType,
                itemSubType, stackCount, equipLoc, icon = getInfo(link)
            gear[slot.id] = {
                name = name or link,
                quality = quality or 1,
                link = resolvedLink or link,
                itemLevel = itemLevel,
                requiredLevel = requiredLevel,
                itemType = itemType,
                itemSubType = itemSubType,
                equipLoc = equipLoc,
                icon = icon or ResolveItemIcon(resolvedLink or link, getIcon),
                resolved = name ~= nil,
                cosmetic = slot.cosmetic == true,
            }
        end
    end
    return gear
end

-- Every talent in every tree, skilled or not -- rank 0 entries included
-- deliberately so the Character tab can render the COMPLETE tree, and a
-- stored snapshot can be diffed tier-by-tier later.
function M.CaptureTalents(getNumTabs, getTabInfo, getTalentInfo, getNumTalents, getTalentPrereqs,
    classToken, getTalentLink)
    getNumTabs = getNumTabs or GetNumTalentTabs
    getTabInfo = getTabInfo or GetTalentTabInfo
    getTalentInfo = getTalentInfo or GetTalentInfo
    getNumTalents = getNumTalents or GetNumTalents
    getTalentPrereqs = getTalentPrereqs or GetTalentPrereqs
    getTalentLink = getTalentLink or GetTalentLink
    local trees = {}
    for tab = 1, (getNumTabs() or 0) do
        local tabName, tabIcon, pointsSpent, background = getTabInfo(tab)
        local tree = {
            tabIndex = tab,
            name = tabName or ("Tree " .. tab),
            icon = tabIcon,
            background = background,
            points = pointsSpent or 0,
            catalogComplete = true,
            talents = {},
        }
        for index = 1, (getNumTalents(tab) or 0) do
            local name, icon, tier, column, rank, maxRank, _, meetsPrereq = getTalentInfo(tab, index)
            if name then
                local talentLink
                if getTalentLink then
                    local ok, link = pcall(getTalentLink, tab, index)
                    if ok then talentLink = link end
                end
                local prerequisites = {}
                if getTalentPrereqs then
                    local values = { getTalentPrereqs(tab, index) }
                    for offset = 1, #values, 3 do
                        local requiredTier = tonumber(values[offset])
                        local requiredColumn = tonumber(values[offset + 1])
                        if requiredTier and requiredColumn then
                            prerequisites[#prerequisites + 1] = {
                                tier = requiredTier,
                                column = requiredColumn,
                                met = values[offset + 2] and true or false,
                            }
                        end
                    end
                end
                tree.talents[#tree.talents + 1] = {
                    index = index, name = name, icon = icon,
                    link = talentLink,
                    spellId = EbonBuilds.TalentCatalog and EbonBuilds.TalentCatalog.GetSpellId
                        and EbonBuilds.TalentCatalog.GetSpellId(classToken, tab, {
                            index = index, tier = tier, column = column,
                        }) or nil,
                    tier = tier or 1, column = column or 1,
                    rank = rank or 0, maxRank = maxRank or 0,
                    available = meetsPrereq ~= false,
                    prerequisites = prerequisites,
                }
            end
        end
        -- Stable visual order: by tree position, not API index.
        table.sort(tree.talents, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            return a.column < b.column
        end)
        trees[tab] = tree
    end
    return trees
end

function M.CaptureGlyphs(getNumSockets, getSocketInfo, getSpellInfo)
    getNumSockets = getNumSockets or GetNumGlyphSockets
    getSocketInfo = getSocketInfo or GetGlyphSocketInfo
    getSpellInfo = getSpellInfo or GetSpellInfo
    local glyphs = {}
    for socket = 1, (getNumSockets and getNumSockets() or 6) do
        local enabled, _, glyphSpellId = getSocketInfo(socket)
        local entry = { socket = socket, kind = GLYPH_SOCKET_TYPE[socket] or "minor", enabled = enabled and true or false }
        if glyphSpellId then
            local spellName, _, spellIcon = getSpellInfo(glyphSpellId)
            entry.spellId = glyphSpellId
            entry.name = spellName or ("Glyph " .. glyphSpellId)
            entry.icon = spellIcon
        end
        glyphs[socket] = entry
    end
    return glyphs
end

function M.Capture(getters)
    getters = getters or {}
    local getUnitClass = getters.getUnitClass or UnitClass
    local getUnitName = getters.getUnitName or UnitName
    local getTalentGroup = getters.getActiveTalentGroup or GetActiveTalentGroup
    local classToken
    if getUnitClass then
        local _
        _, classToken = getUnitClass("player")
    end
    return {
        schemaVersion = 2,
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "",
        characterName = getUnitName and getUnitName("player") or nil,
        classToken = classToken,
        talentGroup = getTalentGroup and getTalentGroup() or nil,
        gear = M.CaptureGear(getters.getInvLink, getters.getInfo, getters.getItemIcon),
        talents = M.CaptureTalents(getters.getNumTabs, getters.getTabInfo, getters.getTalentInfo,
            getters.getNumTalents, getters.getTalentPrereqs, classToken, getters.getTalentLink),
        glyphs = M.CaptureGlyphs(getters.getNumSockets, getters.getSocketInfo, getters.getSpellInfo),
    }
end

-- Stored/shared snapshots are self-contained presentation records. WotLK's
-- talent API exposes only the logged-in class, so cross-character viewing must
-- retain the complete visual catalog rather than borrow live talent metadata.
function M.Compact(snapshot)
    if not snapshot then return nil end
    local compact = {
        schemaVersion = 2,
        capturedAt = snapshot.capturedAt,
        characterName = snapshot.characterName,
        classToken = snapshot.classToken,
        talentGroup = snapshot.talentGroup,
        gear = {},
        glyphs = EbonBuilds.Build.CloneTable(snapshot.glyphs or {}),
        talents = {},
    }
    for slotId, item in pairs(snapshot.gear or {}) do
        compact.gear[slotId] = {
            name = item.name,
            quality = item.quality,
            link = item.link,
            itemLevel = item.itemLevel,
            requiredLevel = item.requiredLevel,
            itemType = item.itemType,
            itemSubType = item.itemSubType,
            equipLoc = item.equipLoc,
            icon = item.icon,
            resolved = item.resolved == true,
            cosmetic = item.cosmetic == true,
        }
    end
    for tab, tree in pairs(snapshot.talents or {}) do
        local target = {
            tabIndex = tree.tabIndex or tab,
            name = tree.name,
            icon = tree.icon,
            background = tree.background,
            points = tree.points or 0,
            catalogComplete = tonumber(snapshot.schemaVersion) == 2 and tree.catalogComplete ~= false,
            talents = {},
        }
        for _, talent in ipairs(tree.talents or {}) do
            local savedTalent = {
                index = talent.index,
                spellId = talent.spellId,
                link = talent.link,
                name = talent.name,
                icon = talent.icon,
                tier = talent.tier,
                column = talent.column,
                rank = talent.rank,
                maxRank = talent.maxRank,
                available = talent.available ~= false,
                prerequisites = {},
            }
            for _, prerequisite in ipairs(talent.prerequisites or {}) do
                savedTalent.prerequisites[#savedTalent.prerequisites + 1] = {
                    tier = prerequisite.tier,
                    column = prerequisite.column,
                    met = prerequisite.met == true,
                }
            end
            target.talents[#target.talents + 1] = savedTalent
        end
        compact.talents[tab] = target
    end
    return compact
end

-- Resolve a stored equipment record without consulting the player's equipped
-- slots. Persisted metadata gives an immediate stable view; GetItemInfo only
-- fills gaps or refreshes cached details for older schema-1 snapshots.
function M.ResolveGear(gear, getInfo, getIcon)
    getInfo = getInfo or GetItemInfo
    getIcon = getIcon or GetItemIcon
    local resolvedGear = {}
    for rawSlotId, stored in pairs(gear or {}) do
        local slotId = tonumber(rawSlotId) or rawSlotId
        local item = EbonBuilds.Build.CloneTable(stored)
        item.icon = item.icon or ResolveItemIcon(item.link, getIcon)
        if item.link and getInfo then
            local name, resolvedLink, quality, itemLevel, requiredLevel, itemType,
                itemSubType, stackCount, equipLoc, icon = getInfo(item.link)
            if name then
                item.name = name
                item.link = resolvedLink or item.link
                item.quality = quality or item.quality or 1
                item.itemLevel = itemLevel or item.itemLevel
                item.requiredLevel = requiredLevel or item.requiredLevel
                item.itemType = itemType or item.itemType
                item.itemSubType = itemSubType or item.itemSubType
                item.equipLoc = equipLoc or item.equipLoc
                item.icon = icon or item.icon
                item.resolved = true
            end
        end
        item.quality = item.quality or 1
        item.resolved = item.resolved == true
        resolvedGear[slotId] = item
    end
    return resolvedGear
end

------------------------------------------------------------------------
-- Talent comparison
------------------------------------------------------------------------

local function PositionKey(tab, talent)
    return tostring(tab) .. ":" .. tostring(tonumber(talent and talent.tier) or 0)
        .. ":" .. tostring(tonumber(talent and talent.column) or 0)
end

local function IndexKey(tab, talent)
    local index = tonumber(talent and talent.index)
    return index and (tostring(tab) .. ":" .. tostring(index)) or nil
end

-- Public stable key for runtime rendering. New captures use the API talent
-- index; legacy snapshots without an index still compare by unique grid
-- position so existing builds remain readable after the visualization update.
function M.TalentKey(tab, talent)
    return IndexKey(tab, talent) or PositionKey(tab, talent)
end

function M.CompareTalents(current, stored)
    local result = {
        comparable = stored ~= nil,
        reason = stored and nil or "NO_SNAPSHOT",
        requiredRanks = 0,
        matchedRanks = 0,
        missingRanks = 0,
        additionalRanks = 0,
        exactTalentCount = 0,
        changedTalentCount = 0,
        unknownTalentCount = 0,
        byKey = {},
    }
    if not stored then return result end
    if current and stored.classToken and current.classToken
        and stored.classToken ~= current.classToken then
        result.comparable = false
        result.reason = "CLASS_MISMATCH"
        return result
    end

    local targetByIndex, targetByPosition = {}, {}
    for tab, tree in pairs(stored.talents or {}) do
        for _, talent in ipairs(tree.talents or {}) do
            local indexKey = IndexKey(tab, talent)
            if indexKey then targetByIndex[indexKey] = talent end
            targetByPosition[PositionKey(tab, talent)] = talent
            result.requiredRanks = result.requiredRanks + math.max(0, tonumber(talent.rank) or 0)
        end
    end

    local seen = {}
    for tab, tree in pairs(current and current.talents or {}) do
        for _, talent in ipairs(tree.talents or {}) do
            local indexKey = IndexKey(tab, talent)
            local positionKey = PositionKey(tab, talent)
            local target = indexKey and targetByIndex[indexKey] or nil
            target = target or targetByPosition[positionKey]
            if target then seen[target] = true end

            local currentRank = math.max(0, tonumber(talent.rank) or 0)
            local targetRank = math.max(0, tonumber(target and target.rank) or 0)
            local matched = math.min(currentRank, targetRank)
            local missing = math.max(0, targetRank - currentRank)
            local additional = math.max(0, currentRank - targetRank)
            local state
            if targetRank == currentRank then
                state = currentRank > 0 and "exact" or "unselected"
                if currentRank > 0 then result.exactTalentCount = result.exactTalentCount + 1 end
            elseif missing > 0 then
                state = "missing"
                result.changedTalentCount = result.changedTalentCount + 1
            else
                state = "additional"
                result.changedTalentCount = result.changedTalentCount + 1
            end

            result.matchedRanks = result.matchedRanks + matched
            result.missingRanks = result.missingRanks + missing
            result.additionalRanks = result.additionalRanks + additional
            result.byKey[M.TalentKey(tab, talent)] = {
                current = currentRank,
                snapshot = targetRank,
                maxRank = tonumber(talent.maxRank) or tonumber(target and target.maxRank) or 0,
                state = state,
                delta = currentRank - targetRank,
            }
        end
    end

    -- A selected talent that no longer exists in the live catalog is missing,
    -- not silently discarded. This also covers malformed or foreign snapshots
    -- without manufacturing a live talent node for them.
    for tab, tree in pairs(stored.talents or {}) do
        for _, target in ipairs(tree.talents or {}) do
            if not seen[target] then
                local targetRank = math.max(0, tonumber(target.rank) or 0)
                result.missingRanks = result.missingRanks + targetRank
                result.changedTalentCount = result.changedTalentCount + 1
                result.unknownTalentCount = result.unknownTalentCount + 1
                result.byKey[M.TalentKey(tab, target)] = {
                    current = 0,
                    snapshot = targetRank,
                    maxRank = tonumber(target.maxRank) or 0,
                    state = "unknown",
                    delta = -targetRank,
                }
            end
        end
    end

    if result.requiredRanks > 0 then
        result.matchPercent = result.matchedRanks / result.requiredRanks * 100
    end
    return result
end

-- Writes the capture onto the build object handed in (the edit context's
-- draft build). Persistence stays with the editor's Save/Cancel flow --
-- this function never touches EbonBuildsDB itself.
function M.ApplyToBuild(build, getters)
    if not build then return nil end
    local snapshot = M.Capture(getters)
    local allowed, reason = M.CanApplyToClass(build.class, snapshot and snapshot.classToken)
    if not allowed then return nil, reason end
    build.characterSnapshot = M.Compact(snapshot)
    return build.characterSnapshot
end

-- Compact one-line summary for the tab ("31/5/5 · 4 glyphs · 17 items"),
-- reusing the classic points notation.
function M.Summarize(snapshot)
    if not snapshot then return nil end
    local points = {}
    for tab = 1, 3 do
        points[#points + 1] = tostring((snapshot.talents and snapshot.talents[tab] and snapshot.talents[tab].points) or 0)
    end
    local glyphCount = 0
    for _, g in ipairs(snapshot.glyphs or {}) do
        if g.spellId then glyphCount = glyphCount + 1 end
    end
    local itemCount = 0
    for _ in pairs(snapshot.gear or {}) do itemCount = itemCount + 1 end
    return string.format("%s · %d glyphs · %d items", table.concat(points, "/"), glyphCount, itemCount)
end
