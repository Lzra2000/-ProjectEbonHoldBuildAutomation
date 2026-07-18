-- EbonBuilds: modules/ui/BuildList.lua
-- Split sidebar: fixed Explore navigation plus a searchable, scrollable build
-- library. Build cards keep identity, state and locked Echoes readable without
-- competing with global navigation.

EbonBuilds.BuildList = {}

local ROW_HEIGHT    = 70
local CARD_MARGIN   = 4
local CLASS_COORDS  = CLASS_ICON_TCOORDS
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_COLORS  = EbonBuilds.Theme.CLASS_COLORS

local container, scrollFrame, scrollChild, scrollBar, searchBox, searchPlaceholder
local emptyState, resultLabel
local rowPool = {}
local navButtons = {}
local selectedNavigation = nil
local searchText = ""

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = classToken and CLASS_COORDS[classToken]
    if coords then
        tex:SetTexture(CLASS_TEXTURE)
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

local function NavigateToBuild(build)
    if not build then return end
    EbonBuilds.Build.SetActive(build.id)
    EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
end

local function SpecText(build)
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local spec = specs and specs[build.spec or 1]
    local className = build.class and build.class:sub(1, 1) .. build.class:sub(2):lower() or "Unknown"
    return spec and (className .. " · " .. spec.name) or className
end

local function MatchesSearch(build)
    if searchText == "" then return true end
    local haystack = string.lower((build.title or "") .. " " .. SpecText(build))
    return haystack:find(searchText, 1, true) ~= nil
end

local function UpdateSearchPlaceholder()
    if not searchBox or not searchPlaceholder then return end
    if searchBox:HasFocus() or (searchBox:GetText() or "") ~= "" then
        searchPlaceholder:Hide()
    else
        searchPlaceholder:Show()
    end
end

local function WireBuildListMouseWheel(frame)
    if not frame or not scrollFrame or not scrollBar then return end
    EbonBuilds.Theme.BindSliderWheel(scrollFrame, scrollBar, 42, frame)
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------

local function CreateNavigationButton(parent, label, route, tooltip)
    local btn = EbonBuilds.Theme.CreateButton(parent)
    btn:SetHeight(27)
    btn:SetText(label)
    btn._route = route
    btn:SetScript("OnClick", function() EbonBuilds.ViewRouter.Show(route) end)
    EbonBuilds.Theme.AttachTooltip(btn, label, tooltip)
    navButtons[route] = btn
    return btn
end

function EbonBuilds.BuildList.SetSelectedNavigation(route)
    selectedNavigation = route
    for name, btn in pairs(navButtons) do
        EbonBuilds.Theme.SetTabSelected(btn, name == route)
    end
end

------------------------------------------------------------------------
-- Build cards
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(ROW_HEIGHT)

    local surface = CreateFrame("Frame", nil, row)
    surface:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    surface:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    EbonBuilds.Theme.ApplyCard(surface)
    surface:SetFrameLevel(row:GetFrameLevel())
    row._surface = surface
    WireBuildListMouseWheel(row)
    WireBuildListMouseWheel(surface)

    local stripe = row:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    stripe:SetWidth(3)
    row._stripe = stripe

    local classBtn = CreateIconButton(row, 28)
    classBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    WireBuildListMouseWheel(classBtn)
    row._classBtn = classBtn

    local title = surface:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", row._classBtn, "TOPRIGHT", 7, -2)
    title:SetHeight(14)
    title:SetJustifyH("LEFT")
    if title.SetNonSpaceWrap then title:SetNonSpaceWrap(false) end
    if title.SetWordWrap then title:SetWordWrap(false) end
    row._titleLabel = title

    local subtitle = surface:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
    subtitle:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    row._subtitleLabel = subtitle

    local active = EbonBuilds.Theme.CreateStatusPill(row, "ACTIVE", "success")
    active:SetSize(46, 16)
    active:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -7)
    WireBuildListMouseWheel(active)
    active:Hide()
    row._activePill = active

    row._lockedBtns = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(row, 18)
        btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10 + (i - 1) * 24, 7)
        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetTexture("Interface\\Buttons\\WHITE8X8")
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        btn._qualityBorder = border
        WireBuildListMouseWheel(btn)
        btn:Hide()
        row._lockedBtns[i] = btn
    end

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -2)
    hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    hover:SetTexture(1, 1, 1, 0.06)

    row:SetScript("OnEnter", function(self)
        if self._surface then EbonBuilds.Theme.SetCardHovered(self._surface, true) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._buildTitle or "Build", 1, 0.82, 0)
        GameTooltip:AddLine(self._isActive and "Active build. Click to open." or "Click to make active and open.", 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if self._surface then EbonBuilds.Theme.SetCardHovered(self._surface, false) end
        GameTooltip:Hide()
    end)
    return row
