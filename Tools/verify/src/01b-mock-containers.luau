--!strict
--[[
    Tools/verify/src/01b-mock-containers.luau

    Part 2 of the offline Roblox/Studio environment used by Tools/verify. Pairs with
    01-mock-value-types.luau (Vector3/CFrame); this file adds Signals, the Instance mock and
    Enum. Extends the shared mock table in place and returns it, so every consumer sees a
    single consistent set of mock classes.
]]

return function(Mock)
local CFrame = Mock.CFrame

--=========================================================
-- [4] SIGNALS
--=========================================================

local SignalClass = {}
SignalClass.__index = SignalClass

function SignalClass.new()
    return setmetatable({ Listeners = {}, Count = 0 }, SignalClass)
end

function SignalClass.Connect(Self, Callback)
    local Listener = { Callback = Callback, Connected = true }
    Self.Count += 1
    Self.Listeners[Self.Count] = Listener

    local Connection = { Connected = true }
    local function Disconnect()
        if not Listener.Connected then
            return
        end
        Listener.Connected = false
        Connection.Connected = false
        for Index = 1, Self.Count do
            if Self.Listeners[Index] == Listener then
                Self.Listeners[Index] = Self.Listeners[Self.Count]
                Self.Listeners[Self.Count] = nil
                Self.Count -= 1
                break
            end
        end
    end
    Connection.Disconnect = Disconnect
    Connection.disconnect = Disconnect
    return Connection
end

function SignalClass.Fire(Self, ...)
    local Count = Self.Count
    if Count == 0 then
        return
    end
    local Snapshot = table.create(Count)
    for Index = 1, Count do
        Snapshot[Index] = Self.Listeners[Index]
    end
    for Index = 1, Count do
        local Listener = Snapshot[Index]
        if Listener and Listener.Connected then
            Listener.Callback(...)
        end
    end
end

--=========================================================
-- [5] INSTANCE
--=========================================================
-- A plain table with ordered children. Parent assignment is intercepted so the tree, and the
-- ChildAdded/ChildRemoved/Destroying signals, behave the way framework code expects.

local InstanceClass = {}

InstanceClass.Ancestry = {
    Instance = {},
    Folder = { "Instance" },
    Model = { "Instance" },
    BasePart = { "Instance" },
    Part = { "BasePart", "Instance" },
    MeshPart = { "BasePart", "Instance" },
    JointInstance = { "Instance" },
    Motor6D = { "JointInstance", "Instance" },
    Attachment = { "Instance" },
    Constraint = { "Instance" },
    AnimationConstraint = { "Constraint", "Instance" },
    BallSocketConstraint = { "Constraint", "Instance" },
    RigidConstraint = { "Constraint", "Instance" },
    Humanoid = { "Instance" },
    BaseScript = { "Instance" },
    Script = { "BaseScript", "Instance" },
    LocalScript = { "BaseScript", "Instance" },
    ModuleScript = { "Instance" },
    BaseRemoteEvent = { "Instance" },
    RemoteEvent = { "BaseRemoteEvent", "Instance" },
    UnreliableRemoteEvent = { "BaseRemoteEvent", "Instance" },
    BindableEvent = { "Instance" },
    ValueBase = { "Instance" },
    StringValue = { "ValueBase", "Instance" },
    ObjectValue = { "ValueBase", "Instance" },
    Camera = { "Instance" },
    Animator = { "Instance" },
    HumanoidDescription = { "Instance" },
}

function InstanceClass.IsA(Self, ClassName)
    if Self.ClassName == ClassName then
        return true
    end
    local Ancestry = InstanceClass.Ancestry[Self.ClassName]
    if not Ancestry then
        return false
    end
    for Index = 1, #Ancestry do
        if Ancestry[Index] == ClassName then
            return true
        end
    end
    return false
end

function InstanceClass.GetChildren(Self)
    local Children = table.create(Self.ChildCount)
    for Index = 1, Self.ChildCount do
        Children[Index] = Self.ChildList[Index]
    end
    return Children
end

function InstanceClass.GetDescendants(Self)
    local Out = {}
    local Count = 0
    local function Visit(Node)
        for Index = 1, Node.ChildCount do
            local Child = Node.ChildList[Index]
            Count += 1
            Out[Count] = Child
            Visit(Child)
        end
    end
    Visit(Self)
    return Out
end

function InstanceClass.FindFirstChild(Self, Name, Recursive)
    for Index = 1, Self.ChildCount do
        local Child = Self.ChildList[Index]
        if Child.Name == Name then
            return Child
        end
    end
    if Recursive then
        for Index = 1, Self.ChildCount do
            local Found = InstanceClass.FindFirstChild(Self.ChildList[Index], Name, true)
            if Found then
                return Found
            end
        end
    end
    return nil
