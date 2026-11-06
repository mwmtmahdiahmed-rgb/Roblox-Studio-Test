-- ProceduralAnimation/Client/ProceduralAnimator
-- All motion is written to Motor6D.Transform. The Humanoid stays alive and in charge of physics.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Parent.Shared.AnimationConfig)
local MathLib = require(script.Parent.Parent.Parent.Shared.AnimationMath)
local Network = require(script.Parent.Parent.Parent.Shared.AnimationNetwork)
local Changelog = require(script.Parent.Parent.Parent.Shared.Changelog)
local Connections = require(script.Parent.Parent.Parent.Shared.Utilities.Connections)
local PlayerTrackerModule = require(script.Parent.PlayerTracker)


local Animator = {}

--=========================================================
-- [1] CONSTANTS
--=========================================================

local MaxJoints = Config.MaxJoints
local MaxGestures = Config.MaxGestures
local MaxEventId = Config.MaxEventId

local GestureClips = Config.Compiled.Gestures

-- Localised every global and library call used on the per-frame path.
local Sqrt = math.sqrt
local Vector3New = Vector3.new
local ProfileBegin = debug.profilebegin
local ProfileEnd = debug.profileend
local ProfilingEnabled = Config.ProfilingEnabled

--=========================================================
-- [2] BUFFERS AND STATE POOL
--=========================================================

-- The character registry is shared with CharacterLifecycle and the heartbeat, so it lives in
-- StatePool rather than here.
local StatePool = require(script.Parent.StatePool)
local ActiveStates = StatePool.Active
-- Read through the pool: StatePool.Count changes as characters are added and removed, so a
-- captured copy would go stale (that is exactly what broke SetPreviewMode and SetLocomotionWeight
-- before the split).
local function GetActiveCount()
    return StatePool.Count
end

local Running = false
local Initialized = false
local Destroyed = false
local HeartbeatConnection = nil
local PreviewMode = Config.PreviewAnchorRoot

local EventCallbacks = {}
for EventId = 1, MaxEventId do
    EventCallbacks[EventId] = {}
end

local function DispatchEvent(EventId, Value)
    local List = EventCallbacks[EventId]
    if not List then
        return
    end
    for Index = 1, #List do
        local Callback = List[Index]
        if Callback then
            task.spawn(Callback, Value)
        end
    end
end

--=========================================================
-- [3] EASING
--=========================================================

local function SampleEase(EasingId, Alpha)
    return MathLib.Ease(EasingId, Alpha)
end

--=========================================================
-- [4] MATH
--=========================================================

--=========================================================
-- [4.5] SPLIT MODULES
--=========================================================
-- Loaded here, after the shared requires and the pose-buffer helpers above, because the
-- kinematics module is constructed with WritePoseAdd/WritePoseBlend. Each module takes its
-- collaborators through a constructor, so none of them requires this one back and the require
-- graph stays acyclic.

local CharacterJoints = require(script.Parent.CharacterJoints)({
    Config = Config,
    Changelog = Changelog,
})

local ClientPosePipeline = require(script.Parent.ClientPosePipeline)
local ClientRigKinematics = require(script.Parent.ClientRigKinematics)({
    Config = Config,
    MathLib = MathLib,
    Workspace = Workspace,
})

-- The lifecycle needs the event bus, which is defined above in [2].
local CharacterLifecycle = require(script.Parent.CharacterLifecycle)({
    Config = Config,
    Changelog = Changelog,
    Workspace = Workspace,
    Players = Players,
    Network = Network,
    FireBusEvent = function(EventId)
        DispatchEvent(EventId, 1)
    end,
    IsPreviewMode = function()
        return PreviewMode
    end,
    CharacterJoints = CharacterJoints,
})

--=========================================================
-- [5] POSE PIPELINE
--=========================================================
-- Clip sampling, the jump state machine, gestures, overlay blending and pose application live in
-- ClientPosePipeline. The dependency table is built here, after every collaborator above exists,
-- so the pipeline closes over the real functions rather than forward references.