end

local function PopulateRow(row, build, activeId, yOffset)
    local active = build.id == activeId
    local r, g, b = EbonBuilds.Theme.ClassRGB(build.class)

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetHeight(ROW_HEIGHT)
    row._buildTitle = build.title or "Untitled"
    row._isActive = active

    row._titleLabel:ClearAllPoints()
    row._titleLabel:SetPoint("TOPLEFT", row._classBtn, "TOPRIGHT", 7, -2)
    if active then
        row._titleLabel:SetPoint("RIGHT", row._activePill, "LEFT", -8, 0)
    else
        row._titleLabel:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    end
    row._titleLabel:SetHeight(14)

    row._stripe:SetWidth(active and 5 or 3)
    row._stripe:SetVertexColor(r, g, b, active and 1 or 0.72)
    row._surface:SetBackdropColor(active and r * 0.11 or 0.075, active and g * 0.11 or 0.075, active and b * 0.11 or 0.095, 0.99)
    row._surface:SetBackdropBorderColor(active and r or 0.20, active and g or 0.20, active and b or 0.25, active and 0.75 or 1)

    SetClassIcon(row._classBtn._icon, build.class)
    row._titleLabel:SetText(build.title or "Untitled")
    row._titleLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))
    row._subtitleLabel:SetText(SpecText(build))
    if active then row._activePill:Show() else row._activePill:Hide() end

    local locked = build.lockedEchoes or {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = row._lockedBtns[i]
        local spellId = locked[i]
        if spellId then
            btn._spellId = spellId
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            local q = EbonBuilds.Quality.OfSpell(spellId)
            local qr, qg, qb = EbonBuilds.Quality.GetRGB(q)
            btn._qualityBorder:SetVertexColor(qr, qg, qb, 1)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(GetSpellInfo(self._spellId) or "Echo", qr, qg, qb)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function() NavigateToBuild(build) end)
            btn:Show()
        else
            btn:Hide()
        end
    end

    row._classBtn:SetScript("OnClick", function() NavigateToBuild(build) end)
    row:SetScript("OnClick", function() NavigateToBuild(build) end)
    row:Show()
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function Render()
    if not scrollChild then return end
    local builds = EbonBuilds.Build.List()
    local activeId = EbonBuildsCharDB.activeBuildId
    local visible = {}
    for i = 1, #builds do
        if MatchesSearch(builds[i]) then visible[#visible + 1] = builds[i] end
    end

    local y = 0
    for i = 1, #visible do
        if not rowPool[i] then rowPool[i] = CreateRow(scrollChild) end
        PopulateRow(rowPool[i], visible[i], activeId, y)
        y = y + ROW_HEIGHT + CARD_MARGIN
    end
    for i = #visible + 1, #rowPool do rowPool[i]:Hide() end

    scrollChild:SetHeight(math.max(1, y))
    if scrollBar and scrollFrame then
        local maxScroll = math.max(0, y - (scrollFrame:GetHeight() or 0))
        scrollBar:SetMinMaxValues(0, maxScroll)
        if scrollBar:GetValue() > maxScroll then scrollBar:SetValue(maxScroll) end
    end
    if emptyState then
        if #visible == 0 then
            emptyState._title:SetText(#builds == 0 and "No builds yet" or "No matching builds")
            emptyState._body:SetText(#builds == 0 and "Create or import a build to begin." or "Clear the build search to see the full library.")
            emptyState:Show()
        else
            emptyState:Hide()
        end
    end
    if resultLabel then
        resultLabel:SetText(#visible == #builds and (#builds .. " builds") or (#visible .. " of " .. #builds .. " builds"))
    end
end

EbonBuilds.BuildList.Refresh = Render

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function CreateSearch(parent, anchor)
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -7)
    wrap:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)
    wrap:SetHeight(24)
    EbonBuilds.Theme.ApplyInput(wrap)

    local edit = CreateFrame("EditBox", nil, wrap)
    edit:SetPoint("TOPLEFT", wrap, "TOPLEFT", 7, -3)
    edit:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -24, 3)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetAutoFocus(false)
    EbonBuilds.Theme.WireEditBox(edit, wrap)

    local placeholder = wrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
    placeholder:SetText("Search builds...")
    placeholder:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local clear = CreateFrame("Button", nil, wrap)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", wrap, "RIGHT", -2, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    clear:SetScript("OnClick", function() edit:SetText(""); edit:ClearFocus() end)

    edit:SetScript("OnTextChanged", function(self)
        searchText = string.lower(self:GetText() or "")
        UpdateSearchPlaceholder()
        Render()
    end)
    edit:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
    edit:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
    edit:SetScript("OnEscapePressed", function(self) if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end end)

    searchBox, searchPlaceholder = edit, placeholder
    UpdateSearchPlaceholder()
    return wrap
end

function EbonBuilds.BuildList.Init(parent)
    container = parent

    local explore = EbonBuilds.Theme.CreateSectionLabel(parent, "Explore", nil, -10)
    local public = CreateNavigationButton(parent, "Public Builds", "publicBuilds", "Browse builds shared by other EbonBuilds users.")
    public:SetPoint("TOPLEFT", explore, "BOTTOMLEFT", -2, -6)
    public:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)

    local atlas = CreateNavigationButton(parent, "Tome Atlas", "tomeAtlas", "Browse Tome sources and community farming information.")
    atlas:SetPoint("TOPLEFT", public, "BOTTOMLEFT", 0, -3)
    atlas:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)

    local affixes = CreateNavigationButton(parent, "Affixes", "affixes", "Review available run affixes and collection progress.")
    affixes:SetPoint("TOPLEFT", atlas, "BOTTOMLEFT", 0, -3)
    affixes:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)

    local myBuilds = EbonBuilds.Theme.CreateSectionLabel(parent, "My Builds", affixes, -13)

    local newBtn = EbonBuilds.Theme.CreateButton(parent, "gold")
    newBtn:SetHeight(27)
    newBtn:SetPoint("TOPLEFT", myBuilds, "BOTTOMLEFT", -2, -6)
    newBtn:SetPoint("RIGHT", parent, "RIGHT", -91, 0)
    newBtn:SetText("+ New Build")
    newBtn:SetScript("OnClick", function() EbonBuilds.ViewRouter.Show("buildWizard") end)

    local importBtn = EbonBuilds.Theme.CreateButton(parent)
    importBtn:SetSize(78, 27)
    importBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)
    importBtn:SetPoint("TOP", newBtn, "TOP", 0, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() EbonBuilds.ExportImport.ShowImportDialog() end)

    local search = CreateSearch(parent, newBtn)

    resultLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultLabel:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -5)
    resultLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    resultLabel:SetText("0 builds")

    scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsBuildListSF", parent)
    scrollFrame:SetPoint("TOPLEFT", resultLabel, "BOTTOMLEFT", -2, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = EbonBuilds.Theme.CreateScrollBar(parent)
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 17, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 17, 2)
    scrollBar:SetValueStep(ROW_HEIGHT + CARD_MARGIN)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    EbonBuilds.Theme.BindSliderWheel(scrollFrame, scrollBar, 42, scrollChild)

    emptyState = EbonBuilds.Theme.CreateEmptyState(scrollFrame, "No builds yet", "Create or import a build to begin.")
    emptyState:SetSize(190, 92)

    local function SyncWidth()
        local width = math.max(120, scrollFrame:GetWidth())
        scrollChild:SetWidth(width)
        Render()
    end
    parent:SetScript("OnSizeChanged", SyncWidth)
    SyncWidth()

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Render)
    end
end
