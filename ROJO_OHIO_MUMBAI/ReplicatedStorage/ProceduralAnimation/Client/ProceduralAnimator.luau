-- ProceduralAnimation/Client/ProceduralAnimator
-- All motion is written to Motor6D.Transform. The Humanoid stays alive and in charge of physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Shared.AnimationConfig)
local MathLib = require(script.Parent.Parent.Shared.AnimationMath)
local Network = require(script.Parent.Parent.Shared.AnimationNetwork)
local Changelog = require(script.Parent.Parent.Shared.Changelog)

local Animator = {}

--=========================================================
-- [1] CONSTANTS
--=========================================================

local JointIndex = Config.JointIndex
local JointNames = Config.JointNames
local JointAliases = Config.JointAliases
local OptionalJoints = Config.OptionalJoints
local RequireOptionalJoints = Config.RequireOptionalJoints
local MaxJoints = Config.MaxJoints
local MaxGestures = Config.MaxGestures
local MaxEventId = Config.MaxEventId

local PoseBytesPerJoint = 12
local PoseBufferLength = MaxJoints * PoseBytesPerJoint

local IdleClip = Config.Compiled.Idle
local WalkClip = Config.Compiled.Walk
local RunClip = Config.Compiled.Run
local JumpClips = Config.Compiled.Jump
local GestureClips = Config.Compiled.Gestures
local CompiledWaves = Config.Compiled.Waves
local WaveOrder = Config.Compiled.WaveOrder
local FabrikChains = Config.FabrikChains

local RootJointIndex = JointIndex.Root
local LegHip = Config.LegJointIndex.Hip
local LegKnee = Config.LegJointIndex.Knee
local LegAnkle = Config.LegJointIndex.Ankle
local ArmShoulder = Config.ArmJointIndex.Shoulder
local ArmElbow = Config.ArmJointIndex.Elbow

local LocomotionIdleMax = Config.Locomotion.IdleMax
local LocomotionWalkMax = Config.Locomotion.WalkMax
local LocomotionRunMax = Config.Locomotion.RunMax
local LocomotionBlendRate = Config.Locomotion.BlendRate

local JumpStateGrounded = 0
local JumpStateAnticipation = 1
local JumpStateLaunch = 2
local JumpStateAirborne = 3
local JumpStateLanding = 4
local JumpStateRecovery = 5

-- Localised every global and library call used on the per-frame path.
local Abs = math.abs
local Sqrt = math.sqrt
local Exp = math.exp
local Sin = math.sin
local Acos = math.acos
local Clamp = math.clamp
local Floor = math.floor
local Clock = os.clock
local BufferCreate = buffer.create
local BufferFill = buffer.fill
local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32
local CFrameNew = CFrame.new
local CFrameAngles = CFrame.fromEulerAnglesXYZ
local CFrameAxisAngle = CFrame.fromAxisAngle
local CFrameIdentity = CFrame.identity
local Vector3New = Vector3.new
local ProfileBegin = debug.profilebegin
local ProfileEnd = debug.profileend
local ProfilingEnabled = Config.ProfilingEnabled
local PlayersGetPlayers = Players.GetPlayers

--=========================================================
-- [2] BUFFERS AND STATE POOL
--=========================================================

local CharacterStates = {}
local ActiveStates = {}
local ActiveStateCount = 0

local Running = false
local Initialized = false
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

local function WritePoseAdd(PoseBuffer, Joint, X, Y, Z)
    local Offset = (Joint - 1) * PoseBytesPerJoint
    BufferWriteF32(PoseBuffer, Offset, BufferReadF32(PoseBuffer, Offset) + X)
    BufferWriteF32(PoseBuffer, Offset + 4, BufferReadF32(PoseBuffer, Offset + 4) + Y)
    BufferWriteF32(PoseBuffer, Offset + 8, BufferReadF32(PoseBuffer, Offset + 8) + Z)
end

