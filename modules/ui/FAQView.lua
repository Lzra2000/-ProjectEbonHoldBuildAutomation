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
    title = "What's New in 2.31",
    lines = {
        GOLD .. "2.31: themed zone picker" .. R,
        "- The Zone filter is a custom, scrollable popup now, not the",
        "  plain Blizzard dropdown that used to run unstyled and",
        "  unbounded off the screen with 50+ zones",
        "- Has its own quick-filter search box",
        "- Matches the addon's dark theme, closes automatically when",
        "  the view is hidden",
        "",
        GOLD .. "2.30: fixed row overlap on long names" .. R,
        "- Fixed: a long tome name wrapped to 2 lines and collided",
        "  with the source text below it -- looked like a garbled",
        "  extra entry, but was really just one long title",
        "- Titles and source lines are single-line now",
        "",
        GOLD .. "2.29: your public builds now show in Public Builds" .. R,
        "- Own public builds are no longer hidden from your own",
        "  Public Builds list -- tagged (You), Import replaced by a",
        "  disabled 'Yours' label",
        "- Lets you visually confirm a build actually published",
        "- Missing? Check the 2.18 title-collision popup -- a colliding",
        "  title auto-unpublishes your build",
        "",
        GOLD .. "2.28: fixed -- Group: Tome showed nothing" .. R,
        "- Root cause via /ebb errors: SourceText() was defined below",
        "  its only caller, a Lua scoping bug -- Zone/Mob don't use",
        "  that function, which is why only Tome mode was affected",
        "- Fixed by moving the function above its caller",
        "",
        GOLD .. "2.27: hotfix -- Tome Atlas could stay blank" .. R,
        "- Fixed: an error in 2.26's owned-echo detection could leave",
        "  Tome Atlas or Public Builds permanently blank, no error",
        "  shown (most players have script errors off by default)",
        "- Render() is now error-safe in both views -- the window",
        "  always opens now; real errors go to /ebb errors instead",
        "- Still blank for you? Check /ebb errors and share what it",
        "  says -- that'll point at the actual cause",
        "",
        GOLD .. "2.26: ProjectEbonhold API audit" .. R,
        "- New: 'Apply to Character' button (Build Overview) -- pushes",
        "  this build's locked echoes to the server's Active Echo",
        "  Loadout, so the game's own pick screen highlights matches",
        "- 'Learned' detection now prefers the server's own",
        "  GetDiscoveredEchoes() API: instant, no more waiting on the",
        "  spellbook tab to populate (old scan kept as a fallback)",
        "- Removed a duplicate spellbook-scan implementation between",
        "  the Missing tab and Tome Atlas (now share one helper)",
        "",
        GOLD .. "2.25: Missing tab Refresh button" .. R,
        "- New: Refresh button forces an immediate spellbook re-scan",
        "- No more waiting on the automatic retry or leaving and",
        "  re-entering the tab to force a re-check",
        "- Local re-scan only -- Echoes come from your own spellbook,",
        "  no server request needed (unlike Affixes' Refresh)",
        "",
        GOLD .. "2.24: fixed freeze/hang after syncing" .. R,
        "- Likely cause found: Tome Atlas + Public Builds re-rendered",
        "  the ENTIRE list on every single incoming sync message --",
        "  a real sync can send 100+, all in a matter of seconds",
        "- Now coalesced: at most one render every 0.3s no matter",
        "  how many sync messages arrive in between",
        "- Settings dialog Save now shows a confirmation toast",
        "  instead of closing with zero feedback",
        "",
        GOLD .. "2.23: sync chat spam fixed" .. R,
        "- Fixed: 'Build X stored in remote' + 'REQ sent on channel'",
        "  printed to chat for every build/request, unconditionally",
        "- Made much worse by 2.15's staggered all-classes sync (up",
        "  to 10 REQ lines per Reload instead of 1)",
        "- Moved behind /ebbsync verbose (off by default); real",
        "  errors now go to /ebb errors instead of chat",
        "",
        GOLD .. "2.22: works with ProjectEbonhold Enhanced" .. R,
        "- Fixed: EbonBuilds couldn't even be enabled with only",
        "  'ProjectEbonhold Enhanced' installed (different folder",
        "  name, same API) -- no more manually editing the .toc",
        "- Now uses OptionalDeps for both variants; load order is",
        "  still guaranteed, just no longer a hard folder-name block",
        "",
        GOLD .. "2.21: deleting an import no longer loses the original" .. R,
        "- Fixed: importing a build deleted its cached copy from",
        "  Public Builds -- deleting your import afterward meant the",
        "  original was gone until someone synced it to you again",
        "- Now: deleting your imported copy makes the original",
        "  reappear in Public Builds immediately, no re-sync needed",
        "",
        GOLD .. "2.20: Tome Atlas categories + item fix" .. R,
        "- Fixed: items from other players via sync were never checked",
        "  to actually be tomes -- a peer's bug could inject anything",
        "- New: Group by Tome / Zone / Mob (cycle button)",
        "- New: Zone filter dropdown, narrows any grouping to one zone",
        "- Search still matches tome, mob, or zone text in every mode",
        "",
        GOLD .. "2.19: Missing tab shows status dots" .. R,
        "- Green/red dot per row, same convention as the Affixes tab",
        "- New 'Show: All' / 'Show: Missing only' toggle (defaults to",
        "  showing everything for your class, owned + missing)",
        "- Owned rows show 'Learned' in green instead of a drop source",
        "- Count label: 'X learned, Y missing'",
        "",
        GOLD .. "2.18: no more duplicate build titles" .. R,
        "- Fixed the actual cause of Public Builds filling up with the",
        "  same title from many authors: editing an imported build",
        "  forked it under your name but kept the title + public flag",
        "- Saving/creating now checks if the title is already public",
        "  under someone else -- if so, unpublished + explained via popup",
        "- Existing duplicates already in the list get collapsed too",
        "  (earliest-known copy kept, both in the browser and relaying)",
        "",
        GOLD .. "2.17: Public Builds paging fix" .. R,
        "- Fixed: browsing got snapped back to page 1 every time a new",
        "  build arrived during a sync -- now stays on your page",
        "- Most noticeable after 2.15's all-classes sync, which streams",
        "  in many builds over several seconds",
        "",
        GOLD .. "2.16: Settings dialog expanded" .. R,
        "- Toast duration finally has an explanation (was missing one)",
        "- New checkboxes: Auto-sell junk, Bag affix dots -- same as",
        "  /ebb autosell / /ebb bagdots, now with a persistent UI too",
        "- Scrolls if it grows further -- can't overflow the window",
        "",
        GOLD .. "2.15: 'All Classes' sync no longer floods responders" .. R,
        "- Reload with 'All Classes' selected now asks each class",
        "  separately, 1.5s apart, instead of one giant unfiltered blast",
        "- Same coverage as before, just no more flooding every peer",
        "  with their entire collection at once",
        "- Still just one Reload click, same 30s cooldown",
        "",
        GOLD .. "2.14: FAQ window fixed" .. R,
        "- Fixed: this window's text could spill out past its own frame",
        "  and draw straight over your action bars / the game world",
        "  once a page got long enough (exactly what you're reading now",
        "  wasn't clipped before -- it is now: a real scrollbar).",
        "- Scroll with the mouse wheel or the bar on the right.",
        "",
        GOLD .. "2.13: faster, smaller syncs" .. R,
        "- Public Builds Reload now only fetches the class you have",
        "  selected in the dropdown (your class by default)",
        "- Pick 'All Classes' for the old everything-at-once behavior",
        "- Peers on older versions still work fine, just ignore the filter",
        "",
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

local frame, titleText, bodyText, scrollFrame, scrollChild, pageLabel, prevBtn, nextBtn
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
    scrollChild:SetHeight(math.max(scrollFrame:GetHeight(), textHeight + 4))
    scrollFrame:SetVerticalScroll(0)
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

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Page title with a thin gold rule underneath
    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -42)
    EbonBuilds.Theme.AddHeaderRule(f, titleText, 516)

    -- Scrollable body: leaves room on the right for the scrollbar and at
    -- the bottom for the Prev/Next/page-count row, and clips anything
    -- that doesn't fit -- unlike the old bare FontString, content can
    -- never draw outside this window regardless of how long a page is.
    scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsFAQSF", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 48)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(504)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    bodyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    bodyText:SetWidth(504)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")

    -- Mouse wheel scrolls content (UIPanelScrollFrameTemplate doesn't
    -- wire this up automatically for a plain Frame scroll child the way
    -- it does for an EditBox).
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local newScroll = self:GetVerticalScroll() - delta * 32
        self:SetVerticalScroll(math.max(0, math.min(newScroll, range)))
    end)

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
