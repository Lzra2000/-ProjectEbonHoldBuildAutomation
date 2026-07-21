local addonName, EbonBuilds = ...

-- EbonBuilds: modules/vendor/AutoSell.lua
-- Sells zero-value bag items to an open vendor. Off by default -- the
-- player must explicitly opt in via the Settings window.
--
-- Originally deliberately narrow (no rule engine, no whitelist -- "that is
-- AutoDelete's job"). Extended on request with a small keep-list and a
-- few category filters, since a fixed sell rule sometimes still catches
-- an item worth keeping despite scoring as zero-value junk. This still
-- isn't trying to be a general-purpose rule engine (no BoE tracking, no
-- disenchant-vs-sell logic -- see modules/ui/BagAffixDots.lua for the
-- disenchant/BoE *awareness* features, which mark items rather than act
-- on them) -- just enough control that the base zero-value sweep doesn't
-- have to be all-or-nothing.
--
-- Selling (not deleting) a worthless item is also the safer choice even
-- though the net gold is the same either way: WoW's vendor buyback tab
-- gives a same-session undo window that a direct bag deletion never has.

EbonBuilds.AutoSell = {}

local enabled = false

function EbonBuilds.AutoSell.SetEnabled(on)
    enabled = on and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("autoSellJunkEnabled", enabled)
    else
        EbonBuildsCharDB.autoSellJunkEnabled = enabled
    end
end

function EbonBuilds.AutoSell.IsEnabled()
    return enabled
end

------------------------------------------------------------------------
-- Keep-list: item names the player never wants auto-sold, regardless of
-- sell price or category. Per-character (junk on a bank alt isn't junk on
-- a main). Keyed by lowercase name for case-insensitive matching; the
-- original-cased name is kept as the value for display.
------------------------------------------------------------------------

local function KeepListDB()
    EbonBuildsCharDB.autoSellKeepList = type(EbonBuildsCharDB.autoSellKeepList) == "table"
        and EbonBuildsCharDB.autoSellKeepList or {}
    return EbonBuildsCharDB.autoSellKeepList
end

-- Returns true if it was actually added (false if already present or the
-- name was empty).
function EbonBuilds.AutoSell.AddToKeepList(itemName)
    if not itemName or itemName == "" then return false end
    local list = KeepListDB()
    local key = strlower(itemName)
    if list[key] then return false end
    list[key] = itemName
    return true
end

function EbonBuilds.AutoSell.RemoveFromKeepList(itemName)
    if not itemName or itemName == "" then return false end
    local list = KeepListDB()
    local key = strlower(itemName)
    if not list[key] then return false end
    list[key] = nil
    return true
end

-- Returns a sorted array of display names (not the internal lowercase-keyed
-- table), for rendering a list in the UI.
function EbonBuilds.AutoSell.GetKeepList()
    local list = KeepListDB()
    local names = {}
    for _, name in pairs(list) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function EbonBuilds.AutoSell.IsKept(itemName)
    if not itemName then return false end
    return KeepListDB()[strlower(itemName)] ~= nil
end

------------------------------------------------------------------------
-- Category filters. All default to preserving the ORIGINAL behavior
-- (poorOnly off = any quality is eligible, matching the pre-3.49 sweep)
-- except the two "exclude" categories, which default ON: a truly
-- zero-value Trade Good or Recipe is unusual enough that sweeping it
-- automatically is more likely a surprise than a convenience.
------------------------------------------------------------------------

local DEFAULT_CATEGORIES = {
    poorOnly = false,          -- true: only quality-0 (Poor/gray) items are eligible
    excludeTradeGoods = true,  -- true: Trade Goods items are never auto-sold
    excludeRecipes = true,     -- true: Recipe items are never auto-sold
}

local categories = {}
for k, v in pairs(DEFAULT_CATEGORIES) do categories[k] = v end

local function LoadCategories()
    local saved = EbonBuildsCharDB.autoSellCategories
    if type(saved) == "table" then
        for k in pairs(DEFAULT_CATEGORIES) do
            if saved[k] ~= nil then categories[k] = saved[k] and true or false end
        end
    end
end

local function SaveCategories()
    EbonBuildsCharDB.autoSellCategories = categories
end

-- key: one of "poorOnly", "excludeTradeGoods", "excludeRecipes".
function EbonBuilds.AutoSell.SetCategory(key, value)
    if DEFAULT_CATEGORIES[key] == nil then return false end
    categories[key] = value and true or false
    SaveCategories()
    return true
