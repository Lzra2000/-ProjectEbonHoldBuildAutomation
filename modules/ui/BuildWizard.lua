-- EbonBuilds: modules/ui/BuildWizard.lua
-- Confidence-aware, player-owned Build Wizard. Uses pooled rows, the shared
-- Echo catalog, the unified theme, and bounded community recommendation data.

EbonBuilds.BuildWizard = {}

local Wizard = EbonBuilds.BuildWizard
local Theme = EbonBuilds.Theme
local Draft = EbonBuilds.WizardDraft
local Evidence = EbonBuilds.BuildWizardEvidence
local Summary = EbonBuilds.BuildWizardSummary

local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_LABEL = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local FAMILY_VALUES = { "None", "Auto", "Caster", "Melee", "Ranged", "Healer", "Tank", "Survivability" }
local SECONDARY_VALUES = { "None", "Caster", "Melee", "Ranged", "Healer", "Tank", "Survivability" }
local viewFrame, contentArea, stepLabel, statusStrip, statusText, confidencePill
local backBtn, nextBtn, alternateBtn, cancelBtn
local stepFrames = {}
local state = {}
local sessionGeneration = 0
local classButtons, specButtons, intentButtons = {}, {}, {}
local locksUI, prioritiesUI, scoringUI, reviewUI
local RenderCurrentStep, RefreshLocks, RefreshPriorities, RefreshScoring, RefreshReview

local function MakeText(parent, font, width, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if width then text:SetWidth(width) end
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function MakePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    Theme.ApplyCard(panel)
    return panel
end

local function VisibleName(name)
    return EbonBuilds.Weights.VisibleName and EbonBuilds.Weights.VisibleName(name) or tostring(name or "")
end

local function CurrentSpecName()
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[state.class]
    return specs and specs[state.spec] and specs[state.spec].name or ("Spec " .. tostring(state.spec or 1))
end

local function SetClassIcon(texture, classToken)
    texture:SetTexture(CLASS_TEXTURE)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if coords then texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

local function EchoInfo(nameOrRef, preferredId)
    if not EbonBuilds.EchoCatalog then return tonumber(preferredId), 0, nil, nil end
    if tostring(nameOrRef or ""):match("^[gs]:%d+$") then
        return EbonBuilds.EchoCatalog.GetBestByRef(nameOrRef, state.class, preferredId)
    end
    return EbonBuilds.EchoCatalog.GetBest(nameOrRef, state.class, preferredId)
end

local function SetEchoIcon(texture, name, preferredId)
    local spellId, quality = EchoInfo(name, preferredId)
    texture:SetTexture((spellId and select(3, GetSpellInfo(spellId))) or QUESTION_ICON)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return tonumber(quality) or 0, spellId
end

local function SetPill(pill, text, kind)
    if not pill then return end
    pill.label:SetText(text or "")
    local c = kind == "success" and Theme.SUCCESS or kind == "warning" and Theme.WARNING
        or kind == "danger" and Theme.DANGER or Theme.BORDER
    pill:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.98)
    pill:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
    pill.label:SetTextColor(c[1], c[2], c[3], 1)
end

local function SnapshotRef(item)
    if not item then return nil end
    if item.refKey then return item.refKey end
    local preferredId = tonumber(item.lockedSpellId or item.spellId)
    if preferredId and EbonBuilds.EchoProjection then
        local entry = EbonBuilds.EchoProjection.ResolveSpell(state.class, preferredId)
        if entry then return entry.refKey end
    end
    local _, _, definition = EbonBuilds.EchoCatalog.GetBest(item.name, state.class, preferredId)
    return definition and definition.refKey or nil
end

local function IndexSnapshot(snapshot)
    state.snapshotByRef = {}
    local function Add(list, kind)
        for _, item in ipairs(list or {}) do
            local refKey = SnapshotRef(item)
            if refKey and not state.snapshotByRef[refKey] then
                state.snapshotByRef[refKey] = { item = item, kind = kind }
            end
        end
    end
    Add(snapshot and snapshot.locked, "lock")
    Add(snapshot and snapshot.priorities, "priority")
    Add(snapshot and (snapshot.defensiveAssociated or snapshot.optionalSurvivability), "defensive")
    Add(snapshot and snapshot.avoid, "avoid")
end

local function SnapshotItem(refKey)
    local found = state.snapshotByRef and state.snapshotByRef[refKey]
    return found and found.item or nil, found and found.kind or "none"
end

local function ShowEchoTooltip(owner, name, preferredId, item, sourceKind)
    local spellId = select(1, EchoInfo(name, preferredId))
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local usedNative = false
    if spellId and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(spellId))
        local count = GameTooltip.NumLines and GameTooltip:NumLines()
        usedNative = ok and (count == nil or count > 0)
    end
    if not usedNative then
        GameTooltip:ClearLines()
        GameTooltip:AddLine((spellId and GetSpellInfo(spellId)) or VisibleName(name) or "Echo", 1, 0.82, 0)
        local description = spellId and EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetDescription(spellId, 500, 1)
        GameTooltip:AddLine(description and description ~= "" and description or "The full server description is currently unavailable.", 1, 1, 1, true)
    end
    if spellId and EbonBuilds.EchoSemantics then
        GameTooltip:AddLine(" ")
        EbonBuilds.EchoSemantics.AddTooltip(spellId)
    end
    GameTooltip:AddLine(" ")
    if Evidence then Evidence.AddTooltip(item, sourceKind) end
    GameTooltip:Show()
end

local function HideSteps()
    for _, frame in pairs(stepFrames) do frame:Hide() end
end

local function ResetComposer()
    state.snapshot = nil
    state.snapshotByRef = nil
    state.draft = nil
    state.loading = false
    state.title = nil
end

local function ConfidenceKind(level)
    if level == "strong" or level == "high" then return "success" end
    if level == "moderate" or level == "medium" then return nil end
    if level == "limited" or level == "low" then return "warning" end
    return "danger"
end

local function UpdateStatusStrip()
    if not statusText or not confidencePill then return end
    local summary = state.draft and Summary and Summary.Compute(state.draft)
    local intent = EbonBuilds.WizardPresets and EbonBuilds.WizardPresets.Label(state.intentKey) or "Community baseline"
    if summary then
        statusText:SetText(string.format("%s · %s | %s | %d/6 locks | %d included",
            CLASS_LABEL[state.class] or state.class, CurrentSpecName(), summary.intentLabel or intent,
            summary.lockedCount or 0, summary.includedCount or 0) .. string.format(" | %d class Echoes", tonumber(state.draft.catalogCount) or 0))
        SetPill(confidencePill, summary.confidenceText or "Manual setup", ConfidenceKind(summary.confidenceLevel))
    else
        statusText:SetText(string.format("%s · %s | %s",
            CLASS_LABEL[state.class] or state.class, CurrentSpecName(), intent))
        SetPill(confidencePill, state.loading and "Loading evidence" or "Not loaded", state.loading and "warning" or nil)
    end
end

local function ReasonText(snapshot)
    if state.loading then return "Reading the bounded local community build cache..." end
    if not snapshot or snapshot.reasonCode == "NO_MATCHING_BUILDS" then
        return "No matching community sample is stored. All Echoes remain available for manual setup."
    end
    if snapshot.reasonCode == "NOT_ENOUGH_ORIGINS" then
        return string.format("Only %d independent origins are stored. Recommendations are limited; manual setup remains available.", snapshot.originCount or 0)
    end
    if snapshot.reasonCode == "NO_STABLE_CORE" then
        return "No stable community pattern was found. All Echoes remain available for manual setup."
    end
    local _, label = Evidence and Evidence.CohortConfidence(snapshot.originCount or 0)
    return string.format("Based on %d independent local origins — %s. Usage is guidance, not proven performance.",
        snapshot.originCount or 0, label or "Limited local sample")
end

------------------------------------------------------------------------
-- Step 1: context and intent
------------------------------------------------------------------------

