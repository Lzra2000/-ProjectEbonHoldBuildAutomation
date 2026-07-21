-- Regression coverage for native level-up Echo controls. Autopilot must hide
-- every known native choice entry point without depending on action observers,
-- and must restore ProjectEbonhold's own renderer on every fallback path.
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("NATIVE CHOICE GUARD FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end
local function assertTrue(value, message) if not value then fail(message) end end
local function assertFalse(value, message) if value then fail(message) end end

EbonBuildsDB = { globalSettings = { evalDelay = 2 } }
EbonBuildsCharDB = {}

local function NewFrame(parent)
    local frame = { shown = false, mouseEnabled = true, parent = parent, hooks = {} }
    function frame:Show()
        self.shown = true
        local hook = self.hooks.OnShow
        if hook then hook(self) end
    end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled == true end
    function frame:GetParent() return self.parent end
    function frame:HookScript(name, callback) self.hooks[name] = callback end
    return frame
end

ProjectEbonholdPerkFrame = NewFrame(nil)
local echoCard = NewFrame(ProjectEbonholdPerkFrame)
PerkChooseButton = NewFrame(nil)
PerkHideButton = NewFrame(ProjectEbonholdPerkFrame)

local tooltipHideCount = 0
GameTooltip = {
    owner = echoCard,
    GetOwner = function(self) return self.owner end,
    Hide = function(self) tooltipHideCount = tooltipHideCount + 1; self.owner = nil end,
}

local choices = { { spellId = 1001, quality = 0 }, { spellId = 1002, quality = 1 } }
local nativeShowCount = 0
ProjectEbonhold = {
    PerkUI = {
        Show = function()
            nativeShowCount = nativeShowCount + 1
            ProjectEbonholdPerkFrame:Show()
            PerkChooseButton:EnableMouse(true)
            PerkHideButton:EnableMouse(true)
            PerkChooseButton:Show()
            PerkHideButton:Show()
        end,
        Hide = function()
            ProjectEbonholdPerkFrame:Hide()
            PerkChooseButton:Hide()
            PerkHideButton:Hide()
        end,
        ResetSelection = function() end,
        UpdateSinglePerk = function() end,
    },
    PerkService = { GetCurrentChoice = function() return choices end },
}

function hooksecurefunc(owner, methodName, postHook)
    local original = owner[methodName]
    owner[methodName] = function(...)
        local results = { original(...) }
        postHook(...)
        return unpack(results)
    end
end

local activeBuild = { id = "build-1", stats = {} }
local automationEnabled = true
local trainingEnabled = false
local scheduled = {}
local listeners = {}

local addon = {
    Build = {
        GetActive = function() return activeBuild end,
        IsAutomationEnabled = function() return automationEnabled end,
    },
    ManualTraining = { IsEnabled = function() return trainingEnabled end },
    ProjectAPI = { GetCurrentChoice = function() return choices end },
    Scheduler = {
        CRITICAL = 1, INTERACTIVE = 2,
        After = function(id, _, callback) scheduled[id] = callback; return true end,
        Cancel = function(id) scheduled[id] = nil; return true end,
    },
    EventHub = {
        On = function(eventName, callback) listeners[eventName] = callback; return true end,
    },
    Toast = { Show = function() end },
}

local chunk, err = loadfile("modules/automation/Automation.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk, "EbonBuilds", addon)
if not ok then fail(loadErr) end
assertTrue(addon.Automation.Init(), "Automation observer failed to initialize")

-- Active Autopilot hides both possible entry buttons, the root card surface,
-- and any tooltip owned by a native Echo card.
ProjectEbonhold.PerkUI.Show(choices)
assertFalse(PerkChooseButton:IsShown(), "compact Echo button remained visible")
assertFalse(PerkHideButton:IsShown(), "native Show/Hide Echo button remained visible")
assertFalse(ProjectEbonholdPerkFrame:IsShown(), "native Echo card surface remained visible")
assertTrue(addon.Automation._IsNativeChoiceSuppressedForTests(), "guard state was not set")
assertTrue(tooltipHideCount == 1, "native Echo tooltip was not dismissed")

-- A later direct Show() from the base addon is caught by the installed OnShow
-- guard rather than exposing a clickable control between evaluations.
PerkChooseButton:Show()
PerkHideButton:Show()
assertFalse(PerkChooseButton:IsShown(), "guard missed a later compact-button Show")
assertFalse(PerkHideButton:IsShown(), "guard missed a later hide-button Show")

-- ProjectEbonhold's successful banish path calls UpdateSinglePerk and then
-- ResetSelection. The reset must not be interpreted as a rejected request: it
-- must keep the replacement board hidden and preserve the chained evaluation.
ProjectEbonhold.PerkUI.UpdateSinglePerk(0, choices[1])
assertTrue(type(scheduled["automation.evaluate"]) == "function", "replacement did not schedule chained evaluation")
ProjectEbonhold.PerkUI.ResetSelection()
assertTrue(type(scheduled["automation.evaluate"]) == "function", "successful replacement reset cancelled chained evaluation")
assertFalse(ProjectEbonholdPerkFrame:IsShown(), "successful replacement reset exposed native card surface")
assertFalse(PerkChooseButton:IsShown(), "successful replacement reset exposed compact button")
assertFalse(PerkHideButton:IsShown(), "successful replacement reset exposed hide/show button")

-- A failed/ineligible evaluation restores the entire native renderer, not one
-- guessed frame, and does not immediately suppress its own fallback call.
addon.Automation.Evaluate = function() return false end
assertTrue(type(scheduled["automation.evaluate"]) == "function", "evaluation timer was not scheduled")
scheduled["automation.evaluate"]()
assertTrue(ProjectEbonholdPerkFrame:IsShown(), "manual fallback did not restore native card surface")
assertTrue(PerkChooseButton:IsShown(), "manual fallback did not restore compact button")
assertTrue(PerkHideButton:IsShown(), "manual fallback did not restore hide/show button")
assertFalse(addon.Automation._IsNativeChoiceSuppressedForTests(), "guard remained set after fallback")

-- ResetSelection without a preceding replacement is the native rejection
-- path. It must cancel retries and restore manual controls instead of looping.
ProjectEbonhold.PerkUI.Show(choices)
assertTrue(type(scheduled["automation.evaluate"]) == "function", "rejection setup did not schedule evaluation")
ProjectEbonhold.PerkUI.ResetSelection()
assertTrue(scheduled["automation.evaluate"] == nil, "rejected request left an automation retry scheduled")
assertTrue(ProjectEbonholdPerkFrame:IsShown(), "rejected request did not restore native card surface")
assertTrue(PerkChooseButton:IsShown(), "rejected request did not restore compact button")

-- A completed selection hides the old board, while the next native Show starts
-- a fresh independent evaluation. This guards the exact multi-level chain.
addon.Automation.Evaluate = function() return true end
ProjectEbonhold.PerkUI.Hide()
choices = { { spellId = 2001, quality = 2 }, { spellId = 2002, quality = 1 } }
ProjectEbonhold.PerkUI.Show(choices)
assertTrue(type(scheduled["automation.evaluate"]) == "function", "next choice board did not schedule automation")
assertFalse(PerkChooseButton:IsShown(), "next choice board exposed compact button")

-- Disabling Autopilot while a board exists also restores the native renderer.
automationEnabled = true
ProjectEbonhold.PerkUI.Show(choices)
automationEnabled = false
listeners.BUILD_RUNTIME_CHANGED()
assertTrue(ProjectEbonholdPerkFrame:IsShown(), "disabling Autopilot did not restore native UI")

-- Manual Training always leaves ProjectEbonhold's native interaction path.
automationEnabled = true
trainingEnabled = true
ProjectEbonhold.PerkUI.Show(choices)
assertTrue(PerkChooseButton:IsShown(), "Manual Training incorrectly hid compact button")
assertTrue(PerkHideButton:IsShown(), "Manual Training incorrectly hid hide/show button")

print("Native level-up Echo choice guard passed.")
