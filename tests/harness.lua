-- Shared headless harness for EbonBuilds tests (WoW 3.3.5a / build 12340).
-- Load with: local H = dofile("tests/harness.lua")
-- Provides assertions, deterministic seeds, and 3.3.5a-shaped API stubs.

local H = {}

H.SEED_DEFAULT = 20260724

function H.new_counters()
    return { failures = 0 }
end

function H.attach_assertions(counters, prefix)
    prefix = prefix or "FAIL"
    local function check(condition, message)
        if not condition then
            counters.failures = counters.failures + 1
            io.stderr:write(prefix .. ": " .. tostring(message) .. "\n")
        end
    end
    local function equal(actual, expected, message)
        check(actual == expected, string.format("%s (expected %s, got %s)",
            message, tostring(expected), tostring(actual)))
    end
    local function near(actual, expected, message, eps)
        eps = eps or 1e-9
        check(type(actual) == "number" and math.abs(actual - expected) < eps,
            string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
    local function contains(haystack, needle, message)
        check(type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil,
            message or ("expected to find " .. tostring(needle)))
    end
    return check, equal, near, contains
end

function H.read_file(path)
    local file, err = io.open(path, "rb")
    if not file then error(err or ("unable to read " .. path), 2) end
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

function H.toc_lua_files()
    local files = {}
    for line in io.lines("EbonBuilds.toc") do
        line = line:gsub("\r$", "")
        if line:match("^%S+%.lua$") then
            files[#files + 1] = line
        end
    end
    return files
end

local function bxor(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit ~= bbit then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

-- Deterministic LCG PRNG (no reliance on math.randomseed quirks across hosts).
function H.rng(seed)
    local state = tonumber(seed) or H.SEED_DEFAULT
    if state <= 0 then state = H.SEED_DEFAULT end
    return function(n)
        -- Numerical Recipes LCG, kept in 32-bit range via modulo.
        state = (state * 1664525 + 1013904223) % 4294967296
        if n then
            return 1 + (state % n)
        end
        return state / 4294967296
    end
end

-- Minimal bit library used by CLEU affiliation masks in 3.3.5a.
function H.ensure_bit()
    bit = bit or {}
    if not bit.band then
        bit.band = function(a, b)
            a, b = tonumber(a) or 0, tonumber(b) or 0
            local result, place = 0, 1
            while a > 0 or b > 0 do
                local abit, bbit = a % 2, b % 2
                if abit == 1 and bbit == 1 then result = result + place end
                a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
            end
            return result
        end
    end
    if not bit.bxor then
        bit.bxor = bxor
    end
    return bit
end

------------------------------------------------------------------------
-- WoW 3.3.5a API surface notes (stubs must match client arity/semantics)
------------------------------------------------------------------------
-- GetContainerItemInfo(bag, slot) -> texture, count, locked, quality, readable,
--   lootable, link  -- quality is the 4th return (NOT the 3rd; 3rd is locked).
-- GetItemInfo(link) -> name, link, quality, iLevel, reqLevel, class, subclass,
--   maxStack, equipLoc, texture, vendorPrice
-- GetAuctionItemClasses() -> localized top-level auction class names (Trade Goods,
--   Recipe, ...). AutoSell compares GetItemInfo's itemType against TRADE_GOODS /
--   RECIPE globals which mirror those localized strings.
-- COMBAT_LOG_EVENT_UNFILTERED (3.3.5a, no hideCaster):
--   timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName,
--   destFlags, ...spell/amount fields by subevent

function H.install_container_stubs(opts)
    opts = opts or {}
    local links = opts.links or {}
    local info = opts.info or {}

    function GetContainerItemLink(bag, slot)
        return links[bag] and links[bag][slot] or nil
    end

    -- 3.3.5a: quality is return #4. Returning only three values (as older stubs
    -- did) silently drops quality and breaks BagAffixDots / AutoSell paths that
    -- accidentally read the wrong slot.
    function GetContainerItemInfo(bag, slot)
        local row = info[bag] and info[bag][slot]
        if not row then
            return nil, nil, nil, nil, nil, nil, nil
        end
        return row.texture, row.count, row.locked, row.quality, row.readable, row.lootable, row.link
    end

    return links, info
end

function H.install_auction_class_stubs(classes)
    -- Default English 3.3.5a auction class names (order matches client).
    classes = classes or {
        "Weapon", "Armor", "Container", "Consumable", "Glyph",
        "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem",
        "Miscellaneous", "Quest",
    }
    function GetAuctionItemClasses()
        return unpack(classes)
    end
    TRADE_GOODS = TRADE_GOODS or "Trade Goods"
    RECIPE = RECIPE or "Recipe"
    return classes
end

function H.install_cleu_constants()
    COMBATLOG_OBJECT_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
    COMBATLOG_OBJECT_AFFILIATION_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
    COMBATLOG_OBJECT_AFFILIATION_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
    COMBATLOG_OBJECT_REACTION_FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010
    COMBATLOG_OBJECT_CONTROL_PLAYER = COMBATLOG_OBJECT_CONTROL_PLAYER or 0x00000100
    COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
end

-- Build a 3.3.5a CLEU argument list (no hideCaster / no raidFlags columns).
function H.cleu_args(fields)
    fields = fields or {}
    return {
        fields.timestamp or 0,
        fields.event or "SPELL_DAMAGE",
        fields.sourceGUID or "0x0",
        fields.sourceName or "Player",
        fields.sourceFlags or COMBATLOG_OBJECT_AFFILIATION_MINE,
        fields.destGUID or "0x1",
        fields.destName or "Target",
        fields.destFlags or 0,
        fields.spellId or 1,
        fields.spellName or "Spell",
        fields.spellSchool or 1,
        fields.amount or 0,
        fields.overkill or 0,
        fields.school or 1,
        fields.resisted or 0,
        fields.blocked or 0,
        fields.absorbed or 0,
        fields.critical or false,
        fields.glancing or false,
        fields.crushing or false,
    }
end

function H.wow_events_stub()
    local listeners = {}
    return {
        listeners = listeners,
        On = function(event, fn, owner)
            local token = { event = event, fn = fn, owner = owner, active = true }
            listeners[#listeners + 1] = token
            return token
        end,
        Off = function(token)
            if type(token) ~= "table" then return false end
            for i = #listeners, 1, -1 do
                if listeners[i] == token then
                    table.remove(listeners, i)
                    token.active = false
                    return true
                end
            end
            return false
        end,
        Emit = function(event, ...)
            local snapshot = {}
            for i, token in ipairs(listeners) do snapshot[i] = token end
            for _, token in ipairs(snapshot) do
                if token.event == event and token.active then
                    token.fn(event, ...)
                end
            end
        end,
        Count = function(event)
            local n = 0
            for _, token in ipairs(listeners) do
                if token.active and (not event or token.event == event) then
                    n = n + 1
                end
            end
            return n
        end,
    }
end

function H.load_addon(path, addon)
    addon = addon or {}
    local chunk, err = loadfile(path)
    if not chunk then error(err or ("loadfile failed: " .. path), 2) end
    local ok, result = pcall(chunk, "EbonBuilds", addon)
    if not ok then error(path .. ": " .. tostring(result), 2) end
    return addon
end

function H.exit_if_failed(counters, label)
    if counters.failures > 0 then
        io.stderr:write(string.format("%d %s failed.\n", counters.failures, label or "test(s)"))
        os.exit(1)
    end
end

return H
