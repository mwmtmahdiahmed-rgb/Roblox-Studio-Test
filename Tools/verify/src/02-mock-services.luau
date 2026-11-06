--[[
    Tools/verify/src/02-mock-services.luau

    Part 2 of the offline Roblox environment used by Tools/verify.

    Builds the service tree (Workspace, ReplicatedStorage, ServerScriptService,
    StarterPlayerScripts, ServerStorage, Players, RunService, Lighting), a RemoteEvent /
    UnreliableRemoteEvent pair that can deliver packets between a simulated server and client,
    humanoids with a working StateChanged machine, and a scriptable raycast surface.

    Every simulation hook used by the tests is namespaced under
    game.__Mock so framework code can never accidentally depend on a harness-only name.
]]

--=========================================================
-- [1] DEPENDENCIES
--=========================================================

return function(Mock)
local Vector3 = Mock.Vector3
local Vector3New = Vector3.new
local CFrame = Mock.CFrame
local Instance = Mock.Instance
local InstanceClass = Mock.InstanceClass
local SignalClass = Mock.SignalClass
local Enum = Mock.Enum

--=========================================================
-- [2] SERVICE TREE
--=========================================================

local Game = Instance.new("DataModel")

local Services = {}

local function AddService(Name, ClassName)
    local Service = Instance.new(ClassName or Name)
    Service.Name = Name
    Service.Parent = Game
    Services[Name] = Service
    return Service
end

local Workspace = AddService("Workspace", "Workspace")
Workspace.CurrentCamera = nil
Workspace.Gravity = 196.2

local ReplicatedStorage = AddService("ReplicatedStorage")
local ServerScriptService = AddService("ServerScriptService")
local ServerStorage = AddService("ServerStorage")
local StarterPlayer = AddService("StarterPlayer")
local StarterPlayerScripts = Instance.new("StarterPlayerScripts")
StarterPlayerScripts.Parent = StarterPlayer
local StarterCharacterScripts = Instance.new("StarterCharacterScripts")
StarterCharacterScripts.Parent = StarterPlayer

local Lighting = AddService("Lighting")
local Players = AddService("Players")
local RunService = AddService("RunService")
local Debris = AddService("Debris")
local HttpService = AddService("HttpService")
local CollectionService = AddService("CollectionService")

local function GetService(Self, Name)
    local Service = Services[Name]
    if not Service then
        error("Mock DataModel:GetService: unknown service " .. tostring(Name), 2)
    end
    return Service
end

local function FindService(Self, Name)
    return Services[Name]
end

--=========================================================
-- [3] RAYCAST SURFACE
--=========================================================
-- Framework code calls Workspace:Raycast. The harness returns whatever the current test
-- installed, so ground alignment and foot IK can be exercised deterministically.

local RaycastHandler = nil

function Workspace.Raycast(Self, Origin, Direction, Params)
    if RaycastHandler then
        return RaycastHandler(Origin, Direction, Params)
    end
    return nil
end

local RaycastParamsClass = {}

function RaycastParamsClass.new()
    return setmetatable({
        FilterType = Enum.RaycastFilterType.Exclude,
        FilterDescendantsInstances = {},
        IgnoreWater = false,
        CollisionGroup = "Default",
    }, { __index = RaycastParamsClass })
end

local RaycastParams = {
    new = RaycastParamsClass.new,
}

local function SetRaycastHandler(Handler)
    RaycastHandler = Handler
end

--=========================================================
-- [4] HUMANULS
--=========================================================
-- Humanoid is rebuilt per character. WalkSpeed, state transitions and the StateChanged
-- signal are all real so jump logic can be driven without a physics engine.

local HumanoidClass = {}

