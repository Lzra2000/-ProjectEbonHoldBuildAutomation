local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/AuctionatorBridge.lua
-- Soft integration with Auctionator 2.6.3 (WotLK / Interface 30300). Uses
-- Auctionator's public price API and Buy-tab search when the separate
-- Auctionator AddOn is installed; every entry point fails closed when it
-- is missing. No Retail/C_AuctionHouse APIs.

EbonBuilds.AuctionatorBridge = {}
local Bridge = EbonBuilds.AuctionatorBridge

local AFFIX_SHOPPING_LIST_NAME = "EbonBuilds Affixes"
local TOME_SHOPPING_LIST_NAME = "EbonBuilds Tomes"
-- Auctionator.lua: local BUY_TAB = 3 (stable in 2.6.3).
local AUCTIONATOR_BUY_TAB = 3

-- Per-list create attempts (avoid hammering Atr_SList.create on soft-fail).
local shoppingListCreateAttempted = {}

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

-- Exact item-name search for echo tomes (Tome/Codex/Scroll/Manual of ...).
-- Strips a trailing " - Quality" suffix if present so AH matches the item.
function Bridge.BuildTomeSearchQuery(tomeName)
    tomeName = tostring(tomeName or ""):match("^%s*(.-)%s*$") or ""
    if tomeName == "" then return "" end
    local stripped = tomeName:match("^(.-)%s+%-%s+%S+$")
    if stripped and stripped ~= "" then
        return stripped
    end
    return tomeName
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

local function OpenBuySearch(query)
    if query == "" then return false, "empty" end
    if not Bridge.IsAvailable() then return false, "missing" end
    if not EnsureBuyPaneReady() then return false, "no-ah" end
    _G.Atr_Search_Box:SetText(query)
    _G.Atr_Search_Onclick()
    return true, "ok"
end

-- Prefills Auctionator's Buy tab and starts a scan for gear carrying this affix.
-- Returns ok, reasonToken ("ok", "missing", "no-ah", "ui-not-ready").
function Bridge.OpenAffixSearch(affixName)
    return OpenBuySearch(Bridge.BuildAffixSearchQuery(affixName))
end

-- Prefills Auctionator's Buy tab for an echo tome item name.
function Bridge.OpenTomeSearch(tomeName)
    return OpenBuySearch(Bridge.BuildTomeSearchQuery(tomeName))
end

-- SavedVariables restore plain tables; Atr_ShoppingListsInit reattaches the
-- Atr_SList metatable. Bridge calls can race that, so re-attach when missing.
local function EnsureListMethods(list)
    if type(list) ~= "table" then return nil end
    if type(list.AddItem) == "function" then return list end
    if type(_G.Atr_SList) == "table" then
        setmetatable(list, _G.Atr_SList)
    end
    return list
end

-- Correct Add path for Auctionator 2.6.3-pe2: Atr_SList:AddItem. Falls back to
-- inserting into list.items when the metatable is still unavailable.
local function AddShoppingItem(list, itemName)
    if type(list) ~= "table" or itemName == nil or itemName == "" then return false end
    list = EnsureListMethods(list)
    if type(list.AddItem) == "function" then
        local ok = pcall(list.AddItem, list, itemName)
        return ok == true
    end
    if type(list.items) ~= "table" then
        list.items = {}
    end
    table.insert(list.items, itemName)
    list.isSorted = false
    return true
end

local function FindShoppingList(listName)
    if type(_G.AUCTIONATOR_SHOPPING_LISTS) ~= "table" then return nil end
    for _, slist in ipairs(_G.AUCTIONATOR_SHOPPING_LISTS) do
        if slist and slist.name == listName then
            return EnsureListMethods(slist)
        end
    end
    return nil
end

