-- WorldIntegration pure helpers + RefreshMapPanel forward-declaration contract.
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

-- Load only needs the module table; UI frames are not exercised here.
-- WorldIntegration captures EbonBuilds.L at load time (i18n PR #109).
local addon = {
    L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    }),
}
addon = H.load_addon("modules/ui/WorldIntegration.lua", addon)
local WI = addon.WorldIntegration

local function listByZoneFactory(zones)
    return function() return zones end
end

------------------------------------------------------------------------
-- BuildZoneTomeLines / ZonesWithTomes
------------------------------------------------------------------------
do
    equal(#WI.BuildZoneTomeLines(nil, listByZoneFactory({})), 0, "nil zone yields no lines")
    equal(#WI.BuildZoneTomeLines("Nowhere", listByZoneFactory({})), 0, "unknown zone yields no lines")

    local zones = {
        {
            zone = "Icecrown",
            tomes = {
                [1] = {
                    itemId = 11,
                    name = "Tome Alpha",
                    total = 5,
                    mobs = {
                        { mob = "Ghoul", count = 3 },
                        { mob = "Geist", count = 2 },
                    },
                },
                [2] = {
                    itemId = 22,
                    name = "Tome Beta",
                    total = 1,
                    mobs = { { mob = "Abomination", count = 1 } },
                },
            },
        },
    }
    local lines = WI.BuildZoneTomeLines("Icecrown", listByZoneFactory(zones))
    equal(#lines, 2, "two tome lines for Icecrown")
    -- Sorted alphabetically by formatted line.
    check(lines[1]:find("Tome Alpha", 1, true), "Alpha line present")
    check(lines[1]:find("Ghoul", 1, true), "top mob is Ghoul")
    check(lines[1]:find("+1", 1, true), "extra mob count annotated")
    check(lines[2]:find("Tome Beta", 1, true), "Beta line present")
    check(not lines[2]:find("+", 1, true), "single-mob line has no +N")

    local set = WI.ZonesWithTomes(listByZoneFactory(zones))
    equal(set["Icecrown"], true, "Icecrown marked as having tomes")
    equal(set["Stormwind"], nil, "zones without tomes absent")

    -- Whitespace-tolerant zone names.
    zones[1].zone = "  Icecrown  "
    set = WI.ZonesWithTomes(listByZoneFactory(zones))
    equal(set["Icecrown"], true, "zone names are trimmed for tome set keys")
end

------------------------------------------------------------------------
-- PinsForZone (coords keyed by tome display name)
------------------------------------------------------------------------
do
    local zones = {
        {
            zone = "Dragonblight",
            tomes = {
                [9] = { itemId = 9, name = "Pin Tome", total = 2, mobs = {} },
                [10] = { itemId = 10, name = "Other Tome", total = 1, mobs = {} },
            },
        },
    }
    WI.SetSourceCoords("Dragonblight", "Pin Tome", 0.41, 0.51)
    local pins = WI.PinsForZone("Dragonblight", listByZoneFactory(zones))
    equal(#pins, 1, "only tomes with registered coords become pins")
    equal(pins[1].name, "Pin Tome", "pin name")
    equal(pins[1].x, 0.41, "pin x")
    equal(pins[1].y, 0.51, "pin y")
    equal(#WI.PinsForZone("Nowhere", listByZoneFactory(zones)), 0, "unknown zone has no pins")
    equal(#WI.PinsForZone(nil, listByZoneFactory(zones)), 0, "nil zone has no pins")

    WI.SetSourceCoords(nil, "Pin Tome", 0.1, 0.2)
    equal(#WI.PinsForZone("Dragonblight", listByZoneFactory(zones)), 1,
        "SetSourceCoords ignores nil zone without breaking existing coords")
end

------------------------------------------------------------------------
-- Forward-declaration contract (issue class: nil upvalue crash)
------------------------------------------------------------------------
do
    local src = H.read_file("modules/ui/WorldIntegration.lua")

    local function declPosFor(name)
        return src:find("local " .. name .. "[%s,\n]")
            or src:find("local " .. name .. "\r\n", 1, true)
    end

    for _, name in ipairs({ "RefreshMapPanel", "ShowZonePins" }) do
        local declPos = declPosFor(name)
        local assignPos = src:find("function " .. name .. "%(")
        check(declPos ~= nil, name .. " must be forward-declared (local " .. name .. ")")
        check(assignPos ~= nil, name .. " must be assigned (function " .. name .. "(...))")
        check(declPos < assignPos, name .. " forward declaration must precede assignment")
    end

    local refreshAssign = src:find("function RefreshMapPanel%(")
    local setPanelPos = src:find("function EbonBuilds%.WorldIntegration%.SetMapPanelEnabled")
    local setMapPos = src:find("function EbonBuilds%.WorldIntegration%.SetMapEnabled")
    check(setPanelPos ~= nil and refreshAssign and setPanelPos < refreshAssign,
        "SetMapPanelEnabled is defined before RefreshMapPanel assignment (needs the forward decl)")
    check(setMapPos ~= nil and refreshAssign and setMapPos < refreshAssign,
        "SetMapEnabled is defined before RefreshMapPanel assignment (needs the forward decl)")

    check(type(WI._RefreshMapPanelForTests) == "function",
        "RefreshMapPanel test hook is a real function after load (forward-decl was assigned)")
    check(type(WI._ShowZonePinsForTests) == "function",
        "ShowZonePins test hook is a real function after load (forward-decl was assigned)")

    -- Must not use post-3.3.5a map APIs.
    check(not src:find("C_Map%.", 1), "WorldIntegration must not call C_Map (post-3.3.5a)")
    check(not src:find("C_Timer%.", 1), "WorldIntegration must not call C_Timer (post-3.3.5a)")
end

H.exit_if_failed(counters, "WorldIntegration test(s)")
print("WorldIntegration coverage passed: zone tome lines, pin helpers, nil guards, and map forward-decls.")
