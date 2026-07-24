local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/CharacterView.lua
-- Responsive Character workspace: overview, one focused game-style talent
-- tree, and a paper-doll equipment view. The stored build snapshot is always
-- the display source; live APIs are consulted only when adopting a replacement.

EbonBuilds.CharacterView = {}

local V = EbonBuilds.CharacterView

-- Pure data layer, split out to modules/build/CharacterViewData.lua (issue #19).
-- Local aliases keep every existing call site and test hook unchanged.
local Data = EbonBuilds.CharacterViewData
local TalentPointsText = Data.TalentPointsText
local HasCompleteTalentCatalog = Data.HasCompleteTalentCatalog
local BuildGearSummary = Data.BuildGearSummary
local ResolveViewportWidth = Data.ResolveViewportWidth
local TalentCanvasWidth = Data.TalentCanvasWidth
local TalentGridMetrics = Data.TalentGridMetrics
local TalentStatusText = Data.TalentStatusText
local GlyphPresentation = Data.GlyphPresentation
local TalentDisplayRank = Data.TalentDisplayRank
local SavedItemAffix = Data.SavedItemAffix
local BuildGearAffixColumns = Data.BuildGearAffixColumns
local BuildRecognizedStats = Data.BuildRecognizedStats
local STAT_NAMES = Data.STAT_NAMES

local Theme
local viewFrame, pageHost, actionBar, snapshotStatus, adoptBtn, itemInfoToken
local navButtons, pages = {}, {}
local activeSubview = "overview"
local mountedContext
local layouting = false

local displayed = { talents = {}, gear = {}, glyphs = {} }
local displayedSnapshot
local comparison
local dirty = { talents = true, gear = true, glyphs = true }
local pendingGearRetries = 0

local Refresh, Layout, ShowSubview

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 },
    [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
    [6] = { 0.90, 0.80, 0.50 }, [7] = { 0.90, 0.80, 0.50 },
}

local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function SetClassIcon(texture, classToken)
    local coords = CLASS_ICON_TCOORDS and classToken and CLASS_ICON_TCOORDS[classToken]
    if coords then
        texture:SetTexture(CLASS_TEXTURE)
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function SpecKeyForContext()
    local class = EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass
        and EbonBuilds.BuildForm.GetEditingClass()
    local spec = EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingSpec
        and EbonBuilds.BuildForm.GetEditingSpec()
    return class and EbonBuilds.GearScore.SpecKey(class, spec) or nil
end

local function StoredSnapshot()
    if mountedContext and mountedContext.readOnly then return mountedContext.snapshot end
    return EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingCharacterSnapshot
        and EbonBuilds.BuildForm.GetEditingCharacterSnapshot() or nil
end

local function CurrentClassToken()
    local token
    if UnitClass then
        local _
        _, token = UnitClass("player")
    end
    return token
end

local function EditingClassToken()
    if mountedContext and mountedContext.readOnly then return mountedContext.snapshotClass end
    return EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass
        and EbonBuilds.BuildForm.GetEditingClass() or nil
end

local function ClassLabel(token)
    return (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token])
        or token or "unknown class"
end

local function CanAdoptCurrentCharacter()
    if mountedContext and mountedContext.readOnly then return false, "READ_ONLY" end
    return EbonBuilds.CharacterSnapshot.CanApplyToClass(
        EditingClassToken(), CurrentClassToken())
end

local function SetStatusText(label, text, kind)
    if not label then return end
    label:SetText(text or "")
    local color = kind == "success" and Theme.SUCCESS
        or kind == "warning" and Theme.WARNING
        or kind == "danger" and Theme.DANGER
        or Theme.TEXT_MUTED
    label:SetTextColor(unpack(color))
end

V._HasCompleteTalentCatalogForTests = HasCompleteTalentCatalog
V._BuildGearSummaryForTests = BuildGearSummary
V._LayoutForTests = Data.LayoutBreakpoints
V._ResolveViewportWidthForTests = ResolveViewportWidth

-- Character subpages are hidden when another subview is active. A hidden
-- frame can briefly report zero or a stale width when it is shown again,
-- which previously made the same window alternate between desktop and
-- compact layouts. Prefer the mounted viewport and its visible parent; the
-- page width is only a last-resort fallback.
local function CharacterViewportWidth(page)
    local viewWidth = viewFrame and viewFrame:GetWidth() or 0
    local parentWidth = 0
    if viewFrame and viewFrame.GetParent then
        local parent = viewFrame:GetParent()
        parentWidth = parent and parent:GetWidth() or 0
    end
    return ResolveViewportWidth(viewWidth, parentWidth, page and page:GetWidth() or 0)
end

------------------------------------------------------------------------
-- Stored display model and bounded item-resolution scheduling
------------------------------------------------------------------------

local function ScheduleGearRetry(unresolved)
    if unresolved <= 0 then pendingGearRetries = 0; return end
    local delays = { 0.25, 0.75, 1.5, 3, 5, 8 }
    if pendingGearRetries >= #delays or not EbonBuilds.Scheduler then return end
    pendingGearRetries = pendingGearRetries + 1
    EbonBuilds.Scheduler.After("character.gear.resolve", delays[pendingGearRetries], function()
        dirty.gear = true
        if viewFrame and viewFrame:IsShown() then Refresh() end
    end, EbonBuilds.Scheduler.INTERACTIVE, true)
end

local function RefreshModels()
    local stored = StoredSnapshot()
    local snapshotChanged = stored ~= displayedSnapshot
    displayedSnapshot = stored
    local presentation = stored
    if EbonBuilds.TalentCatalog and EbonBuilds.TalentCatalog.ResolveSnapshot then
        presentation = EbonBuilds.TalentCatalog.ResolveSnapshot(stored)
    end
    displayed.classToken = presentation and presentation.classToken or EditingClassToken()
    displayed.characterName = presentation and presentation.characterName or nil
    displayed.capturedAt = presentation and presentation.capturedAt or nil
    displayed.talentGroup = presentation and presentation.talentGroup or nil
    displayed.talents = presentation and presentation.talents or {}
    displayed.glyphs = presentation and presentation.glyphs or {}
    displayed._catalogRecovered = presentation and presentation._catalogRecovered == true
    dirty.talents, dirty.glyphs = false, false

    if dirty.gear or snapshotChanged then
        local previousGear = displayed.gear
        local nextGear = EbonBuilds.CharacterSnapshot.ResolveGear(stored and stored.gear or {})
        -- Item-cache events can be delivered in several stages on 3.3.5a.
        -- Once an icon has resolved, keep it for this displayed snapshot even
        -- if a later transient GetItemInfo call returns incomplete metadata.
        for slotId, item in pairs(nextGear) do
            local previous = previousGear and previousGear[slotId]
            if not item.icon and previous and previous.link == item.link then
                item.icon = previous.icon
            end
        end
        displayed.gear = nextGear
        dirty.gear = false
        local summary = BuildGearSummary(displayed.gear)
        ScheduleGearRetry(summary.pending)
    end
    comparison = nil
end

local function MarkDirty(kind)
    if kind == "all" then
        dirty.talents, dirty.gear, dirty.glyphs = true, true, true
        pendingGearRetries = 0
    elseif dirty[kind] ~= nil then
        dirty[kind] = true
        if kind == "gear" then pendingGearRetries = 0 end
    end
    if not (viewFrame and viewFrame:IsShown()) then return end
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.After("character.view.refresh", 0.05, function()
            if viewFrame and viewFrame:IsShown() then Refresh() end
        end, EbonBuilds.Scheduler.INTERACTIVE, true)
    else
        Refresh()
    end
end

------------------------------------------------------------------------
-- Overview page
------------------------------------------------------------------------

local O = {}

