local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/SpecData.lua
-- Static spec metadata per class token. Template file: declarative only.

EbonBuilds.SpecData = {
    WARRIOR     = { { name="Arms",         icon="Interface\\Icons\\Ability_Rogue_Eviscerate" },
                    { name="Fury",         icon="Interface\\Icons\\Ability_Warrior_InnerRage" },
                    { name="Protection",   icon="Interface\\Icons\\Ability_Warrior_DefensiveStance" } },
    PALADIN     = { { name="Holy",         icon="Interface\\Icons\\Spell_Holy_HolyBolt" },
                    { name="Protection",   icon="Interface\\Icons\\Spell_Holy_DevotionAura" },
                    { name="Retribution",  icon="Interface\\Icons\\Spell_Holy_AuraOfLight" } },
    HUNTER      = { { name="Beast Mastery",icon="Interface\\Icons\\Ability_Hunter_BeastTaming" },
                    { name="Marksmanship", icon="Interface\\Icons\\Ability_Marksmanship" },
                    { name="Survival",     icon="Interface\\Icons\\Ability_Hunter_SwiftStrike" } },
    ROGUE       = { { name="Assassination",icon="Interface\\Icons\\Ability_Rogue_DeadlyBrew" },
                    { name="Combat",       icon="Interface\\Icons\\Ability_BackStab" },
                    { name="Subtlety",     icon="Interface\\Icons\\Ability_Stealth" } },
    PRIEST      = { { name="Discipline",   icon="Interface\\Icons\\Spell_Holy_WordFortitude" },
                    { name="Holy",         icon="Interface\\Icons\\Spell_Holy_GuardianSpirit" },
                    { name="Shadow",       icon="Interface\\Icons\\Spell_Shadow_ShadowWordPain" } },
    DEATHKNIGHT = { { name="Blood",        icon="Interface\\Icons\\Spell_Deathknight_BloodPresence" },
                    { name="Frost",        icon="Interface\\Icons\\Spell_Deathknight_FrostPresence" },
                    { name="Unholy",       icon="Interface\\Icons\\Spell_Deathknight_UnholyPresence" } },
    SHAMAN      = { { name="Elemental",    icon="Interface\\Icons\\Spell_Nature_Lightning" },
                    { name="Enhancement",  icon="Interface\\Icons\\Spell_Nature_LightningShield" },
                    { name="Restoration",  icon="Interface\\Icons\\Spell_Nature_MagicImmunity" } },
    MAGE        = { { name="Arcane",       icon="Interface\\Icons\\Spell_Holy_MagicalSentry" },
                    { name="Fire",         icon="Interface\\Icons\\Spell_Fire_FireBolt02" },
                    { name="Frost",        icon="Interface\\Icons\\Spell_Frost_FrostBolt02" } },
    WARLOCK     = { { name="Affliction",   icon="Interface\\Icons\\Spell_Shadow_DeathCoil" },
                    { name="Demonology",   icon="Interface\\Icons\\Spell_Shadow_Metamorphosis" },
                    { name="Destruction",  icon="Interface\\Icons\\Spell_Shadow_RainOfFire" } },
    DRUID       = { { name="Balance",      icon="Interface\\Icons\\Spell_Nature_StarFall" },
                    { name="Feral",        icon="Interface\\Icons\\Ability_Racial_BearForm" },
                    { name="Restoration",  icon="Interface\\Icons\\Spell_Nature_HealingTouch" } },
}
