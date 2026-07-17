-- EbonBuilds: modules/automation/Calibration.lua
-- Self-calibrating threshold advisor.
--
-- Automation's banish/reroll/freeze thresholds are set as a % of a
-- THEORETICAL peak/mean/EV computed from the build's own scoring weights
-- (Scoring.lua). That's a reasonable starting point, but it says nothing
-- about what you're ACTUALLY being offered on this server, with this
-- build's real weight tuning, over hundreds of picks. This module records
-- the score of every echo actually offered (as a % of that evaluation's
-- peak) into a persistent, capped sample buffer, then answers "if I want
-- this threshold to reject/trigger on roughly N% of what I'm really
-- offered, what value should that be?" from the real observed
-- distribution instead of the theoretical one.
--
-- Supports both Classic mode (autoBanishPct/autoRerollPct/autoFreezePct,
-- all already a % of peak -- the same space samples are recorded in) and
-- Smart/EV mode (banishEVPct/freezeEVPct, a % of mean/evBest3 instead --
-- converted via the current mean/peak or evBest3/peak ratio so both modes
-- can be analyzed against the same sample data).
--
-- NOT supported: Smart Reroll (rerollEVPct). Its effective threshold is
-- scaled by a "pacing" factor that changes through a run based on
-- remaining reroll charges (see Automation.lua) -- there's no single
-- static value to suggest without also modeling charge state, which is
-- out of scope here.

EbonBuilds.Calibration = {}

local MAX_SAMPLES = 2000
local MIN_SAMPLES_FOR_SUGGESTION = 30

local function GetStore()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.samples = EbonBuildsCharDB.calibration.samples or {}
    return EbonBuildsCharDB.calibration.samples
end

-- Separate store: one sample per EVALUATION (not per offered echo) of the
-- best offered score, with that evaluation's charge-pacing multiplier
-- divided back out. Reroll (Smart mode) decides based on "best offered
-- vs threshold", not individual echo scores, so it needs its own sample
-- space -- and since the effective threshold moves with remaining
-- charges, normalizing pacing out is what makes samples from different
-- points in a run comparable to each other at all.
local function GetBestStore()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.bestSamples = EbonBuildsCharDB.calibration.bestSamples or {}
    return EbonBuildsCharDB.calibration.bestSamples
end

