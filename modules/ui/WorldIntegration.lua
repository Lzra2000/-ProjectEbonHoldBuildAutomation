local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/WorldIntegration.lua
-- Responsibility: the two places EbonBuilds shows itself in the world
-- rather than in its own windows. (1) Unit tooltips: hovering a player
-- your client has seen addon traffic from gets one line saying they run
-- EbonBuilds, with their announced version when known. (2) The world
-- map: while a zone with known tome sources is open, a compact overlay
-- lists every tome dropping there and who drops it. The atlas data is
-- mob-and-zone keyed (no coordinates exist yet), so the zone panel is
-- the primary view -- but a coordinate-pin system with a toggle legend
-- (RSO-style) is also built and ready: the moment a data file calls
-- SetSourceCoords for a source, its pin and legend row appear
-- automatically, no other change needed here.

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

-- Forward-declared: RefreshMapPanel (below) calls this, but its full
-- definition lives down in section (4) next to the rest of the pin
-- system it belongs with. Without this declaration, the reference inside
-- RefreshMapPanel would resolve to a nonexistent global instead of the
-- local defined later in the file -- exactly the "attempt to call global
-- 'ShowZonePins' (a nil value)" crash this fixes.
local ShowZonePins
local mapPanel, mapLines
local pinPool = {}        -- reusable pin+hit-area pairs on WorldMapDetailFrame
local legendPanel, legendRows = nil, {}

local function MapFeatureEnabled()
    local settings = EbonBuildsDB and EbonBuildsDB.globalSettings
    return not settings or settings.tomeAtlasMapEnabled ~= false
end

function EbonBuilds.WorldIntegration.IsMapEnabled()
    return MapFeatureEnabled()
end

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

local function HideMapFeatures()
    HideOverlays()
    if mapPanel then mapPanel:Hide() end
    if legendPanel then legendPanel:Hide() end
    for i = 1, #pinPool do
        local pin = pinPool[i]
        if pin then
            pin:Hide()
            if pin.hit then pin.hit:Hide() end
        end
    end
    if GameTooltip and GameTooltip.IsOwned then
        for i = 1, #pinPool do
            local pin = pinPool[i]
            if pin and pin.hit and GameTooltip:IsOwned(pin.hit) then
                GameTooltip:Hide()
                break
            end
        end
    end
end

local function ShowContinentOverlays()
    if not MapFeatureEnabled() then
        HideOverlays()
        return
    end
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
    if not MapFeatureEnabled() then
        HideMapFeatures()
        return
    end
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
    ShowZonePins(zoneName)
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

------------------------------------------------------------------------
-- (4) Zone-level source pins + toggle legend
------------------------------------------------------------------------
-- Dormant coordinate-pin system: no tome source has real x/y data yet
-- (see the file header), so SetSourceCoords is never called anywhere in
-- the addon today and this renders nothing. The moment a data file
-- registers a coordinate for a source, its pin and legend row appear
-- automatically -- nothing else here needs touching. RSO-style toggle
-- legend included: a checkbox per visible pin, persisted per-character,
-- so a player can hide a marker they don't care about.

local sourceCoords = {}   -- [zoneName] = { [sourceName] = {x=0..1, y=0..1} }

