-- Headless tests for Details_ProjectEbonhold pure helpers (Lua 5.1).
-- Run: texlua tests/test_details_project_ebonhold.lua

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

local chunk, err = loadfile("vendor/Details_ProjectEbonhold/DetailsProjectEbonholdCore.lua")
if not chunk then
    io.stderr:write("LOAD FAIL: " .. tostring(err) .. "\n")
    os.exit(1)
end
-- Core module has no return value; assert load success via pcall.
local ok, loadErr = pcall(chunk)
if not ok then
    io.stderr:write("LOAD FAIL: " .. tostring(loadErr) .. "\n")
    os.exit(1)
end

local Core = DetailsProjectEbonholdCore
check(Core ~= nil, "Core global exists")

-- PE spell id band
equal(Core.IsPeCustomSpellId(200301), true, "echo-band id")
equal(Core.IsPeCustomSpellId(301250), true, "tome-band id")
equal(Core.IsPeCustomSpellId(133), false, "stock Fireball not PE")
equal(Core.IsPeCustomSpellId(nil), false, "nil spell id")

-- Echo labels
equal(Core.FormatEchoLabel("Crimson Reprisal"), "Crimson Reprisal (Echo)", "echo suffix")
equal(Core.FormatEchoLabel("Crimson Reprisal (Echo)"), "Crimson Reprisal (Echo)", "idempotent echo label")
equal(Core.FormatEchoLabel(""), "Unknown (Echo)", "empty echo name")

-- Proc labels — never emit empty (); never use "<-" (Details GetOnlyName strips %-.*)
equal(Core.FormatProcLabel("Chaos Bolt", "Incinerate"), "Chaos Bolt [Incinerate]", "proc from source")
equal(Core.FormatProcLabel("Trinket Hit", nil), "Trinket Hit", "proc without source omits parens")
equal(Core.FormatProcLabel("Trinket Hit", ""), "Trinket Hit", "empty source omits parens")
equal(Core.FormatProcLabel("Trinket Hit", "   "), "Trinket Hit", "whitespace source omits parens")
equal(Core.FormatProcLabel("X [Y]", "Z"), "X [Y]", "do not nest attribution")
equal(Core.FormatProcLabel("X (<- Y)", "Z"), "X (<- Y)", "do not nest legacy attribution")
equal(Core.FormatProcSourceSuffix("Incinerate"), " [Incinerate]", "source suffix")
equal(Core.FormatProcSourceSuffix(nil), "", "nil source suffix empty")
equal(Core.FormatProcSourceSuffix(""), "", "empty source suffix empty")
equal(Core.StripProcSourceSuffix("Big Bang [Flowing Defense]"), "Big Bang", "strip bracket source")
equal(Core.StripProcSourceSuffix("Big Bang (<- Flowing Defense)"), "Big Bang", "strip legacy arrow source")
-- Critical: labels must not contain the Details-breaking "<-" token
check(not Core.FormatProcLabel("A", "B"):find("<-", 1, true), "new labels must not contain <-")
check(not Core.FormatProcSourceSuffix("B"):find("<", 1, true), "suffix must not contain <")

-- Perk / server icon helpers
equal(Core.IsMissingIcon(nil), true, "nil icon missing")
equal(Core.IsMissingIcon(""), true, "empty icon missing")
equal(Core.IsMissingIcon(Core.QUESTION_ICON), true, "question icon missing")
equal(Core.IsMissingIcon([[Interface\Icons\Spell_Fire_Fireball02]]), false, "real icon ok")
equal(Core.IconFromPerkData({ icon = [[Interface\Icons\Ability_Warrior_SavageBlow]] }),
    [[Interface\Icons\Ability_Warrior_SavageBlow]], "icon from perk data")
equal(Core.IconFromPerkData({ Icon = [[Interface\Icons\Spell_Nature_Lightning]] }),
    [[Interface\Icons\Spell_Nature_Lightning]], "Icon capital field")
equal(Core.IconFromPerkData({ icon = Core.QUESTION_ICON }), nil, "question icon rejected")
equal(Core.NameFromPerkData({ comment = "Flowing Force" }), "Flowing Force", "name from comment")
equal(Core.NameFromPerkData({ name = "  Relentless Pursuit  " }), "Relentless Pursuit", "trim perk name")

-- Likely proc detection
equal(Core.IsLikelyProc(12345, { [12345] = true }), false, "cast spell is not a proc")
equal(Core.IsLikelyProc(99999, { [12345] = true }), true, "uncasted damage is a proc")
equal(Core.IsLikelyProc(1, { [1] = true }), false, "melee id ignored")

-- Resolve source within window
local casts = {
    { spellId = 10, name = "Old", t = 1.0 },
    { spellId = 20, name = "Incinerate", t = 5.0 },
}
local sid, sname = Core.ResolveProcSource(casts, 5.4, 1.5)
equal(sid, 20, "newest in-window source id")
equal(sname, "Incinerate", "newest in-window source name")
sid, sname = Core.ResolveProcSource(casts, 10.0, 1.5)
equal(sid, nil, "expired window yields nil")

