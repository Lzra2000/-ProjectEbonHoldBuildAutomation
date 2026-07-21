local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/WeightsView.lua
-- Host for Echo filters and rank-specific value table.

EbonBuilds.WeightsView = {}

local viewFrame

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    local header = EbonBuilds.Theme.CreatePageHeader(
        f,
        "Echo priorities",
        "Set rank values, filter the catalog, and inspect the final score automation will use."
    )
    f._pageHeader = header
    f._header = header._title
    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
    EbonBuilds.Filters.Init(viewFrame)
    EbonBuilds.EchoTable.Init(viewFrame)
end

local function RefreshHeader()
    if not viewFrame then return end
    local build = EbonBuilds.Build.GetActive()
    local title = build and ("Echo priorities · " .. (build.title or "")) or "Echo priorities"
    EbonBuilds.Theme.UpdatePageHeader(viewFrame._pageHeader, title, "Set rank values, filter the catalog, and inspect the final score automation will use.")
end

function EbonBuilds.WeightsView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshHeader()
    viewFrame:Show()
end

function EbonBuilds.WeightsView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.WeightsView.Init()
    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(RefreshHeader)
    end
end