local function RefreshContextStep()
    for token, button in pairs(classButtons) do Theme.SetTabSelected(button, token == state.class) end
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[state.class] or {}
    for index, button in ipairs(specButtons) do
        local entry = specs[index]
        button._icon:SetTexture(entry and entry.icon or QUESTION_ICON)
        button._label:SetText(entry and entry.name or ("Spec " .. index))
        Theme.SetTabSelected(button, index == state.spec)
    end
    for key, button in pairs(intentButtons) do Theme.SetTabSelected(button, key == state.intentKey) end
    UpdateStatusStrip()
end

StaticPopupDialogs["EBONBUILDS_WIZARD_CONTEXT_CHANGE"] = {
    text = "Changing class or specialization will rebuild the recommendations and remove the current wizard choices.",
    button1 = "Rebuild",
    button2 = "Cancel",
    OnAccept = function()
        local pending = state.pendingContext
        state.pendingContext = nil
        if not pending then return end
        state.class, state.spec = pending.class, pending.spec
        ResetComposer()
        RefreshContextStep()
    end,
    OnCancel = function() state.pendingContext = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function RequestContext(classToken, spec)
    classToken = classToken or state.class
    spec = spec or state.spec
    if classToken == state.class and spec == state.spec then return end
    if state.draft then
        state.pendingContext = { class = classToken, spec = spec }
        StaticPopup_Show("EBONBUILDS_WIZARD_CONTEXT_CHANGE")
    else
        state.class, state.spec = classToken, spec
        ResetComposer()
        RefreshContextStep()
    end
end

local function LayoutContextStep()
    local ui = state.contextUI
    if not ui or not ui.frame then return end
    local width = tonumber(ui.frame:GetWidth()) or 0
    if width < 80 then return end

    local panelWidth = tonumber(ui.intentPanel:GetWidth()) or math.max(1, width - 36)
    local gap, pad = 8, 12
    local wide = panelWidth >= 620
    local columns = wide and 2 or 1
    local cardHeight = wide and 70 or 62
    local cardWidth = math.max(180, math.floor((panelWidth - pad * 2 - gap * (columns - 1)) / columns))
    for index, key in ipairs(ui.intentOrder) do
        local card = intentButtons[key]
        local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
        card:ClearAllPoints()
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint("TOPLEFT", ui.intentPanel, "TOPLEFT", pad + col * (cardWidth + gap), -45 - row * (cardHeight + gap))
        card._description:SetWidth(math.max(140, cardWidth - 20))
    end
end

local function BuildContextStep()
    if stepFrames[1] then return stepFrames[1] end
    local frame = CreateFrame("Frame", nil, contentArea)
    frame:SetAllPoints(contentArea)
    stepFrames[1] = frame

    local title = MakeText(frame, "GameFontHighlightLarge", nil, "CENTER")
    title:SetPoint("TOP", frame, "TOP", 0, -8)
    title:SetText("Choose the build goal")
    local subtitle = MakeText(frame, "GameFontDisableSmall", 650, "CENTER")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("Select the class, specialization, and how untouched recommendations should begin.")

    local classPanel = Theme.CreateSection(frame, "Class", "Only Echoes verified for the selected class are used by the Wizard.")
    classPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -52)
    classPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -52)
    classPanel:SetHeight(92)
    for index, token in ipairs(CLASS_ORDER) do
        local button = Theme.CreateTab(classPanel, "")
        button:SetSize(40, 40)
        button:SetPoint("TOPLEFT", classPanel, "TOPLEFT", 12 + (index - 1) * 48, -43)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(25, 25)
        icon:SetPoint("CENTER")
        SetClassIcon(icon, token)
        Theme.AttachTooltip(button, CLASS_LABEL[token], "Build a strict class-scoped Echo catalog for this class.")
        button:SetScript("OnClick", function() RequestContext(token, 1) end)
        classButtons[token] = button
    end

    local specPanel = Theme.CreateSection(frame, "Specialization", "Community cohorts remain separated by talent specialization.")
    specPanel:SetPoint("TOPLEFT", classPanel, "BOTTOMLEFT", 0, -10)
    specPanel:SetPoint("TOPRIGHT", classPanel, "BOTTOMRIGHT", 0, -10)
    specPanel:SetHeight(104)
    for index = 1, 3 do
        local button = Theme.CreateTab(specPanel, "")
        button:SetSize(188, 54)
        button:SetPoint("TOPLEFT", specPanel, "TOPLEFT", 12 + (index - 1) * 196, -42)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", button, "LEFT", 9, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local label = MakeText(button, "GameFontHighlightSmall", 130)
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        button._icon, button._label = icon, label
        button:SetScript("OnClick", function() RequestContext(state.class, index) end)
        specButtons[index] = button
    end

    local intentPanel = Theme.CreateSection(frame, "What do you want to emphasize?", "Presets modify untouched defaults only and never fabricate a different community cohort.")
    intentPanel:SetPoint("TOPLEFT", specPanel, "BOTTOMLEFT", 0, -10)
    intentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 8)
    local definitions = EbonBuilds.WizardPresets and EbonBuilds.WizardPresets.DEFINITIONS or {}
    local intentOrder = EbonBuilds.WizardPresets and EbonBuilds.WizardPresets.ORDER or { "community", "offensive", "defensive", "manual" }
    for _, key in ipairs(intentOrder) do
        local def = definitions[key] or { label = key, description = "" }
        local button = Theme.CreateTab(intentPanel, def.label)
        local titleText = button.GetFontString and button:GetFontString()
        if titleText then
            titleText:ClearAllPoints()
            titleText:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -9)
            titleText:SetPoint("RIGHT", button, "RIGHT", -10, 0)
            titleText:SetJustifyH("LEFT")
        end
        local desc = MakeText(button, "GameFontDisableSmall", 260, "LEFT")
        desc:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -30)
        desc:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -10, 7)
        desc:SetJustifyV("TOP")
        desc:SetText(def.description)
        button._description = desc
        button:SetScript("OnClick", function()
            state.intentKey = key
            if state.draft then Draft.SetIntent(state.draft, key, true) end
            RefreshContextStep()
            if state.draft and EbonBuilds.Toast and EbonBuilds.Toast.Show then
                EbonBuilds.Toast.Show("Intent applied to untouched wizard choices")
            end
        end)
        intentButtons[key] = button
    end
    state.contextUI = { frame = frame, intentPanel = intentPanel, intentOrder = intentOrder }
    frame:HookScript("OnSizeChanged", function()
        local generation = state.generation
        EbonBuilds.Scheduler.After("buildWizard.contextLayout", 0, function()
            if state.active and state.generation == generation and state.step == 1 then LayoutContextStep() end
        end, EbonBuilds.Scheduler.INTERACTIVE, true)
    end)
    LayoutContextStep()
    return frame
end

------------------------------------------------------------------------
-- Step 2: locked Echoes
------------------------------------------------------------------------

local function FirstEmptyLock()
    if not state.draft then return 1 end
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        if not state.draft.locks[slot] then return slot end
    end
    return nil
end

local function PickLock(slot)
    if not state.draft then return end
    local picker = EbonBuilds.EchoPicker
    if not picker then return end

    local dataSource
    if picker.DataForClass then
        dataSource = picker.DataForClass(state.draft.class, true)
    elseif EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildAllQualitiesList then
        local entries = EbonBuilds.EchoTableRows.BuildAllQualitiesList()
        dataSource = Draft.FilterEntriesForClass and Draft.FilterEntriesForClass(entries, state.draft.class) or entries
    end

    local show = picker.ShowForLock or picker.Show
    if not show then return end
    show(function(spellId, _, name)
        if EbonBuilds.Weights and EbonBuilds.Weights.StripQualitySuffix then
            name = EbonBuilds.Weights.StripQualitySuffix(tostring(name or ""))
        end
        Draft.SetLock(state.draft, slot, spellId, name, "manual")
        RefreshLocks()
    end, dataSource, state.draft.class)
