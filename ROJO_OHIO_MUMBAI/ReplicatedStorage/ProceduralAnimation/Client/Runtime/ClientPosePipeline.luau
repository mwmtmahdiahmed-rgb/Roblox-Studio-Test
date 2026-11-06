--!strict
-- ProceduralAnimation/Client/ClientPosePipeline
-- The per-frame pose pipeline for one character state: locomotion weight blending, FABRIK chain
-- solving, wave-driven offset sampling, two-bone IK, clip sampling, the jump state machine,
-- gesture playback, jump-overlay blending, and writing the finished pose into Motor6D.Transform.
--
-- Split out of ProceduralAnimator to respect the 500-line limit. The split is a relocation: the
-- function bodies below are unchanged. This module holds no cross-frame state of its own; the
-- caller owns the State table and passes it in. The few collaborators it cannot own are injected
-- through the constructor, so this module never requires the animator back and the require graph
-- stays acyclic.

return function(Dependencies: { [string]: any }): any
local Config = Dependencies.Config
local MathLib = Dependencies.MathLib
local DispatchEvent = Dependencies.DispatchEvent
local ProfilingEnabled = Dependencies.ProfilingEnabled
-- Kinematics: orchestrated here, owned there.
local UpdateInverseKinematics = Dependencies.UpdateInverseKinematics
local UpdateFabrikChain = Dependencies.UpdateFabrikChain
local UpdateWaves = Dependencies.UpdateWaves
-- SampleEase wraps the shared easing table, so SetEasingOverride and clip sampling agree.
local SampleEase = Dependencies.SampleEase
-- Network: injected rather than required, so this module stays free of Shared-layer side effects.
local Network = Dependencies.Network
-- Preview mode is a live flag owned by the animator, read through a getter.
local IsPreviewMode = Dependencies.IsPreviewMode
local ProfileBegin = Dependencies.ProfileBegin
local ProfileEnd = Dependencies.ProfileEnd

--=========================================================
-- [1] CONSTANTS
--=========================================================

local LocomotionIdleMax = Config.Locomotion.IdleMax
local LocomotionWalkMax = Config.Locomotion.WalkMax
local LocomotionRunMax = Config.Locomotion.RunMax
local LocomotionBlendRate = Config.Locomotion.BlendRate
local MaxJoints = Config.MaxJoints


local IdleClip = Config.Compiled.Idle
local WalkClip = Config.Compiled.Walk
local RunClip = Config.Compiled.Run

local CompiledWaves = Config.Compiled.Waves
local FabrikChains = Config.FabrikChains

local RootJointIndex = Config.JointIndex.Root

local JumpStateGrounded = 0
local JumpStateAnticipation = 1
local JumpStateLaunch = 2
local JumpStateAirborne = 3
local JumpStateLanding = 4
local JumpStateRecovery = 5

local Abs = math.abs
local Sqrt = math.sqrt
local Exp = math.exp
local Floor = math.floor
local Clock = os.clock
local BufferFill = buffer.fill
local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32
local CFrameNew = CFrame.new
local CFrameAngles = CFrame.fromEulerAnglesXYZ
local CFrameIdentity = CFrame.identity
local Vector3New = Vector3.new

local PosePipeline = {}

--=========================================================
-- [2] POSE BUFFER
--=========================================================
-- Writers and geometry live in the leaf PoseBuffer module, so this module and ClientRigKinematics
-- can both use them without requiring each other.

local PoseBuffer = require(script.Parent.PoseBuffer)
local WritePoseAdd = PoseBuffer.WritePoseAdd
local PoseBufferLength = PoseBuffer.PoseBufferLength
local PoseBytesPerJoint = PoseBuffer.PoseBytesPerJoint

--=========================================================
-- [3] LOCOMOTION WEIGHTS
--=========================================================
-- Moved verbatim from ProceduralAnimator's [6] section: blends idle/walk/run weights and
-- advances the three clip phases.

