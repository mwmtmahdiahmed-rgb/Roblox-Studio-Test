-- ProceduralAnimation/Client/CharacterJoints
-- Character rig discovery: locating the Motor6D for every joint slot, caching it once, recording
-- the rest-pose bone axis, and measuring limb lengths from the rest C0/C1 data.
--
-- Split out of ProceduralAnimator to respect the 500-line limit. The split is a relocation: the
-- function bodies below are unchanged. Everything here is a pure query of the character rig; the
-- returned cache lives on the caller's State table, which is why no state is held in this module.

return function(Dependencies)
local Config = Dependencies.Config
local Changelog = Dependencies.Changelog

--=========================================================
-- [1] CONSTANTS
--=========================================================

local JointNames = Config.JointNames
local JointAliases = Config.JointAliases
local OptionalJoints = Config.OptionalJoints
local RequireOptionalJoints = Config.RequireOptionalJoints
local MaxJoints = Config.MaxJoints

local LegHip = Config.LegJointIndex.Hip
local LegKnee = Config.LegJointIndex.Knee
local LegAnkle = Config.LegJointIndex.Ankle
local ArmShoulder = Config.ArmJointIndex.Shoulder
local ArmElbow = Config.ArmJointIndex.Elbow

local Vector3New = Vector3.new

local CharacterJoints = {}

--=========================================================
-- [2] DISCOVERY
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
-- [3] PUBLIC SURFACE
--=========================================================

CharacterJoints.FindMotor6D = FindMotor6D
CharacterJoints.CacheJoints = CacheJoints
CharacterJoints.CacheLimbLengths = CacheLimbLengths

return CharacterJoints
end
