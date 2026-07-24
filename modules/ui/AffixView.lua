local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/AffixView.lua
-- Shows the character's learned-affix status, fed by the server (see
-- core/AffixServer.lua + modules/affix/Affix.lua) rather than guessed from
-- item tooltips.

EbonBuilds.AffixView = {}

local ROW_HEIGHT   = 30
local VISIBLE_ROWS = 12

local viewFrame, scrollFrame, scrollChild, scrollBar
local searchBox, filterBtn, refreshBtn, syncAhBtn, openAnvilBtn, openVendorBtn, countLabel, emptyText
local rows = {}
local state = { text = "", missingOnly = false }
local offset = 0
local filtered = {}

------------------------------------------------------------------------
-- Acquisition bridges (ProjectEbonhold + Auctionator)
------------------------------------------------------------------------
local function PeAffixBridge() return EbonBuilds.ProjectEbonholdAffixBridge end
local function AuctionBridge() return EbonBuilds.AuctionatorBridge end
local function ShowAcquisitionToast(reason)
 if not (EbonBuilds.Toast and EbonBuilds.Toast.Show) then return end
 if reason=='missing-pe' then EbonBuilds.Toast.Show('Install ProjectEbonhold to use the Enchanted Anvil from here.','info')
 elseif reason=='no-ui' then EbonBuilds.Toast.Show('ProjectEbonhold affix extraction UI is not available.','info')
 elseif reason=='no-merchant' then EbonBuilds.Toast.Show('Open a vendor first, then try again.','info')
 elseif reason=='no-affix-vendor' then EbonBuilds.Toast.Show('This ProjectEbonhold build has no affix vendor UI.','info')
 elseif reason=='missing' then EbonBuilds.Toast.Show('Install Auctionator to search the AH from here.','info')
 elseif reason=='no-ah' then EbonBuilds.Toast.Show('Open the Auction House first, then try again.','info')
 else EbonBuilds.Toast.Show('Could not open that acquisition path.','info') end
end
local function WireAcquisitionButton(btn,title,body,fn)
 btn:SetScript('OnClick',fn)
 btn:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_RIGHT') GameTooltip:SetText(title,1,1,1) if body then GameTooltip:AddLine(body,0.8,0.8,0.8,true) end GameTooltip:Show() end)
 btn:SetScript('OnLeave',function() GameTooltip:Hide() end)
end
------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------


