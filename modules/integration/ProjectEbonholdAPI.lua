local addonName, EbonBuilds = ...

-- EbonBuilds: modules/integration/ProjectEbonholdAPI.lua
-- Read-only compatibility adapter around the ProjectEbonhold globals that are
-- already exposed by the installed addon. EbonBuilds never replaces a
-- ProjectEbonhold handler and never calls onEventReceived(), because that API
-- stores one callback per event and would overwrite ProjectEbonhold's owner.
--
-- Actions use the request methods exposed by ProjectEbonhold.PerkService.
-- The unmodified addon does not expose a safe multi-listener acknowledgement
-- API, so EbonBuilds must never block later automation on inferred UI events.

EbonBuilds.ProjectAPI = {}

local API = EbonBuilds.ProjectAPI
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local initialized = false
local observationHooksInstalled = false
local choiceGeneration = 0
local showGeneration = 0
local hideGeneration = 0
local resetGeneration = 0
local replacementGeneration = 0
local requestSequence = 0

local function Service()
    return ProjectEbonhold and ProjectEbonhold.PerkService
end

local function Emit(signal, ...)
    if EbonBuilds.EventHub and EbonBuilds.EventHub.Bump then
        EbonBuilds.EventHub.Bump(signal, ...)
    end
end

local function BeginAction(action, target, invoker)
    if type(invoker) ~= "function" then return false end

    requestSequence = requestSequence + 1
    local requestId = requestSequence
    local ok, accepted = pcall(invoker)
    if not ok then
        if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
            EbonBuilds.ErrorLog.Record("ProjectAPI." .. tostring(action), accepted)
        end
        return false
    end
    if accepted == false then return false end

    -- The installed ProjectEbonhold build exposes request methods but no safe
    -- multi-listener acknowledgement API. Return local request acceptance and
    -- let its own pending flags/server handlers remain authoritative. Blocking
    -- all later automation behind inferred UI transitions caused permanent
    -- stalls when one transition was absent or reordered.
    return true, requestId, choiceGeneration
end

function API.GetPlayerClassToken()
    local _, classToken = UnitClass("player")
    return classToken and tostring(classToken):upper() or nil
end

function API.GetCurrentChoice()
    local service = Service()
    if not service or type(service.GetCurrentChoice) ~= "function" then return nil end
    local ok, result = pcall(service.GetCurrentChoice)
    return ok and type(result) == "table" and result or nil
end

function API.GetDiscoveryState()
    local service = Service()
    if not service or type(service.GetDiscoveredEchoes) ~= "function" then return nil, false end
    local ok, result = pcall(service.GetDiscoveredEchoes)
    if not ok or type(result) ~= "table" then return nil, false end
    local live = ProjectEbonhold and ProjectEbonhold.Perks
        and type(ProjectEbonhold.Perks.discoveredEchoes) == "table"
    return result, live and true or false
end

function API.GetAddonVersion()
    return tonumber(ProjectEbonhold and ProjectEbonhold.addonVersion)
end

function API.GetModVersion()
    return ProjectEbonhold and ProjectEbonhold.modVersion or nil
end

function API.GetPerkDatabase()
    return ProjectEbonhold and ProjectEbonhold.PerkDatabase or nil
end

function API.GetPerkData(spellId)
    spellId = tonumber(spellId)
    if not spellId or not ProjectEbonhold then return nil end
    if type(ProjectEbonhold.GetPerkData) == "function" then
        local ok, result = pcall(ProjectEbonhold.GetPerkData, spellId)
        if ok and type(result) == "table" then return result end
    end
    local database = ProjectEbonhold.PerkDatabase
    return database and (database[spellId] or database[tostring(spellId)]) or nil
end

