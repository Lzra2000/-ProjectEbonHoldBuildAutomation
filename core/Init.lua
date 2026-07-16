-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}
EbonBuilds.VERSION = "2.20"

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(addonName)
    if addonName ~= "EbonBuilds" then return end

    if not ProjectEbonhold then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444EbonBuilds:|r ProjectEbonhold not found -- EbonBuilds requires it and will stay disabled. " ..
            "Make sure the ProjectEbonhold addon is installed and enabled.")
        return
    end

    EbonBuildsDB = EbonBuildsDB or {
        builds        = {},
        minimapAngle  = 220,
        globalSettings = {
            evalDelay     = 2,
            toastDuration = 3,
        },
    }
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.evalDelay     = EbonBuildsDB.globalSettings.evalDelay     or 2
    EbonBuildsDB.globalSettings.toastDuration = EbonBuildsDB.globalSettings.toastDuration or 3

    EbonBuildsCharDB = EbonBuildsCharDB or {
        activeBuildId = nil,
    }

    EbonBuilds.Build.Migrate()
    EbonBuilds.Session.Init()
    EbonBuilds.SessionHistory.Init()
    EbonBuilds.Weights.Init()
    EbonBuilds.Toast.Init()
    EbonBuilds.WelcomeView.Init()
    EbonBuilds.BonusView.Init()
    EbonBuilds.BuildWizard.Init()
    EbonBuilds.MinimapButton.Init()
    EbonBuilds.MainWindow.Init()
    EbonBuilds.Automation.Init()
    EbonBuilds.Sync.Init()
    EbonBuilds.TomeAtlas.Init()
    EbonBuilds.Affix.Init()
    EbonBuilds.ChatLink.Init()
    EbonBuilds.TalentAutoLearn.Init()
    EbonBuilds.BagAffixDots.Init()
    EbonBuilds.AutoSell.Init()
    EbonBuilds.FAQ.MaybeAnnounceUpdate()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
