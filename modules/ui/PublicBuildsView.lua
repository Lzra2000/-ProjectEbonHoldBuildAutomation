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

local RefreshView, GetFilteredBuilds, ShowInspect, ShowCharacterDetail

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

    -- Vote button (top-right). Shows the distinct-voter tally this
    -- client has heard (see BuildVotes.lua's trust model); the chevron
    -- fills gold when this character's own vote is among them.
    local voteBtn = EbonBuilds.Theme.CreateButton(card)
    voteBtn:SetWidth(50)
    voteBtn:SetHeight(18)
    voteBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
    voteBtn:SetText("")
    local voteIcon = voteBtn:CreateTexture(nil, "ARTWORK")
    voteIcon:SetWidth(14)
    voteIcon:SetHeight(14)
    voteIcon:SetPoint("LEFT", voteBtn, "LEFT", 6, 0)
    voteBtn._icon = voteIcon
    local voteCount = voteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    voteCount:SetPoint("LEFT", voteIcon, "RIGHT", 4, 0)
    voteBtn._count = voteCount
    card._voteBtn = voteBtn
    EbonBuilds.Theme.AttachTooltip(voteBtn, "Upvote",
        "Acknowledge a well-made build. One vote per character, click again to remove it. The number is how many distinct voters this client has heard from.")

    -- The whole card opens the read-only inspect view.
    card:SetScript("OnClick", function(self)
        if self._build and ShowInspect then ShowInspect(self._build) end
    end)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(card, "PublicBuildsView.Card")
    end

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
-- Inspect (read-only detail view, issue #8)
------------------------------------------------------------------------
-- A card's whole surface opens this: class/spec, the author's intent
-- (their comments field), locked Echoes, and top configured priorities
-- -- enough to make an informed vote or import decision without
-- dropping into a full editor the browsing player doesn't own.

local inspectFrame

local function AllPriorities(build)
    if not (EbonBuilds.EchoProjection and EbonBuilds.Weights and EbonBuilds.Quality) then return {} end
    local rows = {}
    for _, info in ipairs(EbonBuilds.EchoProjection.GetAvailable(build.class) or {}) do
        local best, bestQuality = 0, nil
        for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
            if info.qualities and info.qualities[quality] then
                local v = EbonBuilds.Weights.GetForRef(build, info.refKey, quality) or 0
                if v > best then best, bestQuality = v, quality end
            end
        end
        if best > 0 then
            rows[#rows + 1] = {
                name = info.displayName or info.name,
                weight = best,
                quality = bestQuality,
                spellId = info.spellId,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.name < b.name
    end)
    return rows
end

EbonBuilds.PublicBuildsView._TopPrioritiesForTest = AllPriorities

-- CharacterSummary(snapshot): a compact, read-only summary line pair for
-- Inspect -- talent point split across the three tabs, and equipped-gear
-- count with average item level. Deliberately NOT the full talent-tree
-- canvas or paperdoll CharacterView.lua renders for the player's OWN
-- character; those exist for editing, this is for a quick "is this build
-- actually specced/geared the way the title claims" glance while
-- browsing someone else's build.
local function CharacterSummary(snapshot)
    if not snapshot then return nil end
    local talentParts = {}
    for tab = 1, 3 do
        talentParts[#talentParts + 1] = tostring(snapshot.talents and snapshot.talents[tab] and snapshot.talents[tab].points or 0)
    end
    local slots = (EbonBuilds.CharacterSnapshot and EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS) or {}
    local total, equipped, ilvlSum, ilvlCount = #slots, 0, 0, 0
    for _, slot in ipairs(slots) do
        local item = snapshot.gear and snapshot.gear[slot.id]
        if item and not slot.cosmetic then
            equipped = equipped + 1
            if item.itemLevel and item.itemLevel > 0 then
                ilvlSum = ilvlSum + item.itemLevel
                ilvlCount = ilvlCount + 1
            end
        end
    end
    return {
        talentsText = table.concat(talentParts, " / "),
        gearText = ilvlCount > 0
            and string.format("%d/%d equipped, avg item level %.0f", equipped, total, ilvlSum / ilvlCount)
            or string.format("%d/%d equipped", equipped, total),
        capturedAt = snapshot.capturedAt,
    }
end
EbonBuilds.PublicBuildsView._CharacterSummaryForTest = CharacterSummary

local function BuildInspectFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    EbonBuilds.Theme.ApplyBackdropDefinition(f)
    f:SetBackdropColor(0, 0, 0, 0.92)
    -- A frame-level offset alone isn't enough here: it only wins against
    -- siblings in the SAME strata, and the scrollable build list beneath
    -- (nested ScrollFrame -> scrollChild -> card -> buttons) can end up
    -- several levels deep depending on template internals, which was
    -- letting card content show through at reduced brightness instead of
    -- being fully covered. An explicit higher strata is unconditional.
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)

    local closeBtn = EbonBuilds.Theme.CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local classIcon = f:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(36)
    classIcon:SetHeight(36)
    classIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    f._classIcon = classIcon

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 10, -2)
    title:SetPoint("RIGHT", f, "RIGHT", -100, 0)
    title:SetJustifyH("LEFT")
    f._title = title

    local meta = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    meta:SetPoint("RIGHT", f, "RIGHT", -100, 0)
    meta:SetJustifyH("LEFT")
    f._meta = meta

    local voteBtn = EbonBuilds.Theme.CreateButton(f)
    voteBtn:SetWidth(80)
    voteBtn:SetHeight(22)
    voteBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -18)
    voteBtn:SetText("")
    local voteIcon = voteBtn:CreateTexture(nil, "ARTWORK")
    voteIcon:SetWidth(16)
    voteIcon:SetHeight(16)
    voteIcon:SetPoint("LEFT", voteBtn, "LEFT", 12, 0)
    voteBtn._icon = voteIcon
    local voteCount = voteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    voteCount:SetPoint("LEFT", voteIcon, "RIGHT", 5, 0)
    voteBtn._count = voteCount
    f._voteBtn = voteBtn

    local intentLabel = EbonBuilds.Theme.CreateSectionLabel(f, "Intent", classIcon, -18)
    f._intentLabel = intentLabel

    local intentText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intentText:SetPoint("TOPLEFT", intentLabel, "BOTTOMLEFT", 0, -4)
    intentText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    intentText:SetJustifyH("LEFT")
    intentText:SetJustifyV("TOP")
    intentText:SetNonSpaceWrap(true)
    f._intentText = intentText

    local lockedLabel = EbonBuilds.Theme.CreateSectionLabel(f, "Locked Echoes")
    f._lockedLabel = lockedLabel

    f._lockedBtns = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(f, 26)
        f._lockedBtns[i] = btn
    end

    -- Character snapshot summary (talents + gear). Optional on the build
    -- (only present if the author used "Adopt snapshot"), so this reads
    -- gracefully whether or not the data exists rather than showing an
    -- empty section.
    local charLabel = EbonBuilds.Theme.CreateSectionLabel(f, "Character")
    f._charLabel = charLabel

    local talentsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    talentsText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    talentsText:SetJustifyH("LEFT")
    f._talentsText = talentsText

    local gearText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gearText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    gearText:SetJustifyH("LEFT")
    f._gearText = gearText

    -- Opens the full talent tree / gear paperdoll / glyphs view -- the
    -- exact same renderer the build editor uses, mounted read-only
    -- against this build's snapshot instead of the live character.
    local viewCharBtn = EbonBuilds.Theme.CreateButton(f)
    viewCharBtn:SetWidth(150)
    viewCharBtn:SetHeight(20)
    viewCharBtn:SetText("View full character")
    f._viewCharBtn = viewCharBtn
    viewCharBtn:SetScript("OnClick", function()
        if f._build and ShowCharacterDetail then ShowCharacterDetail(f._build) end
    end)

    local priLabel = EbonBuilds.Theme.CreateSectionLabel(f, "Weighted Priorities")
    f._priLabel = priLabel

    local importBtn = EbonBuilds.Theme.CreateButton(f)
    importBtn:SetWidth(140)
    importBtn:SetHeight(24)
    importBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    f._importBtn = importBtn

    -- Scrollable priority list: the old version showed at most 8 flat
    -- text lines ("1. Name (12)"), nothing like the icon + quality-color
    -- rows the editor uses for the same data. This mirrors that instead,
    -- and shows every configured priority rather than a hard cap.
    local priScroll = CreateFrame("ScrollFrame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(priScroll, "PublicBuildsView.Inspect.PriScroll")
    end
    -- BOTTOMRIGHT anchored to f's actual bottom-right corner (not the
    -- horizontally-centered BOTTOM point) with room left for the
    -- scrollbar (34px) and the Import button below (52px).
    priScroll:SetPoint("TOPLEFT", priLabel, "BOTTOMLEFT", 0, -6)
    priScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 52)
    f._priScroll = priScroll

    local priChild = CreateFrame("Frame", nil, priScroll)
    priChild:SetWidth(1)
    priChild:SetHeight(1)
    priScroll:SetScrollChild(priChild)
    f._priChild = priChild

    local priBar = EbonBuilds.Theme.CreateScrollBar(f)
    priBar:SetPoint("TOPLEFT", priScroll, "TOPRIGHT", 4, 0)
    priBar:SetPoint("BOTTOMLEFT", priScroll, "BOTTOMRIGHT", 4, 0)
    priBar:SetValueStep(20)
    priBar:SetMinMaxValues(0, 0)
    priBar:SetValue(0)
    priBar:SetScript("OnValueChanged", function(_, value)
        priChild:ClearAllPoints()
        priChild:SetPoint("TOPLEFT", priScroll, "TOPLEFT", 0, value)
    end)
    f._priBar = priBar
    EbonBuilds.Theme.BindScrollWheel(priScroll, priBar, 24)

    priScroll:SetScript("OnSizeChanged", function()
        local w = priScroll:GetWidth()
        if w and w > 0 and f._priRowPool then
            priChild:SetWidth(w)
            for _, row in ipairs(f._priRowPool) do row:SetWidth(w) end
        end
        if f._currentBuild and f._RefreshPriorities then f._RefreshPriorities() end
    end)

    f._priRowPool = {}
    f._priEmpty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f._priEmpty:SetPoint("TOPLEFT", priLabel, "BOTTOMLEFT", 0, -6)
    f._priEmpty:SetText("No weighted priorities configured.")

    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "PublicBuildsView.Inspect")
    end
    f:Hide()
    return f
