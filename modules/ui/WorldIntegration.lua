-- EbonBuilds: modules/ui/WorldIntegration.lua
-- Responsibility: the two places EbonBuilds shows itself in the world
-- rather than in its own windows. (1) Unit tooltips: hovering a player
-- your client has seen addon traffic from gets one line saying they run
-- EbonBuilds, with their announced version when known. (2) The world
-- map: while a zone with known tome sources is open, a compact overlay
-- lists every tome dropping there and who drops it -- the atlas data is
-- mob-and-zone keyed (no coordinates exist), so an honest zone panel
-- beats fake pin positions.

EbonBuilds.WorldIntegration = {}

------------------------------------------------------------------------
-- (1) Player tooltip: "runs EbonBuilds"
------------------------------------------------------------------------

local function AugmentUnitTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or name == UnitName("player") then return end
    local info = EbonBuilds.Sync and EbonBuilds.Sync.GetPeerInfo and EbonBuilds.Sync.GetPeerInfo(name)
    if not info then return end
    local teal = EbonBuilds.Theme.PRESENCE_TEAL
    if info.version then
        tooltip:AddLine("EbonBuilds " .. info.version, teal[1], teal[2], teal[3])
    else
        tooltip:AddLine("EbonBuilds user", teal[1], teal[2], teal[3])
    end
    tooltip:Show()
end
EbonBuilds.WorldIntegration._AugmentUnitTooltipForTests = AugmentUnitTooltip

------------------------------------------------------------------------
-- (2) World map: tomes of the open zone
------------------------------------------------------------------------

local mapPanel, mapLines

local function EnsureMapPanel()
    if mapPanel then return end
    local Theme = EbonBuilds.Theme
    mapPanel = CreateFrame("Frame", "EbonBuildsMapTomes", WorldMapFrame)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(mapPanel, "WorldIntegration.MapPanel")
    end
    mapPanel:SetFrameStrata("FULLSCREEN")
    mapPanel:SetSize(240, 60)
    mapPanel:SetPoint("TOPRIGHT", WorldMapDetailFrame or WorldMapFrame, "TOPRIGHT", -8, -8)
    -- Theme.lua is always loaded well before this file in EbonBuilds.toc,
    -- so Theme is never actually unavailable here -- no fallback needed.
    Theme.ApplyPanel(mapPanel)
    local title = mapPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 8, -6)
    title:SetText("Tomes in this zone")
    title:SetTextColor(unpack(Theme.ACCENT_GOLD))
    mapPanel.title = title
    Theme.AddHeaderRule(mapPanel, title, 224)
    mapLines = mapPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapLines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    mapLines:SetJustifyH("LEFT")
    mapLines:SetWidth(224)
    mapLines:SetTextColor(unpack(Theme.TEXT_PRIMARY))
    mapPanel:Hide()
end

