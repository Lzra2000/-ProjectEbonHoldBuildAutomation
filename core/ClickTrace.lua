local addonName, EbonBuilds = ...

-- EbonBuilds: core/ClickTrace.lua
-- Diagnostic tool for exactly the situation that's been impossible to
-- debug without a screenshot: "I click a button and nothing happens."
-- Logs every button click (via a single hook in Theme.CreateButton, so it
-- covers the whole addon automatically) and every major view transition.
-- This tells us something a screenshot can't: whether the click is even
-- REACHING EbonBuilds at all.
--
--   Click logged, view didn't change  -> the click IS arriving, something
--                                        in that button's own handler is
--                                        wrong (a real logic bug to find).
--   Click NOT logged at all           -> something else is intercepting
--                                        the click before it reaches this
--                                        button (an overlay, a disabled
--                                        frame, wrong click coordinates).
-- Those are two completely different bugs requiring different fixes, and
-- this is the only way to tell them apart without watching it happen live.

EbonBuilds.ClickTrace = {}

local MAX_ENTRIES = 60
local enabled = false

local function DB()
    EbonBuildsCharDB.clickTrace = EbonBuildsCharDB.clickTrace or {}
    return EbonBuildsCharDB.clickTrace
end

function EbonBuilds.ClickTrace.SetEnabled(on)
    local newValue = on and true or false
    local changed = enabled ~= newValue
    enabled = newValue
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("clickTraceEnabled", enabled)
    elseif EbonBuildsCharDB then
        EbonBuildsCharDB.clickTraceEnabled = enabled
    end
    if enabled and changed then wipe(DB()) end
end

function EbonBuilds.ClickTrace.IsEnabled()
    return enabled
end

function EbonBuilds.ClickTrace.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        enabled = EbonBuilds.Database.GetCharacterPreference("clickTraceEnabled")
    else
        enabled = EbonBuildsCharDB and EbonBuildsCharDB.clickTraceEnabled == true or false
    end
end

local function Now()
    return date and date("%H:%M:%S") or "?"
end

-- kind: "click", "show", "hide" -- label: whatever identifies the widget
-- (button text, view/frame name).
function EbonBuilds.ClickTrace.Log(kind, label)
    if not enabled then return end
    local db = DB()
    table.insert(db, 1, string.format("%s  %-6s %s", Now(), kind, tostring(label or "?")))
    while #db > MAX_ENTRIES do table.remove(db) end
end

function EbonBuilds.ClickTrace.GetText()
    local db = DB()
    if #db == 0 then
        return enabled
            and "(nothing logged yet -- click around, then reopen this)"
            or "(off -- /ebb clicktrace to turn on, then click around and reopen this)"
    end
    return table.concat(db, "\n")
end

function EbonBuilds.ClickTrace.Clear()
    wipe(DB())
end

------------------------------------------------------------------------
-- Copyable window (same conventions as ErrorLog / DebugLog)
------------------------------------------------------------------------

local frame, editBox

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsClickTraceWindow", UIParent)
    f:SetSize(520, 420)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("DIALOG") -- not FULLSCREEN_DIALOG: this window itself
                                -- must never become the next "stuck overlay"
                                -- mystery, so it sits at the same layer as
                                -- the main window, not above it.
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Click Trace (Ctrl+C to copy)")

    local drag = CreateFrame("Frame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "ClickTrace.Drag")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    local sf = CreateFrame("ScrollFrame", "EbonBuildsClickTraceSF", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)

    editBox = CreateFrame("EditBox", nil, sf)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(editBox, "ClickTrace.EditBox")
    end
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(460)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(EbonBuilds.ClickTrace.GetText())
            self:HighlightText()
        end
    end)
    sf:SetScrollChild(editBox)

    local toggleBtn = EbonBuilds.Theme.CreateButton(f)
    toggleBtn:SetSize(110, 22)
    toggleBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    toggleBtn:SetScript("OnClick", function(self)
        EbonBuilds.ClickTrace.SetEnabled(not EbonBuilds.ClickTrace.IsEnabled())
        self:SetText(EbonBuilds.ClickTrace.IsEnabled() and "Tracing: ON" or "Tracing: OFF")
        editBox:SetText(EbonBuilds.ClickTrace.GetText())
    end)
    toggleBtn:SetText(enabled and "Tracing: ON" or "Tracing: OFF")

    local clearBtn = EbonBuilds.Theme.CreateButton(f)
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 8, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.ClickTrace.Clear()
        editBox:SetText(EbonBuilds.ClickTrace.GetText())
    end)

    tinsert(UISpecialFrames, "EbonBuildsClickTraceWindow")
    f:Hide()
    return f
end

function EbonBuilds.ClickTrace.ShowWindow()
    if not frame then frame = BuildWindow() end
    editBox:SetText(EbonBuilds.ClickTrace.GetText())
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
