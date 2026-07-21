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
-- visibility short-circuit). This module only marks items -- it never acts
-- on them; see modules/vendor/AutoSell.lua for the module that actually
-- sells things.

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

    local _, _, quality = GetContainerItemInfo(bag, slot)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not equipLoc or equipLoc == "" then return nil end -- not gear; nothing else to flag

    local bind = GetBindLine(bag, slot)
    if bind == "boe" then return "boe_unbound" end
    if IsDisenchantCandidate(link, quality, equipLoc) then return "disenchant_candidate" end
    return nil
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
            local link = GetContainerItemLink(bag, slot)
            if button._ebbCachedLink ~= link or button._ebbDotVersion ~= dotVersion then
                button._ebbCachedLink  = link
                button._ebbDotVersion  = dotVersion
                SetButtonDot(button, DecideDot(bag, slot, link))
            end
        end
    end
end

-- Forces every currently-visible default bag frame to redraw its dots
-- (e.g. after the learned-affix list updates from the server, or the
-- show/hide setting changes). Cheap: only iterates shown frames.
function EbonBuilds.BagAffixDots.RefreshAll()
    dotVersion = dotVersion + 1
    for i = 1, (NUM_CONTAINER_FRAMES or 12) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            UpdateFrame(frame)
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
end