local function WritePoseBlend(PoseBuffer, Joint, X, Y, Z, Weight)
    local Offset = (Joint - 1) * PoseBytesPerJoint
    local Inverse = 1.0 - Weight
    BufferWriteF32(PoseBuffer, Offset, BufferReadF32(PoseBuffer, Offset) * Inverse + X * Weight)
    BufferWriteF32(PoseBuffer, Offset + 4, BufferReadF32(PoseBuffer, Offset + 4) * Inverse + Y * Weight)
    BufferWriteF32(PoseBuffer, Offset + 8, BufferReadF32(PoseBuffer, Offset + 8) * Inverse + Z * Weight)
end

--=========================================================
-- [5] JOINT CACHE
--=========================================================

local function FindMotor6D(Character, JointName, Aliases)
    local Found = Character:FindFirstChild(JointName, true)
    if Found and Found:IsA("Motor6D") then
        return Found
    end
    if Aliases then
        for AliasIndex = 1, #Aliases do
            local Candidate = Character:FindFirstChild(Aliases[AliasIndex], true)
            if Candidate and Candidate:IsA("Motor6D") then
                return Candidate
            end
        end
    end
    return nil
end

local function CacheJoints(State, Character)
    local Joints = State.Joints
    local BoneAxis = State.BoneAxis
    local Present = State.JointPresent
    local MissingCount = 0
    local MissingName = nil

    for Joint = 1, MaxJoints do
        local Name = JointNames[Joint]
        local Motor = FindMotor6D(Character, Name, JointAliases[Joint])
        if Motor then
            Joints[Joint] = Motor
            Present[Joint] = true
            -- The child bone direction expressed in Transform space: at rest
            -- Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse(), therefore the bone
            -- vector entering Transform is C1:Inverse().Position. Cached once; the rest C0/C1
            -- values are never written.
            local BoneVector = Motor.C1:Inverse().Position
            if BoneVector.Magnitude > 0.05 then
                BoneAxis[Joint] = BoneVector.Unit
            else
                BoneAxis[Joint] = Vector3New(0.0, -1.0, 0.0)
            end
        else
            Joints[Joint] = nil
            Present[Joint] = false
            -- OptionalJoints lists joints that MAY be absent (stock R15 has no Chest Motor6D).
            -- RequireOptionalJoints re-promotes them to hard requirements, so the policy is a
            -- single config switch instead of being hardcoded to "tolerate" here.
            if OptionalJoints[Joint] and not RequireOptionalJoints then
                Changelog.Log("Optional joint missing: " .. Name .. " (setup continues)")
            else
                MissingCount += 1
                if not MissingName then
                    MissingName = Name
                end
            end
        end
    end

    if MissingCount > 0 then
        return false, MissingName
    end
    return true, nil
end

local function CacheLimbLengths(State)
    local Joints = State.Joints
    for Side = 1, 2 do
        local HipJoint = Joints[LegHip[Side]]
        local KneeJoint = Joints[LegKnee[Side]]
        local AnkleJoint = Joints[LegAnkle[Side]]
        if HipJoint and KneeJoint and AnkleJoint then
            local HipPivot = (HipJoint.Part0.CFrame * HipJoint.C0).Position
            local KneePivot = (KneeJoint.Part0.CFrame * KneeJoint.C0).Position
            local AnklePivot = (AnkleJoint.Part0.CFrame * AnkleJoint.C0).Position
            State.LegLength1[Side] = (KneePivot - HipPivot).Magnitude
            State.LegLength2[Side] = (AnklePivot - KneePivot).Magnitude
        else
            State.LegLength1[Side] = 0.0
            State.LegLength2[Side] = 0.0
        end

        local ShoulderJoint = Joints[ArmShoulder[Side]]
        local ElbowJoint = Joints[ArmElbow[Side]]
        local WristJoint = Joints[ArmElbow[Side] + 2]
        if ShoulderJoint and ElbowJoint and WristJoint then
            local ShoulderPivot = (ShoulderJoint.Part0.CFrame * ShoulderJoint.C0).Position
            local ElbowPivot = (ElbowJoint.Part0.CFrame * ElbowJoint.C0).Position
            local WristPivot = (WristJoint.Part0.CFrame * WristJoint.C0).Position
            State.ArmLength1[Side] = (ElbowPivot - ShoulderPivot).Magnitude
            State.ArmLength2[Side] = (WristPivot - ElbowPivot).Magnitude
        else
            State.ArmLength1[Side] = 0.0
            State.ArmLength2[Side] = 0.0
        end
    end
