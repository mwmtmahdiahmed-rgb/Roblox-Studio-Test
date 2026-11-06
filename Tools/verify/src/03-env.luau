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
local MockInstance = nil
-- Declared before any function that closes over them: a local declared further down would be
-- invisible to earlier functions, which then silently read a global instead.
local MockSignalClass = nil
local MockServices = nil

local Env = {}

Env.Logs = {}
Env.LogCount = 0
Env.Errors = {}
Env.ErrorCount = 0

local VirtualClock = 0.0
local DeferredQueue = {}
local DeferredCount = 0

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

local Tree = nil
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
    local Current = Tree
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
            local ServiceInstance = Tree:FindFirstChild(ServiceName)
            if ServiceInstance then
                local Current = ServiceInstance
                for SegmentIndex = 2, #Segments - 1 do
                    local FolderName = Segments[SegmentIndex]
                    local Existing = Current:FindFirstChild(FolderName)
                    if not Existing then
                        Existing = MockInstance.new("Folder")
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

                local ModuleInstance = MockInstance.new(InstanceClassName)
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

--=========================================================
-- [6] GLOBALS
--=========================================================

local function InstallGlobals(MockServices, MockValues)
    local Workspace = MockServices.Workspace
    local Game = MockServices.Game
    local ReplicatedStorage = MockServices.ReplicatedStorage
    local Players = MockServices.Players
    local RunService = MockServices.RunService
    local Vector3 = MockValues.Vector3
    local CFrame = MockValues.CFrame
    MockInstance = MockValues.Instance
    _G.Instance = MockValues.Instance
    local Enum = MockValues.Enum

    Tree = Game

    _G.game = Game
    _G.workspace = Workspace
    _G.Workspace = Workspace
    _G.Vector3 = Vector3
    _G.CFrame = CFrame
    _G.Enum = Enum
    _G.RunService = RunService
    _G.RaycastParams = MockServices.RaycastParams
    _G.OverlapParams = MockServices.RaycastParams

    -- typeof must report the class-shape tables the mock produces as instances, and keep the
    -- native answers for every other type.
    local NativeTypeof = typeof
    _G.typeof = function(Value)
        local Native = NativeTypeof(Value)
        if Native == "table" and type(Value) == "table" and rawget(Value, "ClassName") then
            return "Instance"
        end
        return Native
    end

    _G.print = function(...)
        local Parts = table.pack(...)
        local Out = {}
        for Index = 1, Parts.n do
            Out[Index] = tostring(Parts[Index])
        end
        RecordLog(table.concat(Out, " "), "print")
    end

    _G.warn = function(...)
        local Parts = table.pack(...)
        local Out = {}
        for Index = 1, Parts.n do
            Out[Index] = tostring(Parts[Index])
        end
        RecordLog(table.concat(Out, " "), "warn")
    end

    _G.debug = _G.debug or {}
    _G.debug.profilebegin = function() end
    _G.debug.profileend = function() end

    _G.task = {
        spawn = function(Callback, ...)
            local Results = table.pack(pcall(Callback, ...))
            if not Results[1] then
                RecordLog("task.spawn error: " .. tostring(Results[2]), "error")
            end
        end,
        defer = function(Callback, ...)
            DeferredCount += 1
            DeferredQueue[DeferredCount] = { Callback = Callback, Args = table.pack(...) }
        end,
        delay = function(_, Callback, ...)
            DeferredCount += 1
            DeferredQueue[DeferredCount] = { Callback = Callback, Args = table.pack(...) }
        end,
        wait = function()
            error("task.wait is not available in verification; use the frame pump instead", 2)
        end,
    }

    _G.wait = _G.task.wait

    _G.tick = function()
        return VirtualClock
    end

    local NativeClock = os.clock
    _G.os = setmetatable({
        time = os.time,
        date = os.date,
        difftime = os.difftime,
        clock = function()
            return VirtualClock
        end,
    }, { __index = os })

    -- Ensure nothing in the harness accidentally relies on wall-clock behaviour.
    _G.__NativeClock = NativeClock

    _G.script = nil
end

--=========================================================
-- [7] SIMULATION PRIMITIVES
--=========================================================

function Env.Now()
    return VirtualClock
end

function Env.AdvanceClock(Seconds)
    VirtualClock += Seconds
end

function Env.DrainDeferred()
    local Guard = 0
    while DeferredCount > 0 do
        Guard += 1
        if Guard > 4096 then
            error("deferred task queue did not settle", 2)
        end
        local Batch = DeferredQueue
        local BatchCount = DeferredCount
        DeferredQueue = {}
        DeferredCount = 0
        for Index = 1, BatchCount do
            local Entry = Batch[Index]
            local Results = table.pack(pcall(Entry.Callback, table.unpack(Entry.Args, 1, Entry.Args.n)))
            if not Results[1] then
                RecordLog("deferred task error: " .. tostring(Results[2]), "error")
            end
        end
    end
    return Guard
end

function Env.GetDeferredCount()
    return DeferredCount
end

function Env.FireHeartbeat(DeltaTime)
    VirtualClock += DeltaTime
    local RunService = MockServices and MockServices.RunService
    if not RunService or not MockSignalClass then
        return
    end
    MockSignalClass.Fire(RunService.Heartbeat, DeltaTime)
end

function Env.BindSignalClass(SignalClass, RunService)
    MockSignalClass = SignalClass
end