local Pipeline = ClientPosePipeline({
    Config = Config,
    MathLib = MathLib,
    Workspace = Workspace,
    DispatchEvent = DispatchEvent,
    ProfilingEnabled = ProfilingEnabled,
    ProfileBegin = ProfileBegin,
    ProfileEnd = ProfileEnd,
    UpdateInverseKinematics = ClientRigKinematics.UpdateInverseKinematics,
    UpdateFabrikChain = ClientRigKinematics.UpdateFabrikChain,
    UpdateWaves = ClientRigKinematics.UpdateWaves,
    SampleEase = SampleEase,
    Network = Network,
    IsPreviewMode = function()
        return PreviewMode
    end,
})

-- Only the three entry points the heartbeat and the public API actually call are bound here;
-- the rest of the pipeline's surface is reached through Pipeline directly. Re-binding the whole
-- surface used to leave a dozen dead locals behind after the Phase 3 split.
local FireBusEvent = Pipeline.FireBusEvent
local UpdateLocalCharacter = Pipeline.UpdateLocalCharacter
local UpdateRemoteCharacter = Pipeline.UpdateRemoteCharacter

--=========================================================
-- [6] HEARTBEAT
--=========================================================
-- Kept in this module (rather than the pipeline) because it walks CharacterStates/ActiveStates,
-- the state pool this module owns. It only calls into the pipeline to produce each pose.

local function OnHeartbeat(DeltaTime)
    if not Running then
        return
    end
    if DeltaTime > 0.1 then
        DeltaTime = 0.1
    end

    local Camera = Workspace.CurrentCamera
    local CameraPosition = Camera and Camera.CFrame.Position or Vector3New(0.0, 0.0, 0.0)

    if ProfilingEnabled then
        ProfileBegin("PA_CharacterLoop")
    end

    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State.Valid then
            local RootPart = State.RootPart
            if RootPart and RootPart.Parent then
                local RootPosition = RootPart.Position
                local OffsetX = RootPosition.X - CameraPosition.X
                local OffsetY = RootPosition.Y - CameraPosition.Y
                local OffsetZ = RootPosition.Z - CameraPosition.Z
                State.CameraDistance = Sqrt(OffsetX * OffsetX + OffsetY * OffsetY + OffsetZ * OffsetZ)

                -- Distance LOD: off-screen or far characters keep their last pose untouched.
                if State.IsLocal or State.CameraDistance <= Config.LodDistance then
                    if State.IsLocal then
                        UpdateLocalCharacter(State, DeltaTime)
                    else
                        UpdateRemoteCharacter(State, DeltaTime)
                    end
                end
            else
                State.Valid = false
            end
        end
    end

    if ProfilingEnabled then
        ProfileEnd()
    end

    -- Compact after the loop so a teardown during iteration never disturbs it.
    StatePool.Compact()
end

--=========================================================
-- [7] CHARACTER LIFECYCLE
--=========================================================
-- CreateState, SetupCharacter and TeardownCharacter live in CharacterLifecycle. They own the
-- fail-fast joint check, the rest-pose measurement and every connection each character holds.

local SetupCharacter = CharacterLifecycle.SetupCharacter
local TeardownCharacter = CharacterLifecycle.TeardownCharacter


function Animator.SetupCharacter(Character)
    return SetupCharacter(Character)
end

function Animator.TeardownCharacter(Character)
    return TeardownCharacter(Character)
end

function Animator.SetLocomotionWeight(Weight)
    local Clamped = MathLib.Clamp01(Weight)
    for Index = 1, GetActiveCount() do
        ActiveStates[Index].LocomotionWeight = Clamped
    end
end

function Animator.SetIkTarget(Limb, WorldPosition, Weight)
    local Side = nil
    if Limb == "LeftHand" then
        Side = 1
    elseif Limb == "RightHand" then
        Side = 2
    else
        Changelog.Log("SetIkTarget: unsupported limb " .. tostring(Limb))
        return
    end

    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State.IsLocal then
            State.HandTarget[Side] = WorldPosition
            State.HandWeight[Side] = MathLib.Clamp01(Weight)
        end
    end
end