end

local function CreateLockCard(parent, slot)
    local card = MakePanel(parent)
    card:SetHeight(96)
    local number = MakeText(card, "GameFontDisableSmall")
    number:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -4)
    number:SetText("Slot " .. slot)
    local pill = Theme.CreateStatusPill(card, "Empty")
    pill:SetSize(58, 16)
    pill:SetPoint("TOPRIGHT", card, "TOPRIGHT", -5, -4)
    local pick = CreateFrame("Button", nil, card)
    pick:SetSize(38, 38)
    pick:SetPoint("TOP", card, "TOP", 0, -22)
    local icon = pick:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(QUESTION_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local name = MakeText(card, "GameFontHighlightSmall", 96, "CENTER")
    name:SetPoint("TOP", pick, "BOTTOM", 0, -3)
    name:SetHeight(14)
    local left = Theme.CreateButton(card)
    left:SetSize(22, 18)
    left:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 4, 3)
    left:SetText("<")
    local clear = Theme.CreateButton(card)
    clear:SetSize(42, 18)
    clear:SetPoint("LEFT", left, "RIGHT", 2, 0)
    clear:SetText("Clear")
    local right = Theme.CreateButton(card)
    right:SetSize(22, 18)
    right:SetPoint("LEFT", clear, "RIGHT", 2, 0)
    right:SetText(">")
    pick:SetScript("OnClick", function() PickLock(slot) end)
    pick:SetScript("OnEnter", function(self)
        local lock = state.draft and state.draft.locks[slot]
        if lock then
            local item, kind = SnapshotItem(lock.refKey)
            ShowEchoTooltip(self, lock.refKey, lock.spellId, item, kind)
        end
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    left:SetScript("OnClick", function() Draft.MoveLock(state.draft, slot, math.max(1, slot - 1)); RefreshLocks() end)
    right:SetScript("OnClick", function() Draft.MoveLock(state.draft, slot, math.min(EbonBuilds.Build.LOCKED_SLOTS, slot + 1)); RefreshLocks() end)
    clear:SetScript("OnClick", function() Draft.RemoveLock(state.draft, slot); RefreshLocks() end)
    return { card = card, icon = icon, name = name, pill = pill, left = left, right = right, clear = clear }
end

local function CreateLockSuggestion(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(38)
    Theme.ApplyPanel(row)
    local inspect = CreateFrame("Button", nil, row)
    inspect:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    inspect:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -72, 1)
    local icon = inspect:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", inspect, "LEFT", 5, 0)
    local name = MakeText(inspect, "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 7, -1)
    name:SetPoint("RIGHT", inspect, "RIGHT", -112, 0)
    local meta = MakeText(inspect, "GameFontDisableSmall")
    meta:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 7, 1)
    meta:SetPoint("RIGHT", inspect, "RIGHT", -112, 0)
    local evidence = MakeText(inspect, "GameFontHighlightSmall", 105, "RIGHT")
    evidence:SetPoint("RIGHT", inspect, "RIGHT", -5, 0)
    evidence:SetTextColor(0.45, 0.82, 1, 1)
    local use = Theme.CreateButton(row)
    use:SetSize(62, 22)
    use:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    use:SetText("Use")
    inspect:SetScript("OnEnter", function(self)
        local item = row._item
        if item then ShowEchoTooltip(self, SnapshotRef(item) or item.name, item.lockedSpellId, item, "lock") end
    end)
    inspect:SetScript("OnLeave", function() GameTooltip:Hide() end)
    use:SetScript("OnClick", function()
        local item = row._item
        if not item or not state.draft then return end
        local slot = FirstEmptyLock()
        if not slot then
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("All six lock slots are filled. Clear a slot first.") end
            return
        end
        local refKey = SnapshotRef(item)
        local spellId = tonumber(item.lockedSpellId) or select(1, EchoInfo(refKey or item.name, item.lockedSpellId))
        if spellId then Draft.SetLock(state.draft, slot, spellId, item.name, "accepted"); RefreshLocks() end
    end)
    return { row = row, icon = icon, name = name, meta = meta, evidence = evidence, use = use }
end

local function LayoutLocks()
    if not locksUI then return end
    local width = tonumber(locksUI.slotPanel:GetWidth()) or 700
    if width < 40 then return end

    local columns = width >= 670 and 6 or (width >= 500 and 3 or 2)
    local gap = 6
    local sidePadding = 8
    local headerHeight = locksUI.slotPanel._subtitle and 47 or 34
    local cardHeight = 96
    local rows = math.ceil(EbonBuilds.Build.LOCKED_SLOTS / columns)
    local cardWidth = math.max(84, math.floor((width - sidePadding * 2 - (columns - 1) * gap) / columns))
    local panelHeight = headerHeight + rows * cardHeight + (rows - 1) * gap + 8
    locksUI.slotPanel:SetHeight(panelHeight)

    for slot, ui in ipairs(locksUI.slots) do
        local col, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
        ui.card:ClearAllPoints()
        ui.card:SetSize(cardWidth, cardHeight)
        ui.card:SetPoint("TOPLEFT", locksUI.slotPanel, "TOPLEFT",
            sidePadding + col * (cardWidth + gap), -headerHeight - row * (cardHeight + gap))
        ui.name:SetWidth(math.max(72, cardWidth - 12))

        -- Keep the three compact actions centered as the cards grow from the
        -- six-column layout into the responsive three-column layout.
        ui.clear:ClearAllPoints()
        ui.clear:SetPoint("BOTTOM", ui.card, "BOTTOM", 0, 3)
        ui.left:ClearAllPoints()
        ui.left:SetPoint("RIGHT", ui.clear, "LEFT", -2, 0)
        ui.right:ClearAllPoints()
        ui.right:SetPoint("LEFT", ui.clear, "RIGHT", 2, 0)
    end
end

local function BuildLocksStep()
    if stepFrames[2] then return stepFrames[2] end
    local frame = CreateFrame("Frame", nil, contentArea)
    frame:SetAllPoints(contentArea)
    stepFrames[2] = frame
    local status = MakeText(frame, "GameFontDisableSmall", 650, "CENTER")
    status:SetPoint("TOP", frame, "TOP", 0, -4)
    local slotPanel = Theme.CreateSection(frame, "Core locked Echoes", "Suggested, accepted, and manual ownership remain visually distinct.")
    slotPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    slotPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -28)
    slotPanel:SetHeight(151)
    local slots = {}
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do slots[slot] = CreateLockCard(slotPanel, slot) end

    local recPanel = Theme.CreateSection(frame, "Suggested core", "Apply suggestions without overwriting manual lock choices.")
    recPanel:SetPoint("TOPLEFT", slotPanel, "BOTTOMLEFT", 0, -8)
    recPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 5)
    local apply = Theme.CreateButton(recPanel, "gold")
    apply:SetSize(142, 22)
    apply:SetPoint("TOPRIGHT", recPanel, "TOPRIGHT", -82, -7)
    apply:SetText("Apply suggested core")
    local clear = Theme.CreateButton(recPanel)
    clear:SetSize(68, 22)
    clear:SetPoint("TOPRIGHT", recPanel, "TOPRIGHT", -8, -7)
    clear:SetText("Clear all")
    local rows = {}
    for index = 1, 6 do
        rows[index] = CreateLockSuggestion(recPanel)
        rows[index].row:SetPoint("TOPLEFT", recPanel, "TOPLEFT", 8, -48 - (index - 1) * 40)
        rows[index].row:SetPoint("RIGHT", recPanel, "RIGHT", -8, 0)
    end
    apply:SetScript("OnClick", function()
        if state.draft then Draft.ApplyRecommendedLocks(state.draft, state.snapshot, false); RefreshLocks() end
    end)
    clear:SetScript("OnClick", function()
        if not state.draft then return end
        Draft.BeginBatch(state.draft)
        for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do Draft.RemoveLock(state.draft, slot) end
        Draft.EndBatch(state.draft)
        RefreshLocks()
    end)
    locksUI = { status = status, slotPanel = slotPanel, slots = slots, recPanel = recPanel, rows = rows }
    return frame
