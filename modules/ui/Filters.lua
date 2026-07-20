-- EbonBuilds: modules/ui/Filters.lua
-- Search/filter state and an accessible compact filter bar.

EbonBuilds.Filters = {}

local FAMILIES = { "Tank", "Survivability", "Healer", "Caster DPS", "Melee DPS", "Ranged DPS", "No family" }
local QUALITY_OPTIONS = { { label = "All qualities", quality = nil } }
for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
    QUALITY_OPTIONS[#QUALITY_OPTIONS + 1] = {
        label = EbonBuilds.Quality.LABELS[quality] or tostring(quality),
        quality = quality,
    }
end

local state = { text = "", quality = nil, policy = nil, families = {}, showAllClasses = false, learnedOnly = false, learnedReady = true }
local changeCallbacks = {}
local searchEditBox, searchPlaceholder, qualityDropdown, familyDropdown, policyDropdown, bulkPolicyDropdown
local allClassesToggle, learnedToggle, resultLabel, resultHitFrame
local chipFrame, chipPool = nil, {}
local filterBar, searchContainer, resetButton
local debouncePending = false

local UpdateChips

local function Notify()
    if UpdateChips then UpdateChips() end
    for i = 1, #changeCallbacks do changeCallbacks[i]() end
end

local function ScheduleNotify()
    debouncePending = true
    EbonBuilds.Scheduler.After("filters.notify", 0.12, function()
        if not debouncePending then return end
        debouncePending = false
        Notify()
    end, EbonBuilds.Scheduler.INTERACTIVE, true)
end