end

function EbonBuilds.AutoSell.GetCategory(key)
    return categories[key]
end

-- Returns a shallow copy (callers must not mutate the live table directly).
function EbonBuilds.AutoSell.GetCategories()
    local copy = {}
    for k, v in pairs(categories) do copy[k] = v end
    return copy
end

-- Equip location -> inventory slot id(s). Rings/trinkets map to BOTH of
-- their slots since either could be the one worth replacing.
local EQUIP_SLOT_IDS = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
    INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16}, INVTYPE_2HWEAPON = {16},
    INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18},
    INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}

-- Is this item a gear upgrade over what's currently equipped, for the
-- active build's class/spec? Only meaningful for actual equipment (has an
-- INVTYPE_* equip location) -- everything else returns false and falls
-- through to the normal sellPrice/affix checks.
local function IsGearUpgrade(equipLoc, itemLink)
    local slotIds = equipLoc and EQUIP_SLOT_IDS[equipLoc]
    if not slotIds then return false end
    local build = EbonBuilds.Build.GetActive()
    local specKey = build and EbonBuilds.GearScore.SpecKey(build.class, build.spec)
    if not specKey then return false end

    local newScore = EbonBuilds.GearScore.ScoreItem(itemLink, specKey)
    -- For dual slots (rings/trinkets), compare against the WEAKER of the
    -- two currently equipped -- that's the one worth replacing.
    local worstCurrent = nil
    for _, slotId in ipairs(slotIds) do
        local curLink = GetInventoryItemLink("player", slotId)
        local curScore = curLink and EbonBuilds.GearScore.ScoreItem(curLink, specKey) or 0
        if not worstCurrent or curScore < worstCurrent then
            worstCurrent = curScore
        end
    end
    return newScore > (worstCurrent or 0)
end

-- Pure decision function: should this bag item be sold?
-- getItemInfo(link) -> name, _, quality, _, _, itemType, _, _, equipLoc, _, sellPrice
-- (injected for testability, matching the pattern used by
-- AffixItemScan/Talents).
local TRADE_GOODS_TYPE = TRADE_GOODS or "Trade Goods"
local RECIPE_TYPE = RECIPE or "Recipe"

function EbonBuilds.AutoSell.ShouldSell(link, getItemInfo)
    if not link then return false end
    getItemInfo = getItemInfo or GetItemInfo
    local name, _, quality, _, _, itemType, _, _, equipLoc, _, sellPrice = getItemInfo(link)
    if not name then return false end -- not cached client-side yet; skip, don't guess
    if sellPrice and sellPrice > 0 then return false end -- has real value, not junk
    if categories.poorOnly and quality and quality ~= 0 then return false end
    if categories.excludeTradeGoods and itemType == TRADE_GOODS_TYPE then return false end
    if categories.excludeRecipes and itemType == RECIPE_TYPE then return false end
    if EbonBuilds.AutoSell.IsKept(name) then return false end
    if EbonBuilds.AffixItemScan.IsProtectedFromSelling(name) then return false end
    if IsGearUpgrade(equipLoc, link) then return false end
    return true
end

local sellQueue = EbonBuilds.RingBuffer.New(400)
local sellTicker = false
local SELL_INTERVAL = 0.3 -- seconds between individual sells

local function StopSellTicker()
    sellTicker = false
    EbonBuilds.Scheduler.Cancel("autoSell.tick")
    EbonBuilds.RingBuffer.Clear(sellQueue)
end

local function EnsureSellTicker()
    if sellTicker then return end
    sellTicker = true
    EbonBuilds.Scheduler.Every("autoSell.tick", SELL_INTERVAL, function()
        if EbonBuilds.RingBuffer.Count(sellQueue) == 0 or not MerchantFrame or not MerchantFrame:IsShown() then
            StopSellTicker()
            return false
        end
        local next_ = EbonBuilds.RingBuffer.PopOldest(sellQueue)
        if next_ then
            local link = GetContainerItemLink(next_.bag, next_.slot)
            if link and EbonBuilds.AutoSell.ShouldSell(link) then
                UseContainerItem(next_.bag, next_.slot)
            end
        end
        return SELL_INTERVAL
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "AutoSell")
end

local function SellBags()
    if not enabled then return end
    EbonBuilds.RingBuffer.Clear(sellQueue)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and EbonBuilds.AutoSell.ShouldSell(link) then
                EbonBuilds.RingBuffer.Append(sellQueue, { bag = bag, slot = slot })
            end
        end
    end
    if EbonBuilds.RingBuffer.Count(sellQueue) > 0 then
        EnsureSellTicker()
    end
