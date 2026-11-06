-- ProceduralAnimation/Shared/AnimationMathCore

return function(MathLib, Private)
--=========================================================
-- [1] CONSTANTS
--=========================================================

local Pi = math.pi
local TwoPi = Pi * 2.0
local Sqrt = math.sqrt
local Sin = math.sin
local Cos = math.cos
local Abs = math.abs
local Exp = math.exp
local Acos = math.acos
local Pow = math.pow
local Clamp = math.clamp
local Floor = math.floor
local Vector3New = Vector3.new
local CFrameNew = CFrame.new

MathLib.Pi = Pi
MathLib.TwoPi = TwoPi

local EasingFunctions = {}
local EasingCount = 0
local BezierCurves = Private.BezierCurves

local function RegisterEasing(Function)
    EasingCount += 1
    EasingFunctions[EasingCount] = Function
end

--=========================================================
-- [2] EASING (built-in Enum.EasingStyle equivalents, reimplemented)
--=========================================================

RegisterEasing(function(Alpha)
    return Alpha
end)

-- Sine
RegisterEasing(function(Alpha)
    return 1.0 - Cos(Alpha * Pi * 0.5)
end)
RegisterEasing(function(Alpha)
    return Sin(Alpha * Pi * 0.5)
end)
RegisterEasing(function(Alpha)
    return -(Cos(Pi * Alpha) - 1.0) * 0.5
end)

-- Back
local BackConstant = 1.70158
local BackConstantInOut = BackConstant * 1.525

RegisterEasing(function(Alpha)
    return Alpha * Alpha * ((BackConstant + 1.0) * Alpha - BackConstant)
end)
RegisterEasing(function(Alpha)
    local Shifted = Alpha - 1.0
    return Shifted * Shifted * ((BackConstant + 1.0) * Shifted + BackConstant) + 1.0
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        local Doubled = Alpha * 2.0
        return 0.5 * (Doubled * Doubled * ((BackConstantInOut + 1.0) * Doubled - BackConstantInOut))
    end
    local Doubled = Alpha * 2.0 - 2.0
    return 0.5 * (Doubled * Doubled * ((BackConstantInOut + 1.0) * Doubled + BackConstantInOut) + 2.0)
end)

-- Quad
RegisterEasing(function(Alpha)
    return Alpha * Alpha
end)
RegisterEasing(function(Alpha)
    return 1.0 - (1.0 - Alpha) * (1.0 - Alpha)
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return 2.0 * Alpha * Alpha
    end
    local Shifted = 1.0 - Alpha
    return 1.0 - 2.0 * Shifted * Shifted
end)

-- Quart
RegisterEasing(function(Alpha)
    return Alpha * Alpha * Alpha * Alpha
end)
RegisterEasing(function(Alpha)
    local Shifted = 1.0 - Alpha
    return 1.0 - Shifted * Shifted * Shifted * Shifted
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return 8.0 * Alpha * Alpha * Alpha * Alpha
    end
    local Shifted = 1.0 - Alpha
    return 1.0 - 8.0 * Shifted * Shifted * Shifted * Shifted
end)

-- Quint
RegisterEasing(function(Alpha)
    return Alpha * Alpha * Alpha * Alpha * Alpha
end)
RegisterEasing(function(Alpha)
    local Shifted = 1.0 - Alpha
    return 1.0 - Shifted * Shifted * Shifted * Shifted * Shifted
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return 16.0 * Alpha * Alpha * Alpha * Alpha * Alpha
    end
    local Shifted = 1.0 - Alpha
    return 1.0 - 16.0 * Shifted * Shifted * Shifted * Shifted * Shifted
end)

-- Bounce
local function BounceOut(Alpha)
    local A = Alpha
    if A < 1.0 / 2.75 then
        return 7.5625 * A * A
    elseif A < 2.0 / 2.75 then
        A = A - 1.5 / 2.75
        return 7.5625 * A * A + 0.75
    elseif A < 2.5 / 2.75 then
        A = A - 2.25 / 2.75
        return 7.5625 * A * A + 0.9375
    end
    A = A - 2.625 / 2.75
    return 7.5625 * A * A + 0.984375
end

