-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Missing + Logbook). Registered as "buildOverview" view. Shows build metadata,
-- locked echoes, automation toggle, runtime statistics, and missing echoes.

EbonBuilds.BuildOverview = {}

local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.0,  0.96, 0.41 },
    PRIEST      = { 1.0,  1.0,  1.0  },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.0,  0.44, 0.87 },
    MAGE        = { 0.41, 0.8,  0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.0,  0.49, 0.04 },
}

local QUALITY_BORDER_COLORS = EbonBuilds.Quality.RGB

local QUALITY_LABELS = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

local viewFrame
local tab1, tab2, tab3, tab4
local contentArea
local state = { build = nil }

------------------------------------------------------------------------
-- Delete confirmation dialog
------------------------------------------------------------------------

StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"] = {
    text = "",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        local build = state.build
        if not build or not build.id then return end
        local id = build.id
        local deletedTitle = build.title or "Untitled"
        EbonBuilds.Build.Delete(id)
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        local builds = EbonBuilds.Build.List()
        if #builds > 0 then
            EbonBuilds.Build.SetActive(builds[1].id)
            EbonBuilds.ViewRouter.Show("buildOverview", { build = builds[1] })
        else
            EbonBuilds.ViewRouter.Show("welcome")
        end
        StaticPopupDialogs["EBONBUILDS_UNDO_DELETE"].text =
            "Deleted \"" .. deletedTitle .. "\"."
        StaticPopup_Show("EBONBUILDS_UNDO_DELETE")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONBUILDS_UNDO_DELETE"] = {
    text = "",
    button1 = "Undo",
    button2 = "OK",
    OnAccept = function()
        local restored = EbonBuilds.Build.RestoreLastDeleted()
        if not restored then return end
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        EbonBuilds.Build.SetActive(restored.id)
        EbonBuilds.ViewRouter.Show("buildOverview", { build = restored })
        EbonBuilds.Toast.Show("Restored \"" .. (restored.title or "Untitled") .. "\"")
    end,
    timeout = 10,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

------------------------------------------------------------------------
-- Overview tab
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Missing Echoes computation
------------------------------------------------------------------------

local CLASS_MASK = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8,
    PRIEST = 16, DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, DRUID = 1024,
}

-- Strip common prefixes/suffixes so spell-name comparison is robust against
-- cosmetic variants like "Tome of Brittle Forging" vs "Brittle Forging".
local PREFIXES = { "tome of ", "codex of ", "scroll of ", "manual of ", "grimoire of ", "libram of ", "tablet of " }
-- Plain-text suffixes (compared verbatim via sub(), NOT Lua patterns).
local QUALITY_SUFFIXES = { " - common", " - uncommon", " - rare", " - epic", " - legendary" }

local function NormalizeEchoName(name)
    if not name then return nil end
    local n = strlower(name)
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

-- Exported for unit testing
EbonBuilds.BuildOverview._NormalizeEchoName = NormalizeEchoName

-- Owned-echo detection, shared by this file's Missing tab and
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
function EbonBuilds.BuildOverview.GetOwnedEchoSets(assumeNoneOwned)
    local svc = ProjectEbonhold and ProjectEbonhold.PerkService
    local ownedLower, ownedGroups = {}, {}

    if svc and svc.GetDiscoveredEchoes then
        local discovered = svc.GetDiscoveredEchoes() or {}
        for spellId in pairs(discovered) do
            local data = ProjectEbonhold.PerkDatabase[spellId]
            if data then
                local norm = NormalizeEchoName(GetSpellInfo(spellId))
                if norm then ownedLower[norm] = true end
                if data.groupId then ownedGroups[data.groupId] = true end
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
            return nil, nil
        end
        for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
            if spellbookIds[data.requiredSpell] or spellbookIds[spellId + 100000] then
                local norm = NormalizeEchoName(GetSpellInfo(spellId))
                if norm then ownedLower[norm] = true end
                if data.groupId then ownedGroups[data.groupId] = true end
            end
        end
    end

    -- Echoes granted without ever needing a tome (not in the discovery
    -- list either way) still need this pass, on both paths above.
    if svc and svc.GetGrantedPerks then
        for name in pairs(svc.GetGrantedPerks() or {}) do
            local norm = NormalizeEchoName(name)
            if norm then ownedLower[norm] = true end
        end
    end

    return ownedLower, ownedGroups
end