local function CreateOverviewPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    pages.overview = page

    O.identity = CreateFrame("Frame", nil, page)
    Theme.ApplyCard(O.identity)
    O.classIcon = O.identity:CreateTexture(nil, "ARTWORK")
    O.classIcon:SetSize(54, 54)
    O.classIcon:SetPoint("TOPLEFT", O.identity, "TOPLEFT", 14, -14)
    O.name = O.identity:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    O.name:SetPoint("TOPLEFT", O.classIcon, "TOPRIGHT", 12, -2)
    O.name:SetPoint("RIGHT", O.identity, "RIGHT", -12, 0)
    O.name:SetJustifyH("LEFT")
    O.talentPoints = O.identity:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    O.talentPoints:SetPoint("TOPLEFT", O.name, "BOTTOMLEFT", 0, -8)
    O.talentState = O.identity:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    O.talentState:SetPoint("TOPLEFT", O.talentPoints, "BOTTOMLEFT", 0, -6)
    O.talentState:SetPoint("RIGHT", O.identity, "RIGHT", -12, 0)
    O.talentState:SetJustifyH("LEFT")

    O.talents = CreateFrame("Frame", nil, page)
    Theme.ApplyCard(O.talents)
    O.talentTitle = O.talents:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    O.talentTitle:SetPoint("TOPLEFT", O.talents, "TOPLEFT", 14, -14)
    O.talentTitle:SetText("Talent snapshot")
    O.talentTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    O.talentBody = O.talents:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    O.talentBody:SetPoint("TOPLEFT", O.talentTitle, "BOTTOMLEFT", 0, -10)
    O.talentBody:SetPoint("RIGHT", O.talents, "RIGHT", -14, 0)
    O.talentBody:SetJustifyH("LEFT")
    O.talentBody:SetJustifyV("TOP")
    O.talentBody:SetSpacing(4)
    O.talentBtn = Theme.CreateButton(O.talents, "gold")
    O.talentBtn:SetSize(112, 24)
    O.talentBtn:SetPoint("BOTTOMLEFT", O.talents, "BOTTOMLEFT", 14, 12)
    O.talentBtn:SetText("Open Talents")
    O.talentBtn:SetScript("OnClick", function() ShowSubview("talents") end)

    O.gear = CreateFrame("Frame", nil, page)
    Theme.ApplyCard(O.gear)
    O.gearTitle = O.gear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    O.gearTitle:SetPoint("TOPLEFT", O.gear, "TOPLEFT", 14, -14)
    O.gearTitle:SetText("Equipped gear")
    O.gearTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    O.gearBody = O.gear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    O.gearBody:SetPoint("TOPLEFT", O.gearTitle, "BOTTOMLEFT", 0, -10)
    O.gearBody:SetPoint("RIGHT", O.gear, "RIGHT", -14, 0)
    O.gearBody:SetJustifyH("LEFT")
    O.gearBody:SetJustifyV("TOP")
    O.gearBody:SetSpacing(4)
    O.gearBtn = Theme.CreateButton(O.gear, "gold")
    O.gearBtn:SetSize(104, 24)
    O.gearBtn:SetPoint("BOTTOMLEFT", O.gear, "BOTTOMLEFT", 14, 12)
    O.gearBtn:SetText("Open Gear")
    O.gearBtn:SetScript("OnClick", function() ShowSubview("gear") end)

    O.glyphs = CreateFrame("Frame", nil, page)
    Theme.ApplyCard(O.glyphs)
    O.glyphTitle = O.glyphs:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    O.glyphTitle:SetPoint("TOPLEFT", O.glyphs, "TOPLEFT", 14, -12)
    O.glyphTitle:SetText("Glyphs")
    O.glyphTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    O.glyphBody = O.glyphs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    O.glyphBody:SetPoint("LEFT", O.glyphTitle, "RIGHT", 16, 0)
    O.glyphBody:SetPoint("RIGHT", O.glyphs, "RIGHT", -14, 0)
    O.glyphBody:SetJustifyH("LEFT")
    return page
end

local function LayoutOverview()
    local width = CharacterViewportWidth(pages.overview)
    O.identity:ClearAllPoints()
    O.identity:SetPoint("TOPLEFT", pages.overview, "TOPLEFT", 4, -4)
    O.identity:SetPoint("TOPRIGHT", pages.overview, "TOPRIGHT", -4, -4)
    O.identity:SetHeight(88)

    O.talents:ClearAllPoints()
    O.gear:ClearAllPoints()
    O.glyphs:ClearAllPoints()
    if width >= 620 then
        O.talents:SetPoint("TOPLEFT", O.identity, "BOTTOMLEFT", 0, -8)
        O.talents:SetPoint("BOTTOMRIGHT", pages.overview, "BOTTOM", -4, 50)
        O.gear:SetPoint("TOPLEFT", pages.overview, "TOP", 4, -100)
        O.gear:SetPoint("BOTTOMRIGHT", pages.overview, "BOTTOMRIGHT", -4, 50)
    else
        O.talents:SetPoint("TOPLEFT", O.identity, "BOTTOMLEFT", 0, -8)
        O.talents:SetPoint("TOPRIGHT", O.identity, "BOTTOMRIGHT", 0, -8)
        O.talents:SetHeight(118)
        O.gear:SetPoint("TOPLEFT", O.talents, "BOTTOMLEFT", 0, -8)
        O.gear:SetPoint("TOPRIGHT", O.talents, "BOTTOMRIGHT", 0, -8)
        O.gear:SetPoint("BOTTOM", pages.overview, "BOTTOM", 0, 50)
    end
    O.glyphs:SetPoint("BOTTOMLEFT", pages.overview, "BOTTOMLEFT", 4, 4)
    O.glyphs:SetPoint("BOTTOMRIGHT", pages.overview, "BOTTOMRIGHT", -4, 4)
    O.glyphs:SetHeight(38)
end

