-- EbonBuilds: modules/ui/BuildWizardPriorityStep.lua
-- Grouped, virtualized Echo priority selector for WoW 3.3.5a.
-- One fixed row pool, one authoritative view state, no frame creation in
-- scroll/search/category refresh paths.

EbonBuilds.BuildWizardPriorityStep = {}

local PriorityStep = EbonBuilds.BuildWizardPriorityStep
local Theme = EbonBuilds.Theme
local Draft = EbonBuilds.WizardDraft
local Projection = EbonBuilds.WizardPriorityProjection
local Grouping = EbonBuilds.EchoGrouping
local VirtualList = EbonBuilds.VirtualList
local Evidence = EbonBuilds.BuildWizardEvidence
local Identity = EbonBuilds.EchoIdentity

local ROW_HEIGHT = 38
local ROW_FRAME_HEIGHT = 36
local ROW_TOP_INSET = 2
local ROW_POOL = 16
local NAV_WIDTH = 158
local SUBGROUP_POOL = 8
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local EVIDENCE_WIDTH = 102
local PRIORITY_WIDTH = 88
local INCLUDE_WIDTH = 52

local SORTS = {
    { key = Projection.SORT_RECOMMENDATION, label = "Recommendation" },
    { key = Projection.SORT_NAME, label = "Echo name" },
    { key = Projection.SORT_EVIDENCE, label = "Evidence strength" },
    { key = Projection.SORT_PRIORITY, label = "Your priority" },
    { key = Projection.SORT_INCLUDED, label = "Included first" },
}

local DIAGNOSTICS = {
    { key = Projection.DIAG_UNCLASSIFIED, label = "Needs class.", title = "Needs Classification" },
    { key = Projection.DIAG_UNVERIFIED, label = "Unverified" },
    { key = Projection.DIAG_CONFLICTS, label = "Conflicts" },
    { key = Projection.DIAG_UNAVAILABLE, label = "Unavailable" },
    { key = Projection.DIAG_IMPORTS, label = "Imports" },
}

local NAV_DEFS = {
    { section = "FOCUS", label = "Recommended", view = Projection.VIEW_RECOMMENDED },
    { label = "Included", view = Projection.VIEW_INCLUDED },
    { label = "Modified", view = Projection.VIEW_MODIFIED },
    { label = "Build-changing", view = Projection.VIEW_BUILD_CHANGING },
    { section = "FUNCTION", label = "Damage", view = Projection.VIEW_GROUP, group = Grouping.GROUP_DAMAGE },
    { label = "Survival", view = Projection.VIEW_GROUP, group = Grouping.GROUP_SURVIVAL },
    { label = "Resources", view = Projection.VIEW_GROUP, group = Grouping.GROUP_RESOURCES },
    { label = "Control", view = Projection.VIEW_GROUP, group = Grouping.GROUP_CONTROL },
    { label = "Utility", view = Projection.VIEW_GROUP, group = Grouping.GROUP_UTILITY },
    { label = "Equipment", view = Projection.VIEW_GROUP, group = Grouping.GROUP_EQUIPMENT },
    { label = "Other", view = Projection.VIEW_GROUP, group = Grouping.GROUP_OTHER },
    { section = "DIAGNOSTICS", label = "Diagnostics", view = Projection.VIEW_DIAGNOSTICS },
}

local scheduledRefreshComponent
local scheduledLayoutComponent
local activeComponent

local function LayoutToolbar(component)
    if not component or not component.main or not component.search or not component.scope
        or not component.sortLabel or not component.sort or not component.direction then return end

    local width = tonumber(component.main:GetWidth()) or 0
    if width < 40 then return end

    local compact = width < 390
    local scopeWidth = compact and 62 or (width >= 500 and 76 or 68)
    local sortLabelWidth = compact and 38 or 44
    local sortWidth = compact and 86 or (width >= 500 and 124 or 108)
    local directionWidth = 28
    local gaps = 6 + 6 + 4 + 5
    local fixedWidth = scopeWidth + sortLabelWidth + sortWidth + directionWidth + gaps
    local searchWidth = width - fixedWidth

    local minimumSearchWidth = compact and 96 or 120
    if searchWidth < minimumSearchWidth then
        local deficit = minimumSearchWidth - searchWidth
        sortWidth = math.max(compact and 78 or 92, sortWidth - deficit)
        fixedWidth = scopeWidth + sortLabelWidth + sortWidth + directionWidth + gaps
        searchWidth = math.max(minimumSearchWidth, width - fixedWidth)
    end

    component.search:SetWidth(math.floor(searchWidth))
    component.scope:SetWidth(scopeWidth)
    component.sortLabel:SetWidth(sortLabelWidth)
    component.sort:SetWidth(sortWidth)
    component.direction:SetWidth(directionWidth)
end

