local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/FAQView.lua
-- In-game FAQ / "what's new" (/ebb faq): clean paginated window with one
-- topic per page, plus a one-time chat notice when the version changes.
-- Content is generated from FAQ.md at release time (build-faq-pages.sh).

EbonBuilds.FAQ = {}

local GOLD = "|cffffd100"
local R = "|r"

------------------------------------------------------------------------
-- Pages (one topic each, kept short enough to fit without scrolling)
------------------------------------------------------------------------

-- Pages are GENERATED from FAQ.md by scripts/build-faq-pages.sh (run
-- by release.sh), so the in-game FAQ can no longer drift from the
-- shipped document -- it had been showing 2.99 content at 3.30.
local PAGES = (EbonBuilds.FAQContent and EbonBuilds.FAQContent.PAGES) or {
    { title = "FAQ unavailable", lines = { "FAQ content failed to load; see FAQ.md on GitHub." } },
}
local CATEGORIES = (EbonBuilds.FAQContent and EbonBuilds.FAQContent.CATEGORIES) or {}

-- First page index belonging to a category, so the category dropdown can
-- jump straight there instead of the player clicking Next dozens of times.
local function FirstPageForCategory(category)
    for i, p in ipairs(PAGES) do
        if p.category == category then return i end
    end
    return 1
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local frame, titleText, bodyText, scrollFrame, scrollChild, scrollBar, pageLabel, prevBtn, nextBtn
local categoryDropdown
local page = 1

local function RenderPage()
    local p = PAGES[page]
    if not p then return end
    titleText:SetText(GOLD .. p.title .. R)
    if categoryDropdown and p.category then
        categoryDropdown:SetText(p.category)
    end
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "FAQView.Window")
    end
    f:SetSize(560, 504)
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
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "FAQView.WindowDrag")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    -- Jump-to-category row: with 51 FAQ pages across 7 categories, pure
    -- linear Prev/Next made finding a specific topic mean clicking Next
    -- dozens of times. This jumps straight to a category's first page.
    local jumpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    jumpLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -38)
    jumpLabel:SetText("Jump to:")
    jumpLabel:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))

    categoryDropdown = EbonBuilds.Theme.CreateDropdown(f, 260, CATEGORIES[1] or "Topics")
    categoryDropdown:SetPoint("LEFT", jumpLabel, "RIGHT", 8, 0)
    categoryDropdown:SetMenuBuilder(function()
        local items = {}
        for _, cat in ipairs(CATEGORIES) do
            items[#items + 1] = {
                text = cat,
                checked = PAGES[page] and PAGES[page].category == cat,
                func = function()
                    page = FirstPageForCategory(cat)
                    RenderPage()
                end,
            }
        end
        return items
    end)

    -- Page title with a thin gold rule underneath.
    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -68)
    EbonBuilds.Theme.AddHeaderRule(f, titleText, 516)

    -- Scrollable body: leaves room on the right for the scrollbar and at
    -- the bottom for the Prev/Next/page-count row, and clips anything
    -- that doesn't fit -- unlike the old bare FontString, content can
    -- never draw outside this window regardless of how long a page is.
    scrollFrame = CreateFrame("ScrollFrame", "EbonBuildsFAQSF", f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -104)
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