local function ComputeMissingEchoes(build, assumeNoneOwned, includeOwned)
    if not build or not build.class then return nil end

    local classMask = CLASS_MASK[build.class] or 0

    local ok, ownedLower, ownedGroups = pcall(EbonBuilds.BuildOverview.GetOwnedEchoSets, assumeNoneOwned)
    if not ok then
        if EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("BuildOverview.ComputeMissingEchoes", tostring(ownedLower))
        end
        return nil -- surfaces as "still loading" -- RefreshMissing already retries this
    end
    if not ownedLower then return nil end

    -- Build locked echo name set for priority sorting
    local lockedLower = {}
    if build.lockedEchoes then
        for _, spellId in ipairs(build.lockedEchoes) do
            if spellId then
                local name = GetSpellInfo(spellId)
                if name then lockedLower[NormalizeEchoName(name)] = true end
            end
        end
    end

    -- Group by spell name, keep highest quality per name. Owned status is
    -- tracked per entry now (not filtered out here) so the caller can opt
    -- into seeing owned echoes too, not just missing ones.
    -- Note: deliberately NOT filtered by current player level -- this tab
    -- tracks collection progress (tomes not yet learned), and on Ebonhold
    -- the character resets to level 1 every run, which would empty the list.
    local byName = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local spellName = GetSpellInfo(spellId)
        if spellName then
            local key = NormalizeEchoName(spellName)
            if classMask == 0 or bit.band(data.classMask or 0, classMask) ~= 0 then
                local isOwned = ownedLower[key] or (data.groupId and ownedGroups[data.groupId])
                local existing = byName[key]
                if not existing or (data.quality or 0) > (existing.quality or 0) then
                    byName[key] = { spellId = spellId, data = data, displayName = spellName, owned = isOwned }
                end
            end
        end
    end

    -- Collect missing echoes (only those with known drop source, exclude
    -- banned) plus, when requested, owned ones too (score/drop-source
    -- don't apply to something you already have, so those are omitted).
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    local banList = settings.echoBanList or {}
    local weights = build.echoWeights or {}
    local missing = {}
    for key, entry in pairs(byName) do
        if entry.owned then
            if includeOwned then
                missing[#missing + 1] = {
                    spellId = entry.spellId,
                    name = entry.displayName,
                    quality = entry.data.quality or 0,
                    isLocked = lockedLower[key] or false,
                    owned = true,
                }
            end
        else
            local source = ProjectEbonhold.PerkDropSources and ProjectEbonhold.PerkDropSources[entry.spellId]
            if not source and entry.data.groupId and ProjectEbonhold.PerkDropSourceByGroup then
                source = ProjectEbonhold.PerkDropSourceByGroup[entry.data.groupId]
            end
            local needsTome = entry.data.requiredSpell and entry.data.requiredSpell > 0
            if not banList[entry.spellId] and needsTome then
                -- Build scoring entry
                local scoringEntry = {
                    spellId = entry.spellId,
                    name = entry.displayName,
                    quality = entry.data.quality or 0,
                    families = entry.data.families,
                    classMask = entry.data.classMask,
                }
                local weight = weights[entry.displayName] or 0
                local score = EbonBuilds.Scoring.Score(scoringEntry, weight, settings)
                missing[#missing + 1] = {
                    spellId = entry.spellId,
                    name = entry.displayName,
                    quality = entry.data.quality or 0,
                    dropSource = source or "Unknown",
                    isLocked = lockedLower[key] or false,
                    score = score,
                    owned = false,
                }
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

-- Exported for unit testing
EbonBuilds.BuildOverview._ComputeMissingEchoes = ComputeMissingEchoes

------------------------------------------------------------------------
-- Overview tab content

local function BuildOverviewTab(parent)
    local outer = CreateFrame("Frame", nil, parent)
    outer:SetAllPoints(parent)

    -- Class icon + Build name header
    local classIcon = outer:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(32)
    classIcon:SetHeight(32)
    classIcon:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -10)
    outer._classIcon = classIcon

    local nameLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -6)
    nameLabel:SetPoint("RIGHT",   outer,     "RIGHT",     -10, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetJustifyV("TOP")
    -- Fixed height (enough for 2 wrapped lines) so a long community build
    -- title can never overlap the meta line below it -- previously metaLabel
    -- sat at a position fixed relative to classIcon, which didn't account
    -- for nameLabel needing more than one line.
    nameLabel:SetHeight(32)
    outer._nameLabel = nameLabel

    -- Author + last modified
    local metaLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    metaLabel:SetPoint("RIGHT",  outer,     "RIGHT",      -10, 0)
    metaLabel:SetJustifyH("LEFT")
    metaLabel:SetJustifyV("TOP")
    metaLabel:SetHeight(26)
    outer._metaLabel = metaLabel

    -- Public / Validated status (button frame for tooltip support)
    local statusFrame = CreateFrame("Button", nil, outer)
    statusFrame:SetPoint("TOPLEFT",     metaLabel, "BOTTOMLEFT", 0, -12)
    statusFrame:SetPoint("RIGHT",       outer,     "RIGHT",      -10, 0)
    statusFrame:SetHeight(16)
    local statusLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetAllPoints(statusFrame)
    statusLabel:SetJustifyH("LEFT")
    statusFrame:SetScript("OnEnter", function(self)
        local build = state.build
        if not build or not build.isPublic then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Public Build", 1, 0.82, 0, 1)
        GameTooltip:AddLine("Public builds require validation to appear in the browser.", 0.8, 0.8, 0.8, 1)
        GameTooltip:AddLine("Level a character from 1 to 80 using this build to validate it.", 0.6, 0.6, 0.6, 1)
        GameTooltip:Show()
    end)
    statusFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    outer._statusLabel = statusLabel

    -- Locked echoes
    local lockedHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockedHeader:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -14)
    lockedHeader:SetText("Locked Echoes:")
    outer._lockedHeader = lockedHeader

    local lockedButtons = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(outer, 36)
        btn:SetPoint("TOPLEFT", lockedHeader, "BOTTOMLEFT", (i - 1) * 42, -6)
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._border = border
        btn:SetScript("OnEnter", function(self)
            if not self._spellId then return end
            local name = GetSpellInfo(self._spellId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if name then GameTooltip:AddLine(name, 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lockedButtons[i] = btn
    end
    outer._lockedButtons = lockedButtons

    -- Automation toggle + Edit button
    local autoToggle = EbonBuilds.Theme.CreateButton(outer)
    autoToggle:SetWidth(140)
    autoToggle:SetHeight(22)
    autoToggle:SetPoint("TOPLEFT", lockedButtons[1], "BOTTOMLEFT", 0, -22)
    local function RefreshAutoToggle(self, build)
        local on = build and build.automationEnabled
        self:SetText(on and "Automation: ON" or "Automation: OFF")
        -- Color-code live state so the one control that changes game
        -- behavior stands out from the row of plain navigation buttons.
        if on then
            EbonBuilds.Theme.SetButtonAccent(self, "good")
        else
            EbonBuilds.Theme.ClearButtonAccent(self)
        end
    end
    autoToggle:SetText("Automation: ON")
    autoToggle:SetScript("OnClick", function(self)
        local build = state.build
        if not build then return end
        build.automationEnabled = not build.automationEnabled
        RefreshAutoToggle(self, build)
    end)
    outer._autoToggle = autoToggle
    outer._refreshAutoToggle = RefreshAutoToggle

    local editBtn = EbonBuilds.Theme.CreateButton(outer)
    editBtn:SetWidth(120)
    editBtn:SetHeight(22)
    -- Slightly wider gap than between the action buttons themselves: reads
    -- as "status control | action group" instead of one undifferentiated row.
    editBtn:SetPoint("LEFT", autoToggle, "RIGHT", 16, 0)
    editBtn:SetText("Edit Build")
    editBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = state.build })
        end
    end)

    local linkBtn = EbonBuilds.Theme.CreateButton(outer)
    linkBtn:SetWidth(80)
    linkBtn:SetHeight(22)
    linkBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    linkBtn:SetText("Chat Link")
    linkBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ChatLink.InsertLink(state.build)
        end
    end)
    linkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Share in chat", 1, 1, 1)
        GameTooltip:AddLine("Inserts a build link into your chat box. Other EbonBuilds users can click it to fetch this build (public builds only).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local dupBtn = EbonBuilds.Theme.CreateButton(outer)
    dupBtn:SetWidth(90)
    dupBtn:SetHeight(22)
    dupBtn:SetPoint("LEFT", linkBtn, "RIGHT", 8, 0)
    dupBtn:SetText("Duplicate")
    dupBtn:SetScript("OnClick", function()
        local build = state.build
        if not build or not build.id then return end
        local copy = EbonBuilds.Build.Duplicate(build.id)
        if not copy then return end
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        EbonBuilds.Toast.Show("Created \"" .. copy.title .. "\"")
        EbonBuilds.Build.SetActive(copy.id)
        EbonBuilds.ViewRouter.Show("buildOverview", { build = copy })
    end)

    -- Apply this build's locked echoes to the server's native Active Echo
    -- Loadout (ProjectEbonhold.PerkService.SetActiveEchoLoadout) -- the
    -- server highlights matching picks in its own echo-selection screen
    -- while a loadout is active. Second row: the first row (auto/edit/
    -- link/duplicate) is already close to the panel width.
    local applyBtn = EbonBuilds.Theme.CreateButton(outer)
    applyBtn:SetWidth(150)
    applyBtn:SetHeight(20)
    applyBtn:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -8)
    applyBtn:SetText("Apply to Character")
    applyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Apply to Character", 1, 1, 1)
        GameTooltip:AddLine("Sets this build's locked echoes as your server-tracked active loadout. The game's own echo-pick screen highlights matching choices while it's active.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    applyBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        local svc = ProjectEbonhold and ProjectEbonhold.PerkService
        if not (svc and svc.SetActiveEchoLoadout) then
            EbonBuilds.Toast.Show("Server doesn't support Active Echo Loadout")
            return
        end
        local echoes = {}
        for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
            local spellId = build.lockedEchoes and build.lockedEchoes[i]
            if spellId then
                local data = ProjectEbonhold.PerkDatabase[spellId]
                echoes[#echoes + 1] = { spellId = spellId, quality = data and data.quality or 0, stacks = 1 }
            end
        end
        if #echoes == 0 then
            EbonBuilds.Toast.Show("No locked echoes to apply")
            return
        end
        local ok = svc.SetActiveEchoLoadout({ name = build.title, class = build.class, echoes = echoes })
        if ok then
            EbonBuilds.Toast.Show("Applied \"" .. (build.title or "?") .. "\" to character")
        else
            EbonBuilds.Toast.Show("Failed to apply build")
        end
    end)
    outer._applyBtn = applyBtn

    -- Description header
    local descHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descHeader:SetPoint("TOPLEFT", applyBtn, "BOTTOMLEFT", 0, -14)
    descHeader:SetText("Description:")
    outer._descHeader = descHeader

    -- Description scroll frame (owns scrollbar)
    local descScroll = CreateFrame("ScrollFrame", nil, outer)
    descScroll:SetPoint("TOPLEFT",     descHeader, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", outer,      "BOTTOMRIGHT", -22, 28)

    local descChild = CreateFrame("Frame", nil, descScroll)
    descChild:SetWidth(416)
    descChild:SetHeight(1)
    descScroll:SetScrollChild(descChild)

    local descBar = CreateFrame("Slider", nil, descScroll, "UIPanelScrollBarTemplate")
    descBar:SetPoint("TOPLEFT",    descScroll, "TOPRIGHT",    -2, -4)
    descBar:SetPoint("BOTTOMLEFT", descScroll, "BOTTOMRIGHT", -2,  4)
    descBar:SetValueStep(20)
    descBar:SetScript("OnValueChanged", function(self, value)
        descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, value)
    end)

    -- SMF inside scroll child -- renders text with hyperlink tooltip support
    local descSmf = CreateFrame("ScrollingMessageFrame", nil, descChild)
    descSmf:SetPoint("TOPLEFT", descChild, "TOPLEFT", 0, -2)
    descSmf:SetWidth(416)
    descSmf:SetFontObject("GameFontNormalSmall")
    descSmf:SetJustifyH("LEFT")
    descSmf:SetFading(false)
    descSmf:SetInsertMode("TOP")
    descSmf:SetMaxLines(500)
    descSmf:SetHyperlinksEnabled(true)
    descSmf:EnableMouse(true)
    descSmf:EnableMouseWheel(false)
    descSmf:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    descSmf:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)
    descSmf:SetScript("OnMouseWheel", function(self, delta)
        local v = descBar:GetValue()
        local mn, mx = descBar:GetMinMaxValues()
        descBar:SetValue(math.max(mn, math.min(mx, v - delta * 20)))
    end)

    -- Hidden FontString with same width -- used only to measure wrapped text height
    local descMeasure = descChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descMeasure:SetWidth(416)
    descMeasure:Hide()

    descScroll:EnableMouseWheel(true)
    descScroll:SetScript("OnMouseWheel", function(self, delta)
        local v = descBar:GetValue()
        local mn, mx = descBar:GetMinMaxValues()
        descBar:SetValue(math.max(mn, math.min(mx, v - delta * 20)))
    end)

    outer._descSmf = descSmf
    outer._descMeasure = descMeasure
    outer._descScroll = descScroll
    outer._descChild  = descChild
    outer._descBar    = descBar

    -- Delete button (bottom-left, below description, low misclick probability).
    -- Red accent marks it as destructive rather than just another action
    -- that happens to sit apart from the rest.
    local deleteBtn = EbonBuilds.Theme.CreateButton(outer, "danger")
    deleteBtn:SetSize(64, 20)
    deleteBtn:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 10, 4)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        local name = build.title or "Untitled"
        StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"].text = "Delete build \"" .. name .. "\"?"
        StaticPopup_Show("EBONBUILDS_DELETE_BUILD")
    end)
    outer._deleteBtn = deleteBtn

    return outer, descSmf, descMeasure, descScroll, descChild, descBar
