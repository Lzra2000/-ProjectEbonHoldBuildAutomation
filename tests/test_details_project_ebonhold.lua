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

-- Proc labels
equal(Core.FormatProcLabel("Chaos Bolt", "Incinerate"), "Chaos Bolt (← Incinerate)", "proc from source")
equal(Core.FormatProcLabel("Trinket Hit", nil), "Trinket Hit (Proc)", "proc without source")
equal(Core.FormatProcLabel("X (← Y)", "Z"), "X (← Y)", "do not nest attribution")

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
end)
equal(#rows, 2, "two proc rows")
equal(rows[1].amount, 2000, "highest amount first")
equal(rows[1].key, "ProcB (← Shadow Bolt)", "row key format")
equal(rows[2].amount, 1500, "accumulated same proc+source")

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
