local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/deDE.lua
-- German translation. Game/addon terms (Echo, Build, Autopilot, and the
-- automation actions Banish/Reroll/Freeze/Select) are kept in English,
-- matching the existing README.de.md convention.

EbonBuilds.Locale.Register("deDE", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Prioritäten",
    ["Modifiers"] = "Modifikatoren",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Identität, Klasse, gesperrte Echoes und Teilen.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Rang-spezifische Echo-Werte festlegen und unverzichtbare Echoes schützen.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Rang-, Familien- und Unique-Echo-Strategie anpassen.",
    ["Choose an automation intent and tune its decisions."] = "Eine Automatisierungs-Ausrichtung wählen und ihre Entscheidungen feinjustieren.",

    -- Build editor bottom bar
    ["Save build"] = "Build speichern",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Aktive Felder validieren und Build-Details, Echo-Werte, Boni und Sichtbarkeit speichern.",
    ["Cancel"] = "Abbrechen",
    ["Cancel editing"] = "Bearbeitung abbrechen",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Alle ungespeicherten Build-Details, Echo-Werte, Modifikatoren, Schutzregeln und Autopilot-Einstellungen verwerfen.",
    ["Export"] = "Export",
    ["Export build"] = "Build exportieren",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Erstellt eine kompakte Zeichenfolge, die ein anderer EbonBuilds-Nutzer importieren kann.",
    ["AI report"] = "KI-Bericht",
    ["AI tuning report"] = "KI-Tuning-Bericht",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Erstellt einen lesbaren Bericht über Gewichte, Boni, Schwellenwerte und Tuning-Daten zur Analyse. Kann nicht wieder importiert werden.",
    ["Unsaved changes"] = "Ungespeicherte Änderungen",
    ["All changes saved"] = "Alle Änderungen gespeichert",
    [" · Autopilot uses last saved settings"] = " · Autopilot nutzt zuletzt gespeicherte Einstellungen",

    -- /ebb locale command
    ["Character"] = "Charakter",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Aktuelle Ausrüstung, vollständige Talentbäume und Glyphen; per Klick in den Build übernehmen.",
})
