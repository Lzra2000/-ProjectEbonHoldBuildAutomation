-- Regression coverage for recently reported community bug classes:
--   1. `x = x and nil or true` broken toggles (issue #39): behavioral
--      round-trip checks for the fixed sites that are testable headlessly,
--      plus source contracts for the UI closures.
--   2. Freeze/reroll priority (freeze-first automation): a board holding a
--      frozen Echo must select it (or another legal Echo) instead of
--      rerolling, including the equal-weight tie that triggered the report.
--   3. Hooks that never fire with bag-replacement addons (issue #37):
--      BagAffixDots must hook Bagnon's ItemSlot update path, both when
--      Bagnon loaded first and when it loads late, and must redraw
--      recycled/cached buttons correctly.

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

local function readFile(path)
    local file = assert(io.open(path, "rb"), "unable to read " .. path)
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

------------------------------------------------------------------------
-- 1a. Toggle round-trip: talent snapshot comparison (the third #39 site).
-- The broken pattern made `reason` always "NO_SNAPSHOT", so every build
-- claimed to have no saved talent snapshot even directly after adopting one.
------------------------------------------------------------------------
do
    local addon = {}
    assert(loadfile("modules/build/CharacterSnapshot.lua"))("EbonBuilds", addon)
    local M = addon.CharacterSnapshot

    local none = M.CompareTalents({ talents = {} }, nil)
    equal(none.comparable, false, "missing snapshot is not comparable")
    equal(none.reason, "NO_SNAPSHOT", "missing snapshot reports NO_SNAPSHOT")

    local stored = {
        classToken = "MAGE",
        talents = { [1] = { talents = { { index = 1, tier = 1, column = 1, rank = 2, maxRank = 3 } } } },
    }
    local current = {
        classToken = "MAGE",
        talents = { [1] = { talents = { { index = 1, tier = 1, column = 1, rank = 2, maxRank = 3 } } } },
    }
    local same = M.CompareTalents(current, stored)
    equal(same.comparable, true, "present snapshot is comparable")
    equal(same.reason, nil, "present snapshot must NOT report NO_SNAPSHOT (issue #39 regression)")
    equal(same.requiredRanks, 2, "required ranks counted from the snapshot")
    equal(same.matchedRanks, 2, "identical trees match every rank")
    equal(same.missingRanks, 0, "identical trees miss nothing")
    equal(same.exactTalentCount, 1, "identical skilled talent counts as exact")
    equal(same.matchPercent, 100, "identical trees are a 100% match")

    -- Round-trip the comparison itself: nil -> table -> nil must flip the
    -- reason both ways (the broken pattern only ever flipped it one way).
    local again = M.CompareTalents(current, nil)
    equal(again.reason, "NO_SNAPSHOT", "reason returns after the snapshot is removed")

    local mismatch = M.CompareTalents({ classToken = "PRIEST", talents = {} }, stored)
    equal(mismatch.comparable, false, "cross-class snapshot is not comparable")
    equal(mismatch.reason, "CLASS_MISMATCH", "cross-class snapshot reports CLASS_MISMATCH")
end

------------------------------------------------------------------------
-- 1b. Toggle round-trip semantics on a plain settings table, mirroring the
-- fixed family-protection toggle: on -> off -> on must land on ON, and the
-- OFF state must remove the key entirely (SavedVariables stay compact).
------------------------------------------------------------------------
do
    -- The exact branch shape the fixed UI closures use.
    local function Toggle(set, key)
        if set[key] then set[key] = nil else set[key] = true end
    end
    local protected = {}
    Toggle(protected, "Caster")
    equal(protected.Caster, true, "first toggle turns protection ON")
    Toggle(protected, "Caster")
    equal(protected.Caster, nil, "second toggle turns protection OFF (issue #39 regression)")
    Toggle(protected, "Caster")
    equal(protected.Caster, true, "third toggle turns protection ON again")

    -- Source contracts for the two UI closures that cannot run headlessly:
    -- the broken expression must not return, and the explicit branch must.
    for _, definition in ipairs({
        { "modules/ui/SettingsView.lua", "family protection toggle" },
        { "modules/ui/Filters.lua", "Echo table family filter" },
    }) do
        local source = readFile(definition[1])
        check(not source:find("=%s*[%w_.%[%]]+%s+and%s+nil%s+or%s+true"),
            definition[2] .. " must not use the always-true `and nil or true` toggle")
    end
end

------------------------------------------------------------------------
-- 2. Freeze priority: a frozen Echo must be taken, never rerolled past.
------------------------------------------------------------------------
do
    local addon = {}
    assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
    local D = addon.AutomationBoardDecision

    local function Slot(id, score, flags)
        local slot = { spellId = id, name = "Echo " .. tostring(id), score = score, isValid = true }
        for key, value in pairs(flags or {}) do slot[key] = value end
        return slot
    end
    local function Board(slots, options)
        local board = {
            slots = slots, isValid = true, isStable = true,
            maxFrozen = 2, freezeThreshold = 120, freezeResources = 2,
            canReroll = true, canBanish = false,
            frozenThisBoardBySlot = {}, frozenThisBoardEchoIDs = {},
        }
        for key, value in pairs(options or {}) do board[key] = value end
        for i, slot in ipairs(slots) do
            slot.index = i
            if slot.frozenThisBoard then
                board.frozenThisBoardBySlot[i] = true
                board.frozenThisBoardEchoIDs[slot.spellId] = true
            end
        end
        D.RefreshFrozenState(board)
        return board
    end

    -- The reported shape: two Echoes at the same weight, one already frozen,
    -- and the current offer otherwise weak enough that classic logic wanted
    -- to reroll. The frozen board must SELECT, never REROLL.
    local tie = Board({
        Slot(101, 150, { isFrozen = true }), Slot(102, 150),
    }, { pickIsAcceptable = false, freezeResources = 0 })
    local allowed, reason = D.CanReroll(tie)
    equal(allowed, false, "reroll is illegal while an equal-weight frozen Echo exists")
    check(tostring(reason):find("frozen", 1, true), "reroll refusal names the frozen Echo")
    local tieDecision = D.Decide(tie)
    equal(tieDecision.action, "SELECT", "equal-weight frozen board selects instead of rerolling")
    equal(tieDecision.target.index, 1, "equal scores resolve deterministically left-to-right")

    -- Same tie with the frozen Echo in the second slot: still SELECT, and the
    -- deterministic tiebreak may prefer slot 1, but the action can never
    -- become a reroll loop.
    local tieSecond = Board({
        Slot(201, 150), Slot(202, 150, { isFrozen = true }),
    }, { pickIsAcceptable = false, freezeResources = 0 })
    equal(D.Decide(tieSecond).action, "SELECT", "frozen-in-slot-2 tie also selects")
    equal(D.CanReroll(tieSecond), false, "frozen-in-slot-2 tie blocks reroll")

    -- Directly after this board froze an Echo (confirmed this turn), the
    -- remaining weak offer must not trigger a reroll: the freeze consumed the
    -- board's reroll legality.
    local justFroze = Board({
        Slot(301, 150, { isFrozen = true, frozenThisBoard = true }),
        Slot(302, 150), Slot(303, 20),
    }, { pickIsAcceptable = false, freezeResources = 1 })
    local afterFreeze = D.Decide(justFroze)
    equal(afterFreeze.action, "SELECT", "board that just froze selects instead of rerolling")
    equal(afterFreeze.target.index, 2, "the Echo frozen this turn is withheld; the twin is selected")
    equal(D.CanReroll(justFroze), false, "board that just froze cannot reroll")

    -- A carried frozen Echo from the previous board wins an exact tie with a
    -- fresh Echo deterministically (left-to-right), and is a legal pick.
    local carriedTie = Board({
        Slot(401, 90, { isFrozen = true, isCarried = true }), Slot(402, 90), Slot(403, 10),
    }, { freezeResources = 0 })
    local carried = D.Decide(carriedTie)
    equal(carried.action, "SELECT", "carried frozen Echo board selects")
    equal(carried.target.index, 1, "carried frozen Echo wins the equal-weight tie by position")

    -- Repeated evaluation of the same frozen board must be stable: never a
    -- reroll on any iteration (the reported bug was a reroll LOOP).
    for iteration = 1, 25 do
        local repeated = Board({
            Slot(501, 150, { isFrozen = true }), Slot(502, 150),
        }, { pickIsAcceptable = false, freezeResources = 0 })
        local decision = D.Decide(repeated)
        check(decision.action ~= "REROLL",
            "iteration " .. iteration .. " must not reroll a frozen board")
        equal(decision.action, "SELECT", "iteration " .. iteration .. " selects deterministically")
    end
end

------------------------------------------------------------------------
-- 3. Bag-replacement addon hooks (issue #37): Bagnon buttons get dots.
------------------------------------------------------------------------
do
    -- Fresh sandboxed global surface for this module.
    local addon = {}
    EbonBuildsCharDB = {}

    local containerLinks = {}   -- [bag][slot] = link
    function GetContainerItemLink(bag, slot)
        return containerLinks[bag] and containerLinks[bag][slot] or nil
    end
    function GetContainerItemInfo() return nil, nil, nil end
    function GetItemInfo() return nil end
    function GetInventoryItemLink() return nil end
    function IsAddOnLoaded(name) return _G.__loadedAddons and _G.__loadedAddons[name] or false end
    function ContainerFrame_Update() end

    -- hooksecurefunc stub that really wraps, covering both signatures.
    function hooksecurefunc(target, name, hook)
        if type(target) == "string" then
            target, name, hook = _G, target, name
        end
        local original = target[name]
        target[name] = function(...)
            original(...)
            hook(...)
        end
    end

    -- WoWEvents stub with working On/Off so the late-load listener can
    -- actually unregister itself.
    local wowListeners = {}
    addon.WoWEvents = {
        On = function(event, fn)
            local token = { event = event, fn = fn }
            wowListeners[#wowListeners + 1] = token
            return token
        end,
        Off = function(token)
            for i = #wowListeners, 1, -1 do
                if wowListeners[i] == token then table.remove(wowListeners, i) end
            end
        end,
        Emit = function(event, ...)
            for _, token in ipairs({ unpack(wowListeners) }) do
                if token.event == event then token.fn(event, ...) end
            end
        end,
    }

    local classifyResults = {}
    addon.AffixItemScan = {
        Classify = function(name) return classifyResults[name] end,
    }

    assert(loadfile("modules/ui/BagAffixDots.lua"))("EbonBuilds", addon)

    local function NewTexture()
        local tex = { shown = false }
        function tex:SetTexture() end
        function tex:SetSize() end
        function tex:ClearAllPoints() end
        function tex:SetPoint() end
        function tex:SetVertexColor(r, g, b) self.color = { r, g, b } end
        function tex:Show() self.shown = true end
        function tex:Hide() self.shown = false end
        return tex
    end
    local function NewBagnonButton(bag, slot)
        local button = { _bag = bag, _slot = slot, _visible = true }
        function button:IsVisible() return self._visible end
        function button:GetID() return self._slot end
        function button:GetBag() return self._bag end
        function button:GetParent()
            local owner = self
            return { GetID = function() return owner._bag end }
        end
        function button:CreateTexture() return NewTexture() end
        return button
    end

    -- Scenario A: Bagnon loads AFTER EbonBuilds (the case the original hook
    -- missed entirely -- ContainerFrame_Update never fires for Bagnon).
    _G.__loadedAddons = {}
    addon.BagAffixDots.Init()
    check(_G.Bagnon == nil, "precondition: Bagnon not yet loaded")

    _G.Bagnon = { ItemSlot = { Update = function() end } }
    local originalUpdate = _G.Bagnon.ItemSlot.Update
    addon.WoWEvents.Emit("ADDON_LOADED", "Bagnon")
    check(_G.Bagnon.ItemSlot.Update ~= originalUpdate,
        "late Bagnon load hooks ItemSlot.Update via ADDON_LOADED")
    equal(#wowListeners, 0,
        "BagAffixDots ADDON_LOADED late-load listener must call WoWEvents.Off(token) after a successful bag-addon hook (expected 0 listeners). Do not use frame:RegisterEvent; keep the one-shot via core/WoWEvents.lua. If multiple bag addons are pending (Bagnon/Combuctor), Off after the successful hook — they are mutually exclusive in practice.")

    -- A visible Bagnon button showing an affix item receives a dot even
    -- though no default ContainerFrame ever updates.
    containerLinks[0] = { [1] = "|cff1eff00|Hitem:1:0|h[Affix Item]|h|r" }
    classifyResults["Affix Item"] = "missing_new"
    local button = NewBagnonButton(0, 1)
    _G.Bagnon.ItemSlot.Update(button)
    check(button._ebbAffixDot and button._ebbAffixDot.shown,
        "Bagnon button shows a dot after its Update fires (issue #37 regression)")
    equal(button._ebbAffixDot.color[1], 0.90, "unlearned affix uses the red dot")

    -- Button recycling: Bagnon reuses the same button for another slot; the
    -- change cache must key on bag/slot, not just the link.
    containerLinks[0][2] = "|cff1eff00|Hitem:2:0|h[Plain Item]|h|r"
    classifyResults["Plain Item"] = nil
    button._slot = 2
    _G.Bagnon.ItemSlot.Update(button)
    equal(button._ebbAffixDot.shown, false, "recycled button for a plain item clears its dot")

    button._slot = 1
    _G.Bagnon.ItemSlot.Update(button)
    equal(button._ebbAffixDot.shown, true, "recycling back to the affix slot redraws the dot")

    -- Cached (offline/bank) buttons must never show live-bag conclusions.
    local cachedButton = NewBagnonButton(0, 1)
    cachedButton.IsCached = function() return true end
    _G.Bagnon.ItemSlot.Update(cachedButton)
    check(not (cachedButton._ebbAffixDot and cachedButton._ebbAffixDot.shown),
        "cached Bagnon button shows no dot")

    -- Hidden buttons are skipped entirely (mirrors Bagnon's own
    -- short-circuit; hooksecurefunc fires regardless).
    local hiddenButton = NewBagnonButton(0, 1)
    hiddenButton._visible = false
    _G.Bagnon.ItemSlot.Update(hiddenButton)
    check(hiddenButton._ebbAffixDot == nil, "hidden Bagnon button is not touched")

    -- RefreshAll must reach registered Bagnon buttons: after the learned
    -- state changes, the same link produces a different dot without any
    -- Bagnon-side update event.
    classifyResults["Affix Item"] = "missing_upgrade"
    addon.BagAffixDots.RefreshAll()
    equal(button._ebbAffixDot.color[2], 0.21, "RefreshAll recolors Bagnon dots (purple upgrade)")

    -- Disabling the feature hides existing dots on the next refresh.
    addon.BagAffixDots.SetEnabled(false)
    equal(button._ebbAffixDot.shown, false, "disabling the feature hides Bagnon dots")
    equal(EbonBuildsCharDB.bagAffixDotsEnabled, false, "disabled state persists to the char DB")
    addon.BagAffixDots.SetEnabled(true)
    equal(button._ebbAffixDot.shown, true, "re-enabling restores Bagnon dots")

    -- Scenario B: a fork exposing `Bagnon.Item` instead of `Bagnon.ItemSlot`
    -- is detected by the same feature probe when Bagnon precedes Init.
    local forkAddon = { WoWEvents = addon.WoWEvents, AffixItemScan = addon.AffixItemScan }
    _G.Bagnon = { Item = { Update = function() end } }
    _G.__loadedAddons = { Bagnon = true }
    assert(loadfile("modules/ui/BagAffixDots.lua"))("EbonBuilds", forkAddon)
    local forkOriginal = _G.Bagnon.Item.Update
    forkAddon.BagAffixDots.Init()
    check(_G.Bagnon.Item.Update ~= forkOriginal,
        "Bagnon fork exposing .Item is hooked when already loaded at Init")

    _G.Bagnon = nil
    _G.__loadedAddons = nil
end

------------------------------------------------------------------------
-- 4. v3.84 map zone panel: toggling with world map open must not call a
-- nil global RefreshMapPanel (forward-decl regression).
------------------------------------------------------------------------
do
    local world = readFile("modules/ui/WorldIntegration.lua")
    check(world:find("local RefreshMapPanel[%s,\n]") ~= nil,
        "WorldIntegration must forward-declare local RefreshMapPanel")
    check(world:find("function RefreshMapPanel%(") ~= nil,
        "WorldIntegration must assign function RefreshMapPanel()")

    local function stubMapFrame()
        return {
            shown = true,
            SetFrameStrata = function() end, SetSize = function() end, SetPoint = function() end,
            ClearAllPoints = function() end, Hide = function() end, Show = function() end,
            SetHeight = function() end, SetScript = function() end, HookScript = function() end,
            IsShown = function(self) return self.shown end,
            GetWidth = function() return 512 end, GetHeight = function() return 512 end,
            CreateFontString = function()
                return {
                    SetPoint = function() end, SetText = function() end,
                    SetTextColor = function() end, SetJustifyH = function() end, SetWidth = function() end,
                }
            end,
            CreateTexture = function()
                return {
                    SetTexture = function() end, SetTexCoord = function() end,
                    SetWidth = function() end, SetHeight = function() end,
                    ClearAllPoints = function() end, SetPoint = function() end,
                    SetVertexColor = function() end, SetBlendMode = function() end,
                    SetDrawLayer = function() end, Show = function() end, Hide = function() end,
                }
            end,
        }
    end

    WorldMapFrame = stubMapFrame()
    WorldMapDetailFrame = stubMapFrame()
    WorldMapButton = stubMapFrame()
    GameTooltip = { Hide = function() end, SetOwner = function() end, SetText = function() end,
        Show = function() end, IsOwned = function() return false end }
    CreateFrame = function() return stubMapFrame() end
    GetCurrentMapContinent = function() return 0 end
    GetCurrentMapZone = function() return 0 end
    GetMapZones = function() return "Test Zone" end
    GetZoneText = function() return "Test Zone" end
    UpdateMapHighlight = function() return nil end
    IsAddOnLoaded = function() return false end
    EbonBuildsDB = { globalSettings = { tomeAtlasMapEnabled = true } }
    EbonBuildsCharDB = { mapZonePanelEnabled = true }

    local addon = {
        Theme = {
            ACCENT_GOLD = { 1, 0.8, 0 }, TEXT_PRIMARY = { 1, 1, 1 },
            PRESENCE_TEAL = { 0, 1, 1 }, PRESENCE_TEAL_HEX = "00ffff",
            ApplyPanel = function() end, AddHeaderRule = function() end,
            CreateCloseButton = function() return { SetScript = function() end, Hide = function() end } end,
            CreateCheckbox = function()
                return {
                    ClearAllPoints = function() end, SetPoint = function() end,
                    SetChecked = function() end, SetScript = function() end,
                    Show = function() end, Hide = function() end, GetChecked = function() return true end,
                    _labelFS = { SetText = function() end },
                }
            end,
        },
        TomeAtlas = { ListByZone = function() return {} end },
        Database = {
            GetCharacterPreference = function(key) return EbonBuildsCharDB[key] ~= false end,
            SetCharacterPreference = function(key, value) EbonBuildsCharDB[key] = value end,
        },
        Debug = { RegisterTest = function() end },
        WoWEvents = { On = function() end },
    }

    assert(loadfile("modules/ui/WorldIntegration.lua"))("EbonBuilds", addon)
    local ok, err = pcall(function()
        addon.WorldIntegration.SetMapPanelEnabled(true)
    end)
    check(ok, "SetMapPanelEnabled(true) with world map open must not crash (v3.84 RefreshMapPanel nil global)"
        .. (ok and "" or (" — " .. tostring(err))))
end

if failures > 0 then
    io.stderr:write(string.format("%d bug-class regression test(s) failed.\n", failures))
    os.exit(1)
end
print("Bug-class regressions passed: toggle round-trips, freeze-over-reroll priority, Bagnon hook compatibility, and v3.84 map panel toggle.")
