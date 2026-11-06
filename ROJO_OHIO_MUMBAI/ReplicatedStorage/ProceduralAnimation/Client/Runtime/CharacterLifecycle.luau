--!strict
-- ProceduralAnimation/Client/CharacterLifecycle
-- Bringing a character up and taking it down again:
--   * CreateState builds the per-character state table, pre-allocating every buffer and table the
--     per-frame path touches (no allocation happens during a frame),
--   * SetupCharacter runs the fail-fast joint check, caches lengths, installs the raycast params
--     and connects the humanoid state machine,
--   * TeardownCharacter disconnects everything and releases the remote pose slot.
--
-- Split out of ProceduralAnimator to respect the 500-line limit; bodies are unchanged apart from
-- routing the registry through StatePool, so the heartbeat can iterate the same list.

return function(Dependencies: { [string]: any }): any
local Config = Dependencies.Config
local Changelog = Dependencies.Changelog
local Players = Dependencies.Players
local Network = Dependencies.Network
local FireBusEvent = Dependencies.FireBusEvent
-- Read through a getter: preview mode is a live flag owned by the animator.
local IsPreviewMode = Dependencies.IsPreviewMode
local CharacterJoints = Dependencies.CharacterJoints

local StatePool = require(script.Parent.StatePool)
local PoseBuffer = require(script.Parent.PoseBuffer)

--=========================================================
-- [1] CONSTANTS
--=========================================================

local MaxJoints = Config.MaxJoints
local MaxGestures = Config.MaxGestures
local FabrikChains = Config.FabrikChains

local JumpStateGrounded = 0
local JumpStateAnticipation = 1
local JumpStateLaunch = 2
local JumpStateAirborne = 3
local JumpStateLanding = 4

local BufferCreate = buffer.create
local Vector3New = Vector3.new
local PoseBufferLength = PoseBuffer.PoseBufferLength

local CacheJoints = CharacterJoints.CacheJoints
local CacheLimbLengths = CharacterJoints.CacheLimbLengths

local Lifecycle = {}

--=========================================================
-- [2] LIFECYCLE
--=========================================================

local function CreateState(Character: any, IsLocal: boolean): any
    local State: any = {
        Character = Character,
        Humanoid = Character:FindFirstChildOfClass("Humanoid"),
        RootPart = Character:FindFirstChild("HumanoidRootPart"),
        Player = Players:GetPlayerFromCharacter(Character),
        IsLocal = IsLocal,
        Valid = false,
        SmoothRate = IsLocal and Config.LocalSmoothRate or Config.RemoteSmoothRate,

        Joints = {},
        JointPresent = {},
        BoneAxis = {},
        Applied = {},
        EasingOverride = {},

        Pose = BufferCreate(PoseBufferLength),
        Overlay = BufferCreate(PoseBufferLength),
        Smooth = BufferCreate(PoseBufferLength),

        IdlePhase = 0.0,
        WalkPhase = 0.0,
        RunPhase = 0.0,
        FilteredSpeed = 0.0,
        LookAtTarget = nil,
        LookAtWeight = 0.0,
        LookAtTargetWeight = 0.0,
        -- Per-joint amplitude multipliers (1.0 default). Preallocated length MaxJoints so the
        -- hot loop never grows the table.
        JointAmplitude = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
        IdleWeight = 1.0,
        WalkWeight = 0.0,
        RunWeight = 0.0,
        LocomotionWeight = 1.0,
        Speed = 0.0,

        -- Constant downward ray used by foot raycasting; created once instead of per frame.
        FootRayDirection = Vector3New(0.0, -Config.FootRayLength, 0.0),

        JumpState = JumpStateGrounded,
        JumpTime = 0.0,
        JumpWeight = 0.0,
        JumpOffset = 0.0,

        RootOffsetY = 0.0,
        -- Damped-spring squash & stretch: impulse below in CharacterMotionState kicks Velocity
        -- negative on landing; integrated each frame in ClientPosePipeline.ComputeRootOffset.
        SquashSpring = { Position = 0.0, Velocity = 0.0 },

        Sequence = 0,
        SendAccumulator = 0.0,
        CameraDistance = 0.0,

        IkWeight = { 0.0, 0.0 },
        HandWeight = { 0.0, 0.0 },
        HandTarget = { Vector3New(0.0, 0.0, 0.0), Vector3New(0.0, 0.0, 0.0) },
        LegLength1 = { 0.0, 0.0 },
        LegLength2 = { 0.0, 0.0 },
        ArmLength1 = { 0.0, 0.0 },
        ArmLength2 = { 0.0, 0.0 },

        Gestures = {},

        FabrikChains = {},
    }

    -- Pre-allocate FABRIK chain state so the per-frame path never allocates.
    for ChainName, ChainDef in pairs(FabrikChains) do
        local JointCount = #ChainDef.Joints
        State.FabrikChains[ChainDef] = {
            Positions = table.create(JointCount),
            Lengths = table.create(JointCount - 1),
            LengthsReady = false,
            TargetScratch = { X = 0.0, Y = 0.0, Z = 0.0 },
        }
        for Index = 1, JointCount do
            State.FabrikChains[ChainDef].Positions[Index] = Vector3New(0.0, 0.0, 0.0)
        end
    end

    for Joint = 1, MaxJoints do
        State.EasingOverride[Joint] = 0
    end

    for Slot = 1, MaxGestures do
        State.Gestures[Slot] = {
            Active = false,
            Clip = nil,
            Time = 0.0,
            Duration = 1.0,
            EasingId = 0,
            Weight = 0.0,
        }
    end

    return State