end

--=========================================================
-- [6] LOCOMOTION
--=========================================================

local function UpdateLocomotionWeights(State, DeltaTime)
    local Humanoid = State.Humanoid
    local RootPart = State.RootPart
    local Velocity = RootPart.AssemblyLinearVelocity
    local HorizontalSpeed = Sqrt(Velocity.X * Velocity.X + Velocity.Z * Velocity.Z)

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

--=========================================================
-- [7] INVERSE KINEMATICS
--=========================================================

-- FABRIK chain update: drives multi-bone chains (spine, tail) toward a target.
-- ChainState holds pre-allocated positions; we reuse them every frame.
-- Forward declaration. UpdateFabrikChain (defined above the wave/IK helpers) calls
-- ApplyWorldDirection, whose body is defined further down the file. Declaring the local
-- here keeps the helper a single upvalue instead of an accidental global lookup.
local ApplyWorldDirection

local function UpdateFabrikChain(State, ChainDef, TargetOffset, Weight)
    if Weight <= 0.001 then
        return
    end
    local JointIds = ChainDef.Joints
    local JointCount = #JointIds
    if JointCount < 2 then
        return
    end

    local Joints = State.Joints
    local ChainState = State.FabrikChains[ChainDef]
    if not ChainState then
        return
    end

    -- Build the rest-pose chain positions from the current joint pivots.
    local Positions = ChainState.Positions
    local BoneCount = JointCount - 1
    local Lengths = ChainState.Lengths

    local RootJoint = Joints[JointIds[1]]
    if not RootJoint then
        return
    end
    local RootPivot = (RootJoint.Part0.CFrame * RootJoint.C0).Position
    Positions[1] = RootPivot

    for Index = 1, BoneCount do
        local Joint = Joints[JointIds[Index + 1]]
        if not Joint then
            return
        end
        local Pivot = (Joint.Part0.CFrame * Joint.C0).Position
        Positions[Index + 1] = Pivot
        if Index <= BoneCount then
            -- Lengths[i] is the distance from joint i to joint i+1.
        end
    end

    -- Compute bone lengths from rest pose (cached on first run).
    if not ChainState.LengthsReady then
        for Index = 1, BoneCount do
            local Dx = Positions[Index + 1].X - Positions[Index].X
            local Dy = Positions[Index + 1].Y - Positions[Index].Y
            local Dz = Positions[Index + 1].Z - Positions[Index].Z
            Lengths[Index] = Sqrt(Dx * Dx + Dy * Dy + Dz * Dz)
        end
        ChainState.LengthsReady = true
    end

    -- Target is the rest end-effector plus an offset (from waves or other sources).
    local EndRest = Positions[BoneCount + 1]
    local Target = Vector3New(
        EndRest.X + TargetOffset.X,
        EndRest.Y + TargetOffset.Y,
        EndRest.Z + TargetOffset.Z
    )

    MathLib.SolveFabrik(Positions, Lengths, Target, ChainDef.Tolerance, ChainDef.MaxIterations)

    -- Convert solved positions back into joint-space rotations and blend into the pose buffer.
    for Index = 1, BoneCount do
        local Joint = Joints[JointIds[Index]]
        if Joint then
            local ParentPos = Positions[Index]
            local ChildPos = Positions[Index + 1]
            local Dx = ChildPos.X - ParentPos.X
            local Dy = ChildPos.Y - ParentPos.Y
            local Dz = ChildPos.Z - ParentPos.Z
            local Len = Sqrt(Dx * Dx + Dy * Dy + Dz * Dz)
            if Len > 0.0001 then
                ApplyWorldDirection(State, JointIds[Index], Dx / Len, Dy / Len, Dz / Len, Weight)
            end
        end
    end