local function EnsureShoppingList(listName)
    if not Bridge.IsAvailable() or type(_G.Atr_SList) ~= "table" then return nil end
    local list = FindShoppingList(listName)
    if list then return list end
    if shoppingListCreateAttempted[listName] or type(_G.Atr_SList.create) ~= "function" then
        return nil
    end
    -- Soft-fail when Auctionator shopping lists are not ready yet (nil SV).
    local ok, created = pcall(_G.Atr_SList.create, listName)
    if not ok or not created then
        return nil
    end
    shoppingListCreateAttempted[listName] = true
    return EnsureListMethods(created)
end

local function RebuildShoppingList(listName, terms)
    if not Bridge.IsAvailable() then return false, "missing" end
    local list = EnsureShoppingList(listName)
    if not list or type(list.items) ~= "table" then return false, "list" end

    while #list.items > 0 do
        table.remove(list.items)
    end

    local added = 0
    local seen = {}
    for _, term in ipairs(terms or {}) do
        if type(term) == "string" and term ~= "" and not seen[term] then
            seen[term] = true
            if AddShoppingItem(list, term) then
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

-- Rebuilds Auctionator's "EbonBuilds Affixes" shopping list from affixes the
-- character has not learned yet. Soft-fails when Auctionator or the list is absent.
function Bridge.SyncMissingAffixShoppingList()
    local terms = {}
    if EbonBuilds.Affix and EbonBuilds.Affix.GetLearned then
        for _, affix in ipairs(EbonBuilds.Affix.GetLearned()) do
            if affix and not affix.learned and affix.name and affix.name ~= "" then
                local query = Bridge.BuildAffixSearchQuery(affix.name)
                if query ~= "" then
                    terms[#terms + 1] = query
                end
            end
        end
    end
    return RebuildShoppingList(AFFIX_SHOPPING_LIST_NAME, terms)
end

local function IsTomeOwned(tomeName, ownedSet, spellbookReady)
    if not spellbookReady or not tomeName then return false end
    local norm = EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName
    if not norm then return false end
    return ownedSet[norm(tomeName)] or false
end

-- Collect missing atlas tome names as AH search terms (deduped).
function Bridge.CollectMissingTomeSearchTerms()
    local terms = {}
    if not (EbonBuilds.TomeAtlas and EbonBuilds.TomeAtlas.List) then
        return terms
    end
    local ownedSet, spellbookReady = {}, false
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.GetOwnedEchoSets then
        local ok, set = pcall(EbonBuilds.BuildOverview.GetOwnedEchoSets, true)
        if ok and type(set) == "table" then
            ownedSet = set
            spellbookReady = true
        end
    end
    local seen = {}
    for _, entry in ipairs(EbonBuilds.TomeAtlas.List()) do
        local name = entry and entry.name
        if name and name ~= "" and not IsTomeOwned(name, ownedSet, spellbookReady) then
            local query = Bridge.BuildTomeSearchQuery(name)
            if query ~= "" and not seen[query] then
                seen[query] = true
                terms[#terms + 1] = query
            end
        end
    end
    table.sort(terms)
    return terms
end

-- Rebuilds Auctionator's "EbonBuilds Tomes" shopping list from missing atlas tomes.
function Bridge.SyncMissingTomeShoppingList()
    return RebuildShoppingList(TOME_SHOPPING_LIST_NAME, Bridge.CollectMissingTomeSearchTerms())
end

-- Test hooks (metatable reattach + AddItem fallback + list names).
Bridge._EnsureListMethodsForTest = EnsureListMethods
Bridge._AddShoppingItemForTest = AddShoppingItem
Bridge._AFFIX_SHOPPING_LIST_NAME = AFFIX_SHOPPING_LIST_NAME
Bridge._TOME_SHOPPING_LIST_NAME = TOME_SHOPPING_LIST_NAME

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
    -- TomeAtlasView, GearTooltip, and BagAffixDots. Register for late
    -- Auctionator loads so shopping-list sync works mid-session.
    if EbonBuilds.WoWEvents then
        EbonBuilds.WoWEvents.On("ADDON_LOADED", function(_, name)
            if name == "Auctionator" then
                shoppingListCreateAttempted = {}
            end
        end, "AuctionatorBridge", false, true)
    end
end