-- Record + flatten attribution
local attr = Core.RecordProcDamage(nil, 50001, 20, 1000)
attr = Core.RecordProcDamage(attr, 50001, 20, 500)
attr = Core.RecordProcDamage(attr, 50002, 30, 2000)
local rows = Core.BuildProcRows(attr, function(id)
    if id == 50001 then return "ProcA" end
    if id == 50002 then return "ProcB" end
    if id == 20 then return "Incinerate" end
    if id == 30 then return "Shadow Bolt" end
    return tostring(id)
end, function(id)
    if id == 50002 then return [[Interface\Icons\Spell_Shadow_ShadowBolt]] end
    return nil
end)
equal(#rows, 2, "two proc rows")
equal(rows[1].amount, 2000, "highest amount first")
equal(rows[1].key, "ProcB [Shadow Bolt]", "row key format")
equal(rows[1].procName, "ProcB", "short proc name for bar")
equal(rows[1].sourceSuffix, " [Shadow Bolt]", "source as suffix")
equal(rows[1].icon, [[Interface\Icons\Spell_Shadow_ShadowBolt]], "icon from resolver")
equal(rows[2].amount, 1500, "accumulated same proc+source")
equal(rows[2].icon, Core.QUESTION_ICON, "missing icon falls back to question")

-- Hits accumulate with amount
equal(rows[2].hits, 2, "two hits accumulated for ProcA")
equal(rows[1].hits, 1, "one hit for ProcB")

-- Copy + merge attribution (Overall Data aggregation)
local fight1 = Core.RecordProcDamage(nil, 50001, 20, 1000)
fight1 = Core.RecordProcDamage(fight1, 50001, 20, 500)
local fight2 = Core.RecordProcDamage(nil, 50001, 20, 200)
fight2 = Core.RecordProcDamage(fight2, 50002, 30, 900)
local copied = Core.CopyProcAttribution(fight1)
equal(copied[50001][20].amount, 1500, "copy preserves amount")
equal(copied[50001][20].hits, 2, "copy preserves hits")
copied[50001][20].amount = 1
equal(fight1[50001][20].amount, 1500, "copy is deep (mutate safe)")
local overall = Core.MergeProcAttribution(Core.CopyProcAttribution(fight1), fight2)
equal(overall[50001][20].amount, 1700, "overall merges same proc+source")
equal(overall[50001][20].hits, 3, "overall merges hits")
equal(overall[50002][30].amount, 900, "overall keeps other proc")
local emptyMerge = Core.MergeProcAttribution(nil, fight1)
equal(emptyMerge[50001][20].amount, 1500, "merge from nil dest")

-- Breakdown for click summary
local bd = Core.BuildProcRowBreakdown(attr, 50001, 20, function(id)
    if id == 50001 then return "ProcA" end
    if id == 50002 then return "ProcB" end
    if id == 20 then return "Incinerate" end
    if id == 30 then return "Shadow Bolt" end
    return tostring(id)
end)
check(bd ~= nil, "breakdown exists")
equal(bd.amount, 1500, "breakdown amount")
equal(bd.hits, 2, "breakdown hits")
equal(bd.average, 750, "breakdown average")
equal(bd.key, "ProcA [Incinerate]", "breakdown key")
equal(#bd.siblingSources, 0, "no other sources for ProcA yet")

attr = Core.RecordProcDamage(attr, 50001, 30, 400)
bd = Core.BuildProcRowBreakdown(attr, 50001, 20, function(id)
    if id == 50001 then return "ProcA" end
    if id == 30 then return "Shadow Bolt" end
    if id == 20 then return "Incinerate" end
    return tostring(id)
end)
equal(#bd.siblingSources, 1, "sibling source after second cast")
equal(bd.siblingSources[1].sourceName, "Shadow Bolt", "sibling source name")
equal(bd.siblingSources[1].amount, 400, "sibling source amount")

bd = Core.BuildProcRowBreakdown(attr, 50002, 30, function(id)
    if id == 50002 then return "ProcB" end
    if id == 50001 then return "ProcA" end
    if id == 30 then return "Shadow Bolt" end
    return tostring(id)
end)
equal(#bd.siblingProcs, 1, "sibling proc from same source")
equal(bd.siblingProcs[1].procName, "ProcA", "sibling proc name")

-- NormalizeProcEntry legacy number
local a, h = Core.NormalizeProcEntry(1234)
equal(a, 1234, "legacy amount")
equal(h, 1, "legacy hits default 1")
a, h = Core.NormalizeProcEntry({ amount = 50, hits = 3 })
equal(a, 50, "table amount")
equal(h, 3, "table hits")

-- Empty nameResolver source must not create " ()"
local attr2 = Core.RecordProcDamage(nil, 9, 8, 100)
local rows2 = Core.BuildProcRows(attr2, function(id)
    if id == 9 then return "Flowing Force" end
    return "" -- empty source name
end)
equal(rows2[1].key, "Flowing Force", "empty source name => no parens on key")
equal(rows2[1].sourceSuffix, "", "empty source => empty suffix")

-- Echo damage matching
local index = Core.BuildEchoIndex({
    { spellId = 200100, name = "Echo One" },
    { spellId = 200200, name = "Echo Two" },
})
local matched = Core.MatchEchoDamage({
    [200100] = { total = 4000 },
    [133] = { total = 9000, name = "Fireball" },
    [200200] = { total = 1000, name = "Echo Two" },
}, index)
equal(matched["Echo One"], 4000, "match by id")
equal(matched["Echo Two"], 1000, "match second echo")
equal(matched["Fireball"], nil, "non-echo ignored")

if failures > 0 then
    io.stderr:write(string.format("\n%d failure(s)\n", failures))
    os.exit(1)
end
print("test_details_project_ebonhold: all checks passed")
