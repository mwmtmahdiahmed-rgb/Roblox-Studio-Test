--!strict
-- ProceduralAnimation/Client/Bootstrap/ClientBootstrap
-- Bootstrap only: character lifetime wiring. No developer call is required.
--
-- This module exists instead of running the logic inline in the entry script because scripts
-- may not return values, and the lifecycle handle needs to be a real ModuleScript return for
-- embedders (and for the verification harness, which calls Destroy on cached modules). It does
-- exactly three things at require time:
--   1. requires the runtime and calls Animator.Init() (idempotent inside the runtime),
--   2. forwards the local player's character events to SetupCharacter / TeardownCharacter,
--   3. adopts a character that already existed before this module ran.
--
-- Connections are tracked locally rather than fire-and-forget so the module can be torn down
-- cleanly. Nothing here duplicates work the runtime already does: Animator.Init tracks *other*
-- players, this handles the local one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrap: { [string]: any } = {
    Initialized = false,
}

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
if not Folder then
    warn("[ProceduralAnimation] ProceduralAnimation folder did not replicate within 15s; client bootstrap aborted")
    function Bootstrap.Destroy(): () end
    return Bootstrap
end

local Client = Folder:WaitForChild("Client", 15)
local Runtime = Client and Client:WaitForChild("Runtime", 15)
if not Runtime then
    warn("[ProceduralAnimation] Client/Runtime did not replicate within 15s; client bootstrap aborted")
    function Bootstrap.Destroy(): () end
    return Bootstrap
end

local Animator = require(Runtime.ProceduralAnimator)

Animator.Init()

local Player = Players.LocalPlayer

local LocalConnections: { RBXScriptConnection } = {}

local function Track(Connection: RBXScriptConnection): RBXScriptConnection
    LocalConnections[#LocalConnections + 1] = Connection
    return Connection
end

local function OnCharacterAdded(Character: any): ()
    Animator.SetupCharacter(Character)
end

local function OnCharacterRemoving(Character: any): ()
    Animator.TeardownCharacter(Character)
end

-- Adopt a character that was already spawned before this script executed. Without this, a fast
-- respawn can beat the bootstrapper and the first character never gets animated.
if Player and Player.Character then
    OnCharacterAdded(Player.Character)
end

if Player then
    Track(Player.CharacterAdded:Connect(OnCharacterAdded))
    Track(Player.CharacterRemoving:Connect(OnCharacterRemoving))
end

Bootstrap.Initialized = true

-- Releases the local player's connections. Leaves the runtime running: it is shared with other
-- scripts and tearing it down from a bootstrap module would be surprising.
function Bootstrap.Destroy(): ()
    for Index = #LocalConnections, 1, -1 do
        LocalConnections[Index]:Disconnect()
        LocalConnections[Index] = nil
    end
    table.clear(LocalConnections)
    Bootstrap.Initialized = false
end

return Bootstrap
