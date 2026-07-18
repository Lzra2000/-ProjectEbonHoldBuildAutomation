-- EbonBuilds: modules/ui/EchoPicker.lua
-- Responsibility: accessible modal Echo picker. Shows a searchable list of
-- Echoes and invokes a callback with the selected spell, quality, and name.

EbonBuilds.EchoPicker = {}

local ROW_HEIGHT = 34
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, searchBox, searchContainer, searchPlaceholder, clearSearchButton
local scrollFrame, scrollChild, scrollBar, titleText, resultText, emptyText, helpText
local allEntries = {}
local filtered = {}
local rowPool = {}
local onPick
local searchText = ""

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function BuildEntries()
    local best = EbonBuilds.EchoTableRows.BuildBestByName()
    local list = {}
    for name, entry in pairs(best) do
        list[#list + 1] = {
            spellId = entry.spellId,
            name = name,
            quality = entry.quality,
        }
    end
    table.sort(list, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        return a.name < b.name
    end)
    return list
end

local function ApplySearch()
    filtered = {}
    if searchText == "" then
        for i = 1, #allEntries do filtered[i] = allEntries[i] end
        return
    end
    for i = 1, #allEntries do
        local entry = allEntries[i]
        if (entry.name or ""):lower():find(searchText, 1, true) then
            filtered[#filtered + 1] = entry
        end
    end
end

local function Pick(entry)
    if not entry then return end
    if onPick then onPick(entry.spellId, entry.quality, entry.name) end
    frame:Hide()
end

------------------------------------------------------------------------
-- Search state
------------------------------------------------------------------------

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

local function ClearSearch(keepFocus)
    if not searchBox then return end
    searchBox:SetText("")
    searchText = ""
    ApplySearch()
    if not keepFocus then searchBox:ClearFocus() end
    UpdateSearchChrome()
end

------------------------------------------------------------------------
-- Row pool / rendering
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    row._background = background

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    accent:SetWidth(3)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    row._accent = accent

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))
    row._label = label

    local rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    rank:SetWidth(72)
    rank:SetJustifyH("RIGHT")
    row._rank = rank

    row:SetScript("OnEnter", function(self)
        self._background:SetVertexColor(0.16, 0.16, 0.21, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._entry and self._entry.name or "Echo", 1, 0.82, 0)
        GameTooltip:AddLine("Click to select this Echo.", 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        local alpha = self._even and 0.92 or 0.78
        self._background:SetVertexColor(0.075, 0.075, 0.10, alpha)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self) Pick(self._entry) end)
    if scrollFrame and scrollBar then
        EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, ROW_HEIGHT, row)
    end
    return row
end

local function PopulateRow(row, index, entry)
    row:ClearAllPoints()
    row:SetPoint("LEFT", scrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", scrollChild, "TOP", 0, -(index - 1) * ROW_HEIGHT)
    row._entry = entry
    row._even = index % 2 == 0

    row._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)) or FALLBACK_ICON)
    row._label:SetText(entry.name or "Unknown Echo")

    local quality = entry.quality or 0
    local rankLabel = EbonBuilds.Quality.LABELS[quality] or ("Rank " .. tostring(quality))
    local r, g, b = EbonBuilds.Quality.GetRGB(quality)
    row._rank:SetText(rankLabel)
    row._rank:SetTextColor(r, g, b, 1)
    row._accent:SetVertexColor(r, g, b, 1)
    row._background:SetVertexColor(0.075, 0.075, 0.10, row._even and 0.92 or 0.78)
    row:Show()
end

