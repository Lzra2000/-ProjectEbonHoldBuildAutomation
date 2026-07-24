-- Documents the 3.3.5a COMBAT_LOG_EVENT_UNFILTERED positional layout so a
-- future Session DPS module (issue #46 / PR #65) cannot silently adopt the
-- retail CLEU shape (hideCaster / raidFlags columns). Pure harness smoke.
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

H.ensure_bit()
H.install_cleu_constants()

local args = H.cleu_args({
    timestamp = 12.5,
    event = "SPELL_DAMAGE",
    sourceGUID = "0xPLAYER",
    sourceName = "Tester",
    sourceFlags = COMBATLOG_OBJECT_AFFILIATION_MINE,
    destGUID = "0xMOB",
    destName = "Target",
    destFlags = 0,
    spellId = 133,
    spellName = "Fireball",
    spellSchool = 4,
    amount = 1500,
    overkill = 0,
    school = 4,
    critical = true,
})

-- 3.3.5a CLEU has NO hideCaster between event and sourceGUID.
equal(args[1], 12.5, "1 timestamp")
equal(args[2], "SPELL_DAMAGE", "2 subevent")
equal(args[3], "0xPLAYER", "3 sourceGUID (not hideCaster)")
equal(args[4], "Tester", "4 sourceName")
equal(args[5], COMBATLOG_OBJECT_AFFILIATION_MINE, "5 sourceFlags")
equal(args[6], "0xMOB", "6 destGUID")
equal(args[7], "Target", "7 destName")
equal(args[8], 0, "8 destFlags")
equal(args[9], 133, "9 spellId")
equal(args[10], "Fireball", "10 spellName")
equal(args[12], 1500, "12 amount")
equal(args[18], true, "18 critical")

check(bit.band(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0,
    "bit.band affiliation mask works")

-- Source contract: no shipped module may reference hideCaster (retail CLEU).
for _, path in ipairs(H.toc_lua_files()) do
    if path ~= "modules/data/FAQContent.lua" then
        local text = H.read_file(path)
        check(not text:find("hideCaster", 1, true),
            path .. " must not reference hideCaster (retail CLEU column absent in 3.3.5a)")
    end
end

H.exit_if_failed(counters, "CLEU layout test(s)")
print("CLEU 3.3.5a layout contract passed: positional args and no hideCaster in shipped code.")
