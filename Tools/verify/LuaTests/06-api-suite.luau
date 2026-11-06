--[[
    Tools/verify/LuaTests/06-api-suite.luau

    Public API preservation.

    Two modes share this suite:

      * "snapshot"  records the exported surface of every public module into a baseline table,
                    which the runner writes to Tools/verify/baseline/api.json.
      * "compare"   diffs the current surface against that baseline and fails on any export that
                    disappeared or changed shape.

    The point is that splitting a 1400-line module is only safe if the things it published are
    still published afterwards. Recording the surface first turns "public API preserved" from a
    claim into a measurement.

    Values are described structurally: functions as "function", numbers/strings/booleans as
    their type, tables recursively (bounded depth and cycle-safe). Function identity is
    therefore preserved across refactors while accidental removals and renames are caught.
]]

return function(Env, Kit)
local Suite = { Name = "api" }

local PUBLIC_MODULES = {
    "ReplicatedStorage.ProceduralAnimation.Shared.AnimationConfig",
    "ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath",
    "ReplicatedStorage.ProceduralAnimation.Shared.AnimationNetwork",
    "ReplicatedStorage.ProceduralAnimation.Shared.Networking.Constants.NetworkConstants",
    "ReplicatedStorage.ProceduralAnimation.Shared.Changelog",
    "ReplicatedStorage.ProceduralAnimation.Client.Runtime.ProceduralAnimator",
}