-- Called once per evaluation, with the best offered echo's score (as a
-- % of peak) divided by that evaluation's reroll pacing multiplier.
function EbonBuilds.Calibration.RecordBestSample(normalizedPct)
    if not normalizedPct or normalizedPct < 0 then return end
    local store = GetBestStore()
    store[#store + 1] = normalizedPct
    if #store > MAX_SAMPLES then
        table.remove(store, 1)
    end
end

-- Called once per offered echo during automation evaluation, with its
-- score as a percentage of that evaluation's peak (0-100+, can exceed
-- 100 for an echo scored above the cached peak). Cheap: no sorting or
-- analysis happens here, just an append + cap.
function EbonBuilds.Calibration.RecordSample(pct)
    if not pct or pct < 0 then return end
    local store = GetStore()
    store[#store + 1] = pct
    if #store > MAX_SAMPLES then
        table.remove(store, 1)
    end
end

function EbonBuilds.Calibration.SampleCount()
    return #GetStore()
end

function EbonBuilds.Calibration.BestSampleCount()
    return #GetBestStore()
end

function EbonBuilds.Calibration.Clear()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.samples = {}
    EbonBuildsCharDB.calibration.bestSamples = {}
end

------------------------------------------------------------------------
-- Continuous auto-tune (opt-in)
--
-- Off by default. When enabled, thresholds don't just get SUGGESTED --
-- every TUNE_INTERVAL_SAMPLES newly-collected samples, each supported
-- metric takes one gradual step (TUNE_STEP fraction of the gap) toward
-- its suggested value and saves to the active build automatically.
-- Gradual and rate-limited on purpose: jumping straight to a suggestion
-- computed from a small, noisy recent batch would overreact and could
-- oscillate; small repeated steps converge toward the real distribution
-- as more data accumulates and self-correct if the distribution shifts
-- (new build, different content, etc.) without ever making a single
-- drastic change to live automation behavior.
------------------------------------------------------------------------

local TUNE_STEP = 0.25             -- close 25% of the gap per adjustment
local TUNE_INTERVAL_SAMPLES = 20   -- newly-collected samples between passes
local TUNE_MIN_GAP = 1.5           -- ignore gaps smaller than this (percentage points)

function EbonBuilds.Calibration.IsAutoTuneEnabled()
    return EbonBuildsCharDB.calibration and EbonBuildsCharDB.calibration.autoTuneEnabled == true
end

function EbonBuilds.Calibration.SetAutoTuneEnabled(on)
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.autoTuneEnabled = on and true or false
    EbonBuildsCharDB.calibration.samplesSinceLastTune = 0
end

-- Value at the given percentile (0-100) of an already-sorted list.
local function Percentile(sorted, p)
    if #sorted == 0 then return 0 end
    local idx = math.max(1, math.min(#sorted, math.ceil(p / 100 * #sorted)))
    return sorted[idx]
end

-- What % of samples fall strictly below a given threshold value.
local function FractionBelow(sorted, threshold)
    if #sorted == 0 then return 0 end
    local count = 0
    for _, v in ipairs(sorted) do
        if v < threshold then count = count + 1 end
    end
    return count / #sorted * 100
end

-- Core analysis, worked entirely in "% of peak" space (the space samples
-- are recorded in). direction "below" = Banish/Reroll (triggers under the
-- threshold, target = % you want rejected). direction "above" = Freeze
-- (triggers over the threshold, target = % you want it to catch).
local function BuildSuggestion(currentPctOfPeak, targetFraction, direction, store)
    store = store or GetStore()
    local result = {
        sampleCount = #store,
        currentPctOfPeak = currentPctOfPeak,
        targetFraction = targetFraction,
        direction = direction,
    }
    if #store < MIN_SAMPLES_FOR_SUGGESTION then
        result.insufficientData = true
        return result
    end
    local sorted = {}
    for i, v in ipairs(store) do sorted[i] = v end
    table.sort(sorted)

    local fractionBelow = FractionBelow(sorted, currentPctOfPeak)
    if direction == "above" then
        result.currentFraction   = 100 - fractionBelow
        result.suggestedPctOfPeak = Percentile(sorted, 100 - targetFraction)
    else
        result.currentFraction   = fractionBelow
        result.suggestedPctOfPeak = Percentile(sorted, targetFraction)
    end
    return result
end

------------------------------------------------------------------------
-- Classic mode: settings fields are already a % of peak, no conversion.
------------------------------------------------------------------------

-- Target: reject roughly the bottom 15% of what's actually offered.
function EbonBuilds.Calibration.SuggestBanish(settings)
    local r = BuildSuggestion(settings.autoBanishPct or 0, 15, "below")
    r.currentFieldPct = settings.autoBanishPct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

-- Target: reroll offers landing in the bottom ~45% (proxy for the real
-- sum-of-three check Automation.lua uses -- not an exact match, but
-- directionally useful).
function EbonBuilds.Calibration.SuggestReroll(settings)
    local r = BuildSuggestion(settings.autoRerollPct or 0, 45, "below")
    r.currentFieldPct = settings.autoRerollPct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

-- Target: catch roughly the top 10% of what's offered.
function EbonBuilds.Calibration.SuggestFreeze(settings)
    local r = BuildSuggestion(settings.autoFreezePct or 0, 10, "above")
    r.currentFieldPct = settings.autoFreezePct or 0
    r.suggestedFieldPct = r.suggestedPctOfPeak
    return r
end

------------------------------------------------------------------------
-- Smart (EV) mode: fields are a % of a DIFFERENT baseline (mean or
-- evBest3), not peak directly. Convert via that baseline's current
-- ratio to peak (from the live scoring model), analyze in peak-relative
-- space to match the sample data, then convert the suggestion back.
------------------------------------------------------------------------

local function SuggestSmart(currentFieldPct, baselineRatio, targetFraction, direction)
    if not baselineRatio or baselineRatio <= 0 then
        return { insufficientData = true, sampleCount = EbonBuilds.Calibration.SampleCount() }
    end
    local r = BuildSuggestion(currentFieldPct * baselineRatio, targetFraction, direction)
    r.currentFieldPct = currentFieldPct
    if not r.insufficientData then
        r.suggestedFieldPct = r.suggestedPctOfPeak / baselineRatio
    end
    return r
end

function EbonBuilds.Calibration.SuggestSmartBanish(settings)
    local stats = EbonBuilds.Automation.GetOutcomeStats()
    local peak  = EbonBuilds.Automation.GetPeak()
    local ratio = (peak and peak > 0 and stats.mean) and (stats.mean / peak) or nil
    return SuggestSmart(settings.banishEVPct or 60, ratio, 15, "below")
end

function EbonBuilds.Calibration.SuggestSmartFreeze(settings)
    local stats = EbonBuilds.Automation.GetOutcomeStats()
    local peak  = EbonBuilds.Automation.GetPeak()
    local ratio = (peak and peak > 0 and stats.evBest3) and (stats.evBest3 / peak) or nil
    return SuggestSmart(settings.freezeEVPct or 110, ratio, 10, "above")
end

-- Smart Reroll, finally supported: samples in bestSamples already have
-- each evaluation's pacing multiplier divided out (see Automation.lua's
-- reroll-check hook and RecordBestSample above), so comparing against
-- them is equivalent to asking "what would this threshold do at full
-- pacing (8+ charges)?" -- the live threshold at any given charge count
-- still scales the same way as before via ChargePacing; this only
-- fixes what the SUGGESTION itself is calculated from.
function EbonBuilds.Calibration.SuggestSmartReroll(settings)
    local ev   = EbonBuilds.Automation.GetRerollEV()
    local peak = EbonBuilds.Automation.GetPeak()
    if not (peak and peak > 0 and ev and ev > 0) then
        return { insufficientData = true, sampleCount = EbonBuilds.Calibration.BestSampleCount() }
    end
    local ratio = ev / peak
    local currentFieldPct = settings.rerollEVPct or 95
    local r = BuildSuggestion(currentFieldPct * ratio, 45, "below", GetBestStore())
    r.currentFieldPct = currentFieldPct
    if not r.insufficientData then
        r.suggestedFieldPct = r.suggestedPctOfPeak / ratio
    end
    return r
end

------------------------------------------------------------------------
-- Auto-tune pass (see the opt-in block above for the rationale)
------------------------------------------------------------------------

-- One gradual step for a single metric: nudges `field` by TUNE_STEP of
-- the gap to its suggestion. Returns true if it actually changed anything.
local function StepField(settings, result, field)
    if result.insufficientData then return false end
    local gap = result.suggestedFieldPct - result.currentFieldPct
    if math.abs(gap) < TUNE_MIN_GAP then return false end
    local newValue = result.currentFieldPct + gap * TUNE_STEP
    settings[field] = math.floor(newValue + 0.5)
    return true, settings[field]
end

-- Called after every recorded sample. Cheap check (a counter compare) on
-- every call; the actual analysis (sorting samples, computing suggestions)
-- only runs once every TUNE_INTERVAL_SAMPLES, and only if the player has
-- opted in.
function EbonBuilds.Calibration.MaybeAutoTune()
    if not EbonBuilds.Calibration.IsAutoTuneEnabled() then return end
    EbonBuildsCharDB.calibration.samplesSinceLastTune = (EbonBuildsCharDB.calibration.samplesSinceLastTune or 0) + 1
    if EbonBuildsCharDB.calibration.samplesSinceLastTune < TUNE_INTERVAL_SAMPLES then return end
    EbonBuildsCharDB.calibration.samplesSinceLastTune = 0

    local build = EbonBuilds.Build.GetActive()
    if not build then return end
    local liveSettings = build.settings or EbonBuilds.Build.DefaultSettings()
    local settings = EbonBuilds.Build.CloneSettings(liveSettings)
    local isSmart = (liveSettings.rerollMode or "sum") == "ev"

    local changed = {}
    local okB, valB = StepField(settings,
        isSmart and EbonBuilds.Calibration.SuggestSmartBanish(liveSettings) or EbonBuilds.Calibration.SuggestBanish(liveSettings),
        isSmart and "banishEVPct" or "autoBanishPct")
    if okB then changed[#changed + 1] = ("Banish " .. valB .. "%") end

    local okF, valF = StepField(settings,
        isSmart and EbonBuilds.Calibration.SuggestSmartFreeze(liveSettings) or EbonBuilds.Calibration.SuggestFreeze(liveSettings),
        isSmart and "freezeEVPct" or "autoFreezePct")
    if okF then changed[#changed + 1] = ("Freeze " .. valF .. "%") end

    if not isSmart then
        local okR, valR = StepField(settings, EbonBuilds.Calibration.SuggestReroll(liveSettings), "autoRerollPct")
        if okR then changed[#changed + 1] = ("Reroll " .. valR .. "%") end
    else
        local okR, valR = StepField(settings, EbonBuilds.Calibration.SuggestSmartReroll(liveSettings), "rerollEVPct")
        if okR then changed[#changed + 1] = ("Reroll " .. valR .. "%") end
    end

    if #changed == 0 then return end

    local saved = EbonBuilds.Build.Save(build.id, { settings = settings })
    if not saved then return end

    local summary = table.concat(changed, ", ")
    if EbonBuilds.Toast then
        EbonBuilds.Toast.Show("Auto-tuned: " .. summary)
    end
    if EbonBuilds.DebugLog and EbonBuilds.DebugLog.IsEnabled() then
        EbonBuilds.DebugLog.AddF("-> AUTO-TUNE: %s", summary)
    end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function ApplySuggestion(field, value)
    local build = EbonBuilds.Build.GetActive()
    if not build then return false end
    local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
    settings[field] = math.floor(value + 0.5)
    local saved = EbonBuilds.Build.Save(build.id, { settings = settings })
    return saved ~= nil
end

local frame, countLabel, modeWarning
local banishRow, rerollRow, freezeRow

local function BuildRow(parent, yOffset, label)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    title:SetText(label)

    local current = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    current:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    current:SetWidth(480)
    current:SetJustifyH("LEFT")

    local suggestion = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suggestion:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -4)
    suggestion:SetWidth(400)
    suggestion:SetJustifyH("LEFT")

    local applyBtn = EbonBuilds.Theme.CreateButton(parent)
    applyBtn:SetSize(90, 20)
    applyBtn:SetPoint("LEFT", suggestion, "RIGHT", 8, 0)

    return { title = title, current = current, suggestion = suggestion, applyBtn = applyBtn }
end

local function ClearRow(row, text)
    row.current:SetText(text or "")
    row.suggestion:SetText("")
    row.applyBtn:Hide()
end

local function RefreshRow(row, result, field, unitLabel)
    local verb = result.direction == "above" and "triggers on" or "rejects"
    if result.insufficientData then
        row.current:SetText(string.format("|cff888888Collecting data... (%d / %d samples needed)|r",
            result.sampleCount, MIN_SAMPLES_FOR_SUGGESTION))
        row.suggestion:SetText("")
        row.applyBtn:Hide()
        return
    end
    row.current:SetText(string.format("Current: %.0f%% -- %s ~%.0f%% of what you're actually offered (%d samples)",
        result.currentFieldPct, verb, result.currentFraction, result.sampleCount))
    if math.abs(result.suggestedFieldPct - result.currentFieldPct) < 1 then
        row.suggestion:SetText(string.format("|cff1eff00Already close to the %s target (~%.0f%%).|r", unitLabel, result.targetFraction))
        row.applyBtn:Hide()
    else
        row.suggestion:SetText(string.format("Suggested: |cffffd100%.0f%%|r to target ~%.0f%% %s",
            result.suggestedFieldPct, result.targetFraction, result.direction == "above" and "caught" or "rejected"))
        row.applyBtn:SetText(string.format("Apply %.0f%%", result.suggestedFieldPct))
        row.applyBtn:Show()
        row.applyBtn:SetScript("OnClick", function()
            if ApplySuggestion(field, result.suggestedFieldPct) then
                EbonBuilds.Toast.Show(string.format("%s threshold set to %.0f%%", unitLabel, result.suggestedFieldPct))
                EbonBuilds.Calibration.RefreshWindow()
            end
        end)
    end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsTuningAdvisorWindow", UIParent)
    f:SetSize(560, 440)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Tuning Advisor")

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

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    subtitle:SetWidth(528)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Compares your current thresholds against what your build actually gets offered, and suggests values based on the real distribution instead of the theoretical scoring model. Works with both Classic and Smart (EV) mode.")
    -- No fixed SetHeight: this text needs 3 lines at this width, and a
    -- height sized for 2 (28px) clipped the third line instead of
    -- showing it. Auto-sizing to the wrapped content is safe here --
    -- banishRow/rerollRow/freezeRow below all anchor to fixed offsets
    -- from the window itself, not chained to subtitle, so subtitle
    -- growing a bit taller doesn't push anything else out of place.

    modeWarning = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeWarning:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    modeWarning:SetWidth(500)
    modeWarning:SetJustifyH("LEFT")
    modeWarning:SetTextColor(1, 0.6, 0.2, 1)

    banishRow = BuildRow(f, -160, "Banish")
    rerollRow = BuildRow(f, -220, "Reroll")
    freezeRow = BuildRow(f, -280, "Freeze")

    local autoTuneCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    autoTuneCB:SetWidth(24)
    autoTuneCB:SetHeight(24)
    autoTuneCB:SetPoint("TOPLEFT", freezeRow.suggestion, "BOTTOMLEFT", -4, -10)
    local autoTuneLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoTuneLabel:SetPoint("LEFT", autoTuneCB, "RIGHT", 2, 0)
    autoTuneLabel:SetText("Continuous auto-tune")
    autoTuneCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Continuous auto-tune", 1, 1, 1)
        GameTooltip:AddLine("Off by default. When on, thresholds nudge themselves toward their suggested value automatically -- a small step (25% of the gap) every ~20 newly-recorded offers, not an instant jump. You'll get a toast every time it actually changes something. Rate-limited and gradual on purpose, so it can't overreact to a short noisy streak or make one drastic change to live automation behavior.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoTuneCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoTuneCB:SetScript("OnClick", function(self)
        EbonBuilds.Calibration.SetAutoTuneEnabled(self:GetChecked() and true or false)
    end)

    local perfCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    perfCB:SetWidth(24)
    perfCB:SetHeight(24)
    perfCB:SetPoint("TOPLEFT", autoTuneCB, "BOTTOMLEFT", 0, -6)
    local perfLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    perfLabel:SetPoint("LEFT", perfCB, "RIGHT", 2, 0)
    perfLabel:SetText("Track + share DPS by echo (needs Details!)")
    perfCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Track + share DPS by echo", 1, 1, 1)
        GameTooltip:AddLine("Off by default. Requires the Details! damage meter addon. Every 10s in combat, samples your current DPS and credits it to every echo you currently have active, building a rough real-performance average per echo over time.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Also shares this with other EbonBuilds users of the SAME class over the sync channel, and merges what they share back into your own data -- aggregate numbers only (per-echo average + sample count), never raw combat logs. Both directions use the same toggle. Received data is sanity-checked and can't be inflated by someone re-sending the same numbers.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Approximate on purpose either way: echoes stack together and fights vary a lot, so this can't isolate any single echo's true effect. A rough signal to combine with the scoring model, not a precise measurement. Shown in Export (AI) once you've collected some data.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    perfCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    perfCB:SetScript("OnClick", function(self)
        if self:GetChecked() and not EbonBuilds.EchoPerformance.IsDetailsAvailable() then
            EbonBuilds.Toast.Show("Details! not found -- install it to use DPS tracking")
            self:SetChecked(false)
            return
        end
        EbonBuilds.EchoPerformance.SetEnabled(self:GetChecked() and true or false)
    end)

    local clearBtn = EbonBuilds.Theme.CreateButton(f, "danger")
    clearBtn:SetSize(140, 20)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    clearBtn:SetText("Clear Collected Data")
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Wipes recorded samples. Worth doing after a major reweight, since old samples reflect the previous weighting.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.Calibration.Clear()
        EbonBuilds.Calibration.RefreshWindow()
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)

    f._autoTuneCB = autoTuneCB
    f._perfCB = perfCB
    tinsert(UISpecialFrames, "EbonBuildsTuningAdvisorWindow")
    f:Hide()
    return f
end

function EbonBuilds.Calibration.RefreshWindow()
    if not frame then return end
    if frame._autoTuneCB then
        frame._autoTuneCB:SetChecked(EbonBuilds.Calibration.IsAutoTuneEnabled())
    end
    if frame._perfCB then
        frame._perfCB:SetChecked(EbonBuilds.EchoPerformance.IsEnabled())
    end
    local build = EbonBuilds.Build.GetActive()
    if not build then
        modeWarning:SetText("No active build selected.")
        ClearRow(banishRow)
        ClearRow(rerollRow)
        ClearRow(freezeRow)
        countLabel:SetText("")
        return
    end
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    if (settings.rerollMode or "sum") == "ev" then
        modeWarning:SetText("Smart (EV) mode.")
        RefreshRow(banishRow, EbonBuilds.Calibration.SuggestSmartBanish(settings), "banishEVPct", "Smart Banish")
        RefreshRow(rerollRow, EbonBuilds.Calibration.SuggestSmartReroll(settings), "rerollEVPct", "Smart Reroll")
        RefreshRow(freezeRow, EbonBuilds.Calibration.SuggestSmartFreeze(settings), "freezeEVPct", "Smart Freeze")
    else
        modeWarning:SetText("Classic mode.")
        RefreshRow(banishRow, EbonBuilds.Calibration.SuggestBanish(settings), "autoBanishPct", "Banish")
        RefreshRow(rerollRow, EbonBuilds.Calibration.SuggestReroll(settings), "autoRerollPct", "Reroll")
        RefreshRow(freezeRow, EbonBuilds.Calibration.SuggestFreeze(settings), "autoFreezePct", "Freeze")
    end
    local countText = string.format("%d samples (%d best-offer) collected for %s",
        EbonBuilds.Calibration.SampleCount(), EbonBuilds.Calibration.BestSampleCount(), build.title or "this build")
    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled() then
        local weightSuggestions = EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
        if #weightSuggestions > 0 then
            countText = countText .. string.format(" -- %d weight suggestion(s) available, see Export (AI)", #weightSuggestions)
        end
    end
    countLabel:SetText(countText)
end

function EbonBuilds.Calibration.ShowWindow()
    if not frame then frame = BuildWindow() end
    EbonBuilds.Calibration.RefreshWindow()
    frame:Show()
end
