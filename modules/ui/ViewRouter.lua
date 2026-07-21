local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/ViewRouter.lua
-- Responsibility: register named views and swap which one fills the right panel.
-- A view is a table with Show(container, context) and Hide() methods.

EbonBuilds.ViewRouter = {}

local views       = {}
local currentName = nil
local container   = nil

local PAGE_TITLES = {
    welcome = "Welcome",
    publicBuilds = "Public Builds",
    tomeAtlas = "Tome Atlas",
    affixes = "Affixes",
    buildWizard = "New Build",
    buildTabs = "Edit Build",
    buildOverview = "Build Overview",
}

function EbonBuilds.ViewRouter.SetContainer(frame)
    container = frame
end

function EbonBuilds.ViewRouter.Register(name, view)
    views[name] = view
end

function EbonBuilds.ViewRouter.Show(name, context)
    if not container then return end
    local view = views[name]
    if not view then return end

    if currentName and currentName ~= name then
        local prev = views[currentName]
        if prev and prev.Hide then prev.Hide() end
    end
    currentName = name
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.SetPageContext then
        local title = PAGE_TITLES[name] or name
        if name == "buildTabs" and context and context.mode == "create" then title = "New Build" end
        EbonBuilds.MainWindow.SetPageContext(title)
    end
    if EbonBuilds.BuildList and EbonBuilds.BuildList.SetSelectedNavigation then
        EbonBuilds.BuildList.SetSelectedNavigation(name)
    end
    if EbonBuilds.ClickTrace then
        EbonBuilds.ClickTrace.Log("show", name)
    end
    view.Show(container, context)
end

function EbonBuilds.ViewRouter.Current()
    return currentName
end