local function RefreshOverview()
    local stored = StoredSnapshot()
    SetClassIcon(O.classIcon, displayed.classToken)
    if stored then
        O.name:SetText((displayed.characterName or "Saved character snapshot")
            .. " · " .. ClassLabel(displayed.classToken))
        O.talentPoints:SetText("Saved talent distribution: " .. TalentPointsText(displayed))
        SetStatusText(O.talentState, "Captured " .. (displayed.capturedAt or "at an unknown time"), "success")
    else
        O.name:SetText("No character snapshot · " .. ClassLabel(EditingClassToken()))
        O.talentPoints:SetText("Saved talent distribution: none")
        SetStatusText(O.talentState, "Adopt a matching character snapshot to populate this build.", "warning")
    end

    local catalogNote = displayed._catalogRecovered
        and "\nLegacy talent visuals restored from the built-in 3.3.5a catalog."
        or stored and not HasCompleteTalentCatalog(displayed)
        and "\nLegacy snapshot: only originally stored talent nodes are available." or ""
    O.talentBody:SetText("Snapshot distribution: "
        .. (stored and TalentPointsText(displayed) or "not adopted") .. catalogNote)
    local gear = BuildGearSummary(displayed.gear)
    O.gearBody:SetText(string.format(
        "%d of %d snapshotted slots equipped\n%d resolved · %d pending · %d empty\nScores use the active build's spec model.",
        gear.equipped, gear.total, gear.resolved, gear.pending, gear.empty))

    local major, minor = {}, {}
    for _, glyph in ipairs(displayed.glyphs or {}) do
        if glyph.spellId then
            local targetList = glyph.kind == "major" and major or minor
            targetList[#targetList + 1] = glyph.name or ("Glyph " .. glyph.spellId)
        end
    end
    O.glyphBody:SetText(string.format("Major %d/3 · Minor %d/3", #major, #minor))
end

------------------------------------------------------------------------
-- Talent page
------------------------------------------------------------------------

local TUI = {
    mode = "snapshot",
    presentation = "tree",
    activeTree = 1,
    selectedKey = nil,
    modeButtons = {},
    treeButtons = {},
    presentationButtons = {},
    nodePool = {},
    listPool = {},
    backgrounds = {},
    connectionPool = {},
    arrowPool = {},
}

V._TalentCanvasWidthForTests = TalentCanvasWidth
V._TalentGridMetricsForTests = TalentGridMetrics

local function CurrentTalentCanvasWidth()
    return TalentCanvasWidth(CharacterViewportWidth(pages.talents))
end

local function ActiveTree()
    return displayed.talents and displayed.talents[TUI.activeTree]
end

local function TalentComparison(tab, talent)
    local key = EbonBuilds.CharacterSnapshot.TalentKey(tab, talent)
    return comparison and comparison.byKey and comparison.byKey[key] or nil
end

local function FindSelectedTalent()
    local tree = ActiveTree()
    if not tree then return nil end
    local first = tree.talents and tree.talents[1]
    for _, talent in ipairs(tree.talents or {}) do
        if EbonBuilds.CharacterSnapshot.TalentKey(TUI.activeTree, talent) == TUI.selectedKey then
            return talent
        end
    end
    if first then TUI.selectedKey = EbonBuilds.CharacterSnapshot.TalentKey(TUI.activeTree, first) end
    return first
end

local function TalentSpellId(tab, talent)
    return Data.TalentSpellId(displayed.classToken, tab, talent)
end

V._TalentSpellIdForTests = TalentSpellId

local function ShowTalentTooltip(button)
    local talent = button and button._talent
    if not talent then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local usedNative = false
    if displayed.classToken == CurrentClassToken() and GameTooltip.SetTalent and talent.index then
        usedNative = pcall(GameTooltip.SetTalent, GameTooltip, button._tab, talent.index)
    end
    if not usedNative and talent.link and GameTooltip.SetHyperlink then
        usedNative = pcall(GameTooltip.SetHyperlink, GameTooltip, talent.link)
    end
    local spellId = TalentSpellId(button._tab, talent)
    if not usedNative and spellId and GameTooltip.SetHyperlink then
        usedNative = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(spellId))
    end
    if not usedNative then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(talent.name or "Talent", 1, 0.82, 0)
        GameTooltip:AddLine("The native description is unavailable for this legacy talent record.",
            0.72, 0.72, 0.76, true)
    end
    GameTooltip:AddLine(" ")
    local state = button._comparison
    GameTooltip:AddLine(string.format("Snapshot: %d/%d", tonumber(talent.rank) or 0,
        tonumber(talent.maxRank) or 0), 0.82, 0.82, 0.86)
    if state then
        GameTooltip:AddLine(string.format("Saved snapshot: %d/%d", state.snapshot or 0,
            state.maxRank or talent.maxRank or 0), 0.82, 0.82, 0.86)
        GameTooltip:AddLine(TalentStatusText(state), 1, 0.82, 0)
    end
    GameTooltip:Show()
end

local function GlyphPresentationForDisplay()
    return GlyphPresentation(displayed.glyphs)
end

V._GlyphPresentationForTests = GlyphPresentationForDisplay

local function ApplyTalentNodeVisual(button)
    local talent, state = button._talent, button._comparison
    if not talent then return end
    local displayRank = TalentDisplayRank(talent, state)
    local maxRank = tonumber(talent.maxRank) or state and state.maxRank or 0
    button._rank:SetText(string.format("%d/%d", displayRank, maxRank))
    button._marker:SetText("")

    local border, background = Theme.BORDER_DIM, { 0.055, 0.055, 0.075, 0.98 }
    local iconStrength = displayRank > 0 and 1 or 0.34
    if TUI.mode == "difference" and state then
        if state.state == "exact" then
            border, background = Theme.SUCCESS, { 0.05, 0.14, 0.08, 0.98 }
        elseif state.state == "missing" then
            border, background = Theme.WARNING, { 0.18, 0.10, 0.035, 0.98 }
            button._marker:SetText("!")
        elseif state.state == "additional" then
            border, background = { 0.25, 0.65, 1, 1 }, { 0.035, 0.09, 0.16, 0.98 }
            button._marker:SetText("+")
        elseif state.state == "unknown" then
            border = Theme.DANGER
            button._marker:SetText("?")
        end
    elseif displayRank > 0 then
        border, background = Theme.SUCCESS, { 0.05, 0.14, 0.08, 0.98 }
    end
    if talent.available == false and displayRank <= 0 then
        iconStrength = 0.20
        button._marker:SetText("x")
    end
    if button._key == TUI.selectedKey then border = Theme.ACCENT_GOLD end
    button:SetBackdropColor(unpack(background))
    button:SetBackdropBorderColor(unpack(border))
    button._icon:SetVertexColor(iconStrength, iconStrength, iconStrength, displayRank > 0 and 1 or 0.78)
    button._marker:SetTextColor(unpack(border))
end

local function RefreshTalentInspector()
    local talent = FindSelectedTalent()
    if not talent then
        TUI.inspectorTitle:SetText("No talent selected")
        TUI.inspectorRank:SetText("")
        TUI.inspectorStatus:SetText("No talent data is available for this tree.")
        TUI.inspectorBody:SetText("")
        return
    end
    local state = TalentComparison(TUI.activeTree, talent)
    TUI.inspectorIcon:SetTexture(talent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    TUI.inspectorTitle:SetText(talent.name or "Talent")
    TUI.inspectorRank:SetText(string.format("Snapshot %d/%d%s", tonumber(talent.rank) or 0,
        tonumber(talent.maxRank) or 0, state and string.format(" · Saved %d/%d",
            state.snapshot or 0, state.maxRank or talent.maxRank or 0) or ""))
    SetStatusText(TUI.inspectorStatus, TalentStatusText(state),
        state and state.state == "exact" and "success"
        or state and (state.state == "missing" or state.state == "unknown") and "warning" or nil)
    TUI.inspectorBody:SetText(string.format(
        "Tree position: tier %d, column %d\n%s\n\nHover the talent icon\nfor the full game description.",
        tonumber(talent.tier) or 0, tonumber(talent.column) or 0,
        talent.available == false and "Prerequisites are not currently met." or "Talent is currently available."))
end

local function RefreshGlyphSummary()
    local title, body = GlyphPresentationForDisplay()
    TUI.glyphTitle:SetText(title)
    TUI.glyphBody:SetText(body)
end

local function CreateTalentNode(parent)
    local button = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(button, "CharacterView.TalentNode")
    end
    button:SetSize(34, 34)
    Theme.ApplyCard(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button._icon = icon
    local rank = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    rank:SetTextColor(1, 1, 1)
    rank:SetShadowColor(0, 0, 0, 1)
    rank:SetShadowOffset(1, -1)
    button._rank = rank
    local marker = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    marker:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
    marker:SetShadowColor(0, 0, 0, 1)
    marker:SetShadowOffset(1, -1)
    button._marker = marker
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.ACCENT_GOLD))
        ShowTalentTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        ApplyTalentNodeVisual(self)
    end)
    button:SetScript("OnClick", function(self)
        TUI.selectedKey = self._key
        for _, node in ipairs(TUI.nodePool) do if node:IsShown() then ApplyTalentNodeVisual(node) end end
        RefreshTalentInspector()
    end)
    return button
end

local function AcquireTalentNode(index)
    local button = TUI.nodePool[index]
    if not button then
        button = CreateTalentNode(TUI.canvasChild)
        TUI.nodePool[index] = button
    end
    button:Show()
    return button
end

local function ConfigureTreeBackground(tree, width, height, backgroundLeft, backgroundWidth)
    local suffixes = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" }
    backgroundLeft = tonumber(backgroundLeft) or 0
    backgroundWidth = math.max(1, tonumber(backgroundWidth) or width)
    for index = 1, 4 do
        local texture = TUI.backgrounds[index]
        if not texture then
            texture = TUI.canvasChild:CreateTexture(nil, "BACKGROUND")
            TUI.backgrounds[index] = texture
        end
        texture:ClearAllPoints()
        texture:SetSize(math.ceil(backgroundWidth / 2), math.ceil(height / 2))
        local x = backgroundLeft + (index % 2 == 0 and math.floor(backgroundWidth / 2) or 0)
        local y = index > 2 and -math.floor(height / 2) or 0
        texture:SetPoint("TOPLEFT", TUI.canvasChild, "TOPLEFT", x, y)
        if tree and tree.background and tree.background ~= "" then
            texture:SetTexture("Interface\\TalentFrame\\" .. tree.background .. "-" .. suffixes[index])
            texture:SetVertexColor(0.72, 0.72, 0.78, 0.20)
            texture:Show()
        else
            texture:Hide()
        end
    end
end

local function HideTalentConnections()
    for _, texture in ipairs(TUI.connectionPool) do texture:Hide() end
    for _, arrow in ipairs(TUI.arrowPool) do arrow:Hide() end
end

local function AcquireConnection(index)
    local texture = TUI.connectionPool[index]
    if not texture then
        texture = TUI.canvasChild:CreateTexture(nil, "BORDER")
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        TUI.connectionPool[index] = texture
    end
    texture:Show()
    return texture
end

local function DrawConnectionSegment(index, x1, y1, x2, y2, color)
    if x1 == x2 and y1 == y2 then return index end
    local texture = AcquireConnection(index)
    texture:ClearAllPoints()
    texture:SetVertexColor(color[1], color[2], color[3], color[4])
    if math.abs(x2 - x1) >= math.abs(y2 - y1) then
        local left = math.min(x1, x2)
        texture:SetPoint("TOPLEFT", TUI.canvasChild, "TOPLEFT", left, -math.floor(y1 - 1))
        texture:SetSize(math.max(2, math.abs(x2 - x1)), 2)
    else
        local top = math.min(y1, y2)
        texture:SetPoint("TOPLEFT", TUI.canvasChild, "TOPLEFT", math.floor(x1 - 1), -top)
        texture:SetSize(2, math.max(2, math.abs(y2 - y1)))
    end
    return index + 1
end


local function DrawTalentPrerequisites(tree, metrics)
    HideTalentConnections()
    local segmentIndex, arrowIndex = 1, 1
    for _, talent in ipairs(tree and tree.talents or {}) do
        local targetTier = math.max(1, tonumber(talent.tier) or 1)
        local targetColumn = math.max(1, math.min(4, tonumber(talent.column) or 1))
        local targetX = metrics.gridLeft + (targetColumn - 1) * metrics.columnStep
            + metrics.nodeSize / 2
        local targetY = metrics.top + (targetTier - 1) * metrics.tierStep
            + metrics.nodeSize / 2
        for _, prerequisite in ipairs(talent.prerequisites or {}) do
            local sourceTier = math.max(1, tonumber(prerequisite.tier) or 1)
            local sourceColumn = math.max(1, math.min(4, tonumber(prerequisite.column) or 1))
            local sourceX = metrics.gridLeft + (sourceColumn - 1) * metrics.columnStep
                + metrics.nodeSize / 2
            local sourceY = metrics.top + (sourceTier - 1) * metrics.tierStep
                + metrics.nodeSize / 2
            local met = prerequisite.met or (tonumber(talent.rank) or 0) > 0
            local color = met and { 1.0, 0.82, 0.0, 0.88 } or { 0.34, 0.35, 0.39, 0.78 }
            local arrowText, arrowX, arrowY

            if targetTier > sourceTier then
                local startY = sourceY + metrics.nodeSize / 2
                local endY = targetY - metrics.nodeSize / 2 - 2
                if sourceColumn == targetColumn then
                    segmentIndex = DrawConnectionSegment(segmentIndex, sourceX, startY, targetX, endY, color)
                else
                    local middleY = math.floor(startY + math.max(3, (endY - startY) / 2))
                    segmentIndex = DrawConnectionSegment(segmentIndex, sourceX, startY, sourceX, middleY, color)
                    segmentIndex = DrawConnectionSegment(segmentIndex, sourceX, middleY, targetX, middleY, color)
                    segmentIndex = DrawConnectionSegment(segmentIndex, targetX, middleY, targetX, endY, color)
                end
                arrowText, arrowX, arrowY = "v", targetX, endY + 1
            else
                local direction = targetX >= sourceX and 1 or -1
                local startX = sourceX + direction * metrics.nodeSize / 2
                local endX = targetX - direction * (metrics.nodeSize / 2 + 2)
                segmentIndex = DrawConnectionSegment(segmentIndex, startX, sourceY, endX, targetY, color)
                arrowText = direction > 0 and ">" or "<"
                arrowX, arrowY = endX + direction, targetY
            end

            local arrow = TUI.arrowPool[arrowIndex]
            if not arrow then
                arrow = TUI.canvasChild:CreateFontString(nil, "BORDER", "GameFontNormalSmall")
                arrow:SetShadowColor(0, 0, 0, 1)
                arrow:SetShadowOffset(1, -1)
                TUI.arrowPool[arrowIndex] = arrow
            end
            arrow:ClearAllPoints()
            arrow:SetPoint("CENTER", TUI.canvasChild, "TOPLEFT", arrowX, -arrowY)
            arrow:SetText(arrowText)
            arrow:SetTextColor(color[1], color[2], color[3], color[4])
            arrow:Show()
            arrowIndex = arrowIndex + 1
        end
    end
end

local function RenderTalentTree()
    local tree = ActiveTree()
    for _, button in ipairs(TUI.nodePool) do button:Hide() end
    if not tree then
        HideTalentConnections()
        ConfigureTreeBackground(nil, 400, 440, 73, 254)
        TUI.canvasChild:SetHeight(math.max(420, TUI.canvasScroll:GetHeight() or 0))
        TUI.canvasBar:SetMinMaxValues(0, 0)
        return
    end

    local width = CurrentTalentCanvasWidth()
    local viewportHeight = math.max(240, TUI.canvasScroll:GetHeight() or 0)
    local maxTier = 1
    for _, talent in ipairs(tree.talents or {}) do
        maxTier = math.max(maxTier, tonumber(talent.tier) or 1)
    end
    local metrics = TalentGridMetrics(width, viewportHeight, maxTier)
    local height = metrics.contentHeight
    TUI.canvasChild:SetWidth(width)
    TUI.canvasChild:SetHeight(height)
    if TUI.canvasScroll.SetHorizontalScroll then TUI.canvasScroll:SetHorizontalScroll(0) end
    ConfigureTreeBackground(tree, width, height, metrics.backgroundLeft, metrics.backgroundWidth)
    DrawTalentPrerequisites(tree, metrics)
    for index, talent in ipairs(tree.talents or {}) do
        local button = AcquireTalentNode(index)
        button._talent = talent
        button._tab = TUI.activeTree
        button._key = EbonBuilds.CharacterSnapshot.TalentKey(TUI.activeTree, talent)
        button._comparison = TalentComparison(TUI.activeTree, talent)
        button._icon:SetTexture(talent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button:ClearAllPoints()
        local column = math.max(1, math.min(4, tonumber(talent.column) or 1))
        button:SetPoint("TOPLEFT", TUI.canvasChild, "TOPLEFT",
            metrics.gridLeft + (column - 1) * metrics.columnStep,
            -(metrics.top + ((tonumber(talent.tier) or 1) - 1) * metrics.tierStep))
        ApplyTalentNodeVisual(button)
    end
    local maximum = math.max(0, height - (TUI.canvasScroll:GetHeight() or 0))
    TUI.canvasBar:SetMinMaxValues(0, maximum)
    if TUI.canvasBar:GetValue() > maximum then TUI.canvasBar:SetValue(maximum) end
end

local function CreateTalentListRow(parent)
    local row = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "CharacterView.Row")
    end
    row:SetHeight(36)
    Theme.ApplyCard(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row._icon = icon
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 6)
    name:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    name:SetJustifyH("LEFT")
    row._name = name
    local state = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    state:SetPoint("LEFT", icon, "RIGHT", 8, -8)
    state:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    state:SetJustifyH("LEFT")
    row._state = state
    local rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    rank:SetWidth(82)
    rank:SetJustifyH("RIGHT")
    row._rank = rank
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.ACCENT_GOLD))
        ShowTalentTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropBorderColor(unpack(self._border or Theme.BORDER_DIM))
    end)
    row:SetScript("OnClick", function(self)
        TUI.selectedKey = self._key
        RefreshTalentInspector()
    end)
    return row