function EbonBuilds.Filters.OnChange(fn)
    changeCallbacks[#changeCallbacks + 1] = fn
end

local function FamiliesActive()
    for _ in pairs(state.families) do return true end
    return false
end

local function MatchesFamilies(entry)
    if not next(state.families) then return true end
    local has, hasAnyFamily = {}, false
    for _, fam in ipairs(entry.families or {}) do
        has[fam] = true
        hasAnyFamily = true
    end
    for required in pairs(state.families) do
        if required == "No family" then
            if hasAnyFamily then return false end
        elseif not has[required] then
            return false
        end
    end
    return true
end

local function NormalizeEchoName(name)
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName then
        return EbonBuilds.BuildOverview._NormalizeEchoName(name)
    end
    local stripped = EbonBuilds.Weights and EbonBuilds.Weights.StripQualitySuffix
        and EbonBuilds.Weights.StripQualitySuffix(name) or tostring(name or "")
    return string.lower(stripped)
end

local function GetLearnedSnapshot()
    if not state.learnedOnly then return nil, true end
    local overview = EbonBuilds.BuildOverview
    if not overview or not overview.GetOwnedEchoSets then return nil, false end

    local ok, names, groups, spellIds = pcall(overview.GetOwnedEchoSets)
    if not ok or not names then return nil, false end
    return {
        names = names or {},
        groups = groups or {},
        spellIds = spellIds or {},
    }, true
end

local function EntryIsLearned(entry, snapshot)
    if not snapshot then return true end

    for _, spellId in pairs(entry.spellIds or {}) do
        if snapshot.spellIds[spellId] then return true end
    end
    if entry.spellId and snapshot.spellIds[entry.spellId] then return true end

    for groupId in pairs(entry.groupIds or {}) do
        if snapshot.groups[groupId] then return true end
    end

    if entry.groupId and snapshot.groups[entry.groupId] then return true end

    local normalized = NormalizeEchoName(entry.displayName or entry.sourceName or entry.name)
    return normalized and snapshot.names[normalized] and true or false
end

local function UpdateToggleVisuals()
    if allClassesToggle then
        allClassesToggle:SetText(state.showAllClasses and "All classes: ON" or "All classes")
        EbonBuilds.Theme.SetTabSelected(allClassesToggle, state.showAllClasses)
    end
    if learnedToggle then
        local text
        if state.learnedOnly and not state.learnedReady then
            text = "Learned only: ..."
        elseif state.learnedOnly then
            text = "Learned only: ON"
        else
            text = "Learned only"
        end
        learnedToggle:SetText(text)
        EbonBuilds.Theme.SetTabSelected(learnedToggle, state.learnedOnly)
    end
end

local function PassesFilters(entry, famActive, learnedSnapshot, settings)
    if state.text ~= "" then
        local blob = entry.searchBlob
        if not blob or blob == "" then
            local visible = entry.displayName or entry.sourceName or entry.name or ""
            blob = EbonBuilds.EchoIdentity and EbonBuilds.EchoIdentity.NormalizeSearch
                and EbonBuilds.EchoIdentity.NormalizeSearch(visible) or string.lower(visible)
        end
        if not string.find(blob, state.text, 1, true) then return false end
    end
    if state.quality ~= nil and not (entry.qualities and entry.qualities[state.quality]) then return false end
    if famActive and not MatchesFamilies(entry) then return false end
    if state.learnedOnly and learnedSnapshot and not EntryIsLearned(entry, learnedSnapshot) then return false end
    if state.policy ~= nil and EbonBuilds.EchoPolicy
        and EbonBuilds.EchoPolicy.Get(settings, entry.refKey or entry.name) ~= state.policy then return false end
    return true
end

function EbonBuilds.Filters.Apply(echoList)
    local out, famActive = {}, FamiliesActive()
    local learnedSnapshot, learnedReady = GetLearnedSnapshot()
    local settings = {}
    if EbonBuilds.Scoring and EbonBuilds.Scoring.GetEffectiveSettings and EbonBuildsCharDB then
        settings = EbonBuilds.Scoring.GetEffectiveSettings() or {}
    elseif EbonBuilds.Build and EbonBuilds.Build.DefaultSettings then
        settings = EbonBuilds.Build.DefaultSettings()
    end
    state.learnedReady = learnedReady
    UpdateToggleVisuals()
    for i = 1, #echoList do
        if PassesFilters(echoList[i], famActive, learnedSnapshot, settings) then out[#out + 1] = echoList[i] end
    end
    return out
end

function EbonBuilds.Filters.LearnedOnly()
    return state.learnedOnly
end

-- Regression-test hooks. They do not notify or mutate persistent data.
function EbonBuilds.Filters._SetLearnedOnlyForTest(value)
    state.learnedOnly = value and true or false
end

function EbonBuilds.Filters._EntryIsLearnedForTest(entry, snapshot)
    return EntryIsLearned(entry, snapshot)
end

local function UpdateSearchPlaceholder()
    if not searchPlaceholder or not searchEditBox then return end
    if searchEditBox:HasFocus() or (searchEditBox:GetText() or "") ~= "" then
        searchPlaceholder:Hide()
    else
        searchPlaceholder:Show()
    end
end

local function CreateSearchBox(bar)
    local container = CreateFrame("Frame", nil, bar)
    container:SetSize(182, 24)
    container:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    EbonBuilds.Theme.ApplyInput(container)

    local edit = CreateFrame("EditBox", nil, container)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(edit, "Filters.SearchBox")
    end
    edit:SetPoint("TOPLEFT", container, "TOPLEFT", 7, -3)
    edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -24, 3)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    EbonBuilds.Theme.WireEditBox(edit, container)

    local placeholder = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
    placeholder:SetText("Search echoes...")
    placeholder:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    searchPlaceholder = placeholder

    local clear = CreateFrame("Button", nil, container)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(clear, "Filters.ClearSearch")
    end
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", container, "RIGHT", -2, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(0.72, 0.72, 0.76)
    clear:SetScript("OnEnter", function() x:SetTextColor(1, 0.82, 0) end)
    clear:SetScript("OnLeave", function() x:SetTextColor(0.72, 0.72, 0.76) end)
    clear:SetScript("OnClick", function()
        edit:SetText("")
        edit:ClearFocus()
        UpdateSearchPlaceholder()
    end)
    EbonBuilds.Theme.AttachTooltip(clear, "Clear search", "Remove the current Echo name filter.")

    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        state.text = EbonBuilds.EchoIdentity and EbonBuilds.EchoIdentity.NormalizeSearch
            and EbonBuilds.EchoIdentity.NormalizeSearch(text) or string.lower(text)
        UpdateSearchPlaceholder()
        ScheduleNotify()
    end)
    edit:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
    edit:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
    edit:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)

    searchEditBox = edit
    UpdateSearchPlaceholder()
    return container
