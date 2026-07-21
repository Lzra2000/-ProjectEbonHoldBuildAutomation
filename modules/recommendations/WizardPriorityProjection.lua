local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/WizardPriorityProjection.lua
-- Generation-safe projection for the grouped Build Wizard Echo selector.
-- Static canonical membership is cached per class/catalog revision; dynamic
-- views are rebuilt from the revisioned WizardDraft and atomically published.

EbonBuilds.WizardPriorityProjection = {}

local Projection = EbonBuilds.WizardPriorityProjection
local Grouping = EbonBuilds.EchoGrouping
local EchoProjection = EbonBuilds.EchoProjection
local Identity = EbonBuilds.EchoIdentity
local Draft = EbonBuilds.WizardDraft

Projection.VIEW_RECOMMENDED   = "RECOMMENDED"
Projection.VIEW_INCLUDED      = "INCLUDED"
Projection.VIEW_MODIFIED      = "MODIFIED"
Projection.VIEW_BUILD_CHANGING = "BUILD_CHANGING"
Projection.VIEW_GROUP         = "GROUP"
Projection.VIEW_DIAGNOSTICS   = "DIAGNOSTICS"
Projection.VIEW_SEARCH        = "SEARCH"

Projection.DIAG_UNCLASSIFIED = "UNCLASSIFIED"
Projection.DIAG_UNVERIFIED   = "UNVERIFIED"
Projection.DIAG_CONFLICTS    = "CONFLICTS"
Projection.DIAG_UNAVAILABLE  = "UNAVAILABLE"
Projection.DIAG_IMPORTS      = "IMPORTS"

Projection.SORT_RECOMMENDATION = "RECOMMENDATION"
Projection.SORT_NAME           = "NAME"
Projection.SORT_EVIDENCE       = "EVIDENCE"
Projection.SORT_PRIORITY       = "PRIORITY"
Projection.SORT_INCLUDED       = "INCLUDED"

local IMPORTANCE_RANK = { Essential = 5, Strong = 4, Useful = 3, Neutral = 2, Avoid = 1 }
local SOURCE_RANK = { priority = 4, defensive = 3, avoid = 2, suggested = 2, catalog = 1, manual = 1 }
local membershipCache = {}

local sortModel, sortDraft, sortView

local function WipeArray(list)
    for index = #list, 1, -1 do list[index] = nil end
end

local function NewCanonical()
    local canonical = {}
    for _, groupID in ipairs(Grouping.GROUP_ORDER) do canonical[groupID] = {} end
    return canonical
end