end

function InstanceClass.FindFirstChildOfClass(Self, ClassName)
    for Index = 1, Self.ChildCount do
        local Child = Self.ChildList[Index]
        if Child.ClassName == ClassName then
            return Child
        end
    end
    return nil
end

function InstanceClass.FindFirstAncestorWhichIsA(Self, ClassName)
    local Current = Self.Parent
    while Current do
        if InstanceClass.IsA(Current, ClassName) then
            return Current
        end
        Current = Current.Parent
    end
    return nil
end

function InstanceClass.WaitForChild(Self, Name, Timeout)
    return InstanceClass.FindFirstChild(Self, Name)
end

function InstanceClass.SetAttribute(Self, Name, Value)
    Self.Attributes[Name] = Value
end

function InstanceClass.GetAttribute(Self, Name)
    return Self.Attributes[Name]
end

function InstanceClass.GetPivot(Self)
    return CFrame.new(0.0, 0.0, 0.0)
end

local function InstanceAddChild(ParentInstance, Child)
    ParentInstance.ChildCount += 1
    ParentInstance.ChildList[ParentInstance.ChildCount] = Child
    -- Roblox lets scripts index a direct child by name (folder.ModuleScript). Keep a name map
    -- so the framework's `script.Parent.X` navigation resolves without a linear scan.
    local ByName = ParentInstance._ChildByName
    if ByName then
        local Existing = ByName[Child.Name]
        if Existing == nil then
            ByName[Child.Name] = Child
        elseif type(Existing) == "table" and Existing.ClassName then
            ByName[Child.Name] = { Existing, Child }
        else
            Existing[#Existing + 1] = Child
        end
    end
    SignalClass.Fire(ParentInstance.ChildAdded, Child)
end

local function InstanceUnlinkName(ParentInstance, Child)
    local ByName = ParentInstance._ChildByName
    if not ByName then
        return
    end
    local Existing = ByName[Child.Name]
    if Existing == Child then
        ByName[Child.Name] = nil
    elseif type(Existing) == "table" then
        for Index = 1, #Existing do
            if Existing[Index] == Child then
                table.remove(Existing, Index)
                if #Existing == 1 then
                    ByName[Child.Name] = Existing[1]
                end
                break
            end
        end
    end
end

local function InstanceRemoveChild(ParentInstance, Child)
    for Index = 1, ParentInstance.ChildCount do
        if ParentInstance.ChildList[Index] == Child then
            ParentInstance.ChildList[Index] = ParentInstance.ChildList[ParentInstance.ChildCount]
            ParentInstance.ChildList[ParentInstance.ChildCount] = nil
            ParentInstance.ChildCount -= 1
            break
        end
    end
    InstanceUnlinkName(ParentInstance, Child)
    SignalClass.Fire(ParentInstance.ChildRemoved, Child)
end

InstanceClass.AddChild = InstanceAddChild
InstanceClass.RemoveChild = InstanceRemoveChild

function InstanceClass.DestroyChildren(Self)
    local Children = InstanceClass.GetChildren(Self)
    for Index = 1, #Children do
        Children[Index]:Destroy()
    end
end

-- Parent is a raw field named "_Parent"; reads and writes are intercepted so the tree stays
-- consistent and ChildAdded/ChildRemoved/Destroying behave as scripts expect.

local InstanceMetatable = {}

InstanceMetatable.__index = function(Self, Key)
    if Key == "Parent" then
        return rawget(Self, "_Parent")
    end
    local Member = InstanceClass[Key]
    if Member ~= nil then
        return Member
    end
    local ByName = rawget(Self, "_ChildByName")
    return ByName and ByName[Key] or nil
end

InstanceMetatable.__newindex = function(Self, Key, NewValue)
    if Key == "Parent" then
        local Previous = rawget(Self, "_Parent")
        if Previous then
            InstanceRemoveChild(Previous, Self)
        end
        rawset(Self, "_Parent", NewValue)
        if NewValue then
            InstanceAddChild(NewValue, Self)
        end
        SignalClass.Fire(rawget(Self, "AncestryChanged"), Self, NewValue)
        return
    end
    if Key == "Name" then
        local ParentInstance = rawget(Self, "_Parent")
        if ParentInstance then
            InstanceUnlinkName(ParentInstance, Self)
        end
        rawset(Self, Key, NewValue)
        if ParentInstance then
            InstanceAddChild(ParentInstance, Self)
            -- The child was re-registered above; remove the duplicate ordering entry.
            local Count = ParentInstance.ChildCount
            if Count > 0 and ParentInstance.ChildList[Count] == Self then
                ParentInstance.ChildList[Count] = nil
                ParentInstance.ChildCount = Count - 1
            end
            for Index = 1, ParentInstance.ChildCount do
                if ParentInstance.ChildList[Index] == Self then
                    ParentInstance.ChildList[Index] = nil
                    local Last = ParentInstance.ChildCount
                    ParentInstance.ChildList[Index] = ParentInstance.ChildList[Last]
                    ParentInstance.ChildList[Last] = nil
                    ParentInstance.ChildCount = Last - 1
                    break
                end
            end
        end
        return
    end
    rawset(Self, Key, NewValue)
end

-- Class initialisers let other harness layers attach behaviour to a class name (remotes get
-- their event signals this way) without the value-type layer depending on them.
InstanceClass.ClassInitialisers = {}

function InstanceClass.RegisterClassInitialiser(ClassName, Initialiser)
    InstanceClass.ClassInitialisers[ClassName] = Initialiser
end

function InstanceClass.new(ClassName, Name)
    local Value = setmetatable({
        ClassName = ClassName or "Instance",
        Name = Name or ClassName or "Instance",
        _Parent = nil,
        _ChildByName = {},
        ChildList = {},
        ChildCount = 0,
        Attributes = {},
        Destroyed = false,
        ChildAdded = SignalClass.new(),
        ChildRemoved = SignalClass.new(),
        Destroying = SignalClass.new(),
        AncestryChanged = SignalClass.new(),
        AttributeChanged = SignalClass.new(),
        Changed = SignalClass.new(),
    }, InstanceMetatable)
    local Initialiser = InstanceClass.ClassInitialisers[ClassName]
    if Initialiser then
        Initialiser(Value)
    end
    return Value
end

InstanceClass.Destroy = function(Self)
    local Children = InstanceClass.GetChildren(Self)
    for Index = 1, #Children do
        Children[Index]:Destroy()
    end
    SignalClass.Fire(rawget(Self, "Destroying"))
    rawset(Self, "Destroyed", true)
    Self.Parent = nil
end

local Instance = {
    new = function(ClassName, Parent, Name)
        local Value = InstanceClass.new(ClassName, Name)
        if Parent then
            Value.Parent = Parent
        end
        return Value
    end,
    Class = InstanceClass,
}

--=========================================================
-- [6] ENUM
--=========================================================

local function DefineEnum(Name, ItemNames)
    local EnumType = {}
    local Items = {}
    for Index = 1, #ItemNames do
        local ItemName = ItemNames[Index]
        local Item = { Name = ItemName, Value = Index, EnumType = EnumType }
        EnumType[ItemName] = Item
        Items[Index] = Item
    end
    setmetatable(EnumType, {
        __index = function(Self, Key)
            if Key == "GetEnumItems" then
                return function()
                    local Copy = table.create(#Items)
                    for Index = 1, #Items do
                        Copy[Index] = Items[Index]
                    end
                    return Copy
                end
            elseif Key == "FromName" then
                return function(Named)
                    return EnumType[Named]
                end
            elseif Key == "FromValue" then
                return function(Named)
                    return Items[Named]
                end
            end
            return nil
        end,
    })
    return EnumType
end

local Enum = {
    Material = DefineEnum("Material", {
        "Plastic", "Air", "Wood", "Concrete", "Grass", "Sand", "Metal", "Water",
    }),
    HumanoidStateType = DefineEnum("HumanoidStateType", {
        "FallingDown", "Running", "RunningNoPhysics", "Climbing", "StrafingNoPhysics",
        "Ragdoll", "GettingUp", "Jumping", "Landed", "Freefall", "Flying", "Swimming",
        "Seated", "PlatformStanding", "Dead", "Physics", "None",
    }),
    HumanoidRigType = DefineEnum("HumanoidRigType", { "R6", "R15" }),
    EasingStyle = DefineEnum("EasingStyle", {
        "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic",
        "Exponential", "Circular", "Cubic",
    }),
    EasingDirection = DefineEnum("EasingDirection", { "In", "Out", "InOut" }),
    RaycastFilterType = DefineEnum("RaycastFilterType", { "Exclude", "Include" }),
    NormalId = DefineEnum("NormalId", { "Right", "Top", "Back", "Left", "Bottom", "Front" }),
}

Mock.SignalClass = SignalClass
Mock.Instance = Instance
Mock.InstanceClass = InstanceClass
Mock.Enum = Enum
return Mock
end
