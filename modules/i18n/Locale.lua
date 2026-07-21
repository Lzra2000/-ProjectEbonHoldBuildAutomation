local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/Locale.lua
-- Responsibility: string translation registry and lookup.
--
-- Pattern: EbonBuilds.L is a read-through table keyed by the English
-- string itself (not by an arbitrary ID), so `EbonBuilds.L["Save build"]`
-- returns the translated string in the active locale, or the English key
-- itself if that locale has no entry for it (or no locale is active at
-- all). This means a partial or missing translation file never breaks
-- anything -- it just shows English for whatever isn't translated yet,
-- which is also why call sites can adopt EbonBuilds.L[...] incrementally
-- without waiting for every locale to catch up.
--
-- Locale files (modules/i18n/locales/*.lua) call EbonBuilds.Locale.Register
-- at file scope; this file must load before them (see EbonBuilds.toc).
-- EbonBuilds.Locale.Init() (called once from core/Init.lua's ADDON_LOADED
-- handler) picks the active locale: a saved override if the player set
-- one, otherwise the client's own GetLocale(), otherwise English.

EbonBuilds.Locale = {}

local translations = {}   -- localeCode -> { [englishString] = translated }
local activeLocale = "enUS"

-- WoW 3.3.5a client locales this addon has a translation for. Client
-- locales EbonBuilds has no translation for (koKR, zhCN, zhTW, itIT, ...)
-- fall through to English via GetLocale() returning something not in this
-- map. "plPL" is not a real WoW client locale (Polish was never an
-- official client language) -- it exists here only so /ebb locale pl can
-- select it manually, matching the community README.pl.md translation.
local SUPPORTED_LOCALES = {
    enUS = "English",
    deDE = "Deutsch",
    esES = "Español",
    frFR = "Français",
    plPL = "Polski",
    ptBR = "Português (Brasil)",
    ruRU = "Русский",
}

-- Short aliases accepted by /ebb locale <code>, so players can type
-- "/ebb locale de" instead of the full WoW locale code.
local ALIASES = {
    en = "enUS", ["enus"] = "enUS", english = "enUS",
    de = "deDE", ["dede"] = "deDE", deutsch = "deDE", german = "deDE",
    es = "esES", ["eses"] = "esES", ["esmx"] = "esES", spanish = "esES", ["español"] = "esES",
    fr = "frFR", ["frfr"] = "frFR", french = "frFR", ["français"] = "frFR",
    pl = "plPL", ["plpl"] = "plPL", polish = "plPL", polski = "plPL",
    pt = "ptBR", ["ptbr"] = "ptBR", portuguese = "ptBR",
    ru = "ruRU", ["ruru"] = "ruRU", russian = "ruRU", ["русский"] = "ruRU",
}

function EbonBuilds.Locale.Register(code, stringTable)
    translations[code] = stringTable
end

function EbonBuilds.Locale.IsSupported(code)
    return SUPPORTED_LOCALES[code] ~= nil
end

function EbonBuilds.Locale.GetSupportedLocales()
    local list = {}
    for code, name in pairs(SUPPORTED_LOCALES) do
        list[#list + 1] = { code = code, name = name }
    end
    table.sort(list, function(a, b) return a.code < b.code end)
    return list
end

-- Resolves a player-typed code ("de", "DE", "deDE", "german", ...) to a
-- supported locale code, or nil if it doesn't match anything.
function EbonBuilds.Locale.ResolveAlias(input)
    if not input or input == "" then return nil end
    local lower = input:lower()
    if SUPPORTED_LOCALES[input] then return input end
    for code in pairs(SUPPORTED_LOCALES) do
        if code:lower() == lower then return code end
    end
    return ALIASES[lower]
end

function EbonBuilds.Locale.SetLocale(code)
    if not EbonBuilds.Locale.IsSupported(code) then return false end
    activeLocale = code
    if EbonBuildsDB then
        EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
        EbonBuildsDB.globalSettings.localeOverride = code
    end
    return true
end

function EbonBuilds.Locale.GetActiveLocale()
    return activeLocale
end

-- Detects and sets the active locale: saved override first, then the
-- client's own GetLocale(), then English. Safe to call more than once
-- (e.g. after the player changes the override) -- always re-resolves
-- from scratch rather than assuming it hasn't changed.
function EbonBuilds.Locale.Init()
    local saved = EbonBuildsDB and EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.localeOverride
    if saved and EbonBuilds.Locale.IsSupported(saved) then
        activeLocale = saved
        return
    end
    local clientLocale = GetLocale and GetLocale() or "enUS"
    if EbonBuilds.Locale.IsSupported(clientLocale) then
        activeLocale = clientLocale
    else
        activeLocale = "enUS"
    end
end

-- The read-through lookup table itself. Falls back to the raw key (the
-- English string) whenever the active locale is English, has no table
-- registered, or has no entry for that particular key.
EbonBuilds.L = setmetatable({}, {
    __index = function(_, key)
        local t = translations[activeLocale]
        local value = t and t[key]
        return value or key
    end,
})
