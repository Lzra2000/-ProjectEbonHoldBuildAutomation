local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Missing + Logbook). Registered as "buildOverview" view. Shows build metadata,
-- locked echoes, automation toggle, runtime statistics, and missing echoes.

EbonBuilds.BuildOverview = {}

-- Pure data layer, split out to modules/analytics/BuildOverviewData.lua (issue #19).
-- Local aliases keep every existing call site and test hook unchanged.
local Data = EbonBuilds.BuildOverviewData
local NormalizeEchoName = Data.NormalizeEchoName
local GetOwnedEchoSets = Data.GetOwnedEchoSets
local MissingViewDefinition = Data.MissingViewDefinition
local BuildWeightedEchoSet = Data.BuildWeightedEchoSet
local ComputeMissingEchoes = Data.ComputeMissingEchoes
local OverviewActionGridMetrics = Data.ActionGridMetrics
local DEFAULT_MISSING_VIEW_KEY = Data.DEFAULT_MISSING_VIEW_KEY
local MISSING_VIEW_OPTIONS = Data.MISSING_VIEW_OPTIONS

local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.0,  0.96, 0.41 },
    PRIEST      = { 1.0,  1.0,  1.0  },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.0,  0.44, 0.87 },
    MAGE        = { 0.41, 0.8,  0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.0,  0.49, 0.04 },
}

local QUALITY_BORDER_COLORS = EbonBuilds.Quality.RGB

local QUALITY_LABELS = EbonBuilds.Quality.LABELS

local viewFrame
local RefreshOverview
local tab1, tab2, tab3, tab4
local contentArea
local state = { build = nil }

------------------------------------------------------------------------
-- Delete confirmation dialog
------------------------------------------------------------------------

StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"] = {
    text = "",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        local build = state.build
        if not build or not build.id then return end
        local id = build.id
        local deletedTitle = build.title or "Untitled"
        EbonBuilds.Build.Delete(id)
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        local builds = EbonBuilds.Build.List()
        if #builds > 0 then
            EbonBuilds.Build.SetActive(builds[1].id)
            EbonBuilds.ViewRouter.Show("buildOverview", { build = builds[1] })
        else
            EbonBuilds.ViewRouter.Show("welcome")
        end
        StaticPopupDialogs["EBONBUILDS_UNDO_DELETE"].text =
            "Deleted \"" .. deletedTitle .. "\"."
        StaticPopup_Show("EBONBUILDS_UNDO_DELETE")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONBUILDS_UNDO_DELETE"] = {
    text = "",
    button1 = "Undo",
    button2 = "OK",
    OnAccept = function()
        local restored = EbonBuilds.Build.RestoreLastDeleted()
        if not restored then return end
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        EbonBuilds.Build.SetActive(restored.id)
        EbonBuilds.ViewRouter.Show("buildOverview", { build = restored })
        EbonBuilds.Toast.Show("Restored \"" .. (restored.title or "Untitled") .. "\"")
    end,
    timeout = 10,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(btn, "BuildOverview.IconButton")
    end
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

------------------------------------------------------------------------
-- Overview tab content

