local addonName, EbonBuilds = ...

-- EbonBuilds: modules/analytics/BuildOverviewData.lua
-- Responsibility: pure data derivation for the Build Overview dashboard --
-- owned-echo detection, missing-echo computation, collection view policy,
-- and responsive action-grid metrics. No frames, no rendering.
-- Split out of modules/ui/BuildOverview.lua (issue #19).

EbonBuilds.BuildOverviewData = {}
local Data = EbonBuilds.BuildOverviewData

-- Strip common prefixes/suffixes so spell-name comparison is robust against
-- cosmetic variants like "Tome of Brittle Forging" vs "Brittle Forging".
local PREFIXES = { "tome of ", "codex of ", "scroll of ", "manual of ", "grimoire of ", "libram of ", "tablet of " }
-- Plain-text suffixes (compared verbatim via sub(), NOT Lua patterns).
local QUALITY_SUFFIXES = { " - common", " - uncommon", " - rare", " - epic" }

local function NormalizeEchoName(name)
    if not name then return nil end
    local visible = EbonBuilds.Weights and EbonBuilds.Weights.VisibleName
        and EbonBuilds.Weights.VisibleName(name) or tostring(name or "")
    if visible == "" then return nil end
    -- Never feed raw imported keys with control-byte suffixes to WoW's
    -- 3.3.5a locale lowercasing helper.
    local n = string.lower(visible)
    for _, prefix in ipairs(PREFIXES) do
        if n:sub(1, #prefix) == prefix then
            n = n:sub(#prefix + 1)
            break
        end
    end
    for _, suffix in ipairs(QUALITY_SUFFIXES) do
        if n:sub(-#suffix) == suffix then
            n = n:sub(1, -(#suffix + 1))
            break
        end
    end
    return n
end

-- Owned-echo detection, shared by BuildOverview's Missing tab and
-- TomeAtlasView's tome-collection status.
--
-- Preferred source: ProjectEbonhold.PerkService.GetDiscoveredEchoes() --
-- an authoritative, spellId-keyed table of every echo the character has
-- ever unlocked, backed by a SavedVariables cache so it's available
-- immediately (even before the server confirms), unlike the spellbook.
-- Falls back to scanning the spellbook's "Echoes" tab directly (the old
-- approach) only if that API doesn't exist (older server build).
--
-- Returns (ownedLower, ownedGroups) where ownedLower[normalizedName] and
-- ownedGroups[groupId] are presence sets, or (nil, nil) if the fallback
-- path had to be used and the spellbook isn't populated yet (caller
-- should retry). The preferred path never returns nil/nil.
function Data.GetOwnedEchoSets(assumeNoneOwned)
    local svc = ProjectEbonhold and ProjectEbonhold.PerkService
    local ownedLower, ownedGroups, ownedSpellIds = {}, {}, {}

    local function AddOwnedName(name)
        local norm = NormalizeEchoName(name)
        if norm then ownedLower[norm] = true end
    end

    local function AddOwnedSpell(spellId)
        spellId = tonumber(spellId)
        if not spellId then return end
        ownedSpellIds[spellId] = true
        local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
        if variant then
            AddOwnedName(variant.displayName or variant.sourceName)
            if variant.groupId then ownedGroups[variant.groupId] = true end
            return
        end
        local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase
            and ProjectEbonhold.PerkDatabase[spellId]
        if data then
            AddOwnedName(GetSpellInfo(spellId))
            if data.groupId then ownedGroups[data.groupId] = true end
        end
    end

    if svc and svc.GetDiscoveredEchoes then
        local discovered = svc.GetDiscoveredEchoes() or {}
        for key, value in pairs(discovered) do
            local spellId = tonumber(key)
            if not spellId and type(value) == "number" then
                spellId = value
            elseif not spellId and type(value) == "table" then
                spellId = value.spellId or value.id
            end
            if spellId then
                AddOwnedSpell(spellId)
            else
                local name = type(key) == "string" and key
                    or (type(value) == "string" and value)
                    or (type(value) == "table" and value.name)
                AddOwnedName(name)
                if type(value) == "table" and value.groupId then
                    ownedGroups[value.groupId] = true
                end
            end
        end
    else
        -- Legacy fallback: resolve spellbook "Echoes" tab entries to
        -- PerkDatabase via requiredSpell (or spellId+100000 as backup),
        -- same as EbonBuilds used before GetDiscoveredEchoes existed.
        local spellbookIds = {}
        local echoesTabFound = false
        local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
        for tabIdx = 1, numTabs do
            local tabName, _, offset, numSpells = GetSpellTabInfo(tabIdx)
            if tabName == "Echoes" then
                echoesTabFound = true
                for slot = offset + 1, offset + numSpells do
                    local link = GetSpellLink(slot, "spell")
                    local tomeSpellId = link and tonumber(link:match("spell:(%d+)"))
                    if tomeSpellId then spellbookIds[tomeSpellId] = true end
                end
                break
            end
        end
        -- Spellbook not populated yet (early login / zoning): report "not
        -- ready" instead of wrongly claiming every echo is missing --
        -- UNLESS the caller has given up retrying (assumeNoneOwned).
        if not echoesTabFound and not assumeNoneOwned then
            return nil, nil, nil
        end
        for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
            if spellbookIds[data.requiredSpell] or spellbookIds[spellId + 100000] then
                AddOwnedSpell(spellId)
            end
        end
    end

    -- Echoes granted without ever needing a tome (not in the discovery
    -- list either way) still need this pass, on both paths above.
    if svc and svc.GetGrantedPerks then
        for key, value in pairs(svc.GetGrantedPerks() or {}) do
            local spellId = tonumber(key)
            if not spellId and type(value) == "table" then
                spellId = value.spellId or value.id
            end
            if spellId then
                AddOwnedSpell(spellId)
            else
                local name = type(key) == "string" and key
                    or (type(value) == "string" and value)
                    or (type(value) == "table" and value.name)
                AddOwnedName(name)
            end
        end
    end

    return ownedLower, ownedGroups, ownedSpellIds
end

Data.DEFAULT_MISSING_VIEW_KEY = "weightedMissing"

Data.MISSING_VIEW_OPTIONS = {
    {
        key = "weighted",
        label = "Weighted priorities",
        includeOwned = true,
        weightedOnly = true,
        tooltip = "Show only Echoes with at least one non-zero rank value in this build, including learned and missing Echoes.",
    },
    {
        key = "weightedMissing",
        label = "Weighted missing",
        includeOwned = false,
        weightedOnly = true,
        tooltip = "Show only weighted Echoes that this character has not learned yet.",
    },
    {
        key = "missing",
        label = "All missing",
        includeOwned = false,
        weightedOnly = false,
        tooltip = "Show every unlearned Echo available to this build's class, even when its configured rank values are zero.",
    },
    {
        key = "catalog",
        label = "Learned + missing",
        includeOwned = true,
        weightedOnly = false,
        tooltip = "Show learned and unlearned Echoes available to this build's class.",
    },
}

function Data.MissingViewDefinition(key)
    local requestedKey = key or Data.DEFAULT_MISSING_VIEW_KEY
    for _, option in ipairs(Data.MISSING_VIEW_OPTIONS) do
        if option.key == requestedKey then return option end
    end
    for _, option in ipairs(Data.MISSING_VIEW_OPTIONS) do
        if option.key == Data.DEFAULT_MISSING_VIEW_KEY then return option end
    end
    return Data.MISSING_VIEW_OPTIONS[1]
end

function Data.BuildWeightedEchoSet(weights)
    local weighted = {}
    for name, entry in pairs(weights or {}) do
        if EbonBuilds.Weights.HasNonZero(entry) then
            local normalized = NormalizeEchoName(name)
            if normalized then weighted[normalized] = true end
        end
    end
    return weighted
end

function Data.ComputeMissingEchoes(build, assumeNoneOwned, includeOwned, weightedOnly)
    if not build or not build.class then return nil end
    if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end

    local ok, ownedLower, ownedGroups = pcall(EbonBuilds.BuildOverview.GetOwnedEchoSets, assumeNoneOwned)
    if not ok then
        if EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("BuildOverview.ComputeMissingEchoes", tostring(ownedLower))
        end
        return nil
    end
    if not ownedLower then return nil end

    local lockedRefs = {}
    for _, spellId in ipairs(build.lockedEchoes or {}) do
        local refKey = spellId and EbonBuilds.EchoCatalog.GetRefForSpell(spellId)
        if refKey then lockedRefs[refKey] = true end
    end

    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    local missing = {}
    for _, projected in ipairs(EbonBuilds.EchoProjection.GetAvailable(build.class) or {}) do
        local variant = projected.availableVariants and projected.availableVariants[1]
        if variant then
            local refKey = projected.refKey
            local normalizedCanonical = NormalizeEchoName(projected.canonicalName or projected.sourceName)
            local normalizedDisplay = NormalizeEchoName(projected.displayName or projected.name)
            local isOwned = (normalizedCanonical and ownedLower[normalizedCanonical])
                or (normalizedDisplay and ownedLower[normalizedDisplay])
                or (projected.groupId and ownedGroups[projected.groupId])
            -- Use the same effective rank-value accessor as the Priorities
            -- editor and automation.  Reading echoWeightsByRef directly makes
            -- valid legacy/imported builds appear completely unweighted.
            local weighted = EbonBuilds.Weights.HasNonZeroForRef
                and EbonBuilds.Weights.HasNonZeroForRef(build, refKey)
                or EbonBuilds.Weights.HasNonZero((build.echoWeightsByRef or {})[refKey])
            if (not weightedOnly or weighted) and (includeOwned or not isOwned) then
                if isOwned then
                    missing[#missing + 1] = {
                        spellId = variant.spellId,
                        refKey = refKey,
                        name = projected.displayName or projected.name,
                        quality = variant.quality or 0,
                        isLocked = lockedRefs[refKey] or false,
                        owned = true,
                        weighted = weighted,
                    }
                else
                    local source = ProjectEbonhold.PerkDropSources and ProjectEbonhold.PerkDropSources[variant.spellId]
                    if not source and projected.groupId and ProjectEbonhold.PerkDropSourceByGroup then
                        source = ProjectEbonhold.PerkDropSourceByGroup[projected.groupId]
                    end
                    local needsTome = (tonumber(variant.requiredSpell) or 0) > 0
                    if not EbonBuilds.Scoring.IsBanned(variant.spellId, settings) and needsTome then
                        local weight = EbonBuilds.Weights.GetForRef(build, refKey, variant.quality)
                        local score = EbonBuilds.Scoring.Score(projected, weight, settings)
                        missing[#missing + 1] = {
                            spellId = variant.spellId,
                            refKey = refKey,
                            name = projected.displayName or projected.name,
                            quality = variant.quality or 0,
                            dropSource = source or "Unknown",
                            isLocked = lockedRefs[refKey] or false,
                            score = score,
                            owned = false,
                            weighted = weighted,
                        }
                    end
                end
            end
        end
    end

    -- Sort: missing before owned (when both are shown), then locked
    -- echoes first, then score desc, then quality desc, then name asc.
    table.sort(missing, function(a, b)
        if a.owned ~= b.owned then
            return not a.owned
        end
        if a.isLocked ~= b.isLocked then
            return a.isLocked
        end
        if a.owned then
            return a.name < b.name
        end
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        return a.name < b.name
    end)
    return missing
end

function Data.ActionGridMetrics(outerWidth, count)
    outerWidth = math.max(1, tonumber(outerWidth) or 0)
    count = math.max(1, tonumber(count) or 1)
    local available = math.max(320, outerWidth - 20)
    local columns = available >= 660 and 5 or 3
    local gap = 6
    local buttonWidth = math.floor((available - (columns - 1) * gap) / columns)
    local rows = math.ceil(count / columns)
    return {
        available = available,
        columns = columns,
        gap = gap,
        buttonWidth = math.max(96, buttonWidth),
        rows = rows,
        height = rows * 22 + math.max(0, rows - 1) * gap,
    }
end

Data.NormalizeEchoName = NormalizeEchoName
