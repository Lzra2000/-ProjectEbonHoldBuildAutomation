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
-- Live attribution for the current Details segment (also referenced as
-- combat.pe_proc_attribution). Overall Data merges per-segment tables.
local attribution = {} -- [procId] = { [sourceId] = { amount=, hits= } }
local MAX_RECENT = 24
local ATTR_KEY = "pe_proc_attribution"
local ATTR_MERGED_KEY = "pe_proc_overall_merged"
-- Focus tint used by Details Player Details spell bars (129/125/69).
local BREAKDOWN_FOCUS_COLOR = { 129 / 255, 125 / 255, 69 / 255, 1 }

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

local function IsOverallCombat(combat, details)
    if type(combat) ~= "table" then
        return false
    end
    details = details or (PE.GetDetails and PE.GetDetails())
    if type(details) == "table" and combat == details.tabela_overall then
        return true
    end
    if type(combat.GetCombatType) == "function" and DETAILS_SEGMENTTYPE_OVERALL then
        local ok, ctype = pcall(combat.GetCombatType, combat)
        if ok and ctype == DETAILS_SEGMENTTYPE_OVERALL then
            return true
        end
    end
    return false
end

local function AttachLiveToCombat(combat)
    if type(combat) ~= "table" then
        return
    end
    combat[ATTR_KEY] = attribution
end

-- Start a fresh live map for the new Details segment and pin it on the combat.
function Procs.BeginCombatAttribution(combat)
    attribution = {}
    recentCasts = {}
    wipe(recentCastIds)
    local details = PE.GetDetails and PE.GetDetails()
    if type(combat) ~= "table" then
        -- Only auto-resolve current combat while Details is in combat —
        -- never overwrite a restored history/overall segment after /reload.
        if type(details) == "table" and details.in_combat
            and type(details.GetCurrentCombat) == "function" then
            combat = details:GetCurrentCombat()
        else
            return
        end
    end
    AttachLiveToCombat(combat)
end