end

------------------------------------------------------------------------
-- Keep-list management window
------------------------------------------------------------------------

local keepListWindow, keepListRows, keepListInput

local function RefreshKeepListWindow()
    if not keepListWindow then return end
    local names = EbonBuilds.AutoSell.GetKeepList()
    for i, row in ipairs(keepListRows) do
        local name = names[i]
        if name then
            row.label:SetText(name)
            row:Show()
        else
            row:Hide()
        end
    end
    if #names == 0 then keepListWindow._emptyState:Show() else keepListWindow._emptyState:Hide() end
end

local function BuildKeepListRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "AutoSell.KeepListRow")
    end
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 24)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    EbonBuilds.Theme.ApplyCard(row)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    local remove = CreateFrame("Button", nil, row)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(remove, "AutoSell.KeepListRowRemove")
    end
    remove:SetSize(18, 18)
    remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    local x = remove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(0.72, 0.72, 0.76)
    remove:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    remove:SetScript("OnLeave", function() x:SetTextColor(0.72, 0.72, 0.76) end)
    remove:SetScript("OnClick", function()
        EbonBuilds.AutoSell.RemoveFromKeepList(row.label:GetText())
        RefreshKeepListWindow()
    end)

    return row
end

local function BuildKeepListWindow()
    local T = EbonBuilds.Theme
    local window = CreateFrame("Frame", "EbonBuildsAutoSellKeepListWindow", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(window, "AutoSell.KeepListWindow")
    end
    window:SetSize(360, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    T.ApplyWindow(window)
    window:Hide()

    local drag = CreateFrame("Frame", nil, window)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "AutoSell.KeepListWindowDrag")
    end
    drag:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() window:StartMoving() end)
    drag:SetScript("OnMouseUp", function() window:StopMovingOrSizing() end)

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -10)
    title:SetText("Auto-Sell Keep List")

    T.CreateCloseButton(window)

    local sub = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText("Items here are never auto-sold, even if they'd otherwise be eligible.")

    local inputWrap = CreateFrame("Frame", nil, window)
    inputWrap:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
    inputWrap:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    inputWrap:SetHeight(24)
    T.ApplyInput(inputWrap)

    keepListInput = CreateFrame("EditBox", nil, inputWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(keepListInput, "AutoSell.KeepListInput")
    end
    keepListInput:SetPoint("TOPLEFT", inputWrap, "TOPLEFT", 7, -3)
    keepListInput:SetPoint("BOTTOMRIGHT", inputWrap, "BOTTOMRIGHT", -7, 3)
    keepListInput:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    keepListInput:SetTextColor(1, 1, 1, 1)
    keepListInput:SetAutoFocus(false)
    keepListInput:SetMaxLetters(80)
    T.WireEditBox(keepListInput, inputWrap)

    local placeholder = inputWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", keepListInput, "LEFT", 0, 0)
    placeholder:SetText("Exact item name...")
    placeholder:SetTextColor(unpack(T.TEXT_MUTED))
    keepListInput:HookScript("OnTextChanged", function(self)
        if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
    end)

    local function AddCurrentInput()
        local text = strtrim(keepListInput:GetText() or "")
        if text == "" then return end
        if EbonBuilds.AutoSell.AddToKeepList(text) then
            keepListInput:SetText("")
            RefreshKeepListWindow()
        end
    end
    keepListInput:SetScript("OnEnterPressed", AddCurrentInput)
    keepListInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addButton = T.CreateButton(window)
    addButton:SetSize(60, 24)
    addButton:SetPoint("LEFT", inputWrap, "RIGHT", 6, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", AddCurrentInput)
    -- inputWrap needs room for the Add button beside it.
    inputWrap:SetPoint("RIGHT", window, "RIGHT", -78, 0)

    local listScroll = CreateFrame("ScrollFrame", nil, window)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(listScroll, "AutoSell.KeepListScroll")
    end
    listScroll:SetPoint("TOPLEFT", inputWrap, "BOTTOMLEFT", 0, -10)
    listScroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 14)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(310)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)

    local scrollBar = T.CreateScrollBar(listScroll)
    scrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", -2, 4)
    T.BindScrollWheel(listScroll, scrollBar, 24)

    local emptyState = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyState:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -6)
    emptyState:SetText("No items on the keep-list yet.")
    window._emptyState = emptyState

    keepListRows = {}
    local MAX_ROWS = 60
    for i = 1, MAX_ROWS do
        local row = BuildKeepListRow(listChild, i)
        row:Hide()
        keepListRows[i] = row
    end
    listChild:SetHeight(MAX_ROWS * 24)

    window:SetScript("OnShow", RefreshKeepListWindow)
    keepListWindow = window
    return window
