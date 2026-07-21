-- EbonBuilds: modules/ui/ShowcaseView.lua
-- Responsibility: a one-time "welcome to EbonBuilds" popup shown on first
-- login (account-wide, not per-character -- the command list is the same
-- for every character), listing every slash command with a one-line
-- explanation. Not a replacement for /ebb faq's much deeper per-feature
-- pages -- this is meant to be skimmable in under a minute, with the FAQ
-- as the "go deeper" pointer for anything that needs more than one line.

EbonBuilds.ShowcaseView = {}

local frame

local SECTIONS = {
    {
        title = "|cffffd100Core|r",
        lines = {
            "|cffffffff/ebb|r -- open or close the main window",
            "|cffffffff/ebb faq|r -- full guide: every feature explained in depth (also /ebb help)",
            "|cffffffff/ebb showcase|r -- reopen this popup anytime",
            "|cffffffff/ebb ewl|r -- export the active build as an EWL1 Echo Wish List",
        },
    },
    {
        title = "|cffffd100Tuning & Automation|r",
        lines = {
            "|cffffffff/ebb tuning|r -- the Tuning Advisor: compares your Banish/Reroll/Freeze",
            "  thresholds against what you're actually offered, suggests better values,",
            "  and can auto-tune them gradually. Also where DPS tracking and community",
            "  sharing toggles live.",
            "|cffffffff/ebb cleartraining|r -- wipe the active build's Manual Training data",
            "  (see the \"Training: ON/OFF\" toggle on a build's overview screen)",
        },
    },
    {
        title = "|cffffd100Reference|r",
        lines = {
            "|cffffffff/ebb atlas|r -- Tome Atlas: community drop locations for echo tomes",
            "|cffffffff/ebb affix|r -- Affixes reference",
        },
    },
    {
        title = "|cffffd100Quality of Life|r",
        lines = {
            "|cffffffff/ebb autosell|r -- toggle auto-selling 0-copper junk at vendors",
            "|cffffffff/ebb bagdots|r -- toggle colored dots on bag items missing an affix",
        },
    },
    {
        title = "|cffffd100Diagnostics (for bug reports)|r",
        lines = {
            "|cffffffff/ebb debug|r -- toggle detailed automation decision logging",
            "|cffffffff/ebb debuglog|r (or /ebb log) -- view the captured debug log",
            "|cffffffff/ebb errors|r -- view caught errors, with the exact message and source",
            "|cffffffff/ebb clicktrace|r -- logs every themed button click, for \"I clicked and",
            "  nothing happened\" reports",
            " ",
            "Attaching one of these to a bug report is the single fastest way to get",
            "something actually fixed instead of guessed at.",
        },
    },
}

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsShowcaseWindow", UIParent)
    f:SetSize(560, 480)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Welcome to EbonBuilds")

    local drag = CreateFrame("Frame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "ShowcaseView.Drag")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    subtitle:SetWidth(528)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("EbonBuilds automates echo picks (Banish/Reroll/Freeze/Select) based on a build you define, and helps tune itself over time. Every command below starts with /ebb. This popup only shows once -- reopen it anytime with /ebb showcase.")

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -14)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 50)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(500)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local bar = EbonBuilds.Theme.CreateScrollBar(scroll)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, 4)
    bar:SetValueStep(20)
    bar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)

    local smf = CreateFrame("ScrollingMessageFrame", nil, child)
    smf:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -2)
    smf:SetWidth(480)
    smf:SetFontObject("GameFontHighlightSmall")
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetInsertMode("BOTTOM")
    smf:SetMaxLines(500)
    smf:SetHyperlinksEnabled(false)
    smf:EnableMouse(false)
    for i, section in ipairs(SECTIONS) do
        if i > 1 then smf:AddMessage(" ") end
        smf:AddMessage(section.title)
        for _, line in ipairs(section.lines) do
            smf:AddMessage(line)
        end
    end

    -- ScrollingMessageFrame has no natural height; measure the rendered
    -- content with a throwaway FontString of the same font/width so the
    -- scrollbar range is accurate instead of guessed.
    local measure = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:SetWidth(480)
    measure:SetJustifyH("LEFT")
    measure:Hide()
    local fullText = {}
    for i, section in ipairs(SECTIONS) do
        if i > 1 then fullText[#fullText + 1] = " " end
        fullText[#fullText + 1] = section.title
        for _, line in ipairs(section.lines) do
            fullText[#fullText + 1] = line
        end
    end
    measure:SetText(table.concat(fullText, "\n"))
    local contentHeight = measure:GetStringHeight() + 20
    smf:SetHeight(contentHeight)
    child:SetHeight(contentHeight)

    local visibleHeight = 480 - 38 - 30 - 14 - 50 -- window minus header/subtitle/gap/footer
    local maxScroll = math.max(0, contentHeight - visibleHeight)
    bar:SetMinMaxValues(0, maxScroll)
    bar:SetValue(0)
    EbonBuilds.Theme.BindScrollWheel(scroll, bar, 20, child)

    local gotItBtn = EbonBuilds.Theme.CreateButton(f)
    gotItBtn:SetSize(100, 22)
    gotItBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    gotItBtn:SetText("Got it")
    gotItBtn:SetScript("OnClick", function() f:Hide() end)

    tinsert(UISpecialFrames, "EbonBuildsShowcaseWindow")
    f:Hide()
    return f
end

function EbonBuilds.ShowcaseView.Show()
    if not frame then frame = BuildWindow() end
    frame:Show()
end

-- Called once at startup. Shows automatically the first time ever
-- (account-wide -- the command list doesn't differ per character), then
-- never again unless explicitly reopened with /ebb showcase.
function EbonBuilds.ShowcaseView.MaybeShowFirstLogin()
    if EbonBuildsDB.hasSeenShowcase then return end
    EbonBuildsDB.hasSeenShowcase = true
    EbonBuilds.ShowcaseView.Show()
end