local function MakeText(parent, font, width, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if width then text:SetWidth(width) end
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function WipeArray(list)
    for index = #list, 1, -1 do list[index] = nil end
end

local function CurrentViewKey(component)
    local view = component.viewState
    return table.concat({
        tostring(view.activeView),
        tostring(view.activeGroup or 0),
        tostring(view.diagnosticKey or ""),
        tostring(view.activeSubgroup or "ALL"),
        view.searchAllGroups and "G" or "L",
    }, ":")
end

local function SaveScroll(component)
    if not component or not component.viewState or not component.scrollBar then return end
    component.viewState.scrollByView[CurrentViewKey(component)] = math.floor(tonumber(component.scrollBar:GetValue()) or 0)
end

local function RestoreScroll(component)
    local offset = component.viewState.scrollByView[CurrentViewKey(component)] or 0
    component.settingScroll = true
    component.scrollBar:SetValue(offset)
    component.settingScroll = false
end

local function ScheduledRefresh()
    local component = scheduledRefreshComponent
    scheduledRefreshComponent = nil
    if not component or not component.active or not component.draft then return end
    local reset = component.pendingResetScroll == true
    component.pendingResetScroll = false
    component:Refresh(reset)
end

local function ScheduleRefresh(component, delay, resetScroll)
    if not component then return end
    if resetScroll then component.pendingResetScroll = true end
    scheduledRefreshComponent = component
    EbonBuilds.Scheduler.After("buildWizard.priority.rebuild", delay or 0, ScheduledRefresh,
        EbonBuilds.Scheduler.INTERACTIVE, true)
end

local function ScheduledLayout()
    local component = scheduledLayoutComponent
    scheduledLayoutComponent = nil
    if component and component.active then
        LayoutToolbar(component)
        component:UpdateRows()
    end
end

local function ScheduleLayout(component)
    scheduledLayoutComponent = component
    EbonBuilds.Scheduler.After("buildWizard.priority.layout", 0, ScheduledLayout,
        EbonBuilds.Scheduler.INTERACTIVE, true)
end

local function SearchPlaceholder(component)
    local view = component.viewState
    if view.searchAllGroups then return "Search all class Echoes..." end
    if view.activeView == Projection.VIEW_GROUP then
        return "Search " .. Grouping.GetLabel(view.activeGroup) .. " Echoes..."
    end
    if view.activeView == Projection.VIEW_DIAGNOSTICS then return "Search diagnostics..." end
    if view.activeView == Projection.VIEW_INCLUDED then return "Search included Echoes..." end
    if view.activeView == Projection.VIEW_MODIFIED then return "Search modified Echoes..." end
    if view.activeView == Projection.VIEW_BUILD_CHANGING then return "Search build-changing Echoes..." end
    return "Search recommended Echoes..."
end

local function UpdatePlaceholder(component)
    component.placeholder:SetText(SearchPlaceholder(component))
    local text = component.search:GetText() or ""
    if text ~= "" or component.search:HasFocus() then component.placeholder:Hide() else component.placeholder:Show() end
end

local function CurrentTitle(component)
    local view = component.viewState
    if view.searchAllGroups and (view.searchText or "") ~= "" then return "Search Results" end
    if view.activeView == Projection.VIEW_RECOMMENDED then return "Recommended" end
    if view.activeView == Projection.VIEW_INCLUDED then return "Included" end
    if view.activeView == Projection.VIEW_MODIFIED then return "Modified" end
    if view.activeView == Projection.VIEW_BUILD_CHANGING then return "Build-changing" end
    if view.activeView == Projection.VIEW_DIAGNOSTICS then
        for _, diag in ipairs(DIAGNOSTICS) do
            if diag.key == view.diagnosticKey then return "Diagnostics · " .. (diag.title or diag.label) end
        end
        return "Diagnostics"
    end
    return Grouping.GetLabel(view.activeGroup)
end

local function CurrentDescription(component)
    local view = component.viewState
    if view.searchAllGroups and (view.searchText or "") ~= "" then
        return "Matching Echoes from every canonical function group. Each row shows its navigation group."
    end
    if view.activeView == Projection.VIEW_RECOMMENDED then
        return "Community-supported, defensive, avoid, or otherwise suggested Echoes. Player choices never rewrite source evidence."
    end
    if view.activeView == Projection.VIEW_INCLUDED then
        return "Echoes currently included in generated build output."
    end
    if view.activeView == Projection.VIEW_MODIFIED then
        return "Echoes whose priority or inclusion differs from the original suggestion."
    end
    if view.activeView == Projection.VIEW_BUILD_CHANGING then
        return "Derived view of duplication, unlock, cooldown, resource, triggered-cast, and stacking mechanics."
    end
    if view.activeView == Projection.VIEW_DIAGNOSTICS then
        if view.diagnosticKey == Projection.DIAG_UNCLASSIFIED then return "Available Echoes with missing or incomplete mechanical classification." end
        if view.diagnosticKey == Projection.DIAG_UNVERIFIED then return "Echoes whose class availability cannot be verified. These rows are read-only." end
        if view.diagnosticKey == Projection.DIAG_CONFLICTS then return "Runtime availability conflicts with bundled identity data. Runtime-compatible rows remain editable." end
        if view.diagnosticKey == Projection.DIAG_UNAVAILABLE then return "Known Echoes explicitly unavailable to the selected class. These rows are read-only." end
        return "Imported recommendation references that could not be mapped safely to a canonical refKey."
    end
    return Grouping.GetDescription(view.activeGroup)
end

local function SetNavSelection(component)
    local view = component.viewState
    for _, nav in ipairs(component.navButtons) do
        local def = nav.definition
        local selected = def.view == view.activeView
        if def.view == Projection.VIEW_GROUP then selected = selected and def.group == view.activeGroup end
        Theme.SetTabSelected(nav.button, selected)
    end
end

local function CountForNav(component, def)
    local counts = Projection.GetCounts(component.model) or {}
    local membership = Projection.GetMembership(component.model)
    if def.view == Projection.VIEW_RECOMMENDED then return tostring(counts.recommended or 0) end
    if def.view == Projection.VIEW_INCLUDED then return tostring(counts.included or 0) end
    if def.view == Projection.VIEW_MODIFIED then return tostring(counts.modified or 0) end
    if def.view == Projection.VIEW_BUILD_CHANGING then return tostring(counts.buildChanging or 0) end
    if def.view == Projection.VIEW_DIAGNOSTICS then return tostring(counts.diagnostics or 0) end
    if def.view == Projection.VIEW_GROUP and membership then
        local total = membership.groupCounts[def.group] or 0
        local included = component.model.groupIncluded and component.model.groupIncluded[def.group] or 0
        return tostring(included) .. "/" .. tostring(total)
    end
    return "0"
end

local function UpdateNavCounts(component)
    for _, nav in ipairs(component.navButtons) do nav.count:SetText(CountForNav(component, nav.definition)) end
end

local function DiagnosticCount(component, key)
    local counts = Projection.GetCounts(component.model) or {}
    if key == Projection.DIAG_UNCLASSIFIED then return counts.unclassified or 0 end
    if key == Projection.DIAG_UNVERIFIED then return counts.unverified or 0 end
    if key == Projection.DIAG_CONFLICTS then return counts.conflicts or 0 end
    if key == Projection.DIAG_UNAVAILABLE then return counts.unavailable or 0 end
    if key == Projection.DIAG_IMPORTS then return counts.imports or 0 end
    return 0
end

local function SubgroupCount(component, subgroupKey)
    local membership = Projection.GetMembership(component.model)
    if not membership then return 0 end
    local source = membership.canonical[component.viewState.activeGroup] or {}
    if subgroupKey == Grouping.SUBGROUP_ALL then return #source end
    local count = 0
    for index = 1, #source do
        local entry = EbonBuilds.EchoProjection.GetAnyEntry(component.classToken, source[index])
        if Grouping.MatchesSubgroup(entry, component.viewState.activeGroup, subgroupKey) then count = count + 1 end
    end
    return count
end

local function UpdateSubgroups(component)
    local view = component.viewState
    local definitions = component.subgroupDefinitions
    WipeArray(definitions)

    if view.activeView == Projection.VIEW_GROUP then
        local source = Grouping.GetSubgroups(view.activeGroup)
        for _, subgroup in ipairs(source) do
            local count = SubgroupCount(component, subgroup.key)
            if subgroup.key == Grouping.SUBGROUP_ALL or count > 0 then
                definitions[#definitions + 1] = { key = subgroup.key, label = subgroup.label, count = count, diagnostic = false }
            end
        end
    elseif view.activeView == Projection.VIEW_DIAGNOSTICS then
        for _, diag in ipairs(DIAGNOSTICS) do
            definitions[#definitions + 1] = { key = diag.key, label = diag.label, count = DiagnosticCount(component, diag.key), diagnostic = true }
        end
    else
        definitions[1] = { key = "ALL", label = "All", count = #(view.activeKeys or {}), diagnostic = false }
    end

    local visible = math.min(#definitions, SUBGROUP_POOL)
    local availableWidth = math.max(360, (component.subgroupBar:GetWidth() or 560) - 2)
    local buttonWidth = math.max(62, math.min(96, math.floor((availableWidth - math.max(0, visible - 1) * 4) / math.max(1, visible))))
    for index = 1, SUBGROUP_POOL do
        local button = component.subgroupButtons[index]
        local def = definitions[index]
        if def then
            button.definition = def
            button:SetWidth(buttonWidth)
            button:ClearAllPoints()
            button:SetPoint("LEFT", component.subgroupBar, "LEFT", (index - 1) * (buttonWidth + 4), 0)
            button:SetText(def.label .. (def.count > 0 and (" " .. tostring(def.count)) or ""))
            local selected
            if def.diagnostic then selected = view.diagnosticKey == def.key
            else selected = view.activeSubgroup == def.key end
            Theme.SetTabSelected(button, selected)
            button:Show()
        else
            button.definition = nil
            button:Hide()
        end
    end
end

local function SetView(component, definition)
    if not component or not definition then return end
    SaveScroll(component)
    local view = component.viewState
    view.activeView = definition.view
    if definition.view == Projection.VIEW_GROUP then view.activeGroup = definition.group end
    if definition.view == Projection.VIEW_DIAGNOSTICS and not view.diagnosticKey then
        view.diagnosticKey = Projection.DIAG_UNCLASSIFIED
    end
    view.activeSubgroup = Grouping.SUBGROUP_ALL
    UpdatePlaceholder(component)
    RestoreScroll(component)
    component:Refresh(false)
end

local function Nav_OnClick(self)
    local component = self.ownerComponent
    if component and self.definition then SetView(component, self.definition) end
end

local function Subgroup_OnClick(self)
    local component = self.ownerComponent
    local def = self.definition
    if not component or not def then return end
    SaveScroll(component)
    if def.diagnostic then
        component.viewState.diagnosticKey = def.key
    else
        component.viewState.activeSubgroup = def.key
    end
    RestoreScroll(component)
    component:Refresh(false)
end

local function Search_OnTextChanged(self)
    local component = self.ownerComponent
    if not component or component.settingSearchText then return end
    local text = string.sub(self:GetText() or "", 1, 64)
    if self:GetText() ~= text then
        component.settingSearchText = true
        self:SetText(text)
        component.settingSearchText = false
    end
    component.viewState.searchText = text
    component.viewState.scrollByView[CurrentViewKey(component)] = 0
    UpdatePlaceholder(component)
    ScheduleRefresh(component, 0.12, true)
end

local function SearchFocusGained(self)
    local component = self.ownerComponent
    if component then UpdatePlaceholder(component) end
end

local function SearchFocusLost(self)
    local component = self.ownerComponent
    if component then UpdatePlaceholder(component) end
end

local function Scope_OnClick(self)
    local component = self.ownerComponent
    if not component then return end
    SaveScroll(component)
    component.viewState.searchAllGroups = not component.viewState.searchAllGroups
    self:SetText(component.viewState.searchAllGroups and "All groups" or "This view")
    UpdatePlaceholder(component)
    RestoreScroll(component)
    component:Refresh(true)
end

local function Direction_OnClick(self)
    local component = self.ownerComponent
    if not component then return end
    component.viewState.sortDescending = not component.viewState.sortDescending
    self:SetText(component.viewState.sortDescending and "v" or "^")
    component:Refresh(false)
end

local function CurrentSortLabel(component)
    for _, sort in ipairs(SORTS) do if sort.key == component.viewState.sortKey then return sort.label end end
    return "Recommendation"
end

local function SortMenuBuilder(component)
    local items = component.sortMenuItems
    WipeArray(items)
    for index, sort in ipairs(SORTS) do
        local item = component.sortMenuDefinitions[index]
        if not item then
            item = { text = "", checked = false, func = nil }
            component.sortMenuDefinitions[index] = item
        end
        item.text = sort.label
        item.checked = component.viewState.sortKey == sort.key
        item.sortKey = sort.key
        item.ownerComponent = component
        item.func = item.func or function()
            local owner = item.ownerComponent
            if not owner then return end
            owner.viewState.sortKey = item.sortKey
            owner.sort:SetText(CurrentSortLabel(owner))
            owner:Refresh(false)
        end
        items[#items + 1] = item
    end
    return items
end

local function RowValid(row)
    local component = row and row.ownerComponent
    return component and not row.isBinding and row.bindingGeneration == component.viewState.visibleGeneration
end

local function RowInspect_OnEnter(self)
    local row = self.ownerRow
    if not RowValid(row) then return end
    local component = row.ownerComponent
    local key = row.refKey
    if Projection.IsUnresolvedKey(key) then
        local unresolved = Projection.GetUnresolved(component.model, component.draft, key)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(unresolved and (unresolved.rawName or "Unresolved import") or "Unresolved import", 1, 0.82, 0)
        GameTooltip:AddLine("No canonical Echo reference could be established. The record is quarantined and cannot enter build output.", 1, 1, 1, true)
        if unresolved and unresolved.rawSpellId then GameTooltip:AddLine("Raw spell ID: " .. tostring(unresolved.rawSpellId), 0.72, 0.82, 0.95) end
        if unresolved and unresolved.reason then GameTooltip:AddLine("Reason: " .. tostring(unresolved.reason), 1, 0.55, 0.35) end
        GameTooltip:Show()
        return
    end
    local echo = component.draft.echoes[key]
    local entry = Projection.GetEntry(component.model, component.draft, key)
    local item, kind
    if component.snapshotLookup then item, kind = component.snapshotLookup(key) end
    if component.options.showEchoTooltip then
        component.options.showEchoTooltip(self, key, (echo and echo.spellId) or (entry and entry.spellId), item, kind)
    end
end

local function Row_OnLeave() GameTooltip:Hide() end

local function RowEvidence_OnEnter(self)
    local row = self.ownerRow
    if not RowValid(row) then return end
    local component = row.ownerComponent
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Community evidence", 1, 0.82, 0)
    local item, kind
    if component.snapshotLookup and not Projection.IsUnresolvedKey(row.refKey) then item, kind = component.snapshotLookup(row.refKey) end
    if Evidence then Evidence.AddTooltip(item, kind) end
    if not item then GameTooltip:AddLine("No trusted community evidence is attached to this Echo.", 0.8, 0.8, 0.82, true) end
    GameTooltip:Show()
end

local function SetWeightTextColor(text, weight, active)
    if not text then return end
    weight = tonumber(weight) or 0
    if not active then
        text:SetTextColor(0.52, 0.52, 0.58, 1)
    elseif weight > 0 then
        text:SetTextColor(0.35, 0.95, 0.48, 1)
    elseif weight < 0 then
        text:SetTextColor(1, 0.42, 0.32, 1)
    else
        text:SetTextColor(0.62, 0.62, 0.68, 1)
    end
end

local function RowPriority_OnEnter(self)
    local row = self.ownerRow
    if not RowValid(row) then return end
    local component = row.ownerComponent
    local echo = component.draft and component.draft.echoes[row.refKey]
    if not echo then return end
    local weight = Draft.WeightFor(component.draft, echo.importance)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if echo.importance == "Avoid" then
        GameTooltip:AddLine("Avoid · policy only", 1, 0.82, 0)
        GameTooltip:AddLine("Marks this Echo for the Never Pick policy and keeps its weight at 0. Pressing No resets it to Neutral +0 and removes the policy.", 1.00, 0.52, 0.36, true)
    else
        GameTooltip:AddLine("Priority weight", 1, 0.82, 0)
        GameTooltip:AddLine((echo.importance or "Neutral") .. " applies " .. Draft.FormatWeight(weight) .. " weight while Use is Yes.", 0.82, 0.82, 0.86, true)
        GameTooltip:AddLine("Positive priorities automatically enable the Echo. Choosing Neutral disables it.", 0.62, 0.72, 0.88, true)
    end
    GameTooltip:Show()
end

local function RowInclude_OnEnter(self)
    local row = self.ownerRow
    if not RowValid(row) then return end
    local component = row.ownerComponent
    local echo = component.draft and component.draft.echoes[row.refKey]
    if not echo then return end
    local weight = Draft.WeightFor(component.draft, echo.importance)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Use this Echo", 1, 0.82, 0)
    if echo.importance == "Avoid" then
        if echo.included then
            GameTooltip:AddLine("Click No to reset this Echo to Neutral +0 and remove its Never Pick policy.", 1.00, 0.52, 0.36, true)
        else
            GameTooltip:AddLine("Click Yes to include it while keeping Avoid as a policy-only 0-weight state.", 1.00, 0.52, 0.36, true)
        end
    elseif echo.included then
        GameTooltip:AddLine("Active build weight: " .. Draft.FormatWeight(weight) .. ". Click No to remove it and reset priority to Neutral +0.", 0.82, 0.82, 0.86, true)
    elseif weight == 0 then
        local defaultWeight = Draft.WeightFor(component.draft, Draft.DEFAULT_INCLUDED_IMPORTANCE)
        GameTooltip:AddLine("Clicking Yes will include this Echo and automatically assign " .. Draft.DEFAULT_INCLUDED_IMPORTANCE .. " (" .. Draft.FormatWeight(defaultWeight) .. ").", 0.82, 0.82, 0.86, true)
    else
        GameTooltip:AddLine("Clicking Yes will reactivate its saved " .. Draft.FormatWeight(weight) .. " priority weight.", 0.82, 0.82, 0.86, true)
    end
    GameTooltip:Show()
end

local function ClosePriorityPopup(component)
    if not component or not component.priorityPopup then return end
    component.priorityPopup.targetRefKey = nil
    component.priorityPopup:Hide()
end

local function RowPriority_OnClick(self)
    local row = self.ownerRow
    if not RowValid(row) then return end
    local component = row.ownerComponent
    if row.readOnly then return end
    local popup = component.priorityPopup
    if popup:IsShown() and popup.targetRefKey == row.refKey then ClosePriorityPopup(component); return end
    popup.targetRefKey = row.refKey
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", row.priority, "BOTTOMRIGHT", 0, -3)
    popup:Show()
end

local function RowInclude_OnClick(self)
    local row = self.ownerRow
    if not RowValid(row) or row.readOnly then return end
    local component = row.ownerComponent
    local echo = component.draft.echoes[row.refKey]
    if not echo then return end
    if Draft.SetIncluded(component.draft, row.refKey, not echo.included) then
        component:Refresh(false)
        if component.options.onDraftChanged then component.options.onDraftChanged(row.refKey, "included") end
    end
end

local function PopupImportance_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.importanceKey or "Priority", 1, 0.82, 0)
    local component = self.ownerComponent
    local weight = component and component.draft and Draft.WeightFor(component.draft, self.importanceKey) or 0
    if self.importanceKey == "Avoid" then
        GameTooltip:AddLine("Policy only · Weight: 0", 1.00, 0.52, 0.36)
        GameTooltip:AddLine("Applies Never Pick with weight 0. Pressing No later resets the Echo to Neutral +0 and removes that policy.", 0.82, 0.82, 0.86, true)
    else
        GameTooltip:AddLine("Weight: " .. Draft.FormatWeight(weight), 0.82, 0.82, 0.86)
    end
    GameTooltip:Show()
end

local function PopupImportance_OnLeave()
    GameTooltip:Hide()
end

local function PopupImportance_OnClick(self)
    local component = self.ownerComponent
    local popup = component and component.priorityPopup
    local refKey = popup and popup.targetRefKey
    if not component or not refKey then return end
    ClosePriorityPopup(component)
    if Draft.SetImportanceOnly(component.draft, refKey, self.importanceKey) then
        component:Refresh(false)
        if component.options.onDraftChanged then component.options.onDraftChanged(refKey, "importance") end
    end
end

local function Popup_OnShow(self)
    local component = self.ownerComponent
    if not component then return end
    if self.dismiss then self.dismiss:Show() end
    self:Raise()
    local echo = self.targetRefKey and component.draft and component.draft.echoes[self.targetRefKey]
    local current = echo and echo.importance
    for _, button in ipairs(self.buttons) do
        local selected = button.importanceKey == current
        local weight = Draft.WeightFor(component.draft, button.importanceKey)
        Theme.SetTabSelected(button, selected)
        if button._weightText then
            button._weightText:SetText(button.importanceKey == "Avoid" and "Policy · 0" or Draft.FormatWeight(weight))
            SetWeightTextColor(button._weightText, weight, true)
            if button.importanceKey == "Avoid" then
                button._weightText:SetTextColor(1.00, 0.52, 0.36, 1)
            end
        end
        local label = button:GetFontString()
        if label then
            if selected then label:SetTextColor(1, 0.90, 0.35)
            else label:SetTextColor(0.86, 0.86, 0.90) end
        end
    end
end

local function Popup_OnHide(self)
    local component = self.ownerComponent
    self.targetRefKey = nil
    if self.dismiss then self.dismiss:Hide() end
    if component and component.rows and Theme.ResetButtonVisual then
        for index = 1, #component.rows do
            Theme.ResetButtonVisual(component.rows[index].priority)
            Theme.ResetButtonVisual(component.rows[index].include)
        end
    end
end

local function PopupDismiss_OnClick(self)
    local component = self and self.ownerComponent
    if component then ClosePriorityPopup(component) end
end

local function CreatePriorityPopup(component)
    -- Full-screen click catcher sits below the popup, so clicks outside close
    -- it while the popup and its option buttons remain fully interactive.
    local dismiss = CreateFrame("Button", "EbonBuildsGroupedPriorityDismiss", UIParent)
    dismiss:SetAllPoints(UIParent)
    dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
    dismiss:SetFrameLevel(999)
    dismiss:EnableMouse(true)
    dismiss:RegisterForClicks("AnyUp")
    dismiss.ownerComponent = component
    dismiss:SetScript("OnClick", PopupDismiss_OnClick)
    dismiss:Hide()

    local popup = CreateFrame("Frame", "EbonBuildsGroupedPriorityPopup", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(1001)
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetSize(202, 172)
    Theme.ApplyPanel(popup)
    popup.ownerComponent = component
    popup.dismiss = dismiss
    popup.buttons = {}
    popup:Hide()

    local heading = MakeText(popup, "GameFontNormalSmall")
    heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
    heading:SetText("Choose priority")
    heading:SetPoint("RIGHT", popup, "RIGHT", -28, 0)
    local close = Theme.CreateButton(popup)
    close:SetSize(20, 18)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -5)
    close:SetText("x")
    close.ownerComponent = component
    close:SetFrameLevel(popup:GetFrameLevel() + 3)
    close:RegisterForClicks("LeftButtonUp")
    close:SetScript("OnClick", PopupDismiss_OnClick)

    for index, importance in ipairs(Draft.IMPORTANCE) do
        local button = Theme.CreateButton(popup)
        button:SetText(importance == "Avoid" and "Avoid (policy)" or importance)
        button:SetSize(188, 22)
        button:SetPoint("TOPLEFT", popup, "TOPLEFT", 7, -30 - (index - 1) * 25)
        local label = button:GetFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 8, 0)
            label:SetPoint("RIGHT", button, "RIGHT", -64, 0)
            label:SetJustifyH("LEFT")
            label:SetTextColor(0.88, 0.88, 0.92)
        end
        local weightText = MakeText(button, "GameFontHighlightSmall", 54, "RIGHT")
        weightText:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button._weightText = weightText
        button.importanceKey = importance
        button.ownerComponent = component
        button:SetFrameLevel(popup:GetFrameLevel() + 2)
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", PopupImportance_OnClick)
        button:SetScript("OnEnter", PopupImportance_OnEnter)
        button:SetScript("OnLeave", PopupImportance_OnLeave)
        popup.buttons[index] = button
    end
    popup:SetScript("OnShow", Popup_OnShow)
    popup:SetScript("OnHide", Popup_OnHide)
    return popup
end

local function CreateRow(component, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_FRAME_HEIGHT)
    Theme.ApplyPanel(row)
    row.ownerComponent = component

    local inspect = CreateFrame("Button", nil, row)
    inspect:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    inspect:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -258, 1)
    inspect.ownerRow = row
    local icon = inspect:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", inspect, "LEFT", 5, 0)
    local name = MakeText(inspect, "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 7, -1)
    name:SetPoint("RIGHT", inspect, "RIGHT", -3, 0)
    local meta = MakeText(inspect, "GameFontDisableSmall")
    meta:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 7, 1)
    meta:SetPoint("RIGHT", inspect, "RIGHT", -3, 0)

    local evidence = CreateFrame("Button", nil, row)
    evidence:SetSize(EVIDENCE_WIDTH, 24)
    evidence:SetPoint("RIGHT", row, "RIGHT", -149, 0)
    evidence.ownerRow = row
    local evidenceText = MakeText(evidence, "GameFontHighlightSmall", EVIDENCE_WIDTH, "CENTER")
    evidenceText:SetAllPoints(evidence)
    evidenceText:SetTextColor(0.45, 0.82, 1, 1)

    local priority = Theme.CreateButton(row)
    priority:SetSize(PRIORITY_WIDTH, 22)
    priority:SetPoint("RIGHT", row, "RIGHT", -(INCLUDE_WIDTH + 11), 0)
    priority.ownerRow = row
    local priorityLabel = priority:GetFontString()
    if priorityLabel then
        priorityLabel:ClearAllPoints()
        priorityLabel:SetPoint("LEFT", priority, "LEFT", 5, 0)
        priorityLabel:SetPoint("RIGHT", priority, "RIGHT", -29, 0)
        priorityLabel:SetJustifyH("LEFT")
    end
    local priorityWeight = MakeText(priority, "GameFontHighlightSmall", 26, "RIGHT")
    priorityWeight:SetPoint("RIGHT", priority, "RIGHT", -5, 0)
    local include = Theme.CreateButton(row)
    include:SetSize(INCLUDE_WIDTH, 22)
    include:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    include.ownerRow = row

    inspect:SetScript("OnEnter", RowInspect_OnEnter)
    inspect:SetScript("OnLeave", Row_OnLeave)
    evidence:SetScript("OnEnter", RowEvidence_OnEnter)
    evidence:SetScript("OnLeave", Row_OnLeave)
    priority:SetScript("OnClick", RowPriority_OnClick)
    priority:SetScript("OnEnter", RowPriority_OnEnter)
    priority:SetScript("OnLeave", Row_OnLeave)
    include:SetScript("OnClick", RowInclude_OnClick)
    include:SetScript("OnEnter", RowInclude_OnEnter)
    include:SetScript("OnLeave", Row_OnLeave)

    row.inspect, row.icon, row.name, row.meta = inspect, icon, name, meta
    row.evidence, row.evidenceText = evidence, evidenceText
    row.priority, row.priorityWeight, row.include = priority, priorityWeight, include
    return row
end

local function ResetRow(row)
    local owner = GameTooltip:GetOwner()
    if owner == row.inspect or owner == row.evidence or owner == row.priority or owner == row.include then GameTooltip:Hide() end
    if row.priorityWeight then row.priorityWeight:SetText("") end
    row.refKey = nil
    row.bindingGeneration = 0
    row.readOnly = true
    row:Hide()
end

local function SetRowInteractive(row, interactive)
    if interactive then
        row.priority:Enable()
        row.include:Enable()
    else
        row.priority:Disable()
        row.include:Disable()
    end
end

local function BindRow(component, row, key, poolIndex)
    row.isBinding = true
    row.inspect:EnableMouse(false)
    row.evidence:EnableMouse(false)
    row.priority:EnableMouse(false)
    row.include:EnableMouse(false)
    local tooltipOwner = GameTooltip:GetOwner()
    if tooltipOwner == row.inspect or tooltipOwner == row.evidence or tooltipOwner == row.priority or tooltipOwner == row.include then GameTooltip:Hide() end

    row.refKey = key
    row.bindingGeneration = component.viewState.visibleGeneration
    row.readOnly = Projection.IsReadOnlyKey(component.model, component.draft, key)

    if Projection.IsUnresolvedKey(key) then
        local unresolved = Projection.GetUnresolved(component.model, component.draft, key)
        row.icon:SetTexture(QUESTION_ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name:SetText(unresolved and (unresolved.rawName or ("Spell " .. tostring(unresolved.rawSpellId or "?"))) or "Unresolved import")
        row.meta:SetText("Unresolved import · " .. tostring(unresolved and unresolved.reason or "NO_CANONICAL_REFERENCE"))
        row.evidenceText:SetText("Quarantined")
        row.priority:SetText("N/A")
        row.priorityWeight:SetText("")
        row.include:SetText("No")
        Theme.ClearButtonAccent(row.include)
    else
        local entry = Projection.GetEntry(component.model, component.draft, key)
        local echo = component.draft.echoes[key]
        local quality, spellId = 0, entry and entry.spellId
        if component.options.setEchoIcon then
            quality, spellId = component.options.setEchoIcon(row.icon, key, (echo and echo.spellId) or spellId)
        else
            row.icon:SetTexture((entry and entry.icon) or QUESTION_ICON)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            quality = entry and entry.quality or 0
        end
        local name = (entry and entry.displayName) or (echo and echo.name) or key
        if component.options.visibleName then name = component.options.visibleName(name) end
        if EbonBuilds.Quality and EbonBuilds.Quality.Colorize then name = EbonBuilds.Quality.Colorize(name, quality) end
        row.name:SetText(name)
        local meta = Grouping.RowMeta(entry, 3)
        local provenance = Projection.GetProvenance(component.model, key)
        if provenance == Grouping.PROVENANCE_STALE_INFERRED then meta = meta .. " · stale data"
        elseif provenance == Grouping.PROVENANCE_UNKNOWN then meta = meta .. " · unclassified" end
        if entry and entry.disambiguator and string.find(meta, entry.disambiguator, 1, true) == nil then
            meta = meta .. " · " .. entry.disambiguator
        end
        row.meta:SetText(meta)
        local item, kind
        if component.snapshotLookup then item, kind = component.snapshotLookup(key) end
        row.evidenceText:SetText(Evidence and Evidence.CompactText(item, kind) or "No evidence")
        local importance = echo and (echo.importance or "Neutral") or "Neutral"
        local weight = echo and Draft.WeightFor(component.draft, importance) or 0
        row.priority:SetText(echo and importance or "N/A")
        row.priorityWeight:SetText(echo and Draft.FormatWeight(weight) or "")
        SetWeightTextColor(row.priorityWeight, weight, echo and echo.included)
        row.include:SetText(echo and (echo.included and "Yes" or "No") or "N/A")
        if echo and echo.included then Theme.SetButtonAccent(row.include, "good") else Theme.ClearButtonAccent(row.include) end
    end

    SetRowInteractive(row, not row.readOnly)
    -- Recycled buttons can retain hover/down colors if a popup intercepted
    -- OnLeave. Normalize both controls after their new state is fully bound.
    if Theme.ResetButtonVisual then
        Theme.ResetButtonVisual(row.priority)
        Theme.ResetButtonVisual(row.include)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", component.viewport, "TOPLEFT", 0, -ROW_TOP_INSET - (poolIndex - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", component.viewport, "RIGHT", -18, 0)
    row:Show()

    row.inspect:EnableMouse(true)
    row.evidence:EnableMouse(true)
    row.priority:EnableMouse(true)
    row.include:EnableMouse(true)
    row.isBinding = false
end

local function Scroll_OnValueChanged(self, value)
    local component = self.ownerComponent
    if not component or component.settingScroll then return end
    local offset = math.floor((tonumber(value) or 0) + 0.5)
    component.viewState.scrollByView[CurrentViewKey(component)] = offset
    ClosePriorityPopup(component)
    component:UpdateRows()
end

local function EmptyAction_OnClick(self)
    local component = self.ownerComponent
    if not component then return end
    if (component.viewState.outsideGroupMatches or 0) > 0 then
        component.viewState.searchAllGroups = true
        component.scope:SetText("All groups")
        component:Refresh(true)
    else
        SetView(component, { view = Projection.VIEW_GROUP, group = Grouping.GROUP_DAMAGE })
    end
end

function PriorityStep.Create(parent, options)
    local component = setmetatable({
        options = options or {},
        active = false,
        draft = nil,
        classToken = nil,
        snapshotLookup = nil,
        model = Projection.NewModel(),
        viewState = Projection.NewViewState(),
        navButtons = {}, subgroupButtons = {}, subgroupDefinitions = {},
        sortMenuItems = {}, sortMenuDefinitions = {},
    }, { __index = PriorityStep })

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    component.frame = frame

    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
    rail:SetWidth(NAV_WIDTH)
    Theme.ApplyPanel(rail)
    component.rail = rail

    local y = -8
    local sectionLabel
    for index, def in ipairs(NAV_DEFS) do
        if def.section then
            sectionLabel = MakeText(rail, "GameFontDisableSmall", NAV_WIDTH - 16, "LEFT")
            sectionLabel:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, y)
            sectionLabel:SetText(def.section)
            sectionLabel:SetTextColor(0.55, 0.58, 0.66, 1)
            y = y - 18
        end
        local button = Theme.CreateTab(rail, def.label)
        button:SetSize(NAV_WIDTH - 12, 24)
        button:SetPoint("TOPLEFT", rail, "TOPLEFT", 6, y)
        local buttonLabel = button:GetFontString()
        if buttonLabel then
            buttonLabel:ClearAllPoints()
            buttonLabel:SetPoint("LEFT", button, "LEFT", 8, 0)
            buttonLabel:SetPoint("RIGHT", button, "RIGHT", -57, 0)
            buttonLabel:SetJustifyH("LEFT")
        end
        button.ownerComponent = component
        button.definition = def
        button:SetScript("OnClick", Nav_OnClick)
        local count = MakeText(button, "GameFontDisableSmall", 48, "RIGHT")
        count:SetPoint("RIGHT", button, "RIGHT", -7, 0)
        count:SetText("0")
        component.navButtons[index] = { button = button, count = count, definition = def }
        y = y - 26
        if index == 4 or index == 11 then y = y - 5 end
    end

    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", rail, "TOPRIGHT", 8, 0)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
    component.main = main

    local title = MakeText(main, "GameFontNormal")
    title:SetPoint("TOPLEFT", main, "TOPLEFT", 2, -2)
    title:SetPoint("RIGHT", main, "RIGHT", -222, 0)
    component.title = title
    local description = MakeText(main, "GameFontDisableSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    description:SetPoint("RIGHT", main, "RIGHT", -2, 0)
    description:SetHeight(32)
    description:SetJustifyV("TOP")
    component.description = description

    local search = CreateFrame("EditBox", nil, main)
    search:SetSize(180, 24)
    search:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -56)
    search:SetAutoFocus(false)
    search:SetFontObject("ChatFontNormal")
    search:SetTextInsets(7, 7, 0, 0)
    search.ownerComponent = component
    Theme.ApplyInput(search)
    Theme.WireEditBox(search, search)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", SearchFocusGained)
    search:SetScript("OnEditFocusLost", SearchFocusLost)
    search:SetScript("OnTextChanged", Search_OnTextChanged)
    component.search = search

    local placeholder = MakeText(search, "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    component.placeholder = placeholder

    local scope = Theme.CreateButton(main)
    scope:SetSize(76, 24)
    scope:SetPoint("LEFT", search, "RIGHT", 6, 0)
    scope:SetText("All groups")
    scope.ownerComponent = component
    scope:SetScript("OnClick", Scope_OnClick)
    Theme.AttachTooltip(scope, "Search scope", "Switch between the active view and every canonical function group.")
    component.scope = scope

    local sortLabel = MakeText(main, "GameFontNormalSmall", 44, "RIGHT")
    sortLabel:SetPoint("LEFT", scope, "RIGHT", 6, 0)
    sortLabel:SetText("Sort by")
    sortLabel:SetTextColor(unpack(Theme.ACCENT_GOLD))
    component.sortLabel = sortLabel

    local sort = Theme.CreateDropdown(main, 124, "Recommendation")
    sort:SetPoint("LEFT", sortLabel, "RIGHT", 4, 0)
    sort:SetMenuBuilder(function() return SortMenuBuilder(component) end)
    component.sort = sort

    local direction = Theme.CreateButton(main)
    direction:SetSize(28, 24)
    direction:SetPoint("LEFT", sort, "RIGHT", 5, 0)
    direction:SetText("v")
    direction.ownerComponent = component
    direction:SetScript("OnClick", Direction_OnClick)
    Theme.AttachTooltip(direction, "Sort direction", "Reverse the active Echo sort direction.")
    component.direction = direction

    local count = MakeText(main, "GameFontDisableSmall", 215, "RIGHT")
    count:SetPoint("TOPRIGHT", main, "TOPRIGHT", -1, -3)
    component.count = count

    local subgroupBar = CreateFrame("Frame", nil, main)
    subgroupBar:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    subgroupBar:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -86)
    subgroupBar:SetHeight(24)
    component.subgroupBar = subgroupBar
    for index = 1, SUBGROUP_POOL do
        local button = Theme.CreateTab(subgroupBar, "")
        button:SetHeight(22)
        button.ownerComponent = component
        button:SetScript("OnClick", Subgroup_OnClick)
        component.subgroupButtons[index] = button
    end

    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT", subgroupBar, "BOTTOMLEFT", 0, -5)
    header:SetPoint("TOPRIGHT", main, "TOPRIGHT", -18, -115)
    header:SetHeight(21)
    Theme.ApplyPanel(header)
    local hEcho = MakeText(header, "GameFontNormalSmall")
    hEcho:SetPoint("LEFT", header, "LEFT", 8, 0)
    hEcho:SetText("Echo")
    local hEvidence = MakeText(header, "GameFontNormalSmall", EVIDENCE_WIDTH, "CENTER")
    hEvidence:SetPoint("RIGHT", header, "RIGHT", -149, 0)
    hEvidence:SetText("Evidence")
    local hPriority = MakeText(header, "GameFontNormalSmall", PRIORITY_WIDTH, "CENTER")
    hPriority:SetPoint("RIGHT", header, "RIGHT", -(INCLUDE_WIDTH + 11), 0)
    hPriority:SetText("Priority")
    local hEWL = MakeText(header, "GameFontNormalSmall", INCLUDE_WIDTH, "CENTER")
    hEWL:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    hEWL:SetText("Use")

    local viewport = CreateFrame("Frame", nil, main)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    viewport:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
    component.viewport = viewport

    local scrollBar = Theme.CreateScrollBar(viewport)
    scrollBar:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", 0, 0)
    scrollBar:SetValueStep(1)
    scrollBar.ownerComponent = component
    scrollBar:SetScript("OnValueChanged", Scroll_OnValueChanged)
    component.scrollBar = scrollBar

    component.rows = {}
    for index = 1, ROW_POOL do component.rows[index] = CreateRow(component, viewport) end
    Theme.BindSliderWheel(viewport, scrollBar, 1, unpack(component.rows))

    local emptyState = Theme.CreateEmptyState(viewport, "No matching Echoes", "Change the group, subgroup, or search scope.")
    emptyState:SetHeight(122)
    emptyState:Hide()
    component.emptyState = emptyState
    local emptyAction = Theme.CreateButton(emptyState, "gold")
    emptyAction:SetSize(150, 22)
    emptyAction:SetPoint("TOP", emptyState._body, "BOTTOM", 0, -8)
    emptyAction:SetText("Browse Damage")
    emptyAction.ownerComponent = component
    emptyAction:SetScript("OnClick", EmptyAction_OnClick)
    component.emptyAction = emptyAction

    component.priorityPopup = CreatePriorityPopup(component)

    main:HookScript("OnSizeChanged", function() ScheduleLayout(component) end)
    viewport:HookScript("OnSizeChanged", function() ScheduleLayout(component) end)
    LayoutToolbar(component)
    component.active = false
    return component
end

function PriorityStep:SetContext(draft, classToken, snapshotLookup)
    local changed = self.draft ~= draft or self.classToken ~= tostring(classToken or ""):upper()
    self.draft = draft
    self.classToken = tostring(classToken or (draft and draft.class) or ""):upper()
    self.snapshotLookup = snapshotLookup
    if changed then
        self.model.contextGeneration = (self.model.contextGeneration or 0) + 1
        self.viewState.activeView = Projection.VIEW_RECOMMENDED
        self.viewState.activeGroup = Grouping.GROUP_DAMAGE
        self.viewState.activeSubgroup = Grouping.SUBGROUP_ALL
        self.viewState.diagnosticKey = Projection.DIAG_UNCLASSIFIED
        self.viewState.searchAllGroups = true
        self.viewState.searchText = ""
        WipeArray(self.viewState.activeKeys)
        WipeArray(self.viewState.stagingKeys)
        for key in pairs(self.viewState.scrollByView) do self.viewState.scrollByView[key] = nil end
        self.settingSearchText = true
        self.search:SetText("")
        self.settingSearchText = false
        self.scope:SetText("All groups")
    end
    UpdatePlaceholder(self)
end

function PriorityStep:Refresh(resetScroll)
    if not self.draft then return end
    ClosePriorityPopup(self)
    if resetScroll then
        self.viewState.scrollByView[CurrentViewKey(self)] = 0
        self.settingScroll = true
        self.scrollBar:SetValue(0)
        self.settingScroll = false
    end
    local ok = Projection.Rebuild(self.model, self.draft, self.viewState, self.snapshotLookup)
    if not ok then
        ScheduleRefresh(self, 0, resetScroll)
        return
    end

    self.title:SetText(CurrentTitle(self))
    self.description:SetText(CurrentDescription(self))
    self.sort:SetText(CurrentSortLabel(self))
    self.direction:SetText(self.viewState.sortDescending and "v" or "^")
    SetNavSelection(self)
    UpdateNavCounts(self)
    UpdateSubgroups(self)
    UpdatePlaceholder(self)
    self:UpdateRows()
    if self.options.updateStatus then self.options.updateStatus() end
end

function PriorityStep:UpdateRows()
    if not self.draft then return end
    local visible = self.viewState.activeKeys or {}
    local viewportHeight = self.viewport:GetHeight() or (ROW_HEIGHT * 10)
    local usableHeight = math.max(ROW_FRAME_HEIGHT, viewportHeight - ROW_TOP_INSET)
    -- Rows are 36px tall on a 38px stride. Counting with the stride alone
    -- drops a complete final row whenever the viewport is an exact fit.
    local rowCount = math.floor((usableHeight - ROW_FRAME_HEIGHT) / ROW_HEIGHT) + 1
    rowCount = math.max(1, math.min(ROW_POOL, rowCount))
    local requested = math.floor(tonumber(self.scrollBar:GetValue()) or 0)
    local offset, maxOffset = VirtualList.ClampOffset(#visible, rowCount, requested)
    self.settingScroll = true
    self.scrollBar:SetMinMaxValues(0, maxOffset)
    if self.scrollBar:GetValue() ~= offset then self.scrollBar:SetValue(offset) end
    self.settingScroll = false
    self.viewState.scrollByView[CurrentViewKey(self)] = offset

    for poolIndex = 1, ROW_POOL do
        local row = self.rows[poolIndex]
        local key = poolIndex <= rowCount and visible[offset + poolIndex] or nil
        if key then BindRow(self, row, key, poolIndex) else ResetRow(row) end
    end

    local counts = Projection.GetCounts(self.model) or {}
    self.count:SetText(string.format("%d shown · %d included · %d diagnostics", #visible,
        counts.included or 0, counts.diagnostics or 0))

    if #visible == 0 then
        local outside = tonumber(self.viewState.outsideGroupMatches) or 0
        if outside > 0 then
            self.emptyState._title:SetText("Matches exist outside this group")
            self.emptyState._body:SetText(string.format("%d matching Echo%s exist%s in other function groups.", outside,
                outside == 1 and "" or "es", outside == 1 and "s" or ""))
            self.emptyAction:SetText("Search all groups")
        elseif self.viewState.activeView == Projection.VIEW_RECOMMENDED and (self.viewState.searchText or "") == "" then
            self.emptyState._title:SetText("No community suggestions")
            self.emptyState._body:SetText("No stable recommendation set is stored. The complete class catalogue remains available by function group.")
            self.emptyAction:SetText("Browse Damage")
        else
            self.emptyState._title:SetText("No matching Echoes")
            self.emptyState._body:SetText("Change the search, subgroup, or navigation view.")
            self.emptyAction:SetText("Browse Damage")
        end
        self.emptyState:Show()
    else
        self.emptyState:Hide()
    end
end

function PriorityStep:Show()
    self.active = true
    activeComponent = self
    self.frame:Show()
    LayoutToolbar(self)
    self:Refresh(false)
end

function PriorityStep:Hide()
    self.active = false
    if activeComponent == self then activeComponent = nil end
    ClosePriorityPopup(self)
    if self.search then self.search:ClearFocus() end
    self.frame:Hide()
end

function PriorityStep:RefreshLayout()
    LayoutToolbar(self)
    ScheduleLayout(self)
end

function PriorityStep:CancelScheduled()
    EbonBuilds.Scheduler.Cancel("buildWizard.priority.rebuild")
    EbonBuilds.Scheduler.Cancel("buildWizard.priority.layout")
end

function PriorityStep:GetVisibleKeysForTest()
    return self.viewState.activeKeys
end

local function OnProjectionInvalidated()
    Projection.Invalidate()
    if activeComponent and activeComponent.active and activeComponent.draft then ScheduleRefresh(activeComponent, 0, false) end
end

if EbonBuilds.EventHub and EbonBuilds.EventHub.On then
    EbonBuilds.EventHub.On("ECHO_CATALOG_CHANGED", OnProjectionInvalidated)
    EbonBuilds.EventHub.On("EVIDENCE_REVISION_CHANGED", OnProjectionInvalidated)
    EbonBuilds.EventHub.On("LOCALE_CHANGED", OnProjectionInvalidated)
end