end

local PRI_ROW_HEIGHT = 22
local PRI_ROW_ICON = 18

local function CreatePriorityRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PRI_ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(PRI_ROW_ICON)
    icon:SetHeight(PRI_ROW_ICON)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    name:SetJustifyH("LEFT")
    row._name = name

    local weight = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    weight:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    weight:SetJustifyH("RIGHT")
    weight:SetTextColor(0.7, 0.7, 0.7, 1)
    row._weight = weight

    return row
end

-- Fills the pooled, scrollable priority list from AllPriorities(build).
-- Same icon-lookup convention as the Locked Echoes row (GetSpellInfo's
-- 3rd return is the icon texture).
local function PopulateInspectPriorities(f, build)
    f._currentBuild = build
    f._RefreshPriorities = function() PopulateInspectPriorities(f, build) end
    local rows = AllPriorities(build)
    if #rows == 0 then f._priEmpty:Show() else f._priEmpty:Hide() end
    if #rows > 0 then f._priScroll:Show() else f._priScroll:Hide() end
    if #rows > 0 then f._priBar:Show() else f._priBar:Hide() end

    for i, entry in ipairs(rows) do
        local row = f._priRowPool[i]
        if not row then
            row = CreatePriorityRow(f._priChild)
            f._priRowPool[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f._priChild, "TOPLEFT", 0, -(i - 1) * PRI_ROW_HEIGHT)
        row:SetPoint("RIGHT", f._priChild, "RIGHT", 0, 0)
        if entry.spellId then
            row._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
            row._icon:Show()
        else
            row._icon:Hide()
        end
        local r, g, b = EbonBuilds.Quality.GetRGB(entry.quality)
        row._name:SetText(entry.name)
        row._name:SetTextColor(r, g, b, 1)
        row._weight:SetText(tostring(entry.weight))
        row:Show()
    end
    for i = #rows + 1, #f._priRowPool do
        f._priRowPool[i]:Hide()
    end

    local w = f._priScroll:GetWidth()
    if w and w > 0 then f._priChild:SetWidth(w) end
    local totalHeight = math.max(1, #rows * PRI_ROW_HEIGHT)
    f._priChild:SetHeight(totalHeight)
    local visible = f._priScroll:GetHeight() or 0
    local maxScroll = math.max(0, totalHeight - visible)
    f._priBar:SetMinMaxValues(0, maxScroll)
    f._priBar:SetValue(0)
    f._priChild:ClearAllPoints()
    f._priChild:SetPoint("TOPLEFT", f._priScroll, "TOPLEFT", 0, 0)
end

-- Locked Echo icon count never changes (EbonBuilds.Build.LOCKED_SLOTS is
-- a constant), so this only needs to run once per frame, not per
-- ShowInspect call -- but it's cheap and idempotent, so keeping it here
-- keeps the "re-layout on every open" pattern the rest of the file uses.
local function LayoutInspectRows(f)
    f._lockedLabel:ClearAllPoints()
    f._lockedLabel:SetPoint("TOPLEFT", f._intentText, "BOTTOMLEFT", 0, -16)
    local x = 0
    for i, btn in ipairs(f._lockedBtns) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f._lockedLabel, "BOTTOMLEFT", x, -6)
        x = x + 32
    end
    f._charLabel:ClearAllPoints()
    f._charLabel:SetPoint("TOPLEFT", f._lockedLabel, "BOTTOMLEFT", 0, -40)
    f._viewCharBtn:ClearAllPoints()
    f._viewCharBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, 0)
    f._viewCharBtn:SetPoint("TOP", f._charLabel, "TOP", 0, 4)
    f._talentsText:ClearAllPoints()
    f._talentsText:SetPoint("TOPLEFT", f._charLabel, "BOTTOMLEFT", 0, -4)
    f._talentsText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f._gearText:ClearAllPoints()
    f._gearText:SetPoint("TOPLEFT", f._talentsText, "BOTTOMLEFT", 0, -2)
    f._gearText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f._priLabel:ClearAllPoints()
    f._priLabel:SetPoint("TOPLEFT", f._gearText, "BOTTOMLEFT", 0, -14)