end

local function RenderTalentList()
    local tree = ActiveTree()
    local talents = tree and tree.talents or {}
    for index, talent in ipairs(talents) do
        local row = TUI.listPool[index]
        if not row then
            row = CreateTalentListRow(TUI.listChild)
            TUI.listPool[index] = row
        end
        local state = TalentComparison(TUI.activeTree, talent)
        row._talent, row._comparison, row._tab = talent, state, TUI.activeTree
        row._key = EbonBuilds.CharacterSnapshot.TalentKey(TUI.activeTree, talent)
        row._icon:SetTexture(talent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row._name:SetText(string.format("Tier %d · %s", talent.tier or 0, talent.name or "Talent"))
        row._state:SetText(TalentStatusText(state))
        row._rank:SetText(string.format("%d/%d%s", talent.rank or 0, talent.maxRank or 0,
            state and string.format("  saved %d", state.snapshot or 0) or ""))
        local border = state and state.state == "exact" and Theme.SUCCESS
            or state and state.state == "missing" and Theme.WARNING
            or state and state.state == "additional" and { 0.25, 0.65, 1, 1 }
            or Theme.BORDER_DIM
        row._border = border
        row:SetBackdropBorderColor(unpack(border))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", TUI.listChild, "TOPLEFT", 0, -(index - 1) * 38)
        row:SetPoint("RIGHT", TUI.listChild, "RIGHT", 0, 0)
        row:Show()
    end
    for index = #talents + 1, #TUI.listPool do TUI.listPool[index]:Hide() end
    local height = math.max(TUI.listScroll:GetHeight() or 0, #talents * 38)
    TUI.listChild:SetHeight(height)
    TUI.listChild:SetWidth(math.max(320, (TUI.listScroll:GetWidth() or 360) - 18))
    TUI.listBar:SetMinMaxValues(0, math.max(0, height - (TUI.listScroll:GetHeight() or 0)))
end

local function RefreshTalentControls()
    TUI.mode = "snapshot"
    for name, button in pairs(TUI.modeButtons) do
        button:Enable()
        Theme.SetTabSelected(button, name == TUI.mode)
    end
    for name, button in pairs(TUI.presentationButtons) do
        Theme.SetTabSelected(button, name == TUI.presentation)
    end
    for tab = 1, 3 do
        local tree, button = displayed.talents and displayed.talents[tab], TUI.treeButtons[tab]
        if tree then
            button:SetText(string.format("%s · %d", tree.name or ("Tree " .. tab), tree.points or 0))
            button:Enable()
        else
            button:SetText("Tree " .. tab)
            button:Disable()
        end
        Theme.SetTabSelected(button, tab == TUI.activeTree)
    end
end

local function RefreshTalents()
    if not ActiveTree() then
        for tab = 1, 3 do if displayed.talents and displayed.talents[tab] then TUI.activeTree = tab; break end end
    end
    RefreshTalentControls()
    if TUI.presentation == "tree" then
        TUI.canvasScroll:Show(); TUI.canvasBar:Show()
        TUI.listScroll:Hide(); TUI.listBar:Hide()
        RenderTalentTree()
    else
        TUI.canvasScroll:Hide(); TUI.canvasBar:Hide()
        TUI.listScroll:Show(); TUI.listBar:Show()
        RenderTalentList()
    end
    RefreshTalentInspector()
    RefreshGlyphSummary()
    local stored = StoredSnapshot()
    if not stored then
        SetStatusText(TUI.summary, "No talent snapshot saved on this build.", "warning")
    elseif displayed._catalogRecovered then
        SetStatusText(TUI.summary,
            "Legacy talent snapshot · names and icons restored from the 3.3.5a catalog.", "success")
    elseif not HasCompleteTalentCatalog(displayed) then
        SetStatusText(TUI.summary,
            "Legacy talent snapshot · showing the selected nodes that were originally stored.", "warning")
    else
        SetStatusText(TUI.summary, "Saved talent snapshot · " .. (stored.capturedAt or "unknown capture time"), "success")
    end
end

local function ScheduleTalentGeometryRefresh()
    local function RefreshSettledGeometry()
        if not (viewFrame and viewFrame:IsShown() and activeSubview == "talents") then return end
        Layout()
        RefreshTalents()
    end
    if EbonBuilds.Scheduler then
        EbonBuilds.Scheduler.After("character.talent.geometry", 0,
            RefreshSettledGeometry, EbonBuilds.Scheduler.INTERACTIVE, true)
    else
        RefreshSettledGeometry()
    end
end

local function CreateTalentPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    pages.talents = page

    local modeDefs = { { "snapshot", "Snapshot" } }
    local previous
    for _, def in ipairs(modeDefs) do
        local button = Theme.CreateTab(page, def[2])
        button:SetSize(def[1] == "snapshot" and 112 or 88, 24)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 5, 0)
        else button:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -2) end
        button:SetScript("OnClick", function() TUI.mode = def[1]; RefreshTalents() end)
        TUI.modeButtons[def[1]] = button
        previous = button
    end

    local treeView = Theme.CreateTab(page, "Tree")
    treeView:SetSize(62, 24)
    treeView:SetPoint("TOPRIGHT", page, "TOPRIGHT", -70, -2)
    treeView:SetScript("OnClick", function() TUI.presentation = "tree"; RefreshTalents() end)
    TUI.presentationButtons.tree = treeView
    local listView = Theme.CreateTab(page, "List")
    listView:SetSize(62, 24)
    listView:SetPoint("LEFT", treeView, "RIGHT", 5, 0)
    listView:SetScript("OnClick", function() TUI.presentation = "list"; RefreshTalents() end)
    TUI.presentationButtons.list = listView

    TUI.summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    TUI.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -32)
    TUI.summary:SetPoint("RIGHT", page, "RIGHT", -4, 0)
    TUI.summary:SetJustifyH("LEFT")

    previous = nil
    for tab = 1, 3 do
        local button = Theme.CreateTab(page, "Tree " .. tab)
        button:SetHeight(24)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 5, 0)
        else button:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -52) end
        button:SetScript("OnClick", function()
            TUI.activeTree = tab
            TUI.selectedKey = nil
            RefreshTalents()
        end)
        TUI.treeButtons[tab] = button
        previous = button
    end

    TUI.body = CreateFrame("Frame", nil, page)
    TUI.body:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -82)
    TUI.body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)
    TUI.area = CreateFrame("Frame", nil, TUI.body)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(TUI.area, "CharacterView.TalentArea")
    end
    TUI.area:SetScript("OnSizeChanged", function(_, width, height)
        width = math.floor(tonumber(width) or 0)
        height = math.floor(tonumber(height) or 0)
        if width <= 1 or height <= 1 then return end
        if TUI._geometryWidth == width and TUI._geometryHeight == height then return end
        TUI._geometryWidth, TUI._geometryHeight = width, height
        if viewFrame and viewFrame:IsShown() and activeSubview == "talents" then
            ScheduleTalentGeometryRefresh()
        end
    end)

    TUI.canvasScroll = CreateFrame("ScrollFrame", nil, TUI.area)
    TUI.canvasScroll:SetPoint("TOPLEFT", TUI.area, "TOPLEFT", 0, 0)
    TUI.canvasScroll:SetPoint("BOTTOMRIGHT", TUI.area, "BOTTOMRIGHT", -16, 0)
    TUI.canvasChild = CreateFrame("Frame", nil, TUI.canvasScroll)
    TUI.canvasChild:SetWidth(400)
    TUI.canvasChild:SetHeight(500)
    TUI.canvasScroll:SetScrollChild(TUI.canvasChild)
    TUI.canvasBar = Theme.CreateScrollBar(TUI.area, 12)
    TUI.canvasBar:SetPoint("TOPRIGHT", TUI.area, "TOPRIGHT", -1, 0)
    TUI.canvasBar:SetPoint("BOTTOMRIGHT", TUI.area, "BOTTOMRIGHT", -1, 0)
    Theme.BindScrollWheel(TUI.canvasScroll, TUI.canvasBar, 38, TUI.canvasChild)

    TUI.listScroll = CreateFrame("ScrollFrame", nil, TUI.area)
    TUI.listScroll:SetPoint("TOPLEFT", TUI.area, "TOPLEFT", 0, 0)
    TUI.listScroll:SetPoint("BOTTOMRIGHT", TUI.area, "BOTTOMRIGHT", -16, 0)
    TUI.listChild = CreateFrame("Frame", nil, TUI.listScroll)
    TUI.listChild:SetWidth(400)
    TUI.listChild:SetHeight(400)
    TUI.listScroll:SetScrollChild(TUI.listChild)
    TUI.listBar = Theme.CreateScrollBar(TUI.area, 12)
    TUI.listBar:SetPoint("TOPRIGHT", TUI.area, "TOPRIGHT", -1, 0)
    TUI.listBar:SetPoint("BOTTOMRIGHT", TUI.area, "BOTTOMRIGHT", -1, 0)
    Theme.BindScrollWheel(TUI.listScroll, TUI.listBar, 38, TUI.listChild)

    TUI.inspector = CreateFrame("Frame", nil, TUI.body)
    Theme.ApplyCard(TUI.inspector)
    TUI.inspectorIcon = TUI.inspector:CreateTexture(nil, "ARTWORK")
    TUI.inspectorIcon:SetSize(38, 38)
    TUI.inspectorIcon:SetPoint("TOPLEFT", TUI.inspector, "TOPLEFT", 12, -12)
    TUI.inspectorTitle = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    TUI.inspectorTitle:SetPoint("TOPLEFT", TUI.inspectorIcon, "TOPRIGHT", 9, -1)
    TUI.inspectorTitle:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
    TUI.inspectorTitle:SetJustifyH("LEFT")
    TUI.inspectorRank = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    TUI.inspectorRank:SetPoint("TOPLEFT", TUI.inspectorTitle, "BOTTOMLEFT", 0, -5)
    TUI.inspectorStatus = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    TUI.inspectorStatus:SetPoint("TOPLEFT", TUI.inspectorIcon, "BOTTOMLEFT", 0, -12)
    TUI.inspectorStatus:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
    TUI.inspectorStatus:SetJustifyH("LEFT")
    TUI.inspectorBody = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    TUI.inspectorBody:SetPoint("TOPLEFT", TUI.inspectorStatus, "BOTTOMLEFT", 0, -9)
    TUI.inspectorBody:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
    TUI.inspectorBody:SetJustifyH("LEFT")
    TUI.inspectorBody:SetJustifyV("TOP")
    TUI.glyphTitle = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    TUI.glyphTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    TUI.glyphTitle:SetJustifyH("LEFT")
    TUI.glyphBody = TUI.inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    TUI.glyphBody:SetJustifyH("LEFT")
    TUI.glyphBody:SetJustifyV("TOP")
    TUI.glyphBody:SetSpacing(2)
    return page
