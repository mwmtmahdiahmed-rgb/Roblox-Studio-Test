--!strict
--[[
    Tools/verify/src/03b-env-simulation.luau

    Part 2 of the Env bridge for the offline verification harness (pairs with
    03-env.luau). Attaches the simulation half of the Env table to the handle built by
    03-env.luau:

      * the Roblox globals the framework expects (game, workspace, task, os, tick, typeof),
      * the deterministic simulation primitives (virtual clock, heartbeat pump, deferred
        queue, connection bookkeeping), and
      * the passthrough accessors to the mock services,

    plus the script-introspection helpers, which keep working through the Env.__Context
    bridge table the core chunk stashes (module registry, require graph, host compiler).

    The runner loads this chunk immediately after 03-env.luau and before Boot is called,
    so Env.InstallGlobals and Env.BindSignalClass exist by the time the world boots.
]]

return function(Env)
local Ctx = Env.__Context
local VirtualClock = 0.0
local DeferredQueue = {}
local DeferredCount = 0

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
    Env.MockInstance = MockValues.Instance
    _G.Instance = MockValues.Instance
    local Enum = MockValues.Enum

    Env.Tree = Game

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
        Env.RecordLog(table.concat(Out, " "), "print")
    end

    _G.warn = function(...)
        local Parts = table.pack(...)
        local Out = {}
        for Index = 1, Parts.n do
            Out[Index] = tostring(Parts[Index])
        end
        Env.RecordLog(table.concat(Out, " "), "warn")
    end

    _G.debug = _G.debug or {}
    _G.debug.profilebegin = function() end
    _G.debug.profileend = function() end

    _G.task = {
        spawn = function(Callback, ...)
            local Results = table.pack(pcall(Callback, ...))
            if not Results[1] then
                Env.RecordLog("task.spawn error: " .. tostring(Results[2]), "error")
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
Env.InstallGlobals = InstallGlobals

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
                Env.RecordLog("deferred task error: " .. tostring(Results[2]), "error")
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
    local RunService = Env.MockServices and Env.MockServices.RunService
    local SignalClass = Env.MockSignalClass
    if not RunService or not SignalClass then
        return
    end
    SignalClass.Fire(RunService.Heartbeat, DeltaTime)
end

function Env.BindSignalClass(SignalClass)
    Env.MockSignalClass = SignalClass
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
    return Env.Tree
end

-- Returns the raw source for a script, keyed by Rojo relative path.
function Env.GetSource(RojoPath)
    local Info = Ctx.FindScriptInfo(RojoPath)
    return Info and Info.Source or nil
end

-- Line counts per Rojo path, for the 500-line architectural rule.
function Env.GetLineCounts()
    local Counts = {}
    for _, Info in pairs(Ctx.Modules) do
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
    local Info = Ctx.FindScriptInfo(RojoPath)
    if not Info then
        error("RunScriptFile: no script at " .. tostring(RojoPath), 2)
    end
    if Info.ClassName == "ModuleScript" then
        error("RunScriptFile: " .. RojoPath .. " is a ModuleScript, require it instead", 2)
    end
    Ctx.RequireStack[#Ctx.RequireStack + 1] = Info.Path
    local Chunk = Ctx.HostGet().Compile(Info.Source, Info.Path)
    local ScriptInstance = Ctx.FindByPath(Info.Path)
    local ScriptEnv = setmetatable({}, { __index = _G })
    ScriptEnv.script = ScriptInstance
    ScriptEnv.require = function(Specifier)
        if type(Specifier) == "table" and Specifier.__Path then
            return Ctx.LoadModule(Specifier, Info.Path)
        elseif type(Specifier) == "string" then
            error("require: a script must pass a ModuleScript instance, got \"" .. Specifier .. "\"", 2)
        end
        error("require: expected a ModuleScript instance, got " .. type(Specifier), 2)
    end
    setfenv(Chunk, ScriptEnv)
    local Results = table.pack(pcall(Chunk))
    Ctx.RequireStack[#Ctx.RequireStack] = nil
    if not Results[1] then
        Env.ErrorCount += 1
        Env.Errors[Env.ErrorCount] = { Path = RojoPath, Message = tostring(Results[2]) }
        error(Results[2], 2)
    end
    -- Retain a returned lifecycle handle so ResetModuleCache can release the script's
    -- connections. Without this the script's listeners outlive the world they were made for.
    if type(Results[2]) == "table" then
        Ctx.ScriptHandles[#Ctx.ScriptHandles + 1] = Results[2]
    end

    return Results[2]
end

function Env.GetScriptInstance(RelativePath)
    return Ctx.ScriptInstances[RelativePath]
end

return Env
end
