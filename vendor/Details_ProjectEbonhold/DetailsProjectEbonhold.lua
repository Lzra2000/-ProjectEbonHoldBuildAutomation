-- DetailsProjectEbonhold.lua
-- Project Ebonhold fine-tune layer for Details! (Echo DPS labeling, proc
-- attribution, PE defaults). Target: WoW 3.3.5a / build 12340.
-- Requires Details! core; does not vendor the ~22 MB Details tree.

local ADDON_NAME = "Details_ProjectEbonhold"

DetailsProjectEbonhold = DetailsProjectEbonhold or {}
local PE = DetailsProjectEbonhold
local Core = DetailsProjectEbonholdCore

PE.VERSION = "1.0.0-pe1"
PE._ready = false
PE._defaultsApplied = false

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
    return db
end

-- Soft PE defaults: only flip knobs that help Echo/proc clarity and never
-- overwrite an already-applied flag (players keep their skin/layout).
function PE.ApplyPeDefaults(details)
    local db = EnsureDB()
    if db.defaultsApplied then
        return false
    end
    details = details or PE.GetDetails()
    if type(details) ~= "table" then
        return false
    end
    -- Keep related multi-hit spells merged (Stormstrike, Mutilate, etc.).
    if details.override_spellids == false then
        details.override_spellids = true
        if type(details.UpdateParserGears) == "function" then
            SafeCall(details.UpdateParserGears, details)
        end
    end
    db.defaultsApplied = true
    PE._defaultsApplied = true
    return true
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
    return "Spell #" .. tostring(spellId)
end

function PE.GetSpellIcon(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return [[Interface\Icons\INV_Misc_QuestionMark]]
    end
    if type(GetSpellInfo) == "function" then
        local _, _, icon = GetSpellInfo(spellId)
        if type(icon) == "string" and icon ~= "" then
            return icon
        end
    end
    return [[Interface\Icons\INV_Misc_QuestionMark]]
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
