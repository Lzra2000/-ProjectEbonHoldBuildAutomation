-- ProjectEbonholdAffixBridge soft-dependency tests (Lua 5.1 / headless).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("PE_AFFIX_BRIDGE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertTrue(value, message)
    if not value then fail(message) end
end

local function assertEq(a, b, message)
    if a ~= b then
        fail((message or "not equal") .. ": " .. tostring(a) .. " vs " .. tostring(b))
    end
end

local loadedAddons = {}
function IsAddOnLoaded(name)
    return loadedAddons[name] == true
end

function LoadAddOn() end

local merchantShown = false
function ShowUIPanel(frame)
    if frame == MerchantFrame then
        merchantShown = true
    end
end

MerchantFrame = {
    IsShown = function()
        return merchantShown
    end,
}

local addon = {}
local chunk, err = loadfile("modules/integration/ProjectEbonholdAffixBridge.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk, "EbonBuilds", addon)
if not ok then fail("load ProjectEbonholdAffixBridge: " .. tostring(loadErr)) end

local Bridge = addon.ProjectEbonholdAffixBridge
assertTrue(Bridge, "ProjectEbonholdAffixBridge table missing")

assertTrue(not Bridge.IsProjectEbonholdLoaded(), "PE not loaded initially")
assertTrue(not Bridge.IsExtractionAvailable(), "extraction unavailable without PE")
assertTrue(not Bridge.IsMerchantAffixAvailable(), "vendor unavailable without PE")

local openOk, reason = Bridge.OpenExtractionUi()
assertTrue(not openOk and reason == "missing-pe", "missing PE for extraction")

openOk, reason = Bridge.OpenMerchantUi()
assertTrue(not openOk and reason == "missing-pe", "missing PE for merchant")

loadedAddons.ProjectEbonhold = true
assertTrue(Bridge.IsProjectEbonholdLoaded(), "PE loaded")

assertTrue(not Bridge.IsExtractionAvailable(), "extraction service still absent")
openOk, reason = Bridge.OpenExtractionUi()
assertTrue(not openOk and reason == "no-ui", "no extraction UI")

ExtractionService = { RequestLearnedAffixes = function() end }
assertTrue(Bridge.IsExtractionAvailable(), "extraction service present")
assertTrue(not Bridge.IsExtractionUiAvailable(), "frame still absent")

openOk, reason = Bridge.OpenExtractionUi()
assertTrue(not openOk and reason == "no-ui", "still no extraction frame")

EbonholdExtractionFrame = {
    Show = function() end,
    Hide = function() end,
    sidePanel = { searchBox = { SetText = function() end } },
}
ExtractionUI = { ShowSidePanel = function() end }

assertTrue(Bridge.IsExtractionUiAvailable(), "extraction UI available")
openOk, reason = Bridge.OpenExtractionUi({ affixName = "Keen Strikes III" })
assertTrue(openOk and reason == "ok", "open extraction with affix filter")

assertTrue(not Bridge.IsMerchantAffixAvailable(), "vendor popup still absent")
openOk, reason = Bridge.OpenMerchantUi()
assertTrue(not openOk and reason == "no-affix-vendor", "no vendor UI at all")

ItemPurchasePopup = { ShowPurchase = function() end }
assertTrue(Bridge.IsMerchantAffixAvailable(), "vendor popup available")

merchantShown = false
openOk, reason = Bridge.OpenMerchantUi()
assertTrue(not openOk and reason == "no-merchant", "merchant closed with vendor UI present")

merchantShown = true
openOk, reason = Bridge.OpenMerchantUi()
assertTrue(openOk and reason == "ok", "merchant already open")

print("PE_AFFIX_BRIDGE OK")
