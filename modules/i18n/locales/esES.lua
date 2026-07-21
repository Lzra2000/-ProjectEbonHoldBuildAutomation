local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/esES.lua
-- Spanish translation. "build" stays as a loanword, "Echo" translates to
-- "eco", automation actions (Banish/Reroll/Freeze/Select) and Autopilot
-- stay in English, matching the existing README.es.md convention.

EbonBuilds.Locale.Register("esES", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Prioridades",
    ["Modifiers"] = "Modificadores",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Identidad, clase, ecos bloqueados y compartir.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Define valores de eco por rango y protege los ecos imprescindibles.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Ajusta la estrategia de rango, familia y eco único.",
    ["Choose an automation intent and tune its decisions."] = "Elige una intención de automatización y ajusta sus decisiones.",

    -- Build editor bottom bar
    ["Save build"] = "Guardar build",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Valida los campos activos y guarda los detalles del build, valores de eco, bonificaciones y visibilidad.",
    ["Cancel"] = "Cancelar",
    ["Cancel editing"] = "Cancelar edición",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Descarta todos los detalles del build sin guardar, valores de eco, modificadores, reglas de protección y ajustes de Autopilot.",
    ["Export"] = "Exportar",
    ["Export build"] = "Exportar build",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Crea una cadena compacta que otro usuario de EbonBuilds puede importar.",
    ["AI report"] = "Informe IA",
    ["AI tuning report"] = "Informe de ajuste para IA",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Crea un informe legible de pesos, bonificaciones, umbrales y datos de ajuste para su análisis. No se puede volver a importar.",
    ["Unsaved changes"] = "Cambios sin guardar",
    ["All changes saved"] = "Todos los cambios guardados",
    [" · Autopilot uses last saved settings"] = " · Autopilot usa la última configuración guardada",

    -- /ebb locale command
    ["Character"] = "Personaje",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Equipo actual, árboles de talentos completos y glifos; adóptalos en el build.",
})
