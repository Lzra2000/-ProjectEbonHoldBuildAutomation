-- AutoSell category / keep-list / ShouldSell decision coverage.
-- Category names come from GetAuctionItemClasses() indices 6/9 (3.3.5a),
-- matching GetItemInfo's localized itemType (#71).
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

H.install_auction_class_stubs()
strlower = strlower or string.lower
strtrim = strtrim or function(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

EbonBuildsCharDB = {}
local addon = {
    RingBuffer = {
        New = function() return {} end,
        Clear = function() end,
        Append = function() end,
        Count = function() return 0 end,
        PopOldest = function() return nil end,
    },
    AffixItemScan = {
        IsProtectedFromSelling = function() return false end,
    },
    Build = { GetActive = function() return nil end },
    GearScore = {},
    Scheduler = {
        INTERACTIVE = 1,
        Every = function() end,
        Cancel = function() end,
    },
    WoWEvents = H.wow_events_stub(),
    ErrorLog = {
        Protect = function(_, fn) return fn end,
    },
}
H.load_addon("core/RingBuffer.lua", addon)
H.load_addon("modules/vendor/AutoSell.lua", addon)
local AS = addon.AutoSell

local function StubInfo(name, quality, itemType, equipLoc, sellPrice)
    return function()
        return name, name, quality, 1, 1, itemType, "", 1, equipLoc or "", "", sellPrice or 0
    end
end

------------------------------------------------------------------------
-- Category defaults and persistence
------------------------------------------------------------------------
do
    local cats = AS.GetCategories()
    equal(cats.poorOnly, false, "poorOnly defaults off")
    equal(cats.excludeTradeGoods, true, "excludeTradeGoods defaults on")
    equal(cats.excludeRecipes, true, "excludeRecipes defaults on")

    check(AS.SetCategory("poorOnly", true), "poorOnly can be set")
    equal(AS.GetCategory("poorOnly"), true, "poorOnly persists in memory")
    equal(EbonBuildsCharDB.autoSellCategories.poorOnly, true, "poorOnly persists to char DB")
    check(not AS.SetCategory("notAKey", true), "unknown category key rejected")
    AS.SetCategory("poorOnly", false)
end

------------------------------------------------------------------------
-- Keep-list
------------------------------------------------------------------------
do
    check(AS.AddToKeepList("Ruined Pelt"), "keep-list add")
    check(not AS.AddToKeepList("Ruined Pelt"), "duplicate keep-list add rejected")
    check(not AS.AddToKeepList(""), "empty keep-list name rejected")
    check(AS.IsKept("ruined pelt"), "keep-list match is case-insensitive")
    local names = AS.GetKeepList()
    equal(#names, 1, "keep-list size")
    equal(names[1], "Ruined Pelt", "keep-list preserves display casing")
    check(AS.RemoveFromKeepList("Ruined Pelt"), "keep-list remove")
    check(not AS.IsKept("Ruined Pelt"), "removed name is not kept")
end

------------------------------------------------------------------------
-- ShouldSell decisions (localized category names)
------------------------------------------------------------------------
do
    -- Valuable junk is never auto-sold.
    equal(AS.ShouldSell("link", StubInfo("Copper Coin", 0, "Junk", "", 1)), false,
        "positive sellPrice is never junk")

    -- Zero-value Poor junk sells with defaults.
    equal(AS.ShouldSell("link", StubInfo("Rags", 0, "Junk", "", 0)), true,
        "zero-value junk sells by default")

    -- English auction-class labels (harness GetAuctionItemClasses indices 6/9).
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), false,
        "Trade Goods excluded by default")
    equal(AS.ShouldSell("link", StubInfo("Plans: Foo", 1, "Recipe", "", 0)), false,
        "Recipes excluded by default")

    AS.SetCategory("excludeTradeGoods", false)
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), true,
        "Trade Goods sellable when excludeTradeGoods off")
    AS.SetCategory("excludeTradeGoods", true)

    AS.SetCategory("poorOnly", true)
    equal(AS.ShouldSell("link", StubInfo("White Cloth", 1, "Junk", "", 0)), false,
        "poorOnly blocks Common quality")
    equal(AS.ShouldSell("link", StubInfo("Gray Cloth", 0, "Junk", "", 0)), true,
        "poorOnly allows Poor quality")
    AS.SetCategory("poorOnly", false)

    AS.AddToKeepList("Special Junk")
    equal(AS.ShouldSell("link", StubInfo("Special Junk", 0, "Junk", "", 0)), false,
        "keep-list overrides sell decision")
    AS.RemoveFromKeepList("Special Junk")

    addon.AffixItemScan.IsProtectedFromSelling = function(name)
        return name == "Affix Token"
    end
    equal(AS.ShouldSell("link", StubInfo("Affix Token", 0, "Junk", "", 0)), false,
        "AffixItemScan protection blocks sell")
    addon.AffixItemScan.IsProtectedFromSelling = function() return false end
end

------------------------------------------------------------------------
-- Localized auction class names via GetAuctionItemClasses (issue #71).
-- Called at decision time so deDE/frFR clients match GetItemInfo itemType.
------------------------------------------------------------------------
do
    function GetAuctionItemClasses()
        return "Waffe", "Rüstung", "Behälter", "Verbrauchbar", "Glyphe",
            "Handwerkswaren", "Projektil", "Köcher", "Rezept", "Edelstein",
            "Verschiedenes", "Quest"
    end
    equal(AS.ShouldSell("link", StubInfo("Erz", 1, "Handwerkswaren", "", 0)), false,
        "German Trade Goods (auction class 6) excluded")
    equal(AS.ShouldSell("link", StubInfo("Rezept: Foo", 1, "Rezept", "", 0)), false,
        "German Recipe (auction class 9) excluded")
    -- Restore English auction classes for any later suites in-process.
    H.install_auction_class_stubs()
end

------------------------------------------------------------------------
-- Init wires merchant events through WoWEvents (not raw RegisterEvent)
------------------------------------------------------------------------
do
    AS.Init()
    equal(addon.WoWEvents.Count("MERCHANT_SHOW"), 1, "MERCHANT_SHOW via WoWEvents")
    equal(addon.WoWEvents.Count("MERCHANT_CLOSED"), 1, "MERCHANT_CLOSED via WoWEvents")
end

-- Source contract: prefer GetAuctionItemClasses over English-only globals.
do
    local src = H.read_file("modules/vendor/AutoSell.lua")
    check(not src:find("GetContainerItemInfo"),
        "AutoSell must not call GetContainerItemInfo (uses injected GetItemInfo quality)")
    check(src:find("GetAuctionItemClasses", 1, true),
        "AutoSell resolves localized category names via GetAuctionItemClasses (#71)")
    check(src:find("AUCTION_CLASS_TRADE_GOODS", 1, true) and src:find("AUCTION_CLASS_RECIPE", 1, true),
        "AutoSell uses fixed 3.3.5a auction class indices 6/9")
end

H.exit_if_failed(counters, "AutoSell test(s)")
print("AutoSell coverage passed: categories, keep-list, localized type filters, and WoWEvents merchant hooks.")
