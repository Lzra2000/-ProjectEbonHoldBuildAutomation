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
    title = "What's New in 3.03",
    lines = {
        GOLD .. "3.03: fixed -- windows missing elements after 3.02" .. R,
        "- The settings popup (and any window with the new themed",
        "  checkbox) could stop building midway: sliders present,",
        "  checkboxes and Save/Cancel missing",
        "- Cause: the checkbox used a script type (PreClick) whose",
        "  validity on plain buttons in 3.3.5 wasn't worth betting on",
        "- Rebuilt on plain OnClick only -- same click behavior,",
        "  covered by the same contract test",
        "",
        GOLD .. "3.02: the redesign now covers every window" .. R,
        "- The unified visual language from the big redesign now",
        "  extends to all standalone windows: Tuning Advisor, Debug",
        "  Log, Echo Picker, FAQ, Showcase, Error Log, Click Trace,",
        "  EWL export, and the settings popup",
        "- New themed close button (flat X, red hover) and checkbox",
        "  (gold fill) replace the parchment WotLK widgets everywhere",
    },
},
{
    title = "What's New in 2.99",
    lines = {
        GOLD .. "2.99: Consolidated update from 2.59" .. R,
        "- Unified build workspace and improved editor workflows",
        "- Rebuilt Stats: Summary, Echoes, Actions, and split Recommendations",
        "- Reworked Logbook with run navigation, filters, sorting, and inspector",
        "- Added per-quality weights, negative values, protection, and fast editing",
        "- Missing now defaults to Weighted missing; EWL1 export is included",
        "",
        GOLD .. "Reliability and polish" .. R,
        "- Safer recommendation Apply/Undo/Dismiss and clearer value transitions",
        "- Improved locked-Echo spacing and Lua 5.1 compatibility safeguards",
        GREY .. "This page summarizes the major differences from the uploaded 2.59 build." .. R,
    },
},
{
    title = "Manual Training and analytics",
    lines = {
        GOLD .. "Manual Training" .. R,
        "Enable Training from the build overview. Autopilot yields to the native",
        "picker, while EbonBuilds compares your manual choice with its scored best.",
        "Repeated disagreements become rank-specific raise/lower suggestions.",
        "Use /ebb cleartraining to reset the active build's training history.",
        "",
        GOLD .. "Offer appearance rates" .. R,
        "Every automated evaluation records which Echo families appeared.",
        "Local recording is automatic. Sharing is separately opt-in in /ebb tuning.",
        "Hover an Echo icon or use Export (AI) to see the observed rate.",
        "",
        GOLD .. "Auto-apply" .. R,
        "Optional and off by default. It requires Continuous auto-tune and applies",
        "signed deltas safely to rank tables. Opposing DPS/training signals cancel",
        "instead of one source silently overwriting the other.",
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
        GOLD .. "Tip:" .. R .. " choose Balanced in Autopilot for a clean baseline,",
        "then adjust only the action that feels wrong.",
    },
},
{
    title = "Smart automation (expected value)",
    lines = {
        "Open the Autopilot tab and choose an intent preset.",
        GOLD .. "Balanced" .. R .. " is the recommended default for new builds.",
        "",
        GOLD .. "Smart model:" .. R,
        "- Reroll compares the BEST current offer with the expected best",
        "  result of a fresh three-Echo screen",
        "- Banish compares one offer with an average random offer",
        "- Freeze compares strong offers with an expected best-of-three",
        "",
        "The three action cards translate percentages into real score",
        "cutoffs, so you can understand each decision without math.",
        "",
        GOLD .. "Existing builds are unchanged." .. R,
        "Classic peak-based rules remain available under Advanced.",
        "Frozen/carried Echoes are ignored when rerolling because they",
        "survive the reroll.",
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
        "Autopilot > Advanced explains conflicting combinations:",
        "- Guard below Freeze: junk echoes would block rerolls that",
        "  could have found freeze-worthy ones",
        "- Banish at/above Freeze: banish claims echoes before freeze",
        "  ever sees them",
        "",
        "Each action row shows its current score cutoff in plain language.",
    },
},
{
    title = "Fixed issues",
    lines = {
        GOLD .. "'Reset to default' did nothing" .. R,
        "Autopilot changes once lived only in a temporary copy. They now",
        "save immediately while editing a build (presets, sliders,",
        "model, family protection, and priority ban list).",
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
        "- 'Group: Tome/Zone/Mob' (2.20) reorganizes the whole list;",
        "  the Zone dropdown narrows any of the three to one zone",
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
    title = "\"This name is already public\" popup (2.18)",
    lines = {
        "You imported someone's build, tweaked something, and saved --",
        "which forks your copy under your own name (see the previous",
        "page). Your copy kept the original title AND stayed public,",
        "which is why Public Builds used to fill up with the same",
        "title from many different authors.",
        "",
        GOLD .. "What happens now" .. R,
        "Saving checks if the title is already public under someone",
        "else. If so: your copy is unpublished (not deleted) and this",
        "popup explains whose name it belongs to.",
        "",
        GOLD .. "What to do" .. R,
        "Rename it via Edit Build, then make it public again -- now",
        "under its own name, no longer colliding with anyone else's.",
        "",
        GREY .. "Best-effort check based on what your own client has" .. R,
        GREY .. "seen; there's no central registry to enforce this." .. R,
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
{
    title = "Tuning Advisor (/ebb tuning, 2.33-2.34)",
    lines = {
        "Compares your Banish/Reroll/Freeze thresholds against what",
        "your build actually gets offered, not just the theory.",
        "",
        GOLD .. "How it works" .. R,
        "Every echo automation evaluates gets recorded as a % of that",
        "run's peak, always-on and lightweight. Once there are 30+",
        "samples, the advisor shows what your CURRENT threshold really",
        "rejects/catches (e.g. \"~12% of real offers\") and suggests a",
        "value to hit a sensible target: ~15% Banish, ~45% Reroll,",
        "~10% Freeze.",
        "",
        GOLD .. "Works with both modes (2.34)" .. R,
        "Smart (EV) mode's thresholds are a % of mean/evBest3 instead",
        "of peak -- converted through the live scoring model so both",
        "modes compare fairly against the same sample data.",
        "",
        GOLD .. "Apply" .. R,
        "One click writes the suggested % straight to your active",
        "build's settings.",
        "",
        GOLD .. "Continuous auto-tune (2.35)" .. R,
        "Checkbox, off by default. When on, thresholds nudge toward",
        "their suggestion automatically -- small gradual steps, not",
        "an instant jump, with a toast every time something changes.",
        "Covers Banish, Reroll, and Freeze in both modes.",
        "",
        GREY .. "Smart Reroll (2.48) uses its own sample stream with each" .. R,
        GREY .. "evaluation's charge pacing divided back out, since its" .. R,
        GREY .. "live threshold moves with remaining charges." .. R,
        GREY .. "Clear Collected Data after a major reweight -- old" .. R,
        GREY .. "samples reflect the previous weighting." .. R,
    },
},
{
    title = "Settings dialog (gear icon, 2.16)",
    lines = {
        "Click the gear icon next to the window's close button (this is",
        "separate from the per-build Automation tab).",
        "",
        GOLD .. "Action delay" .. R,
        "How long automation waits before acting on a new echo screen.",
        "Very low values may cause the addon to malfunction.",
        "",
        GOLD .. "Toast duration" .. R,
        "How long pick/reroll/freeze/banish toasts stay on screen.",
        "",
        GOLD .. "Auto-sell junk at vendors" .. R,
        "Same toggle as /ebb autosell, now persistent here too.",
        "",
        GOLD .. "Bag affix dots" .. R,
        "Same toggle as /ebb bagdots, now persistent here too.",
        "",
        GREY .. "This dialog scrolls if it grows further, so it can't" .. R,
        GREY .. "spill past the window no matter how much gets added." .. R,
    },
},
{
    title = "Apply to Character (2.26)",
    lines = {
        "Build Overview > Apply to Character.",
        "",
        "Pushes this build's locked echoes to the server as your",
        "Active Echo Loadout -- a feature built into ProjectEbonhold",
        "itself (both the base and Enhanced versions). Once applied,",
        "the game's OWN echo-pick screen highlights choices that",
        "match this build, in-game, without needing EbonBuilds open.",
        "",
        GOLD .. "Requirements" .. R,
        "The build needs at least one locked echo. If your server",
        "doesn't support this yet, you'll get a clear message instead",
        "of the button silently doing nothing.",
        "",
        GREY .. "This does not pick echoes for you -- it only highlights" .. R,
        GREY .. "matches on the server's normal selection screen." .. R,
    },
},
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local frame, titleText, bodyText, scrollFrame, scrollChild, scrollBar, pageLabel, prevBtn, nextBtn
local page = 1

local function RenderPage()
    local p = PAGES[page]
    if not p then return end
    titleText:SetText(GOLD .. p.title .. R)
    bodyText:SetText(table.concat(p.lines, "\n"))
    -- FontStrings don't clip or scroll on their own -- the scroll child
    -- must be resized to the text's actual rendered height (which varies
    -- a lot page to page) so the scrollbar's range is correct and content
    -- can never spill out past the window (see 2.12/2.13: growing "What's
    -- New" pages overflowed straight over the game world and action bars).
    local textHeight = bodyText:GetStringHeight() or 0
    local contentHeight = math.max(scrollFrame:GetHeight(), textHeight + 4)
    scrollChild:SetHeight(contentHeight)
    if scrollBar then
        scrollBar:SetMinMaxValues(0, math.max(0, contentHeight - scrollFrame:GetHeight()))
        scrollBar:SetValue(0)
    else
        scrollFrame:SetVerticalScroll(0)
    end
    pageLabel:SetText(("Page %d / %d"):format(page, #PAGES))
    if page <= 1 then prevBtn:Disable() else prevBtn:Enable() end
    if page >= #PAGES then nextBtn:Disable() else nextBtn:Enable() end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsFAQWindow", UIParent)
    f:SetSize(560, 480)
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

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    -- Page title with a thin gold rule underneath
    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -42)
    EbonBuilds.Theme.AddHeaderRule(f, titleText, 516)

    -- Scrollable body: leaves room on the right for the scrollbar and at
    -- the bottom for the Prev/Next/page-count row, and clips anything
    -- that doesn't fit -- unlike the old bare FontString, content can
    -- never draw outside this window regardless of how long a page is.
    scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsFAQSF", f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 48)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(504)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    bodyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    bodyText:SetWidth(504)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")

    scrollBar = EbonBuilds.Theme.CreateScrollBar(f)
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 17, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 17, 2)
    scrollBar:SetValueStep(28)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    EbonBuilds.Theme.BindScrollWheel(scrollFrame, scrollBar, 32, scrollChild)

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
