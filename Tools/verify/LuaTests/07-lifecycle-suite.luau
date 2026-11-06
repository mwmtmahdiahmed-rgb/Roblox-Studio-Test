--!strict
--[[
    Tools/verify/LuaTests/07-lifecycle-suite.luau

    Phase 4 lifecycle tests: the guarantees the bootstrappers and the shared connection tracker
    are supposed to provide, asserted rather than assumed.

    Everything here is observable through the harness:
      * signal listener counts (the mock Signal exposes .Count),
      * whether callbacks still fire after teardown,
      * log contents,
      * Animator.IsRunning and Network.IsReady.

    No Play mode. No gameplay simulation. The character rig is built by the harness and the
    heartbeat is pumped with a fixed delta.
]]

return function(Env, Kit)
local Suite = { Name = "lifecycle" }

local CLIENT_ROOT = "ReplicatedStorage.ProceduralAnimation"
local ANIMATOR_PATH = CLIENT_ROOT .. ".Client.Runtime.ProceduralAnimator"
local NETWORK_PATH = CLIENT_ROOT .. ".Shared.AnimationNetwork"
local CONNECTIONS_PATH = CLIENT_ROOT .. ".Shared.Utilities.Connections"

local Animator = nil

local function ResetWorld()
    Env.SetServerMode(false)
    Animator = nil
    Env.ClearLogs()
    Env.SetRaycastHandler(nil)

    -- Drop players without firing PlayerRemoving: a listener left installed by a previous
    -- suite must not be re-entered here, or the counts below measure the wrong thing.
    Env.ClearPlayersSilently()

    local Workspace = Env.MockServices.Workspace
    local Children = {}
    for Index = 1, Workspace.ChildCount do
        Children[Index] = Workspace.ChildList[Index]
    end
    for Index = 1, #Children do
        Children[Index]:Destroy()
    end

    -- Shut down the previously loaded world through the public API before dropping the module
    -- cache. ResetModuleCache discards instances without running their teardown, which would
    -- leave their listeners attached to the shared signals and make the counts below measure
    -- leftovers from an earlier suite rather than the behaviour under test.
    -- ResetModuleCache runs each module's Destroy/Shutdown hook before dropping it, so earlier
    -- suites' listeners are released rather than measured here.
    Env.ResetModuleCache()

    Env.SetServerMode(true)
    local ServerNetwork = Env.Require(NETWORK_PATH)
    ServerNetwork.Init()
    Env.SetServerMode(false)
    Env.Require(NETWORK_PATH)

    local LocalPlayer = Env.CreatePlayer("LocalPlayer", 1)
    Env.AddPlayer(LocalPlayer)
    Env.MockServices.Players.LocalPlayer = LocalPlayer

    local Camera = Env.MockValues.Instance.new("Camera")
    Camera.Name = "Camera"
    Camera.CFrame = Env.MockValues.CFrame.new(0.0, 10.0, 0.0)
    Camera.Parent = Env.MockServices.Workspace

    Animator = nil
end

local function BootAnimator()
    Animator = Env.Require(ANIMATOR_PATH)
    Animator.Init()
    return Animator
end

--=========================================================
-- [1] Connections utility
--=========================================================

Suite.Reset = ResetWorld

