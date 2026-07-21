local addonName, EbonBuilds = ...

-- EbonBuilds: core/Init.lua
-- Private bootstrap. The TOC-provided addon table is the only module namespace;
-- no internal service is published through the global environment.

EbonBuilds.NAME = addonName
EbonBuilds.VERSION = "3.53"
EbonBuilds.Runtime = EbonBuilds.Runtime or {}

local started = false

local function RegisterModules()
    local M = EbonBuilds.Modules

    M.RegisterLegacy("database", M.DATABASE, "Database", "Init")

    M.RegisterLegacy("locale", M.CORE, "Locale", "Init", { "database" })
    M.RegisterLegacy("debugLog", M.CORE, "DebugLog", "Init", { "database", "locale" })
    M.RegisterLegacy("clickTrace", M.CORE, "ClickTrace", "Init", { "database" })
    M.RegisterLegacy("projectAPI", M.CORE, "ProjectAPI", "Init", { "database" })
    M.RegisterLegacy("echoCatalog", M.CORE, "EchoCatalog", "Init", { "database", "projectAPI" })
    M.RegisterLegacy("echoEligibility", M.CORE, "EchoEligibilityEvidence", "Init", { "echoCatalog" })
    M.RegisterLegacy("buildMigration", M.CORE, "Build", "Migrate", { "database", "echoCatalog" })
    M.RegisterLegacy("recommendations", M.CORE, "RecommendationService", "Init", { "buildMigration" })

    M.RegisterLegacy("aggregates", M.RUNTIME, "Aggregates", "Init", { "database", "buildMigration" })
    M.RegisterLegacy("session", M.RUNTIME, "Session", "Init", { "database", "aggregates" })
    M.RegisterLegacy("weights", M.RUNTIME, "Weights", "Init", { "buildMigration" })
    M.RegisterLegacy("automation", M.RUNTIME, "Automation", "Init", { "session", "weights", "echoEligibility" })
    M.RegisterLegacy("sync", M.RUNTIME, "Sync", "Init", { "database", "buildMigration" })
    M.RegisterLegacy("tomeAtlas", M.RUNTIME, "TomeAtlas", "Init", { "database" })
    M.RegisterLegacy("affix", M.RUNTIME, "Affix", "Init", { "database" })
    M.RegisterLegacy("chatLink", M.RUNTIME, "ChatLink", "Init", { "sync" })
    M.RegisterLegacy("talentAutoLearn", M.RUNTIME, "TalentAutoLearn", "Init", { "buildMigration" })
    M.RegisterLegacy("bagAffixDots", M.RUNTIME, "BagAffixDots", "Init", { "affix" })
    M.RegisterLegacy("autoSell", M.RUNTIME, "AutoSell", "Init", { "database" })
    M.RegisterLegacy("echoPerformance", M.RUNTIME, "EchoPerformance", "Init", { "session" })
    M.RegisterLegacy("gearTooltip", M.RUNTIME, "GearTooltip", "Init", { "database" })
    M.RegisterLegacy("manualTraining", M.RUNTIME, "ManualTraining", "Init", { "session" })
    M.RegisterLegacy("calibration", M.RUNTIME, "Calibration", "Init", { "session", "weights" })

    M.RegisterLegacy("toast", M.UI_SHELL, "Toast", "Init", { "locale" })
    M.RegisterLegacy("minimap", M.UI_SHELL, "MinimapButton", "Init", { "database", "toast" })
    M.RegisterLegacy("mainWindow", M.UI_SHELL, "MainWindow", "Init", { "database", "buildMigration", "toast" })
    M.RegisterLegacy("loginPanel", M.UI_SHELL, "LoginPanel", "Init", { "mainWindow" })
    M.RegisterLegacy("worldIntegration", M.UI_SHELL, "WorldIntegration", "Init", { "mainWindow" })

    M.RegisterLegacy("sessionHistory", M.UI_DEFERRED, "SessionHistory", "Init", { "session", "mainWindow" })
    M.RegisterLegacy("welcomeView", M.UI_DEFERRED, "WelcomeView", "Init", { "mainWindow" })
    M.RegisterLegacy("bonusView", M.UI_DEFERRED, "BonusView", "Init", { "mainWindow" })
    M.RegisterLegacy("buildWizard", M.UI_DEFERRED, "BuildWizard", "Init", { "mainWindow", "recommendations" })

    M.Register("faqAnnouncement", {
        phase = M.BACKGROUND,
        dependencies = { "mainWindow" },
        start = function()
            if EbonBuilds.FAQ and EbonBuilds.FAQ.MaybeAnnounceUpdate then
                EbonBuilds.FAQ.MaybeAnnounceUpdate()
            end
        end,
    })
    M.Register("firstLoginShowcase", {
        phase = M.BACKGROUND,
        dependencies = { "mainWindow" },
        start = function()
            if EbonBuilds.ShowcaseView and EbonBuilds.ShowcaseView.MaybeShowFirstLogin then
                EbonBuilds.ShowcaseView.MaybeShowFirstLogin()
            end
        end,
    })
end

local function MissingDependency()
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444EbonBuilds:|r ProjectEbonhold not found -- EbonBuilds requires it and will stay disabled. " ..
            "Make sure ProjectEbonhold (or ProjectEbonholdEnhanced) is installed and enabled.")
    end
end

function EbonBuilds.Start()
    if started then return false end
    started = true

    if not ProjectEbonhold then
        MissingDependency()
        return false
    end

    RegisterModules()
    return EbonBuilds.InitPipeline.Start()
end