end

local function LayoutTalentInspector(compact)
    TUI.inspectorIcon:ClearAllPoints()
    TUI.inspectorTitle:ClearAllPoints()
    TUI.inspectorRank:ClearAllPoints()
    TUI.inspectorStatus:ClearAllPoints()
    TUI.inspectorBody:ClearAllPoints()
    TUI.glyphTitle:ClearAllPoints()
    TUI.glyphBody:ClearAllPoints()

    TUI.inspectorIcon:SetPoint("TOPLEFT", TUI.inspector, "TOPLEFT", 12, -12)
    TUI.inspectorTitle:SetPoint("TOPLEFT", TUI.inspectorIcon, "TOPRIGHT", 9, -1)
    TUI.inspectorRank:SetPoint("TOPLEFT", TUI.inspectorTitle, "BOTTOMLEFT", 0, -5)
    if compact then
        TUI.inspectorTitle:SetPoint("RIGHT", TUI.inspector, "CENTER", -8, 0)
        TUI.inspectorStatus:SetPoint("TOPLEFT", TUI.inspectorIcon, "BOTTOMLEFT", 0, -10)
        TUI.inspectorStatus:SetPoint("RIGHT", TUI.inspector, "CENTER", -8, 0)
        TUI.inspectorBody:SetPoint("TOPLEFT", TUI.inspectorStatus, "BOTTOMLEFT", 0, -7)
        TUI.inspectorBody:SetPoint("RIGHT", TUI.inspector, "CENTER", -8, 0)
        TUI.glyphTitle:SetPoint("TOPLEFT", TUI.inspector, "TOP", 8, -12)
        TUI.glyphTitle:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
        TUI.glyphBody:SetPoint("TOPLEFT", TUI.glyphTitle, "BOTTOMLEFT", 0, -7)
        TUI.glyphBody:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
    else
        TUI.inspectorTitle:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
        TUI.inspectorStatus:SetPoint("TOPLEFT", TUI.inspectorIcon, "BOTTOMLEFT", 0, -12)
        TUI.inspectorStatus:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
        TUI.inspectorBody:SetPoint("TOPLEFT", TUI.inspectorStatus, "BOTTOMLEFT", 0, -9)
        TUI.inspectorBody:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
        TUI.glyphTitle:SetPoint("TOPLEFT", TUI.inspectorBody, "BOTTOMLEFT", 0, -14)
        TUI.glyphTitle:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
        TUI.glyphBody:SetPoint("TOPLEFT", TUI.glyphTitle, "BOTTOMLEFT", 0, -7)
        TUI.glyphBody:SetPoint("RIGHT", TUI.inspector, "RIGHT", -10, 0)
    end
end

