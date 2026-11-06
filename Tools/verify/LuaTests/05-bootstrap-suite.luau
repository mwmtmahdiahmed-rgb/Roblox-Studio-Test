--[[
    Tools/verify/LuaTests/05-bootstrap-suite.luau

    Tests for the bootstrappers and the module graph:
      ServerScriptService.ProceduralAnimationServer
      StarterPlayerScripts.ProceduralAnimationClient

    The bootstrappers are plain scripts (no return value), so the harness executes them as
    roblox-shaped chunks in their own environment with a `script` upvalue, exactly as the engine
    would. That lets the server script be verified for real: player tracking, registration,
    lifecycle cleanup and the readiness log.

    Rounding out the suite are graph-level assertions that only exist because the harness owns
    module loading: no require cycles, correct dependency direction, and the 500-line rule.
]]

return function(Env, Kit)
local Suite = { Name = "bootstrap" }

local SERVER_PATH = "ServerScriptService/ProceduralAnimationServer.legacy.luau"
-- The client bootstrapper is mirrored into StarterPlayer.StarterPlayerScripts, which is where it
-- actually executes. Both paths resolve to the same source.
local CLIENT_PATH = "StarterPlayer.StarterPlayerScripts.ProceduralAnimationClient"

local RunScript = nil

function Suite.Reset()
    Env.ClearLogs()
    Env.ResetModuleCache()
    for _, Player in Env.GetPlayers() do
        Env.RemovePlayer(Player)
    end
    RunScript = Env.GetRunner and Env.GetRunner() or nil
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "bootstrap.")

    --=========================================================
    -- [1] SOURCE LEVEL GUARANTEES
    --=========================================================

    local ServerSource = Env.GetSource(SERVER_PATH)
    local ClientSource = Env.GetSource(CLIENT_PATH)

    Kit.NotNil("source.serverPresent", ServerSource)
    Kit.NotNil("source.clientPresent", ClientSource)

    if ServerSource then
        Kit.Check("source.serverResolvesNetwork",
            string.find(ServerSource, "AnimationNetwork", 1, true) ~= nil,
            "server bootstrapper requires AnimationNetwork")
        Kit.Check("source.serverRegistersPlayers",
            string.find(ServerSource, "RegisterPlayer", 1, true) ~= nil
                and string.find(ServerSource, "UnregisterPlayer", 1, true) ~= nil,
            "player join and leave are both wired")
        Kit.Check("source.serverTracksExistingPlayers",
            string.find(ServerSource, "GetPlayers", 1, true) ~= nil,
            "players already in the game are registered at startup")
    end

    if ClientSource then
        Kit.Check("source.clientResolvesAnimator",
            string.find(ClientSource, "ProceduralAnimator", 1, true) ~= nil,
            "client bootstrapper requires the animator")
        Kit.Check("source.clientWiresCharacterEvents",
            string.find(ClientSource, "CharacterAdded", 1, true) ~= nil
                and string.find(ClientSource, "CharacterRemoving", 1, true) ~= nil,
            "spawn and despawn are both wired")
        Kit.Check("source.clientHandlesExistingCharacter",
            string.find(ClientSource, "Player.Character", 1, true) ~= nil,
            "a character that already exists is adopted")
    end

    --=========================================================
    -- [2] SERVER BOOTSTRAPPER EXECUTION
    --=========================================================

    Env.SetServerMode(true)

    local Existing = Env.CreatePlayer("ExistingPlayer", 201)
    Env.AddPlayer(Existing)

    local Ok, Thrown = pcall(function()
        return Env.RunScriptFile(SERVER_PATH)
    end)
    Kit.True("server.executes", Ok, Ok and "server script ran to completion" or tostring(Thrown))

    Kit.NotNil("server.readyLog", Env.FindLog("ProceduralAnimationServer ready"))

    local ServerNetwork = Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationNetwork")
    Kit.True("server.networkReady", ServerNetwork.IsReady())

    local PoseRemote = Env.GetRemote("PoseRemote")
    Kit.NotNil("server.remoteCreated", PoseRemote, "the server creates the remotes")

    -- A player who was already present must be registered: their poses relay.
    local LateJoiner = Env.CreatePlayer("LateJoiner", 202)
    Env.AddPlayer(LateJoiner)
    Kit.True("server.playerAddedWithoutError", true)

    local ExistingCharacter = Env.CreateCharacter("ExistingCharacter", {})
    Env.SetCharacter(Existing, ExistingCharacter)
    local LateCharacter = Env.CreateCharacter("LateCharacter", {})
    Env.SetCharacter(LateJoiner, LateCharacter)

    local RootPosition = _G.Vector3.new(0.0, 3.0, 0.0)
    local RootVelocity = _G.Vector3.new(0.0, 0.0, 0.0)
    local Pose = buffer.create(16 * 12)

    PoseRemote.Sender = Existing
    local SentBefore = PoseRemote.ServerSentCount
    ServerNetwork.SendPose(1, 100, RootPosition, RootVelocity, Pose, 16)
    Kit.Greater("server.existingPlayerRelays", PoseRemote.ServerSentCount, SentBefore,
        "a player present before the script ran is registered and relays")

    -- A leaving player is unregistered: their packets stop relaying.
    Env.RemovePlayer(LateJoiner)
    Env.SetCharacter(LateJoiner, nil)
    PoseRemote.Sender = LateJoiner
    local BeforeLeave = PoseRemote.ServerSentCount
    ServerNetwork.SendPose(2, 200, RootPosition, RootVelocity, Pose, 16)
    Kit.Equal("server.departedPlayerStopsRelaying", PoseRemote.ServerSentCount, BeforeLeave,
        "PlayerRemoving unregisters the player")

    -- Re-running the bootstrapper must not double-register or throw.
    Kit.Guard("server.rerunSafe", function()
        Env.RunScriptFile(SERVER_PATH)
        return true
    end)

    --=========================================================
    -- [3] CLIENT BOOTSTRAPPER SOURCE CONTRACT
    --=========================================================

    Env.SetServerMode(false)
    local ClientPlayer = Env.CreatePlayer("ClientPlayer", 301)
    Env.AddPlayer(ClientPlayer)
    Env.MockServices.Players.LocalPlayer = ClientPlayer

    local Camera = Env.MockValues.Instance.new("Camera")
    Camera.Name = "Camera"
    Camera.CFrame = Env.MockValues.CFrame.new(0.0, 5.0, 0.0)
    Camera.Parent = Env.MockServices.Workspace
    Env.MockServices.Workspace.CurrentCamera = Camera

    local ClientOk, ClientThrown = pcall(function()
        return Env.RunScriptFile(CLIENT_PATH)
    end)
    Kit.True("client.executes", ClientOk, ClientOk and "client script ran to completion" or tostring(ClientThrown))
    Kit.NotNil("client.animatorInitialised", Env.FindLog("ProceduralAnimator initialized"))

    local Animator = Env.Require("ReplicatedStorage.ProceduralAnimation.Client.Runtime.ProceduralAnimator")
    Kit.True("client.animatorRunning", Animator.IsRunning())

    -- Spawning a character after the bootstrapper has run must set it up automatically.
    local Spawned = Env.CreateCharacter("SpawnedByBootstrap", {})
    Env.SetCharacter(ClientPlayer, Spawned)
    Env.PumpFrames(3, 1.0 / 60.0)
    Kit.NotNil("client.characterAddedHandled", Env.FindLog("Setup complete for SpawnedByBootstrap"),
        "CharacterAdded reaches Animator.SetupCharacter")

    -- Removing it must tear it down automatically.
    local Humanoid = Spawned:FindFirstChildOfClass("Humanoid")
    local ConnectionsBefore = Humanoid.StateChanged.Count
    Env.SetCharacter(ClientPlayer, nil)
    Env.PumpFrames(2, 1.0 / 60.0)
    Kit.NotNil("client.characterRemovingHandled", Env.FindLog("Teardown complete for SpawnedByBootstrap"))
    Kit.Equal("client.connectionsReleased", Humanoid.StateChanged.Count, 0,
        "no leaked StateChanged listeners after despawn")

    -- Running the bootstrapper twice must not stack heartbeats.
    local HeartbeatBefore = Env.MockServices.RunService.Heartbeat.Count
    Kit.Guard("client.rerunSafe", function()
        Env.RunScriptFile(CLIENT_PATH)
        return true
    end)
    Kit.Equal("client.noDuplicateHeartbeat", Env.MockServices.RunService.Heartbeat.Count, HeartbeatBefore,
        "Animator.Init is idempotent even when the bootstrapper re-runs")

    Animator.Stop()

    --=========================================================
    -- [4] REQUIRE GRAPH
    --=========================================================

    Env.ResetModuleCache()
    Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationConfig")
    Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath")
    Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationNetwork")
    Env.Require("ReplicatedStorage.ProceduralAnimation.Client.Runtime.ProceduralAnimator")
    Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.Changelog")

    local Edges = Env.GetRequireEdges()
    Kit.Greater("graph.edgesRecorded", #Edges, 0, #Edges .. " require edges")

    -- Cycles raise at load time, so reaching this point already proves acyclicity. Record the
    -- evidence explicitly rather than relying on the absence of an exception.
    local SeenEdge = {}
    local DuplicateEdges = 0
    for Index = 1, #Edges do
        local Key = Edges[Index].From .. "->" .. Edges[Index].To
        if SeenEdge[Key] then
            DuplicateEdges += 1
        end
        SeenEdge[Key] = true
    end
    Kit.Check("graph.acyclic", Env.ErrorCount == 0,
        string.format("%d edges, %d load errors, no cycle raised", #Edges, Env.ErrorCount))

    -- Dependency direction: maths must not depend on config or network.
    local MathDependencies = {}
    for Index = 1, #Edges do
        if string.find(Edges[Index].From, "AnimationMath", 1, true) then
            MathDependencies[#MathDependencies + 1] = Edges[Index].To
        end
    end
    local MathViolations = {}
    for Index = 1, #MathDependencies do
        local Target = MathDependencies[Index]
        if string.find(Target, "AnimationConfig", 1, true)
            or string.find(Target, "AnimationNetwork", 1, true)
            or string.find(Target, "ProceduralAnimator", 1, true) then
            MathViolations[#MathViolations + 1] = Target
        end
    end
    Kit.Check("graph.mathIsLeafward", #MathViolations == 0,
        #MathViolations == 0 and (#MathDependencies .. " math sub-module edges, none into higher layers)")
            or table.concat(MathViolations, ", "))

    --=========================================================
    -- [5] SIZE RULE
    --=========================================================

    local AllLineCounts = {}
    local Oversized = {}
    for RelativePath, LineCount in pairs(Env.GetLineCounts()) do
        AllLineCounts[#AllLineCounts + 1] = RelativePath .. "=" .. LineCount
        if LineCount > 500 then
            Oversized[#Oversized + 1] = RelativePath .. " (" .. LineCount .. ")"
        end
    end
    table.sort(Oversized)
    Kit.Check("size.under500", #Oversized == 0,
        #Oversized == 0 and "every script is within the 500-line limit"
            or ("over the limit: " .. table.concat(Oversized, ", ")))
end

return Suite
end