-- SetSourceCoords(zoneName, sourceName, x, y): registers where a tome
-- source (by its display name, matching TomeAtlas's t.name) sits on the
-- ZONE map (not continent), as fractions (0..1) of the zone map's width/
-- height. Call this from a future data file to make a pin appear.
function EbonBuilds.WorldIntegration.SetSourceCoords(zoneName, sourceName, x, y)
    if not zoneName or not sourceName or type(x) ~= "number" or type(y) ~= "number" then return end
    sourceCoords[zoneName] = sourceCoords[zoneName] or {}
    sourceCoords[zoneName][sourceName] = { x = x, y = y }
end

local function PinHiddenKey(zoneName, sourceName)
    return zoneName .. "/" .. sourceName
end

local function IsPinHidden(zoneName, sourceName)
    local hidden = EbonBuildsCharDB and EbonBuildsCharDB.mapPinHidden
    return hidden and hidden[PinHiddenKey(zoneName, sourceName)] == true
end

local function SetPinHidden(zoneName, sourceName, hide)
    if not EbonBuildsCharDB then return end
    EbonBuildsCharDB.mapPinHidden = EbonBuildsCharDB.mapPinHidden or {}
    EbonBuildsCharDB.mapPinHidden[PinHiddenKey(zoneName, sourceName)] = hide and true or nil
end

-- PinsForZone(zoneName): which sources in this zone have a registered
-- coordinate -- pure and injectable so the renderer and the legend
-- always agree on the same list, and so this is testable without a real
-- client. Sorted by name for a stable legend order.
function EbonBuilds.WorldIntegration.PinsForZone(zoneName, listByZone)
    listByZone = listByZone or (EbonBuilds.TomeAtlas and EbonBuilds.TomeAtlas.ListByZone)
    local coordsForZone = zoneName and sourceCoords[zoneName]
    if not coordsForZone or not listByZone then return {} end
    local byZone = listByZone()
    local entry
    for _, z in ipairs(byZone or {}) do
        if z.zone == zoneName then
            entry = z
            break
        end
    end
    if not entry then return {} end
    local pins = {}
    for _, t in pairs(entry.tomes) do
        local name = t.name or ("Tome " .. tostring(t.itemId))
        local coord = coordsForZone[name]
        if coord then
            pins[#pins + 1] = { name = name, x = coord.x, y = coord.y }
        end
    end
    table.sort(pins, function(a, b) return a.name < b.name end)
    return pins
end

local function EnsurePin(index)
    local pin = pinPool[index]
    if pin then return pin end
    pin = WorldMapDetailFrame:CreateTexture(nil, "OVERLAY")
    pin:SetTexture("Interface\\Buttons\\WHITE8X8")
    pin:SetSize(8, 8)
    pin:SetVertexColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))
    if pin.SetDrawLayer then pin:SetDrawLayer("OVERLAY", 7) end
    local hit = CreateFrame("Button", nil, WorldMapDetailFrame)
    hit:SetSize(14, 14)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(hit, "WorldIntegration.PinHitArea")
    end
    pin.hit = hit
    pinPool[index] = pin
    return pin
end

local function EnsureLegendPanel()
    if legendPanel then return end
    local Theme = EbonBuilds.Theme
    legendPanel = CreateFrame("Frame", "EbonBuildsMapPinLegend", WorldMapFrame)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(legendPanel, "WorldIntegration.LegendPanel")
    end
    legendPanel:SetFrameStrata("FULLSCREEN")
    legendPanel:SetSize(200, 30)
    legendPanel:SetPoint("TOPLEFT", WorldMapDetailFrame or WorldMapFrame, "TOPLEFT", 8, -8)
    Theme.ApplyPanel(legendPanel)
    local title = legendPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", legendPanel, "TOPLEFT", 8, -6)
    title:SetText("Tome markers")
    title:SetTextColor(unpack(Theme.ACCENT_GOLD))
    Theme.AddHeaderRule(legendPanel, title, 180)
    legendPanel:Hide()
end

local function EnsureLegendRow(index)
    local row = legendRows[index]
    if row then return row end
    row = EbonBuilds.Theme.CreateCheckbox(legendPanel, "")
    legendRows[index] = row
    return row
end

