-- Headless tests for Auctionator Project Ebonhold helpers (Lua 5.1).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("AUCTIONATOR_PE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertEq(a, b, message)
    if a ~= b then
        fail((message or "not equal") .. ": " .. tostring(a) .. " vs " .. tostring(b))
    end
end

local chunk, err = loadfile("vendor/Auctionator/AuctionatorProjectEbonhold.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk)
if not ok then fail("load AuctionatorProjectEbonhold: " .. tostring(loadErr)) end

assertEq(AtrPE_BuildAffixSearchQuery("Keen Strikes III"), "of Keen Strikes III", "affix query")
assertEq(AtrPE_BuildAffixSearchQuery("of Foo Bar I"), "of Foo Bar I", "preserve of-prefix")
assertEq(AtrPE_BuildAffixSearchQuery(""), "", "empty affix query")

assertEq(
    AtrPE_NormalizeAffixSearch("Keen Strikes III"),
    "of Keen Strikes III",
    "normalize affix line"
)
assertEq(
    AtrPE_NormalizeAffixSearch("Misery's End of Keen Strikes III"),
    "Misery's End of Keen Strikes III",
    "preserve full item name"
)
assertEq(AtrPE_NormalizeAffixSearch('"Exact Item"'), '"Exact Item"', "preserve quoted exact")

local calls = 0
function GetAuctionItemInfo(listType, index)
    calls = calls + 1
    if index == 2 then error("simulated core failure") end
    return "Item", nil, 1, 2, true, 80, 100, 5, 500, 0, nil, "Seller"
end

local name, _, count = AtrPE_SafeGetAuctionItemInfo("list", 1)
assertEq(name, "Item", "safe get ok")
assertEq(count, 1, "safe get count")

name = AtrPE_SafeGetAuctionItemInfo("list", 2)
assertEq(name, nil, "safe get failure returns nil")
assertEq(calls, 2, "safe get invoked twice")

local queryCalls = 0
function QueryAuctionItems(...)
    queryCalls = queryCalls + 1
    if queryCalls == 1 then error("simulated query failure") end
end

local okQuery = AtrPE_SafeQueryAuctionItems("of Keen Strikes III", 0, 0)
assertEq(okQuery, false, "query failure returns false")

okQuery = AtrPE_SafeQueryAuctionItems("test", 0, 0)
assertEq(okQuery, true, "query success returns true")

print("AUCTIONATOR_PE OK")
