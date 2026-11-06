--!strict
-- ProceduralAnimationClient
-- Entry point only. The implementation lives in ProceduralAnimation/Client/Bootstrap/
-- ClientBootstrap (a ModuleScript) so the lifecycle logic type-checks and exposes Destroy.
-- Requiring it performs automatic initialization once per session; scripts themselves may not
-- return values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
local Client = Folder and Folder:WaitForChild("Client", 15)
local BootstrapFolder = Client and Client:WaitForChild("Bootstrap", 15)
local ClientBootstrap = BootstrapFolder and BootstrapFolder:WaitForChild("ClientBootstrap", 15)

if not ClientBootstrap then
    warn("[ProceduralAnimation] Client/Bootstrap/ClientBootstrap did not replicate; client bootstrap aborted")
    return
end

require(ClientBootstrap)
