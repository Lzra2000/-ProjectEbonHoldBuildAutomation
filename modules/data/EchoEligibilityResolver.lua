local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoEligibilityResolver.lua
-- Single exact-variant authority for class eligibility. It combines declared
-- metadata, guarded reviewed facts, and validated local positive observations.

EbonBuilds.EchoEligibilityResolver = {}

local Resolver = EbonBuilds.EchoEligibilityResolver
local Identity = EbonBuilds.EchoIdentity
local Facts = EbonBuilds.EchoCorrectionFacts or { eligibility = {} }

Resolver.CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
Resolver.ALL_CLASS_MASK = 1535

Resolver.REASON_DECLARED_MASK = "DECLARED_MASK"
Resolver.REASON_REVIEWED_ALLOW = "REVIEWED_ALLOW"
Resolver.REASON_REVIEWED_DENY = "REVIEWED_DENY"
Resolver.REASON_OBSERVED_OFFER = "OBSERVED_OFFER"
Resolver.REASON_OBSERVED_REPLACEMENT = "OBSERVED_REPLACEMENT"
Resolver.REASON_CONFIRMED_SELECTION = "CONFIRMED_SELECTION"
Resolver.REASON_LIVE_DISCOVERY = "LIVE_DISCOVERY"
Resolver.REASON_ZERO_MASK = "ZERO_MASK"
Resolver.REASON_RUNTIME_MISSING = "RUNTIME_MISSING"
Resolver.REASON_STALE_FACT = "STALE_CORRECTION_FACT"
Resolver.REASON_MASK_CONFLICT = "MASK_CONFLICT"

local staleFacts = {}

function Resolver.ClassBit(classToken)
    return Resolver.CLASS_BITS[tostring(classToken or ""):upper()]
end

local function FactFor(variant)
    local fact = Facts.eligibility and Facts.eligibility[tonumber(variant and variant.spellId)]
    if type(fact) ~= "table" then return nil, nil end
    local definition = EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetByRef(variant.refKey)
    local staleReason
    if tostring(fact.expectedRefKey or "") ~= tostring(variant.refKey or "") then staleReason = "REF_KEY" end
    if not staleReason and tonumber(fact.expectedIdentitySignature)
        and tonumber(fact.expectedIdentitySignature) ~= tonumber(definition and definition.identitySignature) then staleReason = "IDENTITY_SIGNATURE" end
    if not staleReason and tonumber(fact.expectedDescriptionHash)
        and tonumber(fact.expectedDescriptionHash) ~= tonumber(definition and definition.descriptionHash) then staleReason = "DESCRIPTION_HASH" end
    if not staleReason and tonumber(fact.expectedDeclaredMask)
        and tonumber(fact.expectedDeclaredMask) ~= tonumber(variant.classMask) then staleReason = "DECLARED_MASK" end
    if not staleReason and tonumber(fact.expectedQuality)
        and tonumber(fact.expectedQuality) ~= tonumber(variant.quality) then staleReason = "QUALITY" end
    if not staleReason and tonumber(fact.expectedRequiredSpell)
        and tonumber(fact.expectedRequiredSpell) ~= tonumber(variant.requiredSpell) then staleReason = "REQUIRED_SPELL" end
    if not staleReason and tonumber(fact.expectedVariantCount)
        and tonumber(fact.expectedVariantCount) ~= #(definition and definition.variants or {}) then staleReason = "VARIANT_COUNT" end
    if not staleReason and tonumber(fact.sourceAddonRevision) then
        local revision = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetAddonVersion()
            or (EbonBuilds.EchoIdentityData and EbonBuilds.EchoIdentityData.SOURCE_ADDON_VERSION)
        if revision and tonumber(revision) ~= tonumber(fact.sourceAddonRevision) then staleReason = "ADDON_REVISION" end
    end
    if staleReason then
        staleFacts[variant.spellId] = staleReason
        return nil, staleReason
    end
    staleFacts[variant.spellId] = nil
    return fact, nil
end

local function EvidenceReason(flags)
    local Evidence = EbonBuilds.EchoEligibilityEvidence
    if not Evidence or flags == 0 then return nil end
    if bit.band(flags, Evidence.FLAG_GRANTED) ~= 0 then return Resolver.REASON_CONFIRMED_SELECTION end
    if bit.band(flags, Evidence.FLAG_REPLACEMENT) ~= 0 then return Resolver.REASON_OBSERVED_REPLACEMENT end
    if bit.band(flags, Evidence.FLAG_OFFERED) ~= 0 then return Resolver.REASON_OBSERVED_OFFER end
    if bit.band(flags, Evidence.FLAG_DISCOVERED) ~= 0 then return Resolver.REASON_LIVE_DISCOVERY end
    return nil
