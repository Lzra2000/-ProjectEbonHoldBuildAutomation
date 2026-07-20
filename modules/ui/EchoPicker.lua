-- EbonBuilds: modules/ui/EchoPicker.lua
-- Class-scoped, alias-aware Echo picker with a fixed recycled row pool.

EbonBuilds.EchoPicker = {}

local Picker = EbonBuilds.EchoPicker
local Theme = EbonBuilds.Theme
local VirtualList = EbonBuilds.VirtualList
local ROW_HEIGHT = 38
local ROW_POOL = 12
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, searchBox, searchPlaceholder, clearSearchButton
local viewport, scrollFrame, scrollChild, scrollBar, resultText, emptyState, classContextText
local allEntries, filtered, rowPool = {}, {}, {}
local onPick, searchText, scrollOffset = nil, "", 0
local activeClass

local function ClassLabel(classToken)
    local labels = {
        WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
        DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
    }
    return labels[tostring(classToken or ""):upper()] or tostring(classToken or "")
end

local function IsPlaceholderName(value)
    local normalized = EbonBuilds.EchoIdentity.NormalizeSearch(value)
    return normalized == "" or normalized == "unknown" or normalized == "unknown echo"
        or normalized == "unknown spell" or normalized == "echo" or normalized == "spell"
end

local function ResolveEntryName(entry, spellId)
    local candidates = {
        entry and entry.displayName,
        entry and entry.sourceName,
        entry and entry.name,
    }
    for i = 1, #candidates do
        local value = EbonBuilds.EchoIdentity.VisibleName(candidates[i])
        if not IsPlaceholderName(value) then return value end
    end

    local variant = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
    if variant then
        local value = EbonBuilds.EchoIdentity.VisibleName(variant.sourceName)
        if not IsPlaceholderName(value) then return value end
        value = EbonBuilds.EchoIdentity.StripClassPrefix(
            EbonBuilds.EchoIdentity.StripQualitySuffix(variant.internalComment))
        if not IsPlaceholderName(value) then return value end
    end

    local spellName = GetSpellInfo and GetSpellInfo(spellId)
    spellName = EbonBuilds.EchoIdentity.VisibleName(spellName)
    if not IsPlaceholderName(spellName) then return spellName end
    return "Echo #" .. tostring(spellId or "?")
end

local function PrepareEntry(entry)
    if type(entry) ~= "table" then return nil end
    local spellId = tonumber(entry.spellId or entry.id)
    if not spellId then return nil end
    entry.spellId = spellId
    entry.displayName = ResolveEntryName(entry, spellId)
    entry.name = entry.name or entry.displayName
    entry.sourceName = entry.sourceName or entry.displayName
    if not entry.searchBlob or entry.searchBlob == "" then
        entry.searchBlob = EbonBuilds.EchoIdentity.NormalizeSearch(entry.displayName)
    end
    if not entry.refKey and EbonBuilds.EchoCatalog then
        entry.refKey = EbonBuilds.EchoCatalog.GetRefForSpell(spellId)
    end
    return entry
end

local function StrictEntries(classToken)
    local list = {}
    if not EbonBuilds.EchoProjection then return list end
    for _, entry in ipairs(EbonBuilds.EchoProjection.GetAvailable(classToken) or {}) do
        local spellId, quality = EbonBuilds.EchoProjection.GetBestVariant(classToken, entry.refKey)
        if spellId then
            local displayName = ResolveEntryName(entry, spellId)
            list[#list + 1] = {
                refKey = entry.refKey,
                spellId = spellId,
                quality = quality or entry.quality or 0,
                name = displayName,
                displayName = displayName,
                sourceName = entry.sourceName,
                searchBlob = entry.searchBlob,
                disambiguator = entry.disambiguator,
                semantics = entry.semantics,
                groupId = entry.groupId,
                availabilityReason = entry.availabilityReason,
                discrepancyFlags = entry.discrepancyFlags,
                quarantinedAliases = entry.quarantinedAliases,
                canonicalName = entry.canonicalName,
            }
        end
    end
    table.sort(list, function(a, b)
        local an = EbonBuilds.EchoIdentity.NormalizeSearch(a.displayName)
        local bn = EbonBuilds.EchoIdentity.NormalizeSearch(b.displayName)
        if an ~= bn then return an < bn end
        return tostring(a.refKey) < tostring(b.refKey)
    end)
    return list
