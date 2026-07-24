local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/TomeAtlasView.lua
-- AtlasLoot-style community drop browser for echo tomes: which mob drops
-- which tome, in which zone, with community-observed counts. Data comes
-- from core/TomeAtlas.lua and is shared between players via Sync.

EbonBuilds.TomeAtlasView = {}

local ROW_HEIGHT   = 34
local VISIBLE_ROWS = 10

local viewFrame, scrollFrame, scrollChild, scrollBar
local searchBox, filterBtn, syncBtn, syncAhBtn, countLabel, emptyText, zoneSummary
local zonePicker
local rows = {}
local state = { text = "", missingOnly = false, groupBy = "tome", zoneFilter = nil }
local Render -- forward decl: TryToggleTomePool schedules a refresh before Render is assigned

local function MatchesText(haystack)
    return state.text == "" or strlower(tostring(haystack or "")):find(state.text, 1, true) ~= nil
end

local function AuctionBridge()
    return EbonBuilds.AuctionatorBridge
end

local function ShowAuctionToast(reason)
    if not (EbonBuilds.Toast and EbonBuilds.Toast.Show) then return end
    if reason == "missing" then
        EbonBuilds.Toast.Show("Install Auctionator to search the AH from here.", "info")
    elseif reason == "no-ah" then
        EbonBuilds.Toast.Show("Open the Auction House first, then try again.", "info")
    else
        EbonBuilds.Toast.Show("Could not open that Auctionator search.", "info")
    end
end


------------------------------------------------------------------------
-- Owned detection: a tome is "owned" when its taught echo is in the
-- spellbook's Echoes tab (same normalization the Missing tab uses).
------------------------------------------------------------------------

local function BuildOwnedSet()
    if not (EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.GetOwnedEchoSets) then
        return {}, false
    end
    -- assumeNoneOwned=true: never block this view on the legacy fallback's
    -- retry. pcall-wrapped so any error in owned-detection (whichever
    -- ProjectEbonhold API surface a given server actually exposes) can
    -- never abort the whole Tome Atlas render and leave the window blank.
    local ok, ownedLower = pcall(EbonBuilds.BuildOverview.GetOwnedEchoSets, true)
    if not ok or not ownedLower then
        if EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("TomeAtlasView.BuildOwnedSet", tostring(ownedLower))
        end
        return {}, false
    end
    return ownedLower, true
end

local function IsOwned(tomeName, ownedSet)
    local norm = EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName
    if not norm then return false end
    -- NormalizeEchoName strips tome prefixes AND quality suffixes, so
    -- "Tome of Brittle Forging - Rare" maps onto the owned echo name.
    return ownedSet[norm(tomeName)] or false
end

local function ResolveEchoSpellId(itemId)
    if not itemId then return nil end
    if EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.FindEchoSpellIdByTomeItem then
        return EbonBuilds.ProjectAPI.FindEchoSpellIdByTomeItem(itemId)
    end
    return nil
end

local function TomeToggleCapable()
    local caps = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCapabilities
        and EbonBuilds.ProjectAPI.GetCapabilities()
    return caps and caps.tomeToggle and true or false
end

local function IsTomePoolDisabled(spellId)
    if not spellId or not TomeToggleCapable() then return false end
    return EbonBuilds.ProjectAPI.IsTomeEchoDisabled(spellId)
end