function API.GetSpellDescription(spellId, maxLength, stacks)
    spellId = tonumber(spellId)
    if not spellId then return nil end
    local helper = _G.utils and _G.utils.GetSpellDescription
    if type(helper) ~= "function" then return nil end
    local ok, description = pcall(helper, spellId, tonumber(maxLength) or 500, tonumber(stacks) or 1)
    if ok and type(description) == "string" and description ~= "" then return description end
    return nil
end

function API.ClassMask(classToken)
    return CLASS_BITS[tostring(classToken or ""):upper()]
end

function API.IsPerkAvailableForClass(spellId, classToken)
    spellId = tonumber(spellId)
    if EbonBuilds.EchoEligibilityResolver and EbonBuilds.EchoCatalog then
        local state = EbonBuilds.EchoEligibilityResolver.ResolveVariant(spellId, classToken)
        return EbonBuilds.EchoEligibilityResolver.IsAvailableState(state)
    end
    local classMask = API.ClassMask(classToken)
    if not spellId or not classMask then return false end
    local data = API.GetPerkData(spellId)
    local availableMask = tonumber(data and data.classMask) or 0
    return availableMask ~= 0 and bit.band(availableMask, classMask) ~= 0
end

function API.GetTotalPerkCount()
    if ProjectEbonhold and type(ProjectEbonhold.GetTotalPerkCount) == "function" then
        local ok, result = pcall(ProjectEbonhold.GetTotalPerkCount)
        if ok then return tonumber(result) or 0 end
    end
    local count = 0
    for _ in pairs(API.GetPerkDatabase() or {}) do count = count + 1 end
    return count
end

function API.RequestEchoDiscovery()
    local service = Service()
    if not service or type(service.RequestEchoDiscovery) ~= "function" then return false end
    local ok, result = pcall(service.RequestEchoDiscovery)
    return ok and result ~= false
end

function API.IsSpellInActiveEchoLoadout(spellId)
    local service = Service()
    if not service or type(service.IsSpellInActiveEchoLoadout) ~= "function" then return false end
    local ok, result = pcall(service.IsSpellInActiveEchoLoadout, tonumber(spellId))
    return ok and result and true or false
end

function API.GetDiscoveredEchoes()
    local service = Service()
    if not service or type(service.GetDiscoveredEchoes) ~= "function" then return nil end
    local ok, result = pcall(service.GetDiscoveredEchoes)
    return ok and type(result) == "table" and result or nil
end

function API.GetActiveEchoLoadout()
    local service = Service()
    if not service or type(service.GetActiveEchoLoadout) ~= "function" then return nil end
    local ok, result = pcall(service.GetActiveEchoLoadout)
    return ok and type(result) == "table" and result or nil
end

function API.SetActiveEchoLoadout(loadout)
    local service = Service()
    if not service or type(service.SetActiveEchoLoadout) ~= "function" then return false end
    local ok, result = pcall(service.SetActiveEchoLoadout, loadout)
    return ok and result ~= false
end

function API.GetSharedEchoLoadouts()
    local service = Service()
    if not service or type(service.GetSharedEchoLoadouts) ~= "function" then return nil end
    local ok, result = pcall(service.GetSharedEchoLoadouts)
    return ok and type(result) == "table" and result or nil
end

function API.RequestSharedEchoLoadouts(classToken)
    local service = Service()
    if not service or type(service.RequestSharedEchoLoadouts) ~= "function" then return false end
    local ok, result = pcall(service.RequestSharedEchoLoadouts, tostring(classToken or ""):upper())
    return ok and result ~= false
end

------------------------------------------------------------------------
-- Server build slots (designed / verified Perk Loadouts)
-- Capability-gated wrappers around ProjectEbonhold.PerkService. Designed
-- uploads carry locked echoes only -- never weights or characterSnapshot
-- gear/talents (3.3.5a has no safe auto-equip / LearnTalent from foreign
-- snapshots).
------------------------------------------------------------------------

local function NormalizePlayerName(name)
    if not name or name == "" then return nil end
    return tostring(name):match("^([^%-]+)") or tostring(name)
