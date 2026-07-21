local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoCatalog.lua
-- Versioned Echo identity/catalog service. It reconciles bundled MPQ identity
-- data with the live ProjectEbonhold database, exposes strict class-scoped
-- resolution, and preserves old display APIs without using comments as IDs.

EbonBuilds.EchoCatalog = {}

local Catalog = EbonBuilds.EchoCatalog
local Identity = EbonBuilds.EchoIdentity
local Static = EbonBuilds.EchoIdentityData or { groups = {}, spells = {} }
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

Catalog.STATE_UNINITIALIZED = 0
Catalog.STATE_BUNDLED_READY = 1
Catalog.STATE_RUNTIME_RECONCILING = 2
Catalog.STATE_RUNTIME_VERIFIED = 3
Catalog.STATE_RUNTIME_FAILED = 4

local bySpellId, byRef, sortedDefinitions = {}, {}, {}
local sourceNameIndex, aliasIndex = {}, {}
local descriptionCache = {}
local initialized, ready, reconciling, runtimeVerified = false, false, false, false
local catalogState = Catalog.STATE_UNINITIALIZED
local revision = 0
local runtimeFingerprint = "unverified"
local runtimeDatabaseRef, runtimeAddonVersion, runtimeModVersion, runtimePerkCount
local reconcileFailed = false
local diagnostics = {}
local reconcileState
local staticGroupByNormalizedName

-- ProjectEbonhold has shipped more than one PerkDatabase layout.  Most builds
-- expose named fields, while some enhanced/client builds expose compact array
-- records.  The catalog normalises both layouts before it creates identities.
local function RuntimeValue(data, ...)
    if type(data) ~= "table" then return nil end
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        local value = data[key]
        if value ~= nil then return value end
    end
    return nil
end

local function IsPlaceholderName(value)
    local normalized = Identity.NormalizeSearch(value)
    if normalized == "" then return true end
    if normalized == "unknown" or normalized == "unknown echo" or normalized == "unknown spell"
        or normalized == "echo" or normalized == "spell" then
        return true
    end
    return normalized:match("^unknown echo%s*#?%d*$") ~= nil
        or normalized:match("^unknown spell%s*#?%d*$") ~= nil
end

local function CleanRuntimeName(value)
    value = Identity.VisibleName(value)
    if value == "" then return "" end
    value = Identity.StripClassPrefix(Identity.StripQualitySuffix(value))
    if IsPlaceholderName(value) then return "" end
    return value
end

local function BuildStaticGroupNameIndex()
    if staticGroupByNormalizedName then return end
    staticGroupByNormalizedName = {}
    for groupId, group in pairs(Static.groups or {}) do
        local normalized = Identity.NormalizeSearch(group and group[1])
        if normalized ~= "" then
            local existing = staticGroupByNormalizedName[normalized]
            if existing == nil then
                staticGroupByNormalizedName[normalized] = tonumber(groupId)
            elseif existing ~= tonumber(groupId) then
                -- A duplicated display name is not safe to use as an identity.
                staticGroupByNormalizedName[normalized] = false
            end
        end
    end
end

local function StaticGroupForName(value)
    local cleaned = CleanRuntimeName(value)
    if cleaned == "" then return nil end
    BuildStaticGroupNameIndex()
    local groupId = staticGroupByNormalizedName[Identity.NormalizeSearch(cleaned)]
    return type(groupId) == "number" and groupId or nil
end