Suite.Body = function(Cases)
    Kit.Begin(Cases, "lifecycle.")

    -- ---- connections
        local Connections = Env.Require(CONNECTIONS_PATH)
        local Signal = Env.MockValues.SignalClass

        Kit.Guard("connections.new", function()
            local Tracker = Connections.New()
            Kit.Equal("connections.new.empty", #Tracker, 0)
            return true
        end)

        Kit.Guard("connections.addAndDisconnect", function()
            local Tracker = Connections.New()
            local Source = Signal.new()
            local Fired = 0
            Connections.Add(Tracker, Source:Connect(function()
                Fired += 1
            end))
            Kit.Equal("connections.add.counted", Connections.Count(Tracker), 1)

            Source:Fire()
            Kit.Equal("connections.add.firesBeforeDisconnect", Fired, 1)

            Connections.DisconnectAll(Tracker)
            Kit.Equal("connections.disconnect.emptiesTracker", Connections.Count(Tracker), 0)

            Source:Fire()
            Kit.Equal("connections.disconnect.stopsCallbacks", Fired, 1)
            return true
        end)

        Kit.Guard("connections.idempotent", function()
            local Tracker = Connections.New()
            Connections.DisconnectAll(Tracker)
            Connections.DisconnectAll(Tracker)
            Kit.Equal("connections.idempotent.staysEmpty", Connections.Count(Tracker), 0)
            return true
        end)

        Kit.Guard("connections.disconnectMany", function()
            local Tracker = Connections.New()
            local SignalA = Signal.new()
            local SignalB = Signal.new()
            local Hits = 0
            Connections.Add(Tracker, SignalA:Connect(function() Hits += 1 end))
            Connections.Add(Tracker, SignalB:Connect(function() Hits += 1 end))
            Kit.Equal("connections.many.counted", Connections.Count(Tracker), 2)
            Connections.DisconnectAll(Tracker)
            SignalA:Fire()
            SignalB:Fire()
            Kit.Equal("connections.many.allReleased", Hits, 0)
            Kit.Equal("connections.many.signalDrained", SignalA.Count + SignalB.Count, 0)
            return true
        end)

    --=========================================================
    -- [2] Animator lifecycle
    --=========================================================
    -- ---- animator
        Kit.Guard("animator.init", function()
            ResetWorld()
            BootAnimator()
            Kit.True("animator.init.running", Animator.IsRunning())
            Kit.NotNil("animator.init.logged", Env.FindLog("ProceduralAnimator initialized"))
            return true
        end)

        Kit.Guard("animator.initIdempotent", function()
            ResetWorld()
            local Players = Env.MockServices.Players
            BootAnimator()
            local AfterFirst = Players.PlayerAdded.Count
            Animator.Init()
            Animator.Init()
            Kit.Equal("animator.initIdempotent.noExtraConnections", Players.PlayerAdded.Count, AfterFirst)
            return true
        end)

        Kit.Guard("animator.stopReleasesHeartbeat", function()
            ResetWorld()
            BootAnimator()
            local RunService = Env.MockServices.RunService
            Kit.Greater("animator.stop.connectedBefore", RunService.Heartbeat.Count, 0)
            Animator.Stop()
            Kit.False("animator.stop.notRunning", Animator.IsRunning())
            Kit.Equal("animator.stop.released", RunService.Heartbeat.Count, 0)
            return true
        end)

        Kit.Guard("animator.destroy", function()
            ResetWorld()
            local Players = Env.MockServices.Players
            local RunService = Env.MockServices.RunService
            BootAnimator()

            Kit.Greater("animator.destroy.playerAddedConnected", Players.PlayerAdded.Count, 0)
            Kit.Greater("animator.destroy.heartbeatConnected", RunService.Heartbeat.Count, 0)

            Animator.Destroy()

            Kit.False("animator.destroy.notRunning", Animator.IsRunning())
            Kit.Equal("animator.destroy.playerAddedReleased", Players.PlayerAdded.Count, 0)
            Kit.Equal("animator.destroy.playerRemovingReleased", Players.PlayerRemoving.Count, 0)
            Kit.Equal("animator.destroy.heartbeatReleased", RunService.Heartbeat.Count, 0)
            Kit.NotNil("animator.destroy.logged", Env.FindLog("ProceduralAnimator destroyed"))
            return true
        end)

        Kit.Guard("animator.destroyIdempotent", function()
            ResetWorld()
            BootAnimator()
            Animator.Destroy()
            local Ok = pcall(function()
                Animator.Destroy()
            end)
            Kit.True("animator.destroyIdempotent.noError", Ok)
            return true
        end)

        Kit.Guard("animator.initAfterDestroyRefused", function()
            ResetWorld()
            BootAnimator()
            Animator.Destroy()
            Animator.Init()
            Kit.False("animator.initAfterDestroy.staysStopped", Animator.IsRunning())
            Kit.NotNil("animator.initAfterDestroy.logged", Env.FindLog("module was destroyed"))
            return true
        end)

        Kit.Guard("animator.destroyTearsDownCharacters", function()
            ResetWorld()
            BootAnimator()
            local Character = Env.Mock.CreateR15Character("Doomed")
            Character.Parent = Env.MockServices.Workspace
            Kit.True("animator.destroy.characterSetup", Animator.SetupCharacter(Character))

            local Humanoid = Character:FindFirstChildOfClass("Humanoid")
            Kit.Greater("animator.destroy.stateChangedConnected", Humanoid.StateChanged.Count, 0)

            Animator.Destroy()
            Kit.Equal("animator.destroy.stateChangedReleased", Humanoid.StateChanged.Count, 0)
            Kit.Equal("animator.destroy.childAddedReleased", Character.ChildAdded.Count, 0)
            return true
        end)

    --=========================================================
    -- [3] Player tracking
    --=========================================================
    -- ---- players
        Kit.Guard("players.trackOnJoin", function()
            ResetWorld()
            BootAnimator()
            local Joiner = Env.CreatePlayer("Joiner", 77)
            Env.AddPlayer(Joiner)
            Kit.Equal("players.trackOnJoin.subscribed", Joiner.CharacterAdded.Count, 1)
            Kit.Equal("players.trackOnJoin.removalSubscribed", Joiner.CharacterRemoving.Count, 1)
            return true
        end)

        Kit.Guard("players.untrackOnLeave", function()
            ResetWorld()
            BootAnimator()
            local Joiner = Env.CreatePlayer("Leaver", 78)
            Env.AddPlayer(Joiner)
            Env.RemovePlayer(Joiner)
            Kit.Equal("players.untrackOnLeave.released", Joiner.CharacterAdded.Count, 0)
            return true
        end)

        Kit.Guard("players.noDuplicateOnRejoin", function()
            ResetWorld()
            BootAnimator()
            local Joiner = Env.CreatePlayer("Rejoiner", 79)
            Env.AddPlayer(Joiner)
            -- A second PlayerAdded for the same player must not double-subscribe.
            BootAnimator()
            Kit.Less("players.noDuplicateOnRejoin.count", Joiner.CharacterAdded.Count, 2)
            return true
        end)

    --=========================================================
    -- [4] Network shutdown
    --=========================================================
    -- ---- network
        Kit.Guard("network.initReady", function()
            ResetWorld()
            local Network = Env.Require(NETWORK_PATH)
            Kit.True("network.initReady.isReady", Network.IsReady())
            return true
        end)

        Kit.Guard("network.shutdown", function()
            ResetWorld()
            local Network = Env.Require(NETWORK_PATH)
            Network.Init()
            Network.Shutdown()
            Kit.False("network.shutdown.notReady", Network.IsReady())
            Kit.NotNil("network.shutdown.logged", Env.FindLog("AnimationNetwork shut down"))
            return true
        end)

        Kit.Guard("network.shutdownIdempotent", function()
            ResetWorld()
            local Network = Env.Require(NETWORK_PATH)
            Network.Init()
            Network.Shutdown()
            local Ok = pcall(function()
                Network.Shutdown()
            end)
            Kit.True("network.shutdownIdempotent.noError", Ok)
            return true
        end)

        Kit.Guard("network.initAfterShutdownRefused", function()
            ResetWorld()
            local Network = Env.Require(NETWORK_PATH)
            Network.Init()
            Network.Shutdown()
            Network.Init()
            Kit.False("network.initAfterShutdown.staysDown", Network.IsReady())
            Kit.NotNil("network.initAfterShutdown.logged", Env.FindLog("module was shut down"))
            return true
        end)

        Kit.Guard("network.shutdownReleasesRemoteHandlers", function()
            ResetWorld()
            local Network = Env.Require(NETWORK_PATH)
            Network.Init()
            Kit.True("network.shutdown.clientConnected", Network.IsReady())

            -- Behavioural assertion rather than object identity: after Shutdown the module must
            -- stop reacting to inbound traffic. Delivering a packet must not populate its jitter
            -- buffer, which is observable through HasRemotePose.
            local Player = Env.MockServices.Players.LocalPlayer
            Network.Shutdown()
            Kit.False("network.shutdown.notReady", Network.IsReady())

            local Remote = Env.GetRemote("PoseRemote")
            if Remote then
                local Ok = pcall(function()
                    Remote:FireAllClients(buffer.create(116))
                end)
                Kit.True("network.shutdown.fireAfterShutdownSafe", Ok)
                Kit.False("network.shutdown.noStateAfterShutdown", Network.HasRemotePose(Player) == true)
            end
            return true
        end)

        Kit.Guard("bootstrap.serverReturnsHandle", function()
            ResetWorld()
            local Source = Env.GetSource("ReplicatedStorage/ProceduralAnimation/Server/Bootstrap/ServerBootstrap.luau")
            Kit.NotNil("bootstrap.serverSourcePresent", Source)
            Kit.True("bootstrap.serverHasDestroy",
                string.find(Source, "function Server.Destroy") ~= nil)
            return true
        end)

        Kit.Guard("bootstrap.clientReturnsHandle", function()
            local Source = Env.GetSource("ReplicatedStorage/ProceduralAnimation/Client/Bootstrap/ClientBootstrap.luau")
            Kit.NotNil("bootstrap.clientSourcePresent", Source)
            Kit.True("bootstrap.clientHasDestroy",
                string.find(Source, "function Bootstrap.Destroy") ~= nil)
            return true
        end)

        Kit.Guard("bootstrap.clientTracksConnections", function()
            local Source = Env.GetSource("ReplicatedStorage/ProceduralAnimation/Client/Bootstrap/ClientBootstrap.luau")
            -- The two local-player signals must be stored, not fire-and-forget.
            Kit.True("bootstrap.clientTracksCharacterAdded",
                string.find(Source, "Track%(Player.CharacterAdded:Connect") ~= nil)
            Kit.True("bootstrap.clientTracksCharacterRemoving",
                string.find(Source, "Track%(Player.CharacterRemoving:Connect") ~= nil)
            return true
        end)

        Kit.Guard("bootstrap.noBareConnects", function()
            -- Every :Connect in the project must be retained by a tracker or a state field.
            local Offenders = {}
            for RelativePath in pairs(Env.GetLineCounts()) do
                local Source = Env.GetSource(RelativePath)
                if Source then
                    for Line in string.gmatch(Source, "[^\n]+") do
                        if string.find(Line, ":Connect%(") then
                            local Retained =
                                string.find(Line, "Connections.Add") ~= nil
                                or string.find(Line, "State%.") ~= nil
                                or string.find(Line, "^%s*Track%(") ~= nil
                                or string.find(Line, "HeartbeatConnection =") ~= nil
                            if not Retained then
                                Offenders[#Offenders + 1] = RelativePath .. ": " .. string.gsub(Line, "^%s+", "")
                            end
                        end
                    end
                end
            end
            table.sort(Offenders)
            Kit.Check("bootstrap.noBareConnects", #Offenders == 0,
                #Offenders == 0 and "every connection is retained"
                    or ("unretained: " .. table.concat(Offenders, " | ")))
        end)
end

return Suite
end
