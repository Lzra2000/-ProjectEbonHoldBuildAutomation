-- EbonBuilds: modules/automation/DebugLog.lua
-- Captures automation decision traces into an in-memory buffer and shows
-- them in a copyable window, so problems can be pasted into a report
-- instead of described from memory.
--
--   /ebb debug      -> toggle capturing on/off
--   /ebb debuglog   -> open the copyable log window

EbonBuilds.DebugLog = {}

local MAX_LINES = 500

local enabled = false
local lines   = EbonBuilds.RingBuffer.New(MAX_LINES)

function EbonBuilds.DebugLog.IsEnabled()
    return enabled
end

function EbonBuilds.DebugLog.SetEnabled(on)
    local newValue = on and true or false
    local changed = enabled ~= newValue
    enabled = newValue
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("debugLogEnabled", enabled)
    elseif EbonBuildsCharDB then
        EbonBuildsCharDB.debugLogEnabled = enabled
    end
    if not changed then return end
    if enabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100EbonBuilds:|r debug capture ON. Use /ebb debuglog to view/copy.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100EbonBuilds:|r debug capture OFF.")
    end
end

function EbonBuilds.DebugLog.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        enabled = EbonBuilds.Database.GetCharacterPreference("debugLogEnabled")
    else
        enabled = EbonBuildsCharDB and EbonBuildsCharDB.debugLogEnabled == true or false
    end
end

function EbonBuilds.DebugLog.Toggle()
    EbonBuilds.DebugLog.SetEnabled(not enabled)
end

function EbonBuilds.DebugLog.Clear()
    EbonBuilds.RingBuffer.Clear(lines)
end

-- Appends one line (no color codes -- the buffer is meant to be pasted as
-- plain text). Cheap no-op while disabled.
function EbonBuilds.DebugLog.Add(text)
    if not enabled then return end
    EbonBuilds.RingBuffer.Append(lines, date("%H:%M:%S ") .. text)
end

function EbonBuilds.DebugLog.AddF(fmt, ...)
    if not enabled then return end
    EbonBuilds.DebugLog.Add(string.format(fmt, ...))
end

function EbonBuilds.DebugLog.GetText()
    if EbonBuilds.RingBuffer.Count(lines) == 0 then
        return "(debug log empty -- enable capture with /ebb debug, then trigger a choice screen)"
    end
    return table.concat(EbonBuilds.RingBuffer.ToArray(lines), "\n")
end

------------------------------------------------------------------------
-- Copyable window
------------------------------------------------------------------------

local frame, editBox

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsDebugLogWindow", UIParent)
    f:SetSize(560, 380)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Debug Log (Ctrl+C to copy)")

    local drag = CreateFrame("Frame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "DebugLog.Drag")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    local sf = CreateFrame("ScrollFrame", "EbonBuildsDebugLogSF", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)

    editBox = CreateFrame("EditBox", nil, sf)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(editBox, "DebugLog.EditBox")
    end
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(500)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only behavior: any typing restores the log text.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(EbonBuilds.DebugLog.GetText())
            self:HighlightText()
        end
    end)
    sf:SetScrollChild(editBox)

    local selectBtn = EbonBuilds.Theme.CreateButton(f)
    selectBtn:SetSize(100, 22)
    selectBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    local clearBtn = EbonBuilds.Theme.CreateButton(f)
    clearBtn:SetSize(100, 22)
    clearBtn:SetPoint("LEFT", selectBtn, "RIGHT", 8, 0)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.DebugLog.Clear()
        editBox:SetText(EbonBuilds.DebugLog.GetText())
    end)

    tinsert(UISpecialFrames, "EbonBuildsDebugLogWindow")
    f:Hide()
    return f
end

function EbonBuilds.DebugLog.ShowWindow()
    if not frame then frame = BuildWindow() end
    editBox:SetText(EbonBuilds.DebugLog.GetText())
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