local function UpdateLocomotionWeights(State: any, DeltaTime: number): ()
    local Humanoid = State.Humanoid
    local RootPart = State.RootPart
    local Velocity = RootPart.AssemblyLinearVelocity
    local RawSpeed = Sqrt(Velocity.X * Velocity.X + Velocity.Z * Velocity.Z)

    -- Exponential low-pass filter: AssemblyLinearVelocity jitters frame to frame and would
    -- otherwise shimmer the idle/walk/run blend. Filtered value lives on the state so there
    -- is no allocation and no cross-character coupling. Rate 0 disables the filter.
    local FilterRate = Config.VelocityFilterRate
    local HorizontalSpeed
    if FilterRate and FilterRate > 0.0 then
        local Previous = State.FilteredSpeed
        local Filtered = Previous + (RawSpeed - Previous) * (1.0 - Exp(-FilterRate * DeltaTime))
        State.FilteredSpeed = Filtered
        HorizontalSpeed = Filtered
    else
        State.FilteredSpeed = RawSpeed
        HorizontalSpeed = RawSpeed
    end

    if HorizontalSpeed < 0.05 then
        HorizontalSpeed = Humanoid.MoveDirection.Magnitude * Humanoid.WalkSpeed
    end
    State.Speed = HorizontalSpeed

    local IdleWeight, WalkWeight, RunWeight
    if HorizontalSpeed <= LocomotionIdleMax then
        IdleWeight = 1.0
        WalkWeight = 0.0
        RunWeight = 0.0
    elseif HorizontalSpeed <= LocomotionWalkMax then
        local Alpha = (HorizontalSpeed - LocomotionIdleMax) / (LocomotionWalkMax - LocomotionIdleMax)
        IdleWeight = 1.0 - Alpha
        WalkWeight = Alpha
        RunWeight = 0.0
    elseif HorizontalSpeed <= LocomotionRunMax then
        local Alpha = (HorizontalSpeed - LocomotionWalkMax) / (LocomotionRunMax - LocomotionWalkMax)
        IdleWeight = 0.0
        WalkWeight = 1.0 - Alpha
        RunWeight = Alpha
    else
        IdleWeight = 0.0
        WalkWeight = 0.0
        RunWeight = 1.0
    end

    local Blend = 1.0 - Exp(-LocomotionBlendRate * DeltaTime)
    State.IdleWeight += (IdleWeight - State.IdleWeight) * Blend
    State.WalkWeight += (WalkWeight - State.WalkWeight) * Blend
    State.RunWeight += (RunWeight - State.RunWeight) * Blend

    State.IdlePhase = (State.IdlePhase + DeltaTime / IdleClip.Period) % 1.0
    State.WalkPhase = (State.WalkPhase + (HorizontalSpeed * DeltaTime) / WalkClip.Stride) % 1.0
    State.RunPhase = (State.RunPhase + (HorizontalSpeed * DeltaTime) / RunClip.Stride) % 1.0
end

-- Declared up front because the state machine below closes over it. Assigned in [4] once the
-- pose-buffer writers exist.
local SampleClip: (Clip: any, Phase: number, Weight: number, PoseBuffer: buffer, EasingOverride: number, State: any?) -> number

-- Jump phases and gestures live in CharacterMotionState; bodies unchanged, state still on State.
local CharacterMotionState = require(script.Parent.CharacterMotionState)({
    Config = Config,
    DispatchEvent = DispatchEvent,
    MathLib = MathLib,
    -- Assigned in [4]; the closure reads the upvalue, so it picks up the real function.
    SampleClip = function(...)
        return SampleClip(...)
    end,
})
local UpdateJump = CharacterMotionState.UpdateJump
local UpdateGestures = CharacterMotionState.UpdateGestures

--=========================================================
-- [4] PIPELINE
--=========================================================

