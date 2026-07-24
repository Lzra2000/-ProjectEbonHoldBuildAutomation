-- Regression coverage for the v3.84-era world-map zone panel crash class:
--   SetMapPanelEnabled / SetMapEnabled call RefreshMapPanel before its local
--   definition unless forward-declared; RefreshMapPanel calls ShowZonePins the
--   same way. Without the forward decls Lua resolves nil globals at call time.
-- Also guards nil/missing frame paths and the MinimapButton drag scale fix.

unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

local function read(path)
    return H.read_file(path)
end

local function findForwardDecl(src, name)
    return src:find("local " .. name .. "[%s,\n]")
        or src:find("local " .. name .. "\r\n", 1, true)
end

local function findAssign(src, name)
    return src:find("function " .. name .. "%(")
end

------------------------------------------------------------------------
-- Source contracts: forward declarations (architecture + v3.84 fix)
------------------------------------------------------------------------
do
    local world = read("modules/ui/WorldIntegration.lua")

    for _, name in ipairs({ "RefreshMapPanel", "ShowZonePins" }) do
        local decl = findForwardDecl(world, name)
        local assign = findAssign(world, name)
        check(decl and assign and decl < assign,
            name .. " must be forward-declared before its function assignment")
    end

    local refreshAssign = findAssign(world, "RefreshMapPanel")
    local setPanelPos = world:find("function EbonBuilds%.WorldIntegration%.SetMapPanelEnabled")
    local setMapPos = world:find("function EbonBuilds%.WorldIntegration%.SetMapEnabled")
    check(setPanelPos and refreshAssign and setPanelPos < refreshAssign,
        "SetMapPanelEnabled is defined before RefreshMapPanel (needs forward decl)")
    check(setMapPos and refreshAssign and setMapPos < refreshAssign,
        "SetMapEnabled is defined before RefreshMapPanel (needs forward decl)")

    check(not world:find("C_Map%.", 1), "WorldIntegration must not call C_Map (post-3.3.5a)")
    check(not world:find("C_Timer%.", 1), "WorldIntegration must not call C_Timer (post-3.3.5a)")
end

------------------------------------------------------------------------
-- MinimapButton: drag angle must scale against Minimap (v3.84 fix)
------------------------------------------------------------------------
do
    local minimap = read("modules/ui/MinimapButton.lua")
    check(minimap:find("Minimap:GetEffectiveScale%(", 1) ~= nil,
        "GetCursorAngle must divide cursor position by Minimap:GetEffectiveScale()")
    check(not minimap:find("UIParent:GetEffectiveScale%(", 1),
        "GetCursorAngle must not use UIParent:GetEffectiveScale() (wrong drag radius)")
end