local function RuntimeRecord(spellId, data, bundled)
    local explicitName = RuntimeValue(data, "displayName", "name", "Name", "perkName", "echoName")
    local comment = RuntimeValue(data, "comment", "Comment", "internalComment", "descriptionName", 7)
    local groupId = tonumber(RuntimeValue(data, "groupId", "groupID", "GroupID", "group", "GroupId", 5))
        or (bundled and bundled.groupId)

    -- Some runtime tables omit groupId even though their comment still carries
    -- the canonical Echo name.  Recover the stable bundled group rather than
    -- creating one s:<spellId> row for every rank and class variant.
    if not groupId or groupId <= 0 then
        groupId = StaticGroupForName(explicitName) or StaticGroupForName(comment)
    end
    if groupId and groupId <= 0 then groupId = nil end

    local group = groupId and Static.groups and Static.groups[groupId]
    local sourceName = group and group[1] or CleanRuntimeName(explicitName)
    if not sourceName or sourceName == "" then sourceName = CleanRuntimeName(comment) end
    if not sourceName or sourceName == "" then sourceName = nil end

    local classMask = tonumber(RuntimeValue(data, "classMask", "ClassMask", "classes", "class", 2))
        or (bundled and bundled.classMask) or 0
    local quality = tonumber(RuntimeValue(data, "quality", "Quality", "rarity", "perkQuality", 4))
        or (bundled and bundled.quality) or 0
    local requiredSpell = tonumber(RuntimeValue(data, "requiredSpell", "RequiredSpell", "required", 6))
        or (bundled and bundled.requiredSpell) or 0
    local families = RuntimeValue(data, "families", "Families", 8)

    return {
        spellId = spellId,
        groupId = groupId,
        quality = quality,
        classMask = classMask,
        staticClassMask = bundled and bundled.classMask or classMask,
        requiredSpell = requiredSpell,
        internalComment = comment,
        sourceName = sourceName,
        descriptionHash = bundled and bundled.descriptionHash or (group and group[2]) or 0,
        families = type(families) == "table" and families or {},
        runtimePresent = true,
    }
end

local function ClearTable(t)
    for key in pairs(t) do t[key] = nil end
end

local function AddIndex(index, normalized, refKey)
    if not normalized or normalized == "" or not refKey then return end
    local bucket = index[normalized]
    if not bucket then bucket = {}; index[normalized] = bucket end
    if not bucket[refKey] then bucket[refKey] = true end
end

local function DefinitionFor(refKey, groupId, sourceName, descriptionHash)
    local definition = byRef[refKey]
    if not definition then
        definition = {
            key = refKey,
            refKey = refKey,
            groupId = tonumber(groupId),
            sourceName = Identity.VisibleName(sourceName),
            name = Identity.VisibleName(sourceName),
            descriptionHash = tonumber(descriptionHash) or 0,
            aliases = {}, aliasSet = {}, rawAliases = {}, rawAliasSet = {},
            variants = {}, variantsBySpellId = {},
            qualities = {}, spellIds = {}, familySet = {},
            classMask = 0,
            availabilityConflict = false,
        }
        byRef[refKey] = definition
    elseif (not definition.sourceName or definition.sourceName == "") and sourceName then
        definition.sourceName = Identity.VisibleName(sourceName)
        definition.name = definition.sourceName
    end
    return definition
end