local function LayoutTalents()
    local width = CharacterViewportWidth(pages.talents)
    local available = math.max(300, width - 8 - 10)
    local tabWidth = math.floor(available / 3)
    for tab = 1, 3 do TUI.treeButtons[tab]:SetWidth(math.max(88, tabWidth)) end

    TUI.area:ClearAllPoints()
    TUI.inspector:ClearAllPoints()
    if width < 620 then
        TUI.inspector:SetPoint("BOTTOMLEFT", TUI.body, "BOTTOMLEFT", 0, 0)
        TUI.inspector:SetPoint("BOTTOMRIGHT", TUI.body, "BOTTOMRIGHT", 0, 0)
        TUI.inspector:SetHeight(164)
        TUI.area:SetPoint("TOPLEFT", TUI.body, "TOPLEFT", 0, 0)
        TUI.area:SetPoint("BOTTOMRIGHT", TUI.inspector, "TOPRIGHT", 0, 7)
    else
        local inspectorWidth = width < 700 and 190 or 220
        TUI.inspector:SetPoint("TOPRIGHT", TUI.body, "TOPRIGHT", 0, 0)
        TUI.inspector:SetPoint("BOTTOMRIGHT", TUI.body, "BOTTOMRIGHT", 0, 0)
        TUI.inspector:SetWidth(inspectorWidth)
        TUI.area:SetPoint("TOPLEFT", TUI.body, "TOPLEFT", 0, 0)
        TUI.area:SetPoint("BOTTOMRIGHT", TUI.inspector, "BOTTOMLEFT", -7, 0)
    end
    LayoutTalentInspector(width < 620)
    TUI.canvasChild:SetWidth(CurrentTalentCanvasWidth())
end

------------------------------------------------------------------------
-- Gear page
------------------------------------------------------------------------

local G = { slotButtons = {}, selectedSlot = 1 }
local SLOT_SHORT = {
    [1]="Hd", [2]="Nk", [3]="Sh", [4]="Sr", [5]="Ch", [6]="Wa", [7]="Lg",
    [8]="Ft", [9]="Wr", [10]="Ha", [11]="R1", [12]="R2", [13]="T1", [14]="T2",
    [15]="Bk", [16]="MH", [17]="OH", [18]="Rg", [19]="Tb",
}
local LEFT_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }

local function SlotDefinition(slotId)
    for _, slot in ipairs(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) do
        if slot.id == slotId then return slot end
    end
end

V._SavedItemAffixForTests = SavedItemAffix

local function ApplyGearSlotVisual(button)
    local item = displayed.gear and displayed.gear[button._slotId]
    local border = Theme.BORDER_DIM
    if item then
        button._icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button._icon:SetVertexColor(1, 1, 1, item.resolved and 1 or 0.55)
        button._empty:SetText(item.resolved and "" or "...")
        border = item.resolved and (QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]) or Theme.WARNING
    else
        button._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        button._icon:SetVertexColor(0.34, 0.34, 0.38, 0.42)
        button._empty:SetText(SLOT_SHORT[button._slotId] or "-")
    end
    if G.selectedSlot == button._slotId then border = Theme.ACCENT_GOLD end
    button:SetBackdropBorderColor(unpack(border))
end

local function RefreshGearInspector()
    local slot = SlotDefinition(G.selectedSlot)
    local item = displayed.gear and displayed.gear[G.selectedSlot]
    G.inspectorTitle:SetText(slot and slot.name or "Equipment slot")
    if not item then
        G.inspectorIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        G.inspectorIcon:SetVertexColor(0.4, 0.4, 0.45, 0.55)
        G.itemName:SetText("Empty slot")
        G.itemName:SetTextColor(unpack(Theme.TEXT_MUTED))
        G.metadata:SetText(slot and slot.cosmetic and "Cosmetic slot · not scored" or "No item equipped")
        G.score:SetText("")
        G.stats:SetText("")
        G.warning:SetText("")
        return
    end

    G.inspectorIcon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    G.inspectorIcon:SetVertexColor(1, 1, 1, item.resolved and 1 or 0.6)
    G.itemName:SetText(item.name or item.link or "Item data pending")
    G.itemName:SetTextColor(unpack(QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]))
    if not item.resolved then
        G.metadata:SetText("Item data pending from the server")
        G.score:SetText("No score assigned while data is unresolved")
        G.stats:SetText("")
        SetStatusText(G.warning, "Unknown data is not treated as zero.", "warning")
        return
    end

    local affix = SavedItemAffix(item)
    G.metadata:SetText(string.format("Item level %s%s\nAffix: %s", tostring(item.itemLevel or "?"),
        item.itemSubType and " · " .. item.itemSubType or "", affix or "none"))
    local specKey = SpecKeyForContext()
    if slot and slot.cosmetic then
        G.score:SetText("Cosmetic slot · excluded from the gear model")
        G.stats:SetText("")
        G.warning:SetText("")
        return
    elseif not specKey or not EbonBuilds.GearScore.HasWeights(specKey) then
        G.score:SetText("No scoring profile for the edited build")
        G.stats:SetText("")
        SetStatusText(G.warning, "The item is shown without a modeled verdict.", "warning")
        return
    end

    local score = EbonBuilds.GearScore.ScoreItem(item.link, specKey)
    G.score:SetText(string.format("Modeled score: %.0f", score))
    G.score:SetTextColor(unpack(Theme.ACCENT_GOLD))
    local stats, count = BuildRecognizedStats(item, specKey)
    local lines = {}
    for index = 1, math.min(7, #stats) do
        lines[#lines + 1] = string.format("%s: %s", stats[index].name, tostring(stats[index].value))
    end
    G.stats:SetText(#lines > 0 and table.concat(lines, "\n") or "No weighted stats were recognized.")
    if count > 0 then
        SetStatusText(G.warning, "Stats and item level modeled; procs or custom effects may not be.", nil)
    else
        SetStatusText(G.warning, "Partial model: item level only; effects may be unmodeled.", "warning")
    end
end

local function CreateGearSlotButton(parent, slotId)
    local button = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(button, "CharacterView.GearSlot")
    end
    button:SetSize(42, 42)
    button._slotId = slotId
    Theme.ApplyCard(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    button._icon = icon
    local empty = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("CENTER", button, "CENTER", 0, 0)
    empty:SetTextColor(unpack(Theme.TEXT_MUTED))
    button._empty = empty
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.ACCENT_GOLD))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local item = displayed.gear and displayed.gear[self._slotId]
        if item and item.link and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(item.link)
        else
            local slot = SlotDefinition(self._slotId)
            GameTooltip:AddLine(slot and slot.name or "Equipment slot", 1, 0.82, 0)
            GameTooltip:AddLine(item and "Item data pending" or "Empty", 0.82, 0.82, 0.86)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        ApplyGearSlotVisual(self)
    end)
    button:SetScript("OnClick", function(self)
        G.selectedSlot = self._slotId
        for _, slotButton in pairs(G.slotButtons) do ApplyGearSlotVisual(slotButton) end
        RefreshGearInspector()
    end)
    return button
end

local function CreateGearPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    pages.gear = page
    G.summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 5, -6)
    G.summary:SetPoint("RIGHT", page, "RIGHT", -5, 0)
    G.summary:SetJustifyH("LEFT")

    G.body = CreateFrame("Frame", nil, page)
    G.body:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -28)
    G.body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)
    G.paperDoll = CreateFrame("Frame", nil, G.body)
    Theme.ApplyCard(G.paperDoll)
    G.center = CreateFrame("Frame", nil, G.paperDoll)
    Theme.ApplyPanel(G.center)
    G.centerIcon = G.center:CreateTexture(nil, "ARTWORK")
    G.centerIcon:SetSize(50, 50)
    G.centerName = G.center:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    G.centerName:SetJustifyH("CENTER")
    G.centerNote = G.center:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    G.centerNote:SetText("Saved equipment snapshot")

    G.affixPanel = CreateFrame("Frame", nil, G.center)
    G.affixTitle = G.affixPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    G.affixTitle:SetPoint("TOPLEFT", G.affixPanel, "TOPLEFT", 0, 0)
    G.affixTitle:SetPoint("RIGHT", G.affixPanel, "RIGHT", 0, 0)
    G.affixTitle:SetJustifyH("LEFT")
    G.affixTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    G.affixLeft = G.affixPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.affixLeft:SetPoint("TOPLEFT", G.affixTitle, "BOTTOMLEFT", 0, -7)
    G.affixLeft:SetPoint("RIGHT", G.affixPanel, "CENTER", -4, 0)
    G.affixLeft:SetJustifyH("LEFT")
    G.affixLeft:SetJustifyV("TOP")
    G.affixLeft:SetSpacing(2)
    G.affixRight = G.affixPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.affixRight:SetPoint("TOPLEFT", G.affixPanel, "TOP", 4, -20)
    G.affixRight:SetPoint("RIGHT", G.affixPanel, "RIGHT", 0, 0)
    G.affixRight:SetJustifyH("LEFT")
    G.affixRight:SetJustifyV("TOP")
    G.affixRight:SetSpacing(2)

    for _, slot in ipairs(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) do
        G.slotButtons[slot.id] = CreateGearSlotButton(G.paperDoll, slot.id)
    end

    G.inspector = CreateFrame("Frame", nil, G.body)
    Theme.ApplyCard(G.inspector)
    G.inspectorTitle = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    G.inspectorTitle:SetPoint("TOPLEFT", G.inspector, "TOPLEFT", 12, -12)
    G.inspectorTitle:SetTextColor(unpack(Theme.ACCENT_GOLD))
    G.inspectorIcon = G.inspector:CreateTexture(nil, "ARTWORK")
    G.inspectorIcon:SetSize(42, 42)
    G.inspectorIcon:SetPoint("TOPLEFT", G.inspectorTitle, "BOTTOMLEFT", 0, -10)
    G.itemName = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    G.itemName:SetPoint("TOPLEFT", G.inspectorIcon, "TOPRIGHT", 9, 0)
    G.itemName:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    G.itemName:SetJustifyH("LEFT")
    G.metadata = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    G.metadata:SetPoint("TOPLEFT", G.itemName, "BOTTOMLEFT", 0, -6)
    G.metadata:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    G.metadata:SetJustifyH("LEFT")
    G.score = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.score:SetPoint("TOPLEFT", G.inspectorIcon, "BOTTOMLEFT", 0, -14)
    G.score:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    G.score:SetJustifyH("LEFT")
    G.stats = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.stats:SetPoint("TOPLEFT", G.score, "BOTTOMLEFT", 0, -10)
    G.stats:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    G.stats:SetJustifyH("LEFT")
    G.stats:SetJustifyV("TOP")
    G.stats:SetSpacing(3)
    G.warning = G.inspector:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    G.warning:SetPoint("BOTTOMLEFT", G.inspector, "BOTTOMLEFT", 12, 12)
    G.warning:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    G.warning:SetJustifyH("LEFT")
    return page
