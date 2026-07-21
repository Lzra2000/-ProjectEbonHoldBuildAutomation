-- EbonBuilds: core/ErrorLog.lua
-- System-wide error monitoring, separate from the opt-in DebugLog
-- (modules/automation/DebugLog.lua). DebugLog only captures anything
-- while a player has remembered to turn /ebb debug on beforehand -- fine
-- for reproducing a KNOWN problem, useless for catching something that
-- broke silently and was never noticed. This is always on: a small
-- persistent ring buffer that any module can report into via Protect(),
-- so a bug report can start with "check /ebb errors" instead of "did you
-- have debug logging on when it happened?" (usually not).

EbonBuilds.ErrorLog = {}

local MAX_ERRORS = 20

local function DB()
    EbonBuildsCharDB.errorLog = EbonBuildsCharDB.errorLog or {}
    return EbonBuildsCharDB.errorLog
end

-- Records one error. Always available (no enabled/disabled toggle) --
-- errors are rare and small, there's no cost to always capturing them.
-- Also mirrors into the live debug log timeline when that's active, so an
-- error shows up alongside whatever decisions led to it.
function EbonBuilds.ErrorLog.Record(source, err)
    local entry = {
        time = date and date("%Y-%m-%d %H:%M:%S") or "?",
        source = source or "?",
        message = tostring(err),
    }
    local db = DB()
    table.insert(db, 1, entry)
    while #db > MAX_ERRORS do table.remove(db) end
    if EbonBuilds.DebugLog and EbonBuilds.DebugLog.IsEnabled and EbonBuilds.DebugLog.IsEnabled() then
        EbonBuilds.DebugLog.Add("ERROR [" .. entry.source .. "] " .. entry.message)
    end
    return entry
end

-- Wraps fn so any Lua error inside it is caught, recorded, and does NOT
-- propagate -- one broken handler (e.g. from an ElvUI version mismatch,
-- an unexpected nil somewhere) can't take down other handlers on the same
-- event/frame or spam the player's screen with a red error toast.
-- Returns a new function with the same call signature as fn.
function EbonBuilds.ErrorLog.Protect(source, fn)
    return function(...)
        local results = { pcall(fn, ...) }
        if not results[1] then
            EbonBuilds.ErrorLog.Record(source, results[2])
            return nil
        end
        return unpack(results, 2)
    end
end

function EbonBuilds.ErrorLog.GetAll()
    return DB()
end

function EbonBuilds.ErrorLog.Clear()
    wipe(DB())
end

------------------------------------------------------------------------
-- Copyable window (mirrors DebugLog's window, same conventions)
------------------------------------------------------------------------

local frame, editBox

function EbonBuilds.ErrorLog.GetText()
    local db = DB()
    if #db == 0 then
        return "(no errors recorded -- that's good)"
    end
    local lines = {}
    for _, e in ipairs(db) do
        lines[#lines + 1] = string.format("%s [%s] %s", e.time, e.source, e.message)
    end
    return table.concat(lines, "\n")
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsErrorLogWindow", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "ErrorLog.Window")
    end
    f:SetSize(560, 380)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Error Log (Ctrl+C to copy)")

    local drag = CreateFrame("Frame", nil, f)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "ErrorLog.WindowDrag")
    end
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = EbonBuilds.Theme.CreateCloseButton(f)

    local sf = CreateFrame("ScrollFrame", "EbonBuildsErrorLogSF", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)

    editBox = CreateFrame("EditBox", nil, sf)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(editBox, "ErrorLog.WindowEditBox")
    end
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(500)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(EbonBuilds.ErrorLog.GetText())
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
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.ErrorLog.Clear()
        editBox:SetText(EbonBuilds.ErrorLog.GetText())
    end)

    local selfTestStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfTestStatus:SetPoint("RIGHT", f, "BOTTOMRIGHT", -12, 22)

    local selfTestBtn = EbonBuilds.Theme.CreateButton(f)
    selfTestBtn:SetSize(100, 22)
    selfTestBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    selfTestBtn:SetText("Self-Tests")
    selfTestBtn:SetScript("OnClick", function()
        if not (EbonBuilds.Debug and EbonBuilds.Debug.RunSelfTests) then
            selfTestStatus:SetText("Self-test registry unavailable.")
            return
        end
        local summary = EbonBuilds.Debug.RunSelfTests()
        for _, result in ipairs(summary.results) do
            if not result.ok then
                EbonBuilds.ErrorLog.Record("SelfTest: " .. result.name, result.err)
            end
        end
        editBox:SetText(EbonBuilds.ErrorLog.GetText())
        if summary.failed == 0 then
            selfTestStatus:SetTextColor(unpack(EbonBuilds.Theme.SUCCESS))
        else
            selfTestStatus:SetTextColor(unpack(EbonBuilds.Theme.DANGER))
        end
        selfTestStatus:SetText(string.format("%d/%d self-tests passed", summary.passed, summary.total))
    end)

    local hudBtn = EbonBuilds.Theme.CreateButton(f)
    hudBtn:SetSize(80, 22)
    hudBtn:SetPoint("LEFT", selfTestBtn, "RIGHT", 8, 0)
    hudBtn:SetText("HUD")
    hudBtn:SetScript("OnClick", function()
        if EbonBuilds.Debug and EbonBuilds.Debug.ToggleHUD then EbonBuilds.Debug.ToggleHUD() end
    end)

    tinsert(UISpecialFrames, "EbonBuildsErrorLogWindow")
    f:Hide()
    return f
end

function EbonBuilds.ErrorLog.ShowWindow()
    if not frame then frame = BuildWindow() end
    editBox:SetText(EbonBuilds.ErrorLog.GetText())
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
