-- ProceduralAnimationClient
-- Bootstrap only: character lifetime wiring. No developer call is required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
local Client = Folder:WaitForChild("Client", 15)

local Animator = require(Client.ProceduralAnimator)

Animator.Init()

local function OnCharacterAdded(Character)
    Animator.SetupCharacter(Character)
end

local function OnCharacterRemoving(Character)
    Animator.TeardownCharacter(Character)
end

if Player.Character then
    OnCharacterAdded(Player.Character)
end

Player.CharacterAdded:Connect(OnCharacterAdded)
Player.CharacterRemoving:Connect(OnCharacterRemoving)
