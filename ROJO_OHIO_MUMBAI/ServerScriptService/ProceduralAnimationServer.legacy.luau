--!strict
-- ProceduralAnimationServer
-- Bootstrap only: registers players for relay validation and clears their state on leave.
-- No developer call is required.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
local Shared = Folder:WaitForChild("Shared", 15)

local Network = require(Shared.AnimationNetwork)
local Changelog = require(Shared.Changelog)
local Connections = require(Shared.Utilities.Connections)

Network.Init()

-- Every connection this script makes is tracked so Destroy can release all of them. A server
-- Script normally lives for the whole session, but an explicit lifecycle keeps the bootstrapper
-- consistent with the client and makes it testable.
local ConnectionsList = Connections.New()
local Connected: { [Instance]: boolean } = {}

local function OnPlayerAdded(Player: Player)
    if Connected[Player] then
        return
    end
    Connected[Player] = true
    Network.RegisterPlayer(Player)
end

local function OnPlayerRemoving(Player: Player)
    if not Connected[Player] then
        return
    end
    Connected[Player] = nil
    Network.UnregisterPlayer(Player)
end

for Index, Player in ipairs(Players:GetPlayers()) do
    OnPlayerAdded(Player)
end

Connections.Add(ConnectionsList, Players.PlayerAdded:Connect(OnPlayerAdded))
Connections.Add(ConnectionsList, Players.PlayerRemoving:Connect(OnPlayerRemoving))

-- Releases the bootstrapper's connections and networking state. Idempotent.
local Server: { [string]: any } = {}

function Server.Destroy()
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
