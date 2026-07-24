local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/plPL.lua
-- Polish translation. "build" and "echo"/"echa" stay as loanwords,
-- automation actions (Banish/Reroll/Freeze/Select) and Autopilot stay in
-- English, matching the existing README.pl.md convention.
--
-- Note: Polish is not an official WoW 3.3.5a client locale, so GetLocale()
-- will never return "plPL" -- this is only ever selected via the saved
-- override (Settings -> Interface), same as the community README.pl.md
-- exists despite no Polish game client.
--
-- Write proper Polish here, diacritics included. Clients whose fonts lack
-- the Latin-Extended-A glyphs (every stock 3.3.5a client -- they would
-- render ą ć ę ł ń ś ź ż as "?") get an automatic ASCII fallback applied
-- centrally in Locale.lua, so keep the correct spelling in this file.

EbonBuilds.Locale.Register("plPL", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Priorytety",
    ["Modifiers"] = "Modyfikatory",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Tożsamość, klasa, zablokowane echa i udostępnianie.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Ustaw wartości echa dla poszczególnych rang i chroń echa, których nie można stracić.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Dostosuj strategię rangi, rodziny i unikalnego echa.",
    ["Choose an automation intent and tune its decisions."] = "Wybierz cel automatyzacji i dostosuj jej decyzje.",

    -- Build editor bottom bar
    ["Save build"] = "Zapisz build",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Sprawdza aktywne pola i zapisuje szczegóły builda, wartości echa, bonusy i widoczność.",
    ["Cancel"] = "Anuluj",
    ["Cancel editing"] = "Anuluj edycję",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Odrzuca wszystkie niezapisane szczegóły builda, wartości echa, modyfikatory, zasady ochrony i ustawienia Autopilota.",
    ["Export"] = "Eksportuj",
    ["Export build"] = "Eksportuj build",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Tworzy kompaktowy ciąg znaków, który może zaimportować inny użytkownik EbonBuilds.",
    ["AI report"] = "Raport AI",
    ["AI tuning report"] = "Raport dostrajania AI",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Tworzy czytelny raport wag, bonusów, progów i danych dostrajania do analizy. Nie można go ponownie zaimportować.",
    ["Unsaved changes"] = "Niezapisane zmiany",
    ["All changes saved"] = "Wszystkie zmiany zapisane",
    [" · Autopilot uses last saved settings"] = " · Autopilot używa ostatnio zapisanych ustawień",

    -- /ebb locale command
    ["Character"] = "Postać",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Aktualny ekwipunek, pełne drzewka talentów i glify; przejmij je do builda.",
})