end

function EbonBuilds.Filters.ShowAllClasses()
    return state.showAllClasses
end

local function CreateQualityDropdown(bar, leftAnchor)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 150, "All qualities")
    dropdown:SetPoint("LEFT", leftAnchor, "RIGHT", 10, 0)
    dropdown:SetMenuBuilder(function()
        local items = {}
        for _, option in ipairs(QUALITY_OPTIONS) do
            local label, quality = option.label, option.quality
            items[#items + 1] = {
                text = label,
                checked = state.quality == quality,
                func = function()
                    state.quality = quality
                    dropdown:SetText(label)
                    Notify()
                end,
            }
        end
        return items
    end)
    qualityDropdown = dropdown
    return dropdown
end

local function UpdateFamilyLabel()
    if not familyDropdown then return end
    local count = 0
    for _ in pairs(state.families) do count = count + 1 end
    familyDropdown:SetText(count == 0 and "All families" or ("Families (" .. count .. ")"))
    familyDropdown:RefreshMenu()
end

local function CreateFamilyDropdown(bar, leftAnchor)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 150, "All families", { multiSelect = true })
    dropdown:SetPoint("LEFT", leftAnchor, "RIGHT", 10, 0)
    familyDropdown = dropdown
    dropdown:SetMenuBuilder(function()
        local items = {}
        for _, family in ipairs(FAMILIES) do
            local fam = family
            items[#items + 1] = {
                text = fam,
                checked = state.families[fam] and true or false,
                func = function()
                    state.families[fam] = state.families[fam] and nil or true
                    UpdateFamilyLabel()
                    Notify()
                end,
            }
        end
        return items
    end)
    UpdateFamilyLabel()
    return dropdown
end

local function CreatePolicyDropdown(bar)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 138, "All policies", { menuWidth = 230, rowHeight = 28 })
    dropdown:SetPoint("TOPLEFT", bar, "TOPLEFT", 248, -30)
    dropdown:SetMenuBuilder(function()
        local items = {
            {
                text = "All policies",
                checked = state.policy == nil,
                func = function() state.policy = nil; dropdown:SetText("All policies"); Notify() end,
            },
        }
        local api = EbonBuilds.EchoPolicy
        if api then
            for _, policy in ipairs(api.ORDER or {}) do
                local policyKey = policy
                local definition = api.Definition(policyKey)
                items[#items + 1] = {
                    text = definition.label,
                    checked = state.policy == policyKey,
                    color = definition.color,
                    tooltipTitle = definition.label,
                    tooltipBody = definition.description,
                    func = function() state.policy = policyKey; dropdown:SetText(definition.shortLabel or definition.label); Notify() end,
                }
            end
        end
        return items
    end)
    policyDropdown = dropdown
    return dropdown
end