------------------------------------------------------------------------
-- Nil / guard helpers on pure paths (no client frames required)
------------------------------------------------------------------------
do
    local addon = {}
    H.load_addon("modules/ui/WorldIntegration.lua", addon)
    local WI = addon.WorldIntegration

    check(type(WI._RefreshMapPanelForTests) == "function",
        "RefreshMapPanel test hook is assigned after load")
    check(type(WI._ShowZonePinsForTests) == "function",
        "ShowZonePins test hook is assigned after load")

    equal(#WI.BuildZoneTomeLines(nil, function() return {} end), 0, "nil zone name yields no lines")
    equal(#WI.PinsForZone(nil, function() return {} end), 0, "nil zone name yields no pins")

    WI.SetSourceCoords(nil, "Tome", 0.5, 0.5)
    WI.SetSourceCoords("Zone", nil, 0.5, 0.5)
    WI.SetSourceCoords("Zone", "Tome", nil, 0.5)
    WI.SetSourceCoords("Zone", "Tome", 0.5, nil)
    equal(#WI.PinsForZone("Zone", function() return {} end), 0,
        "invalid SetSourceCoords args are ignored")

    local zones = { { zone = "Test", tomes = { { name = "Tome A", itemId = 1, total = 1, mobs = {} } } } }
    WI.SetSourceCoords("Test", "Tome A", 0.2, 0.3)
    equal(#WI.PinsForZone("Test", function() return zones end), 1, "valid coords still register")
end

------------------------------------------------------------------------
-- Behavioral: toggling zone panel / master map with world map open
-- (exact crash path from v3.84 — would error if RefreshMapPanel is nil)
------------------------------------------------------------------------
do
    local function stubFrame()
        local f = {
            scripts = {},
            shown = true,
        }
        function f:SetFrameStrata() end
        function f:SetSize() end
        function f:SetPoint() end
        function f:ClearAllPoints() end
        function f:Hide() f.shown = false end
        function f:Show() f.shown = true end
        function f:SetHeight() end
        function f:SetScript(_, fn) end
        function f:HookScript() end
        function f:IsShown() return f.shown end
        function f:GetWidth() return 512 end
        function f:GetHeight() return 512 end
        function f:CreateFontString()
            return {
                SetPoint = function() end, SetText = function() end,
                SetTextColor = function() end, SetJustifyH = function() end,
                SetWidth = function() end,
            }
        end
        function f:CreateTexture()
            return {
                SetTexture = function() end, SetTexCoord = function() end,
                SetWidth = function() end, SetHeight = function() end,
                ClearAllPoints = function() end, SetPoint = function() end,
                SetVertexColor = function() end, SetBlendMode = function() end,
                SetDrawLayer = function() end, Show = function() end, Hide = function() end,
            }
        end
        return f
    end

    WorldMapFrame = stubFrame()
    WorldMapDetailFrame = stubFrame()
    WorldMapButton = stubFrame()
    GameTooltip = {
        Hide = function() end, SetOwner = function() end, SetText = function() end,
        Show = function() end, IsOwned = function() return false end,
    }
    function CreateFrame()
        local btn = stubFrame()
        btn.SetSize = function() end
        return btn
    end
    GetCurrentMapContinent = function() return 1 end
    GetCurrentMapZone = function() return 1 end
    GetMapZones = function() return "Sholazar Basin" end
    GetZoneText = function() return "Sholazar Basin" end
    UpdateMapHighlight = function() return nil end
    IsAddOnLoaded = function() return false end

    EbonBuildsDB = { globalSettings = { tomeAtlasMapEnabled = true } }
    EbonBuildsCharDB = { mapZonePanelEnabled = true }

    local addon = {
        Theme = {
            ACCENT_GOLD = { 1, 0.8, 0 },
            TEXT_PRIMARY = { 1, 1, 1 },
            PRESENCE_TEAL = { 0, 1, 1 },
            PRESENCE_TEAL_HEX = "00ffff",
            ApplyPanel = function() end,
            AddHeaderRule = function() end,
            CreateCloseButton = function()
                return { SetScript = function() end, Hide = function() end }
            end,
            CreateCheckbox = function()
                return {
                    ClearAllPoints = function() end, SetPoint = function() end,
                    SetChecked = function() end, SetScript = function() end,
                    Show = function() end, Hide = function() end,
                    GetChecked = function() return true end,
                    _labelFS = { SetText = function() end },
                }
            end,
        },
        TomeAtlas = {
            ListByZone = function()
                return {
                    { zone = "Sholazar Basin", tomes = {
                        { name = "Tome of Ferocity", itemId = 1, total = 5, mobs = {} },
                    } },
                }
            end,
        },
        Database = {
            GetCharacterPreference = function(key)
                return EbonBuildsCharDB[key] ~= false
            end,
            SetCharacterPreference = function(key, value)
                EbonBuildsCharDB[key] = value
            end,
        },
        Debug = { RegisterTest = function() end },
        WoWEvents = H.wow_events_stub(),
    }

    H.load_addon("modules/ui/WorldIntegration.lua", addon)
    local WI = addon.WorldIntegration

    local function mustNotCrash(label, fn)
        local ok, err = pcall(fn)
        check(ok, label .. (ok and "" or (" — " .. tostring(err))))
    end

    mustNotCrash("SetMapPanelEnabled(true) with world map open (v3.84 crash path)", function()
        WI.SetMapPanelEnabled(true)
    end)

    mustNotCrash("SetMapPanelEnabled(false) then true round-trip", function()
        WI.SetMapPanelEnabled(false)
        WI.SetMapPanelEnabled(true)
    end)

    mustNotCrash("SetMapEnabled(true) with world map open", function()
        WI.SetMapEnabled(true)
    end)

    mustNotCrash("RefreshMapPanel direct call via test hook", function()
        addon.WorldIntegration._RefreshMapPanelForTests()
    end)

    mustNotCrash("ShowZonePins direct call via test hook", function()
        addon.WorldIntegration._ShowZonePinsForTests("Sholazar Basin")
    end)

    -- Guards: no world map frame / map hidden must not call into nil globals.
    WorldMapFrame = nil
    mustNotCrash("SetMapPanelEnabled(true) without WorldMapFrame", function()
        WI.SetMapPanelEnabled(true)
    end)

    WorldMapFrame = stubFrame()
    WorldMapFrame.shown = false
    mustNotCrash("SetMapPanelEnabled(true) while world map is hidden", function()
        WI.SetMapPanelEnabled(true)
    end)

    EbonBuildsDB.globalSettings.tomeAtlasMapEnabled = false
    mustNotCrash("RefreshMapPanel when master map toggle is off", function()
        addon.WorldIntegration._RefreshMapPanelForTests()
    end)
end

H.exit_if_failed(counters, "map panel regression test(s)")
print("Map panel regression passed: forward-decl contracts, nil guards, live-toggle crash path, and minimap drag scale.")
