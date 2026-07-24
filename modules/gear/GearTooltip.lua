local addonName, EbonBuilds = ...

-- EbonBuilds: modules/gear/GearTooltip.lua
-- Responsibility: item-tooltip upgrade line. Appends one line to item
-- tooltips saying whether the hovered item scores as an upgrade over
-- what's currently equipped, using GearScore's stat weights and the
-- active build's class/spec. This is the wiring GearScore.UpgradeInfo
-- existed for -- the scoring API sat fully built but uncalled until now.

EbonBuilds.GearTooltip = {}

local hooked = false

function EbonBuilds.GearTooltip.IsEnabled()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        return EbonBuilds.Database.GetCharacterPreference("gearTooltipEnabled")
    end
    return EbonBuildsCharDB and EbonBuildsCharDB.gearTooltipEnabled == true
end

function EbonBuilds.GearTooltip.SetEnabled(on)
    local enabled = on and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("gearTooltipEnabled", enabled)
    else
        EbonBuildsCharDB.gearTooltipEnabled = enabled
    end
end

-- Resolves the spec weight key from the ACTIVE BUILD, not the player's
-- current talents: this addon's whole model is "the build is the source
-- of truth," and it also means you can evaluate drops for the spec
-- you're building toward, not the one you happen to be respecced into.
local function ActiveSpecKey()
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build or not build.class then return nil end
    return EbonBuilds.GearScore.SpecKey(build.class, build.spec)
end

-- The actual tooltip augmentation. Deliberately per-call cheap: two
-- early bails (toggle, active build) before any item work happens, so
-- an idle hover with the feature off costs one boolean read.
local function AugmentTooltip(tooltip)
    if not EbonBuilds.GearTooltip.IsEnabled() then return end
    local specKey = ActiveSpecKey()
    if not specKey then return end

    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    local itemName = itemLink:match("%[(.-)%]")
    if itemName and EbonBuilds.AuctionatorBridge and EbonBuilds.AuctionatorBridge.AppendTooltipLines then
        local base, rank = EbonBuilds.AffixItemScan and EbonBuilds.AffixItemScan.ExtractSuffix(itemName)
        local affixName = base and rank and (base .. " " .. rank) or nil
        EbonBuilds.AuctionatorBridge.AppendTooltipLines(tooltip, itemLink, affixName)
    end

    local info = EbonBuilds.GearScore.UpgradeInfo(itemLink, specKey)
    if not info then return end  -- not equippable, or no weights for this spec

    local teal = EbonBuilds.Theme.PRESENCE_TEAL
    if info.slotEmpty then
        tooltip:AddLine("EbonBuilds: upgrade (slot is empty)", teal[1], teal[2], teal[3])
    elseif info.isUpgrade then
        tooltip:AddLine(string.format("EbonBuilds: upgrade (+%.0f vs equipped)", info.delta), teal[1], teal[2], teal[3])
    else
        tooltip:AddLine(string.format("EbonBuilds: not an upgrade (%.0f vs equipped)", info.delta), 0.62, 0.62, 0.66)
    end
    tooltip:Show()  -- re-measure so the added line isn't clipped
end

-- Exposed for tests: same function the hooks call, no widget needed.
EbonBuilds.GearTooltip._AugmentForTests = AugmentTooltip

function EbonBuilds.GearTooltip.Init()
    -- Database.Init owns the normal default. Keep the fallback for isolated
    -- module loading and older integrations that do not expose Database yet.
    if not (EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference)
        and EbonBuildsCharDB.gearTooltipEnabled == nil then
        EbonBuildsCharDB.gearTooltipEnabled = true
    end

    if hooked then return end
    hooked = true

    -- HookScript keeps every other addon's tooltip handler intact --
    -- same guarantee Theme.CreateButton's ClickTrace hook relies on.
    -- Wrapped in pcall via a shared closure: a tooltip that errors here
    -- would otherwise break hovering for the rest of the session.
    local function SafeAugment(tooltip)
        local ok, err = pcall(AugmentTooltip, tooltip)
        if not ok and EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Protect then
            -- Route through Protect's recording path so it lands in the
            -- Error log window rather than vanishing (see 3.10's lesson).
            EbonBuilds.ErrorLog.Protect("GearTooltip", function() error(err, 0) end)()
        end
    end

    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", SafeAugment)
    end
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        ItemRefTooltip:HookScript("OnTooltipSetItem", SafeAugment)
    end
end