local function CreateBulkPolicyDropdown(bar)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 120, "Set results", { menuWidth = 250, rowHeight = 28 })
    dropdown:SetPoint("TOPLEFT", bar, "TOPLEFT", 394, -30)
    dropdown:SetMenuBuilder(function()
        local items = {}
        local api = EbonBuilds.EchoPolicy
        if not api then return items end
        for _, policy in ipairs(api.ORDER or {}) do
            local policyKey = policy
            local definition = api.Definition(policyKey)
            items[#items + 1] = {
                text = definition.label,
                color = definition.color,
                tooltipTitle = "Apply to visible results",
                tooltipBody = "Stage " .. definition.label .. " for every Echo matching the current filters. Cancel Build editing to discard the bulk change.",
                func = function()
                    local count = EbonBuilds.EchoTable and EbonBuilds.EchoTable.ApplyPolicyToFiltered and EbonBuilds.EchoTable.ApplyPolicyToFiltered(policyKey) or 0
                    dropdown:SetText("Set results")
                    if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                        EbonBuilds.Toast.Show(string.format("%s applied to %d filtered Echo%s", definition.label, count, count == 1 and "" or "es"))
                    end
                end,
            }
        end
        return items
    end)
    bulkPolicyDropdown = dropdown
    EbonBuilds.Theme.AttachTooltip(dropdown._button or dropdown, "Bulk policy", "Apply one policy to every Echo matching the current search, quality, family, class, learned, and policy filters. Changes remain staged until Save.")
    return dropdown
end

local function CreateFilterToggle(bar, text, x, width, onClick, tooltipTitle, tooltipBody)
    local btn = EbonBuilds.Theme.CreateTab(bar, text)
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -30)
    btn:SetScript("OnClick", onClick)
    EbonBuilds.Theme.AttachTooltip(btn, tooltipTitle, tooltipBody)
    return btn
end

local function CreateAllClassesToggle(bar)
    allClassesToggle = CreateFilterToggle(
        bar, "All classes", 0, 108,
        function()
            state.showAllClasses = not state.showAllClasses
            UpdateToggleVisuals()
            Notify()
        end,
        "Show all classes",
        "Include Echoes that are not normally available to the build's selected class."
    )
    return allClassesToggle
end

local function CreateLearnedToggle(bar)
    learnedToggle = CreateFilterToggle(
        bar, "Learned only", 116, 124,
        function()
            state.learnedOnly = not state.learnedOnly
            state.learnedReady = true
            UpdateToggleVisuals()
            Notify()
        end,
        "Hide unlearned Echoes",
        "When enabled, the priorities list shows only Echoes your character has learned. Discovery data is used first, with the Echoes spellbook as a compatibility fallback."
    )
    return learnedToggle
end