-- Right-click on a collected tome: flip its L1 draw-pool membership.
-- PE rejects non-L1 itself; we still toast early for clearer feedback.
local function TryToggleTomePool(item)
    if not item or item.kind ~= "tome" or not item.owned or not item.spellId then return end
    if not TomeToggleCapable() then return end
    if (UnitLevel("player") or 1) ~= 1 then
        if EbonBuilds.Toast then
            EbonBuilds.Toast.Show(EbonBuilds.L["Tomes can be toggled at level 1 only"])
        end
        return
    end
    local ok = EbonBuilds.ProjectAPI.ToggleTomeEcho(item.spellId)
    if ok then
        local enabling = item.tomeDisabled
        if EbonBuilds.Toast then
            EbonBuilds.Toast.Show(enabling
                and EbonBuilds.L["Tome enabled for draw pool"]
                or EbonBuilds.L["Tome disabled for draw pool"])
        end
        -- Server replies with refreshed discovery; re-render shortly so the
        -- (pool off)/(collected) tag catches up without reopening the view.
        if EbonBuilds.Scheduler and EbonBuilds.Scheduler.After then
            EbonBuilds.Scheduler.After("tomeAtlas.tomeToggleRefresh", 1.2, function()
                if viewFrame and viewFrame:IsShown() then Render() end
            end)
        end
    end
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function SourceText(sources)
    if #sources == 0 then return "|cff888888No drop data yet|r" end
    local parts = {}
    for i = 1, math.min(3, #sources) do
        local s = sources[i]
        parts[#parts + 1] = string.format("%s |cff888888-|r %s |cffffd100(x%d)|r",
            s.mob or "?", s.zone or "?", s.count or 1)
    end
    local txt = table.concat(parts, "|cff888888  |  |r")
    if #sources > 3 then
        txt = txt .. string.format(" |cff888888(+%d more)|r", #sources - 3)
    end
    return txt
end

local function ConfidenceFromSources(sources)
    local observations = 0
    for _, source in ipairs(sources or {}) do observations = observations + (source.count or 1) end
    if observations >= 10 then return "Confirmed", "success" end
    if observations >= 3 then return "Community", "warning" end
    return "Unverified", "muted"
end

local function BuildTomeItems()
    local all = EbonBuilds.TomeAtlas.List()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local out = {}
    for _, entry in ipairs(all) do
        local owned = spellbookReady and IsOwned(entry.name, ownedSet)
        local zoneOk = true
        if state.zoneFilter then
            zoneOk = false
            for _, s in ipairs(entry.sources) do
                if s.zone == state.zoneFilter then zoneOk = true; break end
            end
        end
        local textOk = MatchesText(entry.name)
        if not textOk then
            for _, s in ipairs(entry.sources) do
                if MatchesText(s.mob) or MatchesText(s.zone) then textOk = true; break end
            end
        end
        if zoneOk and textOk and (not state.missingOnly or not owned) then
            local tRows = {}
            for _, s in ipairs(entry.sources) do
                tRows[#tRows + 1] = { left = s.mob or "?", right = (s.zone or "?") .. "  x" .. (s.count or 1) }
            end
            local confidence, confidenceKind = ConfidenceFromSources(entry.sources)
            local spellId = ResolveEchoSpellId(entry.itemId)
            local tomeDisabled = owned and IsTomePoolDisabled(spellId)
            local tooltipStatus
            if not owned then
                tooltipStatus = "|cffff4444Missing|r"
            elseif tomeDisabled then
                tooltipStatus = "|cffff8040Collected -- draw pool OFF|r"
            else
                tooltipStatus = "|cff1eff00Already collected|r"
            end
            if owned and TomeToggleCapable() then
                tooltipStatus = tooltipStatus .. "\n|cff888888Right-click to toggle draw pool (level 1 only).|r"
            end
            out[#out + 1] = {
                kind = "tome",
                itemId = entry.itemId,
                spellId = spellId,
                title = entry.name,
                owned = owned,
                tomeDisabled = tomeDisabled and true or false,
                lineText = SourceText(entry.sources),
                confidence = confidence,
                confidenceKind = confidenceKind,
                tooltipStatus = tooltipStatus,
                tooltipHeader = "|cffffd100Known sources:|r",
                tooltipRows = tRows,
                tooltipEmpty = "No drop data yet -- be the first to loot one!",
            }
        end
    end
    table.sort(out, function(a, b) return a.title < b.title end)
    return out
end

-- Shared by BuildZoneItems/BuildMobItems: top-3 "Name (xCount)" summary
-- with a "(+N more)" tail, same visual language as SourceText().
local function TopTomesText(sortedRows)
    if #sortedRows == 0 then return "|cff888888No tomes match filter|r" end
    local parts = {}
    for i = 1, math.min(3, #sortedRows) do
        local r = sortedRows[i]
        parts[#parts + 1] = string.format("%s |cffffd100(%s)|r", r.left, r.right)
    end
    local txt = table.concat(parts, "|cff888888  |  |r")
    if #sortedRows > 3 then
        txt = txt .. string.format(" |cff888888(+%d more)|r", #sortedRows - 3)
    end
    return txt
end

local function BuildZoneItems()
    local all = EbonBuilds.TomeAtlas.ListByZone()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local out = {}
    for _, z in ipairs(all) do
        if not state.zoneFilter or z.zone == state.zoneFilter then
            local tRows = {}
            for _, t in ipairs(z.tomes) do
                local owned = spellbookReady and IsOwned(t.name, ownedSet)
                if not state.missingOnly or not owned then
                    tRows[#tRows + 1] = { left = t.name, right = "x" .. t.total, owned = owned, sortKey = t.total }
                end
            end
            local textOk = MatchesText(z.zone)
            if not textOk then
                for _, r in ipairs(tRows) do
                    if MatchesText(r.left) then textOk = true; break end
                end
            end
            if textOk and #tRows > 0 then
                table.sort(tRows, function(a, b) return a.sortKey > b.sortKey end)
                out[#out + 1] = {
                    kind = "zone",
                    title = z.zone,
                    lineText = TopTomesText(tRows),
                    confidence = "Community",
                    confidenceKind = "warning",
                    tooltipStatus = string.format("%d tome(s) known here", #tRows),
                    tooltipHeader = "|cffffd100Tomes findable here:|r",
                    tooltipRows = tRows,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.title < b.title end)
    return out
end

local function BuildMobItems()
    local all = EbonBuilds.TomeAtlas.ListByMob()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local out = {}
    for _, m in ipairs(all) do
        if not state.zoneFilter or m.zone == state.zoneFilter then
            local tRows = {}
            for _, t in ipairs(m.tomes) do
                local owned = spellbookReady and IsOwned(t.name, ownedSet)
                if not state.missingOnly or not owned then
                    tRows[#tRows + 1] = { left = t.name, right = "x" .. t.count, owned = owned, sortKey = t.count }
                end
            end
            local textOk = MatchesText(m.mob) or MatchesText(m.zone)
            if not textOk then
                for _, r in ipairs(tRows) do
                    if MatchesText(r.left) then textOk = true; break end
                end
            end
            if textOk and #tRows > 0 then
                table.sort(tRows, function(a, b) return a.sortKey > b.sortKey end)
                out[#out + 1] = {
                    kind = "mob",
                    title = string.format("%s  |cff888888(%s)|r", m.mob, m.zone or "?"),
                    lineText = TopTomesText(tRows),
                    confidence = "Community",
                    confidenceKind = "warning",
                    tooltipStatus = string.format("%d tome(s) known from this mob", #tRows),
                    tooltipHeader = "|cffffd100Tomes:|r",
                    tooltipRows = tRows,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.title < b.title end)
    return out
end

local function BuildFilteredList()
    if state.groupBy == "zone" then return BuildZoneItems() end
    if state.groupBy == "mob" then return BuildMobItems() end
    return BuildTomeItems()
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "TomeAtlasView.ZoneRow")
    end
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, 0.03)
    row._stripe = stripe

    local ahBtn = EbonBuilds.Theme.CreateButton(row)
    ahBtn:SetSize(34, 18)
    ahBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ahBtn:SetText("AH")
    ahBtn:Hide()
    ahBtn:SetScript("OnClick", function(self)
        local item = self:GetParent()._item
        if not item or item.kind ~= "tome" or item.owned then return end
        local bridge = AuctionBridge()
        if not bridge or not bridge.OpenTomeSearch then return end
        local ok, reason = bridge.OpenTomeSearch(item.title)
        if not ok then ShowAuctionToast(reason) end
    end)
    ahBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search Auctionator for this tome", 1, 1, 1)
        GameTooltip:AddLine("Opens Auctionator Buy with the tome item name.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row._ahBtn = ahBtn

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    name:SetJustifyH("LEFT")
    name:SetPoint("RIGHT", ahBtn, "LEFT", -8, 0)
    -- A long name (unusually long tome title, or "Mob (Zone)" in mob mode)
    -- would otherwise wrap to a second line -- rows are a fixed height, so
    -- a wrapped title visually collides with the source text below it.
    -- One line only; ownedTag is anchored to the title's actual right
    -- edge, so it still lands in the right place either way.
    name:SetWordWrap(false)
    row._name = name

    local ownedTag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ownedTag:SetPoint("TOPLEFT", name, "TOPRIGHT", 6, 0)
    row._owned = ownedTag

    local confidence = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    confidence:SetPoint("TOPRIGHT", ahBtn, "TOPLEFT", -8, 1)
    confidence:SetWidth(78)
    confidence:SetJustifyH("RIGHT")
    row._confidence = confidence

    local src = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    src:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
    src:SetPoint("RIGHT", ahBtn, "LEFT", -8, 0)
    src:SetJustifyH("LEFT")
    src:SetTextColor(0.75, 0.75, 0.75, 1)
    src:SetWordWrap(false)
    row._sources = src

    -- Hover: item tooltip for a tome row (icon, quality, description if the
    -- client has it cached) or a plain text tooltip for zone/mob rows, plus
    -- the FULL detail list -- the on-row text truncates to 3 entries, the
    -- tooltip is where "+N more" lives.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local item = self._item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shownItemTooltip = false
        if item.kind == "tome" and item.itemId then
            shownItemTooltip = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.itemId)
        end
        if not shownItemTooltip then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(item.title or "?", 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        if item.tooltipStatus then
            -- tooltipStatus may contain a newline for the toggle hint
            for line in tostring(item.tooltipStatus):gmatch("[^\n]+") do
                GameTooltip:AddLine(line)
            end
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddLine(item.tooltipHeader or "|cffffd100Details:|r")
        if item.tooltipRows and #item.tooltipRows > 0 then
            for _, r in ipairs(item.tooltipRows) do
                local left = r.left or "?"
                if r.owned then left = "|cff888888" .. left .. "|r" end
                GameTooltip:AddDoubleLine(left, r.right or "", 1, 1, 1, 1, 0.82, 0)
            end
        else
            GameTooltip:AddLine(item.tooltipEmpty or "No data yet.", 0.6, 0.6, 0.6, true)
        end
        if item.kind == "tome" and not item.owned then
            local bridge = AuctionBridge()
            if bridge and bridge.IsAvailable and bridge.IsAvailable() then
                local price = bridge.GetBuyoutPrice and bridge.GetBuyoutPrice(item.title)
                if price and bridge.FormatCopper then
                    local formatted = bridge.FormatCopper(price)
                    if formatted then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Auctionator: " .. formatted, 1, 0.82, 0)
                    end
                end
                GameTooltip:AddLine("Click AH to search the auction house", 0.55, 0.82, 1)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            TryToggleTomePool(self._item)
        end
    end)

    return row
end


------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local offset = 0
local filtered = {}

-- "Best farming" line: zones ranked by how many DISTINCT missing tomes
-- have a known source there. Independent of the search filter -- this is
-- the "where should I fly" answer for collectors.
local function ZoneSummaryText()
    local all = EbonBuilds.TomeAtlas.List()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local zoneCounts = {}
    for _, entry in ipairs(all) do
        local owned = spellbookReady and IsOwned(entry.name, ownedSet)
        if not owned then
            local seen = {}
            for _, s in ipairs(entry.sources) do
                local z = s.zone or "?"
                if z ~= "?" and not seen[z] then
                    seen[z] = true
                    zoneCounts[z] = (zoneCounts[z] or 0) + 1
                end
            end
        end
    end
    local ranked = {}
    for z, n in pairs(zoneCounts) do ranked[#ranked + 1] = { z = z, n = n } end
    if #ranked == 0 then return "" end
    table.sort(ranked, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.z < b.z
    end)
    local parts = {}
    for i = 1, math.min(3, #ranked) do
        parts[#parts + 1] = string.format("%s |cffffd100(%d)|r", ranked[i].z, ranked[i].n)
    end
    return "|cff1eff00Best known coverage:|r " .. table.concat(parts, "|cff888888,|r ")
end

Render = function()
    filtered = BuildFilteredList()
    if zoneSummary then zoneSummary:SetText(ZoneSummaryText()) end

    local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    scrollBar:SetMinMaxValues(0, maxOffset)

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local item = filtered[offset + i]
        if item then
            row._item = item
            row._name:SetText(item.title or "?")
            if item.kind == "tome" then
                if item.owned then
                    row._name:SetTextColor(0.55, 0.55, 0.55, 1)
                    if item.tomeDisabled then
                        row._owned:SetText("|cffff8040(pool off)|r")
                    else
                        row._owned:SetText("|cff1eff00(collected)|r")
                    end
                else
                    row._name:SetTextColor(1, 0.82, 0, 1)
                    row._owned:SetText("")
                end
            else
                row._name:SetTextColor(1, 0.82, 0, 1)
                row._owned:SetText("")
            end
            row._sources:SetText(item.lineText or "")
            row._confidence:SetText(item.confidence or "")
            if item.confidenceKind == "success" then
                row._confidence:SetTextColor(unpack(EbonBuilds.Theme.SUCCESS))
            elseif item.confidenceKind == "warning" then
                row._confidence:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
            else
                row._confidence:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
            end
            if row._ahBtn then
                if item.kind == "tome" and not item.owned then
                    row._ahBtn:Show()
                else
                    row._ahBtn:Hide()
                end
            end
            row._stripe:SetVertexColor(1, 1, 1, (offset + i) % 2 == 0 and 0.05 or 0.02)
            row:Show()
        else
            row._item = nil
            if row._ahBtn then row._ahBtn:Hide() end
            row:Hide()
        end
    end


    local total = #EbonBuilds.TomeAtlas.List()
    if state.groupBy == "zone" then
        countLabel:SetText(string.format("%d zone(s) shown", #filtered))
    elseif state.groupBy == "mob" then
        countLabel:SetText(string.format("%d mob(s) shown", #filtered))
    else
        countLabel:SetText(string.format("%d shown / %d known", #filtered, total))
    end

    if #filtered == 0 then
        if total == 0 then
            emptyText:SetText("No community drop data yet.\n\nTomes you loot are recorded automatically (mob + zone)\nand shared with other EbonBuilds users. Data from other\nplayers arrives when anyone syncs (Public Builds > Reload).")
        else
            emptyText:SetText("Nothing matches your filter.")
        end
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

    EbonBuilds.Theme.CreatePageHeader(
        f,
        "Tome Atlas",
        "Find missing tomes, compare farming locations, and judge source confidence at a glance."
    )

    zoneSummary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneSummary:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -57)
    zoneSummary:SetWidth(520)
    zoneSummary:SetHeight(14)
    zoneSummary:SetJustifyH("LEFT")

    -- Row 1: search box, full width.
    local searchContainer = CreateFrame("Frame", nil, f)
    searchContainer:SetHeight(20)
    searchContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -78)
    searchContainer:SetPoint("RIGHT", f, "RIGHT", -38, 0)
    EbonBuilds.Theme.ApplyInput(searchContainer)
    EbonBuilds.Theme.AddSearchIcon(searchContainer)

    searchBox = CreateFrame("EditBox", nil, searchContainer)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(searchBox, "TomeAtlasView.SearchBox")
    end
    searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 21, -2)
    searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -6, 2)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchBox:SetAutoFocus(false)
    EbonBuilds.Theme.WireEditBox(searchBox, searchContainer)
    local PLACEHOLDER = "Search tome, mob, or zone..."
    local function ShowPlaceholder(self)
        if self:GetText() == "" then
            self:SetTextColor(0.5, 0.5, 0.5, 1)
            self:SetText(PLACEHOLDER)
            self._isPlaceholder = true
        end
    end
    local function HidePlaceholder(self)
        if self._isPlaceholder then
            self:SetText("")
            self:SetTextColor(1, 1, 1, 1)
            self._isPlaceholder = false
        end
    end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        state.text = self._isPlaceholder and "" or strlower(self:GetText() or "")
        offset = 0
        Render()
    end)
    searchBox:SetScript("OnEditFocusGained", HidePlaceholder)
    searchBox:SetScript("OnEditFocusLost", function(self)
        self:SetTextColor(1, 1, 1, 1)
        ShowPlaceholder(self)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ShowPlaceholder(searchBox)

    -- Row 2: everything else -- count on the left, actions on the right.
    -- controlsRow exists purely as an anchor: TOPLEFT (from the search row)
    -- + explicit height fixes its vertical position; RIGHT stretches it to
    -- the frame's right edge. Every widget below anchors to ITS edges, so
    -- nothing can silently drift out of alignment the way the old
    -- independently-positioned widgets did (see the 2.5 layout bug).
    local controlsRow = CreateFrame("Frame", nil, f)
    controlsRow:SetHeight(20)
    controlsRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
    controlsRow:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    syncBtn = EbonBuilds.Theme.CreateButton(f)
    syncBtn:SetSize(70, 20)
    syncBtn:SetPoint("TOPRIGHT", controlsRow, "TOPRIGHT", 0, 0)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        EbonBuilds.Sync.RequestSync()
    end)
    syncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Sync Tome Atlas", 1, 1, 1)
        GameTooltip:AddLine("Requests drop data from other online EbonBuilds users.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncBtn:SetScript("OnUpdate", function(self, dt)
        self._throttle = (self._throttle or 0) + dt
        if self._throttle < 0.25 then return end
        self._throttle = 0
        local remaining = EbonBuilds.Sync.GetCooldownRemaining and EbonBuilds.Sync.GetCooldownRemaining() or 0
        if remaining ~= self._lastRemaining then
            self._lastRemaining = remaining
            if remaining > 0 then
                self:Disable()
                self:SetText(remaining .. "s")
            else
                self:Enable()
                self:SetText("Sync")
            end
        end
    end)

    syncAhBtn = EbonBuilds.Theme.CreateButton(f)
    syncAhBtn:SetSize(92, 20)
    syncAhBtn:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
    syncAhBtn:SetText("Sync AH list")
    syncAhBtn:SetScript("OnClick", function()
        local bridge = AuctionBridge()
        if not bridge or not bridge.SyncMissingTomeShoppingList then return end
        local ok, info = bridge.SyncMissingTomeShoppingList()
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            if ok then
                EbonBuilds.Toast.Show(
                    ("Updated Auctionator list (%d missing tomes)."):format(tonumber(info) or 0),
                    "success"
                )
            elseif info == "missing" then
                EbonBuilds.Toast.Show("Install Auctionator to maintain a tome shopping list.", "info")
            else
                EbonBuilds.Toast.Show("Could not update the Auctionator shopping list.", "info")
            end
        end
    end)
    syncAhBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rebuild Auctionator shopping list", 1, 1, 1)
        GameTooltip:AddLine(
            "Creates/updates \"EbonBuilds Tomes\" with one search term per missing atlas tome.",
            0.8, 0.8, 0.8, true
        )
        GameTooltip:Show()
    end)
    syncAhBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    filterBtn = EbonBuilds.Theme.CreateButton(f)
    filterBtn:SetSize(130, 20)
    filterBtn:SetPoint("RIGHT", syncAhBtn, "LEFT", -8, 0)
    filterBtn:SetText("Show: All")
    filterBtn:SetScript("OnClick", function(self)
        state.missingOnly = not state.missingOnly
        self:SetText(state.missingOnly and "Show: Missing only" or "Show: All")
        offset = 0
        Render()
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("LEFT", controlsRow, "LEFT", 0, 0)
    countLabel:SetPoint("TOP", controlsRow, "TOP", 0, -3)

    -- Row 3: category system -- group the list by Tome (default), Zone,
    -- or Mob, and optionally narrow everything to one zone. Same
    -- fixed-height chaining as controlsRow (no wrap-dependent anchoring).
    local filtersRow = CreateFrame("Frame", nil, f)
    filtersRow:SetHeight(20)
    filtersRow:SetPoint("TOPLEFT", controlsRow, "BOTTOMLEFT", 0, -12)
    filtersRow:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    local GROUP_LABELS = { tome = "Group: Tome", zone = "Group: Zone", mob = "Group: Mob" }
    local GROUP_ORDER = { "tome", "zone", "mob" }

    local groupByBtn = EbonBuilds.Theme.CreateButton(f)
    groupByBtn:SetSize(100, 20)
    groupByBtn:SetPoint("LEFT", filtersRow, "LEFT", 0, 0)
    groupByBtn:SetText(GROUP_LABELS[state.groupBy])
    groupByBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Group Tome Atlas by", 1, 1, 1)
        GameTooltip:AddLine("Tome: one row per tome, its known drop sources.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Zone: one row per zone, tomes findable there.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Mob: one row per mob, tomes it drops.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    groupByBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    groupByBtn:SetScript("OnClick", function(self)
        local idx = 1
        for i, g in ipairs(GROUP_ORDER) do if g == state.groupBy then idx = i break end end
        state.groupBy = GROUP_ORDER[(idx % #GROUP_ORDER) + 1]
        self:SetText(GROUP_LABELS[state.groupBy])
        offset = 0
        Render()
    end)

    -- Custom zone picker (replaces the native UIDropDownMenuTemplate,
    -- which is unstyled against this addon's dark theme and, with ~50+
    -- known zones, just runs an unbounded flat list off the top/bottom of
    -- the screen with no scrolling or search).
    local zoneBtn = EbonBuilds.Theme.CreateButton(f)
    zoneBtn:SetSize(150, 20)
    zoneBtn:SetPoint("LEFT", groupByBtn, "RIGHT", 8, 0)
    zoneBtn:SetText("All Zones \226\150\188") -- trailing dropdown-arrow glyph

    local picker = CreateFrame("Frame", "EbonBuildsTomeAtlasZonePicker", f)
    zonePicker = picker
    picker:SetFrameStrata("TOOLTIP") -- always above the main window and other UI
    picker:SetWidth(180)
    picker:SetHeight(280)
    picker:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", 0, -2)
    EbonBuilds.Theme.ApplyPanel(picker)
    picker:EnableMouse(true)
    picker:Hide()

    local pickerSearchContainer = CreateFrame("Frame", nil, picker)
    pickerSearchContainer:SetHeight(20)
    pickerSearchContainer:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -10)
    pickerSearchContainer:SetPoint("RIGHT", picker, "RIGHT", -12, 0)
    EbonBuilds.Theme.ApplyInput(pickerSearchContainer)
    EbonBuilds.Theme.AddSearchIcon(pickerSearchContainer)

    local pickerSearch = CreateFrame("EditBox", nil, pickerSearchContainer)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(pickerSearch, "TomeAtlasView.PickerSearch")
    end
    pickerSearch:SetPoint("TOPLEFT", pickerSearchContainer, "TOPLEFT", 21, -2)
    pickerSearch:SetPoint("BOTTOMRIGHT", pickerSearchContainer, "BOTTOMRIGHT", -6, 2)
    pickerSearch:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    pickerSearch:SetTextColor(1, 1, 1, 1)
    pickerSearch:SetAutoFocus(false)
    pickerSearch:SetText("")
    EbonBuilds.Theme.WireEditBox(pickerSearch, pickerSearchContainer)

    local pickerScroll = CreateFrame("ScrollFrame", nil, picker)
    pickerScroll:SetPoint("TOPLEFT", pickerSearchContainer, "BOTTOMLEFT", -4, -6)
    pickerScroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -20, 10)

    local pickerChild = CreateFrame("Frame", nil, pickerScroll)
    pickerChild:SetWidth(148)
    pickerChild:SetHeight(1)
    pickerScroll:SetScrollChild(pickerChild)

    local pickerBar = EbonBuilds.Theme.CreateScrollBar(pickerScroll)
    pickerBar:SetPoint("TOPLEFT",    pickerScroll, "TOPRIGHT",    -2, -4)
    pickerBar:SetPoint("BOTTOMLEFT", pickerScroll, "BOTTOMRIGHT", -2,  4)
    pickerBar:SetValueStep(20)
    pickerBar:SetScript("OnValueChanged", function(_, value)
        pickerScroll:SetVerticalScroll(value)
    end)
    EbonBuilds.Theme.BindScrollWheel(pickerScroll, pickerBar, 20, pickerChild)

    local PICKER_ROW_H = 20
    local pickerRows = {}

    local function ClosePicker()
        picker:Hide()
    end

    local function SelectZone(zoneNameOrNil, label)
        state.zoneFilter = zoneNameOrNil
        zoneBtn:SetText(label .. " \226\150\188")
        ClosePicker()
        offset = 0
        Render()
    end

    local function RefreshPickerList()
        local filterText = strlower(pickerSearch:GetText() or "")
        local names = { "All Zones" }
        for _, z in ipairs(EbonBuilds.TomeAtlas.ListZones()) do names[#names + 1] = z end
        local shown = {}
        for _, z in ipairs(names) do
            if filterText == "" or strlower(z):find(filterText, 1, true) then
                shown[#shown + 1] = z
            end
        end

        for i, zoneName in ipairs(shown) do
            local row = pickerRows[i]
            if not row then
                row = CreateFrame("Button", nil, pickerChild)
                if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
                    EbonBuilds.Debug.ProtectScript(row, "TomeAtlasView.PickerRow")
                end
                row:SetHeight(PICKER_ROW_H)
                row:SetPoint("LEFT", pickerChild, "LEFT", 0, 0)
                row:SetPoint("RIGHT", pickerChild, "RIGHT", 0, 0)
                local hl = row:CreateTexture(nil, "BACKGROUND")
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(1, 1, 1, 0.08)
                hl:SetAllPoints(row)
                hl:Hide()
                row._hl = hl
                row:SetScript("OnEnter", function(self) self._hl:Show() end)
                row:SetScript("OnLeave", function(self) self._hl:Hide() end)
                EbonBuilds.Theme.BindScrollWheel(pickerScroll, pickerBar, PICKER_ROW_H, row)
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", row, "LEFT", 4, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                row._label = label
                pickerRows[i] = row
            end
            row._label:SetText(zoneName)
            row:SetPoint("TOPLEFT", pickerChild, "TOPLEFT", 0, -(i - 1) * PICKER_ROW_H)
            row:SetScript("OnClick", function()
                if zoneName == "All Zones" then
                    SelectZone(nil, "All Zones")
                else
                    SelectZone(zoneName, zoneName)
                end
            end)
            row:Show()
        end
        for i = #shown + 1, #pickerRows do pickerRows[i]:Hide() end

        local totalH = math.max(1, #shown * PICKER_ROW_H)
        pickerChild:SetHeight(totalH)
        local maxScroll = math.max(0, totalH - pickerScroll:GetHeight())
        pickerBar:SetMinMaxValues(0, maxScroll)
        if pickerBar:GetValue() > maxScroll then pickerBar:SetValue(maxScroll) end
    end
    pickerSearch:SetScript("OnTextChanged", RefreshPickerList)

    zoneBtn:SetScript("OnClick", function()
        if picker:IsShown() then
            ClosePicker()
        else
            pickerSearch:SetText("")
            RefreshPickerList()
            picker:Show()
        end
    end)

    -- Rows container: anchored to filtersRow's bottom, not a magic number
    -- from the top of the frame -- header height can change again later
    -- without breaking this.
    scrollChild = CreateFrame("Frame", nil, f)
    scrollChild:SetPoint("TOPLEFT", filtersRow, "BOTTOMLEFT", 4, -14)
    scrollChild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)

    for i = 1, VISIBLE_ROWS do
        local row = CreateRow(scrollChild)
        row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * ROW_HEIGHT)
        rows[i] = row
    end

    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER", 0, 20)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    scrollBar = EbonBuilds.Theme.CreateScrollBar(f)
    scrollBar:SetPoint("TOPLEFT", scrollChild, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMRIGHT", 6, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        offset = math.floor(value + 0.5)
        Render()
    end)

    EbonBuilds.Theme.BindSliderWheel(f, scrollBar, 1, scrollChild)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local pendingRefresh = false
local REFRESH_THROTTLE = 0.3 -- seconds; coalesces bursty sync-driven refreshes

local function ScheduleRefresh()
    pendingRefresh = true
    EbonBuilds.Scheduler.After("tomeAtlasView.refresh", REFRESH_THROTTLE, function()
        if pendingRefresh and viewFrame and viewFrame:IsShown() then
            pendingRefresh = false
            local ok, err = pcall(Render)
            if not ok and EbonBuilds.ErrorLog then
                EbonBuilds.ErrorLog.Record("TomeAtlasView.ScheduleRefresh/Render", tostring(err))
            end
        end
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "TomeAtlasView")
end

function EbonBuilds.TomeAtlasView.Show(parent)
    if not viewFrame then
        viewFrame = BuildViewFrame(parent)
    end
    offset = 0
    -- The window must become visible regardless of whether the render
    -- succeeds -- a Render() error used to leave viewFrame:Show() below
    -- unreached, so the whole panel stayed permanently blank with no
    -- visible error (most players have script errors disabled).
    local ok, err = pcall(Render)
    if not ok and EbonBuilds.ErrorLog then
        EbonBuilds.ErrorLog.Record("TomeAtlasView.Show/Render", tostring(err))
    end
    viewFrame:Show()
    return viewFrame
end

function EbonBuilds.TomeAtlasView.Hide()
    if viewFrame then viewFrame:Hide() end
    if zonePicker then zonePicker:Hide() end
end

-- Called once per incoming sync message (potentially dozens to 100+ in a
-- burst during a heavy sync) -- must NOT render synchronously here, see
-- ScheduleRefresh above.
function EbonBuilds.TomeAtlasView.RefreshIfMounted()
    if viewFrame and viewFrame:IsShown() then
        ScheduleRefresh()
    end
end
