--!strict
--[[
    Tools/verify/src/03-env.luau

    Part 3 of the offline Roblox environment used by Tools/verify.

    Env is the bridge between the sandboxed Luau VM and the real framework source. It:

      * installs the Roblox globals (game, workspace, script, require, task, CFrame, ...)
        that framework modules expect to be present,
      * mirrors the Rojo folder layout into a real Instance tree so `script.Parent`
        navigation inside the modules resolves exactly as it does in Studio,
      * loads module source files through a host compiler callback and executes each one in
        its own environment (so per-module `script` and relative `require` work without
        rewriting the source), and
      * exposes deterministic simulation primitives (heartbeat pump, deferred task queue,
        virtual clock, raycast handler) so runtime logic can be driven frame by frame.

    Module loading records the require graph and rejects cycles, which is what lets the
    verification report state "no circular dependencies" as a measured fact.
]]

--=========================================================
-- [1] CONSTANTS
--=========================================================

return function(MockValues, MockServices)
local Host = nil

local Env = {}

Env.Logs = {}
Env.LogCount = 0
Env.Errors = {}
Env.ErrorCount = 0

-- Keyed by dotted instance path ("ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath").
local Modules = {}

-- A file mirrored into two services is registered twice; callers may name either the Rojo
-- path or the dotted instance path.
function FindScriptInfo(RojoPathOrInstancePath)
    for _, Candidate in pairs(Modules) do
        if Candidate.RojoPath == RojoPathOrInstancePath or Candidate.Path == RojoPathOrInstancePath then
            return Candidate
        end
    end
    return nil
end
local ModuleCache = {}
local Loading = {}
local RequireStack = {}
local RequireEdges = {}

local ScriptInstances = {}

--=========================================================
-- [2] HOST CALLBACKS
--=========================================================

-- Called by the runner once, before Boot.
-- Expected keys: Compile(Source, Name) -> function, Clock() -> number, Print(...), Warn(...).
function Env.SetHost(Callbacks)
    Host = Callbacks
end

local function RecordLog(Message, Level)
    if Env.LogCount >= 4096 then
        return
    end
    Env.LogCount += 1
    Env.Logs[Env.LogCount] = { Text = tostring(Message), Level = Level }
end

Env.RecordLog = RecordLog  -- exposed for the simulation chunk (03b-env-simulation.luau)

function Env.ClearLogs()
    Env.Logs = {}
    Env.LogCount = 0
end

function Env.FindLog(Pattern)
    for Index = 1, Env.LogCount do
        if string.find(Env.Logs[Index].Text, Pattern, 1, true) then
            return Env.Logs[Index].Text
        end
    end
    return nil
end

--=========================================================
-- [3] INSTANCE PATHS
--=========================================================

local function ComputePath(InstanceValue)
    if InstanceValue.__Path then
        return InstanceValue.__Path
    end
    local Segments = {}
    local Count = 0
    local Current = InstanceValue
    while Current do
        Count += 1
        Segments[Count] = Current.Name
        Current = Current.Parent
    end
    local Out = ""
    for Index = Count, 1, -1 do
        if Out == "" then
            Out = Segments[Index]
        else
            Out = Out .. "." .. Segments[Index]
        end
    end
    return Out
end

local function FindByPath(Path)
    local Segments = string.split(Path, ".")
    local Current = Env.Tree
    for Index = 1, #Segments do
        local Segment = Segments[Index]
        local Found = nil
        for ChildIndex = 1, Current.ChildCount do
            if Current.ChildList[ChildIndex].Name == Segment then
                Found = Current.ChildList[ChildIndex]
                break
            end
        end
        if not Found then
            return nil
        end
        Current = Found
    end
    return Current
end

--=========================================================
-- [4] MODULE REGISTRY
--=========================================================

