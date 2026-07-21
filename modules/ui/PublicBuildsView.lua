local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/PublicBuildsView.lua
-- Responsibility: paginated browser for builds shared by other players.
-- Exposes Mount/Unmount. Registered as the "publicBuilds" view.

EbonBuilds.PublicBuildsView = {}

local PAGE_SIZE  = 8
local CARD_MARGIN = 4
local CARD_HEIGHT = 74
local CARD_HEIGHT_DOUBLE = 88  -- extra room for a title that wraps to 2 lines
local LOCKED_ICON_SIZE = 22
local TITLE_MAX_W = 380

local titleMeasureFont

-- A long, community-chosen build title used to silently overflow the
-- fixed CARD_HEIGHT box (locked-echo icons pushed past the card's bottom
-- edge into -- or past -- the next card). Measure first so the card can
-- grow to fit, mirroring the same fix already proven in BuildList.lua.
local function NeedsTwoLines(text)
    if not text or text == "" then return false end
    if not titleMeasureFont then return false end
    titleMeasureFont:SetText(text)
    local w = titleMeasureFont:GetStringWidth() or 0
    return w > TITLE_MAX_W
end

local CLASS_COLORS = EbonBuilds.Theme.CLASS_COLORS

local viewFrame
local cardPool   = {}
local pageLabel, prevBtn, nextBtn
local scrollFrame, scrollChild, scrollBar
local noBuildsLabel
local state = { builds = {}, page = 1, totalPages = 1 }

local CLASS_DISPLAY = {
    WARRIOR     = "Warrior",
    PALADIN     = "Paladin",
    HUNTER      = "Hunter",
    ROGUE       = "Rogue",
    PRIEST      = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN      = "Shaman",
    MAGE        = "Mage",
    WARLOCK     = "Warlock",
    DRUID       = "Druid",
}

local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local classDropdown, specDropdown, refreshBtn
local filterClass, filterSpec

------------------------------------------------------------------------
-- Data source
------------------------------------------------------------------------

local function FetchPublicBuilds()
    return EbonBuilds.Build.ListPublic()
end

------------------------------------------------------------------------
-- Filter dropdowns
------------------------------------------------------------------------

local RefreshView, GetFilteredBuilds

local function InitSpecDropdown()
    if not specDropdown then return end
    specDropdown:SetMenuBuilder(function()
        local items = {
            {
                text = "All Specs",
                checked = (filterSpec == nil),
                func = function()
                    filterSpec = nil
                    specDropdown:SetText("All Specs")
                    RefreshView()
                end,
            },
        }
        if filterClass then
            local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[filterClass] or {}
            for i, entry in pairs(specs) do
                if type(i) == "number" then
                    local index, name = i, entry.name
                    items[#items + 1] = {
                        text = name,
                        checked = (index == filterSpec),
                        func = function()
                            filterSpec = index
                            specDropdown:SetText(name)
                            RefreshView()
                        end,
                    }
                end
            end
        end
        return items
    end)
    if filterSpec then
        local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[filterClass] or {}
        local entry = specs[filterSpec]
        if entry then
            specDropdown:SetText(entry.name)
        else
            specDropdown:SetText("All Specs")
            filterSpec = nil
        end
    else
        specDropdown:SetText("All Specs")
    end
    specDropdown:RefreshMenu()
end

local function InitClassDropdown()
    if not classDropdown then return end
    classDropdown:SetMenuBuilder(function()
        local items = {
            {
                text = "All Classes",
                checked = (filterClass == nil),
                func = function()
                    filterClass = nil
                    filterSpec = nil
                    classDropdown:SetText("All Classes")
                    InitSpecDropdown()
                    RefreshView()
                end,
            },
        }
        for _, token in ipairs(CLASS_TOKENS) do
            local classToken = token
            items[#items + 1] = {
                text = CLASS_DISPLAY[classToken],
                checked = (classToken == filterClass),
                func = function()
                    filterClass = classToken
                    filterSpec = nil
                    classDropdown:SetText(CLASS_DISPLAY[classToken])
                    InitSpecDropdown()
                    RefreshView()
                end,
            }
        end
        return items
    end)
    if filterClass then
        classDropdown:SetText(CLASS_DISPLAY[filterClass])
    else
        classDropdown:SetText("All Classes")
    end
    classDropdown:RefreshMenu()
end

------------------------------------------------------------------------
-- Card factory
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "PublicBuildsView.IconButton")
    end
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