function HumanoidClass.new()
    local Value = Instance.new("Humanoid")
    Value.RigType = Enum.HumanoidRigType.R15
    Value.WalkSpeed = 16.0
    Value.MoveDirection = Vector3New(0.0, 0.0, 0.0)
    Value.FloorMaterial = Enum.Material.Air
    Value.Health = 100.0
    Value.HipHeight = 2.0
    Value.JumpPower = 50.0
    Value.DisplayDistanceType = "Viewer"
    Value.State = Enum.HumanoidStateType.Running
    Value.StateChanged = SignalClass.new()
    Value.Jumping = SignalClass.new()
    Value.Landed = SignalClass.new()
    Value.Died = SignalClass.new()
    Value.Seated = SignalClass.new()
    Value.Running = SignalClass.new()
    Value.Changed = SignalClass.new()

    function Value.SetState(HumanoidSelf, NewState)
        local OldState = HumanoidSelf.State
        if OldState == NewState then
            return
        end
        HumanoidSelf.State = NewState
        SignalClass.Fire(HumanoidSelf.StateChanged, OldState, NewState)
    end

    function Value.SetFloorMaterial(HumanoidSelf, Material)
        HumanoidSelf.FloorMaterial = Material
    end

    return Value
end

local Humanoid = {
    new = HumanoidClass.new,
}

--=========================================================
-- [5] REMOTES
--=========================================================
-- Each remote keeps server listeners and client listeners apart and records every delivery
-- so tests can assert what crossed the wire, in what order, with what payload sizes.

local RemoteClass = {}

local function MakeRemote(ClassName, IsUnreliable)
    local Value = InstanceClass.new(ClassName, ClassName)
    Value.IsUnreliable = IsUnreliable
    Value.OnServerEvent = SignalClass.new()
    Value.OnClientEvent = SignalClass.new()
    Value.ServerSentCount = 0
    Value.ClientSentCount = 0
    Value.LastServerPayload = nil
    Value.LastClientPayload = nil
    Value.ServerFireHistory = {}
    Value.ServerFireHistoryCount = 0
    Value.Sender = nil

    function Value.FireServer(RemoteSelf, ...)
        RemoteSelf.ClientSentCount += 1
        RemoteSelf.LastClientPayload = { ... }
        -- Real remotes deliver the calling player as the first argument.
        SignalClass.Fire(RemoteSelf.OnServerEvent, RemoteSelf.Sender, ...)
    end

    function Value.FireClient(RemoteSelf, Client, ...)
        RemoteSelf.ServerSentCount += 1
        RemoteSelf.LastServerPayload = { ... }
        RemoteSelf.LastServerTarget = Client
        RemoteSelf.ServerFireHistoryCount += 1
        RemoteSelf.ServerFireHistory[RemoteSelf.ServerFireHistoryCount] = { Client, ... }
        SignalClass.Fire(RemoteSelf.OnClientEvent, ...)
    end

    function Value.FireAllClients(RemoteSelf, ...)
        RemoteSelf.ServerSentCount += 1
        SignalClass.Fire(RemoteSelf.OnClientEvent, ...)
    end

    return Value
end

local Remotes = {
    new = function(ClassName)
        return MakeRemote(ClassName or "RemoteEvent", ClassName == "UnreliableRemoteEvent")
    end,
}

-- Remotes created with Instance.new must carry their event signals.
InstanceClass.RegisterClassInitialiser("RemoteEvent", function(Value)
    Value.ClientSentCount = 0
    Value.ServerSentCount = 0
    Value.ServerFireHistory = {}
    Value.ServerFireHistoryCount = 0
    Value.OnServerEvent = SignalClass.new()
    Value.OnClientEvent = SignalClass.new()
    Value.FireServer = function(Self, ...)
        Self.ClientSentCount = (Self.ClientSentCount or 0) + 1
        Self.LastClientPayload = { ... }
        SignalClass.Fire(Self.OnServerEvent, Self.Sender, ...)
    end
    Value.FireClient = function(Self, Client, ...)
        Self.ServerSentCount = (Self.ServerSentCount or 0) + 1
        Self.LastServerTarget = Client
        Self.ServerFireHistory = Self.ServerFireHistory or {}
        Self.ServerFireHistoryCount = (Self.ServerFireHistoryCount or 0) + 1
        Self.ServerFireHistory[Self.ServerFireHistoryCount] = { Client, ... }
        SignalClass.Fire(Self.OnClientEvent, ...)
    end
    Value.FireAllClients = function(Self, ...)
        SignalClass.Fire(Self.OnClientEvent, ...)
    end
end)

