--!strict
--[[
    Tools/verify/src/02b-mock-rig.luau

    Part 2 of the offline mocked Roblox environment: the stock R15 character rig builder.
    Split out of 02-mock-services.luau so neither file exceeds the 500-line harness limit.

    Factory contract: called with (Mock, HumanoidClass, MockHelpers) after 02-mock-services.luau
    has built its services table. Assigns CreateR15Character onto MockHelpers (the same table
    as Game.__Mock and the value exposed as Env.Mock) so every consumer sees it, then returns
    MockHelpers.
]]

return function(Mock, HumanoidClass, MockHelpers)
local Vector3 = Mock.Vector3
local Vector3New = Vector3.new
local CFrame = Mock.CFrame
local Instance = Mock.Instance
local InstanceClass = Mock.InstanceClass

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

    local UpperTorso = MakePart(Character, "UpperTorso", Vector3New(2.0, 2.0, 1.0), Vector3New(0.0, 3.0, 0.0))
    local Torso = UpperTorso
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


MockHelpers.CreateR15Character = CreateR15Character
return MockHelpers
end
