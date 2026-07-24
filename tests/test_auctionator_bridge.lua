-- AuctionatorBridge soft-dependency and price helper tests (Lua 5.1 / headless).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("AUCTIONATOR_BRIDGE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertTrue(value, message)
    if not value then fail(message) end
end

local function assertEq(a, b, message)
    if a ~= b then fail((message or "not equal") .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
end

local function assertNil(value, message)
    if value ~= nil then fail(message or ("expected nil, got " .. tostring(value))) end
end

local loadedAddons = {}
function IsAddOnLoaded(name)
    return loadedAddons[name] == true
end

function GetCoinTextureString(copper)
    return tostring(copper) .. "c"
end

local addon = {}
addon.Affix = {
    GetLearned = function()
        return {
            { name = "Keen Strikes III", learned = false },
            { name = "Overwhelming Force II", learned = true },
        }
    end,
}

local chunk, err = loadfile("modules/integration/AuctionatorBridge.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk, "EbonBuilds", addon)
if not ok then fail("load AuctionatorBridge: " .. tostring(loadErr)) end
local Bridge = addon.AuctionatorBridge
assertTrue(Bridge, "AuctionatorBridge table missing")

assertEq(Bridge.BuildAffixSearchQuery("Keen Strikes III"), "of Keen Strikes III", "affix query")
assertEq(Bridge.BuildAffixSearchQuery("of Foo Bar I"), "of Foo Bar I", "preserve of-prefix")
assertEq(Bridge.BuildAffixSearchQuery(""), "", "empty query")

assertTrue(not Bridge.IsAvailable(), "available without Auctionator")
assertNil(Bridge.GetBuyoutPrice("Foo"), "price nil when absent")
assertNil(Bridge.GetAffixLinePrice("Keen Strikes III"), "line price nil when absent")

loadedAddons.Auctionator = true
_G.Atr_GetAuctionBuyout = function(item)
    if item == "Epic Sword of Keen Strikes III" then return 5000 end
    return nil
end
_G.Atr_GetAuctionPrice = function(query)
    if query == "of Keen Strikes III" then return 7500 end
    return nil
end

assertTrue(Bridge.IsAvailable(), "available when globals present")
assertEq(Bridge.GetBuyoutPrice("Epic Sword of Keen Strikes III"), 5000, "item buyout")
assertEq(Bridge.GetAffixLinePrice("Keen Strikes III"), 7500, "affix line price")
assertEq(Bridge.FormatCopper(123), "123c", "format copper")

assertTrue(Bridge.IsAffixBargain("Epic Sword of Keen Strikes III", 10000), "bargain when AH <= apply cost")
assertTrue(not Bridge.IsAffixBargain("Epic Sword of Keen Strikes III", 1000), "not bargain when apply cost lower")

local created
local capturedQuery
_G.Atr_SList = {}
function _G.Atr_SList.create(name)
    created = { name = name, items = {} }
    function created.AddItem(self, item) table.insert(self.items, item) end
    table.insert(_G.AUCTIONATOR_SHOPPING_LISTS, created)
    return created
end
_G.AUCTIONATOR_SHOPPING_LISTS = {}

local syncOk, count = Bridge.SyncMissingAffixShoppingList()
assertTrue(syncOk, "shopping list sync")
assertEq(count, 1, "one missing affix synced")
assertEq(created.name, "EbonBuilds Affixes", "list name")
assertEq(created.items[1], "of Keen Strikes III", "synced search term")

_G.Atr_SelectPane = function() end
_G.Atr_Search_Box = { SetText = function(_, text) capturedQuery = text end }
_G.Atr_Search_Onclick = function() end
_G.Atr_IsModeBuy = function() return true end
AuctionFrame = { IsShown = function() return true end }
function CanSendAuctionQuery() return true end
function ShowUIPanel() end

local openOk, reason = Bridge.OpenAffixSearch("Keen Strikes III")
assertTrue(openOk, "open affix search")
assertEq(reason, "ok", "open reason")
assertEq(capturedQuery, "of Keen Strikes III", "search box query")

loadedAddons.Auctionator = nil
_G.Atr_GetAuctionBuyout = nil
openOk, reason = Bridge.OpenAffixSearch("Keen Strikes III")
assertTrue(not openOk, "open fails without Auctionator")
assertEq(reason, "missing", "missing reason")

print("AUCTIONATOR_BRIDGE OK")