end

RefreshLocks = function()
    if not locksUI then return end
    locksUI.status:SetText(ReasonText(state.snapshot))
    for slot, ui in ipairs(locksUI.slots) do
        local lock = state.draft and state.draft.locks[slot]
        if lock then
            local quality = SetEchoIcon(ui.icon, lock.refKey or lock.name, lock.spellId)
            ui.name:SetText(EbonBuilds.Quality.Colorize(VisibleName(lock.name), quality))
            ui.clear:Enable()
            if slot > 1 then ui.left:Enable() else ui.left:Disable() end
            if slot < EbonBuilds.Build.LOCKED_SLOTS then ui.right:Enable() else ui.right:Disable() end
            if lock.ownership == "suggested" then SetPill(ui.pill, "Suggested", "warning")
            elseif lock.ownership == "accepted" then SetPill(ui.pill, "Accepted", "success")
            else SetPill(ui.pill, "Manual", nil) end
        else
            ui.icon:SetTexture(QUESTION_ICON)
            ui.name:SetText("Choose Echo")
            ui.clear:Disable(); ui.left:Disable(); ui.right:Disable()
            SetPill(ui.pill, "Empty", nil)
        end
    end
    local items = state.snapshot and state.snapshot.locked or {}
    for index, ui in ipairs(locksUI.rows) do
        local item = items[index]
        ui.row._item = item
        if item then
            local refKey = SnapshotRef(item)
            local quality, spellId = SetEchoIcon(ui.icon, refKey or item.name, item.lockedSpellId)
            ui.name:SetText(EbonBuilds.Quality.Colorize(VisibleName(item.name), quality))
            ui.meta:SetText(spellId and EbonBuilds.EchoCatalog.GetSemanticSummary(spellId, 2) or "Classification unavailable")
            ui.evidence:SetText(Evidence and Evidence.CompactText(item, "lock") or "Community")
            local present = false
            for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
                if state.draft and state.draft.locks[slot] and state.draft.locks[slot].refKey == refKey then present = true break end
            end
            ui.use:SetText(present and "Added" or "Use")
            if present then ui.use:Disable() else ui.use:Enable() end
            ui.row:Show()
        else
            ui.row:Hide()
        end
    end
    LayoutLocks()
    UpdateStatusStrip()
end

------------------------------------------------------------------------
-- Step 3: grouped, virtualized priorities
------------------------------------------------------------------------

local function BuildPrioritiesStep()
    if prioritiesUI then return prioritiesUI.frame end
    prioritiesUI = EbonBuilds.BuildWizardPriorityStep.Create(contentArea, {
        setEchoIcon = function(texture, refKey, preferredId)
            return SetEchoIcon(texture, refKey, preferredId)
        end,
        visibleName = VisibleName,
        showEchoTooltip = function(owner, refKey, preferredId, item, sourceKind)
            ShowEchoTooltip(owner, refKey, preferredId, item, sourceKind)
        end,
        updateStatus = UpdateStatusStrip,
        onDraftChanged = function()
            UpdateStatusStrip()
        end,
    })
    stepFrames[3] = prioritiesUI.frame
    return prioritiesUI.frame
end

RefreshPriorities = function()
    if not prioritiesUI or not state.draft then return end
    prioritiesUI:SetContext(state.draft, state.class, SnapshotItem)
    prioritiesUI:Refresh(false)
end

------------------------------------------------------------------------
-- Step 4: scoring
------------------------------------------------------------------------

local function ScoringExample(style)
    local profile = Draft.StyleProfile(style)
    local strongCommon = (profile.weights.Strong or 0) + (profile.quality[0] or 0)
    local usefulEpic = (profile.weights.Useful or 0) + (profile.quality[3] or 0)
    if strongCommon > usefulEpic then return "A Strong common Echo usually ranks above a Useful epic Echo." end
    if strongCommon < usefulEpic then return "A Useful epic Echo can rank above a Strong common Echo." end
    return "A Strong common Echo and a Useful epic Echo are approximately tied."
end

local function FamilyChoiceLabel(value, bonus)
    value = value or "None"
    if value == "None" then return "None (+0)" end
    return string.format("%s (+%d)", value, tonumber(bonus) or 0)
end

local function FamilyMenu(dropdown, values, setter, bonus)
    dropdown:SetMenuBuilder(function()
        local items = {}
        for _, value in ipairs(values) do
            local valueKey = value
            items[#items + 1] = {
                text = FamilyChoiceLabel(valueKey, bonus),
                checked = dropdown._familyValue == valueKey,
                func = function()
                    setter(valueKey)
                    dropdown._familyValue = valueKey
                    dropdown:SetText(FamilyChoiceLabel(valueKey, bonus))
                    RefreshScoring()
                end,
            }
        end
        return items
    end)
end

local function SetScoringCardSelected(card, selected)
    if not card then return end
    card._selected = selected and true or false
    if card._selected then
        card:SetBackdropColor(0.20, 0.17, 0.07, 1)
        card:SetBackdropBorderColor(unpack(Theme.ACCENT_GOLD))
        card.title:SetTextColor(1, 0.90, 0.35, 1)
        card.description:SetTextColor(unpack(Theme.TEXT_PRIMARY))
        card.selectedText:SetText("Selected")
        card.selectedText:Show()
    else
        Theme.ApplyCard(card)
        card.title:SetTextColor(unpack(Theme.TEXT_PRIMARY))
        card.description:SetTextColor(unpack(Theme.TEXT_MUTED))
        card.selectedText:Hide()
    end
end

local function CreateScoringCard(parent, style, description)
    local card = CreateFrame("Button", nil, parent)
    Theme.ApplyCard(card)
    card:RegisterForClicks("LeftButtonUp")

    local title = MakeText(card, "GameFontNormal")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 11, -9)
    title:SetPoint("RIGHT", card, "RIGHT", -72, 0)
    title:SetJustifyH("LEFT")
    title:SetText(style)

    local desc = MakeText(card, "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    desc:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -11, 39)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetText(description)

    local profile = Draft.StyleProfile(style)
    local priorityText = MakeText(card, "GameFontNormalSmall")
    priorityText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 20)
    priorityText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    priorityText:SetJustifyH("LEFT")
    priorityText:SetText(string.format("Priority E %+d · S %+d · U %+d",
        profile.weights.Essential or 0, profile.weights.Strong or 0, profile.weights.Useful or 0))
    priorityText:SetTextColor(0.45, 0.82, 1, 1)

    local rarityText = MakeText(card, "GameFontNormalSmall")
    rarityText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 6)
    rarityText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    rarityText:SetJustifyH("LEFT")
    rarityText:SetText(
        "Rarity "
        .. EbonBuilds.Quality.Colorize(string.format("C %+d", profile.quality[0] or 0), 0)
        .. " · "
        .. EbonBuilds.Quality.Colorize(string.format("U %+d", profile.quality[1] or 0), 1)
        .. " · "
        .. EbonBuilds.Quality.Colorize(string.format("R %+d", profile.quality[2] or 0), 2)
        .. " · "
        .. EbonBuilds.Quality.Colorize(string.format("E %+d", profile.quality[3] or 0), 3)
    )
    local selectedText = MakeText(card, "GameFontNormalSmall", 58, "RIGHT")
    selectedText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -9, -9)
    selectedText:SetText("Selected")
    selectedText:SetTextColor(unpack(Theme.ACCENT_GOLD))
    selectedText:Hide()

    card.title = title
    card.description = desc
    card.priorityText = priorityText
    card.rarityText = rarityText
    card.selectedText = selectedText
    card:SetScript("OnEnter", function(self)
        if not self._selected then Theme.SetCardHovered(self, true) end
    end)
    card:SetScript("OnLeave", function(self)
        if self._selected then SetScoringCardSelected(self, true) else Theme.SetCardHovered(self, false) end
    end)
    Theme.AttachTooltip(card, "Scoring profile", "The cyan line shows priority values. The quality-colored line shows Common, Uncommon, Rare, and Epic bonuses added on top of that priority.")
    return card
