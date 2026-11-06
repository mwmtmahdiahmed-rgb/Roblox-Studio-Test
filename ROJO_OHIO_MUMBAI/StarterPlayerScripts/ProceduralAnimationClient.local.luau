--!strict
-- ProceduralAnimationClient
-- Bootstrap only: character lifetime wiring. No developer call is required.
--
-- Runs exactly once per client session, from StarterPlayerScripts. It does three things:
--   1. requires the runtime and calls Animator.Init() (idempotent inside the runtime),
--   2. forwards the local player's character events to SetupCharacter / TeardownCharacter,
--   3. adopts a character that already existed before this script ran.
--
-- Connections are tracked locally rather than fire-and-forget so the script can be torn down
-- cleanly. Nothing here duplicates work the runtime already does: Animator.Init tracks *other*
-- players, this handles the local one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
if not Folder then
    warn("[ProceduralAnimation] ProceduralAnimation folder did not replicate within 15s; client bootstrap aborted")
    return
end

local Client = Folder:WaitForChild("Client", 15)
local Runtime = Client and Client:WaitForChild("Runtime", 15)
if not Runtime then
    warn("[ProceduralAnimation] Client/Runtime did not replicate within 15s; client bootstrap aborted")
    return
end

local Animator = require(Runtime.ProceduralAnimator)

Animator.Init()

local Bootstrap: { [string]: any } = {}

local LocalConnections: { [number]: RBXScriptConnection } = {}

local function Track(Connection: RBXScriptConnection): RBXScriptConnection
    LocalConnections[#LocalConnections + 1] = Connection
    return Connection
end

local function OnCharacterAdded(Character: Model)
    Animator.SetupCharacter(Character)
end

local function OnCharacterRemoving(Character: Model)
    Animator.TeardownCharacter(Character)
end

-- Adopt a character that was already spawned before this script executed. Without this, a fast
-- respawn can beat the bootstrapper and the first character never gets animated.
if Player.Character then
    OnCharacterAdded(Player.Character)
end

Track(Player.CharacterAdded:Connect(OnCharacterAdded))
Track(Player.CharacterRemoving:Connect(OnCharacterRemoving))

-- Releases the local player's connections. Leaves the runtime running: it is shared with other
-- scripts and tearing it down from a bootstrap script would be surprising.
function Bootstrap.Destroy()
    for Index = #LocalConnections, 1, -1 do
        LocalConnections[Index]:Disconnect()
        LocalConnections[Index] = nil
    end
    table.clear(LocalConnections)
end

return Bootstrap
