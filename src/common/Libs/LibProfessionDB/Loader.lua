local _, ns = ...

-- LibProfessionDB's generated recipe tables are intentionally registered as
-- closures by the vendored data files. Materialize them only when a profession
-- Training/Recipes view is first opened so the optional UI stays dormant when
-- disabled.
local loaded = false

function ns:EnsureProfessionRecipeDatabase()
    local lib = LibStub and LibStub("LibProfessionDB-1.0", true)
    if loaded then return lib and lib:IsReady() and lib or nil end
    loaded = true

    local loaders = ns.LibProfessionDBDataLoaders or {}
    for i = 1, #loaders do
        local ok, err = pcall(loaders[i])
        if not ok and ns.Chat then
            ns:Chat("Trainer", "|cffff5555Recipe database load error:|r " .. tostring(err))
        end
    end

    -- Release the large closure list after its one permitted execution. The
    -- recipe tables themselves are now owned by LibProfessionDB.
    ns.LibProfessionDBDataLoaders = nil
    return lib and lib:IsReady() and lib or nil
end
