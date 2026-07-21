local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/ruRU.lua
-- Russian translation. "build" translates to "билд", "Echo" to "эхо",
-- automation actions (Banish/Reroll/Freeze/Select) and Autopilot stay in
-- English, matching the existing README.ru.md convention.

EbonBuilds.Locale.Register("ruRU", {
    -- Build editor tabs
    ["Build"] = "Билд",
    ["Priorities"] = "Приоритеты",
    ["Modifiers"] = "Модификаторы",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Личность, класс, заблокированные эхо и общий доступ.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Задайте значения эхо по рангам и защитите незаменимые эхо.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Настройте стратегию ранга, семейства и уникального эхо.",
    ["Choose an automation intent and tune its decisions."] = "Выберите направление автоматизации и настройте её решения.",

    -- Build editor bottom bar
    ["Save build"] = "Сохранить билд",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Проверяет активные поля и сохраняет детали билда, значения эхо, бонусы и видимость.",
    ["Cancel"] = "Отмена",
    ["Cancel editing"] = "Отменить редактирование",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Отменяет все несохранённые детали билда, значения эхо, модификаторы, правила защиты и настройки Autopilot.",
    ["Export"] = "Экспорт",
    ["Export build"] = "Экспортировать билд",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Создаёт компактную строку, которую сможет импортировать другой пользователь EbonBuilds.",
    ["AI report"] = "Отчёт для ИИ",
    ["AI tuning report"] = "Отчёт для настройки через ИИ",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Создаёт читаемый отчёт по весам, бонусам, порогам и данным настройки для анализа. Обратный импорт невозможен.",
    ["Unsaved changes"] = "Несохранённые изменения",
    ["All changes saved"] = "Все изменения сохранены",
    [" · Autopilot uses last saved settings"] = " · Autopilot использует последние сохранённые настройки",

    -- /ebb locale command
    ["Character"] = "Персонаж",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Текущая экипировка, полные деревья талантов и символы; перенесите их в билд.",
})