local function CreateCard(parent)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(CARD_HEIGHT)
    card:RegisterForClicks("LeftButtonUp")

    -- Class-colored border via backdrop
    EbonBuilds.Theme.ApplyBackdropDefinition(card)
    card:SetBackdropColor(unpack(EbonBuilds.Theme.CARD_BG))
    card:SetBackdropBorderColor(unpack(EbonBuilds.Theme.BORDER_DIM))

    -- Inner background
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     card, "TOPLEFT",     4, -4)
    bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4,  4)
    bg:SetTexture(0, 0, 0, 0.20)
    card._bg = bg

    -- Left accent stripe
    local stripe = card:CreateTexture(nil, "BACKGROUND")
    stripe:SetPoint("TOPLEFT",    card, "TOPLEFT",    4, -4)
    stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 4,  4)
    stripe:SetWidth(4)
    card._stripe = stripe

    -- Class icon (top-left, 28x28)
    local classIcon = card:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(28)
    classIcon:SetHeight(28)
    classIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -10)
    classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card._classIcon = classIcon

    -- Title (to the right of class icon)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -4)
    title:SetPoint("RIGHT",   card,      "RIGHT",   -90, 0)
    title:SetJustifyH("LEFT")
    card._titleLabel = title

    -- Author + spec + date (below title)
    local meta = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    meta:SetPoint("RIGHT",   card,  "RIGHT",     -90, 0)
    meta:SetJustifyH("LEFT")
    card._metaLabel = meta

    -- Spec icon (bottom-left of class icon)
    local specIcon = card:CreateTexture(nil, "ARTWORK")
    specIcon:SetWidth(14)
    specIcon:SetHeight(14)
    specIcon:SetPoint("TOPLEFT", classIcon, "BOTTOMLEFT", 0, -2)
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card._specIcon = specIcon

    -- Locked echo icons (below meta)
    card._lockedBtns = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(card, LOCKED_ICON_SIZE)
        btn:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", (i - 1) * (LOCKED_ICON_SIZE + 4), -4)
        -- Rarity ring: 1px frame behind the icon, tinted by echo quality.
        local qb = btn:CreateTexture(nil, "BACKGROUND")
        qb:SetTexture("Interface\\Buttons\\WHITE8X8")
        qb:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        qb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        btn._qualityBorder = qb
        btn:Hide()
        btn:SetScript("OnEnter", function(self)
            if not self._spellId then return end
            local spellName = GetSpellInfo(self._spellId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if spellName then
                local r, g, b = EbonBuilds.Quality.GetRGB(EbonBuilds.Quality.OfSpell(self._spellId))
                GameTooltip:AddLine(spellName, r, g, b)
            end
            if utils and utils.GetSpellDescription then
                local desc = utils.GetSpellDescription(self._spellId, 500, 1)
                if desc and desc ~= "" then GameTooltip:AddLine(desc, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card._lockedBtns[i] = btn
    end

    -- Import button (right side, vertically centered)
    local importBtn = EbonBuilds.Theme.CreateButton(card)
    importBtn:SetWidth(70)
    importBtn:SetHeight(22)
    importBtn:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    importBtn:SetText("Import")
    card._importBtn = importBtn

    if scrollFrame and scrollBar then
        EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, 40, card)
    end
    return card
end

------------------------------------------------------------------------
-- Import logic
------------------------------------------------------------------------

local function FindImportedCopy(publicBuildId)
    for _, b in pairs(EbonBuildsDB.builds) do
        if b.importedFrom == publicBuildId then
            return b
        end
    end
    return nil
end

local function ImportBuild(build)
    local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
    local data = {
        title    = (build.title or "Imported") .. " (imported)",
        class    = build.class,
        spec     = build.spec or 1,
        comments = build.comments or "",
        lockedEchoes = build.lockedEchoes or { nil, nil, nil, nil, nil, nil },
        echoWeights = build.echoWeights and EbonBuilds.Weights.CloneWeights(build.echoWeights) or {},
        echoWeightsByRef = build.echoWeightsByRef and EbonBuilds.Weights.CloneRefWeights(build.echoWeightsByRef) or {},
        echoRefs = EbonBuilds.Build.CloneTable(build.echoRefs),
        unresolvedEchoWeights = EbonBuilds.Build.CloneTable(build.unresolvedEchoWeights),
        echoSchema = build.echoSchema,
        echoCatalogFingerprint = build.echoCatalogFingerprint,
        wizardMeta = EbonBuilds.Build.CloneTable(build.wizardMeta),
        settings = settings,
        isPublic = false,
        startPaused = true,
        characterSnapshot = build.characterSnapshot and EbonBuilds.Build.CloneTable(build.characterSnapshot) or nil,
    }
    local newBuild = EbonBuilds.Build.Create(data)
    newBuild.importedFrom = build.id
    newBuild._importedAt = build.lastModified
    EbonBuilds.Build.EnsureSettings(newBuild)
    -- Deliberately NOT removing build.id from EbonBuildsDB.remoteBuilds
    -- here. The browse list already hides this entry independently
    -- (GetFilteredBuilds: hidden once an up-to-date local copy exists via
    -- FindImportedCopy), so deleting the cache was redundant for that --
    -- and harmful: if the player later deletes their imported local
    -- copy, the public build would otherwise be gone from Public Builds
    -- entirely until the original author's client answers a fresh sync.
    -- Leaving the cache in place means deleting the local copy makes the
    -- original reappear immediately, no re-sync needed.
    EbonBuilds.Build.SetActive(newBuild.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    EbonBuilds.ViewRouter.Show("buildOverview", { build = newBuild })
end

local function UpdateLocalBuild(localBuild, publicBuild)
    EbonBuilds.Build.UpdateFromPublic(localBuild, publicBuild)
    EbonBuilds.Build.SetActive(localBuild.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    EbonBuilds.ViewRouter.Show("buildOverview", { build = localBuild })
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function PopulateCard(card, build)
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    -- Border and stripe color by class
    card:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.8)
    card._stripe:SetTexture(cc[1], cc[2], cc[3], 0.8)
    card._bg:SetTexture(cc[1], cc[2], cc[3], 0.06)

    SetClassIcon(card._classIcon, build.class)

    local twoLines = NeedsTwoLines(build.title)
    card:SetHeight(twoLines and CARD_HEIGHT_DOUBLE or CARD_HEIGHT)
    card._cardHeight = twoLines and CARD_HEIGHT_DOUBLE or CARD_HEIGHT

    card._titleLabel:SetText(build.title or "Untitled")
    card._titleLabel:SetTextColor(cc[1], cc[2], cc[3], 1)
    if twoLines then
        card._titleLabel:SetWidth(TITLE_MAX_W)
        card._titleLabel:SetHeight(28)
    else
        card._titleLabel:SetWidth(0)
        card._titleLabel:SetHeight(0)
    end

    local specName = ""
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specEntry = specs and specs[build.spec or 1]
    if specEntry then
        specName = specEntry.name
        card._specIcon:SetTexture(specEntry.icon)
        card._specIcon:Show()
    else
        card._specIcon:Hide()
    end

    local author = build.author or "Unknown"
    local modified = build.lastModified or ""
    local isOwn = EbonBuildsDB.builds[build.id] ~= nil
    if isOwn then
        card._metaLabel:SetText(string.format("by %s |cff1eff00(You)|r | %s | %s", author, specName, modified))
    else
        card._metaLabel:SetText(string.format("by %s | %s | %s", author, specName, modified))
    end

    -- Locked echo icons
    local lockeds = build.lockedEchoes
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = card._lockedBtns[i]
        local spellId = lockeds and lockeds[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            if btn._qualityBorder then
                local q = EbonBuilds.Quality.OfSpell(spellId)
                local r, g, b = EbonBuilds.Quality.GetRGB(q)
                btn._qualityBorder:SetVertexColor(r, g, b, q and 1 or 0)
            end
            btn:Show()
        else
            btn:Hide()
        end
    end

    -- Import / Update button (builds already loaded and up-to-date are hidden by GetFilteredBuilds)
    if isOwn then
        card._importBtn:SetText("Yours")
        card._importBtn:Disable()
        card._importBtn:SetScript("OnClick", nil)
    else
        local localCopy = FindImportedCopy(build.id)
        if localCopy and build.lastModified ~= localCopy._importedAt then
            card._importBtn:SetText("Update")
            card._importBtn:Enable()
            card._importBtn:SetScript("OnClick", function()
                UpdateLocalBuild(localCopy, build)
            end)
        else
            card._importBtn:SetText("Import")
            card._importBtn:Enable()
            card._importBtn:SetScript("OnClick", function()
                ImportBuild(build)
            end)
        end
    end
end

local function RefreshPaginationControls()
    if state.page > 1 then prevBtn:Enable() else prevBtn:Disable() end
    if state.page < state.totalPages then nextBtn:Enable() else nextBtn:Disable() end
    pageLabel:SetText(string.format("Page %d of %d", state.page, state.totalPages))
end

local function Render()
    local all = state.builds or {}
    if #all == 0 then
        for _, card in ipairs(cardPool) do card:Hide() end
        scrollChild:SetHeight(1)
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        pageLabel:SetText("Page 1 of 1")
        prevBtn:Disable()
        nextBtn:Disable()
        if noBuildsLabel then noBuildsLabel:Show() end
        return
    end
    if noBuildsLabel then noBuildsLabel:Hide() end

    local startIdx = (state.page - 1) * PAGE_SIZE + 1
    local endIdx   = math.min(startIdx + PAGE_SIZE - 1, #all)

    local totalHeight = 0
    for i = startIdx, endIdx do
        local poolIdx = i - startIdx + 1
        if not cardPool[poolIdx] then
            cardPool[poolIdx] = CreateCard(scrollChild)
        end
        local card = cardPool[poolIdx]
        PopulateCard(card, all[i])
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
        card:SetPoint("RIGHT",   scrollChild, "RIGHT",   0, 0)
        card:Show()
        totalHeight = totalHeight + (card._cardHeight or CARD_HEIGHT) + CARD_MARGIN
    end
    for i = endIdx - startIdx + 2, #cardPool do
        cardPool[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, totalHeight))

    local visibleHeight = scrollFrame:GetHeight()
    local maxOffset = math.max(0, totalHeight - visibleHeight)
    scrollBar:SetMinMaxValues(0, maxOffset)
    if scrollBar:GetValue() > maxOffset then scrollBar:SetValue(maxOffset) end

    RefreshPaginationControls()
end

GetFilteredBuilds = function()
    local all = FetchPublicBuilds()
    local filtered = {}
    for _, build in ipairs(all) do
        if filterClass and build.class ~= filterClass then
        elseif filterSpec and build.spec ~= filterSpec then
        else
            -- Own builds are now INCLUDED (not hidden) -- seeing your own
            -- public build listed here is confirmation it actually
            -- published, which used to only be checkable indirectly.
            -- Card rendering tags it "(You)" and disables Import on it.
            local ownBuild = EbonBuildsDB.builds[build.id]
            if ownBuild then
                filtered[#filtered + 1] = build
            else
                local localCopy = FindImportedCopy(build.id)
                if localCopy and build.lastModified == localCopy._importedAt then
                    -- Imported copy is up-to-date: hide
                else
                    filtered[#filtered + 1] = build
                end
            end
        end
    end
    return filtered
end

RefreshView = function()
    state.builds     = GetFilteredBuilds()
    state.page       = 1
    state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
    scrollBar:SetValue(0)
    Render()
end

------------------------------------------------------------------------
-- Scrollbar wiring
------------------------------------------------------------------------

local function WireScrollBar()
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, 40, scrollChild)
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    titleMeasureFont = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleMeasureFont:Hide()

    local pageHeader = EbonBuilds.Theme.CreatePageHeader(
        f,
        "Public Builds",
        "Browse community loadouts, filter by class and specialization, then import a copy to customize."
    )

    noBuildsLabel = EbonBuilds.Theme.CreateEmptyState(
        f,
        "No public builds found",
        "Try another class or specialization, or reload community data when sync is available."
    )
    noBuildsLabel:Hide()

    -- Bottom bar: pagination controls
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  10, 10)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    bottomBar:SetHeight(24)

    prevBtn = EbonBuilds.Theme.CreateButton(bottomBar)
    prevBtn:SetWidth(80)
    prevBtn:SetHeight(22)
    prevBtn:SetPoint("LEFT", bottomBar, "LEFT", 0, 0)
    prevBtn:SetText("Previous")
    prevBtn:SetScript("OnClick", function()
        if state.page > 1 then
            state.page = state.page - 1
            scrollBar:SetValue(0)
            Render()
        end
    end)

    nextBtn = EbonBuilds.Theme.CreateButton(bottomBar)
    nextBtn:SetWidth(80)
    nextBtn:SetHeight(22)
    nextBtn:SetPoint("RIGHT", bottomBar, "RIGHT", 0, 0)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function()
        if state.page < state.totalPages then
            state.page = state.page + 1
            scrollBar:SetValue(0)
            Render()
        end
    end)

    pageLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageLabel:SetPoint("CENTER", bottomBar, "CENTER", 0, 0)
    pageLabel:SetText("Page 1 of 1")

    -- Filter bar: class dropdown, spec dropdown, refresh button
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", pageHeader, "BOTTOMLEFT", 0, -8)
    filterBar:SetPoint("RIGHT",   f,   "RIGHT",     -10, 0)
    filterBar:SetHeight(24)

    classDropdown = EbonBuilds.Theme.CreateDropdown(filterBar, 150, "All Classes")
    classDropdown:SetPoint("LEFT", filterBar, "LEFT", 0, 0)

    specDropdown = EbonBuilds.Theme.CreateDropdown(filterBar, 150, "All Specs")
    specDropdown:SetPoint("LEFT", classDropdown, "RIGHT", 8, 0)

    filterClass = EbonBuilds.Build.PlayerClassToken()
    filterSpec = nil
    InitClassDropdown()
    InitSpecDropdown()

    refreshBtn = EbonBuilds.Theme.CreateButton(filterBar)
    refreshBtn:SetWidth(60)
    refreshBtn:SetHeight(22)
    refreshBtn:SetPoint("LEFT", specDropdown, "RIGHT", 8, 0)
    refreshBtn:SetText("Reload")
    refreshBtn:SetScript("OnClick", function()
        if filterClass then
            EbonBuilds.Sync.RequestSync(filterClass)
        else
            EbonBuilds.Sync.RequestSyncAllClasses()
        end
    end)
    refreshBtn:SetScript("OnUpdate", function(self, dt)
        -- Throttle: the cooldown label only shows whole seconds, so per-frame
        -- string building + SetText is wasted garbage churn.
        self._throttle = (self._throttle or 0) + dt
        if self._throttle < 0.25 then return end
        self._throttle = 0

        local remaining = EbonBuilds.Sync.GetCooldownRemaining()
        if remaining ~= self._lastRemaining then
            self._lastRemaining = remaining
            if remaining > 0 then
                refreshBtn:Disable()
                refreshBtn:SetText("Wait " .. remaining .. "s")
            else
                refreshBtn:Enable()
                refreshBtn:SetText("Reload")
            end
        end
    end)

    -- Scroll area
    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(scrollFrame, "PublicBuildsView.ScrollFrame")
    end
    scrollFrame:SetPoint("TOPLEFT",     filterBar, "BOTTOMLEFT",  0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT",    0,  8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Keep scrollChild width in sync with scrollFrame
    scrollFrame:SetScript("OnSizeChanged", function()
        local w = scrollFrame:GetWidth()
        if w and w > 0 then
            scrollChild:SetWidth(w)
            Render()
        end
    end)

    scrollBar = EbonBuilds.Theme.CreateScrollBar(scrollFrame)
    scrollBar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2,  4)
    scrollBar:SetValueStep(20)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)

    WireScrollBar()
    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.PublicBuildsView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    -- Ensure scrollChild has proper width before rendering
    local w = viewFrame:GetWidth()
    if w and w > 0 then scrollChild:SetWidth(w - 24) end

    state.builds     = GetFilteredBuilds()
    state.page       = 1
    state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
    scrollBar:SetValue(0)
    local ok, err = pcall(Render)
    if not ok and EbonBuilds.ErrorLog then
        EbonBuilds.ErrorLog.Record("PublicBuildsView.Mount/Render", tostring(err))
    end
    viewFrame:Show()
end

function EbonBuilds.PublicBuildsView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

local pendingRefresh = false
local REFRESH_THROTTLE = 0.3 -- seconds; coalesces bursty sync-driven refreshes

local function DoRefreshIfMounted()
    if not (viewFrame and viewFrame:IsVisible()) then return end
    state.builds     = GetFilteredBuilds()
    state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
    -- Preserve whatever page the player is currently browsing. This
    -- used to hard-reset to page 1 on every single incoming build --
    -- fine for one build, but a sync (especially the staggered
    -- all-classes sync, 2.15) can stream in dozens over several
    -- seconds, snapping the view back to page 1 over and over and
    -- making it impossible to actually browse while syncing.
    if state.page > state.totalPages then
        state.page = state.totalPages
    end
    Render()
end

function EbonBuilds.PublicBuildsView.RefreshIfMounted()
    if not (viewFrame and viewFrame:IsVisible()) then return end
    pendingRefresh = true
    EbonBuilds.Scheduler.After("publicBuilds.refresh", REFRESH_THROTTLE, function()
        if pendingRefresh then
            pendingRefresh = false
            DoRefreshIfMounted()
        end
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "PublicBuildsView")
end

function EbonBuilds.PublicBuildsView.Init()
end
