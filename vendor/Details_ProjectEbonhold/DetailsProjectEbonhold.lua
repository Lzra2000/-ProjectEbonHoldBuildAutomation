-- DetailsProjectEbonhold.lua
-- Project Ebonhold fine-tune layer for Details! (Echo DPS labeling, proc
-- attribution, PE defaults). Target: WoW 3.3.5a / build 12340.
-- Requires Details! core; does not vendor the ~22 MB Details tree.

local ADDON_NAME = "Details_ProjectEbonhold"

DetailsProjectEbonhold = DetailsProjectEbonhold or {}
local PE = DetailsProjectEbonhold
local Core = DetailsProjectEbonholdCore

PE.VERSION = "1.0.11-pe1"
PE._ready = false
PE._defaultsApplied = false
local QUESTION_ICON = Core.QUESTION_ICON or [[Interface\Icons\INV_Misc_QuestionMark]]

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "not callable"
    end
    return pcall(fn, ...)
end

function PE.IsDetailsReady()
    local d = _G._detalhes or _G.Details
    return type(d) == "table"
        and type(d.GetCurrentCombat) == "function"
        and type(d.spellcache) == "table"
end

function PE.GetDetails()
    return _G._detalhes or _G.Details
end

local function EnsureDB()
    DetailsProjectEbonholdDB = DetailsProjectEbonholdDB or {}
    local db = DetailsProjectEbonholdDB
    db.defaultsApplied = db.defaultsApplied or false
    db.labelEchoes = (db.labelEchoes ~= false)
    db.trackProcs = (db.trackProcs ~= false)
    db.installCustomDisplays = (db.installCustomDisplays ~= false)
    -- spellId -> texture path; filled from GetSpellInfo + PE PerkDatabase (server sync).
    if type(db.iconCache) ~= "table" then
        db.iconCache = {}
    end
    return db
end

