local addonName, EbonBuilds = ...

-- EbonBuilds: core/Modules.lua
-- Deterministic module registry. Registration happens while files load;
-- lifecycle execution happens after ADDON_LOADED through InitPipeline.

EbonBuilds.Modules = {}
local Modules = EbonBuilds.Modules

Modules.DATABASE    = 10
Modules.CORE        = 20
Modules.RUNTIME     = 30
Modules.UI_SHELL    = 40
Modules.UI_DEFERRED = 50
Modules.BACKGROUND  = 60

local registry = {}
local order = {}
local state = {}
local frozen = false

local function Report(name, err)
    local log = EbonBuilds.ErrorLog
    if log and type(log.Record) == "function" then
        log.Record("Modules." .. tostring(name), err)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444EbonBuilds module error:|r " .. tostring(name) .. ": " .. tostring(err))
    end
end

local function ValidDependencies(dependencies)
    if dependencies == nil then return true end
    if type(dependencies) ~= "table" then return false end
    for index = 1, #dependencies do
        if type(dependencies[index]) ~= "string" then return false end
    end
    return true
end

function Modules.Register(name, descriptor)
    if frozen or type(name) ~= "string" or name == "" or type(descriptor) ~= "table" then return false end
    if registry[name] then return false end
    if type(descriptor.start) ~= "function" then return false end
    if not ValidDependencies(descriptor.dependencies) then return false end

    descriptor.name = name
    descriptor.phase = tonumber(descriptor.phase) or Modules.RUNTIME
    descriptor.dependencies = descriptor.dependencies or {}
    registry[name] = descriptor
    order[#order + 1] = name
    state[name] = "registered"
    return true
end

function Modules.RegisterLegacy(name, phase, serviceName, methodName, dependencies)
    return Modules.Register(name, {
        phase = phase,
        dependencies = dependencies,
        start = function()
            local service = EbonBuilds[serviceName]
            local method = service and service[methodName or "Init"]
            if type(method) ~= "function" then
                error("missing service initializer " .. tostring(serviceName) .. "." .. tostring(methodName or "Init"))
            end
            return method()
        end,
    })
end

local function Start(name, stack)
    local current = state[name]
    if current == "started" then return true end
    if current == "starting" then
        error("circular module dependency at " .. tostring(name))
    end

    local descriptor = registry[name]
    if not descriptor then error("unknown module dependency " .. tostring(name)) end
    state[name] = "starting"
    stack[name] = true

    local dependencies = descriptor.dependencies
    for index = 1, #dependencies do
        local dependency = dependencies[index]
        if stack[dependency] then error("circular module dependency " .. tostring(name) .. " -> " .. tostring(dependency)) end
        Start(dependency, stack)
    end

    stack[name] = nil
    local ok, result = pcall(descriptor.start)
    if not ok then
        state[name] = "failed"
        Report(name, result)
        return false, result
    end

    state[name] = "started"
    descriptor.result = result
    return true, result
end

function Modules.Start(name)
    if type(name) ~= "string" then return false end
    return Start(name, {})
end

function Modules.GetPhaseOrder(phase, destination)
    destination = destination or {}
    for index = #destination, 1, -1 do destination[index] = nil end
    for index = 1, #order do
        local name = order[index]
        local descriptor = registry[name]
        if descriptor and descriptor.phase == phase then destination[#destination + 1] = name end
    end
    return destination
end

function Modules.GetState(name)
    return state[name]
end

function Modules.Freeze()
    frozen = true
end

function Modules.IsFrozen()
    return frozen
end

-- ValidateGraph(): pure structural check over every currently-registered
-- module's dependency list -- unknown dependency names and circular
-- chains, with NO side effects (never calls a module's start function).
-- Start()'s own cycle/unknown-dependency detection only fires at real
-- runtime, module by module, as each one is actually started -- this
-- exists so the whole graph can be checked once, headlessly, in CI,
-- instead of a typo'd dependency name only surfacing when a player
-- happens to load the addon.
function Modules.ValidateGraph()
    local problems = {}
    local visitState = {} -- [name] = "visiting" | "done"

    local function Visit(name, chain)
        if visitState[name] == "done" then return end
        if visitState[name] == "visiting" then
            problems[#problems + 1] = "circular dependency: " .. table.concat(chain, " -> ") .. " -> " .. name
            return
        end
        local descriptor = registry[name]
        if not descriptor then
            problems[#problems + 1] = "unknown module referenced as a dependency: " .. tostring(name)
            return
        end
        visitState[name] = "visiting"
        chain[#chain + 1] = name
        local dependencies = descriptor.dependencies or {}
        for index = 1, #dependencies do
            Visit(dependencies[index], chain)
        end
        chain[#chain] = nil
        visitState[name] = "done"
    end

    for index = 1, #order do
        Visit(order[index], {})
    end

    return { ok = #problems == 0, problems = problems }
end

function Modules.ResetForTests()
    for key in pairs(registry) do registry[key] = nil end
    for key in pairs(state) do state[key] = nil end
    for index = #order, 1, -1 do order[index] = nil end
    frozen = false
end