function ShowZonePins(zoneName)
    if not MapFeatureEnabled() then
        for i = 1, #pinPool do
            local pin = pinPool[i]
            if pin then
                pin:Hide()
                if pin.hit then pin.hit:Hide() end
            end
        end
        if legendPanel then legendPanel:Hide() end
        return
    end
    local zoom = GetCurrentMapZone and GetCurrentMapZone() or 0
    if not WorldMapDetailFrame or zoom == 0 then
        for i = 1, #pinPool do pinPool[i]:Hide(); pinPool[i].hit:Hide() end
        if legendPanel then legendPanel:Hide() end
        return
    end
    local pins = EbonBuilds.WorldIntegration.PinsForZone(zoneName)
    local w, h = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    local shown = 0
    if w and w > 0 then
        for _, p in ipairs(pins) do
            if not IsPinHidden(zoneName, p.name) then
                shown = shown + 1
                local pin = EnsurePin(shown)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", p.x * w, -p.y * h)
                pin.hit:ClearAllPoints()
                pin.hit:SetPoint("CENTER", pin, "CENTER", 0, 0)
                pin.hit:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(p.name)
                    GameTooltip:Show()
                end)
                pin.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                pin:Show()
                pin.hit:Show()
            end
        end
    end
    for i = shown + 1, #pinPool do
        pinPool[i]:Hide()
        pinPool[i].hit:Hide()
    end

    if #pins == 0 then
        if legendPanel then legendPanel:Hide() end
        return
    end
    EnsureLegendPanel()
    for i, p in ipairs(pins) do
        local row = EnsureLegendRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", legendPanel, "TOPLEFT", 10, -(26 + (i - 1) * 22))
        row._labelFS:SetText(p.name)
        row:SetChecked(not IsPinHidden(zoneName, p.name))
        row:SetScript("OnClick", function(self)
            SetPinHidden(zoneName, p.name, not self:GetChecked())
            ShowZonePins(zoneName)
        end)
        row:Show()
    end
    for i = #pins + 1, #legendRows do legendRows[i]:Hide() end
    legendPanel:SetHeight(30 + #pins * 22)
    legendPanel:Show()
end
EbonBuilds.WorldIntegration._ShowZonePinsForTests = ShowZonePins

function EbonBuilds.WorldIntegration.SetMapEnabled(enabled)
    EbonBuildsDB = EbonBuildsDB or {}
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.tomeAtlasMapEnabled = enabled and true or false

    if enabled then
        if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
            RefreshMapPanel()
        end
    else
        HideMapFeatures()
    end
end

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    local function StubListByZone()
        return {
            { zone = "Sholazar Basin", tomes = {
                { name = "Tome of Ferocity", itemId = 1, total = 5, mobs = {} },
                { name = "Tome of the Void", itemId = 2, total = 3, mobs = {} },
            } },
        }
    end

    EbonBuilds.Debug.RegisterTest("WorldIntegration.PinsForZone: no pins until a coordinate is registered", function()
        local pins = EbonBuilds.WorldIntegration.PinsForZone("Sholazar Basin", StubListByZone)
        if #pins ~= 0 then error("expected zero pins with no coordinates registered, got " .. #pins) end
    end)

    EbonBuilds.Debug.RegisterTest("WorldIntegration.PinsForZone: registered source appears, unregistered doesn't", function()
        EbonBuilds.WorldIntegration.SetSourceCoords("Sholazar Basin", "Tome of Ferocity", 0.42, 0.61)
        local pins = EbonBuilds.WorldIntegration.PinsForZone("Sholazar Basin", StubListByZone)
        if #pins ~= 1 then error("expected exactly 1 pin, got " .. #pins) end
        if pins[1].name ~= "Tome of Ferocity" or pins[1].x ~= 0.42 or pins[1].y ~= 0.61 then
            error("registered pin has wrong name/coordinates")
        end
    end)

    EbonBuilds.Debug.RegisterTest("WorldIntegration.PinsForZone: a different zone's coordinate doesn't leak in", function()
        local pins = EbonBuilds.WorldIntegration.PinsForZone("Icecrown", StubListByZone)
        if #pins ~= 0 then error("a coordinate registered for a different zone leaked into this one") end
    end)

    EbonBuilds.Debug.RegisterTest("WorldIntegration: forward-declared ShowZonePins is actually assigned after full load", function()
        -- Would have caught the "attempt to call global 'ShowZonePins'
        -- (a nil value)" bug directly: that crash only happens when a
        -- function using ShowZonePins as an upvalue is CALLED, which the
        -- pure-logic tests above never exercise. This just confirms the
        -- forward-declared local actually got assigned by the time the
        -- file finished loading.
        if type(EbonBuilds.WorldIntegration._ShowZonePinsForTests) ~= "function" then
            error("ShowZonePins was never assigned -- a forward declaration without a matching assignment stays nil")
        end
    end)
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
    EbonBuilds.WoWEvents.On("WORLD_MAP_UPDATE", Safe(RefreshMapPanel), "WorldIntegration")
end