function Animator.PlayGesture(GestureId, Duration, EasingId)
    local Clip = GestureClips[GestureId]
    if not Clip then
        Changelog.Log("PlayGesture: unknown gesture " .. tostring(GestureId))
        return
    end

    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State.IsLocal then
            local Slot = nil
            for Candidate = 1, MaxGestures do
                if not State.Gestures[Candidate].Active then
                    Slot = Candidate
                    break
                end
            end
            if not Slot then
                Slot = 1
            end
            local Gesture = State.Gestures[Slot]
            Gesture.Active = true
            Gesture.Clip = Clip
            Gesture.Time = 0.0
            Gesture.Duration = Duration or Clip.Duration or 1.0
            Gesture.EasingId = EasingId or 0
            FireBusEvent(Config.EventId.GestureStart)
        end
    end
end

function Animator.StopGesture(GestureId)
    local Clip = GestureClips[GestureId]
    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State.IsLocal then
            for Slot = 1, MaxGestures do
                local Gesture = State.Gestures[Slot]
                if Gesture.Active and (Clip == nil or Gesture.Clip == Clip) then
                    Gesture.Active = false
                    Gesture.Weight = 0.0
                    FireBusEvent(Config.EventId.ClipStop)
                end
            end
        end
    end
end

function Animator.SetEasingOverride(JointIndexValue, EasingId)
    if JointIndexValue < 1 or JointIndexValue > MaxJoints then
        return
    end
    if EasingId < 1 or EasingId > MathLib.EasingCount then
        return
    end
    for Index = 1, GetActiveCount() do
        ActiveStates[Index].EasingOverride[JointIndexValue] = EasingId
    end
end

function Animator.SetPreviewMode(Enabled)
    PreviewMode = Enabled and true or false
    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State.IsLocal and State.RootPart then
            State.RootPart.Anchored = PreviewMode
            if PreviewMode then
                State.RootOffsetY = 0.0
            end
        end
    end
end

function Animator.Start()
    if Running then
        return
    end
    Running = true
    if not HeartbeatConnection then
        HeartbeatConnection = RunService.Heartbeat:Connect(OnHeartbeat)
    end
end

function Animator.Stop()
    if not Running then
        return
    end
    Running = false

    -- Disconnect rather than merely flagging the loop idle: a retained connection keeps the
    -- script alive across Stop/Start cycles and reuses a stale callback closure.
    if HeartbeatConnection then
        HeartbeatConnection:Disconnect()
        HeartbeatConnection = nil
    end
end

function Animator.BindToEvent(EventName, Callback)
    local EventId = Config.EventId[EventName]
    if not EventId then
        Changelog.Log("BindToEvent: unknown event " .. tostring(EventName))
        return
    end
    local List = EventCallbacks[EventId]
    List[#List + 1] = Callback
end

local PlayerTracker = PlayerTrackerModule({
    Players = Players,
    Connections = Connections,
    SetupCharacter = SetupCharacter,
    TeardownCharacter = TeardownCharacter,
})

--=========================================================
-- [8] PUBLIC API
--=========================================================

function Animator.Init()
    if Initialized then
        return
    end
    if Destroyed then
        -- Destroy is terminal. Reviving would mean re-creating every pooled buffer and rebinding
        -- every connection; reloading the module is cheaper and less error-prone than that.
        Changelog.Log("ProceduralAnimator: Init ignored, module was destroyed")
        return
    end
    Initialized = true

    Network.Init()
    PlayerTracker.Start()

    Changelog.Log("ProceduralAnimator initialized")
    Animator.Start()
end

function Animator.IsRunning()
    return Running
end

-- Full teardown of the runtime. Stops the heartbeat, tears down every tracked character, releases
-- every connection, and clears the state pool. Idempotent and terminal: Init will refuse to run
-- afterwards.
--
-- This exists so a host (a test harness, a mode switch, a game framework reload) can shut the
-- framework down without leaking connections or character state. The bootstrapper never calls it.
function Animator.Destroy()
    if Destroyed then
        return
    end
    Destroyed = true

    Animator.Stop()

    -- Characters first: teardown disconnects each character's own connections.
    for Index = 1, GetActiveCount() do
        local State = ActiveStates[Index]
        if State and State.Character then
            TeardownCharacter(State.Character)
        end
    end
    StatePool.Clear()

    PlayerTracker.Stop()

    for EventId = 1, MaxEventId do
        table.clear(EventCallbacks[EventId])
    end

    Initialized = false
    Changelog.Log("ProceduralAnimator destroyed")
end

return Animator