end

local function LayoutGearCenter(compact)
    G.centerIcon:ClearAllPoints()
    G.centerName:ClearAllPoints()
    G.centerNote:ClearAllPoints()
    G.affixPanel:ClearAllPoints()
    G.affixLeft:ClearAllPoints()
    G.affixRight:ClearAllPoints()
    G.affixLeft:SetPoint("TOPLEFT", G.affixTitle, "BOTTOMLEFT", 0, -7)
    G.affixLeft:SetPoint("RIGHT", G.affixPanel, "RIGHT", 0, 0)
    G.affixLeft:SetSpacing(0)
    G.affixRight:Hide()
    if compact then
        G.centerIcon:SetSize(46, 46)
        G.centerIcon:SetPoint("TOPLEFT", G.center, "TOPLEFT", 12, -12)
        G.centerName:SetPoint("TOPLEFT", G.centerIcon, "TOPRIGHT", 10, -1)
        G.centerName:SetPoint("RIGHT", G.center, "CENTER", -8, 0)
        G.centerName:SetJustifyH("LEFT")
        G.centerNote:SetPoint("TOPLEFT", G.centerName, "BOTTOMLEFT", 0, -6)
        G.centerNote:SetPoint("RIGHT", G.center, "CENTER", -8, 0)
        G.centerNote:SetJustifyH("LEFT")
        G.affixPanel:SetPoint("TOPLEFT", G.center, "TOP", 8, -10)
        G.affixPanel:SetPoint("BOTTOMRIGHT", G.center, "BOTTOMRIGHT", -8, 8)
    else
        G.centerIcon:SetSize(50, 50)
        G.centerIcon:SetPoint("TOP", G.center, "TOP", 0, -10)
        G.centerName:SetPoint("TOP", G.centerIcon, "BOTTOM", 0, -6)
        G.centerName:SetPoint("LEFT", G.center, "LEFT", 6, 0)
        G.centerName:SetPoint("RIGHT", G.center, "RIGHT", -6, 0)
        G.centerName:SetJustifyH("CENTER")
        G.centerNote:SetPoint("TOP", G.centerName, "BOTTOM", 0, -5)
        G.centerNote:SetJustifyH("CENTER")
        G.affixPanel:SetPoint("TOPLEFT", G.center, "TOPLEFT", 8, -108)
        G.affixPanel:SetPoint("BOTTOMRIGHT", G.center, "BOTTOMRIGHT", -8, 8)
    end
end

local function LayoutPaperDoll()
    local frame = G.paperDoll
    if G.compact then
        local width = math.max(470, frame:GetWidth() or 0)
        local columns, step = 10, 46
        local totalWidth = columns * 42 + (columns - 1) * (step - 42)
        local startX = math.max(8, math.floor((width - totalWidth) / 2))
        for index, slot in ipairs(EbonBuilds.CharacterSnapshot.EQUIPMENT_SLOTS or {}) do
            local button = G.slotButtons[slot.id]
            local row = math.floor((index - 1) / columns)
            local column = (index - 1) % columns
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + column * step, -10 - row * step)
        end
        G.center:ClearAllPoints()
        G.center:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -108)
        G.center:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
        LayoutGearCenter(true)
        return
    end
    local height = math.max(330, frame:GetHeight() or 0)
    local step = math.min(44, math.max(34, (height - 64) / 7))
    for index, slotId in ipairs(LEFT_SLOTS) do
        local button = G.slotButtons[slotId]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10 - (index - 1) * step)
    end
    for index, slotId in ipairs(RIGHT_SLOTS) do
        local button = G.slotButtons[slotId]
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10 - (index - 1) * step)
    end
    for index, slotId in ipairs(BOTTOM_SLOTS) do
        local button = G.slotButtons[slotId]
        button:ClearAllPoints()
        button:SetPoint("BOTTOM", frame, "BOTTOM", (index - 2) * 50, 10)
    end
    G.center:ClearAllPoints()
    G.center:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -12)
    G.center:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -62, 60)
    LayoutGearCenter(false)
end

local function LayoutGearInspector(compact)
    G.inspectorTitle:ClearAllPoints()
    G.inspectorTitle:SetPoint("TOPLEFT", G.inspector, "TOPLEFT", 12, -12)
    G.inspectorIcon:ClearAllPoints()
    G.itemName:ClearAllPoints()
    G.metadata:ClearAllPoints()
    G.score:ClearAllPoints()
    G.stats:ClearAllPoints()
    G.warning:ClearAllPoints()
    if compact then
        G.inspectorIcon:SetPoint("TOPLEFT", G.inspector, "TOPLEFT", 12, -38)
        G.itemName:SetPoint("TOPLEFT", G.inspectorIcon, "TOPRIGHT", 9, 0)
        G.itemName:SetPoint("RIGHT", G.inspector, "CENTER", -8, 0)
        G.metadata:SetPoint("TOPLEFT", G.itemName, "BOTTOMLEFT", 0, -6)
        G.metadata:SetPoint("RIGHT", G.inspector, "CENTER", -8, 0)
        G.score:SetPoint("TOPLEFT", G.inspectorIcon, "BOTTOMLEFT", 0, -11)
        G.score:SetPoint("RIGHT", G.inspector, "CENTER", -8, 0)
        G.stats:SetPoint("TOPLEFT", G.inspector, "TOP", 8, -38)
        G.stats:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
        G.warning:SetPoint("BOTTOMLEFT", G.inspector, "BOTTOM", 8, 10)
        G.warning:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    else
        G.inspectorIcon:SetPoint("TOPLEFT", G.inspectorTitle, "BOTTOMLEFT", 0, -10)
        G.itemName:SetPoint("TOPLEFT", G.inspectorIcon, "TOPRIGHT", 9, 0)
        G.itemName:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
        G.metadata:SetPoint("TOPLEFT", G.itemName, "BOTTOMLEFT", 0, -6)
        G.metadata:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
        G.score:SetPoint("TOPLEFT", G.inspectorIcon, "BOTTOMLEFT", 0, -14)
        G.score:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
        G.stats:SetPoint("TOPLEFT", G.score, "BOTTOMLEFT", 0, -10)
        G.stats:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
        G.warning:SetPoint("BOTTOMLEFT", G.inspector, "BOTTOMLEFT", 12, 12)
        G.warning:SetPoint("RIGHT", G.inspector, "RIGHT", -10, 0)
    end
end

local function LayoutGear()
    local width = CharacterViewportWidth(pages.gear)
    G.compact = width < 620
    G.paperDoll:ClearAllPoints()
    G.inspector:ClearAllPoints()
    if G.compact then
        G.inspector:SetPoint("BOTTOMLEFT", G.body, "BOTTOMLEFT", 0, 0)
        G.inspector:SetPoint("BOTTOMRIGHT", G.body, "BOTTOMRIGHT", 0, 0)
        G.inspector:SetHeight(145)
        G.paperDoll:SetPoint("TOPLEFT", G.body, "TOPLEFT", 0, 0)
        G.paperDoll:SetPoint("BOTTOMRIGHT", G.inspector, "TOPRIGHT", 0, 7)
    else
        local inspectorWidth = width < 700 and 210 or 235
        G.inspector:SetPoint("TOPRIGHT", G.body, "TOPRIGHT", 0, 0)
        G.inspector:SetPoint("BOTTOMRIGHT", G.body, "BOTTOMRIGHT", 0, 0)
        G.inspector:SetWidth(inspectorWidth)
        G.paperDoll:SetPoint("TOPLEFT", G.body, "TOPLEFT", 0, 0)
        G.paperDoll:SetPoint("BOTTOMRIGHT", G.inspector, "BOTTOMLEFT", -7, 0)
    end
    LayoutGearInspector(G.compact)
    LayoutPaperDoll()