end

------------------------------------------------------------------------
-- Stats tab
------------------------------------------------------------------------

local STAT_ROWS = {
    { key = "echoesSeen",    label = "Echoes Seen" },
    { key = "runsCompleted", label = "Runs Completed" },
    { key = "runsReset",     label = "Runs Reset" },
    { key = "picks",         label = "Picks" },
    { key = "rerollsUsed",   label = "Rerolls Used" },
    { key = "banishesUsed",  label = "Banishes Used" },
    { key = "freezesUsed",   label = "Freezes Used" },
}

local function BuildStatsTab(parent)
    local y = -10

    -- Left column: Build Statistics header + rows
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    header:SetText("Build Statistics")

    y = y - 30
    local valueLabels = {}
    for i, row in ipairs(STAT_ROWS) do
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        lbl:SetText(row.label .. ":")
        lbl:SetWidth(160)
        lbl:SetJustifyH("LEFT")

        local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        val:SetText("0")
        val:SetWidth(60)
        val:SetJustifyH("RIGHT")
        valueLabels[row.key] = val

        y = y - 22
    end

    -- Most picked / Most banned (left column)
    y = y - 8
    local mostPickedLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostPickedLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    mostPickedLbl:SetText("Most Picked:")
    mostPickedLbl:SetWidth(100)
    mostPickedLbl:SetJustifyH("LEFT")
    local mostPickedVal = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mostPickedVal:SetPoint("LEFT", mostPickedLbl, "RIGHT", 4, 0)
    mostPickedVal:SetText("-")
    mostPickedVal:SetWidth(150)
    mostPickedVal:SetJustifyH("LEFT")
    valueLabels.mostPicked = mostPickedVal

    y = y - 18
    local mostBannedLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostBannedLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    mostBannedLbl:SetText("Most Banned:")
    mostBannedLbl:SetWidth(100)
    mostBannedLbl:SetJustifyH("LEFT")
    local mostBannedVal = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mostBannedVal:SetPoint("LEFT", mostBannedLbl, "RIGHT", 4, 0)
    mostBannedVal:SetText("-")
    mostBannedVal:SetWidth(150)
    mostBannedVal:SetJustifyH("LEFT")
    valueLabels.mostBanned = mostBannedVal

    -- Right column: Quality Distribution
    local qy = -10
    local qHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 270, qy)
    qHeader:SetText("Quality Distribution:")

    qy = qy - 26
    local qualityLabels = {}
    for q = 0, 4 do
        local qlbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qlbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 274, qy)
        qlbl:SetText(QUALITY_LABELS[q] .. ":")
        qlbl:SetWidth(90)
        qlbl:SetJustifyH("LEFT")

        local qval = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qval:SetPoint("LEFT", qlbl, "RIGHT", 4, 0)
        qval:SetText("0 (0%)")
        qval:SetWidth(80)
        qval:SetJustifyH("RIGHT")
        qualityLabels[q] = qval

        qy = qy - 18
    end

    return valueLabels, qualityLabels
