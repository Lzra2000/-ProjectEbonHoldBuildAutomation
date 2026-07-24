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

assertEq(Bridge.BuildTomeSearchQuery("Tome of Brittle Forging"), "Tome of Brittle Forging", "tome query")
assertEq(Bridge.BuildTomeSearchQuery("Tome of Brittle Forging - Rare"), "Tome of Brittle Forging", "strip quality")
assertEq(Bridge.BuildTomeSearchQuery("  Codex of Fire  "), "Codex of Fire", "trim tome")
assertEq(Bridge.BuildTomeSearchQuery(""), "", "empty tome query")

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
    -- Mirror AuctionatorShop.lua: init shopping lists before insert.
    if type(_G.AUCTIONATOR_SHOPPING_LISTS) ~= "table" then
        _G.AUCTIONATOR_SHOPPING_LISTS = {}
    end
    created = { name = name, items = {} }
    function created.AddItem(self, item) table.insert(self.items, item) end
    table.insert(_G.AUCTIONATOR_SHOPPING_LISTS, created)
    return created
end
_G.AUCTIONATOR_SHOPPING_LISTS = nil

local syncOk, count = Bridge.SyncMissingAffixShoppingList()
assertTrue(syncOk, "shopping list sync with nil SV table")
assertEq(count, 1, "one missing affix synced")
assertEq(created.name, "EbonBuilds Affixes", "list name")
assertEq(created.items[1], "of Keen Strikes III", "synced search term")
assertTrue(type(_G.AUCTIONATOR_SHOPPING_LISTS) == "table", "SV table initialized")

-- Soft-fail when PE shopping list cannot be created (fresh Bridge instance).
local addonSoft = { Affix = addon.Affix }
local chunkSoft, errSoft = loadfile("modules/integration/AuctionatorBridge.lua")
if not chunkSoft then fail(errSoft) end
local okSoft, loadErrSoft = pcall(chunkSoft, "EbonBuilds", addonSoft)
if not okSoft then fail("reload AuctionatorBridge: " .. tostring(loadErrSoft)) end
local BridgeSoft = addonSoft.AuctionatorBridge
_G.Atr_SList = {}
function _G.Atr_SList.create()
    error("create unavailable")
end
_G.AUCTIONATOR_SHOPPING_LISTS = nil
local softOk, softReason = BridgeSoft.SyncMissingAffixShoppingList()
assertTrue(not softOk, "sync soft-fails when create errors")
assertEq(softReason, "list", "list-missing reason")
assertNil(_G.AUCTIONATOR_SHOPPING_LISTS, "nil SV left untouched on create failure")

-- Restore happy-path create for remaining open-search tests
_G.Atr_SList = {}
function _G.Atr_SList.create(name)
    if type(_G.AUCTIONATOR_SHOPPING_LISTS) ~= "table" then
        _G.AUCTIONATOR_SHOPPING_LISTS = {}
    end
    created = { name = name, items = {} }
    function created.AddItem(self, item) table.insert(self.items, item) end
    table.insert(_G.AUCTIONATOR_SHOPPING_LISTS, created)
    return created
end
_G.AUCTIONATOR_SHOPPING_LISTS = {}
Bridge = BridgeSoft
local syncOk2, count2 = Bridge.SyncMissingAffixShoppingList()
assertTrue(syncOk2, "shopping list sync after soft-fail recovery")
assertEq(count2, 1, "one missing affix synced after recovery")

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

-- Tome search + missing-tome shopping list (Bridge is addonSoft after soft-fail reload)
addonSoft.TomeAtlas = {
    List = function()
        return {
            { name = "Tome of Alpha", itemId = 1 },
            { name = "Tome of Beta - Rare", itemId = 2 },
            { name = "Tome of Owned", itemId = 3 },
        }
    end,
}
addonSoft.BuildOverview = {
    GetOwnedEchoSets = function()
        return { owned = true }
    end,
    _NormalizeEchoName = function(name)
        if name == "Tome of Owned" then return "owned" end
        return "missing:" .. tostring(name)
    end,
}

local tomeTerms = Bridge.CollectMissingTomeSearchTerms()
assertEq(#tomeTerms, 2, "two missing tome terms")
assertEq(tomeTerms[1], "Tome of Alpha", "sorted first missing tome")
assertEq(tomeTerms[2], "Tome of Beta", "quality stripped in collect")

local tomeCreated
_G.Atr_SList = {}
function _G.Atr_SList.create(name)
    if type(_G.AUCTIONATOR_SHOPPING_LISTS) ~= "table" then
        _G.AUCTIONATOR_SHOPPING_LISTS = {}
    end
    tomeCreated = { name = name, items = {} }
    function tomeCreated.AddItem(self, item) table.insert(self.items, item) end
    table.insert(_G.AUCTIONATOR_SHOPPING_LISTS, tomeCreated)
    return tomeCreated
end
_G.AUCTIONATOR_SHOPPING_LISTS = nil

local tomeOk, tomeCount = Bridge.SyncMissingTomeShoppingList()
assertTrue(tomeOk, "tome shopping list sync")
assertEq(tomeCount, 2, "two missing tomes synced")
assertEq(tomeCreated.name, "EbonBuilds Tomes", "tome list name")
assertEq(tomeCreated.items[1], "Tome of Alpha", "first synced tome")
assertEq(tomeCreated.items[2], "Tome of Beta", "second synced tome")

capturedQuery = nil
local tomeOpenOk, tomeReason = Bridge.OpenTomeSearch("Tome of Alpha - Epic")
assertTrue(tomeOpenOk, "open tome search")
assertEq(tomeReason, "ok", "tome open reason")
assertEq(capturedQuery, "Tome of Alpha", "tome search box query")

-- Plain SV list without metatable: AddItem is nil until Atr_ShoppingListsInit.
-- Bridge must reattach Atr_SList or fall back to list.items insert.
do
    local plain = { name = "EbonBuilds Affixes", items = { "stale" } }
    _G.Atr_SList = {}
    _G.Atr_SList.__index = _G.Atr_SList
    function _G.Atr_SList.AddItem(self, itemName)
        table.insert(self.items, itemName)
        self.isSorted = false
    end
    local ensured = Bridge._EnsureListMethodsForTest(plain)
    assertTrue(type(ensured.AddItem) == "function", "EnsureListMethods attaches AddItem")
    assertTrue(Bridge._AddShoppingItemForTest(plain, "of Keen Strikes III"), "AddShoppingItem via metatable")
    assertEq(plain.items[#plain.items], "of Keen Strikes III", "item appended via AddItem")

    local noMeta = { name = "X", items = {} }
    _G.Atr_SList = nil -- no metatable available: fall back to items insert
    assertTrue(Bridge._AddShoppingItemForTest(noMeta, "of Foo"), "AddShoppingItem falls back to items insert")
    assertEq(noMeta.items[1], "of Foo", "fallback insert works when AddItem missing")
end

loadedAddons.Auctionator = nil
_G.Atr_GetAuctionBuyout = nil
openOk, reason = Bridge.OpenAffixSearch("Keen Strikes III")
assertTrue(not openOk, "open fails without Auctionator")
assertEq(reason, "missing", "missing reason")

print("AUCTIONATOR_BRIDGE OK")