end

--- Map EbonBuilds lockedEchoes (spellId slots) to UploadServerBuildSlot rows.
-- Returns echoes, skippedCount. Each echo: { spellId, stacks, locked }.
-- opts.classToken: when set, class-unusable echoes with known perk data are
-- omitted (reported in skipped). Unknown spellIds are kept for the server.
-- opts.lockAll: default true -- lockedEchoes are always marked locked on the slot.
function API.MapLockedEchoesToServerSlot(lockedEchoes, opts)
    opts = opts or {}
    local lockAll = opts.lockAll ~= false
    local classToken = opts.classToken and tostring(opts.classToken):upper() or nil
    local echoes, skipped = {}, 0
    if type(lockedEchoes) ~= "table" then return echoes, skipped end

    local slots = (EbonBuilds.Build and EbonBuilds.Build.LOCKED_SLOTS) or 6
    for i = 1, slots do
        local spellId = tonumber(lockedEchoes[i])
        if spellId then
            local skip = false
            if classToken then
                local data = API.GetPerkData(spellId)
                if data and data.classMask ~= nil then
                    if not API.IsPerkAvailableForClass(spellId, classToken) then
                        skip = true
                    end
                end
            end
            if skip then
                skipped = skipped + 1
            else
                echoes[#echoes + 1] = {
                    spellId = spellId,
                    stacks = 1,
                    locked = lockAll and true or false,
                }
            end
        end
    end
    return echoes, skipped
end

--- Map lockedEchoes to SetActiveEchoLoadout wishlist rows ({spellId, quality, stacks}).
function API.MapLockedEchoesToWishlist(lockedEchoes)
    local echoes = {}
    if type(lockedEchoes) ~= "table" then return echoes end
    local slots = (EbonBuilds.Build and EbonBuilds.Build.LOCKED_SLOTS) or 6
    local database = API.GetPerkDatabase() or {}
    for i = 1, slots do
        local spellId = tonumber(lockedEchoes[i])
        if spellId then
            local data = database[spellId] or database[tostring(spellId)]
            echoes[#echoes + 1] = {
                spellId = spellId,
                quality = data and tonumber(data.quality) or 0,
                stacks = 1,
            }
        end
    end
    return echoes
end

function API.IsAutoAcceptLoadoutEchoesEnabled()
    local optSvc = _G.ProjectEbonholdOptionsService
    if not optSvc or type(optSvc.GetSetting) ~= "function" then return false end
    local ok, result = pcall(optSvc.GetSetting, optSvc, "autoAcceptLoadoutEchoes")
    return ok and result and true or false
end

--- True when the build is not authored by the local player (imported /
-- public / remote). Used to warn before enabling wishlist/designed loadouts
-- while ProjectEbonhold auto-accept is on.
function API.IsForeignBuild(build)
    if type(build) ~= "table" then return false end
    if build.importedFrom then return true end
    local author = NormalizePlayerName(build.author)
    if not author then return false end
    local me = NormalizePlayerName(UnitName and UnitName("player"))
    if not me then return false end
    return author:lower() ~= me:lower()
end

function API.AreServerBuildSlotsEnabled()
    local service = Service()
    if not service then return false end
    if type(service.AreServerBuildSlotsEnabled) == "function" then
        local ok, result = pcall(service.AreServerBuildSlotsEnabled)
        return ok and result and true or false
    end
    -- Older addon builds: presence of Upload is the capability probe.
    return type(service.UploadServerBuildSlot) == "function"
end

function API.GetServerBuildSlots()
    local service = Service()
    if not service or type(service.GetServerBuildSlots) ~= "function" then return nil end
    local ok, result = pcall(service.GetServerBuildSlots)
    return ok and type(result) == "table" and result or nil
end