RegisterEasing(function(Alpha)
    return 1.0 - BounceOut(1.0 - Alpha)
end)
RegisterEasing(BounceOut)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return (1.0 - BounceOut(1.0 - Alpha * 2.0)) * 0.5
    end
    return BounceOut(Alpha * 2.0 - 1.0) * 0.5 + 0.5
end)

-- Elastic
RegisterEasing(function(Alpha)
    if Alpha == 0.0 then
        return 0.0
    elseif Alpha == 1.0 then
        return 1.0
    end
    return -Pow(2.0, 10.0 * Alpha - 10.0) * Sin((Alpha * 10.0 - 10.75) * TwoPi / 3.0)
end)
RegisterEasing(function(Alpha)
    if Alpha == 0.0 then
        return 0.0
    elseif Alpha == 1.0 then
        return 1.0
    end
    return Pow(2.0, -10.0 * Alpha) * Sin((Alpha * 10.0 - 0.75) * TwoPi / 3.0) + 1.0
end)
RegisterEasing(function(Alpha)
    if Alpha == 0.0 then
        return 0.0
    elseif Alpha == 1.0 then
        return 1.0
    end
    if Alpha < 0.5 then
        return -(Pow(2.0, 20.0 * Alpha - 10.0) * Sin((20.0 * Alpha - 11.125) * TwoPi / 4.5)) * 0.5
    end
    return Pow(2.0, -20.0 * Alpha + 10.0) * Sin((20.0 * Alpha - 11.125) * TwoPi / 4.5) * 0.5 + 1.0
end)

-- Exponential
RegisterEasing(function(Alpha)
    if Alpha == 0.0 then
        return 0.0
    end
    return Pow(2.0, 10.0 * Alpha - 10.0)
end)
RegisterEasing(function(Alpha)
    if Alpha == 1.0 then
        return 1.0
    end
    return 1.0 - Pow(2.0, -10.0 * Alpha)
end)
RegisterEasing(function(Alpha)
    if Alpha == 0.0 then
        return 0.0
    elseif Alpha == 1.0 then
        return 1.0
    end
    if Alpha < 0.5 then
        return Pow(2.0, 20.0 * Alpha - 10.0) * 0.5
    end
    return (2.0 - Pow(2.0, -20.0 * Alpha + 10.0)) * 0.5
end)

-- Circular
RegisterEasing(function(Alpha)
    return 1.0 - Sqrt(1.0 - Alpha * Alpha)
end)
RegisterEasing(function(Alpha)
    local Shifted = Alpha - 1.0
    return Sqrt(1.0 - Shifted * Shifted)
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return (1.0 - Sqrt(1.0 - 4.0 * Alpha * Alpha)) * 0.5
    end
    local Shifted = 2.0 * Alpha - 2.0
    return (Sqrt(1.0 - Shifted * Shifted) + 1.0) * 0.5
end)

-- Cubic
RegisterEasing(function(Alpha)
    return Alpha * Alpha * Alpha
end)
RegisterEasing(function(Alpha)
    local Shifted = 1.0 - Alpha
    return 1.0 - Shifted * Shifted * Shifted
end)
RegisterEasing(function(Alpha)
    if Alpha < 0.5 then
        return 4.0 * Alpha * Alpha * Alpha
    end
    local Shifted = 1.0 - Alpha
    return 1.0 - 4.0 * Shifted * Shifted * Shifted
end)

-- Custom Spring: damped harmonic, lands exactly on 1.
RegisterEasing(function(Alpha)
    if Alpha <= 0.0 then
        return 0.0
    elseif Alpha >= 1.0 then
        return 1.0
    end
    return 1.0 - Exp(-6.0 * Alpha) * Cos(8.0 * Alpha) * (1.0 - Alpha)
end)

-- Custom Elastic: heavier overshoot than the enum version.
RegisterEasing(function(Alpha)
    if Alpha <= 0.0 then
        return 0.0
    elseif Alpha >= 1.0 then
        return 1.0
    end
    return Pow(2.0, -12.0 * Alpha) * Sin((Alpha * 12.0 - 0.5) * TwoPi / 2.5) + 1.0
end)