end

------------------------------------------------------------------------
-- Character detail (full talent tree / gear paperdoll / glyphs)
------------------------------------------------------------------------
-- Mounts the SAME CharacterView the build editor uses -- not a
-- hand-rolled approximation -- against this build's snapshot instead
-- of the live character, via CharacterView's read-only mode (see
-- modules/ui/CharacterView.lua: EditingClassToken/StoredSnapshot check
-- mountedContext.readOnly first). One instance reused across opens;
-- it's a singleton view like every other page in the addon, so Unmount
-- on close hands it back cleanly for the next real editing session.

local characterFrame, characterContainer

local function BuildCharacterFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    EbonBuilds.Theme.ApplyBackdropDefinition(f)
    f:SetBackdropColor(0, 0, 0, 0.94)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 40)

    local closeBtn = EbonBuilds.Theme.CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function()
        if EbonBuilds.CharacterView and EbonBuilds.CharacterView.Unmount then
            EbonBuilds.CharacterView.Unmount()
        end
        f:Hide()
    end)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
    header:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    header:SetJustifyH("LEFT")
    f._header = header

    local container = CreateFrame("Frame", nil, f)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -12)
    container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    f._container = container

    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "PublicBuildsView.CharacterDetail")
    end
    f:Hide()
    return f
end