local function SampleKeyArray(Phases: { number }, Values: { number }, KeyCount: number, Phase: number, EasingId: number): number
    if KeyCount <= 1 then
        return Values[1] or 0.0
    end

    local KeyIndex = 1
    while KeyIndex < KeyCount and Phase > Phases[KeyIndex + 1] do
        KeyIndex += 1
    end

    if KeyIndex >= KeyCount then
        return Values[KeyCount]
    end

    local PhaseStart = Phases[KeyIndex]
    local PhaseEnd = Phases[KeyIndex + 1]
    local Span = PhaseEnd - PhaseStart
    local Alpha = 0.0
    if Span > 0.000001 then
        Alpha = (Phase - PhaseStart) / Span
    end
    Alpha = SampleEase(EasingId, MathLib.Clamp01(Alpha))

    local From = Values[KeyIndex]
    return From + (Values[KeyIndex + 1] - From) * Alpha
end

-- Samples a compiled clip additively into PoseBuffer and returns the scaled root offset.
function SampleClip(Clip: any, Phase: number, Weight: number, PoseBuffer: buffer, EasingOverride: number, State: any?): number
    if Weight <= 0.001 then
        return 0.0
    end

    local TrackCount = Clip.TrackCount
    local TrackJoint = Clip.TrackJoint
    local TrackKeyCount = Clip.TrackKeyCount
    local TrackPhase = Clip.TrackPhase
    local TrackX = Clip.TrackX
    local TrackY = Clip.TrackY
    local TrackZ = Clip.TrackZ
    local ClipEasingId = Clip.EasingId
    local PerJointEasing = State and State.EasingOverride or nil

    for TrackIndex = 1, TrackCount do
        local Joint = TrackJoint[TrackIndex]
        local KeyCount = TrackKeyCount[TrackIndex]
        local Phases = TrackPhase[TrackIndex]

        local EasingId = EasingOverride
        if EasingId == 0 then
            if PerJointEasing and PerJointEasing[Joint] ~= 0 then
                EasingId = PerJointEasing[Joint]
            else
                EasingId = ClipEasingId
            end
        end

        local X = SampleKeyArray(Phases, TrackX[TrackIndex], KeyCount, Phase, EasingId) * Weight
        local Y = SampleKeyArray(Phases, TrackY[TrackIndex], KeyCount, Phase, EasingId) * Weight
        local Z = SampleKeyArray(Phases, TrackZ[TrackIndex], KeyCount, Phase, EasingId) * Weight

        if Abs(X) + Abs(Y) + Abs(Z) > 0.00001 then
            WritePoseAdd(PoseBuffer, Joint, X, Y, Z)
        end
    end

    if Clip.VerticalKeyCount > 0 then
        local VerticalEasing = EasingOverride
        if VerticalEasing == 0 then
            VerticalEasing = ClipEasingId
        end
        return SampleKeyArray(
            Clip.VerticalPhases,
            Clip.VerticalValues,
            Clip.VerticalKeyCount,
            Phase,
            VerticalEasing
        ) * Weight
    end
    return 0.0
end


--=========================================================
-- [9] BLENDING
--=========================================================

local function BlendJumpOverlay(State: any): ()
    local Weight = State.JumpWeight
    if Weight <= 0.001 then
        return
    end

    local Pose = State.Pose
    local Overlay = State.Overlay
    local Inverse = 1.0 - Weight
    local Offset = 0
    while Offset < PoseBufferLength do
        local Base = BufferReadF32(Pose, Offset)
        local Target = BufferReadF32(Overlay, Offset)
        BufferWriteF32(Pose, Offset, Base * Inverse + Target * Weight)
        Offset += 4
    end
end

