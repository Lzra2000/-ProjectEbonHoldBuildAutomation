local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/ProjectEbonholdAffixBridge.lua
-- Soft integration with ProjectEbonhold affix acquisition surfaces:
-- ExtractionService / Enchanted Anvil (EbonholdExtractionFrame) and
-- ItemPurchasePopup on MerchantFrame when present. Every entry point fails
-- closed when ProjectEbonhold or the target UI is absent.

EbonBuilds.ProjectEbonholdAffixBridge = {}
local Bridge = EbonBuilds.ProjectEbonholdAffixBridge

local EXTRACTION_FRAME = "EbonholdExtractionFrame"

local function ExtractionService()
    return _G.ExtractionService
end

local function ExtractionUi()
    return _G.ExtractionUI
end

local function ExtractionFrame()
    return _G[EXTRACTION_FRAME]
end

local function ItemPurchasePopup()
    return _G.ItemPurchasePopup
end

function Bridge.IsProjectEbonholdLoaded()
    return IsAddOnLoaded and (
        IsAddOnLoaded("ProjectEbonhold")
        or IsAddOnLoaded("ProjectEbonholdEnhanced")
    )
end

function Bridge.IsExtractionAvailable()
    if not Bridge.IsProjectEbonholdLoaded() then return false end
    local service = ExtractionService()
    return type(service) == "table"
        and type(service.RequestLearnedAffixes) == "function"
end

function Bridge.IsExtractionUiAvailable()
    if not Bridge.IsExtractionAvailable() then return false end
    local frame = ExtractionFrame()
    return type(frame) == "table"
        and type(frame.Show) == "function"
        and type(frame.Hide) == "function"
end

function Bridge.IsMerchantAffixAvailable()
    if not Bridge.IsProjectEbonholdLoaded() then return false end
    local popup = ItemPurchasePopup()
    return type(popup) == "table"
        and type(popup.ShowPurchase) == "function"
end

function Bridge.IsMerchantOpen()
    return MerchantFrame and type(MerchantFrame.IsShown) == "function"
        and MerchantFrame:IsShown()
end

function Bridge.OpenExtractionUi(opts)
    opts = opts or {}
    if not Bridge.IsExtractionUiAvailable() then
        if not Bridge.IsProjectEbonholdLoaded() then
            return false, "missing-pe"
        end
        return false, "no-ui"
    end

    local service = ExtractionService()
    if service and type(service.RequestLearnedAffixes) == "function" then
        pcall(service.RequestLearnedAffixes)
    end

    local frame = ExtractionFrame()
    frame:Show()

    if opts.affixName and opts.affixName ~= "" then
        local ui = ExtractionUi()
        if ui and type(ui.ShowSidePanel) == "function" then
            ui.ShowSidePanel()
            local sidePanel = frame.sidePanel
            if sidePanel and sidePanel.searchBox
                and type(sidePanel.searchBox.SetText) == "function" then
                sidePanel.searchBox:SetText(tostring(opts.affixName))
            end
        end
    end

    return true, "ok"
end

function Bridge.OpenMerchantUi()
    if not Bridge.IsProjectEbonholdLoaded() then
        return false, "missing-pe"
    end
    if not Bridge.IsMerchantAffixAvailable() then
        return false, "no-affix-vendor"
    end
    if Bridge.IsMerchantOpen() then
        return true, "ok"
    end
    return false, "no-merchant"
end

function Bridge.Init()
    if EbonBuilds.WoWEvents then
        EbonBuilds.WoWEvents.On("ADDON_LOADED", function(_, name)
            if name == "ProjectEbonhold" or name == "ProjectEbonholdEnhanced" then
                if EbonBuilds.AffixView and EbonBuilds.AffixView.RefreshIfMounted then
                    EbonBuilds.AffixView.RefreshIfMounted()
                end
            end
        end, "ProjectEbonholdAffixBridge", false, true)
    end
end