function API.RequestServerBuildSlots()
    local service = Service()
    if not service or type(service.RequestServerBuildSlots) ~= "function" then return false end
    local ok, result = pcall(service.RequestServerBuildSlots)
    return ok and result ~= false
end

function API.UploadServerBuildSlot(slot, name, echoes)
    local service = Service()
    if not service or type(service.UploadServerBuildSlot) ~= "function" then return false end
    if not API.AreServerBuildSlotsEnabled() then return false end
    slot = tonumber(slot) or 0
    if type(echoes) ~= "table" or #echoes == 0 then return false end
    local ok, result = pcall(service.UploadServerBuildSlot, slot, name, echoes)
    return ok and result ~= false
end

function API.ActivateServerBuildSlot(slot)
    local service = Service()
    if not service or type(service.ActivateServerBuildSlot) ~= "function" then return false end
    if not API.AreServerBuildSlotsEnabled() then return false end
    slot = tonumber(slot)
    if not slot or slot < 0 then return false end
    local ok, result = pcall(service.ActivateServerBuildSlot, slot)
    return ok and result ~= false
end

--- Push a build's locked echoes into the client wishlist (highlight /
-- auto-accept only). Does not touch server slots, weights, or snapshots.
-- Returns ok, errKey, info where info may include { skipped, autoAcceptWarn }.
function API.ApplyBuildAsWishlist(build)
    if type(build) ~= "table" then return false, "no_build" end
    local service = Service()
    if not service or type(service.SetActiveEchoLoadout) ~= "function" then
        return false, "unsupported"
    end
    local echoes = API.MapLockedEchoesToWishlist(build.lockedEchoes)
    if #echoes == 0 then return false, "empty" end
    local ok = API.SetActiveEchoLoadout({
        name = build.title,
        class = build.class,
        echoes = echoes,
    })
    if not ok then return false, "failed" end
    return true, nil, {
        count = #echoes,
        autoAcceptWarn = API.IsForeignBuild(build) and API.IsAutoAcceptLoadoutEchoesEnabled() or false,
    }
end

--- Upload locked echoes as a designed server build slot (slot 0 = new).
-- Weights and characterSnapshot are intentionally ignored.
-- Returns ok, errKey, info.
function API.UploadBuildAsServerSlot(build, slot)
    if type(build) ~= "table" then return false, "no_build" end
    if not API.AreServerBuildSlotsEnabled() then return false, "disabled" end
    local service = Service()
    if not service or type(service.UploadServerBuildSlot) ~= "function" then
        return false, "unsupported"
    end
    local echoes, skipped = API.MapLockedEchoesToServerSlot(build.lockedEchoes, {
        classToken = build.class,
        lockAll = true,
    })
    if #echoes == 0 then return false, "empty", { skipped = skipped } end
    local ok = API.UploadServerBuildSlot(tonumber(slot) or 0, build.title or "Loadout", echoes)
    if not ok then return false, "failed", { skipped = skipped } end
    return true, nil, {
        count = #echoes,
        skipped = skipped,
        autoAcceptWarn = API.IsForeignBuild(build) and API.IsAutoAcceptLoadoutEchoesEnabled() or false,
    }
end

-- Confirm before applying a foreign loadout while ProjectEbonhold Auto-Accept
-- is enabled. Character snapshots are never applied (no LearnTalent / equip).
local pendingForeignConfirm