local function LayoutOverviewActions(outer)
    local area = outer and outer._actionArea
    local buttons = outer and outer._actionButtons
    if not area or not buttons or #buttons == 0 then return end
    local metrics = OverviewActionGridMetrics(outer:GetWidth(), #buttons)
    area:SetWidth(metrics.available)
    area:SetHeight(metrics.height)
    for index, button in ipairs(buttons) do
        local row = math.floor((index - 1) / metrics.columns)
        local column = (index - 1) % metrics.columns
        button:ClearAllPoints()
        button:SetSize(metrics.buttonWidth, 22)
        button:SetPoint("TOPLEFT", area, "TOPLEFT",
            column * (metrics.buttonWidth + metrics.gap),
            -row * (22 + metrics.gap))
    end
end

local function BuildOverviewTab(parent)
    local outer = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(outer, "BuildOverview.StatusOuter")
    end
    outer:SetAllPoints(parent)

    -- Editing is the primary action for this page, so it lives separately in
    -- the header instead of competing with runtime and sharing utilities.
    local editBtn = EbonBuilds.Theme.CreateButton(outer, "gold")
    editBtn:SetSize(128, 26)
    editBtn:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -10, -10)
    editBtn:SetText("Edit Build")
    EbonBuilds.Theme.AttachTooltip(editBtn, "Edit Build",
        "Opens the complete build editor. Use the Character action below for direct access to saved gear, talents, glyphs, and affixes.")
    editBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = state.build })
        end
    end)
    outer._editBtn = editBtn

    -- Class icon + Build name header
    local classIcon = outer:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(32)
    classIcon:SetHeight(32)
    classIcon:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -10)
    outer._classIcon = classIcon

    local nameLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -6)
    nameLabel:SetPoint("RIGHT", editBtn, "LEFT", -10, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetJustifyV("TOP")
    -- Fixed height (enough for 2 wrapped lines) so a long community build
    -- title can never overlap the meta line below it -- previously metaLabel
    -- sat at a position fixed relative to classIcon, which didn't account
    -- for nameLabel needing more than one line.
    nameLabel:SetHeight(32)
    outer._nameLabel = nameLabel

    -- Author + last modified
    local metaLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    metaLabel:SetPoint("RIGHT",  outer,     "RIGHT",      -10, 0)
    metaLabel:SetJustifyH("LEFT")
    metaLabel:SetJustifyV("TOP")
    metaLabel:SetHeight(26)
    outer._metaLabel = metaLabel

    -- Public, readiness, and evidence status (button frame for tooltip support)
    local statusFrame = CreateFrame("Button", nil, outer)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(statusFrame, "BuildOverview.StatusFrame")
    end
    statusFrame:SetPoint("TOPLEFT",     metaLabel, "BOTTOMLEFT", 0, -12)
    statusFrame:SetPoint("RIGHT",       outer,     "RIGHT",      -10, 0)
    statusFrame:SetHeight(16)
    local statusLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetAllPoints(statusFrame)
    statusLabel:SetJustifyH("LEFT")
    statusFrame:SetScript("OnEnter", function(self)
        local build = state.build
        if not build then return end
        local readiness = EbonBuilds.Readiness.Get(build)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Build readiness", 1, 0.82, 0, 1)
        GameTooltip:AddLine("State: " .. tostring(readiness.state), 0.85, 0.85, 0.9, 1)
        GameTooltip:AddLine(string.format("Current strategy evidence: %d completed run(s), %d recorded decisions.",
            readiness.completedRuns or 0, readiness.decisionCount or 0), 0.75, 0.75, 0.8, 1)
        if readiness.reviewPending then
            GameTooltip:AddLine("A completed or interrupted run is ready to review.", 1, 0.72, 0.2, 1)
        end
        if build.isPublic then
            GameTooltip:AddLine(build.validated and "This strategy revision has a completed local run."
                or "No completed local run has been recorded for this strategy revision.", 0.65, 0.65, 0.7, 1)
        end
        GameTooltip:Show()
    end)
    statusFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    outer._statusLabel = statusLabel

    -- Locked echoes
    local lockedHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockedHeader:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -14)
    lockedHeader:SetText("Locked Echoes:")
    outer._lockedHeader = lockedHeader

    local lockedButtons = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(outer, 36)
        btn:SetPoint("TOPLEFT", lockedHeader, "BOTTOMLEFT", (i - 1) * 42, -6)
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._border = border
        btn:SetScript("OnEnter", function(self)
            if not self._spellId then return end
            local name = GetSpellInfo(self._spellId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if name then GameTooltip:AddLine(name, 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lockedButtons[i] = btn
    end
    outer._lockedButtons = lockedButtons

    -- Server permanent locks (PerkService.GetLockedPerks) -- distinct from the
    -- build's designed Locked Echoes above. Capability-gated; hidden when PE
    -- does not expose the APIs.
    local permHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    permHeader:SetPoint("TOPLEFT", lockedButtons[1], "BOTTOMLEFT", 0, -12)
    permHeader:SetText(EbonBuilds.L["Permanent locks:"])
    outer._permHeader = permHeader

    local permMeta = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    permMeta:SetPoint("LEFT", permHeader, "RIGHT", 8, 0)
    permMeta:SetText("")
    outer._permMeta = permMeta

    local permButtons = {}
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = CreateIconButton(outer, 32)
        btn:SetPoint("TOPLEFT", permHeader, "BOTTOMLEFT", (i - 1) * 38, -6)
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._border = border
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if self._spellId then
                local name = GetSpellInfo(self._spellId)
                if name then GameTooltip:AddLine(name, 1, 0.82, 0) end
                GameTooltip:AddLine(EbonBuilds.L["Permanent character lock"], 0.75, 0.75, 0.8, true)
                local caps = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCapabilities
                    and EbonBuilds.ProjectAPI.GetCapabilities()
                if caps and caps.unlockPerk then
                    GameTooltip:AddLine(EbonBuilds.L["Click to unlock"], 0.65, 0.65, 0.7, true)
                end
            elseif self._slotAvailable then
                GameTooltip:AddLine(EbonBuilds.L["Empty permanent slot"], 0.6, 0.6, 0.6)
                GameTooltip:AddLine(EbonBuilds.L["Right-click a build locked echo above to lock it permanently."], 0.75, 0.75, 0.8, true)
            else
                GameTooltip:AddLine(EbonBuilds.L["Slot not unlocked yet"], 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self)
            if not self._spellId then return end
            local caps = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCapabilities
                and EbonBuilds.ProjectAPI.GetCapabilities()
            if not (caps and caps.unlockPerk) then return end
            if EbonBuilds.ProjectAPI.UnlockPerk(self._spellId) then
                EbonBuilds.Toast.Show(EbonBuilds.L["Unlock requested"])
                if EbonBuilds.Scheduler and EbonBuilds.Scheduler.After then
                    EbonBuilds.Scheduler.After("buildOverview.permRefresh", 1.2, function()
                        if viewFrame and viewFrame:IsShown() then RefreshOverview() end
                    end)
                end
            end
        end)
        permButtons[i] = btn
    end
    outer._permButtons = permButtons

    -- Right-click a build locked echo to request LockPerk on the character.
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = lockedButtons[i]
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local prevEnter = btn:GetScript("OnEnter")
        btn:SetScript("OnEnter", function(self)
            if prevEnter then prevEnter(self) end
            if self._spellId then
                local caps = EbonBuilds.ProjectAPI and EbonBuilds.ProjectAPI.GetCapabilities
                    and EbonBuilds.ProjectAPI.GetCapabilities()
                if caps and caps.lockPerk then
                    GameTooltip:AddLine(EbonBuilds.L["Right-click to lock permanently on character"], 0.65, 0.65, 0.7, true)
                    GameTooltip:Show()
                end
            end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" or not self._spellId then return end
            local api = EbonBuilds.ProjectAPI
            local caps = api and api.GetCapabilities and api.GetCapabilities()
            if not (caps and caps.lockPerk and caps.lockedPerks and caps.maxPermanentEchoes) then
                EbonBuilds.Toast.Show(EbonBuilds.L["Server doesn't support permanent locks"])
                return
            end
            local locked = api.GetLockedPerks() or {}
            local maxSlots = api.GetMaximumPermanentEchoes()
            if maxSlots <= 0 then
                EbonBuilds.Toast.Show(EbonBuilds.L["No permanent lock slots unlocked"])
                return
            end
            if #locked >= maxSlots then
                EbonBuilds.Toast.Show(EbonBuilds.L["Permanent lock slots full"])
                return
            end
            for _, lp in ipairs(locked) do
                if tonumber(lp.spellId) == tonumber(self._spellId) then
                    EbonBuilds.Toast.Show(EbonBuilds.L["Already permanently locked"])
                    return
                end
            end
            if api.LockPerk(self._spellId) then
                EbonBuilds.Toast.Show(EbonBuilds.L["Lock requested"])
                if EbonBuilds.Scheduler and EbonBuilds.Scheduler.After then
                    EbonBuilds.Scheduler.After("buildOverview.permRefresh", 1.2, function()
                        if viewFrame and viewFrame:IsShown() then RefreshOverview() end
                    end)
                end
            end
        end)
    end

    local actionArea = CreateFrame("Frame", nil, outer)
    actionArea:SetPoint("TOPLEFT", permButtons[1], "BOTTOMLEFT", -40, -18)
    actionArea:SetSize(320, 50)
    outer._actionArea = actionArea

    -- Runtime controls and build actions are created here, then placed by the
    -- shared responsive action grid once every control exists.
    local autoToggle = EbonBuilds.Theme.CreateButton(outer)
    autoToggle:SetWidth(140)
    autoToggle:SetHeight(22)
    autoToggle:SetPoint("TOPLEFT", permButtons[1], "BOTTOMLEFT", 0, -22)
    local function RefreshAutoToggle(self, build)
        local on = build and EbonBuilds.Build.IsAutomationEnabled(build)
        self:SetText(on and "Autopilot: ON" or "Autopilot: OFF")
        -- Color-code live state so the one control that changes game
        -- behavior stands out from the row of plain navigation buttons.
        if on then
            EbonBuilds.Theme.SetButtonAccent(self, "good")
        else
            EbonBuilds.Theme.ClearButtonAccent(self)
        end
    end
    autoToggle:SetText("Autopilot: ON")
    autoToggle:SetScript("OnClick", function(self)
        local build = state.build
        if not build then return end
        local enabling = not EbonBuilds.Build.IsAutomationEnabled(build)
        EbonBuilds.Build.SetAutomationEnabled(build, enabling)
        RefreshAutoToggle(self, build)
        if enabling and EbonBuilds.Automation and EbonBuilds.Automation.WarnPeAutoAcceptConflict then
            EbonBuilds.Automation.WarnPeAutoAcceptConflict()
        end
        if EbonBuilds.MainWindow and EbonBuilds.MainWindow.RefreshContext then EbonBuilds.MainWindow.RefreshContext() end
    end)
    outer._autoToggle = autoToggle
    outer._refreshAutoToggle = RefreshAutoToggle

    -- Manual Training Mode toggle: independent of Automation on/off.
    -- When on, automation never acts for this build (see the check in
    -- Automation.Evaluate) -- the native perk UI shows and EbonBuilds
    -- watches what you pick, building weight suggestions from your own
    -- choices instead of measured DPS. See /ebb tuning or Export (AI).
    local trainToggle = EbonBuilds.Theme.CreateButton(outer)
    trainToggle:SetWidth(140)
    trainToggle:SetHeight(22)
    trainToggle:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -6)
    local function RefreshTrainToggle(self, build)
        local on = build and EbonBuilds.ManualTraining and EbonBuilds.ManualTraining.IsEnabled(build)
        self:SetText(on and "Training: ON" or "Training: OFF")
        if on then
            EbonBuilds.Theme.SetButtonAccent(self, "good")
        else
            EbonBuilds.Theme.ClearButtonAccent(self)
        end
    end
    trainToggle:SetText("Training: OFF")
    trainToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Manual Training Mode", 1, 1, 1)
        GameTooltip:AddLine("Independent of the Automation toggle above. When on, automation never acts for this build -- you pick manually in the native UI, and EbonBuilds compares your picks against what the current weights would suggest. Builds weight-adjustment suggestions from your own choices, shown in Export (AI).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    trainToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    trainToggle:SetScript("OnClick", function(self)
        local build = state.build
        if not build then return end
        EbonBuilds.ManualTraining.SetEnabled(build, not EbonBuilds.ManualTraining.IsEnabled(build))
        RefreshTrainToggle(self, build)
    end)
    outer._trainToggle = trainToggle
    outer._refreshTrainToggle = RefreshTrainToggle

    local characterBtn = EbonBuilds.Theme.CreateButton(outer)
    characterBtn:SetSize(120, 22)
    characterBtn:SetText("Character")
    EbonBuilds.Theme.AttachTooltip(characterBtn, "Open Character",
        "Opens this build's saved talents, glyphs, gear, and affixes directly in the Character editor.")
    characterBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = state.build, tab = 5 })
        end
    end)
    outer._characterBtn = characterBtn

    local linkBtn = EbonBuilds.Theme.CreateButton(outer)
    linkBtn:SetWidth(80)
    linkBtn:SetHeight(22)
    linkBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    linkBtn:SetText("Chat Link")
    linkBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ChatLink.InsertLink(state.build)
        end
    end)
    linkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Share in chat", 1, 1, 1)
        GameTooltip:AddLine("Inserts a build link into your chat box. Other EbonBuilds users can click it to fetch this build (public builds only).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local dupBtn = EbonBuilds.Theme.CreateButton(outer)
    dupBtn:SetWidth(90)
    dupBtn:SetHeight(22)
    dupBtn:SetPoint("LEFT", linkBtn, "RIGHT", 8, 0)
    dupBtn:SetText("Duplicate")
    dupBtn:SetScript("OnClick", function()
        local build = state.build
        if not build or not build.id then return end
        local copy = EbonBuilds.Build.Duplicate(build.id)
        if not copy then return end
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        EbonBuilds.Toast.Show("Created \"" .. copy.title .. "\"")
        EbonBuilds.Build.SetActive(copy.id)
        EbonBuilds.ViewRouter.Show("buildOverview", { build = copy })
    end)

    -- Wishlist (SetActiveEchoLoadout): client SavedVariables highlight +
    -- optional auto-accept. Distinct from designed server slots and from
    -- verified L80 snapshots (those never come from EbonBuilds uploads).
    local L = EbonBuilds.L or setmetatable({}, { __index = function(_, k) return k end })

    local function ToastAutoAcceptWarn(info)
        if info and info.autoAcceptWarn then
            EbonBuilds.Toast.Show("Warning: Auto-Accept is ON for this foreign loadout")
        end
    end

    local function RunApplyWishlist(build)
        local api = EbonBuilds.ProjectAPI
        if not api or not api.ApplyBuildAsWishlist then
            EbonBuilds.Toast.Show("Server doesn't support Active Echo Loadout")
            return
        end
        local ok, err, info = api.ApplyBuildAsWishlist(build)
        if ok then
            EbonBuilds.Toast.Show("Wishlist applied: \"" .. (build.title or "?") .. "\"")
            ToastAutoAcceptWarn(info)
        elseif err == "unsupported" then
            EbonBuilds.Toast.Show("Server doesn't support Active Echo Loadout")
        elseif err == "empty" then
            EbonBuilds.Toast.Show("No locked echoes to apply")
        else
            EbonBuilds.Toast.Show("Failed to apply wishlist")
        end
    end

    local function RunUploadServerSlot(build)
        local api = EbonBuilds.ProjectAPI
        if not api or not api.UploadBuildAsServerSlot then
            EbonBuilds.Toast.Show("Server doesn't support designed build slots")
            return
        end
        local ok, err, info = api.UploadBuildAsServerSlot(build, 0)
        if ok then
            local msg = "Saved \"" .. (build.title or "?") .. "\" as server loadout"
            if info and info.skipped and info.skipped > 0 then
                msg = msg .. string.format(" (%d class-skipped)", info.skipped)
            end
            EbonBuilds.Toast.Show(msg)
            ToastAutoAcceptWarn(info)
        elseif err == "disabled" or err == "unsupported" then
            EbonBuilds.Toast.Show("Server build slots unavailable")
        elseif err == "empty" then
            EbonBuilds.Toast.Show("No locked echoes to upload")
        else
            EbonBuilds.Toast.Show("Failed to save server loadout")
        end
    end

    local function ConfirmForeignAutoAccept(build, run)
        local api = EbonBuilds.ProjectAPI
        if api and api.WithForeignAutoAcceptConfirm then
            api.WithForeignAutoAcceptConfirm(build, run)
            return
        end
        run(build)
    end

    local applyBtn = EbonBuilds.Theme.CreateButton(outer)
    applyBtn:SetWidth(150)
    applyBtn:SetHeight(20)
    applyBtn:SetPoint("TOPLEFT", trainToggle, "BOTTOMLEFT", 0, -8)
    applyBtn:SetText(L["Apply wishlist"])
    applyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Apply wishlist"], 1, 1, 1)
        GameTooltip:AddLine("Sets this build's locked echoes as your ProjectEbonhold wishlist (Active Echo Loadout). The echo-pick screen highlights matches; with Auto-Accept on, matching picks are taken automatically. This is NOT a designed server slot and does NOT apply gear, talents, or weights.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    applyBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        ConfirmForeignAutoAccept(build, RunApplyWishlist)
    end)
    outer._applyBtn = applyBtn

    local serverBtn = EbonBuilds.Theme.CreateButton(outer)
    serverBtn:SetWidth(170)
    serverBtn:SetHeight(20)
    serverBtn:SetText(L["Save as server loadout"])
    serverBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Save as server loadout"], 1, 1, 1)
        GameTooltip:AddLine("Uploads locked echoes as a designed ProjectEbonhold server build slot (highlight + auto-accept only). Not a verified L80 snapshot — no level-1 run guarantee and no full gear/talent swap. Weights and character snapshots stay in EbonBuilds only.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    serverBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    serverBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        ConfirmForeignAutoAccept(build, RunUploadServerSlot)
    end)
    outer._serverLoadoutBtn = serverBtn

    local ewlBtn = EbonBuilds.Theme.CreateButton(outer, "gold")
    ewlBtn:SetWidth(118)
    ewlBtn:SetHeight(20)
    ewlBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    ewlBtn:SetText("Export EWL")
    ewlBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Export Echo Wish List", 1, 0.82, 0)
        GameTooltip:AddLine("Resolves locked rank aliases to EchoWishlist's retained catalog ID and marks them :1, then adds one canonical :0 row per remaining weighted Echo family.", 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    ewlBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ewlBtn:SetScript("OnClick", function()
        if state.build and EbonBuilds.EWL then
            EbonBuilds.EWL.ShowExportDialog(state.build)
        end
    end)
    outer._ewlBtn = ewlBtn

    local reviewBtn = EbonBuilds.Theme.CreateButton(outer)
    reviewBtn:SetWidth(132)
    reviewBtn:SetHeight(20)
    reviewBtn:SetPoint("LEFT", ewlBtn, "RIGHT", 8, 0)
    reviewBtn:SetText("Review Last Run")
    EbonBuilds.Theme.AttachTooltip(reviewBtn, "Review last run",
        "Opens the decision logbook for the latest run and marks its summary as reviewed. Mixed-strategy runs remain clearly labeled.")
    reviewBtn:SetScript("OnClick", function()
        local build = state.build
        local summary = build and EbonBuilds.Review.Build(build)
        if not summary then
            EbonBuilds.Toast.Show("No finished run is available for this build yet")
            return
        end
        EbonBuilds.Review.MarkReviewed(build)
        EbonBuilds.BuildOverview.OpenLogbook()
        local label = summary.completed and "completed" or "interrupted"
        if summary.mixedStrategy then label = label .. ", mixed strategy" end
        EbonBuilds.Toast.Show(string.format("Reviewing %s run: level %d, %d decisions", label,
            summary.maxLevel or 1, summary.decisions or 0))
    end)
    outer._reviewBtn = reviewBtn

    -- Optional: SnapshotCurrentEchoes → new local draft build from the run.
    local snapshotBtn = EbonBuilds.Theme.CreateButton(outer)
    snapshotBtn:SetWidth(132)
    snapshotBtn:SetHeight(20)
    snapshotBtn:SetText(EbonBuilds.L["Snapshot Run"])
    EbonBuilds.Theme.AttachTooltip(snapshotBtn, EbonBuilds.L["Snapshot current run"],
        EbonBuilds.L["Creates a new private draft build whose locked echoes are filled from your current granted + permanent echoes (ProjectEbonhold snapshot)."])
    snapshotBtn:SetScript("OnClick", function()
        local api = EbonBuilds.ProjectAPI
        local caps = api and api.GetCapabilities and api.GetCapabilities()
        if not (caps and caps.snapshotEchoes) then
            EbonBuilds.Toast.Show(EbonBuilds.L["Server doesn't support echo snapshot"])
            return
        end
        local list = api.SnapshotCurrentEchoes()
        if not list or #list == 0 then
            EbonBuilds.Toast.Show(EbonBuilds.L["No echoes to snapshot"])
            return
        end
        local locked = { nil, nil, nil, nil, nil, nil }
        for i = 1, math.min(EbonBuilds.Build.LOCKED_SLOTS, #list) do
            locked[i] = tonumber(list[i].spellId)
        end
        local draft = EbonBuilds.Build.Create({
            title = EbonBuilds.L["Run Snapshot"],
            class = api.GetPlayerClassToken and api.GetPlayerClassToken() or nil,
            lockedEchoes = locked,
            comments = string.format(EbonBuilds.L["Imported from current run (%d unique echoes)."], #list),
            startPaused = true,
        })
        if not draft then
            EbonBuilds.Toast.Show(EbonBuilds.L["Failed to create snapshot build"])
            return
        end
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        EbonBuilds.Build.SetActive(draft.id)
        EbonBuilds.Toast.Show(string.format(EbonBuilds.L["Created \"%s\""], draft.title or "?"))
        EbonBuilds.ViewRouter.Show("buildOverview", { build = draft })
    end)
    outer._snapshotBtn = snapshotBtn

    -- One deterministic action grid replaces the previous chain of mixed
    -- left/top anchors. Wide views use five equal columns over two rows;
    -- narrower views use three columns over three rows without squeezing
    -- labels or changing their semantic order.
    outer._actionButtons = {
        autoToggle, trainToggle, characterBtn, applyBtn, serverBtn,
        linkBtn, dupBtn, ewlBtn, reviewBtn, snapshotBtn,
    }
    LayoutOverviewActions(outer)

    -- Description header
    local descHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descHeader:SetPoint("TOPLEFT", actionArea, "BOTTOMLEFT", 0, -14)
    descHeader:SetText("Description:")
    outer._descHeader = descHeader

    -- Description scroll frame (owns scrollbar)
    local descScroll = CreateFrame("ScrollFrame", nil, outer)
    descScroll:SetPoint("TOPLEFT",     descHeader, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", outer,      "BOTTOMRIGHT", -22, 28)

    local descChild = CreateFrame("Frame", nil, descScroll)
    descChild:SetWidth(416)
    descChild:SetHeight(1)
    descScroll:SetScrollChild(descChild)

    local descBar = EbonBuilds.Theme.CreateScrollBar(descScroll)
    descBar:SetPoint("TOPLEFT",    descScroll, "TOPRIGHT",    -2, -4)
    descBar:SetPoint("BOTTOMLEFT", descScroll, "BOTTOMRIGHT", -2,  4)
    descBar:SetValueStep(20)
    descBar:SetScript("OnValueChanged", function(_, value)
        descScroll:SetVerticalScroll(value)
    end)

    -- SMF inside scroll child -- renders text with hyperlink tooltip support
    local descSmf = CreateFrame("ScrollingMessageFrame", nil, descChild)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(descSmf, "BuildOverview.DescScrollingMessage")
    end
    descSmf:SetPoint("TOPLEFT", descChild, "TOPLEFT", 0, -2)
    descSmf:SetWidth(416)
    descSmf:SetFontObject("GameFontNormalSmall")
    descSmf:SetJustifyH("LEFT")
    descSmf:SetFading(false)
    descSmf:SetInsertMode("TOP")
    descSmf:SetMaxLines(500)
    descSmf:SetHyperlinksEnabled(true)
    descSmf:EnableMouse(true)
    descSmf:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    descSmf:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)

    -- Hidden FontString with same width -- used only to measure wrapped text height
    local descMeasure = descChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descMeasure:SetWidth(416)
    descMeasure:Hide()

    -- Use the shared 3.3.5a-safe route. Moving the child with SetPoint left
    -- ScrollFrame:GetVerticalScroll() at zero, so the description could become
    -- trapped at the bottom when the wheel was turned over the message frame.
    EbonBuilds.Theme.BindScrollWheel(descScroll, descBar, 20, descChild)

    outer._descSmf = descSmf
    outer._descMeasure = descMeasure
    outer._descScroll = descScroll
    outer._descChild  = descChild
    outer._descBar    = descBar

    -- Delete button (bottom-left, below description, low misclick probability).
    -- Red accent marks it as destructive rather than just another action
    -- that happens to sit apart from the rest.
    local deleteBtn = EbonBuilds.Theme.CreateButton(outer, "danger")
    deleteBtn:SetSize(64, 20)
    deleteBtn:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 10, 4)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        local name = build.title or "Untitled"
        StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"].text = "Delete build \"" .. name .. "\"?"
        StaticPopup_Show("EBONBUILDS_DELETE_BUILD")
    end)
    outer._deleteBtn = deleteBtn

    outer:SetScript("OnSizeChanged", function(self) LayoutOverviewActions(self) end)

    return outer, descSmf, descMeasure, descScroll, descChild, descBar
end

------------------------------------------------------------------------
-- Stats tab
------------------------------------------------------------------------

local STAT_ROWS = {
    { key = "echoesSeen",    label = "Echoes Seen" },
    { key = "runsCompleted", label = "Runs Completed" },
    { key = "runsReset",     label = "Runs Reset" },
    { key = "picks",         label = "Picks" },
    { key = "rerollsUsed",   label = "Rerolls Used" },
    { key = "banishesUsed",  label = "Banishes Used" },
    { key = "freezesUsed",   label = "Freezes Used" },
}

local function BuildStatsTab(parent)
    if EbonBuilds.StatsView and EbonBuilds.StatsView.Mount then
        EbonBuilds.StatsView.Mount(parent)
    end
    return {}, {}
end

------------------------------------------------------------------------
-- Missing tab
------------------------------------------------------------------------

local missingState = { view = DEFAULT_MISSING_VIEW_KEY }
local missingViewDropdown, missingCountLabel, missingRefreshBtn
local missingScroll, missingChild, missingBar
local RefreshMissing

local function BuildMissingTab(parent)
    missingCountLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingCountLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -4)

    missingRefreshBtn = EbonBuilds.Theme.CreateButton(parent)
    missingRefreshBtn:SetSize(70, 20)
    missingRefreshBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -2)
    missingRefreshBtn:SetText("Refresh")
    missingRefreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Refresh", 1, 1, 1)
        GameTooltip:AddLine("Re-reads your spellbook for learned echoes right now, " ..
            "instead of waiting for the automatic retry.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    missingRefreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    missingRefreshBtn:SetScript("OnClick", function()
        RefreshMissing()
    end)

    missingViewDropdown = EbonBuilds.Theme.CreateDropdown(parent, 178, "Weighted missing")
    missingViewDropdown:SetPoint("RIGHT", missingRefreshBtn, "LEFT", -8, 0)
    missingViewDropdown:SetHeight(20)
    missingViewDropdown:SetMenuBuilder(function()
        local items = {}
        for _, option in ipairs(MISSING_VIEW_OPTIONS) do
            local view = option
            items[#items + 1] = {
                text = view.label,
                checked = missingState.view == view.key,
                tooltipTitle = view.label,
                tooltipBody = view.tooltip,
                func = function()
                    missingState.view = view.key
                    missingViewDropdown:SetText(view.label)
                    if missingBar then missingBar:SetValue(0) end
                    RefreshMissing()
                end,
            }
        end
        return items
    end)
    EbonBuilds.Theme.AttachTooltip(
        missingViewDropdown,
        "Collection view",
        "Weighted missing is the default. Use the other views to include learned weighted priorities, every missing Echo, or the learned-and-missing collection view."
    )

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     10, -28)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 8)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(460)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local bar = EbonBuilds.Theme.CreateScrollBar(scroll)
    bar:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2,  4)
    bar:SetValueStep(16)

    bar:SetScript("OnValueChanged", function(self, value)
        -- Keep the ScrollFrame's native offset authoritative so the shared
        -- wheel router can move away from the exact bottom boundary reliably.
        scroll:SetVerticalScroll(value)
    end)
    EbonBuilds.Theme.BindScrollWheel(scroll, bar, 16, child)

    return scroll, child, bar
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    EbonBuilds.SessionHistory.Show(parent)
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local overviewOuter
local overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar
local statsValueLabels, statsQualityLabels
local missingRows = {}
RefreshOverview = function()
    local build = state.build
    if not build then return end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    SetClassIcon(overviewOuter._classIcon, build.class)
    overviewOuter._nameLabel:SetText(build.title or "Untitled")
    overviewOuter._nameLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specName = specs and specs[build.spec or 1] and specs[build.spec or 1].name or ""
    overviewOuter._metaLabel:SetText(string.format("by %s | %s | r%d / strategy r%d | %s",
        build.author or "Unknown",
        specName,
        tonumber(build.revision) or tonumber(build.version) or 1,
        tonumber(build.strategyRevision) or 1,
        build.lastModified or ""))

    -- Public / readiness / local evidence status. "Run-tested" is deliberately
    -- precise; it is not a global correctness or quality certification.
    local readiness = EbonBuilds.Readiness.Get(build)
    local publicText = build.isPublic and "|cff19ff19Public|r" or "|cff888888Private|r"
    local stateColor = readiness.state == "INCOMPLETE" and "|cffff5555"
        or readiness.state == "READY" and "|cffffff66"
        or "|cff19ff19"
    local evidence = tostring(readiness.evidenceTier or "INSUFFICIENT"):gsub("_", " ")
    local runTested = build.validated and " · |cff19ff19Locally run-tested|r" or ""
    local review = readiness.reviewPending and " · |cffffb84dReview ready|r" or ""
    overviewOuter._statusLabel:SetText(string.format("%s · %s%s|r · Evidence: %s%s%s",
        publicText, stateColor, readiness.state, evidence, runTested, review))
    if overviewOuter._reviewBtn then
        if EbonBuilds.Review.Latest(build) then overviewOuter._reviewBtn:Enable()
        else overviewOuter._reviewBtn:Disable() end
    end

    overviewOuter._refreshAutoToggle(overviewOuter._autoToggle, build)
    overviewOuter._refreshTrainToggle(overviewOuter._trainToggle, build)

    local desc = build.comments or ""
    overviewDescSmf:Clear()
    overviewDescSmf:AddMessage(desc, 0.8, 0.8, 0.8, 1.0)
    overviewDescMeasure:SetText(desc)

    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local btn = overviewOuter._lockedButtons[i]
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()
            local data = ProjectEbonhold.PerkDatabase[spellId]
            local quality = data and data.quality or 0
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._border:SetTexture(bc[1], bc[2], bc[3])
            btn._border:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._spellId = nil
            btn._border:Hide()
            btn:Show()
        end
    end

    -- Permanent character locks from ProjectEbonhold (capability-gated).
    local api = EbonBuilds.ProjectAPI
    local caps = api and api.GetCapabilities and api.GetCapabilities()
    local showPerm = caps and caps.lockedPerks and caps.maxPermanentEchoes
    if overviewOuter._permHeader then
        if showPerm then
            local locked = api.GetLockedPerks() or {}
            local maxSlots = api.GetMaximumPermanentEchoes()
            overviewOuter._permHeader:Show()
            overviewOuter._permMeta:Show()
            overviewOuter._permMeta:SetText(string.format("%d / %d", #locked, maxSlots))
            for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
                local btn = overviewOuter._permButtons[i]
                local lp = locked[i]
                local slotAvailable = i <= maxSlots
                btn._slotAvailable = slotAvailable
                if lp and lp.spellId then
                    local spellId = tonumber(lp.spellId)
                    btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
                    btn._icon:SetDesaturated(false)
                    btn._spellId = spellId
                    local quality = tonumber(lp.quality) or 0
                    local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
                    btn._border:SetTexture(bc[1], bc[2], bc[3])
                    btn._border:Show()
                    btn:Show()
                elseif slotAvailable then
                    btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                    btn._icon:SetDesaturated(false)
                    btn._spellId = nil
                    btn._border:Hide()
                    btn:Show()
                else
                    btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                    btn._icon:SetDesaturated(true)
                    btn._spellId = nil
                    btn._border:Hide()
                    btn:Show()
                end
            end
        else
            overviewOuter._permHeader:Show()
            overviewOuter._permMeta:Show()
            overviewOuter._permMeta:SetText(EbonBuilds.L["(unsupported)"])
            for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
                local btn = overviewOuter._permButtons[i]
                btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                btn._icon:SetDesaturated(true)
                btn._spellId = nil
                btn._slotAvailable = false
                btn._border:Hide()
                btn:Show()
            end
        end
    end
    if overviewOuter._snapshotBtn then
        if caps and caps.snapshotEchoes then
            overviewOuter._snapshotBtn:Enable()
        else
            overviewOuter._snapshotBtn:Disable()
        end
    end

    -- Adjust description scroll range
    local textHeight = overviewDescMeasure:GetStringHeight() or 0
    overviewDescSmf:SetHeight(math.max(textHeight + 4, 14))
    overviewDescChild:SetHeight(math.max(textHeight + 6, overviewDescScroll:GetHeight()))
    local maxDescriptionScroll = math.max(0, overviewDescChild:GetHeight() - overviewDescScroll:GetHeight())
    overviewDescBar:SetMinMaxValues(0, maxDescriptionScroll)
    if overviewOuter._lastDescription ~= desc then
        overviewOuter._lastDescription = desc
        overviewDescBar:SetValue(0)
        overviewDescScroll:SetVerticalScroll(0)
    elseif overviewDescBar:GetValue() > maxDescriptionScroll then
        overviewDescBar:SetValue(maxDescriptionScroll)
        overviewDescScroll:SetVerticalScroll(maxDescriptionScroll)
    end
end

local QUALITY_COLORS = EbonBuilds.Quality.RGB

-- Returns "Name (Nx)" for the highest-count entry of a name->count map,
-- or "-" if empty. next() alone would return an arbitrary entry.
local function TopEntry(counts)
    local bestName, bestCount = nil, 0
    for name, count in pairs(counts or {}) do
        if type(count) == "number" and count > bestCount then
            bestName, bestCount = name, count
        end
    end
    if not bestName then return "-" end
    return string.format("%s (%dx)", tostring(bestName), bestCount)
end

local function RefreshStats()
    local build = state.build
    if not build then return end
    if EbonBuilds.StatsView and EbonBuilds.StatsView.Refresh then
        EbonBuilds.StatsView.Refresh(build)
    end
end

local missingRetryActive = false
local missingRetryTotal = 0
local MISSING_RETRY_INTERVAL = 1.5
local MISSING_RETRY_TIMEOUT  = 15

local function StopMissingRetry()
    missingRetryActive = false
    missingRetryTotal = 0
    if EbonBuilds.Scheduler then EbonBuilds.Scheduler.Cancel("buildOverview.missingRetry") end
end

RefreshMissing = function(assumeNoneOwned)
    local build = state.build
    if not build or not missingChild then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    local view = MissingViewDefinition(missingState.view)
    local includeOwned = view.includeOwned
    local missing = ComputeMissingEchoes(build, assumeNoneOwned, includeOwned, view.weightedOnly)
    if missing == nil then
        if missingChild.emptyLabel then missingChild.emptyLabel:Hide() end
        missingChild.loadingLabel = missingChild.loadingLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingChild.loadingLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 4, -2)
        missingChild.loadingLabel:SetText("Requesting data...")
        missingChild.loadingLabel:Show()
        missingChild:SetHeight(20)
        -- Auto-retry instead of requiring the player to flip tabs away and
        -- back: poll until the spellbook is ready, or give up after
        -- MISSING_RETRY_TIMEOUT and show the list anyway (see the
        -- assumeNoneOwned comment in ComputeMissingEchoes for why this
        -- can otherwise hang forever on a fresh character).
        if not missingRetryActive then
            missingRetryActive = true
            missingRetryTotal = 0
            EbonBuilds.Scheduler.Every("buildOverview.missingRetry", MISSING_RETRY_INTERVAL, function()
                if not missingRetryActive then return false end
                missingRetryTotal = missingRetryTotal + MISSING_RETRY_INTERVAL
                local giveUp = missingRetryTotal >= MISSING_RETRY_TIMEOUT
                if giveUp and EbonBuilds.DebugLog then
                    EbonBuilds.DebugLog.Add("Missing tab: Echoes spellbook tab never appeared after " ..
                        MISSING_RETRY_TIMEOUT .. "s, showing full list (likely 0 echoes learned yet)")
                end
                RefreshMissing(giveUp)
                return missingRetryActive and MISSING_RETRY_INTERVAL or false
            end, EbonBuilds.Scheduler.BACKGROUND, false, "BuildOverview")
        end
        return
    end
    StopMissingRetry()
    if missingChild.loadingLabel then
        missingChild.loadingLabel:Hide()
    end
    missingChild.emptyLabel = missingChild.emptyLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingChild.emptyLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 6, -8)
    missingChild.emptyLabel:SetPoint("RIGHT", missingChild, "RIGHT", -12, 0)
    missingChild.emptyLabel:SetJustifyH("LEFT")
    missingChild.emptyLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    if #missing == 0 then
        local emptyText
        if view.key == "weighted" then
            emptyText = "No weighted Echoes in this build. Add a non-zero rank value in Priorities to include an Echo here."
        elseif view.key == "weightedMissing" then
            emptyText = "No weighted Echoes are missing. Every weighted priority is already learned."
        elseif view.key == "missing" then
            emptyText = "No unlearned Echoes were found for this build's class."
        else
            emptyText = "No Echoes were found for this build's class."
        end
        missingChild.emptyLabel:SetText(emptyText)
        missingChild.emptyLabel:Show()
        missingChild:SetHeight(math.max(34, missingScroll:GetHeight()))
        missingBar:SetMinMaxValues(0, 0)
        missingBar:SetValue(0)
        if missingCountLabel then missingCountLabel:SetText("0 Echoes") end
        return
    end
    missingChild.emptyLabel:Hide()
    local currY = 0
    local ownedCount, missingCount = 0, 0
    for rowIdx, entry in ipairs(missing) do
        if entry.owned then ownedCount = ownedCount + 1 else missingCount = missingCount + 1 end
        while #missingRows < rowIdx do
            local n = #missingRows + 1
            local btn = CreateFrame("Button", nil, missingChild)
            if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
                EbonBuilds.Debug.ProtectScript(btn, "BuildOverview.MissingRow")
            end
            btn:SetPoint("LEFT", missingChild, "LEFT", 4, 0)
            btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnEnter", function(self)
                if not self._spellId then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                local spellName = GetSpellInfo(self._spellId)
                if spellName then
                    GameTooltip:AddLine(spellName, 1, 0.82, 0)
                end
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(self._spellId, 500, 1)
                    if desc and desc ~= "" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                end
                GameTooltip:AddLine(self._owned and "|cff1eff00Learned|r" or "|cffff4444Not learned|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Rows are created after the initial content-tree binding, so route
            -- their wheel events into the same Missing-list scroll context.
            EbonBuilds.Theme.BindScrollWheel(missingScroll, missingBar, 16, btn)
            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(24)
            icon:SetHeight(24)
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon = icon
            -- Owned/missing status dot, same convention as the Affixes tab:
            -- green = learned, red = not learned yet.
            local statusDot = btn:CreateTexture(nil, "OVERLAY")
            statusDot:SetSize(8, 8)
            statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
            statusDot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            btn._statusDot = statusDot
            -- Name column
            local labelName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 0)
            labelName:SetWidth(160)
            labelName:SetJustifyH("LEFT")
            btn._labelName = labelName
            -- Drop Source column (or "Learned" for owned rows)
            local labelSource = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelSource:SetPoint("TOPLEFT", labelName, "TOPRIGHT", 4, 0)
            labelSource:SetWidth(200)
            labelSource:SetJustifyH("LEFT")
            btn._labelSource = labelSource
            -- Score column (blank for owned rows)
            local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            labelScore:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -2)
            labelScore:SetWidth(54)
            labelScore:SetJustifyH("RIGHT")
            btn._labelScore = labelScore
            missingRows[n] = btn
        end
        local btn = missingRows[rowIdx]
        btn:ClearAllPoints()
        btn._spellId = entry.spellId
        btn._owned = entry.owned
        btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        if entry.owned then
            btn._statusDot:SetVertexColor(0.12, 0.85, 0.12, 1)
        else
            btn._statusDot:SetVertexColor(0.85, 0.2, 0.2, 1)
        end
        local cc = QUALITY_COLORS[entry.quality] or QUALITY_COLORS[0]
        btn._labelName:SetText(entry.name)
        btn._labelName:SetTextColor(cc[1], cc[2], cc[3], entry.owned and 0.7 or 1)
        if entry.owned then
            btn._labelSource:SetText("Learned")
            btn._labelSource:SetTextColor(0.12, 0.85, 0.12, 1)
            btn._labelScore:SetText("")
        else
            local cleanSource = (entry.dropSource or ""):gsub("^Can be found on ", "")
            btn._labelSource:SetText(cleanSource)
            btn._labelSource:SetTextColor(0.6, 0.6, 0.6, 1)
            btn._labelScore:SetText(string.format("%.0f", entry.score))
        end
        local srcH = btn._labelSource:GetStringHeight() or 16
        local rowH = math.max(26, srcH + 4)
        btn:SetHeight(rowH)
        btn:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -currY)
        btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
        btn:Show()
        currY = currY + rowH + 2
    end
    missingChild:SetHeight(math.max(1, currY))
    missingBar:SetMinMaxValues(0, math.max(0, missingChild:GetHeight() - missingScroll:GetHeight()))
    if missingCountLabel then
        if view.key == "weighted" then
            missingCountLabel:SetText(string.format("%d weighted · %d learned · %d missing", #missing, ownedCount, missingCount))
        elseif view.key == "weightedMissing" then
            missingCountLabel:SetText(string.format("%d weighted missing", missingCount))
        elseif view.key == "missing" then
            missingCountLabel:SetText(string.format("%d missing", missingCount))
        else
            missingCountLabel:SetText(string.format("%d learned · %d missing", ownedCount, missingCount))
        end
    end
end

-- Narrow regression hooks: parented 3.3.5 UI objects cannot be destroyed, so
-- repeated refreshes must plateau at the row pool's first high-water mark.
function EbonBuilds.BuildOverview._RefreshMissingForTests(build, assumeNoneOwned)
    if build then state.build = build end
    return RefreshMissing(assumeNoneOwned)
end

function EbonBuilds.BuildOverview._MissingRowPoolSizeForTests()
    return #missingRows
end

function EbonBuilds.BuildOverview._SetMissingViewForTests(key)
    missingState.view = MissingViewDefinition(key).key
end
------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchMissing, switchLogbook
local overviewHeader

local TAB_META = {
    overview = {
        title = "Build overview",
        subtitle = "Review build identity, locked Echoes, sharing, and operational status.",
    },
    stats = {
        title = "Build statistics",
        subtitle = "Identify build patterns, compare runs, and inspect evidence-backed Echo and action analytics.",
    },
    missing = {
        title = "Missing Echoes",
        subtitle = "Review weighted priorities first, then broaden the view to missing Echoes or the learned-and-missing collection view.",
    },
    logbook = {
        title = "Decision logbook",
        subtitle = "Audit automatic decisions, search events, and inspect recorded score breakdowns.",
    },
}

local function UpdateOverviewHeader(tabKey)
    local buildTitle = state.build and state.build.title or "Untitled build"
    local meta = TAB_META[tabKey] or TAB_META.overview
    if EbonBuilds.Theme and EbonBuilds.Theme.UpdatePageHeader then
        EbonBuilds.Theme.UpdatePageHeader(
            overviewHeader,
            meta.title .. " · " .. buildTitle,
            meta.subtitle
        )
    end
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetPageContext then
        EbonBuilds.MainWindow.SetPageContext(meta.title)
    end
end

local function SetOverviewTabSelected(selected)
    EbonBuilds.Theme.SetTabSelected(tab1, selected == 1)
    EbonBuilds.Theme.SetTabSelected(tab2, selected == 2)
    EbonBuilds.Theme.SetTabSelected(tab3, selected == 3)
    EbonBuilds.Theme.SetTabSelected(tab4, selected == 4)
end

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildOverview", UIParent)

    overviewHeader = EbonBuilds.Theme.CreatePageHeader(
        f,
        "Build overview",
        "Review build identity, performance, collection gaps, and automation decisions."
    )

    -- Flat intent-oriented tabs. These share the same geometry and state
    -- treatment as the build editor instead of relying on parchment templates.
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", overviewHeader, "BOTTOMLEFT", 0, -7)
    tabBar:SetPoint("TOPRIGHT", overviewHeader, "BOTTOMRIGHT", 0, -7)
    tabBar:SetHeight(28)

    tab1 = EbonBuilds.Theme.CreateTab(tabBar, "Overview")
    tab1:SetSize(112, 26)
    tab1:SetPoint("LEFT", tabBar, "LEFT", 0, 0)

    tab2 = EbonBuilds.Theme.CreateTab(tabBar, "Stats")
    tab2:SetSize(96, 26)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 6, 0)

    tab3 = EbonBuilds.Theme.CreateTab(tabBar, "Missing")
    tab3:SetSize(104, 26)
    tab3:SetPoint("LEFT", tab2, "RIGHT", 6, 0)

    tab4 = EbonBuilds.Theme.CreateTab(tabBar, "Logbook")
    tab4:SetSize(112, 26)
    tab4:SetPoint("LEFT", tab3, "RIGHT", 6, 0)

    EbonBuilds.Theme.AttachTooltip(tab1, "Build overview", "Review the build's identity, locked Echoes, notes, sharing state, and operational controls.")
    EbonBuilds.Theme.AttachTooltip(tab2, "Build statistics", "Review summary metrics, weighted Echo analytics, action patterns, and evidence-backed recommendations.")
    EbonBuilds.Theme.AttachTooltip(tab3, "Missing Echoes", "Review missing weighted priorities by default, or switch to learned-and-missing weighted priorities, all missing Echoes, or the full collection view.")
    EbonBuilds.Theme.AttachTooltip(tab4, "Decision logbook", "Search and audit automatic choices, including recorded score breakdowns when available.")

    -- Bordered workspace beneath the page title and tabs.
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -7)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 10)
    EbonBuilds.Theme.ApplyPanel(box)

    contentArea = CreateFrame("Frame", nil, box)
    contentArea:SetPoint("TOPLEFT", box, "TOPLEFT", 7, -7)
    contentArea:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -7, 7)

    -- Build Overview tab content
    overviewOuter, overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar = BuildOverviewTab(contentArea)

    -- Build Stats tab content (hidden by default)
    local statsParent = CreateFrame("Frame", nil, contentArea)
    statsParent:SetAllPoints(contentArea)
    statsParent:Hide()
    statsValueLabels, statsQualityLabels = BuildStatsTab(statsParent)

    -- Missing Echoes tab content (hidden by default)
    local missingParent = CreateFrame("Frame", nil, contentArea)
    missingParent:SetAllPoints(contentArea)
    missingParent:Hide()
    missingScroll, missingChild, missingBar = BuildMissingTab(missingParent)

    -- Build Logbook tab content (hidden by default)
    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    local function HideAllContent()
        overviewOuter:Hide()
        statsParent:Hide()
        missingParent:Hide()
        logbookParent:Hide()
        if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.Hide then
            EbonBuilds.SessionHistory.Hide()
        end
    end

    switchOverview = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter:Show()
        overviewOuter._deleteBtn:Show()
        SetOverviewTabSelected(1)
        UpdateOverviewHeader("overview")
        RefreshOverview()
    end

    switchStats = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        statsParent:Show()
        SetOverviewTabSelected(2)
        UpdateOverviewHeader("stats")
        RefreshStats()
    end

    switchMissing = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        missingParent:Show()
        SetOverviewTabSelected(3)
        UpdateOverviewHeader("missing")
        RefreshMissing()
    end

    switchLogbook = function()
        StopMissingRetry()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        logbookParent:Show()
        SetOverviewTabSelected(4)
        UpdateOverviewHeader("logbook")
        EbonBuilds.SessionHistory.Show(logbookParent)
    end

    tab1:SetScript("OnClick", function() if switchOverview then switchOverview() end end)
    tab2:SetScript("OnClick", function() if switchStats then switchStats() end end)
    tab3:SetScript("OnClick", function() if switchMissing then switchMissing() end end)
    tab4:SetScript("OnClick", function() if switchLogbook then switchLogbook() end end)

    SetOverviewTabSelected(1)
    return f
