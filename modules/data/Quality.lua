local addonName, EbonBuilds = ...

-- EbonBuilds: modules/data/Quality.lua
-- Single source of truth for Echo quality labels and colors.
-- Project Ebonhold currently exposes four supported Echo ranks. The UI and
-- score editors intentionally present them from highest to lowest value:
-- Epic, Rare, Uncommon, Common.

EbonBuilds.Quality = {}

local HEX = {
    [0] = "ffffff", -- Common
    [1] = "1eff00", -- Uncommon
    [2] = "0070dd", -- Rare
    [3] = "a335ee", -- Epic
}

local RGB = {}
for q, hex in pairs(HEX) do
    RGB[q] = {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
end

EbonBuilds.Quality.HEX = HEX
EbonBuilds.Quality.RGB = RGB
EbonBuilds.Quality.LABELS = {
    [0] = "Common",
    [1] = "Uncommon",
    [2] = "Rare",
    [3] = "Epic",
}

-- Intent-first order: highest-value rank is always the left-most/first item.
-- Consumers should iterate this table rather than assuming numeric order.
EbonBuilds.Quality.ORDER = { 3, 2, 1, 0 }

function EbonBuilds.Quality.IsValid(quality)
    return EbonBuilds.Quality.LABELS[quality] ~= nil
end

function EbonBuilds.Quality.GetRGB(q)
    local c = RGB[q] or RGB[0]
    return c[1], c[2], c[3]
end

function EbonBuilds.Quality.Colorize(text, q)
    return "|cff" .. (HEX[q] or HEX[0]) .. tostring(text) .. "|r"
end

function EbonBuilds.Quality.OfSpell(spellId)
    if not spellId or not ProjectEbonhold or not ProjectEbonhold.PerkDatabase then return nil end
    local data = ProjectEbonhold.PerkDatabase[spellId]
    return data and data.quality or nil
end
