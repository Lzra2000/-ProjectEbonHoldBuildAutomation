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

-- No official Polish WoW 3.3.5a client exists, so Polish players run this
-- addon on clients (usually enUS) whose fonts -- Fonts\FRIZQT__.TTF and
-- friends -- cover Latin-1 but not Latin Extended-A. Every glyph the font
-- lacks is drawn as "?" on the 3.3.5a client, which turned "Postać" into
-- "Posta?" (GitHub issue #40). Latin-1 letters like ó/Ó render fine (the
-- Spanish and French translations depend on that), so only the eight
-- Latin-Extended-A Polish letters need a fallback.
local POLISH_ASCII_FOLD = {
    ["ą"] = "a", ["ć"] = "c", ["ę"] = "e", ["ł"] = "l", ["ń"] = "n",
    ["ś"] = "s", ["ź"] = "z", ["ż"] = "z",
    ["Ą"] = "A", ["Ć"] = "C", ["Ę"] = "E", ["Ł"] = "L", ["Ń"] = "N",
    ["Ś"] = "S", ["Ź"] = "Z", ["Ż"] = "Z",
}

local foldCache = {}   -- translated string -> ASCII-folded string

local function FoldPolishDiacritics(text)
    local folded = foldCache[text]
    if folded == nil then
        folded = text
        -- Each key is a two-byte UTF-8 sequence with no pattern-magic
        -- characters, so a plain gsub per letter is byte-exact in Lua 5.1.
        for sequence, ascii in pairs(POLISH_ASCII_FOLD) do
            folded = folded:gsub(sequence, ascii)
        end
        foldCache[text] = folded
    end
    return folded
end

-- Probes, once per session, whether the client font actually contains the
-- Polish Latin-Extended-A glyphs. Players who installed a font pack (e.g. a
-- replaced Fonts\FRIZQT__.TTF with full coverage) keep proper diacritics;
-- everyone else gets readable ASCII Polish instead of question marks.
--
-- Detection: the 3.3.5a client substitutes the font's own "?" glyph for any
-- missing glyph, so a missing letter's rendered width equals the width of a
-- literal "?". In any font that really contains them, "ł" is far narrower
-- than "?" and "ą" is not "?"-shaped either -- both matching "?" exactly
-- means the glyphs are absent. GetStringWidth() works on hidden
-- FontStrings, so nothing flashes on screen.
local fontRendersPolish   -- nil until probed, then boolean for the session
local function ClientFontRendersPolish()
    if fontRendersPolish ~= nil then return fontRendersPolish end
    local ok, supported = pcall(function()
        local probe = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        probe:Hide()
        probe:SetText("?")
        local questionWidth = probe:GetStringWidth()
        probe:SetText("ł")
        local lWidth = probe:GetStringWidth()
        probe:SetText("ą")
        local aWidth = probe:GetStringWidth()
        probe:SetText("")
        return lWidth ~= questionWidth or aWidth ~= questionWidth
    end)
    -- On any error (headless test runtime, stubbed widgets) assume no
    -- support: folded ASCII is always safe to display.
    fontRendersPolish = (ok and supported) and true or false
    return fontRendersPolish
end

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
-- registered, or has no entry for that particular key. Polish additionally
-- folds diacritics to ASCII when the client font cannot render them (see
-- POLISH_ASCII_FOLD above), so no string ever displays "?" placeholders.
EbonBuilds.L = setmetatable({}, {
    __index = function(_, key)
        local t = translations[activeLocale]
        local value = t and t[key]
        if value and activeLocale == "plPL" and not ClientFontRendersPolish() then
            return FoldPolishDiacritics(value)
        end
        return value or key
    end,
})