local function BuildMembership(classToken)
    classToken = tostring(classToken or ""):upper()
    local classProjection = EchoProjection.Get(classToken)
    local catalogRevision = classProjection.catalogRevision or 0
    local identityRevision = classProjection.identityRevision or 0
    local eligibilityRevision = classProjection.eligibilityRevision or 0
    local sourceInfo = EbonBuilds.EchoSemantics and EbonBuilds.EchoSemantics.SourceInfo()
    local semanticsKey = tostring(sourceInfo and sourceInfo.sourceFingerprint or "none")
        .. ":" .. tostring(sourceInfo and sourceInfo.runtimeAddonVersion or "none")
    local existing = membershipCache[classToken]
    if existing and existing.catalogRevision == catalogRevision
        and existing.identityRevision == identityRevision
        and existing.eligibilityRevision == eligibilityRevision
        and existing.semanticsKey == semanticsKey then
        return existing
    end

    local membership = {
        classToken = classToken,
        catalogRevision = catalogRevision,
        identityRevision = identityRevision,
        eligibilityRevision = eligibilityRevision,
        semanticsKey = semanticsKey,
        canonical = NewCanonical(),
        primaryGroupByRef = {},
        provenanceByRef = {},
        buildChanging = {},
        groupCounts = {},
        unverified = {}, conflicts = {}, unavailable = {},
        availableCount = classProjection.availableCount or 0,
        unverifiedCount = classProjection.unverifiedCount or 0,
        conflictCount = classProjection.conflictedCount or 0,
        unavailableCount = classProjection.unavailableCount or 0,
        fullCount = classProjection.fullCount or 0,
        reconciliationOK = true,
    }

    local seen = {}
    local canonicalCount = 0
    for _, entry in ipairs(classProjection.available or {}) do
        local groupID, provenance = Grouping.Resolve(entry)
        groupID = tonumber(groupID) or Grouping.GROUP_UNCLASSIFIED
        local list = membership.canonical[groupID] or membership.canonical[Grouping.GROUP_UNCLASSIFIED]
        if seen[entry.refKey] then
            membership.reconciliationOK = false
        else
            seen[entry.refKey] = groupID
            list[#list + 1] = entry.refKey
            canonicalCount = canonicalCount + 1
        end
        membership.primaryGroupByRef[entry.refKey] = groupID
        membership.provenanceByRef[entry.refKey] = provenance
        if Grouping.IsBuildChanging(entry) then
            membership.buildChanging[#membership.buildChanging + 1] = entry.refKey
        end
    end

    for _, groupID in ipairs(Grouping.GROUP_ORDER) do
        membership.groupCounts[groupID] = #(membership.canonical[groupID] or {})
    end
    for _, entry in ipairs(classProjection.unverified or {}) do membership.unverified[#membership.unverified + 1] = entry.refKey end
    for _, entry in ipairs(classProjection.conflicted or {}) do membership.conflicts[#membership.conflicts + 1] = entry.refKey end
    for _, entry in ipairs(classProjection.unavailable or {}) do membership.unavailable[#membership.unavailable + 1] = entry.refKey end

    if canonicalCount ~= membership.availableCount then
        membership.reconciliationOK = false
    end
    if membership.availableCount + membership.unverifiedCount + membership.unavailableCount ~= membership.fullCount then
        membership.reconciliationOK = false
    end
    membership.canonicalCount = canonicalCount
    membershipCache[classToken] = membership

    if not membership.reconciliationOK and EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("ECHO_RECONCILIATION_FAILED", classToken, canonicalCount, membership.availableCount)
    end
    return membership
end

function Projection.Invalidate()
    for key in pairs(membershipCache) do membershipCache[key] = nil end
end

function Projection.NewViewState()
    return {
        activeView = Projection.VIEW_RECOMMENDED,
        activeGroup = Grouping.GROUP_DAMAGE,
        activeSubgroup = Grouping.SUBGROUP_ALL,
        diagnosticKey = Projection.DIAG_UNCLASSIFIED,
        searchText = "",
        searchAllGroups = true,
        sortKey = Projection.SORT_RECOMMENDATION,
        sortDescending = true,
        scrollByView = {},
        visibleGeneration = 0,
        activeKeys = {},
        stagingKeys = {},
        outsideGroupMatches = 0,
    }
end

function Projection.NewModel()
    return {
        classToken = nil,
        catalogRevision = 0,
        draftRevision = 0,
        contextGeneration = 0,
        publishedGeneration = 0,
        membership = nil,
        recommended = {}, included = {}, modified = {},
        unresolvedKeys = {},
        counts = {},
        snapshotLookup = nil,
    }
end

local function IsModified(echo)
    return echo and (echo.included ~= echo.suggestedIncluded or echo.importance ~= echo.suggestedImportance)
end

local function IsRecommended(echo)
    return echo and (echo.sourceKind ~= "catalog" or echo.suggestedIncluded == true
        or (echo.suggestedImportance and echo.suggestedImportance ~= "Neutral"))
end

local function RefreshDynamic(model, draft)
    WipeArray(model.recommended)
    WipeArray(model.included)
    WipeArray(model.modified)
    model.groupIncluded = model.groupIncluded or {}
    for _, groupID in ipairs(Grouping.GROUP_ORDER) do model.groupIncluded[groupID] = 0 end
    for _, refKey in ipairs(draft.echoOrder or {}) do
        local echo = draft.echoes[refKey]
        if echo then
            if IsRecommended(echo) then model.recommended[#model.recommended + 1] = refKey end
            if echo.included then
                model.included[#model.included + 1] = refKey
                local groupID = model.membership and model.membership.primaryGroupByRef[refKey]
                if groupID then model.groupIncluded[groupID] = (model.groupIncluded[groupID] or 0) + 1 end
            end
            if IsModified(echo) then model.modified[#model.modified + 1] = refKey end
        end
    end

    local unresolvedCount = Draft.UnresolvedCount and Draft.UnresolvedCount(draft) or 0
    for index = #model.unresolvedKeys, unresolvedCount + 1, -1 do model.unresolvedKeys[index] = nil end
    for index = 1, unresolvedCount do
        if not model.unresolvedKeys[index] then model.unresolvedKeys[index] = "u:" .. tostring(index) end
    end
end

local function SourceList(model, viewState)
    local membership = model.membership
    if viewState.activeView == Projection.VIEW_RECOMMENDED then return model.recommended end
    if viewState.activeView == Projection.VIEW_INCLUDED then return model.included end
    if viewState.activeView == Projection.VIEW_MODIFIED then return model.modified end
    if viewState.activeView == Projection.VIEW_BUILD_CHANGING then return membership.buildChanging end
    if viewState.activeView == Projection.VIEW_GROUP then
        return membership.canonical[viewState.activeGroup] or membership.canonical[Grouping.GROUP_OTHER]
    end
    if viewState.activeView == Projection.VIEW_DIAGNOSTICS then
        if viewState.diagnosticKey == Projection.DIAG_UNCLASSIFIED then
            return membership.canonical[Grouping.GROUP_UNCLASSIFIED]
        elseif viewState.diagnosticKey == Projection.DIAG_UNVERIFIED then
            return membership.unverified
        elseif viewState.diagnosticKey == Projection.DIAG_CONFLICTS then
            return membership.conflicts
        elseif viewState.diagnosticKey == Projection.DIAG_UNAVAILABLE then
            return membership.unavailable
        elseif viewState.diagnosticKey == Projection.DIAG_IMPORTS then
            return model.unresolvedKeys
        end
    end
    if viewState.activeView == Projection.VIEW_SEARCH then
        return membership.canonical[Grouping.GROUP_DAMAGE] -- ignored by global-search branch
    end
    return model.recommended
end

local function IsUnresolvedKey(key)
    return type(key) == "string" and string.sub(key, 1, 2) == "u:"
end

function Projection.GetUnresolved(model, draft, key)
    if not IsUnresolvedKey(key) then return nil end
    local index = tonumber(string.sub(key, 3))
    local list = draft and draft.unresolvedRecommendations
    return type(list) == "table" and index and list[index] or nil
end

function Projection.GetEntry(model, draft, key)
    if IsUnresolvedKey(key) then return nil end
    return EchoProjection.GetAnyEntry(model.classToken, key)
end

function Projection.GetEcho(draft, key)
    return draft and draft.echoes and draft.echoes[key] or nil
end

local function SearchBlob(model, draft, key)
    if IsUnresolvedKey(key) then
        local unresolved = Projection.GetUnresolved(model, draft, key)
        local raw = unresolved and ((unresolved.rawName or "") .. " " .. tostring(unresolved.rawSpellId or "")) or key
        return Identity.NormalizeSearch(raw)
    end
    local entry = EchoProjection.GetAnyEntry(model.classToken, key)
    if entry and entry.searchBlob and entry.searchBlob ~= "" then return entry.searchBlob end
    local echo = draft.echoes[key]
    return Identity.NormalizeSearch(echo and echo.name or key)
end

local function SearchMatches(model, draft, key, query)
    return query == "" or string.find(SearchBlob(model, draft, key), query, 1, true) ~= nil
end

local function EvidenceScore(model, key)
    if not model.snapshotLookup or IsUnresolvedKey(key) then return 0 end
    local item, kind = model.snapshotLookup(key)
    if not item then return 0 end
    local support
    if kind == "avoid" then support = tonumber(item.negativeOrigins) or 0
    elseif kind == "defensive" then support = tonumber(item.defensivePositiveOrigins) or 0
    else support = tonumber(item.positiveOrigins or item.lockOrigins) or 0 end
    local total = tonumber(item.observedOrigins or item.presentOrigins) or 0
    return support * 1000 + (total > 0 and math.floor(support * 100 / total) or 0)
end

local function SortName(model, draft, key)
    if IsUnresolvedKey(key) then
        local unresolved = Projection.GetUnresolved(model, draft, key)
        return Identity.NormalizeSearch(unresolved and (unresolved.rawName or unresolved.rawSpellId) or key)
    end
    local entry = EchoProjection.GetAnyEntry(model.classToken, key)
    local echo = draft.echoes[key]
    return Identity.NormalizeSearch((entry and entry.displayName) or (echo and echo.name) or key)
end

local function CompareKeys(aKey, bKey)
    local model, draft, view = sortModel, sortDraft, sortView
    local aEcho, bEcho = draft.echoes[aKey], draft.echoes[bKey]
    local av, bv
    if view.sortKey == Projection.SORT_NAME then
        av, bv = SortName(model, draft, aKey), SortName(model, draft, bKey)
    elseif view.sortKey == Projection.SORT_EVIDENCE then
        av, bv = EvidenceScore(model, aKey), EvidenceScore(model, bKey)
    elseif view.sortKey == Projection.SORT_PRIORITY then
        av = aEcho and (IMPORTANCE_RANK[aEcho.importance] or 0) or -1
        bv = bEcho and (IMPORTANCE_RANK[bEcho.importance] or 0) or -1
    elseif view.sortKey == Projection.SORT_INCLUDED then
        av = aEcho and aEcho.included and 1 or 0
        bv = bEcho and bEcho.included and 1 or 0
    else
        av = aEcho and ((SOURCE_RANK[aEcho.sourceKind] or 0) * 1000 - (tonumber(aEcho.sourceIndex) or 999)) or 0
        bv = bEcho and ((SOURCE_RANK[bEcho.sourceKind] or 0) * 1000 - (tonumber(bEcho.sourceIndex) or 999)) or 0
    end
    if av ~= bv then
        if view.sortDescending then return av > bv end
        return av < bv
    end
    local an, bn = SortName(model, draft, aKey), SortName(model, draft, bKey)
    if an ~= bn then return an < bn end
    return tostring(aKey) < tostring(bKey)
end

local function CopyFiltered(model, draft, viewState, source, query, groupID, subgroupKey)
    local out = viewState.stagingKeys
    WipeArray(out)
    for index = 1, #source do
        local key = source[index]
        local entry = not IsUnresolvedKey(key) and EchoProjection.GetAnyEntry(model.classToken, key) or nil
        local subgroupOK = true
        if groupID and subgroupKey and subgroupKey ~= Grouping.SUBGROUP_ALL then
            subgroupOK = Grouping.MatchesSubgroup(entry, groupID, subgroupKey)
        end
        if subgroupOK and SearchMatches(model, draft, key, query) then out[#out + 1] = key end
    end
end

local function CopyGlobalSearch(model, draft, viewState, query)
    local out = viewState.stagingKeys
    WipeArray(out)
    if query == "" then return end
    for _, groupID in ipairs(Grouping.GROUP_ORDER) do
        local source = model.membership.canonical[groupID]
        for index = 1, #source do
            local key = source[index]
            if SearchMatches(model, draft, key, query) then out[#out + 1] = key end
        end
    end
end

local function CountOutsideGroup(model, draft, viewState, query)
    if query == "" or viewState.activeView ~= Projection.VIEW_GROUP or viewState.searchAllGroups then return 0 end
    local count = 0
    for _, groupID in ipairs(Grouping.GROUP_ORDER) do
        if groupID ~= viewState.activeGroup then
            local source = model.membership.canonical[groupID]
            for index = 1, #source do
                if SearchMatches(model, draft, source[index], query) then count = count + 1 end
            end
        end
    end
    return count
end

function Projection.Rebuild(model, draft, viewState, snapshotLookup)
    if not model or not draft or not viewState then return false end
    local classToken = tostring(draft.class or ""):upper()
    local membership = BuildMembership(classToken)
    local expectedDraftRevision = Draft.Revision(draft)
    local expectedCatalogRevision = EbonBuilds.EchoCatalog.GetRevision()

    if model.classToken ~= classToken or model.catalogRevision ~= membership.catalogRevision then
        model.contextGeneration = (model.contextGeneration or 0) + 1
    end
    model.classToken = classToken
    model.catalogRevision = membership.catalogRevision
    model.membership = membership
    model.snapshotLookup = snapshotLookup
    RefreshDynamic(model, draft)

    local query = Identity.NormalizeSearch(string.sub(viewState.searchText or "", 1, 64))
    local source = SourceList(model, viewState)
    if viewState.searchAllGroups and query ~= "" then
        CopyGlobalSearch(model, draft, viewState, query)
    else
        local groupID = viewState.activeView == Projection.VIEW_GROUP and viewState.activeGroup or nil
        CopyFiltered(model, draft, viewState, source, query, groupID, viewState.activeSubgroup)
    end

    viewState.outsideGroupMatches = CountOutsideGroup(model, draft, viewState, query)

    sortModel, sortDraft, sortView = model, draft, viewState
    table.sort(viewState.stagingKeys, CompareKeys)
    sortModel, sortDraft, sortView = nil, nil, nil

    if expectedDraftRevision ~= Draft.Revision(draft)
        or expectedCatalogRevision ~= EbonBuilds.EchoCatalog.GetRevision() then
        WipeArray(viewState.stagingKeys)
        return false
    end

    local old = viewState.activeKeys
    viewState.activeKeys = viewState.stagingKeys
    viewState.stagingKeys = old
    WipeArray(viewState.stagingKeys)
    viewState.visibleGeneration = (viewState.visibleGeneration or 0) + 1
    model.draftRevision = expectedDraftRevision
    model.publishedGeneration = model.contextGeneration

    local counts = model.counts
    counts.recommended = #model.recommended
    counts.included = #model.included
    counts.modified = #model.modified
    counts.buildChanging = #(membership.buildChanging or {})
    counts.unclassified = #(membership.canonical[Grouping.GROUP_UNCLASSIFIED] or {})
    counts.unverified = #membership.unverified
    counts.conflicts = #membership.conflicts
    counts.unavailable = #membership.unavailable
    counts.imports = #model.unresolvedKeys
    counts.diagnostics = counts.unclassified + counts.unverified + counts.conflicts + counts.unavailable + counts.imports
    return true
end

function Projection.GetMembership(model)
    return model and model.membership or nil
end

function Projection.GetCounts(model)
    return model and model.counts or nil
end

function Projection.GetCanonicalGroup(model, refKey)
    return model and model.membership and model.membership.primaryGroupByRef[refKey] or nil
end

function Projection.GetProvenance(model, refKey)
    return model and model.membership and model.membership.provenanceByRef[refKey] or nil
end

function Projection.IsReadOnlyKey(model, draft, key)
    if IsUnresolvedKey(key) then return true end
    local entry = Projection.GetEntry(model, draft, key)
    if not entry then return true end
    return entry.availability == Identity.UNAVAILABLE
        or entry.availability == Identity.UNKNOWN
        or not (draft.echoes and draft.echoes[key])
end

Projection.IsUnresolvedKey = IsUnresolvedKey
Projection._CompareKeysForTest = CompareKeys
