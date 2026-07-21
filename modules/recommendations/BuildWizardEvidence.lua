local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/BuildWizardEvidence.lua
-- Converts bounded integer community counts into honest player-facing labels.

EbonBuilds.BuildWizardEvidence = {}

local Evidence = EbonBuilds.BuildWizardEvidence

function Evidence.CohortConfidence(originCount)
    originCount = tonumber(originCount) or 0
    if originCount >= 20 then return "strong", "Strong local sample" end
    if originCount >= 8 then return "moderate", "Moderate local sample" end
    if originCount >= 3 then return "limited", "Limited local sample" end
    return "insufficient", "Insufficient local sample"
end

local function Counts(item, sourceKind)
    item = item or {}
    local total = tonumber(item.observedOrigins) or 0
    if sourceKind == "lock" then return tonumber(item.lockOrigins) or 0, total end
    if sourceKind == "avoid" then return tonumber(item.negativeOrigins) or 0, total end
    if sourceKind == "defensive" then
        return tonumber(item.defensivePositiveOrigins) or 0, tonumber(item.defensiveOrigins) or 0
    end
    return tonumber(item.positiveOrigins) or 0, total
end

function Evidence.Classify(item, sourceKind)
    if not item then return "none", "No evidence" end
    local support, total = Counts(item, sourceKind)
    local positive = tonumber(item.positiveOrigins) or 0
    local negative = tonumber(item.negativeOrigins) or 0

    if sourceKind == "avoid" then
        if support >= 3 and total > 0 and support / total >= 0.50 then return "negative", "Strong negative" end
        if support >= 2 then return "negative", "Negative tendency" end
        return "limited", "Limited evidence"
    end

    if sourceKind ~= "lock" and positive > 0 and negative > 0 and math.abs(positive - negative) <= 1 then
        return "mixed", "Mixed"
    end
    if total < 3 or support < 2 then return "limited", "Limited" end
    local rate = support / math.max(1, total)
    if support >= 3 and rate >= 0.75 then return "strong", "Strong" end
    if rate >= 0.50 then return "moderate", "Moderate" end
    return "limited", "Limited"
end

function Evidence.CompactText(item, sourceKind)
    if not item then return "No evidence" end
    local _, label = Evidence.Classify(item, sourceKind)
    if sourceKind == "defensive" then
        return string.format("%s · %d/%d def", label,
            tonumber(item.defensivePositiveOrigins) or 0,
            tonumber(item.defensiveOrigins) or 0)
    end
    local support, total = Counts(item, sourceKind)
    return string.format("%s · %d/%d", label, support, total)
end

function Evidence.AddTooltip(item, sourceKind)
    if not item then
        GameTooltip:AddLine("No community evidence is available for this Echo in the selected cohort.", 0.72, 0.72, 0.76, true)
        return
    end
    local total = tonumber(item.observedOrigins) or 0
    if sourceKind == "lock" then
        GameTooltip:AddLine(string.format("Locked in %d of %d independent origins.",
            tonumber(item.lockOrigins) or 0, total), 0.45, 0.85, 1, true)
    elseif sourceKind == "defensive" then
        GameTooltip:AddLine(string.format("Positive in %d of %d defensive-profile origins and %d of %d standard origins.",
            tonumber(item.defensivePositiveOrigins) or 0,
            tonumber(item.defensiveOrigins) or 0,
            tonumber(item.standardPositiveOrigins) or 0,
            tonumber(item.standardOrigins) or 0), 0.45, 0.85, 1, true)
        GameTooltip:AddLine("This is an association in local builds, not proof that the Echo causes survivability.", 0.62, 0.62, 0.66, true)
    else
        GameTooltip:AddLine(string.format("Observed in %d independent origins: %d positive, %d negative, %d locked.",
            total,
            tonumber(item.positiveOrigins) or 0,
            tonumber(item.negativeOrigins) or 0,
            tonumber(item.lockOrigins) or 0), 0.45, 0.85, 1, true)
    end
    GameTooltip:AddLine("Community usage is evidence of preference, not proven performance.", 0.62, 0.62, 0.66, true)
end