local function ChipDefinitionList()
    local out = {}
    if state.quality ~= nil then
        out[#out + 1] = {
            label = EbonBuilds.Quality.LABELS[state.quality] or tostring(state.quality),
            clear = function()
                state.quality = nil
                if qualityDropdown then qualityDropdown:SetText("All qualities") end
            end,
        }
    end
    if state.policy ~= nil and EbonBuilds.EchoPolicy then
        local definition = EbonBuilds.EchoPolicy.Definition(state.policy)
        out[#out + 1] = {
            label = definition.shortLabel or definition.label,
            clear = function()
                state.policy = nil
                if policyDropdown then policyDropdown:SetText("All policies") end
            end,
        }
    end
    for _, family in ipairs(FAMILIES) do
        if state.families[family] then
            local fam = family
            out[#out + 1] = { label = fam, clear = function() state.families[fam] = nil; UpdateFamilyLabel() end }
        end
    end
    if state.showAllClasses then
        out[#out + 1] = { label = "All classes", clear = function() state.showAllClasses = false; UpdateToggleVisuals() end }
    end
    if state.learnedOnly then
        out[#out + 1] = { label = "Learned only", clear = function() state.learnedOnly = false; state.learnedReady = true; UpdateToggleVisuals() end }
    end
    return out
end

UpdateChips = function()
    if not chipFrame then return end
    for _, chip in ipairs(chipPool) do chip:Hide() end
    local defs = ChipDefinitionList()
    local x = 0
    for i, def in ipairs(defs) do
        local chipDef = def
        local chip = chipPool[i]
        if not chip then
            chip = EbonBuilds.Theme.CreateFilterChip(chipFrame, chipDef.label)
            chipPool[i] = chip
        end
        chip._chipLabel = chipDef.label
        chip:SetText(chipDef.label .. "  x")
        chip:SetWidth(math.max(54, 28 + math.min(150, #chipDef.label * 6)))
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", chipFrame, "TOPLEFT", x, 0)
        chip:SetScript("OnClick", function() chipDef.clear(); Notify() end)
        chip:Show()
        x = x + chip:GetWidth() + 5
    end
    if chipFrame._empty then
        if #defs == 0 then chipFrame._empty:Show() else chipFrame._empty:Hide() end
    end
end

local function LayoutMetrics(width)
    width = math.max(520, tonumber(width) or 0)
    local compact = width < 680
    return {
        width = width,
        compact = compact,
        gap = compact and 8 or 10,
        search = compact and 168 or 182,
        quality = compact and 134 or 150,
        family = compact and 134 or 150,
        allClasses = compact and 98 or 108,
        learned = compact and 112 or 124,
        policy = compact and 118 or 138,
        bulk = compact and 106 or 120,
        result = compact and 142 or 150,
    }
end

local function LayoutControls()
    local bar = filterBar
    if not bar or not searchContainer or not qualityDropdown or not familyDropdown then return end
    local metrics = LayoutMetrics(bar:GetWidth())
    local width, gap = metrics.width, metrics.gap

    searchContainer:SetWidth(metrics.search)
    qualityDropdown:SetWidth(metrics.quality)
    familyDropdown:SetWidth(metrics.family)

    searchContainer:ClearAllPoints()
    searchContainer:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    qualityDropdown:ClearAllPoints()
    qualityDropdown:SetPoint("LEFT", searchContainer, "RIGHT", gap, 0)
    familyDropdown:ClearAllPoints()
    familyDropdown:SetPoint("LEFT", qualityDropdown, "RIGHT", gap, 0)
    if resetButton then
        resetButton:ClearAllPoints()
        resetButton:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    end

    allClassesToggle:SetWidth(metrics.allClasses)
    learnedToggle:SetWidth(metrics.learned)
    policyDropdown:SetWidth(metrics.policy)
    bulkPolicyDropdown:SetWidth(metrics.bulk)

    allClassesToggle:ClearAllPoints()
    allClassesToggle:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -30)
    learnedToggle:ClearAllPoints()
    learnedToggle:SetPoint("LEFT", allClassesToggle, "RIGHT", gap, 0)
    policyDropdown:ClearAllPoints()
    policyDropdown:SetPoint("LEFT", learnedToggle, "RIGHT", gap, 0)
    bulkPolicyDropdown:ClearAllPoints()
    bulkPolicyDropdown:SetPoint("LEFT", policyDropdown, "RIGHT", gap, 0)

    local resultWidth = metrics.result
    resultLabel:ClearAllPoints()
    resultLabel:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -33)
    resultLabel:SetWidth(resultWidth)
    resultHitFrame:ClearAllPoints()
    resultHitFrame:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -28)
    resultHitFrame:SetSize(resultWidth + 4, 24)

    if UpdateChips then UpdateChips() end
end

function EbonBuilds.Filters.Reset()
    debouncePending = false
    EbonBuilds.Scheduler.Cancel("filters.notify")
    state.text, state.quality, state.policy, state.families = "", nil, nil, {}
    state.showAllClasses, state.learnedOnly, state.learnedReady = false, false, true
    if searchEditBox then searchEditBox:SetText(""); searchEditBox:ClearFocus() end
    if qualityDropdown then qualityDropdown:SetText("All qualities") end
    if policyDropdown then policyDropdown:SetText("All policies") end
    UpdateFamilyLabel()
    UpdateToggleVisuals()
    UpdateSearchPlaceholder()
    Notify()
end

function EbonBuilds.Filters.SetResultCount(visible, total)
    if not resultLabel then return end
    visible, total = visible or 0, total or 0
    local text
    if visible == total then
        text = total .. " echoes"
    else
        text = visible .. " of " .. total .. " echoes"
    end
    if state.learnedOnly and not state.learnedReady then
        text = text .. " · learned data loading"
    end
    local policySummary
    if EbonBuilds.EchoPolicy and EbonBuilds.Scoring and EbonBuildsCharDB then
        policySummary = EbonBuilds.EchoPolicy.Summary(EbonBuilds.Scoring.GetEffectiveSettings())
        if policySummary.total > 0 then text = text .. " · " .. policySummary.total .. " custom" end
    end
    resultLabel:SetText(text)
    if resultHitFrame then resultHitFrame._policySummary = policySummary end
    if policySummary and policySummary.total >= 30 then
        resultLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
    else
        resultLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    end
end

function EbonBuilds.Filters.Init(parent)
    local bar = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(bar, "Filters.Bar")
    end
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -48)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -48)
    bar:SetHeight(80)
    filterBar = bar

    searchContainer = CreateSearchBox(bar)
    local quality = CreateQualityDropdown(bar, searchContainer)
    CreateFamilyDropdown(bar, quality)
    CreateAllClassesToggle(bar)
    CreateLearnedToggle(bar)
    CreatePolicyDropdown(bar)
    CreateBulkPolicyDropdown(bar)
    UpdateToggleVisuals()

    local resetBtn = EbonBuilds.Theme.CreateButton(bar)
    resetButton = resetBtn
    resetBtn:SetSize(58, 22)
    resetBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", EbonBuilds.Filters.Reset)
    EbonBuilds.Theme.AttachTooltip(resetBtn, "Reset filters", "Show all Echoes for the selected class and clear the search.")

    resultLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultLabel:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -33)
    resultLabel:SetWidth(170)
    resultLabel:SetJustifyH("RIGHT")
    resultLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    resultLabel:SetText("0 echoes")

    resultHitFrame = CreateFrame("Frame", nil, bar)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(resultHitFrame, "Filters.ResultHitFrame")
    end
    resultHitFrame:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -28)
    resultHitFrame:SetSize(174, 24)
    resultHitFrame:EnableMouse(true)
    resultHitFrame:SetScript("OnEnter", function(self)
        local api = EbonBuilds.EchoPolicy
        local summary = self._policySummary
        if not api or not summary then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Configured Echo policies", 1, 0.82, 0)
        GameTooltip:AddLine("Banish on Sight: " .. tostring(summary[api.BANISH_ON_SIGHT] or 0), 1, 0.35, 0.30)
        GameTooltip:AddLine("Banish After Pick: " .. tostring(summary[api.BANISH_AFTER_PICK] or 0), 1, 0.62, 0.24)
        GameTooltip:AddLine("Ignore After Pick: " .. tostring(summary[api.IGNORE_AFTER_PICK] or 0), 0.40, 0.72, 1)
        GameTooltip:AddLine("Never Pick: " .. tostring(summary[api.NEVER_PICK] or 0), 0.96, 0.42, 0.52)
        if (summary.total or 0) >= 30 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Many restrictive policies can cause Autopilot to pause when no eligible Echo remains.", 1, 0.72, 0.20, true)
        end
        GameTooltip:Show()
    end)
    resultHitFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    chipFrame = CreateFrame("Frame", nil, bar)
    chipFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -56)
    chipFrame:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -56)
    chipFrame:SetHeight(20)
    local empty = chipFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("LEFT", chipFrame, "LEFT", 2, 0)
    empty:SetText("No active filters")
    empty:SetTextColor(0.48, 0.50, 0.55, 1)
    chipFrame._empty = empty
    bar:SetScript("OnSizeChanged", LayoutControls)
    LayoutControls()
    UpdateChips()

    return bar
end


function EbonBuilds.Filters.RefreshLayout()
    LayoutControls()
end

EbonBuilds.Filters._LayoutMetricsForTest = LayoutMetrics