--=========================================================
-- [8] BOOT
--=========================================================

function Env.Boot(ServicesValue, ValuesValue)
    InstallGlobals(ServicesValue, ValuesValue)
    MockServices = ServicesValue
    Env.BindSignalClass(ValuesValue.SignalClass)
    Env.MockServices = ServicesValue
    Env.MockValues = ValuesValue
    Env.Mock = ServicesValue.MockHelpers
    return true
end

--=========================================================
-- [9] SIMULATION PASSTHROUGHS
--=========================================================

function Env.SetServerMode(Enabled)
    Env.Mock.SetServerMode(Enabled)
end

function Env.SetRaycastHandler(Handler)
    Env.Mock.SetRaycastHandler(Handler)
end

function Env.CreateCharacter(Name, Options)
    return Env.Mock.CreateR15Character(Name, Options)
end

function Env.CreatePlayer(Name, UserId)
    return Env.Mock.CreatePlayer(Name, UserId)
end

function Env.AddPlayer(Player)
    return Env.Mock.AddPlayer(Player)
end

function Env.RemovePlayer(Player)
    return Env.Mock.RemovePlayer(Player)
end

function Env.SetCharacter(Player, Character)
    return Env.Mock.SetCharacter(Player, Character)
end

function Env.GetPlayers()
    return Env.Mock.GetPlayers()
end

-- Test-support: drops the player list without firing PlayerRemoving.
function Env.ClearPlayersSilently()
    return Env.Mock.ClearPlayersSilently()
end

-- Fires RunService.Heartbeat DeltaSeconds times with a fixed step and drains deferred tasks.
-- Sets who the mock remotes treat as the calling client.
function Env.SetRemoteSender(Player)
    local Root = Env.MockServices.ReplicatedStorage:FindFirstChild("ProceduralAnimation")
    if not Root then
        return nil
    end
    local RemotesFolder = Root:FindFirstChild("Remotes")
    if not RemotesFolder then
        return nil
    end
    for Index = 1, RemotesFolder.ChildCount do
        local Child = RemotesFolder.ChildList[Index]
        if Child.OnServerEvent ~= nil then
            Child.Sender = Player
        end
    end
    return Player
end

function Env.GetRemote(Name)
    local Root = Env.MockServices.ReplicatedStorage:FindFirstChild("ProceduralAnimation")
    if not Root then
        return nil
    end
    local RemotesFolder = Root:FindFirstChild("Remotes")
    if not RemotesFolder then
        return nil
    end
    return RemotesFolder:FindFirstChild(Name)
end

function Env.PumpFrames(Count, Step)
    local DeltaTime = Step or (1.0 / 60.0)
    for _ = 1, Count do
        Env.FireHeartbeat(DeltaTime)
        Env.DrainDeferred()
    end
    return Count
end

function Env.GetTree()
    return Tree
end

-- Returns the raw source for a script, keyed by Rojo relative path.
function Env.GetSource(RojoPath)
    local Info = FindScriptInfo(RojoPath)
    return Info and Info.Source or nil
end

-- Line counts per Rojo path, for the 500-line architectural rule.
function Env.GetLineCounts()
    local Counts = {}
    for _, Info in pairs(Modules) do
        local Count = 1
        for _ in string.gmatch(Info.Source, "\n") do
            Count += 1
        end
        Counts[Info.RojoPath] = Count
    end
    return Counts
end

-- Executes a script file in its own environment with `script` bound to its instance, which is
-- how the engine runs a Script or LocalScript. Used to verify the bootstrappers for real.
-- A file mirrored into two services is registered twice; the caller names the instance path.
function Env.RunScriptFile(RojoPath)
    local Info = FindScriptInfo(RojoPath)
    if not Info then
        error("RunScriptFile: no script at " .. tostring(RojoPath), 2)
    end
    if Info.ClassName == "ModuleScript" then
        error("RunScriptFile: " .. RojoPath .. " is a ModuleScript, require it instead", 2)
    end
    RequireStack[#RequireStack + 1] = Info.Path
    local Chunk = Host.Compile(Info.Source, Info.Path)
    local ScriptInstance = FindByPath(Info.Path)
    local ScriptEnv = setmetatable({}, { __index = _G })
    ScriptEnv.script = ScriptInstance
    ScriptEnv.require = function(Specifier)
        if type(Specifier) == "table" and Specifier.__Path then
            return LoadModule(Specifier, Info.Path)
        elseif type(Specifier) == "string" then
            error("require: a script must pass a ModuleScript instance, got \"" .. Specifier .. "\"", 2)
        end
        error("require: expected a ModuleScript instance, got " .. type(Specifier), 2)
    end
    setfenv(Chunk, ScriptEnv)
    local Results = table.pack(pcall(Chunk))
    RequireStack[#RequireStack] = nil
    if not Results[1] then
        Env.ErrorCount += 1
        Env.Errors[Env.ErrorCount] = { Path = RojoPath, Message = tostring(Results[2]) }
        error(Results[2], 2)
    end
    -- Retain a returned lifecycle handle so ResetModuleCache can release the script's
    -- connections. Without this the script's listeners outlive the world they were made for.
    if type(Results[2]) == "table" then
        ScriptHandles[#ScriptHandles + 1] = Results[2]
    end

    return Results[2]
end

function Env.GetScriptInstance(RelativePath)
    return ScriptInstances[RelativePath]
end

return Env
end
