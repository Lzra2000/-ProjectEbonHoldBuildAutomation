local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/EchoCorrectionFacts.lua
-- Reviewed, versioned corrections for ProjectEbonhold metadata defects.
-- The resolver consumes this schema generically; consumers never branch on a
-- particular Echo name, group, spell, or class.

EbonBuilds.EchoCorrectionFacts = {
    SCHEMA = 1,
    eligibility = {
        [200756] = {
            expectedRefKey = "g:189",
            expectedIdentitySignature = 163513678,
            expectedDescriptionHash = 1735982990,
            expectedDeclaredMask = 1405,
            expectedQuality = 3,
            expectedRequiredSpell = 0,
            expectedVariantCount = 1,

            -- Overtime Conversion is available to every supported class except
            -- Paladin. ProjectEbonhold revision 37 incorrectly omitted Mage.
            allowMask = 128,
            denyMask = 2,
            sourceAddonRevision = 37,
            evidenceType = "CONTROLLED_GAMEPLAY_VERIFICATION",
            note = "Available to every class except Paladin",
        },
    },
}
