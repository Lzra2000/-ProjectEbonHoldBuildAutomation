local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/frFR.lua
-- French translation. "build" stays as a loanword, "Echo" translates to
-- "écho", automation actions (Banish/Reroll/Freeze/Select) and Autopilot
-- stay in English, matching the existing README.fr.md convention.

EbonBuilds.Locale.Register("frFR", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Priorités",
    ["Modifiers"] = "Modificateurs",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Identité, classe, échos verrouillés et partage.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Définir des valeurs d'écho par rang et protéger les échos indispensables.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Ajuster la stratégie de rang, de famille et d'écho unique.",
    ["Choose an automation intent and tune its decisions."] = "Choisir une intention d'automatisation et ajuster ses décisions.",

    -- Build editor bottom bar
    ["Save build"] = "Enregistrer le build",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Valide les champs actifs et enregistre les détails du build, les valeurs d'écho, les bonus et la visibilité.",
    ["Cancel"] = "Annuler",
    ["Cancel editing"] = "Annuler l'édition",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Annule tous les détails de build non enregistrés, les valeurs d'écho, les modificateurs, les règles de protection et les réglages Autopilot.",
    ["Export"] = "Exporter",
    ["Export build"] = "Exporter le build",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Crée une chaîne compacte qu'un autre utilisateur d'EbonBuilds peut importer.",
    ["AI report"] = "Rapport IA",
    ["AI tuning report"] = "Rapport de réglage IA",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Crée un rapport lisible des poids, bonus, seuils et données de réglage pour analyse. Ne peut pas être réimporté.",
    ["Unsaved changes"] = "Modifications non enregistrées",
    ["All changes saved"] = "Toutes les modifications enregistrées",
    [" · Autopilot uses last saved settings"] = " · Autopilot utilise les derniers réglages enregistrés",

    -- /ebb locale command
    ["Character"] = "Personnage",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Équipement actuel, arbres de talents complets et glyphes ; adoptez-les dans le build.",
})
