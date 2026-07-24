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
local TEXTURES = EbonBuilds.ThemeRegistry.Get().textures

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

local classDropdown, specDropdown, refreshBtn, sortDropdown
local searchBox, searchPlaceholder
local peerTabBtn, journalTabBtn
local filterClass, filterSpec
local filterText = ""
local sortMode = "votes"  -- "votes" | "newest" | "itemlevel" | "trending"
-- UI source tabs: peer sync vs PE Echo Journal (CommunityEligibility still
-- uses both independently for recommendations).
local SOURCE_PEER = "peer"
local SOURCE_JOURNAL = "journal"
local listSource = SOURCE_PEER
local SORT_LABELS = {
    votes     = "Most Votes",
    newest    = "Newest",
    itemlevel = "Item Level",
    trending  = "Trending",
}

------------------------------------------------------------------------
-- Data source
------------------------------------------------------------------------

local function FetchPeerBuilds()
    -- Local public + remoteBuilds only (also what Sync relays). Never merge
    -- Echo Journal pseudo-builds into this list.
    local out = EbonBuilds.Build.ListPublic()
    local dense = {}
    for _, b in ipairs(out) do
        if type(b) == "table" then dense[#dense + 1] = b end
    end
    return dense
end

local function FetchJournalBuilds()
    local bridge = EbonBuilds.SharedLoadoutBridge
    if not (bridge and bridge.ListPseudoBuilds) then return {} end
    local dense = {}
    for _, b in ipairs(bridge.ListPseudoBuilds() or {}) do
        if type(b) == "table" then dense[#dense + 1] = b end
    end
    return dense
end

local function FetchPublicBuilds()
    if listSource == SOURCE_JOURNAL then
        return FetchJournalBuilds()
    end
    return FetchPeerBuilds()
end

EbonBuilds.PublicBuildsView._FetchPublicBuildsForTest = FetchPublicBuilds
EbonBuilds.PublicBuildsView._SetListSourceForTest = function(source)
    if source == SOURCE_JOURNAL then
        listSource = SOURCE_JOURNAL
    else
        listSource = SOURCE_PEER
    end
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

local function ToastAutoAcceptWarn(info)
    if info and info.autoAcceptWarn and EbonBuilds.Toast then
        EbonBuilds.Toast.Show("Warning: Auto-Accept is ON for this foreign loadout")
    end
end

local function ApplyPublicWishlist(build)
    local api = EbonBuilds.ProjectAPI
    if not (api and api.ApplyBuildAsWishlist) then
        if EbonBuilds.Toast then EbonBuilds.Toast.Show("Server doesn't support Active Echo Loadout") end
        return
    end
    local function run(b)
        local ok, err, info = api.ApplyBuildAsWishlist(b)
        if not EbonBuilds.Toast then return end
        if ok then
            EbonBuilds.Toast.Show("Wishlist applied: \"" .. (b.title or "?") .. "\"")
            ToastAutoAcceptWarn(info)
        elseif err == "unsupported" then
            EbonBuilds.Toast.Show("Server doesn't support Active Echo Loadout")
        elseif err == "empty" then
            EbonBuilds.Toast.Show("No locked echoes to apply")
        else
            EbonBuilds.Toast.Show("Failed to apply wishlist")
        end
    end
    if api.WithForeignAutoAcceptConfirm then
        api.WithForeignAutoAcceptConfirm(build, run)
    else
        run(build)
    end
end

local function UploadPublicServerSlot(build)
    local api = EbonBuilds.ProjectAPI
    if not (api and api.UploadBuildAsServerSlot) then
        if EbonBuilds.Toast then EbonBuilds.Toast.Show("Server doesn't support designed build slots") end
        return
    end
    local function run(b)
        local ok, err, info = api.UploadBuildAsServerSlot(b, 0)
        if not EbonBuilds.Toast then return end
        if ok then
            local msg = "Saved \"" .. (b.title or "?") .. "\" as server loadout"
            if info and info.skipped and info.skipped > 0 then
                msg = msg .. string.format(" (%d class-skipped)", info.skipped)
            end
            EbonBuilds.Toast.Show(msg)
            ToastAutoAcceptWarn(info)
        elseif err == "disabled" or err == "unsupported" then
            EbonBuilds.Toast.Show("Server build slots unavailable")
        elseif err == "empty" then
            EbonBuilds.Toast.Show("No locked echoes to upload")
        else
            EbonBuilds.Toast.Show("Failed to save server loadout")
        end
    end
    if api.WithForeignAutoAcceptConfirm then
        api.WithForeignAutoAcceptConfirm(build, run)
    else
        run(build)
    end
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
        -- Total order: never return true for both (a,b) and (b,a), and
        -- never index a nil hole if the row list is sparse.
        if a == nil or b == nil then
            if a == nil and b == nil then return false end
            return b == nil
        end
        local wa, wb = a.weight or 0, b.weight or 0
        if wa ~= wb then return wa > wb end
        return tostring(a.name or "") < tostring(b.name or "")
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
        -- Raw average, for sorting -- nil (not 0) when no piece has a
        -- resolved item level yet, so callers can push unknown-ilvl
        -- builds to the bottom of a ranking instead of the top.
        avgItemLevel = ilvlCount > 0 and (ilvlSum / ilvlCount) or nil,
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

    -- Everything from Intent through Weighted Priorities lives inside ONE
    -- scrollable region instead of being anchored directly on the panel.
    -- Intent is free-form author text with no length limit (see the
    -- "DK Solo eco" build report: gear/talent/leveling notes running to
    -- a dozen paragraphs) -- fixed-position anchoring below it meant a
    -- long Intent pushed Locked Echoes, the Character section, and the
    -- priorities list arbitrarily far down, past the panel's own fixed-
    -- height backdrop, with nothing clipping the overflow: it rendered
    -- straight through onto the game world behind the panel. One scroll
    -- region bounds ALL of it to the panel's actual visible area,
    -- regardless of how long any single build's Intent is.
    local contentScroll = CreateFrame("ScrollFrame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(contentScroll, "PublicBuildsView.Inspect.ContentScroll")
    end
    contentScroll:SetPoint("TOPLEFT", intentLabel, "BOTTOMLEFT", 0, -4)
    contentScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 78)
    f._contentScroll = contentScroll

    local contentChild = CreateFrame("Frame", nil, contentScroll)
    contentChild:SetWidth(1)
    contentChild:SetHeight(1)
    contentScroll:SetScrollChild(contentChild)
    f._contentChild = contentChild

    local contentBar = EbonBuilds.Theme.CreateScrollBar(f)
    contentBar:SetPoint("TOPLEFT", contentScroll, "TOPRIGHT", 4, 0)
    contentBar:SetPoint("BOTTOMLEFT", contentScroll, "BOTTOMRIGHT", 4, 0)
    contentBar:SetValueStep(20)
    contentBar:SetMinMaxValues(0, 0)
    contentBar:SetValue(0)
    contentBar:SetScript("OnValueChanged", function(_, value)
        contentChild:ClearAllPoints()
        contentChild:SetPoint("TOPLEFT", contentScroll, "TOPLEFT", 0, value)
    end)
    f._contentBar = contentBar
    EbonBuilds.Theme.BindScrollWheel(contentScroll, contentBar, 24)

    contentScroll:SetScript("OnSizeChanged", function()
        if f._currentBuild and f._RefreshInspectContent then f._RefreshInspectContent() end
    end)

    local intentText = contentChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intentText:SetJustifyH("LEFT")
    intentText:SetJustifyV("TOP")
    intentText:SetNonSpaceWrap(true)
    f._intentText = intentText

    local lockedLabel = EbonBuilds.Theme.CreateSectionLabel(contentChild, "Locked Echoes")
    f._lockedLabel = lockedLabel

    f._lockedBtns = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(contentChild, 26)
        f._lockedBtns[i] = btn
    end

    -- Character snapshot summary (talents + gear). Optional on the build
    -- (only present if the author used "Adopt snapshot"), so this reads
    -- gracefully whether or not the data exists rather than showing an
    -- empty section.
    local charLabel = EbonBuilds.Theme.CreateSectionLabel(contentChild, "Character")
    f._charLabel = charLabel

    local talentsText = contentChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    talentsText:SetJustifyH("LEFT")
    f._talentsText = talentsText

    local gearText = contentChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gearText:SetJustifyH("LEFT")
    f._gearText = gearText

    -- Opens the full talent tree / gear paperdoll / glyphs view -- the
    -- exact same renderer the build editor uses, mounted read-only
    -- against this build's snapshot instead of the live character.
    local viewCharBtn = EbonBuilds.Theme.CreateButton(contentChild)
    viewCharBtn:SetWidth(150)
    viewCharBtn:SetHeight(20)
    viewCharBtn:SetText("View full character")
    f._viewCharBtn = viewCharBtn
    viewCharBtn:SetScript("OnClick", function()
        if f._build and ShowCharacterDetail then ShowCharacterDetail(f._build) end
    end)

    local priLabel = EbonBuilds.Theme.CreateSectionLabel(contentChild, "Weighted Priorities")
    f._priLabel = priLabel

    local importBtn = EbonBuilds.Theme.CreateButton(f)
    importBtn:SetWidth(100)
    importBtn:SetHeight(24)
    importBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    f._importBtn = importBtn

    local L = EbonBuilds.L or setmetatable({}, { __index = function(_, k) return k end })

    local wishlistBtn = EbonBuilds.Theme.CreateButton(f)
    wishlistBtn:SetWidth(120)
    wishlistBtn:SetHeight(24)
    wishlistBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
    wishlistBtn:SetText(L["Apply wishlist"])
    f._wishlistBtn = wishlistBtn

    local serverBtn = EbonBuilds.Theme.CreateButton(f)
    serverBtn:SetWidth(160)
    serverBtn:SetHeight(24)
    serverBtn:SetPoint("LEFT", wishlistBtn, "RIGHT", 8, 0)
    serverBtn:SetText(L["Save as server loadout"])
    f._serverLoadoutBtn = serverBtn

    -- Priority rows: icon + quality-colored name + weight, same as the
    -- editor -- pooled and parented to the single content scroll child
    -- above (no longer a separate nested scroll region of their own).
    f._priRowPool = {}
    f._priEmpty = contentChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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

-- RefreshInspectContent(f): the single pass that lays out and sizes
-- EVERYTHING inside the scrollable content region -- Intent, Locked
-- Echoes, Character summary, and Weighted Priorities -- back to back,
-- each section's start position depending on the ACTUAL rendered
-- height of the one before it (GetStringHeight() only returns a real
-- number after SetText + a resolved width, hence this all runs as one
-- populate-then-measure-then-position pass rather than fixed offsets).
-- Called after any content changes (new build shown, character-summary
-- text set, priority rows repopulated) and on scroll-frame resize.
local function RefreshInspectContent(f, build)
    local w = f._contentScroll:GetWidth()
    if not w or w <= 0 then return end
    f._contentChild:SetWidth(w)

    f._intentText:SetWidth(w)
    f._intentText:ClearAllPoints()
    f._intentText:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, 0)
    local y = -(f._intentText:GetStringHeight() or 14)

    f._lockedLabel:ClearAllPoints()
    f._lockedLabel:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 16)
    y = y - 16 - 14

    local x = 0
    for i, btn in ipairs(f._lockedBtns) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f._lockedLabel, "BOTTOMLEFT", x, -6)
        x = x + 32
    end
    y = y - 6 - 26

    f._charLabel:ClearAllPoints()
    f._charLabel:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 24)
    y = y - 24 - 14

    f._viewCharBtn:ClearAllPoints()
    f._viewCharBtn:SetPoint("TOPRIGHT", f._contentChild, "TOPRIGHT", -6, y - 24)

    f._talentsText:ClearAllPoints()
    f._talentsText:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 4)
    f._talentsText:SetWidth(w - 160)
    y = y - 4 - (f._talentsText:GetStringHeight() or 14)

    f._gearText:ClearAllPoints()
    f._gearText:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 2)
    f._gearText:SetWidth(w - 160)
    y = y - 2 - (f._gearText:GetStringHeight() or 14)

    f._priLabel:ClearAllPoints()
    f._priLabel:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 14)
    y = y - 14 - 14

    local rows = build and AllPriorities(build) or {}
    if #rows == 0 then
        f._priEmpty:ClearAllPoints()
        f._priEmpty:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 6)
        f._priEmpty:Show()
        y = y - 6 - 14
    else
        f._priEmpty:Hide()
        for i, entry in ipairs(rows) do
            local row = f._priRowPool[i]
            if not row then
                row = CreatePriorityRow(f._contentChild)
                f._priRowPool[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f._contentChild, "TOPLEFT", 0, y - 6 - (i - 1) * PRI_ROW_HEIGHT)
            row:SetPoint("RIGHT", f._contentChild, "RIGHT", 0, 0)
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
        y = y - 6 - #rows * PRI_ROW_HEIGHT
    end
    for i = #rows + 1, #f._priRowPool do
        f._priRowPool[i]:Hide()
    end

    local totalHeight = math.max(1, -y)
    f._contentChild:SetHeight(totalHeight)
    local visible = f._contentScroll:GetHeight() or 0
    local maxScroll = math.max(0, totalHeight - visible)
    f._contentBar:SetMinMaxValues(0, maxScroll)
    f._contentBar:SetValue(0)
    f._contentChild:ClearAllPoints()
    f._contentChild:SetPoint("TOPLEFT", f._contentScroll, "TOPLEFT", 0, 0)
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
    inspectFrame._voteBtn._icon:SetTexture(voted and TEXTURES.voteOn or TEXTURES.voteOff)
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
    inspectFrame._currentBuild = build
    inspectFrame._RefreshInspectContent = function() RefreshInspectContent(inspectFrame, build) end

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

    -- Wishlist / designed slot: locked echoes only. Never apply characterSnapshot
    -- talents/gear (no LearnTalent / auto-equip from foreign snapshots).
    if inspectFrame._wishlistBtn then
        inspectFrame._wishlistBtn:Enable()
        inspectFrame._wishlistBtn:SetScript("OnClick", function()
            ApplyPublicWishlist(build)
        end)
        inspectFrame._wishlistBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Apply wishlist", 1, 1, 1)
            GameTooltip:AddLine("Sets locked echoes as your ProjectEbonhold wishlist (highlight / auto-accept). Does not import the build, upload a server slot, or apply gear/talents/weights.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        inspectFrame._wishlistBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if inspectFrame._serverLoadoutBtn then
        inspectFrame._serverLoadoutBtn:Enable()
        inspectFrame._serverLoadoutBtn:SetScript("OnClick", function()
            UploadPublicServerSlot(build)
        end)
        inspectFrame._serverLoadoutBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Save as server loadout", 1, 1, 1)
            GameTooltip:AddLine("Uploads locked echoes as a designed ProjectEbonhold server slot. Not a verified snapshot — no L1 guarantee / L80 full swap. Weights and character snapshots stay display-only.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        inspectFrame._serverLoadoutBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    inspectFrame:ClearAllPoints()
    inspectFrame:SetAllPoints(viewFrame)
    inspectFrame:Show()
    -- Sized after Show(): GetWidth() on the scroll frame can report a
    -- stale/zero value before the panel has actually laid out, and this
    -- is exactly the measurement RefreshInspectContent depends on.
    RefreshInspectContent(inspectFrame, build)
end

EbonBuilds.PublicBuildsView._ShowInspectForTest = ShowInspect
EbonBuilds.PublicBuildsView._GetInspectFrameForTest = function() return inspectFrame end

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
        card._voteBtn._icon:SetTexture(voted and TEXTURES.voteOn or TEXTURES.voteOff)
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

-- ParseLastModified(str, timeFn) -> epoch seconds | nil. lastModified is
-- always written via date("%Y-%m-%d %H:%M:%S") (see Build.lua) -- parsed
-- back into a real timestamp for age-based sorting instead of relying on
-- the string's lexicographic order, which only happens to work for
-- "Newest" and says nothing about "how many days old". timeFn is
-- injectable (defaults to the real time()) so tests can verify the
-- parsing itself without depending on the client's time(table) --
-- WoW's own time() is trustworthy in-game, but the plain "return 1"
-- test-harness stub used for the rest of the suite ignores its
-- argument entirely and can't stand in for it here.
local function ParseLastModified(str, timeFn)
    if type(str) ~= "string" then return nil end
    local y, mo, d, h, mi, se = str:match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$")
    if not y then return nil end
    local ok, result = pcall(timeFn or time, {
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(se),
    })
    return ok and result or nil
end
EbonBuilds.PublicBuildsView._ParseLastModifiedForTest = ParseLastModified

-- TrendingScore(build, now): votes discounted by age -- a build that
-- picked up its votes recently ranks above an old build sitting on a
-- larger but stale total. +1 in the denominator keeps a same-day build
-- from dividing by (near) zero and drowning out everything else; no
-- votes always scores 0 regardless of age, so an empty new build isn't
-- "trending" just for being new (that's what the Newest sort is for).
local function TrendingScore(build, now, timeFn)
    local votes = (EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(build.id)) or 0
    if votes == 0 then return 0 end
    local modified = ParseLastModified(build.lastModified, timeFn)
    local days = modified and math.max(0, (now - modified) / 86400) or 36500 -- unparseable: treat as ancient, not fresh
    return votes / (days + 1)
end
EbonBuilds.PublicBuildsView._TrendingScoreForTest = TrendingScore

local function MatchesSearch(build, needle)
    if needle == "" then return true end
    local title = string.lower(tostring(build.title or ""))
    local author = string.lower(tostring(build.author or ""))
    return title:find(needle, 1, true) ~= nil or author:find(needle, 1, true) ~= nil
end

-- CompareBuilds(a, b, mode, now, timeFn) -> boolean.
-- Strict weak order for table.sort: return true iff a must come strictly
-- before b. Equal elements must yield false both ways; never return true
-- for both (a,b) and (b,a). The previous `primary = x ~= y and x > y or nil`
-- idiom collapsed "a sorts after b" into nil and then fell through to
-- title/id, which could make both directions return true ("invalid order
-- function for sorting"). Nil holes are also guarded so a sparse list
-- never indexes a nil entry. Numeric keys are coerced with tonumber so a
-- non-number never errors mid-compare. timeFn is optional and forwarded
-- to ParseLastModified / TrendingScore (defaults to real time()).
local function CompareBuilds(a, b, mode, now, timeFn)
    -- Treat nil / non-table holes as sortable sentinels so table.sort never
    -- raises "attempt to index local 'b' (a nil value)" on sparse merges
    -- (Echo Journal bridge + remoteBuilds pairs()).
    if type(a) ~= "table" or type(b) ~= "table" then
        if type(a) ~= "table" and type(b) ~= "table" then return false end
        return type(b) ~= "table"
    end

    mode = mode or sortMode
    now = now or ((time and time()) or 0)

    if mode == "newest" then
        local ma = tonumber(ParseLastModified(a.lastModified, timeFn)) or 0
        local mb = tonumber(ParseLastModified(b.lastModified, timeFn)) or 0
        if ma ~= mb then return ma > mb end
    elseif mode == "itemlevel" then
        local sa = CharacterSummary(a.characterSnapshot)
        local sb = CharacterSummary(b.characterSnapshot)
        local ia = sa and tonumber(sa.avgItemLevel) or nil
        local ib = sb and tonumber(sb.avgItemLevel) or nil
        if ia == nil and ib == nil then
            -- fall through to title/id
        elseif ia == nil or ib == nil then
            -- Builds with no gear data sink to the bottom rather than
            -- sorting as "item level 0", which would put them first.
            return ib == nil
        elseif ia ~= ib then
            return ia > ib
        end
    elseif mode == "trending" then
        local ta = tonumber(TrendingScore(a, now, timeFn)) or 0
        local tb = tonumber(TrendingScore(b, now, timeFn)) or 0
        if ta ~= tb then return ta > tb end
    else -- "votes"
        local va = tonumber((EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(a.id)) or 0) or 0
        local vb = tonumber((EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.Count(b.id)) or 0) or 0
        if va ~= vb then return va > vb end
    end

    local ta, tb = tostring(a.title or ""), tostring(b.title or "")
    if ta ~= tb then return ta < tb end
    return tostring(a.id or "") < tostring(b.id or "")
end
EbonBuilds.PublicBuildsView._CompareBuildsForTest = CompareBuilds

-- Compact accidental holes, then sort. Lua 5.1 table.sort uses #list; a
-- hole mid-sequence can yield nil arguments and "invalid order function"
-- / index-nil crashes even with a careful comparator. Scan integer keys
-- (not just #list) so a sparse array is densified before sorting.
local function SortBuilds(list, mode, now, timeFn)
    if type(list) ~= "table" then return list end
    local maxIndex = 0
    for k in pairs(list) do
        if type(k) == "number" and k >= 1 and k == math.floor(k) and k > maxIndex then
            maxIndex = k
        end
    end
    local write = 1
    for read = 1, maxIndex do
        local v = list[read]
        if type(v) == "table" then
            if write ~= read then list[write] = v end
            write = write + 1
        end
    end
    for i = write, maxIndex do list[i] = nil end
    if write <= 1 then return list end
    table.sort(list, function(a, b)
        return CompareBuilds(a, b, mode, now, timeFn)
    end)
    return list
end
EbonBuilds.PublicBuildsView._SortBuildsForTest = SortBuilds

GetFilteredBuilds = function()
    local all = FetchPublicBuilds()
    local filtered = {}
    for _, build in ipairs(all) do
        if filterClass and build.class ~= filterClass then
        -- PE shared loadouts have no talent-spec; keep them visible under any
        -- Spec filter once the class matches (Echo Journal has no Spec field).
        elseif filterSpec and not build.peSharedLoadout and build.spec ~= filterSpec then
        elseif not MatchesSearch(build, filterText) then
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

    -- Deterministic order (the raw list comes out of pairs()) under every
    -- mode: the primary key decides, ties fall through to title then id
    -- so two builds never visibly swap position between refreshes.
    local now = (time and time()) or 0
    SortBuilds(filtered, sortMode, now)
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
        "Browse peer-synced builds or Echo Journal community loadouts, then import a copy to customize."
    )

    noBuildsLabel = EbonBuilds.Theme.CreateEmptyState(
        f,
        "No public builds found",
        "Try another class or specialization, or reload community data when sync is available."
    )
    noBuildsLabel:Hide()

    -- Source tabs: Peer Sync (EbonBuilds WNT/BLD) vs Echo Journal (PE shared).
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", pageHeader, "BOTTOMLEFT", 0, -7)
    tabBar:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    tabBar:SetHeight(28)

    local function UpdateSourceTabs()
        EbonBuilds.Theme.SetTabSelected(peerTabBtn, listSource == SOURCE_PEER)
        EbonBuilds.Theme.SetTabSelected(journalTabBtn, listSource == SOURCE_JOURNAL)
        if listSource == SOURCE_JOURNAL then
            noBuildsLabel._title:SetText("No Echo Journal loadouts")
            noBuildsLabel._body:SetText("Open ProjectEbonhold Echo Journal community loadouts, or press Reload on this tab.")
        else
            noBuildsLabel._title:SetText("No public builds found")
            noBuildsLabel._body:SetText("Try another class or specialization, or reload community data when sync is available.")
        end
    end

    local function SetListSource(source)
        if source ~= SOURCE_JOURNAL then source = SOURCE_PEER end
        if listSource == source then return end
        listSource = source
        UpdateSourceTabs()
        RefreshView()
    end

    peerTabBtn = EbonBuilds.Theme.CreateTab(tabBar, "Peer Sync")
    peerTabBtn:SetSize(112, 26)
    peerTabBtn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    peerTabBtn:SetScript("OnClick", function() SetListSource(SOURCE_PEER) end)

    journalTabBtn = EbonBuilds.Theme.CreateTab(tabBar, "Echo Journal")
    journalTabBtn:SetSize(130, 26)
    journalTabBtn:SetPoint("LEFT", peerTabBtn, "RIGHT", 6, 0)
    journalTabBtn:SetScript("OnClick", function() SetListSource(SOURCE_JOURNAL) end)

    EbonBuilds.Theme.AttachTooltip(peerTabBtn, "Peer Sync",
        "Public builds shared by nearby EbonBuilds players via peer sync (local public + remoteBuilds).")
    EbonBuilds.Theme.AttachTooltip(journalTabBtn, "Echo Journal",
        "ProjectEbonhold Echo Journal community loadouts (ephemeral; not rebroadcast via peer sync).")
    UpdateSourceTabs()

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
    filterBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
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
        if listSource == SOURCE_JOURNAL then
            if EbonBuilds.SharedLoadoutBridge then
                EbonBuilds.SharedLoadoutBridge.Request(filterClass or "")
                EbonBuilds.SharedLoadoutBridge.RefreshFromService()
            end
            RefreshView()
            return
        end
        if filterClass then
            EbonBuilds.Sync.RequestSync(filterClass)
        else
            EbonBuilds.Sync.RequestSyncAllClasses()
        end
    end)
    refreshBtn:SetScript("OnUpdate", function(self, dt)
        -- Peer Sync uses Sync cooldown; Echo Journal reloads freely.
        if listSource == SOURCE_JOURNAL then
            if self._lastRemaining ~= -1 then
                self._lastRemaining = -1
                refreshBtn:Enable()
                refreshBtn:SetText("Reload")
            end
            return
        end
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

    -- Second row: title/author search (left, wide) and sort dropdown
    -- (right). A second row rather than crowding the class/spec row --
    -- both rows stay comfortably click-able instead of shrinking
    -- everything to fit one line.
    local searchRow = CreateFrame("Frame", nil, f)
    searchRow:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    searchRow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    searchRow:SetHeight(24)

    sortDropdown = EbonBuilds.Theme.CreateDropdown(searchRow, 150, SORT_LABELS[sortMode])
    sortDropdown:SetPoint("RIGHT", searchRow, "RIGHT", 0, 0)
    sortDropdown:SetMenuBuilder(function()
        local items = {}
        for _, key in ipairs({ "votes", "newest", "itemlevel", "trending" }) do
            items[#items + 1] = {
                text = SORT_LABELS[key],
                checked = (sortMode == key),
                func = function()
                    sortMode = key
                    sortDropdown:SetText(SORT_LABELS[key])
                    RefreshView()
                end,
            }
        end
        return items
    end)
    sortDropdown:RefreshMenu()

    local searchWrap = CreateFrame("Frame", nil, searchRow)
    searchWrap:SetPoint("LEFT", searchRow, "LEFT", 0, 0)
    searchWrap:SetPoint("RIGHT", sortDropdown, "LEFT", -8, 0)
    searchWrap:SetHeight(24)
    EbonBuilds.Theme.ApplyInput(searchWrap)
    EbonBuilds.Theme.AddSearchIcon(searchWrap)

    local searchEdit = CreateFrame("EditBox", nil, searchWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(searchEdit, "PublicBuildsView.SearchBox")
    end
    searchEdit:SetPoint("TOPLEFT", searchWrap, "TOPLEFT", 21, -3)
    searchEdit:SetPoint("BOTTOMRIGHT", searchWrap, "BOTTOMRIGHT", -24, 3)
    searchEdit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchEdit:SetTextColor(1, 1, 1, 1)
    searchEdit:SetAutoFocus(false)
    EbonBuilds.Theme.WireEditBox(searchEdit, searchWrap)

    local searchPh = searchWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPh:SetPoint("LEFT", searchEdit, "LEFT", 0, 0)
    searchPh:SetText("Search title or author...")
    searchPh:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local function UpdateSearchPlaceholder()
        if searchEdit:HasFocus() or (searchEdit:GetText() or "") ~= "" then
            searchPh:Hide()
        else
            searchPh:Show()
        end
    end

    local searchClear = CreateFrame("Button", nil, searchWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(searchClear, "PublicBuildsView.ClearSearch")
    end
    searchClear:SetSize(20, 20)
    searchClear:SetPoint("RIGHT", searchWrap, "RIGHT", -2, 0)
    local clearX = searchClear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearX:SetPoint("CENTER")
    clearX:SetText("x")
    clearX:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    searchClear:SetScript("OnClick", function() searchEdit:SetText(""); searchEdit:ClearFocus() end)

    searchEdit:SetScript("OnTextChanged", function(self)
        filterText = string.lower(self:GetText() or "")
        UpdateSearchPlaceholder()
        RefreshView()
    end)
    searchEdit:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
    searchEdit:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
    searchEdit:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    searchBox, searchPlaceholder = searchEdit, searchPh

    -- Scroll area
    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(scrollFrame, "PublicBuildsView.ScrollFrame")
    end
    scrollFrame:SetPoint("TOPLEFT",     searchRow, "BOTTOMLEFT",  0, -4)
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

    EbonBuilds.Debug.RegisterTest("PublicBuildsView.ParseLastModified round-trips the stored date format and rejects garbage", function()
        -- The test harness's time() stub ("return 1", ignoring its
        -- argument) can't stand in for date-table conversion -- inject a
        -- small correct converter instead, so this verifies the parsing
        -- regex and field extraction, which is what this function
        -- actually owns. Precise enough for ordering, not a calendar
        -- library: fixed 30-day months, no leap years -- irrelevant here
        -- since only relative order between two nearby dates is checked.
        local function fakeEpoch(t)
            local days = (t.year - 2000) * 365 + (t.month - 1) * 30 + (t.day - 1)
            return days * 86400 + t.hour * 3600 + t.min * 60 + t.sec
        end
        local epoch = EbonBuilds.PublicBuildsView._ParseLastModifiedForTest("2026-07-21 12:00:00", fakeEpoch)
        if type(epoch) ~= "number" then error("expected a numeric timestamp") end
        local later = EbonBuilds.PublicBuildsView._ParseLastModifiedForTest("2026-07-22 12:00:00", fakeEpoch)
        if not (later > epoch) then error("a later date must parse to a larger timestamp") end
        for _, garbage in ipairs({ nil, "", "not a date", "2026-07-21" }) do
            if EbonBuilds.PublicBuildsView._ParseLastModifiedForTest(garbage, fakeEpoch) ~= nil then
                error("expected nil for: " .. tostring(garbage))
            end
        end
    end)

    EbonBuilds.Debug.RegisterTest("PublicBuildsView.TrendingScore favors recent votes over stale ones, and zero votes always scores zero", function()
        -- TrendingScore delegates date parsing to ParseLastModified, which
        -- the test above already covers; here the injected timeFn just
        -- needs to return a fixed epoch per call so "secondsAgo" is exact
        -- and reproducible, independent of the harness's time() stub.
        local now = 2000000000
        local scoreOf = function(secondsAgo, votes)
            local build = { id = "scoretest-" .. tostring(secondsAgo) .. "-" .. tostring(votes),
                lastModified = "2026-01-01 00:00:00" }
            EbonBuildsDB.buildVotes = {}
            for i = 1, votes do
                EbonBuilds.BuildVotes.MergeVote("Voter" .. i, build.id, true)
            end
            local score = EbonBuilds.PublicBuildsView._TrendingScoreForTest(build, now, function() return now - secondsAgo end)
            EbonBuildsDB.buildVotes = {}
            return score
        end
        local freshScore = scoreOf(3600, 1)          -- 1 vote, 1 hour old
        local staleScore = scoreOf(60 * 86400, 2)     -- 2 votes, 60 days old
        if not (freshScore > staleScore) then
            error(string.format("1 recent vote (%.4f) should outrank 2 stale votes (%.4f)", freshScore, staleScore))
        end
        if scoreOf(3600, 0) ~= 0 then
            error("a build with zero votes must always score zero, regardless of age")
        end
    end)

    EbonBuilds.Debug.RegisterTest("PublicBuildsView source tabs keep Peer Sync and Echo Journal lists separate", function()
        local fetch = EbonBuilds.PublicBuildsView._FetchPublicBuildsForTest
        local setSource = EbonBuilds.PublicBuildsView._SetListSourceForTest
        if type(fetch) ~= "function" or type(setSource) ~= "function" then
            error("expected FetchPublicBuilds test hooks")
        end
        local prevRemote = EbonBuildsDB.remoteBuilds
        EbonBuildsDB.remoteBuilds = {
            peerTab = {
                id = "peer-tab-id", title = "Peer Only", author = "A", class = "MAGE",
                isPublic = true, lockedEchoes = { 1 },
            },
        }
        local prevBridge = EbonBuilds.SharedLoadoutBridge
        EbonBuilds.SharedLoadoutBridge = {
            ListPseudoBuilds = function()
                return {
                    {
                        id = "pe-shared:x:MAGE:Journal Only", title = "Journal Only",
                        author = "J", class = "MAGE", peSharedLoadout = true,
                        lockedEchoes = { 2 },
                    },
                }
            end,
        }
        setSource("peer")
        local peer = fetch()
        setSource("journal")
        local journal = fetch()
        setSource("peer")
        EbonBuildsDB.remoteBuilds = prevRemote
        EbonBuilds.SharedLoadoutBridge = prevBridge
        if #peer ~= 1 or peer[1].title ~= "Peer Only" then
            error("Peer Sync tab must list only ListPublic builds")
        end
        if peer[1].peSharedLoadout then
            error("Peer Sync tab must not include Echo Journal cards")
        end
        if #journal ~= 1 or journal[1].title ~= "Journal Only" then
            error("Echo Journal tab must list only SharedLoadoutBridge builds")
        end
        if not journal[1].peSharedLoadout then
            error("Echo Journal tab must keep peSharedLoadout marker")
        end
    end)

    EbonBuilds.Debug.RegisterTest("PublicBuildsView.CompareBuilds is a total order (no invalid order / nil index)", function()
        local cmp = EbonBuilds.PublicBuildsView._CompareBuildsForTest
        local sort = EbonBuilds.PublicBuildsView._SortBuildsForTest
        if type(cmp) ~= "function" or type(sort) ~= "function" then
            error("expected CompareBuilds/SortBuilds test hooks")
        end

        -- Harness time() ignores its date-table argument; inject a tiny
        -- epoch converter so newest/trending keys actually differ.
        local function fakeEpoch(t)
            local days = (t.year - 2000) * 365 + (t.month - 1) * 30 + (t.day - 1)
            return days * 86400 + t.hour * 3600 + t.min * 60 + t.sec
        end

        -- Antisymmetry helper: never true both ways; equals are false both ways.
        local function assertOrder(a, b, mode, expectABeforeB, label)
            local ab = cmp(a, b, mode, 0, fakeEpoch)
            local ba = cmp(b, a, mode, 0, fakeEpoch)
            if ab and ba then
                error("invalid order (true both ways): " .. label)
            end
            if expectABeforeB == true and not ab then
                error("expected a before b: " .. label)
            end
            if expectABeforeB == false and ab then
                error("expected a not before b: " .. label)
            end
            if expectABeforeB == nil then
                if ab or ba then
                    error("equal pair must be false both ways: " .. label)
                end
            end
        end

        local function assertPairwiseTotalOrder(builds, mode, label)
            for i = 1, #builds do
                for j = 1, #builds do
                    local a, b = builds[i], builds[j]
                    local ab = cmp(a, b, mode, 2000000000, fakeEpoch)
                    local ba = cmp(b, a, mode, 2000000000, fakeEpoch)
                    if ab and ba then
                        error(string.format("invalid order (%s) %s vs %s", label,
                            tostring(a and a.id), tostring(b and b.id)))
                    end
                    if i == j and (ab or ba) then
                        error(string.format("reflexivity broken (%s) id=%s", label, tostring(a and a.id)))
                    end
                end
            end
        end

        -- Titles deliberately conflict with date order: older title "Alpha"
        -- sorts before newer title "Zebra". The broken `x ~= y and x > y or nil`
        -- idiom fell through to title and returned true for BOTH directions.
        local older = { id = "a", title = "Alpha", lastModified = "2026-01-01 00:00:00",
            characterSnapshot = { talents = {}, gear = { [1] = { itemLevel = 100 } } } }
        local newer = { id = "b", title = "Zebra", lastModified = "2026-07-01 00:00:00",
            characterSnapshot = { talents = {}, gear = { [1] = { itemLevel = 250 } } } }
        local sameDateDifferentTitle = { id = "c", title = "Beta", lastModified = "2026-07-01 00:00:00" }

        assertOrder(older, newer, "newest", false, "oldest must not precede newest")
        assertOrder(newer, older, "newest", true, "newest precedes oldest")
        assertOrder(newer, sameDateDifferentTitle, "newest", false, "same date: Zebra after Beta")
        assertOrder(sameDateDifferentTitle, newer, "newest", true, "same date: Beta before Zebra")

        EbonBuildsDB.buildVotes = {}
        if EbonBuilds.BuildVotes and EbonBuilds.BuildVotes.MergeVote then
            EbonBuilds.BuildVotes.MergeVote("V1", newer.id, true)
            EbonBuilds.BuildVotes.MergeVote("V2", newer.id, true)
            EbonBuilds.BuildVotes.MergeVote("V3", older.id, true)
        end
        assertOrder(newer, older, "votes", true, "more votes first")
        assertOrder(newer, older, "itemlevel", true, "higher ilvl first")

        local noGear = { id = "d", title = "NoGear", lastModified = "2026-07-01 00:00:00" }
        assertOrder(newer, noGear, "itemlevel", true, "missing ilvl sinks")
        assertOrder(noGear, newer, "itemlevel", false, "missing ilvl does not float")

        assertOrder(nil, newer, "votes", false, "nil does not precede a build")
        assertOrder(newer, nil, "votes", true, "build precedes nil")
        assertOrder(nil, nil, "votes", nil, "nil equals nil")

        local dense = { older, newer, sameDateDifferentTitle }
        local ok, err = pcall(sort, dense, "newest", 0, fakeEpoch)
        if not ok then error("SortBuilds crashed: " .. tostring(err)) end
        -- Primary: date desc → c+b before a; tie-break: title asc → Beta (c) before Zebra (b).
        if dense[1] ~= sameDateDifferentTitle or dense[2] ~= newer or dense[3] ~= older then
            error(string.format("newest order wrong: %s, %s, %s",
                tostring(dense[1] and dense[1].id),
                tostring(dense[2] and dense[2].id),
                tostring(dense[3] and dense[3].id)))
        end

        -- Comparator itself must tolerate nil arguments (BugSack: attempt to
        -- index local 'b'), even if a caller somehow feeds a sparse list.
        ok, err = pcall(function()
            cmp(nil, newer, "newest", 0, fakeEpoch)
            cmp(newer, nil, "newest", 0, fakeEpoch)
            cmp(nil, nil, "newest", 0, fakeEpoch)
        end)
        if not ok then error("CompareBuilds crashed on nil entry: " .. tostring(err)) end

        assertOrder(newer, newer, "newest", nil, "same build equal")

        -- v3.86 BugSack reproduction: many Alpha(old)/Zebra(new) pairs make
        -- Lua 5.1 raise "invalid order function for sorting" under the old
        -- `x ~= y and x > y or nil` idiom. Fixed comparator must sort cleanly.
        local conflicted = {}
        for i = 1, 40 do
            conflicted[#conflicted + 1] = {
                id = "old-" .. i, title = "Alpha",
                lastModified = "2026-01-01 00:00:00",
            }
            conflicted[#conflicted + 1] = {
                id = "new-" .. i, title = "Zebra",
                lastModified = string.format("2026-07-%02d 00:00:00", 1 + (i % 28)),
            }
        end
        ok, err = pcall(sort, conflicted, "newest", 0, fakeEpoch)
        if not ok then
            error("conflicted Alpha/Zebra newest sort failed (v3.86 repro): " .. tostring(err))
        end
        for i = 1, #conflicted - 1 do
            if cmp(conflicted[i + 1], conflicted[i], "newest", 0, fakeEpoch) then
                error("conflicted list not sorted by newest after SortBuilds")
            end
        end

        -- Sparse list: densify + nil-safe compare must not raise.
        local sparse = { older, nil, newer, nil, sameDateDifferentTitle, noGear }
        ok, err = pcall(sort, sparse, "votes", 2000000000, fakeEpoch)
        if not ok then error("sparse SortBuilds crashed: " .. tostring(err)) end
        if #sparse ~= 4 then
            error("sparse SortBuilds should compact to 4 builds, got " .. tostring(#sparse))
        end

        local sample = { older, newer, sameDateDifferentTitle, noGear }
        for _, modeName in ipairs({ "votes", "newest", "itemlevel", "trending" }) do
            assertPairwiseTotalOrder(sample, modeName, modeName)
            local copy = { older, newer, sameDateDifferentTitle, noGear }
            ok, err = pcall(sort, copy, modeName, 2000000000, fakeEpoch)
            if not ok then
                error("SortBuilds crashed in mode " .. modeName .. ": " .. tostring(err))
            end
        end

        EbonBuildsDB.buildVotes = {}
    end)

    EbonBuilds.Debug.RegisterTest("PublicBuildsView.Inspect handles a very long Intent without breaking the layout", function()
        -- Regression test for a real report: a build with a long,
        -- multi-paragraph Intent (gear/talent/leveling notes crammed into
        -- one field) pushed every section below it -- Locked Echoes,
        -- Character, Weighted Priorities -- past the panel's own fixed
        -- bounds, unclipped, rendering straight through onto whatever was
        -- behind the panel. Fixed by moving everything below the header
        -- into one scrollable region (RefreshInspectContent) instead of
        -- fixed-offset anchoring off Intent's actual (unbounded) height.
        local container = CreateFrame("Frame")
        container:SetWidth(600)
        container:SetHeight(500)
        EbonBuilds.PublicBuildsView.Mount(container)

        local longIntent = {}
        for i = 1, 60 do
            longIntent[i] = "Paragraph " .. i .. ": a long line of author notes about gear, talents, and leveling routes."
        end
        local build = {
            id = "inspect-overflow-test", title = "Overflow Test Build", class = "NONEXISTENT_CLASS_TOKEN", spec = 1,
            author = "Test Author", lastModified = "2026-07-21 12:00:00",
            comments = table.concat(longIntent, "\n"),
            lockedEchoes = { 1, 2, 3 },
        }
        EbonBuilds.PublicBuildsView._ShowInspectForTest(build)

        local f = EbonBuilds.PublicBuildsView._GetInspectFrameForTest()
        if not f then error("expected a built inspect frame") end
        local childHeight = f._contentChild:GetHeight()
        if type(childHeight) ~= "number" or childHeight <= 0 then
            error("expected a positive content height, got " .. tostring(childHeight))
        end
        local minVal, maxVal = f._contentBar:GetMinMaxValues()
        if minVal ~= 0 or type(maxVal) ~= "number" or maxVal < 0 then
            error(string.format("expected a well-ordered scrollbar range, got min=%s max=%s", tostring(minVal), tostring(maxVal)))
        end
    end)
end