end

-- Wave sampling: layered harmonics applied additively to specific joints.
-- Driven from data in AnimationConfig; no code changes needed to add a new wave.
local WaveJointMap = {
    Breathing = { JointIndex.Waist, JointIndex.Chest },
    HeadSway = { JointIndex.Neck },
    BodyBob = { JointIndex.Waist },
}

local function UpdateWaves(State, Time)
    -- Walk the compile-time sorted order rather than pairs(): the lookup table is unordered,
    -- and a stable order keeps the additive result identical on every run and every peer.
    for OrderIndex = 1, #WaveOrder do
        local WaveName = WaveOrder[OrderIndex]
        local Compiled = CompiledWaves[WaveName]
        local Value = MathLib.SampleCompiledWave(Compiled, Time)
        local Joints = WaveJointMap[WaveName]
        if Joints then
            for Index = 1, #Joints do
                local Joint = Joints[Index]
                -- Apply to Y axis for breathing/sway, Z for bob.
                if WaveName == "BodyBob" then
                    WritePoseAdd(State.Pose, Joint, 0.0, 0.0, Value)
                else
                    WritePoseAdd(State.Pose, Joint, 0.0, Value, 0.0)
                end
            end
        end
    end
end



-- Two-bone analytic solver: law of cosines on the triangle formed by root, mid and target,
-- with the bend plane defined by a pole vector.
local function SolveTwoBoneChain(RootPosition, TargetPosition, Length1, Length2, PolePosition)
    local ToTargetX = TargetPosition.X - RootPosition.X
    local ToTargetY = TargetPosition.Y - RootPosition.Y
    local ToTargetZ = TargetPosition.Z - RootPosition.Z
    local Distance = Sqrt(ToTargetX * ToTargetX + ToTargetY * ToTargetY + ToTargetZ * ToTargetZ)

    if Distance < 0.0001 then
        Distance = 0.0001
        ToTargetY = 0.0001
    end

    local MaxReach = (Length1 + Length2) * Config.IkReachClamp
    local MinReach = Abs(Length1 - Length2) + 0.01
    local ClampedDistance = Clamp(Distance, MinReach, MaxReach)
    local DirectionX = ToTargetX / Distance
    local DirectionY = ToTargetY / Distance
    local DirectionZ = ToTargetZ / Distance

    local CosRoot = (Length1 * Length1 + ClampedDistance * ClampedDistance - Length2 * Length2)
        / (2.0 * Length1 * ClampedDistance)
    CosRoot = Clamp(CosRoot, -1.0, 1.0)
    local RootAngle = Acos(CosRoot)

    local PoleX = PolePosition.X - RootPosition.X
    local PoleY = PolePosition.Y - RootPosition.Y
    local PoleZ = PolePosition.Z - RootPosition.Z

    local Projection = PoleX * DirectionX + PoleY * DirectionY + PoleZ * DirectionZ
    local PlaneX = PoleX - DirectionX * Projection
    local PlaneY = PoleY - DirectionY * Projection
    local PlaneZ = PoleZ - DirectionZ * Projection
    local PlaneLength = Sqrt(PlaneX * PlaneX + PlaneY * PlaneY + PlaneZ * PlaneZ)

    if PlaneLength < 0.0001 then
        PlaneX, PlaneY, PlaneZ = 0.0, 0.0, 1.0
        PlaneLength = 1.0
    end

    local SinRoot = Sin(RootAngle)
    local UpX = DirectionX * CosRoot + (PlaneX / PlaneLength) * SinRoot
    local UpY = DirectionY * CosRoot + (PlaneY / PlaneLength) * SinRoot
    local UpZ = DirectionZ * CosRoot + (PlaneZ / PlaneLength) * SinRoot

    local MidX = RootPosition.X + UpX * Length1
    local MidY = RootPosition.Y + UpY * Length1
    local MidZ = RootPosition.Z + UpZ * Length1

    local LowerX = RootPosition.X + DirectionX * ClampedDistance - MidX
    local LowerY = RootPosition.Y + DirectionY * ClampedDistance - MidY
    local LowerZ = RootPosition.Z + DirectionZ * ClampedDistance - MidZ
    local LowerLength = Sqrt(LowerX * LowerX + LowerY * LowerY + LowerZ * LowerZ)
    if LowerLength < 0.0001 then
        LowerLength = 0.0001
    end

    return UpX, UpY, UpZ, LowerX / LowerLength, LowerY / LowerLength, LowerZ / LowerLength