-- Pure data step, injectable for tests: zone name -> sorted display
-- lines ("Tome of X -- Ignis (12)"), built on TomeAtlas.ListByZone().
function EbonBuilds.WorldIntegration.BuildZoneTomeLines(zoneName, listByZone)
    listByZone = listByZone or (EbonBuilds.TomeAtlas and EbonBuilds.TomeAtlas.ListByZone)
    if not zoneName or not listByZone then return {} end
    local byZone = listByZone()
    local entry
    for _, z in ipairs(byZone or {}) do
        if z.zone == zoneName then
            entry = z
            break
        end
    end
    if not entry then return {} end
    local lines = {}
    for _, t in pairs(entry.tomes) do
        local topMob, topCount = "?", -1
        for _, m in ipairs(t.mobs or {}) do
            if (m.count or 0) > topCount then topMob, topCount = m.mob, m.count or 0 end
        end
        local extra = #(t.mobs or {}) > 1 and (" +%d"):format(#t.mobs - 1) or ""
        lines[#lines + 1] = string.format("%s -- %s (%d)%s", t.name or ("Tome " .. tostring(t.itemId)), topMob, t.total or 0, extra)
    end
    table.sort(lines)
    return lines
end

------------------------------------------------------------------------
-- (3) Continent view: color every zone with known tome drops
------------------------------------------------------------------------
-- The approach quest-overlay addons use: UpdateMapHighlight(x, y)
-- answers "which zone highlight sits at this point" for the continent
-- map, including the highlight texture's file, size, and position. We
-- sample the map once per continent, cache those answers, and keep the
-- highlight textures of tome-bearing zones shown permanently with a
-- green tint -- zone-level coloring needs zone names only, which is
-- exactly what the atlas has.

local highlightCache = {}   -- [continent] = { [normalizedZoneName] = {file, tpx, tpy, tx, ty, sx, sy} }
local overlayPool = {}      -- reusable texture frames on WorldMapButton
local legend

-- TomeAtlas zone names come from GetRealZoneText() at loot time; map zone
-- names come from UpdateMapHighlight()'s sampling. Both should already be
-- the same localized string for a given zone, but trimming here makes the
-- lookup below tolerant of incidental leading/trailing whitespace instead
-- of silently failing the exact-match and never coloring that zone.
local function NormalizeZoneName(name)
    if type(name) ~= "string" then return name end
    return name:match("^%s*(.-)%s*$")
end

-- Pure step, injectable: which zone names deserve color.
function EbonBuilds.WorldIntegration.ZonesWithTomes(listByZone)
    listByZone = listByZone or (EbonBuilds.TomeAtlas and EbonBuilds.TomeAtlas.ListByZone)
    local set = {}
    if not listByZone then return set end
    for _, z in ipairs(listByZone() or {}) do
        if z.tomes and next(z.tomes) then set[NormalizeZoneName(z.zone)] = true end
    end
    return set
end

local function SampleContinent(cont)
    if highlightCache[cont] then return highlightCache[cont] end
    local cache = {}
    -- 41x31 grid over the map button (0..1 inclusive on both axes) so the
    -- sampling reaches the map's actual edges. The previous 1/41..40/41
    -- and 1/31..30/31 ranges never touched x=0, x=1, y=0, or y=1, which
    -- could miss the highlight region of a zone whose geometry sits at
    -- the continent texture's border. Each grid hit caches one zone's
    -- highlight geometry; this is a one-time cost per continent per
    -- session (see highlightCache above).
    for gx = 0, 40 do
        for gy = 0, 30 do
            local name, file, tpx, tpy, tx, ty, sx, sy = UpdateMapHighlight(gx / 40, gy / 30)
            name = NormalizeZoneName(name)
            if name and file and not cache[name] then
                cache[name] = { file = file, tpx = tpx, tpy = tpy, tx = tx, ty = ty, sx = sx, sy = sy }
            end
        end
    end
    highlightCache[cont] = cache
    return cache
end

local function HideOverlays()
    for _, tex in ipairs(overlayPool) do tex:Hide() end
    if legend then legend:Hide() end
end

local function ShowContinentOverlays()
    local parent = WorldMapButton or WorldMapDetailFrame
    if not parent then return end
    local cont = GetCurrentMapContinent and GetCurrentMapContinent() or 0
    local zone = GetCurrentMapZone and GetCurrentMapZone() or 0
    if cont <= 0 or zone ~= 0 then
        HideOverlays()
        return
    end
    local cache = SampleContinent(cont)
    local wanted = EbonBuilds.WorldIntegration.ZonesWithTomes()
    local w, h = parent:GetWidth(), parent:GetHeight()
    if not w or w == 0 then return end
    local used = 0
    for zoneName in pairs(wanted) do
        local geo = cache[zoneName]
        if geo then
            used = used + 1
            local tex = overlayPool[used]
            if not tex then
                tex = parent:CreateTexture(nil, "OVERLAY")
                overlayPool[used] = tex
            end
            tex:SetTexture("Interface\\WorldMap\\" .. geo.file .. "\\" .. geo.file .. "Highlight")
            tex:SetTexCoord(0, geo.tpx, 0, geo.tpy)
            tex:SetWidth(geo.tx * w)
            tex:SetHeight(geo.ty * h)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", parent, "TOPLEFT", geo.sx * w, -geo.sy * h)
            tex:SetVertexColor(0.35, 0.85, 0.6, 0.45)
            -- Pin to the top of the OVERLAY layer explicitly. Draw order
            -- among same-layer textures otherwise depends on creation
            -- order, and this texture is only created/reused lazily on
            -- first use -- pinning it removes any dependency on exactly
            -- when that first happens relative to Blizzard's own zone-tile
            -- artwork, which is what actually made the tint invisible.
            if tex.SetDrawLayer then tex:SetDrawLayer("OVERLAY", 7) end
            tex:Show()
        end
    end
    for i = used + 1, #overlayPool do overlayPool[i]:Hide() end
    if used > 0 then
        if not legend then
            legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            legend:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
        end
        legend:SetText("|cff" .. EbonBuilds.Theme.PRESENCE_TEAL_HEX .. "Colored zones:|r tome drops known (zoom in for the list)")
        legend:Show()
    elseif legend then
        legend:Hide()
    end
end
EbonBuilds.WorldIntegration._ShowContinentOverlaysForTests = ShowContinentOverlays

local function RefreshMapPanel()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    ShowContinentOverlays()
    EnsureMapPanel()
    -- Displayed zone's localized name (3.3.5a): resolve via the map
    -- zone index; fall back to the player's current zone text when the
    -- map shows a continent view.
    local zoneName
    if GetMapZones and GetCurrentMapContinent and GetCurrentMapZone then
        local cont, zone = GetCurrentMapContinent(), GetCurrentMapZone()
        if cont and cont > 0 and zone and zone > 0 then
            local zones = { GetMapZones(cont) }
            zoneName = zones[zone]
        end
    end
    if not zoneName and GetZoneText then zoneName = GetZoneText() end
    local lines = EbonBuilds.WorldIntegration.BuildZoneTomeLines(zoneName)
    if #lines == 0 then
        mapPanel:Hide()
        return
    end
    local shown = {}
    for i = 1, math.min(#lines, 12) do shown[i] = lines[i] end
    if #lines > 12 then shown[#shown + 1] = ("... and %d more (Tome Atlas)"):format(#lines - 12) end
    mapLines:SetText(table.concat(shown, "\n"))
    mapPanel:SetHeight(30 + #shown * 13)
    mapPanel:Show()
end

function EbonBuilds.WorldIntegration.Init()
    -- Tooltip hook, error-isolated like GearTooltip's.
    -- Error-isolated like every other event/tooltip hook in the addon --
    -- core/Debug.lua's Protect() replaces what used to be a bespoke pcall
    -- wrapper duplicated in this file (this module predates Debug.lua).
    local function Safe(fn)
        if EbonBuilds.Debug and EbonBuilds.Debug.Protect then
            return EbonBuilds.Debug.Protect("WorldIntegration", fn)
        end
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok and EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Protect then
                EbonBuilds.ErrorLog.Protect("WorldIntegration", function() error(err, 0) end)()
            end
        end
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", Safe(AugmentUnitTooltip))
    end
    -- Map refresh on show and zone change.
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", Safe(RefreshMapPanel))
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("WORLD_MAP_UPDATE")
    f:SetScript("OnEvent", Safe(RefreshMapPanel))
end
