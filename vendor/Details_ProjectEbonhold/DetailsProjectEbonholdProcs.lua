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
local BREAKDOWN_ROWS = 14
local BREAKDOWN_LINE_H = 16

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
-- Bump so Details InstallCustomObject replaces older scripts (click meta + hits).
local CUSTOM_VERSION = 4
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
-- Click → breakdown window (Custom Display attribute 5 never opens DPS info)
---------------------------------------------------------------------------

local breakdownFrame
local breakdownLines = {}

local function EnsureBreakdownFrame()
    if breakdownFrame then
        return breakdownFrame
    end
    local f = CreateFrame("Frame", "DetailsPEProcBreakdownFrame", UIParent)
    f:SetSize(420, 320)
    f:SetPoint("CENTER", UIParent, "CENTER", 80, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "DetailsPEProcBreakdownFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -14)
    title:SetJustifyH("LEFT")
    title:SetText("PE Proc Breakdown")
    f.Title = title

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
    subtitle:SetJustifyH("LEFT")
    f.Subtitle = subtitle

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        f:Hide()
    end)

    local scroll = CreateFrame("ScrollFrame", "DetailsPEProcBreakdownScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(360, BREAKDOWN_ROWS * BREAKDOWN_LINE_H)
    scroll:SetScrollChild(content)
    f.Content = content

    for i = 1, BREAKDOWN_ROWS do
        local left = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * BREAKDOWN_LINE_H)
        left:SetWidth(250)
        left:SetJustifyH("LEFT")
        local right = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * BREAKDOWN_LINE_H)
        right:SetWidth(100)
        right:SetJustifyH("RIGHT")
        breakdownLines[i] = { left = left, right = right }
    end

    breakdownFrame = f
    return f
end

local function SetBreakdownLine(index, leftText, rightText, isHeader)
    local line = breakdownLines[index]
    if not line then
        return
    end
    if isHeader then
        line.left:SetFontObject(GameFontNormal)
        line.left:SetTextColor(1, 0.82, 0)
    else
        line.left:SetFontObject(GameFontHighlightSmall)
        line.left:SetTextColor(1, 1, 1)
    end
    line.left:SetText(leftText or "")
    line.right:SetText(rightText or "")
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
    f.Title:SetText(bd.key or "PE Proc Breakdown")
    local hits = bd.hits or 0
    local avg = bd.average or 0
    f.Subtitle:SetText(string.format(
        "Total %s  ·  %d hit%s  ·  avg %s",
        FormatAmount(bd.amount),
        hits,
        hits == 1 and "" or "s",
        FormatAmount(avg)
    ))

    local lines = {}
    lines[#lines + 1] = {
        left = "Proc",
        right = (bd.procName or "?") .. "  id " .. tostring(bd.procId or 0),
        header = true,
    }
    lines[#lines + 1] = {
        left = "Triggered by",
        right = (bd.sourceName or "Unknown") .. (bd.sourceId and bd.sourceId > 0 and ("  id " .. tostring(bd.sourceId)) or ""),
    }
    lines[#lines + 1] = {
        left = "Attributed damage",
        right = FormatAmount(bd.amount),
    }
    lines[#lines + 1] = {
        left = "Hits / average",
        right = string.format("%d / %s", hits, FormatAmount(avg)),
    }

    local siblings = bd.siblingSources or {}
    if #siblings > 0 then
        lines[#lines + 1] = { left = "Other sources of this proc", right = "", header = true }
        for i = 1, #siblings do
            local s = siblings[i]
            lines[#lines + 1] = {
                left = "  " .. (s.sourceName or ("Spell #" .. tostring(s.sourceId or 0))),
                right = string.format("%s (%d)", FormatAmount(s.amount), s.hits or 0),
            }
        end
    end

    local otherProcs = bd.siblingProcs or {}
    if #otherProcs > 0 then
        lines[#lines + 1] = {
            left = "Other procs from " .. (bd.sourceName or "source"),
            right = "",
            header = true,
        }
        for i = 1, #otherProcs do
            local p = otherProcs[i]
            lines[#lines + 1] = {
                left = "  " .. (p.procName or ("Spell #" .. tostring(p.procId or 0))),
                right = string.format("%s (%d)", FormatAmount(p.amount), p.hits or 0),
            }
        end
    end

    if #siblings == 0 and #otherProcs == 0 then
        lines[#lines + 1] = {
            left = "No other attributions for this combat yet.",
            right = "",
        }
    end

    local shown = math.min(#lines, BREAKDOWN_ROWS)
    for i = 1, BREAKDOWN_ROWS do
        if i <= shown then
            SetBreakdownLine(i, lines[i].left, lines[i].right, lines[i].header)
        else
            SetBreakdownLine(i, "", "", false)
        end
    end
    f.Content:SetHeight(math.max(BREAKDOWN_ROWS, #lines) * BREAKDOWN_LINE_H)
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
        desc = "Proc / Echo secondary damage attributed to the cast that likely triggered it. Click a row for a DPS-style breakdown (Project Ebonhold).",
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
GameCooltip:AddLine("Click: breakdown  ·  Mousewheel: scroll list")
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