-- Merge a finished segment into Details overall (once), matching Details DPS overall.
function Procs.FinalizeCombatAttribution(combat)
    if type(combat) ~= "table" then
        return
    end
    -- Ensure the ended combat keeps its own table (not the next fight's live map).
    if combat[ATTR_KEY] == attribution then
        combat[ATTR_KEY] = Core.CopyProcAttribution(attribution)
    elseif type(combat[ATTR_KEY]) ~= "table" then
        combat[ATTR_KEY] = Core.CopyProcAttribution(attribution)
    end

    if combat[ATTR_MERGED_KEY] then
        return
    end
    -- Only fold into overall when Details itself accepted the segment.
    if not combat.overall_added then
        return
    end
    local details = PE.GetDetails and PE.GetDetails()
    local overall = details and details.tabela_overall
    if type(overall) ~= "table" or overall == combat then
        return
    end
    overall[ATTR_KEY] = Core.MergeProcAttribution(overall[ATTR_KEY] or {}, combat[ATTR_KEY])
    combat[ATTR_MERGED_KEY] = true
end

-- Resolve which attribution map the Custom Display / breakdown should read.
-- Overall Data: overall.pe_proc_attribution (+ live current fight while in combat).
-- Segment / current: that combat's pe_proc_attribution (or live fallback).
function Procs.GetAttributionForCombat(combat)
    local details = PE.GetDetails and PE.GetDetails()
    if type(combat) ~= "table" then
        return attribution
    end

    if IsOverallCombat(combat, details) then
        local merged = Core.CopyProcAttribution(combat[ATTR_KEY])
        if type(details) == "table" and details.in_combat then
            local current = type(details.GetCurrentCombat) == "function" and details:GetCurrentCombat()
            if type(current) == "table" and current ~= combat and type(current[ATTR_KEY]) == "table" then
                Core.MergeProcAttribution(merged, current[ATTR_KEY])
            elseif attribution and next(attribution) then
                Core.MergeProcAttribution(merged, attribution)
            end
        end
        return merged
    end

    if type(combat[ATTR_KEY]) == "table" then
        return combat[ATTR_KEY]
    end

    if type(details) == "table" and type(details.GetCurrentCombat) == "function" then
        local current = details:GetCurrentCombat()
        if combat == current then
            AttachLiveToCombat(combat)
            return attribution
        end
    end

    return combat[ATTR_KEY] or {}
end

function Procs.ResetCombatAttribution()
    Procs.BeginCombatAttribution(nil)
end

function Procs.GetAttribution()
    return attribution
end

function Procs.GetProcRows(combat)
    local attr = Procs.GetAttributionForCombat(combat)
    return Core.BuildProcRows(attr, function(id)
        return PE.GetSpellName(id)
    end, function(id)
        return PE.GetSpellIcon(id)
    end)
end

function Procs.GetRowBreakdown(procId, sourceId, combat)
    local attr = Procs.GetAttributionForCombat(combat)
    return Core.BuildProcRowBreakdown(attr, procId, sourceId, NameResolver)
end

-- Resolve combat object from a Details instance (showing segment).
function Procs.GetInstanceCombat(instance)
    if type(instance) ~= "table" then
        return nil
    end
    if type(instance.showing) == "table" then
        return instance.showing
    end
    if type(instance.GetCombat) == "function" then
        local ok, combat = pcall(instance.GetCombat, instance)
        if ok and type(combat) == "table" then
            return combat
        end
    end
    local details = PE.GetDetails and PE.GetDetails()
    if type(details) == "table" and type(details.GetCurrentCombat) == "function" then
        return details:GetCurrentCombat()
    end
    return nil
end

-- Resolve procId/sourceId from a Details custom-bar actor table.
function Procs.ResolveActorPair(actor, combat)
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
        local rows = Procs.GetProcRows(combat)
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

local function EnsureLiveCombatAttach()
    local details = PE.GetDetails and PE.GetDetails()
    if type(details) ~= "table" or not details.in_combat then
        return
    end
    if type(details.GetCurrentCombat) ~= "function" then
        return
    end
    local combat = details:GetCurrentCombat()
    if type(combat) ~= "table" then
        return
    end
    if combat[ATTR_KEY] == attribution then
        return
    end
    if type(combat[ATTR_KEY]) == "table" then
        -- Resume the combat's store (e.g. mid-fight /reload) instead of wiping it.
        attribution = combat[ATTR_KEY]
    else
        AttachLiveToCombat(combat)
    end
end

local function OnDamage(spellId, spellName, amount)
    spellId = tonumber(spellId)
    amount = tonumber(amount) or 0
    if not spellId or amount <= 0 then
        return
    end
    EnsureLiveCombatAttach()
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
local CUSTOM_VERSION = 10
-- Soft minimum height so more proc rows are visible without scrolling immediately.
local CUSTOM_MIN_HEIGHT = 260
-- Native Player Details right-side detail blocks (Details spellInfoSettings.amount).
local RIGHT_DETAIL_SLOTS = 6
-- Offset when docking Breakdown beside the PE Proc Sources / Details instance.
local BREAKDOWN_DOCK_PAD_X = 12
-- Details Player Details! footer strip height (janela_info PLAYER_DETAILS_STATUSBAR_HEIGHT).
local PLAYER_DETAILS_STATUSBAR_HEIGHT = 20
-- Minimum bottom inset so Targets does not sit under the status strip (classic skin uses 6).
local TARGETS_MIN_BOTTOM_INSET = 6 + PLAYER_DETAILS_STATUSBAR_HEIGHT
-- Status-bar tint for secondary right-panel blocks (share / siblings).
local DETAIL_SHARE_COLOR = { 0.55, 0.65, 0.95, 0.85 }
local DETAIL_SIBLING_COLOR = { 0.75, 0.75, 0.55, 0.85 }

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
-- Click → open the real Details! Player Details Breakdown window.
-- Custom Display attribute 5 never calls AbreJanelaInfo; we reuse that frame
-- and fill Sources (spell bars) + Other procs (targets panel) ourselves so
-- chrome/skins match native DPS breakdown (no custom UIPanelScrollFrame).
---------------------------------------------------------------------------

local function HideLegacyCustomBreakdown()
    local legacy = _G.DetailsPEProcBreakdownFrame
    if type(legacy) == "table" and legacy.Hide then
        legacy:Hide()
    end
end

local function ResolveDetails(details)
    if type(details) == "table" then
        return details
    end
    if PE.GetDetails then
        details = PE.GetDetails()
        if type(details) == "table" then
            return details
        end
    end
    return _G._detalhes or _G.Details
end

local function ResolveGump(details)
    details = ResolveDetails(details)
    if type(details) == "table" and type(details.gump) == "table" then
        return details.gump, details
    end
    local fallback = _G._detalhes or _G.Details
    if type(fallback) == "table" and type(fallback.gump) == "table" then
        return fallback.gump, fallback
    end
    return nil, details
end

-- Details builds Player Details! during startup; Custom Display can be clicked
-- before that finishes. Create (or finish) the frame here so first PE click
-- never depends on opening a DPS bar first.
local function EnsurePlayerDetailsWindow(details)
    details = ResolveDetails(details)
    local info = (type(details) == "table" and details.janela_info) or _G.DetailsPlayerDetailsWindow
    if type(info) ~= "table" then
        return nil
    end

    if not info.Loaded then
        local gump, owner = ResolveGump(details)
        if type(gump) == "table" and type(gump.CriaJanelaInfo) == "function" then
            pcall(gump.CriaJanelaInfo, gump)
            if type(owner) == "table" then
                details = owner
            end
        end
        info = (type(details) == "table" and details.janela_info) or _G.DetailsPlayerDetailsWindow
    end

    if type(info) ~= "table" or not info.Loaded then
        return nil
    end

    -- Keep Details' pointer in sync (startup can briefly leave janela_info nil).
    if type(details) == "table" then
        details.janela_info = info
    end
    local root = _G._detalhes or _G.Details
    if type(root) == "table" then
        root.janela_info = info
    end

    if type(info.barras1) ~= "table" then
        info.barras1 = {}
    end
    if type(info.barras2) ~= "table" then
        info.barras2 = {}
    end
    if type(info.barras3) ~= "table" then
        info.barras3 = {}
    end
    if type(info.grupos_detalhes) ~= "table" then
        info.grupos_detalhes = {}
    end

    if type(details) == "table" and type(details.ApplyPDWSkin) == "function" then
        pcall(details.ApplyPDWSkin, details)
    end

    return info
end

Procs.EnsurePlayerDetailsWindow = EnsurePlayerDetailsWindow

local function PrewarmPlayerDetailsWindow()
    local info = EnsurePlayerDetailsWindow(PE.GetDetails and PE.GetDetails())
    return info ~= nil
end

Procs.PrewarmPlayerDetailsWindow = PrewarmPlayerDetailsWindow

local function HidePlayerDetailsTabs(details, info)
    local tabs = details and details.player_details_tabs
    if type(tabs) == "table" then
        for i = 1, #tabs do
            local tab = tabs[i]
            if type(tab) == "table" then
                if tab.Hide then
                    tab:Hide()
                end
                if type(tab.frame) == "table" then
                    -- Tab frames are HIGH strata + EnableMouse and cover Targets;
                    -- keep them inert while PE owns the Summary chrome.
                    if tab.frame.EnableMouse then
                        tab.frame:EnableMouse(false)
                    end
                    if tab.frame.Hide then
                        tab.frame:Hide()
                    end
                end
            end
        end
    end
    if type(info) == "table" and type(info.SummaryWindowWidgets) == "table"
        and info.SummaryWindowWidgets.Show then
        info.SummaryWindowWidgets:Show()
    end
end

local function HideNoTargets(info)
    if type(info) ~= "table" or type(info.no_targets) ~= "table" then
        return
    end
    if info.no_targets.Hide then
        info.no_targets:Hide()
    end
    local text = info.no_targets.text
    if type(text) == "table" then
        if text.SetText then
            text:SetText("")
        end
        if text.Hide then
            text:Hide()
        end
    end
end

-- Details creates the footer status strip as an unnamed child of janela_info
-- with a DF Label at .Text (see gumps/janela_info.lua SetStatusbarText).
local function FindPlayerDetailsStatusBar(info)
    if type(info) ~= "table" then
        return nil
    end
    if type(info._peStatusBar) == "table" then
        return info._peStatusBar
    end
    if type(info.GetNumChildren) ~= "function" or type(info.GetChildren) ~= "function" then
        return nil
    end
    local n = info:GetNumChildren()
    if type(n) ~= "number" or n < 1 then
        return nil
    end
    local children = { info:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if type(child) == "table" and child.Text ~= nil and type(child.GetHeight) == "function" then
            local ok, height = pcall(child.GetHeight, child)
            local name = (type(child.GetName) == "function" and child:GetName()) or nil
            if ok and type(height) == "number"
                and height >= (PLAYER_DETAILS_STATUSBAR_HEIGHT - 2)
                and height <= (PLAYER_DETAILS_STATUSBAR_HEIGHT + 4)
                and (name == nil or name == "") then
                info._peStatusBar = child
                return child
            end
        end
    end
    return nil
end

-- Stop stuck StartMoving captures and keep the status strip from covering
-- Targets (classic skin docks Targets at y=6 while the strip is 20px tall).
local function PreparePeBreakdownInteraction(info)
    if type(info) ~= "table" then
        return
    end

    if info.isMoving and type(info.StopMovingOrSizing) == "function" then
        pcall(info.StopMovingOrSizing, info)
        info.isMoving = false
    end

    local statusBar = FindPlayerDetailsStatusBar(info)
    if type(statusBar) == "table" then
        if statusBar.EnableMouse then
            statusBar:EnableMouse(false)
        end
        if statusBar.Hide then
            statusBar:Hide()
        end
        if statusBar.SetFrameLevel and type(info.GetFrameLevel) == "function" then
            local base = info:GetFrameLevel() or 1
            pcall(statusBar.SetFrameLevel, statusBar, math.max(1, base - 1))
        end
    end

    -- Empty Targets gump OnMouseDown calls StartMoving; if MouseUp is lost
    -- (overlap / strata), the cursor stays captured. Disable drag there in PE.
    local alvos = info.container_alvos
    local gumpFrame = alvos and alvos.gump
    if type(gumpFrame) == "table" and type(gumpFrame.SetScript) == "function"
        and not gumpFrame._peMousePatched then
        gumpFrame._peOrigOnMouseDown = gumpFrame:GetScript("OnMouseDown")
        gumpFrame._peOrigOnMouseUp = gumpFrame:GetScript("OnMouseUp")
        gumpFrame:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then
                local details = ResolveDetails()
                if type(details) == "table" and type(details.FechaJanelaInfo) == "function" then
                    pcall(details.FechaJanelaInfo, details)
                end
            end
            -- LeftButton: ignore — do not StartMoving from empty Targets area.
        end)
        gumpFrame:SetScript("OnMouseUp", function() end)
        gumpFrame._peMousePatched = true
    end

    -- Classic skin pins Targets at bottom inset 6; lift above the strip so
    -- bars are not under the (now hidden) footer / leftover font bleed.
    if type(alvos) == "table" and type(alvos.GetNumPoints) == "function"
        and type(alvos.GetPoint) == "function" and type(alvos.SetPoint) == "function" then
        local ok, nPoints = pcall(alvos.GetNumPoints, alvos)
        if ok and type(nPoints) == "number" and nPoints >= 1 then
            local ok2, point, relativeTo, relativePoint, xOfs, yOfs = pcall(alvos.GetPoint, alvos, 1)
            if ok2 and point == "BOTTOMLEFT" and type(yOfs) == "number"
                and yOfs < TARGETS_MIN_BOTTOM_INSET then
                if not alvos._peOrigPoint then
                    alvos._peOrigPoint = { point, relativeTo, relativePoint, xOfs, yOfs }
                end
                alvos:ClearAllPoints()
                alvos:SetPoint(
                    point,
                    relativeTo or info,
                    relativePoint or "BOTTOMLEFT",
                    xOfs or 20,
                    TARGETS_MIN_BOTTOM_INSET
                )
            end
        end
    end

    HideNoTargets(info)
end

-- Sibling proc rows live in barras2 (isAlvo). Stock Details only focuses
-- isMain (spell) bars — wire LeftClick → OpenBreakdown for that proc/source.
local function IsPeBarClickNotDrag(self)
    if type(self) ~= "table" then
        return true
    end
    if type(self.x) ~= "number" or type(self.y) ~= "number" then
        return true
    end
    if type(GetCursorPosition) ~= "function" then
        return true
    end
    local x, y = GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then
        return true
    end
    return math.floor(x) == self.x and math.floor(y) == self.y
end

local function BindPeSiblingProcBar(barra, procId, sourceId, instance, focused)
    if type(barra) ~= "table" then
        return
    end
    barra.peProcId = tonumber(procId)
    barra.peSourceId = tonumber(sourceId) or 0
    barra.peFocused = focused and true or false
    barra.peInstance = instance
    if barra._peProcClickBound then
        return
    end
    local function onProcClick(self, button)
        if button ~= "LeftButton" or self.peFocused or not IsPeBarClickNotDrag(self) then
            return
        end
        local details = ResolveDetails()
        local info = (type(details) == "table" and details.janela_info) or _G.DetailsPlayerDetailsWindow
        if type(info) == "table" and info.isMoving and type(info.StopMovingOrSizing) == "function" then
            pcall(info.StopMovingOrSizing, info)
            info.isMoving = false
        end
        local pid = tonumber(self.peProcId)
        local sid = tonumber(self.peSourceId) or 0
        if not pid then
            return
        end
        Procs.OpenBreakdown({
            peProcId = pid,
            peSourceId = sid,
            id = pid,
        }, self.peInstance)
    end
    if type(barra.HookScript) == "function" then
        barra:HookScript("OnMouseUp", onProcClick)
        barra._peProcClickBound = true
    elseif type(barra.SetScript) == "function" then
        local prev = barra:GetScript("OnMouseUp")
        barra:SetScript("OnMouseUp", function(self, button)
            if type(prev) == "function" then
                pcall(prev, self, button)
            end
            onProcClick(self, button)
        end)
        barra._peProcClickBound = true
    end
end

-- Sibling source rows (barras1 / isMain) already call MontaDetalhes; also allow
-- a full refocus OpenBreakdown when the player picks another source for this proc.
local function BindPeSiblingSourceBar(barra, procId, sourceId, instance, focused)
    if type(barra) ~= "table" then
        return
    end
    barra.peProcId = tonumber(procId)
    barra.peSourceId = tonumber(sourceId) or 0
    barra.peFocused = focused and true or false
    barra.peInstance = instance
    if barra._peSourceClickBound then
        return
    end
    local function onSourceClick(self, button)
        if button ~= "LeftButton" or self.peFocused or not IsPeBarClickNotDrag(self) then
            return
        end
        local pid = tonumber(self.peProcId)
        local sid = tonumber(self.peSourceId) or 0
        if not pid then
            return
        end
        Procs.OpenBreakdown({
            peProcId = pid,
            peSourceId = sid,
            id = pid,
        }, self.peInstance)
    end
    if type(barra.HookScript) == "function" then
        barra:HookScript("OnMouseUp", onSourceClick)
        barra._peSourceClickBound = true
    end
end

-- Hide empty right-side panels so PE breakdown does not leave a black void
-- where stock DPS would fill Normal/Crit/etc. hit blocks.
local function SyncRightBackgroundVisibility(info, usedCount)
    if type(info) ~= "table" then
        return
    end
    usedCount = tonumber(usedCount) or 0
    for i = 1, RIGHT_DETAIL_SLOTS do
        local bg = info["right_background" .. i]
        if type(bg) == "table" then
            if i <= usedCount then
                if bg.Show then bg:Show() end
            elseif bg.Hide then
                bg:Hide()
            end
        end
    end
end

-- Dock Breakdown beside the Details instance (PE Proc Sources) so the two
-- windows do not stack / overlap. Prefer right of the meter; flip left if
-- that would clip past the right edge of UIParent (3.3.5a has no C_UI).
local function PositionBreakdownNearInstance(info, instance)
    if type(info) ~= "table" or type(info.ClearAllPoints) ~= "function"
        or type(info.SetPoint) ~= "function" then
        return
    end
    local base = instance and instance.baseframe
    if type(base) ~= "table" then
        return
    end
    info:ClearAllPoints()
    local dockRight = true
    if type(base.GetRight) == "function" and type(info.GetWidth) == "function"
        and type(UIParent) == "table" and type(UIParent.GetRight) == "function" then
        local baseRight = base:GetRight()
        local infoW = info:GetWidth() or 890
        local parentRight = UIParent:GetRight()
        if type(baseRight) == "number" and type(parentRight) == "number"
            and (baseRight + BREAKDOWN_DOCK_PAD_X + infoW) > (parentRight - 8) then
            dockRight = false
        end
    end
    if dockRight then
        info:SetPoint("TOPLEFT", base, "TOPRIGHT", BREAKDOWN_DOCK_PAD_X, 0)
    else
        info:SetPoint("TOPRIGHT", base, "TOPLEFT", -BREAKDOWN_DOCK_PAD_X, 0)
    end
end

local function BuildSourceRows(bd)
    local sourceLabel = bd.sourceName or "Unknown"
    local rows = {}
    rows[#rows + 1] = {
        spellId = bd.sourceId or 0,
        name = sourceLabel,
        amount = bd.amount or 0,
        hits = bd.hits or 0,
        average = bd.average or 0,
        focused = true,
        icon = (bd.sourceId and bd.sourceId > 0 and PE.GetSpellIcon and PE.GetSpellIcon(bd.sourceId)) or nil,
    }
    local siblings = bd.siblingSources or {}
    for i = 1, #siblings do
        local s = siblings[i]
        local sid = s.sourceId or 0
        rows[#rows + 1] = {
            spellId = sid,
            name = s.sourceName or ("Spell #" .. tostring(sid)),
            amount = s.amount or 0,
            hits = s.hits or 0,
            average = (s.hits and s.hits > 0 and (s.amount or 0) / s.hits) or 0,
            focused = false,
            icon = (sid > 0 and PE.GetSpellIcon and PE.GetSpellIcon(sid)) or nil,
        }
    end
    return rows
end

local function FillRightPanel(details, info, sourceRow, bd)
    local gump = details.gump
    if type(gump) ~= "table" then
        return 0
    end
    if type(gump.HidaAllDetalheInfo) == "function" then
        pcall(gump.HidaAllDetalheInfo, gump)
    end
    if type(gump.SetaDetalheInfoTexto) ~= "function" then
        SyncRightBackgroundVisibility(info, 0)
        return 0
    end

    local amount = sourceRow and sourceRow.amount or bd.amount or 0
    local hits = sourceRow and sourceRow.hits or bd.hits or 0
    local average = sourceRow and sourceRow.average or bd.average or 0
    if hits > 0 and average == 0 then
        average = amount / hits
    end

    local siblings = bd.siblingSources or {}
    local otherProcs = bd.siblingProcs or {}
    local sourceTotal = amount
    for i = 1, #siblings do
        sourceTotal = sourceTotal + (siblings[i].amount or 0)
    end
    if sourceTotal <= 0 then
        sourceTotal = 1
    end
    local sharePct = (amount / sourceTotal) * 100

    -- Match native DPS detail field order (cast / damage / school / avg / dps / hits).
    local used = 0
    gump:SetaDetalheInfoTexto(
        1, 100,
        "Proc: " .. (bd.procName or "Proc"),
        "Damage: " .. FormatAmount(amount),
        string.format("%.1f%% of sources", sharePct),
        "Average: " .. FormatAmount(average),
        "Triggered by: " .. (sourceRow and sourceRow.name or bd.sourceName or "Unknown"),
        "Hits: " .. tostring(hits)
    )
    used = 1

    gump:SetaDetalheInfoTexto(
        2,
        { p = sharePct, c = DETAIL_SHARE_COLOR },
        "This source share",
        FormatAmount(amount),
        string.format("%.1f%%", sharePct),
        "All sources: " .. FormatAmount(sourceTotal),
        "Sibling sources: " .. tostring(#siblings),
        "Sibling procs: " .. tostring(#otherProcs)
    )
    used = 2

    local slot = 3
    for i = 1, #siblings do
        if slot > RIGHT_DETAIL_SLOTS then
            break
        end
        local s = siblings[i]
        local sAmount = s.amount or 0
        local sHits = s.hits or 0
        local sAvg = (sHits > 0) and (sAmount / sHits) or sAmount
        local sPct = (sAmount / sourceTotal) * 100
        gump:SetaDetalheInfoTexto(
            slot,
            { p = sPct, c = DETAIL_SIBLING_COLOR },
            "Source: " .. (s.sourceName or ("Spell #" .. tostring(s.sourceId or 0))),
            "Damage: " .. FormatAmount(sAmount),
            string.format("%.1f%%", sPct),
            "Average: " .. FormatAmount(sAvg),
            "",
            "Hits: " .. tostring(sHits)
        )
        used = slot
        slot = slot + 1
    end

    for i = 1, #otherProcs do
        if slot > RIGHT_DETAIL_SLOTS then
            break
        end
        local p = otherProcs[i]
        local pAmount = p.amount or 0
        local pHits = p.hits or 0
        local pAvg = (pHits > 0) and (pAmount / pHits) or pAmount
        gump:SetaDetalheInfoTexto(
            slot,
            { p = 100, c = DETAIL_SIBLING_COLOR },
            "Also from source: " .. (p.procName or ("Spell #" .. tostring(p.procId or 0))),
            "Damage: " .. FormatAmount(pAmount),
            "",
            "Average: " .. FormatAmount(pAvg),
            "",
            "Hits: " .. tostring(pHits)
        )
        used = slot
        slot = slot + 1
    end

    local icon = sourceRow and sourceRow.icon
    if (type(icon) ~= "string" or icon == "") and bd.procId and PE.GetSpellIcon then
        icon = PE.GetSpellIcon(bd.procId)
    end
    if type(icon) == "string" and icon ~= "" and info.spell_icone then
        info.spell_icone:SetTexture(icon)
        if info.spell_icone.SetTexCoord then
            info.spell_icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end

    SyncRightBackgroundVisibility(info, used)
    return used
end

local function FillNativeBreakdown(details, info, instance, bd, actor)
    local gump = details.gump
    if type(gump) ~= "table" then
        return false
    end

    local sourceRows = BuildSourceRows(bd)
    local sourceTotal = 0
    for i = 1, #sourceRows do
        sourceTotal = sourceTotal + (sourceRows[i].amount or 0)
    end
    if sourceTotal <= 0 then
        sourceTotal = 1
    end
    local sourceMax = sourceRows[1] and sourceRows[1].amount or 1
    if sourceMax <= 0 then
        sourceMax = 1
    end

    if type(gump.JI_AtualizaContainerBarras) == "function" then
        gump:JI_AtualizaContainerBarras(#sourceRows + 1)
    end

    local barras = info.barras1
    for i = 1, #sourceRows do
        local row = sourceRows[i]
        local barra = barras[i]
        if not barra and type(gump.CriaNovaBarraInfo1) == "function" then
            barra = gump:CriaNovaBarraInfo1(instance, i)
        end
        if barra then
            if type(details.UpdadeInfoBar) == "function" then
                details.UpdadeInfoBar(
                    actor, barra, i, row.spellId, row.name, row.amount,
                    FormatAmount(row.amount), sourceMax,
                    (row.amount / sourceTotal) * 100, row.icon, true
                )
            end
            if type(details.FocusLock) == "function" then
                details.FocusLock(actor, barra, row.spellId)
            end
            if row.focused and barra.textura then
                barra.textura:SetStatusBarColor(
                    BREAKDOWN_FOCUS_COLOR[1], BREAKDOWN_FOCUS_COLOR[2],
                    BREAKDOWN_FOCUS_COLOR[3], BREAKDOWN_FOCUS_COLOR[4]
                )
                barra.on_focus = true
                info.mostrando = barra
            end
            barra.other_actor = nil
            barra.minha_tabela = actor
            barra.show = row.spellId
            BindPeSiblingSourceBar(barra, bd.procId, row.spellId, instance, row.focused)
            barra:Show()
        end
    end

    -- Targets panel → this proc + sibling procs from the same cast/aura
    -- (include self so the panel matches stock DPS density, not an empty void).
    local siblingProcs = bd.siblingProcs or {}
    local procRows = {
        {
            procId = bd.procId,
            procName = bd.procName or "Proc",
            amount = bd.amount or 0,
            hits = bd.hits or 0,
            focused = true,
        },
    }
    for i = 1, #siblingProcs do
        local p = siblingProcs[i]
        procRows[#procRows + 1] = {
            procId = p.procId,
            procName = p.procName,
            amount = p.amount or 0,
            hits = p.hits or 0,
            focused = false,
        }
    end
    if type(gump.HidaAllBarrasAlvo) == "function" then
        gump:HidaAllBarrasAlvo()
    end
    HideNoTargets(info)

    if #procRows > 0 then
        local procTotal = 0
        local procMax = 1
        for i = 1, #procRows do
            local amount = procRows[i].amount or 0
            procTotal = procTotal + amount
            if amount > procMax then
                procMax = amount
            end
        end
        if procTotal <= 0 then
            procTotal = 1
        end
        if type(gump.JI_AtualizaContainerAlvos) == "function" then
            gump:JI_AtualizaContainerAlvos(#procRows)
        end
        local barras2 = info.barras2
        for i = 1, #procRows do
            local p = procRows[i]
            local barra = barras2[i]
            if not barra and type(gump.CriaNovaBarraInfo2) == "function" then
                barra = gump:CriaNovaBarraInfo2(instance, i)
            end
            if barra then
                local amount = p.amount or 0
                local name = p.procName or ("Spell #" .. tostring(p.procId or 0))
                local icon = PE.GetSpellIcon and PE.GetSpellIcon(p.procId)
                if barra.textura then
                    barra.textura:SetValue(amount / procMax * 100)
                    if p.focused then
                        barra.textura:SetStatusBarColor(
                            BREAKDOWN_FOCUS_COLOR[1], BREAKDOWN_FOCUS_COLOR[2],
                            BREAKDOWN_FOCUS_COLOR[3], BREAKDOWN_FOCUS_COLOR[4]
                        )
                    else
                        barra.textura:SetStatusBarColor(1, 1, 1)
                    end
                end
                if barra.texto_esquerdo then
                    barra.texto_esquerdo:SetText(tostring(i) .. ". " .. name)
                end
                if barra.texto_direita then
                    barra.texto_direita:SetText(string.format(
                        "%s (%.1f%%)", FormatAmount(amount), (amount / procTotal) * 100
                    ))
                end
                if barra.icone then
                    barra.icone:SetTexture(icon or Core.QUESTION_ICON)
                    if barra.icone.SetTexCoord then
                        barra.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    end
                end
                barra.minha_tabela = nil
                barra.show = p.procId
                BindPeSiblingProcBar(barra, p.procId, bd.sourceId, instance, p.focused)
                barra:Show()
            end
        end
        HideNoTargets(info)
    else
        HideNoTargets(info)
        if info.no_targets and info.no_targets.Show then
            -- Prefer an empty Targets list over the stock "No Targets" art
            -- mixed under PE proc rows; leave the panel blank when no siblings.
            info.no_targets:Hide()
        end
    end

    FillRightPanel(details, info, sourceRows[1], bd)
    return true
end

function Procs.OpenBreakdown(actor, instance)
    HideLegacyCustomBreakdown()

    local combat = Procs.GetInstanceCombat(instance)
    local procId, sourceId = Procs.ResolveActorPair(actor, combat)
    local bd = Procs.GetRowBreakdown(procId, sourceId, combat)
    if not bd then
        if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Details PE|r No proc attribution for this row yet.")
        end
        return
    end

    local details = ResolveDetails(PE.GetDetails and PE.GetDetails())
    local info = EnsurePlayerDetailsWindow(details)
    if not info then
        -- Last-chance create without asking the player to open a DPS bar first.
        PrewarmPlayerDetailsWindow()
        details = ResolveDetails(PE.GetDetails and PE.GetDetails())
        info = EnsurePlayerDetailsWindow(details)
    end
    if not info then
        return
    end

    if type(instance) ~= "table" then
        if type(details) == "table" and type(details.GetInstance) == "function" then
            instance = details:GetInstance(1)
        end
    end
    if type(instance) ~= "table" then
        return
    end

    local gump = details and details.gump
    local peActor = {
        nome = bd.procName or "Proc",
        name = bd.procName or "Proc",
        classe = "UNKNOW",
        peBreakdown = bd,
        detalhes = bd.sourceId,
        spells = {
            _ActorTable = {},
            PegaHabilidade = function()
                return nil
            end,
        },
        targets = {},
        total = bd.amount or 0,
        total_without_pet = bd.amount or 0,
        grupo = false,
        serial = "",
        enemy = false,
        isTank = false,
    }

    function peActor:Tempo()
        return 1
    end

    function peActor:MontaDetalhes(spellid)
        local sourceRows = BuildSourceRows(self.peBreakdown)
        local chosen = sourceRows[1]
        for i = 1, #sourceRows do
            if sourceRows[i].spellId == spellid then
                chosen = sourceRows[i]
                break
            end
        end
        FillRightPanel(details, info, chosen, self.peBreakdown)
    end

    function peActor:MontaInfo()
        FillNativeBreakdown(details, info, instance, self.peBreakdown, self)
    end

    -- Mirror AbreJanelaInfo chrome setup without going through attribute 5.
    info.ativo = true
    info.atributo = 1
    info.sub_atributo = 1
    info.jogador = peActor
    info.instancia = instance
    info.target_text = "Procs from source:"
    info.target_member = "total"
    info.target_persecond = false
    info.mostrando = nil
    info.mostrando_mouse_over = false
    info.showing = nil
    info.selectedTab = "Summary"

    if info.nome then
        info.nome:SetText(bd.procName or "Proc")
        info.nome:Show()
    end
    if info.atributo_nome then
        info.atributo_nome:SetText("Triggered by " .. (bd.sourceName or "Unknown"))
        if info.nome then
            info.atributo_nome:SetPoint("CENTER", info.nome, "CENTER", 0, 14)
        end
        info.atributo_nome:Show()
    end
    if info.avatar then info.avatar:Hide() end
    if info.avatar_bg then info.avatar_bg:Hide() end
    if info.avatar_nick then info.avatar_nick:Hide() end
    if info.avatar_attribute then info.avatar_attribute:Hide() end

    local procIcon = PE.GetSpellIcon and PE.GetSpellIcon(bd.procId)
    if type(procIcon) ~= "string" or procIcon == "" then
        procIcon = Core.QUESTION_ICON
    end
    if info.classe_icone then
        info.classe_icone:SetTexture(procIcon)
        if info.classe_icone.SetTexCoord then
            info.classe_icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    if info.classe_iconePlus and info.classe_iconePlus.SetTexture then
        info.classe_iconePlus:SetTexture()
    end

    if type(gump) == "table" then
        if type(gump.TrocaBackgroundInfo) == "function" then
            pcall(gump.TrocaBackgroundInfo, gump)
        end
        if type(gump.HidaAllBarrasInfo) == "function" then
            pcall(gump.HidaAllBarrasInfo, gump)
        end
        if type(gump.HidaAllBarrasAlvo) == "function" then
            pcall(gump.HidaAllBarrasAlvo, gump)
        end
        if type(gump.HidaAllDetalheInfo) == "function" then
            pcall(gump.HidaAllDetalheInfo, gump)
        end
        if type(gump.JI_AtualizaContainerBarras) == "function" then
            pcall(gump.JI_AtualizaContainerBarras, gump, -1)
        end
    end

    -- Keep Summary widgets visible without ShowTabs (which flashes HIGH-strata
    -- tab buttons / mouse-eating tab frames over Targets).
    HidePlayerDetailsTabs(details, info)
    if type(info.SummaryWindowWidgets) == "table" and info.SummaryWindowWidgets.Show then
        info.SummaryWindowWidgets:Show()
    end
    if info.targets then
        info.targets:SetText("Procs from source:")
    end

    PreparePeBreakdownInteraction(info)

    peActor:MontaInfo()
    -- Re-apply after MontaInfo in case TrocaBackgroundInfo / skin touched chrome.
    PreparePeBreakdownInteraction(info)
    HideNoTargets(info)
    PositionBreakdownNearInstance(info, instance)

    if type(gump) == "table" and type(gump.Fade) == "function" then
        pcall(gump.Fade, gump, info, 0)
    end
    if info.Show then
        info:Show()
    end
    if info.SetAlpha then
        info:SetAlpha(1)
    end
    info.hidden = false
    info.faded = false
    if info.Raise then
        info:Raise()
    end
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
                -- Attribute 5 normally opens the report window; open native
                -- Player Details! Breakdown filled with PE attribution instead.
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
        desc = "Proc / Echo secondary damage attributed to the cast that likely triggered it. Click a row to open the native Details! Player Details Breakdown (Project Ebonhold).",
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
-- Pass Details' selected segment (incl. Overall Data = tabela_overall).
local rows = pe.Procs.GetProcRows(combat)
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
local bd = pe and pe.Procs and pe.Procs.GetRowBreakdown and pe.Procs.GetRowBreakdown(procId, sourceId, combat)
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
GameCooltip:AddLine("Click: open Player Details! Breakdown  ·  Mousewheel: scroll list")
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
    attribution = {}
    recentCasts = {}
    wipe(recentCastIds)
    InstallCustomDisplay()
    Procs.BindDetailsCombatListener()
    -- Build Player Details! early so the first PE Proc Sources click can open it.
    PrewarmPlayerDetailsWindow()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(2, PrewarmPlayerDetailsWindow)
        C_Timer.After(8, PrewarmPlayerDetailsWindow)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            PLAYER_GUID = UnitGUID and UnitGUID("player")
            BindCustomClickHandler()
            Procs.BindDetailsCombatListener()
            PrewarmPlayerDetailsWindow()
            -- Re-attach live map if Details restored an in-progress combat after /reload.
            EnsureLiveCombatAttach()
            return
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog(self, event, ...)
        end
    end)
end

-- Details CreateEventListener: segment enter/leave + overall reset.
-- Attribution lives on combat.pe_proc_attribution so Overall / history /
-- /reload (Details SavedVariables) can show the same bars as DPS Overall.
function Procs.BindDetailsCombatListener()
    if Procs._detailsListenerBound then
        return
    end
    local details = PE.GetDetails and PE.GetDetails()
    if type(details) ~= "table" or type(details.CreateEventListener) ~= "function" then
        return
    end
    local ok, listener = pcall(details.CreateEventListener, details)
    if not ok or type(listener) ~= "table" or type(listener.RegisterEvent) ~= "function" then
        return
    end

    local function onEnter(event, combat)
        Procs.BeginCombatAttribution(combat)
    end
    local function onLeave(event, combat)
        Procs.FinalizeCombatAttribution(combat)
    end
    local function onReset()
        -- Details wiped segments / overall; drop live map only.
        attribution = {}
        recentCasts = {}
        wipe(recentCastIds)
    end

    pcall(listener.RegisterEvent, listener, "COMBAT_PLAYER_ENTER", onEnter)
    pcall(listener.RegisterEvent, listener, "COMBAT_PLAYER_LEAVE", onLeave)
    pcall(listener.RegisterEvent, listener, "DETAILS_DATA_RESET", onReset)
    Procs._detailsListenerBound = true
    Procs._detailsListener = listener
end