end

------------------------------------------------------------------------
-- Missing tab
------------------------------------------------------------------------

local missingState = { missingOnly = false }
local missingToggleBtn, missingCountLabel, missingRefreshBtn
local RefreshMissing

local function BuildMissingTab(parent)
    missingCountLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingCountLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -4)

    missingRefreshBtn = EbonBuilds.Theme.CreateButton(parent)
    missingRefreshBtn:SetSize(70, 20)
    missingRefreshBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -2)
    missingRefreshBtn:SetText("Refresh")
    missingRefreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Refresh", 1, 1, 1)
        GameTooltip:AddLine("Re-reads your spellbook for learned echoes right now, " ..
            "instead of waiting for the automatic retry.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    missingRefreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    missingRefreshBtn:SetScript("OnClick", function()
        RefreshMissing()
    end)

    missingToggleBtn = EbonBuilds.Theme.CreateButton(parent)
    missingToggleBtn:SetSize(130, 20)
    missingToggleBtn:SetPoint("RIGHT", missingRefreshBtn, "LEFT", -8, 0)
    missingToggleBtn:SetText("Show: All")
    missingToggleBtn:SetScript("OnClick", function(self)
        missingState.missingOnly = not missingState.missingOnly
        self:SetText(missingState.missingOnly and "Show: Missing only" or "Show: All")
        RefreshMissing()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     10, -28)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 8)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(460)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2,  4)
    bar:SetValueStep(16)

    bar:SetScript("OnValueChanged", function(self, value)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = bar:GetValue()
        local mn, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(mn, math.min(mx, v - delta * 16)))
    end)

    return scroll, child, bar
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    EbonBuilds.SessionHistory.Show(parent)
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local overviewOuter
local overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar
local statsValueLabels, statsQualityLabels
local missingScroll, missingChild, missingBar
local missingRows = {}
local function RefreshOverview()
    local build = state.build
    if not build then return end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    SetClassIcon(overviewOuter._classIcon, build.class)
    overviewOuter._nameLabel:SetText(build.title or "Untitled")
    overviewOuter._nameLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specName = specs and specs[build.spec or 1] and specs[build.spec or 1].name or ""
    overviewOuter._metaLabel:SetText(string.format("by %s | %s | %s",
        build.author or "Unknown",
        specName,
        build.lastModified or ""))

    -- Public / Validated status
    local publicText = build.isPublic and "|cff19ff19Public|r" or "|cff888888Private|r"
    local validatedText
    if build.validated then
        validatedText = " |cff19ff19(Validated)|r"
    elseif build.isPublic then
        validatedText = " |cffff4444(Not Validated)|r"
    else
        validatedText = ""
    end
    overviewOuter._statusLabel:SetText(publicText .. validatedText)

    overviewOuter._refreshAutoToggle(overviewOuter._autoToggle, build)

    local desc = build.comments or ""
    overviewDescSmf:Clear()
    overviewDescSmf:AddMessage(desc, 0.8, 0.8, 0.8, 1.0)
    overviewDescMeasure:SetText(desc)

    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = overviewOuter._lockedButtons[i]
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()
            local data = ProjectEbonhold.PerkDatabase[spellId]
            local quality = data and data.quality or 0
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._border:SetTexture(bc[1], bc[2], bc[3])
            btn._border:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._spellId = nil
            btn._border:Hide()
            btn:Show()
        end
    end

    -- Adjust description scroll range
    local textHeight = overviewDescMeasure:GetStringHeight() or 0
    overviewDescSmf:SetHeight(math.max(textHeight + 4, 14))
    overviewDescChild:SetHeight(math.max(textHeight + 6, overviewDescScroll:GetHeight()))
    overviewDescBar:SetMinMaxValues(0, math.max(0, overviewDescChild:GetHeight() - overviewDescScroll:GetHeight()))