local function BuildFilteredList()
    local all = EbonBuilds.Affix.GetLearned()
    local out = {}
    for _, a in ipairs(all) do
        local matchesText = state.text == "" or strlower(a.name or ""):find(state.text, 1, true)
        if matchesText and (not state.missingOnly or not a.learned) then
            out[#out + 1] = a
        end
    end
    table.sort(out, function(x, y)
        if x.learned ~= y.learned then
            return not x.learned  -- missing (not learned) sorts before learned
        end
        return (x.name or "") < (y.name or "")
    end)
    return out
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "AffixView.Row")
    end
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, 0.03)
    row._stripe = stripe

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local statusDot = row:CreateTexture(nil, "OVERLAY")
    statusDot:SetSize(8, 8)
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusDot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    row._statusDot = statusDot

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 6)
    name:SetJustifyH("LEFT")
    name:SetWidth(260)
    row._name = name

    local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", icon, "RIGHT", 8, -8)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.75, 0.75, 0.75, 1)
    row._sub = sub

    local ahBtn = EbonBuilds.Theme.CreateButton(row)
    ahBtn:SetSize(34, 18)
    ahBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ahBtn:SetText("AH")
    ahBtn:Hide()
    WireAcquisitionButton(ahBtn,'Search Auctionator for gear with this affix','Opens Auctionator Buy with an of <affix> search.',function(self)
        local a=self:GetParent()._affix if not a or a.learned then return end
        local bridge=AuctionBridge() if not bridge then return end
        local ok,reason=bridge.OpenAffixSearch(a.name) if not ok then ShowAcquisitionToast(reason) end end)
    row._ahBtn=ahBtn
    local anvilBtn=EbonBuilds.Theme.CreateButton(row) anvilBtn:SetSize(44,18) anvilBtn:SetPoint('RIGHT',ahBtn,'LEFT',-4,0) anvilBtn:SetText('Anvil') anvilBtn:Hide()
    WireAcquisitionButton(anvilBtn,'Open Enchanted Anvil','Extract affixes from corrupted gear.',function(self)
        local a=self:GetParent()._affix if not a or a.learned then return end
        local bridge=PeAffixBridge() if not bridge then return end
        local ok,reason=bridge.OpenExtractionUi({affixName=a.name}) if not ok then ShowAcquisitionToast(reason) end end)
    row._anvilBtn=anvilBtn
    local vendorBtn=EbonBuilds.Theme.CreateButton(row) vendorBtn:SetSize(44,18) vendorBtn:SetPoint('RIGHT',anvilBtn,'LEFT',-4,0) vendorBtn:SetText('Shop') vendorBtn:Hide()
    WireAcquisitionButton(vendorBtn,'Focus affix vendor','Brings merchant forward when at an affix vendor.',function()
        local bridge=PeAffixBridge() if not bridge then return end
        local ok,reason=bridge.OpenMerchantUi() if not ok then ShowAcquisitionToast(reason) end end)
    row._vendorBtn=vendorBtn

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local a = self._affix
        if not a then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = a.id and pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. a.id)
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(a.name or "?", 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(a.learned and "|cff1eff00Learned|r" or "|cffff4444Not learned|r")
        GameTooltip:AddLine(a.weaponOnly and "Weapon-only affix" or "Armor / any slot", 0.7, 0.7, 0.7)
        if a.applyCost and a.applyCost > 0 then
            GameTooltip:AddLine(("Apply cost: %d"):format(a.applyCost), 0.7, 0.7, 0.7)
        end
        if a.appliedCount and a.appliedCount > 0 then
            GameTooltip:AddLine(("Applied %d time(s)"):format(a.appliedCount), 0.7, 0.7, 0.7)
        end
        local bridge = AuctionBridge()
        if bridge and bridge.IsAvailable and bridge.IsAvailable() then
            local linePrice = bridge.GetAffixLinePrice and bridge.GetAffixLinePrice(a.name)
            if linePrice then
                local formatted = bridge.FormatCopper and bridge.FormatCopper(linePrice)
                if formatted then
                    GameTooltip:AddLine("Auctionator (affix line): " .. formatted, 1, 0.82, 0)
                end
            elseif not a.learned then
                GameTooltip:AddLine("Auctionator: no scan data for this affix line yet", 0.55, 0.55, 0.55)
            end
            if not a.learned then
                GameTooltip:AddLine("Click AH to search the auction house", 0.55, 0.82, 1)
            end
        end

        local peBridge = PeAffixBridge()
        if not a.learned and peBridge and peBridge.IsExtractionUiAvailable and peBridge.IsExtractionUiAvailable() then
            GameTooltip:AddLine("Click Anvil to open the Enchanted Anvil extractor", 0.55, 0.82, 1)
        end
        if not a.learned and peBridge and peBridge.IsMerchantAffixAvailable and peBridge.IsMerchantAffixAvailable() then
            GameTooltip:AddLine("Click Shop while at a vendor for affix gear", 0.55, 0.82, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function Render()
    filtered = BuildFilteredList()

    local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    scrollBar:SetMinMaxValues(0, maxOffset)

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local a = filtered[offset + i]
        if a then
            row._affix = a
            row._icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row._name:SetText(a.name or "?")
            if a.learned then
                row._name:SetTextColor(1, 1, 1, 1)
                row._statusDot:SetVertexColor(0.12, 0.85, 0.12, 1)
            else
                row._name:SetTextColor(0.6, 0.6, 0.6, 1)
                row._statusDot:SetVertexColor(0.85, 0.2, 0.2, 1)
            end
            row._sub:SetText(a.weaponOnly and "Weapon-only" or "Armor / any slot")
            if not a.learned then
                local peBridge=PeAffixBridge() local ahBridge=AuctionBridge()
                local showAnvil=peBridge and peBridge.IsExtractionUiAvailable and peBridge.IsExtractionUiAvailable()
                local showVendor=peBridge and peBridge.IsMerchantAffixAvailable and peBridge.IsMerchantAffixAvailable()
                local showAh=ahBridge and ahBridge.IsAvailable and ahBridge.IsAvailable()
                if row._anvilBtn then if showAnvil then row._anvilBtn:Show() else row._anvilBtn:Hide() end end
                if row._vendorBtn then if showVendor then row._vendorBtn:Show() else row._vendorBtn:Hide() end end
                if row._ahBtn then if showAh then row._ahBtn:Show() else row._ahBtn:Hide() end end
            else
                if row._anvilBtn then row._anvilBtn:Hide() end
                if row._vendorBtn then row._vendorBtn:Hide() end
                if row._ahBtn then row._ahBtn:Hide() end
            end
            row._stripe:SetVertexColor(1, 1, 1, (offset + i) % 2 == 0 and 0.05 or 0.02)
            row:Show()
        else
            row._affix = nil
            row:Hide()
        end
    end

    local all = EbonBuilds.Affix.GetLearned()
    local learnedCount = 0
    for _, a in ipairs(all) do if a.learned then learnedCount = learnedCount + 1 end end
    countLabel:SetText(string.format("%d / %d learned", learnedCount, #all))

    if #filtered == 0 then
        if #all == 0 then
            emptyText:SetText("No affix data yet.\n\nPress Refresh to request your learned affixes from the server.")
        else
            emptyText:SetText("No affix matches your filter.")
        end
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

    EbonBuilds.Theme.CreatePageHeader(
        f,
        "Affixes",
        "Track learned gear affixes, find collection gaps, and request a fresh server snapshot."
    )

    -- Row 1: search box, full width. Fixed offset from f (not chained off
    -- sub's rendered height) -- see the Tome Atlas header for why that
    -- matters once text can wrap.
    local searchContainer = CreateFrame("Frame", nil, f)
    searchContainer:SetHeight(20)
    searchContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58)
    searchContainer:SetPoint("RIGHT", f, "RIGHT", -38, 0)
    EbonBuilds.Theme.ApplyInput(searchContainer)
    EbonBuilds.Theme.AddSearchIcon(searchContainer)

    searchBox = CreateFrame("EditBox", nil, searchContainer)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(searchBox, "AffixView.SearchBox")
    end
    searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 21, -2)
    searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -6, 2)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchBox:SetAutoFocus(false)
    EbonBuilds.Theme.WireEditBox(searchBox, searchContainer)
    local PLACEHOLDER = "Search affix..."
    local function ShowPlaceholder(self)
        if self:GetText() == "" then
            self:SetTextColor(0.5, 0.5, 0.5, 1)
            self:SetText(PLACEHOLDER)
            self._isPlaceholder = true
        end
    end
    local function HidePlaceholder(self)
        if self._isPlaceholder then
            self:SetText("")
            self:SetTextColor(1, 1, 1, 1)
            self._isPlaceholder = false
        end
    end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        state.text = self._isPlaceholder and "" or strlower(self:GetText() or "")
        offset = 0
        Render()
    end)
    searchBox:SetScript("OnEditFocusGained", HidePlaceholder)
    searchBox:SetScript("OnEditFocusLost", function(self)
        self:SetTextColor(1, 1, 1, 1)
        ShowPlaceholder(self)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ShowPlaceholder(searchBox)

    -- Row 2: count (left), filter + refresh (right). Same single-anchor
    -- pattern as the Tome Atlas -- see its 2.6 fix for why.
    local controlsRow = CreateFrame("Frame", nil, f)
    controlsRow:SetHeight(20)
    controlsRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
    controlsRow:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    refreshBtn = EbonBuilds.Theme.CreateButton(f)
    refreshBtn:SetSize(80, 20)
    refreshBtn:SetPoint("TOPRIGHT", controlsRow, "TOPRIGHT", 0, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        EbonBuilds.Affix.RequestLearned(true)
    end)
    refreshBtn:SetScript("OnUpdate", function(self, dt)
        self._throttle = (self._throttle or 0) + dt
        if self._throttle < 0.25 then return end
        self._throttle = 0
        local remaining = EbonBuilds.Affix.GetCooldownRemaining()
        if remaining ~= self._lastRemaining then
            self._lastRemaining = remaining
            if remaining > 0 then
                self:Disable()
                self:SetText(remaining .. "s")
            else
                self:Enable()
                self:SetText("Refresh")
            end
        end
    end)

    syncAhBtn = EbonBuilds.Theme.CreateButton(f)
    syncAhBtn:SetSize(92, 20)
    syncAhBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -8, 0)
    syncAhBtn:SetText("Sync AH list")
    syncAhBtn:SetScript("OnClick", function()
        local bridge = AuctionBridge()
        if not bridge then return end
        local ok, info = bridge.SyncMissingAffixShoppingList()
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            if ok then
                EbonBuilds.Toast.Show(("Updated Auctionator list (%d missing affixes)."):format(tonumber(info) or 0), "success")
            elseif info == "missing" then
                EbonBuilds.Toast.Show("Install Auctionator to maintain an affix shopping list.", "info")
            else
                EbonBuilds.Toast.Show("Could not update the Auctionator shopping list.", "info")
            end
        end
    end)
    syncAhBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rebuild Auctionator shopping list", 1, 1, 1)
        GameTooltip:AddLine("Creates/updates \"EbonBuilds Affixes\" with search terms for every missing affix.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    syncAhBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    filterBtn = EbonBuilds.Theme.CreateButton(f)
    filterBtn:SetSize(130, 20)
    filterBtn:SetPoint("RIGHT", syncAhBtn, "LEFT", -8, 0)
    filterBtn:SetText("Show: All")
    filterBtn:SetScript("OnClick", function(self)
        state.missingOnly = not state.missingOnly
        self:SetText(state.missingOnly and "Show: Missing only" or "Show: All")
        offset = 0
        Render()
    end)

    openAnvilBtn = EbonBuilds.Theme.CreateButton(f)
    openAnvilBtn:SetSize(72, 20)
    openAnvilBtn:SetPoint("RIGHT", filterBtn, "LEFT", -8, 0)
    openAnvilBtn:SetText("Anvil")
    WireAcquisitionButton(openAnvilBtn,"Enchanted Anvil","Open ProjectEbonhold affix extraction UI.",function()
        local bridge=PeAffixBridge() if not bridge then return end
        local ok,reason=bridge.OpenExtractionUi() if not ok then ShowAcquisitionToast(reason) end end)
    openAnvilBtn:SetScript("OnUpdate",function(self,dt) self._throttle=(self._throttle or 0)+dt if self._throttle<0.5 then return end self._throttle=0
        local bridge=PeAffixBridge() local available=bridge and bridge.IsExtractionUiAvailable and bridge.IsExtractionUiAvailable()
        if available then self:Show() else self:Hide() end end)
    openVendorBtn = EbonBuilds.Theme.CreateButton(f)
    openVendorBtn:SetSize(72, 20)
    openVendorBtn:SetPoint("RIGHT", openAnvilBtn, "LEFT", -8, 0)
    openVendorBtn:SetText("Vendor")
    WireAcquisitionButton(openVendorBtn,"Affix vendor","Focus merchant when PE affix-vendor UI exists.",function()
        local bridge=PeAffixBridge() if not bridge then return end
        local ok,reason=bridge.OpenMerchantUi() if not ok then ShowAcquisitionToast(reason) end end)
    openVendorBtn:SetScript("OnUpdate",function(self,dt) self._throttle=(self._throttle or 0)+dt if self._throttle<0.5 then return end self._throttle=0
        local bridge=PeAffixBridge() local available=bridge and bridge.IsMerchantAffixAvailable and bridge.IsMerchantAffixAvailable()
        if available then self:Show() else self:Hide() end end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("LEFT", controlsRow, "LEFT", 0, 0)
    countLabel:SetPoint("TOP", controlsRow, "TOP", 0, -3)

    scrollChild = CreateFrame("Frame", nil, f)
    scrollChild:SetPoint("TOPLEFT", controlsRow, "BOTTOMLEFT", 4, -14)
    scrollChild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)

    for i = 1, VISIBLE_ROWS do
        local row = CreateRow(scrollChild)
        row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * ROW_HEIGHT)
        rows[i] = row
    end

    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER", 0, 20)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    scrollBar = EbonBuilds.Theme.CreateScrollBar(f)
    scrollBar:SetPoint("TOPLEFT", scrollChild, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMRIGHT", 6, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        offset = math.floor(value + 0.5)
        Render()
    end)

    EbonBuilds.Theme.BindSliderWheel(f, scrollBar, 1, scrollChild)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

function EbonBuilds.AffixView.Show(parent)
    if not viewFrame then
        viewFrame = BuildViewFrame(parent)
    end
    offset = 0
    Render()
    viewFrame:Show()
    return viewFrame
end

function EbonBuilds.AffixView.Hide()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.AffixView.RefreshIfMounted()
    if viewFrame and viewFrame:IsShown() then
        Render()
    end
end