-- Custom Bounce: six decaying hops.
RegisterEasing(function(Alpha)
    if Alpha <= 0.0 then
        return 0.0
    elseif Alpha >= 1.0 then
        return 1.0
    end
    local Hops = 6.0
    local Local = Alpha * Hops
    local HopIndex = Floor(Local)
    local HopAlpha = Local - HopIndex
    local Amplitude = 1.0 - HopIndex / Hops
    local Height = Abs(Sin(HopAlpha * Pi))
    return 1.0 - Height * Amplitude * 0.6 - (1.0 - Alpha) * 0.4
end)

-- Custom Anticipate-Overshoot: pulls back before travelling, overshoots on arrival.
RegisterEasing(function(Alpha)
    local Tension = 2.5
    if Alpha < 0.5 then
        local Doubled = Alpha * 2.0
        return 0.5 * (Doubled * Doubled * ((Tension + 1.0) * Doubled - Tension))
    end
    local Doubled = Alpha * 2.0 - 2.0
    return 0.5 * (Doubled * Doubled * ((Tension + 1.0) * Doubled + Tension) + 2.0)
end)

MathLib.EasingFunctions = EasingFunctions
MathLib.EasingCount = EasingCount

--=========================================================
-- [3] MATH
--=========================================================

function MathLib.Ease(EasingId, Alpha)
    local Function = EasingFunctions[EasingId]
    if Function then
        return Function(Alpha)
    end
    local Curve = BezierCurves[EasingId]
    if Curve then
        if Curve.Kind == 1 then

return MathLib.BezierQuadratic(Curve.P0, Curve.P1, Curve.P2, Alpha)
        end
        return MathLib.BezierCubic(Curve.P0, Curve.P1, Curve.P2, Curve.P3, Alpha)
    end
    return Alpha
end

function MathLib.Clamp01(Value)
    if Value < 0.0 then
        return 0.0
    elseif Value > 1.0 then
        return 1.0
    end
    return Value
end

function MathLib.SmoothFactor(Rate, DeltaTime)
    -- Frame-rate independent exponential smoothing.
    return 1.0 - Exp(-Rate * DeltaTime)
end

function MathLib.ShortestAngle(From, To)
    local Difference = To - From
    while Difference > Pi do
        Difference -= TwoPi
    end
    while Difference < -Pi do
        Difference += TwoPi
    end
    return Difference
end

--=========================================================
-- [4] LERPING
--=========================================================

function MathLib.LerpNumber(From, To, Alpha)
    return From + (To - From) * Alpha
end

function MathLib.LerpVector3(From, To, Alpha)
    local FromX, FromY, FromZ = From.X, From.Y, From.Z
    local ToX, ToY, ToZ = To.X, To.Y, To.Z
    return Vector3New(
        FromX + (ToX - FromX) * Alpha,
        FromY + (ToY - FromY) * Alpha,
        FromZ + (ToZ - FromZ) * Alpha
    )
end

local function QuaternionFromCFrame(CFrame)
    local Right = CFrame.XVector
    local Up = CFrame.YVector
    local Back = CFrame.ZVector
    local M00, M01, M02 = Right.X, Up.X, Back.X
    local M10, M11, M12 = Right.Y, Up.Y, Back.Y
    local M20, M21, M22 = Right.Z, Up.Z, Back.Z
    local Trace = M00 + M11 + M22
    if Trace > 0.0 then
        local Scale = Sqrt(Trace + 1.0) * 2.0
        return 0.25 * Scale, (M21 - M12) / Scale, (M02 - M20) / Scale, (M10 - M01) / Scale
    elseif M00 > M11 and M00 > M22 then
        local Scale = Sqrt(1.0 + M00 - M11 - M22) * 2.0
        return (M21 - M12) / Scale, 0.25 * Scale, (M01 + M10) / Scale, (M02 + M20) / Scale
    elseif M11 > M22 then
        local Scale = Sqrt(1.0 + M11 - M00 - M22) * 2.0
        return (M02 - M20) / Scale, (M01 + M10) / Scale, 0.25 * Scale, (M12 + M21) / Scale
    end
    local Scale = Sqrt(1.0 + M22 - M00 - M11) * 2.0
    return (M10 - M01) / Scale, (M02 + M20) / Scale, (M12 + M21) / Scale, 0.25 * Scale
