-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}
EbonBuilds.VERSION = "3.53"

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(addonName)
    if addonName ~= "EbonBuilds" then return end

    if not ProjectEbonhold then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444EbonBuilds:|r ProjectEbonhold not found -- EbonBuilds requires it and will stay disabled. " ..
            "Make sure ProjectEbonhold (or ProjectEbonholdEnhanced) is installed and enabled.")
        return
    end

    EbonBuilds.Database.Init()
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.evalDelay     = EbonBuildsDB.globalSettings.evalDelay     or 2
    EbonBuildsDB.globalSettings.toastDuration = EbonBuildsDB.globalSettings.toastDuration or 3
    EbonBuildsDB.globalSettings.uiScale       = EbonBuildsDB.globalSettings.uiScale       or 1

    EbonBuilds.Locale.Init()
    EbonBuilds.DebugLog.Init()
    EbonBuilds.ClickTrace.Init()

    if EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.Init then
        EbonBuilds.EchoCatalog.Init()
    end
    if EbonBuilds.EchoEligibilityEvidence and EbonBuilds.EchoEligibilityEvidence.Init then
        EbonBuilds.EchoEligibilityEvidence.Init()
    end
    EbonBuilds.Build.Migrate()
    EbonBuilds.RecommendationService.Init()
    EbonBuilds.Aggregates.Init()
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
    EbonBuilds.EchoPerformance.Init()
    EbonBuilds.GearTooltip.Init()
    EbonBuilds.LoginPanel.Init()
    EbonBuilds.WorldIntegration.Init()
    EbonBuilds.ManualTraining.Init()
    EbonBuilds.Calibration.Init()
    EbonBuilds.FAQ.MaybeAnnounceUpdate()
    EbonBuilds.ShowcaseView.MaybeShowFirstLogin()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