local function AddAlias(definition, alias)
    alias = Identity.VisibleName(alias)
    if alias == "" then return end
    local normalized = Identity.NormalizeSearch(alias)
    if normalized == "" then return end
    definition.rawAliases = definition.rawAliases or {}
    definition.rawAliasSet = definition.rawAliasSet or {}
    if not definition.rawAliasSet[normalized] then
        definition.rawAliasSet[normalized] = true
        definition.rawAliases[#definition.rawAliases + 1] = alias
    end
end

local function ChooseLocalizedName(spellId, fallback)
    local name = GetSpellInfo and GetSpellInfo(spellId)
    name = Identity.VisibleName(name)
    -- Custom Echo spell records can legitimately return the client placeholder
    -- "Unknown Echo" while still providing a valid icon.  Never let that
    -- placeholder replace the canonical bundled/comment name.
    if not IsPlaceholderName(name) then return name end
    fallback = Identity.VisibleName(fallback)
    return not IsPlaceholderName(fallback) and fallback or ""
end

local function AddVariant(record, sourceKind)
    local spellId = tonumber(record.spellId)
    if not spellId then return nil end
    local groupId = tonumber(record.groupId)
    local refKey = Identity.RefKey(groupId, spellId)
    if not refKey then return nil end

    local bundledGroup = groupId and Static.groups and Static.groups[groupId]
    local sourceName = Identity.VisibleName(record.sourceName or (bundledGroup and bundledGroup[1]))
    if IsPlaceholderName(sourceName) then sourceName = "" end
    if sourceName == "" then sourceName = CleanRuntimeName(record.internalComment) end
    if sourceName == "" then sourceName = ChooseLocalizedName(spellId, "") end
    if sourceName == "" then sourceName = "Echo #" .. tostring(spellId) end

    local definition = DefinitionFor(refKey, groupId, sourceName,
        record.descriptionHash or (bundledGroup and bundledGroup[2]))
    definition.familySet = definition.familySet or {}
    definition.aliasSet = definition.aliasSet or {}
    definition.rawAliases = definition.rawAliases or {}
    definition.rawAliasSet = definition.rawAliasSet or {}
    local localizedName = ChooseLocalizedName(spellId, sourceName)
    local runtimeMask = tonumber(record.classMask) or 0
    local staticMask = tonumber(record.staticClassMask) or runtimeMask
    local availabilityConflict = record.runtimePresent and staticMask ~= 0 and runtimeMask ~= 0 and staticMask ~= runtimeMask
    if availabilityConflict then definition.availabilityConflict = true end

    local tuple = EbonBuilds.EchoSemantics and select(1, EbonBuilds.EchoSemantics.GetBySpellId(spellId)) or nil
    local variant = definition.variantsBySpellId[spellId]
    if not variant then
        variant = {
            spellId = spellId,
            refKey = refKey,
            groupId = groupId,
            quality = tonumber(record.quality) or 0,
            classMask = runtimeMask,
            staticClassMask = staticMask,
            requiredSpell = tonumber(record.requiredSpell) or 0,
            internalComment = Identity.VisibleName(record.internalComment),
            sourceName = sourceName,
            localizedName = localizedName,
            name = sourceName,
            icon = (select(3, GetSpellInfo(spellId))) or QUESTION_ICON,
            semantics = tuple,
            families = record.families or {},
            sourceKind = sourceKind,
            runtimePresent = record.runtimePresent == true,
            availabilityConflict = availabilityConflict,
        }
        definition.variantsBySpellId[spellId] = variant
        definition.variants[#definition.variants + 1] = variant
    else
        variant.classMask = runtimeMask
        variant.runtimePresent = record.runtimePresent == true
        variant.availabilityConflict = availabilityConflict
        variant.internalComment = Identity.VisibleName(record.internalComment or variant.internalComment)
        variant.localizedName = localizedName ~= "" and localizedName or variant.localizedName
        variant.families = record.families or variant.families or {}
        variant.sourceKind = sourceKind or variant.sourceKind
    end

    bySpellId[spellId] = variant
    local quality = variant.quality
    definition.qualities[quality] = true
    local previousId = definition.spellIds[quality]
    if not previousId or spellId < previousId then definition.spellIds[quality] = spellId end
    definition.classMask = bit.bor(definition.classMask or 0, variant.classMask or 0)
    if not definition.spellId or quality > (definition.quality or -1)
        or (quality == definition.quality and spellId < definition.spellId) then
        definition.spellId, definition.quality = spellId, quality
        definition.icon, definition.semantics = variant.icon, variant.semantics
    end
    for _, family in ipairs(variant.families or {}) do definition.familySet[family] = true end

    AddAlias(definition, sourceName)
    AddAlias(definition, localizedName)
    AddAlias(definition, variant.internalComment)
    AddAlias(definition, Identity.StripClassPrefix(Identity.StripQualitySuffix(variant.internalComment)))
    return variant
end

local function FinalizeIndexes()
    ClearTable(sortedDefinitions)
    ClearTable(sourceNameIndex)
    ClearTable(aliasIndex)
    for _, definition in pairs(byRef) do
        table.sort(definition.variants, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            return a.spellId < b.spellId
        end)
        local families = {}
        for family in pairs(definition.familySet or {}) do families[#families + 1] = family end
        table.sort(families)
        definition.families = families
        definition.canonicalName = definition.sourceName
        definition.name = definition.sourceName
        definition.icon = definition.icon or QUESTION_ICON
        sortedDefinitions[#sortedDefinitions + 1] = definition
    end
    table.sort(sortedDefinitions, function(a, b)
        local an, bn = string.lower(a.sourceName or ""), string.lower(b.sourceName or "")
        if an ~= bn then return an < bn end
        return tostring(a.refKey) < tostring(b.refKey)
    end)

    if EbonBuilds.EchoIdentityResolver and EbonBuilds.EchoIdentityResolver.Finalize then
        EbonBuilds.EchoIdentityResolver.Finalize(sortedDefinitions)
    else
        for _, definition in ipairs(sortedDefinitions) do
            definition.displayName = definition.sourceName
            definition.aliases = definition.rawAliases or {}
        end
    end

    for _, definition in ipairs(sortedDefinitions) do
        local blobParts = {}
        local function Blob(value)
            value = Identity.NormalizeSearch(value)
            if value ~= "" then blobParts[#blobParts + 1] = value end
        end
        Blob(definition.displayName)
        Blob(definition.sourceName)
        Blob(definition.refKey)
        for _, alias in ipairs(definition.aliases or {}) do Blob(alias) end
        for _, variant in ipairs(definition.variants or {}) do Blob(variant.spellId) end
        definition.searchBlob = table.concat(blobParts, "\31")
        AddIndex(sourceNameIndex, Identity.NormalizeSearch(definition.sourceName), definition.refKey)
        for _, alias in ipairs(definition.aliases or {}) do
            AddIndex(aliasIndex, Identity.NormalizeSearch(alias), definition.refKey)
        end
    end
end

local function ResetCatalog()
    ClearTable(bySpellId); ClearTable(byRef); ClearTable(sortedDefinitions)
    ClearTable(sourceNameIndex); ClearTable(aliasIndex); ClearTable(descriptionCache)
end

local function BuildBundled(bumpRevision)
    ResetCatalog()
    for spellId, raw in pairs(Static.spells or {}) do
        local group = Static.groups and Static.groups[tonumber(raw[1])]
        AddVariant({
            spellId = spellId,
            groupId = raw[1], quality = raw[2],
            classMask = raw[3], staticClassMask = raw[3],
            requiredSpell = raw[4], internalComment = raw[5],
            sourceName = group and group[1], descriptionHash = group and group[2],
            runtimePresent = false,
        }, "BUNDLED")
    end
    FinalizeIndexes()
    if bumpRevision ~= false then revision = revision + 1 end
    ready = true
    catalogState = Catalog.STATE_BUNDLED_READY
end

local function HashText(hash, value)
    value = tostring(value or "")
    for index = 1, #value do hash = (hash * 33 + value:byte(index)) % 4294967296 end
    return hash
end

local function Hex32(value)
    local digits, out = "0123456789abcdef", {}
    value = value % 4294967296
    for index = 8, 1, -1 do
        local nibble = value % 16
        out[index] = digits:sub(nibble + 1, nibble + 1)
        value = math.floor(value / 16)
    end
    return table.concat(out)
end

local function StartRuntimeReconcile(reason)
    local database = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetPerkDatabase()
        or (ProjectEbonhold and ProjectEbonhold.PerkDatabase)
    if type(database) ~= "table" then
        diagnostics.runtimeUnavailable = true
        reconciling = false
        reconcileFailed = true
        catalogState = Catalog.STATE_RUNTIME_FAILED
        if EbonBuilds.EventHub then
            EbonBuilds.EventHub.Bump("ECHO_RECONCILIATION_FAILED", revision, "RUNTIME_DATABASE_UNAVAILABLE")
        end
        return false
    end

    -- Rebuild the bundled baseline before every full reconciliation so a
    -- runtime-only Echo removed by a later ProjectEbonhold revision cannot
    -- remain indefinitely in the catalog.
    BuildBundled(false)

    local ids = {}
    for rawId in pairs(database) do
        local id = tonumber(rawId)
        if id then ids[#ids + 1] = id end
    end
    table.sort(ids)
    reconcileState = {
        database = database, ids = ids, index = 1, hash = 5381,
        runtimeSeen = {}, reason = reason or "refresh",
    }
    runtimeDatabaseRef = database
    reconciling = true
    runtimeVerified = false
    catalogState = Catalog.STATE_RUNTIME_RECONCILING
    diagnostics.runtimeUnavailable = nil

    local function Slice()
        local state = reconcileState
        if not state then reconciling = false; return false end
        local started = debugprofilestop and debugprofilestop() or nil
        local processed = 0
        while state.index <= #state.ids and processed < 64 do
            local spellId = state.ids[state.index]
            state.index = state.index + 1
            processed = processed + 1
            local data = state.database[spellId] or state.database[tostring(spellId)]
            if type(data) == "table" then
                local bundled = Identity.GetBundledSpell(spellId)
                local record = RuntimeRecord(spellId, data, bundled)
                local variant = AddVariant(record, bundled and "MATCHED" or "RUNTIME")
                if variant then state.runtimeSeen[spellId] = true end
                state.hash = HashText(state.hash, spellId)
                state.hash = HashText(state.hash, record.groupId)
                state.hash = HashText(state.hash, record.quality)
                state.hash = HashText(state.hash, record.classMask)
                state.hash = HashText(state.hash, record.requiredSpell)
                state.hash = HashText(state.hash, record.sourceName)
                state.hash = HashText(state.hash, record.internalComment)
            end
            if started and debugprofilestop and debugprofilestop() - started >= 1.0 then break end
        end
        if state.index <= #state.ids then
            EbonBuilds.Scheduler.After("echoCatalog.reconcile", 0, Slice, EbonBuilds.Scheduler.BACKGROUND, true)
            return false
        end

        diagnostics.runtimeOnly, diagnostics.bundledOnly = 0, 0
        diagnostics.unknownAvailability, diagnostics.classMaskConflicts = 0, 0
        for spellId, variant in pairs(bySpellId) do
            if variant.sourceKind == "RUNTIME" then diagnostics.runtimeOnly = diagnostics.runtimeOnly + 1 end
            if not state.runtimeSeen[spellId] then
                variant.runtimePresent = false
                if variant.sourceKind == "BUNDLED" then diagnostics.bundledOnly = diagnostics.bundledOnly + 1 end
            end
            if (tonumber(variant.classMask) or 0) == 0 then diagnostics.unknownAvailability = diagnostics.unknownAvailability + 1 end
            if variant.availabilityConflict then diagnostics.classMaskConflicts = diagnostics.classMaskConflicts + 1 end
        end
        FinalizeIndexes()
        runtimeFingerprint = string.format("eh%s-%d-%d-%s",
            tostring(EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetAddonVersion() or "?"),
            #state.ids, #sortedDefinitions, Hex32(state.hash))
        revision = revision + 1
        runtimeAddonVersion = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetAddonVersion() or nil
        runtimeModVersion = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetModVersion() or nil
        runtimePerkCount = #state.ids
        reconcileFailed = false
        runtimeVerified = true
        ready, reconciling, reconcileState = true, false, nil
        catalogState = Catalog.STATE_RUNTIME_VERIFIED
        if EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.Invalidate then
            EbonBuilds.EchoProjection.Invalidate()
        end
        if EbonBuilds.EventHub then
            EbonBuilds.EventHub.Bump("ECHO_IDENTITY_CHANGED", EbonBuilds.EchoIdentityResolver and EbonBuilds.EchoIdentityResolver.GetRevision() or revision)
            EbonBuilds.EventHub.Bump("ECHO_CATALOG_CHANGED", revision, runtimeFingerprint, #state.ids)
            EbonBuilds.EventHub.Bump("ECHO_DIAGNOSTICS_CHANGED", revision)
        end
        return false
    end

    EbonBuilds.Scheduler.After("echoCatalog.reconcile", 0, Slice, EbonBuilds.Scheduler.BACKGROUND, true)
    return true
end

function Catalog.Init()
    if initialized then return end
    initialized = true
    BuildBundled(true)
    StartRuntimeReconcile("init")
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("ECHO_CATALOG_READY", revision, Static.SOURCE_FINGERPRINT)
    end
end

function Catalog.Refresh(reason)
    if not initialized then Catalog.Init(); return true end
    return StartRuntimeReconcile(reason or "manual")
end

function Catalog.Invalidate(reason)
    ClearTable(descriptionCache)
    return Catalog.Refresh(reason or "invalidate")
end

function Catalog.IsReady() return ready end
function Catalog.GetState() return catalogState end
function Catalog.IsBundledReady() return catalogState >= Catalog.STATE_BUNDLED_READY end
function Catalog.IsRuntimeVerified() return catalogState == Catalog.STATE_RUNTIME_VERIFIED end
function Catalog.IsReconciling() return catalogState == Catalog.STATE_RUNTIME_RECONCILING end
function Catalog.GetRevision() if not initialized then Catalog.Init() end; return revision end
function Catalog.GetFingerprint() return runtimeFingerprint ~= "unverified" and runtimeFingerprint or Static.SOURCE_FINGERPRINT end
function Catalog.GetBundledFingerprint() return Static.SOURCE_FINGERPRINT end
function Catalog.GetDiagnostics()
    diagnostics.identityConflicts = EbonBuilds.EchoIdentityResolver
        and EbonBuilds.EchoIdentityResolver.GetDiagnostics() or nil
    diagnostics.catalogState = catalogState
    return diagnostics
end

function Catalog.GetBySpellId(spellId)
    if not initialized then Catalog.Init() end
    return bySpellId[tonumber(spellId)]
end

function Catalog.GetByRef(refKey)
    if not initialized then Catalog.Init() end
    return byRef[tostring(refKey or "")]
end

function Catalog.GetRefForSpell(spellId)
    local variant = Catalog.GetBySpellId(spellId)
    return variant and variant.refKey or nil
end

local function RefsFromBucket(bucket)
    local refs = {}
    for refKey in pairs(bucket or {}) do refs[#refs + 1] = refKey end
    table.sort(refs)
    return refs
end

function Catalog.FindRefs(name)
    if not initialized then Catalog.Init() end
    if EbonBuilds.EchoIdentityResolver and EbonBuilds.EchoIdentityResolver.FindRefs then
        return EbonBuilds.EchoIdentityResolver.FindRefs(name)
    end
    local normalized = Identity.NormalizeSearch(name)
    if normalized == "" then return {} end
    local combined = {}
    for refKey in pairs(sourceNameIndex[normalized] or {}) do combined[refKey] = true end
    for refKey in pairs(aliasIndex[normalized] or {}) do combined[refKey] = true end
    return RefsFromBucket(combined)
end

function Catalog.FindLegacyRefs(name)
    if not initialized then Catalog.Init() end
    if EbonBuilds.EchoIdentityResolver and EbonBuilds.EchoIdentityResolver.FindLegacyRefs then
        return EbonBuilds.EchoIdentityResolver.FindLegacyRefs(name)
    end
    return Catalog.FindRefs(name)
end

function Catalog.GetByNameAll(name)
    local out = {}
    for _, refKey in ipairs(Catalog.FindRefs(name)) do
        local definition = byRef[refKey]
        if definition then out[#out + 1] = definition end
    end
    return out
end

function Catalog.GetByName(name)
    local definitions = Catalog.GetByNameAll(name)
    return definitions[1]
end

local function IsVariantAvailable(variant, classToken)
    if EbonBuilds.EchoEligibilityResolver then
        local availability = EbonBuilds.EchoEligibilityResolver.ResolveVariant(variant, classToken)
        return EbonBuilds.EchoEligibilityResolver.IsAvailableState(availability)
    end
    local bitValue = CLASS_BITS[tostring(classToken or ""):upper()]
    local mask = tonumber(variant and variant.classMask) or 0
    return bitValue and mask ~= 0 and bit.band(mask, bitValue) ~= 0 or false
end

function Catalog.GetAvailability(variantOrSpellId, classToken)
    local variant = type(variantOrSpellId) == "table" and variantOrSpellId or Catalog.GetBySpellId(variantOrSpellId)
    if EbonBuilds.EchoEligibilityResolver then
        return EbonBuilds.EchoEligibilityResolver.ResolveVariant(variant, classToken)
    end
    if not variant then return Identity.UNKNOWN end
    local bitValue = CLASS_BITS[tostring(classToken or ""):upper()]
    local mask = tonumber(variant.classMask) or 0
    if not bitValue or mask == 0 then return Identity.UNKNOWN end
    return bit.band(mask, bitValue) ~= 0 and Identity.AVAILABLE or Identity.UNAVAILABLE
end

function Catalog.GetBestByRef(refKey, classToken, preferredId)
    if classToken and EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.GetBestVariant then
        return EbonBuilds.EchoProjection.GetBestVariant(classToken, refKey, preferredId)
    end
    local definition = Catalog.GetByRef(refKey)
    if not definition then return nil, 0, nil, nil end
    preferredId = tonumber(preferredId)
    if preferredId then
        local preferred = definition.variantsBySpellId[preferredId]
        if preferred then return preferred.spellId, preferred.quality, definition, preferred end
    end
    local variant = definition.variants and definition.variants[1]
    return variant and variant.spellId or nil, variant and variant.quality or 0, definition, variant
end

function Catalog.GetBest(nameOrRef, classToken, preferredId)
    if tostring(nameOrRef or ""):match("^[gs]:%d+$") then
        return Catalog.GetBestByRef(nameOrRef, classToken, preferredId)
    end
    preferredId = tonumber(preferredId)
    if preferredId then
        local preferred = Catalog.GetBySpellId(preferredId)
        if preferred and (not classToken or IsVariantAvailable(preferred, classToken)) then
            local normalized = Identity.NormalizeSearch(nameOrRef)
            if normalized == "" or normalized == Identity.NormalizeSearch(preferred.sourceName)
                or (preferred.internalComment and normalized == Identity.NormalizeSearch(preferred.internalComment)) then
                return preferred.spellId, preferred.quality, byRef[preferred.refKey], preferred
            end
        end
    end
    for _, refKey in ipairs(Catalog.FindRefs(nameOrRef)) do
        local spellId, quality, definition, variant = Catalog.GetBestByRef(refKey, classToken)
        if spellId then return spellId, quality, definition, variant end
    end
    return nil, 0, nil, nil
end

function Catalog.GetGlobalRepresentative(refKeyOrName)
    local definition = Catalog.GetByRef(refKeyOrName) or Catalog.GetByName(refKeyOrName)
    if not definition then return nil, 0, nil, nil end
    local variant = definition.variants and definition.variants[1]
    return variant and variant.spellId or nil, variant and variant.quality or 0, definition, variant
end

function Catalog.GetSortedList()
    if not initialized then Catalog.Init() end
    return sortedDefinitions
end

function Catalog.Search(query, classToken)
    local normalized = Identity.NormalizeSearch(query)
    local source = classToken and EbonBuilds.EchoProjection and EbonBuilds.EchoProjection.GetAvailable(classToken)
        or Catalog.GetSortedList()
    if normalized == "" then return source end
    local out = {}
    for _, entry in ipairs(source or {}) do
        if string.find(entry.searchBlob or "", normalized, 1, true) then out[#out + 1] = entry end
    end
    return out
end

function Catalog.GetDescription(spellId, maxLength, stacks)
    spellId = tonumber(spellId)
    maxLength = tonumber(maxLength) or 500
    stacks = tonumber(stacks) or 1
    if not spellId then return nil end
    local key = tostring(spellId) .. ":" .. tostring(stacks) .. ":" .. tostring(maxLength)
    if descriptionCache[key] then return descriptionCache[key] end
    local description = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetSpellDescription(spellId, maxLength, stacks) or nil
    if description and description ~= "" then descriptionCache[key] = description end
    return description
end

function Catalog.GetSemanticSummary(spellId, maxParts)
    local entry = Catalog.GetBySpellId(spellId)
    if not entry or not EbonBuilds.EchoSemantics then return "Unclassified" end
    return EbonBuilds.EchoSemantics.Summary(entry.semantics, maxParts)
end

function Catalog.IsAvailableForClass(entryOrSpellId, classToken)
    local variant = type(entryOrSpellId) == "table" and entryOrSpellId or Catalog.GetBySpellId(entryOrSpellId)
    return Catalog.GetAvailability(variant, classToken) == Identity.AVAILABLE
        or Catalog.GetAvailability(variant, classToken) == Identity.CONFLICTED
end

local function OnCatalogLifecycleEvent(event)
    if not initialized then return end
    if event == "PLAYER_LOGIN" then
        Catalog.Refresh("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local database = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetPerkDatabase()
        local addonVersion = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetAddonVersion() or nil
        local modVersion = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetModVersion() or nil
        local count = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetTotalPerkCount() or 0
        if not ready or reconcileFailed or database ~= runtimeDatabaseRef
            or addonVersion ~= runtimeAddonVersion or modVersion ~= runtimeModVersion
            or count ~= runtimePerkCount then
            Catalog.Refresh("PLAYER_ENTERING_WORLD")
        end
    elseif event == "SPELLS_CHANGED" then
        -- SPELLS_CHANGED is notoriously chatty -- it can fire well over a
        -- hundred times in under a second during login/zoning bursts (this
        -- is exactly what core/Debug.lua's new event-spam detection caught
        -- in the wild: 120+ fires/sec here). Clearing the cache is cheap
        -- once, but pointless to redo on every single fire in a burst --
        -- debounced via the Scheduler's keyed rescheduling: each fire just
        -- pushes the actual clear out, so it runs once after the burst
        -- settles instead of once per fire.
        EbonBuilds.Scheduler.After("EchoCatalog.ClearDescriptionCache", 0.5, function()
            ClearTable(descriptionCache)
        end, EbonBuilds.Scheduler.BACKGROUND)
    end
end

if EbonBuilds.WoWEvents then
    EbonBuilds.WoWEvents.On("PLAYER_LOGIN", OnCatalogLifecycleEvent, "EchoCatalog")
    EbonBuilds.WoWEvents.On("PLAYER_ENTERING_WORLD", OnCatalogLifecycleEvent, "EchoCatalog")
    -- spam-exempt: SPELLS_CHANGED legitimately fires 120+ times/sec during
    -- login/zoning bursts (this is exactly what triggered 3.63's debounce
    -- fix and 3.66's spam-exempt fix in the pre-WoWEvents version).
    EbonBuilds.WoWEvents.On("SPELLS_CHANGED", OnCatalogLifecycleEvent, "EchoCatalog", false, true)
end