local function Render()
    for i = 1, #filtered do
        if not rowPool[i] then rowPool[i] = CreateRow(scrollChild) end
        PopulateRow(rowPool[i], i, filtered[i])
    end
    for i = #filtered + 1, #rowPool do rowPool[i]:Hide() end
    local contentHeight = math.max(1, #filtered * ROW_HEIGHT)
    scrollChild:SetHeight(contentHeight)
    if scrollBar and scrollFrame then
        local maxScroll = math.max(0, contentHeight - (scrollFrame:GetHeight() or 0))
        scrollBar:SetMinMaxValues(0, maxScroll)
        if scrollBar:GetValue() > maxScroll then scrollBar:SetValue(maxScroll) end
    end

    if resultText then
        if #filtered == #allEntries then
            resultText:SetText(#allEntries .. " Echoes")
        else
            resultText:SetText(string.format("%d of %d Echoes", #filtered, #allEntries))
        end
    end
    if emptyText then
        if #filtered == 0 then emptyText:Show() else emptyText:Hide() end
    end
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function CreateSearchBox(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(28)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -66)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -66)
    EbonBuilds.Theme.ApplyInput(container)
    searchContainer = container

    local box = CreateFrame("EditBox", nil, container)
    box:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -4)
    box:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -30, 4)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    EbonBuilds.Theme.WireEditBox(box, container)

    local placeholder = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
    placeholder:SetText("Search Echoes by name...")
    placeholder:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    searchPlaceholder = placeholder

    local clear = CreateFrame("Button", nil, container)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", container, "RIGHT", -3, 0)
    local glyph = clear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    glyph:SetPoint("CENTER")
    glyph:SetText("x")
    glyph:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    clear:SetScript("OnEnter", function() glyph:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD)) end)
    clear:SetScript("OnLeave", function() glyph:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED)) end)
    clear:SetScript("OnClick", function() ClearSearch(true); box:SetFocus() end)
    EbonBuilds.Theme.AttachTooltip(clear, "Clear search", "Show the complete Echo list.")
    clearSearchButton = clear

    box:SetScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        ApplySearch()
        Render()
        UpdateSearchChrome()
    end)
    box:SetScript("OnEditFocusGained", UpdateSearchChrome)
    box:SetScript("OnEditFocusLost", UpdateSearchChrome)
    box:SetScript("OnEnterPressed", function()
        if filtered[1] then Pick(filtered[1]) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then
            ClearSearch(true)
        else
            self:ClearFocus()
            frame:Hide()
        end
    end)

    UpdateSearchChrome()
    return box
end

local function BuildFrame()
    local f = CreateFrame("Frame", "EbonBuildsEchoPicker", UIParent)
    f:SetSize(440, 540)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    title:SetText("Choose an Echo")
    title:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))
    titleText = title

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Search, then click an Echo. Press Enter to choose the first result.")
    subtitle:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local close = EbonBuilds.Theme.CreateCloseButton(f)
    EbonBuilds.Theme.AttachTooltip(close, "Close", "Close without changing the selected Echo.")

    searchBox = CreateSearchBox(f)

    resultText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultText:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", 0, -8)
    resultText:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    helpText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpText:SetPoint("TOPRIGHT", searchContainer, "BOTTOMRIGHT", 0, -8)
    helpText:SetText("Enter: select first  |  Esc: clear or close")
    helpText:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local listPanel = CreateFrame("Frame", nil, f)
    listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -116)
    listPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    EbonBuilds.Theme.ApplyPanel(listPanel)

    scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsEchoPickerSF", listPanel)
    scrollFrame:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 7, -7)
    scrollFrame:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -22, 7)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(376)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = EbonBuilds.Theme.CreateScrollBar(listPanel)
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 17, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 17, 2)
    scrollBar:SetValueStep(ROW_HEIGHT)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, ROW_HEIGHT, scrollChild)

    emptyText = listPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("CENTER", listPanel, "CENTER", 0, 10)
    emptyText:SetText("No Echoes match your search.\nTry a shorter or different name.")
    emptyText:SetJustifyH("CENTER")
    emptyText:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    emptyText:Hide()

    _G.UISpecialFrames = _G.UISpecialFrames or {}
    tinsert(_G.UISpecialFrames, "EbonBuildsEchoPicker")

    f:SetScript("OnHide", function()
        if searchBox then searchBox:ClearFocus() end
        onPick = nil
    end)

    f:Hide()
    return f
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------

function EbonBuilds.EchoPicker.Show(callback, dataSource)
    if not frame then frame = BuildFrame() end
    if type(dataSource) == "table" then
        allEntries = dataSource
    elseif dataSource then
        allEntries = EbonBuilds.EchoTableRows.BuildAllQualitiesList()
    else
        allEntries = BuildEntries()
    end
    onPick = callback
    searchBox:SetText("")
    searchText = ""
    ApplySearch()
    if scrollBar then scrollBar:SetValue(0) end
    Render()
    frame:Show()
    searchBox:SetFocus()
    UpdateSearchChrome()
end

function EbonBuilds.EchoPicker.Hide()
    if frame then frame:Hide() end
end
