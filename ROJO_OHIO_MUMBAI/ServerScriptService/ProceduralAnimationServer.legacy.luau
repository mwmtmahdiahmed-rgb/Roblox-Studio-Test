-- ProceduralAnimationServer
-- Bootstrap only: registers players for relay validation and clears their state on leave.
-- No developer call is required.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
local Shared = Folder:WaitForChild("Shared", 15)

local Network = require(Shared.AnimationNetwork)
local Changelog = require(Shared.Changelog)

Network.Init()

local Connected = {}

local function OnPlayerAdded(Player)
    if Connected[Player] then
        return
    end
    Connected[Player] = true
    Network.RegisterPlayer(Player)
end

local function OnPlayerRemoving(Player)
    if not Connected[Player] then
        return
    end
    Connected[Player] = nil
    Network.UnregisterPlayer(Player)
end

for Index, Player in Players:GetPlayers() do
    OnPlayerAdded(Player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

Changelog.Log("ProceduralAnimationServer ready")
