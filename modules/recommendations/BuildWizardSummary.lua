local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/BuildWizardSummary.lua
-- Bounded, revision-cached summaries for the Build Wizard shell and review.

EbonBuilds.BuildWizardSummary = {}

local Summary = EbonBuilds.BuildWizardSummary

function Summary.Compute(draft)
    if not draft then return nil end
    local revision = tonumber(draft.revision) or 0
    if draft._summaryCache and draft._summaryCache.draftRevision == revision then
        return draft._summaryCache
    end

    local out = {
        draftRevision = revision,
        lockedCount = 0,
        includedCount = 0,
        manualLockCount = 0,
        changedPriorityCount = 0,
        excludedRecommendedCount = 0,
        promotedAvoidCount = 0,
        avoidPolicyCount = 0,
        distribution = { Essential = 0, Strong = 0, Useful = 0, Neutral = 0, Avoid = 0 },
    }

    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local lock = draft.locks and draft.locks[slot]
        if lock then
            out.lockedCount = out.lockedCount + 1
            if lock.ownership == "manual" then out.manualLockCount = out.manualLockCount + 1 end
        end
    end

    for _, name in ipairs(draft.echoOrder or {}) do
        local echo = draft.echoes and draft.echoes[name]
        if echo then
            if echo.included then out.includedCount = out.includedCount + 1 end
            local modified = echo.included ~= echo.suggestedIncluded or echo.importance ~= echo.suggestedImportance
            if echo.included or echo.sourceKind ~= "catalog" or modified then
                out.distribution[echo.importance or "Neutral"] = (out.distribution[echo.importance or "Neutral"] or 0) + 1
            end
            if modified then
                out.changedPriorityCount = out.changedPriorityCount + 1
            end
            if echo.sourceKind == "priority" and echo.suggestedIncluded and not echo.included then
                out.excludedRecommendedCount = out.excludedRecommendedCount + 1
            end
            if echo.sourceKind == "avoid" and echo.included and echo.importance ~= "Avoid" then
                out.promotedAvoidCount = out.promotedAvoidCount + 1
            end
            if echo.importance == "Avoid" then
                out.avoidPolicyCount = out.avoidPolicyCount + 1
            end
        end
    end

    out.intentLabel = EbonBuilds.WizardPresets and EbonBuilds.WizardPresets.Label(draft.intentKey) or tostring(draft.intentKey or "Community")
    out.scoringLabel = draft.scoringStyle or "Recommendation-focused"
    out.confidenceLevel = draft.confidence or "insufficient"
    if EbonBuilds.BuildWizardEvidence then
        local _, label = EbonBuilds.BuildWizardEvidence.CohortConfidence(draft.originCount or 0)
        out.confidenceText = label
    else
        out.confidenceText = tostring(draft.originCount or 0) .. " origins"
    end

    draft._summaryCache = out
    return out
end
