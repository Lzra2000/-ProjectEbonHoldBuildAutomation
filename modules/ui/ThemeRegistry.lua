local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/ThemeRegistry.lua
-- Immutable semantic design tokens. View code consumes these names instead of
-- embedding colors, fonts, textures, spacing, dimensions, or motion timings.

EbonBuilds.ThemeRegistry = {}
local Registry = EbonBuilds.ThemeRegistry

local TOKENS = {
    colors = {
        surfaceWindow = { 0.035, 0.035, 0.050, 0.985 },
        surfacePanel = { 0.060, 0.060, 0.080, 0.985 },
        surfaceCard = { 0.090, 0.090, 0.115, 0.985 },
        surfaceCardHover = { 0.135, 0.135, 0.175, 0.995 },
        surfaceInput = { 0.020, 0.020, 0.030, 0.980 },
        surfaceInputError = { 0.160, 0.025, 0.025, 0.980 },
        surfaceInputDisabled = { 0.030, 0.030, 0.040, 0.650 },
        border = { 0.420, 0.420, 0.480, 1.000 },
        borderDim = { 0.240, 0.240, 0.290, 1.000 },
        borderDisabled = { 0.160, 0.160, 0.190, 0.800 },
        accent = { 1.000, 0.820, 0.000, 1.000 },
        selected = { 0.200, 0.170, 0.070, 1.000 },
        success = { 0.300, 0.860, 0.380, 1.000 },
        warning = { 1.000, 0.660, 0.160, 1.000 },
        danger = { 1.000, 0.260, 0.260, 1.000 },
        presence = { 0.360, 0.770, 0.640, 1.000 },
        textPrimary = { 0.960, 0.960, 0.980, 1.000 },
        textMuted = { 0.660, 0.680, 0.740, 1.000 },
    },
    colorHex = {
        accent = "ffd100",
        presence = "5cc4a3",
    },
    fonts = {
        pageTitle = "GameFontNormalLarge",
        sectionTitle = "GameFontNormal",
        body = "GameFontHighlight",
        bodyMuted = "GameFontDisable",
        small = "GameFontHighlightSmall",
        smallMuted = "GameFontDisableSmall",
        metric = "GameFontNormalLarge",
    },
    textures = {
        flat = "Interface\\Buttons\\WHITE8X8",
        search = "Interface\\Common\\UI-Searchbox-Icon",
    },
    spacing = {
        xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24,
        page = 16, panel = 12, control = 8, row = 6,
    },
    sizes = {
        border = 1,
        borderLowScale = 2,
        controlHeight = 24,
        rowCompact = 24,
        rowStandard = 32,
        iconSmall = 14,
        iconMedium = 20,
        iconLarge = 32,
        scrollbar = 14,
        sidebar = 184,
        header = 42,
    },
    motion = {
        toastDuration = 3,
        pulsePeriod = 0.8,
        tooltipDelay = 0,
    },
    layout = {
        compact = { scale = 0.90, density = 0.88 },
        standard = { scale = 1.00, density = 1.00 },
        wide = { scale = 1.08, density = 1.10 },
    },
}

local revision = 1

function Registry.Get()
    return TOKENS
end

function Registry.Revision()
    return revision
end

-- Runtime overrides are deliberately narrow. They replace an entire semantic
-- token, preserving the rule that view code never owns literal visual values.
function Registry.Override(group, key, value)
    local bucket = TOKENS[group]
    if type(bucket) ~= "table" or bucket[key] == nil or value == nil then return false end
    bucket[key] = value
    revision = revision + 1
    if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("THEME_CHANGED", revision, group, key) end
    return true
end
