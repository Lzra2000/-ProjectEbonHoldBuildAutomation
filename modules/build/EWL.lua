-- EbonBuilds: modules/build/EWL.lua
-- Generates EchoWishlist-compatible EWL1 import strings.
--
-- EchoWishlist does not choose the strongest weighted rank. It builds one
-- player-facing catalog row per cleaned Echo name, retains that row's canonical
-- spellId, and sorts wishlist rows by saved state, unlock state, quality, then
-- name. EbonBuilds mirrors those rules so its output survives an EWL import /
-- export round trip without rank aliases, class aliases, or duplicate families.

EbonBuilds.EWL = {}

local EWL = EbonBuilds.EWL
local Theme = EbonBuilds.Theme

local exportDialog
local tooltipScanner
local TOME_SPELL_CACHE = {}
local ECHO_SPELL_CACHE = {}
local compatibleCatalogCache
local compatibleCatalogDatabase


local function CleanEchoName(name)
    if not name then return nil end
    -- Imported weight keys may contain hidden control-byte discriminators used
    -- by Project Ebonhold to distinguish same-name variants. Keep those bytes
    -- in the build's storage key, but never pass them to WoW's locale helpers
    -- or UI strings. On the 3.3.5a client, strlower/string.lower can terminate
    -- the client when given an embedded NUL byte.
    local cleaned
    if EbonBuilds.Weights and EbonBuilds.Weights.VisibleName then
        cleaned = EbonBuilds.Weights.VisibleName(name)
    else
        cleaned = tostring(name)
        for index = 1, #cleaned do
            local byte = cleaned:byte(index)
            if byte and (byte < 32 or byte == 127) then
                cleaned = cleaned:sub(1, index - 1)
                break
            end
        end
    end
    cleaned = string.gsub(cleaned, "^%s+", "")
    cleaned = string.gsub(cleaned, "%s+$", "")
    cleaned = EbonBuilds.Weights.StripQualitySuffix(cleaned)
    cleaned = string.gsub(cleaned, "^Tome of ", "")
    cleaned = string.gsub(cleaned, "^%a+ %- ", "")
    cleaned = string.gsub(cleaned, "%s+", " ")
    return cleaned
end

local function FamilyKey(name)
    local cleaned = CleanEchoName(name)
    if not cleaned or cleaned == "" then return nil end
    return string.lower(cleaned)
end

local function StripTomeName(name)
    if not name then return nil end
    local stripped = string.gsub(name, "^Tome of ", "")
    if stripped ~= name then return stripped end
    return nil
end

local function GetPerkData(spellId)
    local database = ProjectEbonhold and ProjectEbonhold.PerkDatabase
    if not database or not spellId then return nil end
    return database[spellId] or database[tostring(spellId)]
end

local function TryGetPerkData(spellId)
    local peh = ProjectEbonhold
    if not peh or not spellId then return nil end

    if type(peh.GetPerkData) == "function" then
        local ok, data = pcall(peh.GetPerkData, spellId)
        if ok and data ~= nil then return data end
        ok, data = pcall(peh.GetPerkData, peh, spellId)
        if ok and data ~= nil then return data end
    end

    local data = GetPerkData(spellId)
    if data ~= nil then return data end

    if type(peh.Perks) == "table" then
        return peh.Perks[spellId] or peh.Perks[tostring(spellId)]
    end
    return nil
end

local function CanonicalNameForSpell(spellId)
    local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId
        and EbonBuilds.EchoCatalog.GetBySpellId(spellId) or nil
    local definition = variant and EbonBuilds.EchoCatalog.GetByRef(variant.refKey) or nil
    local name = definition and (definition.displayName or definition.canonicalName or definition.sourceName)
    if name and name ~= "" then return CleanEchoName(name) end
    return CleanEchoName(GetSpellInfo(spellId))
end