end

function EbonBuilds.AutoSell.ShowKeepListWindow()
    if not (EbonBuilds.Theme and EbonBuilds.Theme.ApplyWindow) then return end
    if not keepListWindow then BuildKeepListWindow() end
    keepListWindow:Show()
end

function EbonBuilds.AutoSell.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        enabled = EbonBuilds.Database.GetCharacterPreference("autoSellJunkEnabled")
    elseif EbonBuildsCharDB.autoSellJunkEnabled ~= nil then
        enabled = EbonBuildsCharDB.autoSellJunkEnabled == true
    end
    LoadCategories()
    local onMerchantEvent = EbonBuilds.ErrorLog.Protect("AutoSell", function(event)
        if event == "MERCHANT_SHOW" then
            SellBags()
        else -- MERCHANT_CLOSED: stop immediately, don't wait for the next poll
            EbonBuilds.RingBuffer.Clear(sellQueue)
            if sellTicker then StopSellTicker() end
        end
    end)
    EbonBuilds.WoWEvents.On("MERCHANT_SHOW", onMerchantEvent, "AutoSell")
    EbonBuilds.WoWEvents.On("MERCHANT_CLOSED", onMerchantEvent, "AutoSell")
end

------------------------------------------------------------------------
-- Self-tests (see core/Debug.lua) -- a stub getItemInfo means these don't
-- need a real client, so they run in tests/test_selftests.lua too.
------------------------------------------------------------------------

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    local function StubInfo(quality, itemType, equipLoc, sellPrice)
        return function(link)
            return link, link, quality, 1, 1, itemType, "", 1, equipLoc, "", sellPrice
        end
    end

    EbonBuilds.Debug.RegisterTest("AutoSell: keep-list overrides an otherwise-sellable item", function()
        EbonBuilds.AutoSell.AddToKeepList("Ruined Pelt")
        local should = EbonBuilds.AutoSell.ShouldSell("Ruined Pelt", StubInfo(0, "Junk", "", 0))
        EbonBuilds.AutoSell.RemoveFromKeepList("Ruined Pelt")
        if should then error("kept item was still marked sellable") end
        local afterRemove = EbonBuilds.AutoSell.ShouldSell("Ruined Pelt", StubInfo(0, "Junk", "", 0))
        if not afterRemove then error("item stayed protected after being removed from the keep-list") end
    end)

    EbonBuilds.Debug.RegisterTest("AutoSell: keep-list matching is case-insensitive", function()
        EbonBuilds.AutoSell.AddToKeepList("Broken Fang")
        local kept = EbonBuilds.AutoSell.IsKept("broken fang")
        EbonBuilds.AutoSell.RemoveFromKeepList("Broken Fang")
        if not kept then error("keep-list lookup was case-sensitive") end
    end)

    EbonBuilds.Debug.RegisterTest("AutoSell: poorOnly category restricts to Poor quality", function()
        EbonBuilds.AutoSell.SetCategory("poorOnly", true)
        local grayOk = EbonBuilds.AutoSell.ShouldSell("Gray Item", StubInfo(0, "Junk", "", 0))
        local whiteBlocked = EbonBuilds.AutoSell.ShouldSell("White Item", StubInfo(1, "Junk", "", 0))
        EbonBuilds.AutoSell.SetCategory("poorOnly", false)
        if not grayOk then error("Poor-quality zero-value item was blocked with poorOnly on") end
        if whiteBlocked then error("Common-quality zero-value item was not blocked with poorOnly on") end
    end)

    EbonBuilds.Debug.RegisterTest("AutoSell: excludeTradeGoods/excludeRecipes default on", function()
        local tradeGood = EbonBuilds.AutoSell.ShouldSell("Some Ore", StubInfo(1, TRADE_GOODS_TYPE, "", 0))
        local recipe = EbonBuilds.AutoSell.ShouldSell("Some Recipe", StubInfo(1, RECIPE_TYPE, "", 0))
        if tradeGood then error("Trade Goods item was sellable despite excludeTradeGoods defaulting on") end
        if recipe then error("Recipe item was sellable despite excludeRecipes defaulting on") end
    end)
end
