local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/LoginPanel.lua
-- Responsibility: the one-time panel shown after logging in. Two jobs:
-- ask the DPS-tracking consent question introduced in 3.23 (existing
-- characters were reset to off by that release and would otherwise only
-- discover it by digging through Settings), and surface "What's new"
-- once per addon version. Never shows twice for the same version once
-- dismissed, and never shows at all when there's nothing to say.

EbonBuilds.LoginPanel = {}

local panel
local shownThisSession = false

local function AddonVersion()
    if GetAddOnMetadata then
        local v = GetAddOnMetadata("EbonBuilds", "Version")
        if v and v ~= "" then return v end
    end
    return "unknown"
end

local function ConsentAnswered()
    local consent = EbonBuildsCharDB and EbonBuildsCharDB.consent
    return consent ~= nil and (tonumber(consent.performanceVersion) or 0) >= 1
end

-- The whole decision in one place, injectable-free because it reads only
-- saved state: show when the consent question is unanswered, or when
-- this addon version hasn't been seen by this character yet.
function EbonBuilds.LoginPanel.ShouldShow()
    if not ConsentAnswered() then return true end
    return (EbonBuildsCharDB.loginPanelSeenVersion or "") ~= AddonVersion()
end

function EbonBuilds.LoginPanel.MarkSeen()
    EbonBuildsCharDB.loginPanelSeenVersion = AddonVersion()
end

local function BuildPanel()
    local Theme = EbonBuilds.Theme
    panel = CreateFrame("Frame", "EbonBuildsLoginPanel", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(panel, "LoginPanel.Window")
    end
    panel:SetSize(460, 340)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    Theme.ApplyWindow(panel)
    panel:Hide()

    local drag = CreateFrame("Frame", nil, panel)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "LoginPanel.Drag")
    end
    drag:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, 0)
    drag:SetHeight(36)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(EbonBuilds.ThemeRegistry.Get().textures.minimap)
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -14)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("EbonBuilds " .. AddonVersion())
    Theme.AddHeaderRule(panel, title, 420)

    local whatsNewTeaser = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    whatsNewTeaser:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
    whatsNewTeaser:SetWidth(420)
    whatsNewTeaser:SetJustifyH("LEFT")
    local newestPage = EbonBuilds.FAQContent and EbonBuilds.FAQContent.PAGES and EbonBuilds.FAQContent.PAGES[1]
    local newestHeadline = newestPage and newestPage.title and newestPage.title:match("^What's new: (.*)$")
    if newestHeadline then
        whatsNewTeaser:SetText("Latest: " .. newestHeadline)
    else
        whatsNewTeaser:SetText("")
    end

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", whatsNewTeaser, "BOTTOMLEFT", 0, -10)
    intro:SetWidth(420)
    intro:SetJustifyH("LEFT")
    intro:SetText("Echo automation for ProjectEbonhold. Your builds, weights, and automation settings are exactly where you left them.")

    -- Consent block: only built into view when the question is open.
    local consentHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    consentHeader:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
    consentHeader:SetText("DPS tracking and community sharing")
    consentHeader:SetTextColor(unpack(Theme.ACCENT_GOLD))

    local consentText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    consentText:SetPoint("TOPLEFT", consentHeader, "BOTTOMLEFT", 0, -4)
    consentText:SetWidth(400)
    consentText:SetJustifyH("LEFT")
    consentText:SetText("With your OK, EbonBuilds tracks your DPS per Echo (via Details!, if installed) to power the Tuning Advisor, and shares those aggregates with other EbonBuilds players of your class. This is off until you decide -- and one checkbox in Settings, either way, if you change your mind later.")

    local acceptBtn = Theme.CreateButton(panel)
    acceptBtn:SetSize(180, 24)
    acceptBtn:SetPoint("TOPLEFT", consentText, "BOTTOMLEFT", 0, -8)
    acceptBtn:SetText("Enable tracking & sharing")
    acceptBtn:SetScript("OnClick", function()
        if EbonBuilds.EchoPerformance.IsDetailsAvailable
            and not EbonBuilds.EchoPerformance.IsDetailsAvailable() then
            EbonBuilds.Toast.Show("Details! not found -- install it to collect DPS samples")
            EbonBuilds.EchoPerformance.SetEnabled(false)
        else
            EbonBuilds.EchoPerformance.SetEnabled(true)
        end
        EbonBuilds.LoginPanel._RefreshConsentBlock()
    end)

    local declineBtn = Theme.CreateButton(panel)
    declineBtn:SetSize(120, 24)
    declineBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 8, 0)
    declineBtn:SetText("Keep it off")
    declineBtn:SetScript("OnClick", function()
        EbonBuilds.EchoPerformance.SetEnabled(false)
        EbonBuilds.LoginPanel._RefreshConsentBlock()
    end)

    local consentDone = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    consentDone:SetPoint("TOPLEFT", consentHeader, "BOTTOMLEFT", 0, -4)
    consentDone:SetWidth(400)
    consentDone:SetJustifyH("LEFT")

    function EbonBuilds.LoginPanel._RefreshConsentBlock()
        if ConsentAnswered() then
            consentText:Hide()
            acceptBtn:Hide()
            declineBtn:Hide()
            local on = EbonBuilds.EchoPerformance.IsEnabled()
            consentDone:SetText(on
                and "Tracking and sharing are ON. Change it any time in Settings."
                or "Tracking and sharing stay OFF. Enable them any time in Settings.")
            consentDone:SetTextColor(unpack(Theme.TEXT_MUTED))
            consentDone:Show()
        else
            consentDone:Hide()
            consentText:Show()
            acceptBtn:Show()
            declineBtn:Show()
        end
    end

    -- Bottom row: what's new, getting started, close.
    local whatsNewBtn = Theme.CreateButton(panel)
    whatsNewBtn:SetSize(120, 24)
    whatsNewBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 16)
    whatsNewBtn:SetText("What's new")
    whatsNewBtn:SetScript("OnClick", function()
        if EbonBuilds.FAQ and EbonBuilds.FAQ.Show then EbonBuilds.FAQ.Show() end
    end)

    local guideBtn = Theme.CreateButton(panel)
    guideBtn:SetSize(130, 24)
    guideBtn:SetPoint("LEFT", whatsNewBtn, "RIGHT", 8, 0)
    guideBtn:SetText("Getting started")
    guideBtn:SetScript("OnClick", function()
        if EbonBuilds.ShowcaseView and EbonBuilds.ShowcaseView.Show then EbonBuilds.ShowcaseView.Show() end
    end)

    local closeBtn = Theme.CreateButton(panel)
    closeBtn:SetSize(90, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        EbonBuilds.LoginPanel.MarkSeen()
        panel:Hide()
    end)

    local xBtn = Theme.CreateCloseButton(panel)
    if xBtn and xBtn.SetScript then
        xBtn:SetScript("OnClick", function()
            EbonBuilds.LoginPanel.MarkSeen()
            panel:Hide()
        end)
    end
end

function EbonBuilds.LoginPanel.Show()
    if not panel then BuildPanel() end
    EbonBuilds.LoginPanel._RefreshConsentBlock()
    panel:Show()
end

function EbonBuilds.LoginPanel.Init()
    EbonBuilds.WoWEvents.On("PLAYER_ENTERING_WORLD", function()
        if shownThisSession then return end
        shownThisSession = true
        if EbonBuilds.LoginPanel.ShouldShow() then EbonBuilds.LoginPanel.Show() end
    end, "LoginPanel")
end
