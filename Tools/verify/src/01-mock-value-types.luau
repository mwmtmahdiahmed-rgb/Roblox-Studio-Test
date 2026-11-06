--[[
    Tools/verify/src/01-mock-value-types.luau

    Part 1 of the offline Roblox/Studio environment used by Tools/verify.

    This is VERIFICATION HARNESS CODE, not framework code. It is never placed in
    ReplicatedStorage. It lets every framework module run inside a real Luau VM outside
    Roblox Studio, with faithful stand-ins for the value types and containers the framework
    actually touches: Vector3, CFrame, Instance trees plus signals, and Enum.

    The numeric datatypes are written from their engine definitions (column-major rotation
    matrices, the documented XYZ Euler reconstruction used by ToEulerAnglesXYZ) so that the
    maths assertions in LuaTests are meaningful rather than self-fulfilling.
]]

--=========================================================
-- [1] SHARED HELPERS
--=========================================================

-- The engine replaces non-finite CFrame components with 0 rather than propagating NaN.
function NonFiniteToZero(Value)
    if Value ~= Value then
        return 0.0
    end
    if Value == math.huge or Value == -math.huge then
        return Value > 0.0 and 16384.0 or -16384.0
    end
    return Value
end

--=========================================================
-- [2] VECTOR3
--=========================================================

local Vector3Class = { __index = nil }

local function Vector3New(X, Y, Z)
    return setmetatable({ X = X or 0.0, Y = Y or 0.0, Z = Z or 0.0 }, Vector3Class)
end

local function Vector3Magnitude(Value)
    return math.sqrt(Value.X * Value.X + Value.Y * Value.Y + Value.Z * Value.Z)
end

Vector3Class.__add = function(A, B)
    return Vector3New(A.X + B.X, A.Y + B.Y, A.Z + B.Z)
end

Vector3Class.__sub = function(A, B)
    return Vector3New(A.X - B.X, A.Y - B.Y, A.Z - B.Z)
end

Vector3Class.__mul = function(A, B)
    if type(A) == "number" then
        return Vector3New(A * B.X, A * B.Y, A * B.Z)
    elseif type(B) == "number" then
        return Vector3New(A.X * B, A.Y * B, A.Z * B)
    end
    return Vector3New(A.X * B.X, A.Y * B.Y, A.Z * B.Z)
end

Vector3Class.__div = function(A, B)
    if type(B) == "number" then
        return Vector3New(A.X / B, A.Y / B, A.Z / B)
    end
    return Vector3New(A.X / B.X, A.Y / B.Y, A.Z / B.Z)
end

Vector3Class.__unm = function(A)
    return Vector3New(-A.X, -A.Y, -A.Z)
end

Vector3Class.__eq = function(A, B)
    return A.X == B.X and A.Y == B.Y and A.Z == B.Z
end

Vector3Class.__tostring = function(A)
    return string.format("%g, %g, %g", A.X, A.Y, A.Z)
end

function Vector3Class.Dot(Self, Other)
    return Self.X * Other.X + Self.Y * Other.Y + Self.Z * Other.Z
end

function Vector3Class.Cross(Self, Other)
    return Vector3New(
        Self.Y * Other.Z - Self.Z * Other.Y,
        Self.Z * Other.X - Self.X * Other.Z,
        Self.X * Other.Y - Self.Y * Other.X
    )
end

function Vector3Class.Lerp(Self, Goal, Alpha)
    return Vector3New(
        Self.X + (Goal.X - Self.X) * Alpha,
        Self.Y + (Goal.Y - Self.Y) * Alpha,
        Self.Z + (Goal.Z - Self.Z) * Alpha
    )
end

Vector3Class.__index = function(Self, Key)
    if Key == "Magnitude" then
        return Vector3Magnitude(Self)
    elseif Key == "Unit" then
        local Magnitude = Vector3Magnitude(Self)
        if Magnitude <= 0.0 then
            return Vector3New(0.0, 0.0, 0.0)
        end
        return Vector3New(Self.X / Magnitude, Self.Y / Magnitude, Self.Z / Magnitude)
    end
    return rawget(Vector3Class, Key)
end

local Vector3 = {
    new = Vector3New,
    zero = Vector3New(0.0, 0.0, 0.0),
    one = Vector3New(1.0, 1.0, 1.0),
    xAxis = Vector3New(1.0, 0.0, 0.0),
    yAxis = Vector3New(0.0, 1.0, 0.0),
    zAxis = Vector3New(0.0, 0.0, 1.0),
}

--=========================================================
-- [3] CFRAME
--=========================================================
-- Stored as a position plus a row-major 3x3 rotation matrix (M_row_column), matching the
-- 12-argument CFrame.new(R00, R01, R02, R10, R11, R12, R20, R21, R22) contract.

