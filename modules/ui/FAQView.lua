-- EbonBuilds: modules/ui/FAQView.lua
-- In-game FAQ / "what's new" (/ebb faq): clean paginated window with one
-- topic per page, plus a one-time chat notice when the version changes.
-- The full document also ships as FAQ.md; keep both in sync on release.

EbonBuilds.FAQ = {}

local GOLD = "|cffffd100"
local GREY = "|cffaaaaaa"
local R = "|r"

------------------------------------------------------------------------
-- Pages (one topic each, kept short enough to fit without scrolling)
------------------------------------------------------------------------

local PAGES = {
{
    title = "What's New in 2.12",
    lines = {
        GOLD .. "2.12: previously-built features now actually work" .. R,
        "- New: /ebb autosell -- auto-sells zero-value junk at vendors",
        "  (protects items with an unlearned affix even if worthless)",
        "- New: /ebb bagdots -- colored dots on bag items missing an affix",
        "- New: /ebb errors -- persistent error log, always on, for",
        "  reporting something that broke without needing /ebb debug first",
        "- New: /ebb clicktrace -- diagnostic tool for \"I clicked and",
        "  nothing happened\" (tells you if the click even arrived)",
        "- Talent tracking and gear scoring now load and run correctly",
        "",
        GOLD .. "Automation" .. R,
        "- Stable peak: thresholds stay meaningful for the whole run",
        "- Smart Reroll: new expected-value reroll mode (opt-in)",
        "- Freeze fixed: no more picking or banishing a just-frozen echo",
        "- Class-specific echo weights now apply correctly",
        "",
        GOLD .. "Quality of Life" .. R,
        "- Settings save instantly while editing (reset works now)",
        "- Duplicate build, delete with 10s Undo, smarter wizard",
        "- 6th locked-echo slot, retail-style dark theme, rarity colors",
        "- /ebb debug + /ebb debuglog for easy problem reports",
        "",
        "",
        GOLD .. "2.11: IMPORTANT data-loss fix" .. R,
        "- Fixed: your own build could get silently forked away and",
        "  deleted from its original slot on a later login",
        "- If this happened to you, the build still exists under a new",
        "  slot with a note '\"copied from <your name>\"' - see the FAQ",
        "",
        GOLD .. "2.10: UI layout audit" .. R,
        "- Fixed: Tome Atlas header text could overlap the search row",
        "- Fixed: long build titles could overflow their card in",
        "  Public Builds, overlapping the next one in the list",
        "- Fixed: same overlap risk on the build Overview page header",
        "",
        GOLD .. "2.9: Missing tab stuck-loading fix" .. R,
        "- Fixed: Missing tab could say \"Requesting data...\" forever",
        "  on characters with 0 echoes learned yet",
        "- Now auto-retries, and falls back to showing the full list",
        "  after 15 seconds instead of hanging indefinitely",
        "",
        GOLD .. "2.8: Build list fix" .. R,
        "- Fixed: the 6th locked-echo icon in the build list was clipped",
        "  off the edge of the left panel and hard to see",
        "",
        GOLD .. "2.7: Affix tracking (new)" .. R,
        "- New Affixes tab: your learned gear affixes, straight from the",
        "  server -- no tooltip guessing",
        "- See which affixes you have and which are missing at a glance",
        "- /ebb affix or the Affixes button in the left panel",
        "",
        GOLD .. "2.6: Tome Atlas polish" .. R,
        "- Fixed a layout bug where the search box and buttons overlapped",
        "- Hover any tome for its full item tooltip + complete source list",
        "- Real placeholder text in the search box",
        "",
        GOLD .. "2.5: Sync fix & cleaner UI" .. R,
        "- Fixed: players with no public builds never shared Atlas data",
        "- New Sync button inside the Tome Atlas (no detour needed)",
        "- Automation ON/OFF and Delete are now color-coded",
        "- '+ New Build' stands out as the primary action",
        "",
        GOLD .. "2.4: Full Smart mode, chat links & more" .. R,
        "- Smart (EV) mode now drives banish and freeze too",
        "- Charge pacing: generous with many rerolls, picky with few",
        "- Build links in chat: click to fetch (Chat Link button)",
        "- Tome Atlas shows your best farming zones",
        "- Retail-style buttons across the whole UI",
        "",
        GOLD .. "2.3: Sync overhaul" .. R,
        "- Lost transfers now recover automatically (retransmit requests)",
        "- The same build is no longer downloaded from several players",
        "- Flood protection against sync request spam",
        "- Summary toast when a sync finishes; /ebb debug traces sync",
        "",
        GOLD .. "2.2: Tome Atlas" .. R,
        "- Community drop database: which mob drops which tome, where",
        "- Your looted tomes are recorded and shared automatically",
        "- Tome Atlas button in the left panel, or /ebb atlas",
        "",
        GOLD .. "2.1 hotfixes" .. R,
        "- Pro editor Save works again on imported builds",
        "- Freeze/guard sliders go up to 200% (novelty can beat the peak)",
        "- Opening the Settings tab no longer rewrites out-of-range values",
        "",
        GREY .. "Browse the pages for details." .. R,
    },
},
{
    title = "Reroll feels different after updating?",
    lines = {
        "That is intentional. The peak score no longer includes the",
        "novelty bonus.",
        "",
        "Previously the peak was inflated at run start (everything is",
        "novel), so percentage thresholds became unreachable as the run",
        "consumed novelty - freeze and reroll quietly stopped firing",
        "mid-run.",
        "",
        "The peak is now a stable reference for the whole run. Your",
        "percentages mean what they say, but the absolute values shifted.",
        "",
        GOLD .. "Tip:" .. R .. " press 'Reset thresholds to default' once and re-tune.",
        "Old builds get new settings keys backfilled automatically.",
    },
},
{
    title = "Smart mode (expected value)",
    lines = {
        "New opt-in mode - button in the Automation tab:",
        GOLD .. "Reroll mode: Classic (sum) / Smart (expected value)" .. R,
        "",
        GOLD .. "Classic:" .. R .. " reroll when the SUM of all three offers is below",
        "Auto-reroll % of the peak, unless the guard blocks it.",
        "",
        GOLD .. "Smart:" .. R .. " reroll when the BEST offer is worse than X% of what",
        "an average reroll's best would be worth - computed exactly from",
        "your weights across every echo and quality your class can roll.",
        "",
        "Smart mode is immune to peak outliers and quality-bonus noise.",
        "Frozen/carried echoes are ignored on both sides (they survive",
        "a reroll anyway).",
        "",
        GOLD .. "Recommended: Smart mode at 95%." .. R,
        "That means: only reroll when this screen is worse than an",
        "average roll - statistically never a losing trade.",
        "",
        GOLD .. "Since 2.4, Smart mode also drives:" .. R,
        "- Banish: below Smart banish % of an average card (default 60)",
        "- Freeze: above Smart freeze % of an expected best-of-3 (110)",
        "- Charge pacing: the reroll threshold scales down from 100%",
        "  (8+ charges) to 60% (last charge) automatically.",
    },
},
{
    title = "Build links in chat (new in 2.4)",
    lines = {
        "Share builds directly in chat:",
        "",
        GOLD .. "Sending" .. R,
        "Open a build > press the 'Chat Link' button > the link token",
        "lands in your chat box. Works in say, guild, party, whispers.",
        "",
        GOLD .. "Receiving" .. R,
        "Other EbonBuilds users see a clickable green link. Clicking",
        "opens the build if already known - otherwise it is fetched",
        "automatically from whoever has it (public builds only).",
        "",
        GREY .. "Players without the addon just see plain text - nothing" .. R,
        GREY .. "breaks for them." .. R,
    },
},
{
    title = "Recommended Classic settings",
    lines = {
        "If you stay on Classic mode:",
        "",
        "  Auto-reroll (sum) ...... ~25-30%",
        "  Reroll guard ........... ~30%",
        "  Auto-freeze ............ ~15-20%",
        "  Auto-banish ............ ~5%",
        "",
        "The Settings tab now warns live about conflicting combinations:",
        "- Guard below Freeze: junk echoes would block rerolls that",
        "  could have found freeze-worthy ones",
        "- Banish at/above Freeze: banish claims echoes before freeze",
        "  ever sees them",
        "",
        "Hover any slider for a worked example using your current peak.",
    },
},
{
    title = "Fixed issues",
    lines = {
        GOLD .. "'Reset to default' did nothing" .. R,
        "Settings-tab changes only lived in a temporary copy. They now",
        "save instantly while editing a build (sliders on release, reset,",
        "mode, whitelist, ban list).",
        "",
        GOLD .. "Weighted class echoes were ignored" .. R,
        "Weights for echoes like 'Warrior - X' scored as 0 in automation",
        "due to a name mismatch. Fixed with one shared canonical name.",
        "",
        GOLD .. "Freeze wasted its charge" .. R,
        "Automation could freeze an echo and instantly pick or banish it.",
        "Select and banish now exclude echoes frozen this round.",
        "",
        GOLD .. "Pro editor Save silently failed on imported builds (2.1)" .. R,
        "Saving an imported build forks it under a new internal id; the",
        "editor kept the old id, so the next Save hit a deleted build.",
        "All save paths now adopt the new id.",
        "",
        GOLD .. "Sliders rewrote imported builds (2.1)" .. R,
        "Opening Settings clamped out-of-range thresholds (e.g. freeze",
        "150%) to the slider max and saved that. Freeze/guard now go to",
        "200%, and programmatic refreshes never write values back.",
        "",
        GOLD .. "Missing tab" .. R,
        "No duplicates per quality tier, owning any tier removes the",
        "line, no more emptying after level-1 resets.",
    },
},
{
    title = "Tome Atlas (new in 2.2)",
    lines = {
        "An AtlasLoot-style community database for echo tomes:",
        "which mob drops which tome, in which zone.",
        "",
        GOLD .. "How it works" .. R,
        "- Loot a tome: the addon records the mob and zone",
        "  automatically and shares it with other EbonBuilds users",
        "  (sync channel + guild).",
        "- Data from other players arrives when anyone syncs",
        "  (Public Builds > Reload) and live as drops happen.",
        "- Duplicate reports merge cleanly - counts never double.",
        "",
        GOLD .. "Using it" .. R,
        "- Open via the Tome Atlas button (left panel) or /ebb atlas",
        "- Search by tome, mob, or zone name",
        "- 'Show: Missing only' hides everything you already collected",
        "  (matched against your Echoes spellbook)",
        "- (x3) behind a source = how often the community saw it drop",
        "",
        GREY .. "New players: filter to Missing only and farm the zones" .. R,
        GREY .. "with the most entries - that is your collection route." .. R,
    },
},
{
    title = "Affixes (new in 2.7)",
    lines = {
        "Project Ebonhold tracks a second, separate progression system:",
        "gear Affixes (permanent unlocks applied to weapons/armor), not",
        "to be confused with run Echoes.",
        "",
        GOLD .. "How it works" .. R,
        "The server can tell the addon directly which affixes you have",
        "learned -- no tooltip scanning, no guessing. The Affixes tab",
        "shows every known affix: green dot = learned, red = missing.",
        "",
        GOLD .. "Using it" .. R,
        "- Open via the Affixes button (left panel) or /ebb affix",
        "- Search by name, or toggle 'Show: Missing only'",
        "- Hover any affix for its full tooltip, weapon/armor",
        "  restriction, apply cost, and how many times you have used it",
        "- Press Refresh to request an updated list from the server",
        "",
        GREY .. "This is the foundation -- party-wide affix comparison" .. R,
        GREY .. "and build-level affix goals are planned next." .. R,
    },
},
{
    title = "My build disappeared! (2.11 fix)",
    lines = {
        "If a build vanished after logging in, this was a real bug -",
        "not something you did wrong.",
        "",
        GOLD .. "What happened" .. R,
        "Saving a build compares its stored author to your current",
        "character name to decide 'is this mine or someone else's'.",
        "Your name can occasionally come back from the game in a",
        "different format (with or without the realm attached) after",
        "a reconnect. That mismatch made the addon think YOUR OWN",
        "build belonged to someone else, 'forked' it into a new slot,",
        "and removed the old one.",
        "",
        GOLD .. "The good news" .. R,
        "Nothing was truly deleted - the build kept existing, just",
        "under a different slot, tagged as 'copied from <your name>'.",
        "If you still see a build like that: it is yours, just rename",
        "it and clear the copied-from note via Edit Build.",
        "",
        GOLD .. "Fixed in 2.11" .. R,
        "The comparison now ignores the realm suffix, so this can't",
        "happen again.",
    },
},
{
    title = "Reporting a problem",
    lines = {
        "Help us fix things fast - three steps:",
        "",
        GOLD .. "1.  /ebb debug" .. R,
        "    Turns on decision tracing (confirmation in chat).",
        "",
        GOLD .. "2.  Play until the problem happens." .. R,
        "",
        GOLD .. "3.  /ebb debuglog" .. R,
        "    Opens a window with the full trace, pre-selected.",
        "    Ctrl+C and paste it into your report.",
        "",
        "The log shows the peak, every threshold as an absolute number,",
        "every offered echo with score/weight/frozen state, and the",
        "reason behind every action. Plain text, last 500 lines, zero",
        "cost while disabled.",
    },
},
{
    title = "New tools (2.12)",
    lines = {
        GOLD .. "/ebb autosell" .. R,
        "Toggle. When on, junk (0-copper) bag items auto-sell while a",
        "vendor is open. Items with an unlearned affix are always",
        "protected, even at 0 copper. Off by default.",
        "",
        GOLD .. "/ebb bagdots" .. R,
        "Toggle. Colored dots on bag items with an affix you haven't",
        "learned: red = new affix line, purple = missing rank on one",
        "you already have. On by default.",
        "",
        GOLD .. "/ebb errors" .. R,
        "Opens a small always-on error log (last 20), independent of",
        "/ebb debug. Good first step for \"something broke\" reports.",
        "",
        GOLD .. "/ebb clicktrace" .. R,
        "Diagnostic for \"I clicked and nothing happened.\" Logs every",
        "themed button click and view change, so a report can show",
        "whether the click even reached EbonBuilds.",
    },
},
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local frame, titleText, bodyText, pageLabel, prevBtn, nextBtn
local page = 1

local function RenderPage()
    local p = PAGES[page]
    if not p then return end
    titleText:SetText(GOLD .. p.title .. R)
    bodyText:SetText(table.concat(p.lines, "\n"))
    pageLabel:SetText(("Page %d / %d"):format(page, #PAGES))
    if page <= 1 then prevBtn:Disable() else prevBtn:Enable() end
    if page >= #PAGES then nextBtn:Disable() else nextBtn:Enable() end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsFAQWindow", UIParent)
    f:SetSize(560, 430)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOP", f, "TOP", 0, -12)
    header:SetText("EbonBuilds " .. (EbonBuilds.VERSION or "") .. " - FAQ & What's New")

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Page title with a thin gold rule underneath
    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -42)
    EbonBuilds.Theme.AddHeaderRule(f, titleText, 516)

    bodyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -76)
    bodyText:SetWidth(516)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")

    -- Navigation
    prevBtn = EbonBuilds.Theme.CreateButton(f)
    prevBtn:SetSize(90, 22)
    prevBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    prevBtn:SetText("< Prev")
    prevBtn:SetScript("OnClick", function()
        if page > 1 then page = page - 1; RenderPage() end
    end)

    nextBtn = EbonBuilds.Theme.CreateButton(f)
    nextBtn:SetSize(90, 22)
    nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    nextBtn:SetText("Next >")
    nextBtn:SetScript("OnClick", function()
        if page < #PAGES then page = page + 1; RenderPage() end
    end)

    pageLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pageLabel:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)

    -- Mouse wheel flips pages too
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if delta < 0 and page < #PAGES then page = page + 1; RenderPage()
        elseif delta > 0 and page > 1 then page = page - 1; RenderPage() end
    end)

    tinsert(UISpecialFrames, "EbonBuildsFAQWindow")
    f:Hide()
    return f
end

function EbonBuilds.FAQ.Show()
    if not frame then frame = BuildWindow() end
    page = 1
    RenderPage()
    frame:Show()
end

------------------------------------------------------------------------
-- One-time "what's new" notice on version change
------------------------------------------------------------------------

function EbonBuilds.FAQ.MaybeAnnounceUpdate()
    if not EbonBuildsDB then return end
    local current = EbonBuilds.VERSION or "?"
    if EbonBuildsDB.lastSeenVersion ~= current then
        EbonBuildsDB.lastSeenVersion = current
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffd100EbonBuilds|r updated to |cffffd100" .. current ..
            "|r - type |cffffd100/ebb faq|r to see what's new.")
    end
end
