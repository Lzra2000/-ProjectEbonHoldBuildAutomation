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

Core.QUESTION_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

function Core.IsPeCustomSpellId(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return false
    end
    return spellId >= Core.PE_SPELL_ID_MIN and spellId <= Core.PE_SPELL_ID_MAX
end

function Core.IsMissingIcon(icon)
    if type(icon) ~= "string" or icon == "" then
        return true
    end
    -- Compare case-insensitively; clients may vary slash/case.
    local lower = string.lower(icon)
    return lower == string.lower(Core.QUESTION_ICON)
        or lower:find("inv_misc_questionmark", 1, true) ~= nil
end

-- Pull icon / name fields from a ProjectEbonhold PerkDatabase row (server API sync).
function Core.IconFromPerkData(data)
    if type(data) ~= "table" then
        return nil
    end
    local icon = data.icon or data.Icon or data.iconPath or data.IconPath
    if type(icon) == "string" then
        icon = icon:match("^%s*(.-)%s*$") or icon
        if icon ~= "" and not Core.IsMissingIcon(icon) then
            return icon
        end
    end
    return nil
end

function Core.NameFromPerkData(data)
    if type(data) ~= "table" then
        return nil
    end
    local name = data.name or data.Name or data.comment or data.Comment
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$") or name
        if name ~= "" then
            return name
        end
    end
    return nil
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

-- Trim / reject empty source names so we never emit "Proc ()".
function Core.NormalizeSourceName(sourceName)
    if type(sourceName) ~= "string" then
        return nil
    end
    sourceName = sourceName:match("^%s*(.-)%s*$") or sourceName
    if sourceName == "" then
        return nil
    end
    return sourceName
end

-- Short bar suffix for Details custom rows / spell labels.
-- IMPORTANT: Details GetOnlyName() does gsub("%-.*","") (strip from first
-- hyphen) and RemoveOwnerName() strips " <.*". Never use "<-", "<", or raw
-- "%" format tokens in labels — they get mangled to "(<" / empty "()".
-- Returns "" when source is missing (never " ()").
function Core.FormatProcSourceSuffix(sourceName)
    sourceName = Core.NormalizeSourceName(sourceName)
    if not sourceName then
        return ""
    end
    return string.format(" [%s]", sourceName)
end

function Core.FormatProcLabel(procName, sourceName)
    procName = (type(procName) == "string" and procName ~= "" and procName) or "Unknown Proc"
    sourceName = Core.NormalizeSourceName(sourceName)
    if not sourceName then
        -- No empty parentheses when the cast source is unknown.
        return procName
    end
    -- Avoid nesting if already attributed (new + legacy arrow forms).
    if procName:find(" %[.-%]$") or procName:find("(<- ", 1, true)
        or procName:find("(← ", 1, true) or procName:find("(Proc)", 1, true) then
        return procName
    end
    return procName .. Core.FormatProcSourceSuffix(sourceName)
end

-- Strip prior attribution suffixes (new brackets + legacy arrow forms).
function Core.StripProcSourceSuffix(name)
    if type(name) ~= "string" or name == "" then
        return name
    end
    return name
        :gsub(" %[.-%]$", "")
        :gsub(" %(← .-%)", "")
        :gsub(" %(<%- .-%)", "")
        :gsub(" %(Proc%)", "")
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
-- { key=, procName=, sourceName=, sourceSuffix=, procId=, sourceId=, amount=, icon= }
-- nameResolver(id) -> string; iconResolver(id) -> texture path (optional).
function Core.BuildProcRows(attribution, nameResolver, iconResolver)
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
                    if type(procName) ~= "string" or procName == "" then
                        procName = "Spell #" .. tostring(procId)
                    end
                    local sourceName
                    if (tonumber(sourceId) or 0) > 0 then
                        sourceName = Core.NormalizeSourceName(nameResolver(sourceId))
                    end
                    local sourceSuffix = Core.FormatProcSourceSuffix(sourceName)
                    local icon
                    if type(iconResolver) == "function" then
                        icon = iconResolver(procId)
                    end
                    if Core.IsMissingIcon(icon) then
                        icon = Core.QUESTION_ICON
                    end
                    rows[#rows + 1] = {
                        key = Core.FormatProcLabel(procName, sourceName),
                        procName = procName,
                        sourceName = sourceName,
                        sourceSuffix = sourceSuffix,
                        procId = tonumber(procId),
                        sourceId = tonumber(sourceId) or 0,
                        amount = amount,
                        icon = icon,
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