end

local function LayoutScoringStep()
    if not scoringUI or not scoringUI.frame then return end
    local frame = scoringUI.frame
    local width = tonumber(frame:GetWidth()) or 0
    if width < 40 then return end

    local margin, gap = 12, 8
    local top = -58
    local cards = scoringUI.orderedCards
    local cardsBottom

    if width >= 590 then
        local cardWidth = math.floor((width - margin * 2 - gap * 2) / 3)
        for index, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetSize(cardWidth, 108)
            card:SetPoint("TOPLEFT", frame, "TOPLEFT", margin + (index - 1) * (cardWidth + gap), top)
        end
        cardsBottom = top - 108
    elseif width >= 410 then
        local cardWidth = math.floor((width - margin * 2 - gap) / 2)
        for index, card in ipairs(cards) do card:ClearAllPoints() end
        cards[1]:SetSize(cardWidth, 108)
        cards[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, top)
        cards[2]:SetSize(cardWidth, 108)
        cards[2]:SetPoint("TOPLEFT", frame, "TOPLEFT", margin + cardWidth + gap, top)
        cards[3]:SetSize(width - margin * 2, 96)
        cards[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, top - 108 - gap)
        cardsBottom = top - 108 - gap - 96
    else
        local cardWidth = width - margin * 2
        for index, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetSize(cardWidth, 102)
            card:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, top - (index - 1) * (102 + gap))
        end
        cardsBottom = top - 3 * 102 - 2 * gap
    end

    scoringUI.behaviorPanel:ClearAllPoints()
    scoringUI.behaviorPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, cardsBottom - 10)
    scoringUI.behaviorPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -margin, cardsBottom - 10)
    scoringUI.behaviorPanel:SetHeight(68)
    scoringUI.behavior:ClearAllPoints()
    scoringUI.behavior:SetPoint("LEFT", scoringUI.behaviorPanel, "LEFT", 14, -11)
    scoringUI.behavior:SetPoint("RIGHT", scoringUI.behaviorPanel, "RIGHT", -14, -11)
    scoringUI.behavior:SetJustifyH("CENTER")

    scoringUI.advancedToggle:ClearAllPoints()
    scoringUI.advancedToggle:SetPoint("TOPLEFT", scoringUI.behaviorPanel, "BOTTOMLEFT", 0, -8)

    scoringUI.advanced:ClearAllPoints()
    scoringUI.advanced:SetPoint("TOPLEFT", scoringUI.advancedToggle, "BOTTOMLEFT", 0, -7)
    scoringUI.advanced:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -margin, 8)

    local advancedWidth = math.max(1, width - margin * 2)
    local primaryWidth
    if advancedWidth >= 570 then
        primaryWidth = 150
        scoringUI.primaryLabel:ClearAllPoints()
        scoringUI.primaryLabel:SetPoint("TOPLEFT", scoringUI.advanced, "TOPLEFT", 14, -48)
        scoringUI.primary:ClearAllPoints()
        scoringUI.primary:SetSize(primaryWidth, 24)
        scoringUI.primary:SetPoint("TOPLEFT", scoringUI.primaryLabel, "BOTTOMLEFT", 0, -5)
        scoringUI.primaryResolved:ClearAllPoints()
        scoringUI.primaryResolved:SetPoint("LEFT", scoringUI.primary, "RIGHT", 8, 0)
        scoringUI.primaryResolved:SetWidth(125)

        scoringUI.secondaryLabel:ClearAllPoints()
        scoringUI.secondaryLabel:SetPoint("TOPLEFT", scoringUI.primary, "BOTTOMLEFT", 0, -18)
        scoringUI.secondary:ClearAllPoints()
        scoringUI.secondary:SetSize(primaryWidth, 24)
        scoringUI.secondary:SetPoint("TOPLEFT", scoringUI.secondaryLabel, "BOTTOMLEFT", 0, -5)

        scoringUI.values:ClearAllPoints()
        scoringUI.values:SetPoint("TOPLEFT", scoringUI.advanced, "TOPLEFT", math.floor(advancedWidth * 0.46), -50)
        scoringUI.values:SetPoint("RIGHT", scoringUI.advanced, "RIGHT", -14, 0)
        scoringUI.validation:ClearAllPoints()
        scoringUI.validation:SetPoint("TOPLEFT", scoringUI.values, "BOTTOMLEFT", 0, -12)
        scoringUI.validation:SetPoint("RIGHT", scoringUI.advanced, "RIGHT", -14, 0)
    else
        local controlGap = 10
        local controlWidth = math.max(116, math.floor((advancedWidth - 28 - controlGap) / 2))
        scoringUI.primaryLabel:ClearAllPoints()
        scoringUI.primaryLabel:SetPoint("TOPLEFT", scoringUI.advanced, "TOPLEFT", 14, -48)
        scoringUI.primary:ClearAllPoints()
        scoringUI.primary:SetSize(controlWidth, 24)
        scoringUI.primary:SetPoint("TOPLEFT", scoringUI.primaryLabel, "BOTTOMLEFT", 0, -5)
        scoringUI.primaryResolved:ClearAllPoints()
        scoringUI.primaryResolved:SetPoint("TOPLEFT", scoringUI.primary, "BOTTOMLEFT", 0, -4)
        scoringUI.primaryResolved:SetWidth(controlWidth)

        scoringUI.secondaryLabel:ClearAllPoints()
        scoringUI.secondaryLabel:SetPoint("TOPLEFT", scoringUI.advanced, "TOPLEFT", 14 + controlWidth + controlGap, -48)
        scoringUI.secondary:ClearAllPoints()
        scoringUI.secondary:SetSize(controlWidth, 24)
        scoringUI.secondary:SetPoint("TOPLEFT", scoringUI.secondaryLabel, "BOTTOMLEFT", 0, -5)

        scoringUI.values:ClearAllPoints()
        scoringUI.values:SetPoint("TOPLEFT", scoringUI.advanced, "TOPLEFT", 14, -112)
        scoringUI.values:SetPoint("RIGHT", scoringUI.advanced, "RIGHT", -14, 0)
        scoringUI.validation:ClearAllPoints()
        scoringUI.validation:SetPoint("TOPLEFT", scoringUI.values, "BOTTOMLEFT", 0, -8)
        scoringUI.validation:SetPoint("RIGHT", scoringUI.advanced, "RIGHT", -14, 0)
    end
end

