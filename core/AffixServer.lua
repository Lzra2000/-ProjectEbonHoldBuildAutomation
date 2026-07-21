local addonName, EbonBuilds = ...

-- EbonBuilds: core/AffixServer.lua
-- Wire protocol for Project Ebonhold's server-fed "learned affixes" feed.
-- This is a different system from Echoes: Affixes are permanent per-
-- character unlocks that can be applied to gear (weapon procs, armor
-- stats), tracked server-side and queried over a whisper-based addon
-- message channel -- not something the client has to guess from tooltip
-- text. Protocol details ported from the AutoDelete addon, which already
-- speaks this protocol for its own purposes.
--
-- Pure parsing/formatting only: no CreateFrame, no SendAddonMessage, no
-- game state. Every function here is a straight string -> data transform,
-- which is what makes it fully unit-testable without WoW mocks.

EbonBuilds.AffixServer = {}
local S = EbonBuilds.AffixServer

S.PREFIX                  = "AAM0x9"
S.REQUEST_LEARNED         = 313
S.SEND_LEARNED            = 513
S.REQUEST_THROTTLE_SECONDS = 5

local function NormalizeSender(name)
    name = tostring(name or ""):lower()
    name = name:match("^([^-]+)") or name
    return name
end

-- Filters incoming CHAT_MSG_ADDON events down to genuine server replies:
-- right prefix, whispered (not broadcast), and from the player's own
-- account (the server whispers itself to the requesting character).
function S.ShouldAcceptMessage(prefix, payload, dist, sender, playerName)
    if prefix ~= S.PREFIX then return false, "prefix" end
    if dist ~= "WHISPER" then return false, "dist" end
    if playerName and sender and NormalizeSender(sender) ~= NormalizeSender(playerName) then
        return false, "sender"
    end
    if type(payload) ~= "string" or payload == "" then
        return false, "payload"
    end
    local evtStr = payload:match("^(%d+)\t") or payload:match("^(%d+)$")
    if tonumber(evtStr) ~= S.SEND_LEARNED then
        return false, "event"
    end
    return true
end

-- "513\t<rest>" or bare "513" -> event number, rest-of-payload.
function S.ParseEventPayload(payload)
    if type(payload) ~= "string" then return nil, nil end
    local evtStr, rest = payload:match("^(%d+)\t(.*)$")
    if not evtStr then
        evtStr = payload:match("^(%d+)$")
        rest = ""
    end
    return tonumber(evtStr), rest or ""
end

-- Chunk header format: "@<4-hex message-id>\t<3-hex index>/<3-hex total>\t<slice>"
function S.ParseChunk(rest)
    if type(rest) ~= "string" then return nil end
    local mid, idx, total, slice = rest:match(
        "^@([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])/([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t(.*)$")
    if not mid then return nil end
    return {
        mid   = mid,
        index = tonumber(idx, 16),
        total = tonumber(total, 16),
        slice = slice,
    }
end

-- Body is comma-separated "spellId:applyCost:appliedCount:difficulty:weaponOnly:learned".
-- getSpellInfo is injected (real GetSpellInfo in-game, a stub in tests) so
-- this stays a pure function of its inputs.
function S.ParseLearnedAffixesPayload(body, getSpellInfo)
    local affixes = {}
    if body and body ~= "" then
        for entry in string.gmatch(body, "([^,]+)") do
            local spellIdStr, applyCostStr, appliedCountStr, difficultyStr, weaponOnlyStr, learnedStr =
                entry:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
            if spellIdStr then
                local spellId = tonumber(spellIdStr)
                local spellName, spellIcon
                if type(getSpellInfo) == "function" then
                    local _
                    spellName, _, spellIcon = getSpellInfo(spellId)
                end
                affixes[#affixes + 1] = {
                    id           = spellId,
                    name         = spellName or ("Affix " .. spellId),
                    icon         = spellIcon,
                    applyCost    = tonumber(applyCostStr),
                    appliedCount = tonumber(appliedCountStr),
                    difficulty   = tonumber(difficultyStr),
                    weaponOnly   = tonumber(weaponOnlyStr) == 1,
                    learned      = tonumber(learnedStr) == 1,
                }
            end
        end
    end
    return affixes
end

-- Builds the request payload sent to the server (a bare event number).
function S.BuildRequestPayload()
    return tostring(S.REQUEST_LEARNED)
end
