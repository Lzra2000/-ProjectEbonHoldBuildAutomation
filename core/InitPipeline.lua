local addonName, EbonBuilds = ...

-- EbonBuilds: core/InitPipeline.lua
-- Frame-budgeted lifecycle runner. Existing module initializers are isolated
-- into one coroutine step each; database migrations can yield internally.

EbonBuilds.InitPipeline = {}
local Pipeline = EbonBuilds.InitPipeline
local phaseScratch = {}
local running = false
local complete = false
local currentPhase
local currentModule
local backgroundStarted = false
local analyticsEmitted = false
local databaseToken
local aggregateToken

local PHASES = {
    EbonBuilds.Modules.DATABASE,
    EbonBuilds.Modules.CORE,
    EbonBuilds.Modules.RUNTIME,
    EbonBuilds.Modules.UI_SHELL,
    EbonBuilds.Modules.UI_DEFERRED,
    EbonBuilds.Modules.BACKGROUND,
}

local function Emit(signal, ...)
    if EbonBuilds.EventHub and EbonBuilds.EventHub.Bump then
        EbonBuilds.EventHub.Bump(signal, ...)
    end
end


local function MaybeEmitAnalyticsReady()
    if analyticsEmitted or not backgroundStarted then return false end
    local databaseReady = not EbonBuilds.Database
        or not EbonBuilds.Database.IsReady
        or EbonBuilds.Database.IsReady()
    local aggregatesReady = not EbonBuilds.Aggregates
        or not EbonBuilds.Aggregates.IsBackfillComplete
        or EbonBuilds.Aggregates.IsBackfillComplete()
    if not databaseReady or not aggregatesReady then return false end

    analyticsEmitted = true
    if databaseToken and EbonBuilds.EventHub then EbonBuilds.EventHub.Off(databaseToken) end
    if aggregateToken and EbonBuilds.EventHub then EbonBuilds.EventHub.Off(aggregateToken) end
    databaseToken = nil
    aggregateToken = nil
    Emit("ANALYTICS_READY")
    return true
end

local function Run()
    for phaseIndex = 1, #PHASES do
        local phase = PHASES[phaseIndex]
        currentPhase = phase
        local names = EbonBuilds.Modules.GetPhaseOrder(phase, phaseScratch)
        for index = 1, #names do
            currentModule = names[index]
            EbonBuilds.Modules.Start(currentModule)
            coroutine.yield(0)
        end

        if phase == EbonBuilds.Modules.CORE then
            Emit("CORE_READY")
        elseif phase == EbonBuilds.Modules.RUNTIME then
            Emit("AUTOMATION_READY")
        elseif phase == EbonBuilds.Modules.UI_SHELL then
            Emit("APP_READY")
        elseif phase == EbonBuilds.Modules.BACKGROUND then
            backgroundStarted = true
            MaybeEmitAnalyticsReady()
        end
    end

    currentPhase = nil
    currentModule = nil
    running = false
    complete = true
end

function Pipeline.Start()
    if running or complete then return false end
    running = true
    EbonBuilds.Modules.Freeze()
    if EbonBuilds.EventHub then
        databaseToken = EbonBuilds.EventHub.On("DATABASE_READY", MaybeEmitAnalyticsReady, "InitPipeline")
        aggregateToken = EbonBuilds.EventHub.On("ANALYTICS_BACKFILL_COMPLETE", MaybeEmitAnalyticsReady, "InitPipeline")
    end
    return EbonBuilds.Scheduler.Coroutine(
        "bootstrap.initPipeline",
        Run,
        EbonBuilds.Scheduler.INTERACTIVE,
        false,
        "InitPipeline"
    )
end

function Pipeline.IsRunning()
    return running
end

function Pipeline.IsComplete()
    return complete
end

function Pipeline.GetProgress()
    return currentPhase, currentModule
end
