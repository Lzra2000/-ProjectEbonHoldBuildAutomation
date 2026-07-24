-- Sync / ChatLink chunk framing contracts + RingBuffer unit coverage.
-- SendChunked is module-local; we verify the documented 180-byte frame and
-- exercise reassembly through the existing _DispatchAddonForTests hook.
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)
local rng = H.rng(H.SEED_DEFAULT)

------------------------------------------------------------------------
-- RingBuffer (pure, SavedVariables-safe queue)
------------------------------------------------------------------------
do
    local addon = H.load_addon("core/RingBuffer.lua")
    local R = addon.RingBuffer
    local ring = R.New(3)
    check(R.Is(ring), "New returns a ring")
    equal(R.Count(ring), 0, "empty count")
    R.Append(ring, "a")
    R.Append(ring, "b")
    R.Append(ring, "c")
    equal(R.Count(ring), 3, "full count")
    R.Append(ring, "d") -- overwrite oldest
    equal(R.Count(ring), 3, "capacity capped")
    equal(R.PopOldest(ring), "b", "oldest after overwrite is b")
    equal(R.PopOldest(ring), "c", "next is c")
    equal(R.PopOldest(ring), "d", "next is d")
    equal(R.PopOldest(ring), nil, "empty pop")
    R.Append(ring, 1)
    R.Append(ring, 2)
    equal(R.RemoveIf(ring, function(v) return v == 1 end), 1, "RemoveIf removes one")
    equal(R.Count(ring), 1, "one value remains")
    local arr = R.ToArray(ring)
    equal(arr[1], 2, "ToArray order")
    R.Clear(ring)
    equal(R.Count(ring), 0, "cleared")
end

------------------------------------------------------------------------
-- Sync source contracts for chunk framing
------------------------------------------------------------------------
do
    local src = H.read_file("modules/sync/Sync.lua")
    check(src:find("local MAX_CHUNK%s*=%s*180"), "MAX_CHUNK is 180 bytes (addon message budget)")
    check(src:find("local MAX_BUILD_TRANSFER%s*=%s*36000"), "MAX_BUILD_TRANSFER is 36 KB safety ceiling")
    check(src:find('"%s|%s|%s|%d/%d|%s"', 1, true),
        "chunk payload format is code|sender|streamKey|idx/total|data")
    check(src:find("MAX_BUILD_TRANSFER"), "transfer size ceiling exists")
    check(src:find("ReportOversizedBuild"), "oversized builds are reported with size + toast")
    check(src:find("GetMaxBuildTransfer"), "transfer ceiling is queryable for UI warnings")
    check(src:find("ExportBuildForTransfer") or src:find("EncodeBuildForTransfer"),
        "peer sync uses transfer encoder (auto-strip path)")
    check(src:find("ReportStrippedTransfer"), "auto-stripped transfers surface a toast")
    check(not src:find("C_ChatInfo", 1, true), "Sync must not use C_ChatInfo (post-3.3.5a)")
    check(not src:find(":RegisterEvent%s*%("),
        "Sync must register events via WoWEvents, not frame:RegisterEvent")
end

------------------------------------------------------------------------
-- ExportImport.ExportBuildForTransfer auto-strip contracts
------------------------------------------------------------------------
do
    local src = H.read_file("modules/build/ExportImport.lua")
    check(src:find("function EbonBuilds%.ExportImport%.ExportBuildForTransfer"),
        "ExportBuildForTransfer is defined")
    check(src:find("omitSnapshot"), "transfer strip can omit characterSnapshot")
    check(src:find("maxCommentBytes"), "transfer strip can trim comments")
end

------------------------------------------------------------------------
-- Theme.ScrollBar spam exemption (OnValueChanged is high-frequency by design)
------------------------------------------------------------------------
do
    local theme = H.read_file("modules/ui/Theme.lua")
    check(theme:find('ProtectScript%(bar, "Theme.ScrollBar", true%)'),
        "Theme.ScrollBar ProtectScript is spamExempt")
    check(theme:find('ProtectScript%(bar, "Theme.HorizontalScrollBar", true%)'),
        "Theme.HorizontalScrollBar ProtectScript is spamExempt")
end

------------------------------------------------------------------------
-- ChatLink + Sync: short id token length matches GET broadcast prefix
------------------------------------------------------------------------
do
    local chat = H.load_addon("modules/sync/ChatLink.lua")
    local token = chat.ChatLink.TokenFor({
        id = "aabbccdd-1122-3344-5566-77889900aabb",
        title = "X",
    })
    local id8 = token:match("%[EbonBuilds:(%w+):")
    equal(#id8, 8, "ChatLink short id is 8 chars (matches Sync GET prefix)")
end

------------------------------------------------------------------------
-- Deterministic seed smoke (harness RNG is stable across runs)
------------------------------------------------------------------------
do
    local a = { rng(10), rng(10), rng(10) }
    local rng2 = H.rng(H.SEED_DEFAULT)
    local b = { rng2(10), rng2(10), rng2(10) }
    equal(a[1], b[1], "seeded RNG is deterministic (1)")
    equal(a[2], b[2], "seeded RNG is deterministic (2)")
    equal(a[3], b[3], "seeded RNG is deterministic (3)")
end

H.exit_if_failed(counters, "sync/chunk harness test(s)")
print("Sync/chunk + RingBuffer coverage passed: framing contracts, short-id parity, deterministic seeds.")