end

function Resolver.ResolveVariant(variantOrSpellId, classToken)
    local variant = type(variantOrSpellId) == "table" and variantOrSpellId
        or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(variantOrSpellId))
    local classBit = Resolver.ClassBit(classToken)
    if not variant or not classBit then
        return Identity.UNKNOWN, Resolver.REASON_ZERO_MASK, 0, 0, 0, 0, 0
    end

    local declaredMask = tonumber(variant.classMask) or 0
    local fact, staleReason = FactFor(variant)
    local allowMask = fact and tonumber(fact.allowMask) or 0
    local denyMask = fact and tonumber(fact.denyMask) or 0
    local flags = EbonBuilds.EchoEligibilityEvidence
        and EbonBuilds.EchoEligibilityEvidence.GetFlags(classToken, variant.spellId) or 0
    local observedMask = flags ~= 0 and classBit or 0
    local widened = bit.bor(declaredMask, allowMask, observedMask)
    local allowed = bit.band(bit.bnot(denyMask), Resolver.ALL_CLASS_MASK)
    local effectiveMask = bit.band(widened, allowed)
    local available = bit.band(effectiveMask, classBit) ~= 0
    local discrepancy = 0
    if allowMask ~= 0 or denyMask ~= 0 then discrepancy = bit.bor(discrepancy, 1) end
    if flags ~= 0 and bit.band(declaredMask, classBit) == 0 then discrepancy = bit.bor(discrepancy, 2) end
    if variant.availabilityConflict then discrepancy = bit.bor(discrepancy, 4) end

    if bit.band(denyMask, classBit) ~= 0 then
        return Identity.UNAVAILABLE, Resolver.REASON_REVIEWED_DENY,
            declaredMask, effectiveMask, flags, 4, discrepancy
    end
    if bit.band(allowMask, classBit) ~= 0 then
        return Identity.CONFLICTED, Resolver.REASON_REVIEWED_ALLOW,
            declaredMask, effectiveMask, flags, 4, discrepancy
    end
    if flags ~= 0 and bit.band(declaredMask, classBit) == 0 then
        return Identity.CONFLICTED, EvidenceReason(flags),
            declaredMask, effectiveMask, flags, 3, discrepancy
    end
    if staleReason and declaredMask == 0 then
        return Identity.UNKNOWN, Resolver.REASON_STALE_FACT,
            declaredMask, effectiveMask, flags, 0, discrepancy
    end
    if EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.IsRuntimeVerified
        and EbonBuilds.EchoCatalog.IsRuntimeVerified()
        and variant.runtimePresent ~= true and variant.sourceKind == "BUNDLED" then
        return Identity.UNKNOWN, Resolver.REASON_RUNTIME_MISSING,
            declaredMask, effectiveMask, flags, 0, discrepancy
    end
    if declaredMask == 0 then
        return Identity.UNKNOWN, Resolver.REASON_ZERO_MASK,
            declaredMask, effectiveMask, flags, 0, discrepancy
    end
    if variant.availabilityConflict and available then
        return Identity.CONFLICTED, Resolver.REASON_MASK_CONFLICT,
            declaredMask, effectiveMask, flags, 2, discrepancy
    end
    return available and Identity.AVAILABLE or Identity.UNAVAILABLE,
        Resolver.REASON_DECLARED_MASK, declaredMask, effectiveMask, flags, 1, discrepancy
end

function Resolver.IsAvailableState(state)
    return state == Identity.AVAILABLE or state == Identity.CONFLICTED
end

function Resolver.GetEffectiveMask(variantOrSpellId)
    local variant = type(variantOrSpellId) == "table" and variantOrSpellId
        or (EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(variantOrSpellId))
    if not variant then return 0 end
    local declared = tonumber(variant.classMask) or 0
    local fact = FactFor(variant)
    local allowMask = fact and tonumber(fact.allowMask) or 0
    local denyMask = fact and tonumber(fact.denyMask) or 0
    local observed = 0
    if EbonBuilds.EchoEligibilityEvidence then
        for classToken, classBit in pairs(Resolver.CLASS_BITS) do
            if EbonBuilds.EchoEligibilityEvidence.GetFlags(classToken, variant.spellId) ~= 0 then
                observed = bit.bor(observed, classBit)
            end
        end
    end
    return bit.band(bit.bor(declared, allowMask, observed),
        bit.band(bit.bnot(denyMask), Resolver.ALL_CLASS_MASK))
end

function Resolver.GetStaleFacts() return staleFacts end