end

local function OnHumanoidStateChanged(State: any, OldState: any, NewState: any): ()
    if not State.Valid or not State.IsLocal then
        return
    end
    if NewState == Enum.HumanoidStateType.Jumping then
        if State.JumpState == JumpStateGrounded then
            State.JumpState = JumpStateAnticipation
            State.JumpTime = 0.0
            FireBusEvent(Config.EventId.ClipStart)
        end
    elseif NewState == Enum.HumanoidStateType.Landed then
        if State.JumpState == JumpStateAirborne then
            State.JumpState = JumpStateLanding
            State.JumpTime = 0.0
            FireBusEvent(Config.EventId.Landing)
        end
    elseif NewState == Enum.HumanoidStateType.Freefall then
        if State.JumpState == JumpStateAnticipation or State.JumpState == JumpStateLaunch then
            State.JumpState = JumpStateAirborne
            State.JumpTime = 0.0
        end
    end
end

local function SetupCharacter(Character: any): boolean
    if not Character or not Character:IsA("Model") then
        return false
    end
    if StatePool.Get(Character) then
        return true
    end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid or Humanoid.RigType ~= Enum.HumanoidRigType.R15 then
        return false
    end
    local RootPart = Character:FindFirstChild("HumanoidRootPart")
    if not RootPart then
        return false
    end

    -- 1. Kill the default Animate script so the built-in animation player never fights us.
    local Animate = Character:FindFirstChild("Animate")
    if Animate then
        Animate:Destroy()
    end

    local LocalPlayer = Players.LocalPlayer
    local IsLocal = LocalPlayer ~= nil and Character == LocalPlayer.Character

    local State = CreateState(Character, IsLocal)

    -- 2. Joint presence check.
    local Success, MissingName = CacheJoints(State, Character)
    if not Success then
        Changelog.Log("Setup aborted: missing R15 joint " .. tostring(MissingName))
        return false
    end

    -- 3. Rest C0/C1 are read here and then never touched again.
    CacheLimbLengths(State)

    local RaycastParams = RaycastParams.new()
    RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
    RaycastParams.FilterDescendantsInstances = { Character }
    RaycastParams.IgnoreWater = true
    State.RaycastParams = RaycastParams

    State.Valid = true

    if IsLocal and IsPreviewMode() then
        RootPart.Anchored = true
    end

    -- Destroy any Animate script that reappears later.
    State.ChildAddedConnection = Character.ChildAdded:Connect(function(Child)
        if Child.Name == "Animate" and Child:IsA("LocalScript") then
            Child:Destroy()
        end
    end)

    State.StateChangedConnection = Humanoid.StateChanged:Connect(function(OldState, NewState)
        OnHumanoidStateChanged(State, OldState, NewState)
    end)

    StatePool.Add(Character, State)

    Changelog.Log("Setup complete for " .. Character.Name)
    FireBusEvent(Config.EventId.Setup)

    return true
end

local function TeardownCharacter(Character: any): boolean
    local State = StatePool.Remove(Character)
    if not State then
        return false
    end

    if State.ChildAddedConnection then
        State.ChildAddedConnection:Disconnect()
        State.ChildAddedConnection = nil
    end
    if State.StateChangedConnection then
        State.StateChangedConnection:Disconnect()
        State.StateChangedConnection = nil
    end

    if State.IsLocal and State.RootPart then
        State.RootPart.Anchored = false
    end

    if State.Player then
        Network.ReleaseRemotePose(State.Player)
    end

    Changelog.Log("Teardown complete for " .. Character.Name)
    return true
end

--=========================================================
-- [3] PUBLIC SURFACE
--=========================================================

Lifecycle.CreateState = CreateState
Lifecycle.SetupCharacter = SetupCharacter
Lifecycle.TeardownCharacter = TeardownCharacter

return Lifecycle
end