local function GetSpellTooltipText(spellId)
    if not spellId or spellId == 0 or type(CreateFrame) ~= "function" then return "" end
    if not tooltipScanner then
        tooltipScanner = CreateFrame("GameTooltip", "EbonBuildsEWLTooltipScanner", UIParent, "GameTooltipTemplate")
        tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    end

    tooltipScanner:ClearLines()
    local ok = pcall(function()
        tooltipScanner:SetHyperlink("spell:" .. tostring(spellId))
    end)
    if not ok then return "" end

    local parts = {}
    for i = 1, 20 do
        local left = _G["EbonBuildsEWLTooltipScannerTextLeft" .. i]
        local right = _G["EbonBuildsEWLTooltipScannerTextRight" .. i]
        if left and left:GetText() then parts[#parts + 1] = left:GetText() end
        if right and right:GetText() then parts[#parts + 1] = right:GetText() end
    end
    return table.concat(parts, "\n")
end

local function ExtractUnlockTomeName(text)
    if not text or text == "" then return nil end
    local tome = string.match(text, "[Uu]nlock:%s*([^\n\r]+)")
    if tome then return tome end
    return string.match(text, "(Tome of [^\n\r]+)")
end

local function FindTomeSpellIdByName(echoName)
    echoName = CleanEchoName(echoName)
    if not echoName or echoName == "" then return nil end
    local key = string.lower(echoName)
    if TOME_SPELL_CACHE[key] ~= nil then return TOME_SPELL_CACHE[key] or nil end

    local target = "Tome of " .. echoName
    for spellId = 300000, 301500 do
        if GetSpellInfo(spellId) == target then
            TOME_SPELL_CACHE[key] = spellId
            return spellId
        end
    end
    TOME_SPELL_CACHE[key] = false
    return nil
end

local function FindEchoSpellIdByName(echoName)
    echoName = CleanEchoName(echoName)
    if not echoName or echoName == "" then return nil end
    local key = string.lower(echoName)
    if ECHO_SPELL_CACHE[key] ~= nil then return ECHO_SPELL_CACHE[key] or nil end

    for spellId = 200000, 202500 do
        if GetSpellInfo(spellId) == echoName then
            ECHO_SPELL_CACHE[key] = spellId
            return spellId
        end
    end
    ECHO_SPELL_CACHE[key] = false
    return nil
end

local function IsKnownSpell(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then return false end
    if type(IsSpellKnown) == "function" then
        local ok, known = pcall(IsSpellKnown, spellId)
        if ok and known then return true end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok and known then return true end
    end
    return false
end

local function NormalizePerkData(id, data)
    local item = { id = tonumber(id) }

    if type(data) == "table" then
        item.raw = data
        item.spellId = tonumber(data.spellId or data.spellID or data.spell or data.requiredSpell or data.id or id)
        item.quality = tonumber(data.quality or data.rarity or data.perkQuality or data.Quality or 0) or 0
        item.maxStack = tonumber(data.maxStack or data.maxStacks or data.stacks or 1) or 1
        item.groupId = tonumber(data.groupId or data.group or 0) or 0
        item.requiredSpell = tonumber(data.requiredSpell or data.RequiredSpell or 0) or 0
        item.name = data.name or data.Name
        item.icon = data.icon or data.Icon
        item.description = data.description or data.desc or data.Description
        item.comment = data.comment or data.Comment
    else
        item.spellId = tonumber(id)
        item.quality = 0
        item.maxStack = 1
        item.groupId = 0
        item.requiredSpell = 0
    end

    if not item.spellId or item.spellId == 0 then item.spellId = tonumber(id) end
    local spellName, _, spellIcon = GetSpellInfo(item.spellId)
    item.name = item.name or spellName or CleanEchoName(item.comment) or ("Unknown #" .. tostring(id))
    item.icon = item.icon or spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark"

    local unlockTomeName = ExtractUnlockTomeName(GetSpellTooltipText(item.spellId))
    if unlockTomeName then
        item.tomeName = item.tomeName or unlockTomeName
        item.hasUnlockTome = true
    end

    local peh = ProjectEbonhold
    if peh then
        if type(peh.PerkDropSources) == "table" then
            item.dropSource = peh.PerkDropSources[item.id]
                or peh.PerkDropSources[tostring(item.id)]
                or peh.PerkDropSources[item.spellId]
                or peh.PerkDropSources[tostring(item.spellId)]
        end
        if not item.dropSource and type(peh.PerkDropSourceByGroup) == "table" and item.groupId then
            item.dropSource = peh.PerkDropSourceByGroup[item.groupId]
                or peh.PerkDropSourceByGroup[tostring(item.groupId)]
        end
    end

    local echoName = CleanEchoName(item.name)
    item.tomeSpellId = item.tomeSpellId or FindTomeSpellIdByName(echoName)
    if (not item.requiredSpell or item.requiredSpell == 0) and item.tomeSpellId then
        item.requiredSpell = item.tomeSpellId
    end
    if item.tomeSpellId then item.tomeName = item.tomeName or ("Tome of " .. tostring(echoName)) end
    return item
end

local function AddCandidate(candidates, spellId)
    spellId = tonumber(spellId)
    if spellId and spellId > 0 then candidates[spellId] = true end
end

local function HarvestNumbers(value, candidates, depth, seen)
    if type(value) ~= "table" or depth > 5 or seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        if type(key) == "number" and key >= 100000 then AddCandidate(candidates, key) end
        if type(child) == "number" and child >= 100000 then AddCandidate(candidates, child) end
        if type(child) == "table" then HarvestNumbers(child, candidates, depth + 1, seen) end
    end
end

local function CollectPerkCandidates(peh)
    local candidates = {}
    local databaseCount = 0

    if peh and type(peh.PerkDatabase) == "table" then
        for id, data in pairs(peh.PerkDatabase) do
            if tonumber(id) then
                AddCandidate(candidates, id)
                databaseCount = databaseCount + 1
            end
            if type(data) == "table" then
                AddCandidate(candidates, data.spellId or data.spellID or data.spell or data.id)
            end
        end
    end

    if databaseCount == 0 and peh and type(peh.PerkDropSources) == "table" then
        for id in pairs(peh.PerkDropSources) do AddCandidate(candidates, id) end
    end

    if peh and peh.PerkService and type(peh.PerkService.GetGrantedPerks) == "function" then
        local ok, granted = pcall(peh.PerkService.GetGrantedPerks)
        if ok and type(granted) == "table" then
            for _, stacks in pairs(granted) do
                if type(stacks) == "table" then
                    for _, row in pairs(stacks) do
                        if type(row) == "table" then AddCandidate(candidates, row.spellId) end
                    end
                end
            end
        end
    end

    if databaseCount == 0 then
        HarvestNumbers(peh and peh.Perks, candidates, 0, {})
        HarvestNumbers(peh and peh.PerkDropSources, candidates, 0, {})
    end
    return candidates
end

local function BuildTomeMetadata(peh)
    local byEchoName = {}
    if not peh then return byEchoName end

    local function AddFrom(id, data, sourceOverride)
        local item = NormalizePerkData(id, data)
        local echoName = StripTomeName(item.name)
        if not echoName and type(data) == "table" and data.comment then
            echoName = StripTomeName(tostring(data.comment)) or CleanEchoName(data.comment)
        end
        if echoName and echoName ~= item.name then
            local key = FamilyKey(echoName)
            if key then
                byEchoName[key] = byEchoName[key] or { echoName = echoName }
                local metadata = byEchoName[key]
                metadata.tomeName = metadata.tomeName or item.name or ("Tome of " .. echoName)
                metadata.tomeSpellId = metadata.tomeSpellId or item.spellId or FindTomeSpellIdByName(echoName)
                metadata.dropSource = metadata.dropSource or sourceOverride or item.dropSource
            end
        end
    end

    if type(peh.PerkDatabase) == "table" then
        for id, data in pairs(peh.PerkDatabase) do
            if tonumber(id) then AddFrom(id, data) end
        end
    end
    if type(peh.PerkDropSources) == "table" then
        for id, source in pairs(peh.PerkDropSources) do AddFrom(id, TryGetPerkData(tonumber(id) or id), source) end
    end
    return byEchoName
end

local function MergeCatalogVariant(existing, item)
    existing.maxQuality = math.max(existing.maxQuality or existing.quality or 0, item.quality or 0)
    if (item.quality or 0) > (existing.quality or 0) then existing.quality = item.quality end
    existing.dropSource = existing.dropSource or item.dropSource
    existing.tomeName = existing.tomeName or item.tomeName
    existing.tomeSpellId = existing.tomeSpellId or item.tomeSpellId
    if (not existing.requiredSpell or existing.requiredSpell == 0) and item.requiredSpell and item.requiredSpell > 0 then
        existing.requiredSpell = item.requiredSpell
    end
    existing._variants = existing._variants or {}
    existing._variants[#existing._variants + 1] = item
end

local function BuildLocalCompatibleCatalog()
    local peh = ProjectEbonhold
    local catalog, byCleanName = {}, {}
    if not peh then return catalog end

    local tomeMetadata = BuildTomeMetadata(peh)
    local candidates = CollectPerkCandidates(peh)

    local function AddCatalogItem(item)
        if not item or not item.name or string.find(item.name, "Unknown #", 1, true) then return end
        local key = FamilyKey(item.name)
        if not key then return end
        local existing = byCleanName[key]
        if not existing then
            byCleanName[key] = item
            catalog[#catalog + 1] = item
        else
            MergeCatalogVariant(existing, item)
        end
    end

    for id in pairs(candidates) do
        local data = TryGetPerkData(id)
        local hasDropSource = peh.PerkDropSources
            and (peh.PerkDropSources[id] or peh.PerkDropSources[tostring(id)])
        if data ~= nil or hasDropSource then
            local item = NormalizePerkData(id, data)
            if item.name and not string.find(item.name, "Unknown #", 1, true) then
                local echoNameFromTome = StripTomeName(item.name)
                if echoNameFromTome then
                    local echoSpellId = FindEchoSpellIdByName(echoNameFromTome)
                    local echoData = echoSpellId and TryGetPerkData(echoSpellId) or nil
                    local echoItem = NormalizePerkData(echoSpellId or id, echoData or data)
                    echoItem.name = echoNameFromTome
                    if echoSpellId then echoItem.spellId = echoSpellId end
                    echoItem.dropSource = echoItem.dropSource or item.dropSource
                    echoItem.tomeName = item.name
                    echoItem.tomeSpellId = item.spellId or FindTomeSpellIdByName(echoNameFromTome)
                    if not echoItem.requiredSpell or echoItem.requiredSpell == 0 then
                        echoItem.requiredSpell = echoItem.tomeSpellId or 0
                    end
                    AddCatalogItem(echoItem)
                else
                    local metadata = tomeMetadata[FamilyKey(item.name)]
                    if metadata then
                        item.dropSource = item.dropSource or metadata.dropSource
                        item.tomeName = metadata.tomeName
                        item.tomeSpellId = metadata.tomeSpellId or FindTomeSpellIdByName(item.name)
                        if not item.requiredSpell or item.requiredSpell == 0 then
                            item.requiredSpell = item.tomeSpellId or 0
                        end
                    elseif item.dropSource then
                        item.tomeName = item.tomeName or ("Tome of " .. tostring(item.name))
                        item.tomeSpellId = item.tomeSpellId or FindTomeSpellIdByName(item.name)
                        if not item.requiredSpell or item.requiredSpell == 0 then
                            item.requiredSpell = item.tomeSpellId or 0
                        end
                    end
                    AddCatalogItem(item)
                end
            end
        end
    end
    return catalog
end

local function GetCompatibleCatalog()
    local reference = _G.EchoWishlist
    if type(reference) == "table" then
        if (type(reference.catalog) ~= "table" or #reference.catalog == 0)
            and type(reference.BuildCatalog) == "function" then
            pcall(reference.BuildCatalog, reference)
        end
        if type(reference.catalog) == "table" and #reference.catalog > 0 then
            return reference.catalog, "EchoWishlist"
        end
    end

    local database = ProjectEbonhold and ProjectEbonhold.PerkDatabase
    if compatibleCatalogCache and compatibleCatalogDatabase == database then
        return compatibleCatalogCache, "EbonBuilds mirror"
    end
    compatibleCatalogCache = BuildLocalCompatibleCatalog()
    compatibleCatalogDatabase = database
    return compatibleCatalogCache, "EbonBuilds mirror"
end

function EWL.InvalidateCatalog()
    compatibleCatalogCache = nil
    compatibleCatalogDatabase = nil
end

local function IndexCatalog(catalog)
    local byId, byFamily = {}, {}

    local function IndexId(row, value)
        local numeric = tonumber(value)
        if not numeric then return end
        if not byId[numeric] then byId[numeric] = row end
        if not byId[tostring(numeric)] then byId[tostring(numeric)] = row end
    end

    local function IndexFamily(row, value)
        local key = FamilyKey(value)
        if key and not byFamily[key] then byFamily[key] = row end
    end

    local function IndexItem(row, item)
        if type(item) ~= "table" then return end
        IndexId(row, item.id)
        IndexId(row, item.spellId)
        IndexId(row, item.groupId)
        IndexFamily(row, item.name)
        IndexFamily(row, item.comment)
        if type(item.raw) == "table" then
            IndexFamily(row, item.raw.name or item.raw.Name)
            IndexFamily(row, item.raw.comment or item.raw.Comment)
            IndexId(row, item.raw.id)
            IndexId(row, item.raw.spellId or item.raw.spellID or item.raw.spell)
            IndexId(row, item.raw.groupId or item.raw.group)
        end
    end

    for _, row in ipairs(catalog or {}) do
        IndexItem(row, row)
        for _, variant in ipairs(row._variants or {}) do IndexItem(row, variant) end
    end
    return byId, byFamily
end


local function GetRollStatus(item)
    if not item then return "unknown" end
    local requiredSpell = tonumber(item.requiredSpell or item.tomeSpellId or 0) or 0
    local hasTomeUnlock = item.tomeName or item.tomeSpellId or requiredSpell > 0
    if not item.dropSource and not hasTomeUnlock then return "baseline" end
    if requiredSpell > 0 then
        if IsKnownSpell(requiredSpell) then return "tome" end
        return "locked"
    end
    return "tome"
end

local function ResolveRowForSpell(byId, byFamily, spellId)
    local numeric = tonumber(spellId)
    local row = numeric and (byId[numeric] or byId[tostring(numeric)])
    if row then return row end
    local canonical = CanonicalNameForSpell(numeric)
    return canonical and byFamily[FamilyKey(canonical)] or nil
end

local function MakeFallbackLockedRow(spellId)
    local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId
        and EbonBuilds.EchoCatalog.GetBySpellId(spellId) or nil
    local data = GetPerkData(spellId)
    return {
        id = spellId, spellId = spellId,
        name = CanonicalNameForSpell(spellId) or ("spellId " .. tostring(spellId)),
        quality = variant and tonumber(variant.quality) or (data and tonumber(data.quality) or 0),
        requiredSpell = variant and tonumber(variant.requiredSpell) or (data and tonumber(data.requiredSpell) or 0),
    }
end

-- Returns one EchoWishlist-compatible catalog entry per selected Echo family.
function EWL.BuildEntries(build)
    if not build then return {}, { error = "No build selected." } end

    local classToken = string.upper(tostring(build.class or EbonBuilds.Build.PlayerClassToken() or ""))
    local catalog, catalogSource = GetCompatibleCatalog()
    local byId, byFamily = IndexCatalog(catalog)
    local entries, entriesBySpell, unresolved = {}, {}, {}

    local function AddRow(row, saved, weight, exactSpellId)
        if not row then return nil end
        local spellId = tonumber(exactSpellId or row.spellId or row.id)
        if not spellId then return nil end
        local entry = entriesBySpell[spellId]
        if not entry then
            local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
            entry = {
                row = row, spellId = spellId,
                locked = saved and true or false,
                name = CanonicalNameForSpell(spellId) or CleanEchoName(row.name) or tostring(spellId),
                quality = variant and tonumber(variant.quality) or tonumber(row.quality) or tonumber(row.maxQuality) or 0,
                rollLocked = GetRollStatus(row) == "locked",
                weight = tonumber(weight) or 0,
            }
            entriesBySpell[spellId] = entry
            entries[#entries + 1] = entry
        else
            if saved then entry.locked = true end
            if tonumber(weight) and tonumber(weight) > (entry.weight or 0) then entry.weight = tonumber(weight) end
        end
        return entry
    end

    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local spellId = build.lockedEchoes and tonumber(build.lockedEchoes[slot])
        if spellId then
            local projectionEntry, variant = EbonBuilds.EchoProjection.ResolveSpell(classToken, spellId)
            if projectionEntry and variant then
                local row = byId[spellId] or ResolveRowForSpell(byId, byFamily, spellId)
                if not row then row = MakeFallbackLockedRow(spellId) end
                AddRow(row, true, 0, spellId)
            else
                unresolved[#unresolved + 1] = {
                    name = CanonicalNameForSpell(spellId) or tostring(spellId),
                    spellId = spellId, reason = "inactive",
                }
            end
        end
    end

    if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end
    local hasRefWeights = type(build.echoWeightsByRef) == "table" and next(build.echoWeightsByRef) ~= nil
    if hasRefWeights then
        for refKey, rawWeights in pairs(build.echoWeightsByRef) do
            local weights = EbonBuilds.Weights.NormalizeEntry(rawWeights)
            if EbonBuilds.Weights.HasNonZero(weights) then
                local spellId = select(1, EbonBuilds.EchoProjection.GetBestVariant(classToken, refKey))
                local row = spellId and (byId[spellId] or ResolveRowForSpell(byId, byFamily, spellId)) or nil
                if not row and spellId then row = MakeFallbackLockedRow(spellId) end
                if row and spellId then
                    local maxWeight = nil
                    for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                        local value = EbonBuilds.Weights.GetForRef(build, refKey, quality)
                        if maxWeight == nil or value > maxWeight then maxWeight = value end
                    end
                    AddRow(row, false, maxWeight or 0, spellId)
                else
                    local definition = EbonBuilds.EchoCatalog.GetByRef(refKey)
                    unresolved[#unresolved + 1] = {
                        name = definition and definition.sourceName or refKey,
                        weights = weights,
                        reason = spellId and "catalog" or "inactive",
                    }
                end
            end
        end
    else
        for name, rawWeights in pairs(build.echoWeights or {}) do
            local weights = EbonBuilds.Weights.NormalizeEntry(rawWeights)
            if EbonBuilds.Weights.HasNonZero(weights) then
                local refs = EbonBuilds.EchoCatalog.FindLegacyRefs(name)
                local refKey = refs and #refs == 1 and refs[1] or nil
                local spellId = refKey and select(1, EbonBuilds.EchoProjection.GetBestVariant(classToken, refKey)) or nil
                local row = spellId and (byId[spellId] or ResolveRowForSpell(byId, byFamily, spellId)) or nil
                if row then
                    AddRow(row, false, EbonBuilds.Weights.MaxFromWeights(build.echoWeights, name), spellId)
                else
                    unresolved[#unresolved + 1] = {
                        name = CleanEchoName(name) or tostring(name),
                        weights = weights,
                        reason = not refKey and "ambiguous" or (spellId and "catalog" or "inactive"),
                    }
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.locked ~= b.locked then return a.locked == true end
        if a.rollLocked ~= b.rollLocked then return a.rollLocked == true end
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        local aName = string.lower(tostring(a.name or ""))
        local bName = string.lower(tostring(b.name or ""))
        if aName ~= bName then return aName < bName end
        return (a.spellId or 0) < (b.spellId or 0)
    end)

    local lockedCount = 0
    for _, entry in ipairs(entries) do if entry.locked then lockedCount = lockedCount + 1 end end
    return entries, {
        class = classToken,
        total = #entries,
        locked = lockedCount,
        normal = #entries - lockedCount,
        unresolved = unresolved,
        catalogSource = catalogSource,
    }
end

local function StoredUnresolvedCount(build)
    local count = tonumber(build and build.wizardMeta and build.wizardMeta.unresolvedRecommendations) or 0
    for _ in pairs(build and build.unresolvedEchoWeights or {}) do count = count + 1 end
    return count
end

function EWL.Generate(build)
    if not build then return nil, "No build selected." end
    local storedUnresolved = StoredUnresolvedCount(build)
    if storedUnresolved > 0 then
        return nil, string.format("UNRESOLVED_ECHO_REFERENCES: %d unresolved Echo reference(s) must be fixed before EWL export.", storedUnresolved), {
            unresolvedCount = storedUnresolved,
            unresolved = build.unresolvedEchoWeights or {},
        }
    end

    local entries, info = EWL.BuildEntries(build)
    if info.error then return nil, info.error, info end
    if info.class == "" then return nil, "The build has no class.", info end
    local unresolvedCount = info.unresolved and #info.unresolved or 0
    info.unresolvedCount = unresolvedCount
    -- EchoWishlist export has always been best-effort: valid catalog rows are
    -- exported while unmatched weighted families are omitted and surfaced in
    -- info.unresolved. The export dialog already displays that warning.
    if #entries == 0 then
        return nil, "This build has no locked or weighted Echoes to export.", info
    end

    local parts = {}
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = tostring(entry.spellId) .. ":" .. (entry.locked and "1" or "0")
    end
    return "EWL1:" .. info.class .. ":" .. table.concat(parts, ","), nil, info
end

local function CreateExportDialog()
    local frame = CreateFrame("Frame", "EbonBuildsEWLExportDialog", UIParent)
    frame:SetSize(760, 330)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Theme.ApplyWindow(frame)
    frame:Hide()

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, 0)
    drag:SetHeight(34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    title:SetText("Export Echo Wish List")
    title:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    frame._title = title

    local closeX = EbonBuilds.Theme.CreateCloseButton(frame)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    frame._summary = summary

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -5)
    help:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    help:SetJustifyH("LEFT")
    help:SetText("Locked Echo families are marked saved with :1. Every selected family uses EchoWishlist's retained catalog spell ID; weighted-only families use :0. Rows follow EchoWishlist's saved, unlock-state, quality, and name order. Press Ctrl+C to copy.")
    help:SetTextColor(unpack(Theme.TEXT_MUTED))

    local warning = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    warning:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -5)
    warning:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    warning:SetJustifyH("LEFT")
    warning:SetTextColor(unpack(Theme.WARNING))
    warning:SetText("")
    frame._warning = warning

    local inputFrame = CreateFrame("Frame", nil, frame)
    inputFrame:SetPoint("TOPLEFT", warning, "BOTTOMLEFT", 0, -8)
    inputFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 48)
    Theme.ApplyInput(inputFrame)

    local scroll = CreateFrame("ScrollFrame", nil, inputFrame)
    scroll:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", 7, -7)
    scroll:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", -7, 7)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    box:SetWidth(690)
    box:SetHeight(140)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(box)
    frame._editBox = box
    frame._scroll = scroll

    local bar = Theme.CreateScrollBar(frame)
    bar:SetPoint("TOPLEFT", inputFrame, "TOPRIGHT", 5, -2)
    bar:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOMRIGHT", 5, 2)
    bar:SetValueStep(20)
    bar:SetScript("OnValueChanged", function(_, value)
        box:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    frame._bar = bar

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local minValue, maxValue = bar:GetMinMaxValues()
        bar:SetValue(math.max(minValue, math.min(maxValue, bar:GetValue() - delta * 20)))
    end)

    local selectBtn = Theme.CreateButton(frame, "gold")
    selectBtn:SetSize(94, 24)
    selectBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -108, 13)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        box:SetFocus()
        box:HighlightText()
    end)

    local closeBtn = Theme.CreateButton(frame)
    closeBtn:SetSize(84, 24)
    closeBtn:SetPoint("LEFT", selectBtn, "RIGHT", 8, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    exportDialog = frame
end

function EWL.ShowExportDialog(build)
    local text, err, info = EWL.Generate(build)
    if not text then
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show(err or "Could not generate EWL") end
        return false, err
    end
    if not exportDialog then CreateExportDialog() end

    exportDialog._title:SetText("Export EWL · " .. (build.title or "Untitled"))
    exportDialog._summary:SetText(string.format(
        "%d EWL entries · %d saved · %d weighted",
        info.total or 0, info.locked or 0, info.normal or 0))
    local unresolvedCount = info.unresolved and #info.unresolved or 0
    if unresolvedCount > 0 then
        exportDialog._warning:SetText(string.format(
            "%d weighted Echo famil%s could not be matched to an EchoWishlist-compatible class row and %s omitted.",
            unresolvedCount, unresolvedCount == 1 and "y" or "ies", unresolvedCount == 1 and "was" or "were"))
    else
        exportDialog._warning:SetText("")
    end

    exportDialog._editBox:SetText(text)
    local estimatedLines = math.max(1, math.ceil(#text / 92))
    local contentHeight = math.max(exportDialog._scroll:GetHeight() or 120, estimatedLines * 14 + 18)
    exportDialog._editBox:SetHeight(contentHeight)
    exportDialog._editBox:ClearAllPoints()
    exportDialog._editBox:SetPoint("TOPLEFT", exportDialog._scroll, "TOPLEFT", 0, 0)
    exportDialog._bar:SetMinMaxValues(0, math.max(0, contentHeight - (exportDialog._scroll:GetHeight() or 120)))
    exportDialog._bar:SetValue(0)
    exportDialog:Show()
    exportDialog._editBox:SetFocus()
    exportDialog._editBox:HighlightText()
    return true
end