local function EnsureForeignConfirmDialog()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if StaticPopupDialogs["EBONBUILDS_FOREIGN_LOADOUT_AUTOACCEPT"] then return true end
    StaticPopupDialogs["EBONBUILDS_FOREIGN_LOADOUT_AUTOACCEPT"] = {
        text = "ProjectEbonhold Auto-Accept Loadout Echoes is ON. Applying this foreign build will auto-pick matching echoes in combat. Continue?",
        button1 = "Continue",
        button2 = "Cancel",
        OnAccept = function()
            local pending = pendingForeignConfirm
            pendingForeignConfirm = nil
            if pending and pending.run then pending.run(pending.build) end
        end,
        OnCancel = function()
            pendingForeignConfirm = nil
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    return true
end

function API.WithForeignAutoAcceptConfirm(build, run)
    if type(run) ~= "function" then return end
    if API.IsForeignBuild(build) and API.IsAutoAcceptLoadoutEchoesEnabled()
        and EnsureForeignConfirmDialog() and type(StaticPopup_Show) == "function" then
        pendingForeignConfirm = { build = build, run = run }
        StaticPopup_Show("EBONBUILDS_FOREIGN_LOADOUT_AUTOACCEPT")
        return
    end
    run(build)
end

-- Resolve echo spellId from a tome itemId (PerkDatabase.requiredSpell).
-- Falls back to the documented itemId == spellId + 100000 relationship.
function API.FindEchoSpellIdByTomeItem(tomeItemId)
    tomeItemId = tonumber(tomeItemId)
    if not tomeItemId then return nil end
    local database = API.GetPerkDatabase()
    if type(database) == "table" then
        for spellId, data in pairs(database) do
            if type(data) == "table" and tonumber(data.requiredSpell) == tomeItemId then
                return tonumber(spellId)
            end
        end
        local guessed = tomeItemId - 100000
        if guessed > 0 and database[guessed] then return guessed end
    end
    return nil
end

-- True when a learned tome's echo is toggled out of the L1 draw pool.
function API.IsTomeEchoDisabled(spellId)
    local service = Service()
    if not service or type(service.IsTomeEchoDisabled) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.IsTomeEchoDisabled, spellId)
    return ok and result and true or false
end

-- Flip a learned tome on/off at level 1 (PE shows its own error if not L1).
function API.ToggleTomeEcho(spellId)
    local service = Service()
    if not service or type(service.ToggleTomeEcho) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.ToggleTomeEcho, spellId)
    return ok and result ~= false
end

-- Authoritative permanent/locked echoes for the current run (array of tables).
function API.GetLockedPerks()
    local service = Service()
    if not service or type(service.GetLockedPerks) ~= "function" then return nil end
    local ok, result = pcall(service.GetLockedPerks)
    return ok and type(result) == "table" and result or nil
end

function API.GetMaximumPermanentEchoes()
    local service = Service()
    if not service or type(service.GetMaximumPermanentEchoes) ~= "function" then return 0 end
    local ok, result = pcall(service.GetMaximumPermanentEchoes)
    if not ok then return 0 end
    return tonumber(result) or 0
end

function API.LockPerk(spellId, count)
    local service = Service()
    if not service or type(service.LockPerk) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.LockPerk, spellId, tonumber(count) or 1)
    return ok and result ~= false
end

function API.UnlockPerk(spellId)
    local service = Service()
    if not service or type(service.UnlockPerk) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.UnlockPerk, spellId)
    return ok and result ~= false
end

-- Collapse granted + locked echoes into one list (quality desc, then name).
function API.SnapshotCurrentEchoes()
    local service = Service()
    if not service or type(service.SnapshotCurrentEchoes) ~= "function" then return nil end
    local ok, result = pcall(service.SnapshotCurrentEchoes)
    return ok and type(result) == "table" and result or nil
end

-- Optimistic local discovery updates (PE journal path); no-op when absent.
function API.AddDiscoveredEcho(spellId)
    local service = Service()
    if not service or type(service.AddDiscoveredEcho) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.AddDiscoveredEcho, spellId)
    return ok and result ~= false
end

function API.RemoveDiscoveredEcho(spellId)
    local service = Service()
    if not service or type(service.RemoveDiscoveredEcho) ~= "function" then return false end
    spellId = tonumber(spellId)
    if not spellId then return false end
    local ok, result = pcall(service.RemoveDiscoveredEcho, spellId)
    return ok and result ~= false
end

function API.GetChoiceGeneration()
    return choiceGeneration
