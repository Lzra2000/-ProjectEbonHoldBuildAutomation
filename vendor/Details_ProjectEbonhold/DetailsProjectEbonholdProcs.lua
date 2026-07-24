-- DetailsProjectEbonholdProcs.lua
-- Attribute secondary/proc damage to the player cast that likely triggered it,
-- and surface a Details! Custom Display "PE Proc Sources" with click breakdown.
-- Target: WoW 3.3.5a / build 12340 CLEU (no CombatLogGetCurrentEventInfo).

local PE = DetailsProjectEbonhold
local Core = DetailsProjectEbonholdCore

PE.Procs = PE.Procs or {}
local Procs = PE.Procs

local wipe = wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local PLAYER_GUID
local recentCasts = {} -- { {spellId=, name=, t=}, ... }
local recentCastIds = {} -- set of spellIds currently in the window
local attribution = {} -- [procId] = { [sourceId] = { amount=, hits= } }
local MAX_RECENT = 24
-- Details Player Details Breakdown uses 20px spell bars; match that chrome.
local BREAKDOWN_BAR_H = 20
local BREAKDOWN_HEADER_H = 18
local BREAKDOWN_MAX_ROWS = 28
local BREAKDOWN_BAR_TEXTURE = [[Interface\AddOns\Details\images\bar_serenity]]
local BREAKDOWN_BG = [[Interface\AddOns\Details\images\background]]
local BREAKDOWN_FOCUS_COLOR = { 129 / 255, 125 / 255, 69 / 255, 1 }
local BREAKDOWN_BAR_COLOR = { 1, 1, 1, 0.85 }
local BREAKDOWN_ALT_COLOR = { 0.55, 0.65, 0.85, 0.9 }

local function Db()
    DetailsProjectEbonholdDB = DetailsProjectEbonholdDB or {}
    return DetailsProjectEbonholdDB
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function FormatAmount(value)
    value = tonumber(value) or 0
    local details = PE.GetDetails and PE.GetDetails()
    if type(details) == "table" and type(details.GetCurrentToKFunction) == "function" then
        local ok, fn = pcall(details.GetCurrentToKFunction, details)
        if ok and type(fn) == "function" then
            local ok2, text = pcall(fn, nil, value)
            if ok2 and type(text) == "string" and text ~= "" then
                return text
            end
        end
    end
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    end
    if value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return string.format("%.0f", value)
end

local function NameResolver(id)
    return PE.GetSpellName(id)
end