InstanceClass.RegisterClassInitialiser("UnreliableRemoteEvent", function(Value)
    Value.IsUnreliable = true
    Value.ClientSentCount = 0
    Value.ServerSentCount = 0
    Value.ServerFireHistory = {}
    Value.ServerFireHistoryCount = 0
    Value.OnServerEvent = SignalClass.new()
    Value.OnClientEvent = SignalClass.new()
    Value.FireServer = function(Self, ...)
        Self.ClientSentCount = (Self.ClientSentCount or 0) + 1
        Self.LastClientPayload = { ... }
        SignalClass.Fire(Self.OnServerEvent, Self.Sender, ...)
    end
    Value.FireClient = function(Self, Client, ...)
        Self.ServerSentCount = (Self.ServerSentCount or 0) + 1
        Self.LastServerTarget = Client
        Self.ServerFireHistory = Self.ServerFireHistory or {}
        Self.ServerFireHistoryCount = (Self.ServerFireHistoryCount or 0) + 1
        Self.ServerFireHistory[Self.ServerFireHistoryCount] = { Client, ... }
        SignalClass.Fire(Self.OnClientEvent, ...)
    end
    Value.FireAllClients = function(Self, ...)
        SignalClass.Fire(Self.OnClientEvent, ...)
    end
end)

InstanceClass.RegisterClassInitialiser("BindableEvent", function(Value)
    Value.Event = SignalClass.new()
    Value.Fire = function(Self, ...)
        SignalClass.Fire(Self.Event, ...)
    end
end)

--=========================================================
-- [6] CHARACTER RIG
--=========================================================
-- Builds a stock R15 rig with the 15 Motor6Ds the framework expects, plus the optional
-- Chest joint when requested. Rig geometry is taken from a stock R15 avatar.

local Motor6DNames = {
    "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
    "LeftWrist", "RightWrist", "LeftHip", "RightHip", "LeftKnee", "RightKnee",
    "LeftAnkle", "RightAnkle",
}

local function MakePart(Character, Name, Size, Position)
    local Part = InstanceClass.new("Part", Name)
    Part.Size = Size
    Part.CFrame = CFrame.new(Position)
    Part.Position = Position
    Part.Anchored = false
    Part.Massless = false
    Part.CanCollide = true
    Part.Transparency = 0.0
    Part.AssemblyLinearVelocity = Vector3New(0.0, 0.0, 0.0)
    Part.AssemblyAngularVelocity = Vector3New(0.0, 0.0, 0.0)
    Part.Parent = Character
    return Part
end

local function MakeMotor(Name, Part0, Part1, C0, C1)
    local Motor = InstanceClass.new("Motor6D", Name)
    Motor.Part0 = Part0
    Motor.Part1 = Part1
    Motor.C0 = C0 or CFrame.identity
    Motor.C1 = C1 or CFrame.identity
    Motor.Transform = CFrame.identity
    Motor.CurrentAngle = 0.0
    Motor.DesiredAngle = 0.0
    Motor.MaxVelocity = 0.1
    return Motor
end