end

-- Converts a desired world bone direction into a joint-space Euler offset and blends it into
-- the pose buffer. Everything still goes through Motor6D.Transform.
function ApplyWorldDirection(State, JointIndexValue, DirectionX, DirectionY, DirectionZ, Weight)
    local Joint = State.Joints[JointIndexValue]
    if not Joint then
        return
    end

    local JointCFrame = Joint.Part0.CFrame * Joint.C0
    local LocalDirection = JointCFrame.Rotation:VectorToObjectSpace(
        Vector3New(DirectionX, DirectionY, DirectionZ)
    )
    local Magnitude = LocalDirection.Magnitude
    if Magnitude < 0.0001 then
        return
    end
    LocalDirection = LocalDirection / Magnitude

    local BoneAxis = State.BoneAxis[JointIndexValue]
    local Dot = BoneAxis:Dot(LocalDirection)

    local EulerX, EulerY, EulerZ = 0.0, 0.0, 0.0
    if Dot < 0.99999 then
        local Axis = BoneAxis:Cross(LocalDirection)
        local AxisLength = Axis.Magnitude
        if AxisLength > 0.0001 then
            local Angle = Acos(Clamp(Dot, -1.0, 1.0))
            local Rotation = CFrameAxisAngle(Axis / AxisLength, Angle)
            EulerX, EulerY, EulerZ = Rotation:ToEulerAnglesXYZ()
        end
    end

    EulerX = Clamp(EulerX, Config.IkAngleLimitMin, Config.IkAngleLimitMax)
    EulerY = Clamp(EulerY, Config.IkAngleLimitMin, Config.IkAngleLimitMax)
    EulerZ = Clamp(EulerZ, Config.IkAngleLimitMin, Config.IkAngleLimitMax)

    WritePoseBlend(State.Pose, JointIndexValue, EulerX, EulerY, EulerZ, Weight)
end

