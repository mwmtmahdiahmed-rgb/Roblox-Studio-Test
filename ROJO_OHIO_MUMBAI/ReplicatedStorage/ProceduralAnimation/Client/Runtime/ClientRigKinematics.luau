--!strict
-- ProceduralAnimation/Client/ClientRigKinematics
-- Inverse kinematics and procedural chain solving for a character rig:
--   * FABRIK chain solving driven by authored chain definitions (the spine chain ships enabled),
--   * wave-driven additive joint offsets,
--   * a two-bone analytic solver with a pole vector,
--   * foot raycasting, ground alignment, and hand target IK.
--
-- Split out of ProceduralAnimator to respect the 500-line limit. The function bodies are a
-- relocation of the original [7] section; the only edits are the forward declaration of
-- ApplyWorldDirection (it was a global before, which was the original scope defect) and turning
-- it into a local. Everything is exposed through the returned table so the pose pipeline can
-- call it by name.

return function(Dependencies: { [string]: any }): any
local Config = Dependencies.Config
local MathLib = Dependencies.MathLib
local Workspace = Dependencies.Workspace
local PoseBuffer = require(script.Parent.PoseBuffer)
local WritePoseAdd = PoseBuffer.WritePoseAdd
local WritePoseBlend = PoseBuffer.WritePoseBlend

--=========================================================
-- [1] CONSTANTS
--=========================================================

local Abs = math.abs
local Sqrt = math.sqrt
local Exp = math.exp
local Sin = math.sin
local Acos = math.acos
local Atan2 = math.atan2
local Clamp = math.clamp
local CFrameAxisAngle = CFrame.fromAxisAngle
local Vector3New = Vector3.new

local LegHip = Config.LegJointIndex.Hip
local LegKnee = Config.LegJointIndex.Knee
local LegAnkle = Config.LegJointIndex.Ankle
local ArmShoulder = Config.ArmJointIndex.Shoulder
local ArmElbow = Config.ArmJointIndex.Elbow

local WaveOrder = Config.Compiled.WaveOrder
local CompiledWaves = Config.Compiled.Waves
local JointIndex = Config.JointIndex
local NeckJointIndex = JointIndex.Neck

local Kinematics = {}

--=========================================================
-- [2] CHAINS, WAVES AND IK
--=========================================================

--=========================================================
-- [7] INVERSE KINEMATICS
--=========================================================

-- Defined further down; declared here so the chain helpers below close over a single upvalue
-- instead of resolving an accidental global.
local ApplyWorldDirection: (State: any, JointIndexValue: number, DirectionX: number, DirectionY: number, DirectionZ: number, Weight: number) -> ()

-- FABRIK chain update: drives multi-bone chains (spine, tail) toward a target.
-- ChainState holds pre-allocated positions; we reuse them every frame.

local function UpdateFabrikChain(State: any, ChainDef: any, TargetOffset: any, Weight: number): ()
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
    -- The solver only reads .X/.Y/.Z, so a per-chain scratch table replaces a fresh Vector3
    -- allocation every frame.
    local EndRest = Positions[BoneCount + 1]
    local Target = ChainState.TargetScratch
    Target.X = EndRest.X + TargetOffset.X
    Target.Y = EndRest.Y + TargetOffset.Y
    Target.Z = EndRest.Z + TargetOffset.Z

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
local WaveJointMap: { [string]: { any } } = {
    Breathing = { JointIndex.Waist, JointIndex.Chest },
    HeadSway = { JointIndex.Neck },
    BodyBob = { JointIndex.Waist },
}

local function UpdateWaves(State: any, Time: number): ()
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
local function SolveTwoBoneChain(RootPosition: any, TargetPosition: any, Length1: number, Length2: number, PolePosition: any): (number, number, number, number, number, number)
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
function ApplyWorldDirection(State: any, JointIndexValue: number, DirectionX: number, DirectionY: number, DirectionZ: number, Weight: number): ()
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

-- Look-at: aims the Neck joint toward a world-space target by blending an additive yaw/pitch
-- into the pose buffer. Angles are measured in the root part's frame, so the head tracks targets
-- relative to the body's facing; the exponential weight smoothing means targets appear and
-- disappear gradually instead of snapping. Yaw/pitch are clamped to the same limits as IK.
-- Target and weights live on the state; a nil target disables aiming entirely.
local function ApplyLookAt(State: any, DeltaTime: number): ()
    local TargetWeight = State.LookAtTargetWeight
    if TargetWeight == nil then
        TargetWeight = 0.0
    end

    local Smoothing = Config.LookAt and Config.LookAt.Smoothing or 8.0
    local Blend = 1.0 - Exp(-Smoothing * DeltaTime)
    local PreviousWeight = State.LookAtWeight or 0.0
    local Applied = PreviousWeight + (TargetWeight - PreviousWeight) * Blend
    State.LookAtWeight = Applied
    if Applied < 0.001 then
        return
    end

    local Target = State.LookAtTarget
    if not Target then
        return
    end

    local Joint = State.Joints[NeckJointIndex]
    if not Joint then
        return
    end

    local Root = State.RootPart
    local NeckCFrame = Joint.Part0.CFrame * Joint.C0
    local ToTargetX = Target.X - NeckCFrame.Position.X
    local ToTargetY = Target.Y - NeckCFrame.Position.Y
    local ToTargetZ = Target.Z - NeckCFrame.Position.Z
    local Horizontal = Sqrt(ToTargetX * ToTargetX + ToTargetZ * ToTargetZ)
    local Distance = Sqrt(Horizontal * Horizontal + ToTargetY * ToTargetY)
    if Distance < 0.05 then
        return
    end

    -- Rotate the direction into the root part's frame so yaw/pitch are body-relative.
    local LocalDirection = Root.CFrame.Rotation:VectorToObjectSpace(Vector3New(ToTargetX, ToTargetY, ToTargetZ))
    local LocalHorizontal = Sqrt(LocalDirection.X * LocalDirection.X + LocalDirection.Z * LocalDirection.Z)

    local AngleLimit = Config.IkAngleLimitMax
    local Pitch
    if LocalHorizontal > 0.0001 then
        Pitch = Clamp(Atan2(LocalDirection.Y, LocalHorizontal), -AngleLimit, AngleLimit)
    else
        -- Target almost directly overhead/underfoot: pitch by sign only, yaw is undefined.
        Pitch = LocalDirection.Y >= 0.0 and AngleLimit or -AngleLimit
    end
    local Yaw = Clamp(Atan2(-LocalDirection.X, -LocalDirection.Z), -AngleLimit, AngleLimit)

    -- Blend (not replace) from whatever clips/IK wrote toward the aim, by the smoothed weight.
    WritePoseBlend(State.Pose, NeckJointIndex, Pitch, Yaw, 0.0, Applied)
end

local function UpdateInverseKinematics(State: any, DeltaTime: number): ()
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
                local RayDirection = State.FootRayDirection
                if not RayDirection then
                    RayDirection = Vector3New(0.0, -Config.FootRayLength, 0.0)
                    State.FootRayDirection = RayDirection
                end
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
-- [3] PUBLIC SURFACE
--=========================================================

Kinematics.UpdateFabrikChain = UpdateFabrikChain
Kinematics.UpdateWaves = UpdateWaves
Kinematics.SolveTwoBoneChain = SolveTwoBoneChain
Kinematics.UpdateInverseKinematics = UpdateInverseKinematics
Kinematics.ApplyWorldDirection = ApplyWorldDirection
Kinematics.ApplyLookAt = ApplyLookAt

return Kinematics
end