local function CreateR15Character(Name, Options)
    local Settings = Options or {}
    local Character = InstanceClass.new("Model", Name or "Character")

    local RootPart = MakePart(Character, "HumanoidRootPart", Vector3New(2.0, 2.0, 1.0), Vector3New(0.0, 3.0, 0.0))
    RootPart.Name = "HumanoidRootPart"

    local Humanoid = HumanoidClass.new()
    Humanoid.Parent = Character

    local Torso = MakePart(Character, "UpperTorso", Vector3New(2.0, 2.0, 1.0), Vector3New(0.0, 3.0, 0.0))
    local LowerTorso = MakePart(Character, "LowerTorso", Vector3New(2.0, 1.0, 1.0), Vector3New(0.0, 2.0, 0.0))
    local Head = MakePart(Character, "Head", Vector3New(1.0, 1.0, 1.0), Vector3New(0.0, 4.5, 0.0))

    local LeftUpperArm = MakePart(Character, "LeftUpperArm", Vector3New(1.0, 1.2, 1.0), Vector3New(1.5, 3.2, 0.0))
    local LeftLowerArm = MakePart(Character, "LeftLowerArm", Vector3New(1.0, 1.2, 1.0), Vector3New(1.5, 2.0, 0.0))
    local LeftHand = MakePart(Character, "LeftHand", Vector3New(1.0, 1.0, 1.0), Vector3New(1.5, 0.9, 0.0))
    local RightUpperArm = MakePart(Character, "RightUpperArm", Vector3New(1.0, 1.2, 1.0), Vector3New(-1.5, 3.2, 0.0))
    local RightLowerArm = MakePart(Character, "RightLowerArm", Vector3New(1.0, 1.2, 1.0), Vector3New(-1.5, 2.0, 0.0))
    local RightHand = MakePart(Character, "RightHand", Vector3New(1.0, 1.0, 1.0), Vector3New(-1.5, 0.9, 0.0))

    local LeftUpperLeg = MakePart(Character, "LeftUpperLeg", Vector3New(1.0, 2.0, 1.0), Vector3New(0.5, 2.0, 0.0))
    local LeftLowerLeg = MakePart(Character, "LeftLowerLeg", Vector3New(1.0, 2.0, 1.0), Vector3New(0.5, 0.0, 0.0))
    local LeftFoot = MakePart(Character, "LeftFoot", Vector3New(1.0, 0.4, 2.0), Vector3New(0.5, -1.0, 0.0))
    local RightUpperLeg = MakePart(Character, "RightUpperLeg", Vector3New(1.0, 2.0, 1.0), Vector3New(-0.5, 2.0, 0.0))
    local RightLowerLeg = MakePart(Character, "RightLowerLeg", Vector3New(1.0, 2.0, 1.0), Vector3New(-0.5, 0.0, 0.0))
    local RightFoot = MakePart(Character, "RightFoot", Vector3New(1.0, 0.4, 2.0), Vector3New(-0.5, -1.0, 0.0))

    local Motors = Instance.new("Folder")
    Motors.Parent = Character

    for Index = 1, #Motor6DNames do
        local MotorName = Motor6DNames[Index]
        if MotorName ~= "Chest" then
            local Motor = MakeMotor(MotorName)
            Motor.Parent = Motors
        end
    end

    -- Stock R15 C0/C1 values (the half-heights that place each pivot at the joint line).
    local HalfArm = 0.6
    local HalfLeg = 1.0

    local MotorsFolder = Motors
    local RootJoint = InstanceClass.FindFirstChild(MotorsFolder, "Root")
    RootJoint.Part0 = RootPart
    RootJoint.Part1 = LowerTorso
    RootJoint.C0 = CFrame.new(0.0, 0.0, 0.0)
    RootJoint.C1 = CFrame.new(0.0, 1.0, 0.0)

    local Waist = InstanceClass.FindFirstChild(MotorsFolder, "Waist")
    Waist.Part0 = LowerTorso
    Waist.Part1 = UpperTorso
    Waist.C0 = CFrame.new(0.0, 0.5, 0.0)
    Waist.C1 = CFrame.new(0.0, -1.0, 0.0)

    local Neck = InstanceClass.FindFirstChild(MotorsFolder, "Neck")
    Neck.Part0 = UpperTorso
    Neck.Part1 = Head
    Neck.C0 = CFrame.new(0.0, 1.0, 0.0)
    Neck.C1 = CFrame.new(0.0, -0.5, 0.0)

    local Shoulders = {
        { "LeftShoulder", Torso, LeftUpperArm, 1 },
        { "RightShoulder", Torso, RightUpperArm, -1 },
    }
    for Index = 1, #Shoulders do
        local Entry = Shoulders[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(Entry[4] * 1.0, 0.0, 0.0)
        Motor.C1 = CFrame.new(Entry[4] * HalfArm, 0.0, 0.0)
    end

    local Elbows = {
        { "LeftElbow", LeftUpperArm, LeftLowerArm, 1 },
        { "RightElbow", RightUpperArm, RightLowerArm, -1 },
    }
    for Index = 1, #Elbows do
        local Entry = Elbows[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(0.0, -HalfArm, 0.0)
        Motor.C1 = CFrame.new(0.0, HalfArm, 0.0)
    end

    local Wrists = {
        { "LeftWrist", LeftLowerArm, LeftHand, 1 },
        { "RightWrist", RightLowerArm, RightHand, -1 },
    }
    for Index = 1, #Wrists do
        local Entry = Wrists[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(0.0, -HalfArm, 0.0)
        Motor.C1 = CFrame.new(0.0, 0.0, 0.0)
    end

    local Hips = {
        { "LeftHip", LowerTorso, LeftUpperLeg, 0.5 },
        { "RightHip", LowerTorso, RightUpperLeg, -0.5 },
    }
    for Index = 1, #Hips do
        local Entry = Hips[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(Entry[4], -0.5, 0.0)
        Motor.C1 = CFrame.new(0.0, HalfLeg, 0.0)
    end

    local Knees = {
        { "LeftKnee", LeftUpperLeg, LeftLowerLeg },
        { "RightKnee", RightUpperLeg, RightLowerLeg },
    }
    for Index = 1, #Knees do
        local Entry = Knees[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(0.0, -HalfLeg, 0.0)
        Motor.C1 = CFrame.new(0.0, HalfLeg, 0.0)
    end

    local Ankles = {
        { "LeftAnkle", LeftLowerLeg, LeftFoot },
        { "RightAnkle", RightLowerLeg, RightFoot },
    }
    for Index = 1, #Ankles do
        local Entry = Ankles[Index]
        local Motor = InstanceClass.FindFirstChild(MotorsFolder, Entry[1])
        Motor.Part0 = Entry[2]
        Motor.Part1 = Entry[3]
        Motor.C0 = CFrame.new(0.0, -HalfLeg, 0.0)
        Motor.C1 = CFrame.new(0.0, 0.2, 0.0)
    end

    if Settings.IncludeChest then
        local Chest = MakeMotor("Chest")
        Chest.Part0 = LowerTorso
        Chest.Part1 = UpperTorso
        Chest.C0 = CFrame.new(0.0, 0.5, 0.0)
        Chest.C1 = CFrame.new(0.0, -0.5, 0.0)
        Chest.Parent = MotorsFolder
    end

    if Settings.IncludeAnimator then
        local AnimatorInstance = Instance.new("Animator")
        AnimatorInstance.Parent = Humanoid
    end

    if Settings.IncludeAnimateScript then
        local Animate = Instance.new("LocalScript")
        Animate.Parent = Character
    end

    Character.Motors = MotorsFolder
    Character.PrimaryPart = RootPart
    Character.Humanoid = Humanoid
    Character.HumanoidRootPart = RootPart

    return Character
end

--=========================================================
-- [7] PLAYERS
--=========================================================

local PlayerStore = {}

local function CreatePlayer(Name, UserId)
    local Player = InstanceClass.new("Player", Name)
    Player.UserId = UserId or 1
    Player.Character = nil
    Player.CharacterAdded = SignalClass.new()
    Player.CharacterRemoving = SignalClass.new()
    Player.CharacterAppearanceLoaded = SignalClass.new()
    Player.CameraMode = nil
    Player.Team = nil
    Player.DisplayName = Name
    PlayerStore[#PlayerStore + 1] = Player
    return Player
end

local function GetPlayers()
    local Copy = table.create(#PlayerStore)
    for Index = 1, #PlayerStore do
        Copy[Index] = PlayerStore[Index]
    end
    return Copy
end

local function GetPlayerFromCharacter(Self, Character)
    for Index = 1, #PlayerStore do
        if PlayerStore[Index].Character == Character then
            return PlayerStore[Index]
        end
    end
    return nil
end

local function GetPlayerByUserId(Self, UserId)
    for Index = 1, #PlayerStore do
        if PlayerStore[Index].UserId == UserId then
            return PlayerStore[Index]
        end
    end
    return nil
end

local function AddPlayer(Player)
    PlayerStore[#PlayerStore + 1] = Player
    SignalClass.Fire(Players.PlayerAdded, Player)
    return Player
end

local function RemovePlayer(Player)
    for Index = 1, #PlayerStore do
        if PlayerStore[Index] == Player then
            PlayerStore[Index] = PlayerStore[#PlayerStore]
            PlayerStore[#PlayerStore] = nil
            break
        end
    end
    SignalClass.Fire(Players.PlayerRemoving, Player)
end

local function SetCharacter(Player, Character)
    if Player.Character then
        local Previous = Player.Character
        Player.Character = nil
        SignalClass.Fire(Player.CharacterRemoving, Previous)
    end
    Player.Character = Character
    if Character then
        Character.Parent = Workspace
        SignalClass.Fire(Player.CharacterAdded, Character)
    end
end

--=========================================================
-- [8] RUNSERVICE
--=========================================================

RunService.Heartbeat = SignalClass.new()
RunService.Stepped = SignalClass.new()
RunService.RenderStepped = SignalClass.new()
RunService.PreSimulation = SignalClass.new()
RunService.PostSimulation = SignalClass.new()
RunService.PreRender = SignalClass.new()

local IsServerSide = true

function RunService.IsServer()
    return IsServerSide
end

function RunService.IsClient()
    return not IsServerSide
end

local function SetServerMode(Enabled)
    IsServerSide = Enabled
end

--=========================================================
-- [9] GAME SURFACE
--=========================================================

function Game.GetService(Self, Name)
    return GetService(Self, Name)
end

function Game.FindService(Self, Name)
    return FindService(Self, Name)
end

function Game.IsLoaded(Self)
    return true
end

Game.BindToClose = SignalClass.new()

Game.__Mock = {
    Services = Services,
    SetServerMode = SetServerMode,
    SetRaycastHandler = SetRaycastHandler,
    CreateR15Character = CreateR15Character,
    Humanoid = Humanoid,
    CreatePlayer = CreatePlayer,
    AddPlayer = AddPlayer,
    RemovePlayer = RemovePlayer,
    SetCharacter = SetCharacter,
    PlayerStore = PlayerStore,
    GetPlayers = GetPlayers,
    Remotes = Remotes,
    RaycastParams = RaycastParams,
    Vector3 = Vector3,
    CFrame = CFrame,
    Enum = Enum,
    Instance = Mock.Instance,
    SignalClass = SignalClass,
}

Players.GetPlayers = GetPlayers
Players.GetPlayerFromCharacter = GetPlayerFromCharacter
Players.GetPlayerByUserId = GetPlayerByUserId
Players.PlayerAdded = SignalClass.new()
Players.PlayerRemoving = SignalClass.new()
Players.LocalPlayer = nil

return {
    Game = Game,
    Services = Services,
    Workspace = Workspace,
    ReplicatedStorage = ReplicatedStorage,
    ServerScriptService = ServerScriptService,
    ServerStorage = ServerStorage,
    StarterPlayerScripts = StarterPlayerScripts,
    Lighting = Lighting,
    Players = Players,
    RunService = RunService,
    Debris = Debris,
    HttpService = HttpService,
    RaycastParams = RaycastParams,
    Remotes = Remotes,
    Humanoid = Humanoid,
    MockHelpers = Game.__Mock,
}
end