local function UpdateInverseKinematics(State, DeltaTime)
    local Joints = State.Joints
    local RaycastParams = State.RaycastParams
    local Blend = 1.0 - Exp(-Config.IkBlendRate * DeltaTime)

    for Side = 1, 2 do
        local HipJoint = Joints[LegHip[Side]]
        local KneeJoint = Joints[LegKnee[Side]]
        local AnkleJoint = Joints[LegAnkle[Side]]

        if HipJoint and KneeJoint and AnkleJoint then
            local Length1 = State.LegLength1[Side]
            local Length2 = State.LegLength2[Side]

            if Length1 > 0.0 and Length2 > 0.0 then
                local HipPivot = (HipJoint.Part0.CFrame * HipJoint.C0).Position
                local Origin = Vector3New(HipPivot.X, HipPivot.Y + Config.FootRayHeight, HipPivot.Z)
                local RayDirection = Vector3New(0.0, -Config.FootRayLength, 0.0)
                local Result = Workspace:Raycast(Origin, RayDirection, RaycastParams)

                local Grounded = Result ~= nil
                local TargetWeight = Grounded and 1.0 or 0.0
                State.IkWeight[Side] += (TargetWeight - State.IkWeight[Side]) * Blend
                local Weight = State.IkWeight[Side]

                if Weight > 0.001 and Grounded then
                    local TargetPosition = Result.Position
                    local PolePosition = Vector3New(
                        HipPivot.X + (Side == 1 and -4.0 or 4.0),
                        HipPivot.Y,
                        HipPivot.Z + 6.0
                    )

                    local UpX, UpY, UpZ, LowerX, LowerY, LowerZ =
                        SolveTwoBoneChain(HipPivot, TargetPosition, Length1, Length2, PolePosition)

                    ApplyWorldDirection(State, LegHip[Side], UpX, UpY, UpZ, Weight)
                    ApplyWorldDirection(State, LegKnee[Side], LowerX, LowerY, LowerZ, Weight)

                    -- Foot alignment: rotate the foot's up vector onto the surface normal.
                    local FootUp = AnkleJoint.Part1.CFrame.UpVector
                    local Normal = Result.Normal
                    local AlignDot = FootUp:Dot(Normal)
                    if AlignDot < 0.9999 then
                        local Axis = FootUp:Cross(Normal)
                        local AxisLength = Axis.Magnitude
                        if AxisLength > 0.0001 then
                            local Angle = Acos(Clamp(AlignDot, -1.0, 1.0))
                            local JointCFrame = AnkleJoint.Part0.CFrame * AnkleJoint.C0
                            local LocalAxis = JointCFrame.Rotation:VectorToObjectSpace(Axis / AxisLength)
                            local Rotation = CFrameAxisAngle(LocalAxis.Unit, Angle)
                            local EulerX, EulerY, EulerZ = Rotation:ToEulerAnglesXYZ()
                            WritePoseBlend(
                                State.Pose,
                                LegAnkle[Side],
                                Clamp(EulerX, Config.IkAngleLimitMin, Config.IkAngleLimitMax),
                                Clamp(EulerY, Config.IkAngleLimitMin, Config.IkAngleLimitMax),
                                Clamp(EulerZ, Config.IkAngleLimitMin, Config.IkAngleLimitMax),
                                Weight * Config.FootAlignWeight
                            )
                        end
                    end
                end
            end
        end
    end

    -- Hand IK targets come from SetIkTarget and are blended the same way.
    for Side = 1, 2 do
        local Weight = State.HandWeight[Side]
        if Weight > 0.001 then
            local ShoulderJoint = Joints[ArmShoulder[Side]]
            local ElbowJoint = Joints[ArmElbow[Side]]
            if ShoulderJoint and ElbowJoint then
                local Length1 = State.ArmLength1[Side]
                local Length2 = State.ArmLength2[Side]
                if Length1 > 0.0 and Length2 > 0.0 then
                    local ShoulderPivot = (ShoulderJoint.Part0.CFrame * ShoulderJoint.C0).Position
                    local Target = State.HandTarget[Side]
                    local PolePosition = Vector3New(
                        ShoulderPivot.X + (Side == 1 and -4.0 or 4.0),
                        ShoulderPivot.Y - 4.0,
                        ShoulderPivot.Z - 4.0
                    )
                    local UpX, UpY, UpZ, LowerX, LowerY, LowerZ =
                        SolveTwoBoneChain(ShoulderPivot, Target, Length1, Length2, PolePosition)
                    ApplyWorldDirection(State, ArmShoulder[Side], UpX, UpY, UpZ, Weight)
                    ApplyWorldDirection(State, ArmElbow[Side], LowerX, LowerY, LowerZ, Weight)
                end
            end
        end
    end
end

--=========================================================
-- [8] CLIP PLAYBACK
--=========================================================

local function SampleKeyArray(Phases, Values, KeyCount, Phase, EasingId)
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
local function SampleClip(Clip, Phase, Weight, PoseBuffer, EasingOverride, State)
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

local function GetJumpSegment(StateId)
    if StateId == JumpStateAnticipation then
        return JumpClips[1]
    elseif StateId == JumpStateLaunch then
        return JumpClips[2]
    elseif StateId == JumpStateAirborne then
        return JumpClips[3]
    elseif StateId == JumpStateLanding then
        return JumpClips[4]
    elseif StateId == JumpStateRecovery then
        return JumpClips[5]
    end
    return nil
end

local function FireBusEvent(EventId)
    DispatchEvent(EventId, 1)
end