end

local QUALITY_COLORS = EbonBuilds.Quality.RGB

-- Returns "Name (Nx)" for the highest-count entry of a name->count map,
-- or "-" if empty. next() alone would return an arbitrary entry.
local function TopEntry(counts)
    local bestName, bestCount = nil, 0
    for name, count in pairs(counts or {}) do
        if type(count) == "number" and count > bestCount then
            bestName, bestCount = name, count
        end
    end
    if not bestName then return "-" end
    return string.format("%s (%dx)", tostring(bestName), bestCount)
end

local function RefreshStats()
    local build = state.build
    if not build or not statsValueLabels then return end
    local st = build.stats or {}
    for _, row in ipairs(STAT_ROWS) do
        if statsValueLabels[row.key] then
            statsValueLabels[row.key]:SetText(tostring(st[row.key] or 0))
        end
    end
    -- Percentages are relative to picks with recorded quality data --
    -- qualityPicks tracking started later than the lifetime `picks`
    -- counter, so older builds have picks the distribution never saw.
    local qualityTotal = 0
    for q = 0, 4 do
        qualityTotal = qualityTotal + ((st.qualityPicks or {})[q] or 0)
    end
    for q = 0, 4 do
        if statsQualityLabels[q] then
            local count = (st.qualityPicks or {})[q] or 0
            local pct = qualityTotal > 0 and math.floor(count / qualityTotal * 100 + 0.5) or 0
            statsQualityLabels[q]:SetText(string.format("%d (%d%%)", count, pct))
        end
    end
    statsValueLabels.mostPicked:SetText(TopEntry(st.mostPicked))
    statsValueLabels.mostBanned:SetText(TopEntry(st.mostBanned))