local function BuildScoringStep()
    if stepFrames[4] then return stepFrames[4] end
    local frame = CreateFrame("Frame", nil, contentArea)
    frame:SetAllPoints(contentArea)
    stepFrames[4] = frame

    local title = MakeText(frame, "GameFontHighlightLarge", nil, "CENTER")
    title:SetPoint("TOP", frame, "TOP", 0, -8)
    title:SetText("Choose how priorities become weights")
    local subtitle = MakeText(frame, "GameFontDisableSmall", nil, "CENTER")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -31)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -31)
    subtitle:SetText("Using an Echo automatically assigns the lowest positive weight when needed. Choosing a priority also activates it.")

    local styleButtons = {}
    local orderedCards = {}
    local styleDescriptions = {
        ["Recommendation-focused"] = "Large priority gaps; quality acts mainly as a tie-breaker.",
        ["Balanced"] = "Priority leads, while rarity can overturn close choices.",
        ["Quality-focused"] = "Rarity can overtake higher priority levels more often.",
    }
    for _, style in ipairs(Draft.STYLES) do
        local styleKey = style
        local card = CreateScoringCard(frame, styleKey, styleDescriptions[styleKey])
        card:SetScript("OnClick", function()
            Draft.SetScoringStyle(state.draft, styleKey)
            RefreshScoring()
        end)
        styleButtons[styleKey] = card
        orderedCards[#orderedCards + 1] = card
    end

    local behaviorPanel = Theme.CreateSection(frame, "Current behavior", "Generated from the active scoring table.")
    local behavior = MakeText(behaviorPanel, "GameFontHighlight", nil, "CENTER")

    local advancedToggle = Theme.CreateButton(frame)
    advancedToggle:SetSize(150, 24)
    advancedToggle:SetText("Advanced tuning v")
    local advanced = Theme.CreateSection(frame, "Advanced tuning", "Optional family modifiers are disabled by default.")

    local primaryBonus = Draft.PRIMARY_FAMILY_BONUS or 20
    local secondaryBonus = Draft.SECONDARY_FAMILY_BONUS or 10

    local primaryLabel = MakeText(advanced, "GameFontNormal")
    primaryLabel:SetText(string.format("Primary family bonus (+%d)", primaryBonus))
    local primary = Theme.CreateDropdown(advanced, 150, "None (+0)")
    local primaryResolved = MakeText(advanced, "GameFontDisableSmall")

    local secondaryLabel = MakeText(advanced, "GameFontNormal")
    secondaryLabel:SetText(string.format("Secondary family bonus (+%d)", secondaryBonus))
    local secondary = Theme.CreateDropdown(advanced, 150, "None (+0)")

    local values = MakeText(advanced, "GameFontHighlightSmall")
    values:SetJustifyV("TOP")
    local validation = MakeText(advanced, "GameFontDisableSmall")
    validation:SetJustifyV("TOP")

    advancedToggle:SetScript("OnClick", function()
        state.advancedScoring = not state.advancedScoring
        if state.advancedScoring then advanced:Show(); advancedToggle:SetText("Advanced tuning ^")
        else advanced:Hide(); advancedToggle:SetText("Advanced tuning v") end
    end)
    FamilyMenu(primary, FAMILY_VALUES, function(value) Draft.SetPrimaryFamily(state.draft, value) end, primaryBonus)
    FamilyMenu(secondary, SECONDARY_VALUES, function(value) Draft.SetSecondaryFamily(state.draft, value) end, secondaryBonus)
    Theme.AttachTooltip(primary._button or primary, "Primary family bonus", string.format("Selecting a family adds +%d score to matching Echoes. None adds +0.", primaryBonus))
    Theme.AttachTooltip(secondary._button or secondary, "Secondary family bonus", string.format("Selecting a family adds +%d score to matching Echoes. None adds +0.", secondaryBonus))

    scoringUI = {
        frame = frame, styleButtons = styleButtons, orderedCards = orderedCards,
        behaviorPanel = behaviorPanel, behavior = behavior, advancedToggle = advancedToggle,
        advanced = advanced, primaryLabel = primaryLabel, primary = primary,
        primaryResolved = primaryResolved, secondaryLabel = secondaryLabel,
        secondary = secondary, values = values, validation = validation,
    }

    frame:HookScript("OnSizeChanged", function()
        local generation = state.generation
        EbonBuilds.Scheduler.After("buildWizard.scoringLayout", 0, function()
            if state.active and state.generation == generation and state.step == 4 then LayoutScoringStep() end
        end, EbonBuilds.Scheduler.INTERACTIVE, true)
    end)
    LayoutScoringStep()
    return frame
end

RefreshScoring = function()
    if not scoringUI or not state.draft then return end
    LayoutScoringStep()
    for style, button in pairs(scoringUI.styleButtons) do SetScoringCardSelected(button, style == state.draft.scoringStyle) end
    scoringUI.behavior:SetText(ScoringExample(state.draft.scoringStyle))
    local primaryBonus = Draft.PRIMARY_FAMILY_BONUS or 20
    local secondaryBonus = Draft.SECONDARY_FAMILY_BONUS or 10
    scoringUI.primary._familyValue = state.draft.primaryFamily or "None"
    scoringUI.secondary._familyValue = state.draft.secondaryFamily or "None"
    scoringUI.primary:SetText(FamilyChoiceLabel(scoringUI.primary._familyValue, primaryBonus))
    scoringUI.secondary:SetText(FamilyChoiceLabel(scoringUI.secondary._familyValue, secondaryBonus))
    local resolved = Draft.ResolvePrimaryFamily(state.draft) or "None"
    if not state.draft.primaryFamily or state.draft.primaryFamily == "None" then
        scoringUI.primaryResolved:SetText("No primary family bonus (+0)")
    elseif state.draft.primaryFamily == "Auto" then
        scoringUI.primaryResolved:SetText(string.format("Auto: %s (+%d)", resolved, primaryBonus))
    else
        scoringUI.primaryResolved:SetText(string.format("%s family (+%d)", resolved, primaryBonus))
    end
    local profile = Draft.StyleProfile(state.draft.scoringStyle)
    scoringUI.values:SetText(string.format(
        "Importance values\nEssential %+d · Strong %+d · Useful %+d · Neutral %+d · Avoid %+d\n\nQuality bonuses\nCommon %+d · Uncommon %+d · Rare %+d · Epic %+d\n\nFamily bonuses\nPrimary %+d · Secondary %+d when selected",
        profile.weights.Essential, profile.weights.Strong, profile.weights.Useful, profile.weights.Neutral, profile.weights.Avoid,
        profile.quality[0], profile.quality[1], profile.quality[2], profile.quality[3], primaryBonus, secondaryBonus))
    local ok, diagnostics = Draft.Calibrate(state.draft)
    if ok then
        scoringUI.validation:SetText(string.format("Validation ready · %d included Echoes checked.", tonumber(diagnostics.checkedEchoes) or 0))
        scoringUI.validation:SetTextColor(unpack(Theme.SUCCESS))
    else
        scoringUI.validation:SetText("Review warning: " .. table.concat(diagnostics, " "))
        scoringUI.validation:SetTextColor(unpack(Theme.WARNING))
    end
    if state.advancedScoring then scoringUI.advanced:Show(); scoringUI.advancedToggle:SetText("Advanced tuning ^")
    else scoringUI.advanced:Hide(); scoringUI.advancedToggle:SetText("Advanced tuning v") end
    UpdateStatusStrip()
end

------------------------------------------------------------------------
-- Step 5: review
------------------------------------------------------------------------

local function EditStep(step)
    state.step = step
    RenderCurrentStep()
end

local function CreateReviewSection(parent, title, topOffset, editStep)
    local panel = Theme.CreateSection(parent, title, "")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, topOffset)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, topOffset)
    panel:SetHeight(64)
    local value = MakeText(panel, "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -34)
    value:SetPoint("RIGHT", panel, "RIGHT", -70, 0)
    local edit = Theme.CreateButton(panel)
    edit:SetSize(48, 20)
    edit:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    edit:SetText("Edit")
    edit:SetScript("OnClick", function() EditStep(editStep) end)
    return panel, value
end

local function BuildReviewStep()
    if stepFrames[5] then return stepFrames[5] end
    local frame = CreateFrame("Frame", nil, contentArea)
    frame:SetAllPoints(contentArea)
    stepFrames[5] = frame
    local title = MakeText(frame, "GameFontHighlightLarge", nil, "CENTER")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText("Review and create")

    local nameLabel = MakeText(frame, "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    nameLabel:SetText("Build name")
    local nameBox = CreateFrame("EditBox", nil, frame)
    nameBox:SetHeight(26)
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
    nameBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -58)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(80)
    nameBox:SetFontObject("ChatFontNormal")
    nameBox:SetTextInsets(8, 8, 0, 0)
    Theme.ApplyInput(nameBox)
    Theme.WireEditBox(nameBox, nameBox)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnTextChanged", function(self) state.title = self:GetText() end)

    local contextPanel, contextValue = CreateReviewSection(frame, "Character and goal", -94, 1)
    local lockPanel, lockValue = CreateReviewSection(frame, "Locked Echoes", -164, 2)
    local priorityPanel, priorityValue = CreateReviewSection(frame, "Priorities", -234, 3)
    local scoringPanel, scoringValue = CreateReviewSection(frame, "Scoring", -304, 4)
    local warnings = Theme.CreateSection(frame, "Warnings and deviations", "Only choices that can change interpretation are surfaced here.")
    warnings:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -374)
    warnings:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
    local warningText = MakeText(warnings, "GameFontDisableSmall")
    warningText:SetPoint("TOPLEFT", warnings, "TOPLEFT", 12, -45)
    warningText:SetPoint("BOTTOMRIGHT", warnings, "BOTTOMRIGHT", -12, 8)
    warningText:SetJustifyV("TOP")

    reviewUI = {
        nameBox = nameBox, contextValue = contextValue, lockValue = lockValue,
        priorityValue = priorityValue, scoringValue = scoringValue, warningText = warningText,
    }
    return frame