ShowCharacterDetail = function(build)
    if not (build and build.characterSnapshot and viewFrame) then return end
    if not characterFrame then
        characterFrame = BuildCharacterFrame(viewFrame)
    end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }
    characterFrame._header:SetText((build.title or "Untitled") .. " |cff888888-- read-only|r")
    characterFrame._header:SetTextColor(cc[1], cc[2], cc[3], 1)

    if EbonBuilds.CharacterView and EbonBuilds.CharacterView.Mount then
        EbonBuilds.CharacterView.Mount(characterFrame._container, {
            readOnly = true,
            snapshot = build.characterSnapshot,
            snapshotClass = build.class,
            spec = build.spec,
        })
    end

    characterFrame:ClearAllPoints()
    characterFrame:SetAllPoints(viewFrame)
    characterFrame:Show()
end

-- ShowInspect(build): populates and shows the panel for one build.
-- Reads live so the vote count/state and locked copy stay current
-- across repeated opens without rebuilding the frame.
ShowInspect = function(build)
    if not (inspectFrame and viewFrame) then return end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }
    SetClassIcon(inspectFrame._classIcon, build.class)
    inspectFrame._title:SetText(build.title or "Untitled")
    inspectFrame._title:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specName = ""
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specEntry = specs and specs[build.spec or 1]
    if specEntry then specName = specEntry.name end
    local isOwn = EbonBuildsDB.builds[build.id] ~= nil
    inspectFrame._meta:SetText(string.format("by %s%s | %s | %s",
        build.author or "Unknown", isOwn and " |cff1eff00(You)|r" or "", specName, build.lastModified or ""))

    local votes = (EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(build.id)) or 0
    local voted = EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.HasVoted(build.id)
    inspectFrame._voteBtn._icon:SetTexture(voted
        and "Interface\\AddOns\\EbonBuilds\\media\\vote_icon"
        or "Interface\\AddOns\\EbonBuilds\\media\\vote_icon_off")
    inspectFrame._voteBtn._count:SetText(tostring(votes))
    inspectFrame._voteBtn._count:SetTextColor(voted and 0.90 or 0.78, voted and 0.75 or 0.78, voted and 0.20 or 0.78, 1)
    if isOwn then
        inspectFrame._voteBtn:Disable()
        inspectFrame._voteBtn:SetScript("OnClick", nil)
    else
        inspectFrame._voteBtn:Enable()
        inspectFrame._voteBtn:SetScript("OnClick", function()
            if EbonBuilds.BuildVotes then
                EbonBuilds.BuildVotes.Toggle(build.id)
                ShowInspect(build)
            end
        end)
    end

    local intent = build.comments
    inspectFrame._intentText:SetText((intent and intent ~= "") and intent or "|cff888888No intent notes from the author.|r")

    for i, btn in ipairs(inspectFrame._lockedBtns) do
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()
        else
            btn:Hide()
        end
    end

    inspectFrame._build = build

    local summary = CharacterSummary(build.characterSnapshot)
    if summary then
        inspectFrame._talentsText:SetText("|cffaaaaaaTalents:|r " .. summary.talentsText)
        inspectFrame._gearText:SetText("|cffaaaaaaGear:|r " .. summary.gearText)
        inspectFrame._viewCharBtn:Enable()
    else
        inspectFrame._talentsText:SetText("|cff888888No character snapshot shared for this build.|r")
        inspectFrame._gearText:SetText("")
        inspectFrame._viewCharBtn:Disable()
    end

    PopulateInspectPriorities(inspectFrame, build)

    if isOwn then
        inspectFrame._importBtn:SetText("Yours")
        inspectFrame._importBtn:Disable()
        inspectFrame._importBtn:SetScript("OnClick", nil)
    else
        local localCopy = FindImportedCopy(build.id)
        if localCopy and build.lastModified ~= localCopy._importedAt then
            inspectFrame._importBtn:SetText("Update")
            inspectFrame._importBtn:Enable()
            inspectFrame._importBtn:SetScript("OnClick", function()
                UpdateLocalBuild(localCopy, build)
                inspectFrame:Hide()
            end)
        else
            inspectFrame._importBtn:SetText("Import")
            inspectFrame._importBtn:Enable()
            inspectFrame._importBtn:SetScript("OnClick", function()
                ImportBuild(build)
                inspectFrame:Hide()
            end)
        end
    end

    LayoutInspectRows(inspectFrame)
    inspectFrame:ClearAllPoints()
    inspectFrame:SetAllPoints(viewFrame)
    inspectFrame:Show()
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function PopulateCard(card, build)
    card._build = build
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    -- Vote button: tally + own-vote state. Voting your own build is
    -- disabled -- the credit is meant to come from others.
    if card._voteBtn then
        local votes = (EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(build.id)) or 0
        local voted = EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.HasVoted(build.id)
        card._voteBtn._icon:SetTexture(voted
            and "Interface\\AddOns\\EbonBuilds\\media\\vote_icon"
            or "Interface\\AddOns\\EbonBuilds\\media\\vote_icon_off")
        card._voteBtn._count:SetText(tostring(votes))
        card._voteBtn._count:SetTextColor(voted and 0.90 or 0.78, voted and 0.75 or 0.78, voted and 0.20 or 0.78, 1)
        if EbonBuildsDB.builds[build.id] then
            card._voteBtn:Disable()
            card._voteBtn:SetScript("OnClick", nil)
        else
            card._voteBtn:Enable()
            card._voteBtn:SetScript("OnClick", function()
                if EbonBuilds.BuildVotes then
                    EbonBuilds.BuildVotes.Toggle(build.id)
                    PopulateCard(card, build)
                end
            end)
        end
    end

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
    -- Deterministic order (the raw list comes out of pairs()): most
    -- voted first -- the issue-#8 point of votes is exactly to sort the
    -- cared-for builds from the experiments -- then title, then id.
    table.sort(filtered, function(a, b)
        local va = (EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(a.id)) or 0
        local vb = (EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(b.id)) or 0
        if va ~= vb then return va > vb end
        local ta, tb = tostring(a.title or ""), tostring(b.title or "")
        if ta ~= tb then return ta < tb end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
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
    inspectFrame = BuildInspectFrame(viewFrame)
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
    -- Navigating away from Public Builds entirely while the character
    -- detail overlay is open must hand CharacterView back cleanly --
    -- otherwise it stays mounted read-only against a stale snapshot the
    -- next time something else tries to use it.
    if characterFrame and characterFrame:IsShown() then
        if EbonBuilds.CharacterView and EbonBuilds.CharacterView.Unmount then
            EbonBuilds.CharacterView.Unmount()
        end
        characterFrame:Hide()
    end
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

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    EbonBuilds.Debug.RegisterTest("PublicBuildsView.CharacterSummary reports talents and gear, or nil without a snapshot", function()
        if EbonBuilds.PublicBuildsView._CharacterSummaryForTest(nil) ~= nil then
            error("expected nil summary for a build with no character snapshot")
        end
        local summary = EbonBuilds.PublicBuildsView._CharacterSummaryForTest({
            talents = { [1] = { points = 31 }, [2] = { points = 0 }, [3] = { points = 20 } },
            gear = {
                [1] = { itemLevel = 226 },  -- Head
                [5] = { itemLevel = 232 },  -- Chest
                [4] = { itemLevel = 999 },  -- Shirt (cosmetic, must not count toward ilvl or equipped)
            },
        })
        if not summary then error("expected a summary when a snapshot is present") end
        if summary.talentsText ~= "31 / 0 / 20" then error("wrong talent text: " .. tostring(summary.talentsText)) end
        if not summary.gearText:find("2/19 equipped") then error("wrong gear text: " .. tostring(summary.gearText)) end
        if not summary.gearText:find("229") then error("cosmetic slot must not skew average item level: " .. tostring(summary.gearText)) end
    end)

    EbonBuilds.Debug.RegisterTest("PublicBuildsView.TopPriorities degrades safely without catalog data", function()
        local rows = EbonBuilds.PublicBuildsView._TopPrioritiesForTest({ class = "NONEXISTENT_CLASS_TOKEN" })
        if type(rows) ~= "table" then error("expected a table even with no matching class data") end
    end)
end