end

local function SearchEntry(entry, query)
    if query == "" then return true end
    return string.find(entry.searchBlob or EbonBuilds.EchoIdentity.NormalizeSearch(entry.displayName), query, 1, true) ~= nil
end

local function ApplySearch()
    local query = EbonBuilds.EchoIdentity.NormalizeSearch(searchText)
    for i = #filtered, 1, -1 do filtered[i] = nil end
    for i = 1, #allEntries do
        local entry = allEntries[i]
        if SearchEntry(entry, query) then filtered[#filtered + 1] = entry end
    end
    scrollOffset = 0
end

local function Pick(entry)
    if not entry then return end
    local callback = onPick
    frame:Hide()
    if callback then callback(entry.spellId, entry.quality, entry.displayName, entry.refKey) end
end

local function UpdateSearchChrome()
    if not searchBox then return end
    local hasText = (searchBox:GetText() or "") ~= ""
    if searchPlaceholder then
        if hasText or searchBox:HasFocus() then searchPlaceholder:Hide() else searchPlaceholder:Show() end
    end
    if clearSearchButton then
        if hasText then clearSearchButton:Show() else clearSearchButton:Hide() end
    end
end

local function ResetRow(row)
    row._entry = nil
    row:Hide()
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT - 2)
    Theme.ApplyPanel(row)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", row, "LEFT", 7, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    label:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    label:SetJustifyH("LEFT")
    row._label = label

    local meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    meta:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    meta:SetJustifyH("LEFT")
    row._meta = meta

    local rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    rank:SetWidth(76)
    rank:SetJustifyH("RIGHT")
    row._rank = rank

    row:SetScript("OnEnter", function(self)
        local entry = self._entry
        if not entry then return end
        Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local used = false
        if entry.spellId and GameTooltip.SetHyperlink then
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(entry.spellId))
            used = ok and (not GameTooltip.NumLines or GameTooltip:NumLines() > 0)
        end
        if not used then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(entry.displayName or "Echo", 1, 0.82, 0)
            local description = EbonBuilds.EchoCatalog.GetDescription(entry.spellId, 500, 1)
            if description and description ~= "" then GameTooltip:AddLine(description, 1, 1, 1, true) end
        else
            local title = _G.GameTooltipTextLeft1
            if title and entry.displayName then title:SetText(entry.displayName) end
        end
        if entry.disambiguator then GameTooltip:AddLine(entry.disambiguator, 0.65, 0.78, 1, true) end
        if entry.availabilityReason == "REVIEWED_ALLOW" then
            GameTooltip:AddLine("Class metadata corrected by a verified eligibility fact.",
                Theme.WARNING[1], Theme.WARNING[2], Theme.WARNING[3], true)
        elseif entry.availabilityReason == "OBSERVED_OFFER"
            or entry.availabilityReason == "OBSERVED_REPLACEMENT"
            or entry.availabilityReason == "CONFIRMED_SELECTION" then
            GameTooltip:AddLine("Observed usable in live Project Ebonhold gameplay.",
                Theme.SUCCESS[1], Theme.SUCCESS[2], Theme.SUCCESS[3], true)
        end
        if entry.quarantinedAliases and #entry.quarantinedAliases > 0 then
            GameTooltip:AddLine("Runtime name conflict corrected; canonical Echo identity is shown.",
                Theme.WARNING[1], Theme.WARNING[2], Theme.WARNING[3], true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Available to " .. ClassLabel(activeClass) .. ". Click to select.", 0.75, 0.75, 0.8, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) Theme.SetCardHovered(self, false); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) Pick(self._entry) end)
    return row
end

local function Render()
    if not viewport then return end
    local visibleRows = VirtualList.VisibleCount(viewport:GetHeight(), ROW_HEIGHT, ROW_POOL)
    local requestedPixels = tonumber(scrollBar:GetValue()) or (scrollOffset * ROW_HEIGHT)
    local requested = math.floor(requestedPixels / ROW_HEIGHT + 0.0001)
    local maxOffset
    scrollOffset, maxOffset = VirtualList.ClampOffset(#filtered, visibleRows, requested)

    -- The shared wheel router operates in pixels. This picker remains
    -- virtualized, so convert its row offset to a pixel range while keeping
    -- the recycled rows anchored inside the fixed viewport.
    local maxScroll = maxOffset * ROW_HEIGHT
    local snappedScroll = scrollOffset * ROW_HEIGHT
    scrollBar:SetMinMaxValues(0, maxScroll)
    if scrollBar:GetValue() ~= snappedScroll then scrollBar:SetValue(snappedScroll) end
    if scrollFrame then scrollFrame._virtualScrollValue = snappedScroll end

    for i = 1, ROW_POOL do
        local row = rowPool[i]
        local entry = i <= visibleRows and filtered[scrollOffset + i] or nil
        if entry then
            row._entry = entry
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", viewport, "RIGHT", -18, 0)
            row._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)) or FALLBACK_ICON)
            local r, g, b = EbonBuilds.Quality.GetRGB(entry.quality or 0)
            row._label:SetText(ResolveEntryName(entry, entry.spellId))
            row._label:SetTextColor(r, g, b, 1)
            row._meta:SetText(entry.disambiguator or (EbonBuilds.EchoCatalog.GetSemanticSummary(entry.spellId, 2) or "Unclassified"))
            row._rank:SetText(EbonBuilds.Quality.LABELS[entry.quality or 0] or ("Rank " .. tostring(entry.quality or 0)))
            row._rank:SetTextColor(r, g, b, 1)
            row:Show()
        else
            ResetRow(row)
        end
    end

    resultText:SetText(string.format("%d of %d verified %s Echoes", #filtered, #allEntries, ClassLabel(activeClass)))
    if #filtered == 0 then emptyState:Show() else emptyState:Hide() end
end

local function ClearSearch(keepFocus)
    searchBox:SetText("")
    searchText = ""
    ApplySearch()
    scrollBar:SetValue(0)
    Render()
    if keepFocus then searchBox:SetFocus() else searchBox:ClearFocus() end
    UpdateSearchChrome()
end

local function BuildFrame()
    local f = CreateFrame("Frame", "EbonBuildsEchoPicker", UIParent)
    f:SetSize(460, 540)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    title:SetText("Choose an Echo")
    classContextText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    classContextText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    Theme.CreateCloseButton(f)

    local searchContainer = CreateFrame("Frame", nil, f)
    searchContainer:SetHeight(28)
    searchContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -66)
    searchContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -66)
    Theme.ApplyInput(searchContainer)

    searchBox = CreateFrame("EditBox", nil, searchContainer)
    searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 8, -4)
    searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -30, 4)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(80)
    Theme.WireEditBox(searchBox, searchContainer)
    searchPlaceholder = searchContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 0, 0)

    clearSearchButton = CreateFrame("Button", nil, searchContainer)
    clearSearchButton:SetSize(22, 22)
    clearSearchButton:SetPoint("RIGHT", searchContainer, "RIGHT", -3, 0)
    local glyph = clearSearchButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    glyph:SetPoint("CENTER"); glyph:SetText("x")
    clearSearchButton:SetScript("OnClick", function() ClearSearch(true) end)

    resultText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultText:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", 0, -8)

    local listPanel = CreateFrame("Frame", nil, f)
    listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -116)
    listPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    Theme.ApplyPanel(listPanel)
    viewport = CreateFrame("Frame", nil, listPanel)
    viewport:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 7, -7)
    viewport:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -7, 7)

    -- Bind the virtualized picker through the same content-tree wheel path
    -- used by native ScrollFrames. The adapter exposes pixel scroll values
    -- without moving the viewport itself; Render() converts them back to row
    -- offsets for the recycled pool.
    scrollFrame = viewport
    scrollChild = viewport
    function scrollFrame:GetVerticalScroll()
        return tonumber(self._virtualScrollValue) or 0
    end
    function scrollFrame:SetVerticalScroll(value)
        self._virtualScrollValue = tonumber(value) or 0
    end

    scrollBar = Theme.CreateScrollBar(viewport)
    scrollBar:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", 0, 0)
    scrollBar:SetValueStep(ROW_HEIGHT)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollOffset = math.floor((tonumber(value) or 0) / ROW_HEIGHT + 0.0001)
        Render()
    end)

    for i = 1, ROW_POOL do rowPool[i] = CreateRow(viewport) end
    Theme.BindScrollWheel(scrollFrame, scrollBar, ROW_HEIGHT, scrollChild)
    viewport:HookScript("OnSizeChanged", Render)

    emptyState = Theme.CreateEmptyState(viewport, "No matching Echoes", "Try the player-facing name or a legacy alias.")
    emptyState:Hide()

    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        ApplySearch(); scrollBar:SetValue(0); Render(); UpdateSearchChrome()
    end)
    searchBox:SetScript("OnEditFocusGained", UpdateSearchChrome)
    searchBox:SetScript("OnEditFocusLost", UpdateSearchChrome)
    searchBox:SetScript("OnEnterPressed", function() if filtered[1] then Pick(filtered[1]) end end)
    searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then ClearSearch(true) else self:ClearFocus(); f:Hide() end
    end)

    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "EbonBuildsEchoPicker")
    f:SetScript("OnHide", function() searchBox:ClearFocus(); onPick = nil end)
    f:Hide()
    return f
