--!strict
-- ProceduralAnimationServer
-- Entry point only. The implementation lives in ProceduralAnimation/Server/Bootstrap/
-- ServerBootstrap (a ModuleScript) so the lifecycle logic type-checks and exposes Destroy.
-- Requiring it performs automatic initialization once per session; scripts themselves may not
-- return values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Folder = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
local Server = Folder and Folder:WaitForChild("Server", 15)
local BootstrapFolder = Server and Server:WaitForChild("Bootstrap", 15)
local ServerBootstrap = BootstrapFolder and BootstrapFolder:WaitForChild("ServerBootstrap", 15)

if not ServerBootstrap then
    warn("[ProceduralAnimation] Server/Bootstrap/ServerBootstrap did not replicate; server bootstrap aborted")
    return
end

require(ServerBootstrap)
