-- Pure-protocol coverage for core/AffixServer.lua (learned-affix whisper feed).
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

local addon = H.load_addon("core/AffixServer.lua")
local S = addon.AffixServer

------------------------------------------------------------------------
-- ShouldAcceptMessage
------------------------------------------------------------------------
do
    equal(S.PREFIX, "AAM0x9", "affix addon message prefix")
    equal(S.SEND_LEARNED, 513, "SEND_LEARNED event id")
    equal(S.REQUEST_LEARNED, 313, "REQUEST_LEARNED event id")

    local ok, reason = S.ShouldAcceptMessage("WRONG", "513\tbody", "WHISPER", "Me", "Me")
    equal(ok, false, "wrong prefix rejected")
    equal(reason, "prefix", "wrong prefix reason")

    ok, reason = S.ShouldAcceptMessage(S.PREFIX, "513\tbody", "PARTY", "Me", "Me")
    equal(ok, false, "non-whisper rejected")
    equal(reason, "dist", "non-whisper reason")

    ok, reason = S.ShouldAcceptMessage(S.PREFIX, "513\tbody", "WHISPER", "Other-Realm", "Me")
    equal(ok, false, "foreign sender rejected")
    equal(reason, "sender", "foreign sender reason")

    -- Realm suffix is stripped; case-insensitive.
    ok, reason = S.ShouldAcceptMessage(S.PREFIX, "513\tbody", "WHISPER", "ME-Realm", "me")
    equal(ok, true, "same player with realm suffix accepted")
    equal(reason, nil, "accepted message has no reject reason")

    ok, reason = S.ShouldAcceptMessage(S.PREFIX, "", "WHISPER", "Me", "Me")
    equal(ok, false, "empty payload rejected")
    equal(reason, "payload", "empty payload reason")

    ok, reason = S.ShouldAcceptMessage(S.PREFIX, "313\tbody", "WHISPER", "Me", "Me")
    equal(ok, false, "request event is not a reply")
    equal(reason, "event", "wrong event reason")

    ok = S.ShouldAcceptMessage(S.PREFIX, "513", "WHISPER", "Me", "Me")
    equal(ok, true, "bare SEND_LEARNED event accepted")
end

------------------------------------------------------------------------
-- ParseEventPayload / ParseChunk / BuildRequestPayload
------------------------------------------------------------------------
do
    local evt, rest = S.ParseEventPayload("513\t@ABCD\t001/002\tslice")
    equal(evt, 513, "tabbed event parses")
    equal(rest, "@ABCD\t001/002\tslice", "rest after event tab")

    evt, rest = S.ParseEventPayload("513")
    equal(evt, 513, "bare event parses")
    equal(rest, "", "bare event rest is empty")

    equal(S.ParseEventPayload(nil), nil, "nil payload yields nil event")

    local chunk = S.ParseChunk("@aBcD\t001/00A\thello")
    check(chunk ~= nil, "valid chunk header parses")
    equal(chunk.mid, "aBcD", "chunk message id")
    equal(chunk.index, 1, "chunk index hex")
    equal(chunk.total, 10, "chunk total hex")
    equal(chunk.slice, "hello", "chunk slice")

    equal(S.ParseChunk("not-a-chunk"), nil, "malformed chunk rejected")
    equal(S.ParseChunk(nil), nil, "nil chunk rejected")

    equal(S.BuildRequestPayload(), "313", "request payload is bare event id")
end

------------------------------------------------------------------------
-- ParseLearnedAffixesPayload (injected GetSpellInfo)
------------------------------------------------------------------------
do
    local names = { [9001] = "Test Affix", [9002] = "Weapon Affix" }
    local icons = { [9001] = "Interface\\Icons\\Spell_1", [9002] = "Interface\\Icons\\Spell_2" }
    local function getSpellInfo(id)
        return names[id], nil, icons[id]
    end

    local body = "9001:10:2:3:0:1,9002:5:0:1:1:0,bad-entry,9003:1:1:1:0:1"
    local affixes = S.ParseLearnedAffixesPayload(body, getSpellInfo)
    equal(#affixes, 3, "three well-formed affix entries")
    equal(affixes[1].id, 9001, "first affix id")
    equal(affixes[1].name, "Test Affix", "injected spell name")
    equal(affixes[1].icon, "Interface\\Icons\\Spell_1", "injected spell icon")
    equal(affixes[1].applyCost, 10, "applyCost")
    equal(affixes[1].appliedCount, 2, "appliedCount")
    equal(affixes[1].difficulty, 3, "difficulty")
    equal(affixes[1].weaponOnly, false, "weaponOnly false")
    equal(affixes[1].learned, true, "learned true")
    equal(affixes[2].weaponOnly, true, "second entry weaponOnly")
    equal(affixes[2].learned, false, "second entry not learned")
    equal(affixes[3].name, "Affix 9003", "missing GetSpellInfo falls back to Affix <id>")

    equal(#S.ParseLearnedAffixesPayload("", getSpellInfo), 0, "empty body")
    equal(#S.ParseLearnedAffixesPayload(nil, getSpellInfo), 0, "nil body")
end

H.exit_if_failed(counters, "AffixServer test(s)")
print("AffixServer protocol coverage passed: accept filters, chunk headers, and learned-affix parsing.")
