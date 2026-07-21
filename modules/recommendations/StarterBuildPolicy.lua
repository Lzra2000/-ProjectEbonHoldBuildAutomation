local addonName, EbonBuilds = ...

-- EbonBuilds: modules/recommendations/StarterBuildPolicy.lua
-- Compatibility boundary for callers that still provide the old selection map.

EbonBuilds.StarterBuildPolicy = {}

local Policy = EbonBuilds.StarterBuildPolicy

function Policy.BuildDraft(snapshot, selection, title)
    snapshot, selection = snapshot or {}, selection or {}
    local draft = EbonBuilds.WizardDraft.New(snapshot, snapshot.class, snapshot.spec)

    if selection.locks then
        for slot = EbonBuilds.Build.LOCKED_SLOTS, 1, -1 do
            local lock = draft.locks[slot]
            if lock and selection.locks[lock.name] == false then EbonBuilds.WizardDraft.RemoveLock(draft, slot) end
        end
    end
    if selection.priorities then
        for name, enabled in pairs(selection.priorities) do
            if draft.echoes[name] then EbonBuilds.WizardDraft.SetIncluded(draft, name, enabled ~= false) end
        end
    end
    if selection.optional then
        for name, enabled in pairs(selection.optional) do
            if draft.echoes[name] then EbonBuilds.WizardDraft.SetIncluded(draft, name, enabled == true) end
        end
    end
    return EbonBuilds.WizardDraft.CreateBuildData(draft, title)
end