local function ApplyPose(State: any, DeltaTime: number): ()
    local Joints = State.Joints
    local Pose = State.Pose
    local Smooth = State.Smooth
    local Applied = State.Applied
    local Factor = MathLib.SmoothFactor(State.SmoothRate, DeltaTime)
    local RootOffsetY = State.RootOffsetY * State.LocomotionWeight
    local JointAmplitude = State.JointAmplitude

    for Joint = 1, MaxJoints do
        local Motor = Joints[Joint]
        if Motor then
            local Offset = (Joint - 1) * PoseBytesPerJoint
            local TargetX = BufferReadF32(Pose, Offset)
            local TargetY = BufferReadF32(Pose, Offset + 4)
            local TargetZ = BufferReadF32(Pose, Offset + 8)

            -- Per-joint amplitude (1.0 everywhere by default): scales the desired pose angles
            -- before smoothing, so gains/damps stay well behaved. Never exceeds 3x by
            -- construction (SetJointAmplitude clamps); a read + compare when unset.
            local Amplitude = JointAmplitude[Joint]
            if Amplitude ~= 1.0 then
                TargetX = TargetX * Amplitude
                TargetY = TargetY * Amplitude
                TargetZ = TargetZ * Amplitude
            end

            local CurrentX = BufferReadF32(Smooth, Offset)
            local CurrentY = BufferReadF32(Smooth, Offset + 4)
            local CurrentZ = BufferReadF32(Smooth, Offset + 8)

            local NewX = CurrentX + (TargetX - CurrentX) * Factor
            local NewY = CurrentY + (TargetY - CurrentY) * Factor
            local NewZ = CurrentZ + (TargetZ - CurrentZ) * Factor

            BufferWriteF32(Smooth, Offset, NewX)
            BufferWriteF32(Smooth, Offset + 4, NewY)
            BufferWriteF32(Smooth, Offset + 8, NewZ)

            -- Skip zero-weight joints entirely: no CFrame construction, no property write.
            local Magnitude = Abs(NewX) + Abs(NewY) + Abs(NewZ)
            if Magnitude > 0.0002 then
                if Joint == RootJointIndex then
                    -- Fast path: composed matrix product only when the vertical offset is live.
                    if Abs(RootOffsetY) > 0.0002 then
                        Motor.Transform = CFrameNew(0.0, RootOffsetY, 0.0) * CFrameAngles(NewX, NewY, NewZ)
                    else
                        Motor.Transform = CFrameAngles(NewX, NewY, NewZ)
                    end
                else
                    Motor.Transform = CFrameAngles(NewX, NewY, NewZ)
                end
                Applied[Joint] = true
            elseif Applied[Joint] then
                if Joint == RootJointIndex and Abs(RootOffsetY) > 0.0002 then
                    Motor.Transform = CFrameNew(0.0, RootOffsetY, 0.0)
                else
                    Motor.Transform = CFrameIdentity
                end
                Applied[Joint] = false
            end
        end
    end
end

--=========================================================
-- [10] UPDATE LOOP
--=========================================================

local function ComputeRootOffset(State: any, DeltaTime: number): number
    local Offset = SampleClip(IdleClip, State.IdlePhase, State.IdleWeight, State.Pose, 0, State)
        + SampleClip(WalkClip, State.WalkPhase, State.WalkWeight, State.Pose, 0, State)
        + SampleClip(RunClip, State.RunPhase, State.RunWeight, State.Pose, 0, State)
    if IsPreviewMode() then
        State.SquashSpring.Position = 0.0
        State.SquashSpring.Velocity = 0.0
        return 0.0
    end

    -- Squash & stretch: critically-damped-ish spring anchored at zero. The landing impulse in
    -- CharacterMotionState is what excites it; everywhere else it decays back to neutral.
    local SquashStretch = Config.SquashStretch
    local SquashOffset = 0.0
    if SquashStretch and SquashStretch.Enabled then
        local Step = DeltaTime
        if Step > 0.0667 then
            Step = 0.0667
        end
        SquashOffset = MathLib.StepSpring(State.SquashSpring, 0.0, SquashStretch.Stiffness, SquashStretch.Damping, Step)
    elseif State.SquashSpring then
        State.SquashSpring.Position = 0.0
        State.SquashSpring.Velocity = 0.0
    end

    return Offset + State.JumpOffset * State.JumpWeight + SquashOffset
end