end

local function CFrameFromQuaternion(PositionX, PositionY, PositionZ, QW, QX, QY, QZ)
    local XX, YY, ZZ = QX * QX, QY * QY, QZ * QZ
    local XY, XZ, YZ = QX * QY, QX * QZ, QY * QZ
    local WX, WY, WZ = QW * QX, QW * QY, QW * QZ
    local M00 = 1.0 - 2.0 * (YY + ZZ)
    local M01 = 2.0 * (XY - WZ)
    local M02 = 2.0 * (XZ + WY)
    local M10 = 2.0 * (XY + WZ)
    local M11 = 1.0 - 2.0 * (XX + ZZ)
    local M12 = 2.0 * (YZ - WX)
    local M20 = 2.0 * (XZ - WY)
    local M21 = 2.0 * (YZ + WX)
    local M22 = 1.0 - 2.0 * (XX + YY)
    return CFrameNew(
        PositionX, PositionY, PositionZ,
        M00, M01, M02,
        M10, M11, M12,
        M20, M21, M22
    )
end

function MathLib.SlerpCFrame(From, To, Alpha)
    if Alpha <= 0.0 then
        return From
    elseif Alpha >= 1.0 then
        return To
    end

    local FromW, FromX, FromY, FromZ = QuaternionFromCFrame(From)
    local ToW, ToX, ToY, ToZ = QuaternionFromCFrame(To)

    local Dot = FromW * ToW + FromX * ToX + FromY * ToY + FromZ * ToZ
    -- Dot-product sign correction: flip the target into the same hemisphere so the
    -- interpolation always takes the short arc.
    if Dot < 0.0 then
        ToW, ToX, ToY, ToZ = -ToW, -ToX, -ToY, -ToZ
        Dot = -Dot
    end

    local ResultW, ResultX, ResultY, ResultZ

    if Dot > 0.9995 then
        -- Small-angle linear fallback: slerp degenerates numerically here, and a normalised
        -- lerp is both cheaper and stable.
        ResultW = FromW + (ToW - FromW) * Alpha
        ResultX = FromX + (ToX - FromX) * Alpha
        ResultY = FromY + (ToY - FromY) * Alpha
        ResultZ = FromZ + (ToZ - FromZ) * Alpha
        local Length = Sqrt(ResultW * ResultW + ResultX * ResultX + ResultY * ResultY + ResultZ * ResultZ)
        if Length > 0.0 then
            local Inverse = 1.0 / Length
            ResultW *= Inverse
            ResultX *= Inverse
            ResultY *= Inverse
            ResultZ *= Inverse
        end
    else
        local Theta = Acos(Clamp(Dot, -1.0, 1.0))
        local SinTheta = Sin(Theta)
        local FromScale = Sin((1.0 - Alpha) * Theta) / SinTheta
        local ToScale = Sin(Alpha * Theta) / SinTheta
        ResultW = FromW * FromScale + ToW * ToScale
        ResultX = FromX * FromScale + ToX * ToScale
        ResultY = FromY * FromScale + ToY * ToScale
        ResultZ = FromZ * FromScale + ToZ * ToScale
    end

    return CFrameFromQuaternion(From.X, From.Y, From.Z, ResultW, ResultX, ResultY, ResultZ)
end

function MathLib.LerpCFrame(From, To, Alpha)
    if Alpha <= 0.0 then
        return From
    elseif Alpha >= 1.0 then
        return To
    end

    -- CFrame:Lerp is a C++ shortest-path quaternion slerp, so it is the fastest correct option
    -- for arbitrary rotations. Only when the two rotations are nearly identical do we use the
    -- manual normalised-lerp fallback, which skips the acos/sin setup entirely.
    local Dot = From.XVector:Dot(To.XVector)
        + From.YVector:Dot(To.YVector)
        + From.ZVector:Dot(To.ZVector)

    if Dot > 0.99999 then
        return MathLib.SlerpCFrame(From, To, Alpha)
    end

    return From:Lerp(To, Alpha)
end
end
