-- EbonBuilds: core/Debug.lua
-- Responsibility: ergonomic error-isolation, timing, and contract helpers
-- built on core/ErrorLog.lua, plus a lightweight self-test registry so
-- modules can add a sanity check without hand-editing tests/test_load.lua
-- or tests/test_features.lua.
--
-- Problems this exists to make cheaper than they were before:
--
-- 1. Wrapping every SetScript handler in ErrorLog.Protect by hand does not
--    scale. ProtectScript() lets a widget factory (Theme.CreateButton, etc.)
--    opt a frame in ONCE; every handler any caller attaches afterwards via
--    SetScript is wrapped automatically, with no per-call-site change
--    required anywhere else. It also watches for a handler firing
--    unexpectedly often (usually a sign of over-broad event registration)
--    without a profiler attached.
--
-- 2. New modules only get load/behavior coverage if someone remembers to
--    extend the big hand-written test files. RegisterTest() lets a module
--    register its own small self-check next to the code it's testing;
--    tests/test_selftests.lua runs every registered test in one pass, and
--    the same registry can be run live in-game (Error Log window ->
--    Self-Tests button) since none of it depends on a real WoW client.
--
-- 3. "This should never happen here" spots either get a silent bug or a
--    raw Lua error with no context. Assert() gives them a third option:
--    record to the Error Log and keep going.
--
-- 4. Debug.ShowHUD() is a small always-current window (Error Log -> HUD)
--    summarizing GetStats() -- protected-frame count, self-test pass rate,
--    error/spam-warning counts -- so the state of the addon's own
--    diagnostics is visible without digging through separate windows.

EbonBuilds.Debug = {}

local D = EbonBuilds.Debug
local registeredTests = {}
local protectedFrameCount = 0
local lastSelfTestSummary = nil
local spamWarningCount = 0

-- GetStats(): a few numbers for a diagnostic HUD or a bug report.
function D.GetStats()
    return {
        protectedFrameCount = protectedFrameCount,
        lastSelfTestSummary = lastSelfTestSummary,
        spamWarningCount = spamWarningCount,
        errorCount = EbonBuilds.ErrorLog and #EbonBuilds.ErrorLog.GetAll() or 0,
    }
end

-- Protect(source, fn): thin re-export of ErrorLog.Protect. Exists so call
-- sites can say EbonBuilds.Debug.Protect(...) consistently, without every
-- module needing to know Protect actually lives on ErrorLog.
function D.Protect(source, fn)
    return EbonBuilds.ErrorLog.Protect(source, fn)
end

-- Time(source, fn, thresholdMs): wraps fn so its execution time is
-- measured on every call; a call that exceeds thresholdMs (default 5)
-- gets recorded to the Error Log, the same place a caught error would go
-- -- so a slow handler shows up without a profiler attached. Does not
-- catch errors itself (composes with Protect: Protect(source,
-- Time(source, fn)) if both are wanted) -- keeping one responsibility per
-- wrapper makes each easier to reason about on its own.
function D.Time(source, fn, thresholdMs)
    thresholdMs = thresholdMs or 5
    return function(...)
        local start = debugprofilestop and debugprofilestop() or 0
        local results = { fn(...) }
        local elapsed = (debugprofilestop and debugprofilestop() or 0) - start
        if elapsed > thresholdMs then
            EbonBuilds.ErrorLog.Record((source or "?") .. ".slow",
                string.format("%.1fms (threshold %dms)", elapsed, thresholdMs))
        end
        return unpack(results)
    end
end

-- Assert(condition, message): for "this should never happen here" spots.
-- Records to the Error Log and returns false on failure instead of
-- raising -- a violated assumption shouldn't be able to crash a handler
-- any more than a caught error can. Returns true when condition holds.
function D.Assert(condition, message)
    if condition then return true end
    EbonBuilds.ErrorLog.Record("Assert", message or "assertion failed")
    return false
end

-- ProtectScript(frame, source): from this call on, every handler this frame
-- registers via SetScript is automatically wrapped in ErrorLog.Protect --
-- callers of the frame (anywhere else in the addon) don't have to remember
-- to wrap each OnClick/OnEnter/OnShow/etc by hand, and can't forget to.
-- Idempotent: calling it more than once on the same frame is a no-op after
-- the first call, so it's safe to call from a shared widget factory even if
-- a caller also calls it themselves.
-- A handler firing this many times inside one second is almost always a
-- sign of over-broad event registration (e.g. a frame reacting to every
-- BAG_UPDATE instead of filtering), not intended behavior. OnUpdate is
-- exempt since firing every frame is exactly what it's for.
local SPAM_THRESHOLD = 120
local SPAM_EXEMPT = { OnUpdate = true }

