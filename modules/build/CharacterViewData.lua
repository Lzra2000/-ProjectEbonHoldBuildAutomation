local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/CharacterViewData.lua
-- Responsibility: pure data derivation for the Character workspace -- talent
-- snapshot summaries, gear slot counts, affix columns, glyph presentation,
-- talent grid geometry, and viewport width resolution. No frames, no rendering.
-- Split out of modules/ui/CharacterView.lua (issue #19).

EbonBuilds.CharacterViewData = {}
local Data = EbonBuilds.CharacterViewData

local TALENT_NODE_SIZE = 34
local TALENT_COLUMN_STEP = 52
local TALENT_MAX_TIER_STEP = 52
local TALENT_MIN_TIER_STEP = TALENT_NODE_SIZE + 4
local TALENT_BACKGROUND_WIDTH = 254
local TALENT_TOP_PADDING = 10
local TALENT_BOTTOM_PADDING = 8

Data.STAT_NAMES = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina", ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit", ITEM_MOD_ATTACK_POWER_SHORT = "Attack power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Ranged attack power",
    ITEM_MOD_SPELL_POWER_SHORT = "Spell power", ITEM_MOD_HIT_RATING_SHORT = "Hit",
    ITEM_MOD_CRIT_RATING_SHORT = "Critical strike", ITEM_MOD_HASTE_RATING_SHORT = "Haste",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "Armor penetration",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense", ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "Parry", ITEM_MOD_BLOCK_RATING_SHORT = "Block",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Mana regeneration",
}

local function TalentPointsText(snapshot)
    local values = {}
    for tab = 1, 3 do
        values[#values + 1] = tostring(snapshot and snapshot.talents and snapshot.talents[tab]
            and snapshot.talents[tab].points or 0)
    end
    return table.concat(values, " / ")
end

local function HasCompleteTalentCatalog(snapshot)
    local foundTree = false
    for _, tree in pairs(snapshot and snapshot.talents or {}) do
        foundTree = true
        if tree.catalogComplete ~= true then return false end
    end
    return foundTree
end

local function ComparisonText(result)
    if not result or result.reason == "NO_SNAPSHOT" then
        return "No saved talent snapshot"
    elseif result.reason == "CLASS_MISMATCH" then
        return "Saved snapshot belongs to another class"
    elseif not result.comparable then
        return "Talent comparison unavailable"
    elseif result.unknownTalentCount > 0 then
        return string.format("Incomplete data · %d unresolved · %d ranks missing",
            result.unknownTalentCount, result.missingRanks)
    elseif result.missingRanks > 0 then
        return string.format("Needs attention · %d ranks missing · %d additional",
            result.missingRanks, result.additionalRanks)
    elseif result.additionalRanks > 0 then
        return string.format("Snapshot matched · %d additional ranks", result.additionalRanks)
    end
    return "Saved talent snapshot matched"
end

local function ComparisonKind(result)
    if not result or not result.comparable then return "warning" end
    if result.missingRanks > 0 or result.unknownTalentCount > 0 then return "warning" end
    return "success"
end

local function BuildGearSummary(gear)
    local equipped, resolved, pending = 0, 0, 0
    for _, slot in ipairs(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) do
        local item = gear and gear[slot.id]
        if item then
            equipped = equipped + 1
            if item.resolved then resolved = resolved + 1 else pending = pending + 1 end
        end
    end
    return {
        total = #(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}),
        equipped = equipped,
        resolved = resolved,
        pending = pending,
        empty = #(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) - equipped,
    }
end

local function LayoutBreakpoints(width)
    width = tonumber(width) or 0
    return { compact = width < 620, inspectorWidth = width < 700 and 190 or 220 }
end

local function ResolveViewportWidth(viewWidth, parentWidth, pageWidth)
    local candidates = { viewWidth, parentWidth, pageWidth }
    for _, candidate in ipairs(candidates) do
        candidate = tonumber(candidate) or 0
        if candidate > 1 then return candidate end
    end
    return 1
end

local function TalentCanvasWidth(pageWidth)
    pageWidth = math.max(1, tonumber(pageWidth) or 0)
    local areaWidth = math.max(1, pageWidth - 8)
    if pageWidth >= 620 then
        local inspectorWidth = pageWidth < 700 and 190 or 220
        areaWidth = math.max(1, areaWidth - inspectorWidth - 7)
    end
    return math.max(320, math.floor(areaWidth - 34))
end

