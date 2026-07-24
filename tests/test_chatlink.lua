-- ChatLink token encode/render coverage (plain-text share tokens).
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

EbonBuildsDB = { builds = {}, remoteBuilds = {} }
local addon = H.load_addon("modules/sync/ChatLink.lua")
local CL = addon.ChatLink

------------------------------------------------------------------------
-- TokenFor
------------------------------------------------------------------------
do
    equal(CL.TokenFor(nil), nil, "nil build yields nil token")
    equal(CL.TokenFor({}), nil, "build without id yields nil token")

    local token = CL.TokenFor({
        id = "abcdef12-3456-7890-abcd-ef1234567890",
        title = "My Build",
    })
    equal(token, "[EbonBuilds:abcdef12:My Build]", "token uses first 8 id chars and title")

    token = CL.TokenFor({
        id = "deadbeef-0000-0000-0000-000000000000",
        title = "Evil[|]Title",
    })
    equal(token, "[EbonBuilds:deadbeef:EvilTitle]", "brackets/pipes stripped from title")

    token = CL.TokenFor({ id = "12345678-aaaa-bbbb-cccc-ddddeeeeffff" })
    equal(token, "[EbonBuilds:12345678:Untitled]", "missing title becomes Untitled")

    local long = string.rep("A", 80)
    token = CL.TokenFor({ id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title = long })
    check(token:match("%[EbonBuilds:aaaaaaaa:(.+)%]$"), "long title still forms a token")
    local titlePart = token:match("%[EbonBuilds:aaaaaaaa:(.+)%]$")
    equal(#titlePart, 40, "title truncated to 40 chars")
end

------------------------------------------------------------------------
-- RenderTokens
------------------------------------------------------------------------
do
    local msg, changed = CL.RenderTokens("hello world")
    equal(msg, "hello world", "plain message unchanged")
    equal(changed, false, "plain message not marked changed")

    msg, changed = CL.RenderTokens("see [EbonBuilds:abcdef12:Frost Mage] please")
    equal(changed, true, "token message marked changed")
    check(msg:find("|HEbonBuildsLink:abcdef12|h", 1, true), "renders clickable hyperlink")
    check(msg:find("%[EbonBuilds: Frost Mage%]|h|r"), "display text keeps title")

    msg, changed = CL.RenderTokens(nil)
    equal(msg, nil, "nil message stays nil")
    equal(changed, false, "nil message not changed")
end

------------------------------------------------------------------------
-- Source: Init uses chat filters + SetItemRef hook, not raw RegisterEvent
------------------------------------------------------------------------
do
    local src = H.read_file("modules/sync/ChatLink.lua")
    check(src:find("ChatFrame_AddMessageEventFilter", 1, true),
        "ChatLink filters chat via ChatFrame_AddMessageEventFilter")
    check(src:find('hooksecurefunc("SetItemRef"', 1, true),
        "ChatLink clicks go through SetItemRef hook")
    check(not src:find(":RegisterEvent%s*%("),
        "ChatLink must not call frame:RegisterEvent (use chat filters / hooks)")
end

H.exit_if_failed(counters, "ChatLink test(s)")
print("ChatLink coverage passed: token encoding, render, and click/filter architecture.")