local CFrameClass = {}

local function CFrameFromMatrix(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
    return setmetatable({
        X = X, Y = Y, Z = Z,
        M00 = M00, M01 = M01, M02 = M02,
        M10 = M10, M11 = M11, M12 = M12,
        M20 = M20, M21 = M21, M22 = M22,
    }, CFrameClass)
end

local function CFrameMultiply(A, B)
    local M00 = A.M00 * B.M00 + A.M01 * B.M10 + A.M02 * B.M20
    local M01 = A.M00 * B.M01 + A.M01 * B.M11 + A.M02 * B.M21
    local M02 = A.M00 * B.M02 + A.M01 * B.M12 + A.M02 * B.M22
    local M10 = A.M10 * B.M00 + A.M11 * B.M10 + A.M12 * B.M20
    local M11 = A.M10 * B.M01 + A.M11 * B.M11 + A.M12 * B.M21
    local M12 = A.M10 * B.M02 + A.M11 * B.M12 + A.M12 * B.M22
    local M20 = A.M20 * B.M00 + A.M21 * B.M10 + A.M22 * B.M20
    local M21 = A.M20 * B.M01 + A.M21 * B.M11 + A.M22 * B.M21
    local M22 = A.M20 * B.M02 + A.M21 * B.M12 + A.M22 * B.M22

    local X = A.X + A.M00 * B.X + A.M01 * B.Y + A.M02 * B.Z
    local Y = A.Y + A.M10 * B.X + A.M11 * B.Y + A.M12 * B.Z
    local Z = A.Z + A.M20 * B.X + A.M21 * B.Y + A.M22 * B.Z

    return CFrameFromMatrix(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
end

CFrameClass.__mul = function(A, B)
    if getmetatable(B) == CFrameClass then
        return CFrameMultiply(A, B)
    end
    return Vector3New(
        A.M00 * B.X + A.M01 * B.Y + A.M02 * B.Z,
        A.M10 * B.X + A.M11 * B.Y + A.M12 * B.Z,
        A.M20 * B.X + A.M21 * B.Y + A.M22 * B.Z
    )
end

CFrameClass.__add = function(A, B)
    return CFrameFromMatrix(A.X + B.X, A.Y + B.Y, A.Z + B.Z, A.M00, A.M01, A.M02, A.M10, A.M11, A.M12, A.M20, A.M21, A.M22)
end

CFrameClass.__sub = function(A, B)
    return CFrameFromMatrix(A.X - B.X, A.Y - B.Y, A.Z - B.Z, A.M00, A.M01, A.M02, A.M10, A.M11, A.M12, A.M20, A.M21, A.M22)
end

CFrameClass.__eq = function(A, B)
    return A.X == B.X and A.Y == B.Y and A.Z == B.Z
        and A.M00 == B.M00 and A.M01 == B.M01 and A.M02 == B.M02
        and A.M10 == B.M10 and A.M11 == B.M11 and A.M12 == B.M12
        and A.M20 == B.M20 and A.M21 == B.M21 and A.M22 == B.M22
end

CFrameClass.__tostring = function(Self)
    return string.format("CFrame(%g, %g, %g)", Self.X, Self.Y, Self.Z)
end

function CFrameClass.Inverse(Self)
    local M00, M01, M02 = Self.M00, Self.M10, Self.M20
    local M10, M11, M12 = Self.M01, Self.M11, Self.M21
    local M20, M21, M22 = Self.M02, Self.M12, Self.M22
    local X = -(M00 * Self.X + M01 * Self.Y + M02 * Self.Z)
    local Y = -(M10 * Self.X + M11 * Self.Y + M12 * Self.Z)
    local Z = -(M20 * Self.X + M21 * Self.Y + M22 * Self.Z)
    return CFrameFromMatrix(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
end

function CFrameClass.Lerp(Self, Goal, Alpha)
    if Alpha == 0 then
        return Self
    elseif Alpha == 1 then
        return Goal
    end
    local X = Self.X + (Goal.X - Self.X) * Alpha
    local Y = Self.Y + (Goal.Y - Self.Y) * Alpha
    local Z = Self.Z + (Goal.Z - Self.Z) * Alpha
    local M00 = Self.M00 + (Goal.M00 - Self.M00) * Alpha
    local M01 = Self.M01 + (Goal.M01 - Self.M01) * Alpha
    local M02 = Self.M02 + (Goal.M02 - Self.M02) * Alpha
    local M10 = Self.M10 + (Goal.M10 - Self.M10) * Alpha
    local M11 = Self.M11 + (Goal.M11 - Self.M11) * Alpha
    local M12 = Self.M12 + (Goal.M12 - Self.M12) * Alpha
    local M20 = Self.M20 + (Goal.M20 - Self.M20) * Alpha
    local M21 = Self.M21 + (Goal.M21 - Self.M21) * Alpha
    local M22 = Self.M22 + (Goal.M22 - Self.M22) * Alpha
    return CFrameFromMatrix(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
end

function CFrameClass.VectorToWorldSpace(Self, Vector)
    return Vector3New(
        Self.M00 * Vector.X + Self.M01 * Vector.Y + Self.M02 * Vector.Z,
        Self.M10 * Vector.X + Self.M11 * Vector.Y + Self.M12 * Vector.Z,
        Self.M20 * Vector.X + Self.M21 * Vector.Y + Self.M22 * Vector.Z
    )
end

function CFrameClass.VectorToObjectSpace(Self, Vector)
    return Vector3New(
        Self.M00 * Vector.X + Self.M10 * Vector.Y + Self.M20 * Vector.Z,
        Self.M01 * Vector.X + Self.M11 * Vector.Y + Self.M21 * Vector.Z,
        Self.M02 * Vector.X + Self.M12 * Vector.Y + Self.M22 * Vector.Z
    )
end

function CFrameClass.PointToWorldSpace(Self, Vector)
    return Vector3New(
        Self.X + Self.M00 * Vector.X + Self.M01 * Vector.Y + Self.M02 * Vector.Z,
        Self.Y + Self.M10 * Vector.X + Self.M11 * Vector.Y + Self.M12 * Vector.Z,
        Self.Z + Self.M20 * Vector.X + Self.M21 * Vector.Y + Self.M22 * Vector.Z
    )
end

function CFrameClass.PointToObjectSpace(Self, Vector)
    local OffsetX = Vector.X - Self.X
    local OffsetY = Vector.Y - Self.Y
    local OffsetZ = Vector.Z - Self.Z
    return Vector3New(
        Self.M00 * OffsetX + Self.M10 * OffsetY + Self.M20 * OffsetZ,
        Self.M01 * OffsetX + Self.M11 * OffsetY + Self.M21 * OffsetZ,
        Self.M02 * OffsetX + Self.M12 * OffsetY + Self.M22 * OffsetZ
    )
end

-- Roblox documents ToEulerAnglesXYZ as the inverse of CFrame.fromEulerAnglesXYZ, where
-- R00 = cos(Y)cos(Z), R10 = cos(X)sin(Z) + sin(X)sin(Y)cos(Z), R20 = -sin(Y).
function CFrameClass.ToEulerAnglesXYZ(Self)
    local Y1 = NonFiniteToZero(-Self.M20)
    Y1 = math.clamp(Y1, -1.0, 1.0)
    local Y0 = math.sqrt(math.max(0.0, 1.0 - Y1 * Y1))
    local X0, X1
    if Y0 > 1e-6 then
        X0 = Self.M00 / Y0
        X1 = Self.M10 / Y0
    else
        X0 = 1.0
        X1 = 0.0
    end
    return math.atan2(X1, X0), math.asin(Y1), math.atan2(Self.M21, Self.M22)
end

function CFrameClass.ToEulerAnglesYXZ(Self)
    local X1 = NonFiniteToZero(-Self.M21)
    X1 = math.clamp(X1, -1.0, 1.0)
    local X0 = math.sqrt(math.max(0.0, 1.0 - X1 * X1))
    local Y0, Y1
    if X0 > 1e-6 then
        Y0 = Self.M22 / X0
        Y1 = Self.M20 / X0
    else
        Y0 = 1.0
        Y1 = 0.0
    end
    return math.atan2(X1, X0), math.atan2(Y1, Y0), math.atan2(Self.M01, Self.M11)
end

function CFrameClass.ToOrientation(Self)
    return CFrameFromMatrix(0.0, 0.0, 0.0, Self.M00, Self.M01, Self.M02, Self.M10, Self.M11, Self.M12, Self.M20, Self.M21, Self.M22)
end

function CFrameClass.ToWorldSpace(Self, Target)
    return CFrameMultiply(Self, Target)
end

function CFrameClass.ToObjectSpace(Self, Target)
    return CFrameMultiply(CFrameClass.Inverse(Self), Target)
end

CFrameClass.__index = function(Self, Key)
    if Key == "Position" or Key == "p" then
        return Vector3New(Self.X, Self.Y, Self.Z)
    elseif Key == "XVector" or Key == "RightVector" then
        return Vector3New(Self.M00, Self.M10, Self.M20)
    elseif Key == "YVector" or Key == "UpVector" then
        return Vector3New(Self.M01, Self.M11, Self.M21)
    elseif Key == "ZVector" then
        return Vector3New(Self.M02, Self.M12, Self.M22)
    elseif Key == "LookVector" then
        return Vector3New(-Self.M02, -Self.M12, -Self.M22)
    end
    return rawget(CFrameClass, Key)
end

local function CFrameFromEulerXYZ(AngleX, AngleY, AngleZ)
    local CX, SX = math.cos(AngleX), math.sin(AngleX)
    local CY, SY = math.cos(AngleY), math.sin(AngleY)
    local CZ, SZ = math.cos(AngleZ), math.sin(AngleZ)
    return CFrameFromMatrix(
        0.0, 0.0, 0.0,
        CY * CZ, -CY * SZ, SY,
        CX * SZ + SX * SY * CZ, CX * CZ - SX * SY * SZ, -SX * CY,
        SX * SZ - CX * SY * CZ, SX * CZ + CX * SY * SZ, CX * CY
    )
end

local function CFrameFromEulerYXZ(AngleY, AngleX, AngleZ)
    local CX, SX = math.cos(AngleX), math.sin(AngleX)
    local CY, SY = math.cos(AngleY), math.sin(AngleY)
    local CZ, SZ = math.cos(AngleZ), math.sin(AngleZ)
    return CFrameFromMatrix(
        0.0, 0.0, 0.0,
        CZ * CY, -SZ * CY, SY,
        CZ * SY * SX + SZ * CX, -SZ * SY * SX + CZ * CX, -CY * SX,
        -CZ * SY * CX + SZ * SX, SZ * SY * CX + CZ * SX, CY * CX
    )
end

local function CFrameFromAxisAngle(Axis, Angle)
    local Unit = Axis.Unit
    local C, S = math.cos(Angle), math.sin(Angle)
    local T = 1.0 - C
    local X, Y, Z = Unit.X, Unit.Y, Unit.Z
    return CFrameFromMatrix(
        0.0, 0.0, 0.0,
        T * X * X + C, T * X * Y - S * Z, T * X * Z + S * Y,
        T * X * Y + S * Z, T * Y * Y + C, T * Y * Z - S * X,
        T * X * Z - S * Y, T * Y * Z + S * X, T * Z * Z + C
    )
end

local CFrame = {
    identity = CFrameFromMatrix(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0),
    fromMatrix = function(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
        return CFrameFromMatrix(X, Y, Z, M00, M01, M02, M10, M11, M12, M20, M21, M22)
    end,
    fromEulerAnglesXYZ = CFrameFromEulerXYZ,
    Angles = CFrameFromEulerXYZ,
    fromEulerAnglesYXZ = CFrameFromEulerYXZ,
    fromAxisAngle = CFrameFromAxisAngle,
    lookAt = function(From, To, Up)
        local Look = (To - From).Unit
        local Right = Look:Cross(Up or Vector3New(0.0, 1.0, 0.0)).Unit
        local CorrectedUp = Right:Cross(Look).Unit
        return CFrameFromMatrix(
            From.X, From.Y, From.Z,
            Right.X, CorrectedUp.X, -Look.X,
            Right.Y, CorrectedUp.Y, -Look.Y,
            Right.Z, CorrectedUp.Z, -Look.Z
        )
    end,
}

function CFrame.new(...)
    local Count = select("#", ...)
    if Count == 12 then
        local A = { ... }
        return CFrameFromMatrix(
            A[1], A[2], A[3],
            A[4], A[5], A[6],
            A[7], A[8], A[9],
            A[10], A[11], A[12]
        )
    elseif Count == 7 then
        local A = { ... }
        local QX, QY, QZ, QW = A[4], A[5], A[6], A[7]
        local XX, YY, ZZ = QX * QX, QY * QY, QZ * QZ
        local XY, XZ, YZ = QX * QY, QX * QZ, QY * QZ
        local WX, WY, WZ = QW * QX, QW * QY, QW * QZ
        return CFrameFromMatrix(
            A[1], A[2], A[3],
            1.0 - 2.0 * (YY + ZZ), 2.0 * (XY - WZ), 2.0 * (XZ + WY),
            2.0 * (XY + WZ), 1.0 - 2.0 * (XX + ZZ), 2.0 * (YZ - WX),
            2.0 * (XZ - WY), 2.0 * (YZ + WX), 1.0 - 2.0 * (XX + YY)
        )
    end
    local A = { ... }
    return CFrameFromMatrix(A[1] or 0.0, A[2] or 0.0, A[3] or 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
end

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

function InstanceClass.new(ClassName, Name)
    return setmetatable({
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

return {
    Vector3 = Vector3,
    Vector3Class = Vector3Class,
    CFrame = CFrame,
    CFrameClass = CFrameClass,
    Instance = Instance,
    InstanceClass = InstanceClass,
    SignalClass = SignalClass,
    Enum = Enum,
}