end

local BUILD_SLOT_REQUEST_TTL = 3

local function OptionsService()
    return _G.ProjectEbonholdOptionsService
end

local function PlayerRunService()
    return ProjectEbonhold and ProjectEbonhold.PlayerRunService
end

local function IsBuildSlotRequestBusy(perks)
    if type(perks) ~= "table" or perks.pendingBuildSlotRequest == nil then
        return false
    end
    -- Mirror ProjectEbonhold.PerkService's BuildSlotRequestBusy expiry so a
    -- server-throttled request cannot deadlock Autopilot forever.
    local stampedAt = tonumber(perks.pendingBuildSlotRequestAt) or 0
    if type(GetTime) == "function" then
        local now = tonumber(GetTime()) or 0
        if now - stampedAt > BUILD_SLOT_REQUEST_TTL then
            perks.pendingBuildSlotRequest = nil
            return false
        end
    end
    return true
end

function API.GetPendingAction()
    -- The server distribution of ProjectEbonhold tracks one in-flight request
    -- per action on ProjectEbonhold.Perks. Reading these flags lets EbonBuilds
    -- wait instead of issuing a duplicate request that the service would
    -- refuse (a locally refused request pauses the Autopilot).
    local perks = ProjectEbonhold and ProjectEbonhold.Perks
    if type(perks) ~= "table" then return nil end
    if perks.pendingSelectSpellId ~= nil then return "select" end
    if perks.pendingBanishIndex ~= nil then return "banish" end
    if perks.pendingFreezeIndex ~= nil then return "freeze" end
    if perks.pendingReroll then return "reroll" end
    if IsBuildSlotRequestBusy(perks) then return "slot" end
    return nil
end

function API.GetOption(key)
    local service = OptionsService()
    if not service or type(service.GetSetting) ~= "function" then return nil end
    local ok, value = pcall(service.GetSetting, service, key)
    if not ok then return nil end
    return value
end

function API.IsAutoAcceptLoadoutEchoes()
    return API.GetOption("autoAcceptLoadoutEchoes") and true or false
end

-- True when ProjectEbonhold will auto-SelectPerk a loadout echo on this board
-- (~180ms after SEND_PLAYER_PERK_CHOICE). Autopilot must defer to avoid a
-- dual-executor race that can refuse the second request and stall the run.
function API.WillAutoAcceptChoice(choices)
    if not API.IsAutoAcceptLoadoutEchoes() then return false end
    if type(choices) ~= "table" then return false end
    local service = Service()
    if not service or type(service.IsSpellInActiveEchoLoadout) ~= "function" then
        return false
    end
    for i = 1, #choices do
        local spellId = tonumber(choices[i] and choices[i].spellId)
        if spellId then
            local ok, matched = pcall(service.IsSpellInActiveEchoLoadout, spellId)
            if ok and matched then return true end
        end
    end
    return false
end

function API.GetPendingRollsCount()
    local service = Service()
    if not service or type(service.GetPendingRollsCount) ~= "function" then return nil end
    local ok, count = pcall(service.GetPendingRollsCount)
    if not ok then return nil end
    return tonumber(count)
end

-- level, picksMade, rollsLeft -- same triple ProjectEbonhold exposes for tooltips.
function API.GetRollsDebugInfo()
    local service = Service()
    if not service or type(service.GetRollsDebugInfo) ~= "function" then
        return nil, nil, nil
    end
    local ok, level, picksMade, rollsLeft = pcall(service.GetRollsDebugInfo)
    if not ok then return nil, nil, nil end
    return tonumber(level), tonumber(picksMade), tonumber(rollsLeft)
end

function API.GetRunData()
    if type(EbonholdPlayerRunData) == "table"
        and EbonholdPlayerRunData.remainingBanishes ~= nil then
        return EbonholdPlayerRunData
    end
    local service = PlayerRunService()
    if not service or type(service.GetCurrentData) ~= "function" then return nil end
    local ok, data = pcall(service.GetCurrentData)
    return ok and type(data) == "table" and data or nil