end


function EbonBuilds.BuildOverview.OpenLogbook()
    if switchLogbook then switchLogbook() end
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    state.build = context.build
    if switchOverview then switchOverview() end
    viewFrame:Show()
end

function view.Hide()
    StopMissingRetry()
    if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.Hide then
        EbonBuilds.SessionHistory.Hide()
    end
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.BuildOverview.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildOverview", view)
    EbonBuilds.EventHub.On("RUN_ENDED", function() if viewFrame and viewFrame:IsShown() then RefreshOverview() end end)
    EbonBuilds.EventHub.On("EVIDENCE_REVISION_CHANGED", function() if viewFrame and viewFrame:IsShown() then RefreshOverview() end end)
    EbonBuilds.EventHub.On("BUILD_RUNTIME_CHANGED", function() if viewFrame and viewFrame:IsShown() then RefreshOverview() end end)
end

EbonBuilds.BuildOverview.GetOwnedEchoSets = GetOwnedEchoSets
EbonBuilds.BuildOverview._NormalizeEchoName = NormalizeEchoName
EbonBuilds.BuildOverview._MissingViewDefinition = MissingViewDefinition
EbonBuilds.BuildOverview._BuildWeightedEchoSet = BuildWeightedEchoSet
EbonBuilds.BuildOverview._ComputeMissingEchoes = ComputeMissingEchoes
EbonBuilds.BuildOverview._ActionGridMetricsForTests = OverviewActionGridMetrics