end

local function RefreshGear()
    local summary = BuildGearSummary(displayed.gear)
    SetStatusText(G.summary, string.format(
        "Snapshot · %d/%d equipped · %d resolved · %d pending · %d empty · modeled for the edited build",
        summary.equipped, summary.total, summary.resolved, summary.pending, summary.empty),
        summary.pending > 0 and "warning" or nil)
    SetClassIcon(G.centerIcon, displayed.classToken)
    local name = displayed.characterName or (StoredSnapshot() and "Saved character" or "No saved snapshot")
    local specKey = SpecKeyForContext()
    G.centerName:SetText(name .. (specKey and "\n" .. specKey:gsub("_", " · ") or ""))
    local affixLeft, affixRight, affixCount = BuildGearAffixColumns(displayed.gear)
    G.affixTitle:SetText(string.format("Equipped affixes · %d", affixCount))
    G.affixLeft:SetText(affixLeft)
    G.affixRight:SetText(affixRight)
    for _, button in pairs(G.slotButtons) do ApplyGearSlotVisual(button) end
    RefreshGearInspector()
end

------------------------------------------------------------------------
-- Shared shell, navigation, and lifecycle
------------------------------------------------------------------------

local function RefreshSnapshotStatus()
    if mountedContext and mountedContext.readOnly then
        if actionBar then actionBar:Hide() end
        return
    end
    if actionBar then actionBar:Show() end
    local allowed = CanAdoptCurrentCharacter()
    if not allowed then
        adoptBtn:Disable()
        snapshotStatus:SetText(string.format("Snapshot unavailable · %s character does not match %s build",
            ClassLabel(CurrentClassToken()), ClassLabel(EditingClassToken())))
        snapshotStatus:SetTextColor(unpack(Theme.DANGER))
        return
    end
    adoptBtn:Enable()
    local stored = StoredSnapshot()
    if stored then
        snapshotStatus:SetText(string.format("Saved snapshot: %s · %s",
            EbonBuilds.CharacterSnapshot.Summarize(stored) or "?", stored.capturedAt or "unknown time"))
        snapshotStatus:SetTextColor(unpack(Theme.TEXT_MUTED))
    else
        snapshotStatus:SetText("No snapshot saved on this build. Adopt a matching character to populate it.")
        snapshotStatus:SetTextColor(unpack(Theme.TEXT_MUTED))
    end
end

Refresh = function()
    if not (viewFrame and viewFrame:IsShown()) then return end
    RefreshModels()
    RefreshSnapshotStatus()
    if activeSubview == "overview" then RefreshOverview()
    elseif activeSubview == "talents" then RefreshTalents()
    elseif activeSubview == "gear" then RefreshGear() end
end

ShowSubview = function(name)
    if not pages[name] then return end
    activeSubview = name
    for key, page in pairs(pages) do
        if key == name then page:Show() else page:Hide() end
    end
    for key, button in pairs(navButtons) do Theme.SetTabSelected(button, key == name) end
    Layout()
    Refresh()
    if name == "talents" then ScheduleTalentGeometryRefresh() end
end

Layout = function()
    if layouting or not viewFrame then return end
    layouting = true
    local width = math.max(1, viewFrame:GetWidth() or 1)
    local navWidth = math.max(92, math.floor((width - 18) / 3))
    for _, button in pairs(navButtons) do button:SetWidth(navWidth) end
    snapshotStatus:SetWidth(math.max(180, width - 190))
    LayoutOverview()
    LayoutTalents()
    LayoutGear()
    layouting = false
end

local function EnsureBuilt(container)
    if viewFrame then return end
    Theme = EbonBuilds.Theme
    viewFrame = CreateFrame("Frame", nil, container)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(viewFrame, "CharacterView.ViewFrame")
    end

    local defs = { { "overview", "Overview" }, { "talents", "Talents" }, { "gear", "Gear" } }
    local previous
    for _, def in ipairs(defs) do
        local button = Theme.CreateTab(viewFrame, def[2])
        button:SetHeight(26)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 5, 0)
        else button:SetPoint("TOPLEFT", viewFrame, "TOPLEFT", 4, -2) end
        button:SetScript("OnClick", function() ShowSubview(def[1]) end)
        navButtons[def[1]] = button
        previous = button
    end

    pageHost = CreateFrame("Frame", nil, viewFrame)
    pageHost:SetPoint("TOPLEFT", viewFrame, "TOPLEFT", 0, -32)
    pageHost:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMRIGHT", 0, 34)
    CreateOverviewPage(pageHost)
    CreateTalentPage(pageHost)
    CreateGearPage(pageHost)
    for _, page in pairs(pages) do page:SetAllPoints(pageHost); page:Hide() end

    actionBar = CreateFrame("Frame", nil, viewFrame)
    actionBar:SetPoint("BOTTOMLEFT", viewFrame, "BOTTOMLEFT", 0, 0)
    actionBar:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMRIGHT", 0, 0)
    actionBar:SetHeight(30)
    adoptBtn = Theme.CreateButton(actionBar, "gold")
    adoptBtn:SetSize(160, 24)
    adoptBtn:SetPoint("LEFT", actionBar, "LEFT", 4, 0)
    adoptBtn:SetText("Adopt current snapshot")
    Theme.AttachTooltip(adoptBtn, "Adopt current snapshot",
        "Copies current gear, selected talent ranks, and glyphs into this build draft when the character and build classes match. Save commits it; Cancel discards it.")
    adoptBtn:SetScript("OnClick", function()
        if EbonBuilds.BuildForm and EbonBuilds.BuildForm.AdoptCharacterSnapshot then
            local allowed = CanAdoptCurrentCharacter()
            if not allowed then
                if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                    EbonBuilds.Toast.Show("Current character class must match the build class before taking a snapshot.")
                end
                RefreshSnapshotStatus()
                return
            end
            local adopted, reason = EbonBuilds.BuildForm.AdoptCharacterSnapshot(
                EbonBuilds.CharacterSnapshot.Capture())
            if not adopted then
                if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                    EbonBuilds.Toast.Show(reason == "CLASS_MISMATCH"
                        and "Current character class must match the build class before taking a snapshot."
                        or "Character snapshot could not be adopted.")
                end
                RefreshSnapshotStatus()
                return
            end
            dirty.talents, dirty.gear, dirty.glyphs = true, true, true
            Refresh()
        end
    end)
    snapshotStatus = actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    snapshotStatus:SetPoint("LEFT", adoptBtn, "RIGHT", 10, 0)
    snapshotStatus:SetJustifyH("LEFT")

    viewFrame:SetScript("OnSizeChanged", function()
        Layout()
        if viewFrame:IsShown() then MarkDirty("talents") end
    end)
    viewFrame:SetScript("OnShow", function() Layout(); Refresh() end)

    if not itemInfoToken then
        itemInfoToken = EbonBuilds.WoWEvents.On("GET_ITEM_INFO_RECEIVED", function()
            MarkDirty("gear")
        end, "CharacterView")
    end
end

function V.Mount(container, context)
    EnsureBuilt(container)
    mountedContext = context
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    local spec = (context and context.readOnly) and tonumber(context.spec)
        or (EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingSpec
            and tonumber(EbonBuilds.BuildForm.GetEditingSpec()))
    if spec and spec >= 1 and spec <= 3 then TUI.activeTree = spec end
    TUI.selectedKey = nil
    MarkDirty("all")
    viewFrame:Show()
    ShowSubview(activeSubview)
end

function V.Unmount()
    if viewFrame then viewFrame:Hide() end
end

function V.RefreshLayout()
    Layout()
end

V._RenderForTests = function() Refresh() end
V._DisplayedSnapshotForTests = function() return displayed end
V._CanAdoptForTests = CanAdoptCurrentCharacter
V._AdoptForTests = function()
    if adoptBtn then adoptBtn:GetScript("OnClick")() end
end
V._SetSubviewForTests = function(name) ShowSubview(name) end
V._SetMountedContextForTests = function(ctx) mountedContext = ctx end
V._EditingClassTokenForTests = EditingClassToken
V._StoredSnapshotForTests = StoredSnapshot
V._CanAdoptCurrentCharacterForTests = CanAdoptCurrentCharacter

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    EbonBuilds.Debug.RegisterTest("CharacterView read-only mode sources class/snapshot from context, never offers Adopt", function()
        local fakeSnapshot = { talents = {}, gear = {}, glyphs = {}, capturedAt = "test" }
        V._SetMountedContextForTests({ readOnly = true, snapshotClass = "MAGE", snapshot = fakeSnapshot, spec = 2 })
        if V._EditingClassTokenForTests() ~= "MAGE" then error("read-only class should come from context, not the editing session") end
        if V._StoredSnapshotForTests() ~= fakeSnapshot then error("read-only snapshot should come from context, not the editing session") end
        local allowed, reason = V._CanAdoptCurrentCharacterForTests()
        if allowed ~= false or reason ~= "READ_ONLY" then error("adopting must never be offered while browsing someone else's build") end
        V._SetMountedContextForTests(nil)
        if V._EditingClassTokenForTests() == "MAGE" then error("context override must not leak once cleared") end
    end)
end