local function UpdateJump(State, DeltaTime)
    local Humanoid = State.Humanoid

    if State.JumpState ~= JumpStateGrounded then
        State.JumpTime += DeltaTime
        local Segment = GetJumpSegment(State.JumpState)
        if Segment then
            local Phase = 1.0
            if State.JumpState == JumpStateAirborne then
                -- Airborne holds until the humanoid reports a landing; ramp in over 0.25s.
                Phase = MathLib.Clamp01(State.JumpTime / 0.25)
            elseif Segment.Duration > 0.0001 then
                Phase = MathLib.Clamp01(State.JumpTime / Segment.Duration)
            end

            State.JumpOffset = SampleClip(Segment, Phase, 1.0, State.Overlay, 0, State)

            if State.JumpState ~= JumpStateAirborne
                and Segment.Duration > 0.0001
                and State.JumpTime >= Segment.Duration
            then
                State.JumpTime = 0.0
                State.JumpState += 1
                if State.JumpState > JumpStateRecovery then
                    State.JumpState = JumpStateGrounded
                    State.JumpOffset = 0.0
                    FireBusEvent(Config.EventId.ClipStop)
                end
            end
        else
            State.JumpState = JumpStateGrounded
        end
    end

    -- FloorMaterial poll: catches landings the state machine missed (ledges, low fps).
    if State.JumpState == JumpStateAirborne and Humanoid.FloorMaterial ~= Enum.Material.Air then
        State.JumpState = JumpStateLanding
        State.JumpTime = 0.0
        FireBusEvent(Config.EventId.Landing)
    end

    local TargetWeight = 0.0
    if State.JumpState ~= JumpStateGrounded then
        TargetWeight = 1.0
    end
    local Blend = 1.0 - Exp(-14.0 * DeltaTime)
    State.JumpWeight += (TargetWeight - State.JumpWeight) * Blend
end

local function UpdateGestures(State, DeltaTime)
    local Gestures = State.Gestures
    for Slot = 1, MaxGestures do
        local Gesture = Gestures[Slot]
        if Gesture.Active then
            Gesture.Time += DeltaTime
            local Alpha = Gesture.Time / Gesture.Duration
            if Alpha >= 1.0 then
                Gesture.Active = false
                Gesture.Weight = 0.0
                FireBusEvent(Config.EventId.ClipStop)
            else
                local Weight = 1.0
                if Alpha < 0.15 then
                    Weight = Alpha / 0.15
                elseif Alpha > 0.85 then
                    Weight = (1.0 - Alpha) / 0.15
                end
                Gesture.Weight = Weight
                if Weight > 0.001 then
                    SampleClip(Gesture.Clip, Alpha, Weight, State.Pose, Gesture.EasingId, State)
                end
            end
        end
    end
end

--=========================================================
-- [9] BLENDING
--=========================================================

local function BlendJumpOverlay(State)
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

local function ApplyPose(State, DeltaTime)
    local Joints = State.Joints
    local Pose = State.Pose
    local Smooth = State.Smooth
    local Applied = State.Applied
    local Factor = MathLib.SmoothFactor(State.SmoothRate, DeltaTime)
    local RootOffsetY = State.RootOffsetY * State.LocomotionWeight

    for Joint = 1, MaxJoints do
        local Motor = Joints[Joint]
        if Motor then
            local Offset = (Joint - 1) * PoseBytesPerJoint
            local TargetX = BufferReadF32(Pose, Offset)
            local TargetY = BufferReadF32(Pose, Offset + 4)
            local TargetZ = BufferReadF32(Pose, Offset + 8)

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
                    Motor.Transform = CFrameNew(0.0, RootOffsetY, 0.0) * CFrameAngles(NewX, NewY, NewZ)
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

local function ComputeRootOffset(State)
    local Offset = SampleClip(IdleClip, State.IdlePhase, State.IdleWeight, State.Pose, 0, State)
        + SampleClip(WalkClip, State.WalkPhase, State.WalkWeight, State.Pose, 0, State)
        + SampleClip(RunClip, State.RunPhase, State.RunWeight, State.Pose, 0, State)
    if PreviewMode then
        return 0.0
    end
    return Offset + State.JumpOffset * State.JumpWeight
