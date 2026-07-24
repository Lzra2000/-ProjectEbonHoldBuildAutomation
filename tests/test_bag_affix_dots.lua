-- BagAffixDots bag-addon hook regression (Bagnon + Combuctor, Tuller lineage).
-- Static source checks plus a minimal Init() stub that proves each addon's
-- ItemSlot.Update is hooked without touching ContainerFrame_Update ownership.
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("BAG_AFFIX_DOTS FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertTrue(value, message)
    if not value then fail(message) end
end

local function read(path)
    local file, err = io.open(path, "rb")
    if not file then fail(err or ("unable to read " .. path)) end
    local text = file:read("*a")
    file:close()
    return text
end

local src = read("modules/ui/BagAffixDots.lua")
assertTrue(src:find('"Bagnon"', 1, true), "BagAffixDots no longer feature-detects Bagnon")
assertTrue(src:find('"Combuctor"', 1, true), "BagAffixDots does not feature-detect Combuctor")
assertTrue(src:find("ItemSlot or", 1, true) or src:find("ItemSlot or addon.Item", 1, true),
    "BagAffixDots lost ItemSlot/Item class resolution")
assertTrue(src:find("hooksecurefunc(itemClass, \"Update\"", 1, true)
    or src:find('hooksecurefunc(itemClass, "Update"', 1, true),
    "BagAffixDots does not hooksecurefunc itemClass Update")
assertTrue(src:find("IsCached", 1, true), "BagAffixDots dropped cached-view short-circuit")
assertTrue(src:find("ContainerFrame_Update", 1, true),
    "BagAffixDots no longer hooks default ContainerFrame_Update")

-- Runtime: Init must hook Combuctor.ItemSlot.Update when Combuctor is loaded,
-- and must still hook ContainerFrame_Update for default bags.
local hooks = {}
function hooksecurefunc(owner, methodName, postHook)
    if type(owner) == "string" then
        hooks[#hooks + 1] = { kind = "global", name = owner, hook = methodName or postHook }
        return
    end
    hooks[#hooks + 1] = { kind = "method", owner = owner, name = methodName, hook = postHook }
end

local loadedAddons = { Combuctor = true }
function IsAddOnLoaded(name)
    return loadedAddons[name] == true
end

function GetContainerItemLink() return nil end
function GetItemInfo() return nil end
function GetInventoryItemLink() return nil end
NUM_CONTAINER_FRAMES = 0
ContainerFrame_Update = function() end

local addon = {}
-- Minimal WoWEvents so late-load path is available but unused when already loaded.
addon.WoWEvents = {
    On = function() return "token" end,
    Off = function() end,
}

local combuctorItemSlot = {
    Update = function() end,
}
_G.Combuctor = { ItemSlot = combuctorItemSlot }
_G.Bagnon = nil

local chunk, err = loadfile("modules/ui/BagAffixDots.lua")
if not chunk then fail(err) end
local ok, result = pcall(chunk, "EbonBuilds", addon)
if not ok then fail("load BagAffixDots: " .. tostring(result)) end
assertTrue(addon.BagAffixDots and addon.BagAffixDots.Init, "BagAffixDots.Init missing after load")

addon.BagAffixDots.Init()

local sawContainer = false
local sawCombuctorUpdate = false
local sawBagnonUpdate = false
for _, h in ipairs(hooks) do
    if h.kind == "global" and h.name == "ContainerFrame_Update" then
        sawContainer = true
    elseif h.kind == "method" and h.name == "Update" and h.owner == combuctorItemSlot then
        sawCombuctorUpdate = true
    elseif h.kind == "method" and h.name == "Update" and _G.Bagnon
        and (h.owner == _G.Bagnon.ItemSlot or h.owner == _G.Bagnon.Item) then
        sawBagnonUpdate = true
    end
end

assertTrue(sawContainer, "Init did not hook ContainerFrame_Update (default bags)")
assertTrue(sawCombuctorUpdate, "Init did not hook Combuctor.ItemSlot.Update")
assertTrue(not sawBagnonUpdate, "Init hooked Bagnon when Bagnon was not loaded")

-- Second pass: Bagnon-only load must hook Bagnon and leave Combuctor alone.
hooks = {}
loadedAddons = { Bagnon = true }
local bagnonItemSlot = { Update = function() end }
_G.Bagnon = { ItemSlot = bagnonItemSlot }
_G.Combuctor = nil

-- Re-load into a fresh addon table so Init's local hook flags reset.
local addon2 = {
    WoWEvents = { On = function() return "token" end, Off = function() end },
}
chunk, err = loadfile("modules/ui/BagAffixDots.lua")
if not chunk then fail(err) end
ok, result = pcall(chunk, "EbonBuilds", addon2)
if not ok then fail("reload BagAffixDots: " .. tostring(result)) end
addon2.BagAffixDots.Init()

sawContainer, sawCombuctorUpdate, sawBagnonUpdate = false, false, false
for _, h in ipairs(hooks) do
    if h.kind == "global" and h.name == "ContainerFrame_Update" then
        sawContainer = true
    elseif h.kind == "method" and h.name == "Update" and h.owner == combuctorItemSlot then
        sawCombuctorUpdate = true
    elseif h.kind == "method" and h.name == "Update" and h.owner == bagnonItemSlot then
        sawBagnonUpdate = true
    end
end

assertTrue(sawContainer, "Bagnon-only Init dropped ContainerFrame_Update")
assertTrue(sawBagnonUpdate, "Init did not hook Bagnon.ItemSlot.Update")
assertTrue(not sawCombuctorUpdate, "Init hooked Combuctor when Combuctor was not loaded")

print("BagAffixDots bag-addon hooks passed: default bags + Bagnon + Combuctor feature detection.")
