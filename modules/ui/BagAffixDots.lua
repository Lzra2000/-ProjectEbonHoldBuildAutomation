local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/BagAffixDots.lua
-- Draws a colored dot on bag items worth a second look:
--   red    -- carries a gear affix line you haven't learned at all
--   purple -- carries an affix you know a different rank of (upgrade)
--   blue   -- Bind on Equip and still unbound (tradeable/auctionable --
--             equipping, sending to a vendor, or disenchanting it forfeits
--             that option, so it's worth a second look before either)
--   teal   -- likely worth disenchanting rather than selling: soulbound
--             Uncommon/Rare gear that doesn't score as an upgrade for the
--             active build's spec
-- Hooks the default Blizzard container frame the same low-cost way
-- AutoDelete's proven affix-dot feature does (per-slot link-change cache,
-- visibility short-circuit). When Bagnon or Combuctor (same Tuller lineage)
-- is installed it replaces the default container frames entirely
-- (ContainerFrame_Update never fires for its window), so this module also
-- feature-detects those addons and hooks their ItemSlot update path -- see
-- the "Bagnon / Combuctor compatibility" section below.
-- This module only marks items -- it never acts on them; see
-- modules/vendor/AutoSell.lua for the module that actually sells things.

EbonBuilds.BagAffixDots = {}

local DOT_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DOT_SIZE     = 9
local BACKING_SIZE = 12

local COLORS = {
    missing_new         = { 0.90, 0.15, 0.15 }, -- red
    missing_upgrade     = { 0.64, 0.21, 0.93 }, -- purple
    boe_unbound         = { 0.20, 0.55, 0.95 }, -- blue
    disenchant_candidate = { 0.20, 0.80, 0.60 }, -- teal
}

-- Checked in this order; the first match wins (only one dot per item).
local PRIORITY = { "missing_new", "missing_upgrade", "boe_unbound", "disenchant_candidate" }

local enabled = true
local dotVersion = 0

function EbonBuilds.BagAffixDots.SetEnabled(on)
    enabled = on and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("bagAffixDotsEnabled", enabled)
    elseif EbonBuildsCharDB then
        EbonBuildsCharDB.bagAffixDotsEnabled = enabled
    end
    dotVersion = dotVersion + 1
    EbonBuilds.BagAffixDots.RefreshAll()
end

function EbonBuilds.BagAffixDots.IsEnabled()
    return enabled
end

local function SetButtonDot(button, classification)
    local dot  = button._ebbAffixDot
    local back = button._ebbAffixBacking
    local color = classification and COLORS[classification]

    if not enabled or not color then
        if dot then dot:Hide() end
        if back then back:Hide() end
        return
    end

    if not back then
        back = button:CreateTexture(nil, "ARTWORK")
        back:SetTexture(DOT_TEXTURE)
        back:SetSize(BACKING_SIZE, BACKING_SIZE)
        button._ebbAffixBacking = back
    end
    back:ClearAllPoints()
    back:SetPoint("CENTER", button, "CENTER", 0, 0)
    back:SetVertexColor(0, 0, 0, 1)
    back:Show()

    if not dot then
        dot = button:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(DOT_TEXTURE)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        button._ebbAffixDot = dot
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", back, "CENTER", 0, 0)
    dot:SetVertexColor(color[1], color[2], color[3], 1)
    dot:Show()
end

-- Lazily-created hidden tooltip used only to read bind status off an item
-- (WoW's item APIs don't expose "is this still tradeable" directly -- the
-- tooltip text is the only source). Kept as a singleton like GearTooltip's
-- own scanning frame; ITEM_BIND_ON_EQUIP/ITEM_SOULBOUND are Blizzard's own
-- localized globals, so this doesn't hardcode English tooltip text.
local scanTip