end

RefreshReview = function()
    if not reviewUI or not state.draft then return end
    if not state.title or state.title == "" then state.title = CurrentSpecName() .. " Community Build" end
    if reviewUI.nameBox:GetText() ~= state.title then reviewUI.nameBox:SetText(state.title) end
    local summary = Summary.Compute(state.draft)
    reviewUI.contextValue:SetText(string.format("%s · %s · %s · %s",
        CLASS_LABEL[state.class] or state.class, CurrentSpecName(), summary.intentLabel or "Community baseline",
        summary.confidenceText or "Manual setup") .. string.format(" · %d verified class Echoes", tonumber(state.draft.catalogCount) or 0))

    local lockNames = {}
    for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local lock = state.draft.locks[slot]
        if lock then lockNames[#lockNames + 1] = VisibleName(lock.name) end
    end
    reviewUI.lockValue:SetText(string.format("%d selected · %d manual — %s",
        summary.lockedCount or 0, summary.manualLockCount or 0,
        #lockNames > 0 and table.concat(lockNames, ", ") or "No locked Echoes"))
    local d = summary.distribution
    reviewUI.priorityValue:SetText(string.format("%d included · %d changed — Essential %d · Strong %d · Useful %d · Neutral %d · Avoid %d",
        summary.includedCount or 0, summary.changedPriorityCount or 0,
        d.Essential or 0, d.Strong or 0, d.Useful or 0, d.Neutral or 0, d.Avoid or 0))
    local primary = state.draft.primaryFamily == "Auto" and ("Auto (" .. tostring(Draft.ResolvePrimaryFamily(state.draft) or "None") .. ")") or state.draft.primaryFamily
    reviewUI.scoringValue:SetText(string.format("%s · Primary %s · Secondary %s",
        state.draft.scoringStyle, primary, state.draft.secondaryFamily or "None"))

    local warnings = {}
    if (state.draft.originCount or 0) < 8 then warnings[#warnings + 1] = "• Recommendations are based on a limited local sample." end
    if summary.manualLockCount > 0 then warnings[#warnings + 1] = string.format("• %d locked Echo choice(s) are manual.", summary.manualLockCount) end
    if summary.excludedRecommendedCount > 0 then warnings[#warnings + 1] = string.format("• %d recommended priorit%s excluded.", summary.excludedRecommendedCount, summary.excludedRecommendedCount == 1 and "y is" or "ies are") end
    if summary.promotedAvoidCount > 0 then warnings[#warnings + 1] = string.format("• %d negative-signal Echo(s) were promoted.", summary.promotedAvoidCount) end
    if (summary.avoidPolicyCount or 0) > 0 then warnings[#warnings + 1] = string.format("• %d Avoid Echo(s) will receive the Never Pick policy.", summary.avoidPolicyCount) end
    if (state.draft.unverifiedCount or 0) > 0 then warnings[#warnings + 1] = string.format("• %d Echo record(s) were excluded because class availability could not be verified.", state.draft.unverifiedCount) end
    if (state.draft.unavailableCount or 0) > 0 then warnings[#warnings + 1] = string.format("• %d known Echo record(s) are unavailable to this class and remain inspectable in Diagnostics.", state.draft.unavailableCount) end
    if (state.draft.conflictedCount or 0) > 0 then warnings[#warnings + 1] = string.format("• %d Echo record(s) use runtime availability despite bundled-data conflicts.", state.draft.conflictedCount) end
    local unresolvedCount = Draft.UnresolvedCount and Draft.UnresolvedCount(state.draft) or 0
    if unresolvedCount > 0 then warnings[#warnings + 1] = string.format("• %d legacy recommendation reference(s) could not be resolved safely.", unresolvedCount) end
    if state.catalogChangedWhileOpen then warnings[#warnings + 1] = "• Echo data changed while this Wizard was open. Restart the Wizard before creating this build." end
    if #warnings == 0 then warnings[1] = "No material conflicts detected. Community usage still does not guarantee performance." end
    reviewUI.warningText:SetText(table.concat(warnings, "\n"))
    UpdateStatusStrip()
end

------------------------------------------------------------------------
-- Creation and lifecycle
------------------------------------------------------------------------

local function BuildData()
    return state.draft and Draft.CreateBuildData(state.draft, state.title)
end

local function ValidateCreate()
    if state.catalogChangedWhileOpen then
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("Echo data changed. Restart the Build Wizard before creating this build.") end
        return false
    end
    local title = tostring(state.title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("Enter a build name before creating the build") end
        if reviewUI and reviewUI.nameBox then reviewUI.nameBox:SetFocus() end
        return false
    end
    state.title = title
    return true
end

local function CreateDirect()
    if not ValidateCreate() then return end
    local data = BuildData()
    if not data then return end
    local build = EbonBuilds.Build.Create(data)
    EbonBuilds.Build.SetActive(build.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then EbonBuilds.BuildList.Refresh() end
    EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
    if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("Build created: " .. build.title) end
end

local function CreateAndCustomize()
    if not ValidateCreate() then return end
    local data = BuildData()
    if not data then return end
    EbonBuilds.Runtime.pendingWeights = EbonBuilds.Weights.CloneWeights(data.echoWeights)
    EbonBuilds.Runtime.pendingRefWeights = EbonBuilds.Weights.CloneRefWeights(data.echoWeightsByRef)
    EbonBuilds.Runtime.wizardPrefill = {
        title = data.title, class = data.class, spec = data.spec, comments = data.comments,
        lockedEchoes = data.lockedEchoes, settings = data.settings, isPublic = false,
        wizardMeta = data.wizardMeta, echoWeightsByRef = data.echoWeightsByRef, echoRefs = data.echoRefs,
        echoSchema = data.echoSchema, echoCatalogFingerprint = data.echoCatalogFingerprint,
    }
    EbonBuilds.Runtime.isEditingBuild = true
    EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create", fromWizard = true })
end

local function CancelWizard()
    local active = EbonBuilds.Build.GetActive()
    if active then EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else EbonBuilds.ViewRouter.Show("welcome") end
end

local function LoadRecommendations()
    state.loading = true
    state.snapshot = nil
    state.draft = nil
    UpdateStatusStrip()
    RefreshLocks()
    local wantedKey = EbonBuilds.CommunityEligibility.CohortKey(state.class, state.spec)
    local generation = state.generation
    local catalogRevision = EbonBuilds.EchoCatalog.GetRevision()
    EbonBuilds.RecommendationService.Ensure(state.class, state.spec, function(snapshot)
        if not state.active or state.generation ~= generation then return end
        if not viewFrame or not viewFrame:IsShown() then return end
        if wantedKey ~= EbonBuilds.CommunityEligibility.CohortKey(state.class, state.spec) then return end
        if catalogRevision ~= EbonBuilds.EchoCatalog.GetRevision() then
            state.loading = false
            LoadRecommendations()
            return
        end
        state.snapshot = snapshot or {}
        state.loading = false
        IndexSnapshot(state.snapshot)
        state.draft = Draft.New(state.snapshot, state.class, state.spec, state.intentKey)
        state.catalogRevision = state.draft.catalogRevision
        state.catalogFingerprint = state.draft.catalogFingerprint
        state.catalogChangedWhileOpen = false
        state.draft.step = state.step
        RefreshLocks()
        RefreshPriorities()
        UpdateStatusStrip()
        RenderCurrentStep()
    end)
end

local function ValidateForward()
    if state.step == 2 and state.loading then return false end
    if state.step == 3 then
        local summary = state.draft and Summary.Compute(state.draft)
        if not summary or summary.includedCount < 1 then
            if EbonBuilds.Toast and EbonBuilds.Toast.Show then EbonBuilds.Toast.Show("Include at least one Echo priority before continuing") end
            return false
        end
    end
    return true
end

local function GoNext()
    if state.step == 1 then
        state.step = 2
        RenderCurrentStep()
        local wantedKey = EbonBuilds.CommunityEligibility.CohortKey(state.class, state.spec)
        if not state.draft or not state.snapshot or state.draft.cohortKey ~= wantedKey then
            LoadRecommendations()
        end
        return
    end
    if not ValidateForward() then return end
    if state.step == 2 and state.draft then
        Draft.BeginBatch(state.draft)
        for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
            local lock = state.draft.locks[slot]
            if lock and lock.ownership == "suggested" then Draft.AcceptLock(state.draft, slot) end
        end
        Draft.EndBatch(state.draft)
    end
    if state.step < 5 then
        state.step = state.step + 1
        if state.draft then state.draft.step = state.step end
        RenderCurrentStep()
    else
        CreateDirect()
    end
end

local function GoBack()
    if state.step <= 1 then return end
    state.step = state.step - 1
    if state.draft then state.draft.step = state.step end
    RenderCurrentStep()
end

RenderCurrentStep = function()
    if prioritiesUI and state.step ~= 3 then prioritiesUI:Hide() end
    HideSteps()
    alternateBtn:Hide()
    backBtn:Show()
    cancelBtn:Show()
    stepLabel:SetText("Step " .. tostring(state.step) .. "/5")
    if state.step == 1 then
        BuildContextStep():Show()
        backBtn:Hide()
        nextBtn:SetText("Continue")
        nextBtn:Enable()
        RefreshContextStep()
        LayoutContextStep()
    elseif state.step == 2 then
        BuildLocksStep():Show()
        nextBtn:SetText("Continue")
        if state.loading then nextBtn:Disable() else nextBtn:Enable() end
        RefreshLocks()
    elseif state.step == 3 then
        BuildPrioritiesStep()
        prioritiesUI:SetContext(state.draft, state.class, SnapshotItem)
        prioritiesUI:Show()
        nextBtn:SetText("Continue")
        nextBtn:Enable()
    elseif state.step == 4 then
        BuildScoringStep():Show()
        nextBtn:SetText("Continue")
        nextBtn:Enable()
        RefreshScoring()
    else
        BuildReviewStep():Show()
        nextBtn:SetText("Create Build")
        nextBtn:Enable()
        alternateBtn:SetText("Create & Customize")
        alternateBtn:Show()
        RefreshReview()
    end
    UpdateStatusStrip()
end


local function OnCatalogChanged(_, revision, fingerprint)
    if not state.active then return end
    if state.draft and tonumber(revision) ~= tonumber(state.catalogRevision) then
        state.catalogChangedWhileOpen = true
        UpdateStatusStrip()
        if state.step == 5 then RefreshReview() end
    elseif state.step == 1 and not state.draft then
        state.catalogRevision = revision
        state.catalogFingerprint = fingerprint
        RefreshContextStep()
    end
end

if EbonBuilds.EventHub and EbonBuilds.EventHub.On then
    EbonBuilds.EventHub.On("ECHO_CATALOG_CHANGED", OnCatalogChanged)
end

local view = {}

function view.Show(container)
    sessionGeneration = sessionGeneration + 1
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    state = {
        active = true,
        generation = sessionGeneration,
        step = 1,
        class = EbonBuilds.Build.PlayerClassToken(),
        spec = EbonBuilds.Build.PlayerTopTalentTab(),
        intentKey = "community",
        advancedScoring = false,
        catalogRevision = EbonBuilds.EchoCatalog.GetRevision(),
        catalogFingerprint = EbonBuilds.EchoCatalog.GetFingerprint(),
        catalogChangedWhileOpen = false,
    }
    ResetComposer()
    state.active = true
    state.generation = sessionGeneration
    state.step = 1
    state.class = EbonBuilds.Build.PlayerClassToken()
    state.spec = EbonBuilds.Build.PlayerTopTalentTab()
    state.intentKey = "community"
    viewFrame:Show()
    RenderCurrentStep()
end

function view.Hide()
    state.active = false
    sessionGeneration = sessionGeneration + 1
    if prioritiesUI then prioritiesUI:Hide(); prioritiesUI:CancelScheduled() end
    EbonBuilds.Scheduler.Cancel("buildWizard.search")
    EbonBuilds.Scheduler.Cancel("buildWizard.priorityLayout")
    if viewFrame then viewFrame:Hide() end
end

local function BuildViewFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    local header = MakeText(frame, "GameFontHighlight")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -9)
    header:SetText("Build Wizard")
    stepLabel = MakeText(frame, "GameFontNormal")
    stepLabel:SetPoint("TOP", frame, "TOP", 0, -9)

    statusStrip = CreateFrame("Frame", nil, frame)
    statusStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -32)
    statusStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -32)
    statusStrip:SetHeight(27)
    Theme.ApplyPanel(statusStrip)
    statusText = MakeText(statusStrip, "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", statusStrip, "LEFT", 9, 0)
    statusText:SetPoint("RIGHT", statusStrip, "RIGHT", -148, 0)
    confidencePill = Theme.CreateStatusPill(statusStrip, "Not loaded")
    confidencePill:SetSize(130, 17)
    confidencePill:SetPoint("RIGHT", statusStrip, "RIGHT", -6, 0)

    contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -64)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 48)

    backBtn = Theme.CreateButton(frame)
    backBtn:SetSize(82, 24)
    backBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 14)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", GoBack)
    nextBtn = Theme.CreateButton(frame, "gold")
    nextBtn:SetSize(152, 24)
    nextBtn:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
    nextBtn:SetScript("OnClick", GoNext)
    cancelBtn = Theme.CreateButton(frame)
    cancelBtn:SetSize(72, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 14)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", CancelWizard)
    alternateBtn = Theme.CreateButton(frame)
    alternateBtn:SetSize(156, 24)
    alternateBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
    alternateBtn:SetScript("OnClick", CreateAndCustomize)

    frame:HookScript("OnSizeChanged", function()
        local generation = state.generation
        EbonBuilds.Scheduler.After("buildWizard.layout", 0, function()
            if not state.active or state.generation ~= generation then return end
            if state.step == 2 then LayoutLocks()
            elseif state.step == 3 and prioritiesUI then prioritiesUI:RefreshLayout() end
        end, EbonBuilds.Scheduler.INTERACTIVE, true)
    end)
    frame:Hide()
    return frame
end

function Wizard.RefreshLayout()
    if state.step == 2 then LayoutLocks()
    elseif state.step == 3 and prioritiesUI then prioritiesUI:RefreshLayout() end
end

function Wizard.Init()
    viewFrame = BuildViewFrame()
    EbonBuilds.ViewRouter.Register("buildWizard", view)
end

Wizard._StateForTest = function() return state end
Wizard._PriorityProjectionForTest = EbonBuilds.WizardPriorityProjection
Wizard._PriorityStepForTest = function() return prioritiesUI end