end

function Picker.DataForClass(classToken)
    return StrictEntries(classToken)
end

function Picker.Show(callback, dataSource, classToken)
    if not frame then frame = BuildFrame() end
    activeClass = tostring(classToken or activeClass or EbonBuilds.Build.PlayerClassToken()):upper()
    local source = type(dataSource) == "table" and dataSource or StrictEntries(activeClass)
    allEntries = {}
    for i = 1, #source do
        local entry = PrepareEntry(source[i])
        if entry then allEntries[#allEntries + 1] = entry end
    end
    onPick = callback
    classContextText:SetText("Only verified " .. ClassLabel(activeClass) .. " Echoes are shown.")
    searchPlaceholder:SetText("Search " .. ClassLabel(activeClass) .. " Echoes or aliases...")
    searchBox:SetText("")
    searchText, scrollOffset = "", 0
    ApplySearch(); scrollBar:SetValue(0); Render(); UpdateSearchChrome()
    frame:Show(); searchBox:SetFocus()
end

function Picker.ShowForLock(callback, dataSource, classToken)
    classToken = classToken or activeClass or EbonBuilds.Build.PlayerClassToken()
    Picker.Show(function(spellId, quality, name, refKey)
        if callback then callback(spellId, quality, name, refKey) end
    end, type(dataSource) == "table" and dataSource or StrictEntries(classToken), classToken)
end

function Picker.ShowForPriority(callback, dataSource, classToken)
    classToken = classToken or activeClass or EbonBuilds.Build.PlayerClassToken()
    Picker.Show(function(spellId, quality, name, refKey)
        if callback then callback(refKey or name, spellId, quality, name) end
    end, type(dataSource) == "table" and dataSource or StrictEntries(classToken), classToken)
end

function Picker.Hide() if frame then frame:Hide() end end