-- ProjectEbonhold PerkDatabase / GetPerkData is populated from the PE server API.
local function LookupPerkRecord(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end
    local peh = _G.ProjectEbonhold
    if type(peh) == "table" then
        if type(peh.GetPerkData) == "function" then
            local ok, data = pcall(peh.GetPerkData, spellId)
            if ok and type(data) == "table" then
                return data
            end
        end
        local database = peh.PerkDatabase
        if type(database) == "table" then
            local data = database[spellId] or database[tostring(spellId)]
            if type(data) == "table" then
                return data
            end
        end
    end
    local api = _G.EbonBuilds and _G.EbonBuilds.ProjectAPI
    if type(api) == "table" and type(api.GetPerkData) == "function" then
        local ok, data = pcall(api.GetPerkData, spellId)
        if ok and type(data) == "table" then
            return data
        end
    end
    return nil
end

function PE.ResolveServerSpellIcon(spellId)
    return Core.IconFromPerkData(LookupPerkRecord(spellId))
end

function PE.ResolveServerSpellName(spellId)
    return Core.NameFromPerkData(LookupPerkRecord(spellId))
end

local function CacheIcon(spellId, icon)
    if not spellId or Core.IsMissingIcon(icon) then
        return
    end
    local db = EnsureDB()
    db.iconCache[spellId] = icon
    db.iconCache[tostring(spellId)] = icon
end

-- Soft PE defaults: only flip knobs that help Echo/proc clarity and never
-- overwrite an already-applied flag (players keep their skin/layout).
-- New keys can be added in later PE versions; each is applied once so older
-- installs still pick up newly introduced soft defaults.
function PE.ApplyPeDefaults(details)
    local db = EnsureDB()
    details = details or PE.GetDetails()
    if type(details) ~= "table" then
        return false
    end
    local changed = false

    if not db.defaultsApplied then
        -- Keep related multi-hit spells merged (Stormstrike, Mutilate, etc.).
        if details.override_spellids == false then
            details.override_spellids = true
            if type(details.UpdateParserGears) == "function" then
                SafeCall(details.UpdateParserGears, details)
            end
        end
        -- Avoid empty "()" on the right text when percent is hidden (Details still
        -- wraps brackets around an empty percent string).
        if type(details.tabela_instancias) == "table" then
            for i = 1, #details.tabela_instancias do
                local inst = details.tabela_instancias[i]
                if type(inst) == "table" and type(inst.row_info) == "table"
                    and type(inst.row_info.textR_show_data) == "table" then
                    inst.row_info.textR_show_data[3] = true
                end
            end
        end
        db.defaultsApplied = true
        changed = true
    end

    -- 1.0.7-pe1: keep Overall Data across raid bosses. Stock Details clears
    -- overall on every new raid boss (overall_clear_newboss=true), which feels
    -- like "data not saving". Apply once; players who want auto-wipe can
    -- re-enable Details options → Overall → Clear On New Raid Boss
    -- (deDE: "Bei neuem Schlachtzugsboss löschen").
    if not db.defaultsOverallClearNewBoss then
        details.overall_clear_newboss = false
        db.defaultsOverallClearNewBoss = true
        changed = true
    end

    PE._defaultsApplied = db.defaultsApplied and db.defaultsOverallClearNewBoss
    return changed
end

function PE.SetSpellLabel(spellId, name, icon)
    spellId = tonumber(spellId)
    if not spellId or type(name) ~= "string" or name == "" then
        return false
    end
    local details = PE.GetDetails()
    if type(details) ~= "table" then
        return false
    end
    if type(details.UserCustomSpellAdd) == "function" then
        local ok = SafeCall(details.UserCustomSpellAdd, details, spellId, name, icon)
        if ok then
            return true
        end
    end
    -- Fallback: write SpellOverwrite + spellcache directly.
    if type(details.SpellOverwrite) == "table" then
        details.SpellOverwrite[spellId] = { name = name, icon = icon }
    end
    if type(details.spellcache) == "table" then
        rawset(details.spellcache, spellId, { name, 1, icon })
        return true
    end
    return false
end

function PE.GetSpellName(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return "Unknown"
    end
    local details = PE.GetDetails()
    if details and type(details.GetSpellInfo) == "function" then
        local ok, name = SafeCall(details.GetSpellInfo, details, spellId)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellId)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    local serverName = PE.ResolveServerSpellName(spellId)
    if serverName then
        return serverName
    end
    return "Spell #" .. tostring(spellId)
end

function PE.GetSpellIcon(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return QUESTION_ICON
    end
    local db = EnsureDB()
    local cached = db.iconCache[spellId] or db.iconCache[tostring(spellId)]
    if type(cached) == "string" and not Core.IsMissingIcon(cached) then
        return cached
    end
    if type(GetSpellInfo) == "function" then
        local _, _, icon = GetSpellInfo(spellId)
        if type(icon) == "string" and not Core.IsMissingIcon(icon) then
            CacheIcon(spellId, icon)
            return icon
        end
    end
    -- PE custom spells often lack client DBC icons — use server-synced PerkDatabase.
    local serverIcon = PE.ResolveServerSpellIcon(spellId)
    if serverIcon then
        CacheIcon(spellId, serverIcon)
        return serverIcon
    end
    return QUESTION_ICON
end

local bootFrame

local function OnDetailsReady()
    if PE._ready then
        return
    end
    if not PE.IsDetailsReady() then
        return
    end
    PE._ready = true
    local details = PE.GetDetails()
    EnsureDB()
    PE.ApplyPeDefaults(details)
    if PE.Echo and PE.Echo.Init then
        SafeCall(PE.Echo.Init)
    end
    if PE.Procs and PE.Procs.Init then
        SafeCall(PE.Procs.Init)
    end
    if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99Details PE|r fine-tune " .. PE.VERSION
                .. " — Echo labels + proc attribution ready."
        )
    end
end

local function TryBoot()
    if PE.IsDetailsReady() then
        OnDetailsReady()
        return true
    end
    return false
end

bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME or name == "Details" then
            EnsureDB()
            TryBoot()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        TryBoot()
        -- Details may finish startup slightly after login.
        if not PE._ready and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(2, TryBoot)
            C_Timer.After(8, TryBoot)
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Slash: /detailspe status | echoes | procs
SLASH_DETAILSPE1 = "/detailspe"
SlashCmdList.DETAILSPE = function(msg)
    msg = string.lower(tostring(msg or ""):match("^%s*(.-)%s*$") or "")
    local db = EnsureDB()
    if msg == "echoes" or msg == "echo" then
        db.labelEchoes = not db.labelEchoes
        print("|cff33ff99Details PE|r Echo labels:", db.labelEchoes and "ON" or "OFF")
        if PE.Echo and PE.Echo.RefreshLabels then
            SafeCall(PE.Echo.RefreshLabels)
        end
        return
    end
    if msg == "procs" or msg == "proc" then
        db.trackProcs = not db.trackProcs
        print("|cff33ff99Details PE|r Proc tracking:", db.trackProcs and "ON" or "OFF")
        return
    end
    print("|cff33ff99Details PE|r", PE.VERSION,
        "Details ready:", tostring(PE.IsDetailsReady()),
        "| Echo labels:", tostring(db.labelEchoes),
        "| Procs:", tostring(db.trackProcs))
    print("  /detailspe echoes  — toggle Echo spell labels")
    print("  /detailspe procs   — toggle proc source tracking")
end