-- ProjectFiles is a map of Rojo path -> source text, supplied by the runner.
function Env.LoadProject(ProjectFiles)
    local Sorted = {}
    for RelativePath in pairs(ProjectFiles) do
        Sorted[#Sorted + 1] = RelativePath
    end
    table.sort(Sorted)

    for Index = 1, #Sorted do
        local RelativePath = Sorted[Index]
        local Segments = string.split(RelativePath, "/")
        local FileName = Segments[#Segments]
        local ServiceName = Segments[1]

        if #Segments >= 2 and ServiceName ~= "Tools" then
            local ServiceInstance = Env.Tree:FindFirstChild(ServiceName)
            if ServiceInstance then
                local Current = ServiceInstance
                for SegmentIndex = 2, #Segments - 1 do
                    local FolderName = Segments[SegmentIndex]
                    local Existing = Current:FindFirstChild(FolderName)
                    if not Existing then
                        Existing = Env.MockInstance.new("Folder")
                        Existing.Name = FolderName
                        Existing.Parent = Current
                    end
                    Current = Existing
                end

                -- Rojo naming: Name.luau -> ModuleScript "Name", Name.local.luau -> LocalScript,
                -- Name.server.luau -> Script, Name.legacy.luau -> Script.
                local BaseName = FileName
                local InstanceClassName = "ModuleScript"
                local Suffix = string.match(FileName, "%.([a-z]+)%.luau$")
                if Suffix == "local" then
                    InstanceClassName = "LocalScript"
                    BaseName = string.gsub(FileName, "%.local%.luau$", "")
                elseif Suffix == "server" then
                    InstanceClassName = "Script"
                    BaseName = string.gsub(FileName, "%.server%.luau$", "")
                elseif Suffix == "legacy" then
                    InstanceClassName = "Script"
                    BaseName = string.gsub(FileName, "%.legacy%.luau$", "")
                else
                    BaseName = string.gsub(FileName, "%.luau$", "")
                end

                local ModuleInstance = Env.MockInstance.new(InstanceClassName)
                ModuleInstance.Name = BaseName
                ModuleInstance.Parent = Current
                -- Dotted instance path, which is what require() resolves against.
                local Parts = {}
                for SegmentIndex = 1, #Segments - 1 do
                    Parts[#Parts + 1] = Segments[SegmentIndex]
                end
                Parts[#Parts + 1] = BaseName
                local InstancePath = table.concat(Parts, ".")
                ModuleInstance.__Path = InstancePath
                ModuleInstance.__RojoPath = RelativePath
                ModuleInstance.__Service = ServiceName

                Modules[InstancePath] = {
                    Path = InstancePath,
                    RojoPath = RelativePath,
                    Source = ProjectFiles[RelativePath],
                    Instance = ModuleInstance,
                    ClassName = InstanceClassName,
                    Service = ServiceName,
                }
                ScriptInstances[RelativePath] = ModuleInstance
            end
        end
    end

    return ScriptInstances
end

function Env.GetModules()
    return Modules
end

function Env.GetRequireEdges()
    return RequireEdges
end

function Env.GetLoadingDepth()
    return #RequireStack
end

function Env.ResolveModulePath(RelativePath)
    return FindByPath(RelativePath)
end

--=========================================================
-- [5] REQUIRE
--=========================================================

local function NormaliseRelative(BasePath, Specifier)
    -- BasePath is a dotted instance path to the requiring script.
    local Segments = string.split(BasePath, ".")
    -- Drop the script name itself.
    table.remove(Segments)

    local Parts = string.split(Specifier, "/")
    for Index = 1, #Parts do
        local Part = Parts[Index]
        if Part == "." then
            -- no-op
        elseif Part == ".." then
            if #Segments > 0 then
                table.remove(Segments)
            end
        else
            Segments[#Segments + 1] = Part
        end
    end
    return table.concat(Segments, ".")
end

local function LoadModule(InstanceValue, RequesterPath)
    local Path = InstanceValue.__Path
    if not Path then
        error("require: " .. tostring(InstanceValue.Name) .. " is not part of the project", 3)
    end

    local Cached = ModuleCache[Path]
    if Cached then
        return Cached[1]
    end

    if Loading[Path] then
        local Chain = table.concat(RequireStack, " -> ")
        error("circular require detected: " .. Chain .. " -> " .. Path, 3)
    end

    local Info = Modules[Path]
    if not Info then
        error("require: no source registered for " .. Path, 3)
    end

    Loading[Path] = true
    RequireStack[#RequireStack + 1] = Path

    if RequesterPath then
        RequireEdges[#RequireEdges + 1] = { From = RequesterPath, To = Path }
    end

    local Chunk = Host.Compile(Info.Source, Path)
    local ModuleEnv = setmetatable({}, { __index = _G })
    ModuleEnv.script = InstanceValue
    ModuleEnv.require = function(Specifier)
        local TargetPath
        if type(Specifier) == "table" and Specifier.__Path then
            -- Roblox style: require(script.Parent.AnimationMath). The instance already carries
            -- its Rojo path, so it resolves directly.
            TargetPath = Specifier.__Path
        elseif type(Specifier) == "string" then
            if string.sub(Specifier, 1, 1) == "." then
                TargetPath = NormaliseRelative(Path, Specifier)
            else
                TargetPath = Specifier
            end
        else
            error("require: expected a ModuleScript instance or a path string, got " .. type(Specifier), 2)
        end
        local Target = FindByPath(TargetPath)
        if not Target then
            error("require: module not found: " .. tostring(Specifier) .. " (resolved " .. tostring(TargetPath) .. ")", 2)
        end
        return LoadModule(Target, Path)
    end

    setfenv(Chunk, ModuleEnv)

    local Results = table.pack(pcall(Chunk))

    Loading[Path] = nil
    RequireStack[#RequireStack] = nil

    if not Results[1] then
        Env.ErrorCount += 1
        Env.Errors[Env.ErrorCount] = { Path = Path, Message = tostring(Results[2]) }
        error("module " .. Path .. " failed to load: " .. tostring(Results[2]), 3)
    end

    local Value = Results[2]
    ModuleCache[Path] = { Value }
    return Value
end

-- Public entry point. Accepts an instance path such as
-- "ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath".
function Env.Require(ModulePath)
    local Target = FindByPath(ModulePath)
    if not Target then
        error("Env.Require: module not found at " .. tostring(ModulePath), 2)
    end
    return LoadModule(Target, nil)
end

function Env.RequireInstance(InstanceValue)
    return LoadModule(InstanceValue, nil)
end

-- Scripts that returned a lifecycle handle, so teardown can release their connections.
-- A Script/LocalScript in this project returns a table with Destroy(); the harness retains it
-- the same way a host would, instead of dropping the value on the floor.
local ScriptHandles = {}

local function DestroyScriptHandles()
    for Index = #ScriptHandles, 1, -1 do
        local Handle = ScriptHandles[Index]
        if type(Handle) == "table" and type(Handle.Destroy) == "function" then
            pcall(Handle.Destroy)
        end
        ScriptHandles[Index] = nil
    end
    table.clear(ScriptHandles)
end

-- Runs every cached module's shutdown hook, in any order, before the cache is dropped.
-- ResetModuleCache discards instances without running teardown, which leaves their listeners
-- attached to the shared services. Suites call this so each one starts from a clean world.
function Env.ShutdownCachedModules()
    local Paths = {}
    for Path in pairs(ModuleCache) do
        Paths[#Paths + 1] = Path
    end
    table.sort(Paths)
    for Index = 1, #Paths do
        local Cached = ModuleCache[Paths[Index]]
        local Module = Cached and Cached[1]
        if type(Module) == "table" then
            if type(Module.Destroy) == "function" then
                pcall(Module.Destroy)
            elseif type(Module.Shutdown) == "function" then
                pcall(Module.Shutdown)
            end
        end
    end
end

function Env.IsCached(ModulePath)
    return ModuleCache[ModulePath] ~= nil
end

-- Drops one module from the cache so it can be re-required under a different side
-- (server vs client), which is how the harness simulates both roles in one VM.
function Env.PurgeCache(ModulePath)
    ModuleCache[ModulePath] = nil
end

-- Drops every cached module. Runs each cached module's Destroy/Shutdown hook first: discarding
-- instances without teardown leaves their listeners attached to the shared mock services, so the
-- next suite would observe the previous suite's connections. Doing it here means no individual
-- suite has to remember.
function Env.ResetModuleCache()
    DestroyScriptHandles()
    Env.ShutdownCachedModules()
    ModuleCache = {}
    RequireEdges = {}
    Loading = {}
    RequireStack = {}
end


-- Bridge to the simulation chunk (03b-env-simulation.luau): the introspection entry points
-- that stay in this file keep their closure state; the simulation chunk reaches it through
-- this table instead of re-implementing the module registry.
Env.__Context = {
    FindScriptInfo = FindScriptInfo,
    FindByPath = FindByPath,
    LoadModule = LoadModule,
    Modules = Modules,
    ScriptInstances = ScriptInstances,
    RequireStack = RequireStack,
    ScriptHandles = ScriptHandles,
    HostGet = function() return Host end,
}

function Env.Boot(ServicesValue, ValuesValue)
    Env.MockServices = ServicesValue
    Env.MockValues = ValuesValue
    Env.Mock = ServicesValue.MockHelpers
    Env.InstallGlobals(ServicesValue, ValuesValue)
    Env.BindSignalClass(ValuesValue.SignalClass)
    return true
end

return Env
end