end

function API.GetIntensityData()
    local service = PlayerRunService()
    if not service or type(service.GetIntensityData) ~= "function" then
        if type(EbonholdIntensityData) == "table" then return EbonholdIntensityData end
        return nil
    end
    local ok, data = pcall(service.GetIntensityData)
    if ok and type(data) == "table" then return data end
    if type(EbonholdIntensityData) == "table" then return EbonholdIntensityData end
    return nil
end

function API.HasActionObservers()
    -- No reliable acknowledgement fan-out is exposed by the unmodified base
    -- addon. Kept only as a compatibility query for older EbonBuilds modules.
    return false
end

function API.RequestSelect(spellId)
    local service = Service()
    if not service or type(service.SelectPerk) ~= "function" then return false end
    spellId = tonumber(spellId)
    return BeginAction("select", spellId, function() return service.SelectPerk(spellId) end)
end

function API.RequestBanish(index)
    local service = Service()
    if not service or type(service.BanishPerk) ~= "function" then return false end
    index = tonumber(index)
    return BeginAction("banish", index, function() return service.BanishPerk(index) end)
end

function API.RequestFreeze(index)
    local service = Service()
    if not service or type(service.FreezePerk) ~= "function" then return false end
    index = tonumber(index)
    return BeginAction("freeze", index, function() return service.FreezePerk(index) end)
end

function API.RequestReroll()
    local service = Service()
    if not service or type(service.RequestReroll) ~= "function" then return false end
    return BeginAction("reroll", nil, function() return service.RequestReroll() end)
end

local function InstallObservationHooks()
    if observationHooksInstalled then return true end
    local ui = ProjectEbonhold and ProjectEbonhold.PerkUI
    if not ui or type(hooksecurefunc) ~= "function" then return false end

    if type(ui.Show) == "function" then
        hooksecurefunc(ui, "Show", function(choices)
            showGeneration = showGeneration + 1
            choiceGeneration = choiceGeneration + 1
            Emit("PROJECT_CHOICE_CHANGED", choiceGeneration, choices or API.GetCurrentChoice())
        end)
    end

    if type(ui.Hide) == "function" then
        hooksecurefunc(ui, "Hide", function()
            hideGeneration = hideGeneration + 1
        end)
    end

    if type(ui.ResetSelection) == "function" then
        hooksecurefunc(ui, "ResetSelection", function()
            resetGeneration = resetGeneration + 1
        end)
    end

    if type(ui.UpdateSinglePerk) == "function" then
        hooksecurefunc(ui, "UpdateSinglePerk", function()
            replacementGeneration = replacementGeneration + 1
            choiceGeneration = choiceGeneration + 1
            Emit("PROJECT_CHOICE_CHANGED", choiceGeneration, API.GetCurrentChoice())
        end)
    end

    observationHooksInstalled = true
    return true
end

function API.Init()
    if not initialized then initialized = true end
    InstallObservationHooks()
    return Service() ~= nil
end

function API.GetBoardState(context)
    local BSM = EbonBuilds.AutomationBoardStateMachine
    if not BSM then return nil end

    local perks = ProjectEbonhold and ProjectEbonhold.Perks
    if type(perks) == "table" and type(perks.GetBoardState) == "function" then
        local ok, result = pcall(perks.GetBoardState)
        if ok and type(result) == "table" and BSM.IsValidState(result.state) then
            return {
                state = result.state,
                offerId = result.offerId,
                reasonCode = result.reasonCode,
                source = "server",
            }
        end
    end
    if type(perks) == "table" and BSM.IsValidState(perks.boardState) then
        return {
            state = perks.boardState,
            offerId = perks.offerId,
            source = "server",
        }
    end

    local snapshot = type(context) == "table" and context or {}
    if snapshot.choices == nil and type(API.GetCurrentChoice) == "function" then
        snapshot.choices = API.GetCurrentChoice()
    end
    if snapshot.serverPendingAction == nil and type(API.GetPendingAction) == "function" then
        snapshot.serverPendingAction = API.GetPendingAction()
    end

    local state, reasonCode, source = BSM.Derive(snapshot)
    return {
        state = state,
        reasonCode = reasonCode,
        offerId = snapshot.offerId,
        source = source,
    }
