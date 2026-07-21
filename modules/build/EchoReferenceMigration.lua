local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/EchoReferenceMigration.lua
-- Lazy, atomic compatibility boundary for name-keyed and revision-bound Echo
-- references. Validation is cached per build table so hot GetActive() paths do
-- not repeatedly clone or normalize weight maps.

EbonBuilds.EchoReferenceMigration = {}

local Migration = EbonBuilds.EchoReferenceMigration
local validated = setmetatable({}, { __mode = "k" })

local function CurrentFingerprint()
    return EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetFingerprint()
end

local function IsCurrent(build, record)
    if not record then return false end
    return record.catalogFingerprint == CurrentFingerprint()
        and record.storedFingerprint == build.echoCatalogFingerprint
        and record.weights == build.echoWeightsByRef
        and record.revision == (tonumber(build.revision) or 0)
        and record.classToken == build.class
        and record.schema == tonumber(build.echoSchema)
end

local function MarkCurrent(build)
    validated[build] = {
        catalogFingerprint = CurrentFingerprint(),
        storedFingerprint = build.echoCatalogFingerprint,
        weights = build.echoWeightsByRef,
        revision = tonumber(build.revision) or 0,
        classToken = build.class,
        schema = tonumber(build.echoSchema),
    }
end

function Migration.Ensure(build)
    if type(build) ~= "table" then return false, "INVALID_BUILD" end
    if IsCurrent(build, validated[build]) then return true end
    if not EbonBuilds.Weights or not EbonBuilds.Weights.MigrateBuild then
        return false, "WEIGHTS_UNAVAILABLE"
    end
    local ok, reason = EbonBuilds.Weights.MigrateBuild(build)
    if ok then MarkCurrent(build) else validated[build] = nil end
    return ok, reason
end

function Migration.Invalidate(build)
    if build then validated[build] = nil
    else
        for key in pairs(validated) do validated[key] = nil end
    end
end

function Migration.Diagnostics(build)
    return type(build) == "table" and build.unresolvedEchoWeights or nil
end