-- Exports that are private implementation detail (a factory's scratch table, live state) and
-- should not be treated as part of the public contract.
local IGNORED = {
    ["AnimationNetwork.ReceiveStates"] = true,
}

local function Describe(Value, Depth, Seen)
    Depth = Depth or 0
    Seen = Seen or {}
    local ValueType = type(Value)
    if ValueType == "function" then
        return "function"
    elseif ValueType == "number" then
        return "number"
    elseif ValueType == "string" then
        return "string"
    elseif ValueType == "boolean" then
        return "boolean"
    elseif ValueType == "buffer" then
        return "buffer:" .. tostring(buffer.len(Value))
    elseif ValueType ~= "table" then
        return ValueType
    end
    if Seen[Value] then
        return "<cycle>"
    end
    if Depth > 4 then
        return "<table>"
    end
    Seen[Value] = true

    -- Arrays (dense, integer-keyed) are described by ELEMENT SHAPE, not by index. Appending an
    -- entry to a data table such as Changelog.Entries is not an API break, but fingerprinting
    -- each index makes it look like one. What matters for the contract is that the elements are
    -- still the same kind of record.
    local IsArray = true
    local Count = 0
    for Key in pairs(Value) do
        if type(Key) ~= "number" or Key < 1 or Key % 1 ~= 0 then
            IsArray = false
            break
        end
        if Key > Count then
            Count = Key
        end
    end
    if IsArray and Count > 0 then
        local ElementShapes = {}
        local ShapeSet = {}
        for Index = 1, Count do
            local Shape = Describe(Value[Index], Depth + 1, Seen)
            if not ShapeSet[Shape] then
                ShapeSet[Shape] = true
                ElementShapes[#ElementShapes + 1] = Shape
            end
        end
        table.sort(ElementShapes)
        Seen[Value] = nil
        return "array<" .. table.concat(ElementShapes, "|") .. ">"
    end

    local Keys = {}
    for Key in pairs(Value) do
        Keys[#Keys + 1] = Key
    end
    table.sort(Keys, function(A, B)
        return tostring(A) < tostring(B)
    end)
    local Parts = table.create(#Keys)
    for Index = 1, #Keys do
        local Key = Keys[Index]
        Parts[Index] = tostring(Key) .. "=" .. Describe(Value[Key], Depth + 1, Seen)
    end
    Seen[Value] = nil
    return "{" .. table.concat(Parts, ",") .. "}"
end

local function ModuleShortName(Path)
    local Last = string.match(Path, "([^.]+)$")
    -- Baseline keys are the module's own name. Do NOT alias here: an alias that no longer matches
    -- the recorded baseline makes every lookup miss, and the comparison then passes vacuously.
    return Last or Path
end

local function CaptureSurface()
    local Surface = {}
    for Index = 1, #PUBLIC_MODULES do
        local ModulePath = PUBLIC_MODULES[Index]
        local ShortName = ModuleShortName(ModulePath)
        local Module = Env.Require(ModulePath)
        if type(Module) == "table" then
            local Entries = {}
            for Key, Value in pairs(Module) do
                local FullKey = ShortName .. "." .. tostring(Key)
                if not IGNORED[FullKey] then
                    Entries[tostring(Key)] = Describe(Value)
                end
            end
            Surface[ShortName] = Entries
        else
            Surface[ShortName] = { __moduleType = type(Module) }
        end
    end
    return Surface
end

function Suite.Reset()
    Env.ResetModuleCache()
end

function Suite.Snapshot()
    return CaptureSurface()
end

-- Compares the live surface against a previously captured baseline.
function Suite.Compare(Baseline)
    local Cases = {}
    Kit.Begin(Cases, "api.")
    local Current = CaptureSurface()

    local MissingModules = {}
    local MissingExports = {}
    local ChangedExports = {}
    local AddedExports = {}

    for ModuleName, BaselineEntries in pairs(Baseline) do
        local CurrentEntries = Current[ModuleName]
        if not CurrentEntries then
            MissingModules[#MissingModules + 1] = ModuleName
        else
            for ExportName, BaselineShape in pairs(BaselineEntries) do
                local CurrentShape = CurrentEntries[ExportName]
                if CurrentShape == nil then
                    MissingExports[#MissingExports + 1] = ModuleName .. "." .. ExportName
                elseif CurrentShape ~= BaselineShape then
                    ChangedExports[#ChangedExports + 1] =
                        ModuleName .. "." .. ExportName .. " (" .. BaselineShape .. " -> " .. CurrentShape .. ")"
                end
            end
            for ExportName in pairs(CurrentEntries) do
                if BaselineEntries[ExportName] == nil then
                    AddedExports[#AddedExports + 1] = ModuleName .. "." .. ExportName
                end
            end
        end
    end

    table.sort(MissingModules)
    table.sort(MissingExports)
    table.sort(ChangedExports)
    table.sort(AddedExports)

    Kit.Check("modules.allPresent", #MissingModules == 0,
        #MissingModules == 0 and "every public module still loads"
            or ("missing: " .. table.concat(MissingModules, ", ")))
    Kit.Check("exports.noneRemoved", #MissingExports == 0,
        #MissingExports == 0 and "no baseline export disappeared"
            or ("removed: " .. table.concat(MissingExports, ", ")))
    Kit.Check("exports.noneChangedShape", #ChangedExports == 0,
        #ChangedExports == 0 and "no baseline export changed shape"
            or ("changed: " .. table.concat(ChangedExports, ", ")))

    -- Additions are allowed (and expected while features land) but are reported so the reviewer
    -- sees exactly what grew.
    Kit.Pass("exports.additions", #AddedExports == 0 and "none" or table.concat(AddedExports, ", "))

    local TotalExports = 0
    for _, Entries in pairs(Baseline) do
        for _ in pairs(Entries) do
            TotalExports += 1
        end
    end
    Kit.Greater("exports.baselineSize", TotalExports, 0, TotalExports .. " baseline exports compared")

    return Cases
end

function Suite.Body(Cases)
    -- The runner drives Snapshot and Compare directly; this body only runs when the suite is
    -- executed on its own, in which case it records the current surface for inspection.
    Kit.Begin(Cases, "api.")
    local Surface = Suite.Snapshot()
    local ModuleCount = 0
    local ExportCount = 0
    for _, Entries in pairs(Surface) do
        ModuleCount += 1
        for _ in pairs(Entries) do
            ExportCount += 1
        end
    end
    Kit.Greater("surface.modules", ModuleCount, 0, ModuleCount .. " public modules")
    Kit.Greater("surface.exports", ExportCount, 0, ExportCount .. " exports")
end

return Suite
end