local function GetBindLine(bag, slot)
    if not (ITEM_BIND_ON_EQUIP or ITEM_SOULBOUND) then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EbonBuildsBagDotsScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local fs = _G["EbonBuildsBagDotsScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text == ITEM_SOULBOUND then return "bound" end
        if text == ITEM_BIND_ON_EQUIP then return "boe" end
    end
    return "other" -- readable but neither line found (BoP already worn, unique, etc.)
end

-- A soulbound Uncommon/Rare piece of gear that isn't an upgrade for the
-- active build's spec is a reasonable disenchant candidate -- reuses the
-- same spec-scoring GearScore already does for AutoSell's upgrade check.
local function IsDisenchantCandidate(link, quality, equipLoc)
    if not (quality == 2 or quality == 3) then return false end -- Uncommon/Rare only
    if not equipLoc or equipLoc == "" then return false end -- not equippable gear
    if not (EbonBuilds.Build and EbonBuilds.GearScore) then return false end
    local build = EbonBuilds.Build.GetActive()
    local specKey = build and EbonBuilds.GearScore.SpecKey(build.class, build.spec)
    if not specKey then return false end
    local slotIds = EbonBuilds.GearScore.INVTYPE_SLOTS and EbonBuilds.GearScore.INVTYPE_SLOTS[equipLoc]
    if not slotIds then return false end
    for _, slotId in ipairs(slotIds) do
        local curLink = GetInventoryItemLink("player", slotId)
        if not curLink or EbonBuilds.GearScore.IsUpgrade(link, curLink, specKey) then
            return false -- either an empty slot or an actual upgrade -- not disenchant fodder
        end
    end
    return true
end

-- Decides what (if anything) to draw for a bag slot's current item.
local function DecideDot(bag, slot, link)
    if not link or not enabled then return nil end
    local name = link:match("%[(.-)%]")
    local affixClass = name and EbonBuilds.AffixItemScan.Classify(name)
    if affixClass then return affixClass end

    -- GetItemInfo quality is the 3rd return in 3.3.5a. Do NOT take quality from
    -- GetContainerItemInfo's 3rd return -- that is `locked` (boolean); quality is 4th.
    local _, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not equipLoc or equipLoc == "" then return nil end -- not gear; nothing else to flag

    local bind = GetBindLine(bag, slot)
    if bind == "boe" then return "boe_unbound" end
    if IsDisenchantCandidate(link, quality, equipLoc) then return "disenchant_candidate" end
    return nil
end

-- Shared per-button update with a change cache: recomputes the dot only when
-- the slot's link, the button's bag/slot assignment (Bagnon/Combuctor recycle
-- buttons across slots), or the global dot version changed.
local function UpdateButton(button, bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if button._ebbCachedLink ~= link
        or button._ebbCachedBag ~= bag
        or button._ebbCachedSlot ~= slot
        or button._ebbDotVersion ~= dotVersion then
        button._ebbCachedLink = link
        button._ebbCachedBag  = bag
        button._ebbCachedSlot = slot
        button._ebbDotVersion = dotVersion
        SetButtonDot(button, DecideDot(bag, slot, link))
    end
end

local function UpdateFrame(frame)
    if not frame or not frame:IsShown() then return end
    local name = frame:GetName()
    if not name then return end
    local bag = frame:GetID()
    local size = frame.size or 0
    -- Slot buttons are reverse-indexed: "Item1" is the LAST visual slot.
    for slot = 1, size do
        local button = _G[name .. "Item" .. (size - slot + 1)]
        if button then
            UpdateButton(button, bag, slot)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bagnon / Combuctor compatibility (issue #37 + Combuctor follow-up)
--
-- Bagnon and Combuctor (WotLK 2.x Tuller line used on 3.3.5a) each build a
-- single-window bag out of their own ItemSlot buttons; the default
-- ContainerFrames stay hidden and ContainerFrame_Update never runs, so the
-- hook above draws nothing. Both expose the item-button class as
-- `<Addon>.ItemSlot` (a plain method table; some forks use `.Item`), and every
-- visual refresh funnels through `Update` -- hooking that table entry with
-- hooksecurefunc covers opening the window, item changes, and button recycling.
--
-- Both guarantee `button:GetParent():GetID() == bag` (the shared "dummy bag"
-- hack for ContainerFrameItemButtonTemplate) and `button:GetID() == slot`,
-- wrapped as `button:GetBag()`; that maps straight onto the live-container
-- APIs DecideDot already uses. Verified against Combuctor 2.2.2
-- (TrinityCore/wow_335a_addons Combuctor/item.lua) -- same shape as Bagnon.
-- ---------------------------------------------------------------------------

-- Addons that replace default bags with a Tuller-lineage ItemSlot:Update path.
local BAG_ADDONS = { "Bagnon", "Combuctor" }

-- Weak-keyed registry of every bag-addon button we've dotted, so RefreshAll
-- can redraw them without knowing each addon's frame layout.
local bagAddonButtons

-- Per-addon "already hooked" flags (Bagnon and Combuctor are mutually exclusive
-- in practice, but hooking both is harmless if someone somehow loads both).
local bagAddonHooked = {}

local function UpdateBagAddonButton(button)
    -- hooksecurefunc fires even when Update() short-circuited on a hidden
    -- button; mirror its visibility check.
    if not button:IsVisible() then return end
    bagAddonButtons[button] = true

    -- Bagnon_Forever / Combuctor cached views of other characters (or the bank
    -- while away) are not live containers; GetContainerItemLink would lie.
    if button.IsCached and button:IsCached() then
        button._ebbCachedLink = nil
        SetButtonDot(button, nil)
        return
    end

    local bag = button.GetBag and button:GetBag()
        or (button:GetParent() and button:GetParent():GetID())
    if not bag then return end
    UpdateButton(button, bag, button:GetID())
end

-- Hooks one bag addon's item-button class once it exists. Returns true when
-- hooked (or already hooked), false if that addon isn't ready / isn't known.
local function TryHookBagAddon(addonName)
    if bagAddonHooked[addonName] then return true end
    local addon = _G[addonName]
    -- `ItemSlot` in the standard 2.x WotLK line; `Item` in some later forks.
    local itemClass = addon and (addon.ItemSlot or addon.Item)
    if not (type(itemClass) == "table" and type(itemClass.Update) == "function") then
        return false
    end
    if not bagAddonButtons then
        -- Weak keys: buttons the addon frees can be collected without us holding on.
        bagAddonButtons = setmetatable({}, { __mode = "k" })
    end
    bagAddonHooked[addonName] = true
    hooksecurefunc(itemClass, "Update", UpdateBagAddonButton)
    return true
end

-- Forces every currently-visible bag frame (default, Bagnon, or Combuctor) to
-- redraw its dots (e.g. after the learned-affix list updates from the server,
-- or the show/hide setting changes). Cheap: only iterates shown frames/buttons.
function EbonBuilds.BagAffixDots.RefreshAll()
    dotVersion = dotVersion + 1
    for i = 1, (NUM_CONTAINER_FRAMES or 12) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            UpdateFrame(frame)
        end
    end
    if bagAddonButtons then
        for button in pairs(bagAddonButtons) do
            if button:IsVisible() then
                UpdateBagAddonButton(button)
            end
        end
    end
end

function EbonBuilds.BagAffixDots.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        enabled = EbonBuilds.Database.GetCharacterPreference("bagAffixDotsEnabled")
    elseif EbonBuildsCharDB and EbonBuildsCharDB.bagAffixDotsEnabled ~= nil then
        enabled = EbonBuildsCharDB.bagAffixDotsEnabled == true
    end
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", UpdateFrame)
    end

    -- Bagnon/Combuctor load before EbonBuilds in normal alphabetical addon
    -- order, so this usually hooks immediately; the ADDON_LOADED listener
    -- covers a late/on-demand load and unregisters itself once every known
    -- bag addon that can load has either hooked or been observed.
    local pending = {}
    for _, name in ipairs(BAG_ADDONS) do
        if IsAddOnLoaded and IsAddOnLoaded(name) then
            TryHookBagAddon(name)
        end
        if not bagAddonHooked[name] then
            pending[name] = true
        end
    end
    if next(pending) and EbonBuilds.WoWEvents then
        local token
        token = EbonBuilds.WoWEvents.On("ADDON_LOADED", function(_, name)
            if pending[name] and TryHookBagAddon(name) then
                pending[name] = nil
                if not next(pending) and token then
                    EbonBuilds.WoWEvents.Off(token)
                    token = nil
                end
            end
        end, "BagAffixDots")
    end
end
