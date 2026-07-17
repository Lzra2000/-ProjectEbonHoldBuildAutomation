-- EbonBuilds: modules/automation/ManualTraining.lua
-- Responsibility: opt-in "manual tuning mode." When enabled for a build,
-- Automation.Evaluate() never acts for that build (see the check added
-- there) -- the native perk UI shows after the usual brief delay, same
-- mechanism already used when automation is off, and the player picks by
-- hand. This module observes those picks via hooksecurefunc on
-- ProjectEbonhold.PerkService.SelectPerk and compares what was chosen
-- against what the CURRENT weights would have scored highest.
--
-- This is a genuinely different signal from EchoPerformance's DPS-based
-- weight suggestions: that one measures combat OUTCOME (how much damage
-- you did), noisy and confounded by fight variance. This one captures
-- revealed PREFERENCE (what a human actually chose to pick), a much
-- cleaner signal but a different kind of evidence -- it says "you value
-- this echo," not "this echo performs well." Both are offered; neither
-- replaces the other.

EbonBuilds.ManualTraining = {}

local MIN_DISAGREEMENTS_FOR_SUGGESTION = 3  -- how many times a pattern must repeat before it's worth a suggestion
local WEIGHT_NUDGE = 10                      -- same modest, fixed nudge as the DPS-based suggestions

local function GetStore(buildId)
    EbonBuildsCharDB.manualTraining = EbonBuildsCharDB.manualTraining or {}
    EbonBuildsCharDB.manualTraining[buildId] = EbonBuildsCharDB.manualTraining[buildId] or {
        preferredOverHigher = {},  -- [name] = count -- chosen despite a higher-scored alternative being offered
        passedOverForLower  = {},  -- [name] = count -- NOT chosen despite scoring higher than what was picked
        totalSelects = 0,
    }
    return EbonBuildsCharDB.manualTraining[buildId]
end

function EbonBuilds.ManualTraining.IsEnabled(build)
    return build and build.manualTrainingEnabled == true
end

function EbonBuilds.ManualTraining.SetEnabled(build, on)
    if not build then return end
    EbonBuilds.Build.Save(build.id, { manualTrainingEnabled = on and true or false })
end

function EbonBuilds.ManualTraining.Clear(buildId)
    if not buildId then return end
    EbonBuildsCharDB.manualTraining = EbonBuildsCharDB.manualTraining or {}
    EbonBuildsCharDB.manualTraining[buildId] = nil
end

function EbonBuilds.ManualTraining.GetSampleCount(buildId)
    if not buildId then return 0 end
    local store = EbonBuildsCharDB.manualTraining and EbonBuildsCharDB.manualTraining[buildId]
    return store and store.totalSelects or 0
end

-- Called (via hooksecurefunc) whenever ProjectEbonhold.PerkService.SelectPerk
-- runs, with the spellId the player picked. Compares it against the SAME
-- offered choices and scoring Automation.lua itself would have used.
local function OnPlayerSelect(pickedSpellId)
    local build = EbonBuilds.Build.GetActive()
    if not build or not EbonBuilds.ManualTraining.IsEnabled(build) then return end
    if not (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetCurrentChoice) then return end
    local choices = ProjectEbonhold.PerkService.GetCurrentChoice()
    if not choices or #choices == 0 then return end
    if not (EbonBuilds.Automation and EbonBuilds.Automation._ScoreChoice) then return end

    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local scored = {}
    local picked
    for _, choice in ipairs(choices) do
        local s = EbonBuilds.Automation._ScoreChoice(choice, settings)
        if s then
            scored[#scored + 1] = s
            if choice.spellId == pickedSpellId then picked = s end
        end
    end
    if not picked or #scored < 2 then return end

    local store = GetStore(build.id)
    store.totalSelects = store.totalSelects + 1
    for _, s in ipairs(scored) do
        if s ~= picked and s.score and picked.score and s.score > picked.score then
            store.preferredOverHigher[picked.name] = (store.preferredOverHigher[picked.name] or 0) + 1
            store.passedOverForLower[s.name] = (store.passedOverForLower[s.name] or 0) + 1
        end
    end
end

------------------------------------------------------------------------
-- Weight suggestions from revealed preference (report only, not
-- auto-applied -- same philosophy as the DPS-based ones: this is
-- evidence to weigh, not a verdict to trust blindly).
------------------------------------------------------------------------

-- Returns a sorted list of { name, direction = "raise"/"lower", count,
-- currentWeight, suggestedWeight }, strongest signal first.
function EbonBuilds.ManualTraining.SuggestWeightAdjustments(build)
    if not build then return {} end
    local store = EbonBuildsCharDB.manualTraining and EbonBuildsCharDB.manualTraining[build.id]
    if not store then return {} end

    local weights = build.echoWeights or {}
    local suggestions = {}
    for name, count in pairs(store.preferredOverHigher) do
        if count >= MIN_DISAGREEMENTS_FOR_SUGGESTION then
            local current = weights[name] or 0
            suggestions[#suggestions + 1] = {
                name = name, direction = "raise", count = count,
                currentWeight = current, suggestedWeight = current + WEIGHT_NUDGE,
            }
        end
    end
    for name, count in pairs(store.passedOverForLower) do
        if count >= MIN_DISAGREEMENTS_FOR_SUGGESTION then
            local current = weights[name] or 0
            suggestions[#suggestions + 1] = {
                name = name, direction = "lower", count = count,
                currentWeight = current, suggestedWeight = math.max(0, current - WEIGHT_NUDGE),
            }
        end
    end
    table.sort(suggestions, function(a, b) return a.count > b.count end)
    return suggestions
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

function EbonBuilds.ManualTraining.Init()
    if not (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.SelectPerk) then return end
    if ProjectEbonhold.PerkService._ebonBuildsTrainingHooked then return end
    hooksecurefunc(ProjectEbonhold.PerkService, "SelectPerk", function(spellId)
        local ok, err = pcall(OnPlayerSelect, spellId)
        if not ok and EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("ManualTraining.OnPlayerSelect", err)
        end
    end)
    ProjectEbonhold.PerkService._ebonBuildsTrainingHooked = true
end

-- Exported for unit testing
EbonBuilds.ManualTraining._OnPlayerSelect = OnPlayerSelect