end

local missingRetryFrame
local missingRetryElapsed = 0
local MISSING_RETRY_INTERVAL = 1.5
local MISSING_RETRY_TIMEOUT  = 15

local function StopMissingRetry()
    if missingRetryFrame then missingRetryFrame:Hide() end
    missingRetryElapsed = 0
end

RefreshMissing = function(assumeNoneOwned)
    local build = state.build
    if not build or not missingChild then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    local includeOwned = not missingState.missingOnly
    local missing = ComputeMissingEchoes(build, assumeNoneOwned, includeOwned)
    if missing == nil then
        missingChild.loadingLabel = missingChild.loadingLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingChild.loadingLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 4, -2)
        missingChild.loadingLabel:SetText("Requesting data...")
        missingChild.loadingLabel:Show()
        missingChild:SetHeight(20)
        -- Auto-retry instead of requiring the player to flip tabs away and
        -- back: poll until the spellbook is ready, or give up after
        -- MISSING_RETRY_TIMEOUT and show the list anyway (see the
        -- assumeNoneOwned comment in ComputeMissingEchoes for why this
        -- can otherwise hang forever on a fresh character).
        if not missingRetryFrame then
            missingRetryFrame = CreateFrame("Frame")
            missingRetryFrame:SetScript("OnUpdate", function(self, dt)
                missingRetryElapsed = missingRetryElapsed + dt
                if missingRetryElapsed < MISSING_RETRY_INTERVAL then return end
                missingRetryElapsed = 0
                self._totalWaited = (self._totalWaited or 0) + MISSING_RETRY_INTERVAL
                local giveUp = self._totalWaited >= MISSING_RETRY_TIMEOUT
                if giveUp and EbonBuilds.DebugLog then
                    EbonBuilds.DebugLog.Add("Missing tab: Echoes spellbook tab never appeared after " ..
                        MISSING_RETRY_TIMEOUT .. "s, showing full list (likely 0 echoes learned yet)")
                end
                RefreshMissing(giveUp)
            end)
        end
        missingRetryFrame._totalWaited = missingRetryFrame._totalWaited or 0
        missingRetryFrame:Show()
        return
    end
    StopMissingRetry()
    if missingRetryFrame then missingRetryFrame._totalWaited = 0 end
    if missingChild.loadingLabel then
        missingChild.loadingLabel:Hide()
    end
    local currY = 0
    local ownedCount, missingCount = 0, 0
    for _, entry in ipairs(missing) do
        if entry.owned then ownedCount = ownedCount + 1 else missingCount = missingCount + 1 end
        local rowIdx = #missingRows + 1
        while #missingRows < rowIdx do
            local n = #missingRows + 1
            local btn = CreateFrame("Button", nil, missingChild)
            btn:SetPoint("LEFT", missingChild, "LEFT", 4, 0)
            btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnEnter", function(self)
                if not self._spellId then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                local spellName = GetSpellInfo(self._spellId)
                if spellName then
                    GameTooltip:AddLine(spellName, 1, 0.82, 0)
                end
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(self._spellId, 500, 1)
                    if desc and desc ~= "" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                end
                GameTooltip:AddLine(self._owned and "|cff1eff00Learned|r" or "|cffff4444Not learned|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(24)
            icon:SetHeight(24)
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon = icon
            -- Owned/missing status dot, same convention as the Affixes tab:
            -- green = learned, red = not learned yet.
            local statusDot = btn:CreateTexture(nil, "OVERLAY")
            statusDot:SetSize(8, 8)
            statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
            statusDot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            btn._statusDot = statusDot
            -- Name column
            local labelName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 0)
            labelName:SetWidth(160)
            labelName:SetJustifyH("LEFT")
            btn._labelName = labelName
            -- Drop Source column (or "Learned" for owned rows)
            local labelSource = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelSource:SetPoint("TOPLEFT", labelName, "TOPRIGHT", 4, 0)
            labelSource:SetWidth(200)
            labelSource:SetJustifyH("LEFT")
            btn._labelSource = labelSource
            -- Score column (blank for owned rows)
            local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            labelScore:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -2)
            labelScore:SetWidth(54)
            labelScore:SetJustifyH("RIGHT")
            btn._labelScore = labelScore
            missingRows[n] = btn
        end
        local btn = missingRows[rowIdx]
        btn:ClearAllPoints()
        btn._spellId = entry.spellId
        btn._owned = entry.owned
        btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        if entry.owned then
            btn._statusDot:SetVertexColor(0.12, 0.85, 0.12, 1)
        else
            btn._statusDot:SetVertexColor(0.85, 0.2, 0.2, 1)
        end
        local cc = QUALITY_COLORS[entry.quality] or QUALITY_COLORS[0]
        btn._labelName:SetText(entry.name)
        btn._labelName:SetTextColor(cc[1], cc[2], cc[3], entry.owned and 0.7 or 1)
        if entry.owned then
            btn._labelSource:SetText("Learned")
            btn._labelSource:SetTextColor(0.12, 0.85, 0.12, 1)
            btn._labelScore:SetText("")
        else
            local cleanSource = (entry.dropSource or ""):gsub("^Can be found on ", "")
            btn._labelSource:SetText(cleanSource)
            btn._labelSource:SetTextColor(0.6, 0.6, 0.6, 1)
            btn._labelScore:SetText(string.format("%.0f", entry.score))
        end
        local srcH = btn._labelSource:GetStringHeight() or 16
        local rowH = math.max(26, srcH + 4)
        btn:SetHeight(rowH)
        btn:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -currY)
        btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
        btn:Show()
        currY = currY + rowH + 2
    end
    missingChild:SetHeight(math.max(1, currY))
    missingBar:SetMinMaxValues(0, math.max(0, missingChild:GetHeight() - missingScroll:GetHeight()))
    if missingCountLabel then
        if includeOwned then
            missingCountLabel:SetText(string.format("%d learned, %d missing", ownedCount, missingCount))
        else
            missingCountLabel:SetText(string.format("%d missing", missingCount))
        end
    end
