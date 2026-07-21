local addonName, EbonBuilds = ...

-- EbonBuilds: modules/affix/AffixItemScan.lua
-- Detects which gear affix (if any) a specific ITEM has, and classifies it
-- against the character's learned-affix data (modules/affix/Affix.lua).
--
-- Unlike AffixDex's approach (regex-scanning full tooltip text, which its
-- own changelog shows tripping over embedded color codes, mid-line
-- set-bonus text, and multi-"of" item names), this only looks at the
-- item's NAME. On Ebonhold an affixed item's name always ends in
-- "... of <Affix Name> <Rank>" (e.g. "Misery's End of Keen Strikes III"),
-- so a name-only match sidesteps the tooltip-text pitfalls entirely. The
-- one real gotcha -- a base item name that itself contains "of" (e.g.
-- "Rod of Imprisoned Souls of Overwhelming Force II") -- is handled by
-- taking the LAST "of ... <rank>" occurrence via a greedy match.
--
-- The extracted "<Name> <Rank>" is then cross-checked against the
-- account's actual known-affix list (from the server feed) rather than a
-- hardcoded roman-numeral pattern -- if it doesn't match a real affix, we
-- correctly report "not an affix item" instead of guessing.

EbonBuilds.AffixItemScan = {}

-- Extracts (baseName, rank) from an item's display name, or nil if the
-- name doesn't end in an "of <words> <RANK>" suffix at all. Pure string
-- function, no game API calls, fully unit-testable.
function EbonBuilds.AffixItemScan.ExtractSuffix(itemName)
    if not itemName or itemName == "" then return nil, nil end
    local base, rank = itemName:match(".*of%s+(.-)%s+([IVXLCDM]+)$")
    if not base or base == "" then return nil, nil end
    return base, rank
end

-- Classifies an item name against the known/learned affix list.
-- Returns one of:
--   "learned"       -- the item's exact affix+rank is learned; no dot
--   "missing_new"    -- not learned, and no other rank of this affix line
--                       is learned either (a brand new affix line)
--   "missing_upgrade"-- not learned, but a DIFFERENT rank of the same
--                       affix line is already learned (a rank upgrade)
--   nil              -- not a recognized affix item; nothing to show
function EbonBuilds.AffixItemScan.Classify(itemName)
    local base, rank = EbonBuilds.AffixItemScan.ExtractSuffix(itemName)
    if not base then return nil end
    local fullName = strlower(base .. " " .. rank)

    local list = EbonBuilds.Affix.GetLearned()
    if #list == 0 then return nil end -- no server data yet; nothing to say

    local exact = nil
    local anyOtherRankLearned = false
    for _, a in ipairs(list) do
        local lname = strlower(a.name or "")
        if lname == fullName then
            exact = a
        elseif lname:sub(1, #strlower(base) + 1) == strlower(base) .. " " and a.learned then
            anyOtherRankLearned = true
        end
    end

    if not exact then return nil end -- extracted text didn't match any real affix
    if exact.learned then return "learned" end
    return anyOtherRankLearned and "missing_upgrade" or "missing_new"
end

-- For destructive actions (auto-sell, auto-delete) ONLY. Classify() returns
-- nil both when an item genuinely has no affix suffix AND when we simply
-- can't verify one yet (no server data) -- that ambiguity is fine for a
-- passive UI dot, but wrong for something that permanently disposes of an
-- item. This makes the fail-safe explicit: anything that LOOKS like it
-- could carry an affix (has the "... of X Rank" shape) is protected unless
-- we can positively confirm you already learned that exact affix.
function EbonBuilds.AffixItemScan.IsProtectedFromSelling(itemName)
    local base, rank = EbonBuilds.AffixItemScan.ExtractSuffix(itemName)
    if not base then return false end -- no affix-shaped suffix at all
    local classification = EbonBuilds.AffixItemScan.Classify(itemName)
    return classification ~= "learned"
end
