local addonName, EbonBuilds = ...

-- EbonBuilds: modules/sync/ChatLink.lua
-- Shareable build links in chat. WoW's server strips unknown hyperlink
-- types from outgoing messages, so we send a PLAIN-TEXT token
--   [EbonBuilds:<id8>:<title>]
-- and every EbonBuilds client re-renders it locally as a clickable link.
-- Clicking fetches the build from whoever has it (GET broadcast; only
-- public builds are ever served, mirroring the RTX rule).

EbonBuilds.ChatLink = {}

local TOKEN_PATTERN = "%[EbonBuilds:(%w%w%w%w%w%w%w%w):([^%]|]+)%]"

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------

function EbonBuilds.ChatLink.TokenFor(build)
    if not build or not build.id then return nil end
    local id8 = build.id:gsub("%-", ""):sub(1, 8)
    local title = (build.title or "Untitled"):gsub("[%[%]|]", ""):sub(1, 40)
    return string.format("[EbonBuilds:%s:%s]", id8, title)
end

-- Puts the token into the active chat edit box (or opens one).
function EbonBuilds.ChatLink.InsertLink(build)
    local token = EbonBuilds.ChatLink.TokenFor(build)
    if not token then return end
    local edit = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
    if edit then
        if not edit:IsShown() then
            ChatEdit_ActivateChat(edit)
        end
        edit:Insert(token)
    end
end

------------------------------------------------------------------------
-- Receiving: re-render tokens as clickable links (local display only)
------------------------------------------------------------------------

function EbonBuilds.ChatLink.RenderTokens(msg)
    if not msg or not msg:find("%[EbonBuilds:") then return msg, false end
    local replaced = msg:gsub(TOKEN_PATTERN, function(id8, title)
        return string.format("|cff19ff19|HEbonBuildsLink:%s|h[EbonBuilds: %s]|h|r", id8, title)
    end)
    return replaced, replaced ~= msg
end

local function ChatFilter(_, _, msg, ...)
    local rendered, changed = EbonBuilds.ChatLink.RenderTokens(msg)
    if changed then
        return false, rendered, ...
    end
    return false
end

------------------------------------------------------------------------
-- Clicking: find locally, else fetch from the network
------------------------------------------------------------------------

local function FindByShortId(id8)
    local function matches(id) return id and id:gsub("%-", ""):sub(1, 8) == id8 end
    for id, b in pairs(EbonBuildsDB.builds or {}) do
        if matches(id) then return b, "local" end
    end
    for id, b in pairs(EbonBuildsDB.remoteBuilds or {}) do
        if matches(id) then return b, "remote" end
    end
    return nil
end

local pendingFetch = {}   -- [id8] = request time (throttle repeat clicks)

local function OnLinkClicked(id8)
    local build, where = FindByShortId(id8)
    if build then
        EbonBuilds.MainWindow.Toggle()
        if where == "local" then
            EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
        else
            EbonBuilds.ViewRouter.Show("publicBuilds")
        end
        return
    end

    -- Not known yet: ask the network. Only holders of a PUBLIC build with
    -- this prefix will answer (GET handler mirrors the RTX safety rule).
    local now = GetTime()
    if pendingFetch[id8] and now - pendingFetch[id8] < 10 then return end
    pendingFetch[id8] = now
    if EbonBuilds.Sync and EbonBuilds.Sync.BroadcastGet then
        EbonBuilds.Sync.BroadcastGet(id8)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100EbonBuilds:|r requesting build from other players...")
    end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.ChatLink.Init()
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL",
    }
    for _, ev in ipairs(events) do
        ChatFrame_AddMessageEventFilter(ev, ChatFilter)
    end

    -- Handle clicks on our custom link type.
    hooksecurefunc("SetItemRef", function(link)
        local id8 = link and link:match("^EbonBuildsLink:(%w+)$")
        if id8 then OnLinkClicked(id8) end
    end)
end