local function PruneRecent(now)
    local window = Core.PROC_ATTRIBUTION_WINDOW
    local kept = {}
    wipe(recentCastIds)
    for i = 1, #recentCasts do
        local e = recentCasts[i]
        if e and (now - (e.t or 0)) <= window * 2 then
            kept[#kept + 1] = e
            if e.spellId then
                recentCastIds[e.spellId] = true
            end
        end
    end
    recentCasts = kept
end

local function RememberCast(spellId, spellName)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 10 then
        return
    end
    local now = Now()
    PruneRecent(now)
    recentCasts[#recentCasts + 1] = {
        spellId = spellId,
        name = spellName or PE.GetSpellName(spellId),
        t = now,
    }
    recentCastIds[spellId] = true
    while #recentCasts > MAX_RECENT do
        table.remove(recentCasts, 1)
    end
end

local function IsPlayerSource(guid, flags)
    if PLAYER_GUID and guid == PLAYER_GUID then
        return true
    end
    -- COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400, AFFILIATION_MINE = 0x00000001
    if type(flags) == "number" and bit and bit.band then
        local MINE = 0x00000001
        local PLAYER = 0x00000400
        if bit.band(flags, MINE) ~= 0 and bit.band(flags, PLAYER) ~= 0 then
            return true
        end
        -- Also accept the player's pet/guardian as "our" casts for attribution.
        local PET = 0x00001000
        local GUARDIAN = 0x00002000
        if bit.band(flags, MINE) ~= 0 and (bit.band(flags, PET) ~= 0 or bit.band(flags, GUARDIAN) ~= 0) then
            return true
        end
    end
    return false
end

function Procs.ResetCombatAttribution()
    attribution = {}
end

function Procs.GetAttribution()
    return attribution
end

function Procs.GetProcRows()
    return Core.BuildProcRows(attribution, function(id)
        return PE.GetSpellName(id)
    end, function(id)
        return PE.GetSpellIcon(id)
    end)
end

function Procs.GetRowBreakdown(procId, sourceId)
    return Core.BuildProcRowBreakdown(attribution, procId, sourceId, NameResolver)
end

-- Resolve procId/sourceId from a Details custom-bar actor table.
function Procs.ResolveActorPair(actor)
    if type(actor) ~= "table" then
        return nil, nil
    end
    local procId = tonumber(actor.peProcId) or tonumber(actor.id)
    local sourceId = tonumber(actor.peSourceId)
    if procId and sourceId then
        return procId, sourceId
    end
    local key = actor.displayName or actor.nome or actor.name
    if type(key) == "string" and key ~= "" then
        local rows = Procs.GetProcRows()
        for i = 1, #rows do
            local row = rows[i]
            if row.key == key or row.procName == key then
                return row.procId, row.sourceId
            end
        end
    end
    return procId, sourceId or 0
end

local function AnnotateProcSpell(procId, sourceName)
    local base = PE.GetSpellName(procId)
    -- Strip prior attribution / echo markers for a clean re-label.
    if Core.StripProcSourceSuffix then
        base = Core.StripProcSourceSuffix(base)
    end
    base = base:gsub(" %(Echo%)", "")
    local label
    if Core.IsPeCustomSpellId(procId) then
        -- Prefer "EchoName (Echo) [SourceCast]" in the spell breakdown.
        label = Core.FormatEchoLabel(base)
        local suffix = Core.FormatProcSourceSuffix(sourceName)
        if suffix ~= "" then
            label = label .. suffix
        end
    else
        label = Core.FormatProcLabel(base, sourceName)
    end
    PE.SetSpellLabel(procId, label, PE.GetSpellIcon(procId))
end

local function OnDamage(spellId, spellName, amount)
    spellId = tonumber(spellId)
    amount = tonumber(amount) or 0
    if not spellId or amount <= 0 then
        return
    end
    local now = Now()
    PruneRecent(now)
    if not Core.IsLikelyProc(spellId, recentCastIds) then
        return
    end
    local sourceId, sourceName = Core.ResolveProcSource(recentCasts, now)
    if not sourceId then
        -- Still mark PE custom-band damage as Echo even without a cast source.
        if Core.IsPeCustomSpellId(spellId) and Db().labelEchoes ~= false then
            PE.SetSpellLabel(spellId, Core.FormatEchoLabel(spellName or PE.GetSpellName(spellId)), PE.GetSpellIcon(spellId))
        end
        return
    end
    attribution = Core.RecordProcDamage(attribution, spellId, sourceId, amount)
    AnnotateProcSpell(spellId, sourceName)
end

-- 3.3.5a CLEU: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
local function OnCombatLog(_, _, timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
    if Db().trackProcs == false then
        return
    end
    if not IsPlayerSource(srcGUID, srcFlags) then
        return
    end
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_CAST_START" then
        local spellId, spellName = ...
        RememberCast(spellId, spellName)
        return
    end
    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        -- Offensive buffs applied to the player can also be proc sources
        -- (trinkets, weapon enchants). Only remember auras on self.
        local spellId, spellName = ...
        if dstGUID == srcGUID or (PLAYER_GUID and dstGUID == PLAYER_GUID) then
            RememberCast(spellId, spellName)
        end
        return
    end
    if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
        or subevent == "RANGE_DAMAGE" or subevent == "DAMAGE_SHIELD" then
        local spellId, spellName, _, amount = ...
        OnDamage(spellId, spellName, amount)
    end
end

local CUSTOM_NAME = "PE Proc Sources"
-- Bump so Details InstallCustomObject replaces older scripts / tooltip copy.
local CUSTOM_VERSION = 5
-- Soft minimum height so more proc rows are visible without scrolling immediately.
local CUSTOM_MIN_HEIGHT = 260

local function EnsureReadableInstance(instance)
    if type(instance) ~= "table" then
        return
    end
    if type(instance.row_info) == "table" then
        -- Keep percent visible so Details does not render "97.6K()" with empty brackets.
        if type(instance.row_info.textR_show_data) == "table" then
            instance.row_info.textR_show_data[3] = true
        end
        -- percent_type 1 = vs total (fills the % column).
        if instance.row_info.percent_type ~= 1 and instance.row_info.percent_type ~= 2 then
            instance.row_info.percent_type = 1
        end
    end
    local frame = instance.baseframe or instance.BaseFrame
    if type(frame) == "table" and type(frame.GetHeight) == "function" and type(frame.SetHeight) == "function" then
        local ok, height = pcall(frame.GetHeight, frame)
        if ok and type(height) == "number" and height > 0 and height < CUSTOM_MIN_HEIGHT then
            pcall(frame.SetHeight, frame, CUSTOM_MIN_HEIGHT)
            if type(instance.SetSize) == "function" then
                pcall(instance.SetSize, instance)
            elseif type(instance.BaseFrameAnchors) == "function" then
                pcall(instance.BaseFrameAnchors, instance)
            end
        end
    end
end

Procs.EnsureReadableInstance = EnsureReadableInstance

---------------------------------------------------------------------------
-- Click → Details-styled breakdown (bars + icons + % like Player Details!)
-- Custom Display attribute 5 never opens AbreJanelaInfo; we mirror its chrome.
---------------------------------------------------------------------------

local breakdownFrame
local breakdownRows = {}

local function ResolveBarTexture()
    local details = PE.GetDetails and PE.GetDetails()
    if type(details) == "table" and type(details.player_details_window) == "table" then
        local name = details.player_details_window.bar_texture
        if type(name) == "string" and name ~= "" and LibStub then
            local ok, SharedMedia = pcall(LibStub, "LibSharedMedia-3.0")
            if ok and SharedMedia and type(SharedMedia.Fetch) == "function" then
                local tex = SharedMedia:Fetch("statusbar", name)
                if type(tex) == "string" and tex ~= "" then
                    return tex
                end
            end
        end
    end
    return BREAKDOWN_BAR_TEXTURE
end

local function BarColorForIndex(index, focused)
    if focused then
        return BREAKDOWN_FOCUS_COLOR[1], BREAKDOWN_FOCUS_COLOR[2], BREAKDOWN_FOCUS_COLOR[3], BREAKDOWN_FOCUS_COLOR[4]
    end
    if index % 2 == 0 then
        return BREAKDOWN_ALT_COLOR[1], BREAKDOWN_ALT_COLOR[2], BREAKDOWN_ALT_COLOR[3], BREAKDOWN_ALT_COLOR[4]
    end
    return BREAKDOWN_BAR_COLOR[1], BREAKDOWN_BAR_COLOR[2], BREAKDOWN_BAR_COLOR[3], BREAKDOWN_BAR_COLOR[4]
end

local function CreateBreakdownBar(parent, index)
    local bar = CreateFrame("Button", nil, parent)
    bar:SetHeight(BREAKDOWN_BAR_H)
    bar:EnableMouse(true)
    bar:Hide()

    local status = CreateFrame("StatusBar", nil, bar)
    status:SetAllPoints()
    status:SetMinMaxValues(0, 100)
    status:SetValue(0)
    status:SetStatusBarTexture(ResolveBarTexture())
    status:SetStatusBarColor(1, 1, 1, 0.85)
    status:SetAlpha(0.95)
    local bg = status:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(1, 1, 1, 0.08)
    bar.Status = status

    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(status:GetFrameLevel() + 2)

    local icon = overlay:CreateTexture(nil, "OVERLAY")
    icon:SetSize(BREAKDOWN_BAR_H - 2, BREAKDOWN_BAR_H - 2)
    icon:SetPoint("LEFT", bar, "LEFT", 1, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.Icon = icon

    local left = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    left:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    left:SetJustifyH("LEFT")
    left:SetTextColor(1, 1, 1, 1)
    left:SetNonSpaceWrap(true)
    if left.SetWordWrap then
        left:SetWordWrap(false)
    end
    bar.Left = left

    local right = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    right:SetJustifyH("RIGHT")
    right:SetTextColor(1, 1, 1, 1)
    bar.Right = right

    bar._index = index
    return bar
end

local function CreateSectionHeader(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "QuestFont_Large")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.890, 0.729, 0.015, 1)
    fs:Hide()
    return fs
end

local function EnsureBreakdownFrame()
    if breakdownFrame then
        return breakdownFrame
    end

    local f = CreateFrame("Frame", "DetailsPEProcBreakdownFrame", UIParent)
    f:SetSize(450, 460)
    f:SetPoint("CENTER", UIParent, "CENTER", 100, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f:SetBackdrop({
        bgFile = BREAKDOWN_BG,
        edgeFile = [[Interface\Buttons\WHITE8X8]],
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.94)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "DetailsPEProcBreakdownFrame")

    -- Match native title: gold, centered ("Player Details! Breakdown").
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetTextColor(0.890, 0.729, 0.015, 1)
    title:SetText("PE Proc Breakdown")
    f.Title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, -6)
    close:SetWidth(32)
    close:SetHeight(32)
    close:SetScript("OnClick", function()
        f:Hide()
    end)

    -- Hero icon + name (mirrors class icon / player name in PDW).
    local heroIcon = f:CreateTexture(nil, "ARTWORK")
    heroIcon:SetSize(40, 40)
    heroIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    heroIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.HeroIcon = heroIcon

    local heroName = f:CreateFontString(nil, "OVERLAY", "QuestFont_Large")
    heroName:SetPoint("TOPLEFT", heroIcon, "TOPRIGHT", 10, -2)
    heroName:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    heroName:SetJustifyH("LEFT")
    heroName:SetTextColor(1, 1, 1, 1)
    f.HeroName = heroName

    local heroSub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroSub:SetPoint("TOPLEFT", heroName, "BOTTOMLEFT", 0, -4)
    heroSub:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    heroSub:SetJustifyH("LEFT")
    heroSub:SetTextColor(0.85, 0.85, 0.85, 1)
    f.HeroSub = heroSub

    local stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stats:SetPoint("TOPLEFT", heroIcon, "BOTTOMLEFT", 0, -8)
    stats:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    stats:SetJustifyH("LEFT")
    stats:SetTextColor(0.75, 0.85, 1, 1)
    f.Stats = stats

    local scroll = CreateFrame("ScrollFrame", "DetailsPEProcBreakdownScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -100)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(400)
    content:SetHeight(320)
    scroll:SetScrollChild(content)
    f.Content = content
    f.Scroll = scroll

    for i = 1, BREAKDOWN_MAX_ROWS do
        breakdownRows[i] = {
            header = CreateSectionHeader(content),
            bar = CreateBreakdownBar(content, i),
        }
    end

    breakdownFrame = f
    return f
end

local function HideAllBreakdownRows()
    for i = 1, BREAKDOWN_MAX_ROWS do
        local row = breakdownRows[i]
        if row then
            row.header:Hide()
            row.bar:Hide()
        end
    end
end

local function PlaceRow(y, kind, data)
    -- Returns next y offset (negative downward).
    local slot
    for i = 1, BREAKDOWN_MAX_ROWS do
        local row = breakdownRows[i]
        if row and not row._used then
            slot = row
            slot._used = true
            break
        end
    end
    if not slot then
        return y
    end

    if kind == "header" then
        slot.header:ClearAllPoints()
        slot.header:SetPoint("TOPLEFT", breakdownFrame.Content, "TOPLEFT", 2, y)
        slot.header:SetPoint("RIGHT", breakdownFrame.Content, "RIGHT", -4, 0)
        slot.header:SetText(data.text or "")
        slot.header:Show()
        return y - BREAKDOWN_HEADER_H
    end

    local bar = slot.bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", breakdownFrame.Content, "TOPLEFT", 0, y)
    bar:SetPoint("RIGHT", breakdownFrame.Content, "RIGHT", -4, 0)

    local icon = data.icon
    if type(icon) ~= "string" or icon == "" then
        icon = Core.QUESTION_ICON
    end
    bar.Icon:SetTexture(icon)

    local rank = data.rank
    local name = data.name or "?"
    if rank then
        bar.Left:SetText(tostring(rank) .. ". " .. name)
    else
        bar.Left:SetText(name)
    end

    local amountText = FormatAmount(data.amount)
    local pct = data.percent
    if type(pct) == "number" then
        bar.Right:SetText(string.format("%s (%.1f%%)", amountText, pct))
    else
        bar.Right:SetText(amountText)
    end

    local maxAmount = data.maxAmount or data.amount or 1
    if maxAmount <= 0 then
        maxAmount = 1
    end
    local value = (data.amount or 0) / maxAmount * 100
    if value > 100 then
        value = 100
    end
    if data.rank == 1 then
        value = 100
    end
    bar.Status:SetStatusBarTexture(ResolveBarTexture())
    bar.Status:SetValue(value)
    local r, g, b, a = BarColorForIndex(data.rank or 1, data.focused)
    bar.Status:SetStatusBarColor(r, g, b, a)

    local rightW = bar.Right:GetStringWidth() or 80
    local barWidth = bar:GetWidth()
    if not barWidth or barWidth < 10 then
        barWidth = (breakdownFrame.Content:GetWidth() or 400) - 4
    end
    bar.Left:SetWidth(math.max(40, barWidth - rightW - BREAKDOWN_BAR_H - 16))

    bar:Show()
    return y - (BREAKDOWN_BAR_H + 1)
end

function Procs.OpenBreakdown(actor, instance)
    local procId, sourceId = Procs.ResolveActorPair(actor)
    local bd = Procs.GetRowBreakdown(procId, sourceId)
    if not bd then
        if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Details PE|r No proc attribution for this row yet.")
        end
        return
    end

    local f = EnsureBreakdownFrame()
    HideAllBreakdownRows()
    for i = 1, BREAKDOWN_MAX_ROWS do
        if breakdownRows[i] then
            breakdownRows[i]._used = false
        end
    end

    local procIcon = PE.GetSpellIcon and PE.GetSpellIcon(bd.procId)
    if type(procIcon) ~= "string" or procIcon == "" then
        procIcon = Core.QUESTION_ICON
    end
    f.HeroIcon:SetTexture(procIcon)
    f.HeroName:SetText(bd.procName or "Proc")
    local sourceLabel = bd.sourceName or "Unknown"
    f.HeroSub:SetText("Triggered by " .. sourceLabel)
    local hits = bd.hits or 0
    f.Stats:SetText(string.format(
        "Total %s   ·   %d hit%s   ·   avg %s",
        FormatAmount(bd.amount),
        hits,
        hits == 1 and "" or "s",
        FormatAmount(bd.average or 0)
    ))

    -- Build "Spells" list: this source first (focused), then sibling sources.
    local sourceRows = {}
    sourceRows[#sourceRows + 1] = {
        spellId = bd.sourceId,
        name = sourceLabel,
        amount = bd.amount or 0,
        hits = hits,
        focused = true,
        icon = (bd.sourceId and bd.sourceId > 0 and PE.GetSpellIcon and PE.GetSpellIcon(bd.sourceId)) or nil,
    }
    local siblings = bd.siblingSources or {}
    for i = 1, #siblings do
        local s = siblings[i]
        sourceRows[#sourceRows + 1] = {
            spellId = s.sourceId,
            name = s.sourceName or ("Spell #" .. tostring(s.sourceId or 0)),
            amount = s.amount or 0,
            hits = s.hits or 0,
            focused = false,
            icon = (s.sourceId and s.sourceId > 0 and PE.GetSpellIcon and PE.GetSpellIcon(s.sourceId)) or nil,
        }
    end

    local sourceTotal = 0
    for i = 1, #sourceRows do
        sourceTotal = sourceTotal + (sourceRows[i].amount or 0)
    end
    if sourceTotal <= 0 then
        sourceTotal = 1
    end
    local sourceMax = sourceRows[1] and sourceRows[1].amount or 1

    local y = 0
    y = PlaceRow(y, "header", { text = "Sources:" })
    for i = 1, #sourceRows do
        local row = sourceRows[i]
        y = PlaceRow(y, "bar", {
            rank = i,
            name = row.name,
            amount = row.amount,
            percent = (row.amount / sourceTotal) * 100,
            maxAmount = sourceMax,
            icon = row.icon,
            focused = row.focused,
        })
    end

    -- Targets-like panel: other procs from the same cast/aura.
    local otherProcs = bd.siblingProcs or {}
    if #otherProcs > 0 then
        y = y - 6
        y = PlaceRow(y, "header", {
            text = "Other procs from " .. sourceLabel .. ":",
        })
        local procTotal = 0
        for i = 1, #otherProcs do
            procTotal = procTotal + (otherProcs[i].amount or 0)
        end
        -- Include current proc in total so % matches "share of this source".
        procTotal = procTotal + (bd.amount or 0)
        if procTotal <= 0 then
            procTotal = 1
        end
        local procMax = otherProcs[1] and otherProcs[1].amount or 1
        if (bd.amount or 0) > procMax then
            procMax = bd.amount
        end
        for i = 1, #otherProcs do
            local p = otherProcs[i]
            local icon = PE.GetSpellIcon and PE.GetSpellIcon(p.procId)
            y = PlaceRow(y, "bar", {
                rank = i,
                name = p.procName or ("Spell #" .. tostring(p.procId or 0)),
                amount = p.amount or 0,
                percent = ((p.amount or 0) / procTotal) * 100,
                maxAmount = procMax,
                icon = icon,
                focused = false,
            })
        end
    elseif #siblings == 0 then
        y = y - 6
        y = PlaceRow(y, "header", { text = "No other attributions this combat." })
    end

    local contentH = math.max(120, -y + 8)
    f.Content:SetHeight(contentH)
    f.Content:SetWidth(f.Scroll:GetWidth() or 400)
    if f.Scroll.SetVerticalScroll then
        f.Scroll:SetVerticalScroll(0)
    end
    f:Show()
    f:Raise()
end

-- Custom Display left-click never opens AbreJanelaInfo (attribute 5 → Report).
-- Bind our handler on the PE Proc Sources custom index via row_singleclick_overwrite[5].
local function BindCustomClickHandler()
    local details = PE.GetDetails()
    if type(details) ~= "table" then
        return
    end
    details.row_singleclick_overwrite = details.row_singleclick_overwrite or {}
    if type(details.row_singleclick_overwrite[5]) ~= "table" then
        details.row_singleclick_overwrite[5] = {}
    end
    local customs = details.custom
    if type(customs) ~= "table" then
        return
    end
    for i = 1, #customs do
        local custom = customs[i]
        if type(custom) == "table" and custom.name == CUSTOM_NAME then
            details.row_singleclick_overwrite[5][i] = function(_, actor, instance)
                -- Attribute 5 normally opens the report window; open a DPS-style
                -- attribution breakdown instead (matches user expectation).
                Procs.OpenBreakdown(actor, instance)
            end
        end
    end
end

Procs.BindCustomClickHandler = BindCustomClickHandler

local function InstallCustomDisplay()
    if Db().installCustomDisplays == false then
        return
    end
    local details = PE.GetDetails()
    if type(details) ~= "table" or type(details.InstallCustomObject) ~= "function" then
        return
    end
    local object = {
        name = CUSTOM_NAME,
        icon = [[Interface\Icons\Spell_Shadow_ShadowWordDominate]],
        attribute = false,
        spellid = false,
        author = "Details PE / EbonBuilds",
        desc = "Proc / Echo secondary damage attributed to the cast that likely triggered it. Click a row for a Details-style breakdown with bars, icons, and % (Project Ebonhold).",
        source = false,
        target = false,
        script_version = CUSTOM_VERSION,
        script = [[
local combat, instance_container, instance = ...
local total, top, amount = 0, 0, 0
local pe = DetailsProjectEbonhold
if not pe or not pe.Procs or not pe.Procs.GetProcRows then
    return 0, 0, 0
end
if pe.Procs.EnsureReadableInstance then
    pe.Procs.EnsureReadableInstance(instance)
end
if pe.Procs.BindCustomClickHandler then
    pe.Procs.BindCustomClickHandler()
end
local rows = pe.Procs.GetProcRows()
for i = 1, #rows do
    local row = rows[i]
    local value = row.amount or 0
    if value > 0 then
        local procId = tonumber(row.procId)
        local sourceId = tonumber(row.sourceId) or 0
        -- Unique plain-text label (no "-", "<", "%"). Details GetOnlyName
        -- strips from the first hyphen, which mangled legacy " (<- Source)".
        local fullLabel = row.key
        if type(fullLabel) ~= "string" or fullLabel == "" then
            fullLabel = row.procName or ("Spell #" .. tostring(procId or 0))
            if type(row.sourceSuffix) == "string" and row.sourceSuffix ~= "" then
                fullLabel = fullLabel .. row.sourceSuffix
            end
        end
        -- Key by unique label (proc+source). Do NOT pass id into AddValue:
        -- GetActorTable(id) overwrites nome via GetSpellInfo and collapses
        -- same-proc / different-source rows. Attach id+icon after create.
        local actor = { nome = fullLabel, name = fullLabel }
        instance_container:AddValue(actor, value)
        local stored = instance_container:GetActorTable(actor)
        if stored then
            stored.nome = fullLabel
            stored.name = fullLabel
            stored.displayName = fullLabel
            if procId then
                stored.id = procId
                stored.peProcId = procId
            end
            stored.peSourceId = sourceId
            stored.peHits = row.hits or 0
            local icon = row.icon
            if (type(icon) ~= "string" or icon == "") and pe.GetSpellIcon and procId then
                icon = pe.GetSpellIcon(procId)
            end
            if type(icon) == "string" and icon ~= "" then
                stored.icon = icon
            end
            -- RefreshBarra prefers UNKNOW role sword over spell icons — clear it.
            if stored.classe == "UNKNOW" or stored.classe == "UNGROUPPLAYER" then
                stored.classe = nil
            end
        end
        total = total + value
        if value > top then top = value end
        amount = amount + 1
    end
end
if instance_container.GetTotalAndHighestValue then
    total, top = instance_container:GetTotalAndHighestValue()
end
if instance_container.GetNumActors then
    amount = instance_container:GetNumActors()
end
return total, top, amount
]],
        tooltip = [[
local actor, combat, instance = ...
local pe = DetailsProjectEbonhold
local Format = Details and Details.GetCurrentToKFunction and Details:GetCurrentToKFunction()
local name = actor.displayName or actor.nome or actor.name or "Proc"
GameCooltip:AddLine(name)
if actor.icon then
    GameCooltip:AddIcon(actor.icon, 1, 1, 18, 18)
elseif actor.id and pe and pe.GetSpellIcon then
    local icon = pe.GetSpellIcon(actor.id)
    if icon then
        GameCooltip:AddIcon(icon, 1, 1, 18, 18)
    end
end
local function fmt(v)
    v = tonumber(v) or 0
    if Format then
        local ok, text = pcall(Format, nil, v)
        if ok and type(text) == "string" then return text end
    end
    return tostring(math.floor(v + 0.5))
end
local procId = actor.peProcId or actor.id
local sourceId = actor.peSourceId
local bd = pe and pe.Procs and pe.Procs.GetRowBreakdown and pe.Procs.GetRowBreakdown(procId, sourceId)
if bd then
    GameCooltip:AddLine("Triggered by", bd.sourceName or "Unknown")
    Details:AddTooltipBackgroundStatusbar()
    GameCooltip:AddLine("Damage", fmt(bd.amount))
    Details:AddTooltipBackgroundStatusbar()
    GameCooltip:AddLine("Hits / avg", tostring(bd.hits or 0) .. " / " .. fmt(bd.average or 0))
    Details:AddTooltipBackgroundStatusbar()
    local siblings = bd.siblingSources or {}
    if #siblings > 0 then
        GameCooltip:AddLine("Other sources", "")
        for i = 1, math.min(5, #siblings) do
            local s = siblings[i]
            GameCooltip:AddLine("  " .. (s.sourceName or "?"), fmt(s.amount))
            Details:AddTooltipBackgroundStatusbar()
        end
    end
    local other = bd.siblingProcs or {}
    if #other > 0 then
        GameCooltip:AddLine("Other procs from source", "")
        for i = 1, math.min(5, #other) do
            local p = other[i]
            GameCooltip:AddLine("  " .. (p.procName or "?"), fmt(p.amount))
            Details:AddTooltipBackgroundStatusbar()
        end
    end
else
    GameCooltip:AddLine("Attributed to the cast/aura that likely triggered this secondary hit.")
    if actor.id and pe and pe.GetSpellName then
        GameCooltip:AddLine("Spell: " .. tostring(pe.GetSpellName(actor.id)) .. "  id " .. tostring(actor.id))
    end
end
GameCooltip:AddLine("Click: Details-style breakdown  ·  Mousewheel: scroll list")
]],
        percent_script = [[
local value, top, total = ...
total = tonumber(total) or 0
if total <= 0 then
    return "0.0"
end
return string.format("%.1f", (tonumber(value) or 0) / total * 100)
]],
    }
    pcall(details.InstallCustomObject, details, object)
    BindCustomClickHandler()
end

function Procs.Init()
    PLAYER_GUID = UnitGUID and UnitGUID("player")
    Procs.ResetCombatAttribution()
    InstallCustomDisplay()

    local f = CreateFrame("Frame")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            PLAYER_GUID = UnitGUID and UnitGUID("player")
            BindCustomClickHandler()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            Procs.ResetCombatAttribution()
            recentCasts = {}
            wipe(recentCastIds)
            return
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog(self, event, ...)
        end
    end)
end