-- Wraps an already-Protect()'d handler with per-second call counting.
-- Warns (once per window, not once per call) the first time a window
-- crosses SPAM_THRESHOLD.
local function WrapWithSpamDetection(protectedHandler, source, scriptType)
    local windowStart, count, warned = 0, 0, false
    return function(...)
        local now = GetTime and GetTime() or 0
        if now - windowStart >= 1 then
            windowStart, count, warned = now, 0, false
        end
        count = count + 1
        if count == SPAM_THRESHOLD and not warned then
            warned = true
            spamWarningCount = spamWarningCount + 1
            EbonBuilds.ErrorLog.Record(source .. "." .. scriptType .. ".spam",
                "fired " .. SPAM_THRESHOLD .. "+ times within 1 second -- check event registration scope")
        end
        return protectedHandler(...)
    end
end

function D.ProtectScript(frame, source)
    if not frame or frame._ebonProtectedScript then return frame end
    frame._ebonProtectedScript = true
    protectedFrameCount = protectedFrameCount + 1
    local originalSetScript = frame.SetScript
    frame.SetScript = function(self, scriptType, handler, ...)
        if type(handler) == "function" then
            local protectedHandler = EbonBuilds.ErrorLog.Protect(
                (source or "?") .. "." .. tostring(scriptType), handler)
            if not SPAM_EXEMPT[scriptType] then
                protectedHandler = WrapWithSpamDetection(protectedHandler, source or "?", tostring(scriptType))
            end
            handler = protectedHandler
        end
        return originalSetScript(self, scriptType, handler, ...)
    end
    return frame
end

-- RegisterTest(name, fn): fn should error() (or return false) on failure and
-- return normally on success. Registration order is preserved so results
-- read top-to-bottom in the order modules were loaded.
function D.RegisterTest(name, fn)
    table.insert(registeredTests, { name = name, fn = fn })
end

-- RunSelfTests(): executes every registered test and returns a summary.
-- Used by tests/test_selftests.lua; the same registry can back an in-game
-- diagnostic command later without any test needing to be written twice.
function D.RunSelfTests()
    local passed, failed, results = 0, 0, {}
    for _, entry in ipairs(registeredTests) do
        local ok, err = pcall(entry.fn)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
        table.insert(results, { name = entry.name, ok = ok, err = err })
    end
    lastSelfTestSummary = { passed = passed, failed = failed, total = #registeredTests }
    return { passed = passed, failed = failed, total = #registeredTests, results = results }
end

-- ClearTests(): test-only. Lets a test file reset the registry between
-- independent runs in the same process instead of accumulating across them.
function D.ClearTests()
    registeredTests = {}
end

------------------------------------------------------------------------
-- Diagnostic HUD: a small always-current window summarizing GetStats().
-- Built here (not a separate UI file) since it's purely a view over this
-- module's own state -- same reasoning as AutoSell's keep-list window
-- living next to the data it manages.
------------------------------------------------------------------------

local hudFrame, hudLines

local function RefreshHUD()
    if not hudFrame then return end
    local stats = D.GetStats()
    local selfTestLine
    if stats.lastSelfTestSummary then
        selfTestLine = string.format("Self-tests: %d/%d passed (last run)",
            stats.lastSelfTestSummary.passed, stats.lastSelfTestSummary.total)
    else
        selfTestLine = "Self-tests: not run yet this session"
    end
    hudLines:SetText(table.concat({
        "Protected frames: " .. stats.protectedFrameCount,
        "Errors recorded: " .. stats.errorCount,
        "Spam warnings: " .. stats.spamWarningCount,
        selfTestLine,
    }, "\n"))
end

local function BuildHUD()
    local T = EbonBuilds.Theme
    local f = CreateFrame("Frame", "EbonBuildsDebugHUD", UIParent)
    D.ProtectScript(f, "Debug.HUD")
    f:SetSize(260, 150)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    T.ApplyWindow(f)
    f:Hide()

    local drag = CreateFrame("Frame", nil, f)
    D.ProtectScript(drag, "Debug.HUDDrag")
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("EbonBuilds Diagnostics")
    title:SetTextColor(unpack(T.ACCENT_GOLD))
    T.AddHeaderRule(f, title, 220)

    T.CreateCloseButton(f)

    hudLines = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hudLines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    hudLines:SetJustifyH("LEFT")
    hudLines:SetSpacing(4)

    f:SetScript("OnShow", RefreshHUD)
    hudFrame = f
    return f
end

-- ShowHUD(): opens the diagnostic HUD, building it on first use.
function D.ShowHUD()
    if not (EbonBuilds.Theme and EbonBuilds.Theme.ApplyWindow) then return end
    if not hudFrame then BuildHUD() end
    RefreshHUD()
    hudFrame:Show()
end

-- ToggleHUD(): convenience for a single button/keybind to open or close it.
function D.ToggleHUD()
    if hudFrame and hudFrame:IsShown() then
        hudFrame:Hide()
    else
        D.ShowHUD()
    end
end