end

local function UpdateLocalCharacter(State, DeltaTime)
    BufferFill(State.Pose, 0, PoseBufferLength, 0)
    BufferFill(State.Overlay, 0, PoseBufferLength, 0)

    UpdateLocomotionWeights(State, DeltaTime)

    if ProfilingEnabled then
        ProfileBegin("PA_ClipPlayback")
    end
    State.RootOffsetY = ComputeRootOffset(State)
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

local function UpdateRemoteCharacter(State, DeltaTime)
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

    for Index = 1, ActiveStateCount do
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

    -- Compact the active list after the loop so removal never disturbs iteration.
    local Index = 1
    while Index <= ActiveStateCount do
        local State = ActiveStates[Index]
        if State.Valid then
            Index += 1
        else
            ActiveStates[Index] = ActiveStates[ActiveStateCount]
            ActiveStates[ActiveStateCount] = nil
            ActiveStateCount -= 1
        end
    end
end

--=========================================================
-- [11] PUBLIC API
--=========================================================

local function CreateState(Character, IsLocal)
    local State = {
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
        IdleWeight = 1.0,
        WalkWeight = 0.0,
        RunWeight = 0.0,
        LocomotionWeight = 1.0,
        Speed = 0.0,

        JumpState = JumpStateGrounded,
        JumpTime = 0.0,
        JumpWeight = 0.0,
        JumpOffset = 0.0,

        RootOffsetY = 0.0,

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

local function OnHumanoidStateChanged(State, OldState, NewState)
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

local function SetupCharacter(Character)
    if not Character or not Character:IsA("Model") then
        return false
    end
    if CharacterStates[Character] then
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

    if IsLocal and PreviewMode then
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

    CharacterStates[Character] = State
    ActiveStateCount += 1
    ActiveStates[ActiveStateCount] = State

    Changelog.Log("Setup complete for " .. Character.Name)
    FireBusEvent(Config.EventId.Setup)

    return true
end

local function TeardownCharacter(Character)
    local State = CharacterStates[Character]
    if not State then
        return false
    end

    State.Valid = false
    CharacterStates[Character] = nil

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

function Animator.SetupCharacter(Character)
    return SetupCharacter(Character)
end

function Animator.TeardownCharacter(Character)
    return TeardownCharacter(Character)
end

function Animator.SetLocomotionWeight(Weight)
    local Clamped = MathLib.Clamp01(Weight)
    for Index = 1, ActiveStateCount do
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

    for Index = 1, ActiveStateCount do
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

    for Index = 1, ActiveStateCount do
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
    for Index = 1, ActiveStateCount do
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
    for Index = 1, ActiveStateCount do
        ActiveStates[Index].EasingOverride[JointIndexValue] = EasingId
    end
end

function Animator.SetPreviewMode(Enabled)
    PreviewMode = Enabled and true or false
    for Index = 1, ActiveStateCount do
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

local function TrackPlayer(Player)
    local LocalPlayer = Players.LocalPlayer
    if Player == LocalPlayer then
        return
    end
    Player.CharacterAdded:Connect(function(Character)
        task.defer(function()
            SetupCharacter(Character)
        end)
    end)
    Player.CharacterRemoving:Connect(function(Character)
        TeardownCharacter(Character)
    end)
    if Player.Character then
        SetupCharacter(Player.Character)
    end
end

function Animator.Init()
    if Initialized then
        return
    end
    Initialized = true

    Network.Init()

    local CurrentPlayers = PlayersGetPlayers(Players)
    for Index = 1, #CurrentPlayers do
        TrackPlayer(CurrentPlayers[Index])
    end

    Players.PlayerAdded:Connect(TrackPlayer)

    Players.PlayerRemoving:Connect(function(Player)
        if Player.Character then
            TeardownCharacter(Player.Character)
        end
        Network.ReleaseRemotePose(Player)
    end)

    Changelog.Log("ProceduralAnimator initialized")
    Animator.Start()
end

function Animator.IsRunning()
    return Running
end

return Animator
