-- DetailsProjectEbonholdCore.lua
-- Pure helpers for Project Ebonhold Details! fine-tuning (Echo DPS labels +
-- proc source attribution). Target: WoW 3.3.5a / build 12340.
-- Safe to load in headless Lua 5.1 tests (no WoW API required).

DetailsProjectEbonholdCore = DetailsProjectEbonholdCore or {}

local Core = DetailsProjectEbonholdCore

-- PE perk / echo spell IDs live in the custom 200000–299999 band on Project
-- Ebonhold. Tomes often use 300000+. Damage procs from echoes may share the
-- perk id or a sibling custom id in the same band.
Core.PE_SPELL_ID_MIN = 200000
Core.PE_SPELL_ID_MAX = 399999

Core.PROC_ATTRIBUTION_WINDOW = 1.5 -- seconds after a cast/aura to credit a proc

function Core.IsPeCustomSpellId(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return false
    end
    return spellId >= Core.PE_SPELL_ID_MIN and spellId <= Core.PE_SPELL_ID_MAX
end

function Core.FormatEchoLabel(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return "Unknown (Echo)"
    end
    if spellName:find("%(Echo%)") then
        return spellName
    end
    return spellName .. " (Echo)"
end

function Core.FormatProcLabel(procName, sourceName)
    procName = (type(procName) == "string" and procName ~= "" and procName) or "Unknown Proc"
    if type(sourceName) ~= "string" or sourceName == "" then
        return procName .. " (Proc)"
    end
    -- Avoid nesting if already attributed (plain find; arrows are literal).
    if procName:find("(← ", 1, true) or procName:find("(Proc)", 1, true) then
        return procName
    end
    return string.format("%s (← %s)", procName, sourceName)
end

-- Decide whether a damaging spell should be treated as a "proc" relative to
-- recent player casts. A spell that was itself cast successfully is not a proc.
function Core.IsLikelyProc(spellId, recentCastIds)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 10 then
        return false -- melee / environmental
    end
    if type(recentCastIds) ~= "table" then
        return false
    end
    return recentCastIds[spellId] ~= true
end

-- Pick the most recent eligible source cast within the attribution window.
-- recentCasts: array of { spellId=, name=, t= } newest last (or any order).
-- now: current timestamp (same units as entries' t).
function Core.ResolveProcSource(recentCasts, now, window)
    window = tonumber(window) or Core.PROC_ATTRIBUTION_WINDOW
    now = tonumber(now) or 0
    if type(recentCasts) ~= "table" then
        return nil, nil
    end
    local bestId, bestName, bestT
    for i = 1, #recentCasts do
        local entry = recentCasts[i]
        if type(entry) == "table" then
            local t = tonumber(entry.t) or 0
            local age = now - t
            if age >= 0 and age <= window then
                if not bestT or t >= bestT then
                    bestT = t
                    bestId = tonumber(entry.spellId)
                    bestName = entry.name
                end
            end
        end
    end
    return bestId, bestName
end

-- Accumulate proc damage into attribution[procId][sourceId] = amount.
function Core.RecordProcDamage(attribution, procSpellId, sourceSpellId, amount)
    procSpellId = tonumber(procSpellId)
    sourceSpellId = tonumber(sourceSpellId) or 0
    amount = tonumber(amount) or 0
    if not procSpellId or amount <= 0 then
        return attribution
    end
    attribution = attribution or {}
    local bySource = attribution[procSpellId]
    if not bySource then
        bySource = {}
        attribution[procSpellId] = bySource
    end
    bySource[sourceSpellId] = (bySource[sourceSpellId] or 0) + amount
    return attribution
end

-- Flatten attribution into sorted rows for UI / Custom Display:
-- { { key=, procId=, sourceId=, amount= }, ... } descending by amount.
function Core.BuildProcRows(attribution, nameResolver)
    local rows = {}
    if type(attribution) ~= "table" then
        return rows
    end
    nameResolver = nameResolver or function(id)
        return tostring(id or 0)
    end
    for procId, bySource in pairs(attribution) do
        if type(bySource) == "table" then
            for sourceId, amount in pairs(bySource) do
                amount = tonumber(amount) or 0
                if amount > 0 then
                    local procName = nameResolver(procId)
                    local sourceName = (tonumber(sourceId) or 0) > 0 and nameResolver(sourceId) or "Unknown"
                    rows[#rows + 1] = {
                        key = Core.FormatProcLabel(procName, sourceName),
                        procId = tonumber(procId),
                        sourceId = tonumber(sourceId) or 0,
                        amount = amount,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.amount > b.amount
    end)
    return rows
end

-- Match actor spell totals to known echo spell ids / names.
-- spells: map spellId -> { total= } (Details actor.spells._ActorTable shape)
-- echoIndex: { byId = {[id]=echoName}, byName = {[lowerName]=echoName} }
function Core.MatchEchoDamage(spells, echoIndex)
    local out = {}
    if type(spells) ~= "table" or type(echoIndex) ~= "table" then
        return out
    end
    local byId = echoIndex.byId or {}
    local byName = echoIndex.byName or {}
    for spellId, spell in pairs(spells) do
        local total = type(spell) == "table" and tonumber(spell.total) or tonumber(spell)
        total = total or 0
        if total > 0 then
            local echoName = byId[tonumber(spellId)]
            if not echoName and type(spell) == "table" and type(spell.name) == "string" then
                echoName = byName[string.lower(spell.name)]
            end
            if echoName then
                out[echoName] = (out[echoName] or 0) + total
            end
        end
    end
    return out
end

function Core.BuildEchoIndex(entries)
    local byId, byName = {}, {}
    if type(entries) ~= "table" then
        return { byId = byId, byName = byName }
    end
    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" then
            local name = e.name
            local id = tonumber(e.spellId)
            if id and name then
                byId[id] = name
            end
            if type(name) == "string" and name ~= "" then
                byName[string.lower(name)] = name
            end
        end
    end
    return { byId = byId, byName = byName }
end
