local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/AuctionatorBridge.lua
-- Soft integration with Auctionator 2.6.3 (WotLK / Interface 30300). Uses
-- Auctionator's public price API and Buy-tab search when the separate
-- Auctionator AddOn is installed; every entry point fails closed when it
-- is missing. No Retail/C_AuctionHouse APIs.

EbonBuilds.AuctionatorBridge = {}
local Bridge = EbonBuilds.AuctionatorBridge

local SHOPPING_LIST_NAME = "EbonBuilds Affixes"
-- Auctionator.lua: local BUY_TAB = 3 (stable in 2.6.3).
local AUCTIONATOR_BUY_TAB = 3

local shoppingListEnsured = false

function Bridge.IsAvailable()
    return IsAddOnLoaded and IsAddOnLoaded("Auctionator")
        and type(_G.Atr_GetAuctionBuyout) == "function"
end

-- Returns copper buyout from Auctionator's scan DB, or nil when unknown /
-- Auctionator is absent. Accepts item link, item ID, or plain item name.
function Bridge.GetBuyoutPrice(itemRef)
    if not Bridge.IsAvailable() then return nil end
    if itemRef == nil or itemRef == "" then return nil end
    local price = _G.Atr_GetAuctionBuyout(itemRef)
    if type(price) == "number" and price > 0 then return price end
    return nil
end

-- Market price for an affix *line* (any gear "... of <name> <rank>").
function Bridge.GetAffixLinePrice(affixName)
    if not affixName or affixName == "" then return nil end
    if not Bridge.IsAvailable() or type(_G.Atr_GetAuctionPrice) ~= "function" then
        return nil
    end
    local query = Bridge.BuildAffixSearchQuery(affixName)
    local price = _G.Atr_GetAuctionPrice(query)
    if type(price) == "number" and price > 0 then return price end
    return nil
end

function Bridge.BuildAffixSearchQuery(affixName)
    if type(_G.AtrPE_BuildAffixSearchQuery) == "function" then
        return _G.AtrPE_BuildAffixSearchQuery(affixName)
    end
    affixName = tostring(affixName or ""):match("^%s*(.-)%s*$") or ""
    if affixName == "" then return "" end
    if affixName:lower():find("^of%s+", 1) then return affixName end
    return "of " .. affixName
end

function Bridge.FormatCopper(copper)
    copper = tonumber(copper)
    if not copper or copper <= 0 then return nil end
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

local function EnsureAuctionHouseOpen()
    if CanSendAuctionQuery and CanSendAuctionQuery() and AuctionFrame and AuctionFrame:IsShown() then
        return true
    end
    if LoadAddOn then
        pcall(LoadAddOn, "Blizzard_AuctionUI")
    end
    if AuctionFrame and ShowUIPanel and CanSendAuctionQuery and CanSendAuctionQuery() then
        ShowUIPanel(AuctionFrame)
        return AuctionFrame:IsShown()
    end
    return false
end

local function EnsureBuyPaneReady()
    if not Bridge.IsAvailable() then return false end
    if type(_G.Atr_SelectPane) ~= "function"
        or not _G.Atr_Search_Box
        or type(_G.Atr_Search_Onclick) ~= "function" then
        return false
    end
    if not EnsureAuctionHouseOpen() then return false end
    _G.Atr_SelectPane(AUCTIONATOR_BUY_TAB)
    return _G.Atr_IsModeBuy and _G.Atr_IsModeBuy() or true
end

-- Prefills Auctionator's Buy tab and starts a scan for gear carrying this affix.
-- Returns ok, reasonToken ("ok", "missing", "no-ah", "ui-not-ready").
function Bridge.OpenAffixSearch(affixName)
    local query = Bridge.BuildAffixSearchQuery(affixName)
    if query == "" then return false, "empty" end
    if not Bridge.IsAvailable() then return false, "missing" end
    if not EnsureBuyPaneReady() then return false, "no-ah" end
    _G.Atr_Search_Box:SetText(query)
    _G.Atr_Search_Onclick()
    return true, "ok"
end

local function FindShoppingList()
    if type(_G.AUCTIONATOR_SHOPPING_LISTS) ~= "table" then return nil end
    for _, slist in ipairs(_G.AUCTIONATOR_SHOPPING_LISTS) do
        if slist and slist.name == SHOPPING_LIST_NAME then
            return slist
        end
    end
    return nil
end

local function EnsureShoppingList()
    if not Bridge.IsAvailable() or type(_G.Atr_SList) ~= "table" then return nil end
    local list = FindShoppingList()
    if list then return list end
    if not shoppingListEnsured and type(_G.Atr_SList.create) == "function" then
        shoppingListEnsured = true
        list = _G.Atr_SList.create(SHOPPING_LIST_NAME)
    end
    return list
end

-- Rebuilds Auctionator's "EbonBuilds Affixes" shopping list from affixes the
-- character has not learned yet. No-op when Auctionator is absent.
function Bridge.SyncMissingAffixShoppingList()
    if not Bridge.IsAvailable() then return false, "missing" end
    local list = EnsureShoppingList()
    if not list or type(list.items) ~= "table" then return false, "list" end

    while #list.items > 0 do
        table.remove(list.items)
    end

    local added = 0
    for _, affix in ipairs(EbonBuilds.Affix.GetLearned()) do
        if affix and not affix.learned and affix.name and affix.name ~= "" then
            local query = Bridge.BuildAffixSearchQuery(affix.name)
            if query ~= "" then
                list:AddItem(query)
                added = added + 1
            end
        end
    end
    list.isSorted = false
    if type(_G.Atr_DropDownSL_Initialize) == "function" then
        pcall(_G.Atr_DropDownSL_Initialize)
    end
    return true, added
end

function Bridge.AppendTooltipLines(tooltip, itemRef, affixName)
    if not tooltip or not Bridge.IsAvailable() then return end
    local price = Bridge.GetBuyoutPrice(itemRef)
    if not price and affixName then
        price = Bridge.GetAffixLinePrice(affixName)
    end
    if not price then return end
    local text = Bridge.FormatCopper(price)
    if text then
        tooltip:AddLine("Auctionator: " .. text, 1, 0.82, 0)
    end
end

function Bridge.IsAffixBargain(itemName, applyCostCopper)
    if not itemName or not Bridge.IsAvailable() then return false end
    local price = Bridge.GetBuyoutPrice(itemName)
    if not price then return false end
    applyCostCopper = tonumber(applyCostCopper) or 0
    if applyCostCopper > 0 then
        return price <= applyCostCopper
    end
    return true
end

function Bridge.Init()
    -- Nothing to hook at load time; integration is on-demand from AffixView,
    -- GearTooltip, and BagAffixDots. Register for late Auctionator loads so
    -- shopping-list sync works if the player enables it mid-session.
    if EbonBuilds.WoWEvents then
        EbonBuilds.WoWEvents.On("ADDON_LOADED", function(_, name)
            if name == "Auctionator" then
                shoppingListEnsured = false
            end
        end, "AuctionatorBridge", false, true)
    end
end