end

function API.GetCapabilities()
    local service = Service()
    local uploadReady = service and type(service.UploadServerBuildSlot) == "function"
    local runService = PlayerRunService()
    local options = OptionsService()
    local perks = ProjectEbonhold and ProjectEbonhold.Perks
    local BSM = EbonBuilds.AutomationBoardStateMachine
    return {
        addonVersion = API.GetAddonVersion(),
        perkDatabase = API.GetPerkDatabase() ~= nil,
        perkData = ProjectEbonhold and type(ProjectEbonhold.GetPerkData) == "function" or false,
        totalPerkCount = ProjectEbonhold and type(ProjectEbonhold.GetTotalPerkCount) == "function" or false,
        descriptions = _G.utils and type(_G.utils.GetSpellDescription) == "function" or false,
        discoveredEchoes = service and type(service.GetDiscoveredEchoes) == "function" or false,
        discoveryRequest = service and type(service.RequestEchoDiscovery) == "function" or false,
        activeLoadout = service and type(service.SetActiveEchoLoadout) == "function" or false,
        sharedLoadouts = service and type(service.RequestSharedEchoLoadouts) == "function"
            and type(service.GetSharedEchoLoadouts) == "function" or false,
        serverBuildSlots = uploadReady and true or false,
        serverBuildSlotsEnabled = uploadReady and API.AreServerBuildSlotsEnabled() or false,
        uploadServerBuildSlot = uploadReady and true or false,
        activateServerBuildSlot = service and type(service.ActivateServerBuildSlot) == "function" or false,
        tomeToggle = service and type(service.ToggleTomeEcho) == "function"
            and type(service.IsTomeEchoDisabled) == "function" or false,
        lockedPerks = service and type(service.GetLockedPerks) == "function" or false,
        lockPerk = service and type(service.LockPerk) == "function" or false,
        unlockPerk = service and type(service.UnlockPerk) == "function" or false,
        maxPermanentEchoes = service and type(service.GetMaximumPermanentEchoes) == "function" or false,
        snapshotEchoes = service and type(service.SnapshotCurrentEchoes) == "function" or false,
        discoveryMutators = service and type(service.AddDiscoveredEcho) == "function"
            and type(service.RemoveDiscoveredEcho) == "function" or false,
        pendingFlags = ProjectEbonhold and type(ProjectEbonhold.Perks) == "table" or false,
        pendingBuildSlot = ProjectEbonhold and type(ProjectEbonhold.Perks) == "table" or false,
        pendingRollsCount = service and type(service.GetPendingRollsCount) == "function" or false,
        rollsDebugInfo = service and type(service.GetRollsDebugInfo) == "function" or false,
        autoAcceptLoadoutEchoes = options and type(options.GetSetting) == "function" or false,
        runData = (type(EbonholdPlayerRunData) == "table")
            or (runService and type(runService.GetCurrentData) == "function") or false,
        intensityData = (type(EbonholdIntensityData) == "table")
            or (runService and type(runService.GetIntensityData) == "function") or false,
        actionConfirmation = service and "request_only" or "unavailable",
        boardState = EbonBuilds.AutomationBoardStateMachine ~= nil,
        serverBoardState = (type(perks) == "table" and BSM and (
            type(perks.GetBoardState) == "function" or BSM.IsValidState(perks.boardState)
        )) or false,
    }
end