local function TalentGridMetrics(canvasWidth, viewportHeight, maxTier)
    canvasWidth = math.max(300, tonumber(canvasWidth) or 0)
    viewportHeight = math.max(240, tonumber(viewportHeight) or 0)
    maxTier = math.max(1, tonumber(maxTier) or 1)

    local tierStep = TALENT_MAX_TIER_STEP
    if maxTier > 1 then
        local fitStep = math.floor((viewportHeight - TALENT_TOP_PADDING
            - TALENT_BOTTOM_PADDING - TALENT_NODE_SIZE) / (maxTier - 1))
        tierStep = math.max(TALENT_MIN_TIER_STEP, math.min(TALENT_MAX_TIER_STEP, fitStep))
    end
    local contentHeight = math.max(viewportHeight, TALENT_TOP_PADDING
        + (maxTier - 1) * tierStep + TALENT_NODE_SIZE + TALENT_BOTTOM_PADDING)
    local backgroundWidth = math.min(TALENT_BACKGROUND_WIDTH, canvasWidth - 12)
    local backgroundLeft = math.floor((canvasWidth - backgroundWidth) / 2)
    local gridWidth = TALENT_NODE_SIZE + 3 * TALENT_COLUMN_STEP
    local gridLeft = backgroundLeft + math.floor((backgroundWidth - gridWidth) / 2)
    return {
        nodeSize = TALENT_NODE_SIZE,
        columnStep = TALENT_COLUMN_STEP,
        tierStep = tierStep,
        contentHeight = contentHeight,
        backgroundWidth = backgroundWidth,
        backgroundLeft = backgroundLeft,
        gridLeft = gridLeft,
        top = TALENT_TOP_PADDING,
    }
end

local function TalentStatusText(state)
    if not state then return "Saved snapshot allocation" end
    if state.state == "exact" then return "Matches saved snapshot" end
    if state.state == "missing" then return string.format("Missing %d saved ranks", -state.delta) end
    if state.state == "additional" then return string.format("%d additional ranks", state.delta) end
    if state.state == "unknown" then return "Saved talent could not be resolved" end
    return "Unselected in both"
end

local function TalentSpellId(classToken, tab, talent)
    return talent and (talent.spellId
        or EbonBuilds.TalentCatalog and EbonBuilds.TalentCatalog.GetSpellId
        and EbonBuilds.TalentCatalog.GetSpellId(classToken, tab, talent)) or nil
end

local function GlyphPresentation(glyphs)
    local major, minor = {}, {}
    for socket = 1, 6 do
        local glyph = glyphs and (glyphs[socket] or glyphs[tostring(socket)])
        if glyph and glyph.spellId then
            local name = glyph.name
            if (not name or name == "") and GetSpellInfo then name = GetSpellInfo(glyph.spellId) end
            local kind = glyph.kind or EbonBuilds.CharacterSnapshot.GLYPH_SOCKET_TYPE[socket]
            local target = kind == "major" and major or minor
            target[#target + 1] = name or ("Glyph " .. tostring(glyph.spellId))
        end
    end

    local lines = {}
    for _, name in ipairs(major) do lines[#lines + 1] = "|cffffd100M|r · " .. name end
    for _, name in ipairs(minor) do lines[#lines + 1] = "|cff7fc8ffm|r · " .. name end
    if #lines == 0 then lines[1] = "No glyphs stored in this snapshot." end
    return string.format("Glyphs · Major %d/3 · Minor %d/3", #major, #minor), table.concat(lines, "\n")
end

local function TalentDisplayRank(talent, state)
    return tonumber(talent.rank) or 0
end

local function SavedItemAffix(item)
    if not item then return nil end
    local itemName = item.name
    if (not itemName or itemName == "") and item.link then
        itemName = tostring(item.link):match("%[(.-)%]")
    end
    if not itemName or not EbonBuilds.AffixItemScan
        or not EbonBuilds.AffixItemScan.ExtractSuffix then return nil end
    local base, rank = EbonBuilds.AffixItemScan.ExtractSuffix(itemName)
    return base and (base .. " " .. rank) or nil
end

local function BuildGearAffixColumns(gear)
    local entries = {}
    for _, slot in ipairs(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) do
        local affix = SavedItemAffix(gear and gear[slot.id])
        if affix then entries[#entries + 1] = "|cffffd100" .. slot.name .. "|r · " .. affix end
    end
    if #entries == 0 then return "No affixes found in the saved equipment names.", "", 0 end
    return table.concat(entries, "\n"), "", #entries
end

local function BuildRecognizedStats(item, specKey)
    if not item or not item.link or not item.resolved or not specKey then return {}, 0 end
    local weights = EbonBuilds.GearScore.STAT_WEIGHTS[specKey]
    if not weights then return {}, 0 end
    local stats = GetItemStats and GetItemStats(item.link) or {}
    local values = {}
    for key, value in pairs(stats or {}) do
        if weights[key] and type(value) == "number" then
            values[#values + 1] = {
                name = Data.STAT_NAMES[key] or key,
                value = value,
                weight = weights[key],
            }
        end
    end
    table.sort(values, function(a, b) return a.name < b.name end)
    return values, #values
end

Data.TalentPointsText = TalentPointsText
Data.HasCompleteTalentCatalog = HasCompleteTalentCatalog
Data.ComparisonText = ComparisonText
Data.ComparisonKind = ComparisonKind
Data.BuildGearSummary = BuildGearSummary
Data.LayoutBreakpoints = LayoutBreakpoints
Data.ResolveViewportWidth = ResolveViewportWidth
Data.TalentCanvasWidth = TalentCanvasWidth
Data.TalentGridMetrics = TalentGridMetrics
Data.TalentStatusText = TalentStatusText
Data.TalentSpellId = TalentSpellId
Data.GlyphPresentation = GlyphPresentation
Data.TalentDisplayRank = TalentDisplayRank
Data.SavedItemAffix = SavedItemAffix
Data.BuildGearAffixColumns = BuildGearAffixColumns
Data.BuildRecognizedStats = BuildRecognizedStats