local function UpdateLocalCharacter(State: any, DeltaTime: number): ()
    BufferFill(State.Pose, 0, PoseBufferLength, 0)
    BufferFill(State.Overlay, 0, PoseBufferLength, 0)

    UpdateLocomotionWeights(State, DeltaTime)

    if ProfilingEnabled then
        ProfileBegin("PA_ClipPlayback")
    end
    State.RootOffsetY = ComputeRootOffset(State, DeltaTime)
    UpdateJump(State, DeltaTime)
    BlendJumpOverlay(State)
    UpdateGestures(State, DeltaTime)
    if ProfilingEnabled then
        ProfileEnd()
    end

    if State.CameraDistance <= Config.LodIkDistance then
        UpdateInverseKinematics(State, DeltaTime)
    end

    -- FABRIK spine chain: subtle reach toward a wave-driven offset.
    local SpineChain = FabrikChains.Spine
    if SpineChain and State.Speed < LocomotionIdleMax then
        local BreathValue = MathLib.SampleCompiledWave(CompiledWaves.Breathing, State.IdlePhase * IdleClip.Period)
        UpdateFabrikChain(State, SpineChain, Vector3New(0.0, BreathValue * 0.5, 0.0), SpineChain.Weight * State.IdleWeight)
    end

    -- Idle waves: layered harmonics for breathing, head sway, body bob.
    if State.Speed < LocomotionWalkMax then
        UpdateWaves(State, State.IdlePhase * IdleClip.Period)
    end

    if ProfilingEnabled then
        ProfileBegin("PA_ApplyPose")
    end
    ApplyPose(State, DeltaTime)
    if ProfilingEnabled then
        ProfileEnd()
    end

    -- Throttled, render-rate independent send.
    State.SendAccumulator += DeltaTime
    local Interval = 1.0 / Config.SendRate
    if State.SendAccumulator >= Interval then
        State.SendAccumulator -= Interval
        if State.SendAccumulator > Interval then
            State.SendAccumulator = 0.0
        end
        State.Sequence = (State.Sequence + 1) % Config.Packet.SequenceModulus
        local RootPart = State.RootPart
        Network.SendPose(
            State.Sequence,
            Floor(Clock() * 1000.0) % 4294967296,
            RootPart.Position,
            RootPart.AssemblyLinearVelocity,
            State.Smooth,
            MaxJoints
        )
    end
end

local function UpdateRemoteCharacter(State: any, DeltaTime: number): ()
    if State.Player == nil then
        return
    end
    if not Network.SampleRemotePose(State.Player, State.Pose) then
        return
    end
    State.RootOffsetY = 0.0
    if ProfilingEnabled then
        ProfileBegin("PA_ApplyRemotePose")
    end
    ApplyPose(State, DeltaTime)
    if ProfilingEnabled then
        ProfileEnd()
    end
end



--=========================================================
-- [3] PUBLIC SURFACE
--=========================================================
-- ProceduralAnimator keeps ownership of the heartbeat, the active-state list, setup/teardown and
-- the public API. It calls these by name exactly as it called the local functions before the
-- split, so no call site changed.

PosePipeline.JumpStateGrounded = JumpStateGrounded
PosePipeline.JumpStateAnticipation = JumpStateAnticipation
PosePipeline.JumpStateLaunch = JumpStateLaunch
PosePipeline.JumpStateAirborne = JumpStateAirborne
PosePipeline.JumpStateLanding = JumpStateLanding
PosePipeline.JumpStateRecovery = JumpStateRecovery
PosePipeline.UpdateLocomotionWeights = UpdateLocomotionWeights
PosePipeline.SampleKeyArray = SampleKeyArray
PosePipeline.SampleClip = SampleClip
PosePipeline.FireBusEvent = CharacterMotionState.FireBusEvent
PosePipeline.BlendJumpOverlay = BlendJumpOverlay
PosePipeline.ApplyPose = ApplyPose
PosePipeline.ComputeRootOffset = ComputeRootOffset
PosePipeline.UpdateLocalCharacter = UpdateLocalCharacter
PosePipeline.UpdateRemoteCharacter = UpdateRemoteCharacter

return PosePipeline
end
