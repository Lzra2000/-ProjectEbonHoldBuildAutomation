-- Locale integrity coverage. EbonBuilds.L is keyed by the English string
-- itself (there is no enUS file -- the enUS baseline is the set of English
-- literals in the shipped source), so two invariants keep translations
-- honest:
--   1. Every key a locale registers must exist verbatim somewhere in the
--      shipped non-locale source. A key that appears nowhere can never be
--      looked up -- it is dead weight from a typo or a removed feature and
--      would silently stop translating after any wording change.
--   2. Key parity across locales is REPORTED (not failed): keys present in
--      some locales but missing from others show up in the output so
--      translators can see the gap, without blocking CI on an incomplete
--      translation (partial locales intentionally fall back to English).
-- Plus functional checks of the Locale registry itself.

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
EbonBuildsDB = { globalSettings = {} }
UIParent = nil -- keeps the Polish font probe on its safe fallback path

------------------------------------------------------------------------
-- Load the locale registry and every shipped locale file, in TOC order.
------------------------------------------------------------------------
local localeFiles, sourceFiles = {}, {}
for line in io.lines("EbonBuilds.toc") do
    line = line:gsub("\r$", "")
    if line:match("^%S+%.lua$") then
        if line:match("^modules/i18n/locales/") then
            localeFiles[#localeFiles + 1] = line
        elseif line ~= "modules/i18n/Locale.lua" then
            sourceFiles[#sourceFiles + 1] = line
        end
    end
end
check(#localeFiles >= 6, "TOC ships at least six locale files (got " .. #localeFiles .. ")")

assert(loadfile("modules/i18n/Locale.lua"))("EbonBuilds", EbonBuilds)

-- Capture every registration while still feeding the real registry.
local registered = {}   -- code -> key -> translation
local originalRegister = EbonBuilds.Locale.Register
EbonBuilds.Locale.Register = function(code, stringTable)
    registered[code] = stringTable
    return originalRegister(code, stringTable)
end

for _, path in ipairs(localeFiles) do
    assert(loadfile(path))("EbonBuilds", EbonBuilds)
end

local expectedCodes = { "deDE", "esES", "frFR", "plPL", "ptBR", "ruRU" }
for _, code in ipairs(expectedCodes) do
    check(type(registered[code]) == "table", code .. " registered a translation table")
    check(EbonBuilds.Locale.IsSupported(code), code .. " is a supported locale")
    local count = 0
    for _ in pairs(registered[code] or {}) do count = count + 1 end
    check(count > 0, code .. " registered at least one string (got " .. count .. ")")
end

------------------------------------------------------------------------
-- Invariant 1: every locale key exists verbatim in the shipped source.
------------------------------------------------------------------------
do
    -- One concatenated blob of every non-locale TOC source file. Keys are
    -- looked up with plain find; keys containing characters that must be
    -- escaped inside a Lua double-quoted literal are also tried in their
    -- escaped spelling.
    local parts = {}
    for _, path in ipairs(sourceFiles) do
        local file = assert(io.open(path, "rb"), "unable to read " .. path)
        parts[#parts + 1] = file:read("*a")
        file:close()
    end
    local blob = table.concat(parts, "\n"):gsub("\r\n", "\n")

    local function AppearsInSource(key)
        if blob:find(key, 1, true) then return true end
        local escaped = key:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
        if escaped ~= key and blob:find(escaped, 1, true) then return true end
        return false
    end

    local deadKeys = 0
    for _, code in ipairs(expectedCodes) do
        for key in pairs(registered[code]) do
            if type(key) ~= "string" then
                failures = failures + 1
                io.stderr:write("FAIL: " .. code .. " registered a non-string key\n")
            elseif not AppearsInSource(key) then
                deadKeys = deadKeys + 1
                failures = failures + 1
                io.stderr:write(string.format(
                    "FAIL: %s key %q does not appear in any shipped source file (dead or mistyped key)\n",
                    code, key))
            end
        end
    end
    if deadKeys == 0 then
        print("All locale keys resolve to English literals in the shipped source.")
    end
end

------------------------------------------------------------------------
-- Invariant 2 (report only): key parity across locales.
------------------------------------------------------------------------
do
    local union, unionCount = {}, 0
    for _, code in ipairs(expectedCodes) do
        for key in pairs(registered[code]) do
            if not union[key] then
                union[key] = true
                unionCount = unionCount + 1
            end
        end
    end

    for _, code in ipairs(expectedCodes) do
        local missing = {}
        for key in pairs(union) do
            if registered[code][key] == nil then missing[#missing + 1] = key end
        end
        table.sort(missing)
        if #missing == 0 then
            print(string.format("%s: complete (%d/%d keys).", code, unionCount, unionCount))
        else
            print(string.format("%s: %d/%d keys; %d missing (English fallback applies):",
                code, unionCount - #missing, unionCount, #missing))
            local limit = math.min(#missing, 10)
            for i = 1, limit do
                print(string.format("    missing: %q", missing[i]))
            end
            if #missing > limit then
                print(string.format("    ... and %d more", #missing - limit))
            end
        end
    end
end

------------------------------------------------------------------------
-- Functional registry behavior
------------------------------------------------------------------------
do
    local L = EbonBuilds.L

    equal(EbonBuilds.Locale.GetActiveLocale(), "enUS", "default locale is English")
    equal(L["Save build"], "Save build", "English lookup returns the key itself")

    check(EbonBuilds.Locale.SetLocale("deDE"), "German can be activated")
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "active locale updates")
    equal(EbonBuildsDB.globalSettings.localeOverride, "deDE", "override persists to SavedVariables")
    equal(L["Save build"], "Build speichern", "German lookup returns the translation")
    equal(L["This key exists nowhere"], "This key exists nowhere",
        "unknown keys fall back to the English key")

    check(not EbonBuilds.Locale.SetLocale("koKR"), "unsupported client locale is refused")
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "refused locale does not change state")
    check(not EbonBuilds.Locale.SetLocale(nil), "nil locale is refused")

    -- Alias resolution used by the Settings language picker.
    equal(EbonBuilds.Locale.ResolveAlias("de"), "deDE", "short alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("DEDE"), "deDE", "case-insensitive code resolves")
    equal(EbonBuilds.Locale.ResolveAlias("german"), "deDE", "language-name alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("ruRU"), "ruRU", "exact code resolves")
    equal(EbonBuilds.Locale.ResolveAlias("pl"), "plPL", "manual-only Polish alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("tlh"), nil, "unknown alias resolves to nil")
    equal(EbonBuilds.Locale.ResolveAlias(""), nil, "empty alias resolves to nil")

    local supported = EbonBuilds.Locale.GetSupportedLocales()
    equal(#supported, 7, "seven supported locales (six translations + enUS)")
    for i = 2, #supported do
        check(supported[i - 1].code < supported[i].code, "supported locale list is sorted")
    end

    -- Init(): saved override wins, then client locale, then English.
    EbonBuildsDB.globalSettings.localeOverride = "frFR"
    function GetLocale() return "deDE" end
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "frFR", "saved override wins over the client locale")
    EbonBuildsDB.globalSettings.localeOverride = nil
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "client locale is used without an override")
    function GetLocale() return "koKR" end
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "enUS", "unsupported client locale falls back to English")
end

if failures > 0 then
    io.stderr:write(string.format("%d i18n test(s) failed.\n", failures))
    os.exit(1)
end
print("Locale integrity passed: no dead keys, parity reported, registry behavior verified.")
