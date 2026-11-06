--!strict
-- ProceduralAnimation/Server/Bootstrap/ServerBootstrap
-- Bootstrap only: registers players for relay validation and clears their state on leave.
-- Automatic initialization happens at require time. No developer call is required.
--
-- This module exists instead of running the logic inline in the entry script because scripts
-- may not return values, and the lifecycle handle needs to be a real ModuleScript return for
-- embedders (and for the verification harness, which calls Destroy on cached modules).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
if not Folder then
    warn("[ProceduralAnimation] ProceduralAnimation folder did not replicate within 15s; server bootstrap aborted")
    return {
        Destroy = function(): () end,
    }
end
local Shared = Folder:WaitForChild("Shared", 15)

local Network = require(Shared.AnimationNetwork)
local Changelog = require(Shared.Changelog)
local Connections = require(Shared.Utilities.Connections)

Network.Init()

-- Every connection this module makes is tracked so Destroy can release all of them. A server
-- module normally lives for the whole session, but an explicit lifecycle keeps the bootstrapper
-- consistent with the client and makes it testable.
local ConnectionsList = Connections.New()
local Connected: { [any]: boolean } = {}

local function OnPlayerAdded(Player: any): ()
    if Connected[Player] then
        return
    end
    Connected[Player] = true
    Network.RegisterPlayer(Player)
end

local function OnPlayerRemoving(Player: any): ()
    if not Connected[Player] then
        return
    end
    Connected[Player] = nil
    Network.UnregisterPlayer(Player)
end

for _, Player in Players:GetPlayers() do
    OnPlayerAdded(Player)
end

Connections.Add(ConnectionsList, Players.PlayerAdded:Connect(OnPlayerAdded))
Connections.Add(ConnectionsList, Players.PlayerRemoving:Connect(OnPlayerRemoving))

local Server: { [string]: any } = {}

-- Releases the bootstrapper's connections and networking state. Idempotent.
function Server.Destroy(): ()
    Connections.DisconnectAll(ConnectionsList)
    for Player in pairs(Connected) do
        Connected[Player] = nil
        Network.UnregisterPlayer(Player)
    end
    Network.Shutdown()
    Changelog.Log("ProceduralAnimationServer stopped")
end

Changelog.Log("ProceduralAnimationServer ready")

return Server