end
------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchMissing, switchLogbook

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildOverview", UIParent)

    -- Bordered container
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -24)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  10)
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(unpack(EbonBuilds.Theme.PANEL_BG))
    box:SetBackdropBorderColor(unpack(EbonBuilds.Theme.BORDER_DIM))

    -- Inner content area
    contentArea = CreateFrame("Frame", nil, box)
    contentArea:SetPoint("TOPLEFT",     box, "TOPLEFT",     6, -6)
    contentArea:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6,  6)

    -- Build Overview tab content
    overviewOuter, overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar = BuildOverviewTab(contentArea)

    -- Build Stats tab content (hidden by default)
    local statsParent = CreateFrame("Frame", nil, contentArea)
    statsParent:SetAllPoints(contentArea)
    statsParent:Hide()
    statsValueLabels, statsQualityLabels = BuildStatsTab(statsParent)

    -- Missing Echoes tab content (hidden by default)
    local missingParent = CreateFrame("Frame", nil, contentArea)
    missingParent:SetAllPoints(contentArea)
    missingParent:Hide()
    missingScroll, missingChild, missingBar = BuildMissingTab(missingParent)

    -- Build Logbook tab content (hidden by default)
    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    -- Hide all tab content
    local function HideAllContent()
        overviewOuter:Hide()
        statsParent:Hide()
        missingParent:Hide()
        logbookParent:Hide()
    end

    -- Tab switching functions (defined after content so refs are valid)
    switchOverview = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter:Show()
        overviewOuter._deleteBtn:Show()
        PanelTemplates_SetTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        RefreshOverview()
    end

    switchStats = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        statsParent:Show()
        PanelTemplates_SetTab(f, 2)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        RefreshStats()
    end

    switchMissing = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        missingParent:Show()
        PanelTemplates_SetTab(f, 3)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 4)
        RefreshMissing()
    end

    switchLogbook = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        logbookParent:Show()
        PanelTemplates_SetTab(f, 4)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        EbonBuilds.SessionHistory.Show(logbookParent)
    end

    tab1 = CreateFrame("Button", "EbonBuildsBuildOverviewTab1", f, "OptionsFrameTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Overview")
    tab1:SetPoint("TOPLEFT", f, "TOPLEFT", 10, 0)
    PanelTemplates_TabResize(tab1, 0)
    tab1:SetScript("OnClick", function() if switchOverview then switchOverview() end end)

    tab2 = CreateFrame("Button", "EbonBuildsBuildOverviewTab2", f, "OptionsFrameTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Stats")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab2, 0)
    tab2:SetScript("OnClick", function() if switchStats then switchStats() end end)

    tab3 = CreateFrame("Button", "EbonBuildsBuildOverviewTab3", f, "OptionsFrameTabButtonTemplate")
    tab3:SetID(3)
    tab3:SetText("Missing")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab3, 0)
    tab3:SetScript("OnClick", function() if switchMissing then switchMissing() end end)

    tab4 = CreateFrame("Button", "EbonBuildsBuildOverviewTab4", f, "OptionsFrameTabButtonTemplate")
    tab4:SetID(4)
    tab4:SetText("Logbook")
    tab4:SetPoint("LEFT", tab3, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab4, 0)
    tab4:SetScript("OnClick", function() if switchLogbook then switchLogbook() end end)

    PanelTemplates_SetNumTabs(f, 4)
    PanelTemplates_SetTab(f, 1)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    state.build = context.build
    if switchOverview then switchOverview() end
    viewFrame:Show()
end

function view.Hide()
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.BuildOverview.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildOverview", view)
end